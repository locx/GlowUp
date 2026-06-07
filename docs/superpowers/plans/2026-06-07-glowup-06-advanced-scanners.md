# GlowUp — Plan 6: Advanced Scanners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the default-off advanced scanners — heuristic library orphans, project artifacts, VSCode workspaceStorage orphans, duplicate extension versions, and a report-only large/old-file lister — all in `GlowKit`, fully tested.

**Architecture:** Five new stateless scanners in `GlowKit`, each returning Plan-2 `Candidate`s (so the app/CLI can list and act on them under explicit opt-in) — except the large-file lister, which returns a new **report-only** `Report` type with no actionable surface (spec §2A rule 1). Every actionable scanner re-applies `DenyList.vetoes` so it can never surface a protected path. Heuristic orphans are honest guesswork and stay non-safe (off by default, spec §2A rule 7). **New files only** — no changes to existing sources or `Package.swift` (SwiftPM auto-discovers new files in the `GlowKit` target).

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, Foundation.

**Spec source:** `docs/superpowers/specs/2026-06-06-glowup-spec.md` (§2A rules 1 & 7, §4 categories, §5 coverage: orphans/projects/workspaceStorage/dup-extensions/large-file report).

---

## Plan set (this is Plan 6 of a planned 7)

1. Foundation ✅ · 2. Engine ✅ · 3. Catalog content ✅ · 4. App ✅ · 5. CLI ✅ · **6. Advanced scanners ← this doc** · 7. Packaging

---

## Preconditions

- Plans 1–5 built and green (71 tests). This plan adds **only new files** under `Sources/GlowKit/` and `Tests/GlowKitTests/`. No `Package.swift` edit, no existing-source edits.
- **No git** (build-only; gate = tests green).
- GlowKit API in use: `Candidate(ruleID:app:category:risk:why:url:)`, `Risk`, `DenyList.vetoes(_:home:)`, `BaseRoot`.
- **Safety:** every actionable scanner filters through `DenyList.vetoes`. Orphan/project/workspace/dup candidates are `risk: .rebuildable` (never `.safe`) so they are never default-selected. The large-file lister returns `Report` (no checkbox by type) and skips hidden files so it never lists credential dotfiles (spec §A6 "Protected files are never listed here.").

---

## File structure (this plan)

- Create: `Sources/GlowKit/Models/Report.swift` — report-only item
- Create: `Sources/GlowKit/OrphanScanner.swift`
- Create: `Sources/GlowKit/ProjectScanner.swift`
- Create: `Sources/GlowKit/WorkspaceStorageScanner.swift`
- Create: `Sources/GlowKit/DuplicateExtensionScanner.swift`
- Create: `Sources/GlowKit/LargeFileReporter.swift`
- Create: `Tests/GlowKitTests/{OrphanScanner,ProjectScanner,WorkspaceStorageScanner,DuplicateExtensionScanner,LargeFileReporter}Tests.swift`

---

### Task 1: Report model

**Files:**
- Create: `Sources/GlowKit/Models/Report.swift`
- Test: `Tests/GlowKitTests/LargeFileReporterTests.swift` (added in Task 5; Report is exercised there)

- [ ] **Step 1: Write the implementation** (no standalone test; covered via LargeFileReporter)

