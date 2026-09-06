Pod::Spec.new do |s|
  s.name             = 'notifly_sdk'
  s.version          = '2.6.2'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY iOS SDK : 2.6.2
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grey Box Inc.' => 'team@greyboxhq.com' }
  s.source           = { :git => 'https://github.com/team-michael/notifly-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_versions = '5.0'
  s.default_subspec = 'Full'
  s.pod_target_xcconfig = { 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0' }

  s.subspec 'Full' do |full|
    full.vendored_frameworks = 'Artifacts/notifly_sdk.xcframework'
    full.dependency 'FirebaseCore', '>= 10.0.0', '< 20.0.0'
    full.dependency 'FirebaseMessaging', '>= 10.0.0', '< 20.0.0'
  end

  s.subspec 'Extension' do |e|
    e.source_files = [
        'Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/NotiflyExtension/**/*.swift',
        'Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/NotiflyUtil/**/*.swift'
    ]
  end
end
