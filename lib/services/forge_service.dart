import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/models.dart';

import 'download_service.dart';
import 'process_guard.dart';
import 'runtime_service.dart';
import 'server_catalog.dart';

/// Installs the official Forge distribution and uses its Java argument file.
/// The Android JNI launcher does not support Forge's module-path bootstrap.
class ForgeService {
  static const supportedPlatform = 'Windows';

  static Future<String?> launchFile(Directory directory) async {
    try {
      final receipt = File(p.join(directory.path, 'forge-install.json'));
      if (!await receipt.exists()) return null;
      final data = jsonDecode(await receipt.readAsString()) as Map;
      final relative = data['arguments'] as String;
      if (!RegExp(
        r'^libraries/net/minecraftforge/forge/[0-9.\-]+/win_args\.txt$',
      ).hasMatch(relative))
        return null;
      final file = File(p.join(directory.path, relative));
      return await file.exists() && await file.length() > 0 ? relative : null;
    } on Object {
      return null;
    }
  }

  static Future<void> install({
    required Directory directory,
    required String minecraftVersion,
    required JavaRuntime java,
    required DownloadService download,
    required ServerCatalog catalog,
    required void Function(String) log,
    bool force = false,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Forge hosting currently requires Windows. Choose Fabric or Paper on Android.',
      );
    }
    if (!force && await launchFile(directory) != null) return;
    final receipt = File(p.join(directory.path, 'forge-install.json'));
    // Invalidate the ready marker before attempting a replacement install.
    if (await receipt.exists()) await receipt.delete();
    final build = await catalog.resolve(ServerEngine.forge, minecraftVersion);
    final installer = File(p.join(directory.path, 'forge-installer.jar'));
    await download.file(
      build.url,
      installer,
      checksum: build.hash,
      algorithm: build.algorithm,
      label: 'Downloading Forge ${build.build}',
    );
    download.step('Installing Forge libraries — this can take a few minutes');
    log('Installing Forge ${build.build} for Minecraft $minecraftVersion…');
    final process = await Process.start(
      java.executable,
      [
        '-Djava.awt.headless=true',
        '-Djava.net.preferIPv4Stack=true',
        '-jar',
        installer.path,
        '--installServer',
        '.',
      ],
      workingDirectory: directory.path,
      environment: java.environment,
      runInShell: false,
    );
    ProcessGuard.adopt(process.pid);
    final output = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach(log);
    final errors = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach(log);
    int code;
    try {
      code = await process.exitCode.timeout(const Duration(minutes: 15));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
      await Future.wait([output, errors]);
      throw StateError(
        'Forge installation timed out. Check the console and retry when your connection is stable.',
      );
    }
    await Future.wait([output, errors]);
    if (code != 0) {
      throw StateError(
        'Forge installer exited with code $code. Check the console for the failed dependency, then retry.',
      );
    }
    final relative =
        'libraries/net/minecraftforge/forge/$minecraftVersion-${build.build}/win_args.txt';
    final arguments = File(p.join(directory.path, relative));
    if (!await arguments.exists() || await arguments.length() == 0) {
      throw StateError(
        'Forge did not produce its server launch arguments. Check the installer output in Console.',
      );
    }
    await receipt.writeAsString(
      jsonEncode({
        'minecraft': minecraftVersion,
        'build': build.build,
        'arguments': relative,
        'installedAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
    log(
      'Forge ${build.build} is installed. Add matching Forge mods in Mods & plugins.',
    );
  }
}
