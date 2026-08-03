package com.avee.vpn

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.MutableLiveData
import com.avee.vpn.plugins.AppPlugin
import com.avee.vpn.plugins.TilePlugin
import com.avee.vpn.plugins.VpnPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

enum class RunState {
    START,
    PENDING,
    STOP
}


object GlobalState {
    val runLock = ReentrantLock()

    const val NOTIFICATION_CHANNEL = "avee"
    const val SUBSCRIPTION_NOTIFICATION_CHANNEL = "avee_Subscription"

    const val NOTIFICATION_ID = 1
    const val SUBSCRIPTION_NOTIFICATION_ID = 2

    val runState: MutableLiveData<RunState> = MutableLiveData<RunState>(RunState.STOP)
    // Current clash mode — "rule", "global" or "direct". Pushed from Dart via
    // TilePlugin.updateMode() so the home-screen widget can highlight the
    // active button without duplicating state.
    val currentMode: MutableLiveData<String> = MutableLiveData<String>("rule")
    // Whether the Global mode button should be shown in the widget.
    // Reflects the `flclashx-globalmode` subscription header — pushed from Dart.
    val globalModeEnabled: MutableLiveData<Boolean> = MutableLiveData<Boolean>(true)
    var flutterEngine: FlutterEngine? = null
    private var serviceEngine: FlutterEngine? = null

