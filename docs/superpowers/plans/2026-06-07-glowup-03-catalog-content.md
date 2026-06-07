# GlowUp — Plan 3: Catalog Content (Curated Rules) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single seed rule with the full curated, risk-tiered cleanup catalog (browsers, known apps, dev caches, Xcode, user-owned system logs), and prove the whole catalog is well-formed and safe via lint tests.

**Architecture:** Pure data + a small loader hardening. The catalog stays a single validated JSON resource consumed by Plan 1's `CatalogLoader`/`Resolver`/`DenyList`. No new engine code — every shipped path is expressed as a symbolic `base` + single-segment-`*` glob so the existing safety spine vetoes anything that would escape. One loader change rejects `**` (spec §4: no `**` recursion in v1).

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, JSON.

**Spec source:** `docs/superpowers/specs/2026-06-06-glowup-spec.md` (§4 catalog schema, §5 coverage + risk tiers, §10 safety-lint).

---

## Plan set (this is Plan 3 of a planned 7)

1. Foundation ✅ · 2. Engine ✅ · **3. Catalog content ← this doc** · 4. App · 5. CLI · 6. Advanced scanners · 7. Packaging

---

## Preconditions

- Plans 1–2 built and green (45 tests). This plan changes `catalog.json`, hardens `CatalogLoader`, and adds tests. No engine/UI code.
- Allowed `base` roots (Plan 1 `BaseRoot`): `home`, `appSupport` (`~/Library/Application Support`), `caches` (`~/Library/Caches`), `logs` (`~/Library/Logs`), `xcode` (`~/Library/Developer/Xcode`).
- `DenyList` protects (never target these): `Documents`, `Desktop`, `Downloads`, `Pictures`, `Movies`, `Music`, `Library/Mail`, `Library/Messages`, `Library/Keychains`, `Library/Mobile Documents`, `Library/Application Support/MobileSync`, `.ssh`, `.gnupg`, `.aws`, `.config/gh`, `.kube`, and credential-named files. Every rule below avoids these by construction.
- No git (build-only; completion gate = tests green).

---

## File structure (this plan)

- Modify: `Sources/GlowKit/CatalogLoader.swift` — also reject `**` globs
- Modify: `Tests/GlowKitTests/CatalogLoaderTests.swift` — add the `**` rejection test
- Modify: `Sources/GlowKit/Resources/catalog.json` — full curated catalog
- Create: `Tests/GlowKitTests/CatalogContentTests.swift` — content lint over the shipped catalog

---

### Task 1: Reject `**` recursion globs in the loader

Spec §4 forbids `**` in v1. The loader already rejects empty/absolute/`..` globs; add `**`.

**Files:**
- Modify: `Sources/GlowKit/CatalogLoader.swift`
- Modify: `Tests/GlowKitTests/CatalogLoaderTests.swift`

- [ ] **Step 1: Add the failing test** (append to `CatalogLoaderTests`)

```swift
  func test_rejectsDoubleStarGlob() {
    let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"App/**/Cache"}]} ] }"#
    XCTAssertThrowsError(try CatalogLoader.load(data: Data(s.utf8))) {
      XCTAssertEqual($0 as? CatalogError, .invalidGlob("App/**/Cache"))
    }
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CatalogLoaderTests/test_rejectsDoubleStarGlob`
Expected: FAIL — `**` currently passes validation.

- [ ] **Step 3: Harden the loader**

In `CatalogLoader.load(data:)`, extend the per-glob guard so it also rejects any glob containing `**`. The guard becomes:

```swift
        let g = spec.glob
        guard !g.isEmpty, !g.hasPrefix("/"),
              !g.contains("**"),
              !g.split(separator: "/").contains("..")
        else { throw CatalogError.invalidGlob(g) }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CatalogLoaderTests`
Expected: PASS (all prior loader tests + the new one).

---

### Task 2: Write the full curated catalog

Replace `Sources/GlowKit/Resources/catalog.json` **entirely** with the content below. One rule per app/tool; per-path `risk` overrides keep cookies/history (`privacy`) and sessions/local-storage (`stateful`) off the default-safe run. Categories are restricted to the spec §4 display set (`appCaches`, `browserData`, `systemLogs`). `requiresInstalled: true` only where a reliable bundle ID exists.

- [ ] **Step 1: Overwrite `Sources/GlowKit/Resources/catalog.json`**

