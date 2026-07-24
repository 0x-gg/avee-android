import 'dart:convert';

import 'package:avee/services/avee_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('creates a session from the backend response', () async {
    final client = MockClient((request) async => http.Response(
        jsonEncode({
          'account': {'id': 'a1', 'accountNumber': 'ABC'},
          'device': {'id': 'd1'},
          'session': {'token': 'secret', 'expiresAt': '2026-07-15T00:00:00Z'}
        }),
        201));
    final session = await AveeApi(
            baseUrl: 'http://10.0.2.2:3000/', client: client)
        .createAccount(publicKey: 'public-key-123456789012345678901234567890');
    expect(session.accountId, 'a1');
    expect(session.deviceId, 'd1');
    expect(session.token, 'secret');
  });

  test('redacts no token into error text', () async {
    final client = MockClient((request) async =>
        http.Response(jsonEncode({'message': 'Invalid session'}), 401));
    expect(
        () => AveeApi(baseUrl: 'http://10.0.2.2:3000', client: client)
            .accountState(AveeSession(
                accountId: 'a',
                accountNumber: 'n',
                deviceId: 'd',
                token: 'secret',
                expiresAt: DateTime.utc(2026, 7, 15))),
        throwsA(isA<AveeApiException>()));
  });

  test('deletes an account with explicit confirmation and session header',
      () async {
    late http.Request request;
    final client = MockClient((value) async {
      request = value;
      return http.Response('{"deleted":true}', 200);
    });
    final session = AveeSession(
      accountId: 'a',
      accountNumber: 'n',
      deviceId: 'd',
      token: 'secret',
      expiresAt: DateTime.utc(2026, 7, 15),
    );
    final result =
        await AveeApi(baseUrl: 'http://10.0.2.2:3000', client: client)
            .deleteAccount(session);
    expect(result['deleted'], isTrue);
    expect(request.method, 'DELETE');
    expect(request.headers['x-session-token'], 'secret');
    expect(jsonDecode(request.body)['confirmation'], 'DELETE');
  });
}
