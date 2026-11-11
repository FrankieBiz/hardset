#if os(iOS)
import HardsetCore
import HardsetHealth
import HardsetStore
import HardsetUI
import SwiftUI
import UIKit

struct HealthSettingsSection: View {
  @State private var bridge: HealthBridge
  @State private var bodyMass = ""
  @FocusState private var bodyMassFocused: Bool
  @Environment(\.openURL) private var openURL
  let unit: WeightUnit
  init(store: DeviceHealthStore, unit: WeightUnit) {
    _bridge = State(initialValue: HealthBridge(store: store))
    self.unit = unit
  }
  private var kilograms: Double? {
    Double(bodyMass.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")).map(unit.toKilograms)
  }
  /// A typed value Hardset will send: finite and inside the plausible range, in kilograms.
  private var sendableKilograms: Double? {
    guard let kilograms, kilograms.isFinite, HealthBridge.plausibleBodyMassKilograms.contains(kilograms) else { return nil }
    return kilograms
  }
  /// Something was typed, and it is not a body mass Hardset will send.
  private var showsRangeHint: Bool {
    !bodyMass.trimmingCharacters(in: .whitespaces).isEmpty && sendableKilograms == nil
  }
  private var rangeText: String {
    let range = HealthBridge.plausibleBodyMassKilograms
    let lower = unit.fromKilograms(range.lowerBound).formatted(.number.precision(.fractionLength(0)))
    let upper = unit.fromKilograms(range.upperBound).formatted(.number.precision(.fractionLength(0)))
    return "Enter a body mass from \(lower) to \(upper) \(unit.abbreviation)."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Apple Health")
      Text("Optional. Send completed strength workouts and body mass to Apple Health, or copy recent body mass and workout summaries onto this iPhone. Imported workouts never become machine history. Access can be changed in Apple Health at any time.")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if let latest = bridge.latestBodyMass { latestBodyMass(latest) }
      if bridge.connected {
        Text("Apple Health access has been requested. What Hardset may read or write is up to you in the Health app.")
          .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("Copy recent Health data to this iPhone") { Task { await bridge.readRecent() } }
          .buttonStyle(HardsetButtonStyle(.secondary)).disabled(bridge.isWorking)
        Button("Send completed workouts to Health") { Task { await bridge.writeWorkouts() } }
          .buttonStyle(HardsetButtonStyle(.secondary)).disabled(bridge.isWorking)
        // A visible label that stays once typing starts, so the unit being entered is never in
        // doubt; the prompt is drawn in the measured secondary text colour, not the system's
        // unmeasured placeholder grey.
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text("Body mass (\(unit.abbreviation))")
            .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
            .accessibilityHidden(true)
          TextField(
            text: $bodyMass,
            prompt: Text("Body mass (\(unit.abbreviation))").foregroundStyle(Tokens.Color.textSecondary)
          ) {
            Text("Body mass")
          }
          .keyboardType(.decimalPad)
          .focused($bodyMassFocused)
          .font(Tokens.Text.label.monospacedDigit())
          .foregroundStyle(Tokens.Color.textPrimary)
          .tint(Tokens.Color.accent)
          .padding(Tokens.Spacing.regular)
          .frame(minHeight: Tokens.minimumTapTarget)
          .hardsetEntryField(isFocused: bodyMassFocused)
          .onTapGesture { bodyMassFocused = true }
          .accessibilityLabel("Body mass in \(unit == .kilograms ? "kilograms" : "pounds")")
          // The decimal pad has no return key, so the keyboard gets its own way to close.
          .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
              Spacer()
              Button("Done") { bodyMassFocused = false }
            }
          }
        }
        if showsRangeHint {
          Text(rangeText)
            .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.error)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button("Save entered body mass to Health") { save() }
          .buttonStyle(HardsetButtonStyle(.secondary))
          .disabled(bridge.isWorking || sendableKilograms == nil)
      } else {
        Button("Connect Apple Health") { Task { await bridge.connect() } }
          .buttonStyle(HardsetButtonStyle(.secondary)).disabled(bridge.isWorking)
      }
      if bridge.isWorking { ProgressView().accessibilityLabel("Working with Apple Health") }
      if let message = bridge.message {
        Text(message).font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if bridge.lastError != nil {
        Text("Apple Health could not complete this request. Your workouts remain saved in Hardset. Check Hardset's access in Settings or the Health app, then try again.")
          .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.error)
          .fixedSize(horizontal: false, vertical: true)
        if let settings = URL(string: UIApplication.openSettingsURLString) {
          Button("Open Settings") { openURL(settings) }
            .buttonStyle(HardsetButtonStyle(.quiet))
        }
      }
    }
    .task {
      await bridge.refreshConnection()
      await bridge.loadLatestBodyMass()
    }
    .onChange(of: unit) { bodyMass = "" }
  }

  /// Stated with its date and its source, in the unit the lifter reads.
  private func latestBodyMass(_ latest: DeviceHealthStore.BodyMass) -> some View {
    let value = unit.fromKilograms(latest.kilograms).formatted(.number.precision(.fractionLength(0...1)))
    return VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text("Latest body mass on this iPhone")
        .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
      Text("\(value) \(unit.abbreviation)")
        .font(Tokens.Text.figure.monospacedDigit()).foregroundStyle(Tokens.Color.textPrimary)
      Text("\(latest.measuredAt.formatted(date: .abbreviated, time: .omitted)) · Apple Health")
        .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard()
    .accessibilityElement(children: .combine)
  }

  private func save() {
    guard let kilograms = sendableKilograms else { return }
    Task {
      // Cleared only after Health accepted it, so a failed save keeps what was typed.
      if await bridge.writeBodyMass(kilograms: kilograms) {
        bodyMass = ""
        bodyMassFocused = false
      }
    }
  }
}
#endif
