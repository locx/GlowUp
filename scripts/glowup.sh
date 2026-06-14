#!/usr/bin/env bash
# Catalog-driven list/dry-run fallback; needs jq. No deletion — read-only.
set -euo pipefail

# DIAGNOSTIC/LISTING ONLY — this script does NOT apply the Swift deny-list or glob
# safety checks, so the paths it prints may differ from what the GlowUp binary surfaces.
# Do not use this output to manually delete files.

CATALOG="${1:-$(dirname "$0")/../Sources/GlowKit/Resources/catalog.json}"
HOME_DIR="${HOME}"

# A flag-looking $1 would otherwise be fed to jq as a catalog path and die cryptically.
if [ ! -f "${CATALOG}" ]; then
  echo "usage: glowup.sh [catalog.json]" >&2; exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "glowup.sh requires jq" >&2; exit 2
fi

base_dir() {
  case "$1" in
    home) echo "${HOME_DIR}" ;;
    appSupport) echo "${HOME_DIR}/Library/Application Support" ;;
    caches) echo "${HOME_DIR}/Library/Caches" ;;
    logs) echo "${HOME_DIR}/Library/Logs" ;;
    xcode) echo "${HOME_DIR}/Library/Developer/Xcode" ;;
    *) echo "" ;;
  esac
}

total=0
while IFS=$'\t' read -r base glob risk; do
  [ "${risk}" = "safe" ] || continue
  root="$(base_dir "${base}")"
  [ -n "${root}" ] || continue
  # Only expand safe, non-recursive globs; '*' is a single segment.
  prefix="${glob%%\**}"; rest="${glob#*\*}"; matches=()
  if [ "${glob}" = "${prefix}" ]; then matches=("${root}/${glob}")
  else for d in "${root}/${prefix}"*; do [ -e "${d}${rest}" ] && matches+=("${d}${rest}"); done; fi
  [ "${#matches[@]}" -gt 0 ] || continue
  for path in "${matches[@]}"; do
    [ -e "${path}" ] || continue
    size=$(du -sk "${path}" 2>/dev/null | cut -f1)
    # Empty/non-numeric du output would crash the arithmetic under `set -e`; treat it as 0.
    [ -n "${size}" ] && [ "${size}" -eq "${size}" ] 2>/dev/null || size=0
    total=$((total + size))
    echo "  [${risk}] ${path}"
  done
done < <(jq -r '.rules[] | .risk as $r | .paths[] | [.base, .glob, (.risk // $r)] | @tsv' "${CATALOG}")

# Decimal output so small caches don't truncate to a misleading "0 MB".
echo "Would free ~$(awk "BEGIN{printf \"%.1f\", ${total}/1024}") MB (dry run — nothing was moved)."
