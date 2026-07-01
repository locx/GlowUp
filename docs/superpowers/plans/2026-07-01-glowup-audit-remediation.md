# GlowUp Audit Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the peripheral (non-code-logic) gaps from the 2026-07-01 audit — repo/doc hygiene, a lint CI gate, one privileged-path hardening, doc trade-offs, force-unwrap removal, and a minor view-render cleanup — without touching the load-bearing safety core.

**Architecture:** Five independent tasks, each ending in a green build/test and its own commit. The only ordering note: the privileged-path hardening (Task 3) lands its tests first. No task weakens any of the three safety layers.

**Tech Stack:** Swift (tools 5.9), SwiftPM (no Xcode project), SwiftUI + AppKit, XCTest, GitHub Actions (macos-14).

## Global Constraints

- **Never weaken the three safety layers** (catalog allowlist → `DenyList` veto → Trash-only/recoverable). If a change fights a safety rule, fix the change, not the rule.
- **Catalog edits only in** `Sources/GlowKit/Resources/catalog.json` — not touched by this plan.
- **Comments are WHY-only, ≤2 lines**, no tracker/task IDs. Never reformat or rename pre-existing code; keep every diff minimal.
- **Platform:** macOS 13+, SwiftPM, `swift-tools-version: 5.9`. Binaries: app product `GlowUpApp`, CLI `glowup`.
- **CI baseline stays green:** `swift build`, `swift test`, `bash -n scripts/glowup.sh` (`.github/workflows/ci.yml`, macos-14).
- **Git mutations require the user's explicit per-task go-ahead.** The `git commit` steps below are part of the plan; when executing, obtain authorization before running them (repo governance). The plan never runs `rm` outside `/tmp` — destructive filesystem commands are emitted for the user to run.
- **`swift build` exit 0 and `swift test` green are the definition of "step passes."** Never mark a step done without the command's output.

---

### Task 1: Repo & documentation hygiene

**Files:**
- Modify: `.gitignore`
- Track (new to git): `CLAUDE.md`, and the canonical `GlowUp-Workflow.md`
- Delete (user-run): `GlowUp-Workflow copy.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a repo where `docs/` (this plan) and root `*.md` are trackable; consumed by Task 5's README edit being visible and by this plan living in-repo.

**Context:** `.gitignore` currently blanket-ignores `*.md` and `docs/`, so only a force-added `README.md` is tracked; the project's own `CLAUDE.md` is untracked and a stray `GlowUp-Workflow copy.md` (differs from `GlowUp-Workflow.md`: 386 vs 346 lines) sits in the tree. This is the audit's top-ranked (Medium) process gap.

- [ ] **Step 1: Confirm the current ignore state (characterize before changing)**

Run: `git check-ignore -v CLAUDE.md docs/ ; git ls-files '*.md'`
Expected: `CLAUDE.md` and `docs/` are shown as ignored by `.gitignore` rules `*.md` / `docs/`; `git ls-files` prints only `README.md`.

- [ ] **Step 2: Decide the canonical workflow doc**

Run: `diff "GlowUp-Workflow.md" "GlowUp-Workflow copy.md" ; wc -l GlowUp-Workflow*.md`
Decision: keep `GlowUp-Workflow.md` (the un-suffixed file) as canonical unless the diff shows `copy` is newer/more complete — if so, first `mv "GlowUp-Workflow copy.md" GlowUp-Workflow.md` (user-run; overwrite of an existing file is destructive → emit for the user), then proceed. Default assumption: `GlowUp-Workflow.md` is canonical.

- [ ] **Step 3: Narrow `.gitignore`** — replace the whole file with (drops the `*.md` and `docs/` lines; keeps build/artifact ignores and local `.claude/`):

```gitignore
.build/
.swiftpm/
.claude/
DerivedData/
*.xcuserstate
.DS_Store
dist/
*.dmg
packaging/AppIcon.icns
packaging/GlowUp.iconset/
```

- [ ] **Step 4: Verify docs are now trackable**

Run: `git check-ignore CLAUDE.md docs/superpowers/plans || echo "not ignored"`
Expected: prints `not ignored` (neither path is ignored anymore).

- [ ] **Step 5: Remove the accidental duplicate (user-run destructive command)**

Emit for the user to run (the plan does not run `rm` outside `/tmp`):
```bash
rm "GlowUp-Workflow copy.md"
```
Expected after: `ls GlowUp-Workflow*.md` shows only `GlowUp-Workflow.md`.

- [ ] **Step 6: Stage the newly-trackable docs and commit**

```bash
git add .gitignore CLAUDE.md GlowUp-Workflow.md docs/superpowers/plans/2026-07-01-glowup-audit-remediation.md
git status   # confirm no unintended files (e.g. .build/, .claude/) are staged
git commit -m "chore: stop ignoring docs; track CLAUDE.md and workflow doc"
```
Expected: `git status` shows a clean tree except intended additions; commit succeeds.

---

### Task 2: Safe external-link constants (removes the 3 force-unwraps)

**Files:**
- Create: `Sources/GlowUpUI/AppLinks.swift`
- Create: `Tests/GlowUpUITests/AppLinksTests.swift`
- Modify: `Sources/GlowUpUI/Views/AboutPanel.swift:15`
- Modify: `Sources/GlowUpUI/Views/HeroPanel.swift:168`
- Modify: `Sources/GlowUpUI/Views/OnboardingView.swift:9-11`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum AppLinks { static let gitHub: URL?; static let fullDiskAccessSettings: URL? }` — the only definitions of these two hardcoded URLs, consumed by three views.

