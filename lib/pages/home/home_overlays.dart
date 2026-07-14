import 'dart:io';

import 'package:dropweb/common/common.dart';
import 'package:dropweb/pages/home/connect_circle.dart';
import 'package:flutter/material.dart';

const Alignment _mobileConnectAlignment = Alignment(0, 0.58);

class _ScreenIndicator extends StatelessWidget {
  const _ScreenIndicator({
    required this.currentIndex,
    required this.itemCount,
  });

  final int currentIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 1) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final selectedIndex =
        currentIndex >= itemCount ? itemCount - 1 : currentIndex;

    return IgnorePointer(
      child: SizedBox(
        height: 24,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(itemCount, (index) {
              final isActive = index == selectedIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: isActive ? 16 : 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Connect/add button overlay — Dashboard-scoped. Lives inside the
/// Dashboard PageView item so it slides off with the rest of Dashboard
/// when the user swipes to Tools.
class MobileConnectButtonOverlay extends StatelessWidget {
  const MobileConnectButtonOverlay({required this.buttonSize});

  final double buttonSize;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: Align(
          alignment: _mobileConnectAlignment,
          child: SizedBox.square(
            dimension: buttonSize,
            child: ConnectCircle(buttonSize: buttonSize),
          ),
        ),
      );
}

/// First-run guidance under the connect lens — a short headline + one-liner
/// telling a fresh user WHAT the unlabeled "+" does. Shown ONLY in the empty
/// state ([visible] == `!hasProfiles`, the same condition that flips the
/// button glyph Power→Add). Anchored to [_mobileConnectAlignment] and shifted
/// BELOW the button (button-relative offset, not a fixed screen fraction) so
/// the lens footprint above never moves when the block appears/disappears —
/// the same "anchor to the button, translate down" idiom as
/// [MobileIndicatorOverlay], which occupies this slot once a profile unlocks
/// the Tools page. Opacity fades over the signature [Lumina] motion; wrapped
/// in [IgnorePointer] so it is purely decorative and never steals a tap meant
/// for the button. All copy is provider-neutral l10n; text uses textTheme +
/// colorScheme only (no inline TextStyle, no hardcoded colors).
class MobileEmptyGuidanceOverlay extends StatelessWidget {
  const MobileEmptyGuidanceOverlay({
    required this.buttonSize,
    required this.visible,
  });

  final double buttonSize;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    // Android's empty state is AVEE account onboarding. The legacy copy below
    // describes arbitrary subscription imports, which are not an Android
    // entry point anymore and must not remain visible as an affordance.
    if (Platform.isAndroid) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: _mobileConnectAlignment,
          // ABOVE the lens, in the dead space the subscription card occupies
          // once a profile exists — below-the-button placement collided with
          // the MENU affordance and read as an afterthought. The offset is
          // button-relative (half the lens + a fixed gap + half the ~2-line
          // block) so the lens never moves when the block fades.
          child: Transform.translate(
            offset: Offset(0, -(buttonSize / 2 + 96)),
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: Lumina.luminaDuration,
              curve: Lumina.luminaCurve,
              child: ConstrainedBox(
                // Cap the line length so the one-liner hint stays a one-liner
                // on phones instead of wrapping with an orphan word.
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appLocalizations.dashboardEmptyTitle,
                      textAlign: TextAlign.center,
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appLocalizations.dashboardEmptyHint,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tab/screen indicator overlay — page-independent. Rendered in an outer
/// Stack above the PageView so it stays visible on Dashboard, Settings
/// and any other page. The indicator anchors visually to the same spot
/// the connect button would occupy on Dashboard.
class MobileIndicatorOverlay extends StatelessWidget {
  const MobileIndicatorOverlay({
    required this.buttonSize,
    required this.currentIndex,
    required this.itemCount,
  });

  final double buttonSize;
  final int currentIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    const indicatorGap = 10.0;
    const indicatorHeight = 24.0;

    return Positioned.fill(
      child: Align(
        alignment: _mobileConnectAlignment,
        child: Transform.translate(
          offset: Offset(
            0,
            buttonSize / 2 + indicatorGap + indicatorHeight / 2,
          ),
          child: _ScreenIndicator(
            currentIndex: currentIndex,
            itemCount: itemCount,
          ),
        ),
      ),
    );
  }
}
