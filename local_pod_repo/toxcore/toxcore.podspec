#
# Be sure to run `pod lib lint toxcore.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "toxcore"
  s.version          = "0.2.18"
  s.summary          = "Cocoapods wrapper for toxcore"
  s.homepage         = "https://github.com/Zoxcore/toxcore"
  s.license          = 'GPLv3'
  s.author           = { "Dmytro Vorobiov" => "d@dvor.me" }
  s.source           = {
      :git => "https://github.com/Zoxcore/toxcore.git",
      :tag => s.version.to_s,
      :submodules => true
  }

  s.pod_target_xcconfig = { 'ENABLE_BITCODE' => 'NO', 'OTHER_LDFLAGS' => '-read_only_relocs suppress' }

  s.ios.deployment_target = '7.0'
  s.osx.deployment_target = '10.9'
  s.requires_arc = true

  # Preserve the layout of headers in the toxcore directory
  s.header_mappings_dir = 'toxcore'

  s.source_files = 'toxcore/toxcore/*.{m,h}', 'toxcore/toxencryptsave/*.{m,h}', 'toxcore/toxav/*.{m,h}', 'toxcore/toxcore/events/*.{m,h}'

  # s.dependency 'libopus-patched-config', '1.1'
  s.dependency 'libopus-static', '1.3.1'
  s.dependency 'libsodium', '~> 1.0.12'
  # s.dependency 'msgpack-c'

  s.ios.vendored_frameworks = 'ios/vpx.framework'
  s.osx.vendored_frameworks = 'osx/vpx.framework'
  s.xcconfig = { 'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}"'}

end
