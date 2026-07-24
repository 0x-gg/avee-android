import 'dart:async';
import 'dart:math' as math;

import 'package:avee/providers/providers.dart';
import 'package:avee/common/constant.dart';
import 'package:avee/services/avee_account.dart';
import 'package:avee/services/avee_billing.dart';
import 'package:avee/services/avee_remote_config.dart';
import 'package:avee/state.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:avee/views/dashboard/widgets/start_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> openAveeMenu(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AveeColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AveeLogo(compact: true, horizontal: true),
              ),
            ),
            _aveeMenuTile(
              sheetContext,
              Icons.person_outline,
              'Account',
              () => _pushAveePage(context, const AveeAccountPage()),
            ),
            _aveeMenuTile(
              sheetContext,
              Icons.workspace_premium_outlined,
              'Subscription',
              () => _pushAveePage(context, const AveeSubscriptionPage()),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _aveeMenuTile(
  BuildContext sheetContext,
  IconData icon,
  String label,
  VoidCallback action,
) =>
    ListTile(
      leading: Icon(icon, color: AveeColors.primary),
      title: Text(label, style: const TextStyle(color: AveeColors.text)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: () {
        Navigator.pop(sheetContext);
        action();
      },
    );

Future<void> _pushAveePage(BuildContext context, Widget page) async {
  // Replace stacked sub-screens so Back always returns to Home.
  final navigator = Navigator.of(context);
  navigator.popUntil((route) => route.isFirst);
  await navigator.push<void>(MaterialPageRoute(builder: (_) => page));
}

class AveeMobileShell extends ConsumerStatefulWidget {
  const AveeMobileShell({super.key});
  @override
  ConsumerState<AveeMobileShell> createState() => _AveeMobileShellState();
}

class _AveeMobileShellState extends ConsumerState<AveeMobileShell> {
  bool _syncingManagedProfile = false;
  bool _removingManagedProfile = false;
  bool? _lastAccess;
  String? _lastAccountId;
  Timer? _accountRefreshTimer;

  @override
  void initState() {
    super.initState();
    aveeAccountState.addListener(_accountChanged);
    unawaited(aveeAccountState.refreshLocations());
    WidgetsBinding.instance.addPostFrameCallback((_) => _accountChanged());
    _accountRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          aveeAccountState.session != null &&
          !aveeAccountState.loading) {
        unawaited(aveeAccountState.refresh());
      }
    });
  }

  @override
  void dispose() {
    _accountRefreshTimer?.cancel();
    aveeAccountState.removeListener(_accountChanged);
    super.dispose();
  }

  void _accountChanged() {
    final accountId = aveeAccountState.session?.accountId;
    final accessChanged =
        _lastAccess != aveeAccountState.access || _lastAccountId != accountId;
    _lastAccess = aveeAccountState.access;
    _lastAccountId = accountId;
    if (aveeAccountState.session == null || !aveeAccountState.access) {
      if (!_removingManagedProfile &&
          (accessChanged || ref.read(currentProfileProvider) != null)) {
        unawaited(_removeManagedProfile());
      }
      return;
    }
    if (_syncingManagedProfile ||
        (!accessChanged && ref.read(currentProfileProvider) != null)) {
      return;
    }
    unawaited(_syncManagedProfile());
  }

  Future<void> _removeManagedProfile() async {
    _removingManagedProfile = true;
    try {
      await globalState.appController.removeManagedProfile();
    } finally {
      _removingManagedProfile = false;
    }
  }

  Future<void> _syncManagedProfile() async {
    _syncingManagedProfile = true;
    try {
      final yaml = await aveeAccountState.refreshManagedProfile();
      if (yaml != null) {
        await globalState.appController.installManagedProfile(yaml);
      }
    } catch (_) {
      // Account state exposes profile/API failures to the UI. Keep listener
      // callbacks from becoming unhandled asynchronous errors.
    } finally {
      _syncingManagedProfile = false;
    }
  }

  Future<void> _recover() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AveeRecoveryPage()),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) {
          if (aveeAccountState.session == null) {
            return AveePage(
              child: AveeGuestOnboarding(
                onRecovery: _recover,
                onSettings: () => openAveeMenu(context),
              ),
            );
          }
          return AveePage(
            child: AveeHomeDashboard(
              onSettings: () => openAveeMenu(context),
              onPrepareProfile: _syncManagedProfile,
              onOpenLocations: () =>
                  _pushAveePage(context, const AveeLocationsPage()),
            ),
          );
        },
      );
}

