import Foundation
import Testing

@testable import HardsetStore

@Suite("Saving to Apple Health is off until the lifter turns it on, and stays as they left it")
struct HealthExportSettingTests {
  private func defaults() -> UserDefaults {
    UserDefaults(suiteName: "hardset.tests.\(UUID().uuidString)")!
  }

  @Test("A fresh install is opted out")
  func offByDefault() {
    #expect(!UserDefaultsHealthExportSetting(defaults: defaults()).isEnabled)
    #expect(!InMemoryHealthExportSetting().isEnabled)
  }

  @Test("The choice survives a relaunch, both ways")
  func persists() {
    let suite = defaults()
    UserDefaultsHealthExportSetting(defaults: suite).setEnabled(true)
    #expect(UserDefaultsHealthExportSetting(defaults: suite).isEnabled)
    UserDefaultsHealthExportSetting(defaults: suite).setEnabled(false)
    #expect(!UserDefaultsHealthExportSetting(defaults: suite).isEnabled)
  }
}
