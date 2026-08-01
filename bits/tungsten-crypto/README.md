# tungsten-crypto

SHA-256, Bitcoin consensus primitives, and a working miner — in Tungsten.

```
bin/tungsten -o /tmp/miner bits/tungsten-crypto/bin/miner.w

/tmp/miner selftest     # hash vectors + real mainnet blocks
/tmp/miner bench        # naive vs midstate hash rate
/tmp/miner demo 1e00ffff bc1q...        # mine to an address you control
/tmp/miner solo 127.0.0.1 8332 user pass bc1q...
```

## What it does

| module | contents |
|---|---|
| `lib/sha256.w` | FIPS 180-4 SHA-256, exposed at word level so the compression function and its chaining state are reachable |
| `lib/bitcoin.w` | headers, compact targets, merkle roots, and the byte-order rules |
| `lib/block.w` | coinbase construction (BIP34, BIP141) and block serialization |
| `lib/address.w` | bech32/bech32m decoding — address to scriptPubKey, checksum-validated |
| `lib/miner.w` | midstate-reusing proof-of-work search, plus an unoptimized reference |
| `lib/p2p.w` | Bitcoin wire protocol: framing, handshake, header-chain sync |
| `lib/accel.w` | the same search on the ARMv8 SHA-256 extension |
| `lib/pool.w` | multi-threaded nonce-space partitioning |
| `lib/rpc.w` | Bitcoin Core JSON-RPC client |

Correctness is pinned to data this implementation cannot influence: the FIPS
vectors, the genesis block, mainnet block 100000's merkle root and header
hash, the real block 1 coinbase txid, and Bitcoin Core's `SetCompact`
semantics for compact targets. `spec/crypto_spec.w` runs 34 examples on both
engines.

The strongest check is `spec/rpc_live.w` plus a node: the miner has mined and
submitted a block that an independent verifier accepted after re-parsing the
header, recomputing the double-SHA, checking the proof-of-work against nBits,
re-deriving the merkle root from the submitted coinbase, and validating the
BIP34 height.

## Measured

Apple Silicon M5 Max (6 Super + 12 Performance cores), quiet box. Rates vary
±15% with load — the GPU especially, since a contended CPU starves its
dispatch.

| implementation | rate | vs naive |
|---|---:|---:|
| naive (re-hash all 80 bytes per nonce) | ~0.9 MH/s | 1.0× |
| midstate, pure Tungsten | ~1.9 MH/s | ~2× |
| ARMv8 SHA-256 extension, 1 core | ~36 MH/s | ~40× |
| …across 18 cores | ~500–570 MH/s | ~600× |
| **GPU, hand-written Metal** | **~2.1 GH/s** | **~2300×** |
| GPU via `@gpu fn` (unrolled) | ~0.8 GH/s | ~900× |

The `mine` command uses the GPU automatically when Metal is available and
falls back to the CPU pool otherwise. Reproduce with `benchmarks/bench_gpu.w`
(GPU vs CPU, with correctness checks), `benchmarks/bench_accel.w` (CPU
three-way), and `benchmarks/bench_pool.w` (CPU parallel scaling). All check
against the genesis block before reporting a rate.

The kernel is at the hardware ceiling on both paths: the CPU issues 60
`SHA256H`/`SHA256H2` per nonce at the port's saturation rate, and the GPU
figure is unrolling-bound (the whole 2.4× gap to the `@gpu fn` version is
loop unrolling, nothing else). The single largest remaining lever is not
code — it is a machine the GPU does not have to share.

---

# Can you reuse a partial hash while varying the nonce?

Yes — substantially, and it is the single most important optimization in
mining. But the reuse is *structural*, not algebraic. Here is the precise
boundary between what works and what cannot.

## What SHA-256 lets you reuse

SHA-256 is a Merkle–Damgård construction. The message is cut into 512-bit
blocks and folded one at a time into a 256-bit chaining state. Block *i*'s
output is block *i+1*'s only input — nothing else from block *i* survives.
So **any prefix that fills whole blocks can be hashed once and reused for
every message sharing that prefix.**

A Bitcoin header is 80 bytes, which SHA-256 pads to 128 — exactly two blocks.

