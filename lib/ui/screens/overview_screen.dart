import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/host_controller.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../world_settings_page.dart';
import 'setup_dialog.dart';
import 'server_guide_screen.dart';

class Overview extends StatelessWidget {
  const Overview({
    super.key,
    required this.host,
    required this.onConsole,
    required this.onNetwork,
  });
  final HostController host;
  final VoidCallback onConsole, onNetwork;

  @override
  Widget build(BuildContext context) {
    final c = context.hc;
    final address = host.lanAddresses.isEmpty
        ? null
        : '${host.lanAddresses.first}:${host.serverPort}';
    return PageBody(
      children: [
        const SectionHeading(
          eyebrow: 'Your world. Your hardware.',
          title: 'Make room for adventure.',
          subtitle: 'A little control room for your next big world.',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ServerGuideScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      color: c.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your first server, step by step',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'A guide from choosing software to inviting friends.',
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: c.muted, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
        _ServerCard(host: host, onConsole: onConsole),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final tiles = [
              MetricTile(
                icon: Icons.memory_rounded,
                label: 'Process memory',
                value: host.rssMb == null ? '—' : '${host.rssMb!.round()} MB',
                detail: '${gigabytes(host.profile.memoryMb)} GB heap limit',
              ),
              MetricTile(
                icon: Icons.speed_rounded,
                label: 'CPU usage',
                value: host.cpu == null
                    ? '—'
                    : '${host.cpu!.toStringAsFixed(1)}%',
                detail: '100% = one CPU core',
              ),
              MetricTile(
                icon: Icons.dns_outlined,
                label: 'Server software',
                value: host.profile.engine.label,
                detail: 'Minecraft ${host.profile.version}',
              ),
            ];
            if (constraints.maxWidth < 620) {
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: tiles[0]),
                      const SizedBox(width: 12),
                      Expanded(child: tiles[1]),
                    ],
                  ),
                  tiles[2],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            );
          },
        ),
        if (!Platform.isAndroid && !Platform.isLinux)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              'Live process measurements are available on Android and Linux.',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ),
        if (Platform.isAndroid && host.batteryUnrestricted == false)
          Notice(
            icon: Icons.battery_alert_outlined,
            text: 'Allow background activity to keep your server running when the screen is off.',
            action: OutlinedButton(
              onPressed: host.requestBackgroundAccess,
              child: const Text('Allow background activity'),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final network = FlatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardTitle(
                    icon: Icons.lan_outlined,
                    title: 'Bring your friends',
                  ),
                  const SizedBox(height: 16),
                  const Eyebrow('Local address'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            address ?? 'No local network detected',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: c.text,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy local address',
                          onPressed: address == null
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: address),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Local address copied'),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.copy_outlined, size: 17),
                        ),
                      ],
                    ),
                  ),
                  if (host.profile.crossplay &&
                      host.lanAddresses.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SelectableText(
                      'Bedrock: ${host.lanAddresses.first}:${host.profile.bedrockPort} (UDP)',
                      style: TextStyle(color: c.accent, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Same Wi-Fi? Join with this address while the server is online.',
                    style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: onNetwork,
                    icon: const Icon(Icons.public, size: 17),
                    label: const Text('Connect with Playit'),
                  ),
                ],
              ),
            );
            final worlds = FlatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardTitle(
                    icon: Icons.landscape_outlined,
                    title: 'Worlds & backups',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Keep your next adventure safe.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: c.text,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Fine-tune your world, import a favorite save, or make a backup before trying something new.',
                    style: TextStyle(color: c.muted, fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const WorldSettingsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Manage worlds'),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 740) {
              return Column(children: [network, worlds]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: network),
                const SizedBox(width: 16),
                Expanded(child: worlds),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: _CardTitle(
                icon: Icons.history_rounded,
                title: 'Recent activity',
              ),
            ),
            TextButton.icon(
              onPressed: onConsole,
              icon: const Icon(Icons.arrow_outward, size: 16),
              label: const Text('Console'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FlatCard(
          color: c.consoleBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in host.logs.reversed.take(3).toList().reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.timestamp,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: c.muted,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          line.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.5,
                            color: line.source == 'error'
                                ? c.danger
                                : c.consoleText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (host.logs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    host.phase == ServerPhase.idle
                        ? 'Your story starts here. Set up a server to see its activity.'
                        : 'All quiet. Your server is ready to start.',
                    style: TextStyle(color: c.muted, height: 1.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: context.hc.accent, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.host, required this.onConsole});
  final HostController host;
  final VoidCallback onConsole;
  @override
  Widget build(BuildContext context) {
    final c = context.hc;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xff1b3b36), Color(0xff162931), Color(0xff172332)]
              : const [Color(0xffd7f0e2), Color(0xffe6f2ed), Color(0xffe2edf7)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.accent.withValues(alpha: .24)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final illustrated = constraints.maxWidth >= 680;
          return Stack(
            children: [
              if (illustrated)
                Positioned(
                  right: -8,
                  top: 6,
                  bottom: 0,
                  width: 300,
                  child: ExcludeSemantics(
                    child: CustomPaint(painter: _WorldPainter(dark)),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(constraints.maxWidth < 420 ? 20 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.grass_rounded, color: c.accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'MINECRAFT JAVA',
                            style: TextStyle(
                              color: c.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ),
                        PhaseBadge(host.phase),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Padding(
                      padding: EdgeInsets.only(right: illustrated ? 245 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            host.profile.name,
                            style: TextStyle(
                              fontSize: illustrated ? 30 : 25,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -.8,
                              color: c.text,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            switch (host.phase) {
                              ServerPhase.running => 'Your world is online. Let the good times roll.',
                              ServerPhase.starting =>
                                'Your world is waking up. Almost there.',
                              ServerPhase.stopping =>
                                'Saving your world and stopping the server.',
                              ServerPhase.preparing =>
                                'Getting everything ready for your world.',
                              ServerPhase.failed => 'Something went wrong. Check the console for details.',
                              _ => 'One server. Endless possibilities.',
                            },
                            style: TextStyle(
                              color: c.muted,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    host.working ||
                                        host.phase == ServerPhase.preparing ||
                                        host.phase == ServerPhase.stopping
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
                              if (constraints.maxWidth < 420)
                                IconButton.outlined(
                                  tooltip: 'Open console',
                                  onPressed: onConsole,
                                  icon: const Icon(Icons.terminal, size: 20),
                                )
                              else
                                OutlinedButton.icon(
                                  onPressed: onConsole,
                                  icon: const Icon(Icons.terminal, size: 18),
                                  label: const Text('Console'),
                                ),
                              IconButton(
                                tooltip: 'Edit server setup',
                                onPressed: host.locked
                                    ? null
                                    : () => showSetup(context, host),
                                icon: const Icon(Icons.tune, size: 20),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (host.working ||
                        host.phase == ServerPhase.preparing) ...[
                      const SizedBox(height: 18),
                      LinearProgressIndicator(
                        value: host.progress,
                        backgroundColor: c.surface,
                        color: c.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        host.progressLabel,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Small, resolution-independent block world. Decorative, never a status chart.
class _WorldPainter extends CustomPainter {
  _WorldPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height * .56);
    canvas.scale(.94);
    final line = Paint()
      ..color = (dark ? Colors.white : const Color(0xff38756b)).withValues(
        alpha: .07,
      )
      ..strokeWidth = 1;
    for (var i = -5; i <= 5; i++) {
      canvas.drawLine(
        Offset(-150, i * 24.0),
        Offset(150, i * 24.0 - 100),
        line,
      );
      canvas.drawLine(
        Offset(-150, i * 24.0 - 100),
        Offset(150, i * 24.0),
        line,
      );
    }
    void face(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff142d30).withValues(alpha: .16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
    }

    void block(double x, double y, double width, double height, Color top) {
      final w = width / 2;
      final d = width / 4;
      face([
        Offset(x - w, y),
        Offset(x, y + d),
        Offset(x, y + d + height),
        Offset(x - w, y + height),
      ], Color.lerp(top, const Color(0xff153b3c), .57)!);
      face([
        Offset(x, y + d),
        Offset(x + w, y),
        Offset(x + w, y + height),
        Offset(x, y + d + height),
      ], Color.lerp(top, const Color(0xff10272e), .72)!);
      face([
        Offset(x, y - d),
        Offset(x + w, y),
        Offset(x, y + d),
        Offset(x - w, y),
      ], top);
    }

    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        final x = (col - row) * 28.0;
        final y = (col + row) * 14.0 - 48;
        block(
          x,
          y,
          56,
          44 + (row % 2) * 8,
          (row + col) % 3 == 0
              ? const Color(0xff74c391)
              : const Color(0xff56a881),
        );
      }
    }
    block(0, -56, 56, 30, const Color(0xff8cdaa2));
    block(0, -90, 12, 38, const Color(0xff9a8661));
    block(0, -108, 55, 32, const Color(0xff5cc28d));
    block(0, -132, 38, 22, const Color(0xff91e2ad));
    block(107, 52, 30, 18, const Color(0xff6cbcaf));
    block(-110, 20, 22, 16, const Color(0xff8dc2bd));
    final sparkle = Paint()
      ..color = dark ? const Color(0xffa2edcf) : const Color(0xff4d8c77)
      ..strokeWidth = 1.5;
    for (final p in const [
      Offset(100, -68),
      Offset(-96, -76),
      Offset(65, -118),
    ]) {
      canvas.drawLine(p - const Offset(4, 0), p + const Offset(4, 0), sparkle);
      canvas.drawLine(p - const Offset(0, 4), p + const Offset(0, 4), sparkle);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WorldPainter oldDelegate) => oldDelegate.dark != dark;
}
