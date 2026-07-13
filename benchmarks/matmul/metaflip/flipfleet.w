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
# Use --no-gpu for a CPU-only control and --tensor 3x3 ... --tensor 7x7 to
# select the square matrix-multiplication tensor.  The complete coordinator,
# runtime-generic CPU worker, exact escape banks, and native TUI live in the
# modules imported by flipfleet_native.

use flipfleet_native
