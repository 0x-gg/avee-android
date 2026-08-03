// ignore_for_file: invalid_annotation_target
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:avee/clash/core.dart';
import 'package:avee/common/common.dart';
import 'package:avee/common/share_link_profile.dart';
import 'package:avee/common/smart_pool_patch.dart';
import 'package:avee/enum/enum.dart';
import 'package:avee/utils/device_info_service.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'clash_config.dart';

part 'generated/profile.freezed.dart';
part 'generated/profile.g.dart';

typedef SelectedMap = Map<String, String>;

@freezed
class SubscriptionInfo with _$SubscriptionInfo {
  const factory SubscriptionInfo({
    @Default(0) int upload,
    @Default(0) int download,
    @Default(0) int total,
    @Default(0) int expire,
  }) = _SubscriptionInfo;

  factory SubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$SubscriptionInfoFromJson(json);

  factory SubscriptionInfo.formHString(String? info) {
    if (info == null) return const SubscriptionInfo();
    final list = info.split(";");
    final map = <String, int?>{};
    for (final i in list) {
      final keyValue = i.trim().split("=");
      map[keyValue[0]] = int.tryParse(keyValue[1]);
    }
    return SubscriptionInfo(
      upload: map["upload"] ?? 0,
      download: map["download"] ?? 0,
      total: map["total"] ?? 0,
      expire: map["expire"] ?? 0,
    );
  }
}

/// Process-lifetime negative cache for disconeko (SOS pool) endpoints.
///
/// The SOS fetch sits on the CRITICAL PATH of every subscription
/// import/update. A blackholing endpoint (observed in the wild: the panel
/// advertises a `avee-disconeko` host that drops packets) would otherwise
/// tax every update with a full connect timeout. One failure → the endpoint
/// is skipped for [retryCooldown]; a success clears the record. In-memory
/// only: a fresh launch retries naturally.
abstract final class _SosFetchGate {
  static const fetchTimeout = Duration(seconds: 2);
  static const retryCooldown = Duration(minutes: 15);
  static final Map<String, DateTime> _failedAt = {};

  static bool inCooldown(String url) {
    final at = _failedAt[url];
    if (at == null) return false;
    if (DateTime.now().difference(at) >= retryCooldown) return false;
    commonPrint.log(
      'avee-disconeko skipped: endpoint in failure cooldown',
    );
    return true;
  }

  static void recordFailure(String url) => _failedAt[url] = DateTime.now();

  static void recordSuccess(String url) => _failedAt.remove(url);
}

@freezed
class Profile with _$Profile {
  const factory Profile({
    required String id,
    String? label,
    String? currentGroupName,
    @Default("") String url,
    DateTime? lastUpdateDate,
    required Duration autoUpdateDuration,
    SubscriptionInfo? subscriptionInfo,
    @Default(true) bool autoUpdate,
    @Default({}) SelectedMap selectedMap,
    @Default({}) Set<String> unfoldSet,
    @Default(OverrideData()) OverrideData overrideData,
    @JsonKey(includeToJson: false, includeFromJson: false)
    @Default(false)
    bool isUpdating,
    @Default({}) Map<String, String> providerHeaders,
    String? fallbackUrl,
    @JsonKey(unknownEnumValue: WorkMode.standard)
    @Default(WorkMode.standard)
    WorkMode workMode,
    String? staticCountry,
  }) = _Profile;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);

  factory Profile.normal({
    String? label,
    String url = '',
  }) =>
      Profile(
        label: label,
        url: url,
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        autoUpdateDuration: defaultUpdateDuration,
      );
}

@freezed
class OverrideData with _$OverrideData {
  const factory OverrideData({
    @Default(false) bool enable,
    @Default(OverrideRule()) OverrideRule rule,
  }) = _OverrideData;

  factory OverrideData.fromJson(Map<String, Object?> json) =>
      _$OverrideDataFromJson(json);
}

extension OverrideDataExt on OverrideData {
  List<String> get runningRule {
    if (!enable) {
      return [];
    }
    return rule.rules.map((item) => item.value).toList();
  }
}

@freezed
class OverrideRule with _$OverrideRule {
  const factory OverrideRule({
    @Default(OverrideRuleType.added) OverrideRuleType type,
    @Default([]) List<Rule> overrideRules,
    @Default([]) List<Rule> addedRules,
  }) = _OverrideRule;

  factory OverrideRule.fromJson(Map<String, Object?> json) =>
      _$OverrideRuleFromJson(json);
}

extension OverrideRuleExt on OverrideRule {
  List<Rule> get rules => switch (type == OverrideRuleType.override) {
        true => overrideRules,
        false => addedRules,
      };

  OverrideRule updateRules(List<Rule> Function(List<Rule> rules) builder) {
    if (type == OverrideRuleType.added) {
      return copyWith(addedRules: builder(addedRules));
    }
    return copyWith(overrideRules: builder(overrideRules));
  }
}

