import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flclashx/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class SendToTvPage extends ConsumerStatefulWidget {

  const SendToTvPage({
    super.key,
    required this.profileUrl,
  });
  final String profileUrl;

  @override
  ConsumerState<SendToTvPage> createState() => _SendToTvPageState();
}

class _SendToTvPageState extends ConsumerState<SendToTvPage> {
  static const _syncType = 'flclashx_tv_sync';

  final MobileScannerController _scannerController = MobileScannerController();
  bool _isScanComplete = false;

  Future<void> _handleQrCode(BarcodeCapture capture) async {
    if (_isScanComplete) return;
    if (capture.barcodes.isEmpty) return;

    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue == null) return;

    // The TV now encodes a plain landing-page URL (so a native phone camera can
    // open it too); older TVs encoded a JSON descriptor. Accept both; ignore
    // anything that isn't ours so an accidental scan doesn't lock the screen.
    final endpoint = _parseSyncEndpoint(rawValue);
    if (endpoint == null) return;

    setState(() {
      _isScanComplete = true;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      await dio.post(
        endpoint,
        data: {'url': widget.profileUrl},
      );
      _showResultDialog(appLocalizations.successTitle,
          appLocalizations.sentSuccessfullyMessage);
    } catch (e) {
      commonPrint.log('Error sending profile to TV: $e');
      _showResultDialog(
          appLocalizations.errorTitle, appLocalizations.invalidQrMessage);
    }
  }

  /// Resolve the `/add-profile` endpoint from a scanned code, supporting both
  /// the URL form (`http://ip:port/`) and the legacy JSON form. Returns null
  /// when the code isn't a FlClashX TV-sync code.
  String? _parseSyncEndpoint(String rawValue) {
    final uri = Uri.tryParse(rawValue.trim());
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.hasPort) {
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: '/add-profile',
      ).toString();
    }
    try {
      final payload = jsonDecode(rawValue);
      if (payload is! Map<String, dynamic>) return null;
      if (payload['type'] != _syncType) return null;
      final ip = payload['ip'];
      final port = payload['port'];
      if (ip is! String || ip.isEmpty || port is! int) return null;
      if (port < 1 || port > 65535) return null;
      return Uri(
        scheme: 'http',
        host: ip,
        port: port,
        path: '/add-profile',
      ).toString();
    } catch (_) {
      return null;
    }
  }

  void _showResultDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(appLocalizations.sendToTvTitle)),
      body: MobileScanner(
        controller: _scannerController,
        onDetect: _handleQrCode,
      ),
    );

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }
}
