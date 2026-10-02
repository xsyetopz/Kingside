#!/bin/sh
# Builds the app for one platform and records the unused code that SwiftLint's analyzer rules
# (.swiftlint.yml) and Periphery (.periphery.yml) find in that build.
#
# An import or declaration can be unused on one platform and needed on another, so a single
# platform's findings are not a verdict. Tools/analyze-merge.sh combines the platforms.
#
# Usage: Tools/analyze.sh PLATFORM OUTDIR   (PLATFORM: macOS, iOS, or tvOS; run from the package root)
# Writes OUTDIR/compiled.txt (files this platform compiles) and OUTDIR/findings.txt
# (`path:line: tool/rule: message`, sorted). Exit status: 0 done, 1 build or tool failure, 2 usage error.
# iPadOS compiles from the same SDK as iOS, so the iOS run covers it.

set -eu

case "${1:-}" in
  macOS) destination='generic/platform=macOS' ;;
  iOS) destination='generic/platform=iOS Simulator' ;;
  tvOS) destination='generic/platform=tvOS Simulator' ;;
  *) echo "usage: $0 macOS|iOS|tvOS OUTDIR" >&2; exit 2 ;;
esac
[ $# -eq 2 ] || { echo "usage: $0 macOS|iOS|tvOS OUTDIR" >&2; exit 2; }
platform=$1
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$2"
out=$(CDPATH='' cd -- "$2" && pwd)
cd "$root"
# Periphery runs `swift package describe`; use the selected Xcode's swift, not another one on PATH.
PATH="$(dirname "$(xcrun --find swift)"):$PATH"

# An incremental build logs only the files it recompiles, so start from nothing.
rm -rf "$out/derived" "$out/spm"

xcodebuild -project Kingside.xcodeproj -scheme Kingside -destination "$destination" \
  -derivedDataPath "$out/derived" build CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=YES \
  >"$out/build.log" 2>&1 || { tail -40 "$out/build.log"; exit 1; }
stores="--index-store-path $out/derived/Index.noindex/DataStore"

# The package's test targets build only through SwiftPM, and only for macOS.
if [ "$platform" = macOS ]; then
  swift build --build-tests -v --enable-index-store --scratch-path "$out/spm" \
    >>"$out/build.log" 2>&1 || { tail -40 "$out/build.log"; exit 1; }
  stores="$stores --index-store-path $out/spm/debug/index/store"
fi

grep -o "$root/[^ ]*\.swift" "$out/build.log" | grep -v '/Package\.swift$' | sort -u >"$out/compiled.txt"

# SourceKit's in-process macro plugin server crashes at random (SIGSEGV in its LRUCache) while
# SwiftLint indexes files that use @Test or @Suite. Expanding macros in swift-plugin-server avoids it.
plugin_server=$(xcrun --find swift-plugin-server)
sed -E "s# -in-process-plugin-server-path [^ ]+##g; s# -plugin-path ([^ ]+)# -external-plugin-path \\1\\#$plugin_server#g" \
  "$out/build.log" >"$out/build-oop.log"

# SwiftLint exits 2 when it reports an error-severity violation; any other non-zero status is a failure.
status=0
# shellcheck disable=SC2046 # one argument per path; no path under the package root contains spaces
TOOLCHAIN_DIR=$(dirname "$(dirname "$(dirname "$plugin_server")")") swiftlint analyze --quiet \
  --reporter json --compiler-log-path "$out/build-oop.log" $(cat "$out/compiled.txt") \
  >"$out/swiftlint.json" 2>"$out/swiftlint.err" || status=$?
[ "$status" -eq 0 ] || [ "$status" -eq 2 ] || { tail -20 "$out/swiftlint.err"; exit 1; }

# shellcheck disable=SC2086 # $stores is a list of options
periphery scan --disable-update-check --quiet --skip-build --relative-results $stores \
  >"$out/periphery.txt" 2>"$out/periphery.err" || { cat "$out/periphery.err"; exit 1; }

{
  jq -r --arg root "$root/" '.[] | "\(.file | ltrimstr($root)):\(.line): swiftlint/\(.rule_id): \(.reason)"' \
    "$out/swiftlint.json"
  sed -nE 's/^([^:]+):([0-9]+):[0-9]+: warning: (.*)$/\1:\2: periphery: \3/p' "$out/periphery.txt"
} | sort -u >"$out/findings.txt"
sed -i.bak "s#^$root/##" "$out/compiled.txt" && rm "$out/compiled.txt.bak"
echo "$platform: $(wc -l <"$out/findings.txt" | tr -d ' ') findings in $(wc -l <"$out/compiled.txt" | tr -d ' ') files"
