#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
#
# Fail if any source file is missing the mandatory JFrog copyright header.
# Policy (JFrog OSS): every source file must start with `(c) JFrog Ltd. (YEAR)`
# or `© JFrog Ltd. (YEAR)`. GitHub configuration never enforces this, so it is
# wired into pre-commit + CI here. Reports `<missing>/<total>` and exits
# non-zero on any miss.

set -euo pipefail

roots=("src" "tests" "scripts" "examples")
missing=0
total=0

while IFS= read -r -d '' f; do
  total=$((total + 1))
  if ! head -3 "$f" | grep -q 'JFrog Ltd'; then
    echo "MISSING header: $f"
    missing=$((missing + 1))
  fi
done < <(find "${roots[@]}" -type f \
  \( -name '*.py' -o -name '*.sh' \) -print0 2>/dev/null)

echo "copyright headers: $((total - missing))/${total} present"
if [ "$missing" -gt 0 ]; then
  echo "ERROR: ${missing} file(s) missing the JFrog copyright header."
  exit 1
fi
