# Native code for Automix, ported from BitChord (GPL-3.0; see
# native/BITCHORD_LICENSE.txt). Only the two libraries Automix needs:
#
#  - bitchord_analysis: whole-track DSP analysis (tempo/key/energy/structure)
#    plus the log-mel and STFT front ends the Beat This! and open-unmix
#    models read. The models themselves run through ONNX Runtime in Kotlin.
#  - bitchord_loopmix: the loop mix, two Signalsmith Stretch decks looping
#    whole bars on a ramping tempo (Signalsmith is MIT, header-only, under
#    native/third_party).
#
# Library and JNI names are BitChord's own, unchanged, so the Kotlin side
# (package com.music.bitchord.playback.*) matches without edits.

cmake_minimum_required(VERSION 3.22.1)
project(inzx_automix LANGUAGES C CXX)

set(NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/native")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_library(log-lib log)

add_library(bitchord_analysis SHARED
    ${NATIVE_DIR}/analyzer/audio_analysis.cpp
    ${NATIVE_DIR}/analyzer/tempo_analysis.cpp
    ${NATIVE_DIR}/analyzer/resampler.cpp
    ${NATIVE_DIR}/analyzer/mel_spectrogram.cpp
    ${NATIVE_DIR}/analyzer/vocal_spectrogram.cpp
    jni/analysis_jni.cpp
    jni/mel_jni.cpp
    jni/vocal_jni.cpp
)
target_include_directories(bitchord_analysis PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${NATIVE_DIR}
)
# No -ffast-math: the analyzer is tuned against exact IEEE behaviour.
target_compile_options(bitchord_analysis PRIVATE -O3 -fvisibility=hidden)
target_link_libraries(bitchord_analysis ${log-lib})
# 16 KB page-size support (Android 15+).
target_link_options(bitchord_analysis PRIVATE "-Wl,-z,max-page-size=16384")

add_library(bitchord_loopmix SHARED
    ${NATIVE_DIR}/loopmix/loop_mix_renderer.cpp
    jni/loopmix_jni.cpp
)
target_include_directories(bitchord_loopmix PRIVATE
    ${NATIVE_DIR}
    ${NATIVE_DIR}/third_party
)
target_compile_options(bitchord_loopmix PRIVATE -O3 -ffast-math -fvisibility=hidden -Wno-unused-parameter)
target_link_options(bitchord_loopmix PRIVATE "-Wl,-z,max-page-size=16384")
