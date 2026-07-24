import 'package:avee/common/file_logger.dart';
import 'package:avee/common/log_redaction.dart';
import 'package:avee/models/models.dart';
import 'package:avee/state.dart';
import 'package:flutter/cupertino.dart';

class CommonPrint {
  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  CommonPrint._internal();
  static CommonPrint? _instance;

  void log(String? text) {
    // SECURITY: redact URL credentials/query/fragment centrally so neither
    // console (`debugPrint`), the file log, nor the in-app log buffer ever
    // emit subscription tokens or deep-link payloads in clear text.
    final payload = redactUrls("[AVEE] $text");
    debugPrint(payload);

    // Write to file log
    fileLogger.log(payload);

    if (!globalState.isInit) {
      return;
    }
    globalState.appController.addLog(
      Log.app(payload),
    );
  }
}

final commonPrint = CommonPrint();
