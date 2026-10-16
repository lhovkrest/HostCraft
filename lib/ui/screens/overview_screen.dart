import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/host_controller.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'setup_dialog.dart';

class Overview extends StatelessWidget {
  const Overview({super.key, required this.host, required this.onConsole});
  final HostController host;
  final VoidCallback onConsole;
  @override
  Widget build(BuildContext context) {
    final c = context.hc;
    final ready = host.phase != ServerPhase.idle;
    final soft = c.text.withValues(alpha: .72);
    return PageBody(
      children: [
        const SectionHeading(
          eyebrow: 'Your personal server room',
          title: 'Make room for adventure.',
          subtitle: 'Host a Minecraft world. Bring your friends along.',
        ),
        FlatCard(
          color: c.accentSoft,
          borderColor: Colors.transparent,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.grass_rounded, color: c.accent, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MINECRAFT JAVA',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                        color: soft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PhaseBadge(host.phase),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                host.profile.name,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${host.profile.engine == ServerEngine.paper ? 'Paper' : 'Vanilla'} ${host.profile.version}  ·  Java 21  ·  ${gigabytes(host.profile.memoryMb)} GB heap',
                style: TextStyle(color: soft, fontSize: 13),
              ),
              const SizedBox(height: 20),
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
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: c.surface,
                      foregroundColor: c.text,
                      minimumSize: const Size(48, 48),
                    ),
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
                LinearProgressIndicator(
                  value: host.progress,
                  backgroundColor: c.surface,
                  color: c.accent,
                ),
                const SizedBox(height: 8),
                Text(
                  host.progressLabel,
                  style: TextStyle(fontSize: 12, color: soft),
                ),
              ],
            ],
          ),
        ),
        if (Platform.isAndroid && host.batteryUnrestricted == false)
          Notice(
            icon: Icons.battery_alert_outlined,
            text:
                'Android may pause your server when the screen is off. Allow background activity so friends are not dropped.',
            action: OutlinedButton(
              onPressed: host.requestBackgroundAccess,
              child: const Text('Allow background activity'),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.memory_rounded,
                label: 'Process memory',
                value: host.rssMb == null ? '—' : '${host.rssMb!.round()} MB',
                detail: '${host.profile.memoryMb} MB heap limit',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricTile(
                icon: Icons.speed_rounded,
                label: 'CPU usage',
                value: host.cpu == null
                    ? '—'
                    : '${host.cpu!.toStringAsFixed(1)}%',
                detail: '100% = one CPU core',
              ),
            ),
          ],
        ),
        if (!Platform.isAndroid && !Platform.isLinux)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Live process measurements are available on Android and Linux.',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ),
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lan_outlined, color: c.accent, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Join on your network',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(Icons.wifi, size: 18, color: c.muted),
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
              Text(
                'Use the configured server port if you change it in Settings. For friends outside your Wi-Fi, connect Playit in Network.',
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Eyebrow('Activity'),
              const Spacer(),
              TextButton(
                onPressed: onConsole,
                child: const Text('Open console →'),
              ),
            ],
          ),
        ),
        FlatCard(
          child: Column(
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
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: c.muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          line.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.4),
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
                  style: TextStyle(color: c.muted),
                ),
            ],
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'LOCAL HARDWARE. LIMITLESS STORIES.',
              style: TextStyle(fontSize: 10, letterSpacing: 1.6, color: c.muted),
            ),
          ),
        ),
      ],
    );
  }
}
