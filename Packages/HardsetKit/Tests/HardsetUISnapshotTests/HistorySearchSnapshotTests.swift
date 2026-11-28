#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing

  /// Renders History's search and its month picker to PNG, so the two states a lifter cannot reach
  /// from a screenshot of the plain list can be looked at: matches under the field, the answer
  /// that says nothing matched, the list standing on a month, and the picker itself. Like the rest
  /// of the suite it asserts nothing about pixels and returns at once without `HARDSET_SNAPSHOT_DIR`.
  @Suite("History search and month jump render for review", .serialized)
  @MainActor
  struct HistorySearchSnapshotTests {
    private static func row(
      _ title: String, daysAgo: Double, names: [String], sets: Int = 8
    ) -> HistoryRow {
      HistoryRow(
        id: SessionID(), title: title,
        date: Fixtures.day.addingTimeInterval(-daysAgo * 86_400),
        duration: .seconds(3_600), exerciseNames: names,
        volume: SessionVolume(workingSets: sets, warmupSets: 1, volumeKg: 6_400, reps: sets * 8),
        hasImplausibleDuration: false)
    }

    private static let matches = [
      row("Push", daysAgo: 4, names: ["Barbell Bench Press", "Overhead Press"]),
      row("Upper", daysAgo: 38, names: ["Incline Bench Press", "Lat Pulldown"]),
      row("Push", daysAgo: 410, names: ["Barbell Bench Press", "Cable Triceps Pushdown"]),
    ]

    private static func list(
      rows: [HistoryRow], text: String, state: HistorySearch.State, subtitle: String? = nil,
      canJump: Bool = true, anchored: Bool = false
    ) -> some View {
      HistoryView(
        rows: rows, unit: .kilograms, title: "History", subtitle: subtitle,
        search: HistorySearch(
          text: .constant(text), state: state,
          onJumpToMonth: canJump ? {} : nil, onBackToLatest: anchored ? {} : nil),
        onSelect: { _ in })
    }

    /// Three matches, the subtitle naming the words, in both appearances and at an accessibility size.
    @Test func results() async throws {
      let subtitle = HistoryCopy.searchSubtitle(query: "bench", shown: 3, total: 3)
      try await Snapshot.capture("history-search-results-dark") {
        Self.list(rows: Self.matches, text: "bench", state: .answered("bench"), subtitle: subtitle,
                  canJump: false)
      }
      try await Snapshot.capture("history-search-results-light", style: .light) {
        Self.list(rows: Self.matches, text: "bench", state: .answered("bench"), subtitle: subtitle,
                  canJump: false)
      }
      try await Snapshot.capture("history-search-results-ax3", typeSize: .accessibility3) {
        Self.list(rows: Self.matches, text: "bench", state: .answered("bench"), subtitle: subtitle,
                  canJump: false)
      }
    }

    /// A search that found nothing names the words it searched; one still being read says so.
    @Test func noMatchAndSearching() async throws {
      try await Snapshot.capture("history-search-nomatch-dark") {
        Self.list(rows: [], text: "deadlift", state: .answered("deadlift"), canJump: false)
      }
      try await Snapshot.capture("history-search-nomatch-light-ax3", style: .light, typeSize: .accessibility3) {
        Self.list(rows: [], text: "deadlift", state: .answered("deadlift"), canJump: false)
      }
      try await Snapshot.capture("history-search-searching-dark") {
        Self.list(rows: [], text: "bench", state: .searching("bench"), canJump: false)
      }
      try await Snapshot.capture("history-search-failed-dark") {
        Self.list(rows: [], text: "bench", state: .failed("bench"), canJump: false)
      }
    }

    /// The idle list with the field and the calendar button, and the same list standing on a month,
    /// with its subtitle and the way back.
    @Test func idleAndAnchored() async throws {
      try await Snapshot.capture("history-search-idle-dark") {
        Self.list(rows: Self.matches, text: "", state: .idle)
      }
      // At an accessibility size the field says only "Search" and the scopes wrap on a line under it.
      try await Snapshot.capture("history-search-idle-dark-ax3", typeSize: .accessibility3) {
        Self.list(rows: Self.matches, text: "", state: .idle)
      }
      try await Snapshot.capture("history-search-idle-light", style: .light) {
        Self.list(rows: Self.matches, text: "", state: .idle)
      }
      let subtitle = HistoryCopy.anchoredSubtitle(month: "March 2023", shown: 3, total: 3)
      try await Snapshot.capture("history-anchored-dark") {
        Self.list(rows: Self.matches, text: "", state: .idle, subtitle: subtitle, anchored: true)
      }
      try await Snapshot.capture("history-anchored-light-ax3", style: .light, typeSize: .accessibility3) {
        Self.list(rows: Self.matches, text: "", state: .idle, subtitle: subtitle, anchored: true)
      }
    }

    private static func month(_ year: Int, _ month: Int, _ count: Int) -> HistoryMonth {
      let calendar = Calendar.current
      let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
      let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
      return HistoryMonth(start: start, end: end, workoutCount: count)
    }

    /// The picker with gaps in the years, the month the list stands on marked, and at an
    /// accessibility size; and waiting for its read.
    @Test func monthPicker() async throws {
      let months = [
        Self.month(2024, 1, 3), Self.month(2023, 12, 11), Self.month(2023, 3, 14),
        Self.month(2023, 2, 9), Self.month(2021, 6, 1),
      ]
      let selected = Self.month(2023, 3, 14).start
      try await Snapshot.capture("history-months-dark") {
        HistoryMonthJumpSheet(
          content: .months(months), selected: selected, onSelect: { _ in }, onCancel: {})
      }
      try await Snapshot.capture("history-months-light", style: .light) {
        HistoryMonthJumpSheet(
          content: .months(months), selected: selected, onSelect: { _ in }, onCancel: {})
      }
      try await Snapshot.capture("history-months-ax3", typeSize: .accessibility3) {
        HistoryMonthJumpSheet(
          content: .months(months), selected: selected, onSelect: { _ in }, onCancel: {})
      }
      try await Snapshot.capture("history-months-reading-dark") {
        HistoryMonthJumpSheet(content: .loading, onSelect: { _ in }, onCancel: {})
      }
    }
  }
#endif
