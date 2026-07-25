import 'package:flutter/material.dart';

/// AVEE 2026 mobile visual language — charcoal base + coral accent.
class AveeColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1A1A1A);
  static const surfaceRaised = Color(0xFF242424);
  static const outline = Color(0xFF333333);
  static const primary = Color(0xFFFF8C69);
  static const highlight = Color(0xFFFFC9B8);
  static const signal = Color(0xFFFF6B4A);
  static const text = Color(0xFFFFF8F4);
  static const secondaryText = Color(0xFFC9BDB7);
  static const mutedText = Color(0xFF8F8681);
  static const warning = Color(0xFFFFB36B);
  static const error = Color(0xFFFF5742);
  static const success = Color(0xFFFF8C69);
}

class AveeSpace {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AveeRadius {
  static const card = 20.0;
  static const control = 16.0;
  static const pill = 999.0;
}

/// Keeps AVEE screens readable on phones and tablets by centering content and
/// capping the line length instead of stretching edge-to-edge on wide displays.
class AveeResponsiveScroll extends StatelessWidget {
  const AveeResponsiveScroll({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
    this.maxWidth = 520,
    this.centerVertically = false,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double maxWidth;
  final bool centerVertically;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final align = centerVertically && constraints.maxHeight > 640
              ? Alignment.center
              : Alignment.topCenter;
          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: align,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          );
        },
      );
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

/// Screen chrome: title left, optional back and optional primary action right.
class AveeAppBar extends StatelessWidget {
  const AveeAppBar({
    required this.title,
    this.showBack = false,
    this.onBack,
    this.onMenu,
    this.actionIcon = Icons.menu_rounded,
    this.actionTooltip = 'Menu',
    super.key,
  });

  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;
  final IconData actionIcon;
  final String actionTooltip;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Row(
          children: [
            if (showBack)
              IconButton(
                tooltip: 'Back',
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: AveeColors.text,
              )
            else
              const SizedBox(width: 8),
            Expanded(
              child: title == 'AVEE VPN'
                  ? const AveeLogo(compact: true, horizontal: true)
                  : Text(
                      title,
                      style: const TextStyle(
                        color: AveeColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        height: 1.1,
                      ),
                    ),
            ),
            if (onMenu != null)
              IconButton(
                tooltip: actionTooltip,
                onPressed: onMenu,
                icon: Icon(actionIcon),
                color: AveeColors.text,
                iconSize: 26,
              ),
          ],
        ),
      );
}

@Deprecated('Use AveeAppBar')
class AveeTopBar extends StatelessWidget {
  const AveeTopBar({required this.onSettings, super.key});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => AveeAppBar(
        title: 'AVEE VPN',
        onMenu: onSettings,
      );
}

class AveeLogo extends StatelessWidget {
  const AveeLogo({this.compact = false, this.horizontal = false, super.key});
  final bool compact;
  final bool horizontal;

  static const _asset = 'assets/images/icon.png';

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 42.0;
    final textStyle = TextStyle(
      color: AveeColors.text,
      fontWeight: FontWeight.w600,
      letterSpacing: compact ? 0.4 : 0.6,
      fontSize: compact ? 22 : 28,
      height: 1,
    );
    final vpnStyle = TextStyle(
      color: AveeColors.primary,
      fontSize: compact ? 22 : 28,
      fontWeight: FontWeight.w600,
      letterSpacing: compact ? 0.4 : 0.6,
      height: 1,
    );
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: Image.asset(_asset, width: size, height: size, fit: BoxFit.cover),
    );
    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: 10),
          Text('AVEE', style: textStyle),
          const SizedBox(width: 8),
          Text('VPN', style: vpnStyle),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 8),
        Text('AVEE', style: textStyle),
        const SizedBox(height: 4),
        Text('VPN', style: vpnStyle),
      ],
    );
  }
}

class AveePrimaryButton extends StatelessWidget {
  const AveePrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        width: double.infinity,
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
              borderRadius: BorderRadius.circular(AveeRadius.control),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      );
}

class AveeSecondaryButton extends StatelessWidget {
  const AveeSecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: AveeColors.text,
            side: const BorderSide(color: AveeColors.outline, width: 1.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AveeRadius.control),
            ),
          ),
        ),
      );
}

class AveePanel extends StatelessWidget {
  const AveePanel({
    required this.child,
    this.padding = const EdgeInsets.all(AveeSpace.md),
    this.onTap,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AveeColors.surface,
        borderRadius: BorderRadius.circular(AveeRadius.card),
        border: Border.all(color: AveeColors.outline.withValues(alpha: .7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AveeRadius.card),
        child: content,
      ),
    );
  }
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
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      );
}

class AveeSegmentedControl extends StatelessWidget {
  const AveeSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AveeColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (final option in options)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: option == value
                          ? AveeColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      option,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: option == value
                            ? AveeColors.background
                            : AveeColors.secondaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class AveeToggleTile extends StatelessWidget {
  const AveeToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.trailingChevron = false,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool trailingChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap ?? (onChanged == null ? null : () => onChanged!(!value)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AveeColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AveeColors.mutedText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingChevron)
                const Icon(Icons.chevron_right, color: AveeColors.mutedText)
              else if (onChanged != null)
                Switch.adaptive(
                  value: value,
                  activeThumbColor: AveeColors.background,
                  activeTrackColor: AveeColors.primary,
                  inactiveThumbColor: AveeColors.secondaryText,
                  inactiveTrackColor: AveeColors.outline,
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
      );
}

class AveeFilterChip extends StatelessWidget {
  const AveeFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AveeColors.primary,
          backgroundColor: AveeColors.surfaceRaised,
          labelStyle: TextStyle(
            color: selected ? AveeColors.background : AveeColors.secondaryText,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AveeRadius.pill),
          ),
          showCheckmark: false,
        ),
      );
}
