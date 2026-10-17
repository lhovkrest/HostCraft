import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import '../core/models.dart';
import 'download_service.dart';

/// Where an add-on comes from.
enum ModSource { modrinth, curseforge }

extension ModSourceInfo on ModSource {
  String get label => switch (this) {
    ModSource.modrinth => 'Modrinth',
    ModSource.curseforge => 'CurseForge',
  };
}

/// What a server software loads: Fabric loads mods, Paper-based software loads
/// plugins, Vanilla loads neither.
enum AddonKind { mod, plugin }

extension AddonEngine on ServerEngine {
  AddonKind? get addonKind => switch (this) {
    ServerEngine.fabric || ServerEngine.forge => AddonKind.mod,
    ServerEngine.paper ||
    ServerEngine.folia ||
    ServerEngine.purpur => AddonKind.plugin,
    ServerEngine.vanilla => null,
  };

  /// Folder inside the server directory the add-ons live in.
  String get addonFolder => addonKind == AddonKind.mod ? 'mods' : 'plugins';
}

/// A mod or plugin found in a catalog.
class AddonProject {
  const AddonProject({
    required this.source,
    required this.id,
    required this.slug,
    required this.title,
    this.description = '',
    this.author = '',
    this.downloads = 0,
    this.iconUrl,
    this.pageUrl,
  });
  final ModSource source;
  final String id;
  final String slug;
  final String title;
  final String description;
  final String author;
  final int downloads;
  final String? iconUrl;
  final String? pageUrl;
}

/// A downloadable version of a project.
class AddonFile {
  const AddonFile({
    required this.source,
    required this.projectId,
    required this.versionId,
    required this.versionName,
    required this.fileName,
    required this.url,
    this.hash,
    this.hashAlgorithm = 'sha1',
    this.releaseType = 'release',
    this.dependencies = const [],
  });
  final ModSource source;
  final String projectId;
  final String versionId;
  final String versionName;
  final String fileName;

  /// Empty when the author does not allow downloads from other apps.
  final String url;
  final String? hash;
  final String hashAlgorithm;
  final String releaseType;

  /// Project ids this file needs (required dependencies only).
  final List<String> dependencies;
}

/// A jar in the server's `mods` or `plugins` folder. Jars installed through
/// HostCraft are [tracked] and can be updated; jars added by hand are listed
/// too, just without a catalog link.
class InstalledAddon {
  InstalledAddon({
    this.source,
    this.projectId,
    required this.title,
    this.versionId,
    this.versionName = '',
    required this.fileName,
    this.enabled = true,
    DateTime? installedAt,
  }) : installedAt = installedAt ?? DateTime.now();
  final ModSource? source;
  final String? projectId;
  final String title;
  final String? versionId;
  final String versionName;

  /// File name without the `.disabled` suffix.
  final String fileName;
  bool enabled;
  final DateTime installedAt;

  bool get tracked => source != null && projectId != null;
  String get key => '${source?.name}:$projectId';

  Map<String, dynamic> toJson() => {
    'source': source?.name,
    'projectId': projectId,
    'title': title,
    'versionId': versionId,
    'versionName': versionName,
    'fileName': fileName,
    'installedAt': installedAt.toIso8601String(),
  };

  factory InstalledAddon.fromJson(Map<String, dynamic> json) => InstalledAddon(
    source: ModSource.values.asNameMap()[json['source']],
    projectId: json['projectId'] as String?,
    title: json['title'] as String? ?? '${json['fileName']}',
    versionId: json['versionId'] as String?,
    versionName: json['versionName'] as String? ?? '',
    fileName: json['fileName'] as String,
    installedAt: DateTime.tryParse('${json['installedAt']}'),
  );
}

abstract class AddonProvider {
  Future<List<AddonProject>> search(
    String query, {
    required ServerEngine engine,
    required String mcVersion,
    int offset = 0,
  });

  /// Newest file of [projectId] that works with [engine] and [mcVersion], or
  /// null when there is none.
  Future<AddonFile?> latestFile(
    String projectId, {
    required ServerEngine engine,
    required String mcVersion,
  });

  Future<AddonProject?> project(String projectId);
}

// ---- Modrinth ---------------------------------------------------------------

