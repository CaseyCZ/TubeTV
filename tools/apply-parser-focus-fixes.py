from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Patched {path}")


inner = Path("TubeTV/InnerTubeService.swift")
inner_text = inner.read_text(encoding="utf-8")
helper_marker = "    private static func extractVideos(from root: Any) -> [VideoItem] {\n"
if inner_text.count(helper_marker) != 1:
    raise SystemExit("InnerTubeService.swift: extractVideos marker changed")

helper = '''    private static func videoTitle(\n        from renderer: [String: Any]\n    ) -> String? {\n        firstText(\n            in: renderer,\n            keys: [\"title\", \"headline\", \"primaryText\"]\n        )\n        ?? text(\n            from: nested(\n                renderer,\n                path: [\n                    \"metadata\",\n                    \"tileMetadataRenderer\",\n                    \"title\"\n                ]\n            )\n        )\n        ?? text(\n            from: nested(\n                renderer,\n                path: [\n                    \"metadata\",\n                    \"lockupMetadataViewModel\",\n                    \"title\"\n                ]\n            )\n        )\n    }\n\n'''
inner_text = inner_text.replace(helper_marker, helper + helper_marker, 1)

old_inner = '''        for renderer in renderers {\n            guard let videoID = videoID(from: renderer),\n                  videoID.count == 11,\n                  seen.insert(videoID).inserted else {\n                continue\n            }\n\n            let title =\n                firstText(\n                    in: renderer,\n                    keys: [\"title\", \"headline\", \"primaryText\"]\n                )\n                ?? text(\n                    from: nested(\n                        renderer,\n                        path: [\n                            \"metadata\",\n                            \"tileMetadataRenderer\",\n                            \"title\"\n                        ]\n                    )\n                )\n                ?? text(\n                    from: nested(\n                        renderer,\n                        path: [\n                            \"metadata\",\n                            \"lockupMetadataViewModel\",\n                            \"title\"\n                        ]\n                    )\n                )\n                ?? \"YouTube video\"\n'''
new_inner = '''        for candidate in renderers {\n            guard let videoID = Self.videoID(from: candidate),\n                  videoID.count == 11,\n                  seen.insert(videoID).inserted else {\n                continue\n            }\n\n            // TV Home can expose the same video through both a sparse wrapper\n            // and a richer lockupViewModel. Prefer the duplicate renderer that\n            // actually carries a title before falling back to generic text.\n            let renderer =\n                renderers.first(where: {\n                    Self.videoID(from: $0) == videoID\n                        && videoTitle(from: $0) != nil\n                })\n                ?? candidate\n\n            let title =\n                videoTitle(from: renderer)\n                ?? \"YouTube video\"\n'''
if inner_text.count(old_inner) != 1:
    raise SystemExit(f"InnerTubeService.swift: expected one extractVideos body, found {inner_text.count(old_inner)}")
inner_text = inner_text.replace(old_inner, new_inner, 1)
inner.write_text(inner_text, encoding="utf-8")
print("Patched TubeTV/InnerTubeService.swift")

old_home = '''                    ForEach(\n                        videos.indices,\n                        id: \\.self\n                    ) { index in\n                        let video = videos[index]\n\n                        NavigationLink(\n                            value: video\n                        ) {\n                            VideoCard(video: video)\n                        }\n                        .buttonStyle(.plain)\n                        .onAppear {\n                            let threshold =\n                                max(\n                                    0,\n                                    videos.count - 4\n                                )\n\n                            if index >= threshold {\n                                onLoadMore?()\n                            }\n                        }\n                    }\n'''
new_home = '''                    ForEach(videos) { video in\n                        NavigationLink(\n                            value: video\n                        ) {\n                            VideoCard(video: video)\n                        }\n                        .buttonStyle(.plain)\n                        .onAppear {\n                            let nearEndIDs =\n                                videos\n                                    .suffix(4)\n                                    .map(\\.id)\n\n                            if nearEndIDs.contains(video.id) {\n                                onLoadMore?()\n                            }\n                        }\n                    }\n'''
replace_once("TubeTV/HomeView.swift", old_home, new_home)

old_search = '''                        ForEach(\n                            visibleResults.indices,\n                            id: \\.self\n                        ) { index in\n                            let item = visibleResults[index]\n\n                            searchResultView(item)\n                                .onAppear {\n                                    guard !query.isEmpty,\n                                          index >= max(\n                                            0,\n                                            results.count - 4\n                                          ) else {\n                                        return\n                                    }\n\n                                    let generation = searchGeneration\n\n                                    Task {\n                                        await loadMore(\n                                            generation: generation\n                                        )\n                                    }\n                                }\n                        }\n'''
new_search = '''                        ForEach(visibleResults) { item in\n                            searchResultView(item)\n                                .onAppear {\n                                    let nearEndIDs =\n                                        visibleResults\n                                            .suffix(4)\n                                            .map(\\.id)\n\n                                    guard !query.isEmpty,\n                                          nearEndIDs\n                                            .contains(item.id) else {\n                                        return\n                                    }\n\n                                    let generation = searchGeneration\n\n                                    Task {\n                                        await loadMore(\n                                            generation: generation\n                                        )\n                                    }\n                                }\n                        }\n'''
replace_once("TubeTV/SearchView.swift", old_search, new_search)

old_root = '''        .preferredColorScheme(.dark)\n        .id(appLanguage)\n'''
new_root = '''        .preferredColorScheme(.dark)\n'''
replace_once("TubeTV/RootView.swift", old_root, new_root)
