# Closing sqrt-mitern168 with a checked Wassat proof

## Native default

Wassat now runs both the structural guard and the incremental sweep in process.
On the original input it proposed 288 pairs and proved 565 directed implications.
It restores the original comparator assertion before final search. With the sweep disabled, the same release binary reached the 60-second cutoff on the original input. An unrestricted
file-DRAT run took 8.72 s, followed by 5.42 s for independent checking. The
trimmed proof also passed forward DSR replay and LSR checking. A renumbered copy
took 14.19 s to solve and 7.42 s to check. Reversing the comparator assertion
produced a checked SAT model in 0.66 s plus 0.07 s for checking.
[Native certificate and replay commands](../../../build/sc2026-native-gatemiter/sqrt-mitern168-native-proof.tar.gz)

The same release binary ran each solved control three times per setting in
alternating order. Wall times below exclude the independent model check. All
42 models passed. The other eight controls (six SBDP, reconf and j3037)
timed out at three seconds in both settings.
[Per-run measurements](../../../build/sc2026-native-gatemiter/comparison.jsonl)

| Control | Sweep disabled, median ms | Sweep enabled, median ms |
|---|---:|---:|
| Circuit_multiplier36 | 21.0 | 20.9 |
| st_540 | 11.3 | 11.2 |
| sted5_0x1e3-20 | 39.1 | 40.0 |
| knight_18 | 182.1 | 184.0 |
| sum_of_3_cubes_50_bits_91 | 41.0 | 39.1 |
| n384p5q2_vh.af_138 | 1945.3 | 1902.3 |
| cabp-P-can__445 | 346.6 | 347.3 |

## Follow-up on other SC2026 instances

| Instance | Method on the original CNF | Solver time | Independent check |
|---|---|---:|---|
| vdwb_k5_n260 | Ordinary Wassat file DRAT | 29.49 s | drat-trim verified UNSAT |
| SCPC-500-19 | Ordinary Wassat file DRAT | 27.12 s | drat-trim verified UNSAT |
| WS_500_16_70_10.apx_2_DS-ST | Fast CDCL portfolio, arm 7 | 7.09 s | Full SAT model checked |
| stable-400-0.1-7-9876543214007 | Fast covering case split | 1.14 s | Full SAT model checked |

The WS input contains both binary clauses enforcing each of 500 complementary
pairs. Substitution and deduplication reduce 13,501 clauses to 4,501 on 500
variables. The reduced instance also yielded a model that lifted to a checked
model on all 1,000 original variables. The direct fast run solves the original
without that separate reduction. On stable-400, 14,284 distinct mixed clauses
are single resolvents of a positive coverage clause and a negative conflict
pair. The original fast covering specialist already solves this case.

The initial file-DRAT run on goldb-heqc-k2mul reached 30 seconds. A subsequent native structural pass closed it. [Checked Goldberg proof](sc2026-goldb-heqc-k2mul.md) SBDP4_61_2 and the
reconfiguration case reached 60 seconds in proof mode. These runs produced
no checked refutation. [Proof-mode results](../../../build/sc2026-native-gatemiter/follow.jsonl)
· [Installed binary results](../../../build/sc2026-native-gatemiter/installed-checks.jsonl)

## Earlier external experiment

On the original SC2026 input, CaDiCaL proved 293 internal signal equalities and Wassat completed an UNSAT refutation. The gate queries excluded the two comparator operands. The concatenated DRAT proof checked against the original 18,949 clauses. Its trimmed core also passed a separate forward DSR replay and an LSR check. The certificate bundle includes the input and replay commands. [Certificate](../../../build/sc2026-sqrt168/sqrt-mitern168-proof.tar.gz) · [Implementation and build instructions](../benchmarks/gate_miter/README.md)

## What survived Cruxmiter

