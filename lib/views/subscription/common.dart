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
///
/// Returns whether the probe ACTUALLY ran: `false` when the running core's
/// groups contained NONE of [nodeNames] (nothing to dial — VPN off / core
/// mid-reload), so the caller can report the result as UNMEASURED instead of
/// misreading «no proxies to test» as «all servers dead».
Future<bool> _runCountryDelayTest(Ref ref, Set<String> nodeNames) async {
  if (nodeNames.isEmpty) return false;
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
  if (proxies.isEmpty) return false;
  await delayTest(proxies, null);
  return true;
}

/// True when the core's [groups] currently expose ANY node in [names] — i.e.
/// the core has finished loading this profile and the country nodes are
/// dialable. Used both as the self-heal trigger (a `select` over
/// [currentGroupsStateProvider]) and inside the grace poll.
bool _groupsContainAny(List<Group> groups, Set<String> names) {
  for (final group in groups) {
    for (final proxy in group.all) {
      if (names.contains(proxy.name)) return true;
    }
  }
  return false;
}

/// Outcome of a country liveness probe. Crucially distinguishes «we tested and
/// this is the alive set» from «we could not test at all», so the picker never
/// lies (an empty [alive] with [measured] false means «unknown», NOT «all
/// servers dead»).
class CountryProbeResult {
  const CountryProbeResult({required this.alive, required this.measured});

  /// Node names that resolved ALIVE (delay > 0). Only meaningful when
  /// [measured] is true.
  final Set<String> alive;

  /// Whether the probe ACTUALLY ran a delay test against real core proxies.
  /// `false` when the core groups never contained the target names (VPN off /
  /// core mid-reload → [_runCountryDelayTest] found `proxies.isEmpty`, or the
  /// grace poll expired without a match). Unmeasured → the picker shows every
  /// parsed country unfiltered rather than filtering the world away.
  final bool measured;
}

