import Foundation

public enum ReclaimLabel {
  // Trashing frees nothing until the Trash is emptied — copy never overclaims.
  public static let reclaimHint = "moved to Trash — empty Trash to reclaim"

  public static func hero(bytes: Int64) -> String {
    bytes <= 0 ? "Your Mac is already sparkling"
               : "You can free up \(format(bytes))"
  }

  public static func confirmTitle(bytes: Int64) -> String {
    "Move \(format(bytes)) to the Trash?"
  }

  public static func done(bytes: Int64) -> String {
    bytes <= 0 ? "Nothing to clean" : "Freed \(format(bytes))"
  }

  public static func format(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
  }
}
