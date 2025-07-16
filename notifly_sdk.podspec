Pod::Spec.new do |s|
  s.name             = 'notifly_sdk'
  s.version          = '1.17.2'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY iOS SDK : 1.17.2
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grey Box Inc.' => 'team@greyboxhq.com' }
  s.source           = { :git => 'https://github.com/team-michael/notifly-ios-sdk.git', :tag => s.version.to_s, :submodules => true }

  s.ios.deployment_target = '13.0'
  s.swift_versions = '5.0'
  s.pod_target_xcconfig = { 'IPHONEOS_DEPLOYMENT_TARGET' => '13.0' }

  s.subspec 'Full' do |full|
    full.source_files = ['Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/**/*.{h,swift}']
    full.resource_bundles = {'notifly_sdk_resources' => ['Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/PrivacyInfo.xcprivacy']}
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
