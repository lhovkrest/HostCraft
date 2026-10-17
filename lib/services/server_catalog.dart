import '../core/models.dart';
import 'download_service.dart';

/// A concrete server file to download.
class ServerBuild {
  const ServerBuild({
    required this.url,
    required this.build,
    this.hash,
    this.algorithm = 'sha256',
    this.experimental = false,
  });
  final String url;

  /// Human readable build label (Paper build number, Fabric loader, ...).
  final String build;
  final String? hash;
  final String algorithm;

  /// True when only alpha/beta builds exist for this version.
  final bool experimental;
}

/// Finds which Minecraft versions each server software offers, newest first,
/// and where to download them. Every list comes from the software's own
/// download service, so new releases appear without an app update. Version
/// names are never parsed or sorted here: Minecraft moved from `1.21.x` to
/// `26.x` numbering in 2026, so the order the services return is the truth.
class ServerCatalog {
  ServerCatalog(this._http);
  final DownloadService _http;

  static const _mojang =
      'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
  static final _release = RegExp(r'^\d+(\.\d+)*$');

  // Mojang's manifest and per-version files are shared by every catalog and
  // kept for a few minutes. Opening the setup sheet, picking a version and
  // preparing the server used to fetch the same files over and over.
  static Map<String, dynamic>? _manifestCache;
  static DateTime? _manifestAt;
  static final _metaCache = <String, Map<String, dynamic>>{};
  static const _cacheLife = Duration(minutes: 15);
  final _javaCache = <String, int>{};

