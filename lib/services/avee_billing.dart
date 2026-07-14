import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'avee_account.dart';
import 'avee_play_country.dart';

class AveeBillingOffers {
  const AveeBillingOffers({required this.google, required this.platega});

  final ProductDetailsResponse google;
  final List<Map<String, dynamic>> platega;
}

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

  Future<AveeBillingOffers> offers() async {
    final catalog = await account.billingMethods();
    final plans = (catalog['plans'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final planCodes =
        plans.map((plan) => plan['code']).whereType<String>().toSet();
    ProductDetailsResponse google = ProductDetailsResponse(
      productDetails: <ProductDetails>[],
      notFoundIDs: <String>[],
      error: null,
    );
    if (await store.isAvailable() && planCodes.isNotEmpty) {
      try {
        google = await products(planCodes);
      } catch (_) {
        // A Play catalog outage must not hide a backend-enabled SBP offer.
      }
    }
    final country = await aveePlayCountryService.resolve();
    final methods = (catalog['methods'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((method) => method['provider'])
        .whereType<String>()
        .toSet();
    final platega = country.isRussia && methods.contains('PLATEGA_SBP')
        ? plans
            .where((plan) => plan['currency'] == 'RUB')
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return AveeBillingOffers(google: google, platega: platega);
  }

  Future<bool> buyPlatega(String planCode) async {
    final country = await aveePlayCountryService.resolve();
    if (!country.isRussia) return false;
    final catalog = await account.billingMethods();
    final methods = (catalog['methods'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((method) => method['provider'])
        .whereType<String>()
        .toSet();
    if (!methods.contains('PLATEGA_SBP')) return false;
    final order = await account.createPlategaOrder(planCode: planCode);
    final checkout = order['checkoutUrl'] as String?;
    final uri = checkout == null ? null : Uri.tryParse(checkout);
    if (uri == null || uri.scheme != 'https') {
      throw StateError('Backend returned an invalid payment URL');
    }
    final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (launched) await account.refresh();
    return launched;
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
          child: FutureBuilder<AveeBillingOffers>(
            future: aveeBillingService.offers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || snapshot.data == null) {
                return const Text('Тарифы временно недоступны');
              }
              final products = snapshot.data!.google.productDetails;
              final platega = snapshot.data!.platega;
              if (products.isEmpty && platega.isEmpty) {
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
                  for (final plan in platega)
                    OutlinedButton(
                      onPressed: () async {
                        final opened = await aveeBillingService
                            .buyPlatega(plan['code'] as String);
                        if (opened && context.mounted) Navigator.pop(context);
                      },
                      child: Text(
                          'СБП · ${plan['name'] ?? plan['code']} — ${plan['priceMinor'] ~/ 100} ₽'),
                    ),
                ],
              );
            },
          ),
        ),
      );
}
