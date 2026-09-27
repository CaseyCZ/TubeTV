# TubeTV

![tvOS Build](https://github.com/CaseyCZ/TubeTV/actions/workflows/tvos-build.yml/badge.svg?branch=Master)

### A clean YouTube experience made for Apple TV.

TubeTV is a native tvOS app designed for comfortable YouTube watching from the couch.  
It combines a TV-first interface, Apple TV Remote navigation, high-quality playback, multilingual subtitles and YouTube account features in one simple app.

> **TubeTV is currently in active development.**

---

## ✨ Highlights

### Native Apple TV experience
TubeTV is designed specifically for tvOS with a large-screen interface, focus-based navigation and full Apple TV Remote support.

### Clean playback
TubeTV is built around direct content playback and does not intentionally create playback items from YouTube ad placements.

### High-quality video
Choose the quality that fits your setup:

- Automatic
- 1080p
- 1440p
- 4K / 2160p
- 60 fps when available
- HDR when supported by the video, Apple TV and connected display

During playback, TubeTV can show the actual resolution, frame rate, dynamic range and codec currently in use.

### Subtitles & translation
TubeTV supports YouTube subtitle tracks directly inside the player.

- Native subtitle tracks
- Auto-generated subtitles
- Automatic translation when available
- Quick subtitle switching while watching
- Independent app and subtitle languages

Czech subtitles can remain preferred even when the whole TubeTV interface is set to English.

### YouTube account
Sign in using the familiar TV device-code flow.

After signing in, TubeTV can provide:

- Personalized Home
- Subscriptions
- YouTube History
- Playlists
- Multiple YouTube / Brand Account profiles
- Watch progress synchronization

Account tokens are stored securely in the Apple Keychain.

### Search, channels & playlists
Browse YouTube without leaving the TV interface.

- Search videos
- Paste a YouTube URL or video ID
- Open channels
- Browse channel videos
- Open playlists
- View thumbnails and video metadata

---

## 🎬 Player

The TubeTV player keeps the most useful controls available while the video is playing.

You can change:

- Video quality
- Subtitle track
- Subtitle translation
- Playback speed from 0.5× to 2×
- Active YouTube profile through app settings

Changing quality keeps your current playback position whenever possible.

---

## 🌍 Languages

**English is the default TubeTV language.**

Current interface languages:

- English
- Čeština
- Deutsch
- Polski
- Slovenčina

The interface language and preferred subtitle language are separate settings, so every user can combine them however they want.

More languages can be added over time.

---

## 📺 Designed for

TubeTV is focused on:

- Apple TV
- tvOS
- Large-screen viewing
- Apple TV Remote navigation

Playback capabilities depend on the Apple TV model, tvOS version, connected display and formats available for each YouTube video.

---

## 🚧 Development status

TubeTV is still under active development and is being tested feature by feature.

The current focus is:

- Stable playback on real Apple TV hardware
- Reliable account sign-in and sync
- 1080p / 1440p / 4K playback
- 60 fps and HDR compatibility
- Subtitle reliability
- Ad-free playback path stability
- UI polish and TV usability

The badge at the top of this page shows the current automated tvOS build status.

---

## 🧪 Development build

TubeTV is not yet distributed as a finished public release.

Developers can open:

`TubeTV.xcodeproj`

and build the tvOS target using Xcode.

---

## ❤️ Inspired by the TV experience

TubeTV takes inspiration from the usability and feature set of SmartTube while using its own native Swift / SwiftUI implementation for Apple TV.

Third-party attribution and licensing information is available in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

## Disclaimer

TubeTV is an independent project and is not affiliated with, endorsed by, or sponsored by YouTube, Google, Apple or SmartTube.

YouTube availability, account features and playback formats may change over time because they depend on external services.
