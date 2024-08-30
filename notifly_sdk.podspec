Pod::Spec.new do |s|
  s.name             = 'notifly_sdk'
  s.version          = '1.14.1'
  s.summary          = 'Notifly iOS SDK.'

  s.description      = <<-DESC
  NOTIFLY iOS SDK : 1.14.1
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grey Box Inc.' => 'team@greyboxhq.com' }
  s.source           = { :git => 'https://github.com/team-michael/notifly-ios-sdk.git', :tag => s.version.to_s, :submodules => true }

  s.ios.deployment_target = '13.0'
  s.swift_versions = '5.0'

  s.subspec 'Full' do |full|
    full.source_files = 'Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/**/*'
    full.dependency 'Firebase/Core'
    full.dependency 'FirebaseMessaging'
  end

  s.subspec 'Extension' do |e|
    e.source_files = ['Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/NotiflyExtension/**/*.swift', 'Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/SourceCodes/NotiflyUtil/**/*.swift', 'Sources/Notifly/notifly-ios-sdk/notifly-ios-sdk/PrivacyInfo.xcprivacy']
  end

end