/// Resolves the country picker's liveness into a [CountryProbeResult]. The
/// picker renders the SETTLED list from this in one pass (skeleton → crossfade →
/// complete list) — the canonical «load, then show a stable list» pattern, no
/// incremental row-by-row insertion (that was the first-open jerkiness). It also
/// populates the global delay state ([getDelayProvider]) as a side effect so
/// each row's latency badge is filled.
///
/// SELF-HEALING: this `ref.watch`es a `select` over [currentGroupsStateProvider]
/// that reports whether ANY target node is present in the core's groups. When
/// the core finishes loading the profile (VPN turns on, or a mid-reload
/// settles), that boolean flips true, this provider AUTO re-runs, and the picker
/// upgrades from an unmeasured (show-everything) list to a real measured result
/// with NO user action. The grace poll below only covers the propagation lag
/// between the core update and the `select` re-emitting.
///
/// Always re-pings on (re)run — opening the picker and pull-to-refresh both
/// `invalidate`/`refresh` this, so latency is freshly measured (no stale cache).
/// The probe is AWAITED to completion (each node bounded by the core's per-node
/// timeout): a cold REALITY/gRPC handshake can take a few seconds on the first
/// measure, so capping early dropped real servers that then only appeared on the
/// 2nd open. Dead nodes (АВТО routers, decoys, anything mihomo can't dial)
/// resolve to < 0 and are filtered out. During a re-run the picker keeps showing
/// the PREVIOUS result (cached in the widget), so the list stays stable while
/// badges refresh.
///
/// Watched by the modes tab (pre-warm) and the open picker; autoDispose +
/// family(profileId), kept alive while either watches it.
final countryProbeProvider = FutureProvider.autoDispose
    .family<CountryProbeResult, String>((ref, profileId) async {
  final data = await ref.watch(modeProfileDataProvider(profileId).future);
  final names = {
    for (final e in countryPickerEntries(data.countries)) e.proxyName,
  };
  if (names.isEmpty) {
    return const CountryProbeResult(alive: <String>{}, measured: false);
  }

  Set<String> aliveSnapshot() => {
        for (final n in names)
          if ((ref.read(getDelayProvider(proxyName: n)) ?? 0) > 0) n,
      };

  // Self-heal trigger: re-run this provider the moment the core's groups start
  // exposing any of these nodes. `present` is false while the VPN is off or the
  // core is mid-reload; when it flips true the picker upgrades to measured
  // results on its own.
  final present = ref.watch(currentGroupsStateProvider.select(
    (state) => _groupsContainAny(state.value, names),
  ));

  // Grace poll (bounded ~3s): the `select` can lag the core by a frame or two
  // right after a switch, so give the groups state a moment to propagate before
  // we declare the probe impossible. This is a fallback — the `select` watch
  // above is the real self-heal mechanism.
  if (!present) {
    var disposed = false;
    ref.onDispose(() => disposed = true);
    var appeared = false;
    for (var i = 0; i < 20; i++) {
      if (disposed) {
        return CountryProbeResult(alive: aliveSnapshot(), measured: false);
      }
      if (_groupsContainAny(
          ref.read(currentGroupsStateProvider).value, names)) {
        appeared = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!appeared) {
      // The grace poll expired without the core ever loading a target node —
      // the probe could not run. UNMEASURED: the picker shows every parsed
      // country unfiltered (tappable + appliable), plus an «availability
      // unknown» notice, instead of falsely claiming there are no countries.
      return CountryProbeResult(alive: aliveSnapshot(), measured: false);
    }
  }

  // The core has the nodes: run one probe, awaited to COMPLETION. `tested` is
  // false only if the proxies vanished between the presence check and the probe
  // (another core reload) — treat that as unmeasured too, never «all dead».
  final tested = await _runCountryDelayTest(ref, names);
  return CountryProbeResult(alive: aliveSnapshot(), measured: tested);
});

// ── Country picker decision logic ─────────────────────────────────────────

/// The rendered state of the «Страна» picker — one honest bucket per real
/// situation, so the UI never lies about availability. Resolved purely by
/// [resolveCountryPickerState] (unit-tested) from the data + probe async values.
enum CountryPickerStatus {
  /// First load in flight: profile config or the initial probe hasn't settled.
  skeleton,

  /// The profile config failed to load (data error) — a genuine error, shown
  /// with a retry hint, NOT «no profile» / «no countries».
  error,

  /// The subscription genuinely parsed ZERO countries — the ONLY case where
  /// «обновите подписку» is honest.
  emptyCountries,

  /// Countries exist but liveness is UNKNOWN (probe couldn't run / errored):
  /// show every parsed country unfiltered + an «availability unknown» notice.
  unmeasured,

  /// Probe ran and found NOTHING alive (likely no internet): show every parsed
  /// country + a «servers unreachable» notice.
  allUnreachable,

  /// Probe ran and found live servers: the filtered list (active always kept).
  list,
}

/// The picker's resolved [status] plus the [entries] to render for it. For
/// [CountryPickerStatus.list] the entries are filtered to alive (+ active); for
/// [CountryPickerStatus.unmeasured] / [CountryPickerStatus.allUnreachable] they
/// are ALL parsed entries unfiltered; empty for skeleton/error/emptyCountries.
class CountryPickerState {
  const CountryPickerState(this.status, this.entries);

  final CountryPickerStatus status;
  final List<CountryPickerEntry> entries;
}

/// Pure decision function mapping the picker inputs → a [CountryPickerState].
/// Extracted (and unit-tested in test/views/country_picker_state_test.dart) so
/// the honesty matrix is verifiable without pumping a widget.
///
/// [cachedProbe] is the widget's last SETTLED [CountryProbeResult] (kept locally
/// so a re-ping never flickers the list back to skeleton); `null` before the
/// first settle. [activeCountry] is the currently applied country key, which is
/// always kept in the filtered list even if its probe says dead.
CountryPickerState resolveCountryPickerState({
  required AsyncValue<ModeProfileData> data,
  required AsyncValue<CountryProbeResult> probe,
  required CountryProbeResult? cachedProbe,
  required String? activeCountry,
}) {
  // 2. Config load failed → honest error (retry hint added by the widget).
  if (data.hasError) {
    return const CountryPickerState(CountryPickerStatus.error, []);
  }
  // 1. Config still loading (no value yet) → skeleton.
  if (data.isLoading) {
    return const CountryPickerState(CountryPickerStatus.skeleton, []);
  }
  final allEntries = countryPickerEntries(data.requireValue.countries);
  // 3. Subscription genuinely has no countries → «обновите подписку» (honest).
  if (allEntries.isEmpty) {
    return const CountryPickerState(CountryPickerStatus.emptyCountries, []);
  }
  // 4a. Probe errored → availability unknown, show everything.
  if (probe.hasError) {
    return CountryPickerState(CountryPickerStatus.unmeasured, allEntries);
  }
  // First probe hasn't settled yet (no cache) → skeleton.
  if (cachedProbe == null) {
    return const CountryPickerState(CountryPickerStatus.skeleton, []);
  }
  // 4b. Probe couldn't actually run → availability unknown, show everything.
  if (!cachedProbe.measured) {
    return CountryPickerState(CountryPickerStatus.unmeasured, allEntries);
  }
  // 5. Probe ran but nothing is alive → servers unreachable, show everything.
  if (cachedProbe.alive.isEmpty) {
    return CountryPickerState(CountryPickerStatus.allUnreachable, allEntries);
  }
  // 6. Measured with live servers → filtered list (АВТО/decoy/SOS hidden), the
  // active country always kept.
  final filtered = [
    for (final entry in allEntries)
      if (entry.key == activeCountry ||
          cachedProbe.alive.contains(entry.proxyName))
        entry,
  ];
  return CountryPickerState(CountryPickerStatus.list, filtered);
}
