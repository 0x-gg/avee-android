import 'package:dropweb/common/common.dart';
import 'package:dropweb/common/error_mapper.dart';
import 'package:dropweb/providers/providers.dart';
import 'package:dropweb/views/subscription/common.dart';
import 'package:dropweb/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deep screen for «Страна»: a full-page country picker (opened via
/// [showExtend]). Lists detected countries as [ListItem] rows (Twemoji flag +
/// an availability delay badge — the same delay/ms surface the proxy-group
/// rows use); the active country is checkmarked. Tapping a country row applies
/// the mode through [onApply] (flag only) and pops back to the modes tab.
class CountryDeepView extends ConsumerStatefulWidget {
  const CountryDeepView({
    required this.profileId,
    required this.onApply,
  });

  final String profileId;
  final ValueChanged<String> onApply;

  @override
  ConsumerState<CountryDeepView> createState() => _CountryDeepViewState();
}

class _CountryDeepViewState extends ConsumerState<CountryDeepView> {
  /// One-shot guard: re-ping once when the picker opens so latency is freshly
  /// measured on open (the kept-alive probe would otherwise serve the modes-tab
  /// pre-warm result without re-testing).
  bool _autoPinged = false;

  /// Last settled probe RESULT — kept locally so the list stays stable across a
  /// re-ping (open / pull-to-refresh) regardless of how the AsyncValue reports
  /// the in-flight reload. `null` only before the very first settle.
  CountryProbeResult? _lastResult;

  /// Pull-to-refresh: re-fetch the profile config AND re-run the probe (fresh
  /// ping), awaiting the settle so the [RefreshIndicator] spinner stays until
  /// measurements are in. Invalidating the config too makes the error state's
  /// retry actually re-attempt the load. Errors are swallowed so the spinner
  /// resolves (the state itself re-renders from the async values).
  Future<void> _refresh() async {
    ref.invalidate(modeProfileDataProvider(widget.profileId));
    ref.invalidate(countryProbeProvider(widget.profileId));
    try {
      await ref.read(countryProbeProvider(widget.profileId).future);
    } catch (_) {
      // Surfaced through the rebuilt async value → error/unmeasured state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider);
    final dataAsync = ref.watch(modeProfileDataProvider(widget.profileId));
    // Liveness probe (pre-warmed on the modes tab). During a re-ping (open /
    // pull-to-refresh) the AsyncValue RETAINS the previous alive set, so the
    // list stays stable while badges refresh — only `null` means «never settled».
    final probeAsync = ref.watch(countryProbeProvider(widget.profileId));

    if (profile == null) {
      return NullStatus(label: appLocalizations.nullProfileDesc);
    }

    // Auto-ping on open: force ONE fresh measurement when the picker opens (the
    // kept-alive provider would otherwise serve the pre-warm result untouched).
    if (!_autoPinged) {
      _autoPinged = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(countryProbeProvider(widget.profileId));
      });
    }

    final activeCountry = profile.staticCountry;

