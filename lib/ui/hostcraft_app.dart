import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/host_controller.dart';
import '../core/models.dart';

const mint = Color(0xff8df3bd);
const muted = Color(0xff9caaa7);
const panel = Color(0xff172321);

class HostCraftApp extends StatelessWidget {
  const HostCraftApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HostCraft',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff0c1513),
      colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.dark,
        primary: mint,
        surface: panel,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff0c1513),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff101b18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xff31433c)),
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: const HostShell(),
  );
}

Future<void> openLink(BuildContext context, String url) async {
  try {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('No browser available');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open link: $e')));
    }
  }
}

class HostShell extends ConsumerStatefulWidget {
  const HostShell({super.key});
  @override
  ConsumerState<HostShell> createState() => _HostShellState();
}

class _HostShellState extends ConsumerState<HostShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final wide = MediaQuery.sizeOf(context).width > 850;
    final screens = [
      Overview(host: host, onConsole: () => setState(() => selected = 1)),
      ConsoleScreen(host: host),
      NetworkScreen(host: host),
      SettingsScreen(key: ValueKey(host.profile.key), host: host),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: mint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.view_in_ar_rounded,
                color: Color(0xff10231b),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'HostCraft',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xff34453f)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'EARLY ACCESS',
                style: TextStyle(fontSize: 9, letterSpacing: 1.4, color: muted),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: !host.loaded
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  if (wide)
                    NavigationRail(
                      selectedIndex: selected,
                      onDestinationSelected: (i) =>
                          setState(() => selected = i),
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: const Color(0xff0c1513),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          label: Text('Overview'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.terminal_rounded),
                          label: Text('Console'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.public),
                          label: Text('Network'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.tune),
                          label: Text('Settings'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (host.error != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xff442b2a),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Color(0xffffb4ab),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    host.error!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Dismiss',
                                  onPressed: () {
                                    host.error = null;
                                    host.changed();
                                  },
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: IndexedStack(
                            index: selected,
                            children: screens,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => selected = i),
              backgroundColor: const Color(0xff111e19),
              indicatorColor: const Color(0xff2c493b),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Overview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.terminal_rounded),
                  label: 'Console',
                ),
                NavigationDestination(
                  icon: Icon(Icons.public),
                  label: 'Network',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

Widget heading(String eyebrow, String title, String subtitle) => Padding(
  padding: const EdgeInsets.only(bottom: 24),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: const TextStyle(
          color: mint,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.3,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        title,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        subtitle,
        style: const TextStyle(color: muted, height: 1.5, fontSize: 13),
      ),
    ],
  ),
);
Widget card(Widget child, {EdgeInsets padding = const EdgeInsets.all(20)}) =>
    Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: padding,
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff2b3b33)),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );

