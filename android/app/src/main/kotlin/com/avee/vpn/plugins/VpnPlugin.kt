package com.avee.vpn.plugins

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import com.avee.vpn.AveeApplication
import com.avee.vpn.GlobalState
import com.avee.vpn.RunState
import com.avee.vpn.core.Core
import com.avee.vpn.extensions.awaitResult
import com.avee.vpn.extensions.resolveDns
import com.avee.vpn.models.StartForegroundParams
import com.avee.vpn.models.VpnOptions
import com.avee.vpn.services.BaseServiceInterface
import com.avee.vpn.services.AveeService
import com.avee.vpn.services.AveeVpnService
import com.avee.vpn.services.applyAveeContent
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import kotlin.concurrent.withLock

data object VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var flutterMethodChannel: MethodChannel
    private var aveeService: BaseServiceInterface? = null
    private var options: VpnOptions? = null
    private var isBind: Boolean = false
    private lateinit var scope: CoroutineScope
    private var lastStartForegroundParams: StartForegroundParams? = null
    private var timerJob: Job? = null
    // resolverProcess() is invoked as a JNI callback from the Go core, which
    // resolves per-connection process names from multiple concurrent goroutines.
    // A plain HashMap corrupts / throws ConcurrentModificationException under
    // that fan-in; ConcurrentHashMap gives lock-free reads and atomic writes.
    private val uidPageNameMap = java.util.concurrent.ConcurrentHashMap<Int, String>()
    private val networks = mutableSetOf<Network>()
    // Identity of the underlying physical network set (sorted networkHandle list).
    // A change here under a live tunnel means WiFi<->cell / pocket-Doze switch —
    // stale upstream proxy sessions (mux, Hy2/QUIC) must be dropped. null = no
    // snapshot yet (the first snapshot after start never triggers a close).
    private var lastNetworkKey: String? = null
    // Debounce: collapse the burst of onAvailable/onLost/onLinkPropertiesChanged
    // callbacks a single physical switch emits into at most one core notify / 2s.
    private var lastNetworkChangeMs = 0L
    private var screenReceiverRegistered: Boolean = false
    private var startRequested: Boolean = false
    private var attachCount = 0

    private val connectivity by lazy {
        AveeApplication.getAppContext().getSystemService<ConnectivityManager>()
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            isBind = true
            aveeService = when (service) {
                is AveeVpnService.LocalBinder -> service.getService()
                is AveeService.LocalBinder -> service.getService()
                else -> throw Exception("invalid binder")
            }
            handleStartService()
        }

        override fun onServiceDisconnected(arg: ComponentName) {
            isBind = false
            aveeService = null
            stopForegroundJob()
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        // This singleton is attached to BOTH the main engine and the service engine.
        // Create the scope and register the network callback only once (first attach)
        // so we never overwrite the live scope (leak) nor register `callback` twice
        // (Android throws IllegalArgumentException → unhandled-coroutine crash).
        attachCount++
        if (attachCount == 1) {
            scope = CoroutineScope(Dispatchers.Default)
            scope.launch {
                registerNetworkCallback()
            }
        }
        // Channel assignment stays last-wins by design: the service engine attaches
        // later and is the correct receiver for VPN logic (service isolate runs it).
        flutterMethodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "vpn")
        flutterMethodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        attachCount--
        // Only tear down once the last engine detaches; otherwise the surviving
        // engine keeps its handler and the shared network callback stays registered.
        if (attachCount <= 0) {
            attachCount = 0
            unRegisterNetworkCallback()
            flutterMethodChannel.setMethodCallHandler(null)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val data = call.argument<String>("data")
                result.success(handleStart(Gson().fromJson(data, VpnOptions::class.java)))
            }

            "stop" -> {
                handleStop()
                result.success(true)
            }

            "showSubscriptionNotification" -> {
                val title = call.argument<String>("title") ?: ""
                val message = call.argument<String>("message") ?: ""
                val actionLabel = call.argument<String>("actionLabel") ?: ""
                val actionUrl = call.argument<String>("actionUrl") ?: ""
                showSubscriptionNotification(title, message, actionLabel, actionUrl)
                result.success(true)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    fun handleStart(options: VpnOptions): Boolean {
        startRequested = true
        onUpdateNetwork();
        if (options.enable != this.options?.enable) {
            this.aveeService = null
        }
        this.options = options
        when (options.enable) {
            true -> handleStartVpn()
            false -> handleStartService()
        }
        return true
    }

    private fun handleStartVpn() {
        GlobalState.getCurrentAppPlugin()?.requestVpnPermission {
            handleStartService()
        }
    }

    fun requestGc() {
        flutterMethodChannel.invokeMethod("gc", null)
    }

    fun onUpdateNetwork() {
        val dns = networks.flatMap { network ->
            connectivity?.resolveDns(network) ?: emptyList()
        }.toSet().joinToString(",")
        scope.launch {
            withContext(Dispatchers.Main) {
                flutterMethodChannel.invokeMethod("dnsChanged", dns)
            }
        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            Log.d("VpnPlugin", "Network available: $network")
            networks.add(network)
            onUpdateNetwork()
            updateUnderlyingNetworks()
        }

        override fun onLost(network: Network) {
            Log.d("VpnPlugin", "Network lost: $network")
            networks.remove(network)
            onUpdateNetwork()
            updateUnderlyingNetworks()
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            Log.d("VpnPlugin", "Link properties changed: $network")
            onUpdateNetwork()
            updateUnderlyingNetworks()
        }
    }

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    // Doze can stale the Network ref — keep VPN routing through the live physical network
    private fun updateUnderlyingNetworks() {
        // Change-detection runs BEFORE the service null-check below: the network
        // callback is registered app-wide at first attach, so this fires while
        // aveeService is still null (bind in flight). We only NOTIFY when the
        // tunnel is actually up (runState==START), so a null service is harmless.
        val key = networks.map { it.networkHandle }.sorted().joinToString(",")
        val prev = lastNetworkKey
        lastNetworkKey = key
        if (prev != null && prev != key && key.isNotEmpty()
            && GlobalState.runState.value == RunState.START) {
            val now = SystemClock.elapsedRealtime()
            if (now - lastNetworkChangeMs > 2000) {
                lastNetworkChangeMs = now
                Log.d("VpnPlugin", "Underlying network changed ($prev -> $key) — asking core to drop stale connections")
                scope.launch {
                    withContext(Dispatchers.Main) {
                        flutterMethodChannel.invokeMethod("networkChanged", null)
                    }
                }
            }
        }

        val vpnService = aveeService as? AveeVpnService ?: return
        vpnService.setUnderlyingNetworks(
            if (networks.isEmpty()) null else networks.toTypedArray()
        )
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_SCREEN_ON) {
                Log.d("VpnPlugin", "Screen ON — refreshing network state")
                onUpdateNetwork()
                updateUnderlyingNetworks()
            }
        }
    }

    private fun registerScreenReceiver() {
        if (screenReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            AveeApplication.getAppContext().registerReceiver(
                screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            AveeApplication.getAppContext().registerReceiver(screenReceiver, filter)
        }
        screenReceiverRegistered = true
    }

    private fun unregisterScreenReceiver() {
        if (!screenReceiverRegistered) return
        try {
            AveeApplication.getAppContext().unregisterReceiver(screenReceiver)
        } catch (_: Exception) {}
        screenReceiverRegistered = false
    }

    private fun registerNetworkCallback() {
        networks.clear()
        // Defense in depth: a registration error must never escape and crash the
        // process via an unhandled coroutine.
        try {
            connectivity?.registerNetworkCallback(request, callback)
        } catch (e: Exception) {
            Log.e("VpnPlugin", "registerNetworkCallback failed", e)
        }
    }

    private fun unRegisterNetworkCallback() {
        // IllegalArgumentException if `callback` was never registered.
        try {
            connectivity?.unregisterNetworkCallback(callback)
        } catch (e: IllegalArgumentException) {
            Log.w("VpnPlugin", "unregisterNetworkCallback: callback not registered", e)
        }
        networks.clear()
        onUpdateNetwork()
    }

    private suspend fun startForeground() {
        GlobalState.runLock.lock()
        try {
            if (GlobalState.runState.value != RunState.START) return
            val data = flutterMethodChannel.awaitResult<String>("getStartForegroundParams")
            val startForegroundParams = if (data != null) Gson().fromJson(
                data, StartForegroundParams::class.java
            ) else StartForegroundParams(
                title = "", server = "", content = ""
            )
            if (lastStartForegroundParams != startForegroundParams) {
                lastStartForegroundParams = startForegroundParams
                aveeService?.startForeground(
                    startForegroundParams.title,
                    startForegroundParams.server,
                    startForegroundParams.content,
                )
            }
        } finally {
            GlobalState.runLock.unlock()
        }
    }

    private fun startForegroundJob() {
        stopForegroundJob()
        timerJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                startForeground()
                delay(1000)
            }
        }
    }

    private fun stopForegroundJob() {
        timerJob?.cancel()
        timerJob = null
    }


    suspend fun getStatus(): Boolean? {
        return withContext(Dispatchers.Default) {
            flutterMethodChannel.awaitResult<Boolean>("status", null)
        }
    }

    private fun handleStartService() {
        if (aveeService == null) {
            bindService()
            return
        }
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.START) return
            // A stop() arrived while bindService() was in flight; onServiceConnected
            // re-entered here after the bind completed. Honor that stop intent.
            if (!startRequested) return
            GlobalState.runState.value = RunState.START
            // start() returns a detached fd (service uses establish()?.detachFd()).
            // If startTun throws we own that fd and must close it, else it leaks and
            // runState would stay START with no live tun.
            val fd = aveeService?.start(options!!)
            try {
                Core.startTun(
                    fd = fd ?: 0,
                    protect = this::protect,
                    resolverProcess = this::resolverProcess,
                )
            } catch (e: Exception) {
                Log.e("VpnPlugin", "Core.startTun failed", e)
                if (fd != null && fd > 0) {
                    runCatching { ParcelFileDescriptor.adoptFd(fd).close() }
                }
                GlobalState.runState.value = RunState.STOP
                return
            }
            updateUnderlyingNetworks()
            registerScreenReceiver()
            startForegroundJob()
            // Cross-file flag read by MainActivity.maybeRequestBatteryExemption()
            // to gate the one-time, contextual battery-opt prompt after real VPN use.
            AveeApplication.getAppContext()
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("flutter.vpn_started_once", true)
                .apply()
        }
    }

    private fun protect(fd: Int): Boolean {
        return (aveeService as? AveeVpnService)?.protect(fd) == true
    }

    private fun resolverProcess(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
        uid: Int,
    ): String {
        val nextUid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
        } else {
            uid
        }
        if (nextUid == -1) {
            return ""
        }
        // Atomic compute-and-cache: the previous containsKey+put pair was a
        // check-then-act race across concurrent resolver callbacks. minSdk 24
        // guarantees ConcurrentHashMap.computeIfAbsent. The mapping lambda MUST
        // NOT return null — ConcurrentHashMap forbids null values — so the
        // `?: ""` fallback stays inside the lambda.
        return uidPageNameMap.computeIfAbsent(nextUid) {
            AveeApplication.getAppContext().packageManager?.getPackagesForUid(nextUid)
                ?.firstOrNull() ?: ""
        }
    }

    fun handleStop() {
        Log.d(
            "VpnPlugin",
            "handleStop: runState=${GlobalState.runState.value} caller=${Throwable().stackTrace.getOrNull(1)}"
        )
        startRequested = false
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.STOP) return
            GlobalState.runState.value = RunState.STOP
            aveeService?.stop()
            unregisterScreenReceiver()
            stopForegroundJob()
            Core.stopTun()
            // UID→package mappings go stale across sessions.
            uidPageNameMap.clear()
            // Fresh network-identity baseline for the next session: the first
            // snapshot after the next start must not fire a spurious close.
            lastNetworkKey = null
            // With BIND_AUTO_CREATE the binding keeps the stopped service instance
            // alive forever unless we unbind. After this isBind=false so bindService()
            // won't double-unbind; aveeService=null forces a clean rebind on next start.
            if (isBind) {
                runCatching { AveeApplication.getAppContext().unbindService(connection) }
                isBind = false
            }
            aveeService = null
            GlobalState.handleTryDestroy()
        }
    }

    private fun bindService() {
        if (isBind) {
            AveeApplication.getAppContext().unbindService(connection)
        }
        val intent = when (options?.enable == true) {
            true -> Intent(AveeApplication.getAppContext(), AveeVpnService::class.java)
            false -> Intent(AveeApplication.getAppContext(), AveeService::class.java)
        }
        AveeApplication.getAppContext().bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

    private fun showSubscriptionNotification(title: String, message: String, actionLabel: String, actionUrl: String) {
        val context = AveeApplication.getAppContext()
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel for subscription alerts (Android O+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL,
                "Subscription Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications about subscription expiration"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Create intent for action button (open URL)
        val actionIntent = Intent(Intent.ACTION_VIEW, Uri.parse(actionUrl))
        val actionPendingIntent = PendingIntent.getActivity(
            context,
            0,
            actionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create intent to open app when notification is tapped
        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            1,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, GlobalState.SUBSCRIPTION_NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .applyAveeContent(context, title, message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openAppPendingIntent)
        
        // Only add action button if actionLabel is not empty
        if (actionLabel.isNotEmpty() && actionUrl.isNotEmpty()) {
            builder.addAction(0, actionLabel, actionPendingIntent)
        }

        notificationManager.notify(GlobalState.SUBSCRIPTION_NOTIFICATION_ID, builder.build())
    }
}