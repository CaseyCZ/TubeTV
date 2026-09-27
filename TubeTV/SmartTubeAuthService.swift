import Foundation
import Security

extension Notification.Name {
    static let youtubeAccountDidChange =
        Notification.Name(
            "TubeTV.YouTubeAccountDidChange"
        )
}

struct TVClientCredentials: Hashable {
    let clientID: String
    let clientSecret: String
}

struct TVBootstrap: Hashable {
    let credentials: TVClientCredentials
    let visitorData: String?
}

struct YouTubeAccountProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String?
    let channelHandle: String?
    let avatarURL: URL?
    let pageID: String?
    let isSelected: Bool
    let hasChannel: Bool
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
        let verificationURL = try container.decodeIfPresent(
            String.self,
            forKey: .verificationURL
        )
        let verificationURI = try container.decodeIfPresent(
            String.self,
            forKey: .verificationURI
        )
        self.verificationURL =
            verificationURL
            ?? verificationURI
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
            return L10n.text("auth_tv_page_unavailable")
        case .clientScriptNotFound:
            return L10n.text("auth_client_script_not_found")
        case .credentialsNotFound:
            return L10n.text("auth_credentials_not_found")
        case .invalidResponse:
            return L10n.text("auth_invalid_response")
        case .denied:
            return L10n.text("auth_denied")
        case .expired:
            return L10n.text("auth_expired")
        case .notSignedIn:
            return L10n.text("auth_not_signed_in")
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
    private let selectedPageIDKey = "youtube.selectedPageID"

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
                #"id="base-js"\s+src="(.*?)""#,
                #"\.src = '(.*?m=base)'"#,
                #"\.src = '(.*?)';\s*.\.id = 'base-js'"#
            ],
            capture: 1
        ) else {
            throw SmartTubeAuthError.clientScriptNotFound
        }

        let clientURLString = Self.absoluteYouTubeURL(
            from: rawClientURL
                .replacingOccurrences(of: "\\/", with: "/")
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
        var delay = max(authorization.interval, 3)

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
                saveTokenResponse(
                    token,
                    refreshToken: refreshToken
                )
                postAccountChange()
                return
            }

            switch token.error {
            case "authorization_pending":
                continue
            case "slow_down":
                delay += 5
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

    func accounts() async throws -> [YouTubeAccountProfile] {
        let bootstrap = try await bootstrap()
        let authorization = try await authorizationHeader()
        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60

        var client: [String: Any] = [
            "clientName": Self.tvClientName,
            "clientVersion": Self.tvClientVersion,
            "clientScreen": "WATCH",
            "userAgent": Self.tvUserAgent,
            "acceptLanguage": "cs",
            "acceptRegion": "CZ",
            "utcOffsetMinutes": offsetMinutes,
            "webpSupport": false,
            "animatedWebpSupport": true,
            "tvAppInfo": [
                "appQuality": "TV_APP_QUALITY_FULL_ANIMATION",
                "zylonLeftNav": true
            ]
        ]

        if let visitorData = bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] = visitorData
        }

        let payload: [String: Any] = [
            "context": [
                "client": client,
                "user": [
                    "enableSafetyMode": false,
                    "lockedSafetyMode": false
                ]
            ],
            "racyCheckOk": true,
            "contentCheckOk": true,
            "accountReadMask": [
                "returnOwner": true,
                "returnBrandAccounts": true,
                "returnPersonaAccounts": false
            ]
        ]

        var request = URLRequest(
            url: URL(
                string: "https://www.youtube.com/youtubei/v1/account/accounts_list?prettyPrint=false"
            )!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.tvUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.tvReferer, forHTTPHeaderField: "Referer")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        if let visitorData = bootstrap.visitorData,
           !visitorData.isEmpty {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw SmartTubeAuthError.invalidResponse
        }

        var accountItems: [[String: Any]] = []
        Self.collectAccountItems(from: root, into: &accountItems)

        var profiles: [YouTubeAccountProfile] = []
        var seen = Set<String>()

        for item in accountItems {
            let name = Self.text(from: item["accountName"]) ?? "YouTube"
            let email = Self.text(from: item["accountByline"])
            let handle = Self.text(from: item["channelHandle"])
            let selected = item["isSelected"] as? Bool ?? false
            let disabled = item["isDisabled"] as? Bool ?? false
            let hasChannel = item["hasChannel"] as? Bool ?? true
            let pageID = Self.pageID(from: item)
            let avatar = Self.thumbnailURL(from: item["accountPhoto"])

            guard !disabled else { continue }

            let stableID = pageID
                ?? handle
                ?? email
                ?? name

            guard seen.insert(stableID).inserted else { continue }

            profiles.append(
                YouTubeAccountProfile(
                    id: stableID,
                    name: name,
                    email: email,
                    channelHandle: handle,
                    avatarURL: avatar,
                    pageID: pageID,
                    isSelected: selected,
                    hasChannel: hasChannel
                )
            )
        }

        if selectedPageID() == nil {
            let preferred = profiles.first(where: { $0.isSelected }) ?? profiles.first

            if let preferred {
                selectAccount(preferred)
            }
        }

        return profiles
    }

    func selectedPageID() -> String? {
        UserDefaults.standard.string(forKey: selectedPageIDKey)
    }

    func selectAccount(_ profile: YouTubeAccountProfile) {
        let previousPageID =
            selectedPageID()
        let nextPageID =
            profile.pageID
                .flatMap {
                    $0.isEmpty
                    ? nil
                    : $0
                }

        if let nextPageID {
            UserDefaults.standard.set(
                nextPageID,
                forKey: selectedPageIDKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: selectedPageIDKey
            )
        }

        if previousPageID != nextPageID {
            postAccountChange()
        }
    }

    func signOut() {
        let hadAccount =
            signedIn()
            || selectedPageID() != nil

        TubeTVKeychain.delete(refreshTokenKey)
        TubeTVKeychain.delete(accessTokenKey)
        TubeTVKeychain.delete(accessTokenExpiryKey)
        UserDefaults.standard.removeObject(
            forKey: selectedPageIDKey
        )

        if hadAccount {
            postAccountChange()
        }
    }

    private func postAccountChange() {
        NotificationCenter.default.post(
            name: .youtubeAccountDidChange,
            object: nil
        )
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
                token.errorDescription ?? token.error ?? L10n.text("auth_refresh_failed")
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

    private static func collectAccountItems(
        from node: Any,
        into output: inout [[String: Any]]
    ) {
        if let dictionary = node as? [String: Any] {
            if let item = dictionary["accountItem"] as? [String: Any] {
                output.append(item)
            }

            for value in dictionary.values {
                collectAccountItems(from: value, into: &output)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectAccountItems(from: value, into: &output)
            }
        }
    }

    private static func pageID(from item: [String: Any]) -> String? {
        guard let endpoint = item["serviceEndpoint"] as? [String: Any],
              let select = endpoint["selectActiveIdentityEndpoint"] as? [String: Any],
              let tokens = select["supportedTokens"] as? [[String: Any]] else {
            return nil
        }

        for token in tokens {
            if let pageToken = token["pageIdToken"] as? [String: Any],
               let pageID = pageToken["pageId"] as? String,
               !pageID.isEmpty {
                return pageID
            }
        }

        return nil
    }

    private static func text(from value: Any?) -> String? {
        guard let value else { return nil }

        if let string = value as? String {
            return string
        }

        if let dictionary = value as? [String: Any] {
            if let simpleText = dictionary["simpleText"] as? String {
                return simpleText
            }

            if let runs = dictionary["runs"] as? [[String: Any]] {
                let joined = runs
                    .compactMap { $0["text"] as? String }
                    .joined()

                return joined.isEmpty ? nil : joined
            }

            if let content = dictionary["content"] as? String {
                return content
            }
        }

        return nil
    }

    private static func thumbnailURL(from value: Any?) -> URL? {
        guard let value else { return nil }

        if let dictionary = value as? [String: Any] {
            if let raw = dictionary["url"] as? String {
                return URL(string: raw)
            }

            if let thumbnails = dictionary["thumbnails"] as? [[String: Any]] {
                for item in thumbnails.reversed() {
                    if let raw = item["url"] as? String,
                       let url = URL(string: raw) {
                        return url
                    }
                }
            }

            for nested in dictionary.values {
                if let url = thumbnailURL(from: nested) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array.reversed() {
                if let url = thumbnailURL(from: nested) {
                    return url
                }
            }
        }

        return nil
    }

    private static func extractCredentials(
        from script: String
    ) -> TVClientCredentials? {
        let pairPatterns = [
            #"clientId:"([-\w]+\.apps\.googleusercontent\.com)",\s*[$\w]+:"([-\w]+)""#,
            #"clientId:\s*"([-\w]+\.apps\.googleusercontent\.com)"\s*,\s*[$\w]+:\s*"([-\w]+)""#
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
