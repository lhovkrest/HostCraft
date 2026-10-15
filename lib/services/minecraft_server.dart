import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'background_service.dart';
import 'download_service.dart';
import 'runtime_service.dart';

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
  Future<void> prepare() async {
    if (_busy || _process != null) {
      throw StateError('A server operation is already in progress');
    }
    if (!profile.eulaAccepted) {
      throw StateError('Accept the Minecraft EULA before preparing a server');
    }
    _busy = true;
    onPhase(ServerPhase.preparing);
    try {
      await directory.create(recursive: true);
      final download = DownloadService(
        onProgress: onProgress,
        contact: profile.contact,
      );
      _java = await RuntimeService(root, download).ensure();
      final jar = File(p.join(directory.path, 'server.jar'));
      final receipt = File(p.join(directory.path, 'download.json'));
      if (!await jar.exists() || !await receipt.exists()) {
        log(
          'Resolving ${profile.engine.name} ${profile.version} from the official download service…',
        );
        late String url;
        late String hash;
        var useSha1 = false;
        if (profile.engine == ServerEngine.paper) {
          if (profile.contact.trim().isEmpty) {
            throw StateError(
              'Paper requires a contact URL or email. Add it in server setup, or choose Vanilla.',
            );
          }
          final builds = await download.json(
            'https://fill.papermc.io/v3/projects/paper/versions/${profile.version}/builds',
          ) as List;
          final stable = builds.where((b) => b['channel'] == 'STABLE');
          if (stable.isEmpty) {
            throw StateError(
              'No stable Paper build available for ${profile.version}',
            );
          }
          final item = stable.first['downloads']['server:default'];
          url = item['url'];
          hash = item['checksums']['sha256'];
        } else {
          final manifest = await download.json(
            'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
          );
          final versions = (manifest['versions'] as List).where(
            (v) => v['id'] == profile.version,
          );
          if (versions.isEmpty) throw StateError('Minecraft version not found');
          final metadata = await download.json(versions.first['url']);
          final item = metadata['downloads']['server'];
          url = item['url'];
          hash = item['sha1'];
          useSha1 = true;
          final requiredJava =
              metadata['javaVersion']?['majorVersion'] as int? ?? 21;
          if (requiredJava > 21) {
            throw StateError('This build supports Java 21 servers only');
          }
        }
        await download.file(
          url,
          jar,
          checksum: hash,
          useSha1: useSha1,
          label: 'Downloading ${profile.engine.name} ${profile.version}',
        );
        await receipt.writeAsString(
          jsonEncode({
            'url': url,
            'hash': hash,
            'downloadedAt': DateTime.now().toIso8601String(),
          }),
        );
      }
      await File(p.join(directory.path, 'eula.txt'))
          .writeAsString('# Explicitly accepted in HostCraft\neula=true\n');
      if (!await properties.exists()) {
        await properties.writeAsString(
          ServerProperties('').update(ServerProperties.defaults),
        );
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
      _process = process;
      void consume(String line) {
        log(line);
        if (line.contains('Done (') && !_stopping) onPhase(ServerPhase.running);
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

  Future<void> _sample(int pid) async {
    if (!Platform.isAndroid && !Platform.isLinux) return;
    try {
      final stat = await File('/proc/$pid/stat').readAsString();
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      final ticks = int.parse(fields[11]) + int.parse(fields[12]);
      final now = DateTime.now();
      final status = await File('/proc/$pid/status').readAsString();
      final rss = RegExp(r'VmRSS:\s+(\d+)').firstMatch(status);
      // Linux USER_HZ is conventionally 100; Android reports its actual value.
      final hz = Platform.isAndroid
          ? ((await RuntimeService.androidInfo())['clockTicks'] as num)
                .toDouble()
          : 100.0;
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
  Future<void> stop() =>
      _stopFuture ??= _stop().whenComplete(() => _stopFuture = null);
  Future<void> _stop() async {
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
      await process.exitCode.timeout(const Duration(seconds: 45));
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