    fun getCurrentAppPlugin(): AppPlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(AppPlugin::class.java) as AppPlugin?
    }

    fun syncStatus() {
        CoroutineScope(Dispatchers.Default).launch {
            // runState is the synchronous source of truth for the tile; this Dart
            // round-trip is enrichment only and must never clobber a live START.
            // Bail when the status is indeterminate (no service engine → VPNPlugin
            // null, or null reply) and never overwrite an in-flight PENDING.
            //
            // START is set/cleared ONLY by handleStart/handleStop/onRevoke. We do
            // NOT downgrade START -> STOP from here: with the service engine now
            // surviving an app reopen, the "status" round-trip may be answered by
            // the MAIN isolate (the "vpn" channel is last-wins), which cannot see
            // the core session and always replies false. Honoring that false used
            // to clobber a live START, turning handleStop() into a no-op (its STOP
            // idempotency gate) so the user could not disconnect. runState is
            // in-memory, so process death already resets it to STOP — an upgrade to
            // START from a truthful service-isolate reply is the only useful action.
            val status = getCurrentVPNPlugin()?.getStatus() ?: return@launch
            withContext(Dispatchers.Main) {
                if (runState.value == RunState.PENDING) return@withContext
                if (status) {
                    runState.value = RunState.START
                }
            }
        }
    }
    
    fun hasActiveProfile(): Boolean {
        val prefs = AveeApplication.getAppContext()
            .getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
        val configJson = prefs.getString("flutter.config", null)
        
        if (configJson != null) {
            try {
                val config = org.json.JSONObject(configJson)
                val currentProfileId = config.optString("currentProfileId", null)
                Log.d("GlobalState", "hasActiveProfile: currentProfileId=$currentProfileId")
                return !currentProfileId.isNullOrEmpty()
            } catch (e: Exception) {
                Log.e("GlobalState", "Error parsing config: ${e.message}")
                return false
            }
        }
        Log.d("GlobalState", "hasActiveProfile: no config found")
        return false
    }

    suspend fun getText(text: String): String {
        return getCurrentAppPlugin()?.getText(text) ?: ""
    }

    fun getCurrentTilePlugin(): TilePlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(TilePlugin::class.java) as TilePlugin?
    }

    fun getCurrentVPNPlugin(): VpnPlugin? {
        return serviceEngine?.plugins?.get(VpnPlugin::class.java) as VpnPlugin?
    }

    fun handleToggle() {
        val starting = handleStart()
        if (!starting) {
            handleStop()
        }
    }

    /**
     * Request a mode switch. Routes through TilePlugin to the Dart side
     * (either the main engine if the app is open, or the background service
     * engine), which updates patchClashConfig and pushes the change to core.
     * Safe to call when the service engine is not yet alive — the method
     * spins it up and queues the request via a pending action, mirroring
     * how handleStart() works.
     */
    fun handleChangeMode(mode: String) {
        Log.d("GlobalState", "handleChangeMode: $mode")
        val tilePlugin = getCurrentTilePlugin()
        if (tilePlugin != null) {
            tilePlugin.handleChangeMode(mode)
            // Optimistically reflect the new mode on the widget — Dart will
            // confirm with updateMode() when the patch lands in core.
            currentMode.postValue(mode)
        } else {
            TilePlugin.setPendingMode(mode)
            initServiceEngine()
        }
    }

    fun handleStart(): Boolean {
        Log.d("GlobalState", "handleStart called, current runState: ${runState.value}")
        if (runState.value == RunState.STOP) {
            Log.d("GlobalState", "Setting runState to PENDING")
            runState.value = RunState.PENDING
            runLock.withLock {
                val tilePlugin = getCurrentTilePlugin()
                Log.d("GlobalState", "TilePlugin: $tilePlugin, flutterEngine: $flutterEngine, serviceEngine: $serviceEngine")
                if (tilePlugin != null) {
                    Log.d("GlobalState", "TilePlugin exists, calling handleStart()")
                    tilePlugin.handleStart()
                } else {
                    Log.d("GlobalState", "No TilePlugin, setting pending action and calling initServiceEngine()")
                    // Set pending action BEFORE initializing service engine
                    // When Dart is ready, it will call serviceReady() which triggers the pending action
                    TilePlugin.setPendingAction(TilePlugin.Companion.PendingAction.START)
                    initServiceEngine()
                }
            }
            return true
        }
        Log.d("GlobalState", "handleStart: runState is not STOP, ignoring")
        return false
    }

    fun handleStop() {
        Log.d("GlobalState", "handleStop called, current runState: ${runState.value}")
        if (runState.value == RunState.START) {
            runState.value = RunState.PENDING
            runLock.withLock {
                val tilePlugin = getCurrentTilePlugin()
                if (tilePlugin != null) {
                    tilePlugin.handleStop()
                } else {
                    Log.d("GlobalState", "No TilePlugin for stop, setting pending action")
                    TilePlugin.setPendingAction(TilePlugin.Companion.PendingAction.STOP)
                    initServiceEngine()
                }
            }
        }
    }

    fun handleTryDestroy() {
        if (flutterEngine == null) {
            destroyServiceEngine()
        }
    }

    fun destroyServiceEngine() {
        // Belt-and-braces guard for bug 1a: never destroy the service engine
        // while the VPN is live. The primary fix reattaches the Dart bridge to
        // the running service isolate (re-handshake) instead of destroying it;
        // this refuses the destroy even if some path still requests it, so the
        // engine hosting the live tunnel/core survives an app reopen.
        if (runState.value == RunState.START) {
            Log.w("GlobalState", "destroyServiceEngine refused: runState=START (VPN live)")
            return
        }
        runLock.withLock {
            serviceEngine?.destroy()
            serviceEngine = null
        }
    }

    fun initServiceEngine() {
        Log.d(
            "GlobalState",
            "initServiceEngine called, serviceEngine=$serviceEngine, mainEngine=$flutterEngine"
        )
        if (serviceEngine != null) {
            Log.d("GlobalState", "serviceEngine already exists, returning")
            return
        }
        // Defer to next main looper cycle: executeDartEntrypoint runs synchronously
        // on the platform thread, and if called during MainActivity.onCreate it can
        // starve main FlutterEngine's own Dart main() bootstrap — root cause of the
        // cold-start splash hang. Posting lets MainActivity finish onCreate and
        // FlutterActivity schedule its default entrypoint first.
        if (flutterEngine != null) {
            Log.w(
                "GlobalState",
                "initServiceEngine deferred (main engine alive). Caller:",
                Throwable()
            )
            Handler(Looper.getMainLooper()).post { initServiceEngineNow() }
            return
        }
        initServiceEngineNow()
    }

    private fun initServiceEngineNow() {
        if (serviceEngine != null) {
            Log.d("GlobalState", "initServiceEngineNow: already created, skipping")
            return
        }
        destroyServiceEngine()
        runLock.withLock {
            Log.d("GlobalState", "Creating new serviceEngine")
            serviceEngine = FlutterEngine(AveeApplication.getAppContext())
            Log.d("GlobalState", "Registering plugins")
            io.flutter.plugins.GeneratedPluginRegistrant.registerWith(serviceEngine!!)
            serviceEngine?.plugins?.add(VpnPlugin)
            serviceEngine?.plugins?.add(AppPlugin())
            serviceEngine?.plugins?.add(TilePlugin())
            val vpnService = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "_service"
            )
            val args = if (flutterEngine == null) listOf("quick") else null
            Log.d("GlobalState", "Executing _service entrypoint with args: $args")
            serviceEngine?.dartExecutor?.executeDartEntrypoint(
                vpnService,
                args
            )
            Log.d("GlobalState", "serviceEngine initialized successfully")
        }
    }
}


