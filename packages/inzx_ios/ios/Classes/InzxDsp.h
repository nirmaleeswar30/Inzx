#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The equaliser + AutoEQ chain and per-player loudness gain, run in an
/// MTAudioProcessingTap on every item the just_audio players queue.
///
/// The Dart side (IosAudioDsp) computes the same filter list desktop hands
/// to libmpv and Android runs in EqualizerProcessor / ParametricEqProcessor:
/// RBJ biquads (peaking, shelves, passes) and an overall preamp. A flat chain
/// with unity gain leaves the samples untouched.
@interface InzxDsp : NSObject

+ (instancetype)shared NS_SWIFT_NAME(shared());

/// `filters`: dictionaries of `type` (0 peaking, 1 low shelf, 2 high shelf,
/// 3 low pass, 4 high pass), `f` (Hz), `g` (dB), `q`.
- (void)setFilters:(NSArray<NSDictionary *> *)filters
          preampDb:(double)preampDb NS_SWIFT_NAME(setFilters(_:preampDb:));

/// Linear gain for one player (loudness normalization), 1 for none.
- (void)setGain:(double)gain forPlayer:(NSString *)playerId NS_SWIFT_NAME(setGain(_:forPlayer:));

/// The Automix transition filter for one player during a live blend:
/// low-pass and high-pass cutoffs (20000 / 20 Hz to park them) and the
/// echo out (send and dry; no echo with `echoSeconds` 0). Cutoffs glide.
- (void)setTransitionForPlayer:(NSString *)playerId
                     lowPassHz:(double)lowPassHz
                    highPassHz:(double)highPassHz
                   echoSeconds:(double)echoSeconds
                      echoSend:(double)echoSend
                       echoDry:(double)echoDry
    NS_SWIFT_NAME(setTransition(forPlayer:lowPassHz:highPassHz:echoSeconds:echoSend:echoDry:));

/// Attaches the tap to `item` once its audio track is known. Streaming
/// playlists (HLS) have no asset-level track and play without it.
- (void)attachToItem:(AVPlayerItem *)item
            playerId:(NSString *)playerId NS_SWIFT_NAME(attach(to:playerId:));

/// Frames processed so far, for diagnostics.
@property(nonatomic, readonly) int64_t framesProcessed;

/// The sample rate of the last prepared tap, 0 before any.
@property(nonatomic, readonly) double lastSampleRate;

@end

/// Keeps Automix's FFI functions linked into the app (see InzxFfiSymbols.mm).
/// Returns how many there are.
FOUNDATION_EXPORT NSInteger InzxKeepFfiSymbols(void);

NS_ASSUME_NONNULL_END