/// Modrinth's public API needs no key. Plugins are listed there as projects
/// tagged with a server loader (paper, spigot, bukkit, purpur, folia).
class ModrinthProvider implements AddonProvider {
  ModrinthProvider(this._http);
  final DownloadService _http;

  static List<String> loadersFor(ServerEngine engine) => switch (engine) {
    ServerEngine.fabric => ['fabric'],
    ServerEngine.forge => ['forge'],
    ServerEngine.paper => ['paper', 'spigot', 'bukkit'],
    ServerEngine.purpur => ['purpur', 'paper', 'spigot', 'bukkit'],
    ServerEngine.folia => ['folia'],
    ServerEngine.vanilla => <String>[],
  };

  static List<String> _need(ServerEngine engine) {
    final loaders = loadersFor(engine);
    if (loaders.isEmpty) {
      throw StateError('Vanilla servers cannot load mods or plugins.');
    }
    return loaders;
  }

  @override
  Future<List<AddonProject>> search(
    String query, {
    required ServerEngine engine,
    required String mcVersion,
    int offset = 0,
  }) async {
    final loaders = _need(engine);
    final facets = jsonEncode([
      ['project_type:mod'],
      [for (final l in loaders) 'categories:$l'],
      ['versions:$mcVersion'],
    ]);
    final url = Uri.https('api.modrinth.com', '/v2/search', {
      'query': query,
      'facets': facets,
      'limit': '20',
      'offset': '$offset',
      'index': query.isEmpty ? 'downloads' : 'relevance',
    }).toString();
    final data = await _http.json(url);
    return [
      for (final h in (data['hits'] as List? ?? const []))
        AddonProject(
          source: ModSource.modrinth,
          id: '${h['project_id']}',
          slug: '${h['slug'] ?? ''}',
          title: '${h['title'] ?? h['slug']}',
          description: '${h['description'] ?? ''}',
          author: '${h['author'] ?? ''}',
          downloads: (h['downloads'] as num?)?.toInt() ?? 0,
          iconUrl: h['icon_url'] as String?,
          pageUrl: 'https://modrinth.com/project/${h['slug']}',
        ),
    ];
  }

  @override
  Future<AddonFile?> latestFile(
    String projectId, {
    required ServerEngine engine,
    required String mcVersion,
  }) async {
    final loaders = _need(engine);
    final url = Uri.https(
      'api.modrinth.com',
      '/v2/project/$projectId/version',
      {
        'loaders': jsonEncode(loaders),
        'game_versions': jsonEncode([mcVersion]),
      },
    ).toString();
    final list = (await _http.json(url) as List).cast<Map>();
    if (list.isEmpty) return null;
    // Newest first. Prefer a release over a beta or alpha.
    final v = list.firstWhere(
      (x) => x['version_type'] == 'release',
      orElse: () => list.first,
    );
    final files = (v['files'] as List).cast<Map>();
    if (files.isEmpty) return null;
    final f = files.firstWhere(
      (x) => x['primary'] == true,
      orElse: () => files.first,
    );
    return AddonFile(
      source: ModSource.modrinth,
      projectId: projectId,
      versionId: '${v['id']}',
      versionName: '${v['version_number'] ?? v['name'] ?? ''}',
      fileName: '${f['filename']}',
      url: '${f['url']}',
      hash: (f['hashes']?['sha1'] as String?)?.toLowerCase(),
      hashAlgorithm: 'sha1',
      releaseType: '${v['version_type']}',
      dependencies: [
        for (final d in (v['dependencies'] as List? ?? const []))
          if (d['dependency_type'] == 'required' && d['project_id'] != null)
            '${d['project_id']}',
      ],
    );
  }

  @override
  Future<AddonProject?> project(String projectId) async {
    final d = await _http.json(
      'https://api.modrinth.com/v2/project/$projectId',
    );
    if (d is! Map) return null;
    return AddonProject(
      source: ModSource.modrinth,
      id: '${d['id']}',
      slug: '${d['slug'] ?? ''}',
      title: '${d['title'] ?? d['slug']}',
      description: '${d['description'] ?? ''}',
      downloads: (d['downloads'] as num?)?.toInt() ?? 0,
      iconUrl: d['icon_url'] as String?,
      pageUrl: 'https://modrinth.com/project/${d['slug']}',
    );
  }
}

// ---- CurseForge -------------------------------------------------------------

