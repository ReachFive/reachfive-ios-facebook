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

    //TODO faire l'ancienne méthode si on a les droits de tracking
    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) -> Future<AuthToken, ReachFiveError> {
        
        let tracking: LoginTracking =
        if #available(macCatalyst 14, *), ATTrackingManager.trackingAuthorizationStatus == ATTrackingManager.AuthorizationStatus.authorized {
            .enabled
        } else {
            .limited
        }

        let promise = Promise<AuthToken, ReachFiveError>()

        // Facebook semble incapable de donner le jeton correspondant à la dernière connexion.
        // Que celui-ci soit encore frais ou expiré, tant qu'on ne fait pas un logout on obtient toujours le même lors de l'appel à AuthenticationToken.current.
        // C'est non seulement très peu pratique si on devait parser le jeton pour en extraire l'exp,
        // mais à cause du nonce, il faudrait pouvoir enregistrer ce dernier et le ressortir à chaque fois.
        // C'est pourquoi on fait un logout à chaque fois.
        LoginManager().logOut()

        //TODO sortir le générateur aléatoire dans une classe à part
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
        print("configuration.tracking \(configuration.tracking)")

        LoginManager().logIn(configuration: configuration) { (res: LoginResult) in
            switch res {
            case let .failed(error):
                promise.failure(.TechnicalError(reason: error.localizedDescription))
                break
            case .cancelled:
                promise.failure(.AuthCanceled)
                break
            case let .success(_, _, token):

                print("access token : \(token?.tokenString)")
                let authenticationTokenString = AuthenticationToken.current?.tokenString
                
                if tracking == .enabled, let token {
                    let loginProviderRequest = self.createLoginRequest(token: token, origin: origin, scope: scope)
                    promise.completeWith(self.reachFiveApi
                        .loginWithProvider(loginProviderRequest: loginProviderRequest)
                        .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) }))
                } else {
                    let pkce: Pkce = Pkce.generate()
                    //TODO factoriser ça (avec celui pour Apple et celui du web)
                    let params: [String: String?] = [
                        "provider": self.providerConfig.providerWithVariant,
                        "client_id": self.sdkConfig.clientId,
                        "id_token": authenticationTokenString,
                        "response_type": "code",
                        "redirect_uri": self.sdkConfig.scheme,
                        "scope": (scope ?? []).joined(separator: " "),
                        "code_challenge": pkce.codeChallenge,
                        "code_challenge_method": pkce.codeChallengeMethod,
                        "nonce": nonce.codeVerifier,
                        "origin": origin,
                    ]
                    promise.completeWith(self.reachFiveApi.authorize(params: params).flatMap({ self.authWithCode(code: $0, pkce: pkce) }))
                }
            }
        }

        return promise.future
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
