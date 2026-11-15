import SwiftUI

/// Every screen-chrome state of the component kit, for review from images: the screen header in its
/// layouts, the round header controls at rest and pressed, and the section label. Static: no state,
/// no I/O.
///
/// A `ButtonStyle` cannot be forced pressed in a render, so the pressed circle is the control's own
/// face, `HeaderIconGlyph`, drawn with `isPressed: true`. A `Menu` label receives no pressed state,
/// so the menu is shown at rest only; its press feel is a device check. `hardsetTabRoot` and
/// `hardsetNavigationTitle` have no section: the screen snapshots are their evidence.
public struct ScreenChromeCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case headers, icons, labels
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
    case .headers: ChromeHeaderStates()
    case .icons: ChromeIconStates()
    case .labels: ChromeLabelStates()
    }
  }
}

// MARK: - Headers

private struct ChromeHeaderStates: View {
  var body: some View {
    CatalogSection("Screen headers") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        sample("Title only") {
          ScreenHeader("Train")
        }
        sample("Title and subtitle") {
          ScreenHeader("Train", subtitle: "Saturday 7 November")
        }
        sample("Trailing icon button") {
          ScreenHeader("Train", subtitle: "Saturday 7 November") {
            HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
          }
        }
        sample("Trailing button and menu") {
          ScreenHeader("Train", subtitle: "Saturday 7 November") {
            HStack(spacing: Tokens.Spacing.snug) {
              HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
              HeaderIconMenu(accessibilityLabel: "Workout options") {
                Button("Finish workout") {}
              }
            }
          }
        }
        sample("Long title") {
          ScreenHeader("Lower body hypertrophy block", subtitle: "Week 3 of 6, Westside Barbell") {
            HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
          }
        }
      }
    }
  }

  private func sample<Content: View>(
    _ label: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(label)
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      content()
        // `ScreenHeader` pads its own page margin, which the catalogue already applies.
        .padding(.horizontal, -Tokens.Spacing.loose)
    }
  }
}

// MARK: - Icons

private struct ChromeIconStates: View {
  var body: some View {
    CatalogSection("Header icon buttons") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          note("Rest, then pressed. The circle sinks to steelPressed and never dims")
          HStack(spacing: Tokens.Spacing.regular) {
            HeaderIconGlyph(systemImage: "gearshape", isPressed: false)
            HeaderIconGlyph(systemImage: "gearshape", isPressed: true)
          }
        }
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          note("Menu glyph at rest. A menu label receives no pressed state")
          HStack(spacing: Tokens.Spacing.regular) {
            HeaderIconGlyph(systemImage: "ellipsis")
            HeaderIconMenu(accessibilityLabel: "Workout options") {
              Button("Finish workout") {}
            }
          }
        }
      }
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .hardsetText(.caption)
      .foregroundStyle(Tokens.Color.chalkDim)
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Labels

private struct ChromeLabelStates: View {
  var body: some View {
    CatalogSection("Section labels") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        sample("No count") {
          SectionLabel("Chest")
        }
        sample("Count") {
          SectionLabel("Chest", count: 6)
        }
        sample("Long title") {
          SectionLabel("Muscles counted but not modelled this week", count: 12)
        }
      }
    }
  }

  private func sample<Content: View>(
    _ label: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(label)
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      content()
    }
  }
}

#if DEBUG
  #Preview("Screen chrome, all states") {
    ScreenChromeCatalogView()
  }
#endif
