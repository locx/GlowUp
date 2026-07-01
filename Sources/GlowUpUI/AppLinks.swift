import Foundation

// Hardcoded external destinations defined once. Call sites use `if let`, not force-unwrap,
// so a future typo in one of these literals can never crash the app.
enum AppLinks {
  static let gitHub = URL(string: "https://github.com/locx/GlowUp")
  static let fullDiskAccessSettings =
    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
}
