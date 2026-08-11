#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'usage: %s COMPILER TARGET-LABEL OUTPUT-DIR\n' "$0" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$1"
TARGET_LABEL="$2"
OUTPUT_DIR="$3"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
PACKAGE="tungsten-$VERSION-$TARGET_LABEL"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-release.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT INT TERM

if [[ ! -x "$COMPILER" ]]; then
  printf 'release compiler is missing or not executable: %s\n' "$COMPILER" >&2
  exit 1
fi

mkdir -p "$STAGE/$PACKAGE" "$OUTPUT_DIR"
# Ship the complete toolchain and standard library, but leave the 277 MB
# benchmark corpus and developer-only spec fixtures in the source archive.
# Every listed path is tracked; a missing path therefore makes packaging fail.
git -C "$ROOT" archive --format=tar HEAD -- \
  .ruby-version Bitfile COPYRIGHT Dockerfile Gemfile LICENSE-APACHE LICENSE-MIT \
  Makefile README.md Rakefile TODO.md VERSION \
  bin bits compiler core data doc implementations languages runtime scripts \
  services | tar -xf - -C "$STAGE/$PACKAGE"
cp "$COMPILER" "$STAGE/$PACKAGE/bin/tungsten-compiler"
chmod 755 "$STAGE/$PACKAGE/bin/tungsten-compiler" "$STAGE/$PACKAGE/bin/tungsten"

tar -C "$STAGE" -czf "$OUTPUT_DIR/$PACKAGE.tar.gz" "$PACKAGE"
printf '%s\n' "$OUTPUT_DIR/$PACKAGE.tar.gz"
