package com.avee.vpn.services

import android.annotation.SuppressLint
import android.app.Notification
import android.app.Notification.FOREGROUND_SERVICE_IMMEDIATE
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED
import android.net.VpnService
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import com.avee.vpn.GlobalState
import com.avee.vpn.MainActivity
import com.avee.vpn.R
import com.avee.vpn.extensions.getActionPendingIntent
import com.avee.vpn.models.VpnOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async

interface BaseServiceInterface {

    fun start(options: VpnOptions): Int

    fun stop()

    suspend fun startForeground(title: String, server: String?, content: String)
}

/** Prefer larger notification typography on tablets / large screens. */
fun Context.aveeNotificationLayoutId(): Int {
    val shortest = resources.configuration.smallestScreenWidthDp
    return if (shortest >= 600) R.layout.notification_avee_tablet else R.layout.notification_avee
}

fun Context.aveeNotificationRemoteViews(
    title: String,
    content: String,
    sub: String? = null,
): RemoteViews {
    val views = RemoteViews(packageName, aveeNotificationLayoutId())
    views.setTextViewText(R.id.notification_title, title)
    views.setTextViewText(R.id.notification_content, content)
    if (sub.isNullOrBlank()) {
        views.setViewVisibility(R.id.notification_sub, View.GONE)
    } else {
        views.setViewVisibility(R.id.notification_sub, View.VISIBLE)
        views.setTextViewText(R.id.notification_sub, sub)
    }
    return views
}

fun NotificationCompat.Builder.applyAveeContent(
    context: Context,
    title: String,
    content: String,
    sub: String? = null,
): NotificationCompat.Builder {
    val views = context.aveeNotificationRemoteViews(title, content, sub)
    setContentTitle(title)
    setContentText(content)
    if (!sub.isNullOrBlank()) {
        setSubText(sub)
    }
    setCustomContentView(views)
    setStyle(NotificationCompat.DecoratedCustomViewStyle())
    return this
}

fun Service.createAveeNotificationBuilder(): Deferred<NotificationCompat.Builder> =
    CoroutineScope(Dispatchers.Main).async {
        val stopText = GlobalState.getText("stop")
        val intent = Intent(this@createAveeNotificationBuilder, MainActivity::class.java)

        val pendingIntent = if (Build.VERSION.SDK_INT >= 31) {
            PendingIntent.getActivity(
                this@createAveeNotificationBuilder,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getActivity(
                this@createAveeNotificationBuilder, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        with(
            NotificationCompat.Builder(
                this@createAveeNotificationBuilder, GlobalState.NOTIFICATION_CHANNEL
            )
        ) {
            setSmallIcon(R.drawable.ic_launcher_monochrome)
            applyAveeContent(this@createAveeNotificationBuilder, "AVEE", "")
            setContentIntent(pendingIntent)
            setCategory(NotificationCompat.CATEGORY_SERVICE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                foregroundServiceBehavior = FOREGROUND_SERVICE_IMMEDIATE
            }
            setOngoing(true)
            addAction(
                0, stopText, getActionPendingIntent("STOP")
            )
            setShowWhen(false)
            setOnlyAlertOnce(true)
        }
    }

@SuppressLint("ForegroundServiceType")
fun Service.startForeground(notification: Notification) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val manager = getSystemService(NotificationManager::class.java)
        var channel = manager?.getNotificationChannel(GlobalState.NOTIFICATION_CHANNEL)
        if (channel == null) {
            channel = NotificationChannel(
                GlobalState.NOTIFICATION_CHANNEL, "SERVICE_CHANNEL", NotificationManager.IMPORTANCE_LOW
            )
            manager?.createNotificationChannel(channel)
        }
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        // VpnService subclasses must use SYSTEM_EXEMPTED so they are not
        // killed by the Android 15+ dataSync 6h cumulative FGS timeout
        // (ForegroundServiceDidNotStopInTimeException). Plain background
        // services keep DATA_SYNC. The chosen type MUST match the
        // foregroundServiceType declared in AndroidManifest.xml for the
        // concrete service class.
        val fgsType = if (this is VpnService) {
            FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED
        } else {
            FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        try {
            startForeground(GlobalState.NOTIFICATION_ID, notification, fgsType)
        } catch (_: Exception) {
            startForeground(GlobalState.NOTIFICATION_ID, notification)
        }
    } else {
        startForeground(GlobalState.NOTIFICATION_ID, notification)
    }
}