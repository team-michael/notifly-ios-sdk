Pod::Spec.new do |s|
  s.name             = 'notifly_ios_sdk'
  s.version          = '1.0.0'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY IOS SDK : 1.0.0
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'daesoeng' => 'daeseong@workmichael.com' }
  s.source           = { :git => 'https://github.com/team-michael/notifly-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'

  s.source_files = 'notifly-ios-sdk/notifly-ios-sdk/**/*'
  s.swift_versions = '5.0'

  s.dependency 'FirebaseMessaging'  # Corrected dependency name

  # s.resource_bundles = {
  #   'notifly_ios_sdk_dev' => ['notifly_ios_sdk_dev/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
