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
