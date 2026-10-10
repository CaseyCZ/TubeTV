from pathlib import Path

# Keep the fallback channel web page in the same language as the rest of TubeTV.
path = Path("TubeTV/YouTubeService.swift")
text = path.read_text()
old = '''    func channel(_ channelID: String) async throws -> YouTubeChannelPage {
        guard let url = URL(
            string: "https://www.youtube.com/channel/\\(channelID)/videos?hl=cs&gl=CZ"
        ) else {
            throw YouTubeServiceError.invalidURL
        }
'''
new = '''    func channel(_ channelID: String) async throws -> YouTubeChannelPage {
        var components = URLComponents(
            string: "https://www.youtube.com/channel/\\(channelID)/videos"
        )
        components?.queryItems = [
            URLQueryItem(name: "hl", value: L10n.currentLanguageCode),
            URLQueryItem(name: "gl", value: "CZ")
        ]

        guard let url = components?.url else {
            throw YouTubeServiceError.invalidURL
        }
'''
if old not in text:
    raise SystemExit("YouTubeService channel URL block not found")
text = text.replace(old, new, 1)
path.write_text(text)

# SwiftUI already observes @AppStorage appLanguage; recreating the complete
# Settings subtree discards transient sign-in/profile UI state unnecessarily.
path = Path("TubeTV/SettingsView.swift")
text = path.read_text()
old = '''        .id(appLanguage)\n'''
if old not in text:
    raise SystemExit("Settings appLanguage identity reset not found")
text = text.replace(old, "", 1)
path.write_text(text)
