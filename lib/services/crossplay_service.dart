import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'download_service.dart';

/// Lets Bedrock players (phones, consoles, Windows 10/11 edition) join the Java
/// server using GeyserMC.
///
/// * Geyser translates the Bedrock protocol to Java and listens on UDP 19132.
/// * Floodgate lets Bedrock players join without owning a Java account.
/// * On Fabric, Geyser and Floodgate are mods that also need Fabric API.
///
/// Downloads come from GeyserMC's official downloads API
/// (`download.geysermc.org/v2`), which publishes a SHA-256 for every file.
class CrossplayService {
  CrossplayService(this._http, this.log);
  final DownloadService _http;
  final void Function(String) log;

  static const _api = 'https://download.geysermc.org/v2/projects';

  static bool supports(ServerEngine engine) => engine.crossplayCapable;

  static String platform(ServerEngine engine) =>
      engine == ServerEngine.fabric ? 'fabric' : 'spigot';

  /// Folder Geyser and Floodgate are installed into.
  static Directory addonDir(Directory server, ServerEngine engine) => Directory(
    p.join(server.path, engine == ServerEngine.fabric ? 'mods' : 'plugins'),
  );

  static File geyserConfig(Directory server, ServerEngine engine) => File(
    engine == ServerEngine.fabric
        ? p.join(server.path, 'config', 'Geyser-Fabric', 'config.yml')
        : p.join(server.path, 'plugins', 'Geyser-Spigot', 'config.yml'),
  );

  // ---- install ------------------------------------------------------------

  /// Installs or updates Geyser, Floodgate (and Fabric API on Fabric).
  Future<void> install(
    Directory server,
    ServerEngine engine,
    String mcVersion,
  ) async {
    final dir = addonDir(server, engine);
    await dir.create(recursive: true);
    await setEnabled(server, engine, true);
    final target = platform(engine);
    await _installProject('geyser', target, dir);
    try {
      await _installProject('floodgate', target, dir);
    } catch (e) {
      log(
        'Floodgate could not be installed ($e). Bedrock players will need a Java account to join.',
      );
    }
    if (engine == ServerEngine.fabric) {
      await _installFabricApi(dir, mcVersion);
    } else {
      // Geyser always targets the newest Java protocol. ViaVersion lets a
      // server that is one Minecraft version behind still accept it.
      try {
        await _installViaVersion(dir);
      } catch (e) {
        log(
          'ViaVersion could not be installed ($e). If Bedrock players are told the server is outdated, add ViaVersion to the plugins folder manually.',
        );
      }
    }
  }

  Future<void> _installProject(
    String project,
    String platform,
    Directory dir,
  ) async {
    final base = '$_api/$project/versions/latest/builds/latest';
    final meta = await _http.json(base);
    final download = meta['downloads']?[platform];
    if (download == null) {
      throw StateError('${_title(project)} has no $platform build');
    }
    final name = download['name'] as String;
    final sha = (download['sha256'] as String).toLowerCase();
    final target = File(p.join(dir.path, name));
    if (await target.exists() && await _sha256(target) == sha) {
      log('$name is up to date.');
      return;
    }
    await _removeOld(dir, project, keep: target.path);
    await _http.file(
      '$base/downloads/$platform',
      target,
      checksum: sha,
      label: 'Downloading $name',
    );
    log(
      'Installed $name (version ${meta['version']}, build ${meta['build']}).',
    );
  }

  Future<void> _installFabricApi(Directory dir, String mcVersion) async {
    final games = Uri.encodeComponent('["$mcVersion"]');
    final loaders = Uri.encodeComponent('["fabric"]');
    final list = await _http.json(
      'https://api.modrinth.com/v2/project/fabric-api/version?game_versions=$games&loaders=$loaders',
    ) as List;
    if (list.isEmpty) {
      throw StateError(
        'Fabric API has no build for Minecraft $mcVersion yet, and Geyser on Fabric needs it. Try another version or use Paper.',
      );
    }
    final version = list.firstWhere(
      (v) => v['version_type'] == 'release',
      orElse: () => list.first,
    );
    final files = version['files'] as List;
    final file = files.firstWhere(
      (f) => f['primary'] == true,
      orElse: () => files.first,
    );
    final name = file['filename'] as String;
    final sha1Hash = (file['hashes']['sha1'] as String).toLowerCase();
    final target = File(p.join(dir.path, name));
    if (await target.exists()) return;
    await _removeOld(dir, 'fabric-api', keep: target.path);
    await _http.file(
      file['url'] as String,
      target,
      checksum: sha1Hash,
      algorithm: 'sha1',
      label: 'Downloading $name',
    );
    log('Installed $name.');
  }

