import Foundation
import Security

struct TVClientCredentials: Hashable {
    let clientID: String
    let clientSecret: String
}

struct TVBootstrap: Hashable {
    let credentials: TVClientCredentials
    let visitorData: String?
}

struct TVDeviceAuthorization: Decodable, Hashable {
    let deviceCode: String
    let userCode: String
    let verificationURL: String
    let expiresIn: Int
    let interval: Int

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        deviceCode = try container.decode(String.self, forKey: .deviceCode)
        userCode = try container.decode(String.self, forKey: .userCode)
        verificationURL =
            try container.decodeIfPresent(String.self, forKey: .verificationURL)
            ?? container.decodeIfPresent(String.self, forKey: .verificationURI)
            ?? "https://youtube.com/activate"
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 600
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 3
    }
}

private struct TVTokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let tokenType: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case error
        case errorDescription = "error_description"
    }
}

enum SmartTubeAuthError: LocalizedError {
    case tvPageUnavailable
    case clientScriptNotFound
    case credentialsNotFound
    case invalidResponse
    case denied
    case expired
    case notSignedIn
    case oauth(String)

    var errorDescription: String? {
        switch self {
        case .tvPageUnavailable:
            return "Nepodařilo se načíst YouTube TV."
        case .clientScriptNotFound:
            return "YouTube TV nevrátil přihlašovací skript."
        case .credentialsNotFound:
            return "Nepodařilo se zjistit aktuální YouTube TV přihlašovací údaje."
        case .invalidResponse:
            return "YouTube vrátil neplatnou odpověď."
        case .denied:
            return "Přihlášení bylo zamítnuto."
        case .expired:
            return "Přihlašovací kód vypršel."
        case .notSignedIn:
            return "Nejsi přihlášen k YouTube."
        case .oauth(let message):
            return message
        }
    }
}

