package com.nirmal.inzx

import android.app.Application
import com.music.bitchord.data.settings.AppSettings
import com.nirmal.inzx.audio.InzxAudioOutput
import com.nirmal.inzx.automix.AutomixEngine
import com.ryanheise.just_audio.JustAudioHooks

/**
 * Installs Inzx's ExoPlayer renderers before any player exists. Done here
 * rather than in MainActivity because playback can start without the
 * activity (media buttons, Android Auto, widgets restarting the service).
 */
class InzxApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        InzxAudioOutput.init(this)
        // Automix settings (ported BitChord code reads them as AppSettings).
        AppSettings.init(getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE))
        // Before any player exists: the engine binds to each ExoPlayer as
        // just_audio builds it.
        AutomixEngine.init(this)
        // AutoEQ (LastWave's): live before anything plays, incl. per-device switching.
        com.nirmal.inzx.audio.AutoEqBridge.init(this)
        JustAudioHooks.renderersFactoryProvider =
            JustAudioHooks.RenderersFactoryProvider { context ->
                InzxAudioOutput.renderersFactory(context)
            }
    }
}
