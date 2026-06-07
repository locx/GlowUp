import XCTest
@testable import GlowUpUI

final class ReclaimLabelTests: XCTestCase {
  func test_heroShowsFormattedSize() {
    XCTAssertTrue(ReclaimLabel.hero(bytes: 12_400_000_000).contains("free up"))
  }

  func test_heroEmptyStateNeverShowsZeroBytes() {
    let s = ReclaimLabel.hero(bytes: 0)
    XCTAssertFalse(s.contains("0 bytes"))
    XCTAssertEqual(s, "Your Mac is already sparkling")
  }

  func test_confirmTitleAsksToMoveToTrash() {
    XCTAssertTrue(ReclaimLabel.confirmTitle(bytes: 1_000_000).contains("Trash"))
  }

  func test_doneNeverClaimsFreedWhenNothingMoved() {
    XCTAssertFalse(ReclaimLabel.done(bytes: 0).lowercased().contains("freed 0"))
  }

  func test_reclaimHintMentionsEmptyingTrash() {
    XCTAssertTrue(ReclaimLabel.reclaimHint.contains("empty Trash"))
  }
}
