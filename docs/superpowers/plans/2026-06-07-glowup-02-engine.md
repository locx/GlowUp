# GlowUp — Plan 2: Engine (Scan · Size · Trash · Restore · Tree) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the runtime engine on top of Plan 1's safety spine — turn catalog rules into sized, deny-list-clean cleanup candidates, move them to the Trash recoverably, and restore them across relaunch.

**Architecture:** Pure additions to the `GlowKit` library. `Scanner` walks the validated catalog through `Resolver` (which already vetoes via `DenyList`) and emits `Candidate`s, gated by an injected `AppInventory` and the caller's risk tiers. `SizeMeasurer` measures trees concurrently with cancellation. `Trasher` moves candidates to the Trash through an injected `ItemMover` (so tests never touch the real Trash) and `RestoreStore` persists each batch to disk and puts items back, reporting partial failure honestly. `TreeProvider` lazily enumerates non-vetoed children for the Review tree.

**Tech Stack:** Swift 5.9, SwiftPM, macOS 13+, XCTest, Foundation, AppKit (`NSWorkspace`), Swift Concurrency (`TaskGroup`, cooperative cancellation).

**Spec source:** `docs/superpowers/specs/2026-06-06-glowup-spec.md` (§2 safety model, §2A safety-UX rules 3/4/5, §3 architecture, §4 catalog schema, §5 coverage, §10 testing).

---

## Plan set (this is Plan 2 of a planned 7)

1. Foundation — catalog + safety spine ✅ (built; `plans/2026-06-06-glowup-01-foundation.md`)
2. **Engine — Inventory, Scanner, SizeMeasurer, Trasher, RestoreStore, TreeProvider** ← this doc
3. Catalog content — all curated rules; safety-lint green
4. App — SwiftUI (sidebar, radial ring, tree, clean flow, onboarding, restore, menu-bar)
5. CLI `glowup` + legacy bash refactor to catalog
6. Advanced scanners — orphans, projects, workspaceStorage, dup-extensions, large-file report
7. Packaging — entitlements, DMG, notarize CI, Homebrew cask, repo hygiene

Each plan produces working, tested software on its own.

---

## Preconditions (carried from Plan 1)

- Package lives at the **GlowUp repo root** (`Package.swift`, `Sources/GlowKit/…`, `Tests/GlowKitTests/…`). There is **no** `MacLibCleanup` executable target.
- Plan 1 is built and green (24 tests). This plan only **adds** files; it does not modify Plan 1 sources except `Package.swift` (Task 0, to link AppKit).
- **This project is not yet a git repository.** Commit steps are intentionally omitted — each task's completion gate is "tests green." Initialize git and commit when the owner asks.

### Existing API this plan builds on (verbatim from Plan 1 sources)

```swift
public enum Risk: String, Codable, CaseIterable, Sendable { case safe, stateful, privacy, rebuildable; public var isDefaultSelected: Bool }
public enum BaseRoot: String, Codable, CaseIterable, Sendable { case home, appSupport, caches, logs, xcode; public func url(home: URL) -> URL }
public struct PathSpec: Codable, Sendable, Equatable { public let base: BaseRoot; public let glob: String; public let risk: Risk?; public func effectiveRisk(ruleRisk: Risk) -> Risk }
public struct Rule: Codable, Sendable, Identifiable { public let id: String; public let app: String?; public let appBundleID: String?; public let requiresInstalled: Bool?; public let category: String; public let risk: Risk; public let why: String; public let paths: [PathSpec] }
public struct Catalog: Codable, Sendable { public let schemaVersion: Int; public let rules: [Rule]; public let projectRoots: [String]; public let projectArtifacts: [String] }
public enum CatalogLoader { public static func loadBundled() throws -> Catalog; public static func load(data: Data) throws -> Catalog }
public enum DenyList { public static func vetoes(_ url: URL, home: URL) -> Bool }
public enum Resolver { public static func resolve(_ spec: PathSpec, home: URL) -> [URL] }
```

---

## File structure (this plan)