extension ProfilesExt on List<Profile> {
  Profile? getProfile(String? profileId) {
    final index = indexWhere((profile) => profile.id == profileId);
    return index == -1 ? null : this[index];
  }
}

extension ProfileExtension on Profile {
  ProfileType get type =>
      url.isEmpty == true ? ProfileType.file : ProfileType.url;

  bool get realAutoUpdate => url.isEmpty == true ? false : autoUpdate;

  /// Human-facing subscription/service name, mirroring the dashboard card
  /// resolution (MetainfoWidget.pickTitle): the Remnawave `profile-title`
  /// header wins, then the `avee-servicename` header, then the stored
  /// `label`, then the raw `id`. Both branding headers may arrive base64
  /// (optionally `base64:`-prefixed), so they are decoded here. Never empty.
  String get serviceName {
    String? decode(String? value) {
      if (value == null || value.isEmpty) return null;
      return decodeMaybeBase64(value);
    }

    for (final candidate in [
      decode(providerHeaders['profile-title']),
      decode(providerHeaders['avee-servicename']),
    ]) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    final trimmedLabel = label?.trim();
    return (trimmedLabel != null && trimmedLabel.isNotEmpty)
        ? trimmedLabel
        : id;
  }

  Future<void> checkAndUpdate() async {
    final isExists = await check();
    if (!isExists) {
      if (url.isNotEmpty && realAutoUpdate) {
        await update();
      }
    }
  }

  Future<bool> check() async {
    final profilePath = await appPath.getProfilePath(id);
    return File(profilePath).exists();
  }