**Context:** `AboutPanel:15`, `HeroPanel:168`, `OnboardingView:10` each do `URL(string: "…")!`. They cannot fail at runtime (compile-time constants), so this is safety/style + DRY (the GitHub URL is duplicated). These are the *only* force-unwraps in `Sources/`.

- [ ] **Step 1: Write the failing test**

Create `Tests/GlowUpUITests/AppLinksTests.swift`:
```swift
import XCTest
@testable import GlowUpUI

final class AppLinksTests: XCTestCase {
  func test_externalLinksAreWellFormed() {
    XCTAssertEqual(AppLinks.gitHub?.absoluteString, "https://github.com/locx/GlowUp")
    XCTAssertEqual(AppLinks.fullDiskAccessSettings?.scheme, "x-apple.systempreferences")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GlowUpUITests.AppLinksTests`
Expected: FAIL — compile error, `cannot find 'AppLinks' in scope`.

- [ ] **Step 3: Create the constants**

Create `Sources/GlowUpUI/AppLinks.swift`:
```swift
import Foundation

// Hardcoded external destinations defined once. Call sites use `if let`, not force-unwrap,
// so a future typo in one of these literals can never crash the app.
enum AppLinks {
  static let gitHub = URL(string: "https://github.com/locx/GlowUp")
  static let fullDiskAccessSettings =
    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GlowUpUITests.AppLinksTests`
Expected: PASS.

- [ ] **Step 5: Replace the force-unwrap in `AboutPanel.swift:15`**

Old:
```swift
        Link("View on GitHub", destination: URL(string: "https://github.com/locx/GlowUp")!)
          .buttonStyle(.glowSecondary)
```
New:
```swift
        if let url = AppLinks.gitHub {
          Link("View on GitHub", destination: url).buttonStyle(.glowSecondary)
        }
```

- [ ] **Step 6: Replace the force-unwrap in `HeroPanel.swift:168`**

Old:
```swift
      Link("View on GitHub", destination: URL(string: "https://github.com/locx/GlowUp")!)
        .font(.caption2).foregroundStyle(Color.brand)
```
New:
```swift
      if let url = AppLinks.gitHub {
        Link("View on GitHub", destination: url)
          .font(.caption2).foregroundStyle(Color.brand)
      }
```

- [ ] **Step 7: Replace the force-unwrap in `OnboardingView.swift:9-11`**

