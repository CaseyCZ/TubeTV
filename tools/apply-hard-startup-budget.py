from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {text.count(old)}")
    return text.replace(old, new, 1)

# 1) Cancellation must stop the resolver chain instead of falling through to
# more clients after the task-group timeout has already fired.
path = Path("TubeTV/StreamResolver.swift")
text = path.read_text()
text = replace_once(
    text,
    '''            } catch let error as StreamResolverError {
                if case .ipBlocked = error {
                    throw error
                }

                meaningfulError = error
            } catch {
                // Continue to the SmartTube-compatible fallback chain.
            }
''',
    '''            } catch let error as StreamResolverError {
                try Task.checkCancellation()

                if case .ipBlocked = error {
                    throw error
                }

                meaningfulError = error
            } catch {
                try Task.checkCancellation()
                // Continue to the SmartTube-compatible fallback chain.
            }
''',
    "authenticated resolver cancellation",
)
text = replace_once(
    text,
    '''        } catch let error as StreamResolverError {
            if case .ipBlocked = error {
                throw error
            }

            if case .signInRequired = error {
                throw error
            }

            meaningfulError = error
        } catch {
            // Continue to the final direct-stream fallback.
        }
''',
    '''        } catch let error as StreamResolverError {
            try Task.checkCancellation()

            if case .ipBlocked = error {
                throw error
            }

            if case .signInRequired = error {
                throw error
            }

            meaningfulError = error
        } catch {
            try Task.checkCancellation()
            // Continue to the final direct-stream fallback.
        }
''',
    "alternative resolver cancellation",
)
text = replace_once(
    text,
    '''        } catch {
            if let meaningfulError {
                throw meaningfulError
            }

            throw error
        }
''',
    '''        } catch {
            try Task.checkCancellation()

            if let meaningfulError {
                throw meaningfulError
            }

            throw error
        }
''',
    "YouTubeKit cancellation",
)
path.write_text(text)

# 2) AlternativePlayerService must observe cancellation even when an internal
# helper used try? / catch and otherwise hid URLSession cancellation.
path = Path("TubeTV/AlternativePlayerService.swift")
text = path.read_text()
text = replace_once(
    text,
    '''        if let lastSuccessfulProfile,
           let preferred =
''',
    '''        try Task.checkCancellation()

        if let lastSuccessfulProfile,
           let preferred =
''',
    "post-bootstrap cancellation",
)
text = replace_once(
    text,
    '''        for client in orderedClients {
            let clientStartedAt = Date()
''',
    '''        for client in orderedClients {
            try Task.checkCancellation()

            let clientStartedAt = Date()
''',
    "client-loop cancellation",
)
text = replace_once(
    text,
    '''                    await seedWebSession(
                        videoID: videoID
                    )
                }

                if let source = try await resolve(
''',
    '''                    await seedWebSession(
                        videoID: videoID
                    )
                    try Task.checkCancellation()
                }

                if let source = try await resolve(
''',
    "seed cancellation",
)
text = replace_once(
    text,
    '''            } catch let error as StreamResolverError {
                if case .ipBlocked = error {
''',
    '''            } catch let error as StreamResolverError {
                try Task.checkCancellation()

                if case .ipBlocked = error {
''',
    "client typed catch cancellation",
)
text = replace_once(
    text,
    '''            } catch {
                lastError = error
                logger.error(
                    "Client failed client=\\(client.profile, privacy: .public) error=\\(error.localizedDescription, privacy: .public)"
                )
            }
''',
    '''            } catch {
                try Task.checkCancellation()

                lastError = error
                logger.error(
                    "Client failed client=\\(client.profile, privacy: .public) error=\\(error.localizedDescription, privacy: .public)"
                )
            }
''',
    "client generic catch cancellation",
)
text = replace_once(
    text,
    '''        let bootstrap =
            try? await SmartTubeAuthService
                .shared.bootstrap()
        let bootstrapVisitor =
''',
    '''        let bootstrap =
            try? await SmartTubeAuthService
                .shared.bootstrap()
        try Task.checkCancellation()

        let bootstrapVisitor =
''',
    "per-client bootstrap cancellation",
)
path.write_text(text)

