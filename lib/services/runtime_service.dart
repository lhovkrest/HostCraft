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

  /// Newest Java the Android build bundles. Minecraft 26.1 and later need Java
  /// 25, so raise this when a Java 25 runtime is added to the APK.
  static const androidMaxJava = 21;
  static Future<Map<String, dynamic>> androidInfo() async =>
      Map<String, dynamic>.from(await platform.invokeMethod('info'));
  Future<JavaRuntime> ensure({int major = 21}) async {
    if (Platform.isAndroid) {
      if (major > androidMaxJava) {
        throw StateError(
          'This Minecraft version needs Java $major, but the Android app bundles Java $androidMaxJava. '
          'Choose an older version (1.21.11 or earlier), or host on Windows.',
        );
      }
      download.step('Installing bundled Android Java $androidMaxJava');
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
    if (!Platform.isWindows) {
      throw UnsupportedError('HostCraft supports Android and Windows only.');
    }
    const os = 'windows';
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
    if (await dest.exists()) await dest.delete(recursive: true);
    await dest.create(recursive: true);
    download.step('Extracting Java $major');
    await extractFileToDisk(archive.path, dest.path);
    final executable = await dest
        .list(recursive: true)
        .where((e) => e is File && p.basename(e.path) == 'java.exe')
        .first;
    await marker.writeAsString(executable.path);
    await archive.delete();
    return JavaRuntime(executable.path, {});
  }
}
