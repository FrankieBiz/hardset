import SwiftUI

// MARK: - Section chrome

/// A catalogue section: the shared section label over its content, so every section reads the
/// same way and none draws its own heading. Every catalogue view in the module uses it except
/// `KeypadCatalogView`, whose one section is a whole sheet with a `SectionLabel` of its own.
struct CatalogSection<Content: View>: View {
  private let title: String
  private let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel(title)
      content
    }
  }
}
