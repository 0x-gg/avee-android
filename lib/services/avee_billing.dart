import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'avee_account.dart';
import '../ui/avee_design.dart';

class AveeBillingOffers {
  const AveeBillingOffers({required this.google, required this.plans});

  final ProductDetailsResponse google;
  final List<Map<String, dynamic>> plans;
}

Map<String, dynamic>? _planForProduct(
  List<Map<String, dynamic>> plans,
  ProductDetails product,
) {
  for (final plan in plans) {
    if (plan['code']?.toString() == product.id) return plan;
  }
  return null;
}

String _planTrafficLabel(dynamic raw) {
  final bytes = int.tryParse(raw?.toString() ?? '');
  if (bytes == null) return 'Unlimited data';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  // Plan limits are configured in the billing catalog using decimal
  // marketing units, so a configured 1 TB plan should be shown as 1.0 TB
  // instead of 931 GB.
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final formatted = value >= 10 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[unit]} data';
}

String _planDurationLabel(dynamic raw) {
  final days = int.tryParse(raw?.toString() ?? '');
  if (days == null || days <= 0) return 'Flexible duration';
  if (days % 30 == 0) {
    final months = days ~/ 30;
    return '$months ${months == 1 ? 'month' : 'months'}';
  }
  return '$days ${days == 1 ? 'day' : 'days'}';
}

String _planDevicesLabel(dynamic raw) {
  final devices = int.tryParse(raw?.toString() ?? '');
  if (devices == null || devices <= 0) return 'Device limit set by plan';
  return '$devices ${devices == 1 ? 'device' : 'devices'}';
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
        // A Play catalog outage is reported by the paywall.
      }
    }
    return AveeBillingOffers(google: google, plans: plans);
  }

  Future<bool> buy(ProductDetails product) => store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );

  Future<bool> restore() async {
    if (account.session == null) return false;
    if (!await initialize()) return false;
    await store.restorePurchases();
    await account.restoreGooglePurchases();
    return account.access;
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
        var verified = false;
        if (token.isNotEmpty) {
          verified = await account.completeGooglePurchase(
            productId: purchase.productID,
            purchaseToken: token,
          );
        }
        // Acknowledge/complete only after the backend has verified the token
        // and the account state reflects the entitlement. If the API is down,
        // leave the Play purchase pending so it can be retried/restored.
        if (verified && purchase.pendingCompletePurchase) {
          await store.completePurchase(purchase);
        }
      }
    }
  }
}

final aveeBillingService = AveeBillingService();

Future<void> openAveePlaySubscriptionManagement() async {
  final uri = Uri.parse(
    'https://play.google.com/store/account/subscriptions?package=com.avee.vpn',
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class AveePaywall extends StatelessWidget {
  const AveePaywall({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AveeColors.surface,
        barrierColor: Colors.black87,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => const AveePaywall(),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: FutureBuilder<AveeBillingOffers>(
            future: aveeBillingService.offers(),
            builder: (context, snapshot) {
              if (aveeAccountState.isSubscriptionAccess) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Your subscription is active',
                      style: TextStyle(
                        color: AveeColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage or cancel it in Google Play. No additional plan can be purchased while this subscription is active.',
                      style: TextStyle(color: AveeColors.secondaryText),
                    ),
                    const SizedBox(height: 16),
                    AveePrimaryButton(
                      label: 'Manage subscription',
                      icon: Icons.open_in_new,
                      onPressed: () => openAveePlaySubscriptionManagement(),
                    ),
                  ],
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: AveeColors.primary));
              }
              if (snapshot.hasError || snapshot.data == null) {
                return const Text('Plans are temporarily unavailable',
                    style: TextStyle(color: AveeColors.secondaryText));
              }
              final products = snapshot.data!.google.productDetails;
              if (products.isEmpty) {
                return const Text('Plans are not configured yet',
                    style: TextStyle(color: AveeColors.secondaryText));
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [
                    Icon(Icons.workspace_premium_outlined,
                        color: AveeColors.primary),
                    SizedBox(width: 10),
                    Text('Choose a plan',
                        style: TextStyle(
                            color: AveeColors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 6),
                  const Text('One subscription. Every available AVEE location.',
                      style: TextStyle(color: AveeColors.secondaryText)),
                  const SizedBox(height: 12),
                  for (final product in products)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PlanOfferCard(
                        product: product,
                        plan: _planForProduct(snapshot.data!.plans, product),
                        onPressed: () async {
                          await aveeBillingService.buy(product);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
}

class _PlanOfferCard extends StatelessWidget {
  const _PlanOfferCard({
    required this.product,
    required this.plan,
    required this.onPressed,
  });

  final ProductDetails product;
  final Map<String, dynamic>? plan;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final details = plan;
    final duration = _planDurationLabel(details?['durationDays']);
    final traffic = _planTrafficLabel(details?['trafficLimitBytes']);
    final devices = _planDevicesLabel(details?['maxDevices']);
    return AveePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.title,
                  style: const TextStyle(
                    color: AveeColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                product.price,
                style: const TextStyle(
                  color: AveeColors.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$duration  •  $traffic  •  $devices',
            style: const TextStyle(color: AveeColors.secondaryText),
          ),
          const SizedBox(height: 6),
          const Text(
            'Auto-renewing. Manage or cancel anytime in Google Play.',
            style: TextStyle(color: AveeColors.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          AveePrimaryButton(
            icon: Icons.arrow_forward_rounded,
            label: 'Subscribe now',
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
