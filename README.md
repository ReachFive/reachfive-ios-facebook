<p align="center">
 <img src="https://www.reachfive.com/hubfs/5399904/Logo-ReachFive.svg" alt="Reach5 Logo" width="700" height="192"/>
</p>

[![CircleCI](https://circleci.com/gh/ReachFive/reachfive-ios-facebook/tree/master.svg?style=svg)](https://circleci.com/gh/ReachFive/reachfive-ios-facebook/tree/master)
[![Download](https://img.shields.io/cocoapods/v/Reach5Facebook.svg?style=flat) ](https://cocoapods.org/pods/Reach5Facebook)

# ReachFive Identity iOS SDK for Facebook Login

## Installation

This project is dependent on the primary Reach5 component found at https://github.com/ReachFive/reachfive-ios


### Cocoapods

Add the following line to your **Podfile**:

```
pod 'Reach5Facebook'
```

### Swift Package Manager
Open the following menu item in Xcode:

**File > Add Package Dependencies...**

In the **Search or Enter Package URL** search box enter this URL:

https://github.com/ReachFive/reachfive-ios-facebook.git

Then, select the dependency rule and press **Add Package**.

Or directly add it to the dependencies value of your Package.swift or the Package list in Xcode

```swift
dependencies: [
    .package(url: "https://github.com/ReachFive/reachfive-ios-facebook.git", .upToNextMajor(from: "7.0.0"))
]
```

## XCode

Open the project folder to view it as a package project, not the .xcodeproj or .xcworkspace which makes them seen as a Pod project

## Usage
Refer to the [public documentation](https://developer.reachfive.com/sdk-ios/index.html) to install the SDKs and to initialize your ReachFive client.

The basics are:

- Configuration:

```swift
let reachfive: ReachFive = ReachFive(sdkConfig: sdkConfig, providersCreators: [FacebookProvider()])
```

- Initialisation:

Call this method (that makes a network call) inside the corresponding method of `UIApplicationDelegate`

```swift
reachfive.application(application, didFinishLaunchingWithOptions: launchOptions)
```


## Documentation

You'll find the documentation of the methods exposed on https://developer.reachfive.com/sdk-ios/index.html.

## Changelog

Please refer to [changelog](CHANGELOG.md) to see the descriptions of each release.

## License

[MIT](LICENSE) © [ReachFive](https://reachfive.co/)
