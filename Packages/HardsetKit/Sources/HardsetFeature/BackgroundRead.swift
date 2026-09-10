/// Runs a synchronous store read away from the UI actor.
///
/// GRDB's APIs are intentionally synchronous, but some of the read models built from them can span
/// years of history. Keeping this hop at the composition boundary lets the stores remain simple and
/// deterministic without making a navigation transition wait on SQLite or report aggregation.
nonisolated func readOffMain<Value: Sendable>(
  _ operation: @escaping @Sendable () throws -> Value
) async -> Result<Value, any Error> {
  await Task.detached(priority: .userInitiated) {
    Result { try operation() }
  }
  .value
}
