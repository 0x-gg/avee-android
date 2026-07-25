import 'dart:math' as math;

import 'package:avee/manager/message_manager.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:avee/widgets/scaffold.dart';
import 'package:flutter/material.dart';

extension BuildContextExtension on BuildContext {
  CommonScaffoldState? get commonScaffoldState =>
      findAncestorStateOfType<CommonScaffoldState>();

  Future<void>? showNotifier(String text) =>
      findAncestorStateOfType<MessageManagerState>()?.message(text);

  void showSnackBar(
    String message, {
    SnackBarAction? action,
  }) {
    final layout = AveeLayout.of(this);
    final width = viewWidth;
    final snackWidth = layout.isTablet ? layout.s(420) : 300.0;
    final margin = width < 600
        ? EdgeInsets.fromLTRB(
            layout.s(16),
            0,
            layout.s(16),
            layout.s(16),
          )
        : EdgeInsets.only(
            bottom: layout.s(16),
            left: layout.s(16),
            right: math.max(layout.s(16), width - snackWidth - layout.s(16)),
          );
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        action: action,
        content: Text(
          message,
          style: textTheme.bodyMedium?.copyWith(fontSize: 15),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
        margin: margin,
      ),
    );
  }

  Size get appSize => MediaQuery.of(this).size;

  double get viewWidth => appSize.width;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  TextTheme get textTheme => Theme.of(this).textTheme;

  T? findLastStateOfType<T extends State>() {
    T? state;

    void visitor(Element element) {
      if (!element.mounted) {
        return;
      }
      if (element is StatefulElement) {
        if (element.state is T) {
          state = element.state as T;
        }
      }
      element.visitChildren(visitor);
    }

    visitor(this as Element);
    return state;
  }
}