| Quantity | Original | Checked residual |
|---|---:|---:|
| DIMACS variable bound | 4,322 | 4,322 |
| Variables actually occurring | 4,321 | 4,290 |
| Unit clauses | 2 | 2 |
| Binary clauses | 6,310 | 6,351 |
| Ternary clauses | 8,622 | 8,498 |
| Four-literal clauses | 3,387 | 3,387 |
| Five-literal clauses | 628 | 628 |
| Total clauses | 18,949 | 18,866 |

The Cruxmiter counters reported 120 merges and 31 substitutions in round one, then zero in round two. All 31 disappearing variables came from the right-only cone, including comparator operand 838. The asserted XOR implies the disequality between signals 3 and 838. The prefix contains both binary clauses expressing this disequality before substitution removes 838. The refutation still needs to show that the two pieces of logic always produce equal outputs.

On the original clauses, exhaustive local truth tables identified 4,282 gate definitions. The comparator is variable 2, defined as the XOR of 3 and 838 and asserted true. The two fan-in cones have 873 and 3,518 variables and depths of 318 and 90 gates. Their intersection contains 72 variables, including the 38 primary inputs feeding the output. The checked residual lost 83 clauses in total.

## The next minute

On the checked residual, the first Wassat substitution pass found 8,640 singleton implication-graph components and the AND pass eliminated 452 candidates. I sampled the release executable's main thread over the full 60-second window and resolved symbols with the matching sidemap. Of 5,453 samples, 4,194 (76.9%) were in watched-literal propagation and 881 (16.2%) in conflict analysis. Local search accounted for 85 (1.6%) and backjumping for 73 (1.3%). The memory watchdog has its own thread and is excluded from that denominator. The earlier timed residual run wrote 393,245,569 proof bytes before its cutoff. [CPU sample](../../../build/sc2026-sqrt168/window.sample) · [Residual profile](../../../build/sc2026-sqrt168/window.log)

## The proof

The experiment recovers the original comparator and simulates 1,024 input assignments. It uses signatures to propose equalities and complemented equalities across different gate structures. Incremental SAT queries require both directions to establish an equality. Removing the output assertion from the query formula keeps the internal facts independent of the contradiction being proved.

Of 296 candidate internal pairs, 293 were proved equal up to sign, including 171 links across the two exclusive cones. Wassat received the original input plus 586 proved binary implications, substituted 293 variables, and refuted the result in 130,209 conflicts and 179,638 decisions. In two local runs, recognition, simulation, and sweeping took 4.65–4.80 s, Wassat took 4.14–4.67 s, and composing and checking the proof took 7.24–8.16 s. The runs finished in 16.0 and 17.6 s respectively. The checked proof was 34,213,659 bytes before trimming.

A separate experiment allowed the helper to prove the comparator operands directly. Wassat then closed the miter at zero decisions. The certificate bundled above uses the internal-only experiment.

## Control cases

The structural screen examined all 400 local SC2026 inputs. Five passed gate decoding and comparator simulation. Four SBDP miters had candidate matches confined to one side, so the cross-cone guard admitted only sqrt-mitern168. The guard uses gate structure and truth signatures. It does not inspect filenames or hashes.

The variable-renumbered target also returned checked UNSAT in 17.7 s. Reversing the miter assertion gave a SAT near-neighbor whose model passed the original-clause checker. On 15 other SC2026 cases at a 3 s cutoff, both configurations returned the same seven checked models and eight timeouts. These included argumentation, Stedman, knight, sum of cubes, a multiplier, graph bandwidth, reconfiguration, scheduling and SBDP cases.

The comparisons used a release Wassat at commit `9640787f`. The optional Python driver adds startup latency to fallback runs, which matters for millisecond solves. The production configuration was left as it was. [Paired controls](../../../build/sc2026-sqrt168/controls.jsonl) · [SBDP comparisons](../../../build/sc2026-sqrt168/sbdp-guarded.jsonl) · [400-instance admission scan](../../../build/sc2026-sqrt168/admission-final.json)
