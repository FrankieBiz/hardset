#if canImport(AlarmKit)

import AlarmKit
import HardsetCore

/// Retroactive conformance, deliberately placed here rather than in `HardsetCore`.
///
/// `AlarmMetadata` requires nothing beyond `Codable & Hashable & Sendable`, which
/// `RestMetadata` already satisfies, so this conformance is free. Keeping it out of
/// `HardsetCore` is what lets that module stay Foundation-only: AlarmKit ships only in the
/// iPhoneOS SDK and is unavailable on macCatalyst, so importing it into Core would make the
/// engine -- and its whole unit-test suite -- iOS-device-only.
extension RestMetadata: @retroactive AlarmMetadata {}

#endif  // canImport(AlarmKit)
