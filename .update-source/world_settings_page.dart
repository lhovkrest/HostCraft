import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/host_controller.dart';
import '../core/world_config.dart';
import '../services/world_service.dart';

/// Push this route from your settings or server screen:
/// `Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldSettingsPage()))`
class WorldSettingsPage extends ConsumerStatefulWidget {
  const WorldSettingsPage({super.key});

  @override
  ConsumerState<WorldSettingsPage> createState() => _WorldSettingsPageState();
}

class _WorldSettingsPageState extends ConsumerState<WorldSettingsPage> {
  late WorldConfig config;
  late final TextEditingController name;
  late final TextEditingController seed;
  late final TextEditingController spawnProtection;
  late final TextEditingController maxSize;
  late final TextEditingController generator;
  List<WorldInfo> worlds = [];
  List<File> backups = [];

  @override
  void initState() {
    super.initState();
    config = ref.read(hostProvider).world.copy();
    name = TextEditingController(text: config.levelName);
    seed = TextEditingController(text: config.seed);
    spawnProtection = TextEditingController(text: '${config.spawnProtection}');
    maxSize = TextEditingController(text: '${config.maxWorldSize}');
    generator = TextEditingController(text: config.generatorSettings);
    _refresh();
  }

  @override
  void dispose() {
    for (final c in [name, seed, spawnProtection, maxSize, generator]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    final host = ref.read(hostProvider);
    try {
      final w = await host.listWorlds();
      final b = await host.listBackups();
      if (mounted) {
        setState(() {
          worlds = w;
          backups = b;
        });
      }
    } catch (_) {
      // The server folder does not exist until the first prepare.
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    config
      ..levelName = WorldConfig.sanitizeName(name.text)
      ..seed = seed.text.trim()
      ..spawnProtection = (int.tryParse(spawnProtection.text) ?? 16).clamp(0, 1000).toInt()
      ..maxWorldSize = (int.tryParse(maxSize.text) ?? 29999984).clamp(1, 29999984).toInt()
      ..generatorSettings = generator.text.trim();
    try {
      await ref.read(hostProvider).saveWorld(config.copy());
      name.text = config.levelName;
      _say('World settings saved. They apply on the next start.');
      _refresh();
    } catch (e) {
      _say('$e'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final host = ref.read(hostProvider);
    final ok = await _confirm(
      'Import world?',
      'The zip will be imported as "${WorldConfig.sanitizeName(name.text)}". '
          'A world with that name is kept next to it as a ".old" folder.',
      'Import',
    );
    if (!ok) return;
    await _save();
    await host.importWorld(File(path));
    _refresh();
    _say(host.error ?? 'World imported.');
  }

  Future<void> _reset() async {
    final host = ref.read(hostProvider);
    final ok = await _confirm(
      'Reset world?',
      'This deletes "${host.world.levelName}" and generates a new one on the next start. '
          'A backup zip is made first.',
      'Reset',
    );
    if (!ok) return;
    await host.resetWorld();
    _refresh();
    _say(host.error ?? 'World reset. A backup was saved.');
  }

  String _size(int bytes) => bytes > 1 << 30
      ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
      : '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final locked = host.locked;
    final theme = Theme.of(context);

    Widget toggle(String title, bool value, void Function(bool) set, [String? sub]) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          value: value,
          onChanged: locked ? null : (v) => setState(() => set(v)),
        );

    Widget dropdown(String label, String value, List<String> items, void Function(String) set) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownMenu<String>(
            width: double.infinity,
            label: Text(label),
            initialSelection: value,
            enabled: !locked,
            dropdownMenuEntries: [
              for (final i in items)
                DropdownMenuEntry(value: i, label: i[0].toUpperCase() + i.substring(1)),
            ],
            onSelected: (v) {
              if (v != null) setState(() => set(v));
            },
          ),
        );

    Widget number(String label, TextEditingController c) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: !locked,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('World settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (locked)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Stop the server to change world settings.'),
            ),
          Text('World', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            enabled: !locked,
            decoration: const InputDecoration(
              labelText: 'World name (folder)',
              helperText:
                  'A new name creates a new world. Your old one stays on disk.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: seed,
            enabled: !locked,
            decoration: const InputDecoration(
              labelText: 'Seed',
              helperText:
                  'Leave empty for a random world. Only used when a world is first created.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownMenu<WorldType>(
            width: double.infinity,
            label: const Text('World type'),
            initialSelection: config.type,
            enabled: !locked,
            dropdownMenuEntries: [
              for (final t in WorldType.values)
                DropdownMenuEntry(value: t, label: t.label),
            ],
            onSelected: (v) {
              if (v != null) setState(() => config.type = v);
            },
          ),
          if (config.type == WorldType.flat ||
              config.type == WorldType.singleBiome) ...[
            const SizedBox(height: 12),
            TextField(
              controller: generator,
              enabled: !locked,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Generator settings (JSON)',
                helperText: 'Optional. Superflat layers or the biome to use.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          toggle('Generate structures', config.generateStructures,
              (v) => config.generateStructures = v, 'Villages, temples, strongholds'),
          const Divider(height: 28),
          Text('Gameplay', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          dropdown('Default game mode', config.gamemode, WorldConfig.gamemodes,
              (v) => config.gamemode = v),
          dropdown('Difficulty', config.difficulty, WorldConfig.difficulties,
              (v) => config.difficulty = v),
          toggle('Hardcore', config.hardcore, (v) => config.hardcore = v,
              'One life. Forces hard difficulty.'),
          toggle('Force game mode on join', config.forceGamemode,
              (v) => config.forceGamemode = v),
          toggle('Player vs player', config.pvp, (v) => config.pvp = v),
          toggle('Allow flying', config.allowFlight, (v) => config.allowFlight = v,
              'Stops anti-fly kicks for mods and creative flight'),
          toggle('Nether', config.allowNether, (v) => config.allowNether = v),
          toggle('Command blocks', config.commandBlocks,
              (v) => config.commandBlocks = v),
          const Divider(height: 28),
          Text('Spawning', style: theme.textTheme.titleMedium),
          toggle('Animals', config.spawnAnimals, (v) => config.spawnAnimals = v),
          toggle('Monsters', config.spawnMonsters, (v) => config.spawnMonsters = v),
          toggle('Villagers and NPCs', config.spawnNpcs, (v) => config.spawnNpcs = v),
          const SizedBox(height: 8),
          number('Spawn protection radius (blocks)', spawnProtection),
          number('Maximum world size (blocks, radius)', maxSize),
          FilledButton.icon(
            onPressed: locked ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save world settings'),
          ),
          const Divider(height: 36),
          Text('Worlds on this server', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (worlds.isEmpty)
            const Text('No worlds yet. One is created the first time the server starts.')
          else
            for (final w in worlds)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.public),
                title: Text(w.name),
                subtitle: Text('${_size(w.bytes)} · last played ${w.modified.toLocal().toString().split('.').first}'),
                trailing: w.name == WorldConfig.sanitizeName(name.text)
                    ? const Chip(label: Text('Selected'))
                    : TextButton(
                        onPressed: locked ? null : () => setState(() => name.text = w.name),
                        child: const Text('Use'),
                      ),
              ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: locked || host.working
                    ? null
                    : () async {
                        await host.backupWorld();
                        _refresh();
                        _say(host.error ?? 'Backup saved.');
                      },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Back up'),
              ),
              OutlinedButton.icon(
                onPressed: locked || host.working ? null : _import,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import zip'),
              ),
              OutlinedButton.icon(
                onPressed: locked || host.working ? null : _reset,
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                label: Text('Reset world', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ),
          if (backups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Backups', style: theme.textTheme.titleMedium),
            for (final b in backups.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_zip_outlined),
                title: Text(p.basename(b.path)),
                subtitle: Text(b.path, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
        ],
      ),
    );
  }
}
