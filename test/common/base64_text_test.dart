import 'dart:convert';

import 'package:avee/common/base64_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeMaybeBase64', () {
    test('plain text (invalid base64) is returned as-is', () {
      expect(decodeMaybeBase64('hello world'), 'hello world');
    });

    test('valid base64 of utf8 text is decoded', () {
      final encoded = base64.encode(utf8.encode('Привет, AVEE'));
      expect(decodeMaybeBase64(encoded), 'Привет, AVEE');
    });

    test('base64:-prefixed payload is decoded', () {
      final encoded = 'base64:${base64.encode(utf8.encode('my-server'))}';
      expect(decodeMaybeBase64(encoded), 'my-server');
    });

    test('garbage / invalid base64 is returned as-is', () {
      expect(decodeMaybeBase64('!!!not@base64!!!'), '!!!not@base64!!!');
    });

    test('base64:-prefixed garbage falls back to the original (prefix kept)',
        () {
      expect(decodeMaybeBase64('base64:!!!garbage@@@'), 'base64:!!!garbage@@@');
    });

    test('empty string stays empty', () {
      expect(decodeMaybeBase64(''), '');
    });
  });
}
