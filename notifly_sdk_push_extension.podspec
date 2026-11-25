Pod::Spec.new do |s|
  s.name             = 'notifly_sdk_push_extension'
  s.version          = '2.8.5'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY iOS Push Extension SDK : 2.8.5
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grey Box Inc.' => 'team@greyboxhq.com' }
  s.source           = { :git => 'https://github.com/team-michael/notifly-ios-sdk.git', :tag => s.version.to_s  }

  s.ios.deployment_target = '15.0'
  s.pod_target_xcconfig = { 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0' }
  s.swift_versions = '5.0'
  s.source_files = [
      'Sources/notifly_sdk/Interface/NotificationServiceExtension.swift',
      'Sources/notifly_sdk/Interface/Models/**/*.swift',
      'Sources/notifly_sdk/NotiflyExtension/**/*.swift',
      'Sources/notifly_sdk/NotiflyUtil/**/*.swift',
      'Sources/notifly_sdk/Shared/**/*.swift'
  ]
end
