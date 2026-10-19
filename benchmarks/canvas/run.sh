#!/usr/bin/env bash
# Canvas (CoreGraphics/CoreText) vs Svg + rsvg-convert, frames per second.
# Usage: benchmarks/canvas/run.sh [frames]   (default 60 per lane; macOS only)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
"$ROOT/bin/tungsten" -o /tmp/tungsten_canvas_bench_bin --release "$ROOT/benchmarks/canvas/canvas_bench.w"
/tmp/tungsten_canvas_bench_bin "${1:-60}"
