import 'dart:math' as math;

import 'package:avee/providers/providers.dart';
import 'package:avee/plugins/app.dart';
import 'package:avee/services/avee_account.dart';
import 'package:avee/services/avee_billing.dart';
import 'package:avee/state.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:avee/views/dashboard/widgets/start_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AveeMobileShell extends ConsumerStatefulWidget {
  const AveeMobileShell({super.key});
  @override
  ConsumerState<AveeMobileShell> createState() => _AveeMobileShellState();
}

class _AveeMobileShellState extends ConsumerState<AveeMobileShell> {
  int tab = 0;

  void _openSettings() => setState(() => tab = 3);

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AveeColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: ListenableBuilder(
            listenable: aveeAccountState,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('AVEE',
                      style: TextStyle(
                          color: AveeColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4)),
                ),
                const SizedBox(height: 18),
                _menuItem(sheetContext, Icons.home_outlined, 'Home', 0),
                _menuItem(
                    sheetContext, Icons.person_outline, 'Account & devices', 2),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined,
                      color: AveeColors.primary),
                  title: const Text('Subscription'),
                  subtitle: Text(aveeAccountState.access
                      ? 'Access is active'
                      : 'Choose a plan'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    AveePaywall.show(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext sheetContext, IconData icon, String label,
          int destination) =>
      ListTile(
        leading: Icon(icon,
            color: destination == tab
                ? AveeColors.primary
                : AveeColors.secondaryText),
        title: Text(label),
        selected: destination == tab,
        selectedTileColor: AveeColors.primary.withValues(alpha: .08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () {
          Navigator.pop(sheetContext);
          setState(() => tab = destination);
        },
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) {
          if (aveeAccountState.session == null) {
            return AveePage(child: AveeGuestOnboarding(onRecovery: _recover));
          }
          final pages = <Widget>[
            AveeHomeDashboard(onSettings: _openSettings),
            AveeLocationsPage(),
            AveeAccountPage(),
            AveeConnectionSettingsPage(),
          ];
          return AveePage(
            child: Column(
              children: [
                if (tab != 0) AveeTopBar(onSettings: _openSettings),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    reverseDuration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(tab),
                      child: pages[tab],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _recover() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AveeRecoveryPage()),
    );
  }
}

class AveeGuestOnboarding extends StatelessWidget {
  const AveeGuestOnboarding({required this.onRecovery, super.key});
  final VoidCallback onRecovery;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: AveeLogo(compact: true, horizontal: true),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onRecovery,
                    child: const Text('Recover'),
                  ),
                ],
              ),
              const SizedBox(height: 56),
              Text(
                'Private internet.\nOne clear step.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AveeColors.text,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Create an account and connect without manual setup.',
                style: TextStyle(color: AveeColors.secondaryText, fontSize: 16),
              ),
              const SizedBox(height: 24),
              const _AveePulse(),
              const SizedBox(height: 18),
              if (aveeAccountState.error != null) ...[
                AveePanel(
                  child: Text(
                    _friendlyError(aveeAccountState.error!),
                    style: const TextStyle(color: AveeColors.error),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              AveePrimaryButton(
                label: aveeAccountState.loading
                    ? 'Creating account…'
                    : 'Create account',
                icon: Icons.add_rounded,
                onPressed:
                    aveeAccountState.loading ? null : () => _create(context),
              ),
              const SizedBox(height: 12),
              AveeSecondaryButton(
                label: 'Recover account',
                icon: Icons.key_rounded,
                onPressed: onRecovery,
              ),
              const SizedBox(height: 22),
              const Text(
                'Only the data needed to run the service. Traffic content is not recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AveeColors.mutedText, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      );

  Future<void> _create(BuildContext context) async {
    await aveeAccountState.createAccount();
    if (!context.mounted || aveeAccountState.session == null) return;
    final code = aveeAccountState.recoveryCode;
    if (code == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AveeRecoveryCodePage(
          account: aveeAccountState.session!.accountNumber,
          code: code,
        ),
      ),
    );
  }
}

class _AveePulse extends StatefulWidget {
  const _AveePulse();

  @override
  State<_AveePulse> createState() => _AveePulseState();
}

class _AveePulseState extends State<_AveePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 220,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _PulsePainter(progress: _controller.value),
              child: const Center(
                child: Icon(Icons.power_settings_new_rounded,
                    color: AveeColors.primary, size: 58),
              ),
            ),
          ),
        ),
      );
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .28;
    final pulse = .88 + math.sin(progress * math.pi * 2) * .06;
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        AveeColors.primary.withValues(alpha: .22),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: radius * 2.1));
    canvas.drawCircle(center, radius * 2.1, glow);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AveeColors.outline;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(center, radius * (1.0 + i * .24) * pulse, paint);
    }
    paint
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = AveeColors.primary;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 1.48),
      progress * math.pi * 2,
      math.pi * .56,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _AveeDataRow extends StatelessWidget {
  const _AveeDataRow(
      {required this.label, required this.value, this.accent, this.icon});
  final String label;
  final String value;
  final Color? accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 58),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AveeColors.outline))),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AveeColors.mutedText),
              const SizedBox(width: 10)
            ],
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: AveeColors.secondaryText))),
            Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: accent ?? AveeColors.text,
                        fontWeight: FontWeight.w700))),
          ],
        ),
      );
}

