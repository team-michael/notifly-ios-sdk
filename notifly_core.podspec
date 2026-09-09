Pod::Spec.new do |s|
  s.name             = 'notifly_core'
  s.version          = '2.7.0'
  s.summary          = 'Notifly shared Core SDK.'

  s.description      = <<-DESC
  Shared core used by Notifly platform SDKs.
  DESC

  s.homepage         = 'https://github.com/team-michael/notifly-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grey Box Inc.' => 'team@greyboxhq.com' }
  s.source           = {
    :http => "https://github.com/team-michael/notifly-ios-sdk/releases/download/#{s.version}/NotiflyCore.xcframework.zip",
    # Updated together with the SwiftPM checksum by prepare_kmp_core_release.rb.
    :sha256 => '0000000000000000000000000000000000000000000000000000000000000000'
  }

  s.ios.deployment_target = '15.0'
  s.swift_versions = '5.0'
  s.vendored_frameworks = 'NotiflyCore.xcframework'
end
