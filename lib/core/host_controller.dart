import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/background_service.dart';
import '../services/device_service.dart';
import '../services/file_service.dart';
import '../services/minecraft_server.dart';
import '../services/mod_service.dart';
import '../services/local_environment.dart';
import '../services/server_catalog.dart';
import '../services/tunnel_service.dart';
import '../services/world_service.dart';
import '../services/download_service.dart';
import '../services/runtime_service.dart';
import 'models.dart';
import 'progress.dart';
import 'world_config.dart';

final hostProvider = ChangeNotifierProvider<HostController>(
  (ref) => HostController()..initialize(),
);

class HostController extends ChangeNotifier {
  ServerProfile profile = const ServerProfile();
  WorldConfig world = WorldConfig();
  ServerPhase phase = ServerPhase.idle;
  final logs = <LogLine>[];
  Directory? root;
  MinecraftGameServer? server;
  TunnelService? tunnel;
  StreamSubscription<String>? _logs;
  Timer? _notifyTimer;
  bool loaded = false;
  bool working = false;
  bool disposed = false;
  String? error;
  String progressLabel = '';
  double? progress;

  /// Byte-level download progress for the console. A separate notifier so a
  /// download updating four times a second repaints only the progress strip,
  /// not the whole app.
  final download = ValueNotifier<DownloadProgress?>(null);
  double? rssMb;
  double? cpu;
  DateTime? startedAt;
  List<String> lanAddresses = [];
  int serverPort = 25565;
  int deviceRamMb = DeviceService.fallbackRamMb;
  bool ramDetected = false;
  bool? batteryUnrestricted;
  ThemeMode themeMode = ThemeMode.system;

  /// The user's own CurseForge API key. Saved on this device only; HostCraft
  /// never ships one.
  String curseForgeKey = '';
  String _environmentCurseForgeKey = '';
  bool curseForgeKeyFromEnvironment = false;
  int get maxMemoryMb => DeviceService.maxHeapMb(deviceRamMb);
  int get recommendedMemoryMb => DeviceService.recommendedHeapMb(deviceRamMb);
  bool get active => [
    ServerPhase.starting,
    ServerPhase.running,
    ServerPhase.stopping,
  ].contains(phase);
  bool get locked => working || active || phase == ServerPhase.preparing;
  void changed() {
    if (!disposed) notifyListeners();
  }

  void log(String text, {String source = 'host'}) {
    if (disposed) return;
    for (final line in const LineSplitter().convert(text)) {
      logs.add(
        LogLine(
          line.length > 8000 ? line.substring(0, 8000) : line,
          source: source,
        ),
      );
    }
    if (logs.length > 2000) logs.removeRange(0, logs.length - 2000);
    _notifyTimer ??= Timer(const Duration(milliseconds: 80), () {
      _notifyTimer = null;
      changed();
    });
  }