```swift
import Foundation

// Report-only item: surfaced for the user to act on themselves, never trashed by the app.
public struct Report: Sendable, Identifiable, Equatable {
  public let url: URL
  public let bytes: Int64
  public var id: String { url.path }

  public init(url: URL, bytes: Int64) {
    self.url = url; self.bytes = bytes
  }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles.

---

### Task 2: OrphanScanner (honest guesswork)

Flags top-level `~/Library/Application Support` and `~/Library/Caches` entries whose name is not in a caller-supplied "known/owned" set — possible leftovers from uninstalled apps. Deny-list-filtered; non-safe so never auto-selected.

**Files:**
- Create: `Sources/GlowKit/OrphanScanner.swift`
- Test: `Tests/GlowKitTests/OrphanScannerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class OrphanScannerTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-orphan-\(UUID().uuidString)")
    for rel in ["Library/Application Support/KnownApp",
                "Library/Application Support/OldLeftover",
                "Library/Caches/com.known.app"] {
      try FileManager.default.createDirectory(
        at: home.appending(path: rel), withIntermediateDirectories: true)
    }
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  func test_flagsUnknownEntriesOnly() {
    let found = OrphanScanner.scan(home: home, known: ["KnownApp", "com.known.app"])
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["OldLeftover"])
    XCTAssertEqual(found.first?.category, "libraryOrphans")
    XCTAssertNotEqual(found.first?.risk, .safe)        // never default-selected
  }

  func test_returnsEmptyWhenAllKnown() {
    let found = OrphanScanner.scan(home: home,
      known: ["KnownApp", "OldLeftover", "com.known.app"])
    XCTAssertTrue(found.isEmpty)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OrphanScannerTests`
Expected: FAIL — `OrphanScanner` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum OrphanScanner {
  // Possible leftovers: appSupport/caches children not in the known-owned set.
  public static func scan(home: URL, known: Set<String>) -> [Candidate] {
    let fm = FileManager.default
    var out: [Candidate] = []
    for base in [BaseRoot.appSupport, .caches] {
      let root = base.url(home: home)
      guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
      for name in names where !known.contains(name) && !name.hasPrefix(".") {
        let url = root.appending(path: name)
        guard !DenyList.vetoes(url, home: home) else { continue }
        out.append(Candidate(ruleID: "orphan.\(name)", app: name,
                             category: "libraryOrphans", risk: .rebuildable,
                             why: "Possible leftover — owning app not found.", url: url))
      }
    }
    return out.sorted { $0.url.path < $1.url.path }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OrphanScannerTests`
Expected: PASS.

---

### Task 3: ProjectScanner (rebuildable artifacts under project roots)

Walks each project root (bounded depth) for artifact directories (`node_modules`, `.venv`, …) and returns them as `rebuildable` candidates; does not descend into a matched artifact.

**Files:**
- Create: `Sources/GlowKit/ProjectScanner.swift`
- Test: `Tests/GlowKitTests/ProjectScannerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class ProjectScannerTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-proj-\(UUID().uuidString)")
    for rel in ["app/node_modules/pkg", "app/src", "app/api/.venv/lib", "app/keep"] {
      try FileManager.default.createDirectory(
        at: root.appending(path: rel), withIntermediateDirectories: true)
    }
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  func test_findsArtifactDirsNotPlainDirs() {
    let found = ProjectScanner.scan(roots: [root],
      artifacts: ["node_modules", ".venv"], home: root)
    XCTAssertEqual(Set(found.map(\.url.lastPathComponent)), ["node_modules", ".venv"])
    XCTAssertEqual(found.first?.risk, .rebuildable)
    XCTAssertEqual(found.first?.category, "projectArtifacts")
  }

  func test_doesNotDescendIntoMatchedArtifact() {
    // 'pkg' lives inside node_modules and must not be reported separately.
    let found = ProjectScanner.scan(roots: [root], artifacts: ["node_modules"], home: root)
    XCTAssertFalse(found.contains { $0.url.lastPathComponent == "pkg" })
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectScannerTests`
Expected: FAIL — `ProjectScanner` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum ProjectScanner {
  // Artifact dirs under project roots; does not recurse into a matched artifact.
  public static func scan(roots: [URL], artifacts: Set<String>,
                          home: URL, maxDepth: Int = 6) -> [Candidate] {
    let fm = FileManager.default
    var out: [Candidate] = []
    for root in roots { walk(root, depth: 0, fm: fm, artifacts: artifacts,
                              home: home, maxDepth: maxDepth, out: &out) }
    return out.sorted { $0.url.path < $1.url.path }
  }

  private static func walk(_ dir: URL, depth: Int, fm: FileManager,
                           artifacts: Set<String>, home: URL, maxDepth: Int,
                           out: inout [Candidate]) {
    guard depth <= maxDepth,
          let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
    for entry in entries {
      let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      guard isDir else { continue }
      if artifacts.contains(entry.lastPathComponent) {
        guard !DenyList.vetoes(entry, home: home) else { continue }
        out.append(Candidate(ruleID: "project.\(entry.lastPathComponent)", app: nil,
                             category: "projectArtifacts", risk: .rebuildable,
                             why: "Rebuilt from source on demand.", url: entry))
      } else {
        walk(entry, depth: depth + 1, fm: fm, artifacts: artifacts,
             home: home, maxDepth: maxDepth, out: &out)
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectScannerTests`
Expected: PASS.

---

### Task 4: WorkspaceStorageScanner (VSCode dangling workspaces)

Flags `Code/User/workspaceStorage/*` entries whose `workspace.json` references a folder that no longer exists.

**Files:**
- Create: `Sources/GlowKit/WorkspaceStorageScanner.swift`
- Test: `Tests/GlowKitTests/WorkspaceStorageScannerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class WorkspaceStorageScannerTests: XCTestCase {
  private var home: URL!
  private var storage: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-ws-\(UUID().uuidString)")
    storage = home.appending(path: "Library/Application Support/Code/User/workspaceStorage")
    try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  private func entry(_ id: String, folder: URL) throws {
    let dir = storage.appending(path: id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"{"folder":"\#(folder.absoluteString)"}"#
    try Data(json.utf8).write(to: dir.appending(path: "workspace.json"))
  }

  func test_flagsOnlyDanglingWorkspaces() throws {
    let live = home.appending(path: "projects/live")
    try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
    try entry("aaa", folder: live)                                   // exists
    try entry("bbb", folder: home.appending(path: "projects/gone")) // missing

    let found = WorkspaceStorageScanner.scan(home: home)
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["bbb"])
    XCTAssertEqual(found.first?.category, "workspaceOrphans")
    XCTAssertNotEqual(found.first?.risk, .safe)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceStorageScannerTests`
Expected: FAIL — `WorkspaceStorageScanner` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum WorkspaceStorageScanner {
  // VSCode workspaceStorage entries whose referenced folder no longer exists.
  public static func scan(home: URL) -> [Candidate] {
    let fm = FileManager.default
    let storage = BaseRoot.appSupport.url(home: home)
      .appending(path: "Code/User/workspaceStorage")
    guard let ids = try? fm.contentsOfDirectory(atPath: storage.path) else { return [] }

    var out: [Candidate] = []
    for id in ids where !id.hasPrefix(".") {
      let dir = storage.appending(path: id)
      let meta = dir.appending(path: "workspace.json")
      guard let data = try? Data(contentsOf: meta),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let folder = obj["folder"] as? String,
            let folderURL = URL(string: folder), folderURL.isFileURL
      else { continue }
      if !fm.fileExists(atPath: folderURL.path), !DenyList.vetoes(dir, home: home) {
        out.append(Candidate(ruleID: "workspace.\(id)", app: "Visual Studio Code",
                             category: "workspaceOrphans", risk: .rebuildable,
                             why: "Workspace folder no longer exists.", url: dir))
      }
    }
    return out.sorted { $0.url.path < $1.url.path }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkspaceStorageScannerTests`
Expected: PASS.

---

### Task 5: DuplicateExtensionScanner (older VSCode extension versions)

Groups `~/.vscode/extensions/<publisher>.<name>-<version>` by extension and flags every version below the highest.

**Files:**
- Create: `Sources/GlowKit/DuplicateExtensionScanner.swift`
- Test: `Tests/GlowKitTests/DuplicateExtensionScannerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class DuplicateExtensionScannerTests: XCTestCase {
  private var home: URL!
  private var ext: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-ext-\(UUID().uuidString)")
    ext = home.appending(path: ".vscode/extensions")
    for name in ["pub.tool-1.0.0", "pub.tool-1.2.0", "pub.tool-1.10.0",
                 "other.ext-2.0.0"] {
      try FileManager.default.createDirectory(
        at: ext.appending(path: name), withIntermediateDirectories: true)
    }
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  func test_flagsOlderVersionsKeepingHighest() {
    let found = DuplicateExtensionScanner.scan(home: home)
    // 1.10.0 is highest; 1.0.0 and 1.2.0 flagged; the singleton other.ext kept.
    XCTAssertEqual(Set(found.map(\.url.lastPathComponent)),
                   ["pub.tool-1.0.0", "pub.tool-1.2.0"])
    XCTAssertEqual(found.first?.category, "duplicateExtensions")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DuplicateExtensionScannerTests`
Expected: FAIL — `DuplicateExtensionScanner` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum DuplicateExtensionScanner {
  // Older versions of the same VSCode extension under ~/.vscode/extensions.
  public static func scan(home: URL) -> [Candidate] {
    let fm = FileManager.default
    let dir = home.appending(path: ".vscode/extensions")
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }

    // Group dir names by extension id (publisher.name), keeping each version.
    var groups: [String: [(version: [Int], name: String)]] = [:]
    for name in names where !name.hasPrefix(".") {
      guard let dash = name.lastIndex(of: "-") else { continue }
      let ext = String(name[..<dash])
      let version = name[name.index(after: dash)...]
        .split(separator: ".").map { Int($0) ?? 0 }
      groups[ext, default: []].append((version, name))
    }

    var out: [Candidate] = []
    for (ext, versions) in groups where versions.count > 1 {
      let keep = versions.max { lexLess($0.version, $1.version) }!.name
      for v in versions where v.name != keep {
        let url = dir.appending(path: v.name)
        guard !DenyList.vetoes(url, home: home) else { continue }
        out.append(Candidate(ruleID: "dupext.\(ext)", app: "Visual Studio Code",
                             category: "duplicateExtensions", risk: .rebuildable,
                             why: "Superseded by a newer installed version.", url: url))
      }
    }
    return out.sorted { $0.url.path < $1.url.path }
  }

  // Component-wise numeric version compare (1.10.0 > 1.2.0).
  private static func lexLess(_ a: [Int], _ b: [Int]) -> Bool {
    for i in 0..<max(a.count, b.count) {
      let l = i < a.count ? a[i] : 0, r = i < b.count ? b[i] : 0
      if l != r { return l < r }
    }
    return false
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DuplicateExtensionScannerTests`
Expected: PASS.

---

### Task 6: LargeFileReporter (report-only)

Lists files at or above a size threshold under the given directories. Returns `Report` (no actionable surface, spec §2A rule 1) and skips hidden files so credentials are never listed (spec §A6).

**Files:**
- Create: `Sources/GlowKit/LargeFileReporter.swift`
- Test: `Tests/GlowKitTests/LargeFileReporterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

final class LargeFileReporterTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-large-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 200_000).write(to: dir.appending(path: "big.bin"))
    try Data(repeating: 0, count: 10).write(to: dir.appending(path: "small.bin"))
    try Data(repeating: 0, count: 200_000).write(to: dir.appending(path: ".secret"))
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

  func test_reportsOnlyLargeNonHiddenFiles() {
    let reports = LargeFileReporter.scan(dirs: [dir], minBytes: 100_000)
    XCTAssertEqual(reports.map(\.url.lastPathComponent), ["big.bin"])
    XCTAssertGreaterThanOrEqual(reports.first?.bytes ?? 0, 100_000)
  }

  func test_emptyWhenNothingLarge() {
    XCTAssertTrue(LargeFileReporter.scan(dirs: [dir], minBytes: 10_000_000).isEmpty)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LargeFileReporterTests`
Expected: FAIL — `LargeFileReporter` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum LargeFileReporter {
  // Report-only: large files for the user to review; hidden files are never listed.
  public static func scan(dirs: [URL], minBytes: Int64) -> [Report] {
    let fm = FileManager.default
    var out: [Report] = []
    for dir in dirs {
      guard let entries = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
      for url in entries where !url.lastPathComponent.hasPrefix(".") {
        let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard v?.isRegularFile == true, let size = v?.fileSize, Int64(size) >= minBytes
        else { continue }
        out.append(Report(url: url, bytes: Int64(size)))
      }
    }
    return out.sorted { $0.bytes > $1.bytes }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LargeFileReporterTests`
Expected: PASS.

---

### Task 7: Full-suite green

- [ ] **Step 1: Run tests and build**

Run: `swift test`
Expected: ALL pass — Plans 1–5 plus the five new scanner suites. The Plan-1 `SafetyLintTests` is unaffected (no catalog change).

Run: `swift build`
Expected: clean build of all targets.

---

## Self-review notes

- **Spec coverage (§5 advanced):** heuristic library orphans (OrphanScanner) ✓; project artifacts under roots (ProjectScanner) ✓; VSCode workspaceStorage orphans (WorkspaceStorageScanner) ✓; duplicate extension versions (DuplicateExtensionScanner) ✓; report-only large/old files (LargeFileReporter) ✓.
- **Safety & default-off discipline:** all actionable scanners re-apply `DenyList.vetoes`; every candidate is `risk: .rebuildable` (never `.safe`), so the app's default-safe selection never picks them up (spec §2A rule 7 — orphans stay deselected). Categories use the spec §4 advanced set (`libraryOrphans`, `projectArtifacts`, `workspaceOrphans`, `duplicateExtensions`).
- **Report-only is un-actionable by type:** `LargeFileReporter` returns `Report`, which has no selection/clean affordance anywhere — structurally enforcing spec §2A rule 1. It skips hidden files so credential dotfiles are never listed (spec §A6).
- **New files only:** nothing in this plan edits an existing source or `Package.swift`; SwiftPM auto-discovers the new `GlowKit` files. This keeps the safety spine and engine untouched.
- **Type consistency:** uses Plan-1/2 `Candidate(ruleID:app:category:risk:why:url:)`, `Risk`, `DenyList.vetoes(_:home:)`, `BaseRoot`; new `Report` mirrors `Candidate`'s `Identifiable`/`Equatable` shape.
- **Wiring deferred:** surfacing these in the app's Advanced/Reports views and the CLI `--advanced`/`--projects` flags is a thin follow-up over these pure scanners (UI is manual-verify; CLI `--projects` currently returns the honest deferral from Plan 5). The engine capability lands and is tested here.
```