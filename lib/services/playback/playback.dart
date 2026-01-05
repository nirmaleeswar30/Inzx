/// OuterTune-style YouTube Music Playback Pipeline
///
/// This module provides a reliable, CDN-direct, audio-only
/// streaming pipeline for YouTube Music content.
///
/// Key components:
/// - [YTPlayerUtils] - Core playback resolver (heart of the system)
/// - [InnerTubeApi] - YouTube InnerTube API wrapper
/// - [PoTokenGenerator] - Anti-403 proof-of-origin tokens
/// - [SignatureCipherDecryptor] - Decrypts encrypted stream URLs
/// - [PlaybackData] - Playback data models

export 'playback_data.dart';
export 'yt_playback_client.dart';
export 'po_token_generator.dart';
export 'signature_decryptor.dart';
export 'yt_player_utils.dart';
