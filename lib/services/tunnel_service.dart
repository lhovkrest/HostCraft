import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import 'download_service.dart';
import 'playit_api.dart';
import 'process_guard.dart';
import 'runtime_service.dart';

enum TunnelPhase { idle, linking, creating, starting, connected, failed }

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Connects the local Minecraft server to the public internet with Playit.
///
/// Account linking, tunnel creation and the public address all go through the
/// Playit HTTP API ([PlayitApi]). The Playit agent process is only started to
/// carry the traffic once the tunnel exists, so nothing depends on parsing the
/// agent's console output any more.
class TunnelService {
  TunnelService(
    this.root,
    this.onLog,
    this.onChange, {
    this.localPort,
    this.bedrockPort,
  });
  final int Function()? localPort;

  /// UDP port of Geyser, or null when Bedrock crossplay is off.
  final int? Function()? bedrockPort;
  final Directory root;
  final void Function(String) onLog;
  final void Function() onChange;

  Process? _process;
  Timer? _refresh;
  PlayitApi? _api;
  int _session = 0;
  String? _executable;
  List<String> _prefix = [];
  bool _expectAgent = false;
  final _recent = <String>[];

  TunnelPhase phase = TunnelPhase.idle;
  String status = '';
  String? error;
  String? warning;
  String? claimUrl;
  String? address;

  /// Public address for Bedrock players (host:port), when crossplay is on.
  String? bedrockAddress;

  /// Why the Bedrock tunnel is missing even though Java works.
  String? bedrockNote;

  bool get running => _process != null;
  bool get busy =>
      phase == TunnelPhase.linking ||
      phase == TunnelPhase.creating ||
      phase == TunnelPhase.starting;
  bool get connected => phase == TunnelPhase.connected && running;
  String get secretPath => p.join(root.path, 'playit', 'playit.toml');

  void _set(TunnelPhase next, String text) {
    phase = next;
    status = text;
    onChange();
  }

  Future<void> _install() async {
    if (_executable != null) return;
    await Directory(p.dirname(secretPath)).create(recursive: true);
    if (Platform.isAndroid) {
      final info = await RuntimeService.androidInfo();
      _executable = '${info['nativeLibraryDir']}/libhostcraft_exec.so';
      _prefix = ['--exec', '${info['nativeLibraryDir']}/libplayit.so'];
      return;
    }
    if (!Platform.isWindows) {
      throw UnsupportedError('HostCraft supports Android and Windows only.');
    }
    // Since Playit 1.0 the release named "playit-windows-x86_64-signed.exe" is
    // the playitd daemon (the thing that actually carries traffic). It also
    // runs on Windows on ARM through x64 emulation.
    const asset = 'playit-windows-x86_64-signed.exe';
    const hash =
        '2dbdaad119844cbbc062cc9774b8b462afa5f1b4b7832a9fc5ef4676cae887cf';
    final file = File(p.join(root.path, 'playit', playitAgentVersion, asset));
    if (!await file.exists()) {
      await DownloadService().file(
        'https://github.com/playit-cloud/playit-agent/releases/download/v$playitAgentVersion/$asset',
        file,
        checksum: hash,
        label: 'Playit agent',
      );
    }
    _executable = file.path;
  }

  // ---- account link -------------------------------------------------------

