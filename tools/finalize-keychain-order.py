from pathlib import Path

path = Path("TubeTV/SmartTubeAuthService.swift")
text = path.read_text(encoding="utf-8")

old = '''    private func saveTokenResponse(
        _ token: TVTokenResponse,
        refreshToken: String
    ) throws {
        try TubeTVKeychain.set(refreshToken, for: refreshTokenKey)

        if let accessToken = token.accessToken {
            try TubeTVKeychain.set(accessToken, for: accessTokenKey)
        }

        let expiry = Date()
            .addingTimeInterval(TimeInterval(token.expiresIn ?? 3600))
            .timeIntervalSince1970

        try TubeTVKeychain.set(String(expiry), for: accessTokenExpiryKey)
    }
'''

new = '''    private func saveTokenResponse(
        _ token: TVTokenResponse,
        refreshToken: String
    ) throws {
        // signedIn() uses the refresh token as the durable account marker.
        // Persist derived session state first so a failed first-time write
        // can never leave TubeTV looking signed in with incomplete tokens.
        if let accessToken = token.accessToken {
            try TubeTVKeychain.set(
                accessToken,
                for: accessTokenKey
            )
        }

        let expiry = Date()
            .addingTimeInterval(
                TimeInterval(
                    token.expiresIn
                    ?? 3600
                )
            )
            .timeIntervalSince1970

        try TubeTVKeychain.set(
            String(expiry),
            for: accessTokenExpiryKey
        )

        try TubeTVKeychain.set(
            refreshToken,
            for: refreshTokenKey
        )
    }
'''

count = text.count(old)
if count != 1:
    raise SystemExit(f"Expected one saveTokenResponse block, found {count}")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Reordered Keychain token persistence")
