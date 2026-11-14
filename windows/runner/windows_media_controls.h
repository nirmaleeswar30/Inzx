#ifndef RUNNER_WINDOWS_MEDIA_CONTROLS_H_
#define RUNNER_WINDOWS_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shobjidl.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>

#include <cstdint>
#include <memory>

// Bridges playback to Windows media keys, the volume flyout, and the
// taskbar preview.
class WindowsMediaControls {
 public:
  // Posted to the window when a control is used, because the system raises
  // those events off the platform thread.
  static constexpr UINT kControlMessage = WM_APP + 0x20;

  WindowsMediaControls(flutter::BinaryMessenger* messenger, HWND window);
  ~WindowsMediaControls();

  // Forwards a posted control press to Dart, on the platform thread.
  void HandleControlMessage(WPARAM control, LPARAM value);
  bool HandleTaskbarMessage(UINT message, WPARAM wparam);

 private:
  enum Control : WPARAM { kPlay, kPause, kStop, kNext, kPrevious, kSeek };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void UpdateTimeline(int64_t position_ms);
  void SetTaskbarState(bool active, bool playing, bool can_previous,
                       bool can_next);
  void UpdateTaskbarButtons(bool add, UINT dpi);

  HWND window_;
  const UINT taskbar_created_message_;
  winrt::com_ptr<ITaskbarList3> taskbar_;
  bool taskbar_active_ = false;
  bool taskbar_playing_ = false;
  bool taskbar_can_previous_ = false;
  bool taskbar_can_next_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
  winrt::event_token seek_token_{};
  int64_t duration_ms_ = 0;
};

#endif  // RUNNER_WINDOWS_MEDIA_CONTROLS_H_
