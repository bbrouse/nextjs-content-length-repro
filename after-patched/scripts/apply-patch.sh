#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ESM_TEMPLATE="$PROJECT_DIR/node_modules/next/dist/esm/build/templates/pages.js"
CJS_TEMPLATE="$PROJECT_DIR/node_modules/next/dist/build/templates/pages.js"

BEFORE='Buffer.from(JSON.stringify(result.value.pageData))'
AFTER='JSON.stringify(result.value.pageData)'

patched=0

for file in "$ESM_TEMPLATE" "$CJS_TEMPLATE"; do
  if [ ! -f "$file" ]; then
    echo "Warning: $file not found, skipping"
    continue
  fi

  if grep -q "$BEFORE" "$file"; then
    sed -i.bak "s|$BEFORE|$AFTER|g" "$file" && rm -f "$file.bak"
    echo "Patched: $file"
    patched=$((patched + 1))
  else
    echo "Already patched or pattern not found: $file"
  fi
done

if [ "$patched" -gt 0 ]; then
  echo ""
  echo "Patch applied. Run 'npm run build' to rebuild with the fix."
else
  echo ""
  echo "No files needed patching."
fi
