#!/bin/sh
# Reports localization entries that are still stale source English.
#
# en-US.lproj is the source and fallback. Every other non-English locale starts as a
# full English copy, so any value still identical to en-US is untranslated. English
# variants (en-*) and the POSIX C locale are English by design and are skipped.
# Also reports keys missing from a locale or left over after removal from en-US.
#
# Usage: Tools/check-localizations.sh [-v] [LOCALIZATION_DIR]
#   -v  list every stale key, not only the count per locale
# Exit status: 0 nothing stale, 1 stale or mismatched entries found, 2 usage error.
# Keys whose value is the same in every language (names) go in
# Tools/localization-identical-keys.txt, one per line.

set -eu

verbose=0
if [ "${1:-}" = "-v" ]; then verbose=1; shift; fi
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dir=${1:-"$root/Sources/ChessContent/Resources/Localization"}
allow="$root/Tools/localization-identical-keys.txt"
source_locale=en-US

if [ ! -d "$dir/$source_locale.lproj" ]; then
    echo "error: no $source_locale.lproj in $dir" >&2
    exit 2
fi

# Prints "key<TAB>value" for every entry of a .strings file (one entry per line)
# and "key/category<TAB>value" for every plural form of a .stringsdict file.
entries() {
    [ -f "$1" ] || return 0
    awk '
        FILENAME ~ /\.strings$/ && /^"[^"]+"[ ]*=[ ]*".*";[ ]*$/ {
            key = $0; sub(/^"/, "", key); sub(/".*/, "", key)
            value = $0; sub(/^"[^"]+"[ ]*=[ ]*"/, "", value); sub(/";[ ]*$/, "", value)
            print key "\t" value
        }
        FILENAME ~ /\.stringsdict$/ {
            if (match($0, /^\t<key>[^<]*<\/key>/)) { top = $0; gsub(/^\t<key>|<\/key>.*$/, "", top); next }
            if (match($0, /<key>[^<]*<\/key>/)) { inner = $0; gsub(/^[ \t]*<key>|<\/key>.*$/, "", inner); next }
            if (inner != "" && inner !~ /^NSString/ && match($0, /<string>.*<\/string>/)) {
                value = $0; gsub(/^[ \t]*<string>|<\/string>.*$/, "", value)
                print top "/" inner "\t" value
            }
            inner = ""
        }
    ' "$1"
}

locale_entries() {
    entries "$dir/$1.lproj/Localizable.strings"
    entries "$dir/$1.lproj/Localizable.stringsdict"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
locale_entries "$source_locale" | sort > "$tmp/source"
if [ -f "$allow" ]; then sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$allow" | sort -u > "$tmp/allow"; else : > "$tmp/allow"; fi

status=0
checked=0
for path in "$dir"/*.lproj; do
    locale=$(basename "$path" .lproj)
    case $locale in "$source_locale") continue ;; esac
    checked=$((checked + 1))
    locale_entries "$locale" | sort > "$tmp/locale"
    cut -f1 "$tmp/source" > "$tmp/source-keys"
    cut -f1 "$tmp/locale" > "$tmp/locale-keys"
    comm -23 "$tmp/source-keys" "$tmp/locale-keys" > "$tmp/missing"
    comm -13 "$tmp/source-keys" "$tmp/locale-keys" > "$tmp/obsolete"
    case $locale in
        en-* | C) : > "$tmp/stale" ;;
        *)
            # Identical key and value, ignoring allowed keys (a plural form "key/one"
            # is allowed when "key" is) and values with no word of three letters or more.
            comm -12 "$tmp/source" "$tmp/locale" | awk -F '\t' -v allow="$tmp/allow" '
                BEGIN { while ((getline line < allow) > 0) allowed[line] = 1 }
                {
                    base = $1; sub(/\/.*/, "", base)
                    text = $2; gsub(/%(#@[A-Za-z0-9_]+@|([0-9]+\$)?[-+0-9.#]*[@a-zA-Z])/, "", text)
                    if (!($1 in allowed) && !(base in allowed) && text ~ /[A-Za-z][A-Za-z][A-Za-z]/) print $1
                }' > "$tmp/stale"
            ;;
    esac
    for kind in stale missing obsolete; do
        count=$(wc -l < "$tmp/$kind" | tr -d ' ')
        [ "$count" -eq 0 ] && continue
        status=1
        echo "$locale: $count $kind"
        if [ "$verbose" -eq 1 ]; then sed 's/^/    /' "$tmp/$kind"; fi
    done
done

if [ "$status" -eq 0 ]; then
    echo "ok: $checked locales, no stale English, keys match $source_locale"
fi
exit "$status"
