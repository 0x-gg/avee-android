import 'package:avee/enum/enum.dart';
import 'package:avee/common/common.dart';
import 'package:avee/pages/home/connect_circle.dart';
import 'package:avee/pages/home/home_overlays.dart';
import 'package:avee/pages/home/navigation_bar.dart';
import 'package:avee/providers/providers.dart';
import 'package:avee/state.dart';
import 'package:avee/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/avee_account.dart';
import '../../services/avee_billing.dart';
import '../views/avee_account_sheet.dart';
import 'avee_mobile_shell.dart';

export 'package:avee/pages/home/connect_circle.dart' show connectButtonCenter;

typedef OnSelected = void Function(int index);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => HomeBackScope(
        child: Consumer(
          builder: (_, ref, child) {
            final state = ref.watch(homeStateProvider);
            final viewMode = state.viewMode;
            // Android always uses the AVEE mobile shell. Desktop keeps its
            // own navigation surface.
            if (viewMode == ViewMode.mobile ||
                defaultTargetPlatform == TargetPlatform.android) {
              return const AveeMobileShell();
            }
            final navigationItems = state.navigationItems;
            final pageLabel = state.pageLabel;
            final index = navigationItems.lastIndexWhere(
              (element) => element.label == pageLabel,
            );
            final currentIndex = index == -1 ? 0 : index;
            final navigationBar = CommonNavigationBar(
              viewMode: viewMode,
              navigationItems: navigationItems,
              currentIndex: currentIndex,
            );
            final sideNavigationBar =
                viewMode != ViewMode.mobile ? navigationBar : null;
            return CommonScaffold(
              key: globalState.homeScaffoldKey,
              title: viewMode == ViewMode.mobile ||
                      pageLabel == PageLabel.dashboard
                  ? ''
                  : navigationLabel(pageLabel),
              sideNavigationBar: sideNavigationBar,
              body: child!,
            );
          },
          child: const _HomePageView(),
        ),
      );
}

class _HomePageView extends ConsumerStatefulWidget {
  const _HomePageView();

  @override
  ConsumerState<_HomePageView> createState() => _HomePageViewState();
}