```json
{
  "schemaVersion": 1,
  "rules": [
    {
      "id": "chrome",
      "app": "Google Chrome",
      "appBundleID": "com.google.Chrome",
      "requiresInstalled": true,
      "category": "browserData",
      "risk": "safe",
      "why": "Browser caches are rebuilt automatically.",
      "paths": [
        { "base": "appSupport", "glob": "Google/Chrome/*/Cache" },
        { "base": "appSupport", "glob": "Google/Chrome/*/Code Cache" },
        { "base": "appSupport", "glob": "Google/Chrome/*/GPUCache" },
        { "base": "appSupport", "glob": "Google/Chrome/*/Service Worker/CacheStorage" },
        { "base": "appSupport", "glob": "Google/Chrome/*/Cookies", "risk": "privacy" },
        { "base": "appSupport", "glob": "Google/Chrome/*/History", "risk": "privacy" },
        { "base": "appSupport", "glob": "Google/Chrome/*/Sessions", "risk": "stateful" },
        { "base": "appSupport", "glob": "Google/Chrome/*/Local Storage", "risk": "stateful" }
      ]
    },
    {
      "id": "brave",
      "app": "Brave Browser",
      "appBundleID": "com.brave.Browser",
      "requiresInstalled": true,
      "category": "browserData",
      "risk": "safe",
      "why": "Browser caches are rebuilt automatically.",
      "paths": [
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/Cache" },
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/Code Cache" },
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/GPUCache" },
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/Service Worker/CacheStorage" },
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/Cookies", "risk": "privacy" },
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/History", "risk": "privacy" },
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/Sessions", "risk": "stateful" },
        { "base": "appSupport", "glob": "BraveSoftware/Brave-Browser/*/Local Storage", "risk": "stateful" }
      ]
    },
    {
      "id": "edge",
      "app": "Microsoft Edge",
      "appBundleID": "com.microsoft.edgemac",
      "requiresInstalled": true,
      "category": "browserData",
      "risk": "safe",
      "why": "Browser caches are rebuilt automatically.",
      "paths": [
        { "base": "appSupport", "glob": "Microsoft Edge/*/Cache" },
        { "base": "appSupport", "glob": "Microsoft Edge/*/Code Cache" },
        { "base": "appSupport", "glob": "Microsoft Edge/*/GPUCache" },
        { "base": "appSupport", "glob": "Microsoft Edge/*/Service Worker/CacheStorage" },
        { "base": "appSupport", "glob": "Microsoft Edge/*/Cookies", "risk": "privacy" },
        { "base": "appSupport", "glob": "Microsoft Edge/*/History", "risk": "privacy" }
      ]
    },
    {
      "id": "firefox",
      "app": "Firefox",
      "appBundleID": "org.mozilla.firefox",
      "requiresInstalled": true,
      "category": "browserData",
      "risk": "safe",
      "why": "Browser caches are rebuilt automatically.",
      "paths": [
        { "base": "appSupport", "glob": "Firefox/Profiles/*/cache2" },
        { "base": "appSupport", "glob": "Firefox/Profiles/*/startupCache" },
        { "base": "appSupport", "glob": "Firefox/Profiles/*/cookies.sqlite", "risk": "privacy" },
        { "base": "appSupport", "glob": "Firefox/Profiles/*/sessionstore-backups", "risk": "stateful" }
      ]
    },
    {
      "id": "vscode",
      "app": "Visual Studio Code",
      "appBundleID": "com.microsoft.VSCode",
      "requiresInstalled": true,
      "category": "appCaches",
      "risk": "safe",
      "why": "Regenerated on next launch.",
      "paths": [
        { "base": "appSupport", "glob": "Code/CachedData" },
        { "base": "appSupport", "glob": "Code/CachedExtensionVSIXs" },
        { "base": "appSupport", "glob": "Code/Crashpad" },
        { "base": "appSupport", "glob": "Code/Cache" },
        { "base": "appSupport", "glob": "Code/Code Cache" },
        { "base": "appSupport", "glob": "Code/GPUCache" },
        { "base": "appSupport", "glob": "Code/WebStorage", "risk": "stateful" }
      ]
    },
    {
      "id": "spotify",
      "app": "Spotify",
      "appBundleID": "com.spotify.client",
      "requiresInstalled": true,
      "category": "appCaches",
      "risk": "safe",
      "why": "Streaming cache is re-downloaded on demand.",
      "paths": [
        { "base": "appSupport", "glob": "Spotify/PersistentCache" },
        { "base": "caches", "glob": "com.spotify.client" }
      ]
    },
    {
      "id": "slack",
      "app": "Slack",
      "appBundleID": "com.tinyspeck.slackmacgap",
      "requiresInstalled": true,
      "category": "appCaches",
      "risk": "safe",
      "why": "Regenerated on next launch.",
      "paths": [
        { "base": "appSupport", "glob": "Slack/Cache" },
        { "base": "appSupport", "glob": "Slack/Code Cache" },
        { "base": "appSupport", "glob": "Slack/GPUCache" },
        { "base": "appSupport", "glob": "Slack/Service Worker/CacheStorage" }
      ]
    },
    {
      "id": "discord",
      "app": "Discord",
      "appBundleID": "com.hnc.Discord",
      "requiresInstalled": true,
      "category": "appCaches",
      "risk": "safe",
      "why": "Regenerated on next launch.",
      "paths": [
        { "base": "appSupport", "glob": "discord/Cache" },
        { "base": "appSupport", "glob": "discord/Code Cache" },
        { "base": "appSupport", "glob": "discord/GPUCache" }
      ]
    },
    {
      "id": "teams",
      "app": "Microsoft Teams",
      "appBundleID": "com.microsoft.teams2",
      "requiresInstalled": true,
      "category": "appCaches",
      "risk": "safe",
      "why": "Regenerated on next launch.",
      "paths": [
        { "base": "appSupport", "glob": "Microsoft/Teams/Cache" },
        { "base": "appSupport", "glob": "Microsoft/Teams/Code Cache" },
        { "base": "appSupport", "glob": "Microsoft/Teams/GPUCache" },
        { "base": "appSupport", "glob": "Microsoft/Teams/Service Worker/CacheStorage" }
      ]
    },
    {
      "id": "zoom",
      "app": "Zoom",
      "appBundleID": "us.zoom.xos",
      "requiresInstalled": true,
      "category": "appCaches",
      "risk": "safe",
      "why": "Regenerated on next launch.",
      "paths": [
        { "base": "caches", "glob": "us.zoom.xos" }
      ]
    },
    {
      "id": "dev.huggingface",
      "app": "Hugging Face cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Models re-download on demand.",
      "paths": [ { "base": "home", "glob": ".cache/huggingface" } ]
    },
    {
      "id": "dev.npm",
      "app": "npm cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Package cache is re-fetched on demand.",
      "paths": [ { "base": "home", "glob": ".npm/_cacache" } ]
    },
    {
      "id": "dev.uv",
      "app": "uv cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Package cache is re-fetched on demand.",
      "paths": [ { "base": "caches", "glob": "uv" } ]
    },
    {
      "id": "dev.pnpm",
      "app": "pnpm store",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Package store is re-fetched on demand.",
      "paths": [ { "base": "home", "glob": "Library/pnpm/store" } ]
    },
    {
      "id": "dev.precommit",
      "app": "pre-commit cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Hook environments are rebuilt on demand.",
      "paths": [ { "base": "home", "glob": ".cache/pre-commit" } ]
    },
    {
      "id": "dev.pip",
      "app": "pip cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Wheel cache is re-fetched on demand.",
      "paths": [ { "base": "caches", "glob": "pip" } ]
    },
    {
      "id": "dev.yarn",
      "app": "Yarn cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Package cache is re-fetched on demand.",
      "paths": [ { "base": "caches", "glob": "Yarn" } ]
    },
    {
      "id": "dev.gradle",
      "app": "Gradle cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Build cache is rebuilt on demand.",
      "paths": [ { "base": "home", "glob": ".gradle/caches" } ]
    },
    {
      "id": "dev.cocoapods",
      "app": "CocoaPods cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Pod cache is re-fetched on demand.",
      "paths": [ { "base": "caches", "glob": "CocoaPods" } ]
    },
    {
      "id": "dev.cargo",
      "app": "Cargo registry cache",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Crate cache is re-fetched on demand.",
      "paths": [ { "base": "home", "glob": ".cargo/registry/cache" } ]
    },
    {
      "id": "xcode.deriveddata",
      "app": "Xcode DerivedData",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Rebuilt on next build.",
      "paths": [ { "base": "xcode", "glob": "DerivedData" } ]
    },
    {
      "id": "xcode.devicesupport",
      "app": "Xcode iOS DeviceSupport",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Re-created when a device reconnects.",
      "paths": [ { "base": "xcode", "glob": "iOS DeviceSupport" } ]
    },
    {
      "id": "coresimulator.caches",
      "app": "CoreSimulator caches",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "appCaches",
      "risk": "safe",
      "why": "Rebuilt by the simulator on demand.",
      "paths": [ { "base": "home", "glob": "Library/Developer/CoreSimulator/Caches" } ]
    },
    {
      "id": "system.diagnosticreports",
      "app": "Diagnostic reports",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "systemLogs",
      "risk": "safe",
      "why": "Old crash reports are not needed to run apps.",
      "paths": [ { "base": "logs", "glob": "DiagnosticReports" } ]
    },
    {
      "id": "system.quicklook",
      "app": "QuickLook thumbnails",
      "appBundleID": null,
      "requiresInstalled": false,
      "category": "systemLogs",
      "risk": "safe",
      "why": "Thumbnails regenerate on demand.",
      "paths": [ { "base": "caches", "glob": "com.apple.QuickLook.thumbnailcache" } ]
    }
  ],
  "projectRoots": ["~/projects"],
  "projectArtifacts": [
    "node_modules", ".venv", "venv", ".build", "dist", "build",
    ".next", "__pycache__", "DerivedData", ".ruff_cache", "target"
  ]
}
```

