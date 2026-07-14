import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropweb/state.dart';

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
  final recoveryController = TextEditingController();

  @override
  void dispose() {
    accountController.dispose();
    recoveryController.dispose();
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
                      : 'Аккаунт ${state.session!.accountNumber}'),
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
          onPressed: aveeAccountState.loading ? null : _recover,
          icon: const Icon(Icons.login),
          label: const Text('Восстановить аккаунт'),
        ),
        if (aveeAccountState.recoveryCode != null) _recoveryCard(),
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

  Widget _recoveryCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Сохраните код восстановления — он показывается один раз.'),
              SelectableText(aveeAccountState.recoveryCode!),
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(
                    text: aveeAccountState.recoveryCode!)),
                icon: const Icon(Icons.copy),
                label: const Text('Скопировать код'),
              ),
            ],
          ),
        ),
      );

  Future<void> _recover() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Восстановить аккаунт'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: accountController,
            decoration: const InputDecoration(labelText: 'Номер аккаунта'),
            textCapitalization: TextCapitalization.characters,
          ),
          TextField(
            controller: recoveryController,
            decoration: const InputDecoration(labelText: 'Код восстановления'),
            obscureText: true,
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              await aveeAccountState.recoverAccount(
                accountNumber: accountController.text,
                recoveryCode: recoveryController.text,
              );
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
