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
- YouTube channels with avatar, description and channel videos
- Channels work signed-in through InnerTube and signed-out through the public YouTube page
- Native AVPlayer playback
- SmartTube-style authenticated YouTube TV / InnerTube player after sign-in
- SmartTube-style ad filtering: ad placements are never turned into playable media
- Direct content video/audio streams are preferred over ad-bearing player manifests
- Ad-aware client fallback chain: signed TV → VisionOS → Android VR → iOS → YouTubeKit
- Automatic fallback to YouTubeKit when the authenticated player does not return a compatible stream
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
- SmartTube-style YouTube account history tracking with playback/watchtime updates
- Multiple YouTube / Brand Account profile selection via X-Goog-Pageid
- Settings for automatic captions and translation
- In-player settings panel for quality, subtitles and playback speed
- Actual AVFoundation format inspection: resolution, FPS, SDR/HDR and codec
- Apple TV HDR eligibility check through AVPlayer
- VideoToolbox hardware codec checks for H.264, HEVC and AV1
- Live quality switching while preserving the current playback position
- Full YouTube subtitle language list with native tracks and automatic translations

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


## Ads / ad filtering

TubeTV follows the same high-level principle as SmartTube: the app has no playback path that intentionally renders YouTube ad placements.

The player response may contain fields such as `adPlacements`, `playerAds`, `adSlots` and `adBreakHeartbeatParams`. TubeTV inspects these fields but does not convert them into AVPlayer items.

Playback order:

1. Signed-in YouTube TV / InnerTube direct content formats.
2. VisionOS direct content formats.
3. Android VR direct content formats.
4. iOS direct content formats.
5. YouTubeKit direct stream extraction.

HLS is only a last-resort fallback and is rejected when the same player response contains advertising metadata and no independent direct content stream is available.

This is intentionally separate from SponsorBlock, which handles sponsor messages embedded inside the creator's video itself.
