import 'dart:math' as math;

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

/// Width-driven scale of the phone design. Proportions stay fixed; size grows.
///
/// Reference canvas is 390dp. Content column and all UI metrics use the same
/// scale factor so phones, 7" and 10" tablets keep the same composition ratio.
class AveeLayout {
  const AveeLayout._(this.size);

  factory AveeLayout.of(BuildContext context) =>
      AveeLayout._(MediaQuery.sizeOf(context));

  /// Phone design canvas width.
  static const designWidth = 390.0;

  final Size size;

  bool get isTablet => size.shortestSide >= 600;
  bool get isWideTablet => size.shortestSide >= 840;

  /// Side inset grows slightly with width so content never touches edges.
  double get sideInset => math.max(20.0, size.width * 0.05);

  /// Content column: full usable width on phones; on tablets grows with screen
  /// (~58% of width) while staying capped so CTAs never become banners.
  double get contentMaxWidth {
    final available = size.width - sideInset * 2;
    if (!isTablet) return available;
    final target = size.width * 0.58;
    final maxWidth = isWideTablet ? 640.0 : 560.0;
    return target.clamp(480.0, math.min(available, maxWidth));
  }

  /// Layout scale for spacing, controls, and heroes (not raw font sizes).
  ///
  /// Typography grows via [MediaQuery.textScaler] in [ThemeManager] using the
  /// same factor, so dialogs/snackbars/Material chrome match shell pages
  /// without double-scaling `fontSize: layout.t(...)`.
  double get scale {
    final reference = isTablet
        ? contentMaxWidth
        : math.min(contentMaxWidth, designWidth * 1.08);
    return (reference / designWidth).clamp(0.92, 1.65);
  }

  /// Physical metrics (padding, icon boxes, button heights, orbs).
  double s(double value) => value * scale;

  /// Design-canvas type sizes. Prefer these for `fontSize` so [TextScaler]
  /// can scale Material + AVEE text together.
  double t(double value) => value;

  EdgeInsets get pagePadding => EdgeInsets.fromLTRB(
        isTablet ? sideInset * 0.35 : 0,
        s(12),
        isTablet ? sideInset * 0.35 : 0,
        s(24),
      );

  double get headlineSize => t(28);
  double get bodySize => t(16);
  double get statusSize => t(14);
  double get captionSize => t(12);
  double get buttonHeight => s(56);
  double get buttonHeightSecondary => s(52);
  double get buttonRadius => s(16);
  double get buttonFontSize => t(16);
  double get pulseSize => s(230);
  double get orbSize => s(260);

  /// Comfortable dialog / toast width on any screen.
  double get dialogMaxWidth =>
      math.min(contentMaxWidth, isTablet ? s(420) : 340.0);
}

/// Centers [child] in the scaled content column.
class AveeContentFrame extends StatelessWidget {
  const AveeContentFrame({
    required this.child,
    this.padding,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
        child: Padding(
          padding: padding ?? layout.pagePadding,
          child: child,
        ),
      ),
    );
  }
}

/// Scrollable body with a width-scaled, centered content column.
class AveeResponsiveScroll extends StatelessWidget {
  const AveeResponsiveScroll({
    required this.children,
    this.centerVertically = false,
    @Deprecated('Ignored — scaling replaced tablet panels')
    bool usePanelOnTablet = false,
    super.key,
  });

  final List<Widget> children;
  final bool centerVertically;

