#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the name entry sheet and the gym picker as root views, one capture per state, so the
  /// rebuilt entry and selection screens can be reviewed from images.
  ///
  /// Both are whole screens, so neither is a catalogue section. Each group's default state, the
  /// name sheet with its footnote and the picker with no saved gyms, is also captured in light and
  /// with Increase Contrast. Like the other render suites it is inert unless
  /// `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Name entry and gym picker render for review", .serialized)
  struct NameAndGymSnapshotTests {
    private static let width: CGFloat = 402
    private static let sheet = CGSize(width: width, height: 560)
    private static let tallSheet = CGSize(width: width, height: 760)
    private static let accessibilitySheet = CGSize(width: width, height: 1600)
    private static let phone = CGSize(width: width, height: 874)
    private static let tallPicker = CGSize(width: width, height: 1200)
    private static let accessibilityPicker = CGSize(width: width, height: 2800)

    private static let footnote = "Machines are recorded per gym, so this is what groups them."
    private static let failure = "“Iron Temple” could not be saved. Try again."
    private static let longFailure =
      "“Iron Temple Strength and Conditioning” could not be saved because the database is busy "
      + "or full. Nothing was lost; the name is still in the field. Try again."

    private static let twoGyms = [
      GymOption(id: GymID(), name: "Metroflex Gym"),
      GymOption(id: GymID(), name: "Equinox Hudson Yards"),
    ]

    private static let manyGyms = [
      "Metroflex Gym", "Equinox Hudson Yards", "Iron Temple Strength and Conditioning",
      "Planet Fitness Midtown", "Gold's Gym Venice", "Lifetime Athletic Brooklyn",
      "Crunch Fitness Union Square", "Chelsea Piers Fitness",
    ].map { GymOption(id: GymID(), name: $0) }

    // MARK: - Name entry

    private static func nameEntry(
      footnote: String? = NameAndGymSnapshotTests.footnote,
      errorMessage: String? = nil,
      initialName: String = ""
    ) -> some View {
      NameEntrySheet(
        title: "Add a gym",
        prompt: "Name",
        footnote: footnote,
        errorMessage: errorMessage,
        initialName: initialName,
        onConfirm: { _ in },
        onCancel: {}
      )
      // A real presentation applies hardsetSheet()'s plate-blue tint, so Cancel is plate blue.
      .tint(Tokens.Color.plateBlue)
      // Fills the window with the app canvas, so a sheet shorter than its window leaves no seam
      // of window background below its content.
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    /// The default state, with its footnote and an empty field, in every appearance.
    @Test func nameEntryDefaultInEveryAppearance() async throws {
      try await Snapshot.capture("kit-nameentry-footnote-dark", size: Self.sheet) {
        Self.nameEntry()
      }
      try await Snapshot.capture("kit-nameentry-footnote-light", size: Self.sheet, style: .light) {
        Self.nameEntry()
      }
      try await Snapshot.capture(
        "kit-nameentry-footnote-dark-contrast", size: Self.sheet, contrast: .high
      ) {
        Self.nameEntry()
      }
    }

    @Test func nameEntryStates() async throws {
      try await Snapshot.capture("kit-nameentry-nofootnote-dark", size: Self.sheet) {
        Self.nameEntry(footnote: nil)
      }
      try await Snapshot.capture("kit-nameentry-error-dark", size: Self.sheet) {
        Self.nameEntry(errorMessage: Self.failure, initialName: "Iron Temple")
      }
      try await Snapshot.capture("kit-nameentry-longerror-dark", size: Self.tallSheet) {
        Self.nameEntry(
          errorMessage: Self.longFailure, initialName: "Iron Temple Strength and Conditioning")
      }
      try await Snapshot.capture("kit-nameentry-typed-dark", size: Self.sheet) {
        Self.nameEntry(initialName: "Equinox Hudson Yards")
      }
      // Whitespace only: the confirm button stays disabled until there is a name to save.
      try await Snapshot.capture("kit-nameentry-disabled-dark", size: Self.sheet) {
        Self.nameEntry(initialName: "   ")
      }
    }

    @Test func nameEntryAccessibilitySize() async throws {
      try await Snapshot.capture(
        "kit-nameentry-error-dark-ax3", size: Self.accessibilitySheet,
        typeSize: .accessibility3
      ) {
        Self.nameEntry(errorMessage: Self.failure, initialName: "Iron Temple")
      }
    }

    // MARK: - Gym picker

    private static func picker(
      gyms: [GymOption],
      selected: GymID?,
      errorMessage: String? = nil,
      isLoading: Bool = false,
      onCancel: (() -> Void)? = nil
    ) -> some View {
      NavigationStack {
        GymPickerView(
          gyms: gyms,
          selected: selected,
          errorMessage: errorMessage,
          isLoading: isLoading,
          onSelect: { _ in },
          onAddGym: {},
          onCancel: onCancel
        )
        .hardsetNavigationTitle("Choose a gym")
      }
      // Fills the window with the app canvas, so a picker shorter than its window leaves no seam
      // of window background below its content. This helper sets no tint (the loading capture
      // adds its own), so the fill goes directly on the root.
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    /// The default state, no saved gyms, in every appearance.
    @Test func gymPickerDefaultInEveryAppearance() async throws {
      try await Snapshot.capture("kit-gym-none-dark", size: Self.phone) {
        Self.picker(gyms: [], selected: nil)
      }
      try await Snapshot.capture("kit-gym-none-light", size: Self.phone, style: .light) {
        Self.picker(gyms: [], selected: nil)
      }
      try await Snapshot.capture("kit-gym-none-dark-contrast", size: Self.phone, contrast: .high) {
        Self.picker(gyms: [], selected: nil)
      }
    }

    @Test func gymPickerStates() async throws {
      try await Snapshot.capture("kit-gym-many-dark", size: Self.tallPicker) {
        Self.picker(gyms: Self.manyGyms, selected: Self.manyGyms[2].id)
      }
      try await Snapshot.capture("kit-gym-one-dark", size: Self.phone) {
        Self.picker(gyms: Self.twoGyms, selected: Self.twoGyms[0].id)
      }
      // "Not recorded" selected beside saved gyms: a real choice, not an absence of one.
      try await Snapshot.capture("kit-gym-nil-dark", size: Self.phone) {
        Self.picker(gyms: Self.twoGyms, selected: nil)
      }
      // A selection the list does not hold, as after a failed read: nothing is marked selected.
      try await Snapshot.capture("kit-gym-unlisted-dark", size: Self.phone) {
        Self.picker(gyms: Self.twoGyms, selected: GymID())
      }
      try await Snapshot.capture("kit-gym-error-dark", size: Self.phone) {
        Self.picker(
          gyms: [], selected: nil,
          errorMessage: "The gym was saved, but its list could not be read.")
      }
      // The one gym capture with a toolbar button, so the one that wears the presentation's tint.
      try await Snapshot.capture("kit-gym-loading-dark", size: Self.phone) {
        Self.picker(gyms: [], selected: nil, isLoading: true, onCancel: {})
          .tint(Tokens.Color.plateBlue)
      }
    }

    @Test func gymPickerAccessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-gym-many-dark-ax3", size: Self.accessibilityPicker, typeSize: .accessibility3
      ) {
        Self.picker(gyms: Self.manyGyms, selected: Self.manyGyms[0].id)
      }
      // At accessibility sizes the uncapped banner is the first element of the scrolling content,
      // not pinned above the list (R41). A still render at scroll offset 0 shows the banner and
      // the intro text first and the list below the fold, so it cannot show the rows being
      // reachable: that is structural (the banner scrolls away with the content), and this
      // phone-height capture records how much of the screen the banner takes before scrolling.
      try await Snapshot.capture(
        "kit-gym-error-dark-ax3", size: Self.phone, typeSize: .accessibility3
      ) {
        Self.picker(
          gyms: Self.manyGyms, selected: Self.manyGyms[0].id,
          errorMessage: "The gym was saved, but its list could not be read.")
      }
    }
  }
#endif
