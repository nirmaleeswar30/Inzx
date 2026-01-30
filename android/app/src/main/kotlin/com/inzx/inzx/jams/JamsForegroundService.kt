package com.inzx.inzx.jams

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.inzx.inzx.MainActivity
import com.inzx.inzx.R

/**
 * Native Android Foreground Service for Jams
 * 
 * This service shows a notification while the user is in a Jam session
 * and keeps the app process alive with proper Android lifecycle.
 */
class JamsForegroundService : Service() {

    companion object {
        private const val TAG = "JamsForegroundService"
        private const val NOTIFICATION_ID = 9999
        private const val CHANNEL_ID = "jams_foreground_service"
        private const val CHANNEL_NAME = "Jams Session"

        // Actions
        const val ACTION_START = "com.inzx.inzx.jams.START"
        const val ACTION_STOP = "com.inzx.inzx.jams.STOP"
        const val ACTION_UPDATE_NOTIFICATION = "com.inzx.inzx.jams.UPDATE"

        // Extras
        const val EXTRA_SESSION_CODE = "session_code"
        const val EXTRA_IS_HOST = "is_host"
        const val EXTRA_PARTICIPANT_COUNT = "participant_count"

        var instance: JamsForegroundService? = null
            private set
        
        var isRunning: Boolean = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var sessionCode: String = ""
    private var isHost: Boolean = false
    private var participantCount: Int = 0

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        Log.d(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                sessionCode = intent.getStringExtra(EXTRA_SESSION_CODE) ?: ""
                isHost = intent.getBooleanExtra(EXTRA_IS_HOST, false)
                participantCount = intent.getIntExtra(EXTRA_PARTICIPANT_COUNT, 1)

                Log.d(TAG, "Starting foreground service for session: $sessionCode")
                
                acquireWakeLock()
                startForeground(NOTIFICATION_ID, createNotification())
                isRunning = true
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping foreground service")
                stopForegroundService()
            }
            ACTION_UPDATE_NOTIFICATION -> {
                sessionCode = intent.getStringExtra(EXTRA_SESSION_CODE) ?: sessionCode
                isHost = intent.getBooleanExtra(EXTRA_IS_HOST, isHost)
                participantCount = intent.getIntExtra(EXTRA_PARTICIPANT_COUNT, participantCount)
                
                Log.d(TAG, "Updating notification: $participantCount participants")
                updateNotification()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        releaseWakeLock()
        instance = null
        isRunning = false
        Log.d(TAG, "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopForegroundService() {
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        isRunning = false
    }

    // ============ Notification ============

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows notification while in a Jams session"
                setShowBadge(false)
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (isHost) "Hosting Jam Session" else "In Jam Session"
        val text = if (participantCount > 0) {
            "Code: $sessionCode • $participantCount participant${if (participantCount > 1) "s" else ""}"
        } else {
            "Code: $sessionCode • Tap to return"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun updateNotification() {
        val notification = createNotification()
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    // ============ Wake Lock ============

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Inzx:JamsWakeLock"
            ).apply {
                acquire(4 * 60 * 60 * 1000L) // 4 hours max
            }
            Log.d(TAG, "Wake lock acquired")
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "Wake lock released")
            }
        }
        wakeLock = null
    }
}
