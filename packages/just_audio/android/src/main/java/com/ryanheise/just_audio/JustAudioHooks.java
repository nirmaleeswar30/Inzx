package com.ryanheise.just_audio;

import android.content.Context;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.RenderersFactory;

/**
 * Inzx patch: lets the host app supply the ExoPlayer {@link RenderersFactory}
 * (its audio sink and decoders), which stock just_audio has no way to do,
 * and tells it which ExoPlayer each Dart player owns. Inzx uses the first
 * for hi-res float output, the equaliser and Android 14's bit-perfect USB
 * mode, and the second for Automix, whose transition engine drives both
 * players' volume, tempo and transition filters directly. Null hooks keep
 * just_audio's stock behaviour.
 */
public final class JustAudioHooks {
    private JustAudioHooks() {}

    public interface RenderersFactoryProvider {
        RenderersFactory create(Context context);
    }

    public interface PlayerLifecycle {
        /**
         * An ExoPlayer was built for the Dart player [playerId] (the id the Dart
         * side reads as {@code AudioPlayer.playerId}), with [factory] — the one
         * {@link RenderersFactoryProvider} returned, or null.
         */
        void created(String playerId, ExoPlayer player, RenderersFactory factory);

        /** That ExoPlayer is about to be released. */
        void released(String playerId);
    }

    public static volatile RenderersFactoryProvider renderersFactoryProvider;
    public static volatile PlayerLifecycle playerLifecycle;
}