/// CurseForge only serves its API to holders of a key. HostCraft never ships a
/// key: each user supplies their own through settings or local environment.
class CurseForgeProvider implements AddonProvider {
  CurseForgeProvider(this.apiKey);
  final String apiKey;

  static const _gameId = 432; // Minecraft
  static const _classMods = 6;
  static const _classBukkitPlugins = 5;
  static const _loaderFabric = 4;
  static const _loaderForge = 1;

  Future<Map> _get(String path, [Map<String, String>? query]) async {
    final response = await http
        .get(
          Uri.https('api.curseforge.com', '/v1$path', query),
          headers: {
            'Accept': 'application/json',
            'x-api-key': apiKey,
            'User-Agent': 'HostCraft/$appVersion',
          },
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'CurseForge denied access (HTTP ${response.statusCode}). Use a catalog API key with x-api-key access, not an author upload token. Change it using the key button in Mods & plugins, or edit .env and restart.',
      );
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode} from api.curseforge.com',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  }

  @override
  Future<List<AddonProject>> search(
    String query, {
    required ServerEngine engine,
    required String mcVersion,
    int offset = 0,
  }) async {
    final kind = engine.addonKind;
    if (kind == null) {
      throw StateError('Vanilla servers cannot load mods or plugins.');
    }
    final data = await _get('/mods/search', {
      'gameId': '$_gameId',
      'classId': '${kind == AddonKind.mod ? _classMods : _classBukkitPlugins}',
      'searchFilter': query,
      'gameVersion': mcVersion,
      if (kind == AddonKind.mod)
        'modLoaderType':
            '${engine == ServerEngine.forge ? _loaderForge : _loaderFabric}',
      'sortField': '2', // popularity
      'sortOrder': 'desc',
      'pageSize': '20',
      'index': '$offset',
    });
    return [
      for (final m in (data['data'] as List? ?? const [])) _project(m as Map),
    ];
  }

  AddonProject _project(Map m) {
    final authors = (m['authors'] as List? ?? const []);
    return AddonProject(
      source: ModSource.curseforge,
      id: '${m['id']}',
      slug: '${m['slug'] ?? ''}',
      title: '${m['name'] ?? m['slug']}',
      description: '${m['summary'] ?? ''}',
      author: authors.isEmpty ? '' : '${(authors.first as Map)['name']}',
      downloads: (m['downloadCount'] as num?)?.toInt() ?? 0,
      iconUrl: (m['logo'] as Map?)?['thumbnailUrl'] as String?,
      pageUrl: (m['links'] as Map?)?['websiteUrl'] as String?,
    );
  }

  @override
  Future<AddonFile?> latestFile(
    String projectId, {
    required ServerEngine engine,
    required String mcVersion,
  }) async {
    final kind = engine.addonKind;
    if (kind == null) {
      throw StateError('Vanilla servers cannot load mods or plugins.');
    }
    final data = await _get('/mods/$projectId/files', {
      'gameVersion': mcVersion,
      if (kind == AddonKind.mod)
        'modLoaderType':
            '${engine == ServerEngine.forge ? _loaderForge : _loaderFabric}',
      'pageSize': '30',
    });
    final files = (data['data'] as List? ?? const []).cast<Map>().toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => '${b['fileDate']}'.compareTo('${a['fileDate']}'));
    // releaseType: 1 release, 2 beta, 3 alpha.
    final f = files.firstWhere(
      (x) => x['releaseType'] == 1,
      orElse: () => files.first,
    );
    String? hash;
    var algorithm = 'sha1';
    final hashes = (f['hashes'] as List? ?? const []).cast<Map>();
    for (final h in hashes) {
      if (h['algo'] == 1) {
        hash = '${h['value']}'.toLowerCase();
        break;
      }
    }
    if (hash == null) {
      for (final h in hashes) {
        if (h['algo'] == 2) {
          hash = '${h['value']}'.toLowerCase();
          algorithm = 'md5';
          break;
        }
      }
    }
    return AddonFile(
      source: ModSource.curseforge,
      projectId: projectId,
      versionId: '${f['id']}',
      versionName: '${f['displayName'] ?? f['fileName']}',
      fileName: '${f['fileName']}',
      url: (f['downloadUrl'] as String?) ?? '',
      hash: hash,
      hashAlgorithm: algorithm,
      releaseType: switch (f['releaseType']) {
        1 => 'release',
        2 => 'beta',
        _ => 'alpha',
      },
      dependencies: [
        for (final d in (f['dependencies'] as List? ?? const []))
          if (d['relationType'] == 3) '${d['modId']}', // required dependency
      ],
    );
  }

  @override
  Future<AddonProject?> project(String projectId) async {
    final data = await _get('/mods/$projectId');
    final m = data['data'];
    return m is Map ? _project(m) : null;
  }
}

