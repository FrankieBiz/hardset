import Accessibility
import Foundation
import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI
import UniformTypeIdentifiers

/// File selection, preview and free sharing live outside the logger's rendering path.
///
/// Export and import each keep their own progress and message, drawn beside their own buttons,
/// so a result never lands under unrelated controls. Each result is also announced to VoiceOver.
struct DataPortabilitySection: View {
  let store: DataTransferStore
  let unit: WeightUnit
  /// Called after an import writes workouts, so screens showing history can re-read it.
  var onDataChanged: () -> Void = {}
  @State private var isChoosingFile = false
  @State private var isExporting = false
  @State private var isImporting = false
  @State private var preview: WorkoutImportPreview?
  /// How many of the previewed workouts were imported before and will be skipped; `nil` until read.
  @State private var alreadyImported: Int?
  /// Bumped whenever the preview is replaced or dropped, so a slower earlier read cannot land on top.
  @State private var previewGeneration = 0
  /// The unit on screen as last changed while this section was showing. Held in state because a
  /// running task sees the `unit` this view had when the task began, not the one shown now.
  @State private var liveUnit: WeightUnit?
  @State private var exportURL: URL?
  @State private var exportMessage: String?
  @State private var exportFailed = false
  @State private var importMessage: String?
  @State private var importFailed = false

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Your data")
      Text("Logging, personal history and exports are always free.")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.textSecondary)
      ForEach(DataTransferStore.Format.allCases, id: \.self) { format in
        Button("Export \(format.displayName)") { export(format) }
          .buttonStyle(HardsetButtonStyle(.secondary))
          .disabled(isExporting || isImporting)
      }
      if isExporting { ProgressView().accessibilityLabel("Preparing your export") }
      if let exportURL {
        ShareLink(item: exportURL) {
          Label("Save or share \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(HardsetButtonStyle())
      }
      if let exportMessage {
        Text(exportMessage)
          .font(Tokens.Text.provenance)
          .foregroundStyle(exportFailed ? Tokens.Color.error : Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text("CSV includes every logged set and its machine IDs. JSON and SQLite include all training and device-local tables, including Apple Health data you chose to copy. An export is a readable copy; Hardset can't restore from it. Share only where you intend.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      SectionLabel("Move your workouts")
      Text("Choose an English Strong or Hevy CSV. Unitless Strong loads are read as \(unit.abbreviation), the unit chosen above, and dates without an offset use this device’s time zone. Timed, distance and unweighted sets have no load and reps to record, so they are listed and left out. Workouts already imported from the same app are skipped.")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("Choose workout CSV") { isChoosingFile = true }
        .buttonStyle(HardsetButtonStyle(.secondary))
        .disabled(isImporting || isExporting)
      if let preview { previewCard(preview) }
      if isImporting { ProgressView().accessibilityLabel("Reading your workouts") }
      if let importMessage {
        Text(importMessage)
          .font(Tokens.Text.provenance)
          .foregroundStyle(importFailed ? Tokens.Color.error : Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
      switch result {
      case .success(let url):
        let selectedUnit = liveUnit ?? unit
        replacePreview(in: selectedUnit) { try await Self.readPreview(url, unit: selectedUnit) }
      case .failure(let error): reportImport(error)
      }
    }
    // The preview's loads were converted with the unit in force when it was read. Re-read the
    // retained text in the new unit, so what is committed always matches the unit on screen. A
    // read still running when Units changes is caught when it finishes, in `replacePreview`.
    .onChange(of: unit) { _, newUnit in
      liveUnit = newUnit
      guard let current = preview else { return }
      let text = current.originalCSV
      replacePreview(in: newUnit, unitChanged: true) { try await Self.reparse(text, unit: newUnit) }
    }
    .onChange(of: exportMessage) { _, message in announce(message) }
    .onChange(of: importMessage) { _, message in announce(message) }
  }

  // MARK: - Preview

  @ViewBuilder private func previewCard(_ preview: WorkoutImportPreview) -> some View {
    let skippedWorkouts = alreadyImported ?? 0
    let newWorkouts = preview.sessions.count - skippedWorkouts
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      Text("\(preview.sessions.count) workouts · \(preview.setCount) sets from \(preview.source)")
        .font(Tokens.Text.headline.monospacedDigit())
        .foregroundStyle(Tokens.Color.textPrimary)
      if let sample = preview.sessions.first?.sets.first {
        // One converted set, so the magnitude can be checked before anything is saved.
        Text("First set: \(sample.exercise) · \(Self.load(sample.weightKg, in: unit)) × \(sample.reps)")
          .font(Tokens.Text.provenance.monospacedDigit())
          .foregroundStyle(Tokens.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if skippedWorkouts > 0 {
        Text(skippedWorkouts == preview.sessions.count
          ? "Every workout in this file was already imported from \(preview.source). There is nothing new to import."
          : "\(skippedWorkouts) of these workouts were already imported from \(preview.source) and will be skipped.")
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !preview.skipped.isEmpty {
        Text(Self.skippedSummary(preview.skipped))
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(preview.interpretation).font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Text("Imported • Unevaluated Machine. Imported movements stay separate from your machine-specific history. Set times are unavailable and will be grouped at workout start. A fingerprint of the file is kept on this device so the same file is never imported twice.")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      CertaintyBadge(level: .unevaluated, methodology: "The CSV contains no physical machine identity. No machine or muscle attribution is inferred.")
      if newWorkouts > 0 {
        Button(skippedWorkouts == 0 ? "Import \(preview.setCount) sets" : "Import \(newWorkouts) new workouts") {
          commit(preview)
        }
        .buttonStyle(HardsetButtonStyle())
        .disabled(isImporting || alreadyImported == nil)
      }
      Button(newWorkouts > 0 ? "Cancel import" : "Close preview") { dropPreview() }
        .buttonStyle(HardsetButtonStyle(.quiet))
        .disabled(isImporting)
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard()
  }

  /// "9 rows not imported: 6 timed, distance or zero-rep sets, 3 sets with no recorded load.
  /// Rows 57, 88, …" -- by row number, so the lifter can find them in the original app.
  private static func skippedSummary(_ skipped: [WorkoutImportPreview.SkippedRow]) -> String {
    let noReps = skipped.filter { $0.reason == .noReps }.count
    let noLoad = skipped.count - noReps
    var kinds: [String] = []
    if noReps > 0 { kinds.append("\(noReps) timed, distance or zero-rep \(noReps == 1 ? "set" : "sets")") }
    if noLoad > 0 { kinds.append("\(noLoad) \(noLoad == 1 ? "set" : "sets") with no recorded load") }
    let shown = skipped.prefix(8).map { String($0.line) }.joined(separator: ", ")
    let more = skipped.count > 8 ? " and \(skipped.count - 8) more" : ""
    let rows = skipped.count == 1 ? "Row" : "Rows"
    return "\(skipped.count) \(skipped.count == 1 ? "row" : "rows") not imported: "
      + kinds.joined(separator: ", ") + ". \(rows) \(shown)\(more)."
  }

  private static func load(_ kilograms: Double, in unit: WeightUnit) -> String {
    let value = unit.fromKilograms(kilograms).formatted(.number.precision(.fractionLength(0...2)))
    return "\(value) \(unit.abbreviation)"
  }

  /// Replaces the preview with a freshly read one, then reads how much of it is already imported.
  ///
  /// - Parameters:
  ///   - readUnit: The unit `read` converts unitless loads with. If Units changes while the read
  ///     is running, the result is read again in the new unit before it is shown.
  ///   - unitChanged: Keep the current preview on screen while re-reading, and say why it changed.
  private func replacePreview(
    in readUnit: WeightUnit, unitChanged: Bool = false,
    _ read: @escaping @MainActor () async throws -> WorkoutImportPreview
  ) {
    previewGeneration += 1
    let generation = previewGeneration
    isImporting = true
    alreadyImported = nil
    importMessage = nil
    importFailed = false
    if !unitChanged { preview = nil }
    Task {
      defer { if generation == previewGeneration { isImporting = false } }
      do {
        let next = try await read()
        guard generation == previewGeneration else { return }
        if let liveUnit, liveUnit != readUnit {
          let text = next.originalCSV
          replacePreview(in: liveUnit, unitChanged: true) { try await Self.reparse(text, unit: liveUnit) }
          return
        }
        let duplicates = try await store.alreadyImportedWorkoutCount(in: next)
        guard generation == previewGeneration else { return }
        preview = next
        alreadyImported = duplicates
        if unitChanged {
          importMessage = "Units changed: unitless Strong loads are now read as \(readUnit.abbreviation)."
        }
      } catch {
        guard generation == previewGeneration else { return }
        preview = nil
        reportImport(error)
      }
    }
  }

  private func dropPreview() {
    previewGeneration += 1
    preview = nil
    alreadyImported = nil
  }

  @concurrent private static func readPreview(_ url: URL, unit: WeightUnit) async throws -> WorkoutImportPreview {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 20_000_000 else { throw DataFileError.tooLarge }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count <= 20_000_000, let text = String(data: data, encoding: .utf8) else {
      throw DataFileError.encoding
    }
    return try WorkoutCSVImport.preview(text, strongUnit: unit, skippingUnsupportedRows: true)
  }

  /// The same file text, read again in another unit. The file itself is not reopened: its
  /// security-scoped access ended when the picker's callback returned.
  @concurrent private static func reparse(_ text: String, unit: WeightUnit) async throws -> WorkoutImportPreview {
    try WorkoutCSVImport.preview(text, strongUnit: unit, skippingUnsupportedRows: true)
  }

  // MARK: - Export

  private func export(_ format: DataTransferStore.Format) {
    isExporting = true
    exportURL = nil
    exportMessage = nil
    Task {
      defer { isExporting = false }
      do {
        let url = try await store.export(format,
          directory: FileManager.default.temporaryDirectory.appendingPathComponent("HardsetExports"))
        exportURL = url
        exportFailed = false
        exportMessage = "\(url.lastPathComponent) is ready. Save or share it to keep a copy off this iPhone."
      } catch {
        exportFailed = true
        exportMessage = error.localizedDescription
      }
    }
  }

  // MARK: - Import

  private func commit(_ preview: WorkoutImportPreview) {
    isImporting = true
    importMessage = nil
    Task {
      defer { isImporting = false }
      do {
        let result = try await store.commit(preview)
        dropPreview()
        importFailed = false
        importMessage = Self.summary(result, preview: preview)
        if result.importedSets > 0 { onDataChanged() }
      } catch { reportImport(error) }
    }
  }

  private static func summary(_ result: WorkoutImportResult, preview: WorkoutImportPreview) -> String {
    guard result.importedSets > 0 else {
      return "Nothing new: all \(result.skippedWorkouts) workouts in this file were already imported from \(preview.source)."
    }
    var text = "Imported \(result.importedSets) sets in \(result.importedWorkouts) "
      + "\(result.importedWorkouts == 1 ? "workout" : "workouts") from \(preview.source). They're in History."
    if result.skippedWorkouts > 0 {
      text += " Skipped \(result.skippedWorkouts) already imported."
    }
    if !preview.skipped.isEmpty {
      text += " \(preview.skipped.count) timed, distance or unweighted rows were left out."
    }
    return text
  }

  private func reportImport(_ error: any Error) {
    importFailed = true
    importMessage = error.localizedDescription
  }

  private func announce(_ message: String?) {
    guard let message else { return }
    AccessibilityNotification.Announcement(message).post()
  }
}

private nonisolated enum DataFileError: LocalizedError {
  case tooLarge, encoding
  var errorDescription: String? {
    switch self {
    case .tooLarge: "Choose a CSV smaller than 20 MB."
    case .encoding: "Choose a UTF-8 CSV smaller than 20 MB."
    }
  }
}
