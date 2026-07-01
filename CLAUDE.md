# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

GlowUp is a macOS (13+) disk-cleanup utility built with SwiftPM (no Xcode project). Its design thesis: **safety is the product, reclaim is the feature** — data loss must be structurally hard, not merely discouraged.

## Commands

```sh
swift build
swift test                              # includes the safety-lint gate over the shipped catalog
swift test --filter SafetyLintTests     # one test class
swift test --filter GlowKitTests.SafetyLintTests/test_baitFilesAreVetoed   # one test
bash -n scripts/glowup.sh               # syntax-check the pure-bash fallback (CI gates on this)
```

CI (`.github/workflows/ci.yml`, macos-14) runs exactly: `swift build`, `swift test`, `bash -n scripts/glowup.sh`.

## Targets

Three products from one package; the SwiftUI app binary is named `GlowUpApp` to avoid colliding with the case-insensitive `glowup` CLI binary on macOS filesystems.

- **GlowKit** (`library`) — UI-free core: scanning, safety, trashing, restore. All cleanup logic lives here. Links AppKit; bundles `Resources/catalog.json`.
- **GlowUp** (`executable GlowUpApp`) — SwiftUI app. Depends on GlowUpUI + GlowUpCLI; `main.swift` is excluded (entry point is `GlowUpApp.swift`'s `@main`).
- **glowup** (`executable`, target `GlowUpExec`) — CLI. `GlowUpCLIExec/main.swift` is the thin print shell; `GlowUpCLI/CLI.swift` holds the logic and is pure (returns `(String, Int32)`, never prints) so it's testable.

## Safety architecture — the load-bearing core

A candidate is trashed only if it survives three independent layers. **Never weaken any of them to make a build or feature pass** — fix the rule or the input instead.

1. **Allowlist-first.** Nothing is a candidate unless a vetted rule in `Sources/GlowKit/Resources/catalog.json` names it. Rules use symbolic `base` roots (`home`, `appSupport`, `caches`, `logs`, `xcode` — see `BaseRoot`) and single-segment `*` globs only: no `**`, no absolute paths, no `..`.
2. **Deny-list veto** (`DenyList.vetoes`) — hardcoded in GlowKit, **not catalog-overridable**. Canonicalizes each resolved URL (`resolvingSymlinksInPath`) and rejects protected dirs (Documents, Desktop, Mail, Keychains, `.ssh`, …), credential-named files/dirs, anything outside `$HOME`, `..` traversal, and bare base roots.
3. **Recoverable + reversible.** Trash-only (`ItemMover`/`SystemMover`, never `rm`), dry-run by default, explicit confirm, and `RestoreStore` "Restore last cleanup" that persists across relaunch and refuses to restore if the Trash path's mtime changed (reuse detection).

### Pipeline

`Catalog` rules → `Scanner.scan(includeRisks:)` → `Resolver.resolve` (expands globs via `fnmatch`, filters through `DenyList`) → `[Candidate]` → `Candidate.dedupe` → `SizeMeasurer.measure` → `Trasher.trash` → `RestoreStore.record`. Advanced scanners (`AdvancedScan.run`: orphans, workspace storage, duplicate extensions, project artifacts) are merged only under `--advanced`. `LargeFileReporter` never enters the automated clean set; the app's Reports page lets the user manually move explicitly-selected large files to the Trash (recoverable, recorded for undo via `RestoreStore`).

### Risk tiers (`Risk`)

`safe`, `rebuildable`, `stateful`, `privacy`. A `PathSpec.risk` overrides its rule's risk. Default runs clean **`safe` only**; `--advanced` cleans `safe` + `rebuildable`. `stateful`/`privacy` are listed but **never auto-cleaned**. Only caches belong in `safe`; cookies/history are `privacy`, sessions/local-storage are `stateful`.

### The safety-lint gate

`SafetyLintTests` proves no shipped catalog rule can resolve onto deny-listed data (against planted bait), and that the deny-list fires. A red safety-lint means a rule resolves onto protected data — **fix the rule, never the assertion**.

## Adding/changing catalog rules

Edit `Sources/GlowKit/Resources/catalog.json` only. Keep `swift test` green; obey the glob/base constraints above. `CatalogContentTests` additionally enforces coverage breadth, non-empty `why`/`paths`, allowed categories, no `**`, and that privacy/session paths are not default-`safe`.

## App layer

`AppModel` (`@MainActor`, `ObservableObject`) drives the SwiftUI app. All collaborators (`catalog`, `inventory`, `home`, `mover`, `storeURL`) are injected for testability; `AppModel.live()` wires the real bundled catalog, system services, real `$HOME`, and the history store at `Application Support/GlowUp/history.json`. Phase machine: `idle → scanning → results → cleaning → done`.

## Deliberately excluded (anti-snake-oil)

RAM purge, DNS flush, auto-emptying Trash, deleting language packs, iOS backup deletion. Don't add these.
