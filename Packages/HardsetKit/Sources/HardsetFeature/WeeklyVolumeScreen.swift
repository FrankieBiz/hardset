import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The sheets the Volume screen opens, one at a time. `nonisolated` so its computed `id` satisfies
/// `Identifiable` without isolated-conformance inference, as `ReceiptSelection` does.
private nonisolated enum VolumeSheet: Identifiable {
  /// Muscle history, the paid unlock built around time.
  case muscleHistory
  /// How sets are counted.
  case methodology
  /// The working behind one muscle's count.
  case working(WorkedFromPresentation)

  var id: String {
    switch self {
    case .muscleHistory: "muscle-history"
    case .methodology: "methodology"
    case .working(let presentation): "working-\(presentation.id.uuidString)"
    }
  }
}

/// Sets per muscle for the last seven days, wired.
///
/// Loads once per appearance rather than observing the database. The report is a snapshot of a
/// window, so a figure that changed while being read would be describing two different windows at
/// once — and there is no live-updating requirement here that would justify the complexity.
///
/// Draws its own header in every state, because the Volume tab hides the stock navigation bar.
///
/// The window is rolling, so it is named by its dates rather than called "this week", and it is
/// re-read whenever the app returns to the foreground: a window computed last night and shown this
/// morning would count a day too many under a heading that still says "last 7 days". The lifter
/// can step back a week at a time to compare.
@MainActor
public struct WeeklyVolumeScreen: View {
  @State private var snapshot = SnapshotLoader<VolumeWindow>()
  /// Muscle history's own read, loaded when the sheet opens and kept for that opening. It is a
  /// different snapshot because it covers all history, not the week the free screen is showing.
  @State private var historySnapshot = SnapshotLoader<MuscleHistoryReading>()
  /// The sheet that is up, or `nil`. One value for both, so the screen holds one presentation.
  @State private var presented: VolumeSheet?
  /// The working a lifter opened from inside muscle history. That sheet is itself a sheet, so this
  /// is presented over it, from its own stack, and closing it returns to muscle history.
  @State private var historyWorking: WorkedFromPresentation?
  /// How many whole weeks before now the window ends. Zero is the last seven days.
  @State private var weeksBack = 0
  /// Bumped when the app returns to the foreground, so the rolling window is recomputed from now.
  @State private var reloadToken = 0
  @Environment(\.scenePhase) private var scenePhase

  private let store: VolumeStore
  /// Reads all-history muscle figures for the paid sheet. Separate from `store` because it is a
  /// different window of time, not a different rule.
  private let historyStore: MuscleHistoryStore
  private let now: () -> Date
  /// Changes whenever data was written elsewhere, such as an import from Settings, so the window
  /// on screen is read again while its current figures stay visible.
  private let dataRevision: Int
  private let onShowSettings: (() -> Void)?
  /// Opens the Library, where a movement with no body part gets one.
  private let onShowLibrary: (() -> Void)?

  /// One entitlement app-wide, shared with Settings.
  private let lifetime = LifetimeAccess.shared

  private static let title = "Volume"
  /// How far back the window can step: a year of weeks.
  private static let maximumWeeksBack = 52

  public init(
    store: VolumeStore, historyStore: MuscleHistoryStore,
    now: @escaping () -> Date = { Date() }, dataRevision: Int = 0,
    onShowSettings: (() -> Void)? = nil, onShowLibrary: (() -> Void)? = nil
  ) {
    self.store = store
    self.historyStore = historyStore
    self.now = now
    self.dataRevision = dataRevision
    self.onShowSettings = onShowSettings
    self.onShowLibrary = onShowLibrary
  }