- Modify: `Package.swift` — link `AppKit` to the `GlowKit` target (for `NSWorkspace`)
- Create: `Sources/GlowKit/Models/Candidate.swift` — one scan result
- Create: `Sources/GlowKit/Models/TrashedItem.swift` — `TrashedItem` + `CleanupBatch`
- Create: `Sources/GlowKit/Inventory.swift` — `AppInventory` protocol + `SystemInventory`
- Create: `Sources/GlowKit/Scanner.swift` — catalog → `[Candidate]`
- Create: `Sources/GlowKit/SizeMeasurer.swift` — concurrent, cancellable tree sizing
- Create: `Sources/GlowKit/Trasher.swift` — `ItemMover` protocol + `SystemMover` + `Trasher`
- Create: `Sources/GlowKit/RestoreStore.swift` — persisted history + put-back
- Create: `Sources/GlowKit/TreeProvider.swift` — lazy, veto-filtered children
- Create: `Tests/GlowKitTests/{Candidate,Inventory,Scanner,SizeMeasurer,Trasher,RestoreStore,TreeProvider}Tests.swift`

---

### Task 0: Link AppKit to the GlowKit target

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add the AppKit linker setting to the `GlowKit` target**

In `Package.swift`, change the `GlowKit` target so it links AppKit (needed by `SystemInventory` for `NSWorkspace`). The target becomes:

```swift
.target(
  name: "GlowKit",
  resources: [.copy("Resources/catalog.json")],
  linkerSettings: [.linkedFramework("AppKit")]
),
```

Leave the `GlowKitTests` target and the `GlowKit` library product unchanged.

- [ ] **Step 2: Verify the package still builds and Plan 1 stays green**

Run: `swift test`
Expected: builds; the existing 24 Plan-1 tests still PASS (no behavior change).

---

### Task 1: Candidate model

A `Candidate` is one resolved, deny-list-clean cleanup target with the metadata the UI/CLI need. Size is deliberately **not** part of it — sizing is a separate concern (Task 4) so a candidate is cheap to produce while scanning streams.

**Files:**
- Create: `Sources/GlowKit/Models/Candidate.swift`
- Test: `Tests/GlowKitTests/CandidateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class CandidateTests: XCTestCase {
  func test_idIsStableForRuleAndPath() {
    let url = URL(fileURLWithPath: "/Users/test/Library/Caches/Code/CachedData")
    let a = Candidate(ruleID: "vscode.caches", app: "Visual Studio Code",
                      category: "appCaches", risk: .safe, why: "w", url: url)
    let b = Candidate(ruleID: "vscode.caches", app: "Visual Studio Code",
                      category: "appCaches", risk: .safe, why: "w", url: url)
    XCTAssertEqual(a.id, b.id)
    XCTAssertEqual(a, b)
  }

  func test_idDiffersByPath() {
    let u1 = URL(fileURLWithPath: "/Users/test/Library/Caches/A")
    let u2 = URL(fileURLWithPath: "/Users/test/Library/Caches/B")
    let a = Candidate(ruleID: "r", app: nil, category: "c", risk: .safe, why: "w", url: u1)
    let b = Candidate(ruleID: "r", app: nil, category: "c", risk: .safe, why: "w", url: u2)
    XCTAssertNotEqual(a.id, b.id)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CandidateTests`
