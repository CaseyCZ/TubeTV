import OSLog
import SwiftUI

private enum CIAdFilteringConfiguration {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment[
            "TUBETV_CI_AD_FILTER_SMOKE"
        ] == "1"
    }
}

private enum CIVideoSmokeConfiguration {
    static var videoID: String? {
        ProcessInfo.processInfo.environment["TUBETV_CI_VIDEO_ID"]
    }

    static var directURL: URL? {
        guard let raw =
            ProcessInfo.processInfo.environment[
                "TUBETV_CI_DIRECT_URL"
            ] else {
            return nil
        }

        return URL(string: raw)
    }

    static var enabled: Bool {
        ProcessInfo.processInfo.environment[
            "TUBETV_CI_VIDEO_SMOKE"
        ] == "1"
    }
}

private struct CIAdFilteringSmokeView: View {
    @State private var status = "Testing ad filtering…"

    private let logger = Logger(
        subsystem: "cz.caseycz.tubetv",
        category: "CI"
    )

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "shield.fill")
                .font(.system(size: 72))

            Text("TubeTV ad filtering test")
                .font(.largeTitle.bold())

            Text(status)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .task {
            runTest()
        }
    }

    @MainActor
    private func runTest() {
        let cleanRoot: [String: Any] = [
            "streamingData": [
                "hlsManifestUrl":
                    "https://example.com/content.m3u8",
                "formats": [
                    [
                        "url":
                            "https://example.com/content.mp4"
                    ]
                ]
            ]
        ]

        let adPlacementRoot: [String: Any] = [
            "streamingData": [
                "hlsManifestUrl":
                    "https://example.com/content.m3u8"
            ],
            "adPlacements": [
                [
                    "adPlacementRenderer": [
                        "config": "ad"
                    ]
                ]
            ]
        ]

        let playerAdsRoot: [String: Any] = [
            "playerAds": [
                [
                    "playerLegacyDesktopWatchAdsRenderer": [
                        "playerAdParams": "ad"
                    ]
                ]
            ]
        ]

        let adSlotsRoot: [String: Any] = [
            "adSlots": [
                [
                    "adSlotRenderer": [
                        "slotId": "ad"
                    ]
                ]
            ]
        ]

        let heartbeatRoot: [String: Any] = [
            "adBreakHeartbeatParams": "ad"
        ]

        let cleanMetadata =
            AdFilteringPolicy
                .inspectPlayerResponse(
                    cleanRoot
                )
        let placementMetadata =
            AdFilteringPolicy
                .inspectPlayerResponse(
                    adPlacementRoot
                )

        let detectsAllAdSignals =
            placementMetadata.hasAdPlacements
            && AdFilteringPolicy
                .inspectPlayerResponse(
                    playerAdsRoot
                )
                .hasPlayerAds
            && AdFilteringPolicy
                .inspectPlayerResponse(
                    adSlotsRoot
                )
                .hasAdSlots
            && AdFilteringPolicy
                .inspectPlayerResponse(
                    heartbeatRoot
                )
                .hasAdBreakHeartbeat

        let keepsOnlyContentStreamingData =
            AdFilteringPolicy
                .contentStreamingData(
                    from: adPlacementRoot
                )?["hlsManifestUrl"]
                as? String
            == "https://example.com/content.m3u8"

        let blocksAdBearingHLS =
            !AdFilteringPolicy
                .shouldUseHLSFallback(
                    adMetadata:
                        placementMetadata,
                    hasDirectContentFormats:
                        false
                )

        let allowsCleanHLSFallback =
            AdFilteringPolicy
                .shouldUseHLSFallback(
                    adMetadata:
                        cleanMetadata,
                    hasDirectContentFormats:
                        false
                )

        let prefersDirectContent =
            !AdFilteringPolicy
                .shouldUseHLSFallback(
                    adMetadata:
                        cleanMetadata,
                    hasDirectContentFormats:
                        true
                )

        if detectsAllAdSignals
            && keepsOnlyContentStreamingData
            && blocksAdBearingHLS
            && allowsCleanHLSFallback
            && prefersDirectContent {
            status = "Ad filtering policy passed."
            logger.notice(
                "TUBETV_AD_FILTER_OK"
            )
        } else {
            status = "Ad filtering policy failed."
            logger.error(
                "TUBETV_AD_FILTER_FAILED signals=\(detectsAllAdSignals, privacy: .public) content=\(keepsOnlyContentStreamingData, privacy: .public) blocksAdHLS=\(blocksAdBearingHLS, privacy: .public) cleanHLS=\(allowsCleanHLSFallback, privacy: .public) direct=\(prefersDirectContent, privacy: .public)"
            )
        }
    }
}

private struct CIDirectVideoSmokeView: View {
    let url: URL

    private let logger = Logger(
        subsystem: "cz.caseycz.tubetv",
        category: "CI"
    )

    var body: some View {
        NativePlayerView(
            source: .direct(url),
            youtubeVideoID: nil,
            initialQuality: "Auto",
            captionsEnabled: false,
            captionLanguage: "en",
            allowCaptionTranslation: false
        )
        .task {
            logger.notice(
                "TUBETV_DIRECT_VIDEO_STARTED url=\(url.absoluteString, privacy: .public)"
            )
        }
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
            if CIAdFilteringConfiguration.enabled {
                CIAdFilteringSmokeView()
            } else if CIVideoSmokeConfiguration.enabled,
               let directURL =
                CIVideoSmokeConfiguration.directURL {
                CIDirectVideoSmokeView(
                    url: directURL
                )
            } else if CIVideoSmokeConfiguration.enabled,
                      let videoID =
                        CIVideoSmokeConfiguration.videoID {
                CIVideoSmokeView(videoID: videoID)
            } else {
                RootView()
            }
        }
    }
}
