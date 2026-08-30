#!/usr/bin/env bash
# Downloads Tabler outline icons and generates template image sets.
# Usage: scripts/fetch-tabler-icons.sh
set -euo pipefail

# jsdelivr's @<exact-version> npm URLs are immutable once published, so pinning VERSION without a
# checksum is safe: the same version always resolves to the same bytes. There is no vendored hash
# to compare against, but the fetched SVGs and LICENSE are committed to the repo, so bumping
# VERSION is reviewable as an ordinary diff of what changed.
VERSION="3.46.0"
BASE="https://cdn.jsdelivr.net/npm/@tabler/icons@${VERSION}/icons/outline"
DEST="$(cd "$(dirname "$0")/.." && pwd)/Spark/Assets.xcassets/Icons"

ICONS=(
  activity adjustments-horizontal alert-triangle arrow-down arrow-right arrow-up
  bell-bolt bell-ringing calendar-month chart-bar chart-line chevron-left
  chevron-right circle-arrow-up circle-check circle-plus circle-x clock download
  external-link eye eye-off help-circle heart history key
  layout-grid link link-plus moon numbers palette power refresh refresh-alert
  report-analytics rosette-discount-check send server settings terminal-2
  world
)

tmp_download=""
cleanup() {
  if [[ -n "$tmp_download" && -f "$tmp_download" ]]; then
    rm -f "$tmp_download"
  fi
}
trap cleanup EXIT

mkdir -p "$DEST"
tmp_download="$(mktemp)"
curl -fsSL "https://cdn.jsdelivr.net/npm/@tabler/icons@${VERSION}/LICENSE" -o "$tmp_download"
mv "$tmp_download" "$DEST/TABLER-LICENSE"
tmp_download=""

for name in "${ICONS[@]}"; do
  imageset_dir="$DEST/${name}.imageset"
  mkdir -p "$imageset_dir"
  tmp_download="$(mktemp)"
  curl -fsSL "$BASE/${name}.svg" -o "$tmp_download"
  mv "$tmp_download" "$imageset_dir/${name}.svg"
  tmp_download=""
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
