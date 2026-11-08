import Foundation
import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI
import UniformTypeIdentifiers

/// File selection, preview and free sharing live outside the logger's rendering path.
struct DataPortabilitySection: View {
  let store: DataTransferStore
  let unit: WeightUnit
  @State private var isChoosingFile = false
  @State private var isWorking = false
  @State private var preview: WorkoutImportPreview?
  @State private var exportURL: URL?
  @State private var message: String?
  @State private var failed = false

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Your data")
      Text("Logging, personal history and exports are always free.")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.textSecondary)
      ForEach(DataTransferStore.Format.allCases, id: \.self) { format in
        Button("Export \(format.rawValue.uppercased())") { export(format) }
          .buttonStyle(HardsetButtonStyle(.secondary))
          .disabled(isWorking)
      }
      if let exportURL {
        ShareLink(item: exportURL) { Label("Save or share export", systemImage: "square.and.arrow.up") }
          .buttonStyle(HardsetButtonStyle())
      }
      Text("CSV includes every logged set and its machine IDs. JSON and SQLite include all training and device-local tables, including Apple Health data you chose to read. Share only where you intend.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
      SectionLabel("Move your workouts")
      Text("Choose an English Strong or Hevy CSV. Unitless Strong loads will be read as \(unit.abbreviation), using this device’s time zone for dates without an offset. Change Units above before importing if needed. Timed or distance-only sets require an explicit load and reps and will be rejected.")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.textSecondary)
      Button("Choose workout CSV") { isChoosingFile = true }
        .buttonStyle(HardsetButtonStyle(.secondary))
        .disabled(isWorking)
      if let preview {
        Text("\(preview.sessions.count) workouts · \(preview.setCount) sets from \(preview.source)")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.textPrimary)
        Text("Imported • Unevaluated Machine. Imported movements stay separate from your machine-specific history. Set times are unavailable and will be grouped at workout start. The original file is retained locally for duplicate detection and export.")
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.textSecondary)
        CertaintyBadge(level: .unevaluated, methodology: "The CSV contains no physical machine identity. No machine or muscle attribution is inferred.")
        Button("Import \(preview.setCount) sets") { commit(preview) }
          .buttonStyle(HardsetButtonStyle())
          .disabled(isWorking)
        Button("Cancel import") { self.preview = nil }
          .buttonStyle(HardsetButtonStyle(.quiet))
          .disabled(isWorking)
      }
      if isWorking { ProgressView().accessibilityLabel("Working with your data") }
      if let message {
        Text(message)
          .font(Tokens.Text.provenance)
          .foregroundStyle(failed ? Tokens.Color.error : Tokens.Color.textSecondary)
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
    .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
      switch result {
      case .success(let url):
        isWorking = true
        preview = nil
        message = nil
        let selectedUnit = unit
        Task {
          defer { isWorking = false }
          do { preview = try await Self.readPreview(url, unit: selectedUnit) }
          catch { report(error) }
        }
      case .failure(let error): report(error)
      }
    }
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
    return try WorkoutCSVImport.preview(text, strongUnit: unit)
  }

  private func export(_ format: DataTransferStore.Format) {
    isWorking = true
    exportURL = nil
    message = nil
    Task {
      defer { isWorking = false }
      do {
        exportURL = try await store.export(format,
          directory: FileManager.default.temporaryDirectory.appendingPathComponent("HardsetExports"))
        failed = false
        message = "Your export is ready. Use Save or share export to choose its destination."
      } catch { report(error) }
    }
  }

  private func commit(_ preview: WorkoutImportPreview) {
    isWorking = true
    message = nil
    Task {
      defer { isWorking = false }
      do {
        let count = try await store.importWorkouts(preview)
        self.preview = nil
        failed = false
        message = "Imported \(count) sets. Pull down in History to refresh."
      } catch { report(error) }
    }
  }

  private func report(_ error: any Error) {
    failed = true
    message = error.localizedDescription
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
