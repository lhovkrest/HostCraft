import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/minecraft_server.dart';
import '../services/tunnel_service.dart';
import '../services/download_service.dart';
import '../services/runtime_service.dart';
import 'models.dart';

final hostProvider = ChangeNotifierProvider<HostController>(
  (ref) => HostController()..initialize(),
);

class HostController extends ChangeNotifier {
  ServerProfile profile = const ServerProfile();
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
  double? rssMb;
  double? cpu;
  DateTime? startedAt;
  List<String> lanAddresses = [];
  int serverPort = 25565;
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
      final file = File(p.join(root!.path, 'profile.json'));
      if (await file.exists()) {
        profile = ServerProfile.fromJson(jsonDecode(await file.readAsString()));
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
        if (value == ServerPhase.ready || value == ServerPhase.failed) {
          startedAt = null;
          unawaited(tunnel?.stop() ?? Future.value());
        }
        changed();
      },
      onProgress: (label, value) {
        progressLabel = label;
        progress = value;
        changed();
      },
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
    );
    phase = await File(p.join(server!.directory.path, 'server.jar')).exists()
        ? ServerPhase.ready
        : ServerPhase.idle;
    serverPort =
        int.tryParse((await readSettings())['server-port'] ?? '') ?? 25565;
  }

  Future<void> configure(ServerProfile next) async {
    if (active || phase == ServerPhase.preparing) {
      throw StateError('Stop the server before changing its setup');
    }
    profile = next;
    await File(p.join(root!.path, 'profile.json'))
        .writeAsString(jsonEncode(next.toJson()), flush: true);
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
  Future<void> command(String text) => action(() => server!.sendCommand(text));
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

  Future<void> checkJava() => action(() async {
    final java = await RuntimeService(
      root!,
      DownloadService(
        onProgress: (l, p) {
          progressLabel = l;
          progress = p;
          changed();
        },
      ),
    ).ensure();
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
    if (Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_backgroundMessage);
    }
    super.dispose();
  }
}
