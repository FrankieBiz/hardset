import HardsetCore
import SwiftUI

/// An intentionally static ledger. Sharing never adds a feed or a public profile.
///
/// Sets are listed in the order they were performed, grouped into runs of one movement on one piece
/// of equipment, so the receipt reads like the training log it is rather than repeating the
/// movement's name on every line.
///
/// The same view is rendered into the shared image, so it holds no controls of its own. The one
/// exception is `onDeleteLine`: a screen correcting a past workout passes it while editing, and
/// each set then shows a delete control. The share renderer never passes it.
public struct WorkoutReceiptView: View {
  private let receipt: WorkoutReceipt
  private let unit: WeightUnit
  private let onDeleteLine: ((WorkoutReceipt.Line) -> Void)?

  public init(
    receipt: WorkoutReceipt, unit: WeightUnit,
    onDeleteLine: ((WorkoutReceipt.Line) -> Void)? = nil
  ) {
    self.receipt = receipt
    self.unit = unit
    self.onDeleteLine = onDeleteLine
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      Text("HARDSET")
        .hardsetText(.display)
        .foregroundStyle(Tokens.Color.plateBlue)
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(receipt.title.isEmpty ? "Workout receipt" : receipt.title)
          .font(Tokens.Text.title)
        Text(receipt.startedAt.formatted(date: .abbreviated, time: .shortened))
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
      if let scorecard = receipt.scorecard {
        scorecardBlock(scorecard)
      }
      if receipt.lines.isEmpty {
        Text("No sets were logged in this workout.")
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
      ForEach(receipt.blocks) { block in
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text(block.exerciseName).font(Tokens.Text.headline)
            Text(block.equipmentLabel)
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.chalkDim)
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)
          ForEach(block.lines) { line in
            row(line)
          }
          Divider().overlay(Tokens.Color.hairline)
        }
      }
      Text("Recorded training log. Loads and equipment are user-entered, not independently verified. Records compare working sets of the same movement on the same recorded machine, or with no machine recorded, against history before this workout.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
      if !receipt.notes.isEmpty {
        Text(receipt.notes).font(Tokens.Text.caption).foregroundStyle(Tokens.Color.chalkDim)
      }
    }
    .foregroundStyle(Tokens.Color.chalk)
    .padding(Tokens.Spacing.section)
    .background(Tokens.Color.canvas)
  }

  // MARK: - Scorecard

  /// How the workout went against last time, at the top: the headline in the figure role, the
  /// records on the record surface, the biggest gain, and a mark for each movement that earned one.
  ///
  /// Counted by movement, and every word comes from `ScorecardCopy`, which the share text uses too,
  /// so the image, the screen and the text never disagree. A first time on a machine is stated as a
  /// first time and left out of the count; a movement that fell short is carried by the headline and
  /// not drawn as a failure. The same view is rendered into the shared image, so it holds no controls.
  private func scorecardBlock(_ card: WorkoutScorecard) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      Text(card.headline)
        .font(Tokens.Text.readout)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      if let records = ScorecardCopy.recordsText(card) {
        Label(records, systemImage: "trophy.fill")
          .font(Tokens.Text.labelEmphasis)
          .foregroundStyle(Tokens.Color.plateYellow)
          .padding(.horizontal, Tokens.Spacing.regular)
          .padding(.vertical, Tokens.Spacing.snug)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            Tokens.Color.plateYellowSurface,
            in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
          .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.control)
              .strokeBorder(Tokens.Color.plateYellow.opacity(0.35), lineWidth: Tokens.Stroke.hairline)
          )
      }

      if let gain = ScorecardCopy.gainText(card) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text(gain)
            .font(Tokens.Text.label)
            .fixedSize(horizontal: false, vertical: true)
          // An estimate never stands without its certainty. Not a control: the receipt is rendered
          // into the shared image, so the capsule is the badge's face and does nothing when tapped.
          if let certainty = card.biggestGain?.certainty {
            CertaintyCapsule(level: MethodologySheet.level(for: certainty), isInteractive: false)
          }
        }
        .accessibilityElement(children: .combine)
      }

      VStack(alignment: .leading, spacing: 0) {
        ForEach(card.entries) { entry in
          if let mark = ScorecardCopy.markText(entry, unit: unit) {
            scorecardRow(entry, mark: mark)
          }
        }
      }
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard()
  }

  /// One movement and what it earned. A win is `plateGreen` with an up arrow, a record `plateYellow`
  /// with the trophy, and a match or a first time `chalkDim`, so none is carried by colour alone.
  private func scorecardRow(_ entry: WorkoutScorecard.Entry, mark: String) -> some View {
    let (hue, symbol): (Color, String?) =
      switch entry.outcome {
      case .beat(nil): (Tokens.Color.plateYellow, "trophy.fill")
      case .beat: (Tokens.Color.plateGreen, "arrow.up")
      case .matched: (Tokens.Color.chalkDim, "equal")
      case .firstTime, .notBeaten: (Tokens.Color.chalkDim, nil)
      }
    return HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
      Text(entry.exerciseName)
        .font(Tokens.Text.label)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: Tokens.Spacing.regular)
      HStack(spacing: Tokens.Spacing.tight) {
        if let symbol {
          Image(systemName: symbol).accessibilityHidden(true)
        }
        Text(mark)
      }
      .hardsetText(.provenance)
      .foregroundStyle(hue)
    }
    .padding(.vertical, Tokens.Spacing.snug)
    .overlay(alignment: .top) {
      Rectangle().fill(Tokens.Color.hairline).frame(height: Tokens.Stroke.hairline)
    }
    .accessibilityElement(children: .combine)
  }

  /// One set: its load and reps as figures, then anything it earned. The delete control, when
  /// present, is its own accessibility element so activating the set's description can never
  /// delete it.
  private func row(_ line: WorkoutReceipt.Line) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
      if let onDeleteLine {
        Button {
          onDeleteLine(line)
        } label: {
          Image(systemName: "minus.circle.fill")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.plateRed)
            .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete set, \(Self.spokenSet(line, unit: unit))")
      }
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          Text("\(LoadText.entered(line.weightKg, in: unit)) \(unit.abbreviation) × \(line.reps)")
            .font(Tokens.Text.figure)
            .monospacedDigit()
          if line.isWarmup {
            Text("Warm-up")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.chalkDim)
          }
          Spacer(minLength: 0)
        }
        ForEach(line.records) { record in
          // The trophy, as the live session marks records. The seal is the high-certainty
          // symbol, and in the record hue it read as a mixed certainty claim.
          Label(record.kind.label, systemImage: "trophy.fill")
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.plateYellow)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  /// A set in words, for its delete control and for a confirmation that names what it removes.
  public static func spokenSet(_ line: WorkoutReceipt.Line, unit: WeightUnit) -> String {
    "\(line.exerciseName), \(LoadText.entered(line.weightKg, in: unit)) \(unit.abbreviation) "
      + "× \(line.reps)\(line.isWarmup ? ", warm-up" : "")"
  }
}
