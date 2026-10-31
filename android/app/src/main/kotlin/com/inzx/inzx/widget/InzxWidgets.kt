package com.nirmal.inzx.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.TypedValue
import android.widget.RemoteViews
import com.nirmal.inzx.MainActivity
import com.nirmal.inzx.R
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/** 2×2 — cover with a blurred foot, title and transport. */
class InzxWidgetSquare : InzxWidgetProvider()

/** 4×2 — cover with a blurred foot, title/artist beside the transport. */
class InzxWidgetWide : InzxWidgetProvider()

/** 4×1 — a capsule: round cover, title, Like / previous / play / next / Shuffle. */
class InzxWidgetPill : InzxWidgetProvider()

open class InzxWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        InzxWidgets.update(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        InzxWidgets.update(context, intArrayOf(appWidgetId))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == InzxWidgets.ACTION_REFRESH) InzxWidgets.updateAll(context)
    }
}

/**
 * Shared state and rendering for the three widgets. Playback state arrives
 * from Dart over the `inzx/widget` channel ([saveState]); rendering (which
 * bakes bitmaps) runs on a background thread so the launcher never waits on it.
 */
object InzxWidgets {
    const val ACTION_REFRESH = "com.nirmal.inzx.widget.REFRESH"
    const val ACTION_PREVIOUS = "com.nirmal.inzx.widget.PREVIOUS"
    const val ACTION_PLAY_PAUSE = "com.nirmal.inzx.widget.PLAY_PAUSE"
    const val ACTION_NEXT = "com.nirmal.inzx.widget.NEXT"
    const val ACTION_LIKE = "com.nirmal.inzx.widget.LIKE"
    const val ACTION_SHUFFLE = "com.nirmal.inzx.widget.SHUFFLE"

    const val PREFS = "music_widget_prefs"
    const val KEY_IS_PLAYING = "is_playing"
    const val KEY_IS_LIKED = "is_liked"
    const val KEY_SHUFFLE = "shuffle"
    private const val KEY_TRACK_ID = "track_id"
    private const val KEY_TITLE = "title"
    private const val KEY_ARTIST = "artist"
    private const val KEY_HAS_TRACK = "has_track"
    private const val KEY_ARTWORK_PATH = "artwork_path"

    /** Width (dp) at which the square widget switches to the wide layout. */
    private const val WIDE_LAYOUT_MIN_DP = 230

    /** The 4×2 sets wider type on a lighter blur than the 2×2. */
    private const val WIDE_BLUR_STRENGTH = 0.5f

    private val worker: Handler by lazy {
        Handler(HandlerThread("InzxWidgets").apply { start() }.looper)
    }

    // ── State ────────────────────────────────────────────────────────────

    fun saveState(context: Context, args: Map<*, *>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        val previousTrackId = prefs.getString(KEY_TRACK_ID, null)
        val incomingTrackId = args["trackId"] as? String
        if (args.containsKey("trackId") && incomingTrackId != previousTrackId) {
            prefs.getString(KEY_ARTWORK_PATH, null)?.let { runCatching { File(it).delete() } }
            editor.remove(KEY_ARTWORK_PATH)
            InzxWidgetArt.clear()
            editor.putString(KEY_TRACK_ID, incomingTrackId)
        }
        (args["title"] as? String)?.let { editor.putString(KEY_TITLE, it) }
        if (args.containsKey("artist")) editor.putString(KEY_ARTIST, args["artist"] as? String ?: "")
        (args["isPlaying"] as? Boolean)?.let { editor.putBoolean(KEY_IS_PLAYING, it) }
        (args["hasTrack"] as? Boolean)?.let { editor.putBoolean(KEY_HAS_TRACK, it) }
        (args["isLiked"] as? Boolean)?.let { editor.putBoolean(KEY_IS_LIKED, it) }
        (args["shuffle"] as? Boolean)?.let { editor.putBoolean(KEY_SHUFFLE, it) }
        (args["artBytes"] as? ByteArray)?.takeIf { it.isNotEmpty() }?.let { bytes ->
            saveArtwork(context, incomingTrackId ?: previousTrackId ?: "current", bytes)
                ?.let { editor.putString(KEY_ARTWORK_PATH, it) }
        }
        editor.apply()
    }

