import 'package:flutter/material.dart';
import 'package:avee/state.dart';

import '../services/avee_account.dart';
import '../services/avee_billing.dart';

class AveeAccountSheet extends StatefulWidget {
  const AveeAccountSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const AveeAccountSheet(),
      );

  @override
  State<AveeAccountSheet> createState() => _AveeAccountSheetState();
}

class _AveeAccountSheetState extends State<AveeAccountSheet> {
  final accountController = TextEditingController();

  @override
  void dispose() {
    accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aveeAccountState,
        builder: (context, _) {
          final state = aveeAccountState;
          final remaining = state.trafficRemainingBytes;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('AVEE доступ',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(state.session == null
                      ? 'Создайте аккаунт, чтобы получить управляемый профиль VPN.'
                      : 'AVEE ID ${state.session!.accountId}'),
                  if (state.error != null) ...[
                    const SizedBox(height: 10),
                    Text(state.error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 18),
                  if (state.session == null) ..._loggedOut(context),
                  if (state.session != null) ..._loggedIn(context, remaining),
                  if (state.loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          );
        },
      );

  List<Widget> _loggedOut(BuildContext context) => [
        FilledButton.icon(
          onPressed: aveeAccountState.loading
              ? null
              : () => aveeAccountState.createAccount(),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Создать аккаунт и получить 1 ГБ'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: aveeAccountState.loading ? null : _login,
          icon: const Icon(Icons.login),
          label: const Text('Войти по AVEE ID'),
        ),
      ];

  List<Widget> _loggedIn(BuildContext context, int? remaining) => [
        if (aveeAccountState.access) ...[
          Text(remaining == null
              ? 'Доступ активен'
              : 'Осталось пробного трафика: ${_formatBytes(remaining)}'),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () async {
              final yaml = await aveeAccountState.refreshManagedProfile();
              if (yaml != null) {
                await globalState.appController.installManagedProfile(yaml);
              }
            },
            icon: const Icon(Icons.download_done),
            label: const Text('Получить управляемый профиль'),
          ),
        ] else ...[
          Text(aveeAccountState.accessReason == 'TRIAL_TRAFFIC_EXHAUSTED'
              ? 'Пробный лимит 1 ГБ исчерпан.'
              : 'Пробный доступ ещё не активирован.'),
          const SizedBox(height: 10),
          if (aveeAccountState.accessReason != 'TRIAL_TRAFFIC_EXHAUSTED')
            FilledButton.icon(
              onPressed: () => aveeAccountState.startTrial(),
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Активировать 1 ГБ пробного доступа'),
            ),
          OutlinedButton(
            onPressed: () => AveePaywall.show(context),
            child: const Text('Выбрать тариф и оплатить'),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => aveeBillingService.restore(),
          child: const Text('Восстановить покупки'),
        ),
      ];

  Future<void> _login() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Войти по AVEE ID'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: accountController,
            decoration: const InputDecoration(labelText: 'AVEE ID'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              await aveeAccountState.loginAccount(accountId: accountController.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Войти'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} МБ';
  }
}