class PhaseBadge extends StatelessWidget {
  const PhaseBadge(this.phase, {super.key});
  final ServerPhase phase;
  @override
  Widget build(BuildContext context) {
    final color = phase == ServerPhase.running
        ? mint
        : phase == ServerPhase.failed
        ? const Color(0xffffb4ab)
        : const Color(0xffe9cf8f);
    final label = switch (phase) {
      ServerPhase.idle => 'NOT SET UP',
      ServerPhase.ready => 'OFFLINE',
      ServerPhase.running => 'ONLINE',
      _ => phase.name.toUpperCase(),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class Overview extends StatelessWidget {
  const Overview({super.key, required this.host, required this.onConsole});
  final HostController host;
  final VoidCallback onConsole;
  @override
  Widget build(BuildContext context) {
    final ready = host.phase != ServerPhase.idle;
    return PageBody(
      children: [
        heading(
          'Your personal server room',
          'Make room for adventure.',
          'Host a Minecraft world. Bring your friends along.',
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff244636), Color(0xff182d24), Color(0xff172321)],
            ),
            border: Border.all(color: const Color(0xff45634e)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.grass_rounded, color: mint, size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'MINECRAFT JAVA',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PhaseBadge(host.phase),
                ],
              ),
              const SizedBox(height: 27),
              Text(
                host.profile.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${host.profile.engine == ServerEngine.paper ? 'Paper' : 'Vanilla'} ${host.profile.version}  ·  Java 21  ·  ${(host.profile.memoryMb / 1024).toStringAsFixed(1)} GB heap',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          host.working || host.phase == ServerPhase.stopping
                          ? null
                          : host.active
                          ? host.stop
                          : host.profile.eulaAccepted
                          ? host.start
                          : () => showSetup(context, host),
                      icon: Icon(
                        host.active
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        host.active
                            ? 'Stop server'
                            : host.profile.eulaAccepted
                            ? 'Start server'
                            : 'Set up server',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: host.locked
                        ? null
                        : () => showSetup(context, host),
                    tooltip: 'Edit server setup',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              if (host.working || host.phase == ServerPhase.preparing) ...[
                const SizedBox(height: 18),
                LinearProgressIndicator(value: host.progress),
                const SizedBox(height: 9),
                Text(
                  host.progressLabel,
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.memory_rounded,
                  label: 'PROCESS MEMORY',
                  value: host.rssMb == null ? '—' : '${host.rssMb!.round()} MB',
                  detail: '${host.profile.memoryMb} MB heap limit',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Metric(
                  icon: Icons.speed_rounded,
                  label: 'CPU USAGE',
                  value: host.cpu == null
                      ? '—'
                      : '${host.cpu!.toStringAsFixed(1)}%',
                  detail: '100% = one CPU core',
                ),
              ),
            ],
          ),
        ),
        if (!Platform.isAndroid && !Platform.isLinux)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Live process measurements are available on Android and Linux.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lan_outlined, color: mint, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Join on your network',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.wifi, size: 18, color: muted),
                ],
              ),
              const SizedBox(height: 14),
              SelectableText(
                host.lanAddresses.isEmpty
                    ? 'No local network detected'
                    : '${host.lanAddresses.first}:${host.serverPort}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use the configured server port if you change it in Settings. For friends outside your Wi-Fi, set up a Playit tunnel in Network.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Text(
              'ACTIVITY',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 1.6,
                color: muted,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onConsole,
              child: const Text(
                'Open console →',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in host.logs.reversed.take(3).toList().reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.timestamp,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          line.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              if (host.logs.isEmpty)
                Text(
                  ready
                      ? 'Your server is ready to start.'
                      : 'Set up your first world to get started.',
                  style: const TextStyle(color: muted),
                ),
            ],
          ),
        ),
        const Center(
          child: Text(
            'LOCAL HARDWARE. LIMITLESS STORIES.',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.8,
              color: Color(0xff6d8277),
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });
  final IconData icon;
  final String label, value, detail;
  @override
  Widget build(BuildContext context) => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: muted, size: 22),
        const SizedBox(height: 14),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: muted, letterSpacing: .8),
        ),
        const SizedBox(height: 7),
        FittedBox(
          child: Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 5),
        Text(detail, style: const TextStyle(fontSize: 10, color: muted)),
      ],
    ),
    padding: const EdgeInsets.all(16),
  );
}

