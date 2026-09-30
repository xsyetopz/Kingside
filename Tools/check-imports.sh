#!/bin/sh
# Fails when a target imports a module that Tools/import-rules.json does not allow,
# or when a directory under Sources/ or Tests/ has no rule.
# Usage: Tools/check-imports.sh [RULES.json]   (run from the package root)
set -eu
rules=${1:-Tools/import-rules.json}
status=0

for root in $(jq -r '.unlisted_roots[]' "$rules"); do
  [ -d "$root" ] || continue
  for dir in "$root"/*/; do
    dir=${dir%/}
    if ! jq -e --arg p "$dir" '[.targets[].path] | index($p)' "$rules" >/dev/null; then
      echo "$dir: no entry in $rules"
      status=1
    fi
  done
done

for target in $(jq -r '.targets | keys[]' "$rules"); do
  path=$(jq -r --arg t "$target" '.targets[$t].path' "$rules")
  allowed=$(jq -r --arg t "$target" '.targets[$t].allow[]' "$rules")
  # Matches `import X`, `@testable import X`, `@preconcurrency import X`, `import struct X.Y`.
  violations=$(
    rg --no-heading -n -g '*.swift' \
      '^\s*(@\w+\s+)*(public\s+|internal\s+|package\s+)?import\s+((typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z0-9_]*)' \
      -or '$5' "$path" |
    while IFS=: read -r file line module; do
      printf '%s\n' "$allowed" | grep -qx "$module" || echo "$file:$line: $target may not import $module"
    done
  )
  if [ -n "$violations" ]; then
    echo "$violations"
    status=1
  fi
done

[ "$status" -eq 0 ] && echo "import rules: ok ($rules)"
exit "$status"