Old:
```swift
      Link("Open Full Disk Access settings",
           destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        .buttonStyle(.glowSecondary)
```
New:
```swift
      if let url = AppLinks.fullDiskAccessSettings {
        Link("Open Full Disk Access settings", destination: url)
          .buttonStyle(.glowSecondary)
      }
```

- [ ] **Step 8: Verify no force-unwraps remain and everything builds**

Run: `swift build && grep -rcn 'URL(string:.*)!' Sources/ ; echo "count above should be 0"`
Expected: `Build complete!`; grep prints `0`.

- [ ] **Step 9: Run the full suite**

Run: `swift test`
Expected: all tests pass (no regression).

- [ ] **Step 10: Commit**

```bash
git add Sources/GlowUpUI/AppLinks.swift Tests/GlowUpUITests/AppLinksTests.swift \
        Sources/GlowUpUI/Views/AboutPanel.swift Sources/GlowUpUI/Views/HeroPanel.swift \
        Sources/GlowUpUI/Views/OnboardingView.swift
git commit -m "refactor: centralize external URLs, drop UI force-unwraps"
```

---

### Task 3: Harden the one non-recoverable path (`SystemCacheCleaner`)

**Files:**
- Modify: `Sources/GlowKit/SystemCacheCleaner.swift:63`
- Modify: `Tests/GlowKitTests/SystemCacheCleanerTests.swift` (add one test; update four exact-string assertions)

**Interfaces:**
- Consumes: nothing.
- Produces: `removalCommand` now emits `/bin/rm -rf -- <quoted paths>` (end-of-options guard). Signature unchanged: `static func removalCommand(_ urls: [URL], root: String = root) -> String?`.

**Context:** `SystemCacheCleaner` is the only path that deletes as root with no Trash (`/bin/rm -rf` via `osascript`). Its scope guard is already well-tested. This task adds defense-in-depth: a `--` end-of-options terminator so a future cache directory named like a flag (e.g. `-rf`) can never be parsed as an `rm` option, with a test that pins it. Tests land first; the hardening then updates the characterization assertions.

- [ ] **Step 1: Write the failing test** — add to `SystemCacheCleanerTests.swift` (inside the class):

```swift
  func test_removalCommandUsesEndOfOptionsForFlagLikeNames() {
    // A cache dir named like a flag must be an operand, never an rm option.
    let cmd = SystemCacheCleaner.removalCommand([
      URL(fileURLWithPath: "/Library/Caches/-rf"),
    ])
    XCTAssertEqual(cmd, "/bin/rm -rf -- '/Library/Caches/-rf'")
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GlowKitTests.SystemCacheCleanerTests/test_removalCommandUsesEndOfOptionsForFlagLikeNames`
Expected: FAIL — actual command has no `--` (`/bin/rm -rf '/Library/Caches/-rf'`).

- [ ] **Step 3: Add the end-of-options guard**

In `Sources/GlowKit/SystemCacheCleaner.swift`, change the final line of `removalCommand` (line 63):
Old:
```swift
    return "/bin/rm -rf " + args.joined(separator: " ")
```
New:
```swift
    // `--` ends option parsing, so a cache dir whose name starts with `-` can't act as an rm flag.
    return "/bin/rm -rf -- " + args.joined(separator: " ")
```

- [ ] **Step 4: Update the four existing exact-string assertions to include `--`**

In `SystemCacheCleanerTests.swift`:
- Line 29:
```swift
    XCTAssertEqual(cmd, "/bin/rm -rf -- '/Library/Caches/com.foo' '/Library/Caches/with space'")
```
- Line 47:
```swift
    XCTAssertEqual(cmd, "/bin/rm -rf -- '/Library/Caches/o'\\''brien'")
```
- Line 59:
```swift
    XCTAssertEqual(r.received, "/bin/rm -rf -- '/Library/Caches/com.foo'")
```
- Line 80:
```swift
    XCTAssertEqual(r.received, "/bin/rm -rf -- '\(resolvedChild)'")
```