  Future<String?> _readSecret() async {
    final file = File(secretPath);
    if (!await file.exists()) return null;
    final text = (await file.readAsString()).trim();
    final toml = RegExp(r'''secret_key\s*=\s*["']([0-9a-fA-F]+)["']''')
        .firstMatch(text);
    if (toml != null) return toml[1];
    if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) return text;
    return null;
  }

  Future<void> _writeSecret(String secret) async {
    await Directory(p.dirname(secretPath)).create(recursive: true);
    await File(secretPath)
        .writeAsString('secret_key = "$secret"\n', flush: true);
  }

  /// Whether a Playit account link is stored on this device.
  Future<bool> get linked async => await _readSecret() != null;

  static String _newClaimCode() {
    final random = Random.secure();
    return List.generate(
      5,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _wait(Duration time, bool Function() cancelled) async {
    final end = DateTime.now().add(time);
    while (DateTime.now().isBefore(end)) {
      if (cancelled()) throw const _Cancelled();
      if (_expectAgent && _process == null) throw _agentGone();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (cancelled()) throw const _Cancelled();
    if (_expectAgent && _process == null) throw _agentGone();
  }

  /// Error shown when the agent process ended while we still needed it.
  PlayitApiException _agentGone() {
    String? hint;
    for (final line in _recent.reversed) {
      if (line.toLowerCase().contains('error')) {
        hint = line.length > 180 ? '${line.substring(0, 180)}…' : line;
        break;
      }
    }
    return PlayitApiException(
      'The Playit agent stopped before the tunnel was ready.'
      '${hint == null ? '' : ' Last error: $hint'}',
    );
  }

  Future<String> _ensureSecret(bool Function() cancelled) async {
    final saved = await _readSecret();
    if (saved != null) {
      final api = PlayitApi(secret: saved);
      try {
        await api.agentRunData();
        return saved;
      } on PlayitApiException catch (e) {
        if (!e.auth) rethrow;
        onLog('The saved Playit link is no longer valid. Linking again.');
        await _forget();
      } finally {
        api.close();
      }
    }
    return _claim(cancelled);
  }

  Future<String> _claim(bool Function() cancelled) async {
    final code = _newClaimCode();
    final api = PlayitApi();
    try {
      claimUrl = 'https://playit.gg/claim/$code';
      _set(
        TunnelPhase.linking,
        'Open the link and approve HostCraft in Playit.',
      );
      onLog('Approve HostCraft in Playit: $claimUrl');
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (true) {
        if (cancelled()) throw const _Cancelled();
        if (DateTime.now().isAfter(deadline)) {
          throw const PlayitApiException(
            'The approval link expired. Connect again to get a new one.',
          );
        }
        var state = '';
        try {
          state = await api.claimSetup(
            code,
            version: 'playit-agent $playitAgentVersion',
          );
        } on PlayitApiException catch (e) {
          if (e.code == 'CodeExpired' || e.code == 'InvalidCode') rethrow;
          await _wait(const Duration(seconds: 3), cancelled);
          continue;
        }
        if (state == 'UserRejected') {
          throw const PlayitApiException('The link was declined in Playit.');
        }
        if (state == 'UserAccepted') break;
        await _wait(const Duration(seconds: 2), cancelled);
      }
      _set(TunnelPhase.linking, 'Approved. Finishing the link…');
      var secret = '';
      while (true) {
        if (cancelled()) throw const _Cancelled();
        if (DateTime.now().isAfter(deadline)) {
          throw const PlayitApiException(
            'Playit took too long to finish the link. Connect again.',
          );
        }
        try {
          secret = await api.claimExchange(code);
          break;
        } on PlayitApiException catch (e) {
          if (e.network || e.code == 'NotAccepted' || e.code == 'NotSetup') {
            await _wait(const Duration(seconds: 2), cancelled);
            continue;
          }
          rethrow;
        }
      }
      await _writeSecret(secret);
      onLog('Playit account linked.');
      return secret;
    } finally {
      api.close();
      claimUrl = null;
    }
  }

  Future<void> _forget() async {
    final file = File(secretPath);
    if (await file.exists()) await file.delete();
  }

  /// Removes the stored account link so the next connect asks again.
  Future<void> unlink() async {
    await stop();
    await _forget();
    onLog('Playit account unlinked.');
    onChange();
  }

  // ---- tunnel -------------------------------------------------------------

  static PlayitTunnel? _pick(List<PlayitTunnel> tunnels, int port) {
    PlayitTunnel? fallback;
    for (final tunnel in tunnels) {
      if (tunnel.localPort != port || !tunnel.carriesTcp) continue;
      if (tunnel.tunnelType == 'minecraft-java') return tunnel;
      fallback ??= tunnel;
    }
    return fallback;
  }

  static PlayitTunnel? _pickBedrock(List<PlayitTunnel> tunnels, int port) {
    PlayitTunnel? fallback;
    for (final tunnel in tunnels) {
      if (tunnel.localPort != port || !tunnel.carriesUdp) continue;
      if (tunnel.tunnelType == 'minecraft-bedrock') return tunnel;
      fallback ??= tunnel;
    }
    return fallback;
  }

  Future<String> _addressFor(PlayitApi api, PlayitTunnel tunnel) async {
    try {
      final display = await api.displayAddresses();
      return display[tunnel.id] ?? tunnel.fallbackAddress;
    } catch (_) {
      return tunnel.fallbackAddress;
    }
  }

  Future<PlayitTunnel> _ensureTunnel(
    PlayitApi api,
    int port,
    bool Function() cancelled, {
    bool bedrock = false,
  }) async {
    PlayitTunnel? find(PlayitRunData d) =>
        bedrock ? _pickBedrock(d.tunnels, port) : _pick(d.tunnels, port);
    final label = bedrock ? 'Bedrock' : 'Java';
    var data = await api.agentRunData();
    var tunnel = find(data);
    if (tunnel == null) {
      onLog('Creating a Minecraft $label tunnel for port $port on Playit…');
      _set(TunnelPhase.creating, 'Creating your $label tunnel…');
      for (var i = 0; ; i++) {
        try {
          await api.createTunnel(
            agentId: data.agentId,
            localPort: port,
            tunnelType: bedrock ? 'minecraft-bedrock' : 'minecraft-java',
            portType: bedrock ? 'udp' : 'tcp',
            name: bedrock ? 'HostCraft Bedrock' : 'HostCraft',
          );
          break;
        } on PlayitApiException catch (e) {
          // The agent may still be registering with Playit. Wait and retry.
          if ((e.code != 'AgentVersionTooOld' && !e.network) || i >= 15) {
            rethrow;
          }
          await _wait(const Duration(seconds: 2), cancelled);
          if (cancelled()) throw const _Cancelled();
          data = await api.agentRunData();
        }
      }
      for (var attempt = 0; attempt < 30; attempt++) {
        await _wait(const Duration(seconds: 1), cancelled);
        data = await api.agentRunData();
        tunnel = find(data);
        if (tunnel != null && tunnel.ready) break;
      }
    }
    final result = tunnel;
    if (result == null || !result.ready) {
      throw PlayitApiException(
        'Playit is still preparing your $label tunnel. Wait a moment and connect again.',
      );
    }
    if (result.disabled) {
      throw PlayitApiException(
        'Your Playit $label tunnel for port $port is disabled. Enable it in the Playit dashboard, then connect again.',
      );
    }
    return result;
  }

  // ---- lifecycle ----------------------------------------------------------

  static String _message(Object e) {
    if (e is PlayitApiException) return e.message;
    if (e is UnsupportedError && e.message != null) return '${e.message}';
    return e.toString().replaceFirst(
      RegExp(r'^(Exception|Bad state|Unsupported operation): '),
      '',
    );
  }

  Future<void> start() async {
    if (running || busy) return;
    final session = ++_session;
    bool cancelled() => session != _session;
    error = null;
    warning = null;
    claimUrl = null;
    address = null;
    bedrockAddress = null;
    bedrockNote = null;
    _set(TunnelPhase.linking, 'Checking your Playit account…');
    PlayitApi? api;
    try {
      final port = localPort?.call() ?? 25565;
      await _install();
      if (cancelled()) return;
      final secret = await _ensureSecret(cancelled);
      if (cancelled()) return;
      api = PlayitApi(secret: secret);

      // The agent must connect first, otherwise Playit rejects tunnel
      // creation with AgentVersionTooOld.
      _set(TunnelPhase.starting, 'Starting the Playit agent…');
      await _startAgent();
      _expectAgent = true;
      // Catches an agent that crashes immediately (bad flags, blocked, etc.)
      // instead of waiting for the tunnel polls to time out.
      await _wait(const Duration(seconds: 2), cancelled);
      if (cancelled()) {
        await _killAgent();
        api.close();
        return;
      }

      _set(TunnelPhase.creating, 'Preparing your Minecraft tunnel…');
      final tunnel = await _ensureTunnel(api, port, cancelled);
      if (cancelled()) {
        await _killAgent();
        api.close();
        return;
      }
      address = await _addressFor(api, tunnel);
      if (cancelled()) {
        await _killAgent();
        api.close();
        return;
      }

      // Bedrock is optional: if its tunnel cannot be made (for example the
      // free tunnel limit is used up), Java players can still join.
      final bedrockLocal = bedrockPort?.call();
      if (bedrockLocal != null) {
        try {
          final bedrock = await _ensureTunnel(
            api,
            bedrockLocal,
            cancelled,
            bedrock: true,
          );
          bedrockAddress = await _addressFor(api, bedrock);
        } on _Cancelled {
          rethrow;
        } on PlayitApiException catch (e) {
          if (e.auth || _process == null) rethrow;
          bedrockNote = 'Bedrock tunnel unavailable: ${e.message}';
          onLog('Playit: $bedrockNote');
        } catch (e) {
          if (_process == null) rethrow;
          bedrockNote = 'Bedrock tunnel unavailable: $e';
          onLog('Playit: $bedrockNote');
        }
        if (cancelled()) {
          await _killAgent();
          api.close();
          return;
        }
      }

      _api?.close();
      _api = api;
      _set(TunnelPhase.connected, 'Connected');
      _startRefresh(api, session);
    } on _Cancelled {
      api?.close();
      await _killAgent();
      return;
    } catch (e) {
      api?.close();
      if (cancelled()) return;
      await _killAgent();
      error = _message(e);
      onLog('Playit: $error');
      address = null;
      bedrockAddress = null;
      _set(TunnelPhase.failed, '');
    }
  }

  /// Where the daemon listens for its (unused) local control channel. It is
  /// private to HostCraft so it never clashes with a Playit service the user
  /// may have installed separately.
  String get _socketPath => Platform.isWindows
      ? r'\\.\pipe\hostcraft-playitd'
      : p.join(p.dirname(secretPath), 'playitd.sock');

  /// Command line for the agent. The bundled Android `libplayit.so` is an
  /// older build that only understands `--secret_path <PATH>` (underscore);
  /// the Windows download is the Playit 1.0 daemon, which uses hyphenated
  /// flags. Passing the wrong style makes the agent exit with code 2.
  List<String> get _agentArgs => Platform.isAndroid
      ? [..._prefix, '--secret_path', secretPath]
      : ['--secret-path', secretPath, '--socket-path', _socketPath];

  Future<void> _startAgent() async {
    _recent.clear();
    if (!Platform.isWindows) {
      try {
        final stale = File(_socketPath);
        if (await stale.exists()) await stale.delete();
      } catch (_) {}
    }
    // Playit 1.0 replaced the old `playit --secret_path X start` agent with the
    // playitd daemon, which takes hyphenated flags and starts by itself. The
    // `playit-cli` front-end only talks to an installed service, so it can
    // never be used to carry traffic from inside the app.
    final process = await Process.start(
      _executable!,
      _agentArgs,
      workingDirectory: p.dirname(secretPath),
      environment: {
        'HOME': root.path,
        'RUST_LOG': 'info',
        'PLAYIT_LOG': 'info',
        'NO_COLOR': '1',
      },
      runInShell: false,
    );
    ProcessGuard.adopt(process.pid);
    _process = process;
    final out = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_agentLine);
    final err = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_agentLine);
    unawaited(
      process.exitCode.then((code) async {
        await out.cancel();
        await err.cancel();
        if (!identical(_process, process)) return;
        _process = null;
        _refresh?.cancel();
        onLog('Agent exited with code $code');
        if (phase == TunnelPhase.connected ||
            phase == TunnelPhase.starting ||
            phase == TunnelPhase.creating) {
          address = null;
          bedrockAddress = null;
          error = _agentGone().message.replaceFirst(
            'before the tunnel was ready',
            'unexpectedly (exit code $code)',
          );
          _set(TunnelPhase.failed, '');
        } else {
          onChange();
        }
      }),
    );
  }

  void _agentLine(String value) {
    final clean = value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    onLog(clean);
    _recent.add(clean);
    if (_recent.length > 20) _recent.removeAt(0);
    final problem = detectProblem(clean);
    if (problem != null && warning != problem) {
      warning = problem;
      onChange();
    }
    final claim = RegExp(r'https://playit\.gg/claim/[a-zA-Z0-9_-]+')
        .firstMatch(clean);
    if (claim != null && claimUrl != claim[0]) {
      // The agent lost its link and is asking for approval again.
      claimUrl = claim[0];
      onChange();
    }
    final publicAddress = parseTunnelAddress(clean, localPort?.call() ?? 25565);
    if (publicAddress != null && publicAddress != address) {
      address = publicAddress;
      claimUrl = null;
      onChange();
    }
  }

  void _startRefresh(PlayitApi api, int session) {
    _refresh?.cancel();
    _refresh = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (session != _session || _process == null) return;
      try {
        final data = await api.agentRunData();
        final tunnel = _pick(data.tunnels, localPort?.call() ?? 25565);
        if (tunnel == null) return;
        final latest = await _addressFor(api, tunnel);
        if (session == _session && latest != address) {
          address = latest;
          onChange();
        }
        final bedrockLocal = bedrockPort?.call();
        if (bedrockLocal != null && bedrockAddress != null) {
          final bedrock = _pickBedrock(data.tunnels, bedrockLocal);
          if (bedrock != null) {
            final fresh = await _addressFor(api, bedrock);
            if (session == _session && fresh != bedrockAddress) {
              bedrockAddress = fresh;
              onChange();
            }
          }
        }
      } catch (_) {
        // A missed refresh is harmless; the next one will try again.
      }
    });
  }

  Future<void> _killAgent() async {
    _expectAgent = false;
    final process = _process;
    if (process == null) return;
    _process = null;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  Future<void> stop() async {
    _session++;
    _refresh?.cancel();
    _refresh = null;
    await _killAgent();
    _api?.close();
    _api = null;
    phase = TunnelPhase.idle;
    status = '';
    error = null;
    warning = null;
    claimUrl = null;
    address = null;
    bedrockAddress = null;
    bedrockNote = null;
    onChange();
  }

  // ---- parsing helpers ----------------------------------------------------

  static String? parseTunnelAddress(String line, int port) {
    final m = RegExp(
      r'^\s*([a-zA-Z0-9][a-zA-Z0-9.:-]+)\s+=>\s+(?:127\.0\.0\.1|localhost|\[::1\]):(\d+)\s*$',
    ).firstMatch(line);
    return m != null && int.tryParse(m[2]!) == port ? m[1] : null;
  }

  /// Recognises agent output that means traffic cannot flow even though the
  /// process is alive (most commonly failed DNS lookups on Android).
  static String? detectProblem(String line) {
    final text = line.toLowerCase();
    const dns = [
      'dns error',
      'failed to lookup address',
      'temporary failure in name resolution',
      'name or service not known',
      'no such host',
    ];
    for (final marker in dns) {
      if (text.contains(marker)) {
        return 'The Playit agent cannot look up domain names on this device, so players may not be able to join through the tunnel. Check the "playit" lines in the console.';
      }
    }
    return null;
  }
}
