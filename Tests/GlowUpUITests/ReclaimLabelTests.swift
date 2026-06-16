import XCTest
@testable import GlowUpUI

final class ReclaimLabelTests: XCTestCase {
  func test_confirmTitleAsksToMoveToTrash() {
    XCTAssertTrue(ReclaimLabel.confirmTitle(bytes: 1_000_000).contains("Trash"))
  }

  func test_reclaimHintMentionsEmptyingTrash() {
    XCTAssertTrue(ReclaimLabel.reclaimHint.contains("empty Trash"))
  }
}
