# SC2026 Tactix trials on Wassat

The three upstream openings ran ahead of the same proof-enabled Wassat release at `9640787f`. Each nonempty DSR transformation passed through an independent checker before Wassat saw the residual. An UNSAT result required a checked refutation. A SAT result required a model satisfying the original CNF. Final checking time is separate from solving time.

## Competition screen

The 154 inputs were historical v93 misses from the 400-instance main track. Each configuration received 0.5 seconds per input. This screens for inexpensive transfers and damage to existing fast solves. It gives limited information about longer searches, particularly when an opening timed out during input or proof processing.

| Configuration | Checked SAT | Checked UNSAT | Reached search and timed out | Opening timed out | Prefix check or residual output timed out | Baseline solves lost at cutoff |
|---|---:|---:|---:|---:|---:|---:|
| Wassat | 53 | 0 | 101 | — | — | — |
| Cruxmiter | 9 | 0 | 66 | 69 | 10 | 45 |
| GraphIntervalEquivalence | 13 | 0 | 82 | 50 | 9 | 41 |
| Chvátal twins | 11 | 0 | 70 | 62 | 11 | 43 |

The sole additional checked model at this cutoff was `n384p5q2_vh.af_138`, common to all three openings. Tactix ingestion removed 7,204 duplicate negative binary clauses. Every deleted clause retained another copy. All three policies and input alone produced byte-identical prefixes (SHA-256 starts with `b62be6773dfee8b7`). In the six-second comparison, raw Wassat solved in 1.647 s, Tactix ingestion alone in 0.165 s, and reserializing after an empty prefix in 0.141 s. Removing only duplicate binaries while retaining input order took 1.752 s and the model checked on the original. Clause order accounts for a speedup on this case without any specialist action.

## Structure and matched controls

- **Cruxmiter.** On the authors’ seed 0, there are 536 directly encoded signed two-input AND outputs and zero repeated operand pairs in the raw clauses. The upstream opening found zero congruence merges and zero substitutions. Its entire prefix added one binary clause and deleted one ternary. The original and a variable permutation both timed out at 15 s across all arms. Flipping the miter output unit gave checked SAT models. On the real SC2026 square-root miter, the first round reported 120 merges and 31 substitutions, followed by a round with neither. The SC2026 multiplier already yielded a checked baseline SAT model. With full residual rewriting, both Cruxmiter and twins timed out there at 15 s. Empty-prefix reserialization also timed out. The loss can occur solely from how clauses are presented to Wassat.
- **GraphIntervalEquivalence.** The positive upstream fixture published both binary directions between variables 10 and 11. Removing one defining clause suppressed publication. The interval contradiction also checked as one DSR proof from the original CNF through the Wassat refutation. There were zero observed publications in the competition screen. Fifty interval runs exhausted the budget in the opening.
- **Chvátal.** Five SC2026 inputs logged accepted twin witnesses in the short screen. On the scheduling cases `j3037_9_rggt_bm1` and `j3045_4_rggt_bm1`, the upstream pass proposed 119 and 100 pairs and accepted 2 and 6 directional witnesses respectively. Wassat, the full policy, and the same policy with the pair list suppressed all timed out at 12 s. On the authors’ Chvátal input, the opening found 4,508 pairs across seven rounds, accepted 6,619 directional witnesses and reported 3,335 substitutions. The independently checked transformation reduced 68,854 clauses to 29,049. At a 60 s budget, full twins spent 37.059 s in the opening, 0.232 s checking it and 22.710 s in Wassat. All three arms timed out.
- **Cross-family controls.** At 2 s, baseline returned checked models on the argumentation, Stedman, knight and sum-of-cubes controls. The full Cruxmiter and twin bridges missed all four at that cutoff. Interval retained Stedman and knight. A residual model also failed an original clause on a small substitution control. Pinning the remaining active variables and completing eliminated variables recovered original-checked models on all three failed control runs.

## Stronger comparisons

On the SC2026 square-root miter, baseline and Cruxmiter both reached the 60 s limit. Wassat consumed 59.82 and 59.49 seconds of CPU and peaked at 63.0 and 62.8 MiB RSS respectively. Both runs continued writing proof fragments. Neither completed a refutation.

The raw indexed-column scan read all clauses from all 154 inputs, including those too large for the half-second opening. It found no plausible indexed column on 134, incomplete coverage on 10, and full column coverage at the detected dimension on 10. Full columns are only a precondition. Four of those ten timed out early in the original interval screen. All four completed the interval action at 12 s and it returned no progress on each. Baseline also found an original-checked SAT model on one of those four, `cabp-P-can__445.mtx.rnd-k96`, in 0.251 s. The residual bridge timed out at 12 s.

Publishing only verified short additions while preserving original clause order recovered several fast existing models. Cruxmiter additions still lost the multiplier at a 4 s cutoff. Some proposed add-only prefixes needed intermediate proof steps. The checker rejected those prefixes and the driver fell back to the original CNF.

## Chvátal witness batching

An instrumented replay of the upstream policy timed pair discovery at 0.012 s, the per-witness merge stage at 36.488 s, and substitution at 0.037 s. Both executions emitted the same proof bytes. The bulk prototype uses the same pair finder, proposes both SR directions in bottom-up order, and emits RUP rewrites using the accepted equality relation. dsr-trim independently validates the complete prefix before search.

On the paper input, the checker accepted all 9,016 directional proposals and the quotient proof. The resulting CNF had 39,428 clauses. The prototype took 0.316 s to construct its prefix and 0.132 s to check and emit the quotient, leaving 59.554 s for Wassat. The full upstream opening and verification took 37.291 s and produced a smaller residual. Neither produced a complete refutation within 60 s. The two openings differ in the additional simplifications they perform.

The build, harness, raw per-instance results, profile logs and checked focused certificates are described in [the reproduction notes](../../../build/sc2026-tactix-trials-20261118/README.md).

All five competition instances with accepted witnesses in the initial screen passed the bulk quotient checker. All five timed out at 12 s. Plain Wassat returned a checked SAT model for one of them, `as-p43-l16-o9-567`, in 0.027 s. The upstream twin policy also timed out there. Bulk preserved checked models on the multiplier, Stedman and argumentation controls and missed the 2 s sum-of-cubes control. The prototype remains available for experiments. Wassat's default configuration received no changes.
