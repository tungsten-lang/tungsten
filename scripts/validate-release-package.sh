#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'usage: %s PACKAGE TARGET-LABEL\n' "$0" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$1"
TARGET_LABEL="$2"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
PACKAGE="tungsten-$VERSION-$TARGET_LABEL"
EXPECTED_NAME="$PACKAGE.tar.gz"

if [[ ! "$TARGET_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'invalid release target label: %s\n' "$TARGET_LABEL" >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
  printf 'release package is missing: %s\n' "$ARCHIVE" >&2
  exit 1
fi
if [[ "$(basename "$ARCHIVE")" != "$EXPECTED_NAME" ]]; then
  printf 'release package name is %s, expected %s\n' \
    "$(basename "$ARCHIVE")" "$EXPECTED_NAME" >&2
  exit 1
fi

WORK="$ROOT/build/cache/release-package-validation"
LISTING="$WORK/$TARGET_LABEL.list"
EXTRACTED="$WORK/$TARGET_LABEL"
rm -rf "$EXTRACTED"
mkdir -p "$WORK" "$EXTRACTED"

tar -tzf "$ARCHIVE" > "$LISTING"
if ! awk -v root="$PACKAGE" '
  $0 != root && index($0, root "/") != 1 { exit 1 }
  $0 ~ /(^|\/)\.\.($|\/)/ { exit 1 }
  $0 ~ /^\// { exit 1 }
' "$LISTING"; then
  printf 'release package has an unsafe or unexpected archive path\n' >&2
  exit 1
fi

for path in \
  VERSION \
  bin/tungsten \
  bin/tungsten-compiler \
  core/tungsten.w \
  data/units.tsv \
  doc/CORE.md \
  runtime/runtime.c
do
  if ! grep -Fxq "$PACKAGE/$path" "$LISTING"; then
    printf 'release package is missing %s\n' "$path" >&2
    exit 1
  fi
done

tar -xzf "$ARCHIVE" -C "$EXTRACTED"
PACKAGE_ROOT="$EXTRACTED/$PACKAGE"
if [[ "$(tr -d '[:space:]' < "$PACKAGE_ROOT/VERSION")" != "$VERSION" ]]; then
  printf 'release package VERSION does not match %s\n' "$VERSION" >&2
  exit 1
fi
if [[ ! -x "$PACKAGE_ROOT/bin/tungsten" || ! -x "$PACKAGE_ROOT/bin/tungsten-compiler" ]]; then
  printf 'release package launchers are not executable\n' >&2
  exit 1
fi

printf 'PASS release package %s\n' "$EXPECTED_NAME"
