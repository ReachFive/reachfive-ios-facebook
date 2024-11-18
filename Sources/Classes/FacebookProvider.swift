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

    public init(variant: String? = nil) {
        self.variant = variant
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
            clientConfigResponse: clientConfigResponse
        )
    }
}

public class ConfiguredFacebookProvider: NSObject, Provider {
    public var name: String = FacebookProvider.NAME

    var sdkConfig: SdkConfig
    var providerConfig: ProviderConfig
    var reachFiveApi: ReachFiveApi
    var clientConfigResponse: ClientConfigResponse

    public init(
        sdkConfig: SdkConfig,
        providerConfig: ProviderConfig,
        reachFiveApi: ReachFiveApi,
        clientConfigResponse: ClientConfigResponse
    ) {
        self.sdkConfig = sdkConfig
        self.providerConfig = providerConfig
        self.reachFiveApi = reachFiveApi
        self.clientConfigResponse = clientConfigResponse
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
        }

        // Facebook semble incapable de donner le jeton d'identité (AuthenticationToken.current) correspondant à la dernière connexion.
        // Que celui-ci soit encore frais ou expiré, tant qu'on ne fait pas un logout on obtient toujours le même lors de l'appel à AuthenticationToken.current.
        // C'est non seulement très peu pratique si on devait parser le jeton pour en extraire l'exp,
        // mais à cause du nonce, il faudrait pouvoir enregistrer ce dernier et le ressortir à chaque fois.
        // C'est pourquoi on fait un logout à chaque fois.
        LoginManager().logOut()
        return doFacebookLogin(scope: scope, origin: origin, viewController: viewController)
    }

    private func doFacebookLogin(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) -> Future<AuthToken, ReachFiveError> {

        let tracking: LoginTracking =
        if #available(iOS 14, macCatalyst 14, *), ATTrackingManager.trackingAuthorizationStatus == ATTrackingManager.AuthorizationStatus.authorized {
            .enabled
        } else {
            //TODO est-ce que c'est vraiment le bon comportement pour iOS <= 13 ?
            .limited
        }

        let promise = Promise<AuthToken, ReachFiveError>()

        let nonce = Pkce.generate()

        guard let configuration: LoginConfiguration = LoginConfiguration(
            permissions: providerConfig.scope ?? ["email", "public_profile"],
            tracking: tracking,
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
            case let .success(_, _, token):
                if let token {
                    // On suppose que si on a ce jeton c'est qu'on est dans une situation de connexion classique
                    promise.completeWith(self.accessTokenLogin(token: token, origin: origin, scope: scope))
                } else if let token = AuthenticationToken.current {
                    // connexion limitée
                    promise.completeWith(self.identityTokenLogin(token: token, nonce: nonce, origin: origin, scope: scope))
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
