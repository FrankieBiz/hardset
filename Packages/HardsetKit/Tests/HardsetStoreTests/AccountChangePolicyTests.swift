import Testing

@testable import HardsetStore

/// The blocker-1 invariant, pinned without a database.
///
/// The behavioural tests in `SyncDelegateTests` are the stronger evidence, but each needs its
/// own process (see that file). These run anywhere, always, in microseconds -- so the invariant
/// is never unguarded just because the heavier suite was skipped.
@Suite("No account change ever erases local data")
struct AccountChangePolicyTests {
  @Test("Signing out does not erase local data")
  func signOut() {
    #expect(!AccountChangePolicy.shouldDeleteLocalData(for: .signedOut))
  }

  @Test("Switching accounts does not erase local data")
  func switchAccounts() {
    #expect(!AccountChangePolicy.shouldDeleteLocalData(for: .switchedAccounts))
  }

  @Test("Signing in does not erase local data")
  func signIn() {
    #expect(!AccountChangePolicy.shouldDeleteLocalData(for: .signedIn))
  }

  /// Exhaustive: a new `AccountChange` case must be considered here rather than inheriting a
  /// permissive default.
  @Test("No account change whatsoever erases local data")
  func exhaustive() {
    for change in [AccountChange.signedIn, .signedOut, .switchedAccounts] {
      #expect(
        !AccountChangePolicy.shouldDeleteLocalData(for: change),
        "\(change) would erase local data"
      )
    }
  }
}