- [ ] **Step 2: Verify the catalog still loads and the safety-lint stays green**

Run: `swift test --filter SafetyLintTests`
Run: `swift test --filter CatalogLoaderTests/test_loadsBundledCatalog`
Expected: PASS — the full catalog decodes, validates, and resolves nothing onto protected data.

---

### Task 3: Catalog-content lint tests

Prove the *shipped* catalog is internally well-formed and stays within the spec's display categories and risk discipline — so a future bad edit fails CI.

**Files:**
- Create: `Tests/GlowKitTests/CatalogContentTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import GlowKit

// Lints the SHIPPED catalog; a bad rule fails CI (fix the rule, not the test).
final class CatalogContentTests: XCTestCase {
  private func catalog() throws -> Catalog { try CatalogLoader.loadBundled() }

  func test_catalogHasBroadCoverage() throws {
    let ids = Set(try catalog().rules.map(\.id))
    for expected in ["chrome", "firefox", "vscode", "slack",
                     "xcode.deriveddata", "dev.npm", "system.diagnosticreports"] {
      XCTAssertTrue(ids.contains(expected), "missing rule \(expected)")
    }
    XCTAssertGreaterThanOrEqual(try catalog().rules.count, 20)
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
```

- [ ] **Step 2: Run test to verify it fails (then passes)**

