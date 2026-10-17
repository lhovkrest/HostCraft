import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/world_config.dart';
import 'background_service.dart';
import 'crossplay_service.dart';
import 'download_service.dart';
import 'process_guard.dart';
import 'runtime_service.dart';
import 'server_catalog.dart';

class MinecraftGameServer extends BaseGameServer {
  MinecraftGameServer({
    required this.profile,
    required this.root,
    required this.onPhase,
    required this.onProgress,
    required this.onMetrics,
    JavaRuntime? runtime,
  }) : _java = runtime;
  final ServerProfile profile;
  final Directory root;
  final void Function(ServerPhase) onPhase;
  final void Function(String, double?) onProgress;
  final void Function(double?, double?) onMetrics;
  final _console = StreamController<String>.broadcast();
  Process? _process;
  JavaRuntime? _java;
  Timer? _timer;
  bool _busy = false;
  bool _stopping = false;
  Future<void>? _stopFuture;
  Future<void>? _exitCleanup;
  int? _ticks;
  DateTime? _sampleTime;
  Directory get directory =>
      Directory(p.join(root.path, 'servers', profile.key));
  @override
  String get gameId => 'minecraft';
  @override
  String get displayName => profile.name;
  @override
  Stream<String> get consoleOutput => _console.stream;
  void log(String line) => _console.add(line);
  File get properties => File(p.join(directory.path, 'server.properties'));

