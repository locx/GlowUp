# GlowUp — Plan 7: Packaging & Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold everything needed to ship GlowUp — CI (build+test+safety-lint), a tag-driven sign/notarize/DMG release workflow, hardened-runtime entitlements, an app Info.plist, a DMG build script, a Homebrew cask, and repo-hygiene docs.

**Architecture:** All **new files**; no source or `Package.swift` changes. CI runs `swift build` + `swift test` (the test suite already includes the safety-lint gate) + `bash -n`. The release workflow and DMG script are **scaffolds**: they reference user-provided signing secrets by name only and are run by the maintainer — this tooling never handles credentials and never executes signing/notarization/publishing.

**Tech Stack:** GitHub Actions (macOS runner), `codesign`/`notarytool`/`stapler`, `hdiutil`, Homebrew cask, Markdown.

**Spec source:** `docs/superpowers/specs/2026-06-06-glowup-spec.md` (§11 distribution & trust, §10 testing/CI, §2 safety for SECURITY.md).

---

## Plan set (this is Plan 7 of 7 — final)

1. Foundation ✅ · 2. Engine ✅ · 3. Catalog content ✅ · 4. App ✅ · 5. CLI ✅ · 6. Advanced scanners ✅ · **7. Packaging ← this doc**

---

## Preconditions & boundaries

- Plans 1–6 built and green (81 tests). This plan adds **only new files**.
- **No git, no credentials, no network** (CLAUDE.md §1.1/§1.3/§1.6). Therefore:
  - CI/release YAML, entitlements, Info.plist, DMG script, cask, and docs are **created**.
  - Actual **signing, notarization, DMG creation, and publishing are NOT run here** — they require an Apple Developer ID, secrets, and network/git the tooling must not touch. The maintainer runs them; the commands are emitted at the end.
  - The Homebrew cask `sha256` and release URLs are placeholders the release workflow fills.
- **Verification for this plan** (config/docs only — `tests-waived: packaging is config/docs; verified by parse/lint`): YAML parses, plist is valid, shell scripts pass `bash -n`, and `swift test` is still green (unchanged).

---

## File structure (this plan)

- Create: `.gitignore`
- Create: `LICENSE` (MIT)
- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Create: `.github/ISSUE_TEMPLATE/feature_request.md`
- Create: `packaging/GlowUp.entitlements`
- Create: `packaging/Info.plist`
- Create: `packaging/make-dmg.sh`
- Create: `Casks/glowup.rb`

---

### Task 1: Repo hygiene baseline

**Files:** `.gitignore`, `LICENSE`, `CHANGELOG.md`

- [ ] **Step 1: `.gitignore`**

```gitignore
.build/
.swiftpm/
DerivedData/
*.xcuserstate
.DS_Store
dist/
*.dmg
```

- [ ] **Step 2: `LICENSE`** (MIT)

```text
MIT License

Copyright (c) 2026 Lokesh Chauhan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to GlowUp are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- GlowKit safety spine: catalog loader, symbolic-base resolver, hardcoded deny-list veto, safety-lint gate.
- Engine: inventory, scanner, concurrent size measurement, trash-only delete, restore store, lazy tree.
- Curated risk-tiered catalog (browsers, apps, dev caches, Xcode, user logs).
- GlowUp SwiftUI app and `glowup` CLI.
- Advanced scanners: orphans, project artifacts, workspaceStorage, duplicate extensions, large-file report.
- Packaging scaffold: CI, signing/notarize release workflow, DMG script, Homebrew cask.
```

---

### Task 2: README, CONTRIBUTING, SECURITY

**Files:** `README.md`, `CONTRIBUTING.md`, `SECURITY.md`

- [ ] **Step 1: `README.md`**

```markdown
# GlowUp

A free, open-source macOS cleanup utility you can trust. GlowUp reclaims
meaningful disk space while making data loss structurally hard.
**Safety is the product; reclaim is the feature.**

- **GlowUp** — the SwiftUI app · **GlowKit** — the UI-free core library · **glowup** — the CLI.

## Safety model

Three independent layers; a candidate is cleaned only if it passes all three:

1. **Allowlist-first.** Nothing is cleaned unless a vetted catalog rule names it.
   The default run is `risk == safe` only.
2. **Deny-list veto** — hardcoded in GlowKit, not catalog-overridable. Every
   candidate is canonicalized and rejected if it touches a protected location
   (Documents, Desktop, Downloads, Pictures, Mail, Keychains, `.ssh`, credential
   files, …) or sits at/above a base root.
3. **Recoverable + reversible.** Trash-only, dry-run by default, explicit
   confirm, and **Restore last cleanup** that survives relaunch.

## Trust

- **No telemetry. No network. Open source (MIT).**
- The full cleanup [catalog](Sources/GlowKit/Resources/catalog.json) is public and auditable.

## Build & test

```sh
swift build
swift test          # includes the safety-lint gate over the shipped catalog
```

## CLI usage

```sh
glowup            # dry-run (default): shows what would be freed, moves nothing
glowup --list     # list candidates
glowup --clean    # move safe-tier items to the Trash (recoverable)
glowup --advanced # include non-safe tiers
glowup --json     # machine-readable output
glowup --restore  # put back the last cleanup
glowup --no-color # plain output
```

## Deliberately excluded (anti-snake-oil)

RAM purge, DNS flush, auto-emptying Trash, deleting language packs, iOS backup deletion.
```

