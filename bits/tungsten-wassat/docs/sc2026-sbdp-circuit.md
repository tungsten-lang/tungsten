# Exhaustive circuit certificates for SBDP

On `sbdp4_61_2`, the 644 declared variables encode 614 gates over 28 primary inputs. Variable 644 is fixed false. The asserted output is wire 2, the XOR of wires 3 and 379. Their cones contain 404 and 276 wires respectively, with 39 shared. No primary-input assignment makes the two output signals differ.

## Where the minute went

The fast-mode profile identifies the Gray-code evaluator. It covered 268,435,456 assignments in 4,194,304 batches of 64, with 151,260,664 word-gate evaluations. The previous CLI attributed several different algorithms to a common multiplier-factorization message. The CLI now identifies exhaustive circuit evaluation when that routine wins.

File-DRAT mode skips this evaluator because its exhaustive loop supplies no clausal derivation. Parsing took about 1 ms. The implication graph had 1,284 singleton components, and preprocessing eliminated 24 of 144 AND2 candidates. Of 5,464 main-thread samples across 60 seconds, watched propagation accounted for 4,426 (81.0%), conflict analysis for 697 (12.8%) and local search for 124 (2.3%). The interrupted proof file had reached 425,731,909 bytes. [CPU sample](../../../build/sc2026-sbdp61/window.sample) · [Stage profile](../../../build/sc2026-sbdp61/window.log)

## What the checker proves

The certificate lists primary inputs, fixed literals, the asserted literal and gates in dependency order. Each gate record supplies its input wires, truth table and original clause IDs. Bit *m* of a gate table is the value for the assignment in which input *j* takes bit *j* of *m*.

The independent checker reads the original CNF, validates the units, and tries both gate-output values on every local input assignment. Internal gates must have a unique output under the cited clauses. For the asserted output it computes whether the requested value is **permitted**. This also handles one-sided gate encodings in which both output values can satisfy a local row. It rejects forward references and use of the output predicate as an internal wire.

Any model of the full CNF must satisfy the cited clauses. Induction along the checked gate order therefore fixes each internal signal as a function of the primary inputs. The checker packs up to 16 inputs into Python integer bit positions, enumerates every assignment to the remaining inputs, and requires an empty set of assignments permitting the assertion. This replay uses binary enumeration and Boolean-ring operations independently of Wassat's Gray-code kernels. The circuit certificate has its own checker and format. A DRAT-only checker still requires a clausal proof.

The target certificate is 26,132 bytes. Changing the asserted mismatch to agreement gave a SAT model that satisfied every clause in the modified input. Wassat declined to certify the mutation. Replacing the original assertion and gate table in the certificate with the correct local values for agreement also failed the global check. [Checker](../competition/check_circuit.py) · [Negative tests](../competition/check_circuit_test.py)

## Independent Lean proof for sbdp4_61_2

Lean 4.34.1 kernel-checked the theorem that every Boolean assignment fails the original CNF. A literal-for-literal check matched all 2,619 clauses in order. Local Boolean lemmas connect the clauses to the gate functions. The proof packs 18 primary inputs into bit positions and proves by kernel reduction that each of the 1,024 remaining input blocks has zero output. Together they exhaust all 28 inputs. The standalone replay took 44.1 seconds and Lean reported only `propext`, `Classical.choice` and `Quot.sound` as axioms. [Lean source](../../../build/sc2026-sbdp61/Refutation.lean) · [Kernel log](../../../build/sc2026-sbdp61/formal.log)

## Reproduce

```sh
bits/tungsten-wassat/bin/wassat certify input.cnf --circuit output.cert
python3 bits/tungsten-wassat/competition/check_circuit.py input.cnf output.cert
```

The generator returns exit 20 on an exhaustive refutation and exit 0 with UNKNOWN on a miss. The checker exits successfully only after validation and exhaustive replay.

## Six checked SBDP results

| Instance | Emit (s) | Check (s) | Certificate bytes |
|---|---:|---:|---:|
| sbdp4_61_2 | 0.065 | 0.27 | 26,132 |
| sbdp4_65 | 0.071 | 0.84 | 34,154 |
| sbdp4_136_2 | 1.404 | 95.99 | 79,312 |
| sbdp4_138 | 1.362 | 231.31 | 103,610 |
| sbdp4_138_2 | 1.502 | 91.21 | 79,304 |
| sbdp4_140_2 | 1.504 | 93.83 | 79,330 |

The two smaller instances have 28 free inputs. Each other instance has 32, covering 4,294,967,296 assignments per replay. [Six inputs, certificates and replay tools](../../../build/sc2026-sbdp61/sc2026-sbdp-checked.tar.gz) · [Per-instance results](../../../build/sc2026-sbdp61/results.jsonl)

## Cross-family controls

The previous Goldberg release and the candidate ran seven solved controls three times apiece, in alternating order. All 42 models checked. Median solver times in milliseconds follow.

| Control | Previous | Candidate |
|---|---:|---:|
| Circuit_multiplier36 | 12.2 | 13.9 |
| st_540_25_12_12_9.af | 7.8 | 7.0 |
| sted5_0x1e3-20 | 19.2 | 19.2 |
| knight_18 | 135.6 | 131.6 |
| sum_of_3_cubes_50_bits_91 | 23.3 | 23.6 |
| n384p5q2_vh.af_138 | 1656.5 | 1633.6 |
| cabp-P-can__445.mtx.rnd-k96 | 276.3 | 279.2 |

Both releases reached the three-second file-DRAT cutoff on six SBDP instances, j3037 and the reconfiguration case. The new release retained checked DRAT proofs on goldb-heqc-k2mul (0.14 s), sqrt-mitern168 (5.88 s), SCPC-500-19 (22.73 s) and vdwb_k5_n260 (20.79 s), and checked SAT models on WS_500 (6.61 s) and stable-400-0.1-7 (1.05 s). Times exclude external proof and model checking. The explicit circuit-certification route declined all 15 non-SBDP controls sampled. [Timing ledger](../../../build/sc2026-sbdp61/controls.jsonl) · [Admission checks](../../../build/sc2026-sbdp61/declines.jsonl)
