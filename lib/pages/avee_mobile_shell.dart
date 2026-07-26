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
  final layout = AveeLayout.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AveeColors.surface,
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(layout.s(28))),
    ),
    builder: (sheetContext) {
      final sheetLayout = AveeLayout.of(sheetContext);
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: sheetLayout.contentMaxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                sheetLayout.s(12),
                sheetLayout.s(4),
                sheetLayout.s(12),
                sheetLayout.s(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      sheetLayout.s(12),
                      sheetLayout.s(4),
                      sheetLayout.s(12),
                      sheetLayout.s(12),
                    ),
                    child: const Align(
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
        ),
      );
    },
  );
}

Widget _aveeMenuTile(
  BuildContext sheetContext,
  IconData icon,
  String label,
  VoidCallback action,
) {
  final layout = AveeLayout.of(sheetContext);
  return ListTile(
    leading: Icon(icon, color: AveeColors.primary, size: layout.s(24)),
    title: Text(
      label,
      style: TextStyle(
        color: AveeColors.text,
        fontSize: layout.bodySize,
        fontWeight: FontWeight.w600,
      ),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(layout.s(14)),
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: layout.s(16),
      vertical: layout.s(4),
    ),
    onTap: () {
      Navigator.pop(sheetContext);
      action();
    },
  );
}

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
              child: Builder(
                builder: (context) {
                  final layout = AveeLayout.of(context);
                  return AveeResponsiveScroll(
                    centerVertically: true,
                    children: [
                      Text(
                        'Private internet.\nOne clear step.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AveeColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          fontSize: layout.headlineSize,
                        ),
                      ),
                      SizedBox(height: layout.s(12)),
                      Text(
                        'Create an account and connect without manual setup.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AveeColors.secondaryText,
                          fontSize: layout.bodySize,
                        ),
                      ),
                      SizedBox(height: layout.s(28)),
                      Center(child: _AveePulse(size: layout.pulseSize)),
                      SizedBox(height: layout.s(28)),
                      if (aveeAccountState.error != null) ...[
                        AveePanel(
                          child: Text(
                            _friendlyError(aveeAccountState.error!),
                            style: const TextStyle(color: AveeColors.error),
                          ),
                        ),
                        SizedBox(height: layout.s(16)),
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
                      SizedBox(height: layout.s(12)),
                      AveeSecondaryButton(
                        label: 'Recover account',
                        icon: Icons.key_rounded,
                        onPressed: onRecovery,
                      ),
                      SizedBox(height: layout.s(22)),
                      Text(
                        'Only the data needed to run the service. Traffic content is not recorded.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AveeColors.mutedText,
                          fontSize: layout.captionSize,
                          height: 1.4,
                        ),
                      ),
                    ],
                  );
                },
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
  const _AveePulse({this.size = 220});
  final double size;

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
  Widget build(BuildContext context) {
    final iconSize = widget.size * 0.26;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _PulsePainter(progress: _controller.value),
            child: Center(
              child: Icon(
                Icons.power_settings_new_rounded,
                color: AveeColors.primary,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
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

String _formatTimeRemaining(DateTime expiresAt) {
  final diff = expiresAt.difference(DateTime.now());
  if (diff.isNegative) return 'Expired';
  if (diff.inDays >= 2) return '${diff.inDays} days left';
  if (diff.inDays == 1) return '1 day left';
  if (diff.inHours >= 2) return '${diff.inHours} hours left';
  if (diff.inHours == 1) return '1 hour left';
  return '${diff.inMinutes.clamp(1, 59)} min left';
}

String _subscriptionSourceLabel(String? source) {
  switch (source) {
    case 'GOOGLE_PLAY':
      return 'Google Play subscription';
    case 'ADMIN_GRANT':
      return 'Granted access';
    default:
      return 'Paid subscription';
  }
}

class AveeAccessStatusPanel extends StatelessWidget {
  const AveeAccessStatusPanel({
    this.onSubscribe,
    this.compact = false,
    super.key,
  });

  final VoidCallback? onSubscribe;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = aveeAccountState;
    if (!state.access) return const SizedBox.shrink();
    final layout = AveeLayout.of(context);

    final isTrial = state.isTrialAccess;
    final expiresAt = state.accessExpiresAt;
    final timeLabel =
        expiresAt == null ? null : _formatTimeRemaining(expiresAt);
    final untilLabel = expiresAt == null ? null : 'Until ${_date(expiresAt)}';
    final traffic = state.trafficRemainingBytes;

    return AveePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTrial
                    ? Icons.card_giftcard_outlined
                    : Icons.workspace_premium_outlined,
                color: isTrial ? AveeColors.warning : AveeColors.primary,
                size: layout.s(22),
              ),
              SizedBox(width: layout.s(10)),
              Expanded(
                child: Text(
                  isTrial
                      ? 'Free trial'
                      : _subscriptionSourceLabel(state.subscriptionSource),
                  style: TextStyle(
                    color: AveeColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: layout.bodySize,
                  ),
                ),
              ),
            ],
          ),
          if (timeLabel != null) ...[
            SizedBox(height: layout.s(10)),
            _accessDetailRow(
              context,
              Icons.schedule_outlined,
              compact ? timeLabel : 'Time remaining: $timeLabel',
            ),
            if (!compact && untilLabel != null)
              Padding(
                padding: EdgeInsets.only(top: layout.s(4), left: layout.s(30)),
                child: Text(
                  untilLabel,
                  style: TextStyle(
                    color: AveeColors.mutedText,
                    fontSize: layout.t(13),
                  ),
                ),
              ),
          ],
          if (isTrial && traffic != null && !compact) ...[
            SizedBox(height: layout.s(8)),
            _accessDetailRow(
              context,
              Icons.data_usage_outlined,
              'Data remaining: ${_bytesEnglish(traffic)}',
            ),
          ],
          if (isTrial && !compact) ...[
            SizedBox(height: layout.s(12)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(layout.s(12)),
              decoration: BoxDecoration(
                color: AveeColors.background,
                borderRadius: BorderRadius.circular(layout.s(12)),
                border: Border.all(
                  color: AveeColors.warning.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'When your trial ends, purchase a subscription to keep using AVEE VPN.',
                style: TextStyle(
                  color: AveeColors.secondaryText,
                  fontSize: layout.t(13),
                  height: 1.35,
                ),
              ),
            ),
            if (onSubscribe != null) ...[
              SizedBox(height: layout.s(10)),
              TextButton(
                onPressed: onSubscribe,
                style: TextButton.styleFrom(
                  textStyle: TextStyle(fontSize: layout.bodySize),
                ),
                child: const Text('View subscription plans'),
              ),
            ],
          ] else if (isTrial && compact && onSubscribe != null) ...[
            SizedBox(height: layout.s(8)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: TextStyle(fontSize: layout.bodySize),
                ),
                onPressed: onSubscribe,
                child: const Text('View plans'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accessDetailRow(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    final layout = AveeLayout.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: layout.s(18), color: AveeColors.primary),
        SizedBox(width: layout.s(10)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AveeColors.text,
              fontWeight: FontWeight.w600,
              fontSize: layout.statusSize,
            ),
          ),
        ),
      ],
    );
  }
}

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
                child: Builder(
                  builder: (context) {
                    final layout = AveeLayout.of(context);
                    return AveeResponsiveScroll(
                      centerVertically: true,
                      children: [
                        Text(
                          running
                              ? 'YOUR CONNECTION IS Protected.'
                              : connecting
                                  ? 'YOUR CONNECTION IS Connecting…'
                                  : 'YOUR CONNECTION IS Ready.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AveeColors.secondaryText,
                            fontSize: layout.statusSize,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: layout.s(20)),
                        Center(
                          child: _SignalOrb(
                            size: layout.orbSize,
                            running: running,
                            connecting: connecting,
                            canConnect: aveeAccountState.access && hasProfile,
                            onUnavailable: () => _handleConnectUnavailable(
                              context,
                              ref,
                              onPrepareProfile,
                            ),
                          ),
                        ),
                        SizedBox(height: layout.s(12)),
                        Text(
                          running
                              ? 'Tap to Disconnect'
                              : connecting
                                  ? 'Connecting…'
                                  : 'Tap to Connect',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AveeColors.text,
                            fontSize: layout.bodySize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: layout.s(6)),
                        Text(
                          _formatRuntime(runSeconds),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AveeColors.primary,
                            fontSize: layout.t(18),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: layout.s(28)),
                        AveeAccessStatusPanel(
                          compact: true,
                          onSubscribe: () => _pushAveePage(
                            context,
                            const AveeSubscriptionPage(),
                          ),
                        ),
                        if (aveeAccountState.access)
                          SizedBox(height: layout.s(12)),
                        AveePanel(
                          onTap: onOpenLocations,
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.s(16),
                            vertical: layout.s(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (flag != null && flag.isNotEmpty)
                                Text(
                                  flag,
                                  style: TextStyle(fontSize: layout.t(28)),
                                )
                              else
                                Icon(
                                  Icons.public_outlined,
                                  color: AveeColors.primary,
                                  size: layout.s(28),
                                ),
                              SizedBox(width: layout.s(12)),
                              Flexible(
                                child: Text(
                                  location,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AveeColors.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: layout.bodySize,
                                  ),
                                ),
                              ),
                              SizedBox(width: layout.s(4)),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: AveeColors.mutedText,
                                size: layout.s(24),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _handleConnectUnavailable(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() onPrepareProfile,
) async {
  if (!aveeAccountState.access) {
    if (!aveeAccountState.trialAvailable) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AveeColors.surface,
          title: const Text(
            'Trial already used',
            style: TextStyle(color: AveeColors.text),
          ),
          content: const Text(
            'A free trial was already used on this device. You can create a new account and subscribe, or recover your previous account with your recovery code.',
            style: TextStyle(color: AveeColors.secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const AveeRecoveryPage()),
                );
              },
              child: const Text('Recover account'),
            ),
          ],
        ),
      );
      return;
    }
    await aveeAccountState.startTrial();
    if (!context.mounted) return;
    if (!aveeAccountState.access) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyError(aveeAccountState.error ?? 'Could not start trial'),
          ),
        ),
      );
      return;
    }
    await onPrepareProfile();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(currentProfileProvider) != null
              ? 'Trial started. Tap Connect again.'
              : (aveeAccountState.error ??
                  'Trial started, but the VPN profile is not ready yet.'),
        ),
      ),
    );
    return;
  }
  await onPrepareProfile();
  if (!context.mounted) return;
  if (ref.read(currentProfileProvider) != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('VPN profile is ready. Tap Connect again.'),
      ),
    );
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        aveeAccountState.error ?? 'Could not prepare the VPN profile.',
      ),
    ),
  );
}

