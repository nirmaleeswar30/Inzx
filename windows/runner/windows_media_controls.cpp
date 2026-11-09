#include "windows_media_controls.h"

#include <flutter/standard_method_codec.h>
#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <string>
#include <variant>

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Foundation::Uri;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

namespace {

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

bool GetBool(const EncodableMap& map, const char* key) {
  auto* value = Find(map, key);
  auto* typed = value ? std::get_if<bool>(value) : nullptr;
  return typed && *typed;
}

int64_t GetInt(const EncodableMap& map, const char* key) {
  auto* value = Find(map, key);
  return value ? value->LongValue() : 0;
}

winrt::hstring GetString(const EncodableMap& map, const char* key) {
  auto* value = Find(map, key);
  auto* typed = value ? std::get_if<std::string>(value) : nullptr;
  return typed ? winrt::to_hstring(*typed) : winrt::hstring();
}

TimeSpan Milliseconds(int64_t ms) {
  return std::chrono::duration_cast<TimeSpan>(std::chrono::milliseconds(ms));
}

}  // namespace

WindowsMediaControls::WindowsMediaControls(flutter::BinaryMessenger* messenger,
                                           HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "inzx/windows_media",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  try {
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(controls_)));

    controls_.IsEnabled(false);
    controls_.IsPlayEnabled(true);
    controls_.IsPauseEnabled(true);
    controls_.IsStopEnabled(true);
    controls_.DisplayUpdater().Type(MediaPlaybackType::Music);

    HWND target = window_;
    button_token_ = controls_.ButtonPressed(
        [target](const SystemMediaTransportControls&,
                 const SystemMediaTransportControlsButtonPressedEventArgs& args) {
          WPARAM control;
          switch (args.Button()) {
            case SystemMediaTransportControlsButton::Play:
              control = kPlay;
              break;
            case SystemMediaTransportControlsButton::Pause:
              control = kPause;
              break;
            case SystemMediaTransportControlsButton::Stop:
              control = kStop;
              break;
            case SystemMediaTransportControlsButton::Next:
              control = kNext;
              break;
            case SystemMediaTransportControlsButton::Previous:
              control = kPrevious;
              break;
            default:
              return;
          }
          PostMessage(target, kControlMessage, control, 0);
        });
    seek_token_ = controls_.PlaybackPositionChangeRequested(
        [target](const SystemMediaTransportControls&,
                 const PlaybackPositionChangeRequestedEventArgs& args) {
          auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        args.RequestedPlaybackPosition())
                        .count();
          PostMessage(target, kControlMessage, kSeek, static_cast<LPARAM>(ms));
        });
  } catch (const winrt::hresult_error&) {
    // Media keys are a convenience: playback works without them.
    controls_ = nullptr;
  }
}

WindowsMediaControls::~WindowsMediaControls() {
  if (controls_) {
    controls_.ButtonPressed(button_token_);
    controls_.PlaybackPositionChangeRequested(seek_token_);
  }
}

void WindowsMediaControls::HandleControlMessage(WPARAM control, LPARAM value) {
  switch (control) {
    case kPlay:
      channel_->InvokeMethod("play", nullptr);
      break;
    case kPause:
      channel_->InvokeMethod("pause", nullptr);
      break;
    case kStop:
      channel_->InvokeMethod("stop", nullptr);
      break;
    case kNext:
      channel_->InvokeMethod("next", nullptr);
      break;
    case kPrevious:
      channel_->InvokeMethod("previous", nullptr);
      break;
    case kSeek:
      channel_->InvokeMethod("seek", std::make_unique<EncodableValue>(
                                         static_cast<int64_t>(value)));
      break;
  }
}

void WindowsMediaControls::UpdateTimeline(int64_t position_ms) {
  SystemMediaTransportControlsTimelineProperties timeline;
  timeline.StartTime(Milliseconds(0));
  timeline.EndTime(Milliseconds(duration_ms_));
  timeline.MinSeekTime(Milliseconds(0));
  timeline.MaxSeekTime(Milliseconds(duration_ms_));
  timeline.Position(Milliseconds(position_ms));
  controls_.UpdateTimelineProperties(timeline);
}

void WindowsMediaControls::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (!controls_) {
    result->Success();
    return;
  }

  try {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    const std::string& method = call.method_name();

    if (method == "setState" && args) {
      controls_.IsEnabled(GetBool(*args, "active"));
      controls_.IsNextEnabled(GetBool(*args, "canNext"));
      controls_.IsPreviousEnabled(GetBool(*args, "canPrevious"));
      controls_.PlaybackStatus(GetBool(*args, "playing")
                                   ? MediaPlaybackStatus::Playing
                                   : MediaPlaybackStatus::Paused);
      UpdateTimeline(GetInt(*args, "positionMs"));
    } else if (method == "setMediaItem" && args) {
      duration_ms_ = GetInt(*args, "durationMs");
      auto updater = controls_.DisplayUpdater();
      updater.Type(MediaPlaybackType::Music);
      auto music = updater.MusicProperties();
      music.Title(GetString(*args, "title"));
      music.Artist(GetString(*args, "artist"));
      music.AlbumTitle(GetString(*args, "album"));
      auto art = GetString(*args, "artUri");
      if (art.empty()) {
        updater.Thumbnail(nullptr);
      } else {
        updater.Thumbnail(RandomAccessStreamReference::CreateFromUri(Uri(art)));
      }
      updater.Update();
    } else if (method == "clear") {
      controls_.DisplayUpdater().ClearAll();
      controls_.IsEnabled(false);
    } else {
      result->NotImplemented();
      return;
    }
  } catch (const winrt::hresult_error&) {
    // A bad artwork URI or a busy session must never interrupt playback.
  }
  result->Success();
}
