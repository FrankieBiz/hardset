#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the movement library and the movement editor for review from images. Like the other
  /// render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about
  /// pixels: what it protects is that every state draws at all, for a person to read.
  @MainActor
  @Suite("Library and movement editor render for review", .serialized)
  struct LibrarySnapshotTests {
    private static let phone = CGSize(width: 402, height: 874)
    private static let accessibility = CGSize(width: 402, height: 1800)

    private static func custom(
      _ name: String, modality: ExerciseModality?, primary: Muscle?, secondary: [Muscle] = []
    ) -> CatalogEntry {
      var contributions: [MuscleContribution] = []
      if let primary {
        contributions.append(.init(primary, role: .direct, certainty: .moderate, source: .user))
      }
      contributions += secondary.map {
        .init($0, role: .indirect, certainty: .moderate, source: .user)
      }
      return CatalogEntry(
        id: ExerciseID(), name: name, slug: nil, isCurated: false, modality: modality,
        primaryMuscle: primary.map(MuscleKey.init) ?? MuscleKey(stored: MuscleKey.notAttributedRawValue),
        contributions: contributions)
    }

    private static var curated: [CatalogEntry] { ExerciseCatalog.v1.compactMap(\.catalogEntry) }

    /// A few shipped movements, two of the lifter's own tagged, and two still waiting for a body part.
    private static var mixed: [CatalogEntry] {
      Array(curated.prefix(6)) + [
        custom("Nautilus lever row", modality: .machine, primary: .lats, secondary: [.biceps]),
        custom("Cable fly variation", modality: .cable, primary: .chest),
        custom("Pendulum squat", modality: nil, primary: nil),
        custom("Zercher carry", modality: .barbell, primary: nil),
      ]
    }

    private static func library(_ entries: [CatalogEntry]) -> some View {
      NavigationStack {
        LibraryView(
          sections: LibraryIndex.sections(entries), counts: LibraryIndex.counts(entries),
          onSelect: { _ in }
        )
        .hardsetNavigationTitle("Library")
      }
      .tint(Tokens.Color.plateBlue)
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    private static func editor(_ draft: MovementEditorDraft) -> some View {
      MovementEditorSheet(
        title: "New movement", confirmLabel: "Add to workout", draft: draft, onSave: { _, _ in },
        onCancel: {}
      )
      .hardsetSheet()
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    /// The movement the editor was opened to retag: back, lats, biceps as a secondary.
    private static var tagged: MovementEditorDraft {
      var draft = MovementEditorDraft(name: "Nautilus lever row", modality: .machine)
      draft.choose(bodyPart: .back)
      draft.choose(primary: .lats)
      draft.toggleSecondary(.biceps)
      return draft
    }

    /// Untagged movements first under their warning header, then three body parts, then the footer
    /// ledger counting every part, zeros included.
    @Test func libraryWithUntaggedAndThreeBodyParts() async throws {
      try await Snapshot.capture("kit-library-mixed-dark", size: Self.accessibility) {
        Self.library(Self.mixed)
      }
      try await Snapshot.capture("kit-library-mixed-light", size: Self.accessibility, style: .light) {
        Self.library(Self.mixed)
      }
    }

    @Test func libraryOnlyUntaggedAndEmpty() async throws {
      try await Snapshot.capture("kit-library-untagged-dark", size: Self.phone) {
        Self.library([
          Self.custom("Pendulum squat", modality: nil, primary: nil),
          Self.custom("Zercher carry", modality: .barbell, primary: nil),
        ])
      }
      try await Snapshot.capture("kit-library-empty-dark", size: Self.phone) { Self.library([]) }
    }

    @Test func libraryAtAccessibilitySize() async throws {
      try await Snapshot.capture(
        "kit-library-mixed-dark-ax3", size: Self.accessibility, typeSize: .accessibility3
      ) { Self.library(Self.mixed) }
    }

    /// A new movement with only a name, a movement with a body part and no muscle yet, and a fully
    /// tagged one: Save is disabled in the first two and says what is missing.
    @Test func editorStates() async throws {
      try await Snapshot.capture("kit-movementeditor-new-dark", size: Self.accessibility) {
        Self.editor(MovementEditorDraft(name: "Nautilus lever row"))
      }
      try await Snapshot.capture("kit-movementeditor-new-light", size: Self.accessibility, style: .light) {
        Self.editor(MovementEditorDraft(name: "Nautilus lever row"))
      }
      try await Snapshot.capture("kit-movementeditor-needs-muscle-dark", size: Self.accessibility) {
        var draft = MovementEditorDraft(name: "Lever row")
        draft.choose(bodyPart: .back)
        return Self.editor(draft)
      }
      try await Snapshot.capture("kit-movementeditor-tagged-dark", size: Self.accessibility) {
        Self.editor(Self.tagged)
      }
    }

    @Test func editorAtAccessibilitySize() async throws {
      try await Snapshot.capture(
        "kit-movementeditor-tagged-dark-ax3", size: CGSize(width: 402, height: 2600),
        typeSize: .accessibility3
      ) { Self.editor(Self.tagged) }
    }
  }
#endif
