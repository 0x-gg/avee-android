import 'dart:io';

import 'package:dropweb/common/common.dart';

class SingleInstanceLock {

  factory SingleInstanceLock() {
    _instance ??= SingleInstanceLock._internal();
    return _instance!;
  }

  SingleInstanceLock._internal();
  static SingleInstanceLock? _instance;
  RandomAccessFile? _accessFile;

  // Idempotency cache. `acquire()` is called twice by design (main()'s early
  // desktop gate + window.init()); the second call must be a no-op that returns
  // the SAME verdict without re-locking (re-`lock()`-ing an already-held file
  // can throw on some platforms and would double-open the RandomAccessFile).
  bool? _acquired;

  Future<bool> acquire() async {
    if (_acquired != null) {
      return _acquired!;
    }
    try {
      final lockFilePath = await appPath.lockFilePath;
      final lockFile = File(lockFilePath);
      await lockFile.create();
      _accessFile = await lockFile.open(mode: FileMode.write);
      await _accessFile?.lock();
      _acquired = true;
    } catch (_) {
      _acquired = false;
    }
    return _acquired!;
  }
}

final singleInstanceLock = SingleInstanceLock();