class AveeGuestOnboarding extends StatelessWidget {
  const AveeGuestOnboarding({
    required this.onRecovery,
    required this.onSettings,
    super.key,
  });
  final VoidCallback onRecovery;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) => Column(
          children: [
            AveeAppBar(
              title: 'AVEE VPN',
              onMenu: onSettings,
              actionIcon: Icons.settings_outlined,
              actionTooltip: 'Settings',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 28),
                    Text(
                      'Private internet.\nOne clear step.',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: AveeColors.text,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Create an account and connect without manual setup.',
                      style: TextStyle(
                        color: AveeColors.secondaryText,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _AveePulse(),
                    const SizedBox(height: 20),
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
                      onPressed: aveeAccountState.loading
                          ? null
                          : () => _create(context),
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
                        color: AveeColors.mutedText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
                child: Icon(
                  Icons.power_settings_new_rounded,
                  color: AveeColors.primary,
                  size: 58,
                ),
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

String _formatRuntime(int? elapsedMilliseconds) {
  final value = (elapsedMilliseconds ?? 0) ~/ 1000;
  final h = (value ~/ 3600).toString().padLeft(2, '0');
  final m = ((value % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (value % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String _friendlyError(String error) => error == 'Backend unavailable'
    ? 'AVEE server is temporarily unavailable. Try again.'
    : error;

String _bytesEnglish(int value) => value >= 1000000000
    ? '${(value / 1000000000).toStringAsFixed(1)} GB'
    : value >= 1000000
        ? '${(value / 1000000).toStringAsFixed(0)} MB'
        : '${(value / 1000).toStringAsFixed(0)} KB';

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.'
    '${value.year}';

class AveeHomeDashboard extends ConsumerWidget {
  const AveeHomeDashboard({
    required this.onSettings,
    required this.onPrepareProfile,
    required this.onOpenLocations,
    super.key,
  });

  final VoidCallback onSettings;
  final Future<void> Function() onPrepareProfile;
  final VoidCallback onOpenLocations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runSeconds = ref.watch(runTimeProvider);
    final running = runSeconds != null;
    final connecting = globalState.isConnecting.value;
    final hasProfile = ref.watch(currentProfileProvider) != null;

    return ListenableBuilder(
      listenable: aveeAccountState,
      builder: (context, _) {
        final locationItem = aveeAccountState.selectedLocationItem;
        final location = locationItem?['name']?.toString() ??
            (aveeAccountState.locations.isEmpty
                ? 'No locations available'
                : 'Loading location…');
        final flag = locationItem?['flag']?.toString();
        return Column(
          children: [
            AveeAppBar(
              title: 'AVEE VPN',
              onMenu: onSettings,
              actionIcon: Icons.settings_outlined,
              actionTooltip: 'Settings',
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await aveeAccountState.refresh();
                  await aveeAccountState.refreshLocations();
                },
                color: AveeColors.primary,
                backgroundColor: AveeColors.surface,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    const SizedBox(height: 28),
                    Text(
                      running
                          ? 'YOUR CONNECTION IS Protected.'
                          : connecting
                              ? 'YOUR CONNECTION IS Connecting…'
                              : 'YOUR CONNECTION IS Ready.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AveeColors.secondaryText,
                        fontSize: 14,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SignalOrb(
                      running: running,
                      connecting: connecting,
                      canConnect: aveeAccountState.access && hasProfile,
                      onUnavailable: () async {
                        if (!aveeAccountState.access) {
                          if (!aveeAccountState.trialAvailable) {
                            showDialog<void>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                backgroundColor: AveeColors.surface,
                                title: const Text(
                                  'Trial already used',
                                  style: TextStyle(color: AveeColors.text),
                                ),
                                content: const Text(
                                  'This device already activated a trial on another AVEE account. Recover that account to continue.',
                                  style: TextStyle(
                                    color: AveeColors.secondaryText,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: const Text('Close'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AveeRecoveryPage(),
                                        ),
                                      );
                                    },
                                    child: const Text('Recover account'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }
                          _pushAveePage(
                            context,
                            const AveeSubscriptionPage(),
                          );
                          return;
                        }
                        await onPrepareProfile();
                        if (!context.mounted) return;
                        if (ref.read(currentProfileProvider) != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'VPN profile is ready. Tap Connect again.',
                              ),
                            ),
                          );
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              aveeAccountState.error ??
                                  'Could not prepare the VPN profile.',
                            ),
                          ),
                        );
                      },
                    ),
                    Text(
                      running
                          ? 'Tap to Disconnect'
                          : connecting
                              ? 'Connecting…'
                              : 'Tap to Connect',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AveeColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatRuntime(runSeconds),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AveeColors.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 28),
                    AveePanel(
                      onTap: onOpenLocations,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (flag != null && flag.isNotEmpty)
                            Text(flag, style: const TextStyle(fontSize: 28))
                          else
                            const Icon(
                              Icons.public_outlined,
                              color: AveeColors.primary,
                              size: 28,
                            ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              location,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AveeColors.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AveeColors.mutedText,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SignalOrb extends StatefulWidget {
  const _SignalOrb({
    required this.running,
    required this.connecting,
    required this.canConnect,
    required this.onUnavailable,
  });
  final bool running;
  final bool connecting;
  final bool canConnect;
  final VoidCallback onUnavailable;

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
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(double.infinity, 280),
                  painter: _SignalOrbPainter(
                    progress: _controller.value,
                    active: widget.running,
                    connecting: widget.connecting,
                  ),
                ),
                Icon(
                  Icons.power_settings_new_rounded,
                  color: widget.running || widget.connecting
                      ? AveeColors.primary
                      : AveeColors.highlight,
                  size: 64,
                ),
                if (widget.canConnect)
                  Opacity(
                    opacity: 0,
                    child: SizedBox.expand(child: StartButton(iconSize: 58)),
                  )
                else
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: widget.onUnavailable,
                      ),
                    ),
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
    final accent =
        active || connecting ? AveeColors.primary : AveeColors.outline;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AveeColors.primary.withValues(alpha: active ? .28 : .12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 2.2));
    canvas.drawCircle(center, radius * 2.0, glow);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = accent.withValues(alpha: .85);
    canvas.drawCircle(center, radius, ring);

    final soft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AveeColors.highlight.withValues(alpha: .25);
    canvas.drawCircle(center, radius * 1.18, soft);

    if (active || connecting) {
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = AveeColors.primary;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        progress * math.pi * 2,
        math.pi * (connecting ? .7 : 1.4),
        false,
        sweep,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalOrbPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.connecting != connecting;
}

class AveeLocationsPage extends ConsumerStatefulWidget {
  const AveeLocationsPage({super.key});
  @override
  ConsumerState<AveeLocationsPage> createState() => _AveeLocationsPageState();
}

class _AveeLocationsPageState extends ConsumerState<AveeLocationsPage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(aveeAccountState.refreshLocations());
    unawaited(_refreshManagedProfile());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AveeColors.background,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: aveeAccountState,
            builder: (context, _) {
              final query = _search.text.trim().toLowerCase();
              final items = aveeAccountState.locations.where((item) {
                final name = '${item['name']}'.toLowerCase();
                final code = '${item['countryCode'] ?? ''}'.toLowerCase();
                return query.isEmpty ||
                    name.contains(query) ||
                    code.contains(query);
              }).toList();

              return Column(
                children: [
                  const AveeAppBar(title: 'Locations', showBack: true),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: aveeAccountState.refreshLocations,
                      color: AveeColors.primary,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [
                          TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(color: AveeColors.text),
                            decoration: InputDecoration(
                              hintText: 'Search locations',
                              hintStyle: const TextStyle(
                                color: AveeColors.mutedText,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: AveeColors.mutedText,
                              ),
                              filled: true,
                              fillColor: AveeColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (aveeAccountState.locationsLoading)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AveeColors.primary,
                                ),
                              ),
                            )
                          else if (aveeAccountState.locationsError != null)
                            AveePanel(
                              child: Text(
                                aveeAccountState.locationsError!,
                                style: const TextStyle(
                                  color: AveeColors.error,
                                ),
                              ),
                            )
                          else if (items.isEmpty)
                            const AveePanel(
                              child: Text(
                                'No locations are available.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AveeColors.secondaryText,
                                ),
                              ),
                            )
                          else
                            ...items.map(_locationRow),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

  Widget _locationRow(Map<String, dynamic> item) {
    final name = '${item['name'] ?? 'Location'}';
    final proxyName = '${item['proxyName'] ?? name}';
    final flag = item['flag']?.toString();
    final offline = item['status'] == 'offline';
    final selected = aveeAccountState.selectedLocation == proxyName;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AveeColors.primary.withValues(alpha: .10)
            : AveeColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: offline ? null : () => _selectLocation(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                if (flag != null && flag.isNotEmpty)
                  Text(flag, style: const TextStyle(fontSize: 26))
                else
                  const Icon(
                    Icons.public_outlined,
                    color: AveeColors.primary,
                    size: 26,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color:
                              offline ? AveeColors.mutedText : AveeColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offline ? 'Unavailable' : 'Available',
                        style: TextStyle(
                          color:
                              offline ? AveeColors.error : AveeColors.mutedText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AveeColors.primary,
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AveeColors.mutedText,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectLocation(Map<String, dynamic> item) async {
    final proxyName = item['proxyName']?.toString();
    if (proxyName == null || proxyName.isEmpty) return;

    await aveeAccountState.selectLocation(proxyName);
    var groupName = _findGroupName(proxyName);
    if (groupName == null) {
      await _refreshManagedProfile();
      groupName = _findGroupName(proxyName);
    }

    if (groupName != null) {
      globalState.appController.updateCurrentSelectedMap(
        groupName,
        proxyName,
      );
      globalState.appController.changeProxyDebounce(groupName, proxyName);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The VPN profile is still syncing. Try again in a moment.',
          ),
        ),
      );
      return;
    }

    if (mounted) Navigator.pop(context);
  }

  String? _findGroupName(String proxyName) {
    final groups = ref.read(groupsProvider);
    final currentGroupName = ref.read(currentProfileProvider)?.currentGroupName;
    for (final group in groups) {
      if (group.name == currentGroupName &&
          group.all.any((proxy) => proxy.name == proxyName)) {
        return group.name;
      }
    }
    for (final group in groups) {
      if (group.all.any((proxy) => proxy.name == proxyName)) return group.name;
    }
    return null;
  }

  Future<void> _refreshManagedProfile() async {
    try {
      final yaml = await aveeAccountState.refreshManagedProfile();
      if (yaml != null) {
        await globalState.appController.installManagedProfile(yaml);
      }
    } catch (_) {
      // The locations list remains usable; selection shows a sync error if
      // the refreshed Remnawave profile is temporarily unavailable.
    }
  }
}

class AveeAccountPage extends StatelessWidget {
  const AveeAccountPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AveeColors.background,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: aveeAccountState,
            builder: (context, _) {
              final account = aveeAccountState.session?.accountNumber ?? '—';
              final initial =
                  account.isNotEmpty ? account.substring(0, 1) : 'A';
              return Column(
                children: [
                  const AveeAppBar(title: 'Account', showBack: true),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: AveeColors.primary,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: AveeColors.background,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    'Account #$account',
                                    style: const TextStyle(
                                      color: AveeColors.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    aveeAccountState.access
                                        ? 'Access active'
                                        : 'No active access',
                                    style: TextStyle(
                                      color: aveeAccountState.access
                                          ? AveeColors.primary
                                          : AveeColors.warning,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        AveePrimaryButton(
                          label: 'View plans',
                          icon: Icons.workspace_premium_outlined,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AveeSubscriptionPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AveeSecondaryButton(
                          label: 'Restore purchases',
                          icon: Icons.restore,
                          onPressed: aveeAccountState.loading
                              ? null
                              : aveeBillingService.restore,
                        ),
                        const SizedBox(height: 12),
                        AveeSecondaryButton(
                          label: 'Delete account',
                          icon: Icons.delete_outline,
                          onPressed: () => _delete(context),
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  globalState.openUrl(kAveePrivacyPolicyUrl),
                              child: const Text('Privacy'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  globalState.openUrl(kAveeTermsUrl),
                              child: const Text('Terms'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  globalState.openUrl(kAveeSupportUrl),
                              child: const Text('Support'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () async {
                            await globalState.appController
                                .removeManagedProfile();
                            await aveeAccountState.logOut();
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.logout_rounded,
                              color: AveeColors.error),
                          label: const Text(
                            'Log Out',
                            style: TextStyle(
                              color: AveeColors.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AveeColors.surface,
        title: const Text('Delete account?'),
        content: const Text('Access and local data will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await aveeAccountState.deleteAccount();
      if (aveeAccountState.session == null) {
        await globalState.appController.removeManagedProfile();
        if (context.mounted) Navigator.pop(context);
      }
    }
  }
}

class AveeSubscriptionPage extends StatelessWidget {
  const AveeSubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AveeColors.background,
        body: SafeArea(
          child: Column(
            children: [
              const AveeAppBar(title: 'Subscription', showBack: true),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    aveeAccountState,
                    aveeRemoteConfig,
                  ]),
                  builder: (context, _) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      if (aveeAccountState.access)
                        AveePanel(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                color: AveeColors.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  aveeAccountState.accessExpiresAt == null
                                      ? 'Access is active'
                                      : 'Access is active until ${_date(aveeAccountState.accessExpiresAt!)}',
                                  style: const TextStyle(
                                    color: AveeColors.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _trialOffer(context),
                        const SizedBox(height: 16),
                      ],
                      FutureBuilder<AveeBillingOffers>(
                        future: aveeBillingService.offers(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(28),
                                child: CircularProgressIndicator(
                                  color: AveeColors.primary,
                                ),
                              ),
                            );
                          }
                          final products =
                              snapshot.data?.google.productDetails ?? const [];
                          if (products.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            children: [
                              for (final product in products)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: AveePanel(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          product.title,
                                          style: const TextStyle(
                                            color: AveeColors.text,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          product.price,
                                          style: const TextStyle(
                                            color: AveeColors.primary,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (product.description.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            product.description,
                                            style: const TextStyle(
                                              color: AveeColors.secondaryText,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 14),
                                        AveePrimaryButton(
                                          label: 'Continue',
                                          onPressed: () =>
                                              aveeBillingService.buy(product),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _trialOffer(BuildContext context) {
    final trial = aveeRemoteConfig.value?['trial'];
    final value = trial is Map ? Map<String, dynamic>.from(trial) : const {};
    if (value['enabled'] != true || !aveeAccountState.trialAvailable) {
      return const SizedBox.shrink();
    }
    final days = value['durationDays'] as int? ?? 0;
    final bytes = int.tryParse('${value['trafficLimitBytes'] ?? ''}');
    final details = [
      if (days > 0) '$days days',
      if (bytes != null) _bytesEnglish(bytes),
    ].join(' · ');
    return AveePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Free trial',
            style: TextStyle(
              color: AveeColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details,
              style: const TextStyle(color: AveeColors.secondaryText),
            ),
          ],
          const SizedBox(height: 14),
          AveePrimaryButton(
            label:
                aveeAccountState.loading ? 'Activating…' : 'Start free trial',
            onPressed: aveeAccountState.loading
                ? null
                : () async {
                    await aveeAccountState.startTrial();
                    if (!context.mounted) return;
                    final message = aveeAccountState.access
                        ? 'Trial activated'
                        : _friendlyError(
                            aveeAccountState.error ?? 'Could not start trial',
                          );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
          ),
        ],
      ),
    );
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
        body: SafeArea(
          child: Column(
            children: [
              const AveeAppBar(title: 'Account Recovery', showBack: true),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Text(
                      'Recover Your Account',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AveeColors.text,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your AVEE account number and recovery code to restore access on this device.',
                      style: TextStyle(
                        color: AveeColors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: account,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AveeColors.text),
                      decoration: InputDecoration(
                        labelText: 'Account number',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        filled: true,
                        fillColor: AveeColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: code,
                      obscureText: obscure,
                      style: const TextStyle(color: AveeColors.text),
                      decoration: InputDecoration(
                        labelText: 'Recovery code',
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                        filled: true,
                        fillColor: AveeColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (aveeAccountState.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _friendlyError(aveeAccountState.error!),
                          style: const TextStyle(color: AveeColors.error),
                        ),
                      ),
                    const SizedBox(height: 28),
                    AveePrimaryButton(
                      label: aveeAccountState.loading
                          ? 'Checking…'
                          : 'Recover Account',
                      onPressed: aveeAccountState.loading
                          ? null
                          : () async {
                              if (account.text.trim().isEmpty ||
                                  code.text.trim().isEmpty) {
                                return;
                              }
                              await aveeAccountState.recoverAccount(
                                accountNumber: account.text,
                                recoveryCode: code.text,
                              );
                              if (mounted && aveeAccountState.session != null) {
                                Navigator.pop(context);
                              }
                            },
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Back to create account',
                        style: TextStyle(
                          color: AveeColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class AveeRecoveryCodePage extends StatefulWidget {
  const AveeRecoveryCodePage({
    required this.account,
    required this.code,
    super.key,
  });
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
          child: Column(
            children: [
              AveeAppBar(
                title: 'Save Recovery Code',
                showBack: true,
                onBack: saved ? () => Navigator.pop(context) : null,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Text(
                      'Save your account details',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AveeColors.text,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your recovery code is shown once. Without it, access cannot be restored.',
                      style: TextStyle(
                        color: AveeColors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 26),
                    AveePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Account number',
                            style: TextStyle(color: AveeColors.secondaryText),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            widget.account,
                            style: const TextStyle(
                              color: AveeColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Recovery code',
                            style: TextStyle(color: AveeColors.secondaryText),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            widget.code,
                            style: const TextStyle(
                              color: AveeColors.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton.icon(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(
                                text: '${widget.account}\n${widget.code}',
                              ),
                            ),
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Do not share the code or store it in plain sight.',
                      style: TextStyle(color: AveeColors.warning),
                    ),
                    const SizedBox(height: 20),
                    CheckboxListTile(
                      value: saved,
                      onChanged: (value) =>
                          setState(() => saved = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      activeColor: AveeColors.primary,
                      title: const Text(
                        'I saved the code',
                        style: TextStyle(color: AveeColors.text),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AveePrimaryButton(
                      label: 'Continue',
                      onPressed: saved ? () => Navigator.pop(context) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
