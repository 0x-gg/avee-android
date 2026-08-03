import 'package:avee/common/constant.dart';
import 'package:avee/common/utils.dart' show utils;
import 'package:avee/models/models.dart';

/// Pure: maps a fetched `update.json` manifest to an [AppUpdateInfo] for the
/// android-arm64 platform, or null when there is no newer/valid update.
///
/// Single source of truth for the GitHub Release URL is the `repository`
/// const. The manifest and fallback both resolve to signed GitHub Release
/// assets.
///
/// No IO: callers fetch the manifest (tunnel-aware) and pass it in, which keeps
/// this unit-testable without a network.
AppUpdateInfo? resolveAndroidUpdate({
  required Map<String, dynamic> manifest,
  required String localVersion,
  String platformKey = 'android-arm64',
}) {
  final remote = (manifest['version']?.toString() ?? '').trim();
  if (remote.isEmpty) return null;
  // remote <= local (older or equal) => nothing to offer.
  if (utils.compareVersions(remote, localVersion) <= 0) return null;

  final platforms = manifest['platforms'];
  if (platforms is! Map) return null;
  final entry = platforms[platformKey];
  if (entry is! Map) return null;
  final url = entry['url'];
  if (url is! String || url.isEmpty) return null;

  final version = remote.startsWith('v') ? remote.substring(1) : remote;
  final tag = 'v$version';
  final suffix = kGithubApkAssetByPlatform[platformKey];
  final fallback = suffix == null
      ? null
      : 'https://github.com/$repository/releases/download/$tag/avee-$version-$suffix';

  final notes = manifest['notes'] is List
      ? (manifest['notes'] as List).map((e) => e.toString()).toList()
      : const <String>[];

  return AppUpdateInfo(
    version: version,
    tag: tag,
    notes: notes,
    primaryUrl: url,
    fallbackUrl: fallback,
    sha256: (entry['sha256'] as String?)?.toLowerCase(),
    mandatory: manifest['mandatory'] == true,
    minSupported: manifest['minSupported']?.toString(),
  );
}
