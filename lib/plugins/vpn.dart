import 'dart:async';
import 'dart:convert';

import 'package:avee/clash/clash.dart';
import 'package:avee/common/common.dart';
import 'package:avee/models/models.dart';
import 'package:avee/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class VpnListener {
  void onDnsChanged(String dns) {}
}

class Vpn {
  factory Vpn() {
    _instance ??= Vpn._internal();
    return _instance!;
  }

  Vpn._internal() {
    methodChannel = const MethodChannel("vpn");
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "gc":
          clashCore.requestGc();
        case "getStartForegroundParams":
          if (handleGetStartForegroundParams != null) {
            return await handleGetStartForegroundParams!();
          }
          // Default handler for UI mode - get current proxy name from core
          return await _getDefaultForegroundParams();
        case "status":
          return clashLibHandler?.getRunTime() != null;
        case "networkChanged":
          // Underlying physical network changed beneath the live tunnel (WiFi<->cell,
          // pocket/Doze). Stale upstream proxy sessions (mux, Hy2/QUIC) would otherwise
          // be reused until their own long timeouts — the "minutes-long reconnect".
          // Drop them so new flows re-dial over the live network immediately.
          commonPrint.log(
            "[VPN] underlying network changed — closing stale core connections",
          );
          clashCore.closeConnections();
          // Delay measurements from the previous network are FICTION on the new
          // one (same physical flap that just orphaned those sessions). Wiping
          // delayDataSource flips every badge to «не замерено» (shimmer/blank)
          // instead of leaving stale green numbers next to nodes now failing on
          // the fresh network; the core's URLTest cycles + the rules sheet's
          // open-ping repopulate honest values within a cycle. Safe here:
          // networkChanged only fires under a LIVE tunnel, so the app (and
          // appController) is already initialized — no null-init window.
          globalState.appController.invalidateDelayData();
        default:
          for (final listener in _listeners) {
            switch (call.method) {
              case "dnsChanged":
                final dns = call.arguments as String;
                listener.onDnsChanged(dns);
            }
          }
      }
    });
  }
  static Vpn? _instance;
  late MethodChannel methodChannel;
  FutureOr<String> Function()? handleGetStartForegroundParams;

  /// Cached server name for foreground notification (updated via updateServerName)
  String _cachedServerName = "";

  /// Cached profile info for foreground notification
  String _cachedProfileName = "AVEE";
  String _cachedServiceName = "";

  /// Update cached server name (called from UI when proxy changes)
  void updateServerName(String serverName) {
    _cachedServerName = serverName;
  }

  /// Update cached profile info (called when profile changes or on init)
  void updateProfileInfo({
    required String profileName,
    required String serviceName,
  }) {
    _cachedProfileName = profileName;
    _cachedServiceName = serviceName;
  }

  /// Get cached server name
  String get cachedServerName => _cachedServerName;

  /// Get cached profile name
  String get cachedProfileName => _cachedProfileName;

  /// Get cached service name
  String get cachedServiceName => _cachedServiceName;

  /// Default foreground params when running in UI mode.
  /// Shows: title = panel profile title (else selected server, else cached
  /// service name, else cached profile name), content = traffic speed,
  /// server (subText) = empty.
  Future<String> _getDefaultForegroundParams() async {
    try {
      // UI-mode traffic read goes through the bridge invoke and is async —
      // it MUST be awaited, else the notification renders a Future instance.
      final traffic = await clashCore.getTraffic();
      final profile = globalState.config.currentProfile;

      // Current proxy/server name
      String? proxyName;
      try {
        final header = profile?.providerHeaders['avee-serverinfo'];
        final serverInfoGroupName =
            header == null ? null : decodeMaybeBase64(header);
        if (serverInfoGroupName != null && serverInfoGroupName.isNotEmpty) {
          proxyName = globalState.appController
              .getSelectedProxyName(serverInfoGroupName);
        }
      } catch (e) {
        commonPrint.log('[vpn] failed to resolve selected proxy name: $e');
      }

      // Title: panel profile title (Remnawave `profile-title`, the big
      // dashboard subscription-card title — may be `base64:`-prefixed), else
      // selected server name, else cached service name, else cached profile
      // name. Same preference order as the _service-mode handler in main.dart.
      final rawProfileTitle = profile?.providerHeaders['profile-title'];
      final profileTitle = (rawProfileTitle == null || rawProfileTitle.isEmpty)
          ? ""
          : decodeMaybeBase64(rawProfileTitle).trim();
      final serverDisplay = (proxyName ?? "").trim();
      final title = profileTitle.isNotEmpty
          ? profileTitle
          : (serverDisplay.isNotEmpty
              ? serverDisplay
              : (_cachedServiceName.isNotEmpty
                  ? _cachedServiceName
                  : _cachedProfileName));

      return json.encode({
        "title": title,
        "server": "",
        "content": "\u2191 ${traffic.up.show}/s  \u2193 ${traffic.down.show}/s",
      });
    } catch (e) {
      return json.encode({
        "title": "AVEE",
        "server": "",
        "content": "",
      });
    }
  }

  final ObserverList<VpnListener> _listeners = ObserverList<VpnListener>();

  Future<bool?> start(AndroidVpnOptions options) async =>
      methodChannel.invokeMethod<bool>("start", {
        'data': json.encode(options),
      });

  Future<bool?> stop() async => methodChannel.invokeMethod<bool>("stop");

  /// Show subscription expiration notification
  Future<bool?> showSubscriptionNotification({
    required String title,
    required String message,
    required String actionLabel,
    required String actionUrl,
  }) async =>
      methodChannel.invokeMethod<bool>("showSubscriptionNotification", {
        'title': title,
        'message': message,
        'actionLabel': actionLabel,
        'actionUrl': actionUrl,
      });

  void addListener(VpnListener listener) {
    _listeners.add(listener);
  }

  void removeListener(VpnListener listener) {
    _listeners.remove(listener);
  }
}

Vpn? get vpn {
  // On Android, we always need Vpn instance to handle method channel calls
  // from the VPN service (e.g., getStartForegroundParams)
  if (defaultTargetPlatform == TargetPlatform.android) {
    return Vpn();
  }
  // On other platforms, only create in service mode
  return globalState.isService ? Vpn() : null;
}
