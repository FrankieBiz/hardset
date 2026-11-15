import SwiftUI

/// Every ledger, banner, loading and empty state of the component kit, for review from images:
/// two, three and four figures with and without units, a long value, each banner kind with and
/// without a title, a dismissible banner, a custom symbol and a long message, the loading line,
/// and the empty states with and without detail and action.
///
/// Static: no state, no I/O. A `ButtonStyle` cannot be forced pressed in a render, so the pressed
/// dismiss glyph is drawn through `HardsetPressFace`, the face the live glyph's style uses.
public struct MessagesCatalogView: View {
  public enum Section: String, CaseIterable, Sendable {
    case ledger, banners, loading, empty
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
    case .ledger: LedgerStates()
    case .banners: BannerStates()
    case .loading: LoadingStates()
    case .empty: EmptyStates()
    }
  }
}

// MARK: - Shared

/// A caption over a sample, so every state names itself in the render.
private struct Sample<Content: View>: View {
  private let note: String
  private let content: Content

  init(_ note: String, @ViewBuilder content: () -> Content) {
    self.note = note
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(note)
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      content
    }
  }
}

// MARK: - Ledger

private struct LedgerStates: View {
  var body: some View {
    CatalogSection("Ledger") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        Sample("Two figures, with units") {
          StatLedger([
            .init(label: "Volume", value: "4,820", unit: "kg"),
            .init(label: "Best set", value: "82.5", unit: "kg"),
          ])
        }
        Sample("Three figures, no units") {
          StatLedger([
            .init(label: "Sets", value: "12"),
            .init(label: "Reps", value: "96"),
            .init(label: "Movements", value: "4"),
          ])
        }
        Sample("Three figures, mixed units") {
          StatLedger([
            .init(label: "Sets", value: "12"),
            .init(label: "Reps", value: "96"),
            .init(label: "Volume", value: "4,820", unit: "kg"),
          ])
        }
        Sample("Four figures, with units") {
          StatLedger([
            .init(label: "Sets", value: "18"),
            .init(label: "Reps", value: "144"),
            .init(label: "Volume", value: "6,400", unit: "kg"),
            .init(label: "Time", value: "52", unit: "min"),
          ])
        }
        Sample("Four figures, no units") {
          StatLedger([
            .init(label: "Sets", value: "18"),
            .init(label: "Reps", value: "144"),
            .init(label: "Movements", value: "5"),
            .init(label: "Records", value: "2"),
          ])
        }
        Sample("A long value") {
          StatLedger([
            .init(label: "Volume", value: "12,345.67", unit: "lb"),
            .init(label: "Sets", value: "24"),
          ])
        }
      }
    }
  }
}

// MARK: - Banners

private struct BannerStates: View {
  private let longMessage =
    "This movement was last logged on a different machine, so the load is borrowed from that "
    + "machine and may not carry over. Check the first set against how it feels before you "
    + "trust the number, and log it on this machine to start its own history."

  var body: some View {
    CatalogSection("Banners") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        Sample("Message only, one of each kind") {
          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            HardsetBanner(.error, message: "The set could not be saved. Your workout is intact.")
            HardsetBanner(.caveat, message: "Load carried over from another machine.")
            HardsetBanner(.record, message: "Heaviest set on this machine so far.")
            HardsetBanner(.info, message: "Rest times are kept between workouts.")
          }
        }
        Sample("Title and message, one of each kind") {
          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            HardsetBanner(
              .error, title: "Not saved", message: "The set could not be saved. Try again.")
            HardsetBanner(
              .caveat, title: "Estimated", message: "Only one set on this machine so far.")
            HardsetBanner(.record, title: "Record", message: "Heaviest set on this machine.")
            HardsetBanner(.info, title: "Note", message: "Rest times are kept between workouts.")
          }
        }
        Sample("Dismissible") {
          HardsetBanner(
            .error, title: "Not saved", message: "The set could not be saved. Try again.",
            onDismiss: {})
        }
        Sample("Dismiss glyph, rest then pressed") {
          HStack(spacing: Tokens.Spacing.loose) {
            HardsetPressFace(isPressed: false, reduceMotion: false) {
              DismissGlyphButton(action: {})
            }
            HardsetPressFace(isPressed: true, reduceMotion: false) {
              DismissGlyphButton(action: {})
            }
          }
          .padding(.vertical, Tokens.Spacing.regular)
        }
        Sample("Custom symbol, built with a title") {
          HardsetBanner(
            .caveat, title: "Rest alerts are off",
            message: "Alarms are off for Hardset, so rest ends without an alert. The countdown "
              + "still runs here. Turn on Alarms for Hardset in Settings.",
            systemImage: "bell.slash")
        }
        Sample("Long message") {
          HardsetBanner(.caveat, title: "Borrowed load", message: longMessage, onDismiss: {})
        }
      }
    }
  }
}

// MARK: - Loading

private struct LoadingStates: View {
  var body: some View {
    CatalogSection("Loading") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        Sample("Short") {
          HardsetLoadingState("Loading history")
            .frame(height: 96)
        }
        Sample("Long, wrapping") {
          HardsetLoadingState(
            "Opening your workout history and checking which machines each movement was logged on"
          )
          .frame(height: 144)
        }
      }
    }
  }
}

// MARK: - Empty

private struct EmptyStates: View {
  var body: some View {
    CatalogSection("Empty") {
      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        Sample("Title only, no detail, no action") {
          HardsetEmptyState(title: "No workouts yet", systemImage: "clock")
        }
        Sample("With detail") {
          HardsetEmptyState(
            title: "No workout in progress",
            detail: "Start an empty workout and add movements as you go.",
            systemImage: "figure.strengthtraining.traditional")
        }
        Sample("With an action") {
          HardsetEmptyState(
            title: "No movements yet",
            detail: "Add the first movement to begin this workout.",
            systemImage: "dumbbell", actionTitle: "Add movement", action: {})
        }
        Sample("Retry") {
          HardsetEmptyState(
            title: "History could not be read",
            detail: "Nothing was changed. Try again.",
            systemImage: "exclamationmark.triangle", actionTitle: "Try again",
            actionSystemImage: "arrow.clockwise", action: {})
        }
        Sample("Filter escape") {
          HardsetEmptyState(
            title: "No movement matches",
            detail: "No movement matches the muscle group you chose.",
            systemImage: "magnifyingglass", actionTitle: "Show all movements",
            actionSystemImage: "line.3.horizontal.decrease", action: {})
        }
        Sample("A title without an action hides the button") {
          HardsetEmptyState(
            title: "Nothing to show",
            detail: "An action title with no action draws no button.",
            systemImage: "tray", actionTitle: "Add", action: nil)
        }
      }
    }
  }
}

#if DEBUG
  #Preview("Messages, all states") {
    MessagesCatalogView()
  }
#endif
