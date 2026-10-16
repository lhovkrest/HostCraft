import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import 'download_service.dart';
import 'playit_api.dart';
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
  TunnelService(this.root, this.onLog, this.onChange, {this.localPort});
  final int Function()? localPort;
  final Directory root;
  final void Function(String) onLog;
  final void Function() onChange;

  Process? _process;
  Timer? _refresh;
  PlayitApi? _api;
  int _session = 0;
  String? _executable;
  List<String> _prefix = [];

  TunnelPhase phase = TunnelPhase.idle;
  String status = '';
  String? error;
  String? warning;
  String? claimUrl;
  String? address;

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
    if (Platform.isMacOS) {
      throw UnsupportedError(
        'For macOS, install the Playit agent from playit.gg and configure it for your local server. Automatic agent installation supports Android, Windows and Linux.',
      );
    }
    final arm = Platform.version.contains('arm64');
    final asset = Platform.isWindows
        ? 'playit-windows-x86_64-signed.exe'
        : arm
        ? 'playit-linux-aarch64'
        : 'playit-linux-amd64';
    final hash = Platform.isWindows
        ? '9b00d6ff7d37d1052e5ae097e1348e11deae8617cd7a8ba39d1777f2006316a3'
        : arm
        ? 'cd3fa1cedac40a71d80a120e6353e08836308840340b58e659e8f25d00601f66'
        : 'e78d463d93aa1e3ec36a06ded5a1f4fe879905fdceb865df8f4cef6124f8a555';
    final file = File(p.join(root.path, 'playit', asset));
    if (!await file.exists()) {
      await DownloadService().file(
        'https://github.com/playit-cloud/playit-agent/releases/download/v0.17.1/$asset',
        file,
        checksum: hash,
        label: 'Playit agent',
      );
    }
    if (!Platform.isWindows) await Process.run('chmod', ['+x', file.path]);
    _executable = file.path;
  }

  // ---- account link -------------------------------------------------------

  Future<String?> _readSecret() async {
    final file = File(secretPath);
    if (!await file.exists()) return null;
    final text = (await file.readAsString()).trim();
    final toml = RegExp(
      r'''secret_key\s*=\s*["']([0-9a-fA-F]+)["']''',
    ).firstMatch(text);
    if (toml != null) return toml[1];
    if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) return text;
    return null;
  }

  Future<void> _writeSecret(String secret) async {
    await Directory(p.dirname(secretPath)).create(recursive: true);
    await File(secretPath).writeAsString('secret_key = "$secret"\n', flush: true);
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
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (cancelled()) throw const _Cancelled();
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
          state = await api.claimSetup(code, version: 'hostcraft $appVersion');
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
    bool Function() cancelled,
  ) async {
    var data = await api.agentRunData();
    var tunnel = _pick(data.tunnels, port);
    if (tunnel == null) {
      onLog('Creating a Minecraft tunnel for port $port on Playit…');
      _set(TunnelPhase.creating, 'Creating your Minecraft tunnel…');
      await api.createMinecraftTunnel(agentId: data.agentId, localPort: port);
      for (var attempt = 0; attempt < 30; attempt++) {
        await _wait(const Duration(seconds: 1), cancelled);
        data = await api.agentRunData();
        tunnel = _pick(data.tunnels, port);
        if (tunnel != null && tunnel.ready) break;
      }
    }
    final result = tunnel;
    if (result == null || !result.ready) {
      throw const PlayitApiException(
        'Playit is still preparing your tunnel. Wait a moment and connect again.',
      );
    }
    if (result.disabled) {
      throw PlayitApiException(
        'Your Playit tunnel for port $port is disabled. Enable it in the Playit dashboard, then connect again.',
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
    _set(TunnelPhase.linking, 'Checking your Playit account…');
    PlayitApi? api;
    try {
      final port = localPort?.call() ?? 25565;
      await _install();
      if (cancelled()) return;
      final secret = await _ensureSecret(cancelled);
      if (cancelled()) return;
      api = PlayitApi(secret: secret);
      _set(TunnelPhase.creating, 'Preparing your Minecraft tunnel…');
      final tunnel = await _ensureTunnel(api, port, cancelled);
      if (cancelled()) return;
      address = await _addressFor(api, tunnel);
      if (cancelled()) return;
      _set(TunnelPhase.starting, 'Starting the Playit agent…');
      await _startAgent();
      if (cancelled()) {
        await _killAgent();
        return;
      }
      _api?.close();
      _api = api;
      _set(TunnelPhase.connected, 'Connected');
      _startRefresh(api, session);
    } on _Cancelled {
      api?.close();
      return;
    } catch (e) {
      api?.close();
      if (cancelled()) return;
      await _killAgent();
      error = _message(e);
      onLog('Playit: $error');
      address = null;
      _set(TunnelPhase.failed, '');
    }
  }

  Future<void> _startAgent() async {
    final process = await Process.start(
      _executable!,
      [..._prefix, '--secret_path', secretPath, '--stdout', 'start'],
      workingDirectory: p.dirname(secretPath),
      environment: {'HOME': root.path, 'RUST_LOG': 'info', 'NO_COLOR': '1'},
    );
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
        if (phase == TunnelPhase.connected || phase == TunnelPhase.starting) {
          address = null;
          error = 'The Playit agent stopped unexpectedly (exit code $code).';
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
    final problem = detectProblem(clean);
    if (problem != null && warning != problem) {
      warning = problem;
      onChange();
    }
    final claim = RegExp(
      r'https://playit\.gg/claim/[a-zA-Z0-9_-]+',
    ).firstMatch(clean);
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
      } catch (_) {
        // A missed refresh is harmless; the next one will try again.
      }
    });
  }

  Future<void> _killAgent() async {
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
