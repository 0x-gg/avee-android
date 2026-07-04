import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:dropweb/enum/enum.dart';
import 'package:dropweb/plugins/app.dart';
import 'package:dropweb/plugins/tile.dart';
import 'package:dropweb/plugins/vpn.dart';
import 'package:dropweb/services/deep_link_handler.dart';
import 'package:dropweb/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application.dart';
import 'clash/core.dart';
import 'clash/lib.dart';
import 'common/common.dart';
import 'models/models.dart';

/// Installs global handlers so uncaught framework and async errors are routed
/// through `commonPrint.log` — the central redaction chokepoint — and reach the
/// file log (and in-app log buffer). Without these, uncaught errors in release
/// builds vanish silently (no crash-reporting SDK by design for the RU market).
///
/// Handlers MUST never throw, so `commonPrint.log` is wrapped defensively even
/// though it is safe to call before full app init (it queues to the file log
/// and only touches the app controller once `globalState.isInit` is true).
void _installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    try {
      commonPrint.log(
        '[flutter-error] ${details.exceptionAsString()}\n${details.stack}',
      );
    } catch (_) {}
    // Preserve debug DX: keep the red error screen / console stacktrace.
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      commonPrint.log('[uncaught] $error\n$stack');
    } catch (_) {}
    // Returning true marks the error as handled so it does not propagate.
    return true;
  };
}

Future<void> main() async {
  globalState.isService = false;
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();

  if (Platform.isWindows || Platform.isLinux) {
    DartPluginRegistrant.ensureInitialized();
  }

  if (system.isDesktop) {
    // MUST run before the first `clashCore` access: instantiating ClashService
    // has side effects (unix bridge-socket rebind, core spawn/restart via the
    // Windows helper) that hijack or kill the RUNNING instance's core. The
    // duplicate-launch process must die before touching any of that.
    if (!await singleInstanceLock.acquire()) {
      exit(0);
    }
  }

  final version = await system.version;
  await clashCore.preload();
  await globalState.initApp(version);
  await android?.init();
  await window?.init(version);

  if (Platform.isAndroid) {
    vpn;
  }
  HttpOverrides.global = DropwebHttpOverrides();
  runApp(const ProviderScope(
    child: Application(),
  ));

  if (Platform.isAndroid) {
    unawaited(DeepLinkHandler.init());
  }
}

