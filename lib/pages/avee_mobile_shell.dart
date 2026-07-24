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
                _menuItem(sheetContext, Icons.home_outlined, 'Главная', 0),
                _menuItem(sheetContext, Icons.person_outline,
                    'Профиль и устройства', 2),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined,
                      color: AveeColors.primary),
                  title: const Text('Подписка'),
                  subtitle: Text(aveeAccountState.access
                      ? 'Доступ активен'
                      : 'Выбрать тариф'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    AveePaywall.show(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune_outlined,
                      color: AveeColors.secondaryText),
                  title: const Text('Настройки подключения'),
                  subtitle: const Text('Always-on, DNS и режимы защиты'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => tab = 2);
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
            AveeHomeDashboard(onMenu: _openMenu),
            AveeLocationsPage(),
            AveeAccountPage(),
          ];
          return AveePage(
            child: Column(
              children: [
                if (tab != 0) AveeTopBar(onMenu: _openMenu),
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
                    child: const Text('Восстановить'),
                  ),
                ],
              ),
              const SizedBox(height: 56),
              Text(
                'Безопасный интернет.\nОдин понятный шаг.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AveeColors.text,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Создайте аккаунт и подключайтесь без ручной настройки.',
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
                    ? 'Создаём аккаунт…'
                    : 'Создать аккаунт',
                icon: Icons.add_rounded,
                onPressed:
                    aveeAccountState.loading ? null : () => _create(context),
              ),
              const SizedBox(height: 12),
              AveeSecondaryButton(
                label: 'Восстановить аккаунт',
                icon: Icons.key_rounded,
                onPressed: onRecovery,
              ),
              const SizedBox(height: 22),
              const Text(
                'Минимум данных для работы сервиса. Содержимое трафика не записывается.',
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
            height: 360,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(double.infinity, 360),
                  painter: _SignalOrbPainter(
                    progress: _controller.value,
                    active: widget.running,
                    connecting: widget.connecting,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AveeColors.surfaceRaised,
                        AveeColors.highlight.withValues(alpha: .14),
                        AveeColors.background,
                      ],
                    ),
                    border: Border.all(color: AveeColors.highlight, width: 1.4),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x559CA8B5),
                          blurRadius: 34,
                          spreadRadius: 4),
                      BoxShadow(
                          color: Color(0x55FFA516),
                          blurRadius: 20,
                          spreadRadius: 1),
                    ],
                  ),
                  child: const SizedBox(
                    width: 190,
                    height: 190,
                    child: Icon(Icons.power_settings_new_rounded,
                        color: AveeColors.primary, size: 78),
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
      const SizedBox(height: 18),
      Center(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AveeColors.signal.withValues(alpha: .14),
                  AveeColors.highlight.withValues(alpha: .10),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border:
                  Border.all(color: AveeColors.signal.withValues(alpha: .5)),
              boxShadow: const [
                BoxShadow(color: Color(0x339CA8B5), blurRadius: 18),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle,
                  size: 10,
                  color: running ? AveeColors.primary : AveeColors.signal),
              const SizedBox(width: 10),
              Text(
                  running
                      ? 'CONNECTED'
                      : connecting
                          ? 'CONNECTING'
                          : 'DISCONNECTED',
                  style: const TextStyle(
                      color: AveeColors.signal,
                      fontSize: 14,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(height: 16),
          Text(running ? 'Protected connection' : 'Ready to connect',
              style: const TextStyle(
                  color: AveeColors.secondaryText,
                  fontSize: 22,
                  letterSpacing: .4)),
        ]),
      ),
      _SignalOrb(running: running, connecting: connecting),
      Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AveeColors.primary.withValues(alpha: .24),
              AveeColors.highlight.withValues(alpha: .14),
            ],
          ),
          border: Border.all(color: AveeColors.primary, width: 1.2),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x339CA8B5), blurRadius: 18)
          ],
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
                      color: AveeColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3.5,
                    )),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AveeLocationsPage())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AveeColors.surface.withValues(alpha: .82),
                AveeColors.highlight.withValues(alpha: .08),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AveeColors.outline),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8)),
            ],
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AveeColors.primary.withValues(alpha: .09),
                border: Border.all(
                    color: AveeColors.primary.withValues(alpha: .45)),
              ),
              child: const Icon(Icons.location_on_outlined,
                  color: AveeColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('LOCATION',
                      style: TextStyle(
                          color: AveeColors.mutedText,
                          fontSize: 13,
                          letterSpacing: 3)),
                  const SizedBox(height: 3),
                  Text(location == 'AVEE' ? 'Smart Location' : location,
                      style: const TextStyle(
                          color: AveeColors.text, fontWeight: FontWeight.w700)),
                ])),
            const Icon(Icons.chevron_right, color: AveeColors.primary),
          ]),
        ),
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AveeColors.surface.withValues(alpha: .72),
              AveeColors.highlight.withValues(alpha: .06),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AveeColors.outline),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AveeColors.highlight.withValues(alpha: .10),
              border:
                  Border.all(color: AveeColors.highlight.withValues(alpha: .5)),
            ),
            child: Icon(icon, color: AveeColors.highlight, size: 26),
          ),
          const SizedBox(width: 26),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: AveeColors.mutedText,
                        fontSize: 13,
                        letterSpacing: 3)),
                const SizedBox(height: 8),
                Text(value,
                    style: const TextStyle(
                        color: AveeColors.text,
                        fontSize: 20,
                        letterSpacing: .5)),
              ])),
          const Icon(Icons.chevron_right_rounded,
              color: AveeColors.primary, size: 32),
        ]),
      );
}

