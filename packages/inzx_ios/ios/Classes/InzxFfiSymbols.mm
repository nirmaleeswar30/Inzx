// inzx_ios is a static framework (ONNX Runtime ships as a static library),
// so it's linked into the app executable, and the linker only keeps what
// something references. Dart reaches Automix's C API over FFI by symbol name
// (DynamicLibrary.process()), which the linker can't see: this table
// references every such function so it stays, and InzxIosPlugin touches the
// table at registration. Runner's STRIP_STYLE is non-global so the names
// stay findable (ios/scripts/configure_xcode.rb).

#import "InzxDsp.h"

// The real signatures don't matter here: only the addresses are taken.
extern "C" void ax_analysis_sample_rate(void);
extern "C" void ax_analyze(void);
extern "C" void ax_beat_hop(void);
extern "C" void ax_beat_mels(void);
extern "C" void ax_beat_sample_rate(void);
extern "C" void ax_beat_spectrogram(void);
extern "C" void ax_blend_create(void);
extern "C" void ax_blend_destroy(void);
extern "C" void ax_blend_render(void);
extern "C" void ax_blend_set_deck(void);
extern "C" void ax_blend_set_envelope(void);
extern "C" void ax_default_output(void);
extern "C" void ax_free(void);
extern "C" void ax_last_error(void);
extern "C" void ax_loop_create(void);
extern "C" void ax_loop_destroy(void);
extern "C" void ax_loop_first_frame(void);
extern "C" void ax_loop_heard(void);
extern "C" void ax_loop_prepare(void);
extern "C" void ax_loop_render(void);
extern "C" void ax_loop_render_file(void);
extern "C" void ax_loop_set_deck(void);
extern "C" void ax_loop_set_envelope(void);
extern "C" void ax_model_close(void);
extern "C" void ax_model_open(void);
extern "C" void ax_model_run(void);
extern "C" void ax_resample(void);
extern "C" void ax_vocal_bins(void);
extern "C" void ax_vocal_fft(void);
extern "C" void ax_vocal_hop(void);
extern "C" void ax_vocal_sample_rate(void);
extern "C" void ax_vocal_spectrogram(void);
extern "C" void inzx_decode_region(void);
extern "C" void inzx_decode_free(void);

extern "C" __attribute__((used, visibility("default"))) const void *const inzx_ffi_symbols[] = {
    reinterpret_cast<const void *>(&ax_analysis_sample_rate),
    reinterpret_cast<const void *>(&ax_analyze),
    reinterpret_cast<const void *>(&ax_beat_hop),
    reinterpret_cast<const void *>(&ax_beat_mels),
    reinterpret_cast<const void *>(&ax_beat_sample_rate),
    reinterpret_cast<const void *>(&ax_beat_spectrogram),
    reinterpret_cast<const void *>(&ax_blend_create),
    reinterpret_cast<const void *>(&ax_blend_destroy),
    reinterpret_cast<const void *>(&ax_blend_render),
    reinterpret_cast<const void *>(&ax_blend_set_deck),
    reinterpret_cast<const void *>(&ax_blend_set_envelope),
    reinterpret_cast<const void *>(&ax_default_output),
    reinterpret_cast<const void *>(&ax_free),
    reinterpret_cast<const void *>(&ax_last_error),
    reinterpret_cast<const void *>(&ax_loop_create),
    reinterpret_cast<const void *>(&ax_loop_destroy),
    reinterpret_cast<const void *>(&ax_loop_first_frame),
    reinterpret_cast<const void *>(&ax_loop_heard),
    reinterpret_cast<const void *>(&ax_loop_prepare),
    reinterpret_cast<const void *>(&ax_loop_render),
    reinterpret_cast<const void *>(&ax_loop_render_file),
    reinterpret_cast<const void *>(&ax_loop_set_deck),
    reinterpret_cast<const void *>(&ax_loop_set_envelope),
    reinterpret_cast<const void *>(&ax_model_close),
    reinterpret_cast<const void *>(&ax_model_open),
    reinterpret_cast<const void *>(&ax_model_run),
    reinterpret_cast<const void *>(&ax_resample),
    reinterpret_cast<const void *>(&ax_vocal_bins),
    reinterpret_cast<const void *>(&ax_vocal_fft),
    reinterpret_cast<const void *>(&ax_vocal_hop),
    reinterpret_cast<const void *>(&ax_vocal_sample_rate),
    reinterpret_cast<const void *>(&ax_vocal_spectrogram),
    reinterpret_cast<const void *>(&inzx_decode_region),
    reinterpret_cast<const void *>(&inzx_decode_free),
};

NSInteger InzxKeepFfiSymbols(void) {
  // Read through a volatile pointer: otherwise the compiler folds the loop
  // into a constant, drops the table, and the linker then drops everything
  // it referenced (the first CI build shipped without Automix this way).
  const void *const volatile *table = inzx_ffi_symbols;
  NSInteger count = 0;
  for (size_t i = 0; i < sizeof(inzx_ffi_symbols) / sizeof(inzx_ffi_symbols[0]); i++) {
    if (table[i] != nullptr) count++;
  }
  return count;
}
