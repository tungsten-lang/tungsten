#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: stage.sh <main|parallel> <new-destination>" >&2
  echo "Set WASSAT_STAGE_ALLOW_DIRTY=1 only for local packaging tests." >&2
}

if (( $# != 2 )); then
  usage
  exit 2
fi

track="$1"
destination="$2"
case "$track" in
  main|parallel) ;;
  *) usage; exit 2 ;;
esac

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_root="$(git -C "$script_dir" rev-parse --show-toplevel)"

if [[ -e "$destination" ]]; then
  echo "refusing to overwrite existing staging destination: $destination" >&2
  exit 1
fi

paths=(
  LICENSE-APACHE
  LICENSE-MIT
  VERSION
  bin
  compiler
  core
  implementations/c
  languages/tungsten
  lib
  runtime
  bits/tungsten-wassat
)

status="$(git -C "$source_root" status --porcelain --untracked-files=normal -- "${paths[@]}")"
if [[ -n "$status" && "${WASSAT_STAGE_ALLOW_DIRTY:-0}" != "1" ]]; then
  echo "refusing to stage a dirty source tree; commit the intended solver first" >&2
  printf '%s\n' "$status" >&2
  exit 1
fi

mkdir -p -- "$destination"
destination="$(CDPATH= cd -- "$destination" && pwd)"

# Copy exactly tracked and non-ignored source files from the selected
# worktree paths. Ignored host binaries, caches, proof files, and generated
# sidecars never enter the submission.
git -C "$source_root" ls-files -z --cached --others --exclude-standard -- "${paths[@]}" |
  while IFS= read -r -d '' path; do
    mkdir -p -- "$destination/$(dirname -- "$path")"
    cp -Pp -- "$source_root/$path" "$destination/$path"
  done

cp -Pp -- "$script_dir/build.sh" "$destination/build.sh"
cp -Pp -- "$script_dir/run-main.sh" "$destination/run-main.sh"
cp -Pp -- "$script_dir/run-parallel.sh" "$destination/run-parallel.sh"
if [[ "$track" == "main" ]]; then
  cp -Pp -- "$script_dir/run-main.sh" "$destination/run.sh"
else
  cp -Pp -- "$script_dir/run-parallel.sh" "$destination/run.sh"
  cp -Pp -- "$script_dir/aws/solver_cmd.py" "$destination/solver_cmd.py"
fi
chmod +x "$destination/build.sh" "$destination/run.sh" \
  "$destination/run-main.sh" "$destination/run-parallel.sh"

{
  printf 'track=%s\n' "$track"
  printf 'commit=%s\n' "$(git -C "$source_root" rev-parse HEAD)"
  if [[ -n "$status" ]]; then
    printf 'worktree=dirty\n%s\n' "$status"
  else
    printf 'worktree=clean\n'
  fi
} >"$destination/SOURCE_STATE.txt"

echo "staged $track submission at $destination"
