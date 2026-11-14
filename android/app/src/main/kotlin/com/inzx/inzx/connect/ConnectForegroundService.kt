package com.nirmal.inzx.connect

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.nirmal.inzx.MainActivity
import com.nirmal.inzx.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class ConnectForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "inzx_connect"
        private const val NOTIFICATION_ID = 10001
        private const val SHOW = "com.nirmal.inzx.connect.SHOW"
        private const val DISCONNECT = "com.nirmal.inzx.connect.DISCONNECT"
        private const val PLAY = "com.nirmal.inzx.connect.PLAY"
        private const val PAUSE = "com.nirmal.inzx.connect.PAUSE"
        private const val PREVIOUS = "com.nirmal.inzx.connect.PREVIOUS"
        private const val NEXT = "com.nirmal.inzx.connect.NEXT"
        private var bridge: MethodChannel? = null
        private var activeService: ConnectForegroundService? = null

        fun attach(context: Context, messenger: BinaryMessenger) {
            bridge = MethodChannel(messenger, "inzx/connect_background").apply {
                setMethodCallHandler { call, result ->
                    val intent = Intent(context, ConnectForegroundService::class.java)
                    when (call.method) {
                        "show" -> {
                            intent.action = SHOW
                            for (key in listOf("id", "track", "artist", "device", "artwork")) {
                                intent.putExtra(key, call.argument<String>(key))
                            }
                            for (key in listOf("playing", "buffering")) {
                                intent.putExtra(key, call.argument<Boolean>(key) == true)
                            }
                            for (key in listOf("duration", "position")) {
                                intent.putExtra(key, call.argument<Number>(key)?.toLong() ?: 0L)
                            }
                            intent.putExtra("speed", call.argument<Number>("speed")?.toFloat() ?: 1f)
                            try {
                                val running = activeService
                                if (running == null) {
                                    ContextCompat.startForegroundService(context, intent)
                                } else {
                                    running.show(intent)
                                }
                                result.success(true)
                            } catch (error: RuntimeException) {
                                result.error("foreground_start", error.message, null)
                            }
                        }
                        "stop" -> {
                            context.stopService(intent)
                            result.success(null)
                        }
                        "keepAwake" -> {
                            activeService?.keepAwake()
                            result.success(null)
                        }
                        "artwork" -> {
                            val id = call.argument<String>("id")
                            val path = call.argument<String>("path")
                            val url = call.argument<String>("url")
                            if (id != null && path != null && url != null) {
                                activeService?.updateArtwork(id, url, path)
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        }
    }

    private var session: MediaSession? = null
    private var currentState: Intent? = null
    private var artwork: Bitmap? = null

    private val wakeLock by lazy {
        getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Inzx:Connect")
            .apply { setReferenceCounted(false) }
    }

    private fun keepAwake() {
        // Each desktop heartbeat renews this, including while the PC is paused.
        wakeLock.acquire(30_000L)
    }

    override fun onCreate() {
        super.onCreate()
        session = MediaSession(this, "Inzx Connect").apply {
            setPlaybackToRemote(object : VolumeProvider(VolumeProvider.VOLUME_CONTROL_FIXED, 1, 1) {})
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { bridge?.invokeMethod("play", null) }
                override fun onPause() { bridge?.invokeMethod("pause", null) }
                override fun onSkipToPrevious() { bridge?.invokeMethod("previous", null) }
                override fun onSkipToNext() { bridge?.invokeMethod("next", null) }
                override fun onSeekTo(pos: Long) { bridge?.invokeMethod("seek", pos) }
                override fun onCustomAction(action: String, extras: android.os.Bundle?) {
                    if (action == DISCONNECT) disconnect()
                }
            })
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Inzx Connect", NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            SHOW -> show(intent)
            PLAY -> bridge?.invokeMethod("play", null)
            PAUSE -> bridge?.invokeMethod("pause", null)
            PREVIOUS -> bridge?.invokeMethod("previous", null)
            NEXT -> bridge?.invokeMethod("next", null)
            DISCONNECT -> disconnect()
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (activeService === this) activeService = null
        session?.release()
        session = null
        if (wakeLock.isHeld) wakeLock.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun disconnect() {
        bridge?.invokeMethod("disconnect", null)
        stopSelf()
    }

    private fun updateArtwork(id: String, url: String, path: String) {
        val state = currentState ?: return
        if (id != state.getStringExtra("id") || url != state.getStringExtra("artwork")) return
        artwork = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = 2 })
        val playback = session?.controller?.playbackState
        if (playback?.state == PlaybackState.STATE_PLAYING) {
            val elapsed = SystemClock.elapsedRealtime() - playback.lastPositionUpdateTime
            val position = playback.position + (elapsed * playback.playbackSpeed).toLong()
            val duration = state.getLongExtra("duration", 0L)
            state.putExtra("position", if (duration > 0) position.coerceAtMost(duration) else position)
        }
        show(state)
    }

    private fun show(state: Intent) {
        if (currentState?.getStringExtra("artwork") != state.getStringExtra("artwork")) {
            artwork = null
        }
        currentState = state
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openApp = PendingIntent.getActivity(this, NOTIFICATION_ID, open, PendingIntent.FLAG_IMMUTABLE)
        val playing = state.getBooleanExtra("playing", false)
        val buffering = state.getBooleanExtra("buffering", false)
        val device = state.getStringExtra("device").orEmpty()
        val artist = state.getStringExtra("artist").orEmpty()
        val title = state.getStringExtra("track") ?: "Inzx Connect"
        val mediaSession = session ?: return
        mediaSession.setSessionActivity(openApp)
        mediaSession.setMetadata(MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_MEDIA_ID, state.getStringExtra("id"))
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, artist)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_DESCRIPTION, device)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, state.getLongExtra("duration", 0L))
            .putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, artwork)
            .build())
        mediaSession.setPlaybackState(PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SEEK_TO
            )
            .setState(
                when {
                    playing && buffering -> PlaybackState.STATE_BUFFERING
                    playing -> PlaybackState.STATE_PLAYING
                    else -> PlaybackState.STATE_PAUSED
                },
                state.getLongExtra("position", 0L),
                if (playing && !buffering) state.getFloatExtra("speed", 1f) else 0f
            )
            .addCustomAction(DISCONNECT, "Disconnect", android.R.drawable.ic_menu_close_clear_cancel)
            .build())
        mediaSession.isActive = true
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, CHANNEL_ID)
        } else {
            android.app.Notification.Builder(this)
        }
        @Suppress("DEPRECATION")
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(device)
            .setLargeIcon(artwork)
            .setContentIntent(openApp)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(android.app.Notification.CATEGORY_TRANSPORT)
            .setVisibility(android.app.Notification.VISIBILITY_PRIVATE)
            .addAction(android.R.drawable.ic_media_previous, "Previous", action(PREVIOUS, 1))
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Pause" else "Play",
                action(if (playing) PAUSE else PLAY, 2)
            )
            .addAction(android.R.drawable.ic_media_next, "Next", action(NEXT, 3))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", action(DISCONNECT, 4))
            .setStyle(android.app.Notification.MediaStyle()
                .setMediaSession(mediaSession.sessionToken)
                .setShowActionsInCompactView(0, 1, 2))
            .build()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0
        )
        activeService = this
        keepAwake()
    }

    private fun action(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, ConnectForegroundService::class.java).setAction(action)
        return PendingIntent.getService(this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE)
    }
}
