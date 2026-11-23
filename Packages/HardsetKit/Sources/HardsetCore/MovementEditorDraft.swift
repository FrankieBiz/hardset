import Foundation

/// The rules of the movement editor, held apart from any view so they are tested without one.
///
/// A lifter naming a movement of their own says which body part it trains, which muscle where the
/// part has more than one, up to three more it works, and what the load is applied with. Nothing is
/// inferred from the name. The draft turns that into the `CustomAttribution` the store saves, and
/// refuses to be saved until there is a name and a primary muscle, so a movement is never half
/// tagged.
public struct MovementEditorDraft: Hashable, Sendable {
  /// The five ways a load is applied, in the order the editor offers them. Machine leads because
  /// machines are what this app tracks per piece of equipment.
  public static let equipment: [ExerciseModality] = [
    .machine, .cable, .barbell, .dumbbell, .bodyweight,
  ]

  public var name: String
  /// One of `equipment`, or nil when the movement has no equipment on record. A new movement opens
  /// on machine, which the lifter can see and change, and is not read off the name. A movement that
  /// already exists opens on what it says, and on nothing when it says nothing: saving it with no
  /// equipment chosen leaves it unrecorded, so the app never declares equipment for the lifter. An
  /// estimated max follows from equipment the lifter named, never from one the editor filled in.
  public var modality: ExerciseModality?
  /// An imported movement keeps the name it was imported under. A later import looks it up by that
  /// name, so renaming it would start a second movement beside it with the same history.
  public let nameIsFixed: Bool
  public private(set) var bodyPart: MuscleFilterCategory?
  public private(set) var primary: Muscle?
  /// In the order chosen, at most `CustomAttribution.maximumSecondaries`.
  public private(set) var secondary: [Muscle]

  public init(name: String = "", modality: ExerciseModality? = .machine, nameIsFixed: Bool = false) {
    self.name = name
    self.modality = modality
    self.nameIsFixed = nameIsFixed
    self.bodyPart = nil
    self.primary = nil
    self.secondary = []
  }

  /// Starts from what a movement already says, for retagging it. An untagged movement has no body
  /// part, and one with no equipment on record, or equipment this build does not know, has none
  /// selected. Stabilisers and tokens this build does not know are not carried over as secondaries.
  public init(entry: CatalogEntry) {
    self.init(name: entry.name, modality: entry.modality, nameIsFixed: entry.isImported)
    guard let muscle = entry.primaryMuscle.muscle else { return }
    bodyPart = muscle.filterCategory
    primary = muscle
    var seen: Set<Muscle> = [muscle]
    for contribution in entry.contributions where contribution.role == .indirect {
      guard let other = contribution.key.muscle, seen.insert(other).inserted,
        secondary.count < CustomAttribution.maximumSecondaries
      else { continue }
      secondary.append(other)
    }
  }

  public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Said under a name that cannot be edited, so a field that will not take typing is not a mystery.
  public static let fixedNameNote =
    "Named by the app it came from. A later import finds it by this name, so it stays."

  /// Whether the equipment is still unrecorded, so the editor says what that holds back.
  public var equipmentIsUnset: Bool { modality == nil }

  /// Said under the equipment chips while none is chosen. It is the one place the app says why a
  /// movement has no estimated max, and what makes one possible, without offering a guess.
  public static let equipmentUnsetNote =
    "Not set. Hardset does not estimate a max for a movement until you say what the load is."

  /// Said under Save once it can be pressed. An imported movement's sets already exist, so the
  /// lifter is told what saving it changes: volume counts them from the next read.
  public var savedNote: String {
    nameIsFixed
      ? "Saved as your own choice. Its imported sets count toward these muscles in Volume."
      : "Saved as your own choice, so volume counts these muscles as you say."
  }

  /// What every surface that saves a movement says when its name belongs to another movement, so
  /// the Library, the live workout's picker and the workout editor refuse in the same words. The
  /// name is the one the lifter typed, so it reads back as what they entered.
  public static func nameTakenMessage(_ name: String) -> String {
    "A movement called “\(name)” already exists. Choose another name."
  }

  /// The muscles the chosen body part offers, in anatomical order.
  public var specificMuscles: [Muscle] { bodyPart?.members ?? [] }

  /// Whether the lifter must pick a muscle within the body part. A part with one muscle is that
  /// muscle already.
  public var asksForSpecificMuscle: Bool { specificMuscles.count > 1 }

  public var secondaryLimitReached: Bool {
    secondary.count >= CustomAttribution.maximumSecondaries
  }

  /// A name and a primary muscle. The secondaries may be none, and the equipment may stay as it is:
  /// naming a body part for an imported movement must not oblige the lifter to declare equipment.
  public var canSave: Bool { !trimmedName.isEmpty && primary != nil }

  /// What still stops the movement from being saved, in the lifter's words, or nil when nothing
  /// does. The next step only, name first, so a disabled Save never leaves the reason to a guess.
  public var whatIsMissing: String? {
    if trimmedName.isEmpty { return "Name the movement." }
    if bodyPart == nil { return "Choose a body part." }
    if primary == nil { return "Choose which muscle it trains most." }
    return nil
  }

  /// What the store saves, or nil until there is a primary muscle. Equipment left unset is saved as
  /// "leave it as it is", never as a choice.
  public var attribution: CustomAttribution? {
    primary.flatMap { CustomAttribution(primary: $0, secondary: secondary, modality: modality) }
  }

  /// Picks a body part. A part with one muscle sets the primary; a part with several keeps the
  /// primary only if it belongs to the new part, and otherwise waits for a choice.
  public mutating func choose(bodyPart category: MuscleFilterCategory) {
    bodyPart = category
    let members = category.members
    if members.count == 1 {
      primary = members[0]
    } else if let current = primary, !members.contains(current) {
      primary = nil
    }
    if let primary { secondary.removeAll { $0 == primary } }
  }

  /// Picks the primary muscle within the body part. A muscle chosen as primary is no longer a
  /// secondary, since a muscle cannot be credited twice.
  public mutating func choose(primary muscle: Muscle) {
    bodyPart = muscle.filterCategory
    primary = muscle
    secondary.removeAll { $0 == muscle }
  }

  /// Adds or removes a secondary muscle. Refused, returning false, when the primary is named or the
  /// limit is reached; removing one always works.
  @discardableResult
  public mutating func toggleSecondary(_ muscle: Muscle) -> Bool {
    if let index = secondary.firstIndex(of: muscle) {
      secondary.remove(at: index)
      return true
    }
    guard muscle != primary, !secondaryLimitReached else { return false }
    secondary.append(muscle)
    return true
  }
}
