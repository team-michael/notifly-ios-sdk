Pod::Spec.new do |s|
  s.name             = 'notifly_sdk_push_extension'
  s.version          = '2.2.0'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY iOS Push Extension SDK : 2.2.0
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grey Box Inc.' => 'team@greyboxhq.com' }
  s.source           = { :git => 'https://github.com/team-michael/notifly-ios-sdk.git', :tag => s.version.to_s  }

  s.ios.deployment_target = '15.0'
  s.pod_target_xcconfig = { 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0' }
  s.swift_versions = '5.0'
  s.source_files = [
      'Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/NotiflyExtension/**/*.swift',
      'Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/NotiflyUtil/**/*.swift'
  ]
end
