import Foundation

public enum ByteFormat {
  // Single source for human byte sizes so the CLI and the app never drift apart.
  public static func string(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
  }
}
