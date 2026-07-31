import 'dart:async';
import 'dart:math' as math;

import 'package:avee/providers/providers.dart';
import 'package:avee/common/constant.dart';
import 'package:avee/services/avee_account.dart';
import 'package:avee/services/avee_billing.dart';
import 'package:avee/state.dart';
import 'package:avee/ui/avee_design.dart';
import 'package:avee/views/dashboard/widgets/start_button.dart';
import 'package:avee/models/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      // A server-side HWID deletion revokes the AVEE session. Stop the local
      // tunnel before removing its profile so an already-running connection
      // cannot continue after the account is revoked.
      try {
        await globalState.appController.updateStatus(false);
      } catch (_) {
        // Removing the managed profile is still required if the core is
        // already stopped or unavailable.
      }
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

  Future<void> _loginById(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AveeColors.surface,
        title: const Text('Sign in with AVEE ID'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: aveeFieldDecoration(context, label: 'AVEE ID'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await aveeAccountState.loginAccount(
                accountId: controller.text,
                onAuthenticated: () {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) {
          if (aveeAccountState.session == null) {
            return AveePage(
              child: AveeGuestOnboarding(
                onLogin: () => _loginById(context),
              ),
            );
          }
          return AveePage(
            child: AveeHomeDashboard(
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
    required this.onLogin,
    super.key,
  });
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) => Column(
          children: [
            AveeAppBar(
              title: 'AVEE VPN',
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
                      SizedBox(height: layout.s(10)),
                      AveeSecondaryButton(
                        label: 'Sign in with AVEE ID',
                        icon: Icons.login_rounded,
                        onPressed: onLogin,
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

String _friendlyError(String error) {
  if (error == 'Backend unavailable') {
    return 'AVEE server is temporarily unavailable. Try again.';
  }
  final normalized = error.toLowerCase();
  if (normalized.contains('hwid') &&
      (normalized.contains('limit') ||
          normalized.contains('previous device'))) {
    return 'This subscription is already active on another device. Sign out there, or remove the old device in your AVEE account, then try again.';
  }
  if (normalized.contains('remnawave') ||
      normalized.contains('binding is missing')) {
    return 'Your VPN profile is temporarily unavailable. Refresh your account and try again shortly.';
  }
  return error;
}

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: layout.s(30),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Icon(
                    isTrial
                        ? Icons.card_giftcard_outlined
                        : Icons.workspace_premium_outlined,
                    color: isTrial ? AveeColors.warning : AveeColors.primary,
                    size: layout.s(22),
                  ),
                ),
              ),
              SizedBox(width: layout.s(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTrial
                          ? 'Free trial'
                          : _subscriptionSourceLabel(state.subscriptionSource),
                      style: TextStyle(
                        color: AveeColors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: layout.bodySize,
                      ),
                    ),
                    if (timeLabel != null) ...[
                      SizedBox(height: layout.s(4)),
                      Text(
                        compact ? timeLabel : 'Time remaining: $timeLabel',
                        style: TextStyle(
                          color: AveeColors.secondaryText,
                          fontWeight: FontWeight.w600,
                          fontSize: layout.statusSize,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!compact && untilLabel != null)
            Padding(
              padding: EdgeInsets.only(top: layout.s(4), left: layout.s(40)),
              child: Text(
                untilLabel,
                style: TextStyle(
                  color: AveeColors.mutedText,
                  fontSize: layout.t(13),
                ),
              ),
            ),
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
        SizedBox(
          width: layout.s(30),
          child: Icon(icon, size: layout.s(18), color: AveeColors.primary),
        ),
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
    required this.onPrepareProfile,
    required this.onOpenLocations,
    super.key,
  });

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
              onMenu: () => _pushAveePage(
                context,
                const AveeAccountPage(),
              ),
              actionIcon: Icons.person_outline,
              actionTooltip: 'Account',
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
                          onSubscribe: () => AveePaywall.show(context),
                        ),
                        if (aveeAccountState.session != null &&
                            !aveeAccountState.access &&
                            !aveeAccountState.trialAvailable) ...[
                          SizedBox(height: layout.s(12)),
                          AveePanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your free trial has ended',
                                  style: TextStyle(
                                    color: AveeColors.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: layout.bodySize,
                                  ),
                                ),
                                SizedBox(height: layout.s(6)),
                                Text(
                                  'Subscribe to restore VPN access. Reinstalling the app or creating another AVEE ID will not start a new trial on this device.',
                                  style: TextStyle(
                                    color: AveeColors.secondaryText,
                                    fontSize: layout.captionSize,
                                    height: 1.4,
                                  ),
                                ),
                                SizedBox(height: layout.s(12)),
                                AveePrimaryButton(
                                  label: 'Subscribe now',
                                  icon: Icons.workspace_premium_outlined,
                                  onPressed: () => AveePaywall.show(context),
                                ),
                              ],
                            ),
                          ),
                        ],
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
  if (aveeAccountState.session != null) {
    // Pull the latest panel-backed entitlement/user state before deciding
    // whether to start a trial or prepare a profile.
    await aveeAccountState.refresh();
  }
  if (!aveeAccountState.remnawaveEnabled && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          aveeAccountState.remnawaveError ??
              'VPN access is temporarily disabled by the service. Your account is valid, but access has been paused. Please try again later or contact support.',
        ),
      ),
    );
    return;
  }
  if (aveeAccountState.accessReason == 'REMNAWAVE_BINDING_MISSING' &&
      context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Your subscription is active, but the VPN profile is still being prepared. Refresh your account and try again in a moment.',
        ),
      ),
    );
    return;
  }
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
            'This device has already used its one-time free trial. Reinstalling or creating another AVEE ID will not reset it. Sign in with an AVEE ID that has an active subscription or purchase a subscription to get VPN access.',
            style: TextStyle(color: AveeColors.secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
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

class _LatencyBars extends StatelessWidget {
  const _LatencyBars({required this.quality, required this.size});

  final String quality;
  final double size;

  @override
  Widget build(BuildContext context) {
    final active = switch (quality) {
      'excellent' => 3,
      'good' => 2,
      'poor' => 1,
      _ => 0,
    };
    final color = switch (quality) {
      'excellent' => Colors.green,
      'good' => Colors.amber,
      'poor' => Colors.redAccent,
      _ => AveeColors.mutedText,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        return Container(
          width: size,
          height: size * (index + 1.5),
          margin: EdgeInsets.only(left: size * .6),
          decoration: BoxDecoration(
            color: index < active
                ? color
                : AveeColors.mutedText.withValues(alpha: .28),
            borderRadius: BorderRadius.circular(size),
          ),
        );
      }),
    );
  }
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
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => showDialog<void>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('About ping'),
                                          content: const Text(
                                            'Ping measures the time needed to reach a location. Lower is better for games, calls and other real-time activity. It does not increase your internet speed or reduce normal browsing speed.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialogContext),
                                              child: const Text('Got it'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      icon: const Icon(Icons.info_outline),
                                      label: const Text('What does ping mean?'),
                                    ),
                                  ),
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
    final latency = int.tryParse(item['latencyMs']?.toString() ?? '');
    final quality = item['latencyQuality']?.toString() ?? 'offline';
    final bestLatency = aveeAccountState.locations
        .map(
            (location) => int.tryParse(location['latencyMs']?.toString() ?? ''))
        .whereType<int>()
        .fold<int?>(
            null, (best, value) => best == null || value < best ? value : best);
    final isBest = latency != null && latency == bestLatency;
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
                      Row(
                        children: [
                          Text(
                            offline
                                ? 'Unavailable'
                                : latency == null
                                    ? 'Checking…'
                                    : '$latency ms',
                            style: TextStyle(
                              color: offline
                                  ? AveeColors.error
                                  : AveeColors.mutedText,
                              fontSize: layout.captionSize,
                            ),
                          ),
                          if (isBest) ...[
                            SizedBox(width: layout.s(8)),
                            Text(
                              'Best',
                              style: TextStyle(
                                color: AveeColors.success,
                                fontSize: layout.captionSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const Spacer(),
                          _LatencyBars(
                            quality: quality,
                            size: layout.s(5),
                          ),
                        ],
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
    final locationProxyName = item['proxyName']?.toString();
    if (locationProxyName == null || locationProxyName.isEmpty) return;

    var proxyName = _findProfileProxyName(item);
    var groupName = proxyName == null ? null : _findGroupName(proxyName);
    if (groupName == null) {
      await _refreshManagedProfile();
      proxyName = _findProfileProxyName(item);
      groupName = proxyName == null ? null : _findGroupName(proxyName);
    }

    if (groupName != null && proxyName != null) {
      globalState.appController.updateCurrentSelectedMap(
        groupName,
        proxyName,
      );
      try {
        // Apply the choice before closing the location screen. A debounced
        // change could still be pending when the user immediately taps
        // Connect, leaving the previous node active (usually Denmark).
        await globalState.appController.changeProxy(
          groupName: groupName,
          proxyName: proxyName,
        );
        await globalState.appController.updateGroups();
        Group? appliedGroup;
        for (final group in ref.read(groupsProvider)) {
          if (group.name == groupName) {
            appliedGroup = group;
            break;
          }
        }
        if (appliedGroup?.realNow != proxyName) {
          throw StateError('Mihomo did not apply the selected location.');
        }
        // Persist the location only after Mihomo accepted the new proxy.
        // This prevents the UI from reporting a location that the running
        // profile has not actually selected when a profile refresh fails.
        await aveeAccountState.selectLocation(locationProxyName);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not switch to this location.')),
          );
        }
        return;
      }
    } else if (mounted) {
      final profileError = aveeAccountState.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profileError ??
                'The VPN profile is still syncing. Try again in a moment.',
          ),
        ),
      );
      return;
    }

    if (mounted) Navigator.pop(context);
  }

  String? _findProfileProxyName(Map<String, dynamic> item) {
    final candidates = <String>{
      item['proxyName']?.toString() ?? '',
      item['name']?.toString() ?? '',
    }..removeWhere((value) => value.isEmpty);
    final normalizedCandidates = candidates
        .map(_normalizeLocationName)
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final group in ref.read(groupsProvider)) {
      for (final proxy in group.all) {
        final normalizedProxyName = _normalizeLocationName(proxy.name);
        if (candidates.contains(proxy.name) ||
            (normalizedProxyName.isNotEmpty &&
                normalizedCandidates.contains(normalizedProxyName))) {
          return proxy.name;
        }
      }
    }
    return null;
  }

  String _normalizeLocationName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

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
      if (group.name.toUpperCase() == 'GLOBAL' &&
          group.all.any((proxy) => proxy.name == proxyName)) {
        return group.name;
      }
    }
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
              final account = aveeAccountState.session?.accountId ?? '—';
              return Column(
                children: [
                  const AveeAppBar(title: 'Account', showBack: true),
                  Expanded(
                    child: AveeResponsiveScroll(
                      children: [
                        AveePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AVEE ID',
                                style: TextStyle(
                                  color: AveeColors.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: layout.bodySize,
                                ),
                              ),
                              SizedBox(height: layout.s(4)),
                              Text(
                                'Your AVEE ID identifies this account. Access is protected by this device.',
                                style: TextStyle(
                                  color: AveeColors.mutedText,
                                  fontSize: layout.captionSize,
                                  height: 1.4,
                                ),
                              ),
                              SizedBox(height: layout.s(16)),
                              AveeCopyField(
                                label: 'AVEE ID',
                                value: account,
                              ),
                            ],
                          ),
                        ),
                        if (!aveeAccountState.trialAvailable &&
                            !aveeAccountState.isSubscriptionAccess) ...[
                          SizedBox(height: layout.s(16)),
                          AveePanel(
                            child: Text(
                              aveeAccountState.trialUnavailableReason ==
                                      'DEVICE_TRIAL_USED'
                                  ? 'This device has already used its one-time free trial. Sign in with an AVEE ID that has an active subscription or purchase a subscription to get VPN access.'
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
                            onSubscribe: () => AveePaywall.show(context),
                          ),
                        ],
                        SizedBox(height: layout.s(24)),
                        AveePrimaryButton(
                          label: aveeAccountState.isSubscriptionAccess
                              ? 'Manage subscription'
                              : 'View plans',
                          icon: aveeAccountState.isSubscriptionAccess
                              ? Icons.open_in_new
                              : Icons.workspace_premium_outlined,
                          onPressed: aveeAccountState.isSubscriptionAccess
                              ? () => openAveePlaySubscriptionManagement()
                              : () => AveePaywall.show(context),
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
    final accountId = aveeAccountState.session?.accountId;
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
            accountId == null
                ? 'This removes your AVEE account, access, and local credentials from this device. This cannot be undone.'
                : 'Delete AVEE ID $accountId? Access ends immediately and local credentials are removed. This cannot be undone.',
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
