import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:avee/clash/clash.dart';
import 'package:avee/common/connect_trace.dart';
import 'package:avee/common/error_mapper.dart';
import 'package:avee/common/request.dart';
import 'package:avee/controller.dart';
import 'package:avee/enum/enum.dart';
import 'package:avee/models/models.dart';
import 'package:avee/plugins/vpn.dart';
import 'package:avee/providers/providers.dart';
import 'package:avee/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/common.dart';
import 'backend_compatibility.dart';

/// Connect-lifecycle concern carved out of [AppController].
///
/// [AppController] keeps thin delegating methods with identical signatures, so
/// every existing call site (`globalState.appController.updateStatus(...)`,
/// `updateStart()`, `syncRunStateFromNative()`, …) stays untouched — the nine
/// `updateStatus` callers (start button, QS tile, tray, hotkey, init reconcile,
/// core-death self-heal) never move.
///
/// No [BuildContext] is stored here — the moved code reaches the rest of the
/// app exclusively via `_ref`, `globalState`, and the public [AppController]
/// facade (`globalState.appController.*`) for the few controller-resident
/// concerns that stay: config setup-hash invalidation ([invalidateSetupHash]),
/// core (re)initialization ([initCore]), and the debounced apply / check-ip
/// tasks (`applyProfileDebounce`, `addCheckIpNumDebounce`). The setup-hash and
/// `lastProfileModified` remain owned by the controller's config domain; the
/// realign restart-budget moves here with its sole heavy user ([requestAdmin])
/// and is reset from the staying config entry points via
/// [resetCoreRealignBudget].
///
/// Private controller callers that stay ([AppController.changeProxyDebounce] →
/// [updateForegroundServerName], [AppController.init] →
/// [handleUnexpectedCoreDeath], `_setupClashConfig`/`_updateClashConfig` →
/// [requestAdmin]) reach these now-public service methods through the
/// controller's private delegate stubs.
class ConnectService {
  ConnectService(this._ref);

  final WidgetRef _ref;

  /// Bounded guard for core restarts issued from [requestAdmin] (both the
  /// post-authorize restart and the Windows realign self-heal). Every
  /// restartCore() from requestAdmin recurses via initCore → applyProfile →
  /// setupClashConfig → requestAdmin, and loadingRun has no re-entrancy
  /// guard — an unbounded success↔none alternation under a flapping helper
  /// would recurse forever. So: every restart from here counts against ONE
  /// shared cap, nothing inside the recursion ever resets it, and the counter
  /// is reset only at non-recursive user-action entry points
  /// ([updateStatus], `updateClashConfig`, `handleChangeProfile`) so a later
  /// user action always gets a fresh chance to realign (no permanent
  /// per-session TUN-off).
  int _coreRealignAttempts = 0;

  static const _maxCoreRealignAttempts = 3;

  /// Resets the realign restart-budget. Called from the controller's staying
  /// config entry points (`updateClashConfig`, `handleChangeProfile`) so a
  /// later user action always gets a fresh realign chance.
  void resetCoreRealignBudget() {
    _coreRealignAttempts = 0;
  }

  /// Update cached server name in VPN plugin for foreground notification
  /// Also sends IPC message to service isolate to update selectedMap
  void updateForegroundServerName(String groupName, String serverName) {
    vpn?.updateServerName(serverName);
    // Send IPC message to service isolate (Android only)
    clashLib?.sendIpcMessage({
      'action': 'updateForegroundServer',
      'groupName': groupName,
      'serverName': serverName,
    });
  }

