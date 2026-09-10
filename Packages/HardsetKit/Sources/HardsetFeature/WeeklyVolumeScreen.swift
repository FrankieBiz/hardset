import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Sets per muscle for the last seven days, wired.
///
/// Loads once per appearance rather than observing the database. The report is a snapshot of a
/// window, so a figure that changed while being read would be describing two different windows at
/// once — and there is no live-updating requirement here that would justify the complexity.
@MainActor
public struct WeeklyVolumeScreen: View {
  @State private var report: MuscleVolumeReport?
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isShowingMethodology = false
  /// Captured once per visit. Every browsed window is relative to this instant, so pressing Back and
  /// then Forward returns to exactly the report the lifter just saw instead of a slightly later one.
  @State private var anchor: Date?
  @State private var weekOffset = 0
  /// The oldest set this screen could count, which is where browsing backwards stops.
  ///
  /// Read once per visit rather than per tap: it moves only when a set is logged, and a workout
  /// cannot be logged from this screen.
  @State private var earliestCountable: Date?

  private let store: VolumeStore
  private let now: () -> Date

  public init(store: VolumeStore, now: @escaping () -> Date = { Date() }) {
    self.store = store
    self.now = now
  }

  public var body: some View {
    // The navigator lives outside the state branches on purpose. Nested inside the loaded branch it
    // disappeared the moment a browsed window failed to read, and since a failed window is
    // re-requested identically forever, the forward chevron -- the only way back to this week -- went
    // with it.
    VStack(spacing: 0) {
      windowNavigator
      Group {
        if let report {
          VolumeReportView(
            report: report,
            // Tokens the catalogue cannot train yet are content debt, not the user's coverage gap.
            excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
            periodDescription: periodDescription,
            onExplainCounting: { isShowingMethodology = true }
          )
          // A report should redraw as one whole window. Keeping the old view identity left its bars
          // already revealed, so a historic report appeared to mutate rather than arrive.
          .id(window.endingAt)
        } else if loadFailed {
          // Says what is wrong and what is not. Logged sets are safe either way, and saying so is
          // the difference between an error and a scare.
          ContentUnavailableView {
            Label("Could not read this window", systemImage: "exclamationmark.triangle")
          } description: {
            Text("Your logged sets are safe. Pull down to try again.")
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.ground)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Color.ground)
        }
      }
    }
    .task { await load() }
    .refreshable { await refresh() }
    .sheet(isPresented: $isShowingMethodology) {
      // Generated from the same value the counting uses, so the disclosure cannot drift from the
      // arithmetic.
      MethodologySheet(source: SetCounting.source, certainty: .moderate)
    }
  }

  private func load() async {
    if anchor == nil { anchor = now() }
    isLoading = true
    let store = store
    let requestedWindow = window
    let needsEarliest = earliestCountable == nil
    let result = await readOffMain {
      // A failure here only costs the browsing floor, so it must not fail the report. Nil disables
      // paging farther back, which is the safe direction.
      let earliest = needsEarliest ? try? store.earliestCountableSet() : nil
      return (earliest, try store.report(in: requestedWindow))
    }
    guard !Task.isCancelled, requestedWindow == window else { return }
    switch result {
    case .success(let loaded):
      if let earliest = loaded.0 { earliestCountable = earliest }
      report = loaded.1
      loadFailed = false
    case .failure:
      report = nil
      loadFailed = true
    }
    isLoading = false
  }

  /// Pulling to refresh the current report advances its exclusive upper boundary. Browsed history
  /// keeps the captured anchor, so a refresh can pick up back-filled data without silently moving
  /// the seven-day window the lifter asked to inspect.
  private func refresh() async {
    if weekOffset == 0 { anchor = now() }
    await load()
  }

  private var window: SevenDayWindow {
    SevenDayWindow(endingAt: anchor ?? now()).shifted(byWeeks: weekOffset)
  }

  private var periodDescription: String {
    weekOffset == 0 ? "this week" : "in this seven-day window"
  }

  /// Whether an earlier window could contain anything.
  ///
  /// False when nothing is logged at all, so a fresh install cannot page backwards through empty
  /// weeks before it has any training to show.
  private var canShowEarlier: Bool {
    guard let earliestCountable else { return false }
    return earliestCountable < window.startingAt
  }

  private var windowNavigator: some View {
    HStack(spacing: Tokens.Spacing.regular) {
      navigatorChevron(
        "chevron.left",
        label: "Show the previous seven days",
        enabled: !isLoading && canShowEarlier
      ) { showWeek(offsetBy: -1) }

      VStack(spacing: Tokens.Spacing.hairline) {
        Text(weekOffset == 0 ? "This week" : "Earlier week")
          .font(Tokens.Text.label.weight(.semibold))
          .foregroundStyle(Tokens.Color.textPrimary)
        Text(Self.windowText(window))
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)

      navigatorChevron(
        "chevron.right",
        label: "Show the next seven days",
        enabled: !isLoading && weekOffset != 0
      ) { showWeek(offsetBy: 1) }
    }
    // `edge`, not `regular`: the chevrons have to sit on the same screen gutter as the report
    // content beneath them, or they read as inset by 8pt from a column they belong to.
    .padding(.horizontal, Tokens.Spacing.edge)
    .padding(.vertical, Tokens.Spacing.tight)
    .background(Tokens.Color.surface)
  }

  /// One arrow of the week navigator.
  ///
  /// Two things the inline version got wrong, both invisible in a screenshot and obvious under a
  /// thumb. The 44 pt frame was applied *outside* the `Button`, which pads the button rather than
  /// enlarging it -- the tappable area was the glyph, about thirteen points. And `.plain` opts out
  /// of the automatic dimming a disabled button normally gets, so at the ends of the range both
  /// arrows stayed at full brightness and simply stopped working: the shape this codebase calls a
  /// dead button. The frame now lives on the label, and being unavailable is visible.
  private func navigatorChevron(
    _ symbol: String,
    label: String,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .foregroundStyle(Tokens.Color.accent)
    .opacity(enabled ? 1 : 0.35)
    .accessibilityLabel(label)
  }

  private func showWeek(offsetBy change: Int) {
    guard !isLoading else { return }
    weekOffset += change
    // Never draw one week's bars under another week's date while the background read is running.
    report = nil
    Task { await load() }
  }

  /// Both bounds, because one date cannot describe a half-open interval honestly.
  ///
  /// "Seven days ending Aug 27" named an instant as if it were a day, so adjacent windows both
  /// claimed the same calendar date and nothing said which side a Thursday-evening session landed
  /// on. Printing the start as well makes the shared boundary visible instead of implied.
  static func windowText(_ window: SevenDayWindow) -> String {
    let start = window.startingAt.formatted(.dateTime.month(.abbreviated).day())
    let end = window.endingAt.formatted(.dateTime.month(.abbreviated).day().year())
    return "\(start) – \(end)"
  }
}
