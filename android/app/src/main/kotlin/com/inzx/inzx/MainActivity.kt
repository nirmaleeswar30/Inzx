package com.nirmal.inzx

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.webkit.CookieManager
import androidx.core.content.ContextCompat
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.bluetooth.BluetoothAdapter
import android.content.Context
import com.nirmal.inzx.jams.JamsForegroundService
import com.nirmal.inzx.widget.MusicWidgetProvider
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    companion object {
        // Prevent R8 resource shrinker from stripping dynamic notification drawables in release builds
        @JvmStatic
        val KEEP_RESOURCES = intArrayOf(
            R.drawable.ic_heart_filled,
            R.drawable.ic_heart_outline,
            R.drawable.ic_notification,
        )
    }

    private val COOKIE_CHANNEL = "inzx/cookies"
    private val JAMS_CHANNEL = "inzx/jams_native"
    private val WIDGET_CHANNEL = "inzx/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ROUTING_CHANNEL = "inzx/audio_routing"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ROUTING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getActiveDeviceName" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        
                        var activeDeviceName = "Internal Speaker"
                        var activeIsSpeaker = true
                        
                        val allDevices = mutableListOf<Map<String, Any>>()
                        
                        var phoneName = "Internal Speaker"
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        if (adapter != null) {
                            try {
                                val bName = adapter.name
                                if (!bName.isNullOrEmpty()) {
                                    phoneName = bName
                                }
                            } catch (e: SecurityException) {}
                        }

                        // First determine the active route
                        if (audioManager.isSpeakerphoneOn) {
                            activeIsSpeaker = true
                        } else {
                            for (device in devices) {
                                val isBt = device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || 
                                         device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                         device.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                                         device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                                if (isBt) {
                                    var dName = device.productName.toString()
                                    try {
                                        val address = device.address
                                        if (!address.isNullOrEmpty() && adapter != null) {
                                            val btName = adapter.getRemoteDevice(address)?.name
                                            if (!btName.isNullOrEmpty()) dName = btName
                                        }
                                    } catch (e: Exception) {}
                                    
                                    activeDeviceName = dName
                                    activeIsSpeaker = false
                                    break
                                }
                            }
                        }
                        
                        if (activeIsSpeaker) activeDeviceName = phoneName

                        // Now build the list of all valid outputs
                        // We always add the phone speaker
                        allDevices.add(mapOf("name" to phoneName, "isSpeaker" to true, "isActive" to activeIsSpeaker))
                        
                        // Add external devices
                        for (device in devices) {
                            val isBt = device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || 
                                     device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                     device.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                                     device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                            if (isBt) {
                                var dName = device.productName.toString()
                                try {
                                    val address = device.address
                                    if (!address.isNullOrEmpty() && adapter != null) {
                                        val btName = adapter.getRemoteDevice(address)?.name
                                        if (!btName.isNullOrEmpty()) dName = btName
                                    }
                                } catch (e: Exception) {}
                                
                                allDevices.add(mapOf("name" to dName, "isSpeaker" to false, "isActive" to (dName == activeDeviceName && !activeIsSpeaker)))
                            }
                        }
                        
                        result.success(mapOf(
                            "active" to mapOf("name" to activeDeviceName, "isSpeaker" to activeIsSpeaker),
                            "all" to allDevices
                        ))
                    } catch (e: Exception) {
                        result.error("DEVICE_NAME_ERROR", e.message, null)
                    }
                }
                "openOutputPanel" -> {
                    try {
                        var intentLaunched = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            try {
                                val intent = Intent("com.android.settings.panel.action.MEDIA_OUTPUT").apply {
                                    putExtra("com.android.settings.panel.extra.PACKAGE_NAME", packageName)
                                }
                                startActivity(intent)
                                intentLaunched = true
                            } catch (e: android.content.ActivityNotFoundException) {
                                // Fall through to legacy/fallback
                            }
                        }
                        
                        if (!intentLaunched) {
                            // Fallback to Bluetooth settings so they can connect/disconnect devices
                            val fallbackIntent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                            startActivity(fallbackIntent)
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.message, null)
                    }
                }
                "getVolume" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble()
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).toDouble()
                        val volume = if (max > 0) current / max else 0.0
                        result.success(volume)
                    } catch (e: Exception) {
                        result.success(0.5)
                    }
                }
                "setVolume" -> {
                    try {
                        val vol = call.argument<Double>("volume") ?: 0.5
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val target = (vol * max).toInt()
                        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VOLUME_ERROR", e.message, null)
                    }
                }
                "setAudioRoute" -> {
                    try {
                        val isSpeaker = call.argument<Boolean>("isSpeaker") ?: true
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        
                        // Extremely aggressive hack to force route on Android programmatically
                        if (isSpeaker) {
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            audioManager.stopBluetoothSco()
                            audioManager.isBluetoothScoOn = false
                            audioManager.isSpeakerphoneOn = true
                        } else {
                            audioManager.isSpeakerphoneOn = false
                            audioManager.stopBluetoothSco()
                            audioManager.isBluetoothScoOn = false
                            audioManager.mode = AudioManager.MODE_NORMAL
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ROUTE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
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

        // Music widget bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncPlaybackState" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            MusicWidgetProvider.saveState(this, args)
                        }
                        MusicWidgetProvider.updateAllWidgets(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WIDGET_SYNC_ERROR", e.message, null)
                    }
                }

                "refreshWidget" -> {
                    try {
                        MusicWidgetProvider.updateAllWidgets(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WIDGET_REFRESH_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}