Future<void> showSetup(BuildContext context, HostController host) async {
  final name = TextEditingController(text: host.profile.name);
  final contact = TextEditingController(text: host.profile.contact);
  var engine = host.profile.engine;
  var version = host.profile.version;
  var memory = host.profile.memoryMb.toDouble();
  var eula = host.profile.eulaAccepted;
  final form = GlobalKey<FormState>();
  final result = await showDialog<ServerProfile>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Create your corner of Minecraft'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Server name'),
                    maxLength: 40,
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Give your server a name' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ServerEngine>(
                    isExpanded: true,
                    initialValue: engine,
                    decoration: const InputDecoration(
                      labelText: 'Server software',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ServerEngine.vanilla,
                        child: Text('Vanilla · official Mojang server'),
                      ),
                      DropdownMenuItem(
                        value: ServerEngine.paper,
                        child: Text('Paper · plugins & performance'),
                      ),
                    ],
                    onChanged: (v) => set(() => engine = v!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: version,
                    decoration: const InputDecoration(
                      labelText: 'Minecraft version',
                    ),
                    items: const ['1.21.1', '1.20.4']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => set(() => version = v!),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Each software/version pair uses a separate world folder. These initial versions run on Java 21.',
                    style: TextStyle(fontSize: 11, color: muted, height: 1.5),
                  ),
                  if (engine == ServerEngine.paper) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: contact,
                      decoration: const InputDecoration(
                        labelText: 'Contact email or project URL',
                        helperText: 'Required by the Paper download API',
                      ),
                      validator: (v) =>
                          v == null ||
                              !(v.contains('@') || v.startsWith('https://'))
                          ? 'Enter your contact email or HTTPS project URL'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Memory allocation  ·  ${(memory / 1024).toStringAsFixed(1)} GB',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    value: memory,
                    min: 1024,
                    max: 4096,
                    divisions: 6,
                    onChanged: (v) => set(() => memory = v),
                  ),
                  const Text(
                    'Leave memory for Android and other apps. Start with 1–2 GB on a phone.',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: eula,
                    onChanged: (v) => set(() => eula = v!),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I have read and agree to the Minecraft EULA.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        openLink(context, 'https://www.minecraft.net/eula'),
                    child: const Text('Read the Minecraft EULA ↗'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: eula
                ? () {
                    if (form.currentState!.validate()) {
                      Navigator.pop(
                        context,
                        ServerProfile(
                          name: name.text.trim(),
                          engine: engine,
                          version: version,
                          memoryMb: memory.round(),
                          eulaAccepted: eula,
                          contact: contact.text.trim(),
                        ),
                      );
                    }
                  }
                : null,
            child: const Text('Save setup'),
          ),
        ],
      ),
    ),
  );
  // Controllers belong to the dialog route until its closing animation finishes.
  if (result != null) await host.action(() => host.configure(result));
}

class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key, required this.host});
  final HostController host;
  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final command = TextEditingController();
  final scroll = ScrollController();
  bool follow = true;
  String filter = 'all';
  @override
  void dispose() {
    command.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final logs = host.logs
        .where((l) => filter == 'all' || l.source == filter)
        .toList();
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Live console',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Copy visible logs',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: logs
                          .map((l) => '[${l.timestamp}] ${l.text}')
                          .join('\n'),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_outlined, size: 20),
              ),
              IconButton(
                tooltip: follow ? 'Pause auto-scroll' : 'Follow output',
                onPressed: () => setState(() => follow = !follow),
                icon: Icon(
                  follow ? Icons.vertical_align_bottom : Icons.pause,
                  color: follow ? mint : muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              DropdownButton<String>(
                value: filter,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 12, color: muted),
                items: const ['all', 'server', 'playit', 'error']
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v == 'all' ? 'All output' : v),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => filter = v!),
              ),
              const Spacer(),
              Text(
                '${logs.length} lines',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xff070e0c),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xff2b3b33)),
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Server output will appear here.',
                        style: TextStyle(color: muted),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        final l = logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: Color(0xff53675b),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  '${l.timestamp}  ${l.text}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    height: 1.5,
                                    color: l.source == 'error'
                                        ? const Color(0xffffb4ab)
                                        : l.source == 'playit'
                                        ? const Color(0xffa6c8ef)
                                        : const Color(0xffbdd9c7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: command,
            enabled: host.active && host.phase != ServerPhase.stopping,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.chevron_right, color: mint),
              hintText: host.active
                  ? 'Enter a server command…'
                  : 'Start your server to send commands',
              suffixIcon: IconButton(
                tooltip: 'Send command',
                onPressed: host.active && !host.working ? _send : null,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try: list   ·   say Hello, world!   ·   op YourUsername',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ),
    );
  }

  void _send() {
    final text = command.text.trim();
    if (text.isEmpty) return;
    command.clear();
    widget.host.command(text);
  }
}

