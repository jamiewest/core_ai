#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'apple_speech'
  s.version          = '0.1.0'
  s.summary          = "Flutter bindings for Apple's Speech framework."
  s.description      = <<-DESC
Flutter bindings for Apple's Speech framework: on-device speech-to-text for files and live audio.
                       DESC
  s.homepage         = 'https://github.com/jamiewest/core_ai'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'Jamie West'
  s.source           = { :path => '.' }
  s.source_files     = 'apple_speech/Sources/apple_speech/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
  s.resource_bundles = { 'apple_speech_privacy' => ['apple_speech/Sources/apple_speech/Resources/PrivacyInfo.xcprivacy'] }
end
