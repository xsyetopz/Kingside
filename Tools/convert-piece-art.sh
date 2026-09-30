#!/bin/sh
# Regenerates the bundled vector PDF piece art from the SVG sources.
#
# SpriteKit cannot load SVG, so each Artwork/Pieces/<set>/*.svg becomes
# Sources/ChessContent/Resources/Pieces/<set>/*.pdf through rsvg-convert (librsvg).
# The scene rasterizes the PDFs at the square size it needs.
#
# Usage: Tools/convert-piece-art.sh [SET...]   (default: every set in Artwork/Pieces)

set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$root/Artwork/Pieces"
output_root="$root/Sources/ChessContent/Resources/Pieces"

command -v rsvg-convert >/dev/null 2>&1 || { echo "error: rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
[ -d "$source_root" ] || { echo "error: no SVG sources in $source_root" >&2; exit 1; }

if [ "$#" -eq 0 ]; then
    for dir in "$source_root"/*/; do
        [ -d "$dir" ] && set -- "$@" "$(basename -- "$dir")"
    done
fi

count=0
for set_id in "$@"; do
    case $set_id in */* | .* | '') echo "error: bad set name: $set_id" >&2; exit 2 ;; esac
    [ -d "$source_root/$set_id" ] || { echo "error: no set $set_id in $source_root" >&2; exit 1; }
    mkdir -p "$output_root/$set_id"
    for svg in "$source_root/$set_id"/*.svg; do
        [ -f "$svg" ] || continue
        name=$(basename -- "$svg" .svg)
        rsvg-convert -f pdf -o "$output_root/$set_id/$name.pdf" "$svg"
        count=$((count + 1))
    done
done
echo "converted $count file(s)"
