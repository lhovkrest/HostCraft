import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../core/world_config.dart';

class WorldInfo {
  const WorldInfo(this.name, this.bytes, this.modified);
  final String name;
  final int bytes;
  final DateTime modified;
}

/// Lists, backs up, imports and resets worlds inside a server folder.
///
/// A world is the folder named by `level-name` (it contains `level.dat`). Older
/// servers keep the Nether and End in `<name>_nether` and `<name>_the_end`;
/// those are handled together with the main folder. Every method expects the
/// server to be stopped.
class WorldService {
  WorldService(this.root);
  final Directory root;

  Directory get backupsDir => Directory(p.join(root.path, 'backups'));

  static List<String> _folders(String level) => [
    level,
    '${level}_nether',
    '${level}_the_end',
  ];

  Future<int> _size(Directory dir) async {
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(followLinks: false)) {
      final target = p.join(to.path, p.basename(e.path));
      if (e is Directory) {
        await _copy(e, Directory(target));
      } else if (e is File) {
        await e.copy(target);
      }
    }
  }

  static String _stamp() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Worlds found in [server], newest first.
  Future<List<WorldInfo>> list(Directory server) async {
    final result = <WorldInfo>[];
    if (!await server.exists()) return result;
    await for (final e in server.list(followLinks: false)) {
      if (e is! Directory) continue;
      final name = p.basename(e.path);
      if (name.endsWith('_nether') ||
          name.endsWith('_the_end') ||
          name.contains('.old-')) {
        continue;
      }
      final level = File(p.join(e.path, 'level.dat'));
      if (!await level.exists()) continue;
      result.add(
        WorldInfo(
          p.basename(e.path),
          await _size(e),
          (await level.stat()).modified,
        ),
      );
    }
    result.sort((a, b) => b.modified.compareTo(a.modified));
    return result;
  }

  Future<bool> exists(Directory server, String level) =>
      Directory(p.join(server.path, WorldConfig.sanitizeName(level))).exists();

  /// Zips the world to `backups/<name>-<time>.zip`. Throws when there is no
  /// world with that name yet.
  Future<File> backup(Directory server, String level) async {
    level = WorldConfig.sanitizeName(level);
    final dirs = <Directory>[];
    for (final name in _folders(level)) {
      final dir = Directory(p.join(server.path, name));
      if (await dir.exists()) dirs.add(dir);
    }
    if (dirs.isEmpty) {
      throw StateError('There is no world called "$level" to back up yet.');
    }
    await backupsDir.create(recursive: true);
    final out = File(p.join(backupsDir.path, '$level-${_stamp()}.zip'));
    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    try {
      for (final dir in dirs) {
        await encoder.addDirectory(dir, includeDirName: true);
      }
    } finally {
      await encoder.close();
    }
    return out;
  }

  /// Backups, newest first.
  Future<List<File>> backups() async {
    if (!await backupsDir.exists()) return [];
    final files = <File>[];
    await for (final e in backupsDir.list(followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.zip')) files.add(e);
    }
    final modified = <String, DateTime>{};
    for (final file in files) {
      modified[file.path] = (await file.stat()).modified;
    }
    files.sort((a, b) => modified[b.path]!.compareTo(modified[a.path]!));
    return files;
  }

  /// Imports a zipped world (a HostCraft backup, or a world zipped from any
  /// Minecraft Java server or the single-player `saves` folder) as [level].
  /// An existing world with that name is renamed to `<name>.old-<time>`, never
  /// deleted.
  Future<void> importZip(File zip, Directory server, String level) async {
    level = WorldConfig.sanitizeName(level);
    Directory? staged;
    final temp = Directory(p.join(root.path, 'import-${_stamp()}'));
    try {
      await temp.create(recursive: true);
      await extractFileToDisk(zip.path, temp.path);
      final source = await _findWorld(temp);
      if (source == null) {
        throw StateError(
          'That zip does not contain a Minecraft world (no level.dat found).',
        );
      }
      final stamp = _stamp();
      // The world itself, plus Nether/End folders stored next to it.
      final plan = <Directory, String>{source: level};
      if (!p.equals(source.path, temp.path)) {
        final base = p.basename(source.path);
        for (final suffix in ['_nether', '_the_end']) {
          final sibling = Directory(p.join(source.parent.path, '$base$suffix'));
          if (await sibling.exists()) plan[sibling] = '$level$suffix';
        }
      }
      // Stage every folder before touching any existing world or dimension.
      staged = Directory(p.join(root.path, 'staging-$stamp'));
      for (final entry in plan.entries) {
        await _copy(entry.key, Directory(p.join(staged.path, entry.value)));
      }
      final moved = <String, String>{};
      final installed = <Directory>[];
      await server.create(recursive: true);
      try {
        for (final folder in _folders(level)) {
          final target = Directory(p.join(server.path, folder));
          if (await target.exists()) {
            final oldPath = '${target.path}.old-$stamp';
            await target.rename(oldPath);
            moved[target.path] = oldPath;
          }
        }
        for (final folder in plan.values) {
          final target = Directory(p.join(server.path, folder));
          await Directory(p.join(staged.path, folder)).rename(target.path);
          installed.add(target);
        }
      } catch (_) {
        for (final target in installed) {
          if (await target.exists()) await target.delete(recursive: true);
        }
        for (final entry in moved.entries) {
          await Directory(entry.value).rename(entry.key);
        }
        rethrow;
      }
    } finally {
      if (staged != null && await staged.exists()) {
        await staged.delete(recursive: true);
      }
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  /// The folder holding `level.dat`: the zip root, or a folder one or two
  /// levels down.
  Future<Directory?> _findWorld(Directory dir, [int depth = 0]) async {
    if (await File(p.join(dir.path, 'level.dat')).exists()) return dir;
    if (depth >= 2) return null;
    final children = <Directory>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is Directory &&
          !p.basename(e.path).endsWith('_nether') &&
          !p.basename(e.path).endsWith('_the_end')) {
        children.add(e);
      }
    }
    children.sort((a, b) => a.path.compareTo(b.path));
    for (final child in children) {
      final found = await _findWorld(child, depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  /// Deletes the world and its Nether/End folders. Callers should back up first.
  Future<void> delete(Directory server, String level) async {
    level = WorldConfig.sanitizeName(level);
    for (final name in _folders(level)) {
      final dir = Directory(p.join(server.path, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}
