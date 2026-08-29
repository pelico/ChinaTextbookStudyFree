package com.cstf.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.wifi.WifiManager
import androidx.core.app.NotificationCompat

/**
 * 音频播放前台服务
 *
 * 作用：WebView 里的 HTML5 Audio 在熄屏/后台时容易卡顿或被系统挂起。
 * 启动这个前台服务后：
 *   1. 持有 PARTIAL_WAKE_LOCK，保持 CPU 运行（即使熄屏）
 *   2. 持有 WifiLock，保持 Wi-Fi 连接不被休眠
 *   3. 作为前台服务驻留，降低 APP 被系统回收的概率
 *
 * 由 Web 页面通过 JS Bridge 通知播放/停止状态来启停服务。
 */
class AudioPlaybackService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    companion object {
        const val CHANNEL_ID = "audio_playback_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.cstf.app.START_PLAYBACK"
        const val ACTION_STOP = "com.cstf.app.STOP_PLAYBACK"
        const val EXTRA_TITLE = "title"

        fun start(context: Context, title: String = "正在播放") {
            val intent = Intent(context, AudioPlaybackService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, AudioPlaybackService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "正在播放"
                startForeground(NOTIFICATION_ID, buildNotification(title))
                acquireLocks()
            }
            ACTION_STOP -> {
                releaseLocks()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireLocks() {
        // WakeLock：保持 CPU 运行
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CSTF:AudioPlaybackLock"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }

        // WifiLock：保持 Wi-Fi 连接
        if (wifiLock == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wm.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "CSTF:AudioWifiLock"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        wakeLock?.let {
            if (it.isHeld) it.release()
            wakeLock = null
        }
        wifiLock?.let {
            if (it.isHeld) it.release()
            wifiLock = null
        }
    }

    private fun buildNotification(title: String): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("中国学习助手 - 后台播放中")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "音频播放",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "后台音频播放保活"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
