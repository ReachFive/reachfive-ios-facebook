import Foundation
import UIKit
import Reach5
import BrightFutures
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
        sdkConfig: SdkConfig,
        providerConfig: ProviderConfig,
        reachFiveApi: ReachFiveApi,
        clientConfigResponse: ClientConfigResponse
    ) -> Provider {
        ConfiguredFacebookProvider(
            sdkConfig: sdkConfig,
            providerConfig: providerConfig,
            reachFiveApi: reachFiveApi,
            clientConfigResponse: clientConfigResponse,
            prefersLoginTracking: prefersLoginTracking
        )
    }
}

public class ConfiguredFacebookProvider: NSObject, Provider {
    public var name: String = FacebookProvider.NAME

    var sdkConfig: SdkConfig
    var providerConfig: ProviderConfig
    var reachFiveApi: ReachFiveApi
    var clientConfigResponse: ClientConfigResponse

    var prefersLoginTracking: LoginTracking

    public init(
        sdkConfig: SdkConfig,
        providerConfig: ProviderConfig,
        reachFiveApi: ReachFiveApi,
        clientConfigResponse: ClientConfigResponse,
        prefersLoginTracking: LoginTracking
    ) {
        self.sdkConfig = sdkConfig
        self.providerConfig = providerConfig
        self.reachFiveApi = reachFiveApi
        self.clientConfigResponse = clientConfigResponse
        self.prefersLoginTracking = prefersLoginTracking
    }

    public override var description: String {
        "Provider: \(name)"
    }

    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) -> Future<AuthToken, ReachFiveError> {

        if let token = AccessToken.current, !token.isExpired {
            // User is already logged in.
            return accessTokenLogin(token: token, origin: origin, scope: scope)
                .recoverWith { _ in
                    // Si l'utilisateur a changé son trackingAuthorizationStatus de .authorized à .denied par exemple.
                    return self.doFacebookLogin(scope: scope, origin: origin, viewController: viewController)
                }
        }

        return doFacebookLogin(scope: scope, origin: origin, viewController: viewController)
    }

    private func doFacebookLogin(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) -> Future<AuthToken, ReachFiveError> {
        // Facebook semble incapable de donner le jeton d'identité (AuthenticationToken.current) correspondant à la dernière connexion.
        // cf. https://github.com/facebook/facebook-ios-sdk/issues/1663
        // Que celui-ci soit encore frais ou expiré, tant qu'on ne fait pas un logout on obtient toujours le même lors de l'appel à AuthenticationToken.current.
        // C'est non seulement très peu pratique si on devait parser le jeton pour en extraire l'exp,
        // mais à cause du nonce, il faudrait pouvoir enregistrer ce dernier et le ressortir à chaque fois.
        // C'est pourquoi on fait un logout à chaque fois.
        LoginManager().logOut()

        let suggestedTracking: LoginTracking =
        if #available(iOS 14, *), ATTrackingManager.trackingAuthorizationStatus == ATTrackingManager.AuthorizationStatus.authorized {
            prefersLoginTracking
        } else if #unavailable(iOS 14) {
            prefersLoginTracking
        } else {
            .limited
        }

        let promise = Promise<AuthToken, ReachFiveError>()

        let nonce = Pkce.generate()

        guard let configuration: LoginConfiguration = LoginConfiguration(
            permissions: providerConfig.scope ?? ["email", "public_profile"],
            // Facebook semble forcer à .limited si trackingAuthorizationStatus != .authorized
            tracking: suggestedTracking,
            nonce: nonce.codeChallenge
        )
        else {
            promise.failure(.TechnicalError(reason: "Couldn't create FBSDKLoginKit.LoginConfiguration"))
            return promise.future
        }

        LoginManager().logIn(configuration: configuration) { (res: LoginResult) in
            switch res {
            case let .failed(error):
                promise.failure(.TechnicalError(reason: error.localizedDescription))
                break
            case .cancelled:
                promise.failure(.AuthCanceled)
                break
            case let .success(_, _, accessToken):

                let identityToken = AuthenticationToken.current

                // On obtient toujours un jeton d'accès avec LoginConfiguration.tracking == .enabled
                // Mais si trackingAuthorizationStatus != .authorized le jeton qu'on obtient est invalide
                // Ç'aurait été bien qu'on eusse accès au tracking effectif fait par Facebook
                if let accessToken, suggestedTracking == .enabled {
                    // connexion classique
                    promise.completeWith(self.accessTokenLogin(token: accessToken, origin: origin, scope: scope)
                        .recoverWith { error in
                            // si jamais on s'est trompé, on tente une connexion limitée
                            if let identityToken {
                                self.identityTokenLogin(token: identityToken, nonce: nonce, origin: origin, scope: scope)
                            } else {
                                Future(error: error)
                            }
                        }
                    )
                } else if let identityToken {
                    // connexion limitée
                    promise.completeWith(self.identityTokenLogin(token: identityToken, nonce: nonce, origin: origin, scope: scope))
                } else {
                    promise.failure(.TechnicalError(reason: "No access or identity token from Facebook"))
                }
            }
        }

        return promise.future
    }

    private func accessTokenLogin(token: AccessToken, origin: String, scope: [String]?) -> Future<AuthToken, ReachFiveError> {
        let loginProviderRequest = createLoginRequest(token: token, origin: origin, scope: scope)
        return reachFiveApi
            .loginWithProvider(loginProviderRequest: loginProviderRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
    }

    private func identityTokenLogin(token: FBSDKCoreKit.AuthenticationToken, nonce: Pkce, origin: String, scope: [String]?) -> Future<AuthToken, ReachFiveError> {
        let pkce: Pkce = Pkce.generate()
        //TODO factoriser ça (avec celui pour Apple et celui du web)
        let params: [String: String?] = [
            "provider": self.providerConfig.providerWithVariant,
            "client_id": self.sdkConfig.clientId,
            "id_token": token.tokenString,
            "response_type": "code",
            "redirect_uri": self.sdkConfig.scheme,
            "scope": (scope ?? []).joined(separator: " "),
            "code_challenge": pkce.codeChallenge,
            "code_challenge_method": pkce.codeChallengeMethod,
            "nonce": nonce.codeVerifier,
            "origin": origin,
        ]
        return self.reachFiveApi.authorize(params: params).flatMap({ self.authWithCode(code: $0, pkce: pkce) })
    }

    private func authWithCode(code: String, pkce: Pkce) -> Future<AuthToken, ReachFiveError> {
        let authCodeRequest = AuthCodeRequest(
            clientId: sdkConfig.clientId,
            code: code,
            redirectUri: sdkConfig.scheme,
            pkce: pkce
        )
        return reachFiveApi
            .authWithCode(authCodeRequest: authCodeRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
    }

    private func createLoginRequest(token: AccessToken, origin: String, scope: [String]?) -> LoginProviderRequest {
        LoginProviderRequest(
            provider: providerConfig.providerWithVariant,
            providerToken: token.tokenString,
            code: nil,
            origin: origin,
            clientId: sdkConfig.clientId,
            responseType: "token",
            scope: scope?.joined(separator: " ") ?? self.clientConfigResponse.scope
        )
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

    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        true
    }

    public func logout() -> Future<(), ReachFiveError> {
        LoginManager().logOut()
        return Future(value: ())
    }
}
