# GlowUp — Final Design Spec

Date: 2026-06-06
Status: Canonical. Supersedes and replaces all prior design specs.
This document is the single source of truth for product, engine, safety, UX, and packaging.

---

## 1. Product

A free, open-source macOS cleanup utility a stranger can trust: reclaims
meaningful space ("give your Mac a glow-up") while making data loss
structurally hard. **Safety is the product; reclaim is the feature.**

| Name | Value |
|---|---|
| Product / app | **GlowUp** |
| Core library | **GlowKit** |
| CLI binary | **glowup** |
| Homebrew cask | **glowup** |
| Repo dir | `MacLibCleanup` (until renamed) |
| License | MIT |

**North star (two clicks, zero jargon):** launch → ring auto-fills →
**Clean My Mac** → **Move X to Trash?** → **Freed X.** No speed claims, ever —
we talk about **space**, never "faster." The brand *is* the delight: credible
competence + tactile native polish + radical honesty.

---

## 2. Safety model (the core promise)

Three independent layers; a candidate is cleaned only if it passes all three.

1. **Allowlist-first.** Nothing is cleaned unless a vetted catalog rule names
   it. Default run = rules with `risk == safe`. No name-guessing in the default
   path. Heuristic orphans are a separate, Advanced, default-off scanner.
2. **Deny-list veto** — hardcoded in `GlowKit`, **not** catalog-overridable.
   Every candidate is canonicalized (resolve symlinks + `..`) and rejected if it
   is at/above an allowed base root (never nuke all of `~/Library/Caches`), or
   falls under any protected location: `~/Documents`, `~/Desktop`,
   `~/Downloads`, `~/Pictures` + Photos library, `~/Movies`, `~/Music`, iCloud
   Drive, `~/Library/Mail`, Messages, `~/Library/Keychains`, `~/.ssh`,
   `~/.gnupg`, password-manager vaults, `MobileSync/Backup`, the app/catalog
   itself, or any credential pattern (`*.kdbx`, `*.pem`, `*.key`, `*.p12`,
   `id_rsa*`, `.env*`, `.netrc`, `.pgpass`).
3. **Recoverable + reversible.** Trash-only (`FileManager.trashItem`, Put-Back
   metadata); dry-run by default; explicit confirm; **Restore last cleanup**
   tracks trashed paths and restores them, surviving relaunch.

Catalog paths never contain raw absolutes — only a symbolic `base`
(`appSupport`, `caches`, `logs`, `home`, `xcode`) resolved by `GlowKit`, so a
catalog row cannot point outside controlled roots by construction.

### 2A. Safety-UX rules (binding — must land in `GlowKit` behavior + safety-lint, not just UI)

1. **Report-only items have NO checkbox.** Large/old files, Trash size, APFS
   snapshots, and `/Library` sudo/emit items live in a separate **Reports**
   section and are *un-actionable* by the app.
2. **"Select all safe" excludes non-safe children.** The tri-state cascade and
   ⌘A select `risk==safe` leaves only. A safety-lint test asserts the cascade
   never pulls a non-safe path.
3. **Free-space gauge tells the truth.** Trashing frees nothing until Trash is
   emptied. Label **"X moved to Trash → empty Trash to reclaim."** Never show
   "Freed 0 bytes." Empty Trash is an explicit, separate, user-initiated action.
4. **Restore survives relaunch and reports partial failure.** `RestoreStore`
   persists to disk; Put-Back failures surface honestly
   ("Restored 38/40; 2 couldn't be restored — Trash was emptied").
5. **Never auto-quit running apps.** Per-app, non-blocking choice:
   **Skip (default)** / Quit & clean / Clean anyway.
6. **Zero network — verify, don't assume.** No telemetry, no update phone-home,
   no icon CDN. A safety-lint/CI assertion confirms no outbound calls. Any future
   update check is explicit opt-in.
7. **Orphan scanner = honest guesswork.** Labeled "Possible leftovers (best
   guess)"; items stay deselected even after the scanner is enabled (opt-in
   twice); plain-language risk shown; "Protected files are never listed here."

---

## 3. Architecture

