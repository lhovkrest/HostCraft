import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

extension EnginePresentation on ServerEngine {
  String get purpose => switch (this) {
    ServerEngine.vanilla => 'The original experience',
    ServerEngine.paper => 'Play better, together',
    ServerEngine.fabric => 'Lightweight modding',
    ServerEngine.forge => 'Go big with modpacks',
    ServerEngine.purpur => 'Make every rule yours',
    ServerEngine.folia => 'For ambitious worlds',
  };
  String get badge => switch (this) {
    ServerEngine.vanilla => 'NO MODS',
    ServerEngine.paper => 'RECOMMENDED',
    ServerEngine.fabric => 'FABRIC MODS',
    ServerEngine.forge => 'FORGE MODS',
    ServerEngine.purpur => 'PLUGINS',
    ServerEngine.folia => 'ADVANCED',
  };
  IconData get icon => switch (this) {
    ServerEngine.vanilla => Icons.grass_rounded,
    ServerEngine.paper => Icons.near_me_rounded,
    ServerEngine.fabric => Icons.layers_rounded,
    ServerEngine.forge => Icons.hardware_rounded,
    ServerEngine.purpur => Icons.auto_awesome_rounded,
    ServerEngine.folia => Icons.account_tree_rounded,
  };
  Color get tint => switch (this) {
    ServerEngine.vanilla => const Color(0xff65cf98),
    ServerEngine.paper => const Color(0xff70b7ef),
    ServerEngine.fabric => const Color(0xffd7b482),
    ServerEngine.forge => const Color(0xfff2a274),
    ServerEngine.purpur => const Color(0xffb69af4),
    ServerEngine.folia => const Color(0xff6dd3cb),
  };
}

class EngineChoice extends StatelessWidget {
  const EngineChoice({
    super.key,
    required this.engine,
    required this.selected,
    required this.onTap,
    this.available = true,
  });
  final ServerEngine engine;
  final bool selected, available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hc;
    final tint = Theme.of(context).brightness == Brightness.dark
        ? engine.tint
        : Color.lerp(engine.tint, Colors.black, .42)!;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label:
          '${engine.label}, ${engine.purpose}${available ? '' : ', Windows only'}',
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 166),
        decoration: BoxDecoration(
          color: selected ? Color.lerp(c.surface, tint, .09) : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? tint : c.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: tint.withValues(alpha: .08),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(engine.icon, color: tint, size: 23),
                      ),
                      const Spacer(),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.add_circle_outline_rounded,
                        color: selected ? tint : c.muted,
                        size: 21,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    engine.label,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                      color: available ? c.text : c.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    engine.purpose,
                    style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    available ? engine.badge : 'WINDOWS ONLY',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: tint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupTip extends StatelessWidget {
  const SetupTip({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.lightbulb_outline_rounded,
  });
  final String title, body;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final c = context.hc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent.withValues(alpha: .16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: TextStyle(color: c.muted, height: 1.6, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
