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

## Security posture

- **Not sandboxed** (`com.apple.security.app-sandbox = false`). Reclaiming caches under
  `~/Library` needs Full Disk Access, which the App Sandbox cannot grant, so GlowUp ships
  unsandboxed — with a hardened runtime and notarization instead.
- **One irreversible action.** Everything GlowUp cleans goes to the Trash and is restorable —
  *except* "Clean System Caches" (Advanced), which deletes `/Library/Caches` as root and cannot be
  undone. It is opt-in, warns before running, and requires an administrator password.

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
