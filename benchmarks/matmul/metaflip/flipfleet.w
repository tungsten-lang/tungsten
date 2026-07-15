# flipfleet.w -- authoritative pure-Tungsten MetaFlip fleet entry point.
#
# Build from the repository root:
#   bin/tungsten compile benchmarks/matmul/metaflip/flipfleet.w \
#     --out /tmp/flipfleet --release --fast --lto
# Or, from this file's directory:
#   ../../../bin/tungsten compile flipfleet.w \
#     --out /tmp/flipfleet --release --fast --lto
#
# GPU search is enabled by default with the adaptive mixed role portfolio.
# Use --no-gpu for a CPU-only control. `--tensor` accepts square 2x2..7x7 and
# the exact rectangular profiles 2x2x5, 2x2x6, 2x3x4, 2x3x5, 2x4x5, 2x5x6, 3x3x4, 3x3x5, 3x4x4, 3x4x5,
# 3x4x6, 3x4x7, 3x5x5, 3x5x6, 3x5x7, 4x4x5, 4x4x6, 4x5x5, 4x5x6,
# 4x5x7, 4x5x8, 4x6x6, 4x6x7, 4x6x8, and 5x6x7.
# `--rect` runs an adaptive multi-shape portfolio; `--rect-shapes` overrides
# its default 2x2x5,4x5x7,3x4x6,4x5x6,4x4x6,4x4x5,2x5x6,3x4x7,3x5x6 selection.
# Rectangular dispatch uses its own pure-Tungsten islands (and a specialized
# Metal engine where available) before square state is allocated, and renders
# the same styled TUI with the same keyboard controls (--no-tui for the
# machine-parseable RECT_STATUS stream).

use flipfleet_native
