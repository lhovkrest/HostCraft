import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'download_service.dart';
import 'runtime_service.dart';

class TunnelService {
  TunnelService(this.root, this.onLog, this.onChange, {this.localPort});
  final int Function()? localPort;
  final Directory root;
  final void Function(String) onLog;
  final void Function() onChange;
  Process? _process;
  bool busy = false;
  String? claimUrl;
  String? address;
  String? _executable;
  List<String> _prefix = [];
  bool get running => _process != null;
  String get secretPath => p.join(root.path, 'playit', 'playit.toml');
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

  Future<void> start() async {
    if (running || busy) return;
    busy = true;
    claimUrl = null;
    address = null;
    onChange();
    try {
      await _install();
      final process = await Process.start(
        _executable!,
        [..._prefix, '--secret_path', secretPath, '--stdout', 'start'],
        workingDirectory: p.dirname(secretPath),
        environment: {'HOME': root.path, 'RUST_LOG': 'info', 'NO_COLOR': '1'},
      );
      _process = process;
      void line(String value) {
        final clean = value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
        onLog(clean);
        final match = RegExp(r'https://playit\.gg/claim/[a-zA-Z0-9_-]+')
            .firstMatch(clean);
        if (match != null) {
          claimUrl = match[0];
          onChange();
        }
        final publicAddress = parseTunnelAddress(
          clean,
          localPort?.call() ?? 25565,
        );
        if (publicAddress != null && publicAddress != address) {
          address = publicAddress;
          claimUrl = null;
          onChange();
        }
        if (clean.contains('Add tunnels here:')) {
          address = null;
          onChange();
        }
      }

      final out = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(line);
      final err = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(line);
      unawaited(
        process.exitCode.then((code) async {
          await out.cancel();
          await err.cancel();
          if (identical(_process, process)) {
            _process = null;
            address = null;
            onLog('Agent exited with code $code');
            onChange();
          }
        }),
      );
    } finally {
      busy = false;
      onChange();
    }
  }

  static String? parseTunnelAddress(String line, int port) {
    final m = RegExp(
      r'^\s*([a-zA-Z0-9][a-zA-Z0-9.:-]+)\s+=>\s+(?:127\.0\.0\.1|localhost|\[::1\]):(\d+)\s*$',
    ).firstMatch(line);
    return m != null && int.tryParse(m[2]!) == port ? m[1] : null;
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    _process = null;
    address = null;
    onChange();
  }
}
