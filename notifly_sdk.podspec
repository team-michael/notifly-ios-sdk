Pod::Spec.new do |s|
  s.name             = 'notifly_sdk'
  s.version          = '2.8.5'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY iOS SDK : 2.8.5
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
    full.source_files = ['Sources/notifly_sdk/**/*.{h,swift}']
    full.resource_bundles = {'notifly_sdk_resources' => ['Sources/notifly_sdk/PrivacyInfo.xcprivacy']}
    full.dependency 'FirebaseCore', '>= 10.0.0', '< 20.0.0'
    full.dependency 'FirebaseMessaging', '>= 10.0.0', '< 20.0.0'
    full.dependency 'notifly_core', s.version.to_s
  end

  s.subspec 'Extension' do |e|
    e.source_files = [
        'Sources/notifly_sdk/Interface/NotificationServiceExtension.swift',
        'Sources/notifly_sdk/Interface/Models/**/*.swift',
        'Sources/notifly_sdk/NotiflyExtension/**/*.swift',
        'Sources/notifly_sdk/NotiflyUtil/**/*.swift',
        'Sources/notifly_sdk/Shared/**/*.swift'
    ]
  end
end
