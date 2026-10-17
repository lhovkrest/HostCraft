import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class ServerFileEntry {
  const ServerFileEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    required this.bytes,
    required this.modified,
  });
  final String name;

  /// Path relative to the server folder.
  final String relativePath;
  final bool isDirectory;
  final int bytes;
  final DateTime modified;
}

/// A small file manager that can only see inside one server folder. Every
/// path is given relative to that folder, and anything that would leave it
/// (`..`, absolute paths, links) is refused.
class ServerFiles {
  ServerFiles(Directory root)
    : root = Directory(p.normalize(p.absolute(root.path)));
  final Directory root;

  /// Largest file the built-in editor opens.
  static const maxEditBytes = 512 * 1024;

  static const _textExtensions = {
    '.properties', '.yml', '.yaml', '.json', '.json5', '.txt', '.toml',
    '.cfg', '.conf', '.ini', '.log', '.md', '.xml', '.mcmeta', '.csv',
    '.lang', '.secret',
  };

  /// True for files the editor should offer to open.
  static bool isEditable(String name) {
    final ext = p.extension(name).toLowerCase();
    return _textExtensions.contains(ext) || ext.isEmpty;
  }

  Future<String> _safe(String relative) async {
    final full = p.normalize(p.join(root.path, relative));
    if (full != root.path && !p.isWithin(root.path, full)) {
      throw ArgumentError('That path is outside the server folder.');
    }
    final type = await FileSystemEntity.type(full, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw ArgumentError('Links are not followed.');
    }
    return full;
  }

  static String _cleanName(String name) {
    final clean = name.trim();
    if (clean.isEmpty ||
        clean == '.' ||
        clean == '..' ||
        clean.contains('/') ||
        clean.contains('\\') ||
        RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(clean)) {
      throw ArgumentError('That is not a valid file name.');
    }
    return clean;
  }

  /// The contents of [relative], folders first, then files, both A to Z.
  Future<List<ServerFileEntry>> list([String relative = '']) async {
    final dir = Directory(await _safe(relative));
    if (!await dir.exists()) return [];
    final entries = <ServerFileEntry>[];
    await for (final e in dir.list(followLinks: false)) {
      final stat = await e.stat();
      entries.add(
        ServerFileEntry(
          name: p.basename(e.path),
          relativePath: p.relative(e.path, from: root.path),
          isDirectory: e is Directory,
          bytes: e is File ? stat.size : 0,
          modified: stat.modified,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<String> readText(String relative) async {
    final file = File(await _safe(relative));
    final size = await file.length();
    if (size > maxEditBytes) {
      throw StateError(
        'This file is too large to edit here (${size ~/ 1024} KB).',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) {
      throw StateError('This looks like a binary file, so it cannot be edited as text.');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeText(String relative, String content) async {
    final file = File(await _safe(relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  Future<void> createFolder(String parent, String name) async {
    final dir = Directory(await _safe(p.join(parent, _cleanName(name))));
    if (await dir.exists()) throw StateError('"$name" already exists.');
    await dir.create(recursive: true);
  }

  Future<void> createFile(String parent, String name) async {
    final file = File(await _safe(p.join(parent, _cleanName(name))));
    if (await file.exists()) throw StateError('"$name" already exists.');
    await file.create(recursive: true);
  }

  Future<void> rename(String relative, String newName) async {
    final from = await _safe(relative);
    if (from == root.path) throw ArgumentError('The server folder cannot be renamed.');
    final to = await _safe(p.join(p.dirname(relative), _cleanName(newName)));
    if (await FileSystemEntity.type(to, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('"$newName" already exists.');
    }
    final type = await FileSystemEntity.type(from, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  Future<void> delete(String relative) async {
    final full = await _safe(relative);
    if (full == root.path) {
      throw ArgumentError('The server folder itself cannot be deleted here.');
    }
    final type = await FileSystemEntity.type(full, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(full).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(full).delete();
    }
  }

  /// Copies a file from anywhere on the device into [folder] of the server,
  /// for example a mod jar picked with a file picker.
  Future<void> importFile(File source, [String folder = '']) async {
    final name = _cleanName(p.basename(source.path));
    final target = File(await _safe(p.join(folder, name)));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }
}