@pragma('vm:entry-point')
Future<void> _service(List<String> flags) async {
  commonPrint.log("=== [DART] _service entrypoint started, flags: $flags");

  globalState.isService = true;
  commonPrint.log("[DART] Setting isService = true");

  WidgetsFlutterBinding.ensureInitialized();
  // The VPN service runs in a separate vm:entry-point isolate with its own
  // PlatformDispatcher/zone, so install the same guards here too.
  _installGlobalErrorHandlers();
  // Flush any logs that were queued before bindings were initialized
  fileLogger.flushPendingLogs();
  commonPrint.log("[DART] WidgetsFlutterBinding initialized");

  final quickStart = flags.contains("quick");
  commonPrint.log("[DART] quickStart = $quickStart");

  final clashLibHandler = ClashLibHandler();
  commonPrint.log("[DART] ClashLibHandler created");

  commonPrint.log("[DART] BEFORE try-catch block");
  try {
    commonPrint.log("[DART] Calling globalState.init()...");
    await globalState.init();
    commonPrint.log("[DART] globalState.init() completed");
  } catch (e, stackTrace) {
    commonPrint.log("=== [DART] _service ERROR during globalState.init() ===");
    commonPrint.log("[DART] Error: $e");
    commonPrint.log("[DART] StackTrace: $stackTrace");
    commonPrint.log("[DART] Continuing execution anyway...");
    // Don't rethrow - continue to add listeners
  }
  commonPrint.log("[DART] AFTER try-catch block");

  commonPrint.log("[DART] Adding tile listener...");
  tile?.addListener(
    _TileListenerWithService(
      onStart: () async {
        commonPrint.log("=== [DART] TileService onStart called ===");
        debugPrint("=== TileService onStart called ===");
        try {
          commonPrint.log("TileService: Showing start notification");
          unawaited(app?.tip(appLocalizations.startVpn));

          // Initialize GeoIP/GeoSite only if profile enables it (geodata-mode == true)
          if (await Geodata.currentProfileNeedsGeodata()) {
            commonPrint.log(
                "TileService: Initializing GeoIP/GeoSite (geodata-mode=true)...");
            await ClashCore.initGeo();
            commonPrint.log("TileService: GeoIP/GeoSite initialized");
          } else {
            commonPrint.log(
                "TileService: Skipping Geo init (geodata-mode != true)");
          }

          commonPrint.log("TileService: Getting paths...");
          final homeDirPath = await appPath.homeDirPath;
          final version = await system.version;
          commonPrint
              .log("TileService: homeDirPath=$homeDirPath, version=$version");

          commonPrint.log("TileService: Creating config...");
          final clashConfig = globalState.config.patchClashConfig.copyWith.tun(
            enable: false,
          );

          final profileId = globalState.config.currentProfileId;
          commonPrint.log("TileService: currentProfileId=$profileId");
          if (profileId == null) {
            commonPrint.log("TileService: No profile selected, aborting");
            unawaited(app?.tip("No profile selected"));
            return;
          }
          commonPrint.log("TileService: Getting setup params");
          final params = await globalState.getSetupParams(
            pathConfig: clashConfig,
          );
          commonPrint.log("TileService: Setup params ready");

          commonPrint.log("TileService: Starting ClashCore with quickStart");
          final res = await clashLibHandler.quickStart(
            InitParams(
              homeDir: homeDirPath,
              version: version,
            ),
            params,
            globalState.getCoreState(),
          );
          commonPrint.log("TileService: quickStart result: $res");

          if (res.isNotEmpty) {
            commonPrint.log("TileService: Start failed with error: $res");
            unawaited(app?.tip("Start failed: $res"));
            try {
              await vpn?.stop();
            } catch (e) {
              debugPrint("Tile vpn.stop() error (ignored): $e");
            }
            exit(0);
          }

          commonPrint.log("TileService: Starting VPN service");
          try {
            await vpn?.start(
              clashLibHandler.getAndroidVpnOptions(),
            );
            commonPrint.log("TileService: VPN service started");
          } catch (e) {
            // MissingPluginException may occur if VpnPlugin not yet attached
            // VPN is started by native side via VpnPlugin.handleStart()
            commonPrint.log(
                "TileService: vpn.start() error (may be handled by native): $e");
          }

          commonPrint.log("TileService: Starting listener");
          clashLibHandler.startListener();
          commonPrint.log("=== TileService onStart completed successfully ===");
        } catch (e, stackTrace) {
          commonPrint.log("=== TileService onStart ERROR ===");
          commonPrint.log("Error: $e");
          commonPrint.log("StackTrace: $stackTrace");
          unawaited(app?.tip("Start error: $e"));
          try {
            await vpn?.stop();
          } catch (stopError) {
            debugPrint("Tile vpn.stop() error (ignored): $stopError");
          }
          exit(0);
        }
      },
      onStop: () async {
        try {
          unawaited(app?.tip(appLocalizations.stopVpn));
          clashLibHandler.stopListener();
        } catch (e) {
          debugPrint("Tile stop listener error: $e");
        }
        try {
          await vpn?.stop();
        } catch (e) {
          // MissingPluginException may occur if VpnPlugin not yet attached
          // VPN will be stopped by native side via VpnPlugin.handleStop()
          debugPrint("Tile vpn.stop() error (ignored): $e");
        }
        exit(0);
      },
    ),
  );

  // Provide foreground notification params using data from globalState.config.
  // Shows: title = selected server (else service name, else "dropweb"),
  // content = "↑ speed ↓ speed", subText = "uptime • total".
  vpn?.handleGetStartForegroundParams = () {
    try {
      final traffic = clashLibHandler.getTraffic();
      final profile = globalState.config.currentProfile;

      // Get server group name from header (may be base64-encoded)
      String? groupName = profile?.providerHeaders['dropweb-serverinfo'];
      if (groupName != null && groupName.isNotEmpty) {
        try {
          // Mirror Profile.serviceName: strip the optional `base64:` prefix
          // before normalize/decode, else normalize chokes on the prefix text
          // and the (empty-catch) fallback keeps the raw encoded header.
          final raw =
              groupName.startsWith('base64:') ? groupName.substring(7) : groupName;
          final normalized = base64.normalize(raw);
          groupName = utf8.decode(base64.decode(normalized));
        } catch (_) {}
        groupName = groupName?.trim();
      }

      // Get selected proxy name from selectedMap
      String serverName = "";
      if (groupName != null && groupName.isNotEmpty) {
        final selectedMap = profile?.selectedMap ?? const <String, String>{};
        serverName = selectedMap[groupName] ?? "";
      }

      // Title: selected server name, else provider service name, else "dropweb"
      final serverDisplay = serverName.trim();
      final serviceName = profile?.serviceName.trim() ?? "";
      final title = serverDisplay.isNotEmpty
          ? serverDisplay
          : (serviceName.isNotEmpty ? serviceName : "dropweb");

      // Content: "↑ speed  ↓ speed"
      final content =
          "\u2191 ${traffic.up.show}/s  \u2193 ${traffic.down.show}/s";

      // SubText: "uptime • total traffic"
      String subText = "";
      try {
        final startTime = clashLibHandler.getRunTime();
        if (startTime != null) {
          final elapsed = DateTime.now().difference(startTime);
          final h = elapsed.inHours;
          final m = elapsed.inMinutes % 60;
          final uptime = h > 0 ? "${h}h ${m}m" : "${m}m";
          final total = clashLibHandler.getTotalTraffic(false);
          final totalBytes = total.up.value + total.down.value;
          final totalShow = TrafficValue(value: totalBytes).show;
          subText = "$uptime \u2022 $totalShow";
        }
      } catch (_) {}

      return json.encode({
        "title": title,
        "server": subText,
        "content": content,
      });
    } catch (_) {
      return json.encode({"title": "dropweb", "server": "", "content": ""});
    }
  };

  commonPrint.log("[DART] Adding VPN listener");
  vpn?.addListener(
    _VpnListenerWithService(
      onDnsChanged: (dns) {
        commonPrint.log("handle dns $dns");
        clashLibHandler.updateDns(dns);
      },
    ),
  );

  // Signal to native side that Dart service is ready to receive commands
  // This must be called AFTER adding tile listener so pending actions can be handled
  commonPrint.log("[DART] Signaling service ready to native side");
  await tile?.signalServiceReady();
  commonPrint.log("[DART] Service ready signal sent");

  commonPrint.log("[DART] quickStart=$quickStart");
  if (!quickStart) {
    // App is in memory - set up IPC for communication with main isolate
    commonPrint.log("[DART] Not quickStart, calling _handleMainIpc");
    _handleMainIpc(clashLibHandler);
  } else {
    // App was not in memory - VPN will be started via pending action triggered by signalServiceReady()
    // The onStart callback in tile listener will handle the actual VPN startup
    commonPrint.log(
        "[DART] QuickStart mode - VPN will be started via pending action from tile service");
  }
}

