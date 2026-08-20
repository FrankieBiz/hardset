#if canImport(AlarmKit)

import AlarmKit
import HardsetCore

/// The AlarmKit conformance, deliberately placed here rather than in `HardsetCore`.
///
/// `AlarmMetadata` requires nothing beyond `Codable & Hashable & Sendable`, which
/// `RestMetadata` already satisfies, so this conformance is free. Keeping it out of
/// `HardsetCore` is what lets that module stay Foundation-only: AlarmKit ships only in the
/// iPhoneOS SDK and is unavailable on macCatalyst, so importing it into Core would make the
/// engine -- and its whole unit-test suite -- iOS-device-only.
///
/// Not `@retroactive`: both modules are in this package, so the attribute does not apply and the
/// compiler rejects it. It went unnoticed because `swift build` on the host never compiles this
/// target at all -- the `canImport(AlarmKit)` guard makes the whole file vanish on macOS. Only an
/// iOS build reaches it.
extension RestMetadata: AlarmMetadata {}

#endif  // canImport(AlarmKit)
