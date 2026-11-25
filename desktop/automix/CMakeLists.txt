# Automix's native code for the desktop builds (Windows and Linux).
#
# The sources are BitChord's analysis and loop-mix code that Android builds
# from android/app/src/main/cpp (GPL-3.0; see native/BITCHORD_LICENSE.txt),
# compiled here unchanged behind a plain C API (automix_ffi.cpp) that Dart
# reaches over FFI, plus the blend renderer that plays the role Android's
# live filter chain does. ONNX Runtime runs the two analysis models.
#
# Include from the platform CMakeLists with:
#   add_subdirectory(<repo>/desktop/automix ${CMAKE_BINARY_DIR}/automix)
# then install AUTOMIX_BUNDLED_LIBRARIES next to the executable (Windows) or
# into lib/ (Linux), and AUTOMIX_MODELS into data/automix/.

cmake_minimum_required(VERSION 3.14)
project(inzx_automix LANGUAGES C CXX)

set(AUTOMIX_REPO "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(AUTOMIX_CPP "${AUTOMIX_REPO}/android/app/src/main/cpp")
set(AUTOMIX_NATIVE "${AUTOMIX_CPP}/native")

# ---- ONNX Runtime (MIT), Microsoft's prebuilt release -----------------------
# From Microsoft's NuGet package. The GitHub release archives this used to
# download went offline in November 2026; the package holds the same build
# (its Windows DLL and headers match that archive byte for byte). One package
# carries every platform, so only the headers and this platform's library are
# unpacked, into the include/ and lib/ layout the archive had.
set(ORT_VERSION "1.28.0")
set(ORT_PACKAGE "microsoft.ml.onnxruntime.${ORT_VERSION}.nupkg")
set(ORT_URL "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${ORT_VERSION}/${ORT_PACKAGE}")
set(ORT_SHA256 "769d1d3ea8ab6cd69f737c9dd4d4462aa4ad0ccfa106eaf506efc40d7bead5db")
set(ORT_DOWNLOAD "${CMAKE_BINARY_DIR}/${ORT_PACKAGE}")
set(ORT_DIR "${CMAKE_BINARY_DIR}/onnxruntime-${ORT_VERSION}")
if(WIN32)
  set(ORT_NATIVE "runtimes/win-x64/native")
  set(ORT_LIBRARIES onnxruntime.dll onnxruntime.lib)
else()
  set(ORT_NATIVE "runtimes/linux-x64/native")
  set(ORT_LIBRARIES libonnxruntime.so)
endif()

# The headers go in last, so their presence means the unpacking finished.
if(NOT EXISTS "${ORT_DIR}/include/onnxruntime_cxx_api.h")
  if(NOT EXISTS "${ORT_DOWNLOAD}")
    message(STATUS "Downloading ${ORT_URL}")
    file(DOWNLOAD "${ORT_URL}" "${ORT_DOWNLOAD}"
      EXPECTED_HASH SHA256=${ORT_SHA256}
      SHOW_PROGRESS)
  endif()
  set(ORT_UNPACK "${CMAKE_BINARY_DIR}/onnxruntime-${ORT_VERSION}-unpack")
  file(REMOVE_RECURSE "${ORT_UNPACK}" "${ORT_DIR}")
  file(ARCHIVE_EXTRACT INPUT "${ORT_DOWNLOAD}" DESTINATION "${ORT_UNPACK}"
    PATTERNS "build/native/include/*" "${ORT_NATIVE}/*")
  foreach(lib ${ORT_LIBRARIES})
    file(COPY "${ORT_UNPACK}/${ORT_NATIVE}/${lib}" DESTINATION "${ORT_DIR}/lib")
  endforeach()
  if(NOT WIN32)
    # Named for its SONAME, the name the loader looks for next to Automix.
    file(RENAME "${ORT_DIR}/lib/libonnxruntime.so"
      "${ORT_DIR}/lib/libonnxruntime.so.1")
  endif()
  file(COPY "${ORT_UNPACK}/build/native/include/" DESTINATION "${ORT_DIR}/include")
  file(REMOVE_RECURSE "${ORT_UNPACK}")
endif()

add_library(onnxruntime SHARED IMPORTED GLOBAL)
if(WIN32)
  set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION "${ORT_DIR}/lib/onnxruntime.dll"
    IMPORTED_IMPLIB "${ORT_DIR}/lib/onnxruntime.lib")
  set(ORT_RUNTIME_FILES "${ORT_DIR}/lib/onnxruntime.dll")
else()
  set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION "${ORT_DIR}/lib/libonnxruntime.so.1"
    IMPORTED_SONAME "libonnxruntime.so.1")
  set(ORT_RUNTIME_FILES "${ORT_DIR}/lib/libonnxruntime.so.1")
endif()
target_include_directories(onnxruntime INTERFACE "${ORT_DIR}/include")

# ---- The library Dart loads ---------------------------------------------------
add_library(inzx_automix SHARED
  "${AUTOMIX_NATIVE}/analyzer/audio_analysis.cpp"
  "${AUTOMIX_NATIVE}/analyzer/tempo_analysis.cpp"
  "${AUTOMIX_NATIVE}/analyzer/resampler.cpp"
  "${AUTOMIX_NATIVE}/analyzer/mel_spectrogram.cpp"
  "${AUTOMIX_NATIVE}/analyzer/vocal_spectrogram.cpp"
  "${AUTOMIX_NATIVE}/loopmix/loop_mix_renderer.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/blend_renderer.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/automix_ffi.cpp"
  # AutoEQ's per-device profiles: the output in use.
  "${CMAKE_CURRENT_SOURCE_DIR}/output_device.cpp"
)
set_target_properties(inzx_automix PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
target_include_directories(inzx_automix PRIVATE
  "${AUTOMIX_NATIVE}"
  "${AUTOMIX_NATIVE}/third_party"
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(inzx_automix PRIVATE onnxruntime)
if(WIN32)
  target_link_libraries(inzx_automix PRIVATE ole32)
endif()
if(MSVC)
  # Optimised in every configuration: the analysis is far too slow without
  # it. Debug's runtime checks can't be combined with /O2, so they go.
  foreach(flags CMAKE_CXX_FLAGS_DEBUG CMAKE_C_FLAGS_DEBUG)
    string(REPLACE "/RTC1" "" ${flags} "${${flags}}")
  endforeach()
  # No /fp:fast: the analyzer is tuned against exact IEEE behaviour.
  target_compile_options(inzx_automix PRIVATE /O2 /EHsc /bigobj /utf-8 /wd4244 /wd4267 /wd4305)
  target_compile_definitions(inzx_automix PRIVATE _USE_MATH_DEFINES NOMINMAX _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_options(inzx_automix PRIVATE -O3 -Wno-unused-parameter)
  set_target_properties(inzx_automix PROPERTIES INSTALL_RPATH "$ORIGIN")
endif()

set(AUTOMIX_BUNDLED_LIBRARIES
  "$<TARGET_FILE:inzx_automix>"
  ${ORT_RUNTIME_FILES}
  PARENT_SCOPE)

# The models Android ships in its assets, shared rather than copied.
set(AUTOMIX_MODELS
  "${AUTOMIX_REPO}/android/app/src/main/assets/beat_this_final0_q8.onnx"
  "${AUTOMIX_REPO}/android/app/src/main/assets/vocals_umxhq_int8.onnx"
  PARENT_SCOPE)
