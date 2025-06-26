import Foundation
import UIKit


public protocol ProviderCreator {
    var name: String { get }
    var variant: String? { get }

    func create(sdkConfig: SdkConfig, providerConfig: ProviderConfig, reachFiveApi: ReachFiveApi, clientConfigResponse: ClientConfigResponse) -> Provider
}

public protocol Provider {
    var name: String { get }
    func login(scope: [String]?, origin: String, viewController: UIViewController?) async -> Result<AuthToken, ReachFiveError>
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool
    func logout() async -> Result<(), ReachFiveError>
}

public class ProviderConfig: Codable {
    public let provider: String
    public let variant: String
    public let clientId: String?
    public let universalLink: String?
    public let scope: [String]?
    
    public var providerWithVariant: String { provider + ":" + variant }
}

public class SdkConfig {
    public let domain: String
    public let clientId: String
    
    /// Alias for the `redirectUri`
    public let scheme: String
    
    ///The scheme. Defaults to `reachfive-clientId`
    public let baseScheme: String
    /// The redirect URI for passwordless. Defaults to `reachfive-clientId://callback`
    public let redirectUri: String
    /// The redirect URI for MFA. Defaults to `reachfive-clientId://mfa`
    public let mfaUri: String
    /// The redirect URI for Account Recovery. Defaults to `reachfive-clientId://account-recovery`
    public let accountRecoveryUri: String
    /// The redirect URI for email verification. Defaults to `reachfive-clientId://email-verification`
    public let emailVerificationUri: String
    
    public init(domain: String, clientId: String, scheme: String? = nil, baseScheme: String? = nil, mfaUri: String? = nil, accountRecoveryUri: String? = nil, emailVerificationUri: String? = nil) {
        self.domain = domain
        self.clientId = clientId
        self.baseScheme = baseScheme ?? "reachfive-\(clientId)"
        self.scheme = scheme ?? "\(self.baseScheme)://callback"
        self.redirectUri = self.scheme
        self.mfaUri = mfaUri ?? "\(self.baseScheme)://mfa"
        self.emailVerificationUri = emailVerificationUri ?? "\(self.baseScheme)://email-verification"
        self.accountRecoveryUri = accountRecoveryUri ?? "\(self.baseScheme)://account-recovery"
    }
}

public class ClientConfigResponse: Codable {
    public let scope: String
    public let sms: Bool
    
    public init(scope: String, sms: Bool) {
        self.scope = scope
        self.sms = sms
    }
}

public enum ReachFiveError: Error, CustomStringConvertible {
    /// debug friendly message
    public var description: String {
        ""
    }

    /// user friendly message
    public func message() -> String {
        ""
    }

    case RequestError(apiError: ApiError)
    case AuthFailure(reason: String, apiError: ApiError? = nil)
    /// Returned after signin requests. Either the system doesn't find any credentials and the authentification ends silently, or the user cancels the request.
    /// This is a good time to show a traditional login form, or ask the user to create an account.
    case AuthCanceled
    case TechnicalError(reason: String, apiError: ApiError? = nil)
}

public class ApiError: Codable, CustomStringConvertible {
    public var description: String {
        ""
    }

    public let error: String?
    public let errorId: String?
    public let errorUserMsg: String?
    public let errorMessageKey: String?
    public let errorDescription: String?
    public let errorDetails: [FieldError]?

    public init(error: String? = nil,
                errorId: String? = nil,
                errorUserMsg: String? = nil,
                errorMessageKey: String? = nil,
                errorDescription: String? = nil,
                errorDetails: [FieldError]? = nil) {
        self.error = error
        self.errorId = errorId
        self.errorUserMsg = errorUserMsg
        self.errorMessageKey = errorMessageKey
        self.errorDescription = errorDescription
        self.errorDetails = errorDetails
    }
}

public class FieldError: Codable, CustomStringConvertible {
    public var description: String {
       ""
    }

    public let field: String?
    public let message: String?
    public let code: String?

    public init(field: String? = nil, message: String? = nil, code: String? = nil) {
        self.field = field
        self.message = message
        self.code = code
    }
}

public class ReachFiveApi {
    public func loginWithProvider(
        loginProviderRequest: LoginProviderRequest
    ) async -> Result<AccessTokenResponse, ReachFiveError> {
        .success(AccessTokenResponse.init(idToken: nil, accessToken: "", refreshToken: nil, code: nil, tokenType: nil, expiresIn: nil, error: nil, errorDescription: nil))
    }
    
