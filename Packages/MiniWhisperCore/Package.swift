// swift-tools-version: 6.0
import PackageDescription

/// Module dependency edges follow design §5.2: everything flows downwards and
/// nothing depends on MWPipeline or MWMeetingPipeline.
let package = Package(
    name: "MiniWhisperCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MWSupport", targets: ["MWSupport"]),
        .library(name: "MWConfig", targets: ["MWConfig"]),
        .library(name: "MWCorrections", targets: ["MWCorrections"]),
        .library(name: "MWHotkeys", targets: ["MWHotkeys"]),
        .library(name: "MWAudio", targets: ["MWAudio"]),
        .library(name: "MWStreaming", targets: ["MWStreaming"]),
        .library(name: "MWTranscription", targets: ["MWTranscription"]),
        .library(name: "MWUsage", targets: ["MWUsage"]),
        .library(name: "MWHistory", targets: ["MWHistory"]),
        .library(name: "MWProfiles", targets: ["MWProfiles"]),
        .library(name: "MWPaste", targets: ["MWPaste"]),
        .library(name: "MWOverlaySim", targets: ["MWOverlaySim"]),
        .library(name: "MWPipeline", targets: ["MWPipeline"]),
        .library(name: "MWMeetings", targets: ["MWMeetings"]),
        .library(name: "MWMeetingPipeline", targets: ["MWMeetingPipeline"]),
        .library(name: "MWAgentAccess", targets: ["MWAgentAccess"]),
    ],
    targets: [
        .target(name: "MWSupport"),
        .target(name: "MWConfig", dependencies: ["MWSupport", "MWOverlaySim"]),
        .target(name: "MWCorrections", dependencies: ["MWConfig"]),
        .target(name: "MWHotkeys"),
        .target(name: "MWAudio", dependencies: ["MWSupport"]),
        .target(
            name: "MWStreaming",
            dependencies: ["MWAudio", "MWConfig", "MWCorrections", "MWSupport"]
        ),
        .target(name: "MWTranscription", dependencies: ["MWSupport"]),
        .target(name: "MWUsage", dependencies: ["MWConfig", "MWSupport"]),
        .target(name: "MWHistory", dependencies: ["MWSupport"]),
        .target(name: "MWProfiles", dependencies: ["MWConfig", "MWCorrections"]),
        .target(name: "MWPaste", dependencies: ["MWConfig", "MWSupport"]),
        .target(name: "MWOverlaySim"),
        .target(
            name: "MWPipeline",
            dependencies: [
                "MWSupport", "MWConfig", "MWCorrections", "MWHotkeys", "MWAudio",
                "MWStreaming", "MWTranscription", "MWUsage", "MWHistory", "MWProfiles",
                "MWPaste", "MWOverlaySim",
            ]
        ),
        .target(name: "MWMeetings", dependencies: ["MWConfig", "MWSupport"]),
        .target(
            name: "MWMeetingPipeline",
            dependencies: [
                "MWMeetings", "MWStreaming", "MWAudio", "MWConfig", "MWCorrections", "MWUsage",
                "MWTranscription", "MWSupport",
            ]
        ),
        // Read-only meeting access for the CLI and MCP server: no audio, streaming or pipeline.
        .target(name: "MWAgentAccess", dependencies: ["MWMeetings", "MWSupport"]),
        .target(
            name: "MWTestSupport",
            dependencies: [
                "MWSupport", "MWConfig", "MWCorrections", "MWHotkeys", "MWAudio",
                "MWStreaming", "MWTranscription", "MWUsage", "MWHistory", "MWProfiles",
                "MWPaste", "MWOverlaySim", "MWPipeline", "MWMeetings",
            ],
            // The WAV fixtures several test targets share, reached through
            // `TestFixtures.wav(_:)`.
            resources: [.copy("Fixtures")]
        ),

        .testTarget(name: "MWSupportTests", dependencies: ["MWSupport", "MWTestSupport"]),
        .testTarget(name: "MWConfigTests", dependencies: ["MWConfig", "MWTestSupport"]),
        .testTarget(name: "MWCorrectionsTests", dependencies: ["MWCorrections", "MWTestSupport"]),
        .testTarget(name: "MWHotkeysTests", dependencies: ["MWHotkeys", "MWTestSupport"]),
        .testTarget(name: "MWAudioTests", dependencies: ["MWAudio", "MWTestSupport"]),
        .testTarget(
            name: "MWStreamingTests",
            dependencies: ["MWStreaming", "MWTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MWTranscriptionTests", dependencies: ["MWTranscription", "MWTestSupport"]),
        .testTarget(name: "MWUsageTests", dependencies: ["MWUsage", "MWTestSupport"]),
        .testTarget(name: "MWHistoryTests", dependencies: ["MWHistory", "MWTestSupport"]),
        .testTarget(name: "MWProfilesTests", dependencies: ["MWProfiles", "MWTestSupport"]),
        .testTarget(name: "MWPasteTests", dependencies: ["MWPaste", "MWTestSupport"]),
        .testTarget(name: "MWOverlaySimTests", dependencies: ["MWOverlaySim", "MWTestSupport"]),
        .testTarget(name: "MWPipelineTests", dependencies: ["MWPipeline", "MWTestSupport"]),
        .testTarget(
            name: "MWMeetingsTests",
            dependencies: ["MWMeetings", "MWTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MWMeetingPipelineTests", dependencies: ["MWMeetingPipeline", "MWTestSupport"]),
        .testTarget(name: "MWAgentAccessTests", dependencies: ["MWAgentAccess", "MWTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
