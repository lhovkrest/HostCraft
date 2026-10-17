import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/host_controller.dart';
import '../core/models.dart';
import '../services/runtime_service.dart';

/// Opens the server type / version / crossplay picker.
Future<void> showServerSetup(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const ServerSetupSheet(),
);

class ServerSetupSheet extends ConsumerStatefulWidget {
  const ServerSetupSheet({super.key});

  @override
  ConsumerState<ServerSetupSheet> createState() => _ServerSetupSheetState();
}

class _ServerSetupSheetState extends ConsumerState<ServerSetupSheet> {
  late ServerEngine engine;
  late String version;
  late bool crossplay;
  late final TextEditingController contact;
  late final TextEditingController bedrockPort;
  bool snapshots = false;
  bool loading = false;
  String? loadError;
  List<String> versions = [];
  int? javaMajor;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(hostProvider).profile;
    engine = profile.engine;
    version = profile.version;
    crossplay = profile.crossplay;
    contact = TextEditingController(text: profile.contact);
    bedrockPort = TextEditingController(text: '${profile.bedrockPort}');
    _load();
  }

  @override
  void dispose() {
    contact.dispose();
    bedrockPort.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final list = await ref
          .read(hostProvider)
          .catalogFor(contact.text.trim())
          .versions(engine, snapshots: snapshots);
      if (!mounted) return;
      setState(() {
        versions = list;
        if (list.isNotEmpty && !list.contains(version)) version = list.first;
      });
      await _checkJava();
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _checkJava() async {
    final major = await ref.read(hostProvider).catalog().javaMajor(version);
    if (mounted) setState(() => javaMajor = major);
  }

  bool get _javaTooNew =>
      Platform.isAndroid &&
      javaMajor != null &&
      javaMajor! > RuntimeService.androidMaxJava;

  Future<void> _save() async {
    final host = ref.read(hostProvider);
    final port = int.tryParse(bedrockPort.text.trim()) ?? 19132;
    try {
      await host.configure(
        host.profile.copyWith(
          engine: engine,
          version: version,
          crossplay: crossplay && engine.crossplayCapable,
          bedrockPort: port.clamp(1024, 65535).toInt(),
          contact: contact.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Bad state: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final theme = Theme.of(context);
    final locked = host.locked;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server setup', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownMenu<ServerEngine>(
              width: double.infinity,
              label: const Text('Server software'),
              initialSelection: engine,
              enabled: !locked,
              dropdownMenuEntries: [
                for (final e in ServerEngine.values)
                  DropdownMenuEntry(value: e, label: e.label),
              ],
              onSelected: (value) {
                if (value == null || value == engine) return;
                setState(() {
                  engine = value;
                  if (!engine.crossplayCapable) crossplay = false;
                });
                _load();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
              child: Text(engine.summary, style: theme.textTheme.bodySmall),
            ),
            if (engine.needsContact) ...[
              TextField(
                controller: contact,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Contact URL or email',
                  helperText:
                      'PaperMC asks everyone who downloads from them to identify themselves.',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _load(),
              ),
              const SizedBox(height: 12),
            ],
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (loadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Could not load versions: $loadError',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            else
              DropdownMenu<String>(
                key: ValueKey('$engine-$snapshots-${versions.length}'),
                width: double.infinity,
                label: const Text('Minecraft version'),
                initialSelection: versions.contains(version) ? version : null,
                enabled: !locked && versions.isNotEmpty,
                enableFilter: true,
                requestFocusOnTap: true,
                menuHeight: 320,
                dropdownMenuEntries: [
                  for (var i = 0; i < versions.length; i++)
                    DropdownMenuEntry(
                      value: versions[i],
                      label: i == 0 ? '${versions[i]} (latest)' : versions[i],
                    ),
                ],
                onSelected: (value) {
                  if (value == null) return;
                  setState(() {
                    version = value;
                    javaMajor = null;
                  });
                  _checkJava();
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show snapshots and pre-releases'),
              value: snapshots,
              onChanged: locked
                  ? null
                  : (v) {
                      setState(() => snapshots = v);
                      _load();
                    },
            ),
            if (_javaTooNew)
              _note(
                context,
                'Minecraft $version needs Java $javaMajor, but the Android app bundles Java ${RuntimeService.androidMaxJava}. '
                'Pick 1.21.11 or older, or host this version on Windows.',
                error: true,
              )
            else if (javaMajor != null && javaMajor! > 21)
              _note(
                context,
                'This version needs Java $javaMajor. HostCraft downloads it automatically the first time.',
              ),
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bedrock crossplay (Geyser)'),
              subtitle: Text(
                engine.crossplayCapable
                    ? 'Lets Bedrock players on phones, consoles and Windows join. Installs Geyser and Floodgate automatically.'
                    : '${engine.label} cannot load Geyser. Use Paper, Purpur or Fabric for crossplay.',
              ),
              value: crossplay && engine.crossplayCapable,
              onChanged: locked || !engine.crossplayCapable
                  ? null
                  : (v) => setState(() => crossplay = v),
            ),
            if (crossplay && engine.crossplayCapable) ...[
              TextField(
                controller: bedrockPort,
                enabled: !locked,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Bedrock port (UDP)',
                  helperText: 'Default 19132',
                  border: OutlineInputBorder(),
                ),
              ),
              _note(
                context,
                'Geyser follows new Minecraft releases closely but can lag a few days behind. It works best on the newest version.',
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Each software and version keeps its own server folder. Back up your world in World settings to carry it over.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: locked || loading || versions.isEmpty
                      ? null
                      : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(BuildContext context, String text, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? scheme.onErrorContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
