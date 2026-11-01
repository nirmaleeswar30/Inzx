package com.nirmal.inzx.audio

import android.content.Context
import com.lastwave.app.data.autoeq.AutoEqCatalog
import com.lastwave.app.data.autoeq.AutoEqController
import com.lastwave.app.data.autoeq.AutoEqEntry
import com.lastwave.app.data.autoeq.AutoEqTargets
import com.lastwave.app.data.autoeq.PeqMath
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The AutoEQ screen's link to LastWave's AutoEQ (ported under
 * com.lastwave.app.data.autoeq), over `inzx/autoeq`. The controller is
 * created at app start so a saved correction — and the per-device profile
 * switching — is live before anything plays.
 */
object AutoEqBridge {
    @Volatile private var controller: AutoEqController? = null
    private var catalog: AutoEqCatalog? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** The last search's rows, by path, so a tap selects the exact entry. */
    private val lastResults = HashMap<String, AutoEqEntry>()

    fun init(context: Context) {
        if (controller != null) return
        val app = context.applicationContext
        val cat = AutoEqCatalog(app)
        catalog = cat
        controller = AutoEqController(app, cat, AutoEqTargets(app))
    }

    fun attach(context: Context, messenger: BinaryMessenger) {
        init(context)
        MethodChannel(messenger, "inzx/autoeq").setMethodCallHandler { call, result ->
            val c = controller
            val cat = catalog
            if (c == null || cat == null) {
                result.error("AUTOEQ", "Not ready", null)
                return@setMethodCallHandler
            }
            scope.launch {
                try {
                    when (call.method) {
                        "state" -> result.success(describe(c))
                        "search" -> {
                            val query = call.argument<String>("query").orEmpty()
                            val found = runCatching { cat.search(query) }
                            found.onFailure { result.error("AUTOEQ", it.message, null) }
                            found.onSuccess { rows ->
                                lastResults.clear()
                                rows.forEach { lastResults[it.encodedPath] = it }
                                result.success(rows.map { it.toMap() })
                            }
                        }
                        "select" -> {
                            val entry = lastResults[call.argument<String>("path")]
                            if (entry == null) {
                                result.error("AUTOEQ", "Search again and pick the headphone", null)
                            } else {
                                c.selectProfile(entry)
                                    .onSuccess { result.success(describe(c)) }
                                    .onFailure { result.error("AUTOEQ", it.message, null) }
                            }
                        }
                        "setEnabled" -> {
                            c.setEnabled(call.argument<Boolean>("on") == true).join()
                            result.success(describe(c))
                        }
                        "setAutoPerDevice" -> {
                            c.setAutoPerDevice(call.argument<Boolean>("on") == true).join()
                            result.success(describe(c))
                        }
                        "setTarget" -> {
                            c.setTarget(call.argument<String>("id") ?: AutoEqTargets.DEFAULT_TARGET_ID)
                            result.success(describe(c))
                        }
                        "setBass" -> {
                            c.setBass(call.argument<Double>("db") ?: 0.0)
                            result.success(describe(c))
                        }
                        "setTilt" -> {
                            c.setTilt(call.argument<Double>("db") ?: 0.0)
                            result.success(describe(c))
                        }
                        "reset" -> {
                            c.resetToProfile()
                            result.success(describe(c))
                        }
                        "clear" -> {
                            c.clearProfile()
                            result.success(describe(c))
                        }
                        "saveForDevice" -> {
                            c.saveForCurrentDevice()
                            result.success(describe(c))
                        }
                        "forgetDevice" -> {
                            c.forgetDevice(call.argument<String>("key").orEmpty())
                            result.success(describe(c))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("AUTOEQ", e.message, null)
                }
            }
        }
    }

    private fun AutoEqEntry.toMap() = mapOf(
        "name" to name,
        "subtitle" to subtitle,
        "path" to encodedPath,
        "inEar" to (formFactor == com.lastwave.app.data.autoeq.FormFactor.IN_EAR),
    )

    private fun describe(c: AutoEqController): Map<String, Any?> {
        val s = c.state.value
        val settings = s.settings
        val grid = PeqMath.LOG_GRID
        return mapOf(
            "enabled" to c.enabled.value,
            "busy" to c.busy.value,
            "autoPerDevice" to c.autoPerDevice.value,
            "entry" to s.entry?.toMap(),
            "targetId" to s.targetId,
            "bassDb" to s.bassDb,
            "tiltDb" to s.tiltDbPerOctave,
            "isCustom" to s.isCustom,
            "preampDb" to settings.preampDb,
            "filterCount" to settings.filters.count { it.enabled },
            "targets" to c.availableTargets().map {
                mapOf("id" to it.id, "name" to it.name, "family" to it.family)
            },
            "device" to c.currentDevice.value?.let { mapOf("key" to it.key, "label" to it.label) },
            "savedDevices" to c.deviceProfiles.value.keys.map { key ->
                mapOf(
                    "key" to key,
                    "label" to (c.knownDeviceLabels.value[key] ?: key),
                    "headphone" to c.deviceProfiles.value[key]?.entry?.name,
                )
            },
            // The correction's response, for the graph (dB at each grid Hz).
            "curveHz" to grid.toList(),
            "curveDb" to grid.map { PeqMath.responseDb(settings, it) },
        )
    }
}
