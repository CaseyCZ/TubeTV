import Foundation

struct VideoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let channel: String
    let subtitle: String
    let thumbnailURL: URL?
    let playbackURL: URL?
    let youtubeVideoID: String?
    let channelID: String?

    init(
        id: String,
        title: String,
        channel: String,
        subtitle: String,
        thumbnailURL: URL? = nil,
        playbackURL: URL? = nil,
        youtubeVideoID: String? = nil,
        channelID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.subtitle = subtitle
        self.thumbnailURL = thumbnailURL
        self.playbackURL = playbackURL
        self.youtubeVideoID = youtubeVideoID
        self.channelID = channelID
    }

    static func youtube(
        videoID: String,
        title: String = "YouTube video",
        channel: String = "YouTube",
        subtitle: String = "",
        channelID: String? = nil
    ) -> VideoItem {
        VideoItem(
            id: "youtube-\(videoID)",
            title: title,
            channel: channel,
            subtitle: subtitle.isEmpty ? videoID : subtitle,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"),
            youtubeVideoID: videoID,
            channelID: channelID
        )
    }
}
