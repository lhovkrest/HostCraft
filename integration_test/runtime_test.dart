import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hostcraft/services/runtime_service.dart';
import 'package:hostcraft/services/download_service.dart';
import 'package:hostcraft/services/background_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('packaged Java runs in Android app sandbox and opens a socket', (
    tester,
  ) async {
    final root = await getApplicationSupportDirectory();
    final runtime = await RuntimeService(root, DownloadService()).ensure();
    final process = await Process.start(runtime.executable, [
      '-Djava.home=${runtime.environment['JAVA_HOME']}',
      '-Djava.class.path=${runtime.bootstrap}',
      '--',
      '--self-test',
    ], environment: runtime.environment);
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 90));
      final output = await stdout;
      final errors = await stderr;
      expect(code, 0, reason: errors);
      expect(output, contains('HostCraft Java ready'));
      expect(output, contains('TCP bind successful'));
    } finally {
      process.kill();
    }
    BackgroundService.initialize();
    await BackgroundService.start('Runtime test');
    await BackgroundService.stop();
  });
  testWidgets('packaged Playit executable starts', (tester) async {
    final info = await RuntimeService.androidInfo();
    final result = await Process.run(
      '${info['nativeLibraryDir']}/libhostcraft_exec.so',
      ['--exec', '${info['nativeLibraryDir']}/libplayit.so', 'version'],
    ).timeout(const Duration(seconds: 30));
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('0.17.1'));
  });
}
