import 'dart:io';

import 'package:avee/common/common.dart';
import 'package:avee/state.dart';

class AveeHttpOverrides extends HttpOverrides {
  /// Hosts that are permitted to use self-signed / invalid certificates.
  /// Only the local mihomo helper + control API is allowed — everything else
  /// (subscription servers, update checks, IP detection APIs) MUST present
  /// a valid certificate chain.
  static const _localhostHosts = {'localhost', '127.0.0.1', '::1'};

  static String handleFindProxy(Uri url) {
    if ([localhost].contains(url.host)) {
      return "DIRECT";
    }

    // Mobile: app excluded from VPN, always go direct
    if (Platform.isAndroid || Platform.isIOS) {
      return "DIRECT";
    }

    // Desktop: use proxy when VPN is running (for subscription updates via VPN)
    final port = globalState.config.patchClashConfig.mixedPort;
    final isStart = globalState.appState.runTime != null;
    commonPrint.log("find $url proxy:$isStart");
    if (!isStart) return "DIRECT";
    // When TUN is handling traffic, let the OS network stack send the request
    // so it gets captured by TUN and processed by the core via rules. This
    // avoids depending on the mixed-port inbound at all, which removes issues
    // with inbound `authentication` rejecting the app's own HTTP traffic and
    // also works when the user sets mixed-port to 0 (disabled).
    // Loop prevention: clash-core outbound sockets are protected/bound outside
    // TUN (on Android via TunInterface.protect, on desktop via binding the
    // physical interface).
    //
    // On Android the service is always a VpnService (TUN), so when it's
    // running the traffic is already captured. `realTunEnable` is a desktop-
    // only flag (it tracks admin authorization for TUN on Win/macOS/Linux)
    // and stays false on Android even though TUN is effectively on.
    final tunHandlesTraffic =
        Platform.isAndroid || globalState.appState.realTunEnable;
    if (tunHandlesTraffic) {
      return "DIRECT";
    }
    final port = globalState.config.patchClashConfig.mixedPort;
    if (port == 0) {
      // Mixed-port is disabled and TUN isn't handling traffic — we have no
      // inbound to route through. Go DIRECT; at worst the request leaks, but
      // that's strictly better than trying PROXY localhost:0 which hangs.
      return "DIRECT";
    }
    return "PROXY localhost:$port";
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // SECURITY: never trust bad certs globally — MITM risk on subscription/API fetches.
    client.badCertificateCallback = (cert, host, port) {
      return _localhostHosts.contains(host);
    };
    client.findProxy = handleFindProxy;
    return client;
  }
}
