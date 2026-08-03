import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:avee/common/common.dart';
import 'package:avee/enum/enum.dart';
import 'package:avee/models/models.dart';
import 'package:flutter/material.dart';

const appName = "AVEE";
const appHelperService = "AveeHelperService";
const coreName = "clashx.meta";
const browserUa =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const packageName = "com.avee.vpn";
// SECURITY: Random.secure() (CSPRNG) — plain Random is predictable, IPC hijack risk.
final unixSocketPath =
    "/tmp/aveeSocket_${Random.secure().nextInt(1 << 32).toRadixString(16)}${Random.secure().nextInt(1 << 16).toRadixString(16)}.sock";
// Unique to AVEE — FlClashX (the upstream fork) also runs a Windows helper
// service on 47890; sharing it made both helpers fight for the same port
// (first to bind wins, the other can't serve). 47896 decouples us cleanly.
const helperPort = 47896;
const maxTextScale = 1.4;
const minTextScale = 0.8;
final baseInfoEdgeInsets = EdgeInsets.symmetric(
  vertical: 16.ap,
  horizontal: 16.ap,
);

final defaultTextScaleFactor =
    WidgetsBinding.instance.platformDispatcher.textScaleFactor;
const httpTimeoutDuration = Duration(milliseconds: 5000);
const moreDuration = Duration(milliseconds: 100);
const animateDuration = Duration(milliseconds: 100);
const midDuration = Duration(milliseconds: 200);
const commonDuration = Duration(milliseconds: 300);
const defaultUpdateDuration = Duration(days: 1);
const mmdbFileName = "geoip.metadb";
const asnFileName = "ASN.mmdb";
const geoIpFileName = "GeoIP.dat";
const geoSiteFileName = "GeoSite.dat";
final double kHeaderHeight = system.isDesktop
    ? !Platform.isMacOS
        ? 40
        : 28
    : 0;
const profilesDirectoryName = "profiles";
const localhost = "127.0.0.1";
const clashConfigKey = "clash_config";
const configKey = "config";
const socksPortKey = "socks_port";
const double dialogCommonWidth = 300;
const repository = "0x-gg/avee-android";
const defaultExternalController = "127.0.0.1:9090";
const maxMobileWidth = 600;
const maxLaptopWidth = 840;
const defaultTestUrl = "https://www.gstatic.com/generate_204";

// ─── In-app auto-update (sideloaded Android) — single source of truth ─────────
// See docs/plans/2026-06-25-auto-update.md. No update literals are scattered
// across services/native; everything funnels through these consts. The channel
// gate lives here (not in a view) so non-UI code — services, controller — can
// read it without importing the widget layer.

/// True ONLY on the Google Play build (`--dart-define=PLAY_BUILD=true`). The
/// in-app updater is inert on Play builds (Play policy forbids self-update from
/// an external source); this const-folds so the whole updater tree-shakes out
/// of the Play AAB. Every other channel — crucially the sideloaded RU build —
/// self-updates from [kUpdateManifestUrl].
const bool kIsPlayBuild = bool.fromEnvironment('PLAY_BUILD');

/// Public legal pages on aveevpn.com (linked from app and Play Console).
const kAveePrivacyPolicyUrl = 'https://aveevpn.com/#privacy';
const kAveeTermsUrl = 'https://aveevpn.com/#terms';
const kAveeAcceptableUseUrl = 'https://aveevpn.com/#acceptable-use';
const kAveeSupportUrl = 'https://aveevpn.com/#support';
const kAveeAccountDeletionUrl = 'https://aveevpn.com/#account-deletion';
const kAveeMarketingSiteUrl = 'https://aveevpn.com';

/// Update manifest published as a GitHub Release asset.
const kUpdateManifestUrl =
    "https://github.com/0x-gg/avee-android/releases/latest/download/update.json";

/// GitHub release asset filename SUFFIX per platform key. Release assets are
/// versioned as
/// `avee-<version>-<suffix>` (CI "Version asset filenames" step), so the
/// resolver interpolates the version WITHOUT the leading 'v'
/// (e.g. `avee-0.8.5-android-arm64-v8a.apk`), combined with [repository] +
/// the release tag (WITH 'v') to reconstruct the full asset URL.
const kGithubApkAssetByPlatform = <String, String>{
  'android-arm64': 'android-arm64-v8a.apk',
  'android-universal': 'android-universal.apk',
};

/// Subdir under the app cache dir where a downloaded APK is staged before install.
const kUpdateCacheDirName = "updates";

/// Scheduled (non-manual) auto-check cadence.
const kUpdateCheckInterval = Duration(hours: 24);
final commonFilter = ImageFilter.blur(
  sigmaX: 2.5,
  sigmaY: 2.5,
  tileMode: TileMode.mirror,
);

const navigationItemListEquality = ListEquality<NavigationItem>();
const connectionListEquality = ListEquality<Connection>();
const stringListEquality = ListEquality<String>();
const intListEquality = ListEquality<int>();
const logListEquality = ListEquality<Log>();
const groupListEquality = ListEquality<Group>();
const externalProviderListEquality = ListEquality<ExternalProvider>();
const packageListEquality = ListEquality<Package>();
const hotKeyActionListEquality = ListEquality<HotKeyAction>();
const stringAndStringMapEquality = MapEquality<String, String>();
const stringAndStringMapEntryIterableEquality =
    IterableEquality<MapEntry<String, String>>();
const delayMapEquality = MapEquality<String, Map<String, int?>>();
const stringSetEquality = SetEquality<String>();
const keyboardModifierListEquality = SetEquality<KeyboardModifier>();

const viewModeColumnsMap = {
  ViewMode.mobile: [2, 1],
  ViewMode.laptop: [3, 2],
  ViewMode.desktop: [4, 3],
};

const defaultPrimaryColor = 0xFFFF8C69;

double getWidgetHeight(num lines) => max(lines * 84 + (lines - 1) * 16, 0).ap;

const maxLength = 150;

const mainIsolate = "aveeMainIsolate";

const serviceIsolate = "aveeServiceIsolate";

const defaultPrimaryColors = [
  0xFF29FF76, // Emerald (Падение)
  0xFF38BDF8, // Frost
  0xFFA78BFA, // Amethyst
  0xFFEF4444, // Crimson
  0xFFF59E0B, // Amber
  0xFF64748B, // Stealth
];

/// Theme trio: accent + two ambient orb colors.
class ThemePreset {
  const ThemePreset(
    this.nameKey,
    this.accent,
    this.orbPrimary,
    this.orbSecondary,
  );

  final String nameKey; // l10n key, resolved in UI
  final int accent;
  final int orbPrimary;
  final int orbSecondary;
}

const themePresets = <ThemePreset>[
  ThemePreset('presetEmerald', 0xFF29FF76, 0xFF009938, 0xFF2BFF7A),
  ThemePreset('presetFrost', 0xFF38BDF8, 0xFF60A5FA, 0xFF38BDF8),
  ThemePreset('presetAmethyst', 0xFFA78BFA, 0xFF8B5CF6, 0xFFA855F7),
  ThemePreset('presetCrimson', 0xFFEF4444, 0xFFF87171, 0xFFB91C1C),
  ThemePreset('presetAmber', 0xFFF59E0B, 0xFFFBBF24, 0xFFB45309),
  ThemePreset('presetStealth', 0xFF64748B, 0xFF94A3B8, 0xFF475569),
];

const scriptTemplate = """
const main = (config) => {
  return config;
}""";
