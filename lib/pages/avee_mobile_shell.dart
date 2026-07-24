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
                _menuItem(sheetContext, Icons.public_outlined, 'Локации', 1),
                _menuItem(sheetContext, Icons.speed_outlined, 'Скорость', 2),
                _menuItem(sheetContext, Icons.person_outline, 'Профиль и устройства', 3),
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
                    setState(() => tab = 3);
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
      int destination) => ListTile(
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
          const pages = <Widget>[
            AveeHomeDashboard(),
            AveeLocationsPage(),
            AveeSpeedPage(),
            AveeAccountPage(),
          ];
          return AveePage(
            child: Column(
              children: [
                AveeTopBar(onMenu: _openMenu),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(child: AveeLogo(compact: true)),
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
              const SizedBox(height: 48),
              Text(
                'Приватное подключение.\nБез сложных настроек.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AveeColors.text,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Создайте AVEE-аккаунт и получите 1 ГБ на 3 дня.',
                style: TextStyle(color: AveeColors.secondaryText, fontSize: 16),
              ),
              const SizedBox(height: 24),
              const _AveeOrb(),
              const SizedBox(height: 24),
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
              const SizedBox(height: 28),
              const Row(
                children: [
                  Expanded(
                      child: _Benefit(
                          icon: Icons.touch_app_outlined,
                          title: 'Один тап',
                          text: 'Без сложных настроек')),
                  Expanded(
                      child: _Benefit(
                          icon: Icons.auto_awesome_outlined,
                          title: 'Умные локации',
                          text: 'Доступный сервер')),
                  Expanded(
                      child: _Benefit(
                          icon: Icons.visibility_off_outlined,
                          title: 'Без журналов',
                          text: 'История не записывается')),
                ],
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

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AveeColors.primary, size: 22),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(
                    color: AveeColors.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(text,
                style: const TextStyle(
                    color: AveeColors.mutedText, fontSize: 11, height: 1.3)),
          ],
        ),
      );
}

class _AveeOrb extends StatelessWidget {
  const _AveeOrb();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 180,
        child: CustomPaint(
            painter: _OrbPainter(), child: const Center(child: AveeLogo())),
      );
}

class _OrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .36;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 3; i++) {
      paint.color = AveeColors.primary.withValues(alpha: .16 - i * .035);
      canvas.drawCircle(center, radius + i * 18, paint);
    }
    paint.style = PaintingStyle.fill;
    paint.color = AveeColors.primary.withValues(alpha: .06);
    canvas.drawCircle(center, radius + 34, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class AveeSpeedPage extends ConsumerWidget {
  const AveeSpeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficsProvider).list;
    final last = traffic.isEmpty ? null : traffic.last;
    final running = ref.watch(runTimeProvider.select((value) => value != null));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const SizedBox(height: 16),
        Text('Скорость',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AveeColors.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Только реальные значения активного туннеля.',
            style: TextStyle(color: AveeColors.secondaryText, fontSize: 15)),
        const SizedBox(height: 32),
        _SpeedGauge(
            value: last?.speed.toDouble() ?? 0,
            label: last == null ? '—' : last.down.toString()),
        const SizedBox(height: 30),
        const Divider(color: AveeColors.outline),
        _AveeDataRow(
            label: 'Загрузка',
            value: last?.down.toString() ?? '—',
            accent: AveeColors.primary),
        _AveeDataRow(
            label: 'Отдача',
            value: last?.up.toString() ?? '—',
            accent: AveeColors.signal),
        _AveeDataRow(
            label: 'Состояние',
            value: running ? 'Туннель активен' : 'Подключитесь для измерения'),
      ],
    );
  }
}

