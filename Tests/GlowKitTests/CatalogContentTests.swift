import XCTest
@testable import GlowKit

// Lints the SHIPPED catalog; a bad rule fails CI (fix the rule, not the test).
final class CatalogContentTests: XCTestCase {
  private func catalog() throws -> Catalog { try CatalogLoader.loadBundled() }

  func test_catalogHasBroadCoverage() throws {
    let ids = Set(try catalog().rules.map(\.id))
    for expected in ["chrome", "firefox", "vscode", "slack",
                     "xcode.deriveddata", "dev.npm", "system.diagnosticreports",
                     "vscode.insiders", "cursor", "vivaldi",
                     "jetbrains",
                     "chrome.netcache", "firefox.netcache"] {
      XCTAssertTrue(ids.contains(expected), "missing rule \(expected)")
    }
    XCTAssertGreaterThanOrEqual(try catalog().rules.count, 55)
  }

  func test_everyRuleHasNonEmptyWhyAndPaths() throws {
    for rule in try catalog().rules {
      XCTAssertFalse(rule.why.trimmingCharacters(in: .whitespaces).isEmpty,
                     "rule \(rule.id) has empty why")
      XCTAssertFalse(rule.paths.isEmpty, "rule \(rule.id) has no paths")
    }
  }

  func test_categoriesAreFromAllowedDisplaySet() throws {
    let allowed: Set<String> = ["appCaches", "browserData", "systemLogs"]
    for rule in try catalog().rules {
      XCTAssertTrue(allowed.contains(rule.category),
                    "rule \(rule.id) uses category \(rule.category)")
    }
  }

  func test_noGlobUsesDoubleStarRecursion() throws {
    for rule in try catalog().rules {
      for spec in rule.paths {
        XCTAssertFalse(spec.glob.contains("**"),
                       "rule \(rule.id) uses ** in \(spec.glob)")
      }
    }
  }

  func test_projectArtifactsNeverTargetVirtualEnvs() throws {
    // Virtualenvs anchor active workspaces (interpreter paths, IDE configs) —
    // deleting them breaks projects, so they must never ship as artifacts.
    let vetoed: Set<String> = [".venv", "venv", "env", ".env", "virtualenv", ".virtualenvs"]
    for name in try catalog().projectArtifacts {
      XCTAssertFalse(vetoed.contains(name.lowercased()),
                     "projectArtifacts must not include virtualenv dir \(name)")
    }
  }

  func test_dataStoreShapedPathsAreNeverSafe() throws {
    // Service Worker/CacheStorage and any glob naming a DataStoreGuard segment can hold live
    // app/PWA state; pinning them off `safe` stops a future editor silently auto-trashing it.
    for rule in try catalog().rules {
      for spec in rule.paths {
        let segments = spec.glob.split(separator: "/").map(String.init)
        let isDataStoreShaped = spec.glob.hasSuffix("Service Worker/CacheStorage")
          || segments.contains { DataStoreGuard.names.contains($0) }
        if isDataStoreShaped {
          XCTAssertNotEqual(spec.effectiveRisk(ruleRisk: rule.risk), .safe,
                            "\(rule.id) \(spec.glob) is data-store-shaped and must not be safe")
        }
      }
    }
  }

  func test_browserPrivacyAndSessionPathsAreNotDefaultSafe() throws {
    // Cookies/history must be privacy; sessions/local-storage stateful — never safe.
    for rule in try catalog().rules where rule.category == "browserData" {
      for spec in rule.paths {
        let lower = spec.glob.lowercased()
        if lower.hasSuffix("cookies") || lower.hasSuffix("history")
            || lower.hasSuffix("cookies.sqlite") {
          XCTAssertEqual(spec.effectiveRisk(ruleRisk: rule.risk), .privacy,
                         "\(rule.id) \(spec.glob) should be privacy")
        }
        if lower.hasSuffix("sessions") || lower.hasSuffix("local storage")
            || lower.hasSuffix("sessionstore-backups") {
          XCTAssertEqual(spec.effectiveRisk(ruleRisk: rule.risk), .stateful,
                         "\(rule.id) \(spec.glob) should be stateful")
        }
      }
    }
  }
}
