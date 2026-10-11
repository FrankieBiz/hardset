import Foundation

extension Muscle {
  /// The name a lifter reads.
  ///
  /// Moved here from `ExercisePickerView`, where it was a dictionary with a raw-value fallback: a
  /// muscle missing from it would have shown "rotatorCuff". A total switch cannot miss one, and a
  /// test pins every word. `displayNameKey` remains the String Catalog key for it.
  public var displayName: String {
    switch self {
    case .chest: "Chest"
    case .frontDelts: "Front delts"
    case .sideDelts: "Side delts"
    case .rearDelts: "Rear delts"
    case .rotatorCuff: "Rotator cuff"
    case .lats: "Lats"
    case .upperBack: "Upper back"
    case .traps: "Traps"
    case .lowerBack: "Lower back"
    case .biceps: "Biceps"
    case .triceps: "Triceps"
    case .forearms: "Forearms"
    case .abs: "Abs"
    case .obliques: "Obliques"
    case .neck: "Neck"
    case .quadriceps: "Quads"
    case .hamstrings: "Hamstrings"
    case .glutes: "Glutes"
    case .adductors: "Adductors"
    case .hipAbductors: "Hip abductors"
    case .gastrocnemius: "Gastrocnemius"
    case .soleus: "Soleus"
    }
  }
}

extension MuscleKey {
  /// The muscle's name, or a plain statement of why there is none. Never the raw token: a
  /// generated name looks authored and is not.
  public var displayName: String {
    if let muscle { return muscle.displayName }
    return isReservedSentinel ? "Not attributed" : "Not recognised"
  }
}
