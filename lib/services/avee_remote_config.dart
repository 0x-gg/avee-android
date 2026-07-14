import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'avee_api.dart';

/// Verifies and caches backend-owned policy. The public key is safe to ship in
/// the client; the Ed25519 private key never leaves the backend secret store.
class AveeRemoteConfig extends ChangeNotifier {
  AveeRemoteConfig({AveeApi? api, FlutterSecureStorage? storage})
      : _api = api ?? AveeApi(baseUrl: _defaultBaseUrl),
        _storage = storage ?? const FlutterSecureStorage();

  static const _cacheKey = 'avee.remote_config.last_known_good';
  static const _publicKey = String.fromEnvironment('AVEE_CONFIG_PUBLIC_KEY');

  static String get _defaultBaseUrl =>
      'http://${defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : '127.0.0.1'}:3000';

  final AveeApi _api;
  final FlutterSecureStorage _storage;
  Map<String, dynamic>? value;
  String? error;

  Future<Map<String, dynamic>?> refresh() async {
    try {
      final remote = await _api.clientConfig();
      await _verify(remote);
      await _storage.write(key: _cacheKey, value: jsonEncode(remote));
      value = remote;
      error = null;
      notifyListeners();
      return remote;
    } catch (_) {
      final cached = await _storage.read(key: _cacheKey);
      if (cached != null) {
        try {
          final parsed = jsonDecode(cached) as Map<String, dynamic>;
          await _verify(parsed);
          value = parsed;
          error = 'Using last-known-good policy';
          notifyListeners();
          return parsed;
        } catch (_) {}
      }
      error = 'Remote policy unavailable';
      notifyListeners();
      return null;
    }
  }

  Future<void> _verify(Map<String, dynamic> config) async {
    final expiresAt = DateTime.tryParse(config['expiresAt'] as String? ?? '');
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
      throw const FormatException('Remote policy is expired');
    }
    final algorithm = config['signatureAlgorithm'];
    final signature = config['signature'];
    final payload = config['payload'];
    if (algorithm == 'none' && !kReleaseMode) return;
    if (algorithm != 'ed25519' || signature is! String || payload is! Map) {
      throw const FormatException('Remote policy signature is invalid');
    }
    if (_publicKey.isEmpty)
      throw const FormatException('Config public key missing');
    final publicKey = SimplePublicKey(
      base64Url.decode(base64Url.normalize(_publicKey)),
      type: KeyPairType.ed25519,
    );
    final valid = await Ed25519().verify(
      utf8.encode(jsonEncode(payload)),
      signature: Signature(
        base64Url.decode(base64Url.normalize(signature)),
        publicKey: publicKey,
      ),
    );
    if (!valid) throw const FormatException('Remote policy signature mismatch');
  }
}

final aveeRemoteConfig = AveeRemoteConfig();