- [ ] **Step 2: `CONTRIBUTING.md`**

```markdown
# Contributing to GlowUp

Thanks for helping make GlowUp better.

## Development

```sh
swift build
swift test
bash -n scripts/glowup.sh
```

## Adding a catalog rule

- Edit [`Sources/GlowKit/Resources/catalog.json`](Sources/GlowKit/Resources/catalog.json).
- Use only symbolic `base` roots (`home`, `appSupport`, `caches`, `logs`, `xcode`)
  and single-segment `*` globs — no `**`, no absolute paths, no `..`.
- Only caches belong in the `safe` tier. Cookies/history are `privacy`;
  sessions/local-storage are `stateful`. Both are off by default.
- **The safety-lint must stay green** (`swift test`). A failing safety-lint means
  the rule resolves onto protected data — fix the rule, never the assertion.

## Tests

Every behavior change needs a test. The deny-list and safety-lint are
load-bearing; do not weaken their assertions to make a build pass.
```

- [ ] **Step 3: `SECURITY.md`**

```markdown
# Security Policy

## Reporting a vulnerability

Please report security issues privately to the maintainer rather than opening a
public issue. Include steps to reproduce and the affected version.

## Safety design

GlowUp is built so that a bug is unlikely to cause data loss:

- A hardcoded, non-overridable deny-list vetoes any candidate that touches a
  protected location or a credential file; it canonicalizes paths (resolving
  symlinks) before checking.
- Cleanup is Trash-only and reversible; the app never deletes outright.
- A CI safety-lint resolves every shipped catalog rule against a synthetic home
  and fails the build if anything escapes the allowed roots or hits the deny-list.

If you find a way to make GlowUp delete or surface protected data, that is a
security bug — please report it.
```

---

### Task 3: CI workflow

**Files:** `.github/workflows/ci.yml`

- [ ] **Step 1: Write CI**

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Show Swift version
        run: swift --version
      - name: Build
        run: swift build
      - name: Test (includes safety-lint gate)
        run: swift test
      - name: Lint bash fallback
        run: bash -n scripts/glowup.sh
```

- [ ] **Step 2: Validate YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml ok')"`
Expected: `ci.yml ok`.

---

### Task 4: Release workflow (scaffold — maintainer-run)

**Files:** `.github/workflows/release.yml`

- [ ] **Step 1: Write the release scaffold**

Secrets are referenced by name only; the workflow never embeds credentials.

```yaml
name: Release

on:
  push:
    tags: [ "v*" ]

# Requires maintainer-provided secrets:
#   MACOS_CERT_P12_BASE64, MACOS_CERT_PASSWORD, KEYCHAIN_PASSWORD,
#   AC_API_KEY_ID, AC_API_ISSUER_ID, AC_API_KEY_P8_BASE64, DEVELOPER_ID_APP
jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Build release
        run: swift build -c release --product GlowUp

      - name: Assemble app bundle + DMG
        run: bash packaging/make-dmg.sh

      - name: Import signing certificate
        env:
          CERT: ${{ secrets.MACOS_CERT_P12_BASE64 }}
          CERT_PW: ${{ secrets.MACOS_CERT_PASSWORD }}
          KC_PW: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          echo "$CERT" | base64 --decode > /tmp/cert.p12
          security create-keychain -p "$KC_PW" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$KC_PW" build.keychain
          security import /tmp/cert.p12 -k build.keychain -P "$CERT_PW" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PW" build.keychain

      - name: Codesign (hardened runtime)
        env:
          DEV_ID: ${{ secrets.DEVELOPER_ID_APP }}
        run: |
          codesign --force --options runtime --timestamp \
            --entitlements packaging/GlowUp.entitlements \
            --sign "$DEV_ID" dist/GlowUp.app

      - name: Notarize + staple
        env:
          KEY_ID: ${{ secrets.AC_API_KEY_ID }}
          ISSUER: ${{ secrets.AC_API_ISSUER_ID }}
          KEY_P8: ${{ secrets.AC_API_KEY_P8_BASE64 }}
        run: |
          echo "$KEY_P8" | base64 --decode > /tmp/ac_key.p8
          xcrun notarytool submit dist/GlowUp.dmg \
            --key /tmp/ac_key.p8 --key-id "$KEY_ID" --issuer "$ISSUER" --wait
          xcrun stapler staple dist/GlowUp.dmg

      - name: Publish release
        uses: softprops/action-gh-release@v2
        with:
          files: dist/GlowUp.dmg
```

- [ ] **Step 2: Validate YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('release.yml ok')"`
Expected: `release.yml ok`.

---

### Task 5: Entitlements + Info.plist

**Files:** `packaging/GlowUp.entitlements`, `packaging/Info.plist`