```
catalog.json  ──(loaded + validated)──►  GlowKit (Swift library, UI-free)
  rules[], projectRoots[], artifacts[]     ├ CatalogLoader + schema validate
                                           ├ Resolver (base → real paths, glob)
                                           ├ DenyList (veto, hardcoded)
                                           ├ Scanner (rule candidates)
                                           ├ OrphanScanner (advanced, off)
                                           ├ SizeMeasurer (concurrent, cancel)
                                           ├ TreeProvider (lazy children + sizes)
                                           ├ Trasher + RestoreStore
                                           └ Inventory (apps/brew/mas/pkg)
                                                  ▲              ▲
                          ┌───────────────────────┘              └─────────────┐
              GlowUp (SwiftUI app)                             glowup (CLI)
              onboarding/FDA, selection, clean,               --list/--dry-run/
              restore, before/after free space                --clean/--json/--restore
```

`mac-lib-cleanup.sh` (legacy) reads the same `catalog.json` via `jq` for users
who can't build Swift — same data, no engine duplication. Lowest priority; may
be deprecated for the Swift CLI.

### Migration from current code
Existing Swift services refactor **into** `GlowKit`, not deleted: `Inventory`,
`KnownMatcher` → `OrphanScanner`; `LibraryScanner`/`BrowserDetector` →
catalog-driven `Scanner` + `Resolver`; `LaunchdProbe` (demoted), `SizeMeasurer`,
`Trasher`, `RunningAppDetector` move in. Hand-coded `BROWSER_DEFS`/
`DEV_CACHE_PATHS`/`KEEP_PREFIXES` become `catalog.json` rows.

---