  public var body: some View {
    Group {
      if let window = snapshot.value {
        VolumeReportView(
          report: window.report,
          // Tokens the catalogue cannot train yet are content debt, not the user's coverage gap.
          excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
          title: Self.title,
          subtitle: window.description,
          onExplainCounting: { presented = .methodology },
          period: window.period,
          onShowSettings: onShowSettings,
          onEarlier: weeksBack < Self.maximumWeeksBack ? { weeksBack += 1 } : nil,
          onLater: weeksBack > 0 ? { weeksBack -= 1 } : nil,
          onShowLibrary: onShowLibrary,
          earlierLimitNote: "Volume keeps the last \(Self.maximumWeeksBack) weeks. Earlier weeks are not shown.",
          onShowWorking: { presented = .working(workingPresentation(for: $0, in: window)) },
          onShowTotalWorking: { presented = .working(totalWorkingPresentation(in: window)) }
        )
      } else if snapshot.loadFailed {
        // Says what is wrong and what is not. Logged sets are safe either way, and saying so is
        // the difference between an error and a scare. Scrollable so the pull-to-refresh the
        // message promises actually works.
        ScrollView {
          VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
            header(subtitle: "Sets per muscle")
            HardsetEmptyState(
              title: "Could not read these 7 days",
              detail: "Your logged sets are safe. Pull down to try again.",
              systemImage: "exclamationmark.triangle",
              style: .quiet
            )
          }
          .padding(.bottom, Tokens.Spacing.block)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.canvas)
      } else {
        // A sentence rather than a spinner: the read takes milliseconds, and a spinner would only
        // flash.
        VStack(alignment: .leading, spacing: 0) {
          header(subtitle: "Sets per muscle")
          HardsetLoadingState("Reading the last 7 days…")
        }
        .background(Tokens.Color.canvas)
      }
    }
    .safeAreaInset(edge: .bottom) {
      // Offered where there is history to show, or where the lifter already owns it and may be owed
      // the sheet's own empty state. A deload week has no working sets but still has a history, and
      // showing the offer over nothing would be a claim about an empty dataset (D24 §2.4). No extra
      // query: `hardSets` is in the report the screen already holds.
      if let window = snapshot.value,
        window.report.hardSets > 0 || (lifetime.hasLoaded && lifetime.isUnlocked)
      {
        // Pinned over the list, so a hairline says where the list ends and the control begins.
        // Words and a chevron with no face; the whole row is the control.
        VStack(spacing: 0) {
          Rectangle()
            .fill(Tokens.Color.hairline)
            .frame(height: Tokens.Stroke.hairline)
            .accessibilityHidden(true)
          Button {
            // A fresh opening reads the history again; a previous opening's figures are not left on
            // screen while the new read runs.
            historySnapshot = SnapshotLoader()
            presented = .muscleHistory
          } label: {
            HStack(spacing: Tokens.Spacing.snug) {
              Text(MuscleHistoryCopy.title)
                .frame(maxWidth: .infinity, alignment: .leading)
              Image(systemName: "chevron.right")
                .font(Tokens.Text.caption.weight(.semibold))
                .foregroundStyle(Tokens.Color.chalkDim)
                .accessibilityHidden(true)
            }
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.chalk)
          }
          .buttonStyle(
            InlineControlStyle(
              minHeight: Tokens.loggerTapTarget, alignment: .leading, fullWidth: true)
          )
          .padding(.horizontal, Tokens.Spacing.loose)
        }
        .background(Tokens.Color.canvas)
      }
    }
    .sheet(item: $presented) { sheet in
      switch sheet {
      case .muscleHistory: muscleHistorySheet
      case .methodology: methodologySheet
      case .working(let presentation):
        WorkedFromSheet(account: presentation.account)
          .hardsetSheet()
      }
    }
    // Keyed on the window, the foreground token and the data revision, so stepping, returning or
    // a write elsewhere re-reads, and a superseded read is cancelled. The loader keeps the
    // current figures on screen while it reads.
    .task(id: WindowKey(weeksBack: weeksBack, token: reloadToken, dataRevision: dataRevision)) {
      await load()
    }
    .refreshable { await load() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { reloadToken &+= 1 }
    }
  }

  private var muscleHistorySheet: some View {
    NavigationStack {
      ScrollView {
        switch lifetime.gate {
        case .checking:
          // Says it is checking rather than flashing the purchase offer before the entitlement is
          // known.
          HardsetLoadingState("Checking your purchase…")
        case .offer:
          // A free lifter sees what they would get, stated once, in the one offer this app has.
          // Never their own figures, blurred or truncated: a blurred number is still a claim about
          // their data (D24 §2.4).
          LifetimePurchaseSection(access: lifetime).padding(Tokens.Spacing.loose)
        case .content:
          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            // States why the sheet is open when it was not bought, such as a development build.
            LifetimeDevelopmentNote(access: lifetime).padding(.horizontal, Tokens.Spacing.loose)
            if let reading = historySnapshot.value {
              MuscleHistoryView(
                history: reading.history,
                onShowWorking: { muscle, figure in
                  historyWorking = historyWorkingPresentation(
                    for: muscle, figure: figure, in: reading)
                },
                onShowLibrary: onShowLibrary)
            } else if historySnapshot.loadFailed {
              VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
                HardsetEmptyState(
                  title: "Could not read your history",
                  detail: "Your logged sets are safe. Try again.",
                  systemImage: "exclamationmark.triangle",
                  style: .quiet
                )
                Button("Try again") { Task { await loadHistory() } }
                  .buttonStyle(HardsetButtonStyle(.secondary))
              }
              .padding(Tokens.Spacing.loose)
            } else {
              HardsetLoadingState("Reading your history…")
            }
          }
        }
      }
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle(MuscleHistoryCopy.title)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presented = nil } } }
      .task {
        await lifetime.load()
        if lifetime.gate == .content { await loadHistory() }
      }
      .sheet(item: $historyWorking) { presentation in
        WorkedFromSheet(account: presentation.account)
          .hardsetSheet()
      }
    }
    .hardsetSheet()
  }

  private var methodologySheet: some View {
    // Generated from the same value the counting uses, so the disclosure cannot drift from the
    // arithmetic, and the same sheet Settings opens, so the two cannot disagree.
    MethodologySheet.setCounting()
      .hardsetSheet()
  }

  /// The working behind a muscle's count in the window on screen, derived from the sets and
  /// attribution that window's report was counted from, by the rule the report counts with.
  private func workingPresentation(for muscle: Muscle, in window: VolumeWindow) -> WorkedFromPresentation {
    let working = MuscleCountWorking.derive(
      muscle: muscle, sets: window.reading.sets, attribution: window.reading.attribution,
      imported: window.reading.importedMovements, name: window.reading.name(for:))
    return WorkedFromPresentation(
      working.account(
        muscleName: ExercisePickerView.displayName(MuscleKey(muscle)),
        // A count holds no load, so the unit is never read; only the locale is.
        windowLabel: window.description, format: WorkedFromFormat(unit: .kilograms)))
  }

  /// The working behind the screen's monument, the week's count of working sets, derived from the
  /// sets that window's report was counted from, by the classification the report counts with.
  private func totalWorkingPresentation(in window: VolumeWindow) -> WorkedFromPresentation {
    let working = WorkingSetCountWorking.derive(
      sets: window.reading.sets, attribution: window.reading.attribution,
      imported: window.reading.importedMovements, name: window.reading.name(for:))
    return WorkedFromPresentation(
      working.account(windowLabel: window.description, format: WorkedFromFormat(unit: .kilograms)))
  }

  /// The working behind a muscle's four-week comparison or lifetime figure, derived from the same
  /// inputs and through the same `MuscleCountWorking` derivation the figure came from (D24 §3.6).
  private func historyWorkingPresentation(
    for muscle: Muscle, figure: MuscleHistoryFigure, in reading: MuscleHistoryReading
  ) -> WorkedFromPresentation {
    let account = reading.history.account(
      muscle: muscle, figure: figure,
      muscleName: ExercisePickerView.displayName(MuscleKey(muscle)),
      attribution: reading.attribution, imported: reading.importedMovements,
      name: reading.name(for:),
      // A count holds no load, so the unit is never read; only the locale and dates are.
      format: WorkedFromFormat(unit: .kilograms))
    return WorkedFromPresentation(account)
  }

  private func header(subtitle: String) -> some View {
    ScreenHeader(Self.title, subtitle: subtitle) {
      if let onShowSettings {
        HeaderIconButton(
          systemImage: "gearshape", accessibilityLabel: "Settings", style: .bare,
          action: onShowSettings)
      }
    }
  }

  private func load() async {
    let store = store
    // Whole local days, so the dates in the heading are exactly the days counted.
    let range = VolumeWindowRange(endingAt: now(), weeksBack: weeksBack)
    await snapshot.load {
      let reading = try await store.loadWindow(in: range)
      return VolumeWindow(reading: reading, range: range)
    }
  }

  /// Reads all-history figures once per opening of the sheet, as of the moment it was opened.
  private func loadHistory() async {
    let store = historyStore
    let openedAt = now()
    await historySnapshot.load {
      try await store.load(endingAt: openedAt)
    }
  }
}

/// One read: the report and the window it covers, kept together so the heading always names the
/// window whose numbers are on screen, even while the next one is being read.
private nonisolated struct VolumeWindow: Sendable {
  /// The report and the sets and attribution it was counted from, read together.
  let reading: VolumeWindowReading
  let range: VolumeWindowRange

  var report: MuscleVolumeReport { reading.report }

  /// "Last 7 days, 3 Nov to now", or "7 days, 27 Oct to 2 Nov" for an earlier window. Both name
  /// days counted in full, and adjacent windows never name the same day.
  var description: String {
    let day = Date.FormatStyle.dateTime.day().month(.abbreviated)
    let from = range.start.formatted(day)
    return range.weeksBack == 0
      ? "Last 7 days, \(from) to now"
      : "7 days, \(from) to \(range.lastDay.formatted(day))"
  }

  /// The phrase every sentence on the screen uses for this window.
  var period: String { range.weeksBack == 0 ? "in the last 7 days" : "in these 7 days" }
}

private nonisolated struct WindowKey: Hashable, Sendable {
  let weeksBack: Int
  let token: Int
  let dataRevision: Int
}
