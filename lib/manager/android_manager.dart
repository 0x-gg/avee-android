import 'package:avee/plugins/app.dart';
import 'package:avee/providers/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AndroidManager extends ConsumerStatefulWidget {
  const AndroidManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends ConsumerState<AndroidManager> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Edge-to-edge is the supported Android 15+ system UI mode. Do not set a
    // preferred orientation here: large-screen Android 16 devices must be
    // allowed to resize and rotate naturally.
    ref.listenManual(appSettingProvider.select((state) => state.hidden),
        (prev, next) {
      app?.updateExcludeFromRecents(next);
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
