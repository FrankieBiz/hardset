// swift-tools-version: 6.2
// Tools version 6.2 is the floor: `.iOS("26.1")` and `.defaultIsolation(_:)` are both
// gated on PackageDescription 6.2 (verified empirically against Xcode 26.4).
import PackageDescription

// Every target ships Swift 6 language mode from commit 1. Retrofitting strict
// concurrency later is a rewrite, so it is never off.
let strictConcurrency: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  // The "approachable concurrency" bundle's load-bearing member: nonisolated async
  // functions inherit the caller's isolation instead of hopping to the global executor.
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

// UI and app-facing targets default to MainActor. HardsetCore deliberately does NOT:
// it stays nonisolated so the engine is callable from any context and testable off-device.
let mainActorByDefault: [SwiftSetting] = strictConcurrency + [
  .defaultIsolation(MainActor.self)
]

let package = Package(
  name: "HardsetKit",
  // macOS is listed so the HardsetCore and HardsetStore suites can run on the host with
  // `swift test`, no simulator involved. That is only possible because AlarmKit -- which
  // exists solely in the iPhoneOS SDK -- is isolated in HardsetAlarm behind
  // `#if canImport(AlarmKit)`. It is a test-execution affordance, not a shipping target.
  platforms: [.iOS("26.1"), .macOS("15.0")],
  products: [
    .library(name: "HardsetCore", targets: ["HardsetCore"]),
    .library(name: "HardsetAlarm", targets: ["HardsetAlarm"]),
    .library(name: "HardsetStore", targets: ["HardsetStore"]),
    .library(name: "HardsetUI", targets: ["HardsetUI"]),
    .library(name: "HardsetFeature", targets: ["HardsetFeature"]),
  ],
  dependencies: [
    // Locked decision. Brings GRDB 7.11+ transitively along with ~9 other
    // pointfreeco packages; see DECISIONS.md for the accepted cost.
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.9.0"),
    // Declared explicitly for `Row` and the pragma queries the schema tests need.
    // SQLiteData re-exports only a subset of GRDB, and this is already the locked
    // storage engine rather than a new dependency.
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
  ],
  targets: [
    // Foundation-only, nonisolated, no platform frameworks. Builds and tests on
    // macOS, which is what keeps the unit suite fast and device-independent.
    .target(name: "HardsetCore", swiftSettings: strictConcurrency),

    // iOS-only seam holding the AlarmKit conformance + scheduling wrapper.
    // Kept out of HardsetCore because AlarmKit ships only in the iPhoneOS SDK and is
    // unavailable on macCatalyst -- importing it into Core would make Core un-testable
    // on macOS. `AlarmMetadata` has no requirements beyond Codable/Hashable/Sendable,
    // so a retroactive empty conformance here costs nothing.
    .target(name: "HardsetAlarm", dependencies: ["HardsetCore"], swiftSettings: mainActorByDefault),

    .target(
      name: "HardsetStore",
      dependencies: [
        "HardsetCore",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ],
      swiftSettings: mainActorByDefault
    ),

    .target(
      name: "HardsetUI",
      dependencies: ["HardsetCore"],
      // No resources on purpose. The two dynamic colours these used to hold are now code (see
      // `Tokens.Color`), which removes an asset-catalogue build step that failed outright.
      swiftSettings: mainActorByDefault
    ),

    // The composition root, kept in the package rather than in the app target on purpose.
    // The .xcodeproj app target cannot be compiled from a sandboxed command line here (the
    // Swift macro plugin server fails), so anything living there is unverifiable. Putting the
    // wiring in a package target instead means it builds on the host and the app target shrinks
    // to a handful of lines. AlarmKit stays out: it is iOS-only, so the rest-timer hooks arrive
    // as closures supplied by the app.
    .target(
      name: "HardsetFeature",
      dependencies: [
        "HardsetCore", "HardsetStore", "HardsetUI",
        // Declared explicitly, not leaned on transitively: the composition root takes a
        // `DatabaseWriter`, so this target genuinely uses the type and should say so.
        .product(name: "SQLiteData", package: "sqlite-data"),
      ],
      swiftSettings: mainActorByDefault
    ),

    // Split deliberately: the engine suite has zero external dependencies, so it builds and
    // runs without resolving the SQLiteData graph or touching the network.
    .testTarget(
      name: "HardsetCoreTests",
      dependencies: ["HardsetCore"],
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "HardsetStoreTests",
      dependencies: [
        "HardsetStore", "HardsetCore",
        .product(name: "GRDB", package: "GRDB.swift"),
      ],
      swiftSettings: strictConcurrency
    ),
    // Added because view-layer logic kept needing coverage and had nowhere to go: the copy that
    // states a personal record had a bug that read as a regression, and the only way to catch it
    // was to walk the simulator. `HardsetUI` builds on the host, so its pure pieces -- number
    // formatting, the sentences it writes -- are testable here without a device.
    .testTarget(
      name: "HardsetUITests",
      dependencies: ["HardsetUI", "HardsetCore"],
      swiftSettings: mainActorByDefault
    ),
  ]
)
