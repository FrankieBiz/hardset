import SwiftUI

/// Every selection row, entry field and indicator state, for review from images. Static: no state,
/// no I/O.
///
/// A `ButtonStyle` cannot be forced pressed in a render, so the pressed and disabled card samples
/// are `SelectionCardFace`, the face `SelectionCardButtonStyle` draws, with the state passed in.
/// The focused field is the field's own chrome, `entryFieldChrome(isFocused: true)`, because focus
/// cannot be forced either.
public struct SelectionCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case rows, field, indicators
  }

  private let section: Section?

  public init(section: Section? = nil) {
    self.section = section
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        if let section {
          sectionView(section)
        } else {
          ForEach(Section.allCases, id: \.self) { sectionView($0) }
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.canvas.ignoresSafeArea())
  }

  @ViewBuilder
  private func sectionView(_ section: Section) -> some View {
    switch section {
    case .rows: RowStates()
    case .field: FieldStates()
    case .indicators: IndicatorStates()
    }
  }
}

// MARK: - Rows

private struct RowStates: View {
  var body: some View {
    CatalogSection("Selection rows") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        SelectionRow(title: "Unselected", action: {})
        SelectionRow(
          title: "Selected", subtitle: "moves in 5 kg steps", isSelected: true, action: {})
        SelectionRow(
          title: "Cybex Leg Press", subtitle: "moves in 5 kg steps", badge: "Recent", action: {})
        SelectionRow(
          title: "Metroflex Gym", leadingIcon: "mappin.and.ellipse", isSelected: true, action: {})
        SelectionRow(
          title: "Not recorded", subtitle: "History is kept for the movement, not a machine",
          leadingIcon: "slash.circle", action: {})
        SelectionRow(
          title: "The plate-loaded hack squat by the window, second from the end",
          badge: "Plate loaded", action: {})
        SelectionRow(title: "Disabled", subtitle: "dims to 40%", action: {})
          .disabled(true)
        SelectionCardFace(
          isSelected: false, isPressed: true, isEnabled: true, cornerRadius: Tokens.Radius.control
        ) {
          SelectionRowLabel(
            title: "Pressed", subtitle: "sinks to steelPressed", badge: nil, leadingIcon: nil,
            isSelected: false)
        }
      }
    }
  }
}

// MARK: - Field

private struct FieldStates: View {
  var body: some View {
    CatalogSection("Search field") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        HardsetSearchField(text: .constant(""))
        HardsetSearchField(text: .constant("Bench"))
        focusedSample
      }
    }
  }

  /// The field's chrome with its focus ring drawn, around the same icon and text the live field
  /// shows while focused.
  private var focusedSample: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Image(systemName: "magnifyingglass")
        .font(Tokens.Text.labelEmphasis)
        .foregroundStyle(Tokens.Color.plateBlue)
        .accessibilityHidden(true)
      Text("Focused, ring drawn")
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: Tokens.minimumTapTarget)
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.vertical, Tokens.Spacing.tight)
    .entryFieldChrome(isFocused: true)
  }
}

// MARK: - Indicators

private struct IndicatorStates: View {
  var body: some View {
    CatalogSection("Indicator and card") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        HStack(spacing: Tokens.Spacing.loose) {
          indicator("Off", isSelected: false)
          indicator("On", isSelected: true)
        }
        card("At rest", isSelected: false, isPressed: false, isEnabled: true)
        card("Pressed", isSelected: false, isPressed: true, isEnabled: true)
        card("Selected", isSelected: true, isPressed: false, isEnabled: true)
        card("Disabled", isSelected: false, isPressed: false, isEnabled: false)
      }
    }
  }

  private func indicator(_ title: String, isSelected: Bool) -> some View {
    HStack(spacing: Tokens.Spacing.snug) {
      SelectionIndicator(isSelected: isSelected)
      Text(title)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
    }
    .accessibilityElement(children: .combine)
  }

  private func card(
    _ title: String, isSelected: Bool, isPressed: Bool, isEnabled: Bool
  ) -> some View {
    SelectionCardFace(
      isSelected: isSelected, isPressed: isPressed, isEnabled: isEnabled,
      cornerRadius: Tokens.Radius.control
    ) {
      HStack(spacing: Tokens.Spacing.regular) {
        Text(title)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalk)
          .frame(maxWidth: .infinity, alignment: .leading)
        SelectionIndicator(isSelected: isSelected)
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }
}

#if DEBUG
  #Preview("Selection, all states") {
    SelectionCatalogView()
  }
#endif
