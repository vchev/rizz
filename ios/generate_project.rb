# Regenerates ReplyAssistant.xcodeproj from the folders next to this file.
# Only needed when files are added or removed; Vanessa never has to run it.
#   gem install xcodeproj && ruby ios/generate_project.rb
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path(__dir__)
PROJECT_PATH = File.join(ROOT, 'ReplyAssistant.xcodeproj')
BUNDLE_ID = 'com.vchev.ReplyAssistant'
IOS_VERSION = '17.0'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH, false, 56)
project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
project.root_object.attributes['LastUpgradeCheck'] = '1600'

def swift_files(dir)
  Dir.glob(File.join(ROOT, dir, '*.swift')).sort
end

def add_group(project, name)
  project.main_group.new_group(name, name)
end

shared_group = add_group(project, 'Shared')
app_group = add_group(project, 'ReplyAssistant')
ext_group = add_group(project, 'ShareExtension')
kbd_group = add_group(project, 'Keyboard')
test_group = add_group(project, 'ReplyAssistantTests')

shared_refs = swift_files('Shared').map { |f| shared_group.new_file(File.basename(f)) }
app_refs = swift_files('ReplyAssistant').map { |f| app_group.new_file(File.basename(f)) }
assets_ref = app_group.new_file('Assets.xcassets')
ext_refs = swift_files('ShareExtension').map { |f| ext_group.new_file(File.basename(f)) }
ext_group.new_file('Info.plist')
kbd_refs = swift_files('Keyboard').map { |f| kbd_group.new_file(File.basename(f)) }
kbd_group.new_file('Info.plist')
test_refs = swift_files('ReplyAssistantTests').map { |f| test_group.new_file(File.basename(f)) }

common = {
  'SWIFT_VERSION' => '5.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => IOS_VERSION,
  'TARGETED_DEVICE_FAMILY' => '1',
  'MARKETING_VERSION' => '0.1',
  'CURRENT_PROJECT_VERSION' => '1',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_TEAM' => '',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
}

# App
app = project.new_target(:application, 'ReplyAssistant', :ios, IOS_VERSION)
app.add_file_references(shared_refs + app_refs)
app.resources_build_phase.add_file_reference(assets_ref)
app.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Reply Assistant',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'ENABLE_PREVIEWS' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
  )
  c.build_settings.delete('INFOPLIST_FILE')
end

# Share extension
ext = project.new_target(:app_extension, 'ShareExtension', :ios, IOS_VERSION)
ext.add_file_references(shared_refs + ext_refs)
ext.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.ShareExtension",
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => 'ShareExtension/Info.plist',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Reply Assistant',
    'SKIP_INSTALL' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks',
                                  '@executable_path/../../Frameworks'],
  )
end

# Keyboard extension
kbd = project.new_target(:app_extension, 'Keyboard', :ios, IOS_VERSION)
kbd.add_file_references(shared_refs + kbd_refs)
kbd.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.Keyboard",
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => 'Keyboard/Info.plist',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Reply Assistant',
    'SKIP_INSTALL' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks',
                                  '@executable_path/../../Frameworks'],
  )
end

embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
[ext, kbd].each do |extension|
  app.add_dependency(extension)
  embed_file = embed.add_file_reference(extension.product_reference, true)
  embed_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Unit tests for the pure layout logic (no app host needed)
tests = project.new_target(:unit_test_bundle, 'ReplyAssistantTests', :ios, IOS_VERSION)
layout_logic = shared_refs.select { |r| %w[BubbleLayout.swift Conversation.swift].include?(r.path) }
tests.add_file_references(layout_logic + test_refs)
tests.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.Tests",
    'PRODUCT_NAME' => '$(TARGET_NAME)',
  )
  c.build_settings.delete('INFOPLIST_FILE')
end

project.save

# Shared scheme: Run builds the app (which embeds the extension); Test runs the unit tests.
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests, launch_target: true)
scheme.save_as(PROJECT_PATH, 'ReplyAssistant', true)

puts "Wrote #{PROJECT_PATH}"
