# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(inzx LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "inzx")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# flutter_inappwebview_windows and permission_handler_windows still build with
# /await, which Visual Studio 2026 rejects unless this is defined.
add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Automix's analysis, ONNX Runtime and blend renderer; see desktop/automix.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../desktop/automix"
  "${CMAKE_BINARY_DIR}/automix")
add_dependencies(${BINARY_NAME} inzx_automix)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# Keep Windows WebView shutdown fixes local to the build directory.
function(patch_webview_source target source old_text new_text)
  if(NOT TARGET ${target})
    return()
  endif()
  get_target_property(source_dir ${target} SOURCE_DIR)
  set(original "${source_dir}/${source}")
  file(READ "${original}" code)
  string(REPLACE "${old_text}" "${new_text}" fixed_code "${code}")
  if(fixed_code STREQUAL code)
    return()
  endif()
  get_filename_component(source_name "${source}" NAME)
  get_filename_component(include_dir "${original}" DIRECTORY)
  set(fixed_source "${CMAKE_CURRENT_BINARY_DIR}/fixed_${source_name}")
  file(WRITE "${fixed_source}" "${fixed_code}")
  get_target_property(sources ${target} SOURCES)
  list(REMOVE_ITEM sources "${source}")
  set_property(TARGET ${target} PROPERTY SOURCES "${sources};${fixed_source}")
  target_include_directories(${target} PRIVATE "${include_dir}")
endfunction()

# The engine owns the handler and may already be gone at plugin destruction.
patch_webview_source(desktop_webview_window_plugin "web_view_window_plugin.cc"
  "  channel_->SetMethodCallHandler(nullptr);\n  lifetime_.reset();"
  "  lifetime_.reset();")

# Release composition objects on the UI thread before COM and DLL teardown.
patch_webview_source(flutter_inappwebview_windows_plugin "in_app_webview/in_app_webview_manager.cpp"
  "    windowWebViews.clear();\n    UnregisterClass"
  [=[    windowWebViews.clear();
    compositor_ = nullptr;
    graphics_context_.reset();
    dispatcher_queue_controller_ = nullptr;
    rohelper_.reset();
    valid_ = false;
    UnregisterClass]=])

# The media_kit Windows bundle's older FFmpeg can crash when the first DASH
# fragment fails to load. Bundle a current libmpv alongside the runner.
include(FetchContent)
set(INZX_LIBMPV_VERSION "0.42.0")
if(CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
  set(INZX_LIBMPV_ARCH "aarch64")
  set(INZX_LIBMPV_SHA256 "e5092a8ec0878127fcac2c33d15c566c569bd9dcf13cee4829ae91a2770abbcb")
else()
  set(INZX_LIBMPV_ARCH "x86_64")
  set(INZX_LIBMPV_SHA256 "8e5f77430efc53ef175804ba6618527e3af0448a0dcabf04d3cc72659d1a6fce")
endif()
set(INZX_LIBMPV_ARCHIVE "libmpv-v${INZX_LIBMPV_VERSION}-${INZX_LIBMPV_ARCH}-w64-mingw32-lgpl.zip")
FetchContent_Declare(inzx_libmpv
  URL "https://github.com/mpv-player/mpv/releases/download/v${INZX_LIBMPV_VERSION}/${INZX_LIBMPV_ARCHIVE}"
  URL_HASH "SHA256=${INZX_LIBMPV_SHA256}")
FetchContent_MakeAvailable(inzx_libmpv)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

install(FILES "${inzx_libmpv_SOURCE_DIR}/libmpv-2.dll"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
install(FILES "${inzx_libmpv_SOURCE_DIR}/LICENSE.LGPL"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" RENAME "LICENSE.libmpv.LGPL"
  COMPONENT Runtime)

install(FILES ${AUTOMIX_BUNDLED_LIBRARIES}
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
install(FILES ${AUTOMIX_MODELS}
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/automix"
  COMPONENT Runtime)
# AutoEQ's target curves, shared with Android's assets.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../android/app/src/main/assets/autoeq_targets.json"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
