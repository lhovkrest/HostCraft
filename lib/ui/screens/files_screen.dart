import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/host_controller.dart';
import '../../core/progress.dart';
import '../../services/file_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Browse and edit the files of the current server: configs, plugins, mods,
/// worlds, logs. Reading is always allowed; changing files needs the server
/// to be stopped.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  String _path = '';
  late Future<List<ServerFileEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _entries = ref.read(hostProvider).files().list(_path);

  void _go(String path) => setState(() {
    _path = path;
    _load();
  });

  String get _parent {
    if (_path.isEmpty) return '';
    final up = p.dirname(_path);
    return up == '.' ? '' : up;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() job) async {
    try {
      await job();
      if (mounted) setState(_load);
    } catch (e) {
      _snack(
        '$e'
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    }
  }

  Future<String?> _ask(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(ServerFileEntry e) async {
    if (e.isDirectory) return _go(e.relativePath);
    if (!ServerFiles.isEditable(e.name)) {
      _snack(
        '${e.name} is not a text file. Rename or delete it from the menu.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FileEditor(path: e.relativePath, name: e.name),
      ),
    );
    if (mounted) setState(_load);
  }

  Future<void> _delete(HostController host, ServerFileEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${e.name}?'),
        content: Text(
          e.isDirectory
              ? 'The folder and everything in it is deleted.'
              : 'The file is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => host.files().delete(e.relativePath));
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final c = context.hc;
    final canEdit = !host.locked;
    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_parent);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Text(
            _path.isEmpty ? 'Server files' : _path.replaceAll('\\', '/'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
          actions: [
            if (Platform.isWindows)
              IconButton(
                tooltip: 'Open in Explorer',
                icon: const Icon(Icons.folder_open),
                onPressed: () => Process.start('explorer.exe', [
                  host.files().root.path,
                ], mode: ProcessStartMode.detached),
              ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(_load),
            ),
            if (canEdit)
              PopupMenuButton<String>(
                tooltip: 'Add',
                icon: Icon(Icons.add_circle_outline, color: c.accent),
                onSelected: (value) async {
                  final name = await _ask(
                    value == 'folder' ? 'New folder' : 'New file',
                  );
                  if (name == null || name.trim().isEmpty) return;
                  await _run(
                    () => value == 'folder'
                        ? host.files().createFolder(_path, name)
                        : host.files().createFile(_path, name),
                  );
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'folder', child: Text('New folder')),
                  PopupMenuItem(value: 'file', child: Text('New file')),
                ],
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              ValueListenableBuilder<DownloadProgress?>(
                valueListenable: host.download,
                builder: (_, p, _) => p == null
                    ? const SizedBox.shrink()
                    : DownloadStrip(progress: p),
              ),
              if (!canEdit)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Notice(
                    text: 'The server is busy. Stop it to change files.',
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: FutureBuilder<List<ServerFileEntry>>(
                      future: _entries,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Notice(
                              text: '${snap.error}',
                              color: c.danger,
                            ),
                          );
                        }
                        final items = snap.data ?? const <ServerFileEntry>[];
                        final up = _path.isNotEmpty;
                        if (items.isEmpty && !up) {
                          return Center(
                            child: Text(
                              'No files yet. Prepare the server first to create them.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.muted),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: items.length + (up ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (up && i == 0) {
                              return _row(
                                icon: Icons.arrow_upward,
                                title: '..',
                                subtitle: 'Parent folder',
                                onTap: () => _go(_parent),
                              );
                            }
                            final e = items[i - (up ? 1 : 0)];
                            return _row(
                              icon: e.isDirectory
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined,
                              title: e.name,
                              subtitle: e.isDirectory
                                  ? 'Folder'
                                  : '${formatBytes(e.bytes)} · ${e.modified.toString().split('.').first}',
                              onTap: () => _open(e),
                              menu: canEdit ? _menu(host, e) : null,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(HostController host, ServerFileEntry e) =>
      PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            final name = await _ask('Rename', initial: e.name);
            if (name != null && name.trim().isNotEmpty && name != e.name) {
              await _run(() => host.files().rename(e.relativePath, name));
            }
          } else {
            await _delete(host, e);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? menu,
  }) {
    final c = context.hc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: c.accent),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          trailing: menu,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _FileEditor extends ConsumerStatefulWidget {
  const _FileEditor({required this.path, required this.name});
  final String path;
  final String name;

  @override
  ConsumerState<_FileEditor> createState() => _FileEditorState();
}

class _FileEditorState extends ConsumerState<_FileEditor> {
  final _text = TextEditingController();
  bool _loading = true;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      _text.text = await ref.read(hostProvider).files().readText(widget.path);
    } catch (e) {
      _error = '$e'.replaceFirst('Bad state: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    try {
      await ref.read(hostProvider).files().writeText(widget.path, _text.text);
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved. Changes apply on the next start.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final c = context.hc;
    final canEdit = !host.locked && _error == null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: Text('${widget.name} has unsaved changes.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Text(
            widget.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (canEdit)
              IconButton(
                tooltip: 'Save',
                icon: Icon(
                  Icons.save_outlined,
                  color: _dirty ? c.accent : null,
                ),
                onPressed: _dirty ? _save : null,
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Notice(text: _error!, color: c.danger),
                )
              : Column(
                  children: [
                    if (host.locked)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Notice(
                          text: 'Read only while the server is running.',
                        ),
                      ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.consoleBackground,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: c.border),
                        ),
                        child: TextField(
                          controller: _text,
                          readOnly: !canEdit,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: c.consoleText,
                          ),
                          onChanged: (_) {
                            if (!_dirty) setState(() => _dirty = true);
                          },
                          decoration: const InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.all(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
