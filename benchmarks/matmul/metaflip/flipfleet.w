# flipfleet.w -- authoritative pure-Tungsten MetaFlip fleet entry point.
#
# Build from the repository root:
#   bin/tungsten -o /tmp/flipfleet benchmarks/matmul/metaflip/flipfleet.w \
#     --release --native --fast --lto
# Or, from this file's directory:
#   ../../../bin/tungsten -o /tmp/flipfleet flipfleet.w \
#     --release --native --fast --lto
#
# GPU search is enabled by default with the adaptive mixed role portfolio.
# Use --no-gpu for a CPU-only control. `--tensor` accepts square 3x3..7x7 and
# the exact rectangular profiles 3x3x4, 3x3x5, 3x4x4, 3x4x5, 3x4x6,
# 3x5x5, 4x4x5, 4x5x5, 4x4x6, 4x5x6, and 4x5x7.
# Rectangular dispatch uses its own pure-Tungsten islands (and a specialized
# Metal engine where available) before square state is allocated, and renders
# the same styled TUI with the same keyboard controls (--no-tui for the
# machine-parseable RECT_STATUS stream).

use flipfleet_native
