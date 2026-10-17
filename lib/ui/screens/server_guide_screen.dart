import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/host_controller.dart';
import '../server_setup_sheet.dart';
import '../setup_components.dart';
import '../theme.dart';
import '../widgets.dart';
import '../world_settings_page.dart';
import 'console_screen.dart';
import 'mods_screen.dart';
import 'network_screen.dart';

class ServerGuideScreen extends ConsumerStatefulWidget {
  const ServerGuideScreen({super.key});
  @override
  ConsumerState<ServerGuideScreen> createState() => _ServerGuideScreenState();
}

class _ServerGuideScreenState extends ConsumerState<ServerGuideScreen> {
  int selected = 0;
  static const steps = [
    (
      'Choose your experience',
      'Vanilla, plugins, or a world full of mods.',
      Icons.auto_awesome_rounded,
    ),
    (
      'Set the rules',
      'Name, version, memory and world settings.',
      Icons.tune_rounded,
    ),
    (
      'Add your extras',
      'Install compatible mods or plugins.',
      Icons.extension_rounded,
    ),
    (
      'Bring it online',
      'Start the server and watch the first launch.',
      Icons.play_arrow_rounded,
    ),
    (
      'Invite your friends',
      'Join locally or share a Playit address.',
      Icons.public_rounded,
    ),
    (
      'Keep your world safe',
      'Back up, update carefully and stop cleanly.',
      Icons.shield_outlined,
    ),
  ];

  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final c = context.hc;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Server guide',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: PageBody(
        children: [
          const SectionHeading(
            eyebrow: 'THE HOSTCRAFT FIELD GUIDE',
            title: 'From zero to first join.',
            subtitle: 'Six steps to a world of your own. Keep this guide handy while you build.',
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.accentSoft, c.surface]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.accent.withValues(alpha: .2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You bring the idea. We handle the setup.',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Have a Minecraft Java Edition account, an internet connection for downloads, and free storage for the server and backups. Your device must stay on while people play.',
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.7),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: host.locked
                      ? null
                      : () => showServerSetup(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Open server studio'),
                ),
              ],
            ),
          ),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: selected == i
                        ? c.accent.withValues(alpha: .5)
                        : c.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () =>
                          setState(() => selected = selected == i ? -1 : i),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected == i ? c.accent : c.surfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${i + 1}'.padLeft(2, '0'),
                                style: TextStyle(
                                  color: selected == i ? c.onAccent : c.muted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    steps[i].$1,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    steps[i].$2,
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              selected == i
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: c.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (selected == i)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 24),
                            ..._instructions(i, host),
                            if (i < steps.length - 1) ...[
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => selected = i + 1),
                                icon: const Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 16,
                                ),
                                label: const Text('Next step'),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const SetupTip(
            icon: Icons.help_outline_rounded,
            title: 'Something not working?',
            body: 'Check Console for the first error. A version mismatch usually means the client, loader or mods differ. If friends cannot join, confirm the server is online and the Playit tunnel is connected. If it runs out of memory, reduce mods or view distance before assigning more RAM.',
          ),
        ],
      ),
    );
  }

  Widget _instruction(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(
            Icons.arrow_right_rounded,
            color: context.hc.accent,
            size: 18,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: context.hc.muted,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _instructions(int index, HostController host) => switch (index) {
    0 => [
      _instruction(
        'Open Server studio. Pick Vanilla for the original game, or Paper for a server with plugins and regular Java clients.',
      ),
      _instruction(
        'Choose Fabric for Fabric mods, or Forge for Forge mods and modpacks. HostCraft currently hosts Forge on Windows, for Minecraft 1.18 and newer. Forge and Fabric mods are not interchangeable.',
      ),
      _instruction(
        'Purpur adds more gameplay settings. Folia is for advanced hosts and needs plugins that explicitly support it.',
      ),
      OutlinedButton.icon(
        onPressed: host.locked ? null : () => showServerSetup(context),
        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
        label: const Text('Choose server software'),
      ),
    ],
    1 => [
      _instruction(
        'In Details, name the server and choose the same Minecraft version as your players. Paper and Folia also require a contact email or project URL for downloads.',
      ),
      _instruction(
        'In Resources, choose memory within the device recommendation. Leave enough for your operating system and game. Use your modpack’s published requirements for a modded server.',
      ),
      _instruction(
        'Enable Bedrock crossplay only if you need it. HostCraft supports it on Paper, Purpur and Fabric. Review the setup, read and accept the Minecraft EULA, then save.',
      ),
      _instruction(
        'Open Worlds & backups to set the seed, game mode and difficulty before your first launch. Changing the seed after a world exists does not regenerate that world.',
      ),
      OutlinedButton.icon(
        onPressed: () => _open(const WorldSettingsPage()),
        icon: const Icon(Icons.landscape_outlined, size: 18),
        label: const Text('Open world settings'),
      ),
    ],
    2 => [
      _instruction(
        'This step is optional. While the server is stopped, open Mods & plugins. Search results match the selected software and Minecraft version.',
      ),
      _instruction(
        'For a Forge or Fabric server, install compatible server-side mods. Players need the same gameplay mods and loader; client-only visual mods usually belong only in the player’s game.',
      ),
      _instruction(
        'Modrinth works without a key. CurseForge requires a catalog API key: use the key icon in Mods & plugins. To install a local jar, put it in the server’s mods or plugins folder using Server files.',
      ),
      _instruction(
        'A modpack ZIP is not a world backup. Follow the pack author’s server instructions and use the matching Minecraft and Forge version. HostCraft chooses the recommended Forge build, or latest when there is no recommended build.',
      ),
      OutlinedButton.icon(
        onPressed: () => _open(const ModsScreen()),
        icon: const Icon(Icons.extension_outlined, size: 18),
        label: const Text('Browse mods & plugins'),
      ),
    ],
    3 => [
      _instruction(
        'Choose Start server. The first launch downloads Java and server files. Forge also runs its official installer and downloads its libraries; this can take several minutes.',
      ),
      _instruction(
        'Open Console to follow progress. Wait for ONLINE and the server’s “Done” message before joining. If crossplay asks for a restart after its first setup, stop and start once.',
      ),
      _instruction(
        'On the hosting Windows PC, open Minecraft Java Edition → Multiplayer → Add Server. Use localhost and your server port (normally localhost:25565). Keep HostCraft open while playing.',
      ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: !host.profile.eulaAccepted || host.locked
                ? null
                : host.start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start server'),
          ),
          OutlinedButton.icon(
            onPressed: () => _open(
              Consumer(
                builder: (_, ref, _) =>
                    ConsoleScreen(host: ref.watch(hostProvider)),
              ),
            ),
            icon: const Icon(Icons.terminal_rounded, size: 18),
            label: const Text('Open console'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      PhaseBadge(host.phase),
    ],
    4 => [
      _instruction(
        'On the same Wi-Fi, share the local address from Overview, including the port. Allow Java through the Windows firewall on your private network if Windows asks.',
      ),
      _instruction(
        'For friends elsewhere, keep the server running and open Network. Connect Playit, open its approval link and approve the agent. Return to HostCraft and wait for CONNECTED.',
      ),
      _instruction(
        'Copy the public Java address from Network. Bedrock players need the Bedrock address and UDP port shown there when crossplay is enabled; the Java address is not a Bedrock endpoint.',
      ),
      _instruction(
        'Friends must use a compatible Minecraft version and, for modded servers, the matching loader and gameplay mods. Consider enabling the allowlist in Settings before sharing widely.',
      ),
      OutlinedButton.icon(
        onPressed: () => _open(
          Consumer(
            builder: (_, ref, _) =>
                NetworkScreen(host: ref.watch(hostProvider)),
          ),
        ),
        icon: const Icon(Icons.public_rounded, size: 18),
        label: const Text('Open network'),
      ),
    ],
    _ => [
      _instruction(
        'Use Stop server and wait for it to go offline before changing mods, importing worlds or making backups. This lets Minecraft finish saving.',
      ),
      _instruction(
        'Make a backup in Worlds & backups before changing versions or mods. Keep a copy outside the server folder. A world backup does not include your entire modpack or every server configuration file.',
      ),
      _instruction(
        'Changing software or Minecraft version selects a different server folder. Back up and import your world deliberately; avoid downgrading worlds because older versions may not understand newer data.',
      ),
      _instruction(
        'Keep your host powered on and connected while friends are playing. On Android, allow background activity so the system does not pause hosting.',
      ),
      OutlinedButton.icon(
        onPressed: () => _open(const WorldSettingsPage()),
        icon: const Icon(Icons.backup_outlined, size: 18),
        label: const Text('Manage backups'),
      ),
    ],
  };
}
