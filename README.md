# TubeTV

TubeTV is an independent Apple TV customization project built around the stable YouTube tvOS playback runtime with a separate TV-focused feature layer.

## Current stable direction

The current stable TubeTV build uses:

- **YouTube tvOS 4.54.01 runtime/player** for playback, sign-in, codecs, seeking, captions and Apple TV Remote behavior.
- **TizenTube** for ad blocking and optional enhancements such as SponsorBlock, playback speed controls and other TV-focused settings.
- **TubeTV identity** with bundle identifier `cz.caseycz.tubetv`.
- **Apple TV compatibility adjustments** including support for `AppleTV5,3`, `AppleTV6,2` and `AppleTV11,1`.
- **μTube-inspired Cobalt injection/patching approach** for loading the enhancement layer into the YouTube tvOS runtime.

The current stable build keeps the original YouTube/Cobalt visual appearance. Experimental TubeTV Blue UI work is **not** part of the stable release.

## Stable behavior

The stable baseline is intentionally conservative: playback-related code is left as close as possible to the proven YouTube tvOS runtime while TubeTV adds only the required identity, compatibility and TizenTube integration around it.

SponsorBlock is **not forced on or off by TubeTV**. It remains configurable from TizenTube settings, together with the other optional TizenTube features.

## Supported baseline

The currently validated base is:

- YouTube tvOS: **4.54.01**
- TubeTV bundle identifier: **`cz.caseycz.tubetv`**
- Tested target: Apple TV HD (`AppleTV5,3`)

Binary patch locations are version-specific. Other YouTube versions must be validated before use.

## Repository contents

`Master` documents and tracks the current stable architecture only. The earlier standalone SwiftUI/native TubeTV client remains available in Git history and older branches but is no longer the primary implementation.

This repository does **not** include or redistribute proprietary YouTube application binaries. A compatible user-provided YouTube tvOS build is required for local patching/testing.

See [PATCHING.md](PATCHING.md) for the stable patching model and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for upstream credits.

## Third-party projects

TubeTV uses or is informed by open-source work maintained by other developers:

- **TizenTube** — https://github.com/reisxd/TizenTube — GPL-3.0-only
- **μTube** — https://github.com/Exaphis/mutube — reference for the Apple TV / Cobalt patching approach

These projects are credited as upstream work and are not presented as TubeTV's own code.

## Disclaimer

TubeTV is an independent project and is not affiliated with, endorsed by, or sponsored by YouTube, Google, Apple, TizenTube or μTube.

YouTube is a trademark of Google LLC. Users are responsible for obtaining and using any required application files in accordance with applicable licenses, terms and laws.
