package com.inzx.inzx

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.webkit.CookieManager
import androidx.core.content.ContextCompat
import com.inzx.inzx.jams.JamsForegroundService
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    private val COOKIE_CHANNEL = "inzx/cookies"
    private val JAMS_CHANNEL = "inzx/jams_native"

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

        // Native foreground-service bridge for Jams background sync
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JAMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        val sessionCode = call.argument<String>("sessionCode") ?: ""
                        val isHost = call.argument<Boolean>("isHost") ?: false
                        val participantCount = call.argument<Int>("participantCount") ?: 1

                        val intent = Intent(this, JamsForegroundService::class.java).apply {
                            action = JamsForegroundService.ACTION_START
                            putExtra(JamsForegroundService.EXTRA_SESSION_CODE, sessionCode)
                            putExtra(JamsForegroundService.EXTRA_IS_HOST, isHost)
                            putExtra(JamsForegroundService.EXTRA_PARTICIPANT_COUNT, participantCount)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_SERVICE_ERROR", e.message, null)
                    }
                }

                "stopService" -> {
                    try {
                        val intent = Intent(this, JamsForegroundService::class.java).apply {
                            action = JamsForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_SERVICE_ERROR", e.message, null)
                    }
                }

                "updateNotification" -> {
                    try {
                        val sessionCode = call.argument<String>("sessionCode") ?: ""
                        val isHost = call.argument<Boolean>("isHost") ?: false
                        val participantCount = call.argument<Int>("participantCount") ?: 1

                        val intent = Intent(this, JamsForegroundService::class.java).apply {
                            action = JamsForegroundService.ACTION_UPDATE_NOTIFICATION
                            putExtra(JamsForegroundService.EXTRA_SESSION_CODE, sessionCode)
                            putExtra(JamsForegroundService.EXTRA_IS_HOST, isHost)
                            putExtra(JamsForegroundService.EXTRA_PARTICIPANT_COUNT, participantCount)
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("UPDATE_NOTIFICATION_ERROR", e.message, null)
                    }
                }

                "isServiceRunning" -> {
                    result.success(JamsForegroundService.isRunning)
                }

                "isBatteryOptimizationExempt" -> {
                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                    } catch (e: Exception) {
                        result.error("BATTERY_CHECK_ERROR", e.message, null)
                    }
                }

                "requestBatteryOptimizationExemption" -> {
                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                        if (powerManager.isIgnoringBatteryOptimizations(packageName)) {
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(false)
                    } catch (e: Exception) {
                        result.error("BATTERY_REQUEST_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}