Expected: FAIL — `Candidate` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct Candidate: Sendable, Identifiable, Equatable {
  public let ruleID: String
  public let app: String?
  public let category: String
  public let risk: Risk
  public let why: String
  public let url: URL

  // Stable across runs so selection/restore can key on it.
  public var id: String { "\(ruleID)\u{0}\(url.path)" }

  public init(ruleID: String, app: String?, category: String,
              risk: Risk, why: String, url: URL) {
    self.ruleID = ruleID; self.app = app; self.category = category
    self.risk = risk; self.why = why; self.url = url
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CandidateTests`
Expected: PASS.

---

### Task 2: Inventory (installed-app detection)

`Scanner` must honor `requiresInstalled` without coupling tests to the host's installed apps. An `AppInventory` protocol makes installed-detection injectable; `SystemInventory` is the real `NSWorkspace`-backed implementation. brew/mas/pkg inventory is **out of scope** here (Plan 6 orphan scanning).

**Files:**
- Create: `Sources/GlowKit/Inventory.swift`
- Test: `Tests/GlowKitTests/InventoryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class InventoryTests: XCTestCase {
  func test_fakeInventoryReportsConfiguredBundleIDs() {
    let inv = FakeInventory(installed: ["com.microsoft.VSCode"])
    XCTAssertTrue(inv.isInstalled(bundleID: "com.microsoft.VSCode"))
    XCTAssertFalse(inv.isInstalled(bundleID: "com.unknown.App"))
  }

  func test_systemInventoryDoesNotCrashForUnknownBundleID() {
    // Real lookup of a bundle ID that cannot exist must return false, not throw.
    XCTAssertFalse(SystemInventory().isInstalled(bundleID: "com.glowup.definitely.not.real"))
  }
}

// Test double used here and by ScannerTests.
struct FakeInventory: AppInventory {
  let installed: Set<String>
  func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InventoryTests`
Expected: FAIL — `AppInventory`/`SystemInventory` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import AppKit

public protocol AppInventory: Sendable {
  func isInstalled(bundleID: String) -> Bool
}

public struct SystemInventory: AppInventory {
  public init() {}

  public func isInstalled(bundleID: String) -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter InventoryTests`
Expected: PASS.

---

### Task 3: Scanner (catalog → candidates)

Walks every rule, skips rules whose `requiresInstalled` app is absent, expands each path via `Resolver` (already deny-list-vetoed by construction), and keeps only paths whose **effective** risk is in the caller's requested tiers. Default request is `[.safe]` — matching the spec's default-safe run.

**Files:**
- Create: `Sources/GlowKit/Scanner.swift`
- Test: `Tests/GlowKitTests/ScannerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class ScannerTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-scan-\(UUID().uuidString)")
    try mk("Library/Caches/Code/CachedData")
    try mk("Library/Application Support/Code/WebStorage")
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }
  private func mk(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }

  private func catalog(requiresInstalled: Bool) -> Catalog {
    let rule = Rule(
      id: "vscode.caches", app: "Visual Studio Code",
      appBundleID: "com.microsoft.VSCode",
      requiresInstalled: requiresInstalled, category: "appCaches",
      risk: .safe, why: "Regenerated on next launch.",
      paths: [
        PathSpec(base: .caches, glob: "Code/CachedData"),
        PathSpec(base: .appSupport, glob: "Code/WebStorage", risk: .stateful),
      ])
    return Catalog(schemaVersion: 1, rules: [rule],
                   projectRoots: [], projectArtifacts: [])
  }

  func test_defaultScanReturnsOnlySafeTierPaths() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: false),
                          inventory: FakeInventory(installed: []))
    let found = scanner.scan(home: home)               // default: [.safe]
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["CachedData"])
    XCTAssertEqual(found.first?.risk, .safe)
    XCTAssertEqual(found.first?.app, "Visual Studio Code")
  }

  func test_includingStatefulReturnsBothPaths() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: false),
                          inventory: FakeInventory(installed: []))
    let found = scanner.scan(home: home, includeRisks: [.safe, .stateful])
    XCTAssertEqual(Set(found.map(\.url.lastPathComponent)),
                   ["CachedData", "WebStorage"])
  }

  func test_requiresInstalledSkipsRuleWhenAppAbsent() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: true),
                          inventory: FakeInventory(installed: []))
    XCTAssertTrue(scanner.scan(home: home, includeRisks: Set(Risk.allCases)).isEmpty)
  }

  func test_requiresInstalledKeepsRuleWhenAppPresent() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: true),
                          inventory: FakeInventory(installed: ["com.microsoft.VSCode"]))
    XCTAssertFalse(scanner.scan(home: home).isEmpty)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScannerTests`
Expected: FAIL — `Scanner` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct Scanner {
  private let catalog: Catalog
  private let inventory: AppInventory

  public init(catalog: Catalog, inventory: AppInventory) {
    self.catalog = catalog
    self.inventory = inventory
  }

  // Resolve all rules into candidates whose effective risk is requested.
  public func scan(home: URL, includeRisks: Set<Risk> = [.safe]) -> [Candidate] {
    var out: [Candidate] = []
    for rule in catalog.rules {
      if rule.requiresInstalled == true {
        guard let id = rule.appBundleID, inventory.isInstalled(bundleID: id) else { continue }
      }
      for spec in rule.paths {
        let risk = spec.effectiveRisk(ruleRisk: rule.risk)
        guard includeRisks.contains(risk) else { continue }
        for url in Resolver.resolve(spec, home: home) {
          out.append(Candidate(ruleID: rule.id, app: rule.app,
                               category: rule.category, risk: risk,
                               why: rule.why, url: url))
        }
      }
    }
    return out
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScannerTests`
Expected: PASS (all four tests).

---

### Task 4: SizeMeasurer (concurrent, cancellable)

Measures a file or directory tree in allocated bytes, honoring cooperative cancellation, and measures many URLs concurrently. Allocated size (not logical size) matches what the user actually reclaims.

**Files:**
- Create: `Sources/GlowKit/SizeMeasurer.swift`
- Test: `Tests/GlowKitTests/SizeMeasurerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class SizeMeasurerTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-size-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: root.appending(path: "sub"), withIntermediateDirectories: true)
    try Data(repeating: 0xAB, count: 4096).write(to: root.appending(path: "a.bin"))
    try Data(repeating: 0xCD, count: 4096).write(to: root.appending(path: "sub/b.bin"))
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func test_measuresDirectoryTreeBytes() async {
    let bytes = await SizeMeasurer.size(of: root)
    XCTAssertGreaterThanOrEqual(bytes, 8192)   // two 4 KiB files, allocated
  }

  func test_measuresSingleFile() async {
    let bytes = await SizeMeasurer.size(of: root.appending(path: "a.bin"))
    XCTAssertGreaterThanOrEqual(bytes, 4096)
  }

  func test_missingPathIsZero() async {
    let bytes = await SizeMeasurer.size(of: root.appending(path: "nope"))
    XCTAssertEqual(bytes, 0)
  }

  func test_measureManyReturnsPerURLSizes() async {
    let urls = [root.appending(path: "a.bin"), root.appending(path: "sub/b.bin")]
    let sizes = await SizeMeasurer.measure(urls)
    XCTAssertEqual(sizes.count, 2)
    XCTAssertGreaterThanOrEqual(sizes[urls[0]] ?? 0, 4096)
    XCTAssertGreaterThanOrEqual(sizes[urls[1]] ?? 0, 4096)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SizeMeasurerTests`
Expected: FAIL — `SizeMeasurer` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum SizeMeasurer {
  // Allocated bytes of a file or directory tree; returns early if cancelled.
  public static func size(of url: URL) async -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
    if !isDir.boolValue { return allocated(url) }

    let keys: Set<URLResourceKey> = [.isRegularFileKey,
                                     .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
    guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
    var total: Int64 = 0
    for case let child as URL in en {
      if Task.isCancelled { return total }
      total += allocated(child)
    }
    return total
  }

  // Measure many trees concurrently; one entry per input URL.
  public static func measure(_ urls: [URL]) async -> [URL: Int64] {
    await withTaskGroup(of: (URL, Int64).self) { group in
      for url in urls { group.addTask { (url, await size(of: url)) } }
      var out: [URL: Int64] = [:]
      for await (url, bytes) in group { out[url] = bytes }
      return out
    }
  }

  private static func allocated(_ url: URL) -> Int64 {
    let v = try? url.resourceValues(
      forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
    return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SizeMeasurerTests`
Expected: PASS (all four tests).

---

### Task 5: Trasher (recoverable delete via injected mover)

Moves candidates to the Trash. The move is abstracted behind `ItemMover` so tests use a fake that relocates into a temp "trash" directory — the real Trash is never touched in CI. Each success yields a `TrashedItem` (original + trashed path) for restore; failures are returned, never thrown away (spec §2A rule 4: honest partial failure).

**Files:**
- Create: `Sources/GlowKit/Models/TrashedItem.swift`
- Create: `Sources/GlowKit/Trasher.swift`
- Test: `Tests/GlowKitTests/TrasherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class TrasherTests: XCTestCase {
  private var work: URL!
  private var bin: URL!     // stand-in trash directory

  override func setUpWithError() throws {
    work = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-trash-\(UUID().uuidString)")
    bin = work.appending(path: "_bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: work)
  }
  private func makeFile(_ name: String) throws -> URL {
    let u = work.appending(path: name)
    try Data("x".utf8).write(to: u)
    return u
  }

  func test_trashesFilesAndReportsTrashedItems() throws {
    let f = try makeFile("a.txt")
    let mover = FakeMover(bin: bin)
    let result = Trasher(mover: mover).trash([f])

    XCTAssertEqual(result.trashed.count, 1)
    XCTAssertTrue(result.failures.isEmpty)
    XCTAssertEqual(result.trashed[0].originalPath, f.path)
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))      // moved out
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.trashed[0].trashedPath))
  }

  func test_reportsFailureForMissingFileButKeepsGoing() throws {
    let good = try makeFile("good.txt")
    let missing = work.appending(path: "missing.txt")
    let result = Trasher(mover: FakeMover(bin: bin)).trash([missing, good])

    XCTAssertEqual(result.trashed.count, 1)
    XCTAssertEqual(result.trashed[0].originalPath, good.path)
    XCTAssertEqual(result.failures.count, 1)
    XCTAssertEqual(result.failures[0].0.path, missing.path)
  }
}

// Moves into a temp directory instead of the real Trash.
struct FakeMover: ItemMover {
  let bin: URL
  func trash(_ url: URL) throws -> URL {
    let dest = bin.appending(path: url.lastPathComponent)
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TrasherTests`
Expected: FAIL — `Trasher`/`ItemMover`/`TrashedItem` not found.

- [ ] **Step 3a: Write the models**

Create `Sources/GlowKit/Models/TrashedItem.swift`:

```swift
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
```

- [ ] **Step 3b: Write the Trasher**

Create `Sources/GlowKit/Trasher.swift`:

```swift
import Foundation

public protocol ItemMover: Sendable {
  // Move to the Trash, returning the resulting trashed location.
  func trash(_ url: URL) throws -> URL
}

public struct SystemMover: ItemMover {
  public init() {}

  public func trash(_ url: URL) throws -> URL {
    var resulting: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    // trashItem populates resultingItemURL on success.
    return resulting! as URL
  }
}

public struct Trasher {
  private let mover: ItemMover

  public init(mover: ItemMover = SystemMover()) { self.mover = mover }

  public func trash(_ urls: [URL]) -> (trashed: [TrashedItem], failures: [(URL, Error)]) {
    var trashed: [TrashedItem] = []
    var failures: [(URL, Error)] = []
    for url in urls {
      do {
        let dest = try mover.trash(url)
        trashed.append(TrashedItem(originalPath: url.path, trashedPath: dest.path))
      } catch {
        failures.append((url, error))
      }
    }
    return (trashed, failures)
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TrasherTests`
Expected: PASS (both tests).

---

### Task 6: RestoreStore (persisted history + put-back)

Persists each cleanup batch as JSON on disk so History and Restore survive relaunch (spec §2A rule 4). `restore` moves each trashed item back to its original path and reports how many succeeded plus per-item failures — never silently. Batches are returned newest-first.

**Files:**
- Create: `Sources/GlowKit/RestoreStore.swift`
- Test: `Tests/GlowKitTests/RestoreStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class RestoreStoreTests: XCTestCase {
  private var dir: URL!
  private var store: URL!

  override func setUpWithError() throws {
    dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-restore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    store = dir.appending(path: "history.json")
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func batch(_ id: String, _ items: [TrashedItem]) -> CleanupBatch {
    CleanupBatch(id: id, date: Date(timeIntervalSince1970: 0), items: items)
  }

  func test_recordedBatchesPersistAndReloadNewestFirst() throws {
    let s1 = RestoreStore(storeURL: store)
    try s1.record(batch("one", []))
    try s1.record(batch("two", []))

    let s2 = RestoreStore(storeURL: store)     // fresh instance = reload from disk
    XCTAssertEqual(s2.batches().map(\.id), ["two", "one"])
  }

  func test_restoreMovesItemsBackAndCountsSuccesses() throws {
    // Simulate trashed state: original gone, trashed copy present.
    let original = dir.appending(path: "doc.txt")
    let trashed = dir.appending(path: "_bin/doc.txt")
    try FileManager.default.createDirectory(
      at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: trashed)

    let item = TrashedItem(originalPath: original.path, trashedPath: trashed.path)
    let s = RestoreStore(storeURL: store)
    let result = s.restore(batch("b", [item]))

    XCTAssertEqual(result.restored, 1)
    XCTAssertTrue(result.failed.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.path))
  }

  func test_restoreReportsPartialFailureWhenTrashEmptied() throws {
    let gonePath = dir.appending(path: "_bin/gone.txt").path   // never created
    let item = TrashedItem(originalPath: dir.appending(path: "gone.txt").path,
                           trashedPath: gonePath)
    let result = RestoreStore(storeURL: store).restore(batch("b", [item]))

    XCTAssertEqual(result.restored, 0)
    XCTAssertEqual(result.failed.count, 1)
    XCTAssertEqual(result.failed[0].0, item)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RestoreStoreTests`
Expected: FAIL — `RestoreStore` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct RestoreStore {
  private let storeURL: URL

  public init(storeURL: URL) { self.storeURL = storeURL }

  // Append a batch; newest entries are returned first by `batches()`.
  public func record(_ batch: CleanupBatch) throws {
    var all = load()
    all.append(batch)
    let data = try JSONEncoder().encode(all)
    try FileManager.default.createDirectory(
      at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: storeURL, options: .atomic)
  }

  public func batches() -> [CleanupBatch] { load().reversed() }

  public func restore(_ batch: CleanupBatch) -> (restored: Int, failed: [(TrashedItem, Error)]) {
    let fm = FileManager.default
    var restored = 0
    var failed: [(TrashedItem, Error)] = []
    for item in batch.items {
      let from = URL(fileURLWithPath: item.trashedPath)
      let to = URL(fileURLWithPath: item.originalPath)
      do {
        try fm.createDirectory(at: to.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try fm.moveItem(at: from, to: to)
        restored += 1
      } catch {
        failed.append((item, error))
      }
    }
    return (restored, failed)
  }

  private func load() -> [CleanupBatch] {
    guard let data = try? Data(contentsOf: storeURL),
          let batches = try? JSONDecoder().decode([CleanupBatch].self, from: data)
    else { return [] }
    return batches
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RestoreStoreTests`
Expected: PASS (all four tests).

---

### Task 7: TreeProvider (lazy, veto-filtered children)

Backs the Review tree's lazy disclosure (spec §8): given a directory, return its immediate children as nodes, excluding anything the `DenyList` vetoes. Sizes are intentionally not computed here — the UI fetches them lazily via `SizeMeasurer` so opening a node is instant.

**Files:**
- Create: `Sources/GlowKit/TreeProvider.swift`
- Test: `Tests/GlowKitTests/TreeProviderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class TreeProviderTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-tree-\(UUID().uuidString)")
    try mk("Library/Caches/App/sub")
    try Data("x".utf8).write(to: home.appending(path: "Library/Caches/App/file.txt"))
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }
  private func mk(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }

  func test_listsImmediateChildrenWithDirFlag() {
    let dir = home.appending(path: "Library/Caches/App")
    let nodes = TreeProvider.children(of: dir, home: home)
    let byName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0) })
    XCTAssertEqual(Set(byName.keys), ["sub", "file.txt"])
    XCTAssertTrue(byName["sub"]!.isDirectory)
    XCTAssertFalse(byName["file.txt"]!.isDirectory)
  }

  func test_excludesVetoedChildren() throws {
    // A child that resolves to a protected location must not appear.
    try mk("Documents")
    let link = home.appending(path: "Library/Caches/App/docs")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: home.appending(path: "Documents"))
    let dir = home.appending(path: "Library/Caches/App")
    let names = TreeProvider.children(of: dir, home: home).map(\.name)
    XCTAssertFalse(names.contains("docs"))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TreeProviderTests`
Expected: FAIL — `TreeProvider`/`TreeNode` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct TreeNode: Sendable, Identifiable, Equatable {
  public let url: URL
  public let name: String
  public let isDirectory: Bool

  public var id: String { url.path }

  public init(url: URL, name: String, isDirectory: Bool) {
    self.url = url; self.name = name; self.isDirectory = isDirectory
  }
}

public enum TreeProvider {
  // Immediate, non-vetoed children of a directory (one level; lazy by design).
  public static func children(of url: URL, home: URL) -> [TreeNode] {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isDirectoryKey]
    guard let entries = try? fm.contentsOfDirectory(
      at: url, includingPropertiesForKeys: keys) else { return [] }
    return entries
      .filter { !DenyList.vetoes($0, home: home) }
      .map { child in
        let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return TreeNode(url: child, name: child.lastPathComponent, isDirectory: isDir)
      }
      .sorted { $0.name < $1.name }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TreeProviderTests`
Expected: PASS (both tests).

---

### Task 8: Full-suite green

- [ ] **Step 1: Run the entire suite**

Run: `swift test`
Expected: ALL tests PASS — Plan 1's 24 plus this plan's additions, with zero regressions. The Plan-1 `SafetyLintTests` must still pass (the engine adds no catalog rules, so the safety invariant is unchanged).

---

## Self-review notes

- **Spec coverage (this plan's slice):** Inventory/installed-detection (Task 2) ✓; catalog→candidates honoring risk tiers + `requiresInstalled` (Task 3) ✓ — default-safe scan matches spec §6; concurrent cancellable sizing in allocated bytes (Task 4) ✓; Trash-only recoverable delete with honest partial failure (Task 5, spec §2A rule 4) ✓; persisted, relaunch-surviving restore (Task 6, spec §2A rule 4) ✓; lazy veto-filtered tree for Review (Task 7, spec §8) ✓.
- **Safety is preserved, not re-implemented:** every path that reaches a `Candidate` came through `Resolver.resolve`, which already applies `DenyList.vetoes`. `TreeProvider` independently re-applies the veto so a lazily-disclosed child can never surface a protected path. No deny-list logic is duplicated or weakened.
- **Testability without side effects:** `AppInventory` and `ItemMover` are injected so `Scanner`/`Trasher` tests never depend on installed apps or move anything into the real Trash. `SystemInventory`/`SystemMover` are the thin real implementations, exercised only by a non-destructive smoke assertion.
- **Type consistency:** `Candidate`, `TrashedItem`, `CleanupBatch`, `AppInventory.isInstalled(bundleID:)`, `Scanner.scan(home:includeRisks:)`, `SizeMeasurer.size(of:)/measure(_:)`, `ItemMover.trash(_:)`, `Trasher.trash(_:)`, `RestoreStore.record(_:)/batches()/restore(_:)`, `TreeProvider.children(of:home:)` are referenced identically across tasks.
- **Deferred (correctly not here):** real catalog rules (Plan 3); cascade-excludes-non-safe selection + zero-network CI assertion (selection/runtime — Plan 4); orphan/project/large-file scanners and brew/mas/pkg inventory (Plan 6); Empty-Trash action and before/after free-space UI (Plan 4).
```