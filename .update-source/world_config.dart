import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum WorldType {
  normal('minecraft:normal', 'Normal'),
  flat('minecraft:flat', 'Superflat'),
  largeBiomes('minecraft:large_biomes', 'Large biomes'),
  amplified('minecraft:amplified', 'Amplified'),
  singleBiome('minecraft:single_biome_surface', 'Single biome');

  const WorldType(this.id, this.label);
  final String id;
  final String label;

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('minecraft:', '')
      .replaceAll('_', '')
      .replaceAll('default', 'normal');

  /// Accepts both modern (`minecraft:large_biomes`) and legacy
  /// (`largebiomes`, `default`) level-type values.
  static WorldType parse(String? value) {
    final wanted = _norm(value ?? '');
    for (final type in WorldType.values) {
      if (_norm(type.id) == wanted) return type;
    }
    return WorldType.normal;
  }
}

/// How the world is generated and played. Saved as `world.json` in the
/// HostCraft folder and written into the server's `server.properties`, so the
/// same world settings follow you when you change server software or version.
///
/// Network and performance options (port, player limit, view distance, MOTD)
/// stay in the normal server settings and are not part of this file.
class WorldConfig {
  WorldConfig();

  String levelName = 'world';

  /// Empty means a random seed.
  String seed = '';
  WorldType type = WorldType.normal;
  bool generateStructures = true;
  bool hardcore = false;
  String gamemode = 'survival';
  String difficulty = 'normal';
  bool forceGamemode = false;
  bool pvp = true;
  bool allowNether = true;
  bool allowFlight = false;
  bool spawnAnimals = true;
  bool spawnMonsters = true;
  bool spawnNpcs = true;
  bool commandBlocks = false;
  int spawnProtection = 16;
  int maxWorldSize = 29999984;

  /// Superflat layers or single-biome settings, as JSON. Empty is default.
  String generatorSettings = '';

  static const gamemodes = ['survival', 'creative', 'adventure', 'spectator'];
  static const difficulties = ['peaceful', 'easy', 'normal', 'hard'];

  /// World folders live inside the server folder, so the name must be a plain
  /// folder name: no slashes, no dots at the start, nothing that could point
  /// outside the server directory.
  static String sanitizeName(String name) {
    final clean = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9 _.\-]'), '')
        .replaceFirst(RegExp(r'^\.+'), '');
    return clean.isEmpty ? 'world' : clean;
  }

  WorldConfig copy() => WorldConfig.fromJson(toJson());

  Map<String, String> toProperties() => {
    'level-name': sanitizeName(levelName),
    'level-seed': seed.trim(),
    'level-type': type.id,
    'generate-structures': '$generateStructures',
    'hardcore': '$hardcore',
    'gamemode': gamemode,
    'difficulty': difficulty,
    'force-gamemode': '$forceGamemode',
    'pvp': '$pvp',
    'allow-nether': '$allowNether',
    'allow-flight': '$allowFlight',
    'spawn-animals': '$spawnAnimals',
    'spawn-monsters': '$spawnMonsters',
    'spawn-npcs': '$spawnNpcs',
    'enable-command-block': '$commandBlocks',
    'spawn-protection': '$spawnProtection',
    'max-world-size': '$maxWorldSize',
    'generator-settings': generatorSettings.trim(),
  };

  /// Reads the same keys back from a `server.properties` map.
  factory WorldConfig.fromProperties(Map<String, String> v) {
    bool b(String key, bool fallback) =>
        v[key] == null ? fallback : v[key]!.toLowerCase() == 'true';
    int i(String key, int fallback) => int.tryParse(v[key] ?? '') ?? fallback;
    final c = WorldConfig();
    c.levelName = sanitizeName(v['level-name'] ?? 'world');
    c.seed = v['level-seed'] ?? '';
    c.type = WorldType.parse(v['level-type']);
    c.generateStructures = b('generate-structures', true);
    c.hardcore = b('hardcore', false);
    c.gamemode = gamemodes.contains(v['gamemode']) ? v['gamemode']! : 'survival';
    c.difficulty = difficulties.contains(v['difficulty'])
        ? v['difficulty']!
        : 'normal';
    c.forceGamemode = b('force-gamemode', false);
    c.pvp = b('pvp', true);
    c.allowNether = b('allow-nether', true);
    c.allowFlight = b('allow-flight', false);
    c.spawnAnimals = b('spawn-animals', true);
    c.spawnMonsters = b('spawn-monsters', true);
    c.spawnNpcs = b('spawn-npcs', true);
    c.commandBlocks = b('enable-command-block', false);
    c.spawnProtection = i('spawn-protection', 16);
    c.maxWorldSize = i('max-world-size', 29999984);
    c.generatorSettings = v['generator-settings'] ?? '';
    return c;
  }

  Map<String, dynamic> toJson() => {
    'levelName': levelName,
    'seed': seed,
    'type': type.name,
    'generateStructures': generateStructures,
    'hardcore': hardcore,
    'gamemode': gamemode,
    'difficulty': difficulty,
    'forceGamemode': forceGamemode,
    'pvp': pvp,
    'allowNether': allowNether,
    'allowFlight': allowFlight,
    'spawnAnimals': spawnAnimals,
    'spawnMonsters': spawnMonsters,
    'spawnNpcs': spawnNpcs,
    'commandBlocks': commandBlocks,
    'spawnProtection': spawnProtection,
    'maxWorldSize': maxWorldSize,
    'generatorSettings': generatorSettings,
  };

  factory WorldConfig.fromJson(Map<String, dynamic> j) {
    final c = WorldConfig();
    c.levelName = sanitizeName('${j['levelName'] ?? 'world'}');
    c.seed = '${j['seed'] ?? ''}';
    c.type = WorldType.values.asNameMap()[j['type']] ?? WorldType.normal;
    c.generateStructures = j['generateStructures'] != false;
    c.hardcore = j['hardcore'] == true;
    c.gamemode = gamemodes.contains(j['gamemode']) ? j['gamemode'] : 'survival';
    c.difficulty = difficulties.contains(j['difficulty'])
        ? j['difficulty']
        : 'normal';
    c.forceGamemode = j['forceGamemode'] == true;
    c.pvp = j['pvp'] != false;
    c.allowNether = j['allowNether'] != false;
    c.allowFlight = j['allowFlight'] == true;
    c.spawnAnimals = j['spawnAnimals'] != false;
    c.spawnMonsters = j['spawnMonsters'] != false;
    c.spawnNpcs = j['spawnNpcs'] != false;
    c.commandBlocks = j['commandBlocks'] == true;
    c.spawnProtection = (j['spawnProtection'] as num?)?.toInt() ?? 16;
    c.maxWorldSize = (j['maxWorldSize'] as num?)?.toInt() ?? 29999984;
    c.generatorSettings = '${j['generatorSettings'] ?? ''}';
    return c;
  }

  static File _file(Directory root) => File(p.join(root.path, 'world.json'));

  /// The saved world config, or defaults when none exists or it is unreadable.
  static Future<WorldConfig> load(Directory root) async {
    try {
      final file = _file(root);
      if (!await file.exists()) return WorldConfig();
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, dynamic>
          ? WorldConfig.fromJson(data)
          : WorldConfig();
    } catch (_) {
      return WorldConfig();
    }
  }

  Future<void> save(Directory root) => _file(root).writeAsString(
    const JsonEncoder.withIndent('  ').convert(toJson()),
    flush: true,
  );
}
