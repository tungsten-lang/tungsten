# Fixed-rank pocket words (2026-07-21)

The autonomous fixed-rank pocket move becomes more useful when treated as a
short word rather than a one-shot density operator.  The benchmark
`flipfleet_fixed_rank_pocket_word_bench.w` beam-searches two- and three-ticket
words with the following hard bounds on every ticket:

- at most five selected terms;
- at most five local flips;
- at most 512 retained local states;
- at most 12 bits of density debt on any local edge;
- exact whole-tensor verification at every ticket endpoint.

Literal one-flip ticket endpoints are retained alongside each ticket's
density-best local closure.  This is what makes neutral or uphill prefixes
available to a later word.  Whole schemes are canonical-term-set deduplicated;
the hash is only a prefilter and exact set equality is authoritative.

## Results

The packaged 7x7 C013 composition improves as follows:

```
d3554 --A1:g10--> d3544 --A1:g10--> d3534 --A1:g10--> d3524
```

Each `A1` is autonomous ticket ordinal 1 resolved against the current exact
scheme.  Each local closure has depth one, barrier zero, three retained local
states, and 4,419 proposals.  The final scheme is support-distance 12 from
C013.  Its certificate is
`matmul_7x7_rank247_d3524_fixed_rank_pocket_word_gf2.txt`.

Starting from the independently found d3546 barrier child yields:

```
d3546 --A1:g10--> d3536 --A1:g10--> d3526 --A1:g10--> d3516
```

That certificate is
`matmul_7x7_rank247_d3516_fixed_rank_pocket_word_gf2.txt`, also at support
distance 12 from its immediate root.

Extending the word to bounded convergence showed that a fixed ordinal is only
a prepass.  Replaying ordinal 1 stops after the three steps above, but a full
strict-gain rescan of the current ticket surface reaches:

```
3554 -> 3544 -> 3534 -> 3524 -> 3514 -> 3506 -> 3498 -> 3496
ticket     1      1      1      3      4     42      7
gain      10     10     10     10      8      8      2
```

The first four closures have local depth one.  The next two have depth four
and require local uphill edges of `+10` and `+9`; the final gain-two closure is
again depth one.  A complete rescan after d3496 finds no strict gain, so the
chain stops after seven tickets rather than cycling or hitting its 32-ticket
limit.  It used 344 ticket searches, 43,303 retained states, and 50,740,254
local proposals.  Its endpoint is support-distance 28 from C013.  Starting
from d3546 reaches the same canonical term set in six tickets.

The packaged production prepass consumes the first three ordinal-1 gains for
17,676 proposals, then begins full rescans.  It reaches the same d3496 endpoint
in 31,614,912 proposals, 37.7% less work than rescanning all 43 tickets at the
first three rungs.  The exact certificate is
`matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt`.  This is a
reproducible closure, not a rank record: the live rank-247 density leader
remains d3094. A later CUDA campaign independently rediscovered the already
packaged d3492 child, whose support is only four terms away and which beat
d3496 20/24 times with four ties in matched one-million-move continuations.
The catalog therefore uses d3492 for the automatic C013-density slot and keeps
d3496 in the explicit experiment inventory.

A wide 64-parent beam did not improve either productive word.  It considered
4,898 tickets per C013-rooted run, roughly 610,000 retained local states, and
716--717 million local proposals.  It also found exact tunnel-only words.  The
best C013 example ends at d3534 after two productive tickets and a neutral
literal ticket; it is inferior in density to the all-productive word but pins
the intended neutral-prefix capability.

The initial six paired 250,000-move controls favored d3524 5--1 over C013 and
split d3516 3--3 against d3546.  A longer 24-trial, one-million-move three-arm
control was appropriately less decisive for those short words: root,
one-ticket child, and three-ticket word won 7/12/5 from C013 and 8/11/5 from
d3546.  In contrast, the converged d3496 door won 24/24 trials against both
the root and one-ticket child from either starting branch.  Its minimum and
integer-average final densities were 3492/3495, versus 3510--3511/3513 for
C013 controls and 3502/3504--3505 for d3546 controls.  This supports a bounded
low-cadence productive closure, not making it a normal per-move policy.

Controls were negative and useful: no chained density improvement was found
from the 3x3 d139, 4x4 d450, 5x5 d967, 6x6 d1860, or 7x7 d3094 leaders.  The
4x4 leader has no legal ticket at all.  Neutral/worse doors from 6x6 and the
7x7 d3094 leader lost all six matched continuations; the 3x3 and 5x5 neutral
doors tied their roots.

`flipfleet_fixed_rank_pocket_word_test.w` replays both three-ticket words from
scratch, reloads both certificates, verifies every exact endpoint, pins the
density sequence and support distance, and reconstructs the neutral-prefix
tunnel. `flipfleet_fixed_rank_pocket_chain_bench.w` independently extends the
fixed and greedy policies to convergence and emits the full ticket/proposal/
barrier trace. The packaged strategy regression reconstructs d3496 without a
target certificate and proves that the ordinal-1 prepass preserves the result
while saving more than 18 million proposals.
