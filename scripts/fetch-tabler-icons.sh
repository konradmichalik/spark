#!/usr/bin/env bash
# Downloads Tabler outline icons and generates template image sets.
# Usage: scripts/fetch-tabler-icons.sh
set -euo pipefail

VERSION="3.46.0"
BASE="https://cdn.jsdelivr.net/npm/@tabler/icons@${VERSION}/icons/outline"
DEST="$(cd "$(dirname "$0")/.." && pwd)/Spark/Assets.xcassets/Icons"

ICONS=(
  activity adjustments-horizontal alert-triangle arrow-down arrow-right arrow-up
  bell bell-bolt bell-ringing calendar-month chart-bar chart-line chevron-left
  chevron-right circle-arrow-up circle-check circle-plus circle-x clock download
  external-link eye eye-off folders help-circle heart history info-circle key
  layout-grid layout-navbar link link-plus moon numbers palette power refresh refresh-alert
  report-analytics rosette-discount-check send server settings sparkles terminal-2
  user-circle world
)

mkdir -p "$DEST"
curl -fsSL "https://cdn.jsdelivr.net/npm/@tabler/icons@${VERSION}/LICENSE" \
  -o "$DEST/TABLER-LICENSE"

for name in "${ICONS[@]}"; do
  imageset_dir="$DEST/${name}.imageset"
  mkdir -p "$imageset_dir"
  curl -fsSL "$BASE/${name}.svg" -o "$imageset_dir/${name}.svg"
  cat > "$imageset_dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "${name}.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-data" : true,
    "template-rendering-intent" : "template"
  }
}
JSON
done

cat > "$DEST/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "provides-namespace" : false
  }
}
JSON

echo "Generated ${#ICONS[@]} image sets in $DEST"