```
                  THE 80-BYTE BITCOIN BLOCK HEADER
                (the entire proof-of-work preimage)

  offset  size  field          endianness   notes
  ──────  ────  ────────────   ──────────   ─────────────────────────────
     0      4   version        little       BIP9 bits; rolled by AsicBoost
     4     32   prev_block     internal     hash of the previous header
    36     32   merkle_root    internal     commits to EVERY transaction
    68      4   time           little       unix seconds
    72      4   bits           little       compact target (nBits)
    76      4   nonce          little       ◄── the entire search space
  ──────────────────────────────────────────────────────────────────────
                80 bytes total.  Transaction data is NOT here — it is
                reached only through the 32-byte merkle_root, so a block
                with 4 transactions hashes exactly as fast as one with
                4,000.


        SHA-256 pads those 80 bytes to 128 = exactly two 512-bit blocks

  byte 0                          64                                   128
       ├─────────── BLOCK 1 ───────┼─────────────── BLOCK 2 ─────────────┤
       │ version │ prev_block │ mrkl │ mrkl │time│bits│NONCE│  padding   │
       │  0..3   │   4..35    │36..63│64..67│    │    │76-79│  80..127   │
       └─────────────────────────────┴──────────────────────────────────┘
        ╰────── constant for the whole ──────╯╰── rebuilt every nonce ──╯
                 2³² nonce search
              compressed ONCE ⇒ MIDSTATE

       note: merkle_root STRADDLES the block boundary — 28 of its bytes
       land in block 1, the last 4 in block 2.


  BLOCK 2, as the compression function actually sees it (16 × 32-bit words)

    w[ 0]  merkle_root[28..31] ┐
    w[ 1]  time                ├─ fixed per work item
    w[ 2]  bits                ┘   ⇒ rounds 0..2 precomputed once
    w[ 3]  ► N O N C E ◄           ⇒ enters at round 3; all 61 later
    w[ 4]  0x80000000          ┐      rounds are fresh every candidate
    w[ 5..14]  0x00000000      ├─ SHA-256 padding for a 640-bit message
    w[15]  640 (bit length)    ┘
                                   w[16],w[17] also nonce-free ⇒ precomputed
                                   w[18..63] all depend on w[3]


  THE PIPELINE — two compressions per candidate, not three

    header[0..63] ──▶ compress ──▶ ╔═══════════╗
                                   ║ MIDSTATE  ║   computed once
                                   ╚═════╤═════╝
                                         │  reused for all 2³² nonces
                                         ▼
    header[64..79] + pad ──────▶ compress ──▶ H1 (32 bytes)
                                                  │
                                                  ▼
              H1 + pad ──────────────────▶ compress ──▶ H2
                                                  │
                                                  ▼
                                     read H2 as a LITTLE-endian
                                     256-bit int; win if ≤ target
```

**The nonce lands in block 2.** Block 1 is therefore constant across an
entire 2³²-nonce search, and the chaining state after it — the *midstate* —
is computed once and reused forever.

Two things the diagram makes visual. The reusable region is a *prefix* that
ends at byte 64, while the nonce sits at bytes 76–79 with nothing after it
but padding — there is no suffix to skip. And the second hash consumes H1,
which changes completely on every candidate, so it can never be partially
reused no matter where the nonce sits.

This is not a trick; it is the shape of the hash. Bitcoin's original
`getwork` RPC literally returned a `midstate` field alongside the header.
It disappeared only because Stratum moved coinbase construction to the
miner, which then computes its own midstate.

Naive cost per candidate is three compressions (two for the 80-byte first
hash, one for the 32-byte second). With the midstate it is two. That is the
**33% saving** every real miner takes, and it is why a chip advertised at
*n* TH/s runs an internal compression rate near 2*n*, not 3*n*.

Three smaller reuses are also available, and `lib/miner.w` implements all
of them:

- **Rounds 0–2 of block 2** consume `w[0..2]` — merkle tail, time, bits.
  None is the nonce, so the working variables after round 2 are also fixed
  per work item. The per-nonce compression resumes at round 3.
- **Schedule words `w[16]` and `w[17]`** depend on `w[0..2]` and `w[9..15]`
  but not on `w[3]`, so they are precomputed too.
- **The final word H7** is fully determined by the state after round 60,
  because the rounds rotate the working variables. The last three rounds of
  the *second* hash are skipped on the reject path — and since a candidate
  must have zero high bits, H7 alone rejects essentially every nonce. The
  full digest is assembled only for a survivor.

An ASIC goes further in the same direction: it hardwires the early rounds
as constants and never builds silicon for block 1 at all. A mining chip is
fed a 32-byte midstate and a 12-byte tail, not an 80-byte header.

## What you cannot do — and why

> *Can we solve the partial hash for an increment or transformation to apply
> to the nonce?*

No. Not with a clever encoding, and not by any published technique. This is
not an engineering gap; it would be a break of SHA-256 itself.

**The nonce's influence is total within a few rounds.** The nonce enters at
`w[3]`. Round 3 mixes it into `e` and `a` through Σ₁, the choice function,
and modular addition. Each subsequent round rotates it into another working
variable while Σ₀/Σ₁ apply three different rotations and XOR them together.
By round ~8 every one of the eight working variables depends on every nonce
bit. Modular addition then couples bits through carry chains that no
rotation can undo. After that, rounds 3–63 of block 2 and all 64 rounds of
the second hash have to be executed. There is no shortcut through them
because destroying such shortcuts is the entire design goal.

**"Solving for the nonce" is preimage resistance.** Asking for a
transformation that maps a partial hash to a nonce meeting a target is
asking to invert SHA-256 on its ~76 most significant output bits. The best
published preimage attack is the biclique result of Khovratovich,
Rechberger and Savelieva (FSE 2012), reaching **45 of 64 rounds** at a
complexity of about 2²⁵⁵·⁵ — a hair under brute force, and purely
theoretical. Full-round SHA-256 has no preimage attack. Bitcoin uses
*double* SHA-256, so the constraint sits on the output of a 128-round
composition.

