#
# For hosts that build with CocoaPods rather than Swift Package Manager. Both
# compile the same source.
#
Pod::Spec.new do |s|
  s.name             = 'rendel_push'
  s.version          = '0.2.0'
  s.summary          = 'Rendel push: the iOS half, straight to Apple.'
  s.description      = <<-DESC
Asks for notification permission, reads the APNs device token and opens Rendel's pushes. No Firebase.
                       DESC
  s.homepage         = 'https://rendel.ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Rendel'
  s.source           = { :path => '.' }
  s.source_files = 'rendel_push/Sources/rendel_push/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'rendel_push_privacy' => ['rendel_push/Sources/rendel_push/PrivacyInfo.xcprivacy']}
end