// ---- manager ----------------------------------------------------------------

/// Installs, updates, disables and removes the mods or plugins of one server.
/// The server must be stopped while any of this runs.
class AddonManager {
  AddonManager({
    required this.serverDir,
    required this.engine,
    required this.mcVersion,
    required this.download,
    required this.log,
    this.curseForgeKey = '',
  });
  final Directory serverDir;
  final ServerEngine engine;
  final String mcVersion;
  final DownloadService download;
  final void Function(String) log;
  final String curseForgeKey;

  AddonKind? get kind => engine.addonKind;
  Directory get dir => Directory(p.join(serverDir.path, engine.addonFolder));
  File get _manifest => File(p.join(serverDir.path, 'hostcraft-addons.json'));

  AddonProvider provider(ModSource source) => switch (source) {
    ModSource.modrinth => ModrinthProvider(download),
    ModSource.curseforge =>
      curseForgeKey.isEmpty
          ? throw StateError(
              'Add your CurseForge API key in the Mods screen first.',
            )
          : CurseForgeProvider(curseForgeKey),
  };

  // ---- manifest -----------------------------------------------------------

  Future<List<InstalledAddon>> _load() async {
    try {
      if (!await _manifest.exists()) return [];
      final data = jsonDecode(await _manifest.readAsString());
      if (data is! List) return [];
      return [
        for (final e in data)
          if (e is Map) InstalledAddon.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<InstalledAddon> list) async {
    await serverDir.create(recursive: true);
    await _manifest.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert([for (final e in list) e.toJson()]),
      flush: true,
    );
  }

  // ---- listing ------------------------------------------------------------

  /// Everything in the add-on folder: tracked jars first matched to the
  /// manifest, then any other jar as a manual entry.
  Future<List<InstalledAddon>> installed() async {
    final tracked = await _load();
    final result = <InstalledAddon>[];
    if (!await dir.exists()) return result;
    final files = <String, bool>{}; // file name -> enabled
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      final lower = name.toLowerCase();
      if (lower.endsWith('.jar')) {
        files[name] = true;
      } else if (lower.endsWith('.jar.disabled')) {
        files[name.substring(0, name.length - '.disabled'.length)] = false;
      }
    }
    for (final entry in tracked) {
      final on = files.remove(entry.fileName);
      if (on == null) continue; // the jar was deleted by hand
      entry.enabled = on;
      result.add(entry);
    }
    for (final entry in files.entries) {
      result.add(
        InstalledAddon(
          title: entry.key,
          fileName: entry.key,
          enabled: entry.value,
        ),
      );
    }
    result.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return result;
  }

  bool _looksInstalled(List<String> names, String slug) {
    final s = slug.toLowerCase();
    return s.isNotEmpty && names.any((n) => n.toLowerCase().contains(s));
  }

  // ---- install / update ---------------------------------------------------

  /// Installs the newest compatible version of [project] and the projects it
  /// requires. Returns what was newly installed or updated.
  Future<List<InstalledAddon>> install(AddonProject project) async {
    if (kind == null) {
      throw StateError('Vanilla servers cannot load mods or plugins.');
    }
    final done = <InstalledAddon>[];
    await _installProject(
      project.source,
      project.id,
      project.title,
      done,
      {},
      0,
    );
    return done;
  }

  Future<InstalledAddon?> update(InstalledAddon addon) async {
    if (!addon.tracked) {
      throw StateError(
        '"${addon.title}" was added by hand, so it has no catalog to update from.',
      );
    }
    final done = <InstalledAddon>[];
    await _installProject(
      addon.source!,
      addon.projectId!,
      addon.title,
      done,
      {},
      0,
    );
    return done.isEmpty ? null : done.first;
  }

