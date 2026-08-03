import 'dart:io';

import 'package:flutter/services.dart';

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
/// used for payment eligibility. The Android bridge reads BillingClient's
/// billing configuration API directly.
class AveePlayCountryService {
  static const _channel = MethodChannel('avee/billing_region');

  Future<AveePlayCountry> resolve() async {
    if (!Platform.isAndroid) {
      return const AveePlayCountry(status: AveePlayCountryStatus.unknown);
    }
    try {
      final value =
          await _channel.invokeMethod<Map<Object?, Object?>>('getPlayCountry');
      final status = value?['status'] as String?;
      final country = (value?['countryCode'] as String?)?.toUpperCase();
      return AveePlayCountry(
        status: switch (status) {
          'resolved' when country?.length == 2 =>
            AveePlayCountryStatus.resolved,
          'billingUnavailable' => AveePlayCountryStatus.billingUnavailable,
          'temporarilyUnavailable' =>
            AveePlayCountryStatus.temporarilyUnavailable,
          _ => AveePlayCountryStatus.unknown,
        },
        countryCode: country,
      );
    } on PlatformException {
      return const AveePlayCountry(
          status: AveePlayCountryStatus.temporarilyUnavailable);
    } catch (_) {
      return const AveePlayCountry(status: AveePlayCountryStatus.unknown);
    }
  }
}

final aveePlayCountryService = AveePlayCountryService();
