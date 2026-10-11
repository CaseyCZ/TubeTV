# Third-party notices

TubeTV is an independent project. The current stable architecture relies on or is informed by the following third-party software and proprietary runtime components.

## TizenTube

Project: https://github.com/reisxd/TizenTube

License: GPL-3.0-only

TizenTube provides the TV-focused enhancement layer used by the current TubeTV direction, including ad blocking and optional features such as SponsorBlock and playback-related settings.

TubeTV does not claim TizenTube as its own work. Any TizenTube-derived code distributed by TubeTV must remain compliant with the applicable GPL terms.

## μTube

Project: https://github.com/Exaphis/mutube

μTube is credited as an important reference for the Apple TV / Cobalt injection and patching approach used to integrate a userscript layer with the YouTube tvOS runtime.

TubeTV does not claim μTube's work as its own. Before redistributing code copied from μTube, its current licensing terms must be reviewed and followed.

## YouTube / Google

The YouTube tvOS application, runtime, media services, trademarks and related proprietary components belong to Google and their respective rights holders.

The TubeTV source repository contains the TubeTV-specific builder, patch data and customization source, but does not store the proprietary YouTube tvOS base package used for local rebuilding. The validated YouTube tvOS 4.54.01 base is kept locally as `Tube.tipa`; only its version, metadata and cryptographic fingerprints are tracked in `BASE_INPUT.md` and the patch map.

The published TubeTV release asset is separate from the source-controlled development baseline. Use of YouTube application components remains subject to the applicable licenses, terms and laws.

## Apple

Apple, Apple TV and tvOS are trademarks of Apple Inc. TubeTV is not affiliated with or endorsed by Apple.

## Historical native client work

Earlier TubeTV history contains a standalone SwiftUI/native client and experiments informed by other open-source TV clients, including SmartTube. That implementation is retained in Git history for reference but is not the current stable architecture.
