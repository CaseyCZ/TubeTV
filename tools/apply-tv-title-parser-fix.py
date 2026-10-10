from pathlib import Path

path = Path("TubeTV/InnerTubeService.swift")
text = path.read_text()

start = text.index("    private static func videoTitle(\n")
end = text.index("\n    private static func extractVideos", start)
replacement = '''    private static func videoTitle(
        from renderer: [String: Any]
    ) -> String? {
        if let direct = firstText(
            in: renderer,
            keys: ["title", "headline", "primaryText"]
        ), !direct.isEmpty {
            return direct
        }

        // Keep current TV tile parsing aligned with SmartTube's
        // MediaServiceCore. YouTube can place the title either in
        // tile metadata or inside the thumbnail overlay.
        if let value = nested(
            renderer,
            path: [
                "metadata",
                "tileMetadataRenderer",
                "title"
            ]
        ), let title = text(from: value), !title.isEmpty {
            return title
        }

        if let overlays = nested(
            renderer,
            path: [
                "header",
                "tileHeaderRenderer",
                "thumbnailOverlays"
            ]
        ) as? [Any] {
            for overlay in overlays {
                guard let dictionary = overlay as? [String: Any],
                      let value = nested(
                        dictionary,
                        path: [
                            "tileMetadataRenderer",
                            "title"
                        ]
                      ),
                      let title = text(from: value),
                      !title.isEmpty else {
                    continue
                }

                return title
            }
        }

        if let value = nested(
            renderer,
            path: [
                "header",
                "trackTileHeaderRenderer",
                "title"
            ]
        ), let title = text(from: value), !title.isEmpty {
            return title
        }

        if let value = nested(
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
    }

    private static func isModernTVVideoRenderer(
        _ renderer: [String: Any]
    ) -> Bool {
        if let contentType = renderer["contentType"] as? String,
           contentType.hasPrefix("TILE_")
            || contentType.hasPrefix("LOCKUP_") {
            return true
        }

        return nested(
            renderer,
            path: ["metadata", "tileMetadataRenderer"]
        ) != nil
            || nested(
                renderer,
                path: ["metadata", "lockupMetadataViewModel"]
            ) != nil
    }
'''
text = text[:start] + replacement + text[end:]

old = '''            let channel =
                [rawChannel]
                    .compactMap { $0 }
                    .first(where: {
                        !looksLikeDuration($0)
                    })
                ?? metadata.first(
                    where: {
                        !looksLikeDuration($0)
                    }
                )
                ?? "YouTube"
'''
new = '''            let channel =
                [rawChannel]
                    .compactMap { $0 }
                    .first(where: {
                        !looksLikeDuration($0)
                    })
                ?? (
                    isModernTVVideoRenderer(renderer)
                    ? nil
                    : metadata.first(
                        where: {
                            !looksLikeDuration($0)
                        }
                    )
                )
                ?? "YouTube"
'''
if old not in text:
    raise SystemExit("channel fallback block not found")
text = text.replace(old, new, 1)

path.write_text(text)
