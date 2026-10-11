# Stable patching model

The stable TubeTV direction is based on a compatible user-provided YouTube tvOS 4.54.01 application package.

## Stable changes

TubeTV applies only the changes needed for the proven Apple TV build:

1. Keep the original YouTube tvOS runtime/player for playback and account handling.
2. Use the TubeTV application identity:
   - bundle identifier: `cz.caseycz.tubetv`
   - display name: `TubeTV`
3. Keep compatibility for the validated Apple TV device set:
   - `AppleTV5,3`
   - `AppleTV6,2`
   - `AppleTV11,1`
4. Apply the Cobalt injection hooks needed to load the TizenTube userscript layer.
5. Keep TizenTube functionality and settings intact, including user-configurable SponsorBlock.
6. Do not force the experimental TubeTV Blue theme in the stable build.
7. Re-sign the resulting application locally with the user's own signing identity before installation.

## Version constraint

The binary patch locations used by this approach are specific to YouTube tvOS **4.54.01**. A different YouTube build must be independently validated before the same patch strategy is used.

## Distribution

The source repository intentionally excludes YouTube IPA/TIPA files and extracted proprietary application payloads. This repository is for project documentation and the open customization layer only.

The tested stable IPA is treated as a local/user-supplied build artifact, not as source-controlled project content.
