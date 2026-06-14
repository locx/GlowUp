import Foundation

public struct TrashedItem: Codable, Sendable, Equatable {
  public let originalPath: String
  public let trashedPath: String
  // Size of the trashed item at trash time; 0 when unmeasurable. Optional in JSON for back-compat.
  public let bytes: Int64
  // Modification date of the trashed path at trash time; used to detect Trash-path reuse.
  public let modified: Date?

  public init(originalPath: String, trashedPath: String, bytes: Int64 = 0, modified: Date? = nil) {
    self.originalPath = originalPath
    self.trashedPath = trashedPath
    self.bytes = bytes
    self.modified = modified
  }

  // Back-compat: decode older records that may lack `bytes` or `modified`.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    originalPath = try c.decode(String.self, forKey: .originalPath)
    trashedPath = try c.decode(String.self, forKey: .trashedPath)
    bytes = (try? c.decode(Int64.self, forKey: .bytes)) ?? 0
    modified = try? c.decode(Date.self, forKey: .modified)
  }
}

public struct CleanupBatch: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let date: Date
  public let items: [TrashedItem]

  public init(id: String, date: Date, items: [TrashedItem]) {
    self.id = id; self.date = date; self.items = items
  }

  public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}
