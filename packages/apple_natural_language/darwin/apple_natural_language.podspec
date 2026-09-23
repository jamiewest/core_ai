#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'apple_natural_language'
  s.version          = '0.1.0'
  s.summary          = "Flutter bindings for Apple's NaturalLanguage framework."
  s.description      = <<-DESC
Flutter bindings for Apple's NaturalLanguage framework: language identification, tagging, tokenization and embeddings.
                       DESC
  s.homepage         = 'https://github.com/jamiewest/core_ai'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'Jamie West'
  s.source           = { :path => '.' }
  s.source_files     = 'apple_natural_language/Sources/apple_natural_language/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
  s.resource_bundles = { 'apple_natural_language_privacy' => ['apple_natural_language/Sources/apple_natural_language/Resources/PrivacyInfo.xcprivacy'] }
end
