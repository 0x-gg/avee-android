import 'dart:convert';

import 'package:http/http.dart' as http;

class AveeApiException implements Exception {
  const AveeApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'AveeApiException($statusCode): $message';
}

class AveeSession {
  const AveeSession(
      {required this.accountId,
      required this.accountNumber,
      required this.deviceId,
      required this.token,
      required this.expiresAt,
      this.recoveryCode});

  final String accountId;
  final String accountNumber;
  final String deviceId;
  final String token;
  final DateTime expiresAt;
  final String? recoveryCode;

  factory AveeSession.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>;
    final device = json['device'] as Map<String, dynamic>;
    final session = json['session'] as Map<String, dynamic>;
    return AveeSession(
        accountId: account['id'] as String,
        accountNumber: account['accountNumber'] as String,
        deviceId: device['id'] as String,
        token: session['token'] as String,
        expiresAt: DateTime.parse(session['expiresAt'] as String),
        recoveryCode: json['recoveryCode'] as String?);
  }
}

class AveeApi {
  AveeApi({required String baseUrl, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
        client = client ?? http.Client();

  final String baseUrl;
  final http.Client client;

  Future<AveeSession> createAccount(
      {required String publicKey,
      String? installationId,
      String? deviceFingerprint,
      String? playIntegrityToken,
      String? playIntegrityRequestHash,
      String? deviceName,
      String? appVersion}) async {
    final response = await _request('POST', '/accounts', body: {
      'publicKey': publicKey,
      if (installationId != null) 'installationId': installationId,
      if (deviceFingerprint != null) 'deviceFingerprint': deviceFingerprint,
      if (playIntegrityToken != null) 'playIntegrityToken': playIntegrityToken,
      if (playIntegrityRequestHash != null)
        'playIntegrityRequestHash': playIntegrityRequestHash,
      if (deviceName != null) 'deviceName': deviceName,
      if (appVersion != null) 'appVersion': appVersion
    });
    return AveeSession.fromJson(response);
  }

  Future<AveeSession> recoverAccount({
    required String accountNumber,
    required String recoveryCode,
    required String publicKey,
    String? installationId,
    String? deviceFingerprint,
    String? playIntegrityToken,
    String? playIntegrityRequestHash,
    String? deviceName,
    String? appVersion,
  }) async {
    final response = await _request('POST', '/accounts/recover', body: {
      'accountNumber': accountNumber,
      'recoveryCode': recoveryCode,
      'publicKey': publicKey,
      if (installationId != null) 'installationId': installationId,
      if (deviceFingerprint != null) 'deviceFingerprint': deviceFingerprint,
      if (playIntegrityToken != null) 'playIntegrityToken': playIntegrityToken,
      if (playIntegrityRequestHash != null)
        'playIntegrityRequestHash': playIntegrityRequestHash,
      if (deviceName != null) 'deviceName': deviceName,
      if (appVersion != null) 'appVersion': appVersion,
    });
    return AveeSession.fromJson(response);
  }

  Future<Map<String, dynamic>> accountState(AveeSession session) =>
      _request('GET', '/accounts/${session.accountId}/state',
          token: session.token);

  Future<Map<String, dynamic>> deleteAccount(AveeSession session) =>
      _request('DELETE', '/accounts/${session.accountId}',
          token: session.token, body: {'confirmation': 'DELETE'});

  Future<Map<String, dynamic>> startTrial(AveeSession session) =>
      _request('POST', '/accounts/${session.accountId}/trial',
          token: session.token);

  Future<
      Map<String,
          dynamic>> issueDeviceChallenge(AveeSession session) => _request(
      'POST',
      '/accounts/${session.accountId}/devices/${session.deviceId}/challenge',
      token: session.token);

  Future<Map<String, dynamic>> verifyDeviceChallenge(AveeSession session,
          {required String challenge, required String signature}) =>
      _request('POST',
          '/accounts/${session.accountId}/devices/${session.deviceId}/challenge/verify',
          token: session.token,
          body: {'challenge': challenge, 'signature': signature});

  Future<Map<String, dynamic>> clientConfig() =>
      _request('GET', '/config/client');

  Future<Map<String, dynamic>> billingMethods() =>
      _request('GET', '/config/billing/methods');

  Future<Map<String, dynamic>> locations() => _request('GET', '/locations');

  Future<Map<String, dynamic>> completeGooglePurchase(AveeSession session,
          {required String productId, required String purchaseToken}) =>
      _request('POST', '/billing/google/complete',
          token: session.token,
          extraHeaders: {'x-account-id': session.accountId},
          body: {'productId': productId, 'purchaseToken': purchaseToken});

  Future<Map<String, dynamic>> restoreGooglePurchases(AveeSession session) =>
      _request('POST', '/billing/google/restore',
          token: session.token,
          extraHeaders: {'x-account-id': session.accountId});

  Future<Map<String, dynamic>> createPlategaOrder(AveeSession session,
          {required String planCode, required String currency}) =>
      _request('POST', '/billing/platega/orders',
          token: session.token,
          extraHeaders: {'x-account-id': session.accountId},
          body: {'planCode': planCode, 'currency': currency});

  Future<Map<String, dynamic>> getPlategaOrder(
          AveeSession session, String orderId) =>
      _request('GET', '/billing/platega/orders/$orderId',
          token: session.token,
          extraHeaders: {'x-account-id': session.accountId});

  Future<String> managedMihomoProfile(AveeSession session,
      {String? hwid}) async {
    final response = await _request('GET', '/config/mihomo',
        token: session.token,
        extraHeaders: {
          'x-account-id': session.accountId,
          if (hwid != null) 'x-avee-hwid': hwid
        },
        acceptYaml: true);
    return response['_raw'] as String;
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {String? token,
      Map<String, dynamic>? body,
      Map<String, String>? extraHeaders,
      bool acceptYaml = false}) async {
    final headers = <String, String>{
      'accept': acceptYaml ? 'application/yaml' : 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (token != null) 'x-session-token': token,
      ...?extraHeaders
    };
    final uri = Uri.parse('$baseUrl/v1$path');
    final response = switch (method) {
      'GET' => await client.get(uri, headers: headers),
      'POST' => await client.post(uri,
          headers: headers, body: body == null ? null : jsonEncode(body)),
      'DELETE' => await client.delete(uri,
          headers: headers, body: body == null ? null : jsonEncode(body)),
      _ => throw ArgumentError('Unsupported HTTP method: $method'),
    };
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw AveeApiException(response.statusCode, _errorMessage(response));
    if (acceptYaml) return {'_raw': response.body};
    if (response.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _errorMessage(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic> && value['message'] != null)
        return value['message'].toString();
    } catch (_) {}
    return 'Request failed';
  }
}