class _HomePageViewState extends ConsumerState<_HomePageView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _pageIndex,
      keepPage: true,
    );
    ref
      ..listenManual(currentPageLabelProvider, (prev, next) {
        if (prev != next) {
          _toPage(next);
        }
      })
      ..listenManual(currentNavigationsStateProvider, (prev, next) {
        if (prev?.value != next.value) {
          _updatePageController();
        }
      });
  }

  int get _pageIndex {
    final navigationItems = ref.read(currentNavigationsStateProvider).value;
    final index = navigationItems.indexWhere(
      (item) => item.label == globalState.appState.pageLabel,
    );
    return index == -1 ? 0 : index;
  }

  Future<void> _toPage(
    PageLabel pageLabel, [
    bool ignoreAnimateTo = false,
  ]) async {
    if (!mounted) {
      return;
    }
    final navigationItems = ref.read(currentNavigationsStateProvider).value;
    final index = navigationItems.indexWhere((item) => item.label == pageLabel);
    if (index == -1) {
      return;
    }
    final isAnimateToPage = ref.read(appSettingProvider).isAnimateToPage;
    final isMobile = ref.read(isMobileViewProvider);
    if (isAnimateToPage && isMobile && !ignoreAnimateTo) {
      await _pageController.animateToPage(
        index,
        duration: kTabScrollDuration,
        curve: Curves.easeOut,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  void _updatePageController() {
    final pageLabel = globalState.appState.pageLabel;
    final navigationItems = ref.read(currentNavigationsStateProvider).value;
    final hasPage = navigationItems.any((item) => item.label == pageLabel);
    if (!hasPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        globalState.appController.toPage(PageLabel.dashboard);
      });
      return;
    }
    _toPage(pageLabel, true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigationItems = ref.watch(currentNavigationsStateProvider).value;
    final isMobile = ref.watch(isMobileViewProvider);
    final currentLabel = ref.watch(currentPageLabelProvider);
    // Defensive HomePage-level guard: regardless of what the provider
    // returns, when there is no profile/subscription we collapse the
    // visible navigation to Dashboard only. This is the second line of
    // defense behind `currentNavigationsState` so the swipe, indicator
    // and PageView item count cannot expose a Tools page that the user
    // hasn't unlocked yet.
    final hasProfiles = ref.watch(
      profilesProvider.select((profiles) => profiles.isNotEmpty),
    );
    final effectiveNavigationItems = hasProfiles
        ? navigationItems
        : navigationItems
            .where((item) => item.label == PageLabel.dashboard)
            .toList();
    final currentIndex = effectiveNavigationItems.indexWhere(
      (item) => item.label == currentLabel,
    );
    final canSwipe = isMobile && effectiveNavigationItems.length > 1;
    final connectSize = isMobile ? connectSizeFor(context) : 0.0;
    final pageView = PageView.builder(
      controller: _pageController,
      // Mobile: horizontal swipe between dashboard ↔ tools (settings).
      // Non-mobile and no-profile single-page state: swipe stays disabled.
      physics: canSwipe
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: effectiveNavigationItems.length,
      onPageChanged: !canSwipe
          ? null
          : (index) {
              if (index < 0 || index >= effectiveNavigationItems.length) {
                return;
              }
              final newLabel = effectiveNavigationItems[index].label;
              // Guard against the swipe → toPage → animate → onPageChanged
              // → toPage feedback loop: only push the new label up if it
              // actually differs from what the provider currently holds.
              final currentLabel = ref.read(currentPageLabelProvider);
              if (currentLabel == newLabel) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (ref.read(currentPageLabelProvider) == newLabel) return;
                globalState.appController.toPage(newLabel);
              });
            },
      itemBuilder: (_, index) {
        final navigationItem = effectiveNavigationItems[index];
        final page = KeepScope(
          keep: navigationItem.keep,
          key: Key(navigationItem.label.name),
          child: navigationItem.view,
        );
        // The connect/add button belongs to the Dashboard page itself so
        // PageView physics slides it off-screen with the rest of Dashboard
        // when the user swipes to Tools. The tab indicator is rendered
        // outside the PageView (see below) so it stays visible across
        // pages.
        if (isMobile && navigationItem.label == PageLabel.dashboard) {
          return Stack(
            children: [
              page,
              // First-run guidance under the lens. Kept mounted (opacity-driven,
              // not an `if` gate) so it FADES out when the first profile lands
              // instead of popping; `visible` mirrors the exact empty-state
              // condition (`!hasProfiles`) that makes StartButton show the "+"
              // add glyph. Painted before the button so the lens sits on top.
              MobileEmptyGuidanceOverlay(
                buttonSize: connectSize,
                visible: !hasProfiles,
              ),
              MobileConnectButtonOverlay(buttonSize: connectSize),
            ],
          );
        }
        return page;
      },
    );

    if (!isMobile) {
      return pageView;
    }

    return Stack(
      children: [
        pageView,
        const Positioned(
          top: 8,
          left: 16,
          right: 16,
          child: AveeAccountBanner(),
        ),
        if (!hasProfiles)
          Positioned(
            top: 92,
            left: 16,
            right: 16,
            bottom: 142,
            child: AveeWelcomeCard(
              onAccount: () => AveeAccountSheet.show(context),
              onTrial: () async {
                if (aveeAccountState.session == null) {
                  await AveeAccountSheet.show(context);
                } else {
                  await aveeAccountState.startTrial();
                }
              },
            ),
          ),
        MobileIndicatorOverlay(
          buttonSize: connectSize,
          currentIndex: currentIndex == -1 ? 0 : currentIndex,
          itemCount: effectiveNavigationItems.length,
        ),
      ],
    );
  }
}

class AveeWelcomeCard extends StatelessWidget {
  const AveeWelcomeCard({
    required this.onAccount,
    required this.onTrial,
    super.key,
  });

