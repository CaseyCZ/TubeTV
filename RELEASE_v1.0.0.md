# TubeTV 1.0.0 Stable

**Status:** Stable

TubeTV 1.0.0 is the first stable release of the current Apple TV implementation.

## Highlights

- Validated against **YouTube tvOS 4.54.01**
- TubeTV bundle identifier: `cz.caseycz.tubetv`
- Apple TV compatibility including `AppleTV5,3`, `AppleTV6,2` and `AppleTV11,1`
- TizenTube integration
- Ad blocking through TizenTube
- SponsorBlock remains user-configurable in TizenTube settings
- Native YouTube tvOS playback path retained for playback, sign-in, codecs, seeking and captions
- Apple TV Remote behavior inherited from the YouTube tvOS client
- Experimental TubeTV Blue UI is not included in this stable release

## Stable baseline

This release intentionally keeps the original YouTube/Cobalt visual appearance and minimizes changes to the proven playback runtime.

The current implementation uses the YouTube tvOS application as the playback/runtime base and adds TubeTV identity, device compatibility adjustments and the TizenTube enhancement layer.

## Installation / binary note

The public repository does not redistribute proprietary YouTube application binaries. A compatible user-provided YouTube tvOS 4.54.01 build is required for local patching/testing.

See [PATCHING.md](PATCHING.md) for the stable patching model.

## Third-party credits

TubeTV uses or is informed by:

- TizenTube — GPL-3.0-only — https://github.com/reisxd/TizenTube
- μTube — reference for the Apple TV / Cobalt injection approach — https://github.com/Exaphis/mutube

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

## Disclaimer

TubeTV is an independent project and is not affiliated with, endorsed by, or sponsored by YouTube, Google, Apple, TizenTube or μTube.
