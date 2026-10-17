import 'dart:convert';

enum ServerEngine { vanilla, paper, folia, purpur, fabric, forge }

/// Display text and capabilities for each server software.
extension ServerEngineInfo on ServerEngine {
  String get label => switch (this) {
    ServerEngine.vanilla => 'Vanilla',
    ServerEngine.paper => 'Paper',
    ServerEngine.folia => 'Folia',
    ServerEngine.purpur => 'Purpur',
    ServerEngine.fabric => 'Fabric',
    ServerEngine.forge => 'Forge',
  };

  String get summary => switch (this) {
    ServerEngine.vanilla => 'Official Mojang server. No plugins or mods.',
    ServerEngine.paper =>
      'Fast and stable. Runs Bukkit and Spigot plugins. Best default.',
    ServerEngine.folia =>
      'Paper with multi-threaded regions. Many plugins do not work. Advanced.',
    ServerEngine.purpur =>
      'Paper with extra gameplay options. Runs Bukkit and Spigot plugins.',
    ServerEngine.fabric => 'Lightweight mod loader. Runs Fabric mods.',
    ServerEngine.forge =>
      'Classic modpacks and big adventures. Runs Forge mods.',
  };

  /// Runs Bukkit/Spigot plugins from a `plugins` folder.
  bool get usesPlugins =>
      this == ServerEngine.paper ||
      this == ServerEngine.folia ||
      this == ServerEngine.purpur;

  /// PaperMC asks API users to identify themselves with a contact.
  bool get needsContact =>
      this == ServerEngine.paper || this == ServerEngine.folia;

  /// Bedrock players can join through Geyser on this software.
  bool get crossplayCapable =>
      this == ServerEngine.paper ||
      this == ServerEngine.purpur ||
      this == ServerEngine.fabric;
}

enum ServerPhase { idle, preparing, ready, starting, running, stopping, failed }

class ServerProfile {
  const ServerProfile({
    this.name = 'My Minecraft server',
    this.engine = ServerEngine.vanilla,
    this.version = '1.21.1',
    this.memoryMb = 2048,
    this.eulaAccepted = false,
    this.contact = '',
    this.crossplay = false,
    this.bedrockPort = 19132,
  });
  final String name;
  final ServerEngine engine;
  final String version;
  final int memoryMb;
  final bool eulaAccepted;
  final String contact;

  /// Lets Bedrock players join through Geyser and Floodgate.
  final bool crossplay;

  /// UDP port Geyser listens on for Bedrock players.
  final int bedrockPort;
  String get key => '${engine.name}-$version';
  ServerProfile copyWith({
    String? name,
    ServerEngine? engine,
    String? version,
    int? memoryMb,
    bool? eulaAccepted,
    String? contact,
    bool? crossplay,
    int? bedrockPort,
  }) => ServerProfile(
    name: name ?? this.name,
    engine: engine ?? this.engine,
    version: version ?? this.version,
    memoryMb: memoryMb ?? this.memoryMb,
    eulaAccepted: eulaAccepted ?? this.eulaAccepted,
    contact: contact ?? this.contact,
    crossplay: crossplay ?? this.crossplay,
    bedrockPort: bedrockPort ?? this.bedrockPort,
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'engine': engine.name,
    'version': version,
    'memoryMb': memoryMb,
    'eulaAccepted': eulaAccepted,
    'contact': contact,
    'crossplay': crossplay,
    'bedrockPort': bedrockPort,
  };
  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    name: json['name'] as String,
    engine:
        ServerEngine.values.asNameMap()[json['engine']] ?? ServerEngine.vanilla,
    version: json['version'] as String,
    memoryMb: json['memoryMb'] as int,
    eulaAccepted: json['eulaAccepted'] == true,
    contact: json['contact'] as String? ?? '',
    crossplay: json['crossplay'] == true,
    bedrockPort: json['bedrockPort'] as int? ?? 19132,
  );
}

class LogLine {
  LogLine(this.text, {this.source = 'host', DateTime? time})
    : time = time ?? DateTime.now();
  final String text;
  final String source;
  final DateTime time;
  String get timestamp =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
}

/// Preserves comments, unknown keys, escaped values and Java continuation lines.
class ServerProperties {
  ServerProperties(this.source);
  final String source;
  static final defaults = <String, String>{
    'gamemode': 'survival',
    'difficulty': 'normal',
    'max-players': '10',
    'online-mode': 'true',
    'motd': 'A HostCraft world',
    'server-port': '25565',
    'view-distance': '6',
    'simulation-distance': '4',
    'enable-rcon': 'false',
    'white-list': 'false',
  };
  static String decode(String s) => s.replaceAllMapped(
    RegExp(r'\\(u[0-9a-fA-F]{4}|.)'),
    (m) => switch (m[1]!) {
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      'f' => '\f',
      final v when v.startsWith('u') && v.length == 5 => String.fromCharCode(
        int.parse(v.substring(1), radix: 16),
      ),
      final v => v,
    },
  );
  static String encode(String s) {
    final b = StringBuffer();
    for (final unit in s.codeUnits) {
      b.write(switch (unit) {
        10 => r'\n',
        13 => r'\r',
        9 => r'\t',
        92 => r'\\',
        final n when n < 32 || n > 126 =>
          '\\u${n.toRadixString(16).padLeft(4, '0')}',
        final n => String.fromCharCode(n),
      });
    }
    return b.toString();
  }

  List<String> get _lines => const LineSplitter().convert(source);
  List<({String raw, String? key, String? value})> get _entries {
    final result = <({String raw, String? key, String? value})>[];
    final lines = _lines;
    for (var i = 0; i < lines.length; i++) {
      var raw = lines[i];
      var line = raw;
      while (RegExp(r'\\+$').firstMatch(line)?.group(0)!.length.isOdd == true &&
          i + 1 < lines.length) {
        final next = lines[++i];
        raw += '\n$next';
        line = line.substring(0, line.length - 1) + next.trimLeft();
      }
      final m = RegExp(r'^\s*([^#!\s:=]+)\s*[:=\s]\s*(.*)$').firstMatch(line);
      result.add((
        raw: raw,
        key: m?[1],
        value: m == null ? null : decode(m[2]!),
      ));
    }
    return result;
  }

  Map<String, String> get values => {
    ...defaults,
    for (final e in _entries)
      if (e.key != null) e.key!: e.value!,
  };
  String update(Map<String, String> changes) {
    final seen = <String>{};
    final b = StringBuffer();
    for (final e in _entries) {
      if (changes.containsKey(e.key)) {
        if (seen.add(e.key!)) b.writeln('${e.key}=${encode(changes[e.key]!)}');
      } else {
        b.writeln(e.raw);
      }
    }
    for (final e in changes.entries) {
      if (!seen.contains(e.key)) b.writeln('${e.key}=${encode(e.value)}');
    }
    return b.toString();
  }
}

abstract class BaseGameServer {
  String get gameId;
  String get displayName;
  Future<void> prepare();
  Future<void> start();
  Future<void> stop();
  Future<void> sendCommand(String command);
  Stream<String> get consoleOutput;
}
