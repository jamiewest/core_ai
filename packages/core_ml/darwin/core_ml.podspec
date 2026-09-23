#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'core_ml'
  s.version          = '0.1.0'
  s.summary          = "Flutter bindings for Apple's Core ML framework."
  s.description      = <<-DESC
Flutter bindings for Apple's Core ML framework: run .mlmodel and .mlpackage models.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'apple_ai authors' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'core_ml/Sources/core_ml/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  # CoreML is not listed as a framework dependency. The sources use it behind
  # `#if canImport(CoreML)` and `@available(iOS 18, macOS 15)`, so autolinking
  # weak-links it; on older systems `isSupported()` returns false.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
  s.resource_bundles = { 'core_ml_privacy' => ['core_ml/Sources/core_ml/Resources/PrivacyInfo.xcprivacy'] }
end
