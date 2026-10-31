package com.nirmal.inzx.widget

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.util.LruCache
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Bitmaps the widgets draw. RemoteViews can't blur, clip or shade anything at
 * runtime, so every effect is baked here once per track and size and cached:
 *
 *  - [cover]: the artwork filling the whole widget with rounded corners, its
 *    foot melting into a blur and a soft scrim for the title and transport.
 *  - [circle]: the artwork cut to a circle (the 4×1 capsule's cover).
 *  - [pill]: the artwork blurred down to its colours and darkened, cut to a
 *    capsule — the 4×1 widget's body.
 */
object InzxWidgetArt {

    private val cache = object : LruCache<String, Bitmap>(12 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }

    fun clear() = cache.evictAll()

    fun cover(
        source: Bitmap,
        key: String,
        widthPx: Int,
        heightPx: Int,
        blurPx: Int,
        radiusPx: Float,
        blurStrength: Float = 1f,
    ): Bitmap =
        cached("cover|$key|$widthPx|$heightPx|$blurPx|$blurStrength") {
            val out = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            canvas.drawCentreCropped(source, widthPx, heightPx)
            canvas.blurFoot(out, blurPx, blurStrength)
            canvas.scrimFoot(widthPx, heightPx, blurPx)
            out.roundedCorners(radiusPx)
        }

    fun circle(source: Bitmap, key: String, sizePx: Int): Bitmap =
        cached("circle|$key|$sizePx") {
            val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                shader = centreCropShader(source, sizePx, sizePx)
            }
            canvas.drawOval(RectF(0f, 0f, sizePx.toFloat(), sizePx.toFloat()), paint)
            out
        }

    fun pill(source: Bitmap, key: String, widthPx: Int, heightPx: Int): Bitmap =
        cached("pill|$key|$widthPx|$heightPx") {
            // Blur on a tiny working copy: only the colours should survive.
            val workW = 48
            val workH = max(8, (workW * heightPx.toFloat() / widthPx).roundToInt())
            val small = Bitmap.createBitmap(workW, workH, Bitmap.Config.ARGB_8888)
            Canvas(small).drawCentreCropped(source, workW, workH)
            boxBlur(small, radius = 6, passes = 3)

            val body = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(body)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                shader = BitmapShader(small, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                    setLocalMatrix(Matrix().apply {
                        setScale(widthPx / workW.toFloat(), heightPx / workH.toFloat())
                    })
                }
                alpha = PILL_ALPHA
            }
            val capsule = RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat())
            val radius = heightPx / 2f
            canvas.drawRoundRect(capsule, radius, radius, paint)
            // Darken just enough for white text to hold on any cover.
            canvas.drawRoundRect(
                capsule, radius, radius,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(70, 0, 0, 0) },
            )
            small.recycle()
            body
        }

    private inline fun cached(key: String, make: () -> Bitmap): Bitmap {
        cache.get(key)?.let { if (!it.isRecycled) return it }
        return make().also { cache.put(key, it) }
    }

    private fun centreCropShader(src: Bitmap, w: Int, h: Int): BitmapShader {
        val scale = max(w / src.width.toFloat(), h / src.height.toFloat())
        val dx = (w - src.width * scale) / 2f
        val dy = (h - src.height * scale) / 2f
        return BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
            setLocalMatrix(Matrix().apply {
                setScale(scale, scale)
                postTranslate(dx, dy)
            })
        }
    }

    private fun Canvas.drawCentreCropped(src: Bitmap, w: Int, h: Int) {
        val scale = max(w / src.width.toFloat(), h / src.height.toFloat())
        val cropW = (w / scale).roundToInt().coerceAtMost(src.width)
        val cropH = (h / scale).roundToInt().coerceAtMost(src.height)
        val left = (src.width - cropW) / 2
        val top = (src.height - cropH) / 2
        drawBitmap(
            src,
            Rect(left, top, left + cropW, top + cropH),
            Rect(0, 0, w, h),
            Paint(Paint.FILTER_BITMAP_FLAG),
        )
    }

    /**
     * Blurs the bottom [blurPx] of [art] — exactly the strip the title and
     * transport occupy, so the blur ends at the top of the text instead of
     * eating into the cover. Two gently blurred copies are laid over it, each
     * fading in from the strip's top edge, so the start of the blur is a soft
     * transition rather than a hard line.
     */
    private fun Canvas.blurFoot(art: Bitmap, blurPx: Int, strength: Float) {
        val w = art.width
        val h = art.height
        val regionH = blurPx.coerceIn(1, h)
        val regionTop = h - regionH
        // Sample a little above the strip so the blur has real pixels to pull
        // from at its top edge (instead of smearing the edge row).
        val sampleTop = (regionTop - regionH / 3).coerceAtLeast(0)
        val sampleH = h - sampleTop
        val sample = Bitmap.createBitmap(art, 0, sampleTop, w, sampleH)

        FOOT_LAYERS.forEach { (fadeEndFraction, blurFraction) ->
            // Blur after downscaling, so scaling back up shows no blockiness.
            val workW = max(24, w / 5)
            val workH = max(8, sampleH * workW / w)
            val work = Bitmap.createScaledBitmap(sample, workW, workH, true)
            boxBlur(work, radius = max(1, (workW * blurFraction * strength).roundToInt()), passes = 3)

            val layer = Bitmap.createBitmap(w, regionH, Bitmap.Config.ARGB_8888)
            val lc = Canvas(layer)
            lc.drawBitmap(
                work,
                null,
                Rect(0, sampleTop - regionTop, w, regionH),
                Paint(Paint.FILTER_BITMAP_FLAG),
            )
            // Transparent at the strip's top, fully in by fadeEndFraction.
            lc.drawRect(
                0f, 0f, w.toFloat(), regionH.toFloat(),
                Paint().apply {
                    shader = LinearGradient(
                        0f, 0f, 0f, regionH * fadeEndFraction,
                        Color.TRANSPARENT, Color.BLACK, Shader.TileMode.CLAMP,
                    )
                    xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                },
            )
            drawBitmap(layer, 0f, regionTop.toFloat(), null)
            layer.recycle()
            work.recycle()
        }
        sample.recycle()
    }

    /** A light dark gradient inside the strip so white glyphs read on light covers. */
    private fun Canvas.scrimFoot(w: Int, h: Int, blurPx: Int) {
        val top = (h - blurPx).coerceAtLeast(0).toFloat()
        drawRect(
            0f, top, w.toFloat(), h.toFloat(),
            Paint().apply {
                shader = LinearGradient(
                    0f, top, 0f, h.toFloat(),
                    intArrayOf(Color.TRANSPARENT, Color.argb(55, 0, 0, 0), Color.argb(95, 0, 0, 0)),
                    floatArrayOf(0f, 0.45f, 1f),
                    Shader.TileMode.CLAMP,
                )
            },
        )
    }

    private fun Bitmap.roundedCorners(radiusPx: Float): Bitmap {
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(this@roundedCorners, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        Canvas(out).drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radiusPx, radiusPx, paint)
        recycle()
        return out
    }

    /** Separable box blur, [passes] times (three approximates a Gaussian). */
    private fun boxBlur(bitmap: Bitmap, radius: Int, passes: Int) {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        val scratch = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        repeat(passes) {
            blurLine(pixels, scratch, w, h, radius, horizontal = true)
            blurLine(scratch, pixels, w, h, radius, horizontal = false)
        }
        bitmap.setPixels(pixels, 0, w, 0, 0, w, h)
    }

    private fun blurLine(src: IntArray, dst: IntArray, w: Int, h: Int, r: Int, horizontal: Boolean) {
        val lines = if (horizontal) h else w
        val len = if (horizontal) w else h
        val window = r * 2 + 1
        for (line in 0 until lines) {
            fun idx(i: Int): Int {
                val c = i.coerceIn(0, len - 1)
                return if (horizontal) line * w + c else c * w + line
            }
            var a = 0; var rr = 0; var g = 0; var b = 0
            for (i in -r..r) {
                val p = src[idx(i)]
                a += p ushr 24; rr += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF
            }
            for (i in 0 until len) {
                dst[idx(i)] = ((a / window) shl 24) or ((rr / window) shl 16) or ((g / window) shl 8) or (b / window)
                val out = src[idx(i - r)]
                val inn = src[idx(i + r + 1)]
                a += (inn ushr 24) - (out ushr 24)
                rr += ((inn shr 16) and 0xFF) - ((out shr 16) and 0xFF)
                g += ((inn shr 8) and 0xFF) - ((out shr 8) and 0xFF)
                b += (inn and 0xFF) - (out and 0xFF)
            }
        }
    }

    /** (where the layer is fully faded in, as a fraction of the strip; blur radius as a fraction of width) */
    private val FOOT_LAYERS = listOf(0.35f to 0.025f, 0.6f to 0.05f)

    private const val PILL_ALPHA = 215
}
