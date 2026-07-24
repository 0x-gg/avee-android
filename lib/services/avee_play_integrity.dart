import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dropweb/common/constant.dart';
import 'package:flutter/services.dart';

class AveePlayIntegrityAttestation {
  const AveePlayIntegrityAttestation({
    required this.token,
    required this.requestHash,
  });

  final String token;
  final String requestHash;
}

/// Requests a Play Integrity token for account bootstrap on Play builds.
class AveePlayIntegrity {
  static const _channel = MethodChannel('avee/play_integrity');

  static const _cloudProjectNumber = String.fromEnvironment(
    'PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER',
  );

  static Future<AveePlayIntegrityAttestation?> request() async {
    if (!Platform.isAndroid || !kIsPlayBuild) return null;
    if (_cloudProjectNumber.isEmpty) return null;
    final requestHash = _randomRequestHash();
    try {
      final token = await _channel.invokeMethod<String>(
        'requestIntegrityToken',
        {
          'cloudProjectNumber': _cloudProjectNumber,
          'requestHash': requestHash,
        },
      );
      if (token == null || token.isEmpty) return null;
      return AveePlayIntegrityAttestation(
        token: token,
        requestHash: requestHash,
      );
    } on PlatformException {
      return null;
    }
  }

  static String _randomRequestHash() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(sha256.convert(bytes).bytes);
  }
}