    private fun saveArtwork(context: Context, trackId: String, bytes: ByteArray): String? = runCatching {
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        // Big enough for a 4×2 widget on a dense screen, small enough to bake fast.
        val side = 1200
        val scale = side.toFloat() / max(decoded.width, decoded.height)
        val scaled = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).roundToInt(),
                (decoded.height * scale).roundToInt(),
                true,
            )
        } else {
            decoded
        }
        val dir = File(context.cacheDir, "widget_art").apply { mkdirs() }
        val file = File(dir, trackId.replace(Regex("[^A-Za-z0-9._-]"), "_") + ".jpg")
        FileOutputStream(file).use { scaled.compress(Bitmap.CompressFormat.JPEG, 95, it) }
        if (scaled !== decoded) decoded.recycle()
        scaled.recycle()
        file.absolutePath
    }.getOrNull()

    // ── Rendering ────────────────────────────────────────────────────────

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = listOf(InzxWidgetSquare::class.java, InzxWidgetWide::class.java, InzxWidgetPill::class.java)
            .flatMap { manager.getAppWidgetIds(ComponentName(context, it)).toList() }
        if (ids.isNotEmpty()) update(context, ids.toIntArray())
    }

    fun update(context: Context, ids: IntArray) {
        val app = context.applicationContext
        worker.post {
            val manager = AppWidgetManager.getInstance(app)
            ids.forEach { id -> runCatching { render(app, manager, id) } }
        }
    }

    private fun render(context: Context, manager: AppWidgetManager, id: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hasTrack = prefs.getBoolean(KEY_HAS_TRACK, false)
        val title = if (hasTrack) {
            prefs.getString(KEY_TITLE, null).orEmpty()
        } else {
            context.getString(R.string.widget_inzx_not_playing)
        }
        val artist = if (hasTrack) prefs.getString(KEY_ARTIST, null).orEmpty() else "Inzx"
        val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
        val trackKey = prefs.getString(KEY_TRACK_ID, null) ?: "none"
        val artwork = prefs.getString(KEY_ARTWORK_PATH, null)
            ?.takeIf { hasTrack }
            ?.let { runCatching { BitmapFactory.decodeFile(it) }.getOrNull() }

        val provider = manager.getAppWidgetInfo(id)?.provider?.className
        val options = manager.getAppWidgetOptions(id)
        val density = context.resources.displayMetrics.density
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)

        val views = when {
            provider == InzxWidgetPill::class.java.name ->
                pillViews(context, title, isPlaying, prefs, artwork, trackKey, widthDp, density)
            provider == InzxWidgetWide::class.java.name || widthDp >= WIDE_LAYOUT_MIN_DP ->
                coverViews(context, R.layout.widget_inzx_wide, R.dimen.widget_inzx_blur_wide,
                    title, artist, isPlaying, artwork, trackKey, widthDp, heightDp, density,
                    blurStrength = WIDE_BLUR_STRENGTH)
            else ->
                coverViews(context, R.layout.widget_inzx_square, R.dimen.widget_inzx_blur_square,
                    title, null, isPlaying, artwork, trackKey, widthDp, heightDp, density)
        }
        artwork?.recycle()
        manager.updateAppWidget(id, views)
    }

    private fun coverViews(
        context: Context,
        layout: Int,
        blurDimen: Int,
        title: String,
        artist: String?,
        isPlaying: Boolean,
        artwork: Bitmap?,
        trackKey: String,
        widthDp: Int,
        heightDp: Int,
        density: Float,
        blurStrength: Float = 1f,
    ): RemoteViews = RemoteViews(context.packageName, layout).apply {
        setTextViewText(R.id.widget_title, title)
        if (artist != null) setTextViewText(R.id.widget_artist, artist)
        bindTransport(context, this, isPlaying)
        setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))

        if (artwork != null && widthDp > 0 && heightDp > 0) {
            // Cap the bitmap so RemoteViews stays under the launcher's memory limit.
            val scale = minOf(density, 1200f / widthDp, 1200f / heightDp)
            val w = (widthDp * scale).roundToInt()
            val h = (heightDp * scale).roundToInt()
            val blur = (context.resources.getDimension(blurDimen) * scale / density).roundToInt()
            val radius = widgetCornerRadius(context) * scale / density
            setImageViewBitmap(
                R.id.widget_art,
                InzxWidgetArt.cover(artwork, trackKey, w, h, blur, radius, blurStrength),
            )
        } else {
            setImageViewBitmap(R.id.widget_art, null)
        }
    }

    private fun pillViews(
        context: Context,
        title: String,
        isPlaying: Boolean,
        prefs: android.content.SharedPreferences,
        artwork: Bitmap?,
        trackKey: String,
        widthDp: Int,
        density: Float,
    ): RemoteViews = RemoteViews(context.packageName, R.layout.widget_inzx_pill).apply {
        setTextViewText(R.id.widget_title, title)
        bindTransport(context, this, isPlaying)
        setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))

        val liked = prefs.getBoolean(KEY_IS_LIKED, false)
        setImageViewResource(
            R.id.widget_like,
            if (liked) R.drawable.ic_inzx_widget_heart_filled else R.drawable.ic_inzx_widget_heart,
        )
        setOnClickPendingIntent(R.id.widget_like, actionIntent(context, ACTION_LIKE, 204))

        val shuffle = prefs.getBoolean(KEY_SHUFFLE, false)
        setInt(
            R.id.widget_shuffle,
            "setBackgroundResource",
            if (shuffle) R.drawable.widget_inzx_toggle_on else R.drawable.widget_inzx_button,
        )
        setOnClickPendingIntent(R.id.widget_shuffle, actionIntent(context, ACTION_SHUFFLE, 205))

        if (artwork != null) {
            val artPx = context.resources.getDimensionPixelSize(R.dimen.widget_inzx_pill_art)
            setImageViewBitmap(R.id.widget_art, InzxWidgetArt.circle(artwork, trackKey, artPx))
            if (widthDp > 0) {
                val heightPx = context.resources.getDimensionPixelSize(R.dimen.widget_inzx_pill_height)
                val widthPx = (widthDp * density).roundToInt().coerceAtMost(1400)
                setImageViewBitmap(R.id.widget_pill_bg, InzxWidgetArt.pill(artwork, trackKey, widthPx, heightPx))
            }
        } else {
            setImageViewBitmap(R.id.widget_art, null)
            setImageViewBitmap(R.id.widget_pill_bg, null)
        }
    }

    private fun bindTransport(context: Context, views: RemoteViews, isPlaying: Boolean) {
        views.setImageViewResource(
            R.id.widget_toggle,
            if (isPlaying) R.drawable.ic_inzx_widget_pause else R.drawable.ic_inzx_widget_play,
        )
        views.setOnClickPendingIntent(R.id.widget_previous, actionIntent(context, ACTION_PREVIOUS, 201))
        views.setOnClickPendingIntent(R.id.widget_toggle, actionIntent(context, ACTION_PLAY_PAUSE, 202))
        views.setOnClickPendingIntent(R.id.widget_next, actionIntent(context, ACTION_NEXT, 203))
    }

    private fun widgetCornerRadius(context: Context): Float {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            runCatching {
                return context.resources.getDimension(android.R.dimen.system_app_widget_background_radius)
            }
        }
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 22f, context.resources.displayMetrics)
    }

    private fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        200,
        Intent(context, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun actionIntent(context: Context, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, MusicWidgetActionReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
