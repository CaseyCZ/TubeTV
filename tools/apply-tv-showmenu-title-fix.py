from pathlib import Path

path = Path("TubeTV/InnerTubeService.swift")
text = path.read_text()

needle = '''        if let value = nested(
            renderer,
            path: [
                "metadata",
                "lockupMetadataViewModel",
                "title"
            ]
        ), let title = text(from: value), !title.isEmpty {
            return title
        }

        return nil
'''
replacement = '''        if let value = nested(
            renderer,
            path: [
                "metadata",
                "lockupMetadataViewModel",
                "title"
            ]
        ), let title = text(from: value), !title.isEmpty {
            return title
        }

        // Final SmartTube TileItem title fallback. Current YouTube TV Home
        // payloads can keep the visible video title only on the long-press
        // show-menu command even when tile metadata itself is sparse.
        if let value = nested(
            renderer,
            path: [
                "onLongPressCommand",
                "showMenuCommand",
                "title"
            ]
        ), let title = text(from: value), !title.isEmpty {
            return title
        }

        return nil
'''

if needle not in text:
    raise SystemExit("videoTitle lockup fallback block not found")

text = text.replace(needle, replacement, 1)
path.write_text(text)
