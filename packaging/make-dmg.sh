#!/usr/bin/env bash
# Assemble GlowUp.app from the release build and produce dist/GlowUp.dmg.
# Run by the maintainer/CI; does not sign or notarize (the workflow does that).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${ROOT}/.build/release/GlowUpApp"
APP="${ROOT}/dist/GlowUp.app"
DMG="${ROOT}/dist/GlowUp.dmg"

[ -x "${BIN}" ] || { echo "Build first: swift build -c release --product GlowUpApp" >&2; exit 1; }

# Generate icon if not already present (CI only checks out tracked files).
[ -f "${ROOT}/packaging/AppIcon.icns" ] || { swift "${ROOT}/packaging/make-icon.swift" && iconutil -c icns "${ROOT}/packaging/GlowUp.iconset" -o "${ROOT}/packaging/AppIcon.icns"; }

BUNDLE="${ROOT}/.build/release/GlowUp_GlowKit.bundle"
# Without the staged resource bundle the binary falls back to the build machine's absolute
# .build path and crashes at launch everywhere else.
[ -d "${BUNDLE}" ] || { echo "Missing ${BUNDLE} — build first" >&2; exit 1; }

rm -rf "${APP}" "${DMG}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/GlowUp"
cp "${ROOT}/packaging/Info.plist" "${APP}/Contents/Info.plist"
cp "${ROOT}/packaging/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
cp -R "${BUNDLE}" "${APP}/Contents/Resources/"

hdiutil create -volname "GlowUp" -srcfolder "${APP}" -ov -format UDZO "${DMG}"
echo "Created ${DMG}"
