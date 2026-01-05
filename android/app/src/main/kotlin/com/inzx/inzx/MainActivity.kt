package com.inzx.inzx

import android.webkit.CookieManager
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    private val COOKIE_CHANNEL = "inzx/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Cookie channel for YouTube Music authentication
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COOKIE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    try {
                        val url = call.argument<String>("url") ?: "https://music.youtube.com"
                        val cookieManager = CookieManager.getInstance()
                        val cookies = cookieManager.getCookie(url)
                        result.success(cookies)
                    } catch (e: Exception) {
                        result.error("ERROR", "Could not get cookies", e.message)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