  /// Initialize foreground notification cache with current profile and server.
  ///
  /// Pushes profileName / serviceName / serverName into the VPN plugin's
  /// in-memory cache that feeds the Android foreground notification. Call sites:
  ///   • connect ([updateStatus] `isStart==true`) — seed the cache before the
  ///     service comes up.
  ///   • profile switch ([AppController.handleChangeProfile]) — a switch while
  ///     connected hot-swaps the core config but left this cache untouched, so
  ///     the notification kept showing the PREVIOUS profile's label until a
  ///     reconnect/restart (owner-reported).
  ///   • current-profile update ([AppController.updateProfile], active-profile
  ///     branch) — a subscription refresh can change `avee-servicename` /
  ///     the label rendered in the notification.
  /// The plugin setters (`updateProfileInfo`/`updateServerName`) are pure
  /// in-memory writes with no MethodChannel/notification side effect, so calling
  /// this while disconnected is a cheap, harmless cache prime (never flashes a
  /// notification).
  void initForegroundCache({Profile? profileOverride}) {
    final profile = profileOverride ?? globalState.config.currentProfile;
    if (profile == null) return;

    final profileName = profile.label ?? profile.id;

    // Decode service name from header (may be `base64:`-prefixed base64).
    String serviceName = "";
    final svc = profile.providerHeaders['avee-servicename'];
    if (svc != null && svc.isNotEmpty) {
      serviceName = decodeMaybeBase64(svc).trim();
    }

    vpn?.updateProfileInfo(
      profileName: profileName,
      serviceName: serviceName,
    );

    // Get current server name from selectedMap
    final groupName = profile.providerHeaders['avee-serverinfo'];
    if (groupName != null && groupName.isNotEmpty) {
      final decodedGroupName = decodeMaybeBase64(groupName).trim();
      final serverName = profile.selectedMap[decodedGroupName] ?? "";
      vpn?.updateServerName(serverName);
    }

    // The plugin cache writes above only feed the notification when the MAIN
    // isolate composes foreground params. In Android service mode the title is
    // composed by the handler in main.dart from the SERVICE isolate's OWN
    // `globalState.config.currentProfile` snapshot, which mutates ONLY via IPC
    // ('updateForegroundServer' → selectedMap, 'updateMode' → mode). A profile
    // switch/update sends no IPC, so that snapshot keeps the OLD profile and the
    // title (profile-title → avee-serverinfo → servicename chain) stays stale
    // even after the cache write above (live speed updates masked it — the
    // service isolate was the one answering). Mirror the updateForegroundServer
    // precedent: push the freshly-active profile to the service isolate so its
    // title chain resolves the NEW profile. Fire-and-forget — sendIpcMessage
    // awaits the handshake internally, so this stays sync (same as
    // updateForegroundServerName, which also does not await).
    clashLib?.sendIpcMessage({
      'action': 'updateCurrentProfile',
      'profileId': profile.id,
      'profile': json.encode(profile.toJson()),
    });
  }

  Future<void> restartCore() async {
    commonPrint.log("restart core");
    // A restarted core process starts UNCONFIGURED. The content-hash gate in
    // _setupClashConfig compares against the last SUCCESSFUL setup of the
    // PREVIOUS process — with unchanged inputs it would "hash match" and skip
    // the setup entirely, leaving the fresh core with no proxies/rules while
    // the UI claims connected. A new process must never hit the cache.
    globalState.appController.invalidateSetupHash();
    await clashService?.reStart();
    await globalState.appController.initCore();
    if (_ref.read(runTimeProvider.notifier).isStart) {
      await globalState.handleStart();
    }
  }

  /// Timestamp of the last automatic recovery from an unexpected desktop core
  /// death. Bounds the self-heal to at most ONE auto-restart per
  /// [_coreDeathRecoveryCooldown]: a crash-looping core must not be restarted
  /// forever — once the budget is spent we fail HONEST (stopped state + a
  /// visible error) instead of hammering a doomed core or lying "connected".
  DateTime? _lastCoreDeathRecovery;
  static const _coreDeathRecoveryCooldown = Duration(minutes: 5);

