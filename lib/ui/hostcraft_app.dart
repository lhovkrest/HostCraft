import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/exit_service.dart';
import '../core/host_controller.dart';
import '../core/models.dart';
import 'screens/console_screen.dart';
import 'screens/files_screen.dart';
import 'screens/mods_screen.dart';
import 'screens/network_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/server_guide_screen.dart';
import 'server_setup_sheet.dart';
import 'theme.dart';
import 'widgets.dart';
import 'world_settings_page.dart';

final ThemeData _lightTheme = buildTheme(Brightness.light);
final ThemeData _darkTheme = buildTheme(Brightness.dark);

class HostCraftApp extends ConsumerWidget {
  const HostCraftApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(hostProvider).themeMode;
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'HostCraft',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: mode,
      home: const HostShell(),
    );
  }
}

class HostShell extends ConsumerStatefulWidget {
  const HostShell({super.key});
  @override
  ConsumerState<HostShell> createState() => _HostShellState();
}

class _HostShellState extends ConsumerState<HostShell> {
  int selected = 0;
  static const labels = ['Overview', 'Console', 'Network', 'Settings'];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.terminal_rounded,
    Icons.public_rounded,
    Icons.tune_rounded,
  ];

  void _openTool(String tool) {
    final page = switch (tool) {
      'Server guide' => const ServerGuideScreen(),
      'Worlds & backups' => const WorldSettingsPage(),
      'Mods & plugins' => const ModsScreen(),
      _ => const FilesScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final c = context.hc;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width > 850;
    final screens = [
      Overview(
        host: host,
        onConsole: () => setState(() => selected = 1),
        onNetwork: () => setState(() => selected = 2),
      ),
      ConsoleScreen(host: host),
      NetworkScreen(host: host),
      SettingsScreen(key: ValueKey(host.profile.key), host: host),
    ];
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 232,
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(right: BorderSide(color: c.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 26, 20, 32),
                      child: _Brand(),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(26, 0, 0, 12),
                      child: Eyebrow('Workspace'),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            IntrinsicHeight(
                              child: NavigationRail(
                                extended: true,
                                minExtendedWidth: 230,
                                selectedIndex: selected,
                                onDestinationSelected: (i) =>
                                    setState(() => selected = i),
                                destinations: [
                                  for (var i = 0; i < labels.length; i++)
                                    NavigationRailDestination(
                                      icon: Icon(icons[i]),
                                      label: Text(labels[i]),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(26, 30, 0, 12),
                              child: Eyebrow('Manage'),
                            ),
                            for (final tool in const [
                              ('Server guide', Icons.auto_stories_outlined),
                              ('Worlds & backups', Icons.landscape_outlined),
                              ('Mods & plugins', Icons.extension_outlined),
                              ('Server files', Icons.folder_outlined),
                            ])
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 2,
                                ),
                                child: Material(
                                  color: c.surface,
                                  child: ListTile(
                                    enabled: host.loaded,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    leading: Icon(
                                      tool.$2,
                                      size: 20,
                                      color: c.muted,
                                    ),
                                    title: Text(
                                      tool.$1,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: c.muted,
                                      ),
                                    ),
                                    onTap: () => _openTool(tool.$1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.dns_outlined,
                                  color: c.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Your local server',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              host.profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.muted, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            PhaseBadge(host.phase),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.border)),
                    ),
                    child: Row(
                      children: [
                        if (wide) ...[
                          Icon(icons[selected], size: 18, color: c.muted),
                          const SizedBox(width: 10),
                          Text(
                            labels[selected],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 14),
                          Text('/', style: TextStyle(color: c.border)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              host.profile.engine.label,
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ),
                        ] else
                          const Expanded(child: _Brand()),
                        IconButton(
                          tooltip: dark
                              ? 'Switch to light mode'
                              : 'Switch to dark mode',
                          onPressed: () => host.setThemeMode(
                            dark ? ThemeMode.light : ThemeMode.dark,
                          ),
                          icon: Icon(
                            dark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            size: 20,
                          ),
                        ),
                        if (wide) ...[
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: !host.loaded || host.locked
                                ? null
                                : () => showServerSetup(context),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Server setup'),
                          ),
                        ] else
                          PopupMenuButton<String>(
                            tooltip: 'Server tools',
                            enabled: host.loaded,
                            onSelected: (value) {
                              if (value == 'Server setup') {
                                showServerSetup(context);
                              } else {
                                _openTool(value);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'Server setup',
                                enabled: !host.locked,
                                child: const Text('Server setup'),
                              ),
                              for (final tool in [
                                'Server guide',
                                'Worlds & backups',
                                'Mods & plugins',
                                'Server files',
                              ])
                                PopupMenuItem(value: tool, child: Text(tool)),
                            ],
                            icon: const Icon(Icons.more_horiz),
                          ),
                      ],
                    ),
                  ),
                  if (host.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Notice(
                        text: host.error!,
                        color: c.danger,
                        onClose: () {
                          host.error = null;
                          host.changed();
                        },
                      ),
                    ),
                  Expanded(
                    child: !host.loaded
                        ? const Center(child: CircularProgressIndicator())
                        : IndexedStack(index: selected, children: screens),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (i) => setState(() => selected = i),
                destinations: [
                  for (var i = 0; i < labels.length; i++)
                    NavigationDestination(
                      icon: Icon(icons[i]),
                      label: labels[i],
                    ),
                ],
              ),
            ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    final c = context.hc;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.accent, Color.lerp(c.accent, c.info, .4)!],
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.view_in_ar_rounded, color: c.onAccent, size: 22),
        ),
        const SizedBox(width: 10),
        const Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'HostCraft',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
