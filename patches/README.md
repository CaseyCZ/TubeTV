# Active TubeTV patch sources

This directory contains the active patch data used by the current TubeTV implementation.

## Files

- `tubetv-stable-v1.js` — exact JavaScript injection used by the validated v1.0.0 build.
- `youtube-4.54.01.json` — validated executable SHA-256 values, metadata, code-cave layout and ARM64 patch locations for YouTube tvOS 4.54.01.
- `youtube-4.54.01-native.hex` — native support block written into the validated code cave.

The builder is `tools/build_tubetv.py`.

## Local base package

The patch sources in this directory are designed for the validated local `Tube.tipa` base documented in `BASE_INPUT.md`.

Recommended local repository layout:

```text
TubeTV/
├── Tube.tipa                 # local only, ignored by Git
├── tools/
│   └── build_tubetv.py
└── patches/
    ├── tubetv-stable-v1.js
    ├── youtube-4.54.01.json
    └── youtube-4.54.01-native.hex
```

Reference base executable SHA-256:

```text
2a1747008e4e9585bfd6b80fa180263395817415af1681c9090f12ba64f016da
```

Reference `Tube.tipa` package SHA-256:

```text
48f65a92c87a36775ed8294a77994f0ad0f2c44a9fbf92bf2f4ca3a2acd3b514
```

## Reproducing v1.0.0

From the repository root:

```bash
python3 tools/build_tubetv.py Tube.tipa -o TubeTV-Stable.ipa
```

If the local base is stored elsewhere, pass its full path instead.

With the unchanged stable injection source, the patched executable must become:

```text
377c21b1620de9248574d008832dff1c7b25ad30ce48047ac3323f66f409b22c
```

This was verified against the executable and `Info.plist` contained in the published TubeTV v1.0.0 stable IPA.

## Developing the next version

Keep `tubetv-stable-v1.js` unchanged as the v1.0.0 baseline. For TubeTV-only changes, copy it to a new versioned file, for example:

```text
patches/tubetv-v1.0.1.js
```

Then build from the same local base:

```bash
python3 tools/build_tubetv.py Tube.tipa \
  --js patches/tubetv-v1.0.1.js \
  -o TubeTV-v1.0.1.ipa
```

The current JS code cave has a maximum payload size of **2040 bytes**. If a future injection exceeds that size or a different YouTube tvOS version is used, create and validate a new patch map/native layout instead of reusing the 4.54.01 offsets blindly.

The older standalone SwiftUI implementation is not the active TubeTV runtime; it remains available in Git history for reference.
