import SwiftUI

struct ChannelView: View {
    let channelID: String
    let fallbackTitle: String

    @State private var page: YouTubeChannelPage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 24) {
                    Group {
                        if let avatarURL = page?.avatarURL {
                            AsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .empty:
                                    ProgressView()
                                default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 12) {
                        Text(page?.title ?? fallbackTitle)
                            .font(.largeTitle.bold())

                        if let description = page?.description,
                           !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .frame(maxWidth: 1200, alignment: .leading)
                        }

                        if isLoading {
                            ProgressView("Načítám kanál…")
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if let videos = page?.videos,
                   !videos.isEmpty {
                    Text("Videa")
                        .font(.title2.bold())

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420), spacing: 28)],
                        spacing: 28
                    ) {
                        ForEach(videos) { video in
                            NavigationLink(value: video) {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
            }
            .padding(48)
        }
        .navigationDestination(for: VideoItem.self) { video in
            VideoDetailView(video: video)
        }
        .task {
            await loadChannel()
        }
    }

    @MainActor
    private func loadChannel() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if await SmartTubeAuthService.shared.signedIn() {
                do {
                    page = try await InnerTubeService.shared.channel(channelID)
                } catch {
                    page = try await YouTubeService.shared.channel(channelID)
                }
            } else {
                page = try await YouTubeService.shared.channel(channelID)
            }

            if page?.videos.isEmpty == true {
                errorMessage = "Kanál nevrátil žádná dostupná videa."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
