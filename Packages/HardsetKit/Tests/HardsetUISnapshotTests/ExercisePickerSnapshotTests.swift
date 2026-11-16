#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the exercise picker for review from images. The picker is a whole screen, so each
  /// state is the snapshot's root view: every state once in dark, plus the default state, browse,
  /// in light and Increase Contrast. The two filtered states are rendered through
  /// `initialCategory`, because the region filter is private state. Like the other render suites it
  /// is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Exercise picker renders for review", .serialized)
  struct ExercisePickerSnapshotTests {
    private static let phone = CGSize(width: 402, height: 874)
    /// Phone height plus 160 pt for the browse and recents-first lists, which run past any window:
    /// at phone height their captures ended mid-row, and this height is meant to show the last row
    /// in view and its provenance line whole.
    private static let longList = CGSize(width: 402, height: 1034)
    private static let accessibility = CGSize(width: 402, height: 1800)

    private static let curated = ExerciseCatalog.v1.compactMap(\.catalogEntry)

    private static var chestOnly: [CatalogEntry] {
      curated.filter { MuscleFilterCategory.chest.matches($0.primaryMuscle) }
    }

    /// Two shipped movements and two of the lifter's own, one with a modality and one without.
    private static var withCustom: [CatalogEntry] {
      Array(chestOnly.prefix(2)) + [
        custom("Cable Fly Variation", modality: .cable, primary: .chest),
        custom("Zercher Carry", modality: nil, primary: .forearms),
      ]
    }

    /// Two shipped movements, one row with no attribution and one with a token this build does
    /// not know, so both honest section names render.
    private static var withUnknownMuscles: [CatalogEntry] {
      Array(chestOnly.prefix(2)) + [
        CatalogEntry(
          id: ExerciseID(), name: "Sled Drag", slug: nil, isCurated: false, modality: nil,
          primaryMuscle: MuscleKey(stored: MuscleKey.notAttributedRawValue), contributions: []
        ),
        CatalogEntry(
          id: ExerciseID(), name: "Neck Harness Raise", slug: nil, isCurated: false, modality: nil,
          primaryMuscle: MuscleKey(stored: "muscle-from-a-newer-version"), contributions: []
        ),
      ]
    }

    private static func custom(
      _ name: String, modality: ExerciseModality?, primary: Muscle
    ) -> CatalogEntry {
      CatalogEntry(
        id: ExerciseID(), name: name, slug: nil, isCurated: false, modality: modality,
        primaryMuscle: MuscleKey(primary),
        contributions: [
          MuscleContribution(primary, role: .direct, certainty: .low, source: .user)
        ]
      )
    }

    /// The caller's search results for `query`, as the live session's database read would give.
    private static func matches(_ entries: [CatalogEntry], for query: String) -> [CatalogEntry] {
      guard !query.isEmpty else { return entries }
      return entries.filter {
        $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }

    private static func picker(
      entries: [CatalogEntry]? = nil,
      query: String = "",
      recent: [CatalogEntry] = [],
      errorMessage: String? = nil,
      allowsCreate: Bool = true,
      category: MuscleFilterCategory? = nil
    ) -> some View {
      NavigationStack {
        ExercisePickerView(
          query: .constant(query),
          entries: matches(entries ?? curated, for: query),
          recent: recent,
          errorMessage: errorMessage,
          onCancel: {},
          onCreate: allowsCreate ? { (_: String) in } : nil,
          initialCategory: category
        ) { _ in }
        .hardsetNavigationTitle("Add movement")
      }
      // A real presentation applies hardsetSheet()'s plate-blue tint, so Cancel is plate blue.
      .tint(Tokens.Color.plateBlue)
      // Fills the window with the app canvas, so a picker shorter than its window leaves no seam
      // of window background below its content.
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    /// The default state, browse, in every appearance.
    @Test func browseInEveryAppearance() async throws {
      let name = "kit-exercisepicker-browse"
      try await Snapshot.capture("\(name)-dark", size: Self.longList) { Self.picker() }
      try await Snapshot.capture("\(name)-light", size: Self.longList, style: .light) {
        Self.picker()
      }
      try await Snapshot.capture("\(name)-dark-contrast", size: Self.longList, contrast: .high) {
        Self.picker()
      }
    }

    @Test func recentsFirstAndPartialQuery() async throws {
      try await Snapshot.capture("kit-exercisepicker-recents-first-dark", size: Self.longList) {
        Self.picker(recent: Array(Self.curated.prefix(3)))
      }
      try await Snapshot.capture("kit-exercisepicker-partial-query-dark", size: Self.phone) {
        Self.picker(query: "bench")
      }
    }

    @Test func noMatch() async throws {
      try await Snapshot.capture("kit-exercisepicker-no-match-create-dark", size: Self.phone) {
        Self.picker(query: "Zercher carry")
      }
      try await Snapshot.capture("kit-exercisepicker-no-match-no-create-dark", size: Self.phone) {
        Self.picker(query: "Zercher carry", allowsCreate: false)
      }
    }

    /// Both states are seeded through `initialCategory`. Chest lists only chest movements; Calves
    /// over a chest-only list hides every match, which offers "Show all regions".
    @Test func regionFilter() async throws {
      try await Snapshot.capture("kit-exercisepicker-region-filter-dark", size: Self.phone) {
        Self.picker(category: .chest)
      }
      try await Snapshot.capture("kit-exercisepicker-hidden-by-filter-dark", size: Self.phone) {
        Self.picker(entries: Self.chestOnly, query: "press", category: .calves)
      }
    }

    @Test func loadingAndReadFailed() async throws {
      try await Snapshot.capture("kit-exercisepicker-loading-dark", size: Self.phone) {
        Self.picker(entries: [])
      }
      try await Snapshot.capture("kit-exercisepicker-read-failed-dark", size: Self.phone) {
        Self.picker(
          entries: [], errorMessage: "Your movements could not be read. Close this and try again."
        )
      }
    }

    @Test func customTagsAndUnknownMuscles() async throws {
      try await Snapshot.capture("kit-exercisepicker-custom-tags-dark", size: Self.phone) {
        Self.picker(entries: Self.withCustom)
      }
      try await Snapshot.capture("kit-exercisepicker-unattributed-dark", size: Self.phone) {
        Self.picker(entries: Self.withUnknownMuscles)
      }
    }

    /// At accessibility sizes the tags stack under the movement name.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-exercisepicker-stacked-tags-dark-ax3", size: Self.accessibility,
        typeSize: .accessibility3
      ) { Self.picker(entries: Self.withCustom) }
      // At accessibility sizes the uncapped banner is inside the scrolling content, not pinned
      // under the search field and the rail. This phone-height capture checks that, with the
      // banner there, the first two list rows are visible, so it can fail. The read-failure
      // message sits over the browse list, as in the machine and gym pickers' captures, because
      // with no rows there would be nothing for the check to find.
      try await Snapshot.capture(
        "kit-exercisepicker-error-dark-ax3", size: Self.phone, typeSize: .accessibility3
      ) {
        Self.picker(
          errorMessage: "Your movements could not be read. Close this and try again."
        )
      }
    }
  }
#endif
