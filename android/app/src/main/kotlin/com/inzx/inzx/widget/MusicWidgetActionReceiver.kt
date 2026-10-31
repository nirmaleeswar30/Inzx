package com.nirmal.inzx.widget

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioService
import com.ryanheise.audioservice.MediaButtonReceiver

class MusicWidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(InzxWidgets.PREFS, Context.MODE_PRIVATE)
        when (intent.action) {
            InzxWidgets.ACTION_PREVIOUS -> dispatchMediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            InzxWidgets.ACTION_NEXT -> dispatchMediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            InzxWidgets.ACTION_PLAY_PAUSE -> {
                val isPlaying = prefs.getBoolean(InzxWidgets.KEY_IS_PLAYING, false)
                // Flip optimistically so the glyph answers the tap immediately;
                // the player's own state sync confirms it a moment later.
                prefs.edit().putBoolean(InzxWidgets.KEY_IS_PLAYING, !isPlaying).apply()
                dispatchMediaButton(
                    context,
                    if (isPlaying) KeyEvent.KEYCODE_MEDIA_PAUSE else KeyEvent.KEYCODE_MEDIA_PLAY,
                )
            }
            // Like and Shuffle have no media-button key, so they go through the
            // media session audio_service runs (customAction / setShuffleMode).
            InzxWidgets.ACTION_LIKE -> {
                prefs.edit()
                    .putBoolean(InzxWidgets.KEY_IS_LIKED, !prefs.getBoolean(InzxWidgets.KEY_IS_LIKED, false))
                    .apply()
                withSession(context) { it.sendCustomAction("toggle_like", null) }
            }
            InzxWidgets.ACTION_SHUFFLE -> {
                val shuffle = !prefs.getBoolean(InzxWidgets.KEY_SHUFFLE, false)
                prefs.edit().putBoolean(InzxWidgets.KEY_SHUFFLE, shuffle).apply()
                withSession(context) {
                    it.setShuffleMode(
                        if (shuffle) PlaybackStateCompat.SHUFFLE_MODE_ALL else PlaybackStateCompat.SHUFFLE_MODE_NONE,
                    )
                }
            }
        }
        InzxWidgets.updateAll(context)
    }

    private fun withSession(
        context: Context,
        block: (MediaControllerCompat.TransportControls) -> Unit,
    ) {
        val pending = goAsync()
        val finished = java.util.concurrent.atomic.AtomicBoolean(false)
        fun finish() {
            if (finished.compareAndSet(false, true)) pending.finish()
        }
        var browser: MediaBrowserCompat? = null
        browser = MediaBrowserCompat(
            context,
            ComponentName(context, AudioService::class.java),
            object : MediaBrowserCompat.ConnectionCallback() {
                override fun onConnected() {
                    try {
                        browser?.let { block(MediaControllerCompat(context, it.sessionToken).transportControls) }
                    } catch (_: Exception) {
                        // Best-effort: the player may be shutting down.
                    } finally {
                        browser?.disconnect()
                        finish()
                    }
                }

                override fun onConnectionFailed() = finish()
                override fun onConnectionSuspended() = finish()
            },
            null,
        )
        browser.connect()
    }

    private fun dispatchMediaButton(context: Context, keyCode: Int) {
        sendMediaButton(context, KeyEvent.ACTION_DOWN, keyCode)
        sendMediaButton(context, KeyEvent.ACTION_UP, keyCode)
    }

    private fun sendMediaButton(context: Context, action: Int, keyCode: Int) {
        val mediaIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, MediaButtonReceiver::class.java)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(action, keyCode))
        }
        context.sendBroadcast(mediaIntent)
    }
}
