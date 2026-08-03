import 'dart:math';

import 'package:avee/common/constant.dart';
import 'package:avee/common/measure.dart';
import 'package:avee/common/theme.dart';
import 'package:avee/providers/config.dart';
import 'package:avee/state.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeManager extends ConsumerWidget {
  const ThemeManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = ref.watch(
      themeSettingProvider.select((state) => state.textScale),
    );
    final double userScale = max<double>(
      min<double>(
        textScale.enable ? textScale.scale : defaultTextScaleFactor,
        maxTextScale,
      ),
      minTextScale,
    );
    final layout = AveeLayout.of(context);
    // Screen-adaptive scale so dialogs/snackbars/Material chrome match the
    // AVEE shell on phones and tablets. Cap high so 10" stays readable.
    final double textScaleFactor =
        (userScale * layout.scale).clamp(0.9, 1.85).toDouble();

    globalState.measure = Measure.of(context, textScaleFactor);
    globalState.theme = CommonTheme.of(context, textScaleFactor);
    final padding = MediaQuery.of(context).padding;
    final height = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScaleFactor),
        padding: padding.copyWith(
          top: padding.top > height * 0.3 ? 20.0 : padding.top,
        ),
      ),
      child: Theme(
        data: theme.copyWith(
          dialogTheme: DialogThemeData(
            titleTextStyle: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Onest',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: theme.colorScheme.onSurface,
            ),
            contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'Onest',
              fontSize: 16,
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
            actionsPadding: EdgeInsets.fromLTRB(
              layout.s(16),
              0,
              layout.s(16),
              layout.s(12),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: layout.sideInset,
              vertical: layout.s(24),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(layout.s(20)),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'Onest',
              fontSize: 15,
              color: theme.colorScheme.onInverseSurface,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(layout.s(14)),
            ),
          ),
          bottomSheetTheme: BottomSheetThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(layout.s(28)),
              ),
            ),
            dragHandleSize: Size(layout.s(40), layout.s(4)),
          ),
          listTileTheme: ListTileThemeData(
            titleTextStyle: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'Onest',
              fontSize: 16,
            ),
            subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'Onest',
              fontSize: 13,
            ),
            minVerticalPadding: layout.s(10),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              minimumSize: Size(layout.s(64), layout.s(44)),
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (_, container) {
            globalState.appController.updateViewSize(
              Size(
                container.maxWidth,
                container.maxHeight,
              ),
            );
            return child;
          },
        ),
      ),
    );
  }
}
