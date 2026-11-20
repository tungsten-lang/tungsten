# A structural proof for goldb-heqc-k2mul

Wassat proves the original 11,680-variable, 74,581-clause CNF unsatisfiable by simplifying both circuits from inputs to outputs. The local release build emitted 18,006,436 bytes of DRAT in 0.19 seconds. Backward checking took 3.37 seconds. The trimmed proof passed forward DSR checking in 0.78 seconds and LSR checking in 0.19 seconds. The certificate contains the original input, trimmed DRAT, checksums and replay commands. [Certificate](../../../build/sc2026-goldb/goldb-heqc-k2mul-native-proof.tar.gz)

## Recovered circuit

The only shared wires are the 90 primary inputs. Each side has 5,750 gates, two fixed wires, and a maximum depth of 13. Another 86 XOR gates compare output pairs, and the final clause asserts that at least one differs. Across the two sides and comparator there are 11,352 four-input definitions and 234 two-input definitions, counting syntactic inputs before removing redundant ones.

The old single-output guard reads the first literal of each non-unit clause as the gate being defined. Line 359 of the DIMACS file starts with 177, which already has a complete definition. That line actually begins the definition of 179. Its three clauses reduce to the identity 179 = 178. Independently, the final assertion is an 86-literal disjunction, outside the old guard's single-unit contract.

The native multi-output path accepts a consecutive sequence of gate definitions, verifies their complete truth tables, and rejects cycles. It normalizes each table over sorted signed wire representatives, removes inessential inputs and represents a function and its complement with opposite signs. An independent decoder found 2,445 distinct functions with at least two essential inputs after normalization, keyed by both support and truth table. All 86 comparison results reduce to false.

For DRAT, a full assignment to the local inputs forces the output of a verified definition by unit propagation. Resolving complementary assignments removes inessential inputs. The same construction proves each direction of an alias. This yields a negative unit for every mismatch signal and discharges the original final clause. The trimmed native proof used 305,178 lemmas and zero RAT steps. [Implementation](../lib/output_miter.w)

## Baseline profile

Wassat parsed the CNF in 3 ms. The implication graph had 23,348 singleton components and the AND2 pass found zero candidates. In a 30-second macOS sample, 2,017 of 2,700 main-thread samples (74.7%) were in watched propagation, 461 (17.1%) in conflict analysis, 81 (3.0%) in backjumping and 40 (1.5%) in local search. The interrupted run had emitted 149,811,532 bytes of proof. [CPU sample](../../../build/sc2026-goldb/window.sample) · [Stage log](../../../build/sc2026-goldb/window.log)

Changing the first comparator from XOR to XNOR gives a satisfiable neighbor. Both an independently constructed all-zero-primary-input witness and Wassat's ordinary fast-search model checked against the modified CNF. On 24 small circuits with shuffled gate-literal positions, variable order changes and a redundant input, all 12 equivalence proofs and all 12 inequivalence models passed external checking.

## Cross-family checks

The previous and candidate release binaries each ran the seven solved controls three times, alternating their order. All 42 models passed independent checking. Six SBDP instances, j3037 and the reconfiguration instance reached the three-second limit on both binaries. The candidate also produced checked proofs on sqrt-mitern168 (6.98 s), SCPC-500-19 (23.62 s) and vdwb_k5_n260 (20.06 s). It produced checked models on the original WS_500 argumentation case (7.25 s) and stable-400-0.1-7 (1.10 s). Times in this section exclude external checking. [Per-run results](../../../build/sc2026-goldb/controls.jsonl)

Three controls with variable first-pass times were repeated in six counterbalanced rounds after the longer jobs finished. Each model passed checking. Median wall times in milliseconds follow. The bypass setting disables both miter guards on the candidate. [Repeat timings](../../../build/sc2026-goldb/repeat.jsonl)

| Control | Previous release | Candidate | Candidate with guards bypassed |
|---|---:|---:|---:|
| n384p5q2_vh.af_138 | 1616.5 | 1595.5 | 1574.8 |
| knight_18 | 125.5 | 127.6 | 128.0 |
| Circuit_multiplier36 | 8.7 | 8.7 | 8.6 |
