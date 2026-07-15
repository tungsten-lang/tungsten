# Direct GF(2) rank-19 campaign for `<2,2,6>`

## Claim boundary

The rigorous interval is unchanged:

```text
19 <= R_GF(2)(<2,2,6>) <= 21.
```

The lower endpoint is Bläser's concise-tensor bound
`ac+a+c-1 = 6*2+6+2-1 = 19`, applied in the cyclic orientation
`<6,2,2>`.  The upper endpoint is the exact 21-term three-Strassen-block
scheme in
[`matmul_2x2x6_rank21_strassen_blocks_gf2.txt`](../matmul_2x2x6_rank21_strassen_blocks_gf2.txt),
whose SHA-256 is
`4c1820d0a51df84721ecb52bdb540c30c1008aa7319ef39c89a539f5212f8f04`.

The direct campaign below asks whether rank at most 19 exists.  All current
runs are **indeterminate**.  They neither raise the lower bound to 20 nor
lower the upper bound to 19.  A lower-bound claim requires every shard to be
UNSAT, every FRAT-XOR proof to be elaborated, and every elaborated proof to
pass the checked verifier.

## Complete 43-shard split

The cyclic `<6,2,2>` orientation permits both the primary and optional dual
inner-dimension-two quotient conditions.  Fixing one used term and splitting
its residual stabilizer orbits gives the same complete case counts as the
adjacent `<5,2,2>` campaign:

| fixed adjacent-factor case | shards |
|---|---:|
| `a1_b1_p0` | 7 |
| `a1_b1_p1` | 7 |
| `a1_b2` | 7 |
| `a2_b1` | 13 |
| `a2_b2` | 9 |

The canonical arm uses the primary quotient condition, its exact RREF gauge,
lexicographic ordering of terms 1 through 18, and nonzero third factors.  The
last condition is sound because the independent analytic lower bound is
already 19: any rank-at-most-19 decomposition would use exactly 19 terms.
The runner and proof verifier independently audit this prerequisite.

Generate the reproducible canonical campaign with:

```sh
cd benchmarks/matmul/metaflip/proof_inner2
python3 inner2_generate_campaign.py /tmp/n622-r19-v1 \
  --a 6 --c 2 --terms 19 \
  --known-lower-bound 19 --nonzero-c --lex-terms
```

The measured manifest SHA-256 is
`e33077ef9bd88cc2e9241c408a0767233092831682fc6817c66dbfd7558e0a2e`.
Each of its 43 formulas has 18,398 variables, 57,328 ordinary clauses, 1,488
native XOR constraints, and 997,659 bytes.  Regeneration with the current
tools reproduces that manifest byte for byte.

Run it serially and resumably with:

```sh
python3 inner2_run_xnf_campaign.py \
  /tmp/n622-r19-v1/manifest.json \
  /tmp/n622-r19-v1-run \
  --seconds 60 --priority least-cpu
```

`least-cpu` levels cumulative solver time across shards, while every retry
advances the random seed.  The initial calibration gave all 43 formulas two
CPU seconds.  Every result was `INDETERMINATE`; conflict counts ranged from
48,385 to 62,182, with a mean of 55,917 over 78.05 aggregate reported CPU
seconds.  These counts measure solver behavior, not mathematical progress.

For a final UNSAT attempt, retain a proof with `--proof`.  Solver-reported
UNSAT remains explicitly unchecked until
`inner2_verify_xnf_campaign.py` validates complete coverage and formula
hashes, audits the analytic prerequisite, and successfully replays all 43
elaborated proofs through the checked XLRUP verifier.

## Safe solver portfolio

The canonical RREF arm remains the proof-production default.  The following
arms are equisatisfiable and useful for discovery diversity, but none has
solved a rank-19 shard:

- `--no-rref` removes the quotient factorization gauge.  It processed about
  94,487 conflicts per matched three-second probe versus 73,409 for the
  canonical arm, but it also retained much more auxiliary symmetry.
- `--dual-inner2-quotient --no-rref` adds the second cyclic quotient while
  leaving both quotient bases ungauged.  It averaged 86,905 conflicts in the
  same three-shard window.
- generating the transposed cyclic orientation with `--a 2 --c 6` averaged
  79,004 conflicts.  This is a variable-order portfolio arm, not additional
  coverage: either complete orientation already covers the tensor.
- CryptoMiniSat `--polar=true` was the strongest distinct solver trajectory.
  Across three matched ten-second seeds on the `a2_b2/o8` shard it averaged
  674,160 conflicts, versus 235,585 for the default.  On the adjacent known-
  UNSAT `<4,2,2>` rank-13 calibration it was still indeterminate after 60
  seconds, however, and it produced fewer intermediate level-zero reductions.
  It should receive a discovery/diversity fraction, not replace the default.

Run the positive-polarity arm in a separate resume directory so its attempts
and telemetry remain distinguishable:

```sh
python3 inner2_run_xnf_campaign.py \
  /tmp/n622-r19-v1/manifest.json \
  /tmp/n622-r19-v1-polar-true-run \
  --seconds 60 --priority least-cpu \
  --cms-arg=--polar=true
```

RREF, dual-RREF, no-RREF, and polarity are search choices only.  An UNSAT
formula is useful for the bound only after proof logging and checked replay,
regardless of which safe arm found it.  A SAT line is accepted only after the
independent model auditor reconstructs the full tensor.

## Witness-free factor-span strengthening

`--span-dependency-weight W` adds an optional consequence of conciseness.
In every exact decomposition, the displayed A, B, and C columns span their
complete factor spaces.  Therefore no nonzero linear combination of factor
coordinate rows can vanish across every term.  The option excludes all such
dependencies through Hamming weight `W`, using native XOR parity helpers and
one nonvanishing clause per checked row combination.  It introduces no
inverse witness and hence no affine witness symmetry.

The full-weight `<2,2,2>` rank-seven control remained SAT and its model was
independently reconstructed with all seven terms.  On `<6,2,2>`, weight one
adds only 28 clauses and no variables; weight two adds 2,622 parity variables,
2,622 XOR constraints, and 138 clauses.  In the known-UNSAT `<4,2,2>`
rank-13 calibration, weight two raised preprocessing assignments but did not
solve the shard or improve time to a conclusion.  The strengthening is thus
retained as an opt-in experimental arm, not enabled in the canonical
manifest.  Leaving the option at zero preserves the canonical formula and
manifest hashes exactly.

## Telemetry correction

The resume runner now parses CryptoMiniSat's scaled integer counters.  Values
such as `39.4M` propagations are stored as `39,400,000`, rather than the old
truncated value `39`.  This changes only campaign telemetry; it does not
change formulas, hashes, solver commands, proof acceptance, or the rank
interval.
