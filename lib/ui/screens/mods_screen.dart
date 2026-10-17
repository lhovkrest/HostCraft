import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/host_controller.dart';
import '../../core/models.dart';
import '../../core/progress.dart';
import '../../services/mod_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Browse Modrinth or CurseForge, install mods (Fabric) or plugins (Paper,
/// Purpur, Folia), and manage what is already in the server folder.
class ModsScreen extends ConsumerStatefulWidget {
  const ModsScreen({super.key});

  @override
  ConsumerState<ModsScreen> createState() => _ModsScreenState();
}

class _ModsScreenState extends ConsumerState<ModsScreen> {
  final _query = TextEditingController();
  final _key = TextEditingController();
  ModSource _source = ModSource.modrinth;
  List<AddonProject> _results = [];
  bool _searching = false;
  bool _searched = false;
  String? _searchError;
  Future<List<InstalledAddon>>? _installed;
  Map<String, AddonFile> _updates = {};
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _query.dispose();
    _key.dispose();
    super.dispose();
  }

  void _reload() => _installed = ref.read(hostProvider).listAddons();

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editKey() async {
    _key.clear();
    final host = ref.read(hostProvider);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CurseForge API key'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                host.curseForgeKey.isEmpty
                    ? 'Add a catalog API key to browse CurseForge.'
                    : host.curseForgeKeyFromEnvironment
                    ? 'Using your local environment key. Save a new key to override it on this device.'
                    : 'Using a key saved on this device.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _key,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'New API key'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Use environment key'),
          ),
          FilledButton(
            onPressed: () {
              if (_key.text.trim().isNotEmpty) {
                Navigator.pop(context, _key.text.trim());
              }
            },
            child: const Text('Save key'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await host.setCurseForgeKey(value);
    _key.clear();
    if (!mounted) return;
    _snack(
      host.curseForgeKey.isEmpty
          ? 'No environment key found. Add CURSEFORGE_API_KEY to .env and restart.'
          : 'CurseForge key updated.',
    );
    if (_source == ModSource.curseforge) _search();
  }

  Future<void> _search() async {
    final host = ref.read(hostProvider);
    if (host.profile.engine.addonKind == null) return;
    if (_source == ModSource.curseforge && host.curseForgeKey.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final found = await host.searchAddons(_source, _query.text.trim());
      if (!mounted) return;
      setState(() {
        _results = found;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchError = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _install(AddonProject project) async {
    final host = ref.read(hostProvider);
    await host.installAddon(project);
    if (!mounted) return;
    setState(_reload);
    _snack(
      host.error ?? '${project.title} installed. It loads on the next start.',
    );
  }

  Future<void> _checkUpdates() async {
    setState(() => _checking = true);
    try {
      final found = await ref.read(hostProvider).checkAddonUpdates();
      if (!mounted) return;
      setState(() => _updates = found);
      _snack(
        found.isEmpty
            ? 'Everything is up to date.'
            : '${found.length} update(s) available.',
      );
    } catch (e) {
      _snack('$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _update(InstalledAddon addon) async {
    final host = ref.read(hostProvider);
    await host.updateAddon(addon);
    if (!mounted) return;
    setState(() {
      _updates = {..._updates}..remove(addon.key);
      _reload();
    });
    _snack(host.error ?? '${addon.title} updated.');
  }

  Future<void> _remove(InstalledAddon addon) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${addon.title}?'),
        content: const Text('The jar file is deleted from the server folder.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final host = ref.read(hostProvider);
    await host.removeAddon(addon);
    if (!mounted) return;
    setState(_reload);
    if (host.error != null) _snack(host.error!);
  }

  Future<void> _toggle(InstalledAddon addon, bool on) async {
    final host = ref.read(hostProvider);
    await host.setAddonEnabled(addon, on);
    if (!mounted) return;
    setState(_reload);
    if (host.error != null) _snack(host.error!);
  }

  Widget _width(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostProvider);
    final kind = host.profile.engine.addonKind;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: const Text(
            'Mods & plugins',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.4),
          ),
          actions: [
            IconButton(
              tooltip: 'Change CurseForge API key',
              onPressed: _editKey,
              icon: const Icon(Icons.key_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Browse'),
              Tab(text: 'Installed'),
            ],
          ),
        ),
        body: SafeArea(
          child: kind == null
              ? _width(
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Notice(
                      text: 'Vanilla servers cannot load mods or plugins. Choose Paper, Purpur or Folia for plugins, or Fabric or Forge for mods in Server setup. Forge hosting requires Windows.',
                    ),
                  ),
                )
              : Column(
                  children: [
                    ValueListenableBuilder<DownloadProgress?>(
                      valueListenable: host.download,
                      builder: (_, p, _) => p == null
                          ? const SizedBox.shrink()
                          : DownloadStrip(progress: p),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _width(_browse(host, kind)),
                          _width(_installedTab(host)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _lockedNotice(HostController host) => host.locked
      ? const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Notice(
            text: 'Stop the server to install or change mods and plugins.',
          ),
        )
      : const SizedBox.shrink();

  Widget _browse(HostController host, AddonKind kind) {
    final c = context.hc;
    final noun = kind == AddonKind.plugin ? 'plugins' : 'mods';
    final needsKey =
        _source == ModSource.curseforge && host.curseForgeKey.isEmpty;
    return Column(
      children: [
        _lockedNotice(host),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ModSource>(
              segments: [
                for (final s in ModSource.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_source},
              onSelectionChanged: (value) {
                setState(() {
                  _source = value.first;
                  _results = [];
                  _searched = false;
                  _searchError = null;
                });
                _search();
              },
            ),
          ),
        ),
        if (needsKey)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FlatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('CURSEFORGE API KEY'),
                  const SizedBox(height: 8),
                  Text(
                    'Paste a CurseForge catalog API key, or set CURSEFORGE_API_KEY in your local .env file and restart. Author upload tokens are a different credential.',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        openLink(context, 'https://console.curseforge.com/'),
                    child: const Text('Open console.curseforge.com'),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'API key'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await host.setCurseForgeKey(_key.text);
                        _key.clear();
                        _search();
                      },
                      child: const Text('Save key'),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText:
                    'Search $noun for ${host.profile.engine.label} ${host.profile.version}',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _search,
                ),
              ),
            ),
          ),
        if (_searching) const LinearProgressIndicator(),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Notice(text: _searchError!, color: c.danger),
          ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _searched
                        ? 'Nothing found for this version.'
                        : (needsKey ? '' : 'Search to get started.'),
                    style: TextStyle(color: c.muted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _results.length,
                  itemBuilder: (context, i) => _resultCard(host, _results[i]),
                ),
        ),
      ],
    );
  }

  Widget _icon(String? url, double size) {
    final c = context.hc;
    final fallback = Icon(Icons.extension_outlined, color: c.accent);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: c.surfaceAlt,
        alignment: Alignment.center,
        child: (url ?? '').isEmpty
            ? fallback
            : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  Widget _resultCard(HostController host, AddonProject r) {
    final c = context.hc;
    return FlatCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _icon(r.iconUrl, 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.author.isEmpty ? '' : 'by ${r.author} · '}${_compact(r.downloads)} downloads',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  r.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: host.locked ? null : () => _install(r),
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  Widget _installedTab(HostController host) {
    final c = context.hc;
    return Column(
      children: [
        _lockedNotice(host),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _checking ? null : _checkUpdates,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.update),
              label: const Text('Check for updates'),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<InstalledAddon>>(
            future: _installed,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Notice(
                    text: '${snap.error}'.replaceFirst('Bad state: ', ''),
                    color: c.danger,
                  ),
                );
              }
              final items = snap.data ?? const <InstalledAddon>[];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'Nothing installed yet.',
                    style: TextStyle(color: c.muted),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: items.length,
                itemBuilder: (context, i) => _installedCard(host, items[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _installedCard(HostController host, InstalledAddon a) {
    final c = context.hc;
    final update = _updates[a.key];
    final details = [
      if (a.versionName.isNotEmpty)
        a.versionName
      else if (!a.tracked)
        'added by hand',
      if (!a.enabled) 'disabled',
    ].join(' · ');
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Switch(
            value: a.enabled,
            onChanged: host.locked ? null : (on) => _toggle(a, on),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: a.enabled ? c.text : c.muted,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(details, style: TextStyle(color: c.muted, fontSize: 12)),
                if (update != null)
                  Text(
                    'Update available: ${update.versionName}',
                    style: TextStyle(color: c.accent, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (update != null)
            TextButton(
              onPressed: host.locked ? null : () => _update(a),
              child: const Text('Update'),
            ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: host.locked ? null : () => _remove(a),
          ),
        ],
      ),
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
