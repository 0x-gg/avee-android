import 'package:dropweb/common/common.dart';
import 'package:dropweb/common/smart_pool_patch.dart';
import 'package:dropweb/models/models.dart' hide Action;
import 'package:dropweb/providers/providers.dart';
import 'package:dropweb/state.dart';
import 'package:dropweb/views/proxies/common.dart';
import 'package:dropweb/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

Future<void> _pingAllProxies(WidgetRef ref) async {
  // Use the RAW groups (not currentGroupsState, which drops hidden:true groups)
  // so the disconeko 🧠 Smart pool is still delay-tested — otherwise the
  // 📶 First Available row (now = 🧠 Smart) loses its availability badge.
  final groups = ref.read(groupsProvider);
  final allProxies = <Proxy>[];
  final seenNames = <String>{};
  for (final group in groups) {
    for (final proxy in group.all) {
      if (!seenNames.contains(proxy.name)) {
        seenNames.add(proxy.name);
        allProxies.add(proxy);
      }
    }
  }
  if (allProxies.isNotEmpty) await delayTest(allProxies, null);
}

// ── Proxies view (shared across all 3 modes) ─────────────────────────────

class RulesProxiesView extends ConsumerStatefulWidget {
  const RulesProxiesView();

  @override
  ConsumerState<RulesProxiesView> createState() => _RulesProxiesViewState();
}

class _RulesProxiesViewState extends ConsumerState<RulesProxiesView> {
  bool _pingTriggered = false;

  @override
  Widget build(BuildContext context) {
    // Filter the disconeko 🧠 Smart pool out of the LIST (UI-only, by name) so
    // it is never a standalone selectable row — while it stays a real,
    // health-checked group in the config so 📶 First Available (which
    // references it) still auto-selects and shows its availability badge.
    final groups = ref
        .watch(currentGroupsStateProvider)
        .value
        .where((g) => g.name != disconekoSmartGroupName)
        .toList();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (groups.isEmpty) {
      return NullStatus(label: appLocalizations.nullProfileDesc);
    }

    // Populate availability badges on open (incl. the 🧠 Smart pool that backs
    // 📶 First Available), once per open — matching the old behavior where
    // badges showed immediately. Pull-to-refresh re-tests.
    if (!_pingTriggered) {
      _pingTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pingAllProxies(ref));
    }

    return RefreshIndicator(
      onRefresh: () => _pingAllProxies(ref),
      color: colorScheme.primary,
      child: ListView.builder(
        // shrinkWrap so the sheet hugs its content (few groups → short sheet,
        // anchored to the bottom); the parent ConstrainedBox caps + scrolls.
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: groups.length,
        itemBuilder: (_, index) => _RulesGroupCard(
            key: ValueKey(groups[index].name),
            group: groups[index],
            isDark: isDark),
      ),
    );
  }
}

class _RulesGroupCard extends ConsumerWidget {
  final Group group;
  final bool isDark;
  const _RulesGroupCard({super.key, required this.group, required this.isDark});

  void _openSelector(BuildContext context) {
    showSheet(
      context: context,
      props: const SheetProps(isScrollControlled: true),
      builder: (_, type) => AdaptiveSheetScaffold(
        type: type,
        title: group.name,
        body: _ProxySelectorSheet(group: group),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyName = ref.watch(getProxyNameProvider(group.name));
    final selectedName =
        proxyName != null && proxyName.isNotEmpty ? proxyName : group.realNow;
    final selectedProxy =
        group.all.where((p) => p.name == selectedName).firstOrNull;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Lumina.radiusLg),
        child: InkWell(
          onTap: () => _openSelector(context),
          borderRadius: BorderRadius.circular(Lumina.radiusLg),
          splashColor: colorScheme.primary.withValues(alpha: 0.08),
          highlightColor: colorScheme.primary.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Lumina.radiusLg),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                if (group.icon.isNotEmpty && !group.icon.startsWith('http'))
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: EmojiText(
                      group.icon,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EmojiText(
                        group.name,
                        style: context.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      EmojiText(
                        selectedProxy != null
                            ? '${selectedProxy.type} · $selectedName'
                            : selectedName.isNotEmpty
                                ? selectedName
                                : '...',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selectedName.isNotEmpty)
                  Consumer(
                    builder: (context, ref, _) {
                      final delay = ref.watch(getDelayProvider(
                        proxyName: selectedName,
                        testUrl: group.testUrl,
                      ));
                      final label = utils.delayBadgeLabel(delay);
                      if (label == null) {
                        return const SizedBox(width: 48);
                      }
                      final delayColor = utils.getDelayColor(delay);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
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
                    },
                  ),
                const SizedBox(width: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: 14,
                    color: isDark
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Proxy selector sheet ──────────────────────────────────────────────────

class _ProxySelectorSheet extends ConsumerWidget {
  final Group group;
  const _ProxySelectorSheet({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final proxyName = ref.watch(getProxyNameProvider(group.name));
    final selectedName =
        proxyName != null && proxyName.isNotEmpty ? proxyName : group.realNow;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: group.all.length,
        itemBuilder: (context, index) {
          final proxy = group.all[index];
          final isSelected = proxy.name == selectedName;
          return _ProxySelectorRow(
            proxy: proxy,
            testUrl: group.testUrl,
            isSelected: isSelected,
            isDark: isDark,
            onTap: () {
              final appController = globalState.appController;
              appController.updateCurrentSelectedMap(
                group.name,
                proxy.name,
              );
              appController.changeProxyDebounce(
                group.name,
                proxy.name,
              );
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }
}

class _ProxySelectorRow extends ConsumerWidget {
  final Proxy proxy;
  final String? testUrl;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ProxySelectorRow({
    required this.proxy,
    required this.testUrl,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final delay = ref.watch(getDelayProvider(
      proxyName: proxy.name,
      testUrl: testUrl,
    ));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: isDark ? 0.10 : 0.08)
            : isDark
                ? Colors.white.withValues(alpha: 0.04)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Lumina.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Lumina.radiusLg),
          splashColor: colorScheme.primary.withValues(alpha: 0.08),
          highlightColor: colorScheme.primary.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Lumina.radiusLg),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.35)
                    : isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  const SizedBox(width: 30),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EmojiText(
                        proxy.name,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? colorScheme.primary : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        proxy.type,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (utils.delayBadgeLabel(delay) != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          utils.getDelayColor(delay)?.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      utils.delayBadgeLabel(delay)!,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: utils.getDelayColor(delay),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
