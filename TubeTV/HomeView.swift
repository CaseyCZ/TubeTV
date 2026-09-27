import SwiftUI

struct HomeView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var videos: [VideoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 44) {
                    HStack {
                        Text(L10n.text("home", languageCode: appLanguage))
                            .font(.largeTitle.bold())

                        Spacer()

                        if isLoading {
                            ProgressView()
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    if videos.isEmpty && !isLoading {
                        VideoRow(title: "TubeTV", videos: VideoItem.demo)
                    } else {
                        VideoRow(
                            title: L10n.text("recommended", languageCode: appLanguage),
                            videos: Array(videos.prefix(24))
                        )

                        if videos.count > 24 {
                            VideoRow(
                                title: L10n.text("more_videos", languageCode: appLanguage),
                                videos: Array(videos.dropFirst(24).prefix(24))
                            )
                        }
                    }
                }
                .padding(48)
            }
            .navigationDestination(for: VideoItem.self) { video in
                VideoDetailView(video: video)
            }
            .task {
                await loadHome()
            }
        }
    }

    @MainActor
    private func loadHome() async {
        guard videos.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if await SmartTubeAuthService.shared.signedIn() {
                do {
                    videos = try await InnerTubeService.shared.homeVideos()
                } catch {
                    // Keep Home usable even if YouTube changes the signed TV feed.
                    videos = try await YouTubeService.shared.home()
                }
            } else {
                videos = try await YouTubeService.shared.home()
            }

            if videos.isEmpty {
                errorMessage = L10n.text("youtube_no_videos", languageCode: appLanguage)
            }
        } catch {
            errorMessage = error.localizedDescription
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
                    Text(L10n.text("test"))
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
