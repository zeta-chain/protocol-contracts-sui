#!/usr/bin/env bash
set -euo pipefail

sui move build --doc
rm -rf docs
mkdir -p docs
rsync -a build/gateway/docs/gateway/ docs/

find docs -name '*.md' -type f | while read -r file; do
  sed -E -i.bak \
    -e 's/<a name="[^"]*"><\/a>//g' \
    -e 's/<a href="[^"]*"[^>]*>//g' \
    -e 's/<\/a>//g' \
    "$file"
  rm -f "${file}.bak"
done