- [ ] **Step 1: `packaging/GlowUp.entitlements`** (hardened runtime; not sandboxed — needs Full Disk Access)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <false/>
</dict>
</plist>
```

- [ ] **Step 2: `packaging/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GlowUp</string>
  <key>CFBundleDisplayName</key><string>GlowUp</string>
  <key>CFBundleIdentifier</key><string>com.glowup.app</string>
  <key>CFBundleExecutable</key><string>GlowUp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Lokesh Chauhan. MIT licensed.</string>
</dict>
</plist>
```

- [ ] **Step 3: Validate both plists**

Run: `plutil -lint packaging/GlowUp.entitlements packaging/Info.plist`
Expected: both report `OK`. (If `plutil` is unavailable, validate as XML with `python3 -c "import plistlib; plistlib.load(open('packaging/Info.plist','rb')); plistlib.load(open('packaging/GlowUp.entitlements','rb')); print('plists ok')"`.)

---

### Task 6: DMG build script (maintainer-run)

**Files:** `packaging/make-dmg.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Assemble GlowUp.app from the release build and produce dist/GlowUp.dmg.
# Run by the maintainer/CI; does not sign or notarize (the workflow does that).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${ROOT}/.build/release/GlowUp"
APP="${ROOT}/dist/GlowUp.app"
DMG="${ROOT}/dist/GlowUp.dmg"

[ -x "${BIN}" ] || { echo "Build first: swift build -c release --product GlowUp" >&2; exit 1; }

rm -rf "${APP}" "${DMG}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/GlowUp"
cp "${ROOT}/packaging/Info.plist" "${APP}/Contents/Info.plist"

hdiutil create -volname "GlowUp" -srcfolder "${APP}" -ov -format UDZO "${DMG}"
echo "Created ${DMG}"
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n packaging/make-dmg.sh`
Expected: exit 0.

---

### Task 7: Homebrew cask

**Files:** `Casks/glowup.rb`

- [ ] **Step 1: Write the cask** (version/sha filled by the release process)

```ruby
cask "glowup" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/lokeshchauhan/GlowUp/releases/download/v#{version}/GlowUp.dmg"
  name "GlowUp"
  desc "Safe, open-source macOS cleanup utility"
  homepage "https://github.com/lokeshchauhan/GlowUp"

  depends_on macos: ">= :ventura"

  app "GlowUp.app"

  zap trash: [
    "~/Library/Application Support/GlowUp",
  ]
end
```

- [ ] **Step 2: Sanity-check the Ruby parses** (if `ruby` is available)

Run: `ruby -c Casks/glowup.rb`
Expected: `Syntax OK`. (If `ruby` is unavailable, skip — the cask is validated by `brew audit` at publish time.)

---

### Task 8: Issue templates + final verification

**Files:** `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`

- [ ] **Step 1: `bug_report.md`**

```markdown
---
name: Bug report
about: Report a problem with GlowUp
labels: bug
---

**What happened**

**Steps to reproduce**

**Expected**

**macOS version / GlowUp version**

**Did it involve cleaning or restoring?** (helps triage safety issues)
```

- [ ] **Step 2: `feature_request.md`**

```markdown
---
name: Feature request
about: Suggest an idea for GlowUp
labels: enhancement
---

**The problem**

**Proposed solution**

**Safety considerations** (does it touch user files? which?)
```

- [ ] **Step 3: Final verification (config/docs only)**

Run: `swift test`
Expected: still 81 tests green (this plan changed no source).

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); yaml.safe_load(open('.github/workflows/release.yml')); print('workflows ok')"`
Expected: `workflows ok`.

Run: `bash -n packaging/make-dmg.sh`
Expected: exit 0.

---

## Self-review notes

- **Spec coverage (§11):** open-source MIT (LICENSE) ✓; public auditable catalog (README links it) ✓; no-telemetry/no-network stated prominently (README + SECURITY) ✓; Hardened Runtime + Developer-ID sign + notarize + stapled DMG (release.yml + entitlements) ✓; not sandboxed (entitlements: app-sandbox false) ✓; Homebrew cask `glowup` ✓; GitHub Actions build+test+safety-lint, tag→sign/notarize/publish (ci.yml + release.yml) ✓; repo hygiene README/LICENSE/CHANGELOG/CONTRIBUTING/SECURITY/issue templates ✓.
- **Credentials never handled (§1.3):** signing certs and App Store Connect keys are referenced only as named GitHub secrets; no values appear anywhere. The release workflow and DMG script are maintainer/CI-run.
- **Honest scope:** signing, notarization, DMG creation, and publishing are **not executed** in this build — they need an Apple Developer ID, secrets, network, and git that this tooling must not touch. They are scaffolded and emitted as commands for the maintainer.
- **Verification is parse/lint** (config/docs only; `tests-waived: packaging is config/docs`): YAML parses, plists are valid, shell scripts pass `bash -n`, and the unchanged `swift test` stays green.
- **New files only:** no source or `Package.swift` change; the engine, app, CLI, and safety spine are untouched.
```