    public func authWithCode(authCodeRequest: AuthCodeRequest) async -> Result<AccessTokenResponse, ReachFiveError> {
        .success(AccessTokenResponse.init(idToken: nil, accessToken: "", refreshToken: nil, code: nil, tokenType: nil, expiresIn: nil, error: nil, errorDescription: nil))
    }
    
    public func authorize(params: [String: String?]?) async -> Result<String, ReachFiveError> {
        .success("")
    }
}
public class Pkce: NSObject, Codable {
    public let codeVerifier: String = ""
    public let codeChallenge: String = ""
    public let codeChallengeMethod: String = ""

    init(codeVerifier: String) {
    }
    
    public static func generate() -> Pkce {
        return Pkce(codeVerifier: "")
    }
    
    static func random(length: Int) -> String {
        return ""
    }
    
    public override var description: String {
        "PKCE"
    }
}

public class AuthCodeRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let code: String
    public let grantType: String
    public let redirectUri: String
    public let codeVerifier: String?

    public convenience init(
        clientId: String,
        code: String,
        redirectUri: String,
        pkce: Pkce? = nil
    ) {
        self.init(
            clientId: clientId,
            code: code,
            grantType: "authorization_code",
            redirectUri: redirectUri,
            codeVerifier: pkce?.codeVerifier
        )
    }

    public init(
        clientId: String,
        code: String,
        grantType: String,
        redirectUri: String,
        codeVerifier: String?
    ) {
        self.clientId = clientId
        self.code = code
        self.grantType = grantType
        self.redirectUri = redirectUri
        self.codeVerifier = codeVerifier
    }
}

protocol DictionaryEncodable: Encodable {}

extension DictionaryEncodable {
    func dictionary() -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let json = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any]
        else {
            return nil
        }
        return dict
    }
}

public class LoginProviderRequest: Codable, DictionaryEncodable {
    public let provider: String
    public let providerToken: String?
    public let code: String?
    public let origin: String?
    public let clientId: String
    public let responseType: String
    public let scope: String
    
    public init(provider: String, providerToken: String?, code: String?, origin: String?, clientId: String, responseType: String, scope: String) {
        self.provider = provider
        self.providerToken = providerToken
        self.code = code
        self.origin = origin
        self.clientId = clientId
        self.responseType = responseType
        self.scope = scope
    }
}

extension Result {
    //TODO: revenir à la fin quand le SDK compile et voir si je peux renommer cette méthode en « flatMap »
    func flatMapAsync<NewSuccess>(_ transform: (Success) async -> Result<NewSuccess, Failure>) async -> Result<NewSuccess, Failure> where NewSuccess : ~Copyable {
        switch self {
        case .success(let value):
            return await transform(value)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    public consuming func flatMapErrorAsync<NewFailure>(_ transform: (Failure) async -> Result<Success, NewFailure>) async -> Result<Success, NewFailure> where NewFailure : Error {
        switch self {
        case .success(let value):
            return .success(value)
        case .failure(let error):
            return await transform(error)
        }
    }
}

public class AccessTokenResponse: Codable {
    public let idToken: String?
    public let accessToken: String
    public let refreshToken: String?
    public let code: String?
    public let tokenType: String?
    public let expiresIn: Int?
    public let error: String?
    public let errorDescription: String?
    
    public init(idToken: String?, accessToken: String, refreshToken: String?, code: String?, tokenType: String?, expiresIn: Int?, error: String?, errorDescription: String?) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.code = code
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.error = error
        self.errorDescription = errorDescription
    }
}

public class AuthToken: Codable {
    public let idToken: String?
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String?
    public let expiresIn: Int?
//    public let user: OpenIdUser?
    
    public init(
        idToken: String?,
        accessToken: String,
        refreshToken: String?,
        tokenType: String?,
        expiresIn: Int?,
//        user: OpenIdUser?
    ) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
//        self.user = user
    }
    
    public static func fromOpenIdTokenResponse(_ openIdTokenResponse: AccessTokenResponse) -> Result<AuthToken, ReachFiveError> {
        .success(AuthToken.init(idToken: nil, accessToken: "", refreshToken: nil, tokenType: nil, expiresIn: nil))
    }
}
