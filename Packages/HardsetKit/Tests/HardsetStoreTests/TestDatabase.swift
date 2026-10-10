import Foundation
import GRDB

extension Configuration {
  /// The configuration every store test builds its database from.
  ///
  /// Exists because the schema's primary keys default to `uuid()`, which Apple's SQLite
  /// provides and the Linux distribution's does not. Without it every insert on Linux fails
  /// with "unknown function: uuid()". On Darwin this adds nothing, so Apple runs are unchanged.
  ///
  /// `GRDB.Configuration()` is spelled out on purpose: a bulk replace of `Configuration()` with
  /// `Configuration.forTesting()` must not turn this line into infinite recursion. A probe did
  /// exactly that, and every database test segfaulted.
  static func forTesting() -> Configuration {
    var configuration = GRDB.Configuration()
    #if !canImport(Darwin)
    configuration.prepareDatabase { db in
      db.add(
        function: DatabaseFunction("uuid", argumentCount: 0, pure: false) { _ in
          UUID().uuidString.lowercased()
        }
      )
    }
    #endif
    return configuration
  }
}
