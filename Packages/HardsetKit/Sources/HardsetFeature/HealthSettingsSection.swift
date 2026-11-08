#if os(iOS)
import HardsetCore
import HardsetHealth
import HardsetStore
import HardsetUI
import SwiftUI

struct HealthSettingsSection: View {
  @State private var bridge: HealthBridge
  @State private var bodyMass = ""
  let unit: WeightUnit
  init(store: DeviceHealthStore, unit: WeightUnit) {
    _bridge = State(initialValue: HealthBridge(store: store))
    self.unit = unit
  }
  private var kilograms: Double? {
    Double(bodyMass.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")).map(unit.toKilograms)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Apple Health")
      Text("Optional. Read recent body mass and workout summaries on this device, or send completed strength workouts to Apple Health. Imported workouts never become machine history. Access can be changed in Apple Health at any time.")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
      Button("Connect Apple Health") { Task { await bridge.connect() } }
        .buttonStyle(HardsetButtonStyle(.secondary)).disabled(bridge.isWorking)
      if bridge.connected {
        Button("Read recent Health data") { Task { await bridge.readRecent() } }
          .buttonStyle(HardsetButtonStyle(.secondary)).disabled(bridge.isWorking)
        Button("Send completed workouts to Health") { Task { await bridge.writeWorkouts() } }
          .buttonStyle(HardsetButtonStyle(.secondary)).disabled(bridge.isWorking)
        TextField("Body mass (\(unit.abbreviation))", text: $bodyMass)
          .keyboardType(.decimalPad)
          .font(Tokens.Text.label).padding(Tokens.Spacing.regular)
          .frame(minHeight: Tokens.minimumTapTarget)
          .background(Tokens.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
          .accessibilityLabel("Body mass in \(unit.abbreviation)")
        Button("Save entered body mass to Health") {
          if let kilograms { Task { await bridge.writeBodyMass(kilograms: kilograms) } }
        }
        .buttonStyle(HardsetButtonStyle(.secondary))
        .disabled(bridge.isWorking || kilograms.map { !$0.isFinite || $0 <= 0 } != false)
      }
      if bridge.isWorking { ProgressView().accessibilityLabel("Working with Apple Health") }
      if let message = bridge.message {
        Text(message).font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
      }
      if bridge.lastError != nil {
        Text("Apple Health could not complete this request. Your workouts remain saved in Hardset. Check permissions in Apple Health and try again.")
          .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.error)
      }
    }
  }
}
#endif