/// Mutable holder for the main-isolate [SendPort] this service isolate targets.
///
/// The main isolate can be destroyed and recreated while this service isolate
/// (and the live VPN core it hosts) stays alive — e.g. the user swipes the app
/// from recents and reopens it. Instead of destroying the service engine (which
/// tears the tunnel, bug 1a/1b), the fresh main isolate re-looks-up this
/// isolate's control port and asks for a re-handshake; we then repoint this
/// holder at the NEW main SendPort so every in-flight IPC send follows the live
/// isolate rather than a dead port.
class _SendPortHolder {
  _SendPortHolder(this.value);
  SendPort value;
}

void _handleMainIpc(ClashLibHandler clashLibHandler) {
  final initialSendPort = IsolateNameServer.lookupPortByName(mainIsolate);
  if (initialSendPort == null) {
    return;
  }
  final sendPortHolder = _SendPortHolder(initialSendPort);
  final serviceReceiverPort = ReceivePort();
  serviceReceiverPort.listen((message) async {
    // Handle special IPC messages for foreground notification updates
    if (message is Map<String, dynamic>) {
      final action = message['action'];
      if (action == 'updateForegroundServer') {
        final serverName = message['serverName'] as String? ?? '';
        final groupName = message['groupName'] as String? ?? '';
        // Update selectedMap in globalState.config
        final profile = globalState.config.currentProfile;
        if (profile != null && groupName.isNotEmpty) {
          final newSelectedMap = Map<String, String>.from(profile.selectedMap);
          newSelectedMap[groupName] = serverName;
          final updatedProfile = profile.copyWith(selectedMap: newSelectedMap);
          globalState.config = globalState.config.copyWith(
            profiles: globalState.config.profiles
                .map((p) => p.id == profile.id ? updatedProfile : p)
                .toList(),
          );
        }
        sendPortHolder.value.send({'success': true});
        return;
      }
      if (action == 'updateMode') {
        final modeName = message['mode'] as String? ?? 'rule';
        final mode = Mode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => Mode.rule,
        );
        globalState.config = globalState.config.copyWith(
          patchClashConfig:
              globalState.config.patchClashConfig.copyWith(mode: mode),
        );
        sendPortHolder.value.send({'success': true});
        return;
      }
    }
    final res = await clashLibHandler.invokeAction(message);
    sendPortHolder.value.send(res);
  });
  sendPortHolder.value.send(serviceReceiverPort.sendPort);
  final messageReceiverPort = ReceivePort();
  clashLibHandler.attachMessagePort(
    messageReceiverPort.sendPort.nativePort,
  );
  // Route native messages through the holder (not a captured tear-off) so a
  // post-rehandshake repoint is honored.
  messageReceiverPort.listen((msg) => sendPortHolder.value.send(msg));

  // Register a control port so a freshly (re)started main isolate can trigger a
  // re-handshake — reattaching to this live service isolate — instead of the
  // old destroy-service-engine path that tore the VPN tunnel (bug 1a/1b).
  final controlPort = ReceivePort();
  IsolateNameServer.removePortNameMapping(serviceIsolate);
  IsolateNameServer.registerPortWithName(controlPort.sendPort, serviceIsolate);
  controlPort.listen((msg) {
    if (msg is Map && msg['action'] == 'rehandshake') {
      final fresh = IsolateNameServer.lookupPortByName(mainIsolate);
      if (fresh != null) {
        sendPortHolder.value = fresh;
        fresh.send(serviceReceiverPort.sendPort); // repeat SendPort handshake
      }
    }
  });
}

@immutable
class _TileListenerWithService with TileListener {
  const _TileListenerWithService({
    required Function() onStart,
    required Function() onStop,
  })  : _onStart = onStart,
        _onStop = onStop;

  final Function() _onStart;
  final Function() _onStop;

  @override
  void onStart() {
    _onStart();
  }

  @override
  void onStop() {
    _onStop();
  }
}

@immutable
class _VpnListenerWithService with VpnListener {
  const _VpnListenerWithService({
    required Function(String dns) onDnsChanged,
  }) : _onDnsChanged = onDnsChanged;
  final Function(String dns) _onDnsChanged;

  @override
  void onDnsChanged(String dns) {
    super.onDnsChanged(dns);
    _onDnsChanged(dns);
  }
}
