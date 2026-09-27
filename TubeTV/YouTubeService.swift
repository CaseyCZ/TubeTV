import Foundation

enum YouTubeServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case initialDataNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Nepodařilo se sestavit požadavek na YouTube."
        case .invalidResponse:
            return "YouTube vrátil neplatnou odpověď."
        case .initialDataNotFound:
            return "Nepodařilo se načíst data YouTube. Struktura stránky se mohla změnit."
        }
    }
}

actor YouTubeService {
    static let shared = YouTubeService()

    func home() async throws -> [VideoItem] {
        var components = URLComponents(string: "https://www.youtube.com/")
        components?.queryItems = [
            URLQueryItem(name: "hl", value: "cs"),
            URLQueryItem(name: "gl", value: "CZ")
        ]

        guard let url = components?.url else {
            throw YouTubeServiceError.invalidURL
        }

        return try await fetchVideos(from: url)
    }

    func search(query: String) async throws -> [VideoItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: trimmed),
            URLQueryItem(name: "hl", value: "cs"),
            URLQueryItem(name: "gl", value: "CZ")
        ]

        guard let url = components?.url else {
            throw YouTubeServiceError.invalidURL
        }

        return try await fetchVideos(from: url)
    }

    private func fetchVideos(from url: URL) async throws -> [VideoItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        Self.applyYouTubeHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw YouTubeServiceError.invalidResponse
        }

        guard let initialData = Self.extractInitialData(from: html),
              let json = try? JSONSerialization.jsonObject(with: initialData) else {
            throw YouTubeServiceError.initialDataNotFound
        }

        var renderers: [[String: Any]] = []
        Self.collectVideoRenderers(from: json, into: &renderers)

        var seen = Set<String>()
        var videos: [VideoItem] = []

        for renderer in renderers {
            guard let videoID = renderer["videoId"] as? String,
                  videoID.count == 11,
                  seen.insert(videoID).inserted else {
                continue
            }

            let title = Self.text(from: renderer["title"]) ?? "YouTube video"
            let channel = Self.text(from: renderer["ownerText"])
                ?? Self.text(from: renderer["longBylineText"])
                ?? "YouTube"
            let channelID = Self.channelID(from: renderer)

            let duration = Self.text(from: renderer["lengthText"])
            let published = Self.text(from: renderer["publishedTimeText"])
            let views = Self.text(from: renderer["viewCountText"])

            let subtitle = [published, views, duration]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")

            let thumbnailURL = Self.thumbnailURL(from: renderer["thumbnail"])
                ?? URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")

            videos.append(
                VideoItem(
                    id: "youtube-\(videoID)",
                    title: title,
                    channel: channel,
                    subtitle: subtitle,
                    thumbnailURL: thumbnailURL,
                    youtubeVideoID: videoID,
                    channelID: channelID
                )
            )

            if videos.count >= 60 {
                break
            }
        }

        return videos
    }

    private static func collectVideoRenderers(
        from node: Any,
        into output: inout [[String: Any]]
    ) {
        if let dictionary = node as? [String: Any] {
            if let renderer = dictionary["videoRenderer"] as? [String: Any] {
                output.append(renderer)
            }

            for value in dictionary.values {
                collectVideoRenderers(from: value, into: &output)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectVideoRenderers(from: value, into: &output)
            }
        }
    }

    private static func text(from value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }

        if let simpleText = dictionary["simpleText"] as? String {
            return simpleText
        }

        if let runs = dictionary["runs"] as? [[String: Any]] {
            let value = runs
                .compactMap { $0["text"] as? String }
                .joined()

            return value.isEmpty ? nil : value
        }

        return nil
    }

    private static func channelID(from renderer: [String: Any]) -> String? {
        for key in ["ownerText", "longBylineText", "shortBylineText"] {
            guard let text = renderer[key] as? [String: Any],
                  let runs = text["runs"] as? [[String: Any]] else {
                continue
            }

            for run in runs {
                guard let endpoint = run["navigationEndpoint"] as? [String: Any],
                      let browse = endpoint["browseEndpoint"] as? [String: Any],
                      let browseID = browse["browseId"] as? String,
                      browseID.hasPrefix("UC") else {
                    continue
                }

                return browseID
            }
        }

        return nil
    }

    private static func thumbnailURL(from value: Any?) -> URL? {
        guard let dictionary = value as? [String: Any],
              let thumbnails = dictionary["thumbnails"] as? [[String: Any]] else {
            return nil
        }

        for thumbnail in thumbnails.reversed() {
            if let raw = thumbnail["url"] as? String,
               let url = URL(string: raw) {
                return url
            }
        }

        return nil
    }

    private static func applyYouTubeHeaders(to request: inout URLRequest) {
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("cs-CZ,cs;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("CONSENT=YES+cb.20210328-17-p0.en+FX+667", forHTTPHeaderField: "Cookie")
    }

    private static func extractInitialData(from html: String) -> Data? {
        let markers = [
            "var ytInitialData = ",
            "ytInitialData = ",
            "window[\"ytInitialData\"] = ",
            "window['ytInitialData'] = "
        ]

        for marker in markers {
            guard let markerRange = html.range(of: marker) else { continue }
            let remainder = html[markerRange.upperBound...]

            guard let openingBrace = remainder.firstIndex(of: "{") else { continue }
            let jsonSlice = remainder[openingBrace...]

            if let data = balancedJSONObjectData(from: jsonSlice) {
                return data
            }
        }

        return nil
    }

    private static func balancedJSONObjectData(
        from substring: Substring
    ) -> Data? {
        let bytes = Array(substring.utf8)
        var depth = 0
        var inString = false
        var escaped = false

        for index in bytes.indices {
            let byte = bytes[index]

            if inString {
                if escaped {
                    escaped = false
                    continue
                }

                if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }

                continue
            }

            if byte == 0x22 {
                inString = true
                continue
            }

            if byte == 0x7B {
                depth += 1
            } else if byte == 0x7D {
                depth -= 1

                if depth == 0 {
                    return Data(bytes[0...index])
                }
            }
        }

        return nil
    }
}
