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

## Download

The stable build is published on GitHub Releases as:

- `TubeTV-Stable.ipa`
- Release: https://github.com/CaseyCZ/TubeTV/releases/tag/v1.0.0

## Stable baseline

This release intentionally keeps the original YouTube/Cobalt visual appearance and minimizes changes to the proven playback runtime.

The implementation uses the YouTube tvOS 4.54.01 application as the playback/runtime base and adds TubeTV identity, device compatibility adjustments and the TizenTube enhancement layer.

## Source and rebuild

`Master` contains the complete TubeTV-specific patch/build source used as the baseline for future versions:

- `tools/build_tubetv.py`
- `patches/tubetv-stable-v1.js`
- `patches/youtube-4.54.01.json`
- `patches/youtube-4.54.01-native.hex`
- `BASE_INPUT.md`
- `PATCHING.md`

The validated base package itself is kept locally as `Tube.tipa` and is not stored in Git source control. Its exact SHA-256, executable fingerprint, version and bundle metadata are documented in `BASE_INPUT.md`.

With the local validated base in the repository root, v1.0.0 can be rebuilt with:

```bash
python3 tools/build_tubetv.py Tube.tipa -o TubeTV-Stable.ipa
```

The builder validates the base package and the resulting patched executable against the v1.0.0 baseline.

## Development baseline

Future TubeTV releases should start from this v1.0.0 source baseline. Keep `patches/tubetv-stable-v1.js` unchanged and create a new versioned patch file for each subsequent release, for example `patches/tubetv-v1.0.1.js`.

See [PATCHING.md](PATCHING.md) for the current development and release workflow.

## Third-party credits

TubeTV uses or is informed by:

- TizenTube — GPL-3.0-only — https://github.com/reisxd/TizenTube
- μTube — reference for the Apple TV / Cobalt injection approach — https://github.com/Exaphis/mutube

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

## Disclaimer

TubeTV is an independent project and is not affiliated with, endorsed by, or sponsored by YouTube, Google, Apple, TizenTube or μTube.

YouTube is a trademark of Google LLC. Third-party projects, applications and components remain subject to their own licenses and terms.
