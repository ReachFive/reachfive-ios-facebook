require_relative 'version'

Pod::Spec.new do |spec|
  spec.name                  = "IdentitySdkFacebook"
  spec.version               = $VERSION
  spec.summary               = "ReachFive IdentitySdkFacebook"
  spec.description           = <<-DESC
      ReachFive Identity Sdk Facebook
  DESC
  spec.homepage              = "https://github.com/ReachFive/reachfive-ios-facebook"
  spec.license               = { :type => "MIT", :file => "LICENSE" }
  spec.author                = "ReachFive"
  spec.authors               = { "François" => "francois.devemy@reach5.co", "Pierre" => "pierre.bar@reach5.co" }
  spec.swift_versions        = ["5"]
  spec.source                = { :git => "https://github.com/ReachFive/reachfive-ios-facebook.git", :tag => "#{spec.version}" }
  spec.source_files          = "IdentitySdkFacebook/Classes/**/*.*"
  spec.platform              = :ios
  spec.ios.deployment_target = $IOS_DEPLOYMENT_TARGET

  spec.dependency 'IdentitySdkCore'
  spec.dependency 'FBSDKCoreKit', '~> 17.0.0'
  spec.dependency 'FBSDKLoginKit', '~> 17.0.0'
end
