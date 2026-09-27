import Foundation

protocol YouTubeServing {
    func home() async throws -> [VideoItem]
    func search(query: String) async throws -> [VideoItem]
}

actor YouTubeService: YouTubeServing {
    func home() async throws -> [VideoItem] {
        // TODO: replace with the YouTube catalog layer.
        VideoItem.demo
    }

    func search(query: String) async throws -> [VideoItem] {
        // TODO: connect the native YouTube search layer.
        guard !query.isEmpty else { return VideoItem.demo }

        return VideoItem.demo.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.channel.localizedCaseInsensitiveContains(query)
        }
    }
}
