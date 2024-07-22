# Changelog

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

## v6.2.0
### New features
- Add privacy manifest.

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
