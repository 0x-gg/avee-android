import 'dart:io';

import 'package:avee/plugins/app.dart';
import 'package:avee/state.dart';

class Android {
  Future<void> init() async {
    app?.onExit = () async {
      await globalState.appController.savePreferences();
    };
  }
}

final android = Platform.isAndroid ? Android() : null;
