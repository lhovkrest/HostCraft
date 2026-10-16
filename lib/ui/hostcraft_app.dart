import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/host_controller.dart';
import 'screens/console_screen.dart';
import 'screens/network_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

final ThemeData _lightTheme = buildTheme(Brightness.light);
final ThemeData _darkTheme = buildTheme(Brightness.dark);

class HostCraftApp extends ConsumerWidget {
  const HostCraftApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(hostProvider).themeMode;
    return MaterialApp(
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
  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final c = context.hc;
    final dark = Theme.of(context).brightness == Brightness.dark;
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
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.view_in_ar_rounded, color: c.onAccent, size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'HostCraft',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: () =>
                host.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 4),
        ],
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
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          selectedIcon: Icon(Icons.dashboard),
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
                          child: IndexedStack(index: selected, children: screens),
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
                NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
              ],
            ),
    );
  }
}
