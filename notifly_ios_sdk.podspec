#
#  Be sure to run `pod spec lint notifly_ios_sdk.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  These will help people to find your library, and whilst it
  #  can feel like a chore to fill in it's definitely to your advantage. The
  #  summary should be tweet-length, and the description more in depth.
  #

  spec.name         = "notifly_ios_sdk"
  spec.version      = "1.0.0"
  spec.summary      = "Notifly iOS SDK"

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  spec.description  = <<-DESC
  notifly_ios_sdk: 1.0.0
                   DESC

  spec.homepage     = "https://github.com/team-michael/notifly-ios-sdk"
  # spec.screenshots  = "www.example.com/screenshots_1.gif", "www.example.com/screenshots_2.gif"

  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author             = { "edenkim00" => "daeseong@workmichael.com" }
  spec.source       = { :git => "https://github.com/team-michael/notifly-ios-sdk.git", :tag => "#{spec.version}" }

  spec.source_files  = "notifly-ios-sdk/**/*"
  spec.ios.deployment_target = "14.0"
  spec.swift_versions = "5.0"
  spec.dependency 'FirebaseMessaging'  # Corrected dependency name

end