  Future<void> _installProject(
    ModSource source,
    String id,
    String title,
    List<InstalledAddon> done,
    Set<String> seen,
    int depth,
  ) async {
    if (!seen.add('${source.name}:$id') || depth > 4) return;
    final prov = provider(source);

    if (depth > 0) {
      // A library the user already added by hand must not be installed twice.
      try {
        final info = await prov.project(id);
        if (info != null) {
          title = info.title;
          final names = await dir.exists()
              ? [
                  await for (final e in dir.list(followLinks: false))
                    if (e is File) p.basename(e.path),
                ]
              : <String>[];
          if (_looksInstalled(names, info.slug)) {
            log('$title is already in the ${engine.addonFolder} folder.');
            return;
          }
        }
      } catch (_) {}
    }

    final file = await prov.latestFile(
      id,
      engine: engine,
      mcVersion: mcVersion,
    );
    if (file == null) {
      throw StateError(
        '$title has no version for ${engine.label} $mcVersion yet.',
      );
    }
    if (file.url.isEmpty) {
      throw StateError(
        'The author of $title does not allow downloads from other apps. Download the jar from its ${source.label} page and put it in the ${engine.addonFolder} folder using Files.',
      );
    }
    final entries = await _load();
    final existing = entries
        .where((e) => e.source == source && e.projectId == id)
        .toList();
    if (existing.isNotEmpty && existing.first.versionId == file.versionId) {
      log('$title is already up to date.');
    } else {
      if (file.releaseType != 'release') {
        log(
          '$title has no stable release for $mcVersion. Using a ${file.releaseType} build.',
        );
      }
      await dir.create(recursive: true);
      final name = _safeName(file.fileName);
      await download.file(
        file.url,
        File(p.join(dir.path, name)),
        checksum: file.hash,
        algorithm: file.hashAlgorithm,
        label: 'Downloading $name',
      );
      for (final old in existing) {
        if (old.fileName != name) await _deleteFile(old.fileName);
      }
      entries.removeWhere((e) => e.source == source && e.projectId == id);
      final entry = InstalledAddon(
        source: source,
        projectId: id,
        title: title,
        versionId: file.versionId,
        versionName: file.versionName,
        fileName: name,
      );
      entries.add(entry);
      await _save(entries);
      done.add(entry);
      log('Installed $title ${file.versionName}.');
    }
    for (final dep in file.dependencies) {
      await _installProject(
        source,
        dep,
        'a required dependency',
        done,
        seen,
        depth + 1,
      );
    }
  }

  /// Newest file for every tracked add-on that has a newer version, keyed by
  /// [InstalledAddon.key]. Add-ons that cannot be checked are skipped.
  Future<Map<String, AddonFile>> checkUpdates() async {
    final result = <String, AddonFile>{};
    for (final entry in await _load()) {
      if (!entry.tracked) continue;
      try {
        final file = await provider(entry.source!)
            .latestFile(entry.projectId!, engine: engine, mcVersion: mcVersion);
        if (file != null && file.versionId != entry.versionId) {
          result[entry.key] = file;
        }
      } catch (_) {}
    }
    return result;
  }

  // ---- remove / enable ----------------------------------------------------

  Future<void> remove(InstalledAddon addon) async {
    await _deleteFile(addon.fileName);
    final entries = await _load();
    entries.removeWhere((e) => e.fileName == addon.fileName);
    await _save(entries);
  }

  /// Turns an add-on off without deleting it, by renaming it to `.jar.disabled`
  /// (the server ignores files with that ending).
  Future<void> setEnabled(InstalledAddon addon, bool enabled) async {
    final on = File(p.join(dir.path, addon.fileName));
    final off = File('${on.path}.disabled');
    if (enabled && await off.exists()) {
      await off.rename(on.path);
    } else if (!enabled && await on.exists()) {
      await on.rename(off.path);
    }
    addon.enabled = enabled;
  }

  Future<void> _deleteFile(String fileName) async {
    for (final path in [
      p.join(dir.path, fileName),
      '${p.join(dir.path, fileName)}.disabled',
    ]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  /// Only a plain `.jar` file name is accepted, never a path.
  static String _safeName(String name) {
    final base = p.basename(name.replaceAll('\\', '/'));
    final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9 _.\-+()\[\]]'), '_');
    if (!clean.toLowerCase().endsWith('.jar')) {
      throw StateError('Unexpected file type: $base');
    }
    return clean;
  }
}
