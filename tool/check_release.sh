#!/usr/bin/env bash
# Validate publication without uploading anything. Run from any directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "$#" -eq 0 ]]; then
  package_dirs=(packages/*)
else
  package_dirs=()
  for package in "$@"; do
    if [[ "$package" == */* || ! -f "packages/$package/pubspec.yaml" ]]; then
      printf 'Unknown package: %s\n' "$package" >&2
      exit 64
    fi
    package_dirs+=("packages/$package")
  done
fi

flutter pub get
dart analyze --fatal-infos packages
dart format --output=none --set-exit-if-changed packages

failed=0
for package_dir in "${package_dirs[@]}"; do
  printf '\nChecking %s\n' "$package_dir"
  if (
    cd "$package_dir" || exit "$?"
    flutter test || exit "$?"
    if [[ -d example/test ]]; then
      (cd example && flutter test) || exit "$?"
    fi
    flutter pub publish --dry-run
  ); then
    printf 'Passed: %s\n' "$package_dir"
  else
    printf 'Needs attention: %s\n' "$package_dir" >&2
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  printf '\nRelease checks found failures or publication warnings. Nothing was published.\n' >&2
  exit 1
fi
printf '\nRelease checks passed. Nothing was published.\n'
