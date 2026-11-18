#
# Inzx's iOS-only native code. See ../pubspec.yaml.
#
# Automix's C++ (BitChord's analyzer and loop mix, GPL-3.0, plus the desktop
# blend renderer and its C API) is compiled from where it already lives in the
# repo: the files under Classes/automix only #include those sources, found
# through the header search paths below ($(PODS_ROOT) is <repo>/ios/Pods).
#
Pod::Spec.new do |s|
  s.name             = 'inzx_ios'
  s.version          = '1.0.0'
  s.summary          = 'Inzx iOS native code'
  s.description      = 'Audio tap, routes, folder access, widgets and Automix for Inzx on iOS.'
  s.homepage         = 'https://github.com/nirmaleeswar30/Inzx'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'Inzx' => 'inzx@nirmaleeswar.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m,mm,swift,cpp}'
  s.public_header_files = 'Classes/InzxDsp.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '17.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'AVFoundation', 'AVKit', 'MediaPlayer', 'MediaToolbox',
                       'CoreMedia', 'AudioToolbox', 'Accelerate', 'UniformTypeIdentifiers'
  s.weak_frameworks  = 'WidgetKit'
  s.library          = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    # The analyzer is tuned against exact IEEE behaviour: never -ffast-math.
    'GCC_OPTIMIZATION_LEVEL' => '3',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) INZX_IOS=1 SIGNALSMITH_USE_ACCELERATE=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) ' \
      '"$(PODS_ROOT)/../../android/app/src/main/cpp" ' \
      '"$(PODS_ROOT)/../../android/app/src/main/cpp/native" ' \
      '"$(PODS_ROOT)/../../android/app/src/main/cpp/native/third_party" ' \
      '"$(PODS_ROOT)/../../desktop/automix"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fno-fast-math -Wno-shorten-64-to-32 -Wno-comma',
  }
end