  /// Wired to [ClashService.onUnexpectedCoreDeath] (desktop only). The core
  /// process died or the bridge socket dropped without us initiating it.
  Future<void> handleUnexpectedCoreDeath(String reason) async {
    commonPrint.log('[core-bridge] controller: core died — $reason');
    final now = DateTime.now();
    final last = _lastCoreDeathRecovery;
    if (last != null && now.difference(last) < _coreDeathRecoveryCooldown) {
      // Budget spent within the cooldown window: stop restarting. Present an
      // honest stopped state and a user-visible error rather than a lying
      // "connected" UI whose every request silently times out.
      commonPrint.log(
        '[core-bridge] within cooldown — failing honest (stopped)',
      );
      await updateStatus(false);
      globalState.showNotifier(ErrorMapper.vpnStartFailed);
      return;
    }
    _lastCoreDeathRecovery = now;
    // One bounded self-heal: restartCore() clears _lastSetupHash and re-runs
    // handleStart if the UI still shows started.
    await restartCore();
  }

  /// Read-only reconcile of Dart VPN state with native runtime. Never toggles VPN.
  Future<void> syncRunStateFromNative() async {
    if (!Platform.isAndroid) return;
    final prevStartTime = globalState.startTime;
    await globalState.updateStartTime();
    final nativeIsRunning = globalState.startTime != null;
    final uiIsRunning = _ref.read(runTimeProvider.notifier).isStart;
    if (nativeIsRunning == uiIsRunning) return;

    commonPrint.log(
      'syncRunStateFromNative: native=$nativeIsRunning ui=$uiIsRunning '
      '(prev startTime=$prevStartTime, new=${globalState.startTime})',
    );

    if (nativeIsRunning) {
      updateRunTime();
      // The periodic ticker (runtime + speed) is armed only by
      // handleStart -> startUpdateTasks. On an EXTERNAL start (QS tile /
      // notification) the app isolate can be fresh, so globalState.tasks is
      // empty and the dashboard would freeze at a static runtime and 0 B/s.
      // Re-arm with the same task pair handleStart uses; startUpdateTasks is
      // idempotent via its timer.isActive guard.
      unawaited(globalState.startUpdateTasks([updateRunTime, updateTraffic]));
      // Symmetry with the stop branch's updateIcon(false) — macOS-only no-op
      // on Android, kept for parity with updateStatus(true)'s connected icon.
      await StatusBarManager.updateIcon(isConnected: true);
    } else {
      // Native already stopped — tear down Dart bookkeeping without re-calling handleStop.
      clashCore.resetTraffic();
      _ref.read(trafficsProvider.notifier).clear();
      _ref.read(totalTrafficProvider.notifier).value = Traffic();
      _ref.read(runTimeProvider.notifier).value = null;
      globalState.stopUpdateTasks();
      await StatusBarManager.updateIcon(isConnected: false);
      globalState.appController.addCheckIpNumDebounce();
    }
  }

