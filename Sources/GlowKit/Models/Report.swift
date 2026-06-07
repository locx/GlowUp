import Foundation

// Report-only item: surfaced for the user to act on themselves, never trashed by the app.
public struct Report: Sendable, Identifiable, Equatable {
  public let url: URL
  public let bytes: Int64
  public var id: String { url.path }

  public init(url: URL, bytes: Int64) {
    self.url = url; self.bytes = bytes
  }
}
