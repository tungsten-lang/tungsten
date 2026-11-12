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
  runtime/runtime.c \
  build/compiler-images/tungsten-repl \
  build/compiler-images/tungsten-metal
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
# The compiler execs these for the REPL, --interpret and @gpu programs, and
# never builds one on launch: a package without them ships those modes broken.
IMAGES="$PACKAGE_ROOT/build/compiler-images"
for kind in repl metal; do
  if [[ ! -x "$IMAGES/tungsten-$kind" ]]; then
    printf 'release package compiler image is not executable: tungsten-%s\n' "$kind" >&2
    exit 1
  fi
done

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
  # The Metal image is only exec'd for a @gpu program; prove it starts on
  # this host (right architecture and CPU level) without needing a GPU. An
  # image is never a user entry point: the compiler execs it with its kind and
  # the root that owns it, so this does the same.
  IMAGE_OUTPUT="$WORK/$TARGET_LABEL.metal-image.out"
  if ! (cd "$WORK" && env TUNGSTEN_ROOT="$PACKAGE_ROOT" TUNGSTEN_COMPILER_IMAGE=metal \
      "$IMAGES/tungsten-metal" --help) > "$IMAGE_OUTPUT" 2>&1 ||
     ! grep -Fq 'compile-batch' "$IMAGE_OUTPUT"; then
    printf 'release package Metal compiler image does not start\n' >&2
    head -20 "$IMAGE_OUTPUT" >&2
    exit 1
  fi

  # Compile, link and run a program through the packaged launcher. The source
  # sits outside every checkout, so core/ and runtime/ can only come from the
  # package. --dev keeps this to one -O0 runtime archive; the release workflow
  # adds the default and --release (LTO) profiles.
  SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-release-smoke.XXXXXX")"
  trap 'rm -rf "$SMOKE"' EXIT INT TERM
  printf '<< "release package " + (6 * 7).to_s\n' > "$SMOKE/smoke.w"
  LINK_OUTPUT="$WORK/$TARGET_LABEL.link.out"
  if ! (cd "$SMOKE" && env -u TUNGSTEN_ROOT -u TUNGSTEN_CACHE_DIR -u TUNGSTEN_CLANG_OPT \
      "$PACKAGE_ROOT/bin/tungsten" -o "$SMOKE/smoke" --dev "$SMOKE/smoke.w") > "$LINK_OUTPUT" 2>&1 ||
     [[ ! -x "$SMOKE/smoke" ]]; then
    printf 'release package cannot compile and link a program\n' >&2
    head -40 "$LINK_OUTPUT" >&2
    exit 1
  fi
  if [[ "$("$SMOKE/smoke" 2>&1)" != "release package 42" ]]; then
    printf 'release package built a program that does not run correctly\n' >&2
    "$SMOKE/smoke" 2>&1 | head -20 >&2 || true
    exit 1
  fi
fi

printf 'PASS release package %s\n' "$EXPECTED_NAME"
