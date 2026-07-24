import 'package:flutter/material.dart';

/// AVEE's mobile visual language. Screens consume these tokens instead of
/// embedding one-off colors, radii, and spacing values.
class AveeColors {
  // AVEE Solar Editorial: warm coral action, soft peach highlight, graphite base.
  static const background = Color(0xFF0B0C0D);
  static const surface = Color(0xFF141516);
  static const surfaceRaised = Color(0xFF202021);
  static const outline = Color(0xFF353536);
  static const primary = Color(0xFFFF7A59);
  static const highlight = Color(0xFFFFC9B8);
  static const signal = Color(0xFFFF5742);
  static const text = Color(0xFFFFF8F4);
  static const secondaryText = Color(0xFFD1C5C0);
  static const mutedText = Color(0xFF9B8F8A);
  static const warning = Color(0xFFFFB36B);
  static const error = Color(0xFFFF5742);
}

class AveeSpace {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AveeRadius {
  static const card = 16.0;
  static const control = 16.0;
  static const pill = 999.0;
}

class AveePage extends StatelessWidget {
  const AveePage({required this.child, this.bottomNavigationBar, super.key});
  final Widget child;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AveeColors.background,
        body: SafeArea(child: child),
        bottomNavigationBar: bottomNavigationBar,
      );
}

class AveeTopBar extends StatelessWidget {
  const AveeTopBar({required this.onSettings, super.key});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 14, 4),
        child: Row(
          children: [
            const Expanded(
              child: Center(child: AveeLogo(compact: true, horizontal: true)),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
              color: AveeColors.primary,
              iconSize: 27,
            ),
          ],
        ),
      );
}

class AveeLogo extends StatelessWidget {
  const AveeLogo({this.compact = false, this.horizontal = false, super.key});
  final bool compact;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AveeColors.text,
          fontWeight: FontWeight.w300,
          letterSpacing: compact ? 3.8 : 5.2,
          fontSize: compact ? 20 : 28,
          height: 1,
        );
    final vpnStyle = TextStyle(
        color: AveeColors.primary,
        fontSize: compact ? 20 : 28,
        fontWeight: FontWeight.w300,
        letterSpacing: compact ? 3.2 : 4.2,
        height: 1);
    if (horizontal) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text('AVEE', style: textStyle),
        const SizedBox(width: 14),
        Text('VPN', style: vpnStyle),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('AVEE', style: textStyle),
        const SizedBox(height: 4),
        Text('VPN', style: vpnStyle)
      ],
    );
  }
}

class AveePrimaryButton extends StatelessWidget {
  const AveePrimaryButton(
      {required this.label, required this.onPressed, this.icon, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: AveeColors.primary,
            foregroundColor: AveeColors.background,
            disabledBackgroundColor: AveeColors.outline,
            disabledForegroundColor: AveeColors.mutedText,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AveeRadius.control)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
}

class AveeSecondaryButton extends StatelessWidget {
  const AveeSecondaryButton(
      {required this.label, required this.onPressed, this.icon, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: AveeColors.text,
            side: const BorderSide(color: AveeColors.outline),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AveeRadius.control)),
          ),
        ),
      );
}

class AveePanel extends StatelessWidget {
  const AveePanel(
      {required this.child,
      this.padding = const EdgeInsets.all(AveeSpace.md),
      super.key});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AveeColors.surface.withValues(alpha: .90),
              AveeColors.highlight.withValues(alpha: .08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AveeColors.outline.withValues(alpha: .95)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x22000000), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: child,
      );
}

class AveeStatusPill extends StatelessWidget {
  const AveeStatusPill({required this.label, required this.color, super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(AveeRadius.pill),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      );
}
