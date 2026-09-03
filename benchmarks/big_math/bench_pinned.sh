#!/bin/sh
# Item 20 — run the bignum benchmark at raised QoS to reduce preemption
# from background GPU/compile load. macOS has no unprivileged P-core pin;
# taskpolicy sets the process QoS clamp. -c defaults to utility; we clear
# any background clamp and request the highest unprivileged tier. Falls
# back to a plain run if taskpolicy is unavailable.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if command -v taskpolicy >/dev/null 2>&1; then
  exec taskpolicy -c utility -t 0 -l 0 "$ROOT/bin/tungsten" bench bignum "$@"
fi
exec "$ROOT/bin/tungsten" bench bignum "$@"
