import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/host_controller.dart';
import '../../core/models.dart';
import '../theme.dart';

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
    final c = context.hc;
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Live console',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
                  color: follow ? c.accent : c.muted,
                ),
              ),
            ],
          ),
          Row(
            children: [
              DropdownButton<String>(
                value: filter,
                underline: const SizedBox(),
                dropdownColor: c.surface,
                style: TextStyle(fontSize: 13, color: c.muted),
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
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: c.consoleBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        'Server output will appear here.',
                        style: TextStyle(color: c.muted),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        final l = logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 30,
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: c.consoleLineNumber,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  '${l.timestamp}  ${l.text}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    height: 1.5,
                                    color: l.source == 'error'
                                        ? c.danger
                                        : l.source == 'playit'
                                        ? c.info
                                        : c.consoleText,
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
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.chevron_right, color: c.accent),
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
          Text(
            'Try: list   ·   say Hello, world!   ·   op YourUsername',
            style: TextStyle(fontSize: 11, color: c.muted),
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
