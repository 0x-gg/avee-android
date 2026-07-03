import 'package:dropweb/common/common.dart';
import 'package:dropweb/common/work_mode_patch.dart';
import 'package:dropweb/models/models.dart' hide Action;
import 'package:dropweb/providers/providers.dart';
import 'package:dropweb/state.dart';
import 'package:dropweb/views/proxies/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Parsed work-mode inputs for the current profile, read from the profile's
/// resolved config so they reflect the actual subscription nodes:
/// - [countries]: flag-emoji → node names (flagless nodes appear as their own
///   single-node groups keyed by node name, see [groupNodesByCountry]),
///   produced over [interceptLeafNodes] (rule-group leaves only — the
///   disconeko SOS pool baked into raw `proxies` is excluded so the picker
///   shows only panel-curated countries);
/// - [hasSmartCandidates]: whether the smart «Умный» group will be injectable
///   (a primary router exists AND resolves to ≥1 leaf node). Smart mode is
///   unavailable otherwise — matches [smartGroupWillInject], the exact
///   condition the work-mode patch uses to inject.
class ModeProfileData {
  const ModeProfileData({
    required this.countries,
    required this.hasSmartCandidates,
  });

  final Map<String, List<String>> countries;
  final bool hasSmartCandidates;
}

/// File-scoped: only the modes tab consumes this. Keyed by profile id so a
/// profile switch re-reads the right config.
final modeProfileDataProvider =
    FutureProvider.autoDispose.family<ModeProfileData, String>(
  (ref, profileId) async {
    // Re-evaluate when THIS profile's subscription is updated: getProfileConfig
    // reads the saved file, whose content changes on update while `profileId`
    // (the family key) does NOT — without this watch the provider would keep a
    // stale (possibly mid-update empty) result, which is what made the country
    // list transiently vanish after a refresh. `lastUpdateDate` changes on every
    // successful update; `providerHeaders` covers a disconeko-header flip.
    ref.watch(profilesProvider.select((profiles) {
      final p = profiles.getProfile(profileId);
      return (p?.lastUpdateDate, p?.providerHeaders.length);
    }));
    final cfg = await globalState.getProfileConfig(profileId);
    // Country candidates come from the rule-group leaves only (same structurally
    // SOS-free set as Smart) — NOT raw cfg['proxies'], which carries the
    // disconeko emergency pool. Otherwise the picker would surface SOS flags
    // (🇷🇺/🇬🇧/…) the panel subscription never offers. `interceptLeafNodes`
    // resolves rules from either the 'rules' or 'rule' key (`_resolveRules`),
    // and getProfileConfig output uses 'rules'. Native Remnawave Hy2 nodes flow
    // through here as ordinary leaf nodes — no special-case overlay needed.
    return ModeProfileData(
      countries: groupNodesByCountry(interceptLeafNodes(cfg)),
      hasSmartCandidates: smartGroupWillInject(cfg),
    );
  },
);

/// Runs a through-proxy delay test on [nodeNames] (resolved to live proxy
/// objects from the running core's groups state, via the [delayTest] primitive
/// with the app's default test URL). Populates the global delay state; callers
/// read liveness back via [getDelayProvider].
Future<void> _runCountryDelayTest(Ref ref, Set<String> nodeNames) async {
  if (nodeNames.isEmpty) return;
  final groups = ref.read(currentGroupsStateProvider).value;
  final proxies = <Proxy>[];
  final seen = <String>{};
  for (final group in groups) {
    for (final proxy in group.all) {
      if (nodeNames.contains(proxy.name) && seen.add(proxy.name)) {
        proxies.add(proxy);
      }
    }
  }
  if (proxies.isEmpty) return;
  await delayTest(proxies, null);
}

/// Resolves the country picker's liveness and returns the set of node names that
/// are ALIVE (delay > 0). The picker renders the SETTLED list from this in one
/// pass (skeleton → crossfade → complete list) — the canonical «load, then show
/// a stable list» pattern, no incremental row-by-row insertion (that was the
/// first-open jerkiness). It also populates the global delay state
/// ([getDelayProvider]) as a side effect so each row's latency badge is filled.
///
/// Always re-pings on (re)run — opening the picker and pull-to-refresh both
/// `invalidate`/`refresh` this, so latency is freshly measured (no stale cache).
/// First it waits (bounded) for the core to actually load THIS profile's nodes
/// (the core reloads asynchronously on a switch), then probes and AWAITS the
/// probe to completion (each node bounded by the core's per-node timeout): a
/// cold REALITY/gRPC handshake can take a few seconds on the first measure, so
/// capping early dropped real servers that then only appeared on the 2nd open.
/// Dead nodes (АВТО routers, decoys, anything mihomo can't dial) resolve to < 0
/// and are filtered out. During a re-run the picker keeps showing the PREVIOUS
/// alive set (cached in the widget), so the list stays stable while badges
/// refresh.
///
/// Watched by the modes tab (pre-warm) and the open picker; autoDispose +
/// family(profileId), kept alive while either watches it.
final countryProbeProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, profileId) async {
  final data = await ref.watch(modeProfileDataProvider(profileId).future);
  final names = {
    for (final e in countryPickerEntries(data.countries)) e.proxyName,
  };
  if (names.isEmpty) return const <String>{};

  Set<String> aliveSnapshot() => {
        for (final n in names)
          if ((ref.read(getDelayProvider(proxyName: n)) ?? 0) > 0) n,
      };

  // Wait (bounded ~3s) for the core groups to contain these nodes — after a
  // profile switch the core reloads asynchronously, so they can be missing for
  // a moment.

  var disposed = false;
  ref.onDispose(() => disposed = true);
  for (var i = 0; i < 20; i++) {
    if (disposed) return aliveSnapshot();
    final available = <String>{
      for (final g in ref.read(currentGroupsStateProvider).value)
        for (final p in g.all) p.name,
    };
    if (names.any(available.contains)) break;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  if (disposed) return aliveSnapshot();

  // One probe, awaited to COMPLETION (each node is already bounded by the
  // core's per-node timeout). A cold VLESS-REALITY / gRPC handshake can take a
  // few seconds on the FIRST measure, so an early cap dropped real servers that
  // then only showed up on the 2nd open. We wait for every node to resolve;
  // dead ones simply end up < 0 and are filtered out of the alive set.
  await _runCountryDelayTest(ref, names);
  return aliveSnapshot();
});
