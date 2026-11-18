# Adds what the Flutter template's Runner project doesn't have. Idempotent:
# safe to run before every build (CI does), and a no-op once applied.
#
#  1. "[Inzx] Copy bundled data": copies AutoEQ's target curves and Automix's
#     two ONNX models from android/app/src/main/assets into Runner.app/data,
#     where the Dart side looks for them (next to the executable, as on
#     desktop). They aren't Flutter assets: adding assets would change the
#     Android build and break Shorebird patches for the shipped release.
#  2. The InzxWidget WidgetKit extension (ios/InzxWidget), embedded in the
#     app, with its playback App Intents also compiled into Runner (iOS runs
#     an AudioPlaybackIntent in the app's own process).
#
#   ruby ios/scripts/configure_xcode.rb
require 'xcodeproj'

IOS_DIR = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(IOS_DIR, 'Runner.xcodeproj')
WIDGET = 'InzxWidget'
WIDGET_BUNDLE_ID = 'com.nirmal.inzx.InzxWidget'
DEPLOYMENT = '17.0'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' } or abort('no Runner target')
changed = false

# ---- 1. Bundled data ---------------------------------------------------------
DATA_PHASE = '[Inzx] Copy bundled data'
unless runner.shell_script_build_phases.any? { |p| p.name == DATA_PHASE }
  phase = runner.new_shell_script_build_phase(DATA_PHASE)
  phase.shell_script = <<~'SH'
    set -e
    ASSETS="${SRCROOT}/../android/app/src/main/assets"
    DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/data"
    mkdir -p "${DEST}/automix"
    cp "${ASSETS}/autoeq_targets.json" "${DEST}/autoeq_targets.json"
    for model in "${ASSETS}"/*.onnx; do
      [ -f "${model}" ] && cp "${model}" "${DEST}/automix/"
    done
    exit 0
  SH
  phase.always_out_of_date = '1'
  changed = true
end

# ---- 2. Widget extension -------------------------------------------------------
widget_dir = File.join(IOS_DIR, WIDGET)
if Dir.exist?(widget_dir) && project.targets.none? { |t| t.name == WIDGET }
  version = File.read(File.join(IOS_DIR, '..', 'pubspec.yaml'))[/^version:\s*(\S+)/, 1] || '1.0.0'
  build_name, build_number = version.split('+')
  build_number ||= build_name

  widget = project.new_target(:app_extension, WIDGET, :ios, DEPLOYMENT, nil, :swift)
  widget.add_build_configuration('Profile', :release) unless widget.build_configurations.any? { |c| c.name == 'Profile' }

  group = project.main_group.find_subpath(WIDGET, true)
  group.set_source_tree('<group>')
  group.set_path(WIDGET)

  shared_refs = []
  Dir[File.join(widget_dir, '*.swift')].sort.each do |file|
    ref = group.new_reference(File.basename(file))
    widget.add_file_references([ref])
    # The intents and the snapshot model are needed by the app as well.
    shared_refs << ref if File.basename(file).start_with?('Shared')
  end
  runner.add_file_references(shared_refs) unless shared_refs.empty?
  group.new_reference('Info.plist')
  group.new_reference("#{WIDGET}.entitlements")

  widget.build_configurations.each do |config|
    s = config.build_settings
    s['PRODUCT_NAME'] = WIDGET
    s['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE_ID
    s['INFOPLIST_FILE'] = "#{WIDGET}/Info.plist"
    s['GENERATE_INFOPLIST_FILE'] = 'NO'
    s['CODE_SIGN_ENTITLEMENTS'] = "#{WIDGET}/#{WIDGET}.entitlements"
    s['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
    s['SWIFT_VERSION'] = '5.0'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['MARKETING_VERSION'] = build_name
    s['CURRENT_PROJECT_VERSION'] = build_number
    s['SKIP_INSTALL'] = 'YES'
    s['ENABLE_BITCODE'] = 'NO'
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
    s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
    s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  end

  embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
          runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  build_file = embed.add_file_reference(widget.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  runner.add_dependency(widget)

  # The embed phase must come before Flutter's "Thin Binary" script, which
  # expects everything to be in place.
  thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  if thin
    runner.build_phases.delete(embed)
    runner.build_phases.insert(runner.build_phases.index(thin), embed)
  end
  changed = true
end

if changed
  project.save
  puts 'configure_xcode: project updated'
else
  puts 'configure_xcode: nothing to do'
end
