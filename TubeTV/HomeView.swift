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

                if let thumbnailURL = video.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()

                        case .failure:
                            placeholder

                        case .empty:
                            ProgressView()

                        @unknown default:
                            placeholder
                        }
                    }
                    .frame(width: 420, height: 236)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    placeholder
                }

                if video.playbackURL != nil {
                    Text("TEST")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(14)
                }
            }
            .frame(width: 420, height: 236)

            Text(video.title)
                .font(.headline)
                .lineLimit(2)
                .frame(width: 420, alignment: .leading)

            Text(video.channel)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !video.subtitle.isEmpty {
                Text(video.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 64))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