String _locationName(AveeAccountState state) {
  for (final item in state.locations) {
    final status = '${item['status'] ?? ''}';
    if (status == 'available' || status == 'online') {
      return '${item['name'] ?? item['code'] ?? 'AVEE'}';
    }
  }
  return 'AVEE';
}

String _flagForLocation(String value) {
  final name = value.toLowerCase();
  if (name.contains('united kingdom') ||
      name.contains('uk') ||
      name.contains('англ')) return '🇬🇧';
  if (name.contains('france') || name.contains('франц')) return '🇫🇷';
  if (name.contains('germany') || name.contains('герм')) return '🇩🇪';
  if (name.contains('australia') || name.contains('австрал')) return '🇦🇺';
  if (name.contains('armenia') || name.contains('арм')) return '🇦🇲';
  return '🌐';
}

class _SignalOrb extends StatefulWidget {
  const _SignalOrb({required this.running, required this.connecting});
  final bool running;
  final bool connecting;

  @override
  State<_SignalOrb> createState() => _SignalOrbState();
}

class _SignalOrbState extends State<_SignalOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => SizedBox(
            height: 292,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(double.infinity, 292),
                  painter: _SignalOrbPainter(
                    progress: _controller.value,
                    active: widget.running,
                    connecting: widget.connecting,
                  ),
                ),
                const SizedBox(
                  width: 148,
                  height: 148,
                  child: Center(
                    child: Icon(Icons.power_settings_new_rounded,
                        color: AveeColors.primary, size: 70),
                  ),
                ),
                Opacity(
                  opacity: 0,
                  child: SizedBox.expand(child: StartButton(iconSize: 58)),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SignalOrbPainter extends CustomPainter {
  const _SignalOrbPainter({
    required this.progress,
    required this.active,
    required this.connecting,
  });
  final double progress;
  final bool active;
  final bool connecting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .34;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AveeColors.highlight.withValues(alpha: .24),
          AveeColors.primary.withValues(alpha: .14),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.55));
    canvas.drawCircle(center, radius * 1.5, glow);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = connecting ? 2.4 : 1.5
      ..color = AveeColors.highlight.withValues(alpha: connecting ? .68 : .38);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (.82 + i * .16), ring);
    }
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = AveeColors.primary.withValues(alpha: active ? .92 : .72);
    final sweepRect = Rect.fromCircle(center: center, radius: radius * 1.14);
    canvas.drawArc(
        sweepRect, progress * math.pi * 2, math.pi * .42, false, sweep);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = AveeColors.primary.withValues(alpha: active ? .9 : .7);
    canvas.drawCircle(center, radius * .72, rim);
  }

  @override
  bool shouldRepaint(covariant _SignalOrbPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.connecting != connecting;
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.state,
    required this.running,
    required this.connecting,
  });
  final AveeAccountState state;
  final bool running;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final location = _locationName(state);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 28),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            running
                ? 'PROTECTED'
                : connecting
                    ? 'CONNECTING'
                    : 'READY TO CONNECT',
            style: const TextStyle(
                color: AveeColors.mutedText,
                fontSize: 12,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w600),
          ),
          Icon(Icons.circle,
              size: 8, color: running ? AveeColors.primary : AveeColors.signal),
        ],
      ),
      const SizedBox(height: 5),
      Text(running ? 'Connection is active' : 'One step to private access',
          style: const TextStyle(
              color: AveeColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w700)),
      _SignalOrb(running: running, connecting: connecting),
      Container(
        height: 58,
        decoration: BoxDecoration(
          color: AveeColors.primary,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Stack(
          children: [
            Opacity(
              opacity: 0,
              child: SizedBox.expand(child: StartButton(iconSize: 24)),
            ),
            IgnorePointer(
              child: Center(
                child: Text(running ? 'DISCONNECT' : 'CONNECT',
                    style: const TextStyle(
                      color: AveeColors.background,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                    )),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      InkWell(
        borderRadius: BorderRadius.circular(2),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AveeLocationsPage())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(children: [
            const Icon(Icons.public, color: AveeColors.primary, size: 22),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('LOCATION',
                      style: TextStyle(
                          color: AveeColors.mutedText,
                          fontSize: 13,
                          letterSpacing: 2.2)),
                  const SizedBox(height: 3),
                  Text(location == 'AVEE' ? 'Smart Location' : location,
                      style: const TextStyle(color: AveeColors.text)),
                ])),
            const Icon(Icons.chevron_right, color: AveeColors.primary),
          ]),
        ),
      ),
      const Divider(color: AveeColors.outline, height: 1),
      _AveeDataLine(
          icon: Icons.show_chart_rounded,
          label: 'DATA USAGE',
          value: state.trafficUsedBytes == null
              ? '0 B'
              : _bytesEnglish(state.trafficUsedBytes!)),
    ]);
  }
}

