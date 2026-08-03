# tungsten-crypto — SHA-256, Bitcoin consensus primitives, and a miner.
#
# Load order is the dependency chain:
#
#   config   ~/.tungsten/crypto.config defaults
#   sha256   FIPS 180-4 SHA-256, exposed at word level so the compression
#            function and its chaining state are reachable
#   bitcoin  headers, targets, merkle roots, hash/hex byte-order handling
#   block    coinbase construction and block serialization
#   address  bech32/bech32m decoding to a scriptPubKey
#   miner    midstate-reusing proof-of-work search
#   accel    the same search on the ARMv8 SHA-256 crypto extension
#   pool     multi-threaded nonce-space partitioning
#
# `gpu_search` is deliberately NOT in this list. It pulls in core/metal,
# which the interpreter cannot execute — adding it here crashes every
# interpreted consumer of the bit, including the spec suite. Compiled
# programs that want the GPU opt in explicitly with `use ../lib/gpu_search`
# (see bin/miner.w and benchmarks/bench_gpu_search.w).
#   tui      live display, updated between chunks (never in the hash loop)
#   p2p      Bitcoin wire protocol: framing, handshake, header sync
#   rpc      Bitcoin Core JSON-RPC client
#
# Everything is a top-level function in the root namespace, which is the
# pattern that actually works across bits — a namespaced class is
# unreachable from interpreted consumer code.

use version
use config
use sha256
use bitcoin
use block
use address
use base58
use prices
use coins
use miner
use accel
use pool
use tui
use p2p
use rpc
