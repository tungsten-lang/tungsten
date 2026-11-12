#!/usr/bin/env bash
set -euo pipefail

# Package one release: the tracked toolchain tree at HEAD, the compiler built
# for the target, and that compiler's images. `tungsten build --target ...`
# writes all three binaries for one target and CPU under
# build/releases/<triple>/<cpu>/: tungsten-compiler and, beside it,
# compiler-images/tungsten-{repl,metal}. The compiler never builds an image on
# launch, so a package without them cannot start the REPL, run --interpret, or
# compile a @gpu program.
if [[ $# -ne 3 ]]; then
  printf 'usage: %s COMPILER TARGET-LABEL OUTPUT-DIR\n' "$0" >&2
  printf '  images are read from the directory of COMPILER: compiler-images/tungsten-{repl,metal}\n' >&2
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
IMAGES="$(dirname "$COMPILER")/compiler-images"
IMAGE_KINDS=(repl metal)
for kind in "${IMAGE_KINDS[@]}"; do
  if [[ ! -x "$IMAGES/tungsten-$kind" ]]; then
    printf 'release compiler image is missing or not executable: %s\n' "$IMAGES/tungsten-$kind" >&2
    printf 'build the artifact and its images together: bin/tungsten build --release --target TRIPLE [--cpu CPU]\n' >&2
    exit 1
  fi
done

mkdir -p "$STAGE/$PACKAGE" "$OUTPUT_DIR"
# Ship the complete toolchain and standard library, but leave the 277 MB
# benchmark corpus and developer-only spec fixtures in the source archive.
# Every listed path is tracked; a missing path therefore makes packaging fail.
git -C "$ROOT" archive --format=tar HEAD -- \
  .dockerignore .ruby-version Bitfile COPYRIGHT Dockerfile Gemfile \
  LICENSE-APACHE LICENSE-MIT Makefile README.md Rakefile TODO.md VERSION \
  bin bits compiler core data doc implementations languages runtime scripts \
  services | tar -xf - -C "$STAGE/$PACKAGE"
cp "$COMPILER" "$STAGE/$PACKAGE/bin/tungsten-compiler"
chmod 755 "$STAGE/$PACKAGE/bin/tungsten-compiler" "$STAGE/$PACKAGE/bin/tungsten"

# Images live where the compiler looks for them: build/compiler-images
# under the root that holds its runtime/ (compiler_image_dir in
# compiler/lib/driver/link.w). The side maps symbolize Tungsten frames.
PACKAGE_IMAGES="$STAGE/$PACKAGE/build/compiler-images"
mkdir -p "$PACKAGE_IMAGES"
for kind in "${IMAGE_KINDS[@]}"; do
  cp "$IMAGES/tungsten-$kind" "$PACKAGE_IMAGES/tungsten-$kind"
  chmod 755 "$PACKAGE_IMAGES/tungsten-$kind"
  if [[ -f "$IMAGES/tungsten-$kind.sidemap" ]]; then
    cp "$IMAGES/tungsten-$kind.sidemap" "$PACKAGE_IMAGES/tungsten-$kind.sidemap"
  fi
done

tar -C "$STAGE" -czf "$OUTPUT_DIR/$PACKAGE.tar.gz" "$PACKAGE"
printf '%s\n' "$OUTPUT_DIR/$PACKAGE.tar.gz"
