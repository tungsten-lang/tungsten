#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 || ( $# -eq 3 && "$3" != "--structure-only" ) ]]; then
  printf 'usage: %s PACKAGE TARGET-LABEL [--structure-only]\n' "$0" >&2
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
  data/unit_names.txt \
  data/unit_registry.json \
  data/unit_metadata.tsv \
  data/substance_densities.json \
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

# Invoke the extracted compiler directly from an unrelated directory. This
# exercises executable-relative data discovery without the launcher/root env.
if [[ "${3:-}" != "--structure-only" ]]; then
  LEX_SOURCE="$WORK/release-units.w"
  LEX_OUTPUT="$WORK/$TARGET_LABEL.units.out"
  printf '1 mmol/L\n1 eV\n' > "$LEX_SOURCE"
  if ! (cd "$WORK" && env -u TUNGSTEN_ROOT -u TUNGSTEN_UNIT_NAMES \
      "$PACKAGE_ROOT/bin/tungsten-compiler" --lex "$LEX_SOURCE") > "$LEX_OUTPUT" 2>&1 ||
     ! grep -Fq '44 [1, mmol/L]' "$LEX_OUTPUT" ||
     ! grep -Fq '44 [1, eV]' "$LEX_OUTPUT"; then
    printf 'release package unit registry smoke test failed\n' >&2
    head -20 "$LEX_OUTPUT" >&2
    exit 1
  fi
  REPL_OUTPUT="$WORK/$TARGET_LABEL.metadata.out"
  if ! (cd "$WORK" && printf '? 1 m\n' | env -u TUNGSTEN_ROOT -u TUNGSTEN_UNIT_NAMES \
      "$PACKAGE_ROOT/bin/tungsten-compiler" --repl) > "$REPL_OUTPUT" 2>&1 ||
     ! grep -Fq 'etymology' "$REPL_OUTPUT" ||
     ! grep -Fq 'history' "$REPL_OUTPUT"; then
    printf 'release package external unit metadata smoke test failed\n' >&2
    head -20 "$REPL_OUTPUT" >&2
    exit 1
  fi
fi

printf 'PASS release package %s\n' "$EXPECTED_NAME"
