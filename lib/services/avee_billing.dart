import 'dart:async';

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
