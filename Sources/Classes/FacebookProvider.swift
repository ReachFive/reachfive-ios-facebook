import Foundation
import UIKit
import Reach5
import FBSDKLoginKit
import AppTrackingTransparency

public class FacebookProvider: ProviderCreator {
    public static var NAME: String = "facebook"

    public var name: String = NAME
    public var variant: String?
    public var prefersLoginTracking: LoginTracking
    public var appSwitch: AppSwitch

    public init(variant: String? = nil, prefersLoginTracking: LoginTracking = .limited, appSwitch: AppSwitch = AppSwitch.enabled) {
        self.variant = variant
        self.prefersLoginTracking = prefersLoginTracking
        self.appSwitch = appSwitch
    }

    public func create(
        reachFive: ReachFive,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse
    ) -> Provider {
        ConfiguredFacebookProvider(
            reachFive: reachFive,
            providerConfig: providerConfig,
            clientConfigResponse: clientConfigResponse,
            prefersLoginTracking: prefersLoginTracking,
            appSwitch: appSwitch
        )
    }
}

public class ConfiguredFacebookProvider: NSObject, Provider {
    public let name: String = FacebookProvider.NAME

    let providerConfig: ProviderConfig
    let clientConfigResponse: ClientConfigResponse

    let prefersLoginTracking: LoginTracking
    let appSwitch: AppSwitch


    /// `weak`: ReachFive retains its providers, a strong reference here would create a
    /// ReachFive ↔ ConfiguredFacebookProvider cycle and the SDK graph would never be deallocated.
    private weak var reachFive: ReachFive?

    public init(
        reachFive: ReachFive,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse,
        prefersLoginTracking: LoginTracking,
        appSwitch: AppSwitch
    ) {
        self.reachFive = reachFive
        self.providerConfig = providerConfig
        self.clientConfigResponse = clientConfigResponse
        self.prefersLoginTracking = prefersLoginTracking
        self.appSwitch = appSwitch
    }

    public override var description: String {
        "Provider: \(name)"
    }

    /// `presenting` is unused: the Facebook SDK manages its own presentation.
    public func login(
        scope: [String]?,
        origin: String,
        presenting: Presentation
    ) async throws -> AuthToken {
        // Read before Facebook's dialog opens, so a deallocated SDK fails the login right away instead of
        // once the user has signed in — `doFacebookLogin` even logs the user out of Facebook first, so
        // failing late would leave them logged out for nothing.
        let reachFive = try requireReachFive()

        // A stored access token is only worth trying while App Tracking Transparency still allows the
        // classic login: Facebook keeps handing it out afterwards, but the backend rejects it.
        if let token = AccessToken.current, !token.isExpired, !trackingForcedToLimited {
            // User is already logged in.
            do {
                return try await accessTokenLogin(reachFive: reachFive, token: token, origin: origin, scope: scope)
            } catch let error as ReachFiveError {
                switch error {
                case .RequestError, .AuthFailure:
                    // The backend rejected the Facebook token, so it is stale: only a new login fixes it.
                    return try await self.doFacebookLogin(reachFive: reachFive, scope: scope, origin: origin)
                case .AuthCanceled, .TechnicalError:
                    // A network or server failure: logging the user out of Facebook and asking them to
                    // consent again fixes neither, and destroys a session that is still valid.
                    throw error
                }
            }
        }

        return try await doFacebookLogin(reachFive: reachFive, scope: scope, origin: origin)
    }

