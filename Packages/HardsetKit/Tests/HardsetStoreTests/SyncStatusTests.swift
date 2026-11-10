import Testing

@testable import HardsetStore

/// The startup decision that keeps a build without iCloud from refusing to open.
///
/// A personal development team cannot sign the iCloud entitlement. Before local-only mode, such a
/// device build failed `prepareForLaunch` on every attempt and showed only "Could not open
/// Hardset". These pin which launches sync and which open local-only.
@Suite("Sync status chooses local-only when no container exists")
struct SyncStatusTests {
  @Test("No explicit and no entitled container opens local-only")
  func noContainerIsLocalOnly() {
    #expect(SyncStatus.container(explicit: nil, entitled: nil) == nil)
  }

  @Test("A blank container counts as none rather than reaching the engine")
  func blankContainerIsLocalOnly() {
    #expect(SyncStatus.container(explicit: "", entitled: nil) == nil)
    #expect(SyncStatus.container(explicit: nil, entitled: "  ") == nil)
    #expect(SyncStatus.container(explicit: " ", entitled: "\n") == nil)
  }

  @Test("The entitled container is used when none is passed")
  func entitledContainerIsUsed() {
    #expect(
      SyncStatus.container(explicit: nil, entitled: "iCloud.com.example.hardset")
        == "iCloud.com.example.hardset"
    )
    #expect(
      SyncStatus.container(explicit: "", entitled: "iCloud.com.example.hardset")
        == "iCloud.com.example.hardset"
    )
  }

  @Test("An explicit container wins over the entitlement")
  func explicitContainerWins() {
    #expect(
      SyncStatus.container(explicit: "iCloud.tests.suite", entitled: "iCloud.com.example.hardset")
        == "iCloud.tests.suite"
    )
  }

  @Test("Only an enabled status claims to sync")
  func onlyEnabledSyncs() {
    #expect(SyncStatus.enabled(containerIdentifier: "iCloud.com.example.hardset").isSyncing)
    #expect(!SyncStatus.localOnly.isSyncing)
  }
}
