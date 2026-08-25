# Changelog

## Unreleased

## v9.0.0

### Breaking changes
- Requires Reach5 11.0.0 or later, whose `Provider` protocol this version implements.
- `login` takes a `presenting: Presentation` parameter instead of `viewController: UIViewController?`, although it is not used (the Facebook SDK manages its own presentation).
- CocoaPods support is dropped, the SDK is distributed exclusively with Swift Package Manager.

### New features
- Support for Fast App Switch configuration

### Other changes
- A limited login with no explicit `scope` now requests the scope of the client configuration, as the classic login already did, instead of an empty scope.

### Dependencies
- Updated Facebook from 17.4 to 18.1

## v8.0.1
### Bug fixes
- Support Reach5 dependency version for new major version

## v8.0.0
### Breaking changes
- Use Swift's native concurrency model instead of Futures. See the migration guide at https://developer.reachfive.com/sdk-ios/guides/migrate-futures.html

## v7.2.2
### Feature
- Allow SPM to depend on Reach5 version up to 8

## v7.2.1
### Bug fixes
- Fix dependency version to Reach5

## v7.2.0
### New features
- Support for Facebook limited login alongside classic Facebook Login.

  Choose which one you prefer with `FacebookProvider(prefersLoginTracking: .enabled)` or `FacebookProvider(prefersLoginTracking: .limited)`

## v7.1.1
### New features
- Fix variant communication with backend

## v7.1.0
### New features
- Support choosing a variant


## v7.0.0
### Breaking changes
- New name for the Pod: `Reach5Facebook`

Change all your import from
```
import IdentitySdkFacebook
```
to
```
import Reach5Facebook
```

### New features
- Support for Swift Package Manager
- Add privacy manifest.

## v6.2.0
### Dependencies
- Updated Facebook from 16.2 to 17.0

## v6.0.0

Warning: There are Breaking Changes

### Breaking changes
- Add a new method in `Provider` and `ReachFive`: `application(_:continue:restorationHandler:)` to handle universal links
- Remove an obsolete method in `Provider` and `ReachFive`: `application(_:open:sourceApplication:annotation:)`

### Dependencies
- Updated Facebook from 14.1 to 16.2

## v5.7.0

Warning: There are Breaking Changes

### Breaking changes
- The SDK mandates a minimum version of iOS 13
- New method `Provider.application(_:didFinishLaunchingWithOptions:)` to call at startup to initialize the social providers
- New required key `FacebookClientToken` to configure Facebook Login
- Parameter `viewController` in `Provider.login(scope:origin:viewController:)` is now mandatory
- Some error messages may have changed

### New features
- Don't ask again to confirm app access for Facebook Login when a user still has a valid Access Token

### Other changes
- Update dependency `FBSDKCoreKit` from 9.0.0 to 14.1.0
- Update dependency `FBSDKLoginKit` from 9.0.0 to 14.1.0
- Remove dependencies `FacebookCore`, `FacebookLogin`

## v5.5.0
- Update `FBSDKCoreKit` and `FBSDKLoginKit` to version 9.x

## v5.2.0
### Breaking changes
- `RequestErrors` is renamed to `ApiError`
- `ReachFiveError.AuthFailure` contain an optional parameter of type `ApiError`
## v5.1.0
### Breaking changes
- The login with provider requires now the `scope` parameter `login(scope: [String]?, origin: String, viewController: UIViewController?).`

## v5.0.0

- Use [Futures](https://github.com/Thomvis/BrightFutures) instead of callbacks, we use the [BrightFutures](https://github.com/Thomvis/BrightFutures) library

### Breaking changes
We use Future instead callbacks, you need to transform yours callbacks into the Future
```swift
AppDelegate.reachfive()
  .loginWithPassword(username: email, password: password)
  .onSuccess { authToken in
    // Handle success
  }
  .onFailure { error in
    // Handle error
  }
```

instead of

```swift
AppDelegate.reachfive()
  .loginWithPassword(
    username: email,
    password: password,
    callback: { response in
        switch response {
          case .success(let authToken):
            // Handle success
          case .failure(let error):
            // handle error
          }
    }
)
```

## v4.0.0

### 9th July 2019

### Changes

New modular version of the Identity SDK iOS:

- [`IdentitySdkCore`](IdentitySdkCore)
- [`IdentitySdkFacebook`](IdentitySdkFacebook)
- [`IdentitySdkGoogle`](IdentitySdkGoogle)
- [`IdentitySdkWebView`](IdentitySdkWebView)