## 4. Catalog schema (`catalog.json`, v1)

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
        { "base": "appSupport", "glob": "Code/CachedExtensionVSIXs" },
        { "base": "appSupport", "glob": "Code/Crashpad" },
        { "base": "appSupport", "glob": "Code/WebStorage", "risk": "stateful" }
      ]
    }
  ],
  "projectRoots": ["~/projects"],
  "projectArtifacts": ["node_modules", ".venv", "venv", ".build",
                       "dist", "build", ".next", "__pycache__", "DerivedData"]
}
```

- `risk`: `safe` | `stateful` | `privacy` | `rebuildable`; per-rule, with
  per-path override. Per-path `effectiveRisk` falls back to the rule risk.
- `base`: symbolic root from a fixed allowlist resolved in `GlowKit`.
- `glob`: single-segment `*` wildcard via `fnmatch` (e.g. `Brave/*/Cache`);
  no `**` recursion in v1.
- `requiresInstalled`: clean only when `appBundleID` is present.
- Categories: `libraryOrphans` (advanced), `appCaches`, `browserData`,
  `systemLogs`, `projectArtifacts`, `workspaceOrphans`, `duplicateExtensions`,
  `largeFiles` (report-only). Modeled as `String` in Plan 1; may converge to an
  enum later.

**Validation (CatalogLoader):** reject unsupported `schemaVersion`, duplicate
rule IDs, and any glob that is empty, absolute (`/…`), or contains `..`.

---

## 5. Coverage (curated, risk-tiered, Trash-only)

- **Browsers, all profiles:** caches (`safe`); cookies/history/form (`privacy`,
  off); sessions/Local Storage/IndexedDB (`stateful`, off).
- **Known apps:** VSCode deep caches incl. WebStorage, Spotify, Slack, Discord,
  Teams, Zoom, generic Electron `Cache/Code Cache/GPUCache/Crashpad`.
- **Dev caches:** `~/.cache/huggingface`, `~/.npm/_cacache`, uv, pnpm, ruff,
  pre-commit, pip, yarn, gradle, CocoaPods, cargo registry cache.
- **Xcode:** DerivedData, old DeviceSupport; emit `simctl delete unavailable`.
- **System (user-owned, no sudo):** `~/Library/Logs/*`, DiagnosticReports,
  QuickLook/font caches.
- **VSCode workspaceStorage orphans**, **duplicate extension versions**.
- **Project artifacts** (`rebuildable`, off): under configurable roots.
- **Report-only (never auto-select):** large/old files in `~/Downloads`,
  `~/Movies`; Trash size; APFS snapshots and `/Library`/sudo items are
  **emit-only** (printed commands), never executed by the tool.
- **Heuristic orphans:** Advanced view, default-off.

**Deliberately excluded (anti-snake-oil, stated in README):** RAM purge, DNS
flush, auto-emptying Trash, deleting language packs, iOS backups deletion.

### Risk tiers
`safe` is the only default-selected tier; `stateful`/`privacy`/`rebuildable`
are opt-in. Palette (color never the sole signal — always + symbol + label):
`safe` emerald `#10B981` · `rebuildable` sky `#0EA5E9` · `stateful` amber
`#FBBF24` · `privacy` fuchsia `#D946EF`. **Red** is reserved solely for
emit-only/irreversible items the app won't perform.

---

## 6. Front-ends

### App (GlowUp)
- **One primary button: "Clean My Mac."** Auto-scans (read-only, safe) on launch
  so the ring fills within ~1s; the button then trashes **safe-tier only**.
  Default path touches **zero** checkboxes/tree nodes. "Scan" survives as manual
  refresh only.
- **Progressive disclosure.** Land on **Recommended**, rows collapsed and
  pre-selected. The tree/tri-state/risk-capsule inspector hides behind a quiet
  **"Review what will be cleaned"** link. Advanced (orphans, projects) and
  Reports are deliberate clicks away.
- **No risk jargon on the happy path.** The default user never reads
  "stateful/rebuildable/risk." Capsules appear only in Review/Advanced.
- **FDA: value first, then ask.** Scan what's reachable, show a number, then
  prompt "Grant Full Disk Access to find ~X GB more." One screen, 3-frame switch
  visual, deep link (`x-apple.systempreferences:…?Privacy_AllFiles`),
  **auto-recheck on app activation** (no "I've done it" button). Denied →
  **degraded mode** with one calm persistent banner, never a modal.
- **Calm confirm, no theater.** One sheet; weight scales with risk. All-safe →
  light summary. Includes non-safe → itemize only the consequential part. Never
  a type-"DELETE" gate. No warning iconography on safe rows.
- **Restore / History.** Persistent History view of past cleanups with one-click
  Put-Back; partial-failure honesty.

### CLI (glowup)
`--list`, `--dry-run` (default), `--clean`, `--advanced` (orphans),
`--projects`, `--json`, `--restore`, `--no-color`.

### Microcopy (binding strings)

| Location | String |
|---|---|
| Primary CTA | **Clean My Mac** |
| Hero, post-scan | **You can free up 12.4 GB** |
| Confirm title | **Move 12.4 GB to the Trash?** |
| Confirm body (all-safe) | **These are app caches and logs your Mac rebuilds automatically. Nothing is deleted — everything goes to the Trash, and you can restore it anytime.** |
| Confirm primary / secondary | **Move to Trash** / **Not now** |
| Done | **Freed 12.4 GB** (+ "moved to Trash — empty Trash to reclaim") |
| Restore | **Put it all back** |
| Degraded banner | **Limited access — grant Full Disk Access to reclaim more →** |
| Empty state | **Your Mac is already sparkling** (no emoji in UI; pair with `checkmark.seal.fill`) |
| Copy summary | **Reclaimed 12.3 GB safely, all recoverable — GlowUp.** |

---

## 7. Visual design — "Emerald Graphite"

- **Accent + tokens.** Brand emerald `#10B981` on graphite `#16181A`;
  `.tint(.brand)` at root. Asset-catalog Color Sets with Any/Dark variants.
  Token layer: `surface`, `surfaceRaised`, `textPrimary/Secondary`. No
  hand-rolled `colorScheme` toggling. The accent doubles as the safe-tier hue.
- **The radial ring (hero).** Concentric **segmented arcs per category** via
  `trim(from:to:)`/custom `Shape`, `StrokeStyle(lineWidth: 28, lineCap: .round)`
  with ~1.5° gaps; per-segment `AngularGradient`; staggered spring fill as
  results stream (`.spring(response:0.6, dampingFraction:0.8)`, ~60ms apart);
  center total via `Text(bytes, format:.byteCount(…))` +
  `.contentTransition(.numericText())`. Empty = faint dashed track + Scan CTA;
  scanning = slow gradient sweep; nothing-to-clean = single full green arc +
  `checkmark.seal.fill .symbolEffect(.bounce)`.
- **Typography.** Headline number `.system(size:40, weight:.semibold,
  design:.rounded).monospacedDigit()`; subtitle `.title3`; headers `.headline`;
  rows `.body`; secondary `.caption/.subheadline`; badges `.caption2.semibold`
  uppercased `.tracking(0.5)`. Monospaced digits wherever sizes render.
- **Spacing & surfaces.** 8pt rhythm (4/8/12/16/24/32); hero min-height ~280pt;
  cards `.background(.surfaceRaised, in:.rect(cornerRadius:12))` + 0.5pt
  `.separator` stroke.
- **Iconography.** SF Symbols `.hierarchical` tinted by category; `.multicolor`
  reserved for the success mark. Real per-app icons
  (`NSWorkspace.shared.icon(forFile:)`) at 18–20pt, 4pt corner, 0.5pt stroke,
  fallback `app.dashed`. Distinctive category glyphs (not `folder` everywhere).
- **Window.** `.windowStyle(.hiddenTitleBar)`, content under the toolbar,
  `.defaultSize(960×640)`, `.windowResizability(.contentMinSize)`. First open
  lands on the ring + prominent `.borderedProminent .controlSize(.large)` CTA —
  never an empty table.
- **App icon.** Squircle on the macOS grid, brand-green gradient, one confident
  glyph (disk/ring + subtle sparkle or shield-with-sweep) — avoid broom/sparkle
  cliché. Ship full `.icns` ladder + a **template monochrome** menu-bar glyph
  (`NSImage.isTemplate = true`).

---

## 8. Motion & accessibility

- Centralized motion policy keyed to `@Environment(\.accessibilityReduceMotion)`:
  one `anim` token; Reduce Motion → ~0.15s opacity crossfades, ring fills
  instantly, no stagger/scale/geometry.
- `matchedGeometryEffect` on the total (ring → confirm → done), gated.
- Visible tri-state cascade (staggered, gated).
- Lazy disclosure shows inline `ProgressView().controlSize(.small)` while
  `TreeProvider` enumerates; crossfade children in.
- Full VoiceOver labels, Dynamic Type, keyboard navigation, Increase Contrast.

---

## 9. Delight (tasteful, honest)

**Do:** streaming/skeleton scan (rows appear as the Scanner yields; sizes
shimmer→number); before/after reveal as the emotional climax (count-up + gauge
growth, one spring); relatable framing ("≈ 1,200 photos," always
"approximately," documented constants); calm menu-bar extra (reclaimable at a
glance + tiny ring + one-click **Clean Safe Items Now**, badge off by default);
restore-as-confidence; keyboard kit (Space=Quick Look, ⌘F search, arrows+Space
in tree, ⌘A select-safe, ⌘⏎ Clean, ⌘Z Restore, ⌘1–4 sidebar, `?` cheat-sheet);
restrained row-collapse cleaning animation; copy summary; all-time stat
(local History, resettable); in-app trust pills ("No telemetry · No network ·
Open source (MIT)" + **View the catalog** + View on GitHub).

**Skip (v1):** confetti/particles; custom sounds (system Trash crumple only);
gamification (streaks, badges, "optimization score"); alarmist nagging;
mascots; auto-generated share cards / social buttons. Haptics optional,
trackpad-only, low priority.

---

## 10. Testing

- **`GlowKitTests`:** catalog decode + schema validation; base resolution & glob
  expansion on a synthetic `$HOME`; **deny-list veto table** (hostile rows that
  must all be rejected, incl. base-root, credential patterns, and a **symlink
  inside Caches pointing at `~/Documents`**); orphan matcher; restore round-trip;
  size measurement on a fixture tree.
- **Safety-lint (unit test + CI gate):** for every shipped catalog rule, resolve
  on a synthetic `$HOME` and assert nothing escapes allowed bases, hits the
  deny-list, or uses an unbounded glob. Adds the **cascade-excludes-non-safe**
  and **zero-network** assertions. A bad rule fails CI; the fix is the rule or
  the deny-list — never the assertion.
- **CLI smoke:** `--json` emits valid, schema-conformant JSON.
- App UI verified manually.

---

## 11. Distribution & trust

- **Open source**, MIT; **public auditable catalog**; **no telemetry, no
  network** by default — stated prominently in README.
- **Hardened Runtime**, Developer-ID signed, **notarized** (notarytool), stapled
  **DMG**. Not App-Sandboxed (needs FDA + broad read; MAS out of scope).
- **Homebrew cask** `glowup`.
- **GitHub Actions:** build + test + safety-lint; on tag → sign + notarize +
  publish DMG. Signing certs/secrets are **user-provided** (workflow +
  entitlements scaffolded; credentials never handled by the tooling).
- Repo hygiene: README + screenshots, LICENSE, CHANGELOG, CONTRIBUTING,
  SECURITY.md, issue templates.

---

## 12. Implementation plan set (7 plans)

Each plan produces working, tested software on its own. Plan 1 is written
(file below); Plans 2–7 are the intended roadmap and not yet authored.

1. **Foundation — catalog + safety spine** (← `plans/2026-06-06-glowup-01-foundation.md`)
2. **Engine** — Inventory, Scanner, SizeMeasurer, Trasher, RestoreStore, TreeProvider
3. **Catalog content** — all curated rules; safety-lint green
4. **App** — SwiftUI (sidebar, radial ring, tree, clean flow, onboarding, restore, menu-bar)
5. **CLI `glowup`** + legacy bash refactor to catalog
6. **Advanced scanners** — orphans, projects, workspaceStorage, dup-extensions, large-file report
7. **Packaging** — entitlements, DMG, notarize CI, Homebrew cask, repo hygiene

### Corrections folded in from Plan 1 review (apply when implementing)
- **Naming unified to GlowUp/GlowKit/glowup throughout** (resolves the
  earlier body-text vs. locked-section naming split).
- **`Resolver` must `import Darwin`** — `fnmatch` is used but was missing from
  the snippet; won't compile otherwise.
- **Confirm catalog resource path** stays `Sources/GlowKit/Resources/catalog.json`
  for `Bundle.module` resolution; don't let it drift under `Models/`.
- **Add the symlink-veto test** (Caches → Documents) — currently untested; the
  `resolvingSymlinksInPath()` line in `DenyList.vetoes` is load-bearing.
- Plan 1 Task 7 "Expected: FAIL" wording is self-contradicting → "PASS once
  Tasks 4–6 land; a real failure here is a safety bug."

---

## 13. Resolved design decisions

1. **Name:** GlowUp / GlowKit / glowup (locked).
2. **Ring:** concentric segmented arcs per category (not one continuous arc).
3. **Empty Trash:** single action, surfaced both on the Done screen and in
   Reports (one implementation, two entry points).

---

## Appendix A — UI mocks (layout reference)

ASCII layout mocks; color/motion per §7–§8.

### A1 — First launch, auto-scan (~1s)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ●  ●  ●                                                          GlowUp ⌄  │
├────────────────┬───────────────────────────────────────────────────────── │
│  Recommended ● │                  ╭─────────────────╮                      │
│  Advanced      │                ╭─╯   scanning…     ╰─╮  (gradient sweep)  │
│  Reports       │               │      2.1 GB and counting │               │
│  ─────────────  │               ╰─╮               ╭─╯                      │
│  History        │                 ╰─────────────────╯                      │
│  About          │            Looking through caches and logs…              │
│                │              [ ▓▓▓▓▓▓▓░░░░  Scanning ]   (disabled)        │
└────────────────┴────────────────────────────────────────────────────────── ┘
```

### A2 — Post-scan hero (happy path)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ●  ●  ●                                                          GlowUp ⌄  │
├────────────────┬───────────────────────────────────────────────────────── │
│  Recommended ● │                  ╭─────────────────╮                      │
│  Advanced      │                ╭─╯ ███ emerald ███ ╰─╮  (segmented arcs)  │
│  Reports       │               │██     12.4 GB       ██│                   │
│  ─────────────  │               │██    to free up     ██│                  │
│  History        │               ╰─╮               ╭─╯                      │
│  About          │                 ╰─────────────────╯                      │
│                │              You can free up 12.4 GB                      │
│                │            ┌──────────────────────────┐                  │
│                │            │      Clean My Mac         │  (brand, large)  │
│                │            └──────────────────────────┘                  │
│                │            Review what will be cleaned  ›                 │
└────────────────┴────────────────────────────────────────────────────────── ┘
```

### A3 — Confirm sheet (all-safe)

```
        ╭──────────────────────────────────────────────────╮
        │           Move 12.4 GB to the Trash?               │
        │   These are app caches and logs your Mac           │
        │   rebuilds automatically. Nothing is deleted —     │
        │   everything goes to the Trash, restore anytime.   │
        │              [ Not now ]   [ Move to Trash ]       │
        ╰──────────────────────────────────────────────────╯
```
Non-safe selection adds one line: **"Includes: sign-out of 3 sites."** Never a type-DELETE gate.

### A4 — Done / before-after

```
┌──────────────────────────────────────────────────────────────────────────┐
│                  ╭─────────────────╮      ✓ seal.fill .bounce              │
│                 │██   Freed 12.4 GB ██│   (ring settles, count-up)         │
│                  ╰─────────────────╯                                        │
│        Freed 12.4 GB · moved to Trash — empty Trash to reclaim             │
│            [ Empty Trash ]        [ Put it all back ]                      │
│        No telemetry · No network · Open source (MIT)   View the catalog ›  │
└──────────────────────────────────────────────────────────────────────────┘
```

### A5 — Review what will be cleaned (tree + risk capsules)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ‹ Back to summary                                              ⌘F  search │
├────────────────┬────────────────────────────────────────────────────────── │
│  Recommended ● │  ▾ ☑  Visual Studio Code          [safe]          4.2 GB  │
│  Advanced      │       ☑   CachedData               [safe]         3.1 GB  │
│  Reports       │       ☐   WebStorage           [stateful ▲]       1.1 GB  │  (amber, not preselected)
│  ─────────────  │  ▸ ☑  Xcode                       [safe]          5.8 GB  │
│  History        │  ▸ ◧  Brave                  [safe · privacy]    0.5 GB  │  (tri-state mixed)
│  About          │  ⌘A selects safe leaves only — never amber WebStorage    │
│                │  ☑ 11.3 GB selected (safe)            [ Clean Selected ]   │
└────────────────┴────────────────────────────────────────────────────────── ┘
```

### A6 — Reports (un-actionable by design)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Reports — things to look at yourself. GlowUp won't touch these.           │
├────────────────┬────────────────────────────────────────────────────────── │
│  Reports     ● │  Large & old in Downloads          8.7 GB                 │  (no checkbox anywhere)
│                │     installer.dmg · 1 yr           2.1 GB        [Reveal]  │
│                │  Trash (already there)             3.2 GB   [Empty Trash]  │
│                │  APFS local snapshots              6.0 GB  [How to clear ›]│
│                │  /Library system items (sudo)      —       [Copy command]  │
│                │  Protected files are never listed here.                    │
└────────────────┴────────────────────────────────────────────────────────── ┘
```

### A7 — FDA value-first + degraded banner

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ⚠ Limited access — grant Full Disk Access to reclaim ~6 GB more  →        │
├────────────────────────────────────────────────────────────────────────── ┤
│   ┌──────┐   ┌──────┐   ┌──────┐                                           │
│   │ ☐ off│ → │  ◑   │ → │ ☑ on │   GlowUp   (3-frame switch)               │
│   └──────┘   └──────┘   └──────┘                                           │
│            [ Open Full Disk Access settings ]   (auto-recheck on activate) │
└──────────────────────────────────────────────────────────────────────────┘
```

### A8 — Menu-bar extra (calm)

```
        ╭───────────────────────────────╮
        │ GlowUp            ◜◝  12.4 GB  │
        │ reclaimable safely            │
        │  ⚡ Clean Safe Items Now       │
        │  Open GlowUp…                 │
        │  142 GB reclaimed all-time    │
        ╰───────────────────────────────╯
```

### A9 — Empty state

```
                  ╭─────────────────╮   ✓ checkmark.seal.fill .bounce
                 │██ single full arc ██│
                  ╰─────────────────╯
              Your Mac is already sparkling
```
