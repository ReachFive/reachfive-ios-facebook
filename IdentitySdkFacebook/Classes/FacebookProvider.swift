import Foundation
import UIKit
import IdentitySdkCore
import BrightFutures
import FacebookCore
import FacebookLogin
import FBSDKLoginKit

public class FacebookProvider: ProviderCreator {
    public static var NAME: String = "facebook"
    
    public var name: String = NAME
    
    public init() {}

    public func create(sdkConfig: SdkConfig, providerConfig: ProviderConfig, reachFiveApi: ReachFiveApi) -> Provider {
        return ConfiguredFacebookProvider(sdkConfig: sdkConfig, providerConfig: providerConfig, reachFiveApi: reachFiveApi)
    }
}

public class ConfiguredFacebookProvider: NSObject, Provider {
    public var name: String = FacebookProvider.NAME

    var sdkConfig: SdkConfig
    var providerConfig: ProviderConfig
    var reachFiveApi: ReachFiveApi
    
    public init(sdkConfig: SdkConfig, providerConfig: ProviderConfig, reachFiveApi: ReachFiveApi) {
        self.sdkConfig = sdkConfig
        self.providerConfig = providerConfig
        self.reachFiveApi = reachFiveApi
    }
    
    public override var description: String {
        return "Provider: \(name)"
    }
    
    public func login(
        scope: [String],
        origin: String,
        viewController: UIViewController?
    ) -> Future<AuthToken, ReachFiveError> {
        let promise = Promise<AuthToken, ReachFiveError>()
        
        LoginManager().logIn(permissions: [.email, .publicProfile], viewController: viewController) { result in
            switch (result) {
            case .success(_, _, let token):
                let loginProviderRequest = LoginProviderRequest(
                    provider: self.providerConfig.provider,
                    providerToken: token.tokenString,
                    code: nil,
                    origin: origin,
                    clientId: self.sdkConfig.clientId,
                    responseType: "token",
                    scope: scope.joined(separator: " ")
                )
                self.reachFiveApi
                    .loginWithProvider(loginProviderRequest: loginProviderRequest)
                    .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
                    .onSuccess { authToken in
                        promise.success(authToken)
                    }
                    .onFailure { error in
                        promise.failure(error)
                    }
            case .cancelled:
                promise.failure(.AuthCanceled)
            case .failed(let error):
                promise.failure(.TechnicalError(reason: error.localizedDescription))
            }
        }
        
        return promise.future
    }
    
    public func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        return FBSDKCoreKit.ApplicationDelegate.shared.application(application, open: url, sourceApplication: sourceApplication, annotation: annotation)
    }
    
    public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool {
        return FBSDKCoreKit.ApplicationDelegate.shared.application(app, open: url, options: options)
    }
    
    public func applicationDidBecomeActive(_ application: UIApplication) {
        AppEvents.activateApp()
    }
    
    public func logout() -> Future<Void, ReachFiveError> {
        LoginManager().logOut()
        return Future()
    }
}
