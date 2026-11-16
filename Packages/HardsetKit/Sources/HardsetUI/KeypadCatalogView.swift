import HardsetCore
import SwiftUI

/// The one keypad state that needs an internal seam, for review from images: the load-step
/// sheet after a rejected save. Its `failed` flag is private `@State`, so a render cannot reach
/// it through the public initialiser. Every other keypad and load-step state is rendered
/// directly as the snapshot's root view. Static: no timer, no I/O.
public struct KeypadCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case loadStep
  }

  private let section: Section?

  public init(section: Section? = nil) {
    self.section = section
  }

  /// Unlike the other catalogues this page does not scroll: the sheet is a whole screen with a
  /// scroll view of its own, and nesting it in another would leave it no height to lay out in.
  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      if let section {
        sectionView(section)
      } else {
        ForEach(Section.allCases, id: \.self) { sectionView($0) }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Tokens.Color.canvas.ignoresSafeArea())
  }

  @ViewBuilder
  private func sectionView(_ section: Section) -> some View {
    switch section {
    case .loadStep: LoadStepStates()
    }
  }
}

private struct LoadStepStates: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Load step, failed save")
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
      LoadStepSheet(
        machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .kilograms, showsFailure: true,
        onSave: { _ in false }, onCancel: {})
    }
  }
}

#if DEBUG
  #Preview("Keypad, load-step failed save") {
    KeypadCatalogView()
  }
#endif