Run: `swift test --filter CatalogContentTests`
Expected: with Task 2's catalog in place, these PASS. If any fails, the catalog is wrong — fix the rule, never the assertion.

---

### Task 4: Full-suite green

- [ ] **Step 1: Run the entire suite**

Run: `swift test`
Expected: ALL tests PASS — Plans 1–2 plus this plan's loader test and catalog-content lint, with the Plan-1 `SafetyLintTests` still green over the now-full catalog.

---

## Self-review notes

- **Spec coverage (§5):** browsers all-profiles via `*` glob with caches `safe` and cookies/history `privacy`, sessions/local-storage `stateful` (chrome/brave/edge/firefox) ✓; known apps incl. VSCode deep caches + WebStorage stateful, Spotify, Slack, Discord, Teams, Zoom ✓; dev caches (huggingface, npm, uv, pnpm, pre-commit, pip, yarn, gradle, CocoaPods, cargo) ✓; Xcode DerivedData + DeviceSupport + CoreSimulator caches ✓; user-owned system (DiagnosticReports, QuickLook) ✓; project artifacts list expanded ✓.
- **Safety by construction:** every path uses an allowed symbolic `base` + single-segment-`*` glob; none targets a `DenyList`-protected location; the Plan-1 `SafetyLintTests` re-runs over the full catalog and must stay green. The loader now also rejects `**` (spec §4).
- **Risk discipline:** only caches are `safe` (default-selected); browser cookies/history are `privacy`, sessions/local-storage `stateful` — both off by default. Asserted by `test_browserPrivacyAndSessionPathsAreNotDefaultSafe`.
- **Deliberately deferred:** report-only large/old files, Trash size, APFS snapshots, `/Library` sudo items, and heuristic orphans/workspaceStorage/dup-extensions are Plans 4/6, not catalog rules. Safari (sandboxed under Containers) is intentionally omitted in v1 to avoid mis-targeting.
- **Type consistency:** uses Plan-1 `CatalogLoader.loadBundled()`, `Catalog`/`Rule`/`PathSpec.effectiveRisk(ruleRisk:)`, `CatalogError.invalidGlob` — all unchanged signatures.
```