- [ ] **Step 5: Run the whole SystemCacheCleaner suite**

Run: `swift test --filter GlowKitTests.SystemCacheCleanerTests`
Expected: all tests pass (the new one plus the four updated assertions plus the scope/symlink guards).

- [ ] **Step 6: Full suite + safety-lint still green**

Run: `swift test`
Expected: all pass (including `SafetyLintTests`).

- [ ] **Step 7: Commit**

```bash
git add Sources/GlowKit/SystemCacheCleaner.swift Tests/GlowKitTests/SystemCacheCleanerTests.swift
git commit -m "fix: add -- end-of-options guard to root cache removal"
```

---

### Task 4: Document the security posture trade-offs

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a README section stating the non-sandbox rationale and the single irreversible action.

**Context:** The app is intentionally not sandboxed (`packaging/GlowUp.entitlements`: `app-sandbox = false`) because Full Disk Access scanning is incompatible with the sandbox; it ships hardened + notarized instead. The in-app irreversibility warning already exists (`ReviewTreeView.swift:131` — "This cannot be undone — there is no Trash for these…"), so this task only adds the README rationale; it does **not** duplicate in-app copy.

- [ ] **Step 1: Add a "Security posture" section** — insert immediately before the `## Trust` heading in `README.md`:

```markdown
## Security posture

- **Not sandboxed** (`com.apple.security.app-sandbox = false`). Reclaiming caches under
  `~/Library` needs Full Disk Access, which the App Sandbox cannot grant, so GlowUp ships
  unsandboxed — with a hardened runtime and notarization instead.
- **One irreversible action.** Everything GlowUp cleans goes to the Trash and is restorable —
  *except* "Clean System Caches" (Advanced), which deletes `/Library/Caches` as root and cannot be
  undone. It is opt-in, warns before running, and requires an administrator password.

```

- [ ] **Step 2: Verify the section is present and the doc still parses**

