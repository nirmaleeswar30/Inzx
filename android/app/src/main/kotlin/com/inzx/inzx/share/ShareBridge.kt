package com.nirmal.inzx.share

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Its own subclass so it can't clash with a plugin's FileProvider in the merged manifest. */
class ShareCardFileProvider : FileProvider()

/**
 * Native half of the share sheet. share_plus can only open Android's share
 * menu, so sending a card straight to one app, knowing which apps are
 * installed and saving to the gallery all live here.
 */
object ShareBridge {
    private const val CHANNEL = "inzx/share"

    private val TARGET_PACKAGES = mapOf(
        "instagram" to "com.instagram.android",
        "snapchat" to "com.snapchat.android",
    )

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installedTargets" -> result.success(installedTargets(activity))

                "shareImage" -> {
                    val path = call.argument<String>("path")
                    val target = call.argument<String>("target")
                    val packageName = TARGET_PACKAGES[target]
                    if (path == null || packageName == null) {
                        result.error("BAD_ARGS", "A path and a known target are required", null)
                    } else {
                        result.success(
                            shareImage(activity, File(path), packageName, call.argument("text")),
                        )
                    }
                }

                "saveImage" -> {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name")
                    if (path == null || name == null) {
                        result.error("BAD_ARGS", "A path and a name are required", null)
                    } else {
                        result.success(saveImage(activity, File(path), name))
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun installedTargets(activity: Activity): List<String> =
        TARGET_PACKAGES.filterValues { packageName ->
            try {
                activity.packageManager.getPackageInfo(packageName, 0)
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }.keys.toList()

    private fun shareImage(activity: Activity, file: File, packageName: String, text: String?): Boolean {
        return try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.share_cards",
                file,
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                setPackage(packageName)
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!text.isNullOrEmpty()) putExtra(Intent.EXTRA_TEXT, text)
                // Some apps only take the read grant from the clip data.
                clipData = ClipData.newRawUri(null, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    /** Adds the image to Pictures/Inzx. Scoped storage needs no permission for this on Android 10+. */
    private fun saveImage(activity: Activity, file: File, name: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Inzx")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { it.copyTo(out) }
            } ?: throw java.io.IOException("No output stream")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (_: Exception) {
            resolver.delete(uri, null, null)
            false
        }
    }
}
