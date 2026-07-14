import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

enum AveePlayCountryStatus {
  resolved,
  billingUnavailable,
  temporarilyUnavailable,
  unknown,
}

class AveePlayCountry {
  const AveePlayCountry({required this.status, this.countryCode});

  final AveePlayCountryStatus status;
  final String? countryCode;

  bool get isRussia =>
      status == AveePlayCountryStatus.resolved && countryCode == 'RU';
}

/// Uses Google Play Billing's storefront country. Locale, SIM and IP are not
/// used for payment eligibility. The plugin delegates this to BillingClient's
/// billing configuration API on Android.
class AveePlayCountryService {
  Future<AveePlayCountry> resolve() async {
    if (!Platform.isAndroid) {
      return const AveePlayCountry(status: AveePlayCountryStatus.unknown);
    }
    try {
      final store = InAppPurchase.instance;
      if (!await store.isAvailable()) {
        return const AveePlayCountry(
            status: AveePlayCountryStatus.billingUnavailable);
      }
      final country = (await store.countryCode()).toUpperCase();
      if (country.length != 2) {
        return const AveePlayCountry(status: AveePlayCountryStatus.unknown);
      }
      return AveePlayCountry(
          status: AveePlayCountryStatus.resolved, countryCode: country);
    } on InAppPurchaseException {
      return const AveePlayCountry(
          status: AveePlayCountryStatus.temporarilyUnavailable);
    } catch (_) {
      return const AveePlayCountry(status: AveePlayCountryStatus.unknown);
    }
  }
}

final aveePlayCountryService = AveePlayCountryService();
