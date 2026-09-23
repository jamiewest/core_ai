#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'media_intelligence'
  s.version          = '0.1.0'
  s.summary          = "Flutter bindings for Apple's MediaIntelligence framework."
  s.description      = <<-DESC
Flutter bindings for Apple's MediaIntelligence framework: face grouping and video analysis.
                       DESC
  s.homepage         = 'https://github.com/jamiewest/core_ai'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'Jamie West'
  s.source           = { :path => '.' }
  s.source_files     = 'media_intelligence/Sources/media_intelligence/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
  s.resource_bundles = { 'media_intelligence_privacy' => ['media_intelligence/Sources/media_intelligence/Resources/PrivacyInfo.xcprivacy'] }
end
