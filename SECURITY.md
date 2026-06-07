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
