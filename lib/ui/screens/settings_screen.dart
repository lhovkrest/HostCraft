import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/host_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import '../world_settings_page.dart';
import '../server_setup_sheet.dart';

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
    final c = context.hc;
    if (values == null) {
      return Center(
        child: loadError != null
            ? Text(loadError!)
            : const CircularProgressIndicator(),
      );
    }
    return PageBody(
      children: [
        const SectionHeading(
          eyebrow: 'Preferences',
          title: 'Your server, your rules.',
          subtitle: 'Settings take effect the next time your server starts.',
        ),
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Appearance',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {host.themeMode},
                  onSelectionChanged: (selection) =>
                      host.setThemeMode(selection.first),
                ),
              ),
            ],
          ),
        ),
        FlatCard(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.dns_outlined, color: c.accent),
                title: const Text('Server software & crossplay'),
                trailing: const Icon(Icons.chevron_right),
                onTap: host.locked ? null : () => showServerSetup(context),
              ),
              ListTile(
                leading: Icon(Icons.folder_outlined, color: c.accent),
                title: const Text('World settings & backups'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WorldSettingsPage()),
                ),
              ),
            ],
          ),
        ),
        if (host.active)
          Notice(
            icon: Icons.lock_outline,
            color: c.accent,
            text: 'Stop your server to edit its settings.',
          ),
        Form(
          key: form,
          child: AbsorbPointer(
            absorbing: host.locked || saving,
            child: FlatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connection & access',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: players,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Maximum players',
                    ),
                    validator: (v) => _number(v, 1, 100),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Server port'),
                    validator: (v) => _number(v, 1024, 65535),
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xff1b1b1b),
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
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Verify player accounts',
                      style: TextStyle(fontSize: 15),
                    ),
                    subtitle: Text(
                      'Online mode · recommended',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    value: values!['online-mode'] == 'true',
                    onChanged: (v) =>
                        setState(() => values!['online-mode'] = '$v'),
                  ),
                  if (values!['online-mode'] != 'true')
                    Notice(
                      text: 'With verification disabled, players can impersonate usernames. Keep verification on for public servers.',
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Require allowlist',
                      style: TextStyle(fontSize: 15),
                    ),
                    subtitle: Text(
                      'Add players with: whitelist add Username',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    value: values!['white-list'] == 'true',
                    onChanged: (v) =>
                        setState(() => values!['white-list'] = '$v'),
                  ),
                  const SizedBox(height: 14),
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
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Runtime & storage',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                host.ramDetected
                    ? 'This device has ${gigabytes(host.deviceRamMb)} GB of RAM. Your server may use up to ${gigabytes(host.maxMemoryMb)} GB; ${gigabytes(host.recommendedMemoryMb)} GB or less is recommended. The server currently uses a ${gigabytes(host.profile.memoryMb)} GB heap, which you can change in the server setup.'
                    : 'HostCraft could not read this device\'s RAM. The server currently uses a ${gigabytes(host.profile.memoryMb)} GB heap, which you can change in the server setup.',
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 12),
              Text(
                Platform.isAndroid
                    ? 'Android Java 21 is installed privately from this APK. Hosting uses a foreground notification and CPU wake lock. Android can still stop the app under memory pressure.'
                    : 'A portable Java runtime is downloaded into HostCraft storage. Your system Java configuration stays unchanged.',
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.6),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      host.batteryUnrestricted == false
                          ? Icons.battery_alert_outlined
                          : Icons.battery_charging_full_outlined,
                      size: 20,
                      color: host.batteryUnrestricted == false
                          ? c.warning
                          : c.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        host.batteryUnrestricted == false
                            ? 'Background activity is restricted'
                            : 'Background activity allowed',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                if (host.batteryUnrestricted == false) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: host.requestBackgroundAccess,
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    label: const Text('Allow background activity'),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: host.locked ? null : host.checkJava,
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Check Java runtime'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: host.locked ? null : host.updateServerFiles,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Update server files'),
              ),
              const SizedBox(height: 16),
              const Eyebrow('Server files'),
              const SizedBox(height: 6),
              SelectableText(
                host.server?.directory.path ?? '',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'HostCraft',
                  applicationVersion: appVersion,
                ),
                child: const Text('Open-source licenses'),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
        'online-mode': values!['online-mode']!,
        'white-list': values!['white-list']!,
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