class _SignalOrb extends StatefulWidget {
  const _SignalOrb({
    required this.size,
    required this.running,
    required this.connecting,
    required this.canConnect,
    required this.onUnavailable,
  });
  final double size;
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
  Widget build(BuildContext context) {
    final iconSize = widget.size * 0.23;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
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
                size: iconSize,
              ),
              if (widget.canConnect)
                Opacity(
                  opacity: 0,
                  child: SizedBox.expand(
                    child: StartButton(iconSize: iconSize * 0.9),
                  ),
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

              final layout = AveeLayout.of(context);
              return Column(
                children: [
                  const AveeAppBar(title: 'Locations', showBack: true),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: aveeAccountState.refreshLocations,
                      color: AveeColors.primary,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          layout.sideInset,
                          layout.s(8),
                          layout.sideInset,
                          layout.s(28),
                        ),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: layout.contentMaxWidth,
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _search,
                                    onChanged: (_) => setState(() {}),
                                    style: TextStyle(
                                      color: AveeColors.text,
                                      fontSize: layout.bodySize,
                                    ),
                                    decoration: aveeFieldDecoration(
                                      context,
                                      label: 'Search locations',
                                      hintText: 'Search locations',
                                      prefixIcon: Icon(
                                        Icons.search,
                                        color: AveeColors.mutedText,
                                        size: layout.s(22),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: layout.s(16)),
                                  if (aveeAccountState.locationsLoading)
                                    Padding(
                                      padding: EdgeInsets.all(layout.s(32)),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: AveeColors.primary,
                                        ),
                                      ),
                                    )
                                  else if (aveeAccountState.locationsError !=
                                      null)
                                    AveePanel(
                                      child: Text(
                                        aveeAccountState.locationsError!,
                                        style: TextStyle(
                                          color: AveeColors.error,
                                          fontSize: layout.bodySize,
                                        ),
                                      ),
                                    )
                                  else if (items.isEmpty)
                                    AveePanel(
                                      child: Text(
                                        'No locations are available.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AveeColors.secondaryText,
                                          fontSize: layout.bodySize,
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
    final layout = AveeLayout.of(context);
    final name = '${item['name'] ?? 'Location'}';
    final proxyName = '${item['proxyName'] ?? name}';
    final flag = item['flag']?.toString();
    final offline = item['status'] == 'offline';
    final selected = aveeAccountState.selectedLocation == proxyName;
    final radius = layout.s(16);

    return Container(
      margin: EdgeInsets.only(bottom: layout.s(8)),
      child: Material(
        color: selected
            ? AveeColors.primary.withValues(alpha: .10)
            : AveeColors.surface,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: offline ? null : () => _selectLocation(item),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.s(14),
              vertical: layout.s(14),
            ),
            child: Row(
              children: [
                if (flag != null && flag.isNotEmpty)
                  Text(flag, style: TextStyle(fontSize: layout.t(26)))
                else
                  Icon(
                    Icons.public_outlined,
                    color: AveeColors.primary,
                    size: layout.s(26),
                  ),
                SizedBox(width: layout.s(12)),
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
                          fontSize: layout.bodySize,
                        ),
                      ),
                      SizedBox(height: layout.s(2)),
                      Text(
                        offline ? 'Unavailable' : 'Available',
                        style: TextStyle(
                          color:
                              offline ? AveeColors.error : AveeColors.mutedText,
                          fontSize: layout.captionSize,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  color: selected ? AveeColors.primary : AveeColors.mutedText,
                  size: layout.s(24),
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

String _accountAccessHeadline(AveeAccountState state) {
  if (!state.access) return 'No active access';
  if (state.isTrialAccess) {
    final time = state.accessExpiresAt == null
        ? null
        : _formatTimeRemaining(state.accessExpiresAt!);
    return time == null ? 'Trial active' : 'Trial · $time';
  }
  final time = state.accessExpiresAt == null
      ? null
      : _formatTimeRemaining(state.accessExpiresAt!);
  return time == null ? 'Subscription active' : 'Subscription · $time';
}

class AveeVersionFooter extends StatelessWidget {
  const AveeVersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    final info = globalState.packageInfo;
    return Padding(
      padding: EdgeInsets.only(top: layout.s(10), bottom: layout.s(8)),
      child: Center(
        child: Text(
          'AVEE VPN · Version ${info.version} (${info.buildNumber})',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AveeColors.mutedText,
            fontSize: layout.captionSize,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
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
              final layout = AveeLayout.of(context);
              final account = aveeAccountState.session?.accountNumber ?? '—';
              final initial =
                  account.isNotEmpty ? account.substring(0, 1) : 'A';
              return Column(
                children: [
                  const AveeAppBar(title: 'Account', showBack: true),
                  Expanded(
                    child: AveeResponsiveScroll(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: layout.s(28),
                              backgroundColor: AveeColors.primary,
                              child: Text(
                                initial,
                                style: TextStyle(
                                  color: AveeColors.background,
                                  fontWeight: FontWeight.w800,
                                  fontSize: layout.t(22),
                                ),
                              ),
                            ),
                            SizedBox(width: layout.s(14)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    'Account #$account',
                                    style: TextStyle(
                                      color: AveeColors.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: layout.bodySize,
                                    ),
                                  ),
                                  SizedBox(height: layout.s(4)),
                                  Text(
                                    _accountAccessHeadline(aveeAccountState),
                                    style: TextStyle(
                                      color: aveeAccountState.access
                                          ? AveeColors.primary
                                          : AveeColors.warning,
                                      fontWeight: FontWeight.w600,
                                      fontSize: layout.statusSize,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: layout.s(16)),
                        AveePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account credentials',
                                style: TextStyle(
                                  color: AveeColors.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: layout.bodySize,
                                ),
                              ),
                              SizedBox(height: layout.s(4)),
                              Text(
                                'Save these to recover access on another device.',
                                style: TextStyle(
                                  color: AveeColors.mutedText,
                                  fontSize: layout.captionSize,
                                  height: 1.4,
                                ),
                              ),
                              SizedBox(height: layout.s(16)),
                              AveeCopyField(
                                label: 'Account number',
                                value: account,
                              ),
                              if (aveeAccountState.storedRecoveryCode !=
                                  null) ...[
                                SizedBox(height: layout.s(16)),
                                AveeCopyField(
                                  label: 'Recovery code',
                                  value: aveeAccountState.storedRecoveryCode!,
                                ),
                              ] else ...[
                                SizedBox(height: layout.s(12)),
                                Text(
                                  'Recovery code is shown once when the account is created. Use Recover account if you saved it elsewhere.',
                                  style: TextStyle(
                                    color: AveeColors.mutedText,
                                    fontSize: layout.captionSize,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!aveeAccountState.trialAvailable) ...[
                          SizedBox(height: layout.s(16)),
                          AveePanel(
                            child: Text(
                              aveeAccountState.trialUnavailableReason ==
                                      'TRIAL_ALREADY_USED_ON_DEVICE'
                                  ? 'A free trial was already used on this device. You can still subscribe or recover your previous account.'
                                  : 'Free trial is not available on this device.',
                              style: TextStyle(
                                color: AveeColors.warning,
                                fontSize: layout.captionSize,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                        if (aveeAccountState.access) ...[
                          SizedBox(height: layout.s(16)),
                          AveeAccessStatusPanel(
                            onSubscribe: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AveeSubscriptionPage(),
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: layout.s(24)),
                        AveePrimaryButton(
                          label: 'View plans',
                          icon: Icons.workspace_premium_outlined,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AveeSubscriptionPage(),
                            ),
                          ),
                        ),
                        SizedBox(height: layout.s(12)),
                        AveeSecondaryButton(
                          label: 'Restore purchases',
                          icon: Icons.restore,
                          onPressed: aveeAccountState.loading
                              ? null
                              : () => _restorePurchases(context),
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: layout.s(6)),
                          child: Text(
                            'Re-links an active Google Play subscription to this AVEE account after reinstall or device change.',
                            style: TextStyle(
                              color: AveeColors.mutedText,
                              fontSize: layout.captionSize,
                              height: 1.4,
                            ),
                          ),
                        ),
                        SizedBox(height: layout.s(12)),
                        AveeSecondaryButton(
                          label: 'Delete account',
                          icon: Icons.delete_outline,
                          onPressed: () => _delete(context),
                        ),
                        SizedBox(height: layout.s(28)),
                        Wrap(
                          spacing: layout.s(12),
                          runSpacing: layout.s(8),
                          children: [
                            TextButton(
                              onPressed: () =>
                                  globalState.openUrl(kAveePrivacyPolicyUrl),
                              style: TextButton.styleFrom(
                                textStyle: TextStyle(fontSize: layout.bodySize),
                              ),
                              child: const Text('Privacy'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  globalState.openUrl(kAveeTermsUrl),
                              style: TextButton.styleFrom(
                                textStyle: TextStyle(fontSize: layout.bodySize),
                              ),
                              child: const Text('Terms'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  globalState.openUrl(kAveeSupportUrl),
                              style: TextButton.styleFrom(
                                textStyle: TextStyle(fontSize: layout.bodySize),
                              ),
                              child: const Text('Support'),
                            ),
                          ],
                        ),
                        SizedBox(height: layout.s(12)),
                        TextButton.icon(
                          onPressed: () async {
                            await globalState.appController
                                .removeManagedProfile();
                            await aveeAccountState.logOut();
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: Icon(
                            Icons.logout_rounded,
                            color: AveeColors.error,
                            size: layout.s(22),
                          ),
                          label: Text(
                            'Log Out',
                            style: TextStyle(
                              color: AveeColors.error,
                              fontWeight: FontWeight.w700,
                              fontSize: layout.bodySize,
                            ),
                          ),
                        ),
                        const AveeVersionFooter(),
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
    final accountNumber = aveeAccountState.session?.accountNumber;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final layout = AveeLayout.of(dialogContext);
        return AlertDialog(
          backgroundColor: AveeColors.surface,
          title: Text(
            'Delete account?',
            style: TextStyle(
              color: AveeColors.text,
              fontSize: layout.t(20),
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            accountNumber == null
                ? 'This removes your AVEE account, access, and local credentials from this device. This cannot be undone.'
                : 'Delete account #$accountNumber? Access ends immediately and local credentials are removed. Save your recovery code first if you may need this account again.',
            style: TextStyle(
              color: AveeColors.secondaryText,
              fontSize: layout.bodySize,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AveeColors.error),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete account'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;

    await globalState.appController.updateStatus(false);
    final deleted = await aveeAccountState.deleteAccount();
    if (!context.mounted) return;

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            aveeAccountState.error ?? 'Could not delete account. Try again.',
          ),
          backgroundColor: AveeColors.error,
        ),
      );
      return;
    }

    await globalState.appController.removeManagedProfile();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Account deleted. You can create a new one, but this device will not receive another free trial.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _restorePurchases(BuildContext context) async {
    final restored = await aveeBillingService.restore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? 'Purchases restored. Subscription access is active.'
              : aveeAccountState.error ??
                  'No active Google Play subscription was found for this account.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: restored ? AveeColors.surfaceRaised : AveeColors.error,
      ),
    );
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
                  builder: (context, _) {
                    final layout = AveeLayout.of(context);
                    final trialPanel = _trialOffer(context);
                    return AveeResponsiveScroll(
                      children: [
                        if (aveeAccountState.access) ...[
                          const AveeAccessStatusPanel(),
                          SizedBox(height: layout.s(16)),
                        ] else ...[
                          trialPanel,
                          SizedBox(height: layout.s(16)),
                        ],
                        FutureBuilder<AveeBillingOffers>(
                          future: aveeBillingService.offers(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return Center(
                                child: Padding(
                                  padding: EdgeInsets.all(layout.s(28)),
                                  child: const CircularProgressIndicator(
                                    color: AveeColors.primary,
                                  ),
                                ),
                              );
                            }
                            final products =
                                snapshot.data?.google.productDetails ??
                                    const [];
                            if (products.isEmpty) {
                              return AveePanel(
                                child: Text(
                                  aveeAccountState.access
                                      ? 'Subscription products are not available in this build yet.'
                                      : 'Paid plans appear here after Play billing is configured. Tap Connect on Home to start the trial first.',
                                  style: TextStyle(
                                    color: AveeColors.secondaryText,
                                    fontSize: layout.bodySize,
                                  ),
                                ),
                              );
                            }
                            return Column(
                              children: [
                                for (final product in products)
                                  Padding(
                                    padding:
                                        EdgeInsets.only(bottom: layout.s(12)),
                                    child: AveePanel(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            product.title,
                                            style: TextStyle(
                                              color: AveeColors.text,
                                              fontSize: layout.t(20),
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          SizedBox(height: layout.s(6)),
                                          Text(
                                            product.price,
                                            style: TextStyle(
                                              color: AveeColors.primary,
                                              fontSize: layout.t(26),
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (product
                                              .description.isNotEmpty) ...[
                                            SizedBox(height: layout.s(8)),
                                            Text(
                                              product.description,
                                              style: TextStyle(
                                                color: AveeColors.secondaryText,
                                                fontSize: layout.bodySize,
                                              ),
                                            ),
                                          ],
                                          SizedBox(height: layout.s(14)),
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
                        const AveeVersionFooter(),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _trialOffer(BuildContext context) {
    final layout = AveeLayout.of(context);
    if (!aveeAccountState.trialAvailable) {
      return AveePanel(
        child: Text(
          aveeAccountState.trialUnavailableReason ==
                  'TRIAL_ALREADY_USED_ON_DEVICE'
              ? 'This device already used a free trial. Subscribe below or recover your previous account.'
              : 'Free trial is not available on this device.',
          style: TextStyle(
            color: AveeColors.warning,
            fontSize: layout.bodySize,
            height: 1.45,
          ),
        ),
      );
    }
    final trial = aveeRemoteConfig.value?['trial'];
    final value = trial is Map ? Map<String, dynamic>.from(trial) : const {};
    if (value['enabled'] == false) {
      return const SizedBox.shrink();
    }
    final days = value['durationDays'] as int? ?? 3;
    final bytes =
        int.tryParse('${value['trafficLimitBytes'] ?? ''}') ?? 1073741824;
    final details = [
      if (days > 0) '$days days',
      _bytesEnglish(bytes),
    ].join(' · ');
    return AveePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Free trial',
            style: TextStyle(
              color: AveeColors.text,
              fontSize: layout.t(20),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (details.isNotEmpty) ...[
            SizedBox(height: layout.s(6)),
            Text(
              details,
              style: TextStyle(
                color: AveeColors.secondaryText,
                fontSize: layout.bodySize,
              ),
            ),
          ],
          SizedBox(height: layout.s(14)),
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return Scaffold(
      backgroundColor: AveeColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AveeAppBar(title: 'Account Recovery', showBack: true),
            Expanded(
              child: AveeResponsiveScroll(
                children: [
                  Text(
                    'Recover Your Account',
                    style: TextStyle(
                      color: AveeColors.text,
                      fontWeight: FontWeight.w800,
                      fontSize: layout.headlineSize,
                    ),
                  ),
                  SizedBox(height: layout.s(8)),
                  Text(
                    'Enter your AVEE account number and recovery code to restore access on this device.',
                    style: TextStyle(
                      color: AveeColors.secondaryText,
                      height: 1.4,
                      fontSize: layout.bodySize,
                    ),
                  ),
                  SizedBox(height: layout.s(28)),
                  TextField(
                    controller: account,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: AveeColors.text,
                      fontSize: layout.bodySize,
                    ),
                    decoration: aveeFieldDecoration(
                      context,
                      label: 'Account number',
                      prefixIcon: Icon(
                        Icons.badge_outlined,
                        size: layout.s(22),
                      ),
                    ),
                  ),
                  SizedBox(height: layout.s(16)),
                  TextField(
                    controller: code,
                    obscureText: obscure,
                    style: TextStyle(
                      color: AveeColors.text,
                      fontSize: layout.bodySize,
                    ),
                    decoration: aveeFieldDecoration(
                      context,
                      label: 'Recovery code',
                      prefixIcon: Icon(
                        Icons.vpn_key_outlined,
                        size: layout.s(22),
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                          size: layout.s(22),
                        ),
                      ),
                    ),
                  ),
                  if (aveeAccountState.error != null)
                    Padding(
                      padding: EdgeInsets.only(top: layout.s(16)),
                      child: Text(
                        _friendlyError(aveeAccountState.error!),
                        style: TextStyle(
                          color: AveeColors.error,
                          fontSize: layout.bodySize,
                        ),
                      ),
                    ),
                  SizedBox(height: layout.s(28)),
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
                  SizedBox(height: layout.s(24)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Back to create account',
                      style: TextStyle(
                        color: AveeColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: layout.bodySize,
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
  Widget build(BuildContext context) {
    final layout = AveeLayout.of(context);
    return Scaffold(
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
              child: AveeResponsiveScroll(
                children: [
                  Text(
                    'Save your account details',
                    style: TextStyle(
                      color: AveeColors.text,
                      fontWeight: FontWeight.w800,
                      fontSize: layout.headlineSize,
                    ),
                  ),
                  SizedBox(height: layout.s(8)),
                  Text(
                    'Your recovery code is shown once. Without it, access cannot be restored.',
                    style: TextStyle(
                      color: AveeColors.secondaryText,
                      height: 1.4,
                      fontSize: layout.bodySize,
                    ),
                  ),
                  SizedBox(height: layout.s(26)),
                  AveePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AveeCopyField(
                          label: 'Account number',
                          value: widget.account,
                        ),
                        SizedBox(height: layout.s(18)),
                        AveeCopyField(
                          label: 'Recovery code',
                          value: widget.code,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: layout.s(18)),
                  Text(
                    'Do not share the code or store it in plain sight.',
                    style: TextStyle(
                      color: AveeColors.warning,
                      fontSize: layout.bodySize,
                    ),
                  ),
                  SizedBox(height: layout.s(20)),
                  CheckboxListTile(
                    value: saved,
                    onChanged: (value) =>
                        setState(() => saved = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    activeColor: AveeColors.primary,
                    title: Text(
                      'I saved the code',
                      style: TextStyle(
                        color: AveeColors.text,
                        fontSize: layout.bodySize,
                      ),
                    ),
                  ),
                  SizedBox(height: layout.s(14)),
                  AveePrimaryButton(
                    label: 'Continue',
                    onPressed: saved
                        ? () async {
                            await aveeAccountState.persistRecoveryCode(
                              widget.code,
                            );
                            if (context.mounted) Navigator.pop(context);
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
