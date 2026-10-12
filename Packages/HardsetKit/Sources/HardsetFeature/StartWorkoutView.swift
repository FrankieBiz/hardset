import HardsetUI
import SwiftUI

/// The Train tab's start screen: the empty state, the gym row, the Start button and, if the last
/// attempt failed, the line that says so. Draws only; the gym, the failure and both actions are
/// the root's, passed in.
struct StartWorkoutView: View {
  /// The selected gym's name, or nil while none is recorded.
  let gymName: String?
  let startFailed: Bool
  let onChooseGym: () -> Void
  let onStart: () -> Void

  var body: some View {
    VStack(spacing: Tokens.Spacing.loose) {
      ContentUnavailableView {
        Label("No workout in progress", systemImage: "figure.strengthtraining.traditional")
      } description: {
        Text("Start an empty workout and add movements as you go.")
      }
      gymRow

      startButton
        .padding(.horizontal, Tokens.Spacing.section)

      if startFailed {
        Text("Could not start a workout. Nothing has been lost — try again.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.critical)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Tokens.Color.background)
  }

  /// The start screen's prominent action, and one of the four places glass is allowed: it is for
  /// the functional layer (Start, the Finish toolbar action, the rest accessory and the Undo bar),
  /// never a set row or a card. `.glassProminent` is iOS 26 and macOS 26, and this target also
  /// builds for macOS 15, which keeps the plain button.
  @ViewBuilder private var startButton: some View {
    if #available(macOS 26.0, *) {
      Button(action: onStart) {
        Text("Start workout")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      }
      .buttonStyle(.glassProminent)
    } else {
      Button(action: onStart) {
        Text("Start workout")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.accent)
      .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
    }
  }

  /// Sets where this workout is, which is what makes per-machine tracking reachable at all: a
  /// machine belongs to a gym, so a session with no gym can only ever log `machineID == nil`.
  ///
  /// Stated as one line rather than a required step. It is preselected from the last gym used, so
  /// the common case — training at the same place — costs nothing.
  private var gymRow: some View {
    Button {
      onChooseGym()
    } label: {
      HStack(spacing: Tokens.Spacing.snug) {
        Image(systemName: "mappin.and.ellipse")
        Text(gymName ?? "Add a gym to track machines")
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption)
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(
        gymName == nil ? Tokens.Color.textSecondary : Tokens.Color.textPrimary
      )
      .frame(minHeight: Tokens.minimumTapTarget)
      .padding(.horizontal, Tokens.Spacing.regular)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, Tokens.Spacing.section)
  }
}
