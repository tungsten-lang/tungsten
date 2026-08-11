#!/usr/bin/env bash
# Cut a source tag and let GitHub build the native release matrix.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
REMOTE="${TUNGSTEN_RELEASE_REMOTE:-origin}"
SKIP_TESTS=0
NO_PUSH=0
DRY_RUN=0
REQUESTED_VERSION=""

usage() {
  cat <<'EOF'
Usage: tungsten release [VERSION] [options]

Validate the repository, run the root test suite, create an annotated vVERSION
tag, and push it. The tag triggers the native GitHub release matrix.

Options:
  --dry-run      Validate without testing, tagging, or pushing
  --skip-tests   Skip the root rake gate
  --no-push      Create the local tag but do not push it
  -h, --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --no-push) NO_PUSH=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'tungsten release: unknown option %s\n' "$1" >&2; exit 2 ;;
    *)
      if [[ -n "$REQUESTED_VERSION" ]]; then
        printf 'tungsten release: expected one VERSION\n' >&2
        exit 2
      fi
      REQUESTED_VERSION="${1#v}"
      ;;
  esac
  shift
done

cd "$ROOT"
FILE_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
VERSION="${REQUESTED_VERSION:-$FILE_VERSION}"
TAG="v$VERSION"

if [[ "$VERSION" != "$FILE_VERSION" ]]; then
  printf 'tungsten release: VERSION contains %s, not %s\n' "$FILE_VERSION" "$VERSION" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}([.-][0-9A-Za-z]+)*$ ]]; then
  printf 'tungsten release: invalid version %s\n' "$VERSION" >&2
  exit 1
fi
if [[ "$(git branch --show-current)" != "main" ]]; then
  printf 'tungsten release: releases must be cut from main\n' >&2
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  printf 'tungsten release: worktree is not clean\n' >&2
  git status --short >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  printf 'tungsten release: local tag %s already exists\n' "$TAG" >&2
  exit 1
fi
if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
  printf 'tungsten release: remote tag %s already exists on %s\n' "$TAG" "$REMOTE" >&2
  exit 1
fi

printf 'Tungsten %s release matrix:\n' "$VERSION"
printf '  macOS arm64 (target baseline)\n'
printf '  macOS x86_64 (x86-64-v2, x86-64-v3)\n'
printf '  Linux arm64 (target baseline)\n'
printf '  Linux x86_64 (x86-64-v2, x86-64-v3)\n'

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'release validation: ok (dry run)\n'
  exit 0
fi

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  printf '\n==> Root test gate\n'
  bundle exec rake
fi

git tag -a "$TAG" -m "Tungsten $VERSION"
printf 'created annotated tag %s at %s\n' "$TAG" "$(git rev-parse --short HEAD)"

if [[ "$NO_PUSH" -eq 1 ]]; then
  printf 'tag not pushed (--no-push)\n'
  exit 0
fi

git push "$REMOTE" "$TAG"
printf 'pushed %s; GitHub Actions will publish the native artifacts\n' "$TAG"