  @override
  Future<void> prepare({bool force = false}) async {
    if (_busy || _process != null) {
      throw StateError('A server operation is already in progress');
    }
    if (!profile.eulaAccepted) {
      throw StateError('Accept the Minecraft EULA before preparing a server');
    }
    if (profile.crossplay && !profile.engine.crossplayCapable) {
      throw StateError(
        'Bedrock crossplay is not available on ${profile.engine.label}. Use Paper, Purpur or Fabric, or turn crossplay off.',
      );
    }
    if (profile.engine.needsContact && profile.contact.trim().isEmpty) {
      throw StateError(
        '${profile.engine.label} requires a contact URL or email. Add it in server setup, or choose another server type.',
      );
    }
    _busy = true;
    onPhase(ServerPhase.preparing);
    try {
      await directory.create(recursive: true);
      final download = DownloadService(
        onProgress: onProgress,
        contact: profile.contact,
      );
      final catalog = ServerCatalog(download);
      // Mojang publishes the Java version each Minecraft version needs
      // (Java 25 from 26.1 on). Anything older than 21 also runs on 21.
      final needed = await catalog.javaMajor(profile.version);
      _java = await RuntimeService(
        root,
        download,
      ).ensure(major: needed < 21 ? 21 : needed);
      final jar = File(p.join(directory.path, 'server.jar'));
      final receipt = File(p.join(directory.path, 'download.json'));
      if (force || !await jar.exists() || !await receipt.exists()) {
        log(
          'Resolving ${profile.engine.label} ${profile.version} from the official download service…',
        );
        final build = await catalog.resolve(profile.engine, profile.version);
        if (build.experimental) {
          log(
            '${profile.engine.label} has no stable build for ${profile.version} yet. Using the newest experimental build; expect bugs.',
          );
        }
        await download.file(
          build.url,
          jar,
          checksum: build.hash,
          algorithm: build.algorithm,
          label: 'Downloading ${profile.engine.label} ${profile.version}',
        );
        await receipt.writeAsString(
          jsonEncode({
            'engine': profile.engine.name,
            'version': profile.version,
            'build': build.build,
            'url': build.url,
            'hash': build.hash,
            'downloadedAt': DateTime.now().toIso8601String(),
          }),
        );
        log('Downloaded ${profile.engine.label} ${profile.version} (${build.build}).');
      }
      await File(p.join(directory.path, 'eula.txt'))
          .writeAsString('# Explicitly accepted in HostCraft\neula=true\n');
      if (!await properties.exists()) {
        // A new server folder starts with the saved world settings.
        final world = await WorldConfig.load(root);
        await properties.writeAsString(
          ServerProperties('').update({
            ...ServerProperties.defaults,
            ...world.toProperties(),
          }),
        );
      }
      final crossplay = CrossplayService(download, log);
      if (profile.crossplay) {
        await crossplay.install(directory, profile.engine, profile.version);
      } else if (profile.engine.crossplayCapable) {
        await crossplay.setEnabled(directory, profile.engine, false);
      }
      log('Server files and Java are ready.');
      onPhase(ServerPhase.ready);
    } catch (e) {
      onPhase(ServerPhase.failed);
      rethrow;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> start() async {
    if (_process != null || _busy) throw StateError('Server is already active');
    if (!await File(p.join(directory.path, 'server.jar')).exists() ||
        _java == null) {
      await prepare();
    }
    _busy = true;
    _stopping = false;
    _ticks = null;
    _sampleTime = null;
    onPhase(ServerPhase.starting);
    try {
      if (!Platform.isAndroid && !Platform.isWindows) {
        throw StateError('HostCraft supports Android and Windows only.');
      }
      if (profile.crossplay) {
        final patched = await CrossplayService(
          DownloadService(),
          log,
        ).applyConfig(directory, profile.engine, profile.bedrockPort);
        if (patched) log('Updated the Geyser settings for Bedrock players.');
        log('Bedrock players connect on UDP port ${profile.bedrockPort}.');
      }
      await BackgroundService.start(profile.name);
      final java = _java!;
      final args = <String>[
        '-Xms256M',
        '-Xmx${profile.memoryMb}M',
        '-Djava.awt.headless=true',
        '-Dfile.encoding=UTF-8',
        '-Djava.net.preferIPv4Stack=true',
      ];
      if (Platform.isAndroid) {
        args.addAll([
          '-Djava.home=${java.environment['JAVA_HOME']}',
          '-Djava.io.tmpdir=${java.environment['TMPDIR']}',
          '-Dio.netty.transport.noNative=true',
          '-Dio.netty.native.workdir=${java.environment['TMPDIR']}',
          '-Djava.class.path=${java.bootstrap}:${p.join(directory.path, 'server.jar')}',
          '--',
          p.join(directory.path, 'server.jar'),
          'nogui',
        ]);
      } else {
        args.addAll(['-jar', 'server.jar', 'nogui']);
      }
      log('Starting Java with ${profile.memoryMb} MB maximum heap…');
      final process = await Process.start(
        java.executable,
        args,
        workingDirectory: directory.path,
        environment: java.environment,
        runInShell: false,
      );
      ProcessGuard.adopt(process.pid);
      _process = process;
      void consume(String line) {
        log(line);
        if (line.contains('Done (') && !_stopping) {
          onPhase(ServerPhase.running);
          if (profile.crossplay) unawaited(_finishCrossplay());
        }
      }

      final out = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach(consume);
      final err = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach(consume);
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _sample(process.pid),
      );
      _exitCleanup = process.exitCode.then((code) async {
        await Future.wait([out, err]);
        if (!identical(_process, process)) return;
        _process = null;
        _timer?.cancel();
        onMetrics(null, null);
        await BackgroundService.stop();
        log('Server exited with code $code.');
        onPhase(
          code == 0 || _stopping ? ServerPhase.ready : ServerPhase.failed,
        );
      });
      unawaited(_exitCleanup);
    } catch (e) {
      await BackgroundService.stop();
      onPhase(ServerPhase.failed);
      rethrow;
    } finally {
      _busy = false;
    }
  }

  /// Geyser creates its config on the first run with defaults that do not let
  /// Floodgate players in. Patch it once and ask for a single restart.
  Future<void> _finishCrossplay() async {
    try {
      final changed = await CrossplayService(
        DownloadService(),
        log,
      ).applyConfig(directory, profile.engine, profile.bedrockPort);
      if (changed) {
        log(
          'Crossplay setup finished. Restart the server once so Bedrock players can join.',
        );
      }
    } catch (e) {
      log('Could not finish the crossplay setup: $e');
    }
  }

  Future<void> _sample(int pid) async {
    if (!Platform.isAndroid) return; // Needs /proc; not available on Windows.
    try {
      final stat = await File('/proc/$pid/stat').readAsString();
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      final ticks = int.parse(fields[11]) + int.parse(fields[12]);
      final now = DateTime.now();
      final status = await File('/proc/$pid/status').readAsString();
      final rss = RegExp(r'VmRSS:\s+(\d+)').firstMatch(status);
      // Android reports its actual clock tick rate.
      final hz = ((await RuntimeService.androidInfo())['clockTicks'] as num)
          .toDouble();
      final cpu = _ticks == null
          ? null
          : (ticks - _ticks!) /
                hz /
                (now.difference(_sampleTime!).inMilliseconds / 1000) *
                100;
      _ticks = ticks;
      _sampleTime = now;
      if (_process?.pid == pid) {
        onMetrics(rss == null ? null : double.parse(rss[1]!) / 1024, cpu);
      }
    } catch (_) {
      if (_process?.pid == pid) onMetrics(null, null);
    }
  }

  @override
  Future<void> sendCommand(String command) async {
    if (command.trim().isEmpty) return;
    if (command.contains('\n') || command.contains('\r')) {
      throw ArgumentError('Send one command at a time');
    }
    final process = _process;
    if (process == null) {
      throw StateError('Start the server before sending commands');
    }
    process.stdin.writeln(command);
    await process.stdin.flush();
    log('> $command');
  }

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 45)}) =>
      _stopFuture ??= _stop(grace).whenComplete(() => _stopFuture = null);
  Future<void> _stop(Duration grace) async {
    final process = _process;
    if (process == null) return;
    _stopping = true;
    onPhase(ServerPhase.stopping);
    try {
      await sendCommand('stop');
    } catch (_) {
      process.kill();
    }
    try {
      await process.exitCode.timeout(grace);
    } on TimeoutException {
      log('Graceful stop timed out. Terminating Java.');
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
    }
    await _exitCleanup;
  }

  Future<void> dispose() async {
    await stop();
    _timer?.cancel();
    await _console.close();
  }
}
