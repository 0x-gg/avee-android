import 'dart:math';

import 'package:avee/providers/app.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CommonDialog extends ConsumerWidget {
  const CommonDialog({
    super.key,
    required this.title,
    this.titleBuilder,
    this.actions,
    this.child,
    this.padding,
    this.overrideScroll = false,
    this.backgroundColor,
  });
  final String title;

  /// Optional locale-reactive title resolver; falls back to [title]. Lets a
  /// dialog re-localize its title in place when the app language changes.
  final String Function(BuildContext context)? titleBuilder;
  final Widget? child;
  final List<Widget>? actions;
  final EdgeInsets? padding;
  final bool overrideScroll;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(viewSizeProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final title = titleBuilder?.call(context) ?? this.title;
    final layout = AveeLayout.of(context);

    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      title: title.isEmpty ? null : Text(title),
      actions: actions,
      contentPadding: padding ??
          EdgeInsets.fromLTRB(
            layout.s(24),
            layout.s(12),
            layout.s(24),
            layout.s(8),
          ),
      backgroundColor:
          backgroundColor ?? colorScheme.surface.withValues(alpha: 0.92),
      content: Container(
        constraints: BoxConstraints(
          maxHeight: min(
            size.height - layout.s(80),
            layout.s(520),
          ),
          maxWidth: layout.dialogMaxWidth,
        ),
        width: min(size.width - layout.sideInset * 2, layout.dialogMaxWidth),
        child: !overrideScroll
            ? SingleChildScrollView(
                child: child,
              )
            : child,
      ),
    );
  }
}

class CommonModal extends ConsumerWidget {
  const CommonModal({
    super.key,
    this.child,
  });
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(viewSizeProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final layout = AveeLayout.of(context);
    return Center(
      child: Container(
        width: min(size.width * 0.9, layout.contentMaxWidth * 1.15),
        height: size.height * (layout.isTablet ? 0.75 : 0.85),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(layout.s(16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
