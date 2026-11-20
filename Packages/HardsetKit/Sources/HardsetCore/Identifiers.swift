import Foundation

/// UUID-backed typed identifiers.
///
/// Primary keys must be globally unique and are encoded into a CKRecord's `recordName`,
/// which may only contain ASCII, must be under 255 characters, and must not begin with an
/// underscore. A lowercase UUID string satisfies all three.
public protocol HardsetID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible
where RawValue == UUID {
  init(rawValue: UUID)
}

extension HardsetID {
  public init() { self.init(rawValue: UUID()) }
  public var description: String { rawValue.uuidString.lowercased() }
}

public struct ExerciseID: HardsetID {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct MachineID: HardsetID {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct GymID: HardsetID {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct TemplateID: HardsetID {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct SessionID: HardsetID {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct SetID: HardsetID {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// The unit progression is tracked against.
///
/// Machine-level awareness is a product differentiator, not a detail: 80 kg on one brand's
/// leg press is not 80 kg on another's, so a load history keyed only by exercise is
/// misleading. `machineID` is nil for free-weight work, where the bar is the bar.
public struct ProgressionKey: Hashable, Sendable, Codable {
  public let exerciseID: ExerciseID
  public let machineID: MachineID?

  /// Imported equipment is unknown, even when its movement matches a native one. This keeps
  /// imported sets apart from both named machines and native free-weight history.
  public let isImported: Bool

  public init(exerciseID: ExerciseID, machineID: MachineID? = nil, isImported: Bool = false) {
    self.exerciseID = exerciseID
    self.machineID = machineID
    self.isImported = isImported
  }

  private enum CodingKeys: String, CodingKey { case exerciseID, machineID, isImported }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    exerciseID = try values.decode(ExerciseID.self, forKey: .exerciseID)
    machineID = try values.decodeIfPresent(MachineID.self, forKey: .machineID)
    isImported = try values.decodeIfPresent(Bool.self, forKey: .isImported) ?? false
  }
}
