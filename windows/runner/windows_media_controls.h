#ifndef RUNNER_WINDOWS_MEDIA_CONTROLS_H_
#define RUNNER_WINDOWS_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>

#include <cstdint>
#include <memory>

// Bridges the app's playback to the System Media Transport Controls, so media
// keys and the Windows volume flyout control Inzx.
class WindowsMediaControls {
 public:
  // Posted to the window when a control is used, because the system raises
  // those events off the platform thread.
  static constexpr UINT kControlMessage = WM_APP + 0x20;

  WindowsMediaControls(flutter::BinaryMessenger* messenger, HWND window);
  ~WindowsMediaControls();

  // Forwards a posted control press to Dart, on the platform thread.
  void HandleControlMessage(WPARAM control, LPARAM value);

 private:
  enum Control : WPARAM { kPlay, kPause, kStop, kNext, kPrevious, kSeek };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void UpdateTimeline(int64_t position_ms);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
  winrt::event_token seek_token_{};
  int64_t duration_ms_ = 0;
};

#endif  // RUNNER_WINDOWS_MEDIA_CONTROLS_H_
