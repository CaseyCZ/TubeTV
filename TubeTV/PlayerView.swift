import AVKit
import SwiftUI

struct VideoDetailView: View {
    let video: VideoItem
    @State private var showPlayer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()

            Text(video.title)
                .font(.largeTitle.bold())

            Text(video.channel)
                .font(.title2)

            Text(video.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Button {
                    showPlayer = true
                } label: {
                    Label("Přehrát", systemImage: "play.fill")
                }
                .disabled(video.playbackURL == nil)

                Button {
                } label: {
                    Label("Titulky: Čeština", systemImage: "captions.bubble.fill")
                }
            }

            Spacer()
        }
        .padding(64)
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = video.playbackURL {
                NativePlayerView(url: url)
            }
        }
    }
}

struct NativePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                player.play()
            }
            .onDisappear {
                player.pause()
            }
            .onExitCommand {
                dismiss()
            }
    }
}