enum TubeTVKeychain {
    private static let service = "cz.caseycz.tubetv"

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

actor SmartTubeAuthService {
    static let shared = SmartTubeAuthService()

    // Kept aligned with SmartTube MediaServiceCore TV client.
    static let tvClientName = "TVHTML5"
    static let tvClientVersion = "7.20260901.15.00"
    static let tvUserAgent =
        "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)"
    static let tvReferer = "https://www.youtube.com/tv"

    private let refreshTokenKey = "youtube.refreshToken"
    private let accessTokenKey = "youtube.accessToken"
    private let accessTokenExpiryKey = "youtube.accessTokenExpiry"

    private var cachedBootstrap: TVBootstrap?

    func signedIn() -> Bool {
        TubeTVKeychain.string(for: refreshTokenKey) != nil
    }

    func bootstrap() async throws -> TVBootstrap {
        if let cachedBootstrap {
            return cachedBootstrap
        }

        var request = URLRequest(url: URL(string: Self.tvReferer)!)
        request.timeoutInterval = 20
        request.setValue(Self.tvUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("cs-CZ,cs;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SmartTubeAuthError.tvPageUnavailable
        }

        let visitorData = Self.firstMatch(
            in: html,
            patterns: [
                #"visitorData":"(.*?)""#,
                #"VISITOR_DATA":"(.*?)""#
            ],
            capture: 1
        )

        guard let rawClientURL = Self.firstMatch(
            in: html,
            patterns: [
                #"id="base-js"s+src="(.*?)""#,
                #".src = '(.*?m=base)'"#,
                #".src = '(.*?)';s*..id = 'base-js'"#
            ],
            capture: 1
        ) else {
            throw SmartTubeAuthError.clientScriptNotFound
        }

        let clientURLString = Self.absoluteYouTubeURL(
            from: rawClientURL
                .replacingOccurrences(of: #"/"#, with: "/")
                .replacingOccurrences(of: #"\u0026"#, with: "&")
        )

        guard let clientURL = URL(string: clientURLString) else {
            throw SmartTubeAuthError.clientScriptNotFound
        }

        var scriptRequest = URLRequest(url: clientURL)
        scriptRequest.timeoutInterval = 20
        scriptRequest.setValue(Self.tvUserAgent, forHTTPHeaderField: "User-Agent")
        scriptRequest.setValue(Self.tvReferer, forHTTPHeaderField: "Referer")

        let (scriptData, scriptResponse) = try await URLSession.shared.data(for: scriptRequest)

        guard let scriptHTTP = scriptResponse as? HTTPURLResponse,
              (200..<300).contains(scriptHTTP.statusCode),
              let script = String(data: scriptData, encoding: .utf8) else {
            throw SmartTubeAuthError.clientScriptNotFound
        }

        guard let credentials = Self.extractCredentials(from: script) else {
            throw SmartTubeAuthError.credentialsNotFound
        }

        let result = TVBootstrap(
            credentials: credentials,
            visitorData: visitorData
        )

        cachedBootstrap = result
        return result
    }

    func beginSignIn() async throws -> TVDeviceAuthorization {
        let data = try await bootstrap()

        let payload: [String: Any] = [
            "client_id": data.credentials.clientID,
            "device_id": persistentDeviceID(),
            "model_name": "ytlr::",
            "scope": "http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content"
        ]

        let response = try await postJSON(
            URL(string: "https://www.youtube.com/o/oauth2/device/code")!,
            payload: payload
        )

        return try JSONDecoder().decode(TVDeviceAuthorization.self, from: response)
    }

    func finishSignIn(_ authorization: TVDeviceAuthorization) async throws {
        let data = try await bootstrap()
        let deadline = Date().addingTimeInterval(TimeInterval(authorization.expiresIn))
        let delay = max(authorization.interval, 3)

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(
                nanoseconds: UInt64(delay) * 1_000_000_000
            )

            let payload: [String: Any] = [
                "code": authorization.deviceCode,
                "client_id": data.credentials.clientID,
                "client_secret": data.credentials.clientSecret,
                "grant_type": "http://oauth.net/grant_type/device/1.0"
            ]

            let response = try await postJSON(
                URL(string: "https://www.youtube.com/o/oauth2/token")!,
                payload: payload,
                allowErrorResponse: true
            )

            let token = try JSONDecoder().decode(TVTokenResponse.self, from: response)

            if let refreshToken = token.refreshToken {
                saveTokenResponse(token, refreshToken: refreshToken)
                return
            }

            switch token.error {
            case "authorization_pending":
                continue
            case "slow_down":
                continue
            case "access_denied":
                throw SmartTubeAuthError.denied
            case "expired_token":
                throw SmartTubeAuthError.expired
            case let error?:
                throw SmartTubeAuthError.oauth(
                    token.errorDescription ?? error
                )
            case nil:
                throw SmartTubeAuthError.invalidResponse
            }
        }

        throw SmartTubeAuthError.expired
    }

    func authorizationHeader() async throws -> String {
        if let token = TubeTVKeychain.string(for: accessTokenKey),
           let rawExpiry = TubeTVKeychain.string(for: accessTokenExpiryKey),
           let expiry = TimeInterval(rawExpiry),
           Date(timeIntervalSince1970: expiry) > Date().addingTimeInterval(60) {
            return "Bearer \(token)"
        }

        return "Bearer \(try await refreshAccessToken())"
    }

    func signOut() {
        TubeTVKeychain.delete(refreshTokenKey)
        TubeTVKeychain.delete(accessTokenKey)
        TubeTVKeychain.delete(accessTokenExpiryKey)
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = TubeTVKeychain.string(for: refreshTokenKey) else {
            throw SmartTubeAuthError.notSignedIn
        }

        let data = try await bootstrap()

        let payload: [String: Any] = [
            "refresh_token": refreshToken,
            "client_id": data.credentials.clientID,
            "client_secret": data.credentials.clientSecret,
            "grant_type": "refresh_token"
        ]

        let response = try await postJSON(
            URL(string: "https://www.youtube.com/o/oauth2/token")!,
            payload: payload
        )

        let token = try JSONDecoder().decode(TVTokenResponse.self, from: response)

        guard let accessToken = token.accessToken else {
            throw SmartTubeAuthError.oauth(
                token.errorDescription ?? token.error ?? "Obnovení přihlášení selhalo."
            )
        }

        saveTokenResponse(token, refreshToken: refreshToken)
        return accessToken
    }

    private func saveTokenResponse(
        _ token: TVTokenResponse,
        refreshToken: String
    ) {
        TubeTVKeychain.set(refreshToken, for: refreshTokenKey)

        if let accessToken = token.accessToken {
            TubeTVKeychain.set(accessToken, for: accessTokenKey)
        }

        let expiry = Date()
            .addingTimeInterval(TimeInterval(token.expiresIn ?? 3600))
            .timeIntervalSince1970

        TubeTVKeychain.set(String(expiry), for: accessTokenExpiryKey)
    }

    private func persistentDeviceID() -> String {
        let key = "youtube.deviceID"

        if let stored = UserDefaults.standard.string(forKey: key),
           !stored.isEmpty {
            return stored
        }

        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    private func postJSON(
        _ url: URL,
        payload: [String: Any],
        allowErrorResponse: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.tvUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.tvReferer, forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SmartTubeAuthError.invalidResponse
        }

        if !allowErrorResponse && !(200..<300).contains(http.statusCode) {
            throw SmartTubeAuthError.invalidResponse
        }

        return data
    }

    private static func extractCredentials(
        from script: String
    ) -> TVClientCredentials? {
        let pairPatterns = [
            #"clientId:"([-w]+.apps.googleusercontent.com)",s*[$w]+:"([-w]+)""#,
            #"clientId:s*"([-w]+.apps.googleusercontent.com)"s*,s*[$w]+:s*"([-w]+)""#
        ]

        for pattern in pairPatterns {
            if let groups = matchGroups(
                in: script,
                pattern: pattern,
                captures: [1, 2]
            ),
            groups.count == 2 {
                return TVClientCredentials(
                    clientID: groups[0],
                    clientSecret: groups[1]
                )
            }
        }

        return nil
    }

    private static func firstMatch(
        in text: String,
        patterns: [String],
        capture: Int
    ) -> String? {
        for pattern in patterns {
            if let groups = matchGroups(
                in: text,
                pattern: pattern,
                captures: [capture]
            ),
            let first = groups.first {
                return first
            }
        }

        return nil
    }

    private static func matchGroups(
        in text: String,
        pattern: String,
        captures: [Int]
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(
            in: text,
            options: [],
            range: range
        ) else {
            return nil
        }

        var values: [String] = []

        for capture in captures {
            let captureRange = match.range(at: capture)

            guard captureRange.location != NSNotFound,
                  let swiftRange = Range(captureRange, in: text) else {
                return nil
            }

            values.append(String(text[swiftRange]))
        }

        return values
    }

    private static func absoluteYouTubeURL(from value: String) -> String {
        if value.hasPrefix("https://") || value.hasPrefix("http://") {
            return value
        }

        if value.hasPrefix("//") {
            return "https:\(value)"
        }

        if value.hasPrefix("/") {
            return "https://www.youtube.com\(value)"
        }

        return "https://www.youtube.com/\(value)"
    }
}