  Future<void> initialize() async {
    try {
      root = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'HostCraft'),
      );
      await root!.create(recursive: true);
      final detected = await DeviceService.totalRamMb();
      if (detected != null) {
        deviceRamMb = detected;
        ramDetected = true;
      }
      final file = File(p.join(root!.path, 'profile.json'));
      if (await file.exists()) {
        profile = ServerProfile.fromJson(jsonDecode(await file.readAsString()));
      } else {
        profile = profile.copyWith(
          memoryMb: DeviceService.defaultHeapMb(deviceRamMb),
        );
      }
      final limited = DeviceService.clampHeapMb(profile.memoryMb, deviceRamMb);
      if (ramDetected && limited != profile.memoryMb) {
        log(
          'Memory allocation lowered from ${profile.memoryMb} MB to $limited MB to fit this device.',
        );
        profile = profile.copyWith(memoryMb: limited);
      }
      world = await WorldConfig.load(root!);
      await _loadAppearance();
      await _loadAddonSettings();
      if (Platform.isAndroid) {
        batteryUnrestricted = await BackgroundService.isUnrestricted();
      }
      await _attach();
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      lanAddresses = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .toList();
      if (Platform.isAndroid) {
        FlutterForegroundTask.addTaskDataCallback(_backgroundMessage);
      }
      log('Welcome to HostCraft. Your world, your hardware.');
    } catch (e) {
      error = 'Could not load HostCraft: $e';
      log(error!);
    } finally {
      loaded = true;
      changed();
    }
  }

  void _clearDownload() {
    if (!disposed) download.value = null;
  }

  void _onDownload(DownloadProgress p) {
    if (disposed) return;
    if (!p.done) {
      download.value = p;
      return;
    }
    _clearDownload();
    if (!p.failed && !p.isStep && p.received >= 256 * 1024) {
      log(
        '${p.label}: ${formatBytes(p.received)} in ${formatDuration(p.elapsed)} (average ${formatSpeed(p.bytesPerSecond)}).',
      );
    }
  }

  void _backgroundMessage(Object data) {
    if (data == 'stop' && active && phase != ServerPhase.stopping) {
      unawaited(stop());
    }
  }

  Future<void> _attach() async {
    await _logs?.cancel();
    await server?.dispose();
    server = MinecraftGameServer(
      profile: profile,
      root: root!,
      onPhase: (value) {
        phase = value;
        if (value == ServerPhase.starting) startedAt = DateTime.now();
        if (value == ServerPhase.ready ||
            value == ServerPhase.failed ||
            value == ServerPhase.idle) {
          _clearDownload();
        }
        if (value == ServerPhase.ready || value == ServerPhase.failed) {
          startedAt = null;
          unawaited(tunnel?.stop() ?? Future.value());
        }
        changed();
      },
      onProgress: (label, value) {
        final unchanged =
            label == progressLabel &&
            (value == progress ||
                (value != null &&
                    progress != null &&
                    value < 1 &&
                    (value - progress!).abs() < .01));
        progressLabel = label;
        progress = value;
        // Repaint the app only when the label or the bar visibly moves.
        if (!unchanged) changed();
      },
      onDownload: _onDownload,
      onMetrics: (memory, usage) {
        rssMb = memory;
        cpu = usage;
        changed();
      },
    );
    _logs = server!.consoleOutput.listen(
      (value) => log(value, source: 'server'),
    );
    tunnel ??= TunnelService(
      root!,
      (line) => log(line, source: 'playit'),
      changed,
      localPort: () => serverPort,
      bedrockPort: () => profile.crossplay && profile.engine.crossplayCapable
          ? profile.bedrockPort
          : null,
    );
    phase = await server!.isPrepared() ? ServerPhase.ready : ServerPhase.idle;
    final settings = await readSettings();
    serverPort = int.tryParse(settings['server-port'] ?? '') ?? 25565;
    if (await server!.properties.exists()) {
      world = WorldConfig.fromProperties(settings);
    }
    await world.save(root!);
  }

  Future<void> configure(ServerProfile next) async {
    if (active || phase == ServerPhase.preparing) {
      throw StateError('Stop the server before changing its setup');
    }
    profile = next.copyWith(
      memoryMb: DeviceService.clampHeapMb(next.memoryMb, deviceRamMb),
    );
    await File(p.join(root!.path, 'profile.json'))
        .writeAsString(jsonEncode(profile.toJson()), flush: true);
    await _attach();
    error = null;
    changed();
  }

  Future<void> action(Future<void> Function() fn) async {
    if (working) return;
    working = true;
    error = null;
    changed();
    try {
      await fn();
    } catch (e) {
      error = e.toString().replaceFirst('Bad state: ', '');
      log(error!, source: 'error');
    } finally {
      working = false;
      changed();
    }
  }

  Future<void> prepare() => action(() => server!.prepare());
  Future<void> start() => action(() => server!.start());
  Future<void> stop() => action(() async {
    await tunnel?.stop();
    await server?.stop();
  });

  /// Stops everything HostCraft started (Playit agent, then Java) and waits
  /// until the processes are gone. Used when the app is being closed, so it
  /// does not depend on [working] and uses a shorter graceful-stop window.
  Future<void> shutdown() async {
    try {
      await tunnel?.stop();
    } catch (_) {}
    try {
      await server?.stop(grace: const Duration(seconds: 25));
    } catch (_) {}
  }

  Future<void> command(String text) => action(() => server!.sendCommand(text));

  /// Re-downloads the server jar (and Geyser/Floodgate) to pick up the newest
  /// build of the selected version.
  Future<void> updateServerFiles() =>
      action(() => server!.prepare(force: true));

  /// Version lists and download lookups for the selected software.
  ServerCatalog catalog() => catalogFor(profile.contact);

  ServerCatalog catalogFor(String contact) =>
      ServerCatalog(DownloadService(contact: contact));

  // ---- world ----------------------------------------------------------------

  void _requireStopped() {
    if (active || phase == ServerPhase.preparing) {
      throw StateError('Stop the server first');
    }
  }

  /// Saves the world settings to HostCraft's `world.json` and into this
  /// server's `server.properties`. They apply on the next start.
  Future<void> saveWorld(WorldConfig next) async {
    if (locked) throw StateError('Stop the server before changing the world');
    next.levelName = WorldConfig.sanitizeName(next.levelName);
    await next.save(root!);
    final file = server!.properties;
    // Before the first prepare the file does not exist yet; prepare applies
    // the saved world settings when it creates it.
    if (await file.exists()) {
      await file.writeAsString(
        ServerProperties(await file.readAsString()).update(next.toProperties()),
        flush: true,
      );
    }
    world = next;
    log('World settings saved. They apply on the next start.');
    changed();
  }

  Future<List<WorldInfo>> listWorlds() =>
      WorldService(root!).list(server!.directory);

  Future<List<File>> listBackups() => WorldService(root!).backups();

  Future<void> backupWorld() => action(() async {
    _requireStopped();
    final file = await WorldService(root!)
        .backup(server!.directory, world.levelName);
    log('World backed up to ${file.path}');
  });

  /// Imports a zipped world as the current world name. The previous world with
  /// that name is kept next to it as `<name>.old-<time>`.
  Future<void> importWorld(File zip) => action(() async {
    _requireStopped();
    await WorldService(root!)
        .importZip(zip, server!.directory, world.levelName);
    log(
      'Imported ${p.basename(zip.path)} as "${world.levelName}". Start the server to play it.',
    );
  });

  /// Deletes the current world so a fresh one is generated. A backup is made
  /// first.
  Future<void> resetWorld() => action(() async {
    _requireStopped();
    final service = WorldService(root!);
    final dir = server!.directory;
    if (!await service.exists(dir, world.levelName)) {
      log('There is no world called "${world.levelName}" yet.');
      return;
    }
    final backup = await service.backup(dir, world.levelName);
    log('Backed up the old world to ${backup.path}');
    await service.delete(dir, world.levelName);
    log(
      'World "${world.levelName}" deleted. A new one is generated on the next start.',
    );
  });
  Future<Map<String, String>> readSettings() async {
    final file = server!.properties;
    return ServerProperties(
      await file.exists() ? await file.readAsString() : '',
    ).values;
  }

  Future<void> saveSettings(Map<String, String> values) async {
    if (active || phase == ServerPhase.preparing) {
      throw StateError('Stop the server before saving settings');
    }
    final file = server!.properties;
    await file.parent.create(recursive: true);
    final original = await file.exists() ? await file.readAsString() : '';
    await file.writeAsString(
      ServerProperties(original).update(values),
      flush: true,
    );
    serverPort = int.tryParse(values['server-port'] ?? '') ?? 25565;
    log('Server settings saved. They apply on the next start.');
  }

  Future<void> _loadAppearance() async {
    try {
      final file = File(p.join(root!.path, 'ui.json'));
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      final name = data is Map ? data['themeMode'] : null;
      for (final mode in ThemeMode.values) {
        if (mode.name == name) themeMode = mode;
      }
    } catch (_) {
      themeMode = ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    changed();
    final folder = root;
    if (folder == null) return;
    try {
      await File(p.join(folder.path, 'ui.json'))
          .writeAsString(jsonEncode({'themeMode': mode.name}), flush: true);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  // ---- mods, plugins and files ---------------------------------------------

  Future<void> _loadAddonSettings() async {
    _environmentCurseForgeKey = await LocalEnvironment.curseForgeKey(
      supportDirectory: root!,
    );
    curseForgeKey = _environmentCurseForgeKey;
    curseForgeKeyFromEnvironment = curseForgeKey.isNotEmpty;
    try {
      final file = File(p.join(root!.path, 'addons.json'));
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      final saved = data is Map ? '${data['curseForgeKey'] ?? ''}'.trim() : '';
      if (saved.isNotEmpty) {
        curseForgeKey = saved;
        curseForgeKeyFromEnvironment = false;
      }
    } catch (_) {
      // Keep the environment fallback if the saved settings are unreadable.
    }
  }

  Future<void> setCurseForgeKey(String key) async {
    final saved = key.trim();
    curseForgeKey = saved.isEmpty ? _environmentCurseForgeKey : saved;
    curseForgeKeyFromEnvironment = saved.isEmpty && curseForgeKey.isNotEmpty;
    changed();
    final folder = root;
    if (folder == null) return;
    try {
      await File(p.join(folder.path, 'addons.json'))
          .writeAsString(jsonEncode({'curseForgeKey': saved}), flush: true);
    } catch (_) {
      // The key still works for this session.
    }
  }

  /// Installs, updates and removes mods (Fabric) or plugins (Paper, Purpur,
  /// Folia) for the current server.
  AddonManager addons() {
    final current = server;
    if (current == null) throw StateError('HostCraft is still loading.');
    return AddonManager(
      serverDir: current.directory,
      engine: profile.engine,
      mcVersion: profile.version,
      curseForgeKey: curseForgeKey,
      download: DownloadService(
        curseForgeKey: curseForgeKey,
        onProgress: (label, value) {
          progressLabel = label;
          progress = value;
          changed();
        },
        onDetail: _onDownload,
        onNote: log,
        contact: profile.contact,
      ),
      log: log,
    );
  }

  /// A file manager limited to the current server's folder.
  ServerFiles files() {
    final current = server;
    if (current == null) throw StateError('HostCraft is still loading.');
    return ServerFiles(current.directory);
  }

  Future<List<AddonProject>> searchAddons(
    ModSource source,
    String query, {
    int offset = 0,
  }) => addons()
      .provider(source)
      .search(
        query,
        engine: profile.engine,
        mcVersion: profile.version,
        offset: offset,
      );

  Future<List<InstalledAddon>> listAddons() => addons().installed();

  Future<Map<String, AddonFile>> checkAddonUpdates() => addons().checkUpdates();

  Future<void> installAddon(AddonProject project) => action(() async {
    _requireStopped();
    final done = await addons().install(project);
    _clearDownload();
    log(
      done.isEmpty
          ? '${project.title} is already installed.'
          : 'Installed ${done.map((e) => e.title).join(', ')}. Restart the server to load it.',
    );
  });

  Future<void> updateAddon(InstalledAddon addon) => action(() async {
    _requireStopped();
    await addons().update(addon);
    _clearDownload();
    log('${addon.title} updated. Restart the server to load it.');
  });

  Future<void> removeAddon(InstalledAddon addon) => action(() async {
    _requireStopped();
    await addons().remove(addon);
    log('Removed ${addon.title}.');
  });

  Future<void> setAddonEnabled(InstalledAddon addon, bool enabled) =>
      action(() async {
        _requireStopped();
        await addons().setEnabled(addon, enabled);
        log('${addon.title} ${enabled ? 'enabled' : 'disabled'}.');
      });

  Future<void> requestBackgroundAccess() async {
    await BackgroundService.requestUnrestricted();
    batteryUnrestricted = await BackgroundService.isUnrestricted();
    changed();
  }

  Future<void> unlinkPlayit() async {
    await tunnel?.unlink();
    changed();
  }

  Future<void> checkJava() => action(() async {
    final java = await RuntimeService(
      root!,
      DownloadService(
        onProgress: (l, p) {
          progressLabel = l;
          progress = p;
          changed();
        },
        onDetail: _onDownload,
      ),
    ).ensure();
    _clearDownload();
    final result = await Process.run(
      java.executable,
      Platform.isAndroid
          ? [
              '-Djava.home=${java.environment['JAVA_HOME']}',
              '-Djava.class.path=${java.bootstrap}',
              '--',
              '--self-test',
            ]
          : ['-version'],
      environment: java.environment,
    ).timeout(const Duration(seconds: 45));
    log('${result.stdout}\n${result.stderr}');
    if (result.exitCode != 0) {
      throw StateError('Java check failed (${result.exitCode}). See console.');
    }
    log('Java runtime check passed.');
  });
  @override
  void dispose() {
    disposed = true;
    _notifyTimer?.cancel();
    _logs?.cancel();
    download.dispose();
    if (Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_backgroundMessage);
    }
    super.dispose();
  }
}
