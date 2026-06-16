import Foundation

// Large-file finding (user data): trashed only on the user's explicit, recoverable request — never auto-cleaned.
public struct Report: Sendable, Identifiable, Equatable {
  public let url: URL
  public let bytes: Int64
  public var id: String { url.path }

  public init(url: URL, bytes: Int64) {
    self.url = url; self.bytes = bytes
  }
}