# 3) Bound AVPlayer failover itself. Initial resolver is capped at 12 s; an
# 18 s player window therefore keeps ordinary worst-case startup around 30 s.
path = Path("TubeTV/PlayerView.swift")
text = path.read_text()
text = replace_once(
    text,
    '''    private var didPrepare = false
    private var playerStartupStartedAt: Date?
''',
    '''    private var didPrepare = false
    private var playerStartupStartedAt: Date?
    private let maximumFailoverDuration: TimeInterval = 18
''',
    "player failover constant",
)
text = replace_once(
    text,
    '''        var lastError: Error =
            StreamResolverError.noPlayableStream

        for attempt in 1...10 {
            guard let source = nextSource,
                  !attemptedSources.contains(source) else {
                break
            }
''',
    '''        var lastError: Error =
            StreamResolverError.noPlayableStream
        let failoverDeadline =
            Date().addingTimeInterval(
                maximumFailoverDuration
            )

        for attempt in 1...10 {
            guard Date() < failoverDeadline else {
                playbackLogger.error(
                    "Startup failover budget exhausted"
                )
                break
            }

            guard let source = nextSource,
                  !attemptedSources.contains(source) else {
                break
            }
''',
    "player failover deadline",
)
text = replace_once(
    text,
    '''                try await activateAndVerify(
                    source
                )
''',
    '''                try await activateAndVerify(
                    source,
                    deadline: failoverDeadline
                )
''',
    "startup activation deadline",
)
text = replace_once(
    text,
    '''                failedClientProfiles.insert(
                    failedProfile
                )

                do {
                    nextSource =
''',
    '''                failedClientProfiles.insert(
                    failedProfile
                )

                // A retry resolver can consume up to eight seconds. Do not
                // start one if it cannot finish inside this failover window.
                guard failoverDeadline.timeIntervalSinceNow >= 8 else {
                    playbackLogger.error(
                        "Startup budget too small for another resolver retry"
                    )
                    nextSource = nil
                    break
                }

                do {
                    nextSource =
''',
    "resolver retry budget",
)
text = replace_once(
    text,
    '''    private func activateAndVerify(
        _ source: PlaybackSource
    ) async throws {
        let item =
            try await makePlayerItem(
                from: source
            )

        guard TubeTVPlayerEngine.shared
''',
    '''    private func activateAndVerify(
        _ source: PlaybackSource,
        deadline: Date? = nil
    ) async throws {
        let item =
            try await makePlayerItem(
                from: source
            )

        if let deadline,
           Date() >= deadline {
            throw StreamResolverError
                .noPlayableStream
        }

        guard TubeTVPlayerEngine.shared
''',
    "activation signature",
)
text = replace_once(
    text,
    '''        try await waitUntilReadyToPlay(
            item
        )
''',
    '''        try await waitUntilReadyToPlay(
            item,
            deadline: deadline
        )
''',
    "startup readiness deadline",
)
text = replace_once(
    text,
    '''    private func waitUntilReadyToPlay(
        _ item: AVPlayerItem
    ) async throws {
        // A healthy HLS/muxed source should become ready quickly. Do not
        // spend tens of seconds on a source that AVPlayer can't prepare;
        // fail over to the next SmartTube client instead.
        for _ in 0..<80 {
            switch item.status {
''',
    '''    private func waitUntilReadyToPlay(
        _ item: AVPlayerItem,
        deadline: Date? = nil
    ) async throws {
        // A healthy HLS/muxed source should become ready quickly. Do not
        // spend tens of seconds on a source that AVPlayer can't prepare;
        // fail over to the next SmartTube client instead. During initial
        // failover, all sources also share one global player deadline.
        for _ in 0..<80 {
            if let deadline,
               Date() >= deadline {
                playbackLogger.notice(
                    "Startup global player deadline reached"
                )
                throw StreamResolverError
                    .noPlayableStream
            }

            switch item.status {
''',
    "readiness deadline",
)
path.write_text(text)

# 4) Remove the duplicate content fallback introduced while validating modern
# TV TextItem parsing. The guarded version before `runs` is sufficient and
# avoids returning an empty content string before structured fallback keys.
path = Path("TubeTV/InnerTubeService.swift")
text = path.read_text()
text = replace_once(
    text,
    '''            if let content = dictionary["content"] as? String {
                return content
            }

            for nestedKey in [
''',
    '''            for nestedKey in [
''',
    "duplicate TextItem content fallback",
)
path.write_text(text)