Run: `grep -n "Security posture" README.md && python3 -c "print('readme readable')"`
Expected: prints the heading line and `readme readable`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document non-sandbox rationale and the irreversible system-cache clean"
```

---

### Task 5: Cache the permanent-action set in `ReviewTreeView` (polish)

**Files:**
- Modify: `Sources/GlowUpUI/Views/ReviewTreeView.swift` (lines 14–15, 42, 137, 140, 194–197)

**Interfaces:**
- Consumes: nothing.
- Produces: `permanentSection(_ ids: [PermanentAction]) -> some View` and `allPermanentBinding(_ ids: [PermanentAction]) -> Binding<Bool>` — both fed the once-computed `permanent` list.

**Context:** `permanentIDs` (a two-`Bool` derivation) is recomputed on each access inside `allPermanentBinding`'s getter/setter and at the `body` guard. This mirrors the already-mitigated pattern in `HeroPanel.swift:28` (bind once per body). Value is marginal (audit rated it Low), so the change is deliberately minimal and behavior-identical. This is a SwiftUI view refactor with no unit-testable surface; verification is build + the existing suite staying green + a manual visual check.

- [ ] **Step 1: Compute the list once at the top of `body`** — change lines 14–15:

Old:
```swift
  var body: some View {
    VStack(spacing: 0) {
```
New:
```swift
  var body: some View {
    let permanent = model.advanced ? permanentIDs : []
    VStack(spacing: 0) {
```

- [ ] **Step 2: Use the hoisted value at the guard** — change line 42:

Old:
```swift
      if model.advanced, !permanentIDs.isEmpty { permanentSection }
```
New:
```swift
      if !permanent.isEmpty { permanentSection(permanent) }
```

- [ ] **Step 3: Make `permanentSection` take the list** — change line 137 and its internal binding call (line 140):

Line 137 old → new:
```swift
  @ViewBuilder private func permanentSection(_ ids: [PermanentAction]) -> some View {
```
Line 140 old:
```swift
        Toggle("", isOn: allPermanentBinding).toggleStyle(.glowCheckboxBareDanger)
```
Line 140 new:
```swift
        Toggle("", isOn: allPermanentBinding(ids)).toggleStyle(.glowCheckboxBareDanger)
```

- [ ] **Step 4: Make `allPermanentBinding` take the list** — replace lines 194–197:

Old:
```swift
  private var allPermanentBinding: Binding<Bool> {
    Binding(get: { !permanentIDs.isEmpty && permanentIDs.allSatisfy(selectedPermanent.contains) },
            set: { on in selectedPermanent = on ? Set(permanentIDs) : [] })
  }
```
New:
```swift
  private func allPermanentBinding(_ ids: [PermanentAction]) -> Binding<Bool> {
    Binding(get: { !ids.isEmpty && ids.allSatisfy(selectedPermanent.contains) },
            set: { on in selectedPermanent = on ? Set(ids) : [] })
  }
```

(The `permanentIDs` computed property stays — it now has a single caller in `body`.)

- [ ] **Step 5: Build and run the full suite**

Run: `swift build && swift test`
Expected: `Build complete!`; all tests pass (logic unchanged).

- [ ] **Step 6: Manual visual check**

Launch the app (`swift run GlowUpApp`), enable **Advanced**, and confirm: the red "Permanent · cannot be undone" section still appears when system caches / unavailable simulators exist, its select-all toggle still selects/clears both rows, and it hides when nothing permanent is present. (SwiftUI rendering is not unit-testable here — this manual check is the verification.)

- [ ] **Step 7: Commit**

```bash
git add Sources/GlowUpUI/Views/ReviewTreeView.swift
git commit -m "refactor: compute permanent-action set once per render"
```

---

## Milestone mapping

- **Milestone 0 (safety net):** Task 3 Steps 1–2 (characterizing test before the privileged-path change).
- **Milestone 1 (critical fixes):** none — the audit found no Critical/High code defects. Task 3's hardening is the nearest (Medium, defense-in-depth).
- **Milestone 2 (high-leverage):** Task 1 (repo/doc hygiene) — changes the slope of all future contribution.
- **Milestone 3 (quality & polish):** Task 2 (force-unwraps), Task 4 (docs), Task 5 (view polish).

**Quick wins (do first, S effort):** Task 1, Task 2, Task 4.

**Considered and dropped — CI lint gate.** `swift format --lint` cannot pass without a full reformat: even with every toggleable rule disabled and `lineLength` at 200, 571 pretty-printer diffs (`Indentation`/`AddLines`/`Spacing`/`TrailingComma`) remain, and those are not in the rules map. Reformatting the deliberate compact style is not worth it, and SwiftLint was declined too — so no lint runs in CI. Style stays author-enforced (already tidy); revisit only if drift appears.

**Out of scope (deliberately excluded):** the `AppModel` split (audit T7 — speculative until a feature forces it), any XCTest→Swift Testing migration (pure churn), and sandboxing the app (would break Full Disk Access scanning). See audit §4 non-goals.

---

## Self-Review

**Spec coverage** (audit tasks T1–T7): T1 → Task 1 ✓; T3 → Task 3 ✓; T4 → Task 4 ✓; T5 → Task 2 ✓; T6 → Task 5 ✓; T2 (lint gate) → deliberately dropped (see "Considered and dropped"); T7 out of scope ✓.

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Every code step shows exact old/new text; every verify step shows an exact command and expected output.

**Type/name consistency:** `AppLinks.gitHub` / `AppLinks.fullDiskAccessSettings` used identically in Task 2 Steps 3–7 and `AppLinksTests`. `removalCommand` signature unchanged in Task 3; the `--` string appears identically in the implementation (Step 3) and all five assertions (Steps 1, 4). `permanentSection(_:)` and `allPermanentBinding(_:)` take `[PermanentAction]` consistently across Task 5 Steps 2–4.

**Ordering dependency check:** Task 3 lands its characterizing test before its code change ✓. No cross-task ordering dependency remains after the lint gate was dropped ✓.
