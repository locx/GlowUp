# GlowUp — Plan 1: Foundation (Catalog + Safety Spine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `GlowKit` Swift library's safety spine — load a validated cleanup catalog, resolve symbolic paths via glob, and veto any candidate that touches a protected location — all under test.

**Architecture:** A pure, UI-free SwiftPM library target (`GlowKit`) with the cleanup catalog as a versioned JSON resource. The catalog names only *symbolic* base roots (never raw absolutes); `Resolver` expands them and every result passes a hardcoded, non-overridable `DenyList` veto. A safety-lint test proves no shipped rule can ever resolve onto protected data.

**Tech Stack:** Swift 5.9, SwiftPM, macOS 13+, XCTest, Foundation, Darwin `fnmatch`.

**Spec source:** `docs/superpowers/specs/2026-06-06-glowup-spec.md` (§2 Safety model, §2A safety-UX, §4 Catalog schema).

---

## Plan set (Plan 1 of a planned 7; Plans 2–7 not yet written)

1. **Foundation — catalog + safety spine** ← this doc
2. Engine — Inventory, Scanner, SizeMeasurer, Trasher, RestoreStore, TreeProvider
3. Catalog content — all curated rules; safety-lint green
4. App — SwiftUI (sidebar, radial ring, tree, clean flow, onboarding, restore, menu-bar)
5. CLI `glowup` + legacy bash refactor to catalog
6. Advanced scanners — orphans, projects, workspaceStorage, dup-extensions, large-file report
7. Packaging — entitlements, DMG, notarize CI, Homebrew cask, repo hygiene

Each plan produces working, tested software on its own. Plans 2–7 above are the
intended roadmap; their plan files do not exist yet.

---

## File structure (this plan)

- Create: `Sources/GlowKit/Models/Risk.swift` — risk tiers
- Create: `Sources/GlowKit/Models/BaseRoot.swift` — symbolic roots → URLs
- Create: `Sources/GlowKit/Models/Catalog.swift` — `Catalog`/`Rule`/`PathSpec`
- Create: `Sources/GlowKit/CatalogLoader.swift` — decode + validate
- Create: `Sources/GlowKit/DenyList.swift` — protected-path veto
- Create: `Sources/GlowKit/Resolver.swift` — glob expansion + veto
- Create: `Sources/GlowKit/Resources/catalog.json` — seed catalog (1 rule)
- Create: `Tests/GlowKitTests/*` — one test file per unit
- Modify: `Package.swift` — add `GlowKit` library + `GlowKitTests`

---

### Task 0: Restructure the package

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Rewrite `Package.swift` to add the library + test target**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "GlowUp",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GlowKit", targets: ["GlowKit"]),
    .executable(name: "MacLibCleanup", targets: ["MacLibCleanup"]),
  ],
  targets: [
    .target(
      name: "GlowKit",
      resources: [.copy("Resources/catalog.json")]
    ),
    .executableTarget(
      name: "MacLibCleanup",
      path: "Sources/MacLibCleanup"
    ),
    .testTarget(
      name: "GlowKitTests",
      dependencies: ["GlowKit"]
    ),
  ]
)
```

- [ ] **Step 2: Create the seed catalog so the resource exists**

Create `Sources/GlowKit/Resources/catalog.json`:

```json
{
  "schemaVersion": 1,
  "rules": [
    {
      "id": "vscode.caches",
      "app": "Visual Studio Code",
      "appBundleID": "com.microsoft.VSCode",
      "requiresInstalled": true,
      "category": "appCaches",
      "risk": "safe",
      "why": "Regenerated on next launch.",
      "paths": [
        { "base": "appSupport", "glob": "Code/CachedData" },
        { "base": "appSupport", "glob": "Code/WebStorage", "risk": "stateful" }
      ]
    }
  ],
  "projectRoots": ["~/projects"],
  "projectArtifacts": ["node_modules", ".venv", ".build"]
}
```

- [ ] **Step 3: Verify the package resolves and builds**

Run: `cd ~/projects/MacLibCleanup && swift build`
Expected: builds with no errors (the existing app target still compiles; `GlowKit` is empty but valid).

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/GlowKit/Resources/catalog.json
git commit -m "build: add GlowKit library + test targets and seed catalog"
```

---

### Task 1: Risk tiers

