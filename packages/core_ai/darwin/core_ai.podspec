#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'core_ai'
  s.version          = '0.1.0'
  s.summary          = "Flutter bindings for Apple's Core AI framework."
  s.description      = <<-DESC
Flutter bindings for Apple's Core AI framework (iOS 27+ / macOS 27+), built on
Pigeon platform channels.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'core_ai authors' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'core_ai/Sources/core_ai/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  # CoreAI is not listed as a framework dependency: it only exists on iOS 27+
  # devices and macOS 27+ (not in the iOS Simulator SDK). The sources use it
  # behind `#if canImport(CoreAI)` and `@available`, so autolinking weak-links
  # it where it exists.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
  s.resource_bundles = { 'core_ai_privacy' => ['core_ai/Sources/core_ai/Resources/PrivacyInfo.xcprivacy'] }
end
