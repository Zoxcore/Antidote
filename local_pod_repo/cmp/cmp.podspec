#
# Be sure to run `pod lib lint toxcore.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "cmp"
  s.version          = "20.0.0"
  s.summary          = "Cocoapods wrapper for cmp"
  s.homepage         = "https://github.com/camgunz/cmp"
  s.license          = 'MIT'
  s.author           = "Zoff"
  s.source           = {
      :git => "https://github.com/camgunz/cmp.git",
      :tag => s.version.to_s,
      :submodules => true
  }

  s.pod_target_xcconfig = { 'ENABLE_BITCODE' => 'NO', 'OTHER_LDFLAGS' => '-read_only_relocs suppress' }

  s.ios.deployment_target = '8.0'
  s.requires_arc = true

  s.source_files = 'cmp/*h', 'cmp/*.c'

end