  @override
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: layout.sideInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
              child: Padding(
                padding: EdgeInsets.only(
                  top: layout.s(12),
                  bottom: layout.s(24),
                ),
                child: Column(
                  mainAxisAlignment: centerVertically
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scales AVEE hero from the shared layout scale.
double aveeHeroSize(
  BoxConstraints constraints, {
  BuildContext? context,
  double reservedHeight = 0,
  double minSize = 160,
  double maxSize = 280,
}) {
  if (context != null) {
    final layout = AveeLayout.of(context);
    final target = maxSize >= 250 ? layout.orbSize : layout.pulseSize;
    return target.clamp(minSize, layout.s(maxSize));
  }
  final byWidth = constraints.maxWidth * 0.72;
  final byHeight =
      math.max(constraints.maxHeight - reservedHeight, minSize) * 0.92;
  return math.min(byWidth, byHeight).clamp(minSize, maxSize);
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.s(8),
        layout.s(6),
        layout.s(8),
        layout.s(4),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: layout.contentMaxWidth + layout.sideInset * 2,
          ),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_rounded, size: layout.s(24)),
                  color: AveeColors.text,
                  iconSize: layout.s(24),
                )
              else
                SizedBox(width: layout.s(8)),
              Expanded(
                child: title == 'AVEE VPN'
                    ? const AveeLogo(compact: true, horizontal: true)
                    : Text(
                        title,
                        style: TextStyle(
                          color: AveeColors.text,
                          fontSize: layout.t(22),
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
                  iconSize: layout.s(26),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
    final layout = AveeLayout.of(context);
    final size = layout.s(compact ? 34 : 42);
    final textStyle = TextStyle(
      color: AveeColors.text,
      fontWeight: FontWeight.w600,
      letterSpacing: compact ? 0.4 : 0.6,
      fontSize: layout.t(compact ? 22 : 28),
      height: 1,
    );
    final vpnStyle = TextStyle(
      color: AveeColors.primary,
      fontSize: layout.t(compact ? 22 : 28),
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
          SizedBox(width: layout.s(10)),
          Text('AVEE', style: textStyle),
          SizedBox(width: layout.s(8)),
          Text('VPN', style: vpnStyle),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: layout.s(8)),
        Text('AVEE', style: textStyle),
        SizedBox(height: layout.s(4)),
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return SizedBox(
      height: layout.buttonHeight,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon == null
            ? const SizedBox.shrink()
            : Icon(icon, size: layout.s(22)),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AveeColors.primary,
          foregroundColor: AveeColors.background,
          disabledBackgroundColor: AveeColors.outline,
          disabledForegroundColor: AveeColors.mutedText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(layout.buttonRadius),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: layout.buttonFontSize,
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return SizedBox(
      height: layout.buttonHeightSecondary,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null
            ? const SizedBox.shrink()
            : Icon(icon, size: layout.s(22)),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AveeColors.text,
          side: const BorderSide(color: AveeColors.outline, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(layout.buttonRadius),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: layout.buttonFontSize,
          ),
        ),
      ),
    );
  }
}

class AveePanel extends StatelessWidget {
  const AveePanel({
    required this.child,
    this.padding,
    this.onTap,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    final radius = layout.s(AveeRadius.card);
    final content = Container(
      padding: padding ?? EdgeInsets.all(layout.s(16)),
      decoration: BoxDecoration(
        color: AveeColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AveeColors.outline.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x33000000),
            blurRadius: layout.s(18),
            offset: Offset(0, layout.s(8)),
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
        borderRadius: BorderRadius.circular(radius),
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.s(10),
        vertical: layout.s(6),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AveeRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: layout.t(13),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return Container(
      padding: EdgeInsets.all(layout.s(4)),
      decoration: BoxDecoration(
        color: AveeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(layout.s(14)),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(vertical: layout.s(10)),
                  decoration: BoxDecoration(
                    color: option == value
                        ? AveeColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(layout.s(11)),
                  ),
                  child: Text(
                    option,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: option == value
                          ? AveeColors.background
                          : AveeColors.secondaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: layout.t(13),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return InkWell(
      onTap: onTap ?? (onChanged == null ? null : () => onChanged!(!value)),
      borderRadius: BorderRadius.circular(layout.s(12)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.s(12)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AveeColors.text,
                      fontSize: layout.bodySize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: layout.s(4)),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: AveeColors.mutedText,
                        fontSize: layout.captionSize,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingChevron)
              Icon(
                Icons.chevron_right,
                color: AveeColors.mutedText,
                size: layout.s(24),
              )
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return Padding(
      padding: EdgeInsets.only(right: layout.s(8)),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AveeColors.primary,
        backgroundColor: AveeColors.surfaceRaised,
        labelStyle: TextStyle(
          color: selected ? AveeColors.background : AveeColors.secondaryText,
          fontWeight: FontWeight.w700,
          fontSize: layout.t(13),
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AveeRadius.pill),
        ),
        showCheckmark: false,
      ),
    );
  }
}

/// Shared filled text-field look, scaled with [AveeLayout].
InputDecoration aveeFieldDecoration(
  BuildContext context, {
  required String label,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? hintText,
}) {
  final layout = AveeLayout.of(context);
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AveeColors.surface,
    labelStyle: TextStyle(
      color: AveeColors.mutedText,
      fontSize: layout.t(14),
    ),
    hintStyle: TextStyle(
      color: AveeColors.mutedText,
      fontSize: layout.bodySize,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(layout.s(16)),
      borderSide: BorderSide.none,
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: layout.s(16),
      vertical: layout.s(16),
    ),
  );
}
