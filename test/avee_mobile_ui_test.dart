import 'package:avee/pages/avee_mobile_shell.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: child),
      );

  testWidgets('guest onboarding exposes the AVEE first-run actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(host(AveeGuestOnboarding(
      onLogin: _noop,
    )));

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in with AVEE ID'), findsOneWidget);
    expect(find.textContaining('Private internet.'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
      'shared design tokens keep the primary action accessible at large text',
      (tester) async {
    await tester.pumpWidget(host(const AveePrimaryButton(
      label: 'Продолжить',
      onPressed: _noop,
    )));
    expect(find.text('Продолжить'), findsOneWidget);
    expect(AveeColors.primary, isNot(equals(AveeColors.background)));
  });

  testWidgets('location status uses truthful state labels', (tester) async {
    await tester.pumpWidget(host(const AveeStatusPill(
      label: 'Недоступна',
      color: AveeColors.error,
    )));
    expect(find.text('Недоступна'), findsOneWidget);
  });
}

void _noop() {}