  Future<void> updateStatus(bool isStart) async {
    // Fresh user action — new core-restart budget for requestAdmin.
    _coreRealignAttempts = 0;
    if (isStart) {
      // A panel/node/API upgrade may deliberately invalidate the old client
      // contract. Check just before connection so a stale app cannot present a
      // misleading "connected" state. Network failure is fail-open here; the
      // entitlement and managed-profile checks below remain authoritative.
      if (!await backendCompatibilityService.requireCompatibleOrExplain()) {
        return;
      }
      ConnectTrace.mark('updateStatus');
      // Central safety gate: every code path that turns the VPN on must
      // pass through here, so first-run disclosure consent is enforced
      // even for non-UI entry points (Quick Settings tile, desktop tray,
      // hotkey, hidden auto-run). Disconnect is intentionally never gated.
      // UI is NOT shown from the controller — the dashboard StartButton is
      // responsible for surfacing the dialog and persisting consent before
      // it calls back into this method. If consent is missing we simply
      // refuse the start so external triggers can't bypass the disclosure.
      if (!await vpnConsent.isAccepted()) {
        commonPrint.log(
          'updateStatus(true) refused: VPN disclosure consent not granted',
        );
        return;
      }
    }
    if (isStart) {
      // Regenerate proxy credentials for this session (SOCKS port protection)
      globalState.regenerateProxyCredentials();
      // Initialize foreground notification cache before starting
      initForegroundCache();
      // The managed profile can have been refreshed or a location can have
      // been selected immediately before the tap. Apply the complete config
      // synchronously before starting Android's VPN service; a debounced apply
      // after start allowed the service to come up with the previous selector
      // (often the first node in the profile) and made the first tap appear to
      // do nothing until the user opened Locations.
      if (Platform.isAndroid && _ref.read(currentProfileProvider) != null) {
        try {
          await globalState.appController.applyProfile(silence: true);
        } catch (error) {
          commonPrint
              .log('[connect] profile apply before start failed: $error');
          unawaited(backendCompatibilityService.checkAndNotify());
          globalState.showNotifier(
            'The VPN profile could not be applied. Refresh your account and try again.',
          );
          return;
        }
      }
      final started = await globalState.handleStart([
        updateRunTime,
        updateTraffic,
      ]);
      // null => a start/stop transition is already in flight (double-tap).
      // Do nothing: no toast, and leave the status icon untouched.
      if (started == null) {
        return;
      }
      // false => the start was attempted but failed. Revert the icon (it may
      // have been flipped on by an optimistic UI) and surface the error.
      if (started == false) {
        await StatusBarManager.updateIcon(isConnected: false);
        unawaited(backendCompatibilityService.checkAndNotify());
        globalState.showNotifier(ErrorMapper.vpnStartFailed);
        return;
      }
      // true => connected. Only now is it honest to show the connected icon.
      if (Platform.isAndroid) {
        // TUN readiness proves that the local VPN service is alive, but not
        // that traffic can actually reach the outside network through the
        // selected proxy. Confirm an external IP response before presenting a
        // successful connection. On failure the tunnel is rolled back so the
        // UI cannot claim a working VPN while traffic is going direct/stuck.
        final verified = await _verifyAndroidTunnel();
        if (!verified) {
          await updateStatus(false);
          unawaited(backendCompatibilityService.checkAndNotify());
          globalState.showNotifier(
            'The VPN tunnel started, but internet access could not be verified. Try another location or refresh the profile.',
          );
          return;
        }
        await StatusBarManager.updateIcon(isConnected: true);
        unawaited(
          const MethodChannel('com.avee.vpn/navigation')
              .invokeMethod<void>('requestBatteryExemption')
              .catchError((Object _) {}),
        );
        // FlClashX parity: the long-lived mihomo executor (DNS resolver, fake-ip
        // pool, providers) survives stop→start and degrades over long sessions —
        // force a full profile re-setup on every Android connect.
        // The mobile shell does not mount the legacy home scaffold. Passing
        // silence=true makes applyProfile run through the shell-safe path
        // instead of returning early when the old scaffold is absent.
        return;
      }
      await StatusBarManager.updateIcon(isConnected: true);
      final currentLastModified =
          await _ref.read(currentProfileProvider)?.profileLastModified;
      if (currentLastModified == null ||
          globalState.appController.lastProfileModified == null) {
        globalState.appController.addCheckIpNumDebounce();
        return;
      }
      if (currentLastModified <=
          (globalState.appController.lastProfileModified ?? 0)) {
        globalState.appController.addCheckIpNumDebounce();
        return;
      }
      globalState.appController.applyProfileDebounce();
    } else {
      // false => stop was ignored because a transition is in flight; do not
      // tear down UI/providers for a stop that never happened.
      final stopped = await globalState.handleStop();
      if (!stopped) return;
      await StatusBarManager.updateIcon(isConnected: false);
      // The mihomo executor survives stop→start and degrades over long
      // sessions (B2). The forced Android applyProfileDebounce() on connect
      // would be defeated by the setup-hash cache ("setup skipped"), so drop
      // the hash here: every connect-after-disconnect performs a REAL core
      // re-setup, while repeated applies during a live session stay cached.
      globalState.appController.invalidateSetupHash();
      // Clear credentials on disconnect
      globalState.clearProxyCredentials();
      clashCore.resetTraffic();
      _ref.read(trafficsProvider.notifier).clear();
      _ref.read(totalTrafficProvider.notifier).value = Traffic();
      _ref.read(runTimeProvider.notifier).value = null;
      globalState.appController.addCheckIpNumDebounce();
    }
  }

