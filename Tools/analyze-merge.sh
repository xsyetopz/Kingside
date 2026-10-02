#!/bin/sh
# Combines Tools/analyze.sh results and fails on code that is unused on every platform.
#
# A finding counts only when every platform that compiles its file reports it: an import that
# macOS does not need can still be needed by #if os(iOS) code.
#
# Usage: Tools/analyze-merge.sh OUTDIR...   (the OUTDIRs written by Tools/analyze.sh)
# Exit status: 0 no finding on every platform, 1 findings printed, 2 usage error.

set -eu

[ $# -ge 1 ] || { echo "usage: $0 OUTDIR..." >&2; exit 2; }
for dir in "$@"; do
  [ -f "$dir/findings.txt" ] && [ -f "$dir/compiled.txt" ] || { echo "$dir: no Tools/analyze.sh results" >&2; exit 2; }
done

# Counts the platforms that compile each file and the platforms that report each finding.
findings=$(
  for dir in "$@"; do
    sed 's/^/C /' "$dir/compiled.txt"
    sed 's/^/F /' "$dir/findings.txt"
  done | awk '
    $1 == "C" { compiled[$2]++; next }
    {
      line = substr($0, 3)
      file = line; sub(/:.*/, "", file)
      seen[line]++
      if (!(line in fileof)) { fileof[line] = file; order[++n] = line }
    }
    END { for (i = 1; i <= n; i++) if (seen[order[i]] == compiled[fileof[order[i]]]) print order[i] }
  ' | sort
)

[ -z "$findings" ] && { echo "No code is unused on every platform."; exit 0; }
printf '%s\n' "$findings"
echo "$(printf '%s\n' "$findings" | wc -l | tr -d ' ') findings are unused on every platform that compiles their file."
exit 1
