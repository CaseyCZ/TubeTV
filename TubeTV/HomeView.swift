import SwiftUI

struct HomeView: View {
    private let videos = VideoItem.demo

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 44) {
                    Text("Domů")
                        .font(.largeTitle.bold())

                    VideoRow(title: "Doporučené", videos: videos)
                    VideoRow(title: "Pokračovat ve sledování", videos: videos)
                }
                .padding(48)
            }
            .navigationDestination(for: VideoItem.self) { video in
                VideoDetailView(video: video)
            }
        }
    }
}

struct VideoRow: View {
    let title: String
    let videos: [VideoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    ForEach(videos) { video in
                        NavigationLink(value: video) {
                            VideoCard(video: video)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
    }
}

struct VideoCard: View {
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.12))

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(video.playbackURL == nil ? "PŘIPRAVUJEME" : "TEST")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(14)
            }
            .frame(width: 420, height: 236)

            Text(video.title)
                .font(.headline)
                .lineLimit(2)
                .frame(width: 420, alignment: .leading)

            Text(video.channel)
                .foregroundStyle(.secondary)
        }
    }
}