  /// Confirms the Android VPN is usable beyond the local TUN handshake.
  ///
  /// [request.checkIp] uses the normal platform network stack, so on Android
  /// its request is routed through the newly-created VPN tunnel. Multiple
  /// attempts tolerate the short DNS/proxy warm-up after the service starts.
  Future<bool> _verifyAndroidTunnel() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      try {
        final result = await request.checkIp();
        if (result.isSuccess && result.data != null) return true;
      } catch (error) {
        commonPrint.log('[connect] Android tunnel verification failed: $error');
      }
    }
    return false;
  }

  void updateRunTime() {
    final startTime = globalState.startTime;
    if (startTime != null) {
      final startTimeStamp = startTime.millisecondsSinceEpoch;
      final nowTimeStamp = DateTime.now().millisecondsSinceEpoch;
      _ref.read(runTimeProvider.notifier).value = nowTimeStamp - startTimeStamp;
    } else {
      _ref.read(runTimeProvider.notifier).value = null;
    }
  }

  Future<void> updateTraffic() async {
    final traffic = await clashCore.getTraffic();
    _ref.read(trafficsProvider.notifier).addTraffic(traffic);
    _ref.read(totalTrafficProvider.notifier).value =
        await clashCore.getTotalTraffic();
  }

  Future<Result<bool>> requestAdmin(bool enableTun) async {
    final realTunEnable = _ref.read(realTunEnableProvider);
    if (enableTun != realTunEnable && realTunEnable == false) {
      final code = await system.authorizeCore();
      switch (code) {
        case AuthorizeCode.success:
          if (_coreRealignAttempts >= _maxCoreRealignAttempts) {
            commonPrint.log(
                "[helper] restart budget exhausted after authorize — degrading to TUN-off for this apply cycle");
            enableTun = false;
            break;
          }
          _coreRealignAttempts++;
          await restartCore();
          return Result.error("");
        case AuthorizeCode.none:
          // Windows: AuthorizeCode.none only means "the helper service is up
          // and verified" — it does NOT mean the LIVE core was spawned through
          // it. On first launch / after an update / on the logon auto-start
          // race the core was spawned directly (unprivileged) before the
          // helper came up; pushing tun.enable=true at it silently fails
          // (wintun needs privileges) and used to poison the session until an
          // app restart. Realign: restart the core through the now-ready
          // helper, sharing the same bounded restart budget as the success
          // path so no authorize-outcome alternation can recurse forever.
          if (Platform.isWindows &&
              clashService?.coreStartedByHelper == false) {
            if (_coreRealignAttempts >= _maxCoreRealignAttempts) {
              // Budget exhausted — ship an honest proxy-only session instead
              // of a fake TUN one. The next user action resets the budget.
              commonPrint.log(
                  "[helper] realign budget exhausted — degrading to TUN-off for this apply cycle");
              enableTun = false;
              break;
            }
            _coreRealignAttempts++;
            commonPrint.log(
                "[helper] core is unprivileged but helper is ready — realigning core via helper (attempt $_coreRealignAttempts/$_maxCoreRealignAttempts)");
            await restartCore();
            return Result.error("");
          }
          break;
        case AuthorizeCode.error:
          enableTun = false;
          break;
      }
    }
    _ref.read(realTunEnableProvider.notifier).value = enableTun;
    return Result.success(enableTun);
  }

  void updateStart() {
    updateStatus(!_ref.read(runTimeProvider.notifier).isStart);
  }
}
