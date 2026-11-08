import Foundation

/// A durable desired state plus OS operations still needing reconciliation.
/// Old alarm IDs stay recorded until cancellation succeeds, including across process death.
public struct RestCheckpoint: Codable, Hashable, Sendable {
  public let state: RestTimerState
  public let metadata: RestMetadata?
  public let alarmID: UUID?
  public let scheduledAlarmID: UUID?
  public let retiredAlarmIDs: [UUID]

  public init(state: RestTimerState = .idle, metadata: RestMetadata? = nil,
    alarmID: UUID? = nil, scheduledAlarmID: UUID? = nil, retiredAlarmIDs: [UUID] = []) {
    self.state = state; self.metadata = metadata; self.alarmID = alarmID
    self.scheduledAlarmID = scheduledAlarmID
    self.retiredAlarmIDs = retiredAlarmIDs
  }
}
