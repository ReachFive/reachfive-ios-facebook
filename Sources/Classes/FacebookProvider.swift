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

    public init(variant: String? = nil, prefersLoginTracking: LoginTracking = .limited) {
        self.variant = variant
        self.prefersLoginTracking = prefersLoginTracking
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
            prefersLoginTracking: prefersLoginTracking
        )
    }
}

public class ConfiguredFacebookProvider: NSObject, Provider {
    public var name: String = FacebookProvider.NAME

    var providerConfig: ProviderConfig
    var clientConfigResponse: ClientConfigResponse

    var prefersLoginTracking: LoginTracking

    /// `weak`: ReachFive retains its providers, a strong reference here would create a
    /// ReachFive ↔ ConfiguredFacebookProvider cycle and the SDK graph would never be deallocated.
    private weak var reachFive: ReachFive?

    public init(
        reachFive: ReachFive,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse,
        prefersLoginTracking: LoginTracking
    ) {
        self.reachFive = reachFive
        self.providerConfig = providerConfig
        self.clientConfigResponse = clientConfigResponse
        self.prefersLoginTracking = prefersLoginTracking
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

        if let token = AccessToken.current, !token.isExpired {
            // User is already logged in.
            do {
                return try await accessTokenLogin(token: token, origin: origin, scope: scope)
            } catch {
                // For instance when the user switched their trackingAuthorizationStatus from .authorized to .denied.
                return try await self.doFacebookLogin(scope: scope, origin: origin)
            }
        }

        return try await doFacebookLogin(scope: scope, origin: origin)
    }

    /// Isolated to the main actor because it drives the Facebook SDK's UI: `logIn` is documented as
    /// having to be called on the main thread ("This method will present a UI to the user and thus
    /// should be called on the main thread")
    @MainActor
    private func doFacebookLogin(
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

        let suggestedTracking: LoginTracking =
        if #available(iOS 14, *), ATTrackingManager.trackingAuthorizationStatus == ATTrackingManager.AuthorizationStatus.authorized {
            prefersLoginTracking
        } else if #unavailable(iOS 14) {
            prefersLoginTracking
        } else {
            .limited
        }

        let nonce = Pkce.generate()

        guard let configuration: LoginConfiguration = LoginConfiguration(
            permissions: providerConfig.scope ?? ["email", "public_profile"],
            // Facebook seems to force .limited when trackingAuthorizationStatus != .authorized
            tracking: suggestedTracking,
            nonce: nonce.codeChallenge
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
                                    return try await self.accessTokenLogin(token: accessToken, origin: origin, scope: scope)
                                } catch _ where identityToken != nil {
                                    // in case we got it wrong, try a limited login
                                    return try await self.identityTokenLogin(token: identityToken!, nonce: nonce, origin: origin, scope: scope)
                                }
                            }
                        } else if let identityToken {
                            // limited login
                            continuation.resume {
                                try await self.identityTokenLogin(token: identityToken, nonce: nonce, origin: origin, scope: scope)
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
    private func accessTokenLogin(token: AccessToken, origin: String, scope: [String]?) async throws -> AuthToken {
        let reachFive = try requireReachFive()
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
    private func identityTokenLogin(token: FBSDKCoreKit.AuthenticationToken, nonce: Pkce, origin: String, scope: [String]?) async throws -> AuthToken {
        try await requireReachFive().login(
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
