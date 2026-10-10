#
# For hosts that build with CocoaPods rather than Swift Package Manager. Both
# compile the same source.
#
Pod::Spec.new do |s|
  s.name             = 'rendel'
  s.version          = '0.29.0'
  s.summary          = 'Rendel for Flutter: the iOS half.'
  s.description      = <<-DESC
Checks the host app's Info.plist for the usage strings the copilot's microphone needs.
                       DESC
  s.homepage         = 'https://rendel.ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Rendel'
  s.source           = { :path => '.' }
  s.source_files = 'rendel/Sources/rendel/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'rendel_privacy' => ['rendel/Sources/rendel/PrivacyInfo.xcprivacy']}
end
