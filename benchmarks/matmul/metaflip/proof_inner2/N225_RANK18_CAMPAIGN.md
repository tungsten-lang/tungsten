# Closing the GF(2) `<2,2,5>` rank gap

## Claim boundary

The rigorous status remains

```text
17 <= R_GF(2)(<2,2,5>) <= 18.
```

The lower endpoint is the checked Wang certificate replayed by
`n225_verify_wang.py`.  The upper endpoint is the exact rank-18 `3+2` block
composition checked into the parent directory.  Nothing in the experiments
below is a rank-18 lower bound: that claim requires all 43 direct-rank shards
to be UNSAT, every solver proof to be elaborated, and every elaborated proof
to pass the checked verifier.

## Why the current Wang tree stops at 17

The checked finite-geometry certificate has 11 constrained-subspace orbits.
All forced-product searches which can occur in this tree have at most `2^25`
candidates.  A one-thread exhaustive rerun at cap 25 completed both full
spaces: the dimension-two child finished at lower bound 15 after 60.30
seconds and the dimension-one child finished at 15 after 41.30 seconds.
Increasing the cap cannot expose another projection; the search wrapper also
tries all three cyclic factor positions.  An unlimited root backtracking
recheck completed in 0.58 seconds and retained 17.

Artificial child-bound probes localize the obstruction exactly.  Raising
only dimension-one orbit 8 from 15 to 16 makes the Wang root derive 18, while
raising the other dimension-one child does not.  This is a diagnostic, not a
proof.  Orbit 8 has constraint `0001`, which sets the `x00` coordinate to
zero, and it has this explicit 15-term decomposition, three terms for every
`k` in `0..4`:

```text
x01 tensor y1k tensor z(k,0)
x10 tensor y0k tensor z(k,1)
x11 tensor y1k tensor z(k,1)
```

Wang's checked child lower bound is 15, so this decomposition proves that the
child rank is exactly 15.  The current orbit recursion therefore cannot raise
that child to 16 and cannot derive root 18.  More time, a higher forced-product
cap, or more root backtracking on the same tree cannot remove this barrier.
Escaping it would require a genuinely stronger theorem, a different recursion
that does not depend on this exact child, or the direct-rank campaign below.

## Complete direct rank-17 split

Use the cyclic orientation `<5,2,2>`, covered by the generic `<a,2,c>` exact
encoding.  Every used decomposition has a first nonzero term.  Its adjacent
factor ranks and rank-one pairing fall into five coarse cases; the stabilizer
split then gives exactly 43 shards:

| case | shards |
|---|---:|
| `a1_b1_p0` | 7 |
| `a1_b1_p1` | 7 |
| `a1_b2` | 7 |
| `a2_b1` | 13 |
| `a2_b2` | 9 |

The canonical formulas use quotient-rank strengthening, exact RREF gauge,
term lexicographic ordering, and nonzero third factors.  The last guard is
sound here only because the independently checked lower bound is already 17:
a hypothetical rank-at-most-17 decomposition must have exactly 17 used
terms.  The generator records that prerequisite, and both the campaign runner
and final proof verifier hash-audit the pinned Wang rank-17 package before
accepting a guarded campaign.

Generate the canonical formulas with:

```sh
python3 inner2_generate_campaign.py /tmp/n522-r17-close18-v2 \
  --a 5 --c 2 --terms 17 --known-lower-bound 17 \
  --nonzero-c --lex-terms
```

The measured canonical manifest has SHA-256
`3e72c905764cb1a107480d5be9ccb893ce62994d15b8052eb16fb9581aeffd38`.
Each shard has 12,436 variables, 39,032 CNF clauses, 1,080 native XORs, and
about 642 KB of input.

Run one CPU thread at a time and preserve resume state with:

```sh
python3 inner2_run_xnf_campaign.py \
  /tmp/n522-r17-close18-v2/manifest.json \
  /tmp/n522-r17-close18-v2-run \
  --seconds 60 --priority least-cpu
```

The output directory stores an atomic, manifest-hash-gated
`campaign_status.json` plus every transcript.  `least-cpu` repeatedly levels
the cumulative CPU budget across the 43 shards; rerunning with 300, 1,800,
and then 10,800 seconds is a resumable staged campaign.  Seeds advance on
each attempt.  SAT output is independently decoded and its full tensor is
reconstructed immediately.  Solver-reported UNSAT remains explicitly
`UNSAT_UNCHECKED`; it is not a theorem.

For final proof production, rerun an UNSAT shard with `--proof`, elaborate its
FRAT-XOR trace to XLRUP, and accept it only through
`inner2_verify_xnf_campaign.py`.  That verifier rebuilds the complete orbit
cover, checks all formula hashes and sizes, audits the checked rank-17
prerequisite, and requires CakeML verification of every shard.  A complete
checked set raises the lower bound to 18 and closes the tensor exactly.

## A second cyclic quotient projection

The orientation `<5,2,2>` has two inner-dimension-two contractions.  The
original strengthening projects `A_t tensor B_t` modulo the first `I_2`.
`--dual-inner2-quotient` additionally projects `B_t tensor C_t` modulo the
cyclic `I_2` and enforces the independent rank-at-most-seven condition on its
`30 x 17` projected term matrix.  This is a redundant consequence of exact
tensor equality, so it cannot remove a real decomposition.

The known `<2,2,2>` rank-seven control remained SAT with both projections and
the independently decoded model reconstructed the tensor exactly.  For the
canonical rank-17 shard, the dual formula has 17,304 variables, 55,444
clauses, 1,760 XORs, and about 949 KB.  Generate the complete optional arm by
adding `--dual-inner2-quotient`; its measured manifest SHA-256 is
`a9ba8df2c740e9f0aa39ede2eb2176d74922b9288a0d6f557f637d07b32f0a7b`.

This arm is not the default.  Across three matched ten-second seeds it used
about 7.7% fewer conflicts than the canonical formula while doing roughly
11% more propagation; at 30 seconds it remained indeterminate with 695,901
conflicts.  A dual no-RREF arm reached 334,020--344,514 conflicts in ten
seconds and is the better SAT-discovery portfolio member.  The checked RREF
arm remains the conservative proof-production input until a solved shard
gives a stronger comparison.

## Measured search tail

These bounded runs only calibrate difficulty:

- all 43 non-RREF, nonzero-C, lex shards were indeterminate after two seconds
  each; conflict counts ranged from 65,191 to 78,768;
- the five smallest-orbit canonical RREF shards were indeterminate after 30
  seconds each, at 736,095 to 783,964 conflicts;
- nonzero-C, pair-distinctness, RREF/no-RREF, and CryptoMiniSat Gaussian matrix
  limits of 0, 5, and 16 all remained indeterminate in matched ten-second
  probes.

The no-RREF arms processed more conflicts in short probes, so the dual
no-RREF variant is useful as a secondary SAT-discovery portfolio, but it is
not yet justified as the canonical proof formula. Pair-distinctness is
mathematically sound at exact minimum rank, but its larger CNF was slower in
the same window. The staged canonical campaign plus a smaller dual no-RREF
discovery allocation is therefore the defensible next compute portfolio.
