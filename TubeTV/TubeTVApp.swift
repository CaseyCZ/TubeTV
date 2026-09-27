import OSLog
import SwiftUI

private enum CIVideoSmokeConfiguration {
    static var videoID: String? {
        ProcessInfo.processInfo.environment["TUBETV_CI_VIDEO_ID"]
    }

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["TUBETV_CI_VIDEO_SMOKE"] == "1"
            && videoID != nil
    }
}

private struct CIVideoSmokeView: View {
    let videoID: String

    @State private var source: PlaybackSource?
    @State private var errorMessage: String?

    private let logger = Logger(
        subsystem: "cz.caseycz.tubetv",
        category: "CI"
    )

    var body: some View {
        Group {
            if let source {
                NativePlayerView(
                    source: source,
                    youtubeVideoID: videoID,
                    initialQuality: "Auto",
                    captionsEnabled: false,
                    captionLanguage: "en",
                    allowCaptionTranslation: false
                )
            } else if let errorMessage {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 72))

                    Text("YouTube playback test failed")
                        .font(.largeTitle.bold())

                    Text(errorMessage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Resolving YouTube video…")
                    .font(.title2)
            }
        }
        .task {
            await resolveVideo()
        }
    }

    @MainActor
    private func resolveVideo() async {
        do {
            source = try await StreamResolver.resolveYouTubeVideo(
                videoID: videoID,
                preferredQuality: "Auto"
            )

            logger.notice(
                "TUBETV_VIDEO_RESOLVED videoID=\(videoID, privacy: .public)"
            )
        } catch {
            errorMessage = error.localizedDescription

            logger.error(
                "TUBETV_VIDEO_RESOLVE_FAILED error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

@main
struct TubeTVApp: App {
    var body: some Scene {
        WindowGroup {
            if CIVideoSmokeConfiguration.enabled,
               let videoID = CIVideoSmokeConfiguration.videoID {
                CIVideoSmokeView(videoID: videoID)
            } else {
                RootView()
            }
        }
    }
}