class _NeonBrandHeader extends StatelessWidget {
  const _NeonBrandHeader({required this.onMenu});
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [AveeColors.primary, AveeColors.highlight],
            ).createShader(bounds),
            child: const Text(
              'A',
              style: TextStyle(
                color: Colors.white,
                fontSize: 62,
                height: .9,
                fontWeight: FontWeight.w800,
                letterSpacing: -5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const AveeLogo(compact: true, horizontal: true),
          const Spacer(),
          IconButton(
            onPressed: onMenu,
            tooltip: 'Меню',
            icon: const Icon(Icons.menu_rounded),
            color: AveeColors.primary,
            iconSize: 28,
          ),
        ],
      );
}

class AveeHomeDashboard extends ConsumerWidget {
  const AveeHomeDashboard({required this.onMenu, super.key});
  final VoidCallback onMenu;
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
              _NeonBrandHeader(onMenu: onMenu),
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
    ? 'Сервер AVEE временно недоступен. Попробуйте ещё раз.'
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
            Text('Локации',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AveeColors.text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'Статус обновляется по данным AVEE. Без выдуманных ping и нагрузки.',
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
                  child: Text('Локации пока недоступны.',
                      style: TextStyle(color: AveeColors.secondaryText)))
            else
              ...aveeAccountState.locations.map(_locationRow)
          ])));
  Widget _locationRow(Map<String, dynamic> item) {
    final name = item['name'] ?? item['code'] ?? 'Локация';
    final status = item['status'] ?? 'unknown';
    final label = status == 'available' || status == 'online'
        ? 'Доступна'
        : status == 'degraded'
            ? 'Высокая нагрузка'
            : 'Недоступна';
    final color = label == 'Доступна'
        ? AveeColors.primary
        : label == 'Высокая нагрузка'
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
            const Text('Проверено по данным AVEE',
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
            Text('Аккаунт',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AveeColors.text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            AveePanel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Номер AVEE-аккаунта',
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
                            ? 'Доступ активен'
                            : 'Нужна подписка',
                        style: const TextStyle(
                            color: AveeColors.text,
                            fontWeight: FontWeight.w600)),
                  ])
                ])),
            const SizedBox(height: 16),
            AveePrimaryButton(
                label: 'Открыть тарифы',
                icon: Icons.workspace_premium_outlined,
                onPressed: () => AveePaywall.show(context)),
            const SizedBox(height: 12),
            AveeSecondaryButton(
                label: 'Восстановить покупки',
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
            const Text('Аккаунт и безопасность',
                style: TextStyle(
                    color: AveeColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
                'Храните recovery-код в безопасном месте. Он нужен для восстановления аккаунта на новом устройстве. AVEE не сохраняет содержимое вашего трафика.',
                style: TextStyle(color: AveeColors.secondaryText, height: 1.4)),
            const SizedBox(height: 32),
            AveeSecondaryButton(
                label: 'Удалить аккаунт',
                icon: Icons.delete_outline,
                onPressed: () => _delete(context))
          ]));
  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Удалить аккаунт?'),
                content: const Text('Доступ и локальные данные будут удалены.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Удалить'))
                ]));
    if (ok == true) await aveeAccountState.deleteAccount();
  }

  Future<void> _openAlwaysOn(BuildContext context) async {
    final opened = await app?.openVpnSettings() ?? false;
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось открыть настройки Always-on VPN')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Включите Always-on VPN и «Блокировать подключения без VPN»')));
  }
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
        Text('Восстановить аккаунт',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AveeColors.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Введите номер AVEE-аккаунта и recovery-код.',
            style: TextStyle(color: AveeColors.secondaryText)),
        const SizedBox(height: 28),
        TextField(
            controller: account,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Номер аккаунта')),
        const SizedBox(height: 16),
        TextField(
            controller: code,
            obscureText: obscure,
            decoration: InputDecoration(
                labelText: 'Recovery-код',
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
            label: aveeAccountState.loading ? 'Проверяем…' : 'Восстановить',
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
        Text('Сохраните данные аккаунта',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AveeColors.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
            'Recovery-код показывается один раз. Без него восстановить доступ будет нельзя.',
            style: TextStyle(color: AveeColors.secondaryText, height: 1.4)),
        const SizedBox(height: 26),
        AveePanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Номер аккаунта',
              style: TextStyle(color: AveeColors.secondaryText)),
          const SizedBox(height: 6),
          SelectableText(widget.account,
              style: const TextStyle(
                  color: AveeColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          const Text('Recovery-код',
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
              label: const Text('Скопировать'))
        ])),
        const SizedBox(height: 18),
        const Text(
            'Не отправляйте код посторонним и не храните его в открытом виде.',
            style: TextStyle(color: AveeColors.warning)),
        const SizedBox(height: 20),
        CheckboxListTile(
            value: saved,
            onChanged: (value) => setState(() => saved = value ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text('Я сохранил код',
                style: TextStyle(color: AveeColors.text))),
        const SizedBox(height: 14),
        AveePrimaryButton(
            label: 'Продолжить',
            onPressed: saved ? () => Navigator.pop(context) : null)
      ])));
}
