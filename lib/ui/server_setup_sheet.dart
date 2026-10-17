import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/host_controller.dart';
import '../core/models.dart';
import '../services/device_service.dart';
import '../services/runtime_service.dart';
import 'theme.dart';
import 'widgets.dart';
import 'setup_components.dart';

Future<void> showServerSetup(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 1000),
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
  late bool crossplay, eula;
  late double memory;
  late final TextEditingController name, contact, bedrockPort;
  bool snapshots = false, loading = false, saving = false;
  String? loadError;
  List<String> versions = [];
  int? javaMajor;
  int request = 0;
  int step = 0;
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final profile = ref.read(hostProvider).profile;
    engine = profile.engine;
    version = profile.version;
    crossplay = profile.crossplay;
    eula = profile.eulaAccepted;
    memory = profile.memoryMb.toDouble();
    name = TextEditingController(text: profile.name);
    contact = TextEditingController(text: profile.contact);
    bedrockPort = TextEditingController(text: '${profile.bedrockPort}');
    _load();
  }

  @override
  void dispose() {
    scroll.dispose();
    name.dispose();
    contact.dispose();
    bedrockPort.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ticket = ++request;
    setState(() {
      loading = true;
      loadError = null;
      javaMajor = null;
    });
    try {
      final catalog = ref.read(hostProvider).catalogFor(contact.text.trim());
      final list = await catalog.versions(engine, snapshots: snapshots);
      if (!mounted || ticket != request) return;
      setState(() {
        versions = list;
        if (list.isNotEmpty && !list.contains(version)) version = list.first;
      });
      if (list.isNotEmpty) {
        final major = await catalog.javaMajor(version);
        if (mounted && ticket == request) setState(() => javaMajor = major);
      }
    } catch (e) {
      if (mounted && ticket == request) setState(() => loadError = '$e');
    } finally {
      if (mounted && ticket == request) setState(() => loading = false);
    }
  }

  Future<void> _selectVersion(String value) async {
    final ticket = ++request;
    setState(() {
      version = value;
      javaMajor = null;
      loading = true;
      loadError = null;
    });
    try {
      final major = await ref.read(hostProvider).catalog().javaMajor(value);
      if (mounted && ticket == request) setState(() => javaMajor = major);
    } catch (e) {
      if (mounted && ticket == request) setState(() => loadError = '$e');
    } finally {
      if (mounted && ticket == request) setState(() => loading = false);
    }
  }

  bool get javaTooNew =>
      Platform.isAndroid &&
      javaMajor != null &&
      javaMajor! > RuntimeService.androidMaxJava;

  Future<void> _save() async {
    final host = ref.read(hostProvider);
    final port = int.tryParse(bedrockPort.text.trim());
    if (name.text.trim().isEmpty ||
        (engine.needsContact && contact.text.trim().isEmpty) ||
        (crossplay && (port == null || port < 1024 || port > 65535))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a server name, required contact, and a UDP port from 1024 to 65535.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await host.configure(
        host.profile.copyWith(
          name: name.text.trim(),
          engine: engine,
          version: version,
          memoryMb: memory.round(),
          eulaAccepted: eula,
          crossplay: crossplay && engine.crossplayCapable,
          bedrockPort: port ?? 19132,
          contact: contact.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  bool get forgeUnavailable =>
      engine == ServerEngine.forge && !Platform.isWindows;
  bool get versionReady =>
      !loading &&
      loadError == null &&
      javaMajor != null &&
      !javaTooNew &&
      versions.contains(version);
  bool get detailsReady =>
      name.text.trim().isNotEmpty &&
      (!engine.needsContact || contact.text.trim().isNotEmpty) &&
      versionReady;
  bool get resourcesReady =>
      !crossplay ||
      ((int.tryParse(bedrockPort.text) ?? 0) >= 1024 &&
          (int.tryParse(bedrockPort.text) ?? 0) <= 65535);
  bool get canContinue =>
      !forgeUnavailable &&
      switch (step) {
        0 => true,
        1 => detailsReady,
        2 => resourcesReady,
        _ => detailsReady && resourcesReady && eula,
      };

  void _go(int next) {
    setState(() => step = next);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> _chooseVersion() async {
    var query = '';
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          final matches = versions
              .where((v) => v.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return AlertDialog(
            title: const Text('Minecraft version'),
            content: SizedBox(
              width: 420,
              height: math.min(420, MediaQuery.sizeOf(context).height * .55),
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Find a version, like 1.20.1',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => refresh(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text('No matching versions'))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (_, i) => ListTile(
                              title: Text(matches[i]),
                              subtitle: matches[i] == versions.first
                                  ? const Text('Latest available')
                                  : null,
                              trailing: matches[i] == version
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: context.hc.accent,
                                    )
                                  : null,
                              onTap: () =>
                                  Navigator.pop(dialogContext, matches[i]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (choice != null && mounted) _selectVersion(choice);
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final c = context.hc;
    final locked = host.locked || saving;
    const names = ['Software', 'Details', 'Resources', 'Ready'];
    const titles = [
      'What kind of world?',
      'Make it your own.',
      'Give it room to grow.',
      'Your world is almost ready.',
    ];
    const subtitles = [
      'Pick the experience. We will handle the server files and Java.',
      'Name your server and choose the version your friends will play.',
      'Choose how much memory to use and who can join.',
      'Review your setup, then save it. You control when the server starts.',
    ];
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SizedBox(
        height: math.min(
          860,
          (MediaQuery.sizeOf(context).height - inset) * .94,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: c.accent,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Server studio',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  Text(
                    '${step + 1} / 4',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Close setup',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 3,
                            decoration: BoxDecoration(
                              color: i <= step ? c.accent : c.border,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            names[i],
                            style: TextStyle(
                              fontSize: 11,
                              color: i == step ? c.text : c.muted,
                              fontWeight: i == step
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titles[step],
                      style: TextStyle(
                        fontSize: MediaQuery.sizeOf(context).width < 480
                            ? 26
                            : 32,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitles[step],
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ...switch (step) {
                      0 => _software(locked),
                      1 => _details(locked),
                      2 => _resources(host, locked),
                      _ => _review(host, locked),
                    },
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  if (step > 0)
                    OutlinedButton(
                      onPressed: saving ? null : () => _go(step - 1),
                      child: const Text('Back'),
                    )
                  else
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: locked || !canContinue
                        ? null
                        : step == 3
                        ? _save
                        : () => _go(step + 1),
                    icon: Icon(
                      step == 3
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
                    label: Text(
                      saving
                          ? 'Saving…'
                          : step == 3
                          ? 'Save setup'
                          : 'Continue',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _software(bool locked) => [
    LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 440
            ? 2
            : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final choice in [
              ServerEngine.paper,
              ServerEngine.vanilla,
              ServerEngine.fabric,
              ServerEngine.forge,
              ServerEngine.purpur,
              ServerEngine.folia,
            ])
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                child: EngineChoice(
                  engine: choice,
                  selected: engine == choice,
                  available: choice != ServerEngine.forge || Platform.isWindows,
                  onTap:
                      locked ||
                          (choice == ServerEngine.forge && !Platform.isWindows)
                      ? null
                      : () {
                          if (engine == choice) return;
                          setState(() {
                            engine = choice;
                            if (!engine.crossplayCapable) crossplay = false;
                          });
                          _load();
                        },
                ),
              ),
          ],
        );
      },
    ),
    const SizedBox(height: 20),
    SetupTip(
      title: 'Selected: ${engine.label}',
      body: switch (engine) {
        ServerEngine.paper => 'A good starting point for playing with friends. Add server plugins without asking players to install mods.',
        ServerEngine.vanilla => 'The official Minecraft experience. Players use the regular Java Edition client. No mods or plugins.',
        ServerEngine.fabric => 'Choose this for Fabric mods. Players usually need the same Minecraft version, loader and gameplay mods.',
        ServerEngine.forge => 'Forge hosting is available on Windows for Minecraft 1.18+. Use matching Forge mods on the server and each player’s game. Bedrock crossplay is not supported here.',
        ServerEngine.purpur => 'Paper-compatible plugins with more gameplay settings. Start with defaults, then customize the rules.',
        ServerEngine.folia => 'For experienced hosts. Only use plugins that explicitly support Folia’s region-based threading.',
      },
    ),
  ];

  List<Widget> _details(bool locked) {
    final c = context.hc;
    return [
      _fieldLabel('Server name', 'Give your world a name you will recognize.'),
      TextField(
        controller: name,
        enabled: !locked,
        maxLength: 40,
        decoration: const InputDecoration(
          hintText: 'e.g. The weekend world',
          prefixIcon: Icon(Icons.dns_outlined),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 20),
      _fieldLabel(
        'Minecraft version',
        'Match the version in your Minecraft launcher.',
      ),
      Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(Icons.view_in_ar_outlined, color: c.accent),
          title: Text(
            versions.contains(version) ? version : 'Choose a version',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            loading
                ? 'Checking available versions…'
                : '${versions.length} versions available',
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          trailing: const Icon(Icons.unfold_more_rounded),
          onTap: locked || loading || versions.isEmpty ? null : _chooseVersion,
        ),
      ),
      if (engine != ServerEngine.forge)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Show preview releases',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            'Snapshots may be less stable.',
            style: TextStyle(fontSize: 12),
          ),
          value: snapshots,
          onChanged: locked
              ? null
              : (v) {
                  setState(() => snapshots = v);
                  _load();
                },
        ),
      if (engine.needsContact) ...[
        const SizedBox(height: 16),
        _fieldLabel(
          'Contact email or project URL',
          'PaperMC requires this for download requests.',
        ),
        TextField(
          controller: contact,
          enabled: !locked,
          decoration: const InputDecoration(
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _load(),
        ),
        TextButton.icon(
          onPressed: locked ? null : _load,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Refresh versions'),
        ),
      ],
      const SizedBox(height: 18),
      if (loading) const LinearProgressIndicator(),
      if (loadError != null)
        Notice(
          text: 'Could not load versions: $loadError',
          action: TextButton(
            onPressed: locked ? null : _load,
            child: const Text('Retry'),
          ),
        ),
      if (javaTooNew)
        Notice(
          color: c.danger,
          text:
              'This version needs Java $javaMajor. Android currently bundles Java ${RuntimeService.androidMaxJava}. Choose an older release.',
        ),
      if (!javaTooNew && javaMajor != null)
        SetupTip(
          icon: Icons.check_circle_outline_rounded,
          title: 'Java is taken care of',
          body:
              '${engine == ServerEngine.forge ? 'Forge will use Java $javaMajor' : 'Minecraft requires Java $javaMajor'}. HostCraft installs the required runtime on Windows. You do not need to set it up yourself.',
        ),
    ];
  }

  Widget _fieldLabel(String title, String hint) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(color: context.hc.muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );

  List<Widget> _resources(HostController host, bool locked) => [
    FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Memory allocation'),
          const SizedBox(height: 8),
          Text(
            '${gigabytes(memory)} GB',
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          Text(
            'Maximum memory for your server',
            style: TextStyle(color: context.hc.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Slider(
            value: memory.clamp(
              DeviceService.minMemoryMb.toDouble(),
              host.maxMemoryMb.toDouble(),
            ),
            min: DeviceService.minMemoryMb.toDouble(),
            max: host.maxMemoryMb.toDouble(),
            divisions: math.max(
              1,
              (host.maxMemoryMb - DeviceService.minMemoryMb) ~/
                  DeviceService.memoryStepMb,
            ),
            onChanged: locked ? null : (v) => setState(() => memory = v),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mb in [
                1024,
                2048,
                4096,
                6144,
                8192,
              ].where((mb) => mb <= host.maxMemoryMb))
                ChoiceChip(
                  label: Text('${mb ~/ 1024} GB'),
                  selected: memory.round() == mb,
                  onSelected: locked
                      ? null
                      : (_) => setState(() => memory = mb.toDouble()),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Recommended ceiling on this device: ${gigabytes(host.recommendedMemoryMb)} GB',
            style: TextStyle(color: context.hc.muted, fontSize: 12),
          ),
        ],
      ),
    ),
    if (memory > host.recommendedMemoryMb)
      const Notice(
        text: 'This leaves little memory for other apps. Try a smaller allocation if your device slows down.',
      ),
    FlatCard(
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Let Bedrock friends join',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              engine.crossplayCapable
                  ? 'Adds Geyser and Floodgate for crossplay.'
                  : 'HostCraft crossplay supports Paper, Purpur and Fabric.',
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
            value: crossplay && engine.crossplayCapable,
            onChanged: locked || !engine.crossplayCapable
                ? null
                : (v) => setState(() => crossplay = v),
          ),
          if (crossplay && engine.crossplayCapable) ...[
            const SizedBox(height: 14),
            TextField(
              controller: bedrockPort,
              enabled: !locked,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Bedrock port',
                hintText: '19132',
                helperText: 'UDP port, from 1024 to 65535',
                errorText: resourcesReady ? null : 'Enter a valid port',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    ),
    SetupTip(
      title: engine == ServerEngine.forge || engine == ServerEngine.fabric
          ? 'Planning to add mods?'
          : 'Leave room for your device',
      body: engine == ServerEngine.forge || engine == ServerEngine.fabric
          ? 'Modpacks can need more memory. Follow the pack’s requirements, keep server and client mods compatible, and add mods while the server is stopped.'
          : 'More RAM is not always faster. Start within the recommendation, then adjust based on your world and player count.',
    ),
  ];

  List<Widget> _review(HostController host, bool locked) => [
    FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(engine.icon, color: engine.tint, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name.text.trim(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final item in [
            ('Software', engine.label),
            ('Minecraft', version),
            ('Memory', '${gigabytes(memory)} GB'),
            ('Players', crossplay ? 'Java + Bedrock' : 'Java Edition'),
            if (engine == ServerEngine.forge) ('Host platform', 'Windows'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.$1,
                      style: TextStyle(color: context.hc.muted, fontSize: 13),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      item.$2,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text(
        'I agree to the Minecraft EULA',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      value: eula,
      onChanged: locked ? null : (v) => setState(() => eula = v ?? false),
    ),
    TextButton.icon(
      onPressed: () => openLink(context, 'https://www.minecraft.net/eula'),
      icon: const Icon(Icons.open_in_new_rounded, size: 16),
      label: const Text('Read the Minecraft EULA'),
    ),
    const SizedBox(height: 16),
    const SetupTip(
      title: 'What happens next?',
      body: 'Save your setup, then choose Start server on Overview. HostCraft downloads the software, prepares your world and shows progress in Console. Once it is online, open Network to invite friends.',
    ),
    const SizedBox(height: 12),
    Text(
      'Each software and Minecraft version uses its own folder. Back up your world before moving it to a different setup.',
      style: TextStyle(color: context.hc.muted, height: 1.6, fontSize: 12),
    ),
  ];
}