    Widget buildRow(CountryPickerEntry entry) => ListItem(
          // No reserved leading checkmark column: it skewed the row inset
          // (~48px left vs 16px right). The active row is marked by the primary
          // color + weight instead, keeping insets symmetric.
          title: EmojiText(
            // «<flag>  <name>»: a country/server row keeps its real flag.
            '${entry.flag}  ${entry.label}',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: entry.key == activeCountry
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: entry.key == activeCountry ? colorScheme.primary : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _CountryAvailabilityBadge(proxyName: entry.proxyName),
          onTap: () {
            widget.onApply(entry.key);
            Navigator.of(context).pop();
          },
        );

    // A centered, pull-to-refresh-able message panel (error / empty-countries).
    Widget centeredRefresh(String message) => RefreshIndicator(
          onRefresh: _refresh,
          color: colorScheme.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: 240,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    // A staggered, pull-to-refresh-able list of country rows, with an optional
    // small non-blocking [notice] pinned at the top (unmeasured / unreachable
    // states). The rows stay tappable/appliable regardless of the notice — the
    // apply path never depends on the probe.
    Widget buildList(List<CountryPickerEntry> entries, {String? notice}) =>
        RefreshIndicator(
          onRefresh: _refresh,
          color: colorScheme.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (notice != null) _InlineNotice(message: notice),
                for (final (i, entry) in entries.indexed)
                  _RowReveal(
                    key: ValueKey(entry.key),
                    delay: Duration(milliseconds: i.clamp(0, 7) * 40),
                    child: buildRow(entry),
                  ),
              ],
            ),
          ),
        );

    // Cache the last SETTLED probe result locally so a re-ping (open /
    // pull-to-refresh) never flickers the list to skeleton — the pure resolver
    // reads the cache, refreshing only the badges. `null` only before the very
    // first settle. Canonical «load → stable list».
    final settled = probeAsync.valueOrNull;
    if (settled != null) _lastResult = settled;

    // The honesty matrix lives in [resolveCountryPickerState] (pure + tested).
    final state = resolveCountryPickerState(
      data: dataAsync,
      probe: probeAsync,
      cachedProbe: _lastResult,
      activeCountry: activeCountry,
    );

    final Widget child;
    final String stateKey;
    switch (state.status) {
      case CountryPickerStatus.skeleton:
        stateKey = 'skeleton';
        child = const _CountrySkeletonList();
      case CountryPickerStatus.error:
        stateKey = 'error';
        // A real load failure — a mapped message when we recognise it, else the
        // generic «couldn't load, pull to retry» copy. NEVER «no profile».
        final mapped = ErrorMapper.mapError(dataAsync.error?.toString() ?? '');
        child = centeredRefresh(mapped ?? appLocalizations.countriesLoadFailed);
      case CountryPickerStatus.emptyCountries:
        // The ONLY honest «обновите подписку» — the subscription truly has none.
        stateKey = 'empty';
        child = centeredRefresh(appLocalizations.countriesNotDetected);
      case CountryPickerStatus.unmeasured:
        // Countries exist but liveness is unknown: show them ALL, with a small
        // notice; the user can still tap and apply any country.
        stateKey = 'unmeasured';
        child = buildList(
          state.entries,
          notice: appLocalizations.countriesAvailabilityUnknown,
        );
      case CountryPickerStatus.allUnreachable:
        // Probe ran, nothing answered (likely no internet): show them ALL with
        // an honest connectivity hint rather than hiding every country.
        stateKey = 'allUnreachable';
        child = buildList(
          state.entries,
          notice: appLocalizations.countriesAllUnreachable,
        );
      case CountryPickerStatus.list:
        // Measured with live servers: the filtered list (decoys/SOS hidden).
        stateKey = 'list';
        child = buildList(state.entries);
    }

    return AnimatedSwitcher(
      duration: Lumina.luminaDuration,
      switchInCurve: Lumina.luminaCurve,
      switchOutCurve: Lumina.luminaCurve,
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}

/// A small, non-blocking advisory pinned above the country list (unmeasured /
/// unreachable states). Deliberately quiet — a left-aligned [bodySmall] line in
/// [onSurfaceVariant] on the existing surface, no new visual language, no glass
/// panel — so it informs without stealing focus from the tappable rows below.
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          message,
          style: context.textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Premium entrance for a country-picker row: it FADES in while gently RISING
/// into place (slide-up), on the Lumina motion tokens. The settled list mounts
/// all at once, and a small per-index [delay] staggers the rows into a cascade.
/// The slide is paint-only (no layout reflow), so the sheet stays put while rows
/// settle in. Keyed by entry so an already-shown row never re-animates on
/// rebuild.
class _RowReveal extends StatefulWidget {
  const _RowReveal(
      {super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_RowReveal> createState() => _RowRevealState();
}

class _RowRevealState extends State<_RowReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Lumina.luminaDuration,
  );
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Lumina.luminaCurve);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

