import 'package:avee/common/common.dart';
import 'package:avee/enum/enum.dart';
import 'package:avee/providers/app.dart';
import 'package:avee/providers/state.dart';
import 'package:avee/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VpnManager extends ConsumerStatefulWidget {
  const VpnManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends ConsumerState<VpnManager> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(vpnStateProvider, (prev, next) {
      // Skip the tip when the vpnState change came from a config setup applying
      // (e.g. a profile switch syncing the provider's tun.stack). Those apply
      // live; only genuine manual VPN/network-setting changes should warn.
      if (globalState.suppressVpnTip) return;
      showTip();
    });
  }

  void showTip() {
    debouncer.call(
      FunctionTag.vpnTip,
      () {
        if (ref.read(runTimeProvider.notifier).isStart) {
          globalState.showNotifier(
            appLocalizations.vpnTip,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
