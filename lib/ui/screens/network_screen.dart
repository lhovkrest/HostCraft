import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/host_controller.dart';
import '../../services/tunnel_service.dart';
import '../theme.dart';
import '../widgets.dart';

class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key, required this.host});
  final HostController host;

  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hc;
    final tunnel = host.tunnel;
    final phase = tunnel?.phase ?? TunnelPhase.idle;
    final connected = tunnel?.connected == true;
    final busy = tunnel?.busy == true;
    final claimUrl = tunnel?.claimUrl;
    final address = tunnel?.address;

    final (pillLabel, pillColor) = switch (phase) {
      TunnelPhase.connected => ('CONNECTED', c.accent),
      TunnelPhase.linking => ('LINKING', c.warning),
      TunnelPhase.creating => ('CREATING', c.warning),
      TunnelPhase.starting => ('STARTING', c.warning),
      TunnelPhase.failed => ('FAILED', c.danger),
      TunnelPhase.idle => ('DISCONNECTED', c.muted),
    };
    final description = switch (phase) {
      TunnelPhase.idle =>
        host.active
            ? 'Connect once and HostCraft sets everything up with Playit. Friends can then join from anywhere.'
            : 'Start your Minecraft server first, then connect. HostCraft creates the Playit tunnel for you.',
      TunnelPhase.connected => 'Your tunnel is live. Share the public address below with your friends.',
      TunnelPhase.failed =>
        'The connection did not finish. Fix the problem below and try again.',
      _ => tunnel?.status ?? '',
    };

    return PageBody(
      children: [
        const SectionHeading(
          eyebrow: 'Beyond your Wi-Fi',
          title: 'Invite the whole crew.',
          subtitle: 'Connect your server with Playit. No router configuration.',
        ),
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public, color: c.accent, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Playit tunnel',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusPill(pillLabel, pillColor),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: TextStyle(color: c.muted, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (claimUrl != null)
                Notice(
                  icon: Icons.link,
                  color: c.info,
                  text: 'Playit needs your OK once. Open the link, sign in to Playit and approve HostCraft. This screen carries on by itself afterwards.',
                  action: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => openLink(context, claimUrl),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open Playit to approve'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _copy(context, claimUrl, 'Approval link copied'),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy link'),
                      ),
                    ],
                  ),
                ),
              if (tunnel?.error != null)
                Notice(
                  icon: Icons.error_outline,
                  color: c.danger,
                  text: tunnel!.error!,
                ),
              if (tunnel?.warning != null) Notice(text: tunnel!.warning!),
              if (busy) ...[
                LinearProgressIndicator(color: c.accent, minHeight: 3),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: connected
                    ? OutlinedButton.icon(
                        onPressed: () => tunnel!.stop(),
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                      )
                    : busy
                    ? OutlinedButton.icon(
                        onPressed: () => tunnel!.stop(),
                        icon: const Icon(Icons.close),
                        label: const Text('Stop connecting'),
                      )
                    : FilledButton.icon(
                        onPressed:
                            tunnel == null || !host.active || host.working
                            ? null
                            : () => tunnel.start(),
                        icon: const Icon(Icons.link),
                        label: Text(
                          phase == TunnelPhase.failed
                              ? 'Try again'
                              : 'Connect Playit',
                        ),
                      ),
              ),
            ],
          ),
        ),
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Java · TCP'),
              const SizedBox(height: 12),
              SelectableText(
                address ?? 'Not connected yet',
                style: TextStyle(
                  fontSize: address == null ? 15 : 20,
                  fontFamily: 'monospace',
                  color: address == null ? c.muted : c.accent,
                ),
              ),
              const SizedBox(height: 12),
              if (address != null)
                OutlinedButton.icon(
                  onPressed: () => _copy(context, address, 'Address copied'),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy address'),
                ),
              if (address != null) const SizedBox(height: 12),
              if (tunnel?.bedrockAddress != null) ...[
                const Divider(height: 28),
                const Eyebrow('Bedrock · UDP'),
                const SizedBox(height: 12),
                SelectableText(
                  tunnel!.bedrockAddress!,
                  style: TextStyle(
                    color: c.accent,
                    fontFamily: 'monospace',
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _copy(
                    context,
                    tunnel.bedrockAddress!,
                    'Bedrock address copied',
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Bedrock address'),
                ),
              ],
              if (tunnel?.bedrockNote != null)
                Notice(text: tunnel!.bedrockNote!),
              Text(
                'Connected means the agent is running and the tunnel exists on Playit. Try joining from another network to confirm it works end to end.',
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
        ),
        FlatCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('How it works'),
              const SizedBox(height: 16),
              const StepTile(
                number: '1',
                title: 'Approve once',
                body: 'The first connection opens a Playit link. Approve HostCraft there. The link is remembered on this device.',
              ),
              const StepTile(
                number: '2',
                title: 'Tunnel created for you',
                body: 'HostCraft asks Playit for a Minecraft Java tunnel that points at 127.0.0.1 and your server port. No dashboard setup is needed.',
              ),
              const StepTile(
                number: '3',
                title: 'Share the address',
                body: 'Friends enter the public address in Minecraft Java Edition.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        openLink(context, 'https://playit.gg/account/tunnels'),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open Playit dashboard'),
                  ),
                  if (tunnel != null && !busy && !tunnel.running)
                    TextButton.icon(
                      onPressed: host.working
                          ? null
                          : () async {
                              await host.unlinkPlayit();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Playit account unlinked'),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.link_off, size: 16),
                      label: const Text('Unlink Playit'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
