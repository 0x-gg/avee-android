import 'package:avee/common/common.dart';
import 'package:avee/state.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'avee_api.dart';

class BackendCompatibility {
  const BackendCompatibility({
    required this.clientVersion,
    required this.compatible,
    required this.updateAvailable,
    required this.requiredUpdate,
    required this.minimumVersion,
    required this.recommendedVersion,
    required this.storeUrl,
    required this.message,
    required this.apiContract,
    required this.panelVersion,
    required this.nodeVersion,
    required this.subpageVersion,
    required this.mihomoVersion,
  });

  final String clientVersion;
  final bool compatible;
  final bool updateAvailable;
  final bool requiredUpdate;
  final String minimumVersion;
  final String recommendedVersion;
  final String storeUrl;
  final String message;
  final String apiContract;
  final String panelVersion;
  final String nodeVersion;
  final String subpageVersion;
  final String mihomoVersion;

  factory BackendCompatibility.fromJson(Map<String, dynamic> json) {
    final stack = json['stack'] is Map
        ? Map<String, dynamic>.from(json['stack'] as Map)
        : const <String, dynamic>{};
    return BackendCompatibility(
      clientVersion: json['clientVersion']?.toString() ?? '',
      compatible: json['compatible'] == true,
      updateAvailable: json['updateAvailable'] == true,
      requiredUpdate: json['requiredUpdate'] == true,
      minimumVersion: json['minimumVersion']?.toString() ?? '0.0.0',
      recommendedVersion: json['recommendedVersion']?.toString() ?? '0.0.0',
      storeUrl: json['storeUrl']?.toString() ??
          'https://play.google.com/store/apps/details?id=com.avee.vpn',
      message: json['message']?.toString() ??
          'AVEE service infrastructure was updated. Update the app if connection is unavailable.',
      apiContract: stack['apiContract']?.toString() ?? 'unknown',
      panelVersion: stack['panel']?.toString() ?? 'unknown',
      nodeVersion: stack['node']?.toString() ?? 'unknown',
      subpageVersion: stack['subpage']?.toString() ?? 'unknown',
      mihomoVersion: stack['mihomo']?.toString() ?? 'unknown',
    );
  }
}

/// Checks compatibility without exposing provider credentials or forcing the
/// app to poll in the background. It is called at launch/foreground and again
/// immediately before a connection attempt.
class BackendCompatibilityService {
  BackendCompatibilityService({AveeApi? api})
      : _api = api ?? AveeApi(baseUrl: _defaultBaseUrl);

  static const _defaultBaseUrl = 'https://api.aveevpn.app';
  final AveeApi _api;
  BackendCompatibility? lastKnown;
  DateTime? _lastNoticeAt;

  Future<BackendCompatibility?> check() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final result = BackendCompatibility.fromJson(
        await _api.compatibility(appVersion: packageInfo.version),
      );
      lastKnown = result;
      return result;
    } catch (error) {
      // Compatibility is fail-open when the control plane cannot be reached;
      // the normal entitlement/profile checks remain authoritative.
      commonPrint.log('[compatibility] check failed: $error');
      return null;
    }
  }

  Future<void> checkAndNotify() async {
    final result = await check();
    if (result == null || !result.updateAvailable) return;
    final now = DateTime.now();
    if (_lastNoticeAt != null &&
        now.difference(_lastNoticeAt!) < const Duration(hours: 12)) {
      return;
    }
    _lastNoticeAt = now;
    if (result.requiredUpdate) {
      await _showUpdateDialog(result);
    } else {
      globalState.showNotifier(
        'An AVEE service update is available. Update the app if connection is unavailable.',
      );
    }
  }

  Future<bool> requireCompatibleOrExplain() async {
    final result = await check();
    if (result == null || result.compatible) return true;
    await _showUpdateDialog(result);
    return false;
  }

  Future<void> _showUpdateDialog(BackendCompatibility result) async {
    final context = globalState.navigatorKey.currentContext;
    if (context == null) {
      globalState.showNotifier(result.message);
      return;
    }
    final accepted = await globalState.showMessage(
      title: 'Update required',
      message: TextSpan(
        text: '${result.message}\n\n'
            'Installed app: ${result.clientVersion}\n'
            'Required app: ${result.minimumVersion}',
      ),
      cancelable: !result.requiredUpdate,
      confirmText: 'Update app',
    );
    if (accepted != true) return;
    final uri = Uri.tryParse(result.storeUrl);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

final backendCompatibilityService = BackendCompatibilityService();
