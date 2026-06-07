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
