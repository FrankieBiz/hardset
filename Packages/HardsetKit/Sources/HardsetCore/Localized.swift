import Foundation

#if canImport(Darwin)
  /// What Core copy is written as. On Apple platforms a literal here is a
  /// `String.LocalizationValue`: an interpolated `Int` becomes `%lld` and a `String` `%@`, so the
  /// String Catalog can translate the sentence around them and vary it by plural.
  typealias CopyText = String.LocalizationValue
#else
  /// On Linux, where only the tests run, copy is plain English (`DECISIONS.md` §23).
  typealias CopyText = String
#endif

/// The one door Core's words go through on their way to a screen (spec 3.8).
///
/// `String(localized:)` and `LocalizedStringResource` do not exist in the Linux toolchain's
/// Foundation (swift:6.2, checked 2026-10-11), and Core's tests run there. So the call is made
/// here, once: Apple platforms look the text up in Core's String Catalog, and Linux returns the
/// English, which is the catalog's source language and the key. Both platforms therefore return
/// the same English, and every copy test pins both.
///
/// Interpolate only `String` and `Int`. A `Double` would become `%lf` on Apple platforms and print
/// six decimals there while printing "2.5" on Linux; format numbers first.
func localized(_ text: CopyText, comment: StaticString) -> String {
  #if canImport(Darwin)
    String(localized: text, bundle: .module, comment: comment)
  #else
    text
  #endif
}

/// The same, for copy that already has a stable key, such as a literal `"muscle.chest"`.
///
/// Literals only: the key is a `StaticString`, so a non-literal (`Muscle.displayNameKey`, a runtime
/// `String`) compiles on Linux but not on Darwin.
func localized(key: StaticString, default text: CopyText, comment: StaticString) -> String {
  #if canImport(Darwin)
    String(localized: key, defaultValue: text, bundle: .module, comment: comment)
  #else
    text
  #endif
}
