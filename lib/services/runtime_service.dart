import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'download_service.dart';

class JavaRuntime {
  const JavaRuntime(this.executable, this.environment, {this.bootstrap});
  final String executable;
  final Map<String, String> environment;
  final String? bootstrap;
}

class RuntimeService {
  RuntimeService(this.root, this.download);
  final Directory root;
  final DownloadService download;
  static const platform = MethodChannel('dev.hostcraft/runtime');
  static Future<Map<String, dynamic>> androidInfo() async =>
      Map<String, dynamic>.from(await platform.invokeMethod('info'));
  Future<JavaRuntime> ensure({int major = 21}) async {
    if (Platform.isAndroid) {
      download.onProgress?.call('Installing bundled Android Java 21', null);
      final info = Map<String, dynamic>.from(
        await platform.invokeMethod('installRuntime'),
      );
      final home = info['javaHome'] as String;
      return JavaRuntime('${info['nativeLibraryDir']}/libhostcraft_exec.so', {
        'JAVA_HOME': home,
        'HOME': root.path,
        'TMPDIR': info['cacheDir'],
        'LD_LIBRARY_PATH':
            '$home/lib:$home/lib/server:${info['nativeLibraryDir']}',
      }, bootstrap: info['bootstrap']);
    }
    final os = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'mac'
        : 'linux';
    final arch = Platform.version.contains('arm64') ? 'aarch64' : 'x64';
    final dest = Directory(p.join(root.path, 'runtimes', '$major-$os-$arch'));
    final marker = File(p.join(dest.path, 'java-path.txt'));
    if (await marker.exists()) {
      final executable = await marker.readAsString();
      if (await File(executable).exists()) return JavaRuntime(executable, {});
    }
    final data = await download.json(
      'https://api.adoptium.net/v3/assets/latest/$major/hotspot?architecture=$arch&image_type=jre&os=$os&vendor=eclipse',
    ) as List;
    if (data.isEmpty) {
      throw StateError('No Java $major runtime for $os / $arch');
    }
    final pkg = data.first['binary']['package'];
    final archive = File(p.join(root.path, pkg['name']));
    await download.file(
      pkg['link'],
      archive,
      checksum: pkg['checksum'],
      label: 'Downloading Java $major',
    );
    await dest.create(recursive: true);
    download.onProgress?.call('Extracting Java $major', null);
    if (Platform.isWindows) {
      await extractFileToDisk(archive.path, dest.path);
    } else {
      final result = await Process.run('tar', [
        '-xzf',
        archive.path,
        '-C',
        dest.path,
      ]);
      if (result.exitCode != 0) {
        throw ProcessException('tar', [], '${result.stderr}', result.exitCode);
      }
    }
    final executable = await dest
        .list(recursive: true)
        .where(
          (e) =>
              e is File &&
              p.basename(e.path) == (Platform.isWindows ? 'java.exe' : 'java'),
        )
        .first;
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', executable.path]);
    }
    await marker.writeAsString(executable.path);
    await archive.delete();
    return JavaRuntime(executable.path, {});
  }
}
