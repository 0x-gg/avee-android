import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yaml/yaml.dart';

import 'avee_api.dart';

/// Thin client-side AVEE account state. The VPN profile remains owned by
/// Dropweb; this service only owns the AVEE control-plane session and device
/// identity needed to obtain a managed profile later.
class AveeAccountState extends ChangeNotifier {
  AveeAccountState({AveeApi? api, FlutterSecureStorage? storage})
      : _api = api ?? AveeApi(baseUrl: _defaultBaseUrl),
        _storage = storage ?? const FlutterSecureStorage();

  static const _accountIdKey = 'avee.account_id';
  static const _accountNumberKey = 'avee.account_number';
  static const _deviceIdKey = 'avee.device_id';
  static const _sessionTokenKey = 'avee.session_token';
  static const _sessionExpiresKey = 'avee.session_expires_at';
  static const _publicKeyKey = 'avee.device_public_key';
  static const _privateKeyKey = 'avee.device_private_key';
  static const _managedProfileKey = 'avee.managed_profile';

  static String get _defaultBaseUrl {
    const configured = String.fromEnvironment('AVEE_API_URL');
    if (configured.isNotEmpty) return configured;
    return 'http://${Platform.isAndroid ? '10.0.2.2' : '127.0.0.1'}:3000';
  }

  final AveeApi _api;
  final FlutterSecureStorage _storage;

  AveeSession? session;
  bool loading = false;
  bool reachable = false;
  bool access = false;
  DateTime? accessExpiresAt;
  String? error;
  DateTime? managedProfileUpdatedAt;

  Future<void> restore() async {
    final values = await Future.wait([
      _storage.read(key: _accountIdKey),
      _storage.read(key: _accountNumberKey),
      _storage.read(key: _deviceIdKey),
      _storage.read(key: _sessionTokenKey),
      _storage.read(key: _sessionExpiresKey),
    ]);
    if (values.any((value) => value == null)) return;
    final expiresAt = DateTime.tryParse(values[4]!);
    if (expiresAt == null || expiresAt.isBefore(DateTime.now())) {
      await clear();
      return;
    }
    session = AveeSession(
      accountId: values[0]!,
      accountNumber: values[1]!,
      deviceId: values[2]!,
      token: values[3]!,
      expiresAt: expiresAt,
    );
    notifyListeners();
    await refresh();
  }

  Future<void> createAccount() async {
    await _run(() async {
      final keyPair = await _ensureDeviceKeyPair();
      final info = await PackageInfo.fromPlatform();
      final created = await _api.createAccount(
        publicKey: base64UrlEncode(keyPair.publicKey.bytes),
        deviceName: Platform.operatingSystem,
        appVersion: info.version,
      );
      await _save(created);
      await verifyDevice();
      await refresh();
    });
  }

  Future<void> recoverAccount({
    required String accountNumber,
    required String recoveryCode,
  }) async {
    await _run(() async {
      final keyPair = await _ensureDeviceKeyPair();
      final info = await PackageInfo.fromPlatform();
      final recovered = await _api.recoverAccount(
        accountNumber: accountNumber.trim(),
        recoveryCode: recoveryCode.trim(),
        publicKey: base64UrlEncode(keyPair.publicKey.bytes),
        deviceName: Platform.operatingSystem,
        appVersion: info.version,
      );
      await _save(recovered);
      await verifyDevice();
      await refresh();
    });
  }

  Future<void> startTrial() async {
    final current = session;
    if (current == null) return;
    await _run(() async {
      await _api.startTrial(current);
      await refresh();
    });
  }

