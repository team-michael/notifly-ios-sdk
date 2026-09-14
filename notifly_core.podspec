Pod::Spec.new do |s|
  s.name             = 'notifly_core'
  s.version          = '2.8.0-alpha.1'
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
    :sha256 => '22af0e1224033b39e34ced8e333a8d37ac3fe741a6156a6a5dfb0bffae8b569f'
  }

  s.ios.deployment_target = '15.0'
  s.swift_versions = '5.0'
  s.vendored_frameworks = 'NotiflyCore.xcframework'
end
