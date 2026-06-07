import AppKit

public protocol AppInventory: Sendable {
  func isInstalled(bundleID: String) -> Bool
}

public struct SystemInventory: AppInventory {
  public init() {}

  public func isInstalled(bundleID: String) -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
  }
}
