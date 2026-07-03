#!/usr/bin/env bash
# Build, ad-hoc-sign, and package GlowUp for FREE distribution (no Apple Developer ID).
# Ad-hoc signing is required for arm64 apps to launch; it is NOT notarization, so a
# downloaded app is still quarantined until the user clears it (see notes below).
#
# Usage:
#   bash packaging/package.sh                     # build dist/GlowUp.dmg, install app to /Applications
#   VERSION=v0.1.0 PUBLISH=1 bash packaging/package.sh   # also create a GitHub release
#
# Free install paths for end users:
#   - brew install --cask --no-quarantine <your-tap>/glowup  # skips Gatekeeper for the unsigned app
#   - download the DMG, then: xattr -dr com.apple.quarantine /Applications/GlowUp.app
#   - build from source: swift build -c release --product GlowUp
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-v0.0.1}"
DIST="${ROOT}/dist"
APP="${DIST}/GlowUp.app"
DMG="${DIST}/GlowUp.dmg"
INSTALLED="/Applications/GlowUp.app"

swift build -c release --product GlowUpApp

# Assemble the .app bundle + DMG via the shared assembler (single source of truth).
bash "${ROOT}/packaging/make-dmg.sh"

# Ad-hoc signature: the minimum for an arm64 bundle to run at all (free, no cert).
codesign --force --deep --sign - "${APP}"
codesign --verify --strict "${APP}"

# Refresh the DMG from the now-signed bundle (the distributable artifact).
hdiutil create -volname "GlowUp" -srcfolder "${APP}" -ov -format UDZO "${DMG}"

# Install into /Applications, replacing any prior copy; dist/ keeps only the dmg.
rm -rf "${INSTALLED}"
mv "${APP}" "${INSTALLED}"

SHA="$(shasum -a 256 "${DMG}" | cut -d' ' -f1)"
echo "Packaged:"
echo "  ${DMG}"
echo "  installed: ${INSTALLED}"
echo "  sha256(dmg) = ${SHA}"

if [ "${PUBLISH:-0}" = "1" ]; then
  command -v gh >/dev/null 2>&1 || { echo "gh CLI required to publish" >&2; exit 2; }
  gh release create "${VERSION}" "${DMG}" \
    --prerelease \
    --title "GlowUp ${VERSION}" \
    --notes "Unsigned (ad-hoc) build — not notarized.

Install via Homebrew (recommended): brew removes the quarantine flag automatically.
Or download the DMG and run once:
    xattr -dr com.apple.quarantine /Applications/GlowUp.app

dmg sha256: ${SHA}"
  echo "Published ${VERSION}."
fi
