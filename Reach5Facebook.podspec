require_relative 'version'

Pod::Spec.new do |spec|
  spec.name                  = "Reach5Facebook"
  spec.version               = $VERSION
  spec.summary               = "Reachfive Identity SDK for Facebook Login"
  spec.description           = <<-DESC
      Reachfive Identity SDK for iOS integrating with Facebook Login
  DESC
  spec.homepage              = "https://github.com/ReachFive/reachfive-ios-facebook"
  spec.license               = { :type => "MIT", :file => "LICENSE" }
  spec.author                = "ReachFive"
  spec.authors               = { "François" => "francois.devemy@reach5.co", "Pierre" => "pierre.bar@reach5.co" }
  spec.swift_versions        = ["5"]
  spec.source                = { :git => "https://github.com/ReachFive/reachfive-ios-facebook.git", :tag => "#{spec.version}" }
  spec.source_files          = "Sources/Classes/**/*.*"
  spec.platform              = :ios
  spec.ios.deployment_target = $IOS_DEPLOYMENT_TARGET
  spec.resource_bundle = {
    'Reach5Facebook' => ['Sources/PrivacyInfo.xcprivacy']
  }

  spec.prepare_command = <<-CMD
    VERSION=$(ruby -r ./version.rb -e 'puts $VERSION')
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Sources/Info.plist
  CMD

#TODO:   spec.dependency 'Reach5', '>= 7.1.5', '< 9'
  spec.dependency 'FBSDKCoreKit', '~> 17.4.0'
  spec.dependency 'FBSDKLoginKit', '~> 17.4.0'
end