**Files:**
- Create: `Sources/GlowKit/Models/Risk.swift`
- Test: `Tests/GlowKitTests/RiskTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class RiskTests: XCTestCase {
  func test_decodesFromLowercaseString() throws {
    let data = Data("\"stateful\"".utf8)
    XCTAssertEqual(try JSONDecoder().decode(Risk.self, from: data), .stateful)
  }

  func test_safeIsDefaultSelectable() {
    XCTAssertEqual(Risk.allCases.filter { $0.isDefaultSelected }, [.safe])
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RiskTests`
Expected: FAIL — `Risk` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
public enum Risk: String, Codable, CaseIterable, Sendable {
  case safe, stateful, privacy, rebuildable

  // Only safe-tier items are pre-selected; the rest are opt-in.
  public var isDefaultSelected: Bool { self == .safe }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RiskTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GlowKit/Models/Risk.swift Tests/GlowKitTests/RiskTests.swift
git commit -m "feat: add Risk tier model"
```

---

### Task 2: Symbolic base roots

**Files:**
- Create: `Sources/GlowKit/Models/BaseRoot.swift`
- Test: `Tests/GlowKitTests/BaseRootTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class BaseRootTests: XCTestCase {
  private let home = URL(fileURLWithPath: "/Users/test")

  func test_resolvesAppSupport() {
    XCTAssertEqual(BaseRoot.appSupport.url(home: home).path,
                   "/Users/test/Library/Application Support")
  }

  func test_resolvesCachesAndHome() {
    XCTAssertEqual(BaseRoot.caches.url(home: home).path,
                   "/Users/test/Library/Caches")
    XCTAssertEqual(BaseRoot.home.url(home: home).path, "/Users/test")
  }

  func test_decodesFromString() throws {
    let data = Data("\"logs\"".utf8)
    XCTAssertEqual(try JSONDecoder().decode(BaseRoot.self, from: data), .logs)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BaseRootTests`
Expected: FAIL — `BaseRoot` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum BaseRoot: String, Codable, CaseIterable, Sendable {
  case home, appSupport, caches, logs, xcode

  public func url(home: URL) -> URL {
    switch self {
    case .home:       return home
    case .appSupport: return home.appending(path: "Library/Application Support")
    case .caches:     return home.appending(path: "Library/Caches")
    case .logs:       return home.appending(path: "Library/Logs")
    case .xcode:      return home.appending(path: "Library/Developer/Xcode")
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BaseRootTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GlowKit/Models/BaseRoot.swift Tests/GlowKitTests/BaseRootTests.swift
git commit -m "feat: add symbolic BaseRoot resolution"
```

---

### Task 3: Catalog models

**Files:**
- Create: `Sources/GlowKit/Models/Catalog.swift`
- Test: `Tests/GlowKitTests/CatalogModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class CatalogModelTests: XCTestCase {
  func test_decodesRuleWithPerPathRiskOverride() throws {
    let json = """
    { "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [],
      "rules": [
        { "id": "x", "category": "appCaches", "risk": "safe", "why": "w",
          "paths": [
            { "base": "caches", "glob": "A" },
            { "base": "appSupport", "glob": "B/WebStorage", "risk": "stateful" }
          ] } ] }
    """
    let cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
    XCTAssertEqual(cat.rules.count, 1)
    let r = cat.rules[0]
    XCTAssertNil(r.paths[0].risk)              // inherits rule risk
    XCTAssertEqual(r.paths[1].risk, .stateful) // overrides
  }

  func test_effectiveRiskFallsBackToRule() throws {
    let p = PathSpec(base: .caches, glob: "A", risk: nil)
    XCTAssertEqual(p.effectiveRisk(ruleRisk: .safe), .safe)
    let q = PathSpec(base: .caches, glob: "A", risk: .privacy)
    XCTAssertEqual(q.effectiveRisk(ruleRisk: .safe), .privacy)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CatalogModelTests`
Expected: FAIL — `Catalog`/`PathSpec` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct PathSpec: Codable, Sendable, Equatable {
  public let base: BaseRoot
  public let glob: String
  public let risk: Risk?

  public init(base: BaseRoot, glob: String, risk: Risk? = nil) {
    self.base = base; self.glob = glob; self.risk = risk
  }

  public func effectiveRisk(ruleRisk: Risk) -> Risk { risk ?? ruleRisk }
}

public struct Rule: Codable, Sendable, Identifiable {
  public let id: String
  public let app: String?
  public let appBundleID: String?
  public let requiresInstalled: Bool?
  public let category: String
  public let risk: Risk
  public let why: String
  public let paths: [PathSpec]
}

public struct Catalog: Codable, Sendable {
  public let schemaVersion: Int
  public let rules: [Rule]
  public let projectRoots: [String]
  public let projectArtifacts: [String]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CatalogModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GlowKit/Models/Catalog.swift Tests/GlowKitTests/CatalogModelTests.swift
git commit -m "feat: add Catalog/Rule/PathSpec models"
```

---

### Task 4: Catalog loader + validation

**Files:**
- Create: `Sources/GlowKit/CatalogLoader.swift`
- Test: `Tests/GlowKitTests/CatalogLoaderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class CatalogLoaderTests: XCTestCase {
  private func decode(_ s: String) throws -> Catalog {
    try CatalogLoader.load(data: Data(s.utf8))
  }

  func test_loadsBundledCatalog() throws {
    let cat = try CatalogLoader.loadBundled()
    XCTAssertEqual(cat.schemaVersion, 1)
    XCTAssertFalse(cat.rules.isEmpty)
  }

  func test_rejectsWrongSchemaVersion() {
    let s = #"{ "schemaVersion": 2, "rules": [], "projectRoots": [], "projectArtifacts": [] }"#
    XCTAssertThrowsError(try decode(s)) {
      XCTAssertEqual($0 as? CatalogError, .unsupportedSchema(2))
    }
  }

  func test_rejectsDuplicateRuleIDs() {
    let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"X"}]}, {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"Y"}]} ] }"#
    XCTAssertThrowsError(try decode(s)) {
      XCTAssertEqual($0 as? CatalogError, .duplicateRuleID("a"))
    }
  }

  func test_rejectsGlobWithParentTraversal() {
    let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"../escape"}]} ] }"#
    XCTAssertThrowsError(try decode(s)) {
      XCTAssertEqual($0 as? CatalogError, .invalidGlob("../escape"))
    }
  }

  func test_rejectsAbsoluteOrEmptyGlob() {
    for bad in ["/abs", ""] {
      let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"\#(bad)"}]} ] }"#
      XCTAssertThrowsError(try decode(s), "glob \(bad) should be rejected")
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CatalogLoaderTests`
Expected: FAIL — `CatalogLoader`/`CatalogError` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum CatalogError: Error, Equatable {
  case unsupportedSchema(Int)
  case duplicateRuleID(String)
  case invalidGlob(String)
  case missingResource
}

public enum CatalogLoader {
  public static func loadBundled() throws -> Catalog {
    guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json")
    else { throw CatalogError.missingResource }
    return try load(data: Data(contentsOf: url))
  }

  public static func load(data: Data) throws -> Catalog {
    let cat = try JSONDecoder().decode(Catalog.self, from: data)
    guard cat.schemaVersion == 1 else {
      throw CatalogError.unsupportedSchema(cat.schemaVersion)
    }
    var seen = Set<String>()
    for rule in cat.rules {
      guard seen.insert(rule.id).inserted else {
        throw CatalogError.duplicateRuleID(rule.id)
      }
      for spec in rule.paths {
        let g = spec.glob
        guard !g.isEmpty, !g.hasPrefix("/"), !g.split(separator: "/").contains("..")
        else { throw CatalogError.invalidGlob(g) }
      }
    }
    return cat
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CatalogLoaderTests`
Expected: PASS (all five tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GlowKit/CatalogLoader.swift Tests/GlowKitTests/CatalogLoaderTests.swift
git commit -m "feat: add catalog loader with schema/id/glob validation"
```

---

### Task 5: DenyList veto (defense in depth)

**Files:**
- Create: `Sources/GlowKit/DenyList.swift`
- Test: `Tests/GlowKitTests/DenyListTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class DenyListTests: XCTestCase {
  private let home = URL(fileURLWithPath: "/Users/test")

  // Every hostile path must be vetoed.
  func test_vetoesProtectedLocations() {
    let hostile = [
      "/Users/test/Documents/report.txt",
      "/Users/test/Desktop/a",
      "/Users/test/Downloads/x",
      "/Users/test/Pictures/Photos Library.photoslibrary",
      "/Users/test/Movies/film.mov",
      "/Users/test/Library/Mail/box",
      "/Users/test/Library/Keychains/login.keychain-db",
      "/Users/test/Library/Mobile Documents/iCloud~x",
      "/Users/test/Library/Application Support/MobileSync/Backup/dev",
      "/Users/test/.ssh/id_rsa",
      "/Users/test/.gnupg/secring",
      "/Users/test/Library/Caches/secret.kdbx",
      "/Users/test/Library/Caches/app/private.key",
    ]
    for p in hostile {
      XCTAssertTrue(DenyList.vetoes(URL(fileURLWithPath: p), home: home),
                    "should veto \(p)")
    }
  }

  // A base root itself must be vetoed (never nuke all of ~/Library/Caches).
  func test_vetoesBaseRootItself() {
    XCTAssertTrue(DenyList.vetoes(BaseRoot.caches.url(home: home), home: home))
    XCTAssertTrue(DenyList.vetoes(BaseRoot.appSupport.url(home: home), home: home))
  }

  // A genuine cache path must NOT be vetoed.
  func test_allowsGenuineCachePath() {
    let ok = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.app")
    XCTAssertFalse(DenyList.vetoes(ok, home: home))
  }

  func test_vetoesParentTraversal() {
    let p = URL(fileURLWithPath: "/Users/test/Library/Caches/../../Documents")
    XCTAssertTrue(DenyList.vetoes(p, home: home))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DenyListTests`
Expected: FAIL — `DenyList` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum DenyList {
  // Home-relative directories whose contents are never cleanup candidates.
  private static let protectedRelDirs = [
    "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music",
    "Library/Mail", "Library/Messages", "Library/Keychains",
    "Library/Mobile Documents",
    "Library/Application Support/MobileSync",
    ".ssh", ".gnupg", ".aws", ".config/gh", ".kube",
  ]

  // Filenames that signal credentials regardless of location.
  private static let credentialSuffixes = [
    ".kdbx", ".pem", ".key", ".p12", ".netrc", ".pgpass",
  ]
  private static let credentialPrefixes = ["id_rsa", ".env"]

  public static func vetoes(_ url: URL, home: URL) -> Bool {
    // Reject before canonicalization if the literal path tries to traverse up.
    if url.pathComponents.contains("..") { return true }

    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let homePath = home.standardizedFileURL.path

    // Never act on a bare base root.
    for base in BaseRoot.allCases where path == base.url(home: home).path {
      return true
    }

    for rel in protectedRelDirs {
      let prot = home.appending(path: rel).path
      if path == prot || path.hasPrefix(prot + "/") { return true }
    }

    let name = url.lastPathComponent
    if credentialSuffixes.contains(where: { name.hasSuffix($0) }) { return true }
    if credentialPrefixes.contains(where: { name.hasPrefix($0) }) { return true }

    // Anything outside the home dir is out of scope for the user-safe path.
    if path != homePath, !path.hasPrefix(homePath + "/") { return true }

    return false
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DenyListTests`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GlowKit/DenyList.swift Tests/GlowKitTests/DenyListTests.swift
git commit -m "feat: add hardcoded DenyList veto"
```

---

### Task 6: Resolver (glob expansion + veto)

**Files:**
- Create: `Sources/GlowKit/Resolver.swift`
- Test: `Tests/GlowKitTests/ResolverTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class ResolverTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glowkit-\(UUID().uuidString)")
    try mk("Library/Caches/Code/CachedData")
    try mk("Library/Application Support/Brave/Default/Cache")
    try mk("Library/Application Support/Brave/Profile 1/Cache")
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }
  private func mk(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }

  func test_resolvesExactPath() {
    let spec = PathSpec(base: .caches, glob: "Code/CachedData")
    let urls = Resolver.resolve(spec, home: home)
    XCTAssertEqual(urls.map(\.lastPathComponent), ["CachedData"])
  }

  func test_resolvesProfileGlobAcrossProfiles() {
    let spec = PathSpec(base: .appSupport, glob: "Brave/*/Cache")
    let names = Set(Resolver.resolve(spec, home: home).map { $0.path })
    XCTAssertEqual(names.count, 2)   // Default + Profile 1
  }

  func test_skipsNonexistentPaths() {
    let spec = PathSpec(base: .caches, glob: "DoesNotExist")
    XCTAssertTrue(Resolver.resolve(spec, home: home).isEmpty)
  }

  func test_neverReturnsVetoedPaths() throws {
    try mk("Documents/Code")   // would match the glob shape but is protected
    let spec = PathSpec(base: .home, glob: "Documents/Code")
    XCTAssertTrue(Resolver.resolve(spec, home: home).isEmpty)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ResolverTests`
Expected: FAIL — `Resolver` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum Resolver {
  // Expand a spec to existing, non-vetoed URLs under its base root.
  public static func resolve(_ spec: PathSpec, home: URL) -> [URL] {
    let segments = spec.glob.split(separator: "/").map(String.init)
    var frontier = [spec.base.url(home: home)]
    for seg in segments {
      if seg.contains("*") {
        frontier = frontier.flatMap { children($0, matching: seg) }
      } else {
        frontier = frontier.map { $0.appending(path: seg) }
      }
    }
    let fm = FileManager.default
    return frontier.filter { fm.fileExists(atPath: $0.path) }
                   .filter { !DenyList.vetoes($0, home: home) }
  }

  private static func children(_ dir: URL, matching pattern: String) -> [URL] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
    return names
      .filter { fnmatch(pattern, $0, 0) == 0 }
      .map { dir.appending(path: $0) }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ResolverTests`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GlowKit/Resolver.swift Tests/GlowKitTests/ResolverTests.swift
git commit -m "feat: add glob Resolver with deny-list veto"
```

---

### Task 7: Safety-lint over the shipped catalog (CI gate)

**Files:**
- Test: `Tests/GlowKitTests/SafetyLintTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

// Proves no shipped rule can resolve onto protected data, and that the
// deny-list actually fires against planted bait.
final class SafetyLintTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glowlint-\(UUID().uuidString)")
    for bait in ["Documents/keep.txt", "Desktop/keep", ".ssh/id_rsa"] {
      let u = home.appending(path: bait)
      try FileManager.default.createDirectory(
        at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: u)
    }
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  func test_noShippedRuleResolvesOntoProtectedData() throws {
    let cat = try CatalogLoader.loadBundled()
    for rule in cat.rules {
      for spec in rule.paths {
        for url in Resolver.resolve(spec, home: home) {
          XCTAssertFalse(DenyList.vetoes(url, home: home),
                         "rule \(rule.id) resolved a vetoed path: \(url.path)")
        }
      }
    }
  }

  func test_baitFilesAreVetoed() {
    for bait in ["Documents/keep.txt", "Desktop/keep", ".ssh/id_rsa"] {
      XCTAssertTrue(DenyList.vetoes(home.appending(path: bait), home: home))
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SafetyLintTests`
Expected: FAIL — compiles but assertions reference units; if any is missing it fails to build. (If all prior tasks done, this should compile and then PASS — see step 3.)

- [ ] **Step 3: Make it pass**

No new production code needed; this test composes Tasks 4–6. If it fails, the failure is a real safety bug — fix the offending rule in `catalog.json` or `DenyList`, never the assertion.

- [ ] **Step 4: Run the full suite**

Run: `swift test`
Expected: ALL tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/GlowKitTests/SafetyLintTests.swift
git commit -m "test: add safety-lint gate over shipped catalog"
```

---

## Self-review notes

- **Spec coverage (this plan's slice):** symbolic `base` roots (Task 2) ✓;
  catalog schema + validation (Tasks 3–4) ✓; deny-list veto incl. base-root and
  credential protection (Task 5) ✓; allowlist-by-construction via resolve→veto
  (Task 6) ✓; safety-lint CI gate (Task 7) ✓. Risk tiers + default-selection
  rule (Task 1) ✓. Scanner/sizing/trash/restore are **Plan 2** (not here).
- **Type consistency:** `Risk`, `BaseRoot`, `PathSpec.effectiveRisk(ruleRisk:)`,
  `Catalog`, `CatalogLoader.load(data:)/loadBundled()`, `CatalogError`,
  `DenyList.vetoes(_:home:)`, `Resolver.resolve(_:home:)` used identically
  across tasks.
- **Open follow-ups for Plan 2:** the `cascade-excludes-non-safe` selection
  rule and the `zero-network` assertion (spec §2A; safety-lint per §10) are selection/runtime
  concerns tested where that code lands.