/// Availability delay badge for a country row. Reuses the EXACT mechanism the
/// proxy-group rows use ([_ProxySelectorRow] / [_RulesGroupCard]):
/// [getDelayProvider] for the country's leaf node (default test URL),
/// [utils.delayBadgeLabel] for the ms label and [utils.getDelayColor] for the
/// tint. Renders nothing (a fixed-width spacer for alignment) until a delay
/// sample exists.
class _CountryAvailabilityBadge extends ConsumerWidget {
  const _CountryAvailabilityBadge({required this.proxyName});

  final String proxyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = ref.watch(getDelayProvider(proxyName: proxyName));
    final label = utils.delayBadgeLabel(delay);

    final Widget content;
    if (label == null) {
      // Probe still in flight (delay null = not measured yet, 0 = testing):
      // the latency «loads INSIDE the card» via a Lumina glass shimmer pill —
      // never a blocking overlay. The row itself is already visible.
      content = const _ShimmerBadge(key: ValueKey('loading'));
    } else {
      final delayColor = utils.getDelayColor(delay);
      content = Container(
        key: ValueKey(label),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: delayColor?.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: context.textTheme.labelSmall?.copyWith(
            color: delayColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Smooth crossfade between the loading spinner and the resolved latency
    // badge (Lumina motion tokens) — the «smooth loading inside the card».
    return AnimatedSwitcher(
      duration: Lumina.luminaDuration,
      switchInCurve: Lumina.luminaCurve,
      switchOutCurve: Lumina.luminaCurve,
      child: content,
    );
  }
}

/// Lumina-styled loading skeleton for a latency badge: a dark glass pill with a
/// soft accent-glow band sweeping across it (the canonical sliding-LinearGradient
/// shimmer technique, driven on a repeating controller). Sized to match the
/// resolved latency pill so the row doesn't jump when it crossfades in.
class _ShimmerBadge extends StatefulWidget {
  const _ShimmerBadge({super.key});

  @override
  State<_ShimmerBadge> createState() => _ShimmerBadgeState();
}

class _ShimmerBadgeState extends State<_ShimmerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 22,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: _shimmerGradient(_controller.value),
            ),
          ),
        ),
      );
}

/// The Lumina shimmer fill: a dark-glass base with a soft accent-glow band that
/// [_SlideGradient] sweeps across as [t] runs 0→1. Shared by the latency-badge
/// shimmer and the country-list skeleton so they pulse identically.
LinearGradient _shimmerGradient(double t) => LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Lumina.surface3,
        Lumina.surface5,
        Color.lerp(Lumina.surface5, Lumina.glowAccent, 0.45)!,
        Lumina.surface5,
        Lumina.surface3,
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      transform: _SlideGradient(t),
    );

/// Translates a gradient horizontally by [t] (0→1 sweeps the highlight band
/// from off-left to off-right across the painted bounds), turning a fixed
/// multi-stop gradient into a moving shimmer.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues((t * 2 - 1) * bounds.width, 0, 0);
}

/// Lumina loading skeleton for the country picker: a column of placeholder rows
/// (shimmer flag + name bar + latency pill) on a single shared controller, so
/// the user sees a premium loading state — never junk that pops in and out —
/// while the liveness probe resolves. No real (possibly-dead) node names are
/// rendered here.
class _CountrySkeletonList extends StatefulWidget {
  const _CountrySkeletonList();

  /// Placeholder row count — a typical short picker height; the sheet is
  /// scroll-capped anyway.
  static const int _rowCount = 7;

  @override
  State<_CountrySkeletonList> createState() => _CountrySkeletonListState();
}

class _CountrySkeletonListState extends State<_CountrySkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _bar(double t,
          {double? width, required double height, double radius = 6}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: _shimmerGradient(t),
        ),
      );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _CountrySkeletonList._rowCount; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        _bar(t, width: 30, height: 22, radius: 6),
                        const SizedBox(width: 16),
                        Expanded(child: _bar(t, height: 16)),
                        const SizedBox(width: 16),
                        _bar(t, width: 48, height: 22, radius: 8),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