**Adjacent nonces give you nothing.** H(nonce+1) is not cheaper to compute
from H(nonce) than from scratch. The avalanche property means a one-bit
nonce change re-randomizes the entire state; there is no incremental update.
Differential cryptanalysis does relate input and output differences, but
only probabilistically and only for reduced rounds — collision results sit
around 31 steps for practical collisions and the high 30s for
semi-free-start variants. Collisions are the wrong tool anyway: mining needs
a *specific numeric range*, not a matching pair.

### On encoding it as SAT for wassat

SHA-256 does encode to CNF mechanically: modular additions become
ripple-carry adder circuits, rotations are free wire relabelings, the
bitwise functions are a few clauses per bit. One full SHA-256 is roughly
100k–200k clauses over ~50k variables; the double hash is about twice that.

This has been tried, on exactly this problem. Heusser's *satcoin* (2013)
encoded Bitcoin mining itself to CNF via CBMC and solved for valid nonces.
It works — and its own conclusion is that it is unoptimized research code,
not a competitor to brute force, with any efficiency gain likely dwarfed by
the probability of finding a valid nonce at all.

The published ceiling is low. SAT-based **preimage** attacks on the SHA-256
compression function reach about **17–19 rounds** of 64. SAT-assisted
collision work goes further (into the 20s, and high 30s for semi-free-start
with programmatic SAT), but that is a different problem. Nobody is near 64,
let alone 128.

The reason is not solver quality. CDCL solvers win when fixing one variable
cascades through unit propagation and a learned clause prunes a large
structured subspace. SHA-256's message schedule is an expander and its
carry chains couple everything, so fixing a bit propagates almost nothing
and there are no large structured subspaces to prune. The solver degenerates
to brute force while carrying orders of magnitude of constant-factor
overhead per candidate.

There is also a decisive economic point specific to mining rather than
preimage: **the free variable is only 32 bits.** A 2³² space is something
this miner exhausts in about 20 seconds and an ASIC exhausts in
microseconds. Handing a 4-billion-element search to a SAT solver is strictly
worse than counting.

Where wassat *would* be interesting is measuring the wall rather than citing
it: encode *k*-round SHA-256 for increasing *k* and plot solve time. That
produces a real curve on real hardware.

## What actually improves profitability

Ranked by how much they matter, since that was the goal:

1. **Hardware.** An S21-class ASIC does ~200 TH/s at ~3.5 kW. This miner does
   0.199 GH/s. The ASIC is about **one million times faster**, and its
   energy per hash is better by a similar factor. No software change closes
   a gap of that size — mining profitability is set by joules per hash, and
   that is a silicon property.

2. **Midstate reuse** — implemented here. 33% of the compression work,
   1.7× measured end to end.

3. **The SHA-256 instruction extension** — implemented here. 14× over the
   pure-Tungsten loop. Every modern CPU and ASIC uses dedicated SHA
   datapaths; scalar code is not competitive even among CPUs.

4. **Parallelism** — implemented here. The nonce space partitions perfectly;
   8.4× across 18 cores (the ceiling is efficiency-core throughput, not the
   algorithm).

5. **AsicBoost** — the one *legitimate* algorithmic edge anyone has found,
   worth about **20%**. It is worth understanding because it is the closest
   thing to what the question was reaching for. Instead of reusing a prefix,
   it reuses *suffix* work: pick four candidate headers whose block-2
   message schedules collide in the last four expansion words, and the final
   four rounds of the first hash can be shared across all four. Covert
   AsicBoost manipulated the merkle root to find such collisions; overt
   AsicBoost rolls the header's version field instead, which is why BIP310
   exists. Note the shape of it — it is still *structural reuse of work
   across candidates*, not an inversion of the hash. Nobody has found more
   than 20% this way in fifteen years of trying.

6. **Not solo mining.** At 0.199 GH/s against a network near 700 EH/s, this
   miner holds about 2.8 × 10⁻¹³ of the hash rate, so the expected time to
   find a block alone is roughly **67 million years**. Pooled mining
   converts that lottery into steady fractional payments; it changes
   variance, not expected value. The honest summary is that this
   miner is correct, reasonably fast for a CPU, and economically pointless
   on mainnet — which is exactly why `demo` and regtest exist.

## Notes on the implementation

`-march=native` **disables** the ARM crypto extensions on Apple Silicon —
Apple clang enables them by default and the flag resets the feature set to a
baseline without them. Tungsten compiles C with `-march=native`, so keying
the fast path off `__ARM_FEATURE_CRYPTO` silently compiled it out and fell
back to scalar at 1/10 the speed with no diagnostic. `runtime/sha256_hw.c`
therefore marks each accelerated function `__attribute__((target("sha2")))`,
which is independent of the global flags, and probes the CPU at runtime
before dispatching.

Byte order is stated once in `lib/bitcoin.w` and obeyed everywhere. Three
representations coexist: the digest words SHA-256 produces, the internal
byte order stored in a serialized header, and the reversed display hex that
explorers print. Most Bitcoin implementation bugs live here.
