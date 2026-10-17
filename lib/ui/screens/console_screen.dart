import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/host_controller.dart';
import '../../core/models.dart';
import '../../core/progress.dart';
import '../theme.dart';
import '../widgets.dart';

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
  String query = '';
  bool searching = false;
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
        .where(
          (l) =>
              (filter == 'all' || l.source == filter) &&
              l.text.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width > 850 ? 32 : 20,
        24,
        MediaQuery.sizeOf(context).width > 850 ? 32 : 20,
        20,
      ),
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
                tooltip: 'Search logs',
                onPressed: () => setState(() {
                  searching = !searching;
                  if (!searching) query = '';
                }),
                icon: const Icon(Icons.search),
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
          Text(
            'A direct line to your world.',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (searching)
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search output...'),
              onChanged: (v) => setState(() => query = v),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final shortcut in ['stop', 'help', 'list', 'op'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 12),
                    child: OutlinedButton.icon(
                      style: shortcut == 'stop'
                          ? OutlinedButton.styleFrom(foregroundColor: c.danger)
                          : null,
                      onPressed:
                          !host.active ||
                              host.working ||
                              host.phase == ServerPhase.stopping
                          ? null
                          : () {
                              if (shortcut == 'stop') {
                                host.stop();
                              } else if (shortcut == 'op') {
                                command.text = 'op ';
                                command.selection = TextSelection.collapsed(
                                  offset: command.text.length,
                                );
                              } else {
                                host.command(shortcut);
                              }
                            },
                      icon: Icon(
                        shortcut == 'stop'
                            ? Icons.close
                            : shortcut == 'op'
                            ? Icons.shield_outlined
                            : Icons.terminal,
                        size: 18,
                      ),
                      label: Text('/$shortcut'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.consoleBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  ValueListenableBuilder<DownloadProgress?>(
                    valueListenable: host.download,
                    builder: (context, progress, _) => progress == null
                        ? const SizedBox.shrink()
                        : DownloadStrip(progress: progress),
                  ),
                  Expanded(
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      l.source == 'error'
                                          ? Icons.error_outline
                                          : Icons.chat_bubble_outline,
                                      size: 20,
                                      color: l.source == 'error'
                                          ? c.danger
                                          : c.muted,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${l.timestamp}  ${l.source.toUpperCase()}',
                                            style: TextStyle(
                                              color: c.muted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: .8,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          SelectableText(
                                            l.text,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 13,
                                              height: 1.55,
                                              color: l.source == 'error'
                                                  ? c.danger
                                                  : l.source == 'playit'
                                                  ? c.info
                                                  : c.consoleText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
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
                icon: const Icon(Icons.send_rounded),
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
