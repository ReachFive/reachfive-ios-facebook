import Foundation
import UIKit
import IdentitySdkCore
import BrightFutures
import FBSDKLoginKit

public class FacebookProvider: ProviderCreator {
    public static var NAME: String = "facebook"
    
    public var name: String = NAME
    
    public init() {}
    
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
            let loginProviderRequest = createLoginRequest(token: token, origin: origin, scope: scope)
            return reachFiveApi
                .loginWithProvider(loginProviderRequest: loginProviderRequest)
                .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
        }
        
        let promise = Promise<AuthToken, ReachFiveError>()
        LoginManager().logIn(permissions: providerConfig.scope ?? ["email", "public_profile"], from: viewController) { (result, error) in
            guard let result = result else {
                let reason = error == nil ? "No result" : error!.localizedDescription
                promise.failure(.TechnicalError(reason: reason))
                return
            }
            if (result.isCancelled) {
                promise.failure(.AuthCanceled)
            } else {
                let loginProviderRequest = self.createLoginRequest(token: result.token, origin: origin, scope: scope)
                promise.completeWith(self.reachFiveApi
                    .loginWithProvider(loginProviderRequest: loginProviderRequest)
                    .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) }))
            }
        }
        
        return promise.future
    }
    
    private func createLoginRequest(token: AccessToken?, origin: String, scope: [String]?) -> LoginProviderRequest {
        LoginProviderRequest(
            provider: providerConfig.provider,
            providerToken: token?.tokenString,
            code: nil,
            origin: origin,
            clientId: sdkConfig.clientId,
            responseType: "token",
            scope: scope != nil ? scope!.joined(separator: " ") : self.clientConfigResponse.scope
        )
    }
    
    public func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        FBSDKCoreKit.ApplicationDelegate.shared.application(application, open: url, sourceApplication: sourceApplication, annotation: annotation)
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
    
    public func logout() -> Future<(), ReachFiveError> {
        LoginManager().logOut()
        return Future.init(value: ())
    }
}
