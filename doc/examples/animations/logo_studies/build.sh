#!/usr/bin/env bash
set -euo pipefail
logo_source_dir="$(cd "$(dirname "$0")" && pwd)"
logo_repo_root="$(cd "$logo_source_dir/../../../.." && pwd)"
logo_animation_root="${1:-$logo_repo_root}"
logo_output_dir="${2:-$logo_repo_root/build/logo-studies-2026-09-05}"
logo_study_source="${3:-$logo_source_dir/tungsten_logos.w}"
if [ ! -f "$logo_animation_root/core/animation.w" ]; then
  printf 'Supply a checkout containing core/animation.w as argument 1.\n' >&2
  exit 1
fi
logo_animation_root="$(cd "$logo_animation_root" && pwd)"
mkdir -p "$logo_output_dir"
logo_output_dir="$(cd "$logo_output_dir" && pwd)"
# Source and cwd must both belong to the animation checkout. A newer unrelated
# Core mixed with this checkout's interpreter has incompatible native ccalls.
mkdir -p "$logo_animation_root/build"
logo_stage_dir="$(mktemp -d "$logo_animation_root/build/logo-studies.XXXXXX")"
trap 'rm -f "$logo_stage_dir/tungsten_logos.w" "$logo_stage_dir/timelines.json"; rmdir "$logo_stage_dir"' EXIT
cp "$logo_study_source" "$logo_stage_dir/tungsten_logos.w"
(
  cd "$logo_animation_root"
  bin/tungsten run "$logo_stage_dir/tungsten_logos.w" > "$logo_stage_dir/timelines.json"
)
mv "$logo_stage_dir/timelines.json" "$logo_output_dir/timelines.json"
logo_python="${LOGO_PYTHON:-python3}"
"$logo_python" "$logo_source_dir/render.py" "$logo_output_dir"