  final VoidCallback onAccount;
  final Future<void> Function() onTrial;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) {
          final state = aveeAccountState;
          final accent = Theme.of(context).colorScheme.primary;
          final surface = Theme.of(context).colorScheme.surface;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: accent.withValues(alpha: .24)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(accent.withValues(alpha: .10), surface),
                  surface.withValues(alpha: .92),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .08),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.shield_outlined, color: accent),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'AVEE VPN',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.4,
                            ),
                          ),
                        ),
                        Icon(Icons.auto_awesome, color: accent),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      state.session == null
                          ? 'Приватное подключение в одно касание'
                          : 'Ваш доступ готов к активации',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.session == null
                          ? 'Создайте AVEE-аккаунт и получите 1 ГБ пробного доступа на 3 дня.'
                          : 'Активируйте пробный период, выберите локацию и подключитесь через защищённый туннель.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        _AveeFeatureChip(Icons.bolt, 'Быстрый старт'),
                        _AveeFeatureChip(
                            Icons.visibility_off_outlined, 'Без журналов'),
                        _AveeFeatureChip(Icons.public, 'Умные локации'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _AveeRouteSignal(accent: accent),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: state.loading
                            ? null
                            : (state.session == null ? onAccount : onTrial),
                        icon: Icon(state.session == null
                            ? Icons.person_add_alt_1
                            : Icons.play_arrow_rounded),
                        label: Text(state.session == null
                            ? 'Создать аккаунт'
                            : 'Активировать 1 ГБ пробного доступа'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'P2P и торрент-трафик запрещены',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _AveeRouteSignal extends StatelessWidget {
  const _AveeRouteSignal({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _AveeRouteNode(label: 'Устройство', accent: accent),
          Expanded(child: _AveeRouteLine(accent: accent)),
          _AveeRouteNode(label: 'AVEE', accent: accent, active: true),
          Expanded(child: _AveeRouteLine(accent: accent)),
          _AveeRouteNode(label: 'Интернет', accent: accent),
        ],
      );
}

class _AveeRouteNode extends StatelessWidget {
  const _AveeRouteNode({
    required this.label,
    required this.accent,
    this.active = false,
  });

  final String label;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            width: active ? 12 : 9,
            height: active ? 12 : 9,
            decoration: BoxDecoration(
              color: active ? accent : accent.withValues(alpha: .45),
              shape: BoxShape.circle,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: .45),
                        blurRadius: 10,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _AveeRouteLine extends StatelessWidget {
  const _AveeRouteLine({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: CustomPaint(
          painter: _AveeRouteLinePainter(accent),
          size: const Size(double.infinity, 8),
        ),
      );
}

class _AveeRouteLinePainter extends CustomPainter {
  const _AveeRouteLinePainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: .35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width * .42, size.height / 2)
      ..lineTo(size.width * .55, 1)
      ..lineTo(size.width, 1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AveeRouteLinePainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class _AveeFeatureChip extends StatelessWidget {
  const _AveeFeatureChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 15),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );
}

class AveeAccountBanner extends StatelessWidget {
  const AveeAccountBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) {
          final state = aveeAccountState;
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.session == null
                              ? 'AVEE: подключите аккаунт для управляемого доступа'
                              : state.access
                                  ? 'AVEE: доступ активен'
                                  : 'AVEE: активируйте пробный доступ',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (state.antiAbuseNotice != null)
                          Text(
                            state.antiAbuseNotice!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (state.loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: state.session == null
                              ? () => AveeAccountSheet.show(context)
                              : state.access
                                  ? () => _refreshManagedProfile(context)
                                  : aveeAccountState.startTrial,
                          child: Text(
                            state.session == null
                                ? 'Аккаунт'
                                : state.access
                                    ? 'Обновить профиль'
                                    : 'Пробный период',
                          ),
                        ),
                        if (state.session != null)
                          TextButton(
                            onPressed: () => AveePaywall.show(context),
                            child: const Text('Тарифы'),
                          ),
                        if (state.session != null)
                          TextButton(
                            onPressed: aveeBillingService.restore,
                            child: const Text('Восстановить покупки'),
                          ),
                        if (state.session != null)
                          TextButton(
                            onPressed: () => _confirmDeletion(context),
                            child: const Text('Удалить аккаунт'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _confirmDeletion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
            'Сессии и устройства будут отозваны, доступ Remnawave отключён. Google Play подписка автоматически не отменяется.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await globalState.appController.updateStatus(false);
      final deleted = await aveeAccountState.deleteAccount();
      if (deleted) {
        await globalState.appController.removeManagedProfile();
      }
    }
  }

  Future<void> _refreshManagedProfile(BuildContext context) async {
    final yaml = await aveeAccountState.refreshManagedProfile();
    if (yaml == null) return;
    try {
      await globalState.appController.installManagedProfile(yaml);
    } catch (error) {
      commonPrint.log('[avee] managed profile install failed: $error');
      if (context.mounted) {
        globalState.showNotifier('Не удалось применить управляемый профиль');
      }
    }
  }
}
