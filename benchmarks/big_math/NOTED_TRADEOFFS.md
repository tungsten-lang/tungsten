# Noted, not taken

Wins in one area that cost another get recorded here instead of shipped:
the measured win, the measured loss, and the condition that would make the
trade worth it. (Bignum campaign ground rule, 2026-08-02.)

## BN_BIGINT_HYBRID_CAP default flip — NOT taken (2026-08-02)

**Claimed win (prior session, real workloads):** hybrid (p2<=32 + q32)
measured -32% real RSS on live sets and ~1% faster whole-program.

**Measured loss (this session, 21-op accurate matrix, 110ms/9-run
discipline):** geomean 0.774 -> 0.777, zero losses >= 1.05, but **27
cells regress > 5%** against the power-of-two baseline — including
mul@64 0.827 -> 0.995 (the historical red cell), div@256 +20%,
shl@1024 +23% — vs 21 cells improving > 5%. The flip's acceptance
criteria (no cell regressing > 5%, zero win->loss flips) fail. The
mixed-size capacity trace agrees directionally: power-of-two takes
8.8 ns/request vs hybrid 10.7 (the hybrid pool take pays a first-bucket
size check per hit).

*Caveats:* the hybrid matrix ran under spec-suite load (ratios are
load-robust by design, but the regression tail may be inflated), and the
capacity trace's hit% is pinned at 99.99+ (live_depth defect), so its
allocator-pressure signal is weak. Baselines:
`baselines/matrix-7a96d5c-accurate-20260802.json` (pow2) vs
`baselines/matrix-hybrid3232-accurate-20260802.json`.

**Condition to take it:** the B4 capacity grid (with the live_depth fix)
finds a hybrid point that keeps the op matrix clean, or the campaign's
headline metric moves from the op matrix to whole-program benchmarks (E3)
where hybrid's RSS win is the thing being measured. Both measurements are
one runtime -D flag apart; nothing needs rebuilding to revisit.

## Raw-slot promotion keeps i64 silent-wrap semantics for `+ - *` (pre-existing)

**What:** Untyped block/loop locals whose defining chain is "int-shaped"
(`analysis.w` `int_shaped_node?`) are promoted to raw i64 stack slots for
speed, with explicitly documented silent-wrap semantics. Compiled code then
diverges from the interpreter when such a local overflows i64:

```
(1..1).each -> (k)
  x = 1000000000000 * k
  y = x * x            # compiled: 2003764205206896640 (wrapped)
                       # interpreted: 10^24 (promoted to BigInt)
```

**Win being protected:** raw slots avoid boxing in untyped numeric loops
(the boxing penalty is ~18x; the promotion machinery exists because of it).

**Loss:** engine-parity break for untyped arithmetic that overflows i64
inside inlined iterator blocks / while loops. Silent wrong values, the worst
failure class. `<<` was removed from this machinery on 2026-08-02 (see
below); `+ - *` remain because their wrap point (2^63) is far rarer in
practice than a shift's, and no raw representation exists for a promoted
BigInt in a raw slot.

**Condition to take the fix:** either (a) guarded raw ops with a deopt path
that re-boxes the loop state on first overflow, or (b) accepting the boxing
cost for untyped loops and reserving raw slots for `## i64`-hinted locals
only, with a benchmark showing the regression is confined to code that
should be hinted anyway.

**Related fix that WAS taken (2026-08-02):** shift-left. `1 << 200`
compiled to 0, and `a << 13` inside a block dropped its top limb — a shift
overflows i64 with tiny operands, and `1 << bits` is how BigInts are born,
so `<<` now (1) is not int-shaped (`analysis.w`), (2) folds literal bases
that provably fit i48 and otherwise routes literal-based shifts through the
checked `__w_shl_fast` (`ops.w`), and (3) infers nil (boxed) for a bare
literal base instead of `:i64` (`lowering.w`), mirroring the `**` rule.
Declared `## i64`/`## u64` bases keep the raw machine `shl` and its wrap
contract.