class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key, required this.host});
  final HostController host;
  @override
  Widget build(BuildContext context) {
    final tunnel = host.tunnel;
    return PageBody(
      children: [
        heading(
          'Beyond your Wi-Fi',
          'Invite the whole crew.',
          'Connect your server with Playit. No router configuration.',
        ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.public, color: mint, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Playit tunnel',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    tunnel?.running == true ? 'AGENT RUNNING' : 'DISCONNECTED',
                    style: const TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Start your Minecraft server, then connect the agent. The first connection asks you to link your Playit account.',
                style: TextStyle(color: muted, height: 1.5, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    host.working ||
                        tunnel == null ||
                        tunnel.busy ||
                        !host.active
                    ? null
                    : () => host.action(
                        tunnel.running ? tunnel.stop : tunnel.start,
                      ),
                icon: Icon(
                  tunnel?.running == true ? Icons.link_off : Icons.link,
                ),
                label: Text(
                  tunnel?.running == true
                      ? 'Disconnect agent'
                      : 'Connect Playit',
                ),
              ),
              if (tunnel?.claimUrl != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => openLink(context, tunnel!.claimUrl!),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Link this agent to Playit'),
                ),
              ],
              if (tunnel?.busy == true) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ONE-TIME CONNECTION',
                style: TextStyle(color: mint, fontSize: 10, letterSpacing: 1.5),
              ),
              const SizedBox(height: 18),
              _step(
                '1',
                'Link your account',
                'Open the agent link above and approve it in Playit.',
              ),
              _step(
                '2',
                'Add a Minecraft Java tunnel',
                'In the Playit dashboard, choose this agent and point the tunnel to 127.0.0.1 and your server port (default 25565).',
              ),
              _step(
                '3',
                'Share your public address',
                'The address appears below after creating the tunnel. Friends use this address in Minecraft Java Edition.',
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    openLink(context, 'https://playit.gg/account/tunnels'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Playit dashboard'),
              ),
            ],
          ),
        ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PUBLIC ADDRESS',
                style: TextStyle(
                  fontSize: 10,
                  color: muted,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                tunnel?.address ?? 'Waiting for a configured tunnel',
                style: TextStyle(
                  fontSize: tunnel?.address == null ? 14 : 19,
                  fontFamily: 'monospace',
                  color: tunnel?.address == null ? muted : mint,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Updates automatically while connected',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                  if (tunnel?.address != null)
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: tunnel!.address!),
                      ),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                ],
              ),
              const Text(
                'An agent running does not confirm public connectivity. Check the tunnel target in Playit and test joining from another network.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _step(String n, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xff2d4637),
          child: Text(n, style: const TextStyle(color: mint, fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.host});
  final HostController host;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final form = GlobalKey<FormState>();
  final motd = TextEditingController();
  final players = TextEditingController();
  final port = TextEditingController();
  Map<String, String>? values;
  String? loadError;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.host.server == null) return;
    try {
      final v = await widget.host.readSettings();
      if (!mounted) return;
      setState(() {
        values = v;
        motd.text = v['motd']!;
        players.text = v['max-players']!;
        port.text = v['server-port']!;
      });
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  @override
  void dispose() {
    motd.dispose();
    players.dispose();
    port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    if (values == null) {
      return Center(
        child: loadError != null
            ? Text(loadError!)
            : const CircularProgressIndicator(),
      );
    }
    return PageBody(
      children: [
        heading(
          'World controls',
          'Your server, your rules.',
          'Settings take effect the next time your server starts.',
        ),
        if (host.active)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Stop your server to edit its settings.',
              style: TextStyle(color: mint),
            ),
          ),
        Form(
          key: form,
          child: AbsorbPointer(
            absorbing: host.locked || saving,
            child: card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gameplay',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  _dropdown('gamemode', 'Game mode', [
                    'survival',
                    'creative',
                    'adventure',
                    'spectator',
                  ]),
                  const SizedBox(height: 16),
                  _dropdown('difficulty', 'Difficulty', [
                    'peaceful',
                    'easy',
                    'normal',
                    'hard',
                  ]),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: players,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Maximum players',
                    ),
                    validator: (v) => _number(v, 1, 100),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Server port'),
                    validator: (v) => _number(v, 1024, 65535),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: motd,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Message of the day',
                      helperText:
                          'Minecraft color codes use §, e.g. §aWelcome!',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xff0b1510),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text.rich(
                      TextSpan(children: _motdSpans(motd.text)),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Verify player accounts',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Online mode · recommended',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    value: values!['online-mode'] == 'true',
                    onChanged: (v) =>
                        setState(() => values!['online-mode'] = '$v'),
                  ),
                  if (values!['online-mode'] != 'true')
                    const Text(
                      'With verification disabled, players can impersonate usernames. Keep verification on for public servers.',
                      style: TextStyle(fontSize: 11, color: Color(0xffe9cf8f)),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Require allowlist',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Add players with: whitelist add Username',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    value: values!['white-list'] == 'true',
                    onChanged: (v) =>
                        setState(() => values!['white-list'] = '$v'),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: host.locked || saving ? null : _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(saving ? 'Saving…' : 'Save settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Runtime & storage',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                Platform.isAndroid
                    ? 'Android Java 21 is installed privately from this APK. Hosting uses a foreground notification and CPU wake lock. Android can still stop the app under memory pressure.'
                    : 'A portable Java runtime is downloaded into HostCraft storage. Your system Java configuration stays unchanged.',
                style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: host.locked ? null : host.checkJava,
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Check Java runtime'),
              ),
              const SizedBox(height: 14),
              const Text(
                'SERVER FILES',
                style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.5),
              ),
              const SizedBox(height: 6),
              SelectableText(
                host.server?.directory.path ?? '',
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: muted,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'HostCraft',
                  applicationVersion: '0.1.0',
                ),
                child: const Text('Open-source licenses'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dropdown(String key, String label, List<String> options) =>
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: options.contains(values![key])
            ? values![key]
            : options.first,
        decoration: InputDecoration(labelText: label),
        items: options
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text('${v[0].toUpperCase()}${v.substring(1)}'),
              ),
            )
            .toList(),
        onChanged: (v) => values![key] = v!,
      );
  String? _number(String? text, int min, int max) {
    final n = int.tryParse(text ?? '');
    return n == null || n < min || n > max
        ? 'Enter a number from $min to $max'
        : null;
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    await widget.host.action(() async {
      await widget.host.saveSettings({
        ...values!,
        'motd': motd.text,
        'max-players': players.text,
        'server-port': port.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    });
    if (mounted) setState(() => saving = false);
  }
}

List<TextSpan> _motdSpans(String text) {
  const colors = [
    Color(0xff000000),
    Color(0xff0000aa),
    Color(0xff00aa00),
    Color(0xff00aaaa),
    Color(0xffaa0000),
    Color(0xffaa00aa),
    Color(0xffffaa00),
    Color(0xffaaaaaa),
    Color(0xff555555),
    Color(0xff5555ff),
    Color(0xff55ff55),
    Color(0xff55ffff),
    Color(0xffff5555),
    Color(0xffff55ff),
    Color(0xffffff55),
    Color(0xffffffff),
  ];
  final spans = <TextSpan>[];
  var color = Colors.white;
  var bold = false;
  var buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) {
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: TextStyle(
            color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }
    buffer = StringBuffer();
  }

  for (var i = 0; i < text.length; i++) {
    if (text[i] == '§' && i + 1 < text.length) {
      flush();
      final code = text[++i].toLowerCase();
      final index = int.tryParse(code, radix: 16);
      if (index != null) {
        color = colors[index];
        bold = false;
      } else if (code == 'l') {
        bold = true;
      } else if (code == 'r') {
        color = Colors.white;
        bold = false;
      }
    } else {
      buffer.write(text[i]);
    }
  }
  flush();
  return spans;
}
