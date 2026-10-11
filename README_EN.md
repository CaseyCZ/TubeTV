<p align="center">
  <img src="readme-header.svg" alt="TubeTV by CaseyCZ" width="100%" />
</p>

<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/CZ-%C4%8Ce%C5%A1tina-172033?style=for-the-badge&labelColor=111827" alt="Čeština" /></a>
  <img src="https://img.shields.io/badge/EN-English-38BDF8?style=for-the-badge&labelColor=0284C7" alt="English" />
</p>

<p align="center">
  YouTube for Apple TV with <strong>TizenTube</strong> enhancements, ad blocking and the native tvOS playback path preserved.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/RELEASE-v1.0.0-38BDF8?style=for-the-badge&labelColor=0284C7" alt="TubeTV v1.0.0" />
  <img src="https://img.shields.io/badge/STATUS-Stable-86EFAC?style=for-the-badge&labelColor=166534" alt="Stable" />
  <img src="https://img.shields.io/badge/tvOS-YouTube%204.54.01-172033?style=for-the-badge&labelColor=111827" alt="YouTube tvOS 4.54.01" />
</p>

<p align="center">
  <a href="https://github.com/CaseyCZ/TubeTV/releases/tag/v1.0.0"><img src="https://img.shields.io/badge/Download-TubeTV%20Stable-38BDF8?style=for-the-badge&labelColor=0284C7&logo=github&logoColor=white" alt="Download TubeTV Stable" /></a>
  <a href="PATCHING.md"><img src="https://img.shields.io/badge/Build%20%26%20Patching-Guide-172033?style=for-the-badge&labelColor=111827" alt="Build and patching guide" /></a>
  <a href="https://github.com/CaseyCZ/TubeTV/issues"><img src="https://img.shields.io/badge/GitHub-Report%20issue-172033?style=for-the-badge&labelColor=111827&logo=github&logoColor=white" alt="Report issue" /></a>
</p>

## About

**TubeTV** is an independent YouTube modification for Apple TV focused on stable playback and practical TV enhancements without replacing the original tvOS player.

The current stable release uses the validated **YouTube tvOS 4.54.01** runtime with **TizenTube** layered on top. The original YouTube / Cobalt interface, sign-in flow, captions, seeking, codec handling and Apple TV Remote behavior remain intact.

## Main features

- 📺 original YouTube / Cobalt interface
- 🚫 ad blocking through TizenTube
- ⏭️ optional **SponsorBlock** in TizenTube settings
- ⚡ playback speed and additional TV-focused TizenTube features
- 🔐 standard YouTube sign-in
- 💬 captions and the original YouTube tvOS playback path
- 🎮 native Apple TV Remote behavior
- 📦 dedicated TubeTV identity `cz.caseycz.tubetv`
- 🍎 compatibility with `AppleTV5,3`, `AppleTV6,2` and `AppleTV11,1`

## Current release

**TubeTV 1.0.0 Stable** is the current production release.

| Item | Value |
|---|---|
| Base | YouTube tvOS **4.54.01** |
| Validated device | Apple TV HD (`AppleTV5,3`) |
| Bundle ID | `cz.caseycz.tubetv` |
| Interface | original YouTube / Cobalt |
| Feature layer | TizenTube |
| SponsorBlock | optional |
| Release asset | `TubeTV-Stable.ipa` |

The current build is available from **[GitHub Releases](https://github.com/CaseyCZ/TubeTV/releases/tag/v1.0.0)**.

Experimental **TubeTV Blue UI** is not part of the stable release.

## Architecture

TubeTV keeps YouTube tvOS as the main runtime and playback layer. The project adds its own app identity, validated ARM64/Cobalt patches and the TubeTV/TizenTube injection layer.

This approach minimizes changes to the part of the application responsible for playback and makes future releases reproducible from the same validated base.

## Source and future development

`Master` contains all **TubeTV-specific source files** required for fixes and future releases:

- `tools/build_tubetv.py` — reproducible IPA/TIPA builder
- `patches/tubetv-stable-v1.js` — stable TubeTV/TizenTube injection for v1.0.0
- `patches/youtube-4.54.01.json` — validated patch locations, metadata and SHA-256 checks
- `patches/youtube-4.54.01-native.hex` — ARM64 native patch block
- `BASE_INPUT.md` — exact fingerprint of the supported base package
- `PATCHING.md` — complete build and development workflow

The only item **not stored in Git** is the local `Tube.tipa` base containing the YouTube tvOS 4.54.01 runtime. It is kept locally, and `.gitignore` intentionally excludes `*.tipa` and `*.ipa`.

Recommended local layout after cloning the repository:

```text
TubeTV/
├── Tube.tipa                 # local base, not committed
├── tools/
│   └── build_tubetv.py
├── patches/
├── PATCHING.md
└── BASE_INPUT.md
```

The current stable IPA can then be rebuilt directly:

```bash
python3 tools/build_tubetv.py Tube.tipa -o TubeTV-Stable.ipa
```

The builder validates the package fingerprint, version, bundle ID, executable and expected native patch locations. The exact supported local input is documented in **[BASE_INPUT.md](BASE_INPUT.md)**.

See **[PATCHING.md](PATCHING.md)** and **[patches/README.md](patches/README.md)** for future release development.

## Credits

TubeTV uses or builds on work from these open-source projects:

- **TizenTube** — https://github.com/reisxd/TizenTube — GPL-3.0-only
- **μTube** — https://github.com/Exaphis/mutube — reference for Apple TV / Cobalt patching

See **[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)** for details.

## Important

TubeTV is an independent community project and is not officially affiliated with, supported by or endorsed by YouTube, Google, Apple, TizenTube or μTube.

YouTube is a trademark of Google LLC. Third-party projects, applications and components remain subject to their own licenses and terms.

## Support

<p align="center">
  <a href="https://www.buymeacoffee.com/caseycz"><img src="https://img.shields.io/badge/Support%20CaseyCZ-Buy%20Me%20a%20Coffee-38BDF8?style=for-the-badge&labelColor=0284C7&logo=buymeacoffee&logoColor=white" alt="Support CaseyCZ" /></a>
</p>

<p align="center">
  <a href="https://www.buymeacoffee.com/caseycz"><img src="https://caseycz.github.io/support-qr.svg" width="150" alt="Buy Me a Coffee QR code" /></a><br>
  <sub>Scan the QR code or click the button.</sub>
</p>

<p align="center">
  <a href="https://caseycz.github.io/"><img src="https://img.shields.io/badge/CaseyCZ%20Website-Open-172033?style=flat-square&labelColor=111827" alt="CaseyCZ Website" /></a>
</p>