  /// Lets a server that is one Minecraft version behind accept Geyser, which
  /// always targets the newest Java protocol.
  Future<void> _installViaVersion(Directory dir) async {
    final loaders = Uri.encodeComponent('["paper"]');
    final list = await _http.json(
      'https://api.modrinth.com/v2/project/viaversion/version?loaders=$loaders',
    ) as List;
    if (list.isEmpty) {
      throw StateError('ViaVersion has no Paper build available');
    }
    final version = list.firstWhere(
      (v) => v['version_type'] == 'release',
      orElse: () => list.first,
    );
    final files = version['files'] as List;
    final file = files.firstWhere(
      (f) => f['primary'] == true,
      orElse: () => files.first,
    );
    final name = file['filename'] as String;
    final sha1Hash = (file['hashes']['sha1'] as String).toLowerCase();
    final target = File(p.join(dir.path, name));
    if (await target.exists()) return;
    await _removeOld(dir, 'viaversion', keep: target.path);
    await _http.file(
      file['url'] as String,
      target,
      checksum: sha1Hash,
      algorithm: 'sha1',
      label: 'Downloading $name',
    );
    log('Installed $name.');
  }

  Future<void> _removeOld(
    Directory dir,
    String project, {
    required String keep,
  }) async {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || entity.path == keep) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (name.contains(project) &&
          (name.endsWith('.jar') || name.endsWith('.jar.disabled'))) {
        await entity.delete();
      }
    }
  }

  static String _title(String s) => s[0].toUpperCase() + s.substring(1);

  Future<String> _sha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  // ---- enable / disable ---------------------------------------------------

  /// Turns Geyser and Floodgate on or off without deleting them, by renaming
  /// their jars. Fabric API is left alone.
  Future<void> setEnabled(
    Directory server,
    ServerEngine engine,
    bool enabled,
  ) async {
    final dir = addonDir(server, engine);
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final lower = name.toLowerCase();
      if (!lower.contains('geyser') && !lower.contains('floodgate')) continue;
      if (enabled && lower.endsWith('.jar.disabled')) {
        await entity.rename(
          p.join(dir.path, name.substring(0, name.length - '.disabled'.length)),
        );
      } else if (!enabled && lower.endsWith('.jar')) {
        await entity.rename('${entity.path}.disabled');
      }
    }
  }

  Future<bool> _hasFloodgate(Directory server, ServerEngine engine) async {
    final dir = addonDir(server, engine);
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path).toLowerCase();
      if (entity is File &&
          name.contains('floodgate') &&
          name.endsWith('.jar')) {
        return true;
      }
    }
    return false;
  }

  // ---- configuration ------------------------------------------------------

  /// Patches Geyser's own `config.yml` so Bedrock players can join: the UDP
  /// [bedrockPort], and `auth-type: floodgate` when Floodgate is installed.
  ///
  /// Geyser writes its default config the first time it runs, so on a brand
  /// new server there is nothing to patch yet. Returns true when the file was
  /// changed, which means the server needs one restart for it to take effect.
  Future<bool> applyConfig(
    Directory server,
    ServerEngine engine,
    int bedrockPort,
  ) async {
    final file = geyserConfig(server, engine);
    if (!await file.exists()) return false;
    final floodgate = await _hasFloodgate(server, engine);
    final original = await file.readAsString();
    final newline = original.contains('\r\n') ? '\r\n' : '\n';
    final lines = original.split(RegExp(r'\r?\n'));
    final section = RegExp(r'^([A-Za-z0-9_-]+):\s*(#.*)?$');
    final entry = RegExp(
      r'^(\s*)([A-Za-z0-9_-]+):(\s*)([^#\s][^#]*?)?(\s*#.*)?$',
    );
    var current = '';
    var changed = false;
    for (var i = 0; i < lines.length; i++) {
      final header = section.firstMatch(lines[i]);
      if (header != null) {
        current = header[1]!;
        continue;
      }
      final m = entry.firstMatch(lines[i]);
      if (m == null) continue;
      final indent = m[1]!;
      final key = m[2]!;
      String? want;
      if (key == 'auth-type' && floodgate) want = 'floodgate';
      if (key == 'port' && current == 'bedrock' && indent.isNotEmpty) {
        want = '$bedrockPort';
      }
      if (want == null || m[4]?.trim() == want) continue;
      final gap = m[3]!.isEmpty ? ' ' : m[3]!;
      lines[i] = '$indent$key:$gap$want${m[5] ?? ''}';
      changed = true;
    }
    if (changed) await file.writeAsString(lines.join(newline), flush: true);
    return changed;
  }
}