import Foundation
import Testing

@testable import HardsetCore

/// The app target's resource files, checked where a test can read them.
///
/// The app and widget targets cannot be built here, but their plists, manifests and colour sets
/// are plain files. `Tools/linux-test.sh` mounts the whole checkout, so these run on Linux as
/// well as on the Mac.
@Suite("The app's launch colour, manifests and plists say what the code does")
struct AppResourcesTests {
  /// The checkout root: `Tests/HardsetCoreTests/<file>` → `Packages/HardsetKit` → the repo.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

  private func data(_ path: String) throws -> Data {
    try Data(contentsOf: Self.root.appendingPathComponent(path))
  }

  private func plist(_ path: String) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(from: data(path), format: nil)
    return try #require(object as? [String: Any], "\(path) is not a dictionary plist")
  }

  private func components(_ entry: [String: Any]) throws -> PaletteColor {
    let color = try #require(entry["color"] as? [String: Any])
    let parts = try #require(color["components"] as? [String: String])
    func value(_ key: String) throws -> Double { try #require(parts[key].flatMap(Double.init)) }
    return PaletteColor(red: try value("red"), green: try value("green"), blue: try value("blue"))
  }

  private func close(_ a: PaletteColor, _ b: PaletteColor) -> Bool {
    abs(a.red - b.red) < 0.002 && abs(a.green - b.green) < 0.002 && abs(a.blue - b.blue) < 0.002
  }

  @Test("The launch screen is the app's background, light and dark")
  func launchBackgroundMatchesPalette() throws {
    let object = try JSONSerialization.jsonObject(
      with: data("Hardset/Assets.xcassets/LaunchBackground.colorset/Contents.json"))
    let colors = try #require((object as? [String: Any])?["colors"] as? [[String: Any]])
    let light = try #require(colors.first { $0["appearances"] == nil })
    let dark = try #require(colors.first { $0["appearances"] != nil })
    #expect(close(try components(light), Palette.backgroundLight))
    #expect(close(try components(dark), Palette.backgroundDark))
    let info = try plist("Hardset/Info.plist")
    let launch = try #require(info["UILaunchScreen"] as? [String: Any])
    #expect(launch["UIColorName"] as? String == "LaunchBackground")
  }

  @Test("The app declares its own defaults only, tracks nothing, collects nothing")
  func appManifest() throws {
    let manifest = try plist("Hardset/PrivacyInfo.xcprivacy")
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    #expect(accessed.count == 1)
    #expect(accessed.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
    #expect(accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
  }

  @Test("The widget has its own manifest, and it declares nothing it does not do")
  func widgetManifest() throws {
    let manifest = try plist("HardsetWidget/PrivacyInfo.xcprivacy")
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    #expect((manifest["NSPrivacyAccessedAPITypes"] as? [Any])?.isEmpty == true)
  }

  /// `DECISIONS.md` §25. 1C8F.1 is undeclared because no shared suite exists. Adding one without
  /// declaring it in both manifests is how an upload gets rejected, so this test fails first.
  @Test("No code opens a shared UserDefaults suite")
  func noSharedDefaultsSuite() throws {
    // Hardset and HardsetWidget must exist, or this scans nothing and passes for the wrong reason.
    let required = ["Hardset", "HardsetWidget"]
    let optional = ["HardsetIntents", "Packages/HardsetKit/Sources"]
    var offenders: [String] = []
    var scanned = 0
    for folder in required + optional {
      let url = Self.root.appendingPathComponent(folder)
      if required.contains(folder) {
        #expect(FileManager.default.fileExists(atPath: url.path), "\(folder) is missing")
      }
      guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
      else { continue }
      for case let file as URL in files where file.pathExtension == "swift" {
        scanned += 1
        let text = try String(contentsOf: file, encoding: .utf8)
        if text.contains("UserDefaults(suiteName:") || text.contains(".init(suiteName:") {
          offenders.append(file.lastPathComponent)
        }
      }
    }
    try #require(scanned > 0, "no Swift files were scanned; is the checkout mounted?")
    #expect(offenders.isEmpty, "declare 1C8F.1 in both privacy manifests first: \(offenders)")
  }
}
