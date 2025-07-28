#!/usr/bin/env bash
set -euo pipefail

sui move build --doc
rm -rf docs
mkdir -p docs
rsync -a build/gateway/docs/gateway/ docs/

if [[ "$(uname)" == "Darwin" ]]; then
  # macOS (BSD sed)
  sed_i() { sed -E -i '' "$@"; }
else
  # Linux (GNU sed)
  sed_i() { sed -E -i "$@"; }
fi

find docs -name '*.md' -type f | while read -r file; do
  sed_i \
    -e 's/<a name="[^"]*"><\/a>//g' \
    -e 's/<a href="[^"]*"[^>]*>//g' \
    -e 's/<\/a>//g' \
    "$file"
done
