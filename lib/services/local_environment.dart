import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Reads local credentials without compiling them into the application.
class LocalEnvironment {
  static String parseCurseForgeKey(String source) {
    for (var line in source.split('\n')) {
      line = line.trim();
      if (line.startsWith('export ')) line = line.substring(7).trim();
      final separator = line.indexOf('=');
      if (separator < 0 ||
          line.substring(0, separator).trim() != 'CURSEFORGE_API_KEY') {
        continue;
      }
      var value = line.substring(separator + 1).trim();
      if (value.startsWith('"') || value.startsWith("'")) {
        final end = value.indexOf(value[0], 1);
        if (end < 0) return '';
        return value.substring(1, end).trim();
      }
      final comment = value.indexOf(RegExp(r'\s+#'));
      if (comment >= 0) value = value.substring(0, comment);
      // API keys can contain dollar signs; do not interpolate variables.
      return value.trim();
    }
    return '';
  }

  static Future<String> curseForgeKey({
    required Directory supportDirectory,
    Map<String, String>? environment,
    List<Directory>? searchDirectories,
  }) async {
    final fromProcess =
        (environment ?? Platform.environment)['CURSEFORGE_API_KEY']?.trim();
    if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
    final folders =
        searchDirectories ??
        [
          supportDirectory,
          if (!Platform.isAndroid && !Platform.isIOS)
            File(Platform.resolvedExecutable).parent,
          if (kDebugMode) Directory.current,
        ];
    for (final folder in folders) {
      try {
        final file = File(p.join(folder.path, '.env'));
        if (!await file.exists()) continue;
        final key = parseCurseForgeKey(await file.readAsString());
        if (key.isNotEmpty) return key;
      } on FileSystemException {
        // An optional, unreadable local file must not prevent app startup.
      }
    }
    return '';
  }
}
