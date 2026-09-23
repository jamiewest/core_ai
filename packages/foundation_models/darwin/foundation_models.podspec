#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'foundation_models'
  s.version          = '0.1.0'
  s.summary          = "Flutter bindings for Apple's Foundation Models framework."
  s.description      = <<-DESC
Flutter bindings for Apple's Foundation Models framework: the on-device and Private Cloud Compute Apple Intelligence language models.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'apple_ai authors' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'foundation_models/Sources/foundation_models/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
  s.resource_bundles = { 'foundation_models_privacy' => ['foundation_models/Sources/foundation_models/Resources/PrivacyInfo.xcprivacy'] }
end