class _SpeedGauge extends StatelessWidget {
  const _SpeedGauge({required this.value, required this.label});
  final double value;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 226,
        child: CustomPaint(
          painter: _SpeedGaugePainter(value: value),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: const TextStyle(
                      color: AveeColors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('текущая скорость',
                  style: TextStyle(color: AveeColors.mutedText, fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _SpeedGaugePainter extends CustomPainter {
  const _SpeedGaugePainter({required this.value});
  final double value;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: 178, height: 178);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..color = AveeColors.outline;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..color = AveeColors.primary;
    canvas.drawArc(rect, math.pi * .72, math.pi * 1.56, false, track);
    canvas.drawArc(
        rect,
        math.pi * .72,
        math.pi *
            1.56 *
            (value <= 0 ? .05 : (value / (value + 100)).clamp(.05, .96)),
        false,
        fill);
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) =>
      oldDelegate.value != value;
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
            height: 344,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(double.infinity, 344),
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
                        AveeColors.violet.withValues(alpha: .14),
                        AveeColors.background,
                      ],
                    ),
                    border: Border.all(color: AveeColors.violet, width: 1.4),
                    boxShadow: const [
                      BoxShadow(color: Color(0x669B6CFF), blurRadius: 34, spreadRadius: 4),
                      BoxShadow(color: Color(0x55FFA516), blurRadius: 20, spreadRadius: 1),
                    ],
                  ),
                  child: const SizedBox(
                    width: 138,
                    height: 138,
                    child: Icon(Icons.power_settings_new_rounded,
                        color: AveeColors.primary, size: 62),
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
    final radius = math.min(size.width, size.height) * .35;
    final accent = AveeColors.primary;
    final alpha = active ? .48 : .30;
    final sphere = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = accent.withValues(alpha: alpha);

    for (var i = -9; i <= 9; i++) {
      final latitude = i / 10.0;
      final halfWidth = radius * math.sqrt(math.max(0, 1 - latitude * latitude));
      final path = Path();
      for (var step = 0; step <= 48; step++) {
        final t = step / 48;
        final x = center.dx - halfWidth + halfWidth * 2 * t;
        final wave = math.sin(t * math.pi * 5 + i * .42 + progress * math.pi * 2) * 3.2;
        final y = center.dy + radius * latitude + wave;
        if (step == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, sphere);
    }

    for (var i = -5; i <= 5; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * .12);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: radius * (1.1 + i.abs() * .08), height: radius * 2),
          sphere);
      canvas.restore();
    }

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AveeColors.violet.withValues(alpha: connecting ? .72 : .38);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-.22 + i * .45);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: radius * 3.0, height: radius * .92), orbitPaint);
      canvas.restore();
      final angle = progress * math.pi * 2 + i * 2.1;
      final dot = Offset(center.dx + math.cos(angle) * radius * 1.45,
          center.dy + math.sin(angle) * radius * .48);
      canvas.drawCircle(dot, 4.5, Paint()..color = i.isEven ? accent : AveeColors.violet);
    }
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
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 12, color: running ? AveeColors.primary : AveeColors.signal),
              const SizedBox(width: 12),
              Text(running ? 'CONNECTED' : connecting ? 'CONNECTING' : 'DISCONNECTED',
                  style: const TextStyle(color: AveeColors.signal, fontSize: 16, letterSpacing: 5, fontWeight: FontWeight.w400)),
            ]),
            const SizedBox(height: 16),
            Text(running ? 'Protected connection' : 'Ready to connect',
                style: const TextStyle(color: AveeColors.secondaryText, fontSize: 22, letterSpacing: .4)),
          ]),
        ),
        _SignalOrb(running: running, connecting: connecting),
        Container(
          height: 58,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AveeColors.primary.withValues(alpha: .16),
                AveeColors.violet.withValues(alpha: .18),
              ],
            ),
            border: Border.all(color: AveeColors.primary, width: 1.2),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x339B6CFF), blurRadius: 18)],
          ),
          child: Stack(
            children: [
              Opacity(
                opacity: 0,
                child: SizedBox.expand(child: StartButton(iconSize: 24)),
              ),
               IgnorePointer(
                 child: Center(
                   child: Row(mainAxisSize: MainAxisSize.min, children: [
                     Icon(Icons.power_settings_new_rounded,
                         color: AveeColors.primary, size: 24),
                     const SizedBox(width: 18),
                     Text(
                       running ? 'DISCONNECT' : 'CONNECT',
                       style: const TextStyle(
                         color: AveeColors.primary,
                         fontSize: 16,
                         fontWeight: FontWeight.w700,
                         letterSpacing: 3.5,
                       ),
                     ),
                   ]),
                 ),
               ),
            ],
          ),
        ),
        const SizedBox(height: 8),
         InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AveeLocationsPage())),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AveeColors.outline))),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AveeColors.primary.withValues(alpha: .09),
                  border: Border.all(color: AveeColors.primary.withValues(alpha: .45)),
                ),
                child: const Icon(Icons.location_on_outlined, color: AveeColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                     const Text('LOCATION',
                         style: TextStyle(
                             color: AveeColors.mutedText, fontSize: 13, letterSpacing: 3)),
                    const SizedBox(height: 3),
                     Text(location == 'AVEE' ? 'Smart Location' : location,
                        style: const TextStyle(
                            color: AveeColors.text,
                            fontWeight: FontWeight.w700)),
                  ])),
              const Icon(Icons.chevron_right, color: AveeColors.primary),
            ]),
          ),
        ),
         _AveeDataLine(icon: Icons.show_chart_rounded, label: 'DATA USAGE', value: state.trafficUsedBytes == null ? '0 B' : _bytesEnglish(state.trafficUsedBytes!)),
      ]);
  }
}

class _AveeDataLine extends StatelessWidget {
  const _AveeDataLine({required this.icon, required this.label, required this.value});
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
              AveeColors.violet.withValues(alpha: .06),
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
              color: AveeColors.violet.withValues(alpha: .10),
              border: Border.all(color: AveeColors.violet.withValues(alpha: .5)),
            ),
            child: Icon(icon, color: AveeColors.violet, size: 26),
          ),
          const SizedBox(width: 26),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AveeColors.mutedText, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: AveeColors.text, fontSize: 20, letterSpacing: .5)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AveeColors.primary, size: 32),
        ]),
      );
}

class AveeHomeDashboard extends ConsumerWidget {
  const AveeHomeDashboard({super.key});
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