  Future<void> completeGooglePurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    final current = session;
    if (current == null) return;
    await _run(() async {
      await _api.completeGooglePurchase(current,
          productId: productId, purchaseToken: purchaseToken);
      await refresh();
    });
  }

  Future<Map<String, dynamic>> billingMethods() => _api.billingMethods();

  Future<void> restoreGooglePurchases() async {
    final current = session;
    if (current == null) return;
    await _run(() async {
      await _api.restoreGooglePurchases(current);
      await refresh();
    });
  }

  Future<void> verifyDevice() async {
    final current = session;
    if (current == null) return;
    await _run(() async {
      final challenge = await _api.issueDeviceChallenge(current);
      final privateKey = await _storage.read(key: _privateKeyKey);
      final publicKey = await _storage.read(key: _publicKeyKey);
      if (privateKey == null || publicKey == null) {
        throw StateError('Device key is missing');
      }
      final keyPair = SimpleKeyPairData(
        base64Url.decode(privateKey),
        type: KeyPairType.ed25519,
        publicKey: SimplePublicKey(
          base64Url.decode(publicKey),
          type: KeyPairType.ed25519,
        ),
      );
      final signature = await Ed25519().sign(
        utf8.encode(challenge['challenge'] as String),
        keyPair: keyPair,
      );
      await _api.verifyDeviceChallenge(
        current,
        challenge: challenge['challenge'] as String,
        signature: base64UrlEncode(signature.bytes),
      );
      await refresh();
    });
  }

  Future<String?> refreshManagedProfile() async {
    final current = session;
    if (current == null || !access) return null;
    try {
      final yaml = await _api.managedMihomoProfile(current);
      final parsed = loadYaml(yaml);
      if (parsed is! YamlMap || parsed['proxies'] is! YamlList) {
        throw const FormatException('Managed profile has no proxies');
      }
      await _storage.write(key: _managedProfileKey, value: yaml);
      managedProfileUpdatedAt = DateTime.now();
      error = null;
      notifyListeners();
      return yaml;
    } catch (exception) {
      // Keep the last-known-good profile in secure storage. A transient
      // Remnawave outage must not erase the user's working configuration.
      error = exception is AveeApiException
          ? exception.message
          : 'Profile refresh failed';
      notifyListeners();
      return _storage.read(key: _managedProfileKey);
    }
  }

  Future<void> refreshManagedProfileForButton() async {
    await refreshManagedProfile();
  }

  Future<void> refresh() async {
    final current = session;
    if (current == null) return;
    try {
      final state = await _api.accountState(current);
      reachable = true;
      access = state['access'] == true;
      accessExpiresAt =
          DateTime.tryParse(state['entitlementExpiresAt'] as String? ?? '');
      error = null;
    } on AveeApiException catch (exception) {
      reachable = true;
      error = exception.message;
      if (exception.statusCode == 401) await clear();
    } catch (_) {
      reachable = false;
      error = 'Backend unavailable';
    }
    notifyListeners();
  }

  Future<void> clear() async {
    session = null;
    access = false;
    await Future.wait([
      _storage.delete(key: _accountIdKey),
      _storage.delete(key: _accountNumberKey),
      _storage.delete(key: _deviceIdKey),
      _storage.delete(key: _sessionTokenKey),
      _storage.delete(key: _sessionExpiresKey),
    ]);
    notifyListeners();
  }

  Future<SimpleKeyPairData> _ensureDeviceKeyPair() async {
    final existingPrivate = await _storage.read(key: _privateKeyKey);
    final existingPublic = await _storage.read(key: _publicKeyKey);
    if (existingPrivate != null && existingPublic != null) {
      return SimpleKeyPairData(
        base64Url.decode(existingPrivate),
        type: KeyPairType.ed25519,
        publicKey: SimplePublicKey(
          base64Url.decode(existingPublic),
          type: KeyPairType.ed25519,
        ),
      );
    }
    final pair = await Ed25519().newKeyPair();
    final publicKey = await pair.extractPublicKey();
    final privateKey = await pair.extractPrivateKeyBytes();
    await _storage.write(
        key: _privateKeyKey, value: base64UrlEncode(privateKey));
    await _storage.write(
        key: _publicKeyKey, value: base64UrlEncode(publicKey.bytes));
    return SimpleKeyPairData(
      privateKey,
      type: KeyPairType.ed25519,
      publicKey: publicKey,
    );
  }

  Future<void> _save(AveeSession value) async {
    session = value;
    await Future.wait([
      _storage.write(key: _accountIdKey, value: value.accountId),
      _storage.write(key: _accountNumberKey, value: value.accountNumber),
      _storage.write(key: _deviceIdKey, value: value.deviceId),
      _storage.write(key: _sessionTokenKey, value: value.token),
      _storage.write(
          key: _sessionExpiresKey, value: value.expiresAt.toIso8601String()),
    ]);
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on AveeApiException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Backend unavailable';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

final aveeAccountState = AveeAccountState();