    /// Whether App Tracking Transparency forces the login to `.limited`, whatever the app prefers.
    /// Below iOS 14 there is no such status, so nothing is forced.
    private var trackingForcedToLimited: Bool {
        if #available(iOS 14, *) {
            ATTrackingManager.trackingAuthorizationStatus != .authorized
        } else {
            false
        }
    }

    /// Isolated to the main actor because it drives the Facebook SDK's UI: `logIn` is documented as
    /// having to be called on the main thread ("This method will present a UI to the user and thus
    /// should be called on the main thread")
    @MainActor
    private func doFacebookLogin(
        reachFive: ReachFive,
        scope: [String]?,
        origin: String
    ) async throws -> AuthToken {
        // Facebook seems unable to hand out the identity token (AuthenticationToken.current) matching the last login.
        // cf. https://github.com/facebook/facebook-ios-sdk/issues/1663
        // Fresh or expired, as long as we don't log out, AuthenticationToken.current always returns the same one.
        // Not only is that impractical if we had to parse the token to read its exp, but because of the nonce
        // we would also have to store that nonce and produce it again on every login.
        // Hence the logout before each login.
        self.logout()

        let suggestedTracking: LoginTracking = trackingForcedToLimited ? .limited : prefersLoginTracking

        let nonce = Pkce.generate()

        guard let configuration: LoginConfiguration = LoginConfiguration(
            permissions: providerConfig.scope ?? ["email", "public_profile"],
            // Facebook seems to force .limited when trackingAuthorizationStatus != .authorized
            tracking: suggestedTracking,
            nonce: nonce.codeChallenge,
            appSwitch: appSwitch
        )
        else {
            throw ReachFiveError.TechnicalError(reason: "Couldn't create FBSDKLoginKit.LoginConfiguration")
        }

        return try await withCheckedThrowingContinuation { continuation in
            LoginManager().logIn(configuration: configuration) { (res: LoginResult) in
                Task {
                    switch res {
                    case let .failed(error):
                        continuation.resume(throwing: ReachFiveError.TechnicalError(reason: error.localizedDescription))
                        break
                    case .cancelled:
                        continuation.resume(throwing: ReachFiveError.AuthCanceled)
                        break
                    case let .success(_, _, accessToken):

                        let identityToken = AuthenticationToken.current

                        // An access token always comes back with LoginConfiguration.tracking == .enabled,
                        // but when trackingAuthorizationStatus != .authorized that token is invalid.
                        // It would have been nice to be told the tracking Facebook actually applied.
                        if let accessToken, suggestedTracking == .enabled {
                            // classic login
                            continuation.resume {
                                do {
                                    return try await self.accessTokenLogin(reachFive: reachFive, token: accessToken, origin: origin, scope: scope)
                                } catch _ where identityToken != nil {
                                    // in case we got it wrong, try a limited login
                                    return try await self.identityTokenLogin(reachFive: reachFive, token: identityToken!, nonce: nonce, origin: origin, scope: scope)
                                }
                            }
                        } else if let identityToken {
                            // limited login
                            continuation.resume {
                                try await self.identityTokenLogin(reachFive: reachFive, token: identityToken, nonce: nonce, origin: origin, scope: scope)
                            }
                        } else {
                            continuation.resume(throwing: ReachFiveError.TechnicalError(reason: "No access or identity token from Facebook"))
                        }
                    }
                }
            }
        }
    }

    /// Classic login: exchanges the Facebook access token for a ReachFive token.
    /// Reach5 exposes no higher-level helper for that exchange, hence the direct API call.
    private func accessTokenLogin(reachFive: ReachFive, token: AccessToken, origin: String, scope: [String]?) async throws -> AuthToken {
        let loginProviderRequest = LoginProviderRequest(
            provider: providerConfig.providerWithVariant,
            providerToken: token.tokenString,
            code: nil,
            origin: origin,
            clientId: reachFive.sdkConfig.clientId,
            responseType: "token",
            scope: scope?.joined(separator: " ") ?? clientConfigResponse.scope
        )
        let response = try await reachFive.reachFiveApi.loginWithProvider(loginProviderRequest: loginProviderRequest)
        return try AuthToken.fromOpenIdTokenResponse(response)
    }

    /// Limited login: the core SDK exchanges the Facebook identity token for a ReachFive token,
    /// running the same `/oauth/authorize` then `/oauth/token` exchange as Sign In With Apple.
    private func identityTokenLogin(reachFive: ReachFive, token: FBSDKCoreKit.AuthenticationToken, nonce: Pkce, origin: String, scope: [String]?) async throws -> AuthToken {
        try await reachFive.login(
            withProvider: providerConfig.providerWithVariant,
            idToken: token.tokenString,
            nonce: nonce,
            scope: scope,
            origin: origin
        )
    }

    private func requireReachFive() throws -> ReachFive {
        guard let reachFive else { throw ReachFiveError.TechnicalError(reason: "ReachFive instance was deallocated") }
        return reachFive
    }

    public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        FBSDKCoreKit.ApplicationDelegate.shared.application(app, open: url, options: options)
    }

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FBSDKCoreKit.ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        AppEvents.shared.activateApp()
    }

    public func logout() {
        LoginManager().logOut()
    }
}
