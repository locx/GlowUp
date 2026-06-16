import Foundation
import GlowKit

public enum ReclaimLabel {
  // Trashing frees nothing until the Trash is emptied — copy never overclaims.
  public static let reclaimHint = "moved to Trash — empty Trash to reclaim"

  public static func confirmTitle(bytes: Int64) -> String {
    "Move \(format(bytes)) to the Trash?"
  }

  public static func format(_ bytes: Int64) -> String { ByteFormat.string(bytes) }
}
