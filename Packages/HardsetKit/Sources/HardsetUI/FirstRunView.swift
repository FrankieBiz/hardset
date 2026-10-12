import HardsetCore
import SwiftUI

/// The one screen a new lifter sees (spec 3.5): three promises, the unit, an optional gym, the
/// privacy line, and Start. It asks for nothing else: no goal, no target, no program, no
/// questionnaire. Draws only; the unit, the gym name, the failure and Start are the root's.
public struct FirstRunView: View {
  @Binding private var useImperial: Bool
  private let inferredUnit: WeightUnit
  @Binding private var gymName: String
  private let errorMessage: String?
  private let onStart: () -> Void

  public init(
    useImperial: Binding<Bool>,
    inferredUnit: WeightUnit,
    gymName: Binding<String>,
    errorMessage: String?,
    onStart: @escaping () -> Void
  ) {
    self._useImperial = useImperial
    self.inferredUnit = inferredUnit
    self._gymName = gymName
    self.errorMessage = errorMessage
    self.onStart = onStart
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
          ForEach(FirstRunCopy.promises) { promise in
            promiseRow(promise)
          }
        }
        unitSection
        gymSection
        Label {
          Text(FirstRunCopy.privacy)
        } icon: {
          Image(systemName: "lock")
        }
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        if let errorMessage {
          Label {
            Text(errorMessage)
          } icon: {
            Image(systemName: "exclamationmark.circle")
          }
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.critical)
        }
        startButton
      }
      .frame(maxWidth: 520, alignment: .leading)
      .padding(.horizontal, Tokens.Spacing.section)
      .padding(.vertical, Tokens.Spacing.section)
      .frame(maxWidth: .infinity)
    }
    .background(Tokens.Color.background)
  }

  private func promiseRow(_ promise: FirstRunPromise) -> some View {
    HStack(alignment: .top, spacing: Tokens.Spacing.regular) {
      Image(systemName: promise.symbolName)
        .font(.title2)
        .foregroundStyle(Tokens.Color.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(promise.title)
          .font(Tokens.Text.label.weight(.semibold))
        Text(promise.detail)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// The chip is shown only while the unit still is the guess; once the lifter changes it, it is
  /// a choice and the claim "from your region" would be untrue.
  private var unitSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      if useImperial == (inferredUnit == .pounds) {
        let assumption = Assumption.unitFromRegion(inferredUnit)
        AssumptionChip(
          label: assumption.label, correctionPrompt: assumption.correctionPrompt,
          onCorrect: { useImperial.toggle() })
      }
      Picker("Weight", selection: $useImperial) {
        Text(WeightUnit.kilograms.abbreviation).tag(false)
        Text(WeightUnit.pounds.abbreviation).tag(true)
      }
      .pickerStyle(.segmented)
    }
  }

  private var gymSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      TextField(FirstRunCopy.gymFieldPrompt, text: $gymName)
        #if os(iOS)
          .textContentType(.organizationName)
        #endif
        .textFieldStyle(.roundedBorder)
        .frame(minHeight: Tokens.minimumTapTarget)
      Text(FirstRunCopy.gymFootnote)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
  }

  /// Styled as the start screen's glass Start. `.glassProminent` is macOS 26 / iOS 26; this target
  /// also builds for macOS 15, which keeps the plain button.
  @ViewBuilder private var startButton: some View {
    if #available(macOS 26.0, *) {
      Button(action: onStart) {
        Text(FirstRunCopy.start)
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      }
      .buttonStyle(.glassProminent)
    } else {
      Button(action: onStart) {
        Text(FirstRunCopy.start)
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.accent)
      .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
    }
  }
}

#if DEBUG
  #Preview("Kilograms region") {
    FirstRunView(
      useImperial: .constant(false), inferredUnit: .kilograms, gymName: .constant(""),
      errorMessage: nil, onStart: {})
  }

  #Preview("Pounds region") {
    FirstRunView(
      useImperial: .constant(true), inferredUnit: .pounds, gymName: .constant("Iron Temple"),
      errorMessage: nil, onStart: {})
  }

  #Preview("Error") {
    FirstRunView(
      useImperial: .constant(false), inferredUnit: .kilograms, gymName: .constant("Iron Temple"),
      errorMessage: "The gym could not be saved. Nothing was lost; try again.", onStart: {})
  }
#endif