class _AveeDataLine extends StatelessWidget {
  const _AveeDataLine(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(children: [
          Icon(icon, color: AveeColors.secondaryText, size: 22),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: AveeColors.mutedText,
                        fontSize: 13,
                        letterSpacing: 2.2)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: AveeColors.text)),
              ])),
        ]),
      );
}

class _AveeBrandHeader extends StatelessWidget {
  const _AveeBrandHeader({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const AveeLogo(compact: true, horizontal: true),
          const Spacer(),
          IconButton(
            onPressed: onSettings,
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            color: AveeColors.primary,
            iconSize: 28,
          ),
        ],
      );
}

class AveeHomeDashboard extends ConsumerWidget {
  const AveeHomeDashboard({required this.onSettings, super.key});
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(runTimeProvider.select((value) => value != null));
    final connecting = globalState.isConnecting.value;
    return ListenableBuilder(
      listenable: aveeAccountState,
      builder: (context, _) {
        final state = aveeAccountState;
        return RefreshIndicator(
          onRefresh: state.refresh,
          color: AveeColors.primary,
          backgroundColor: AveeColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              _AveeBrandHeader(onSettings: onSettings),
              _ConnectionCard(
                state: state,
                running: running,
                connecting: connecting,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}';
String _bytesEnglish(int value) => value >= 1000000000
    ? '${(value / 1000000000).toStringAsFixed(1)} GB'
    : value >= 1000000
        ? '${(value / 1000000).toStringAsFixed(0)} MB'
        : '${(value / 1000).toStringAsFixed(0)} KB';
String _friendlyError(String error) => error == 'Backend unavailable'
    ? 'AVEE server is temporarily unavailable. Try again.'
    : error;

class AveeLocationsPage extends StatefulWidget {
  const AveeLocationsPage({super.key});
  @override
  State<AveeLocationsPage> createState() => _AveeLocationsPageState();
}

class _AveeLocationsPageState extends State<AveeLocationsPage> {
  @override
  void initState() {
    super.initState();
    aveeAccountState.refreshLocations();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: aveeAccountState,
      builder: (context, _) => RefreshIndicator(
          onRefresh: aveeAccountState.refreshLocations,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const SizedBox(height: 16),
            Text('Locations',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AveeColors.text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'Status is based on AVEE data. No invented ping or load values.',
                style: TextStyle(color: AveeColors.secondaryText)),
            const SizedBox(height: 20),
            if (aveeAccountState.locationsLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child:
                          CircularProgressIndicator(color: AveeColors.primary)))
            else if (aveeAccountState.locations.isEmpty)
              const AveePanel(
                  child: Text('Locations are currently unavailable.',
                      style: TextStyle(color: AveeColors.secondaryText)))
            else
              ...aveeAccountState.locations.map(_locationRow)
          ])));
  Widget _locationRow(Map<String, dynamic> item) {
    final name = item['name'] ?? item['code'] ?? 'Location';
    final status = item['status'] ?? 'unknown';
    final label = status == 'available' || status == 'online'
        ? 'Available'
        : status == 'degraded'
            ? 'High load'
            : 'Unavailable';
    final color = label == 'Available'
        ? AveeColors.primary
        : label == 'High load'
            ? AveeColors.warning
            : AveeColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AveeColors.outline)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AveeColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.public, color: AveeColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$name',
                style: const TextStyle(
                    color: AveeColors.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Verified from AVEE data',
                style: TextStyle(color: AveeColors.mutedText, fontSize: 11)),
          ]),
        ),
        AveeStatusPill(label: label, color: color),
      ]),
    );
  }
}

