import Foundation

public struct TrashedItem: Codable, Sendable, Equatable {
  public let originalPath: String
  public let trashedPath: String

  public init(originalPath: String, trashedPath: String) {
    self.originalPath = originalPath
    self.trashedPath = trashedPath
  }
}

public struct CleanupBatch: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let date: Date
  public let items: [TrashedItem]

  public init(id: String, date: Date, items: [TrashedItem]) {
    self.id = id; self.date = date; self.items = items
  }
}
