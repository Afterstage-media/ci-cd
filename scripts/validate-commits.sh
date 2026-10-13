#!/usr/bin/env bash
set -euo pipefail
range="${1:-HEAD~1..HEAD}"
subjects="$(git log --format=%s "${range}")"
[[ -z "${subjects}" ]] && exit 0
while IFS= read -r subject; do
  [[ "${subject}" =~ ^Merge[[:space:]] ]] && continue
  grep -Eq '^(feat|fix|perf|docs|refactor|test|build|ci|chore|revert)(\([^)]*\))?!?:[[:space:]].+' <<< "${subject}" || { echo "Commit fuera de Conventional Commits: ${subject}" >&2; exit 1; }
done <<< "${subjects}"
