# Learned residual completion: first bounded screen

Runtime decision after the native port: remove the public flag and production
integration. The port passed correctness tests (340 parity cases and bounded
fleet integration), but those were not a matched efficacy improvement. Extra
same-rank representations alone did not establish downstream composition
utility. The native implementation/model now live under
`tools/learned_residual/`, outside the shipped runtime, for further research.
Proven useful methods should run automatically; an opt-in switch is not a
substitute for establishing usefulness. Existing automatic refinement remains.

Decision: retain the offline experiment; do not enable a production fleet lane.
No rank improvement or world record was found. Five parent-distinct tensors
were found by learned ordering but neither control in this particular screen;
that is search diversity, not proof of global novelty or composition utility.

## Mechanism and correctness boundary

The proposer receives only a GF(2) residual tensor and its dimensions. Lossless
mode-space compression is computed from tensor fibers, not from the removed
factor list. It searches the complete rank-one alphabet when each compressed
mode has dimension at most four. Larger modes are unsupported in this version.
All policies share exact flattening lower bounds, exact rank-one tail
completion, exact residual transpositions, beam width four, and a 24,000-XOR
work cap plus three-second wall cap. Beam exhaustion is not an impossibility
certificate. Density is not a learned search feature.

The 18-input, 24-hidden-unit local NumPy MLP ranks residuals using all
slice-combination matrix-rank histograms. These features are invariant under
invertible changes of the three mode bases and permutations of the modes.
Training used 10,000 generated recipes, deduplicated to 2,330 residuals. Labels
are the smallest observed recipe lengths, **upper bounds, not optimal ranks**.
Whole feature-identical groups stay in one split: 1,950 train / 221 validation /
159 test. No real matrix-multiplication seed windows train the model. Selection
of the 400-epoch model uses validation loss; the test label MSE is 0.813. This is
an exploratory, single-model screen, not a statistically established gain.

## Matched results

Real sources: 2x2x2/r7, 3x3x3/r23, 2x4x5/r33, 4x4x5/r60, 5x5x5/r93. Each gets
60 fixed windows of 3–6 removed terms, alternating random and shared-factor
selection. Each window is tested both at k-1 terms and at k terms. Controls are
residual-popcount and random beam ordering with the same alphabet, exact
helpers, window, seed and work cap—not the older sampled-512-term beam.

| Outcome | Learned | Popcount | Random |
|---|---:|---:|---:|
| Synthetic held-out completions / 128 | 123 | 111 | 59 |
| Real recoveries / 300 | 150 | 150 | 147 |
| Parent-distinct real representations | 10 | 5 | 11 |
| Real strict rank drops / 300 | 0 | 0 | 0 |
| Real recovery search seconds | 22.58 | 15.99 | 16.98 |
| Synthetic search seconds | 12.04 | 6.46 | 7.41 |

120/300 real recovery windows exceed the four-dimensional model scope. For
strict drops, 267/300 are excluded by the exact flattening lower bound, three
are unsupported, and thirty exhaust the bounded beam without a result. These
counts limit the usefulness of random small windows on the current leaders.
No time cap fired. Policy order rotates, the shared rank cache is cleared, and
timings include dictionary construction/features/inference but exclude model
training and outer full-tensor admission. This is not an equal-wall-time win.

The broad run retained **20** distinct parent-different representations across
all arms; union with the pilot is **21**, not 23. They have not been compared
against every archived tensor or tested for composition gains. Do not count
them as new globally known decompositions.

## Replay

```sh
python3 bits/tungsten-metaflip/spec/learned_residual_completion_test.py
python3 bits/tungsten-metaflip/tools/learned_residual_completion.py \
  --output /tmp/metaflip-learned-residual-run --samples 10000 --epochs 400 \
  --windows 60 --holdout 128 --budget 24000 --seconds 3
python3 bits/tungsten-metaflip/tools/audit_learned_residual.py \
  /tmp/metaflip-learned-residual-run
```

Recorded run: `/private/tmp/metaflip-learned-residual-20260914-v3/`.
It retains source snapshot, model, training recipes/features, input hashes,
case definitions, every result, candidate files and report. Replay passed all
2,184 result rows, 740 exact completions and 25 independent Ruby full-tensor
checks (20 distinct candidates plus five original seeds). Nine focused tests
also pass, including all 256 binary 2x2x2 residual tensors, compression/lifting,
basis/mode invariance, model schema/roundtrip, budgets and corrupted-candidate
rejection. No background jobs, commits, publication or reference updates.

Pilot evidence remains in `...-v2/`; `...-v1/` records a startup failure caused
by the initial reader not accepting R-prefixed seed files. The corrected reader
is covered by the declared-real-seed test. Do not report v1 as a completed run.

Next useful test: score which windows deserve repair using observed exact
outcomes, and/or a richer residual policy on modes five/six. Simply deploying
this value model would add about 41% real-recovery time without more completed
real repairs. A native implementation needs an equal-wall-time quality win
before it should consume default fleet capacity.