class AveeAccountPage extends StatelessWidget {
  const AveeAccountPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: aveeAccountState,
      builder: (context, _) =>
          ListView(padding: const EdgeInsets.all(16), children: [
            const SizedBox(height: 16),
            Text('Account',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AveeColors.text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            AveePanel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('AVEE account number',
                      style: TextStyle(color: AveeColors.secondaryText)),
                  const SizedBox(height: 8),
                  SelectableText(aveeAccountState.session?.accountNumber ?? '—',
                      style: const TextStyle(
                          color: AveeColors.text,
                          fontSize: 22,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(Icons.circle,
                        size: 8,
                        color: aveeAccountState.access
                            ? AveeColors.primary
                            : AveeColors.warning),
                    const SizedBox(width: 8),
                    Text(
                        aveeAccountState.access
                            ? 'Access is active'
                            : 'Subscription required',
                        style: const TextStyle(
                            color: AveeColors.text,
                            fontWeight: FontWeight.w600)),
                  ])
                ])),
            const SizedBox(height: 16),
            AveePrimaryButton(
                label: 'View plans',
                icon: Icons.workspace_premium_outlined,
                onPressed: () => AveePaywall.show(context)),
            const SizedBox(height: 12),
            AveeSecondaryButton(
                label: 'Restore purchases',
                icon: Icons.restore,
                onPressed: aveeAccountState.loading
                    ? null
                    : () => aveeAccountState.restoreGooglePurchases()),
            const SizedBox(height: 12),
            AveeSecondaryButton(
                label: 'Always-on / Kill switch',
                icon: Icons.lock_outline,
                onPressed: () => _openAlwaysOn(context)),
            const SizedBox(height: 32),
            const Text('Account & security',
                style: TextStyle(
                    color: AveeColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
                'Keep your recovery code in a safe place. It is required to restore your account on a new device. AVEE does not record traffic content.',
                style: TextStyle(color: AveeColors.secondaryText, height: 1.4)),
            const SizedBox(height: 32),
            AveeSecondaryButton(
                label: 'Delete account',
                icon: Icons.delete_outline,
                onPressed: () => _delete(context))
          ]));
  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Delete account?'),
                content: const Text('Access and local data will be removed.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ]));
    if (ok == true) await aveeAccountState.deleteAccount();
  }

  Future<void> _openAlwaysOn(BuildContext context) async {
    final opened = await app?.openVpnSettings() ?? false;
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open Always-on VPN settings')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Enable Always-on VPN and “Block connections without VPN”')));
  }
}

class AveeConnectionSettingsPage extends StatelessWidget {
  const AveeConnectionSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text('Connection settings',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AveeColors.text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Control how AVEE protects your connection.',
              style: TextStyle(color: AveeColors.secondaryText)),
          const SizedBox(height: 24),
          const AveePanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Security',
                    style: TextStyle(
                        color: AveeColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text(
                    'Always-on VPN reconnects when the tunnel drops. Android controls the final system policy.',
                    style: TextStyle(
                        color: AveeColors.secondaryText, height: 1.4)),
              ])),
          const SizedBox(height: 16),
          AveePrimaryButton(
              label: 'Open Android VPN settings',
              icon: Icons.settings_outlined,
              onPressed: () => _openAlwaysOnVpn(context)),
          const SizedBox(height: 12),
          const AveePanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Connection defaults',
                    style: TextStyle(
                        color: AveeColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 14),
                _AveeSettingLine(label: 'Protocol', value: 'Automatic'),
                _AveeSettingLine(label: 'DNS protection', value: 'Enabled'),
                _AveeSettingLine(
                    label: 'IPv6 leak protection', value: 'Enabled'),
              ])),
        ],
      );
}

