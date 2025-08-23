#!/usr/bin/env bash

modules=$(grep "defmodule" lib/**/*.ex | grep ":defmodule" | awk '/defmodule/ {print $2}')

missing_modules=()

# Loop through each module and check in mix.exs
for module in $modules; do
  if ! grep -Fq "$module" mix.exs; then
    missing_modules+=("$module")
  fi
done

# Final summary
if [ ${#missing_modules[@]} -gt 0 ]; then
  echo "✖ The following modules were missing in mix.exs:"
  for m in "${missing_modules[@]}"; do
    echo "  - $m"
  done
  exit 1
else
  echo "✅ All modules were found in mix.exs"
  exit 0
fi
