import HardsetCore
import SwiftUI

/// Picks the month History opens on.
///
/// Every row is a month that holds workouts, newest first and grouped under its year, so a lifter
/// who trained until three years ago reaches that period in two taps and can never land on an empty
/// month. The month the list already starts at is marked as selected, by the ring and the filled
/// check of every selection row, not by colour alone.
///
/// The year is the group's heading and the month is the row, as the History list itself reads, so
/// VoiceOver moves by year with the headings rotor and hears "March, 14 workouts" on the row.
public struct HistoryMonthJumpSheet: View {
  /// What the sheet has to show. The months are read when it opens, so it can be waiting or failed.
  public enum Content {
    case loading
    case failed
    case months([HistoryMonth])
  }

  private let content: Content
  private let selected: Date?
  private let calendar: Calendar
  private let onSelect: (HistoryMonth) -> Void
  private let onCancel: () -> Void

  /// - Parameter selected: The start of the month the list is already on, if it starts at one.
  public init(
    content: Content,
    selected: Date? = nil,
    calendar: Calendar = .current,
    onSelect: @escaping (HistoryMonth) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.content = content
    self.selected = selected
    self.calendar = calendar
    self.onSelect = onSelect
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Tokens.Spacing.snug, pinnedViews: [.sectionHeaders]) {
          switch content {
          case .loading:
            Text(HistoryCopy.monthSheetLoading)
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.chalkDim)
              .padding(.horizontal, Tokens.Spacing.loose)
              .padding(.top, Tokens.Spacing.loose)
          case .failed:
            HardsetEmptyState(
              title: HistoryCopy.monthSheetFailedTitle, detail: HistoryCopy.monthSheetFailedDetail,
              systemImage: "exclamationmark.triangle"
            )
            .padding(.top, Tokens.Spacing.loose)
          case .months(let months):
            if months.isEmpty {
              HardsetEmptyState(
                title: HistoryCopy.monthSheetEmptyTitle, detail: HistoryCopy.monthSheetEmptyDetail,
                systemImage: "clock.arrow.circlepath"
              )
              .padding(.top, Tokens.Spacing.loose)
            } else {
              ForEach(HistoryMonth.years(months, calendar: calendar)) { group in
                Section {
                  ForEach(group.months) { month in
                    SelectionRow(
                      title: month.start.formatted(.dateTime.month(.wide)),
                      subtitle: HistoryCopy.workoutCount(month.workoutCount),
                      isSelected: month.start == selected
                    ) {
                      onSelect(month)
                    }
                    .padding(.horizontal, Tokens.Spacing.loose)
                  }
                } header: {
                  // Opaque, so rows scrolling under a pinned heading never show through it.
                  SectionLabel(String(group.year), count: group.workoutCount)
                    .padding(.horizontal, Tokens.Spacing.loose)
                    .padding(.top, Tokens.Spacing.loose)
                    .padding(.bottom, Tokens.Spacing.snug)
                    .background(Tokens.Color.canvas)
                }
              }
            }
          }
        }
        .padding(.bottom, Tokens.Spacing.section)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle(HistoryCopy.jumpToMonth)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

#if DEBUG
  private struct MonthJumpPreviewHarness: View {
    let content: HistoryMonthJumpSheet.Content
    var selected: Date?

    var body: some View {
      HistoryMonthJumpSheet(content: content, selected: selected, onSelect: { _ in }, onCancel: {})
    }

    static func month(_ year: Int, _ month: Int, _ count: Int) -> HistoryMonth {
      let calendar = Calendar.current
      let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
      let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
      return HistoryMonth(start: start, end: end, workoutCount: count)
    }
  }

  #Preview("Jump to a month") {
    MonthJumpPreviewHarness(
      content: .months([
        MonthJumpPreviewHarness.month(2024, 1, 3), MonthJumpPreviewHarness.month(2023, 12, 11),
        MonthJumpPreviewHarness.month(2023, 3, 14), MonthJumpPreviewHarness.month(2021, 2, 1),
      ]),
      selected: MonthJumpPreviewHarness.month(2023, 3, 14).start
    )
  }

  #Preview("Jump to a month, reading") {
    MonthJumpPreviewHarness(content: .loading)
  }
#endif