class _AveeSettingLine extends StatelessWidget {
  const _AveeSettingLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: AveeColors.secondaryText)),
            Text(value,
                style: const TextStyle(
                    color: AveeColors.primary, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

Future<void> _openAlwaysOnVpn(BuildContext context) async {
  final opened = await app?.openVpnSettings() ?? false;
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Always-on VPN settings')));
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:
          Text('Enable Always-on VPN and “Block connections without VPN”')));
}

class AveeRecoveryPage extends StatefulWidget {
  const AveeRecoveryPage({super.key});
  @override
  State<AveeRecoveryPage> createState() => _AveeRecoveryPageState();
}

class _AveeRecoveryPageState extends State<AveeRecoveryPage> {
  final account = TextEditingController();
  final code = TextEditingController();
  bool obscure = true;
  @override
  void dispose() {
    account.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AveeColors.background,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const AveeLogo(compact: true)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 28),
        Text('Recover account',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AveeColors.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Enter your AVEE account number and recovery code.',
            style: TextStyle(color: AveeColors.secondaryText)),
        const SizedBox(height: 28),
        TextField(
            controller: account,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Account number')),
        const SizedBox(height: 16),
        TextField(
            controller: code,
            obscureText: obscure,
            decoration: InputDecoration(
                labelText: 'Recovery code',
                suffixIcon: IconButton(
                    onPressed: () => setState(() => obscure = !obscure),
                    icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off)))),
        if (aveeAccountState.error != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_friendlyError(aveeAccountState.error!),
                  style: const TextStyle(color: AveeColors.error))),
        const SizedBox(height: 28),
        AveePrimaryButton(
            label: aveeAccountState.loading ? 'Checking…' : 'Recover',
            onPressed: aveeAccountState.loading
                ? null
                : () async {
                    if (account.text.trim().isEmpty || code.text.trim().isEmpty)
                      return;
                    await aveeAccountState.recoverAccount(
                        accountNumber: account.text, recoveryCode: code.text);
                    if (mounted && aveeAccountState.session != null)
                      Navigator.pop(context);
                  })
      ]));
}

class AveeRecoveryCodePage extends StatefulWidget {
  const AveeRecoveryCodePage(
      {required this.account, required this.code, super.key});
  final String account;
  final String code;
  @override
  State<AveeRecoveryCodePage> createState() => _AveeRecoveryCodePageState();
}

class _AveeRecoveryCodePageState extends State<AveeRecoveryCodePage> {
  bool saved = false;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AveeColors.background,
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 38),
        const AveeLogo(),
        const SizedBox(height: 42),
        Text('Save your account details',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AveeColors.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
            'Your recovery code is shown once. Without it, access cannot be restored.',
            style: TextStyle(color: AveeColors.secondaryText, height: 1.4)),
        const SizedBox(height: 26),
        AveePanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Account number',
              style: TextStyle(color: AveeColors.secondaryText)),
          const SizedBox(height: 6),
          SelectableText(widget.account,
              style: const TextStyle(
                  color: AveeColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          const Text('Recovery code',
              style: TextStyle(color: AveeColors.secondaryText)),
          const SizedBox(height: 6),
          SelectableText(widget.code,
              style: const TextStyle(
                  color: AveeColors.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextButton.icon(
              onPressed: () => Clipboard.setData(
                  ClipboardData(text: '${widget.account}\n${widget.code}')),
              icon: const Icon(Icons.copy),
              label: const Text('Copy'))
        ])),
        const SizedBox(height: 18),
        const Text('Do not share the code or store it in plain sight.',
            style: TextStyle(color: AveeColors.warning)),
        const SizedBox(height: 20),
        CheckboxListTile(
            value: saved,
            onChanged: (value) => setState(() => saved = value ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text('I saved the code',
                style: TextStyle(color: AveeColors.text))),
        const SizedBox(height: 14),
        AveePrimaryButton(
            label: 'Continue',
            onPressed: saved ? () => Navigator.pop(context) : null)
      ])));
}
