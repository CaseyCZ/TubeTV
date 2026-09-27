import Foundation

struct VideoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let channel: String
    let subtitle: String
    let playbackURL: URL?
}

extension VideoItem {
    static let demo: [VideoItem] = [
        VideoItem(
            id: "demo-player",
            title: "TubeTV – test nativního přehrávače",
            channel: "TubeTV",
            subtitle: "Apple HLS test stream",
            playbackURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")
        ),
        VideoItem(
            id: "demo-quality",
            title: "Kvalita 1080p / 1440p / 4K / HDR",
            channel: "TubeTV",
            subtitle: "Stream resolver přijde v další etapě",
            playbackURL: nil
        ),
        VideoItem(
            id: "demo-captions",
            title: "Automatické české titulky",
            channel: "TubeTV",
            subtitle: "Čeština bude preferovaný jazyk",
            playbackURL: nil
        )
    ]
}
