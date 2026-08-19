import CloudKit
import Foundation
import SQLiteData
import Synchronization

/// What happened to the iCloud account, surfaced to the app instead of acted on silently.
// `nonisolated` is deliberate. This module defaults to MainActor isolation, which is right
// for view-facing types and wrong for this: schema work runs on GRDB's database queues and
// these declarations are pure. Isolating them to the main actor would both mislead and
// force every caller -- including the test suite -- to hop actors for no reason.
public nonisolated enum AccountChange: Hashable, Sendable {
  case signedIn
  case signedOut
  case switchedAccounts
}

/// The account-change handler that keeps local data alive.
///
/// ## Why this class must exist
///
/// SQLiteData erases local data on iCloud sign-out through **two independent paths**, and
/// both are the default:
///
/// 1. **No delegate at all.** `SyncEngine.handleAccountChange` (SyncEngine.swift:1359-1365 in
///    1.9.0/1.10.0) does `guard let delegate else { try await deleteLocalData(); return }`.
///    The `delegate:` initialiser parameter defaults to `nil`, so simply forgetting it wipes
///    the database.
/// 2. **A delegate that does not implement the method.** `SyncEngineDelegate`'s default
///    protocol extension (SyncEngineDelegate.swift:84-101) implements
///    `syncEngine(_:accountChanged:)` as
///    `case .signOut, .switchAccounts: await withErrorReporting { try await syncEngine.deleteLocalData() }`.
///
/// Path 2 is the dangerous one, because Swift silently supplies the default when a
/// conformance omits the method -- no warning, no error. It also means a test that merely
/// asserts "a delegate is installed" would pass while data is still being destroyed. The
/// test that matters is behavioural: fire a sign-out and assert the rows survive.
///
/// ## What sign-out actually costs
///
/// `deleteLocalData()` empties every table registered with the `SyncEngine` and erases the
/// metadatabase. It does **not** touch CloudKit, so anything already uploaded comes back when
/// the user signs into the same account again. The genuinely unrecoverable data is (a) rows
/// created offline that never uploaded, and (b) everything, from the user's point of view, if
/// they switch to a different account and don't realise they can switch back. With no backend
/// of our own, that is not a risk worth taking for a tidier signed-out state.
///
/// ## Retain-cycle note
///
/// `SyncEngine.delegate` is a non-weak `let`, so the engine holds this object strongly. This
/// class therefore must not hold a strong reference back to its `SyncEngine`. It stores no
/// engine reference at all.
/// Whether an account change should erase local data.
///
/// Extracted from the delegate as a pure function so the invariant can be asserted without a
/// database, a CloudKit container or a `SyncEngine` -- none of which are reliably constructible
/// more than once per process in a test run.
public nonisolated enum AccountChangePolicy {
  /// Always `false`.
  ///
  /// This app has no backend of its own, so local rows that never reached iCloud exist in
  /// exactly one place. Erasing them because the *account* changed conflates "who is signed
  /// in" with "whose training history this is". If this ever becomes conditional, it must be
  /// gated behind an explicit user confirmation, never a silent default.
  public static func shouldDeleteLocalData(for change: AccountChange) -> Bool {
    switch change {
    case .signedIn, .signedOut, .switchedAccounts: false
    }
  }
}

// `nonisolated` is deliberate. This module defaults to MainActor isolation, which is right
// for view-facing types and wrong for this: schema work runs on GRDB's database queues and
// these declarations are pure. Isolating them to the main actor would both mislead and
// force every caller -- including the test suite -- to hop actors for no reason.
public nonisolated final class HardsetSyncDelegate: SyncEngineDelegate {
  private struct State {
    var last: AccountChange?
    var continuations: [UUID: AsyncStream<AccountChange>.Continuation] = [:]
  }

  private let state = Mutex(State())

  public init() {}

  /// The most recent account change, for a UI that wants to show a one-off banner.
  public var lastChange: AccountChange? {
    state.withLock { $0.last }
  }

  /// Account changes as they arrive, so the app can prompt the user rather than guess.
  public var changes: AsyncStream<AccountChange> {
    let id = UUID()
    return AsyncStream { continuation in
      state.withLock { $0.continuations[id] = continuation }
      // `Mutex` is non-copyable, so it cannot be captured directly -- capturing it would
      // consume it. Reaching it through a weak `self` borrows it instead.
      continuation.onTermination = { [weak self] _ in
        self?.state.withLock { $0.continuations[id] = nil }
      }
    }
  }

  /// Explicitly implemented so the destructive default extension can never apply.
  ///
  /// Do not delete this method, and do not call `syncEngine.deleteLocalData()` from it
  /// without a user-facing confirmation first. Removing it re-enables the wipe silently.
  public func syncEngine(
    _ syncEngine: SyncEngine,
    accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
  ) async {
    let change: AccountChange =
      switch changeType {
      case .signIn: .signedIn
      case .signOut: .signedOut
      case .switchAccounts: .switchedAccounts
      @unknown default: .signedOut
      }

    // The policy is consulted rather than inlined, so the decision is unit-testable and so a
    // future change has to go through one auditable place. It currently always answers `false`.
    if AccountChangePolicy.shouldDeleteLocalData(for: change) {
      assertionFailure(
        "Deleting local data on account change requires explicit user confirmation first."
      )
    }

    state.withLock { state in
      state.last = change
      for continuation in state.continuations.values {
        continuation.yield(change)
      }
    }
  }
}
