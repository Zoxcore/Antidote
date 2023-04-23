#
# Be sure to run `pod lib lint objcTox.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "objcTox"
  s.version          = "0.7.8"
  s.summary          = "Objective-C wrapper for Tox"
  s.homepage         = "https://github.com/Zoxcore/objcTox"
  s.license          = "MIT"
  s.author           = { "Dmytro Vorobiov" => "d@dvor.me" }
  s.source           = {
      :git => "https://github.com/Zoxcore/objcTox.git",
      :tag => s.version.to_s,
      :submodules => false
  }

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.9'
  s.requires_arc = true

  s.source_files = 'Classes/**/*.{m,h}'
  s.public_header_files = 'Classes/Public/**/*.h'
  s.dependency 'toxcore', '~> 0.2.12'
  s.dependency 'TPCircularBuffer', '~> 0.0.1'
  s.dependency 'CocoaLumberjack', '1.9.2'
  s.dependency 'Realm', '10.38.0'

  s.resource_bundle = {
      'objcTox' => 'Classes/Public/Manager/nodes.json'
  }
end
