Pod::Spec.new do |s|
  s.name             = 'notifly_sdk'
  s.version          = '1.0.2'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY IOS SDK : 1.0.2
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'daeseong' => 'daeseong@workmichael.com' }
  s.source           = { :git => 'https://github.com/team-michael/notifly-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'

  s.source_files = 'notifly-ios-sdk/notifly-ios-sdk/**/*'
  s.swift_versions = '5.0'

  s.dependency 'Firebase', '~> 9.6.0'
  s.dependency 'FirebaseMessaging'

end
