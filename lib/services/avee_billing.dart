import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'avee_account.dart';

/// Google Play purchase boundary. Store state never grants access locally;
/// every token is sent to AVEE Backend for verification before refreshing the
/// account state.
class AveeBillingService {
  AveeBillingService({AveeAccountState? account})
      : account = account ?? aveeAccountState;

  final AveeAccountState account;
  final InAppPurchase store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<bool> initialize() async {
    if (!await store.isAvailable()) return false;
    _subscription ??= store.purchaseStream.listen(_handlePurchases);
    return true;
  }

  Future<ProductDetailsResponse> products(Set<String> productIds) =>
      store.queryProductDetails(productIds);

  Future<ProductDetailsResponse> productsFromBackend() async {
    final catalog = await account.billingMethods();
    final plans = (catalog['plans'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((plan) => plan['code'])
        .whereType<String>()
        .toSet();
    return products(plans);
  }

  Future<bool> buy(ProductDetails product) => store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );

  Future<void> restore() async {
    await initialize();
    await store.restorePurchases();
    await account.restoreGooglePurchases();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final token = purchase.verificationData.serverVerificationData;
        if (token.isNotEmpty) {
          await account.completeGooglePurchase(
            productId: purchase.productID,
            purchaseToken: token,
          );
        }
      }
      if (purchase.pendingCompletePurchase) {
        await store.completePurchase(purchase);
      }
    }
  }
}

final aveeBillingService = AveeBillingService();

class AveePaywall extends StatelessWidget {
  const AveePaywall({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const AveePaywall(),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<ProductDetailsResponse>(
            future: aveeBillingService.productsFromBackend(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || snapshot.data == null) {
                return const Text('Тарифы временно недоступны');
              }
              final products = snapshot.data!.productDetails;
              if (products.isEmpty) {
                return const Text('Тарифы пока не настроены');
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Выберите тариф',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  for (final product in products)
                    FilledButton(
                      onPressed: () async {
                        await aveeBillingService.buy(product);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text('${product.title} — ${product.price}'),
                    ),
                ],
              );
            },
          ),
        ),
      );
}
