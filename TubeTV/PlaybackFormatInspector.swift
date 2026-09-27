import AVFoundation
import CoreMedia
import Foundation

struct PlaybackFormatInfo: Hashable {
    let width: Int
    let height: Int
    let fps: Double
    let codec: String
    let dynamicRange: String

    var resolutionLabel: String {
        guard height > 0 else { return "Neznámé" }

        if height >= 2160 {
            return "2160p"
        }

        if height >= 1440 {
            return "1440p"
        }

        if height >= 1080 {
            return "1080p"
        }

        if height >= 720 {
            return "720p"
        }

        return "\(height)p"
    }

    var fpsLabel: String {
        guard fps > 0 else { return "" }

        let rounded = Int(fps.rounded())

        if rounded >= 50 {
            return "\(rounded) fps"
        }

        return "\(rounded) fps"
    }

    var displayName: String {
        [
            resolutionLabel,
            fpsLabel,
            dynamicRange,
            codec
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }
}

enum PlaybackFormatInspector {
    static func inspect(
        asset: AVAsset
    ) async -> PlaybackFormatInfo? {
        do {
            let tracks = try await asset.loadTracks(
                withMediaType: .video
            )

            guard let track = tracks.first else {
                return nil
            }

            async let naturalSize = track.load(.naturalSize)
            async let transform = track.load(.preferredTransform)
            async let nominalFrameRate = track.load(.nominalFrameRate)
            async let formatDescriptions = track.load(.formatDescriptions)

            let rawSize = try await naturalSize
            let preferredTransform = try await transform
            let fps = Double(try await nominalFrameRate)
            let descriptions = try await formatDescriptions

            let transformed = rawSize.applying(preferredTransform)
            let width = Int(abs(transformed.width).rounded())
            let height = Int(abs(transformed.height).rounded())

            let firstDescription = descriptions.first
            let codec = firstDescription
                .map { codecName(for: CMFormatDescriptionGetMediaSubType($0)) }
                ?? "Video"

            let dynamicRange = firstDescription
                .map(dynamicRangeName)
                ?? "SDR"

            return PlaybackFormatInfo(
                width: width,
                height: height,
                fps: fps,
                codec: codec,
                dynamicRange: dynamicRange
            )
        } catch {
            return nil
        }
    }

    private static func codecName(
        for subtype: FourCharCode
    ) -> String {
        let code = fourCC(subtype).lowercased()

        if code.hasPrefix("avc") {
            return "H.264"
        }

        if code == "hvc1" || code == "hev1" {
            return "HEVC"
        }

        if code == "av01" {
            return "AV1"
        }

        if code == "vp09" || code == "vp9 " {
            return "VP9"
        }

        if code == "dvh1" || code == "dvhe" {
            return "Dolby Vision"
        }

        return fourCC(subtype)
    }

    private static func dynamicRangeName(
        _ description: CMFormatDescription
    ) -> String {
        let codec = fourCC(
            CMFormatDescriptionGetMediaSubType(description)
        ).lowercased()

        if codec == "dvh1" || codec == "dvhe" {
            return "Dolby Vision"
        }

        let extensions =
            CMFormatDescriptionGetExtensions(description)
            as NSDictionary

        let text = extensions.description.lowercased()

        if text.contains("smpte_st_2084")
            || text.contains("2084")
            || text.contains("pq") {
            return "HDR10"
        }

        if text.contains("itu_r_2100_hlg")
            || text.contains("2100")
            || text.contains("hlg") {
            return "HLG"
        }

        if text.contains("hdr") {
            return "HDR"
        }

        return "SDR"
    }

    private static func fourCC(
        _ value: FourCharCode
    ) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]

        return String(
            bytes: bytes,
            encoding: .ascii
        ) ?? String(format: "0x%08X", value)
    }
}