  Future<File> getFile() async {
    final path = await appPath.getProfilePath(id);
    final file = File(path);
    final isExists = await file.exists();
    if (!isExists) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<int> get profileLastModified async {
    final file = await getFile();
    return (await file.lastModified()).microsecondsSinceEpoch;
  }

  Future<Profile> update({bool shouldSendHeaders = true}) async {
    final headers = <String, dynamic>{};

    if (shouldSendHeaders) {
      final deviceInfoService = DeviceInfoService();
      final details = await deviceInfoService.getDeviceDetails();

      if (details.hwid != null) headers['x-hwid'] = details.hwid;
      if (details.os != null) headers['x-device-os'] = details.os;
      if (details.osVersion != null) headers['x-ver-os'] = details.osVersion;
      if (details.model != null) headers['x-device-model'] = details.model;
    }

    // Resolve URL on demand — `this.url` is empty post-migration.
    final primaryUrl = await preferences.getProfileUrl(this);
    if (primaryUrl == null || primaryUrl.isEmpty) {
      throw Exception(
        'Profile ${id} has no subscription URL in secure storage',
      );
    }
    final fallback = await preferences.getProfileFallbackUrl(this);

    Response<Uint8List> response;
    try {
      response = await request.getFileResponseForUrl(
        primaryUrl,
        headers: headers.isNotEmpty ? headers : null,
      );
    } catch (e) {
      if (fallback != null && fallback.isNotEmpty) {
        response = await request.getFileResponseForUrl(
          fallback,
          headers: headers.isNotEmpty ? headers : null,
        );
      } else {
        rethrow;
      }
    }

    final disposition = response.headers.value("content-disposition");
    final userinfo = response.headers.value('subscription-userinfo');

    final responseData = response.data;
    if (responseData == null) {
      throw Exception("Failed to get profile data from response.");
    }

    final providerHeaders = <String, String>{};

    final headersToCollect = [
      'announce',
      'support-url',
      'profile-update-interval',
      'x-hwid-limit',
      'fallback-url',
      // Standard Remnawave subscription headers — profile title and the
      // subscription page URL, collected as harmless metadata.
      'profile-title',
      'profile-web-page-url',
    ];

    for (final headerName in headersToCollect) {
      final value = response.headers.value(headerName);
      if (value != null && value.isNotEmpty) {
        providerHeaders[headerName] = value;
      }
    }

    // Subscription providers (Remnawave panel templates) return avee-*
    // HTTP headers to customize the dashboard layout, theme, service name,
    // logo, and behavior. Legacy flclashx-* headers from FlClashX-targeted
    // panels are intentionally NOT accepted — AVEE is a distinct product
    // and must not share a customization protocol surface with FlClashX
    // (see .sisyphus/plans/2026-04-20-flclashx-hard-decouple.md for the
    // decision record).
    response.headers.forEach((name, values) {
      if (name.toLowerCase().startsWith('avee-') && values.isNotEmpty) {
        providerHeaders[name.toLowerCase()] = values.first;
      }
    });

    Duration? durationFromHeader;
    final updateIntervalHeader = providerHeaders['profile-update-interval'];
    if (updateIntervalHeader != null) {
      final hours = int.tryParse(updateIntervalHeader);
      if (hours != null && hours > 0) {
        durationFromHeader = Duration(hours: hours);
      }
    }

    final newFallbackUrl = providerHeaders['fallback-url'];

    // Some providers return a raw, newline-separated list of share links
    // (e.g. `vless://...`, `trojan://...`) instead of a Mihomo/Clash YAML
    // document. Detect that case here and rewrite the bytes to a minimal,
    // self-contained Mihomo YAML before they hit `saveFile`. Returns `null`
    // for normal YAML, in which case `responseData` flows through unchanged.
    var bytesToSave = responseData;
    final decoded = utf8.decode(responseData, allowMalformed: true);
    final converted = convertShareLinkSubscriptionToMihomo(decoded);
    if (converted != null) {
      bytesToSave = Uint8List.fromList(utf8.encode(converted));
    }

    // SOS / disconeko emergency fallback. When the provider advertises a
    // `avee-disconeko` URL it points to a SEPARATE pool of emergency
    // servers (raw share links or a Mihomo YAML). Merge that pool into the
    // delivered config and surface it through the `📶 First Available`
    // (`type: fallback`) proxy-group — a manual, opt-in selection the user must
    // pick deliberately; it never becomes the default route. The fallback group
    // is created if the delivered config lacks one. This is strictly best-
    // effort: the emergency pool is optional and must NEVER break the primary
    // update.
    final disconekoUrl = providerHeaders['avee-disconeko'];
    if (disconekoUrl != null &&
        disconekoUrl.isNotEmpty &&
        !_SosFetchGate.inCooldown(disconekoUrl)) {
      try {
        // Hard cap on the OPTIONAL emergency-pool fetch. Without it an
        // unreachable disconeko endpoint stalls EVERY import/update for the
        // full Dio connect timeout (observed: +15s on first import and on
        // every startup refresh). A healthy endpoint answers well under 2s;
        // on expiry the TimeoutException lands in the catch below, the
        // failure is remembered ([_SosFetchGate]) so follow-up updates skip
        // the dead endpoint instantly, and the primary update proceeds
        // unpatched.
        final sosResponse = await request
            .getFileResponseForUrl(disconekoUrl)
            .timeout(_SosFetchGate.fetchTimeout);
        _SosFetchGate.recordSuccess(disconekoUrl);
        final sosData = sosResponse.data;
        if (sosData != null) {
          final sosContent = utf8.decode(sosData, allowMalformed: true);
          final sosProxies = parseSubscriptionToProxies(sosContent);
          if (sosProxies.isNotEmpty) {
            final patched = patchSmartPool(
              utf8.decode(bytesToSave),
              sosProxies,
            );
            // Best-effort: if the embedded core rejects the patched config
            // (e.g. an unsupported field on this older fork), keep the
            // un-patched profile rather than breaking the whole subscription.
            final patchError = await clashCore.validateConfig(patched);
            if (patchError.isEmpty) {
              bytesToSave = Uint8List.fromList(utf8.encode(patched));
            } else {
              commonPrint.log(
                'avee-disconeko patch rejected by core: $patchError',
              );
            }
          }
        }
      } catch (e) {
        // Best-effort: the SOS pool is optional. Skip it on any failure (fetch,
        // decode, parse) and keep the primary profile update intact. Remember
        // the failure so the next updates don't pay the timeout again.
        _SosFetchGate.recordFailure(disconekoUrl);
        commonPrint.log('avee-disconeko SOS merge skipped: $e');
      }
    }

    return copyWith(
      label: label ?? utils.getFileNameForDisposition(disposition) ?? id,
      subscriptionInfo: SubscriptionInfo.formHString(userinfo),
      autoUpdateDuration: durationFromHeader ?? autoUpdateDuration,
      providerHeaders: providerHeaders,
      fallbackUrl: newFallbackUrl ?? fallbackUrl,
    ).saveFile(bytesToSave);
  }

  Future<Profile> saveFile(Uint8List bytes) async {
    final message = await clashCore.validateConfig(utf8.decode(bytes));
    if (message.isNotEmpty) {
      throw message;
    }
    final file = await getFile();
    // Atomic write: stage into a sibling temp file then rename over the target.
    // A kill mid-write would otherwise leave the stored profile truncated/corrupt.
    // File.rename is atomic on the same filesystem (macOS/Linux/Android); on
    // Windows a rename onto an existing target can throw, so fall back to
    // delete-then-rename.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(file.path);
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    }
    return copyWith(lastUpdateDate: DateTime.now());
  }

  Future<Profile> saveFileWithString(String value) async {
    final message = await clashCore.validateConfig(value);
    if (message.isNotEmpty) {
      throw message;
    }
    final file = await getFile();
    // Atomic write: stage into a sibling temp file then rename over the target.
    // A kill mid-write would otherwise leave the stored profile truncated/corrupt.
    // File.rename is atomic on the same filesystem (macOS/Linux/Android); on
    // Windows a rename onto an existing target can throw, so fall back to
    // delete-then-rename.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    try {
      await tmp.rename(file.path);
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    }
    return copyWith(lastUpdateDate: DateTime.now());
  }
}
