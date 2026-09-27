# TubeTV

Native Apple TV (tvOS) YouTube client experiment built with **Swift + SwiftUI**.

TubeTV is an independent project and is not affiliated with YouTube, Google, or SmartTube.

## Current status

The project is a normal Xcode project:

`TubeTV.xcodeproj`

No XcodeGen or generated workspace is required.

### Implemented

- Native tvOS SwiftUI interface
- Apple TV Remote / Focus Engine navigation
- Home screen with live YouTube video cards
- Native YouTube search
- Paste a YouTube URL or 11-character video ID
- YouTube thumbnails
- Native AVPlayer playback
- Direct YouTube stream extraction through YouTubeKit
- Adaptive video + audio playback path for higher resolutions
- Quality preference:
  - Auto
  - 1080p
  - 1440p
  - 4K / 2160p
- Automatic fallback to a compatible combined stream
- Caption discovery from YouTube
- Czech captions preferred by default
- YouTube automatic caption translation to Czech when available
- Custom synchronized caption overlay
- Settings for automatic captions and translation

### In progress / next

- Validate adaptive 1080p / 1440p / 4K playback on real Apple TV hardware
- HDR / codec selection
- YouTube account sign-in
- Subscriptions
- YouTube history
- Playlists
- Channel detail
- Better video detail metadata
- Player quality selector while video is playing
- Subtitle language selector while video is playing
- SponsorBlock
- UI polish closer to SmartTube

## First Apple TV test

1. Open `TubeTV.xcodeproj`.
2. Select the TubeTV tvOS target.
3. Let Xcode resolve the YouTubeKit Swift Package.
4. Run on Apple TV or tvOS Simulator.
5. Test **Domů**.
6. Test **Hledat** with a normal query.
7. Open a result and press **Přehrát**.
8. Test quality settings.
9. Test a video with English or auto-generated captions and verify Czech translation.

## Dependency

Playback stream extraction currently uses:

- [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) 0.4.8

YouTubeKit supports tvOS and exposes direct video/audio stream URLs for native playback.