  Future<Map<String, dynamic>> _mojangManifest() async {
    final cached = _manifestCache;
    final at = _manifestAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheLife) {
      return cached;
    }
    final fresh = Map<String, dynamic>.from(await _http.json(_mojang));
    _manifestCache = fresh;
    _manifestAt = DateTime.now();
    return fresh;
  }

  Future<Map<String, dynamic>> _versionMeta(String url) async {
    final cached = _metaCache[url];
    if (cached != null) return cached;
    final fresh = Map<String, dynamic>.from(await _http.json(url));
    _metaCache[url] = fresh;
    return fresh;
  }

  Map<String, dynamic>? _mojangEntry(Map<String, dynamic> manifest, String id) {
    for (final v in manifest['versions'] as List) {
      if (v['id'] == id) return Map<String, dynamic>.from(v as Map);
    }
    return null;
  }

  // ---- version lists ------------------------------------------------------

  /// Minecraft versions [engine] can run, newest first. Snapshots and other
  /// non-release versions are only included when [snapshots] is true.
  Future<List<String>> versions(
    ServerEngine engine, {
    bool snapshots = false,
  }) async {
    switch (engine) {
      case ServerEngine.vanilla:
        final manifest = await _mojangManifest();
        return [
          for (final v in manifest['versions'] as List)
            if (snapshots || v['type'] == 'release') v['id'] as String,
        ];
      case ServerEngine.paper:
        return _fill('paper', snapshots);
      case ServerEngine.folia:
        return _fill('folia', snapshots);
      case ServerEngine.purpur:
        final data = await _http.json('https://api.purpurmc.org/v2/purpur');
        final all = (data['versions'] as List).cast<String>().reversed;
        return [
          for (final v in all)
            if (snapshots || _release.hasMatch(v)) v,
        ];
      case ServerEngine.fabric:
        final data = await _http.json(
          'https://meta.fabricmc.net/v2/versions/game',
        ) as List;
        return [
          for (final v in data)
            if (snapshots || v['stable'] == true) v['version'] as String,
        ];
      case ServerEngine.forge:
        final promos = await _forgePromotions();
        final manifest = await _mojangManifest();
        return [
          for (final v in manifest['versions'] as List)
            if (v['type'] == 'release' &&
                supportsForgeVersion(v['id'] as String) &&
                (promos.containsKey('${v['id']}-recommended') ||
                    promos.containsKey('${v['id']}-latest')))
              v['id'] as String,
        ];
    }
  }

  Future<List<String>> _fill(String project, bool snapshots) async {
    final data =
        await _http.json('https://fill.papermc.io/v3/projects/$project') as Map;
    final groups = data['versions'];
    final all = <String>[];
    if (groups is Map) {
      // Grouped by Minecraft series, newest group and newest version first.
      for (final group in groups.values) {
        if (group is List) all.addAll(group.cast<String>());
      }
    } else if (groups is List) {
      all.addAll(groups.cast<String>());
    }
    return snapshots ? all : all.where(_release.hasMatch).toList();
  }

  // ---- Java requirement ---------------------------------------------------

  /// The Java major version Mojang says [version] needs (17, 21, 25, ...).
  /// Unknown versions and network failures are surfaced to the caller.
  Future<int> javaMajor(String version) async {
    final cached = _javaCache[version];
    if (cached != null) return cached;
    final entry = _mojangEntry(await _mojangManifest(), version);
    if (entry == null) {
      throw StateError(
        'Cannot determine the Java requirement for $version. Refresh the version list.',
      );
    }
    final meta = await _versionMeta(entry['url'] as String);
    final major = (meta['javaVersion']?['majorVersion'] as num?)?.toInt() ?? 8;
    return _javaCache[version] = major;
  }

  // ---- downloads ----------------------------------------------------------

  Future<ServerBuild> resolve(ServerEngine engine, String version) async {
    switch (engine) {
      case ServerEngine.vanilla:
        return _vanilla(version);
      case ServerEngine.paper:
        return _fillBuild('paper', version);
      case ServerEngine.folia:
        return _fillBuild('folia', version);
      case ServerEngine.purpur:
        return _purpur(version);
      case ServerEngine.fabric:
        return _fabric(version);
      case ServerEngine.forge:
        return _forge(version);
    }
  }

  /// The modern Forge argument-file launcher supports Minecraft 1.18 onward.
  static bool supportsForgeVersion(String version) {
    final parts = version.split('.').map(int.tryParse).toList();
    if (parts.isEmpty || parts.any((v) => v == null)) return false;
    return parts.first! > 1 ||
        (parts.first == 1 && parts.length > 1 && parts[1]! >= 18);
  }

  Future<Map<String, dynamic>> _forgePromotions() async {
    final data = await _http.json(
      'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json',
    );
    return Map<String, dynamic>.from(data['promos'] as Map);
  }

  Future<ServerBuild> _forge(String version) async {
    if (!supportsForgeVersion(version)) {
      throw StateError(
        'HostCraft supports Forge for Minecraft 1.18 and newer.',
      );
    }
    final promos = await _forgePromotions();
    final build = promos['$version-recommended'] ?? promos['$version-latest'];
    if (build is! String || !RegExp(r'^\d+(\.\d+)+$').hasMatch(build)) {
      throw StateError('No official Forge build is available for $version.');
    }
    final artifact = '$version-$build';
    final url =
        'https://maven.minecraftforge.net/net/minecraftforge/forge/$artifact/forge-$artifact-installer.jar';
    final checksum = (await _http.text('$url.sha1')).trim();
    if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(checksum)) {
      throw const FormatException(
        'Forge returned an invalid installer checksum.',
      );
    }
    return ServerBuild(
      url: url,
      build: build,
      hash: checksum,
      algorithm: 'sha1',
    );
  }

  Future<ServerBuild> _vanilla(String version) async {
    final entry = _mojangEntry(await _mojangManifest(), version);
    if (entry == null) {
      throw StateError('Minecraft version $version was not found');
    }
    final meta = await _versionMeta(entry['url'] as String);
    final server = meta['downloads']?['server'];
    if (server == null) {
      throw StateError('Mojang has no server download for $version');
    }
    return ServerBuild(
      url: server['url'] as String,
      build: version,
      hash: server['sha1'] as String?,
      algorithm: 'sha1',
    );
  }

  Future<ServerBuild> _fillBuild(String project, String version) async {
    final name = project[0].toUpperCase() + project.substring(1);
    final builds = await _http.json(
      'https://fill.papermc.io/v3/projects/$project/versions/$version/builds',
    ) as List;
    if (builds.isEmpty) {
      throw StateError('$name has no builds for $version yet');
    }
    // Newest first. Prefer a stable/recommended build, otherwise take the
    // newest alpha or beta and flag it.
    Map? pick;
    for (final b in builds) {
      if (b['channel'] == 'STABLE' || b['channel'] == 'RECOMMENDED') {
        pick = b as Map;
        break;
      }
    }
    final experimental = pick == null;
    pick ??= builds.first as Map;
    final item = pick['downloads']?['server:default'];
    if (item == null) {
      throw StateError('$name build ${pick['id']} has no server download');
    }
    return ServerBuild(
      url: item['url'] as String,
      build: '${pick['id']}',
      hash: item['checksums']?['sha256'] as String?,
      experimental: experimental,
    );
  }

  Future<ServerBuild> _purpur(String version) async {
    final base = 'https://api.purpurmc.org/v2/purpur/$version';
    final info = await _http.json(base);
    final all = ((info['builds']?['all'] as List?) ?? const [])
        .map((b) => '$b')
        .toList();
    if (all.isEmpty) throw StateError('Purpur has no builds for $version yet');
    final latest = '${info['builds']?['latest'] ?? all.last}';
    // Newest first; skip builds Purpur marked as failed.
    final order = [latest, ...all.reversed.where((b) => b != latest)];
    for (final build in order.take(6)) {
      final meta = await _http.json('$base/$build');
      if (meta['result'] != null && meta['result'] != 'SUCCESS') continue;
      return ServerBuild(
        url: '$base/$build/download',
        build: build,
        hash: meta['md5'] as String?,
        algorithm: 'md5',
      );
    }
    throw StateError('No successful Purpur build found for $version');
  }

  Future<ServerBuild> _fabric(String version) async {
    final loaders = await _http.json(
      'https://meta.fabricmc.net/v2/versions/loader/$version',
    ) as List;
    if (loaders.isEmpty) {
      throw StateError('Fabric does not support Minecraft $version yet');
    }
    final loader = (loaders.firstWhere(
      (l) => l['loader']?['stable'] == true,
      orElse: () => loaders.first,
    ))['loader']['version'];
    final installers = await _http.json(
      'https://meta.fabricmc.net/v2/versions/installer',
    ) as List;
    final installer = (installers.firstWhere(
      (i) => i['stable'] == true,
      orElse: () => installers.first,
    ))['version'];
    // The launcher is generated on demand, so Fabric publishes no checksum.
    // The download is still HTTPS-only and size-checked.
    return ServerBuild(
      url:
          'https://meta.fabricmc.net/v2/versions/loader/$version/$loader/$installer/server/jar',
      build: 'loader $loader',
    );
  }
}
