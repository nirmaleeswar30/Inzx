// Inzx desktop: which audio output is in use, for AutoEQ's per-device
// profiles (Android reads the same from AudioManager in AutoEqController).
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.

#include <cstdlib>
#include <cstring>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#define AX_API extern "C" __declspec(dllexport)
#else
#define AX_API extern "C" __attribute__((visibility("default")))
#endif

#if defined(_WIN32)
namespace {

std::string toUtf8(const wchar_t* text) {
  if (text == nullptr) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), size, nullptr, nullptr);
  return out;
}

std::string stringProperty(IPropertyStore* store, const PROPERTYKEY& key) {
  PROPVARIANT value;
  PropVariantInit(&value);
  std::string out;
  if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_LPWSTR) {
    out = toUtf8(value.pwszVal);
  }
  PropVariantClear(&value);
  return out;
}

unsigned long numberProperty(IPropertyStore* store, const PROPERTYKEY& key) {
  PROPVARIANT value;
  PropVariantInit(&value);
  unsigned long out = 0;
  if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_UI4) out = value.ulVal;
  PropVariantClear(&value);
  return out;
}

}  // namespace
#endif

/// The default render endpoint as "id\nname\nadapter\nformFactor" (UTF-8,
/// free with ax_free), or null. formFactor is EndpointFormFactor: 1
/// speakers, 3 headphones, 5 headset, 9 display audio, ...
AX_API char* ax_default_output() {
#if defined(_WIN32)
  const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninit = SUCCEEDED(init);
  std::string result;
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IPropertyStore* store = nullptr;
  LPWSTR id = nullptr;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                 __uuidof(IMMDeviceEnumerator),
                                 reinterpret_cast<void**>(&enumerator))) &&
      SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)) &&
      SUCCEEDED(device->GetId(&id)) &&
      SUCCEEDED(device->OpenPropertyStore(STGM_READ, &store))) {
    result = toUtf8(id) + "\n" + stringProperty(store, PKEY_Device_FriendlyName) + "\n" +
             stringProperty(store, PKEY_DeviceInterface_FriendlyName) + "\n" +
             std::to_string(numberProperty(store, PKEY_AudioEndpoint_FormFactor));
  }
  if (id != nullptr) CoTaskMemFree(id);
  if (store != nullptr) store->Release();
  if (device != nullptr) device->Release();
  if (enumerator != nullptr) enumerator->Release();
  if (uninit) CoUninitialize();
  if (result.empty()) return nullptr;
  char* out = static_cast<char*>(std::malloc(result.size() + 1));
  if (out != nullptr) std::memcpy(out, result.c_str(), result.size() + 1);
  return out;
#else
  return nullptr;
#endif
}
