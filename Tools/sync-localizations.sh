#!/bin/sh
# Aligns every locale with the en-US source catalog.
#
# Rewrites each locale's Localizable.strings and .stringsdict in source order:
# keys the locale already has keep their value, missing keys get the source English
# value, and keys removed from en-US are dropped. Locales named as arguments that do
# not exist yet are created as full English copies.
#
# Usage: Tools/sync-localizations.sh [NEW_LOCALE...]
# Run Tools/check-localizations.sh afterwards to list what still needs translating.

set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dir=${LOCALIZATION_DIR:-"$root/Sources/ChessContent/Resources/Localization"}
source_dir="$dir/en-US.lproj"

for locale in "$@"; do
    case $locale in */* | .* | '') echo "error: bad locale name: $locale" >&2; exit 2 ;; esac
    [ -d "$dir/$locale.lproj" ] || mkdir "$dir/$locale.lproj"
done

# Source lines are kept; an entry line takes the locale's value when it has one.
sync_strings() {
    awk '
        function key_of(line) { k = line; sub(/^"/, "", k); sub(/".*/, "", k); return k }
        NR == FNR { if ($0 ~ /^"[^"]+"[ ]*=/) have[key_of($0)] = $0; next }
        /^"[^"]+"[ ]*=/ { k = key_of($0); print ((k in have) ? have[k] : $0); next }
        { print }
    ' "$1" "$source_dir/Localizable.strings"
}

# Top-level entries run from a line "<TAB><key>NAME</key>" to the next "<TAB></dict>".
sync_stringsdict() {
    awk '
        function top_key(line) { k = line; gsub(/^\t<key>|<\/key>.*$/, "", k); return k }
        NR == FNR {
            if ($0 ~ /^\t<key>/) { current = top_key($0); block[current] = "" }
            if (current != "") block[current] = block[current] $0 "\n"
            if ($0 ~ /^\t<\/dict>/) current = ""
            next
        }
        $0 ~ /^\t<key>/ { current = top_key($0); if (current in block) { printf "%s", block[current]; skipping = 1 } }
        { if (!skipping) print }
        $0 ~ /^\t<\/dict>/ { current = ""; skipping = 0 }
    ' "$1" "$source_dir/Localizable.stringsdict"
}

for path in "$dir"/*.lproj; do
    [ "$path" = "$source_dir" ] && continue
    for file in Localizable.strings Localizable.stringsdict; do
        target="$path/$file"
        if [ ! -f "$target" ]; then
            cp "$source_dir/$file" "$target"
            continue
        fi
        case $file in
            *.strings) sync_strings "$target" > "$target.tmp" ;;
            *) sync_stringsdict "$target" > "$target.tmp" ;;
        esac
        mv "$target.tmp" "$target"
    done
done
