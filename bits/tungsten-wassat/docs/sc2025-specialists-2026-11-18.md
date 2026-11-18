# Wassat specialist results on competition inputs

The arithmetic, finite-domain, counting, parity and local-induction work came
from the review of LymphoSAT’s 126 specialists. Family decisions use clauses
from the input. The SAT routes replay complete assignments, and the explicit
certificate command emits proofs for independent checking against the original
DIMACS. [Specialist audit](lymphosat-specialist-audit-2026-11-17.md) ·
[LymphoSAT paper](https://arxiv.org/abs/2609.14836)

| Family | Competition evidence |
|---|---|
| Summle | The twelve-clause admission check selected one of 800 SC2025 and SC2026 prefixes. The arithmetic witness for that SC2025 input completed all 93,724 Boolean variables. [Profile and witness](summle-2026-11-18.md) |
| Finite-domain CSP | Recovered models for SC2025 `frb35-17-5_ext` and `case20` and SC2026 `rbsat-v945c61409gyes9`. Two search trajectories shared a 150 ms deadline. The isolated corpus scan missed `case20` once under load. The ordinary CLI found it in all five paired release trials. [Search, timings and permutations](compact-domains-2026-11-18.md) |
| Clique capacity | Independently proved UNSAT for twelve SC2025 register-allocation inputs, two further SC2025 shuffled inputs and three SC2026 entries. One input appears in both years. [Derivation](polynomial-clique-capacity-certificate-2026-11-17.md) |
| Parity | Five checked SC2025 Tseitin proofs, including the 400 × 400 grid. Generation was faster than independent checking on all three large inputs. [Proofs and memory](parity-certificates-2026-11-18.md) |
| Local induction | Six generated UNSAT proofs passed verification. Six weakened SAT inputs returned UNKNOWN. Of 83 competition entries passing the initial shape check, none yielded a new induction proof. [Rule and controls](local-induction-2026-11-18.md) |

Profiling a separate graph-partition control, `GP_105_308_40`, showed a
dispatcher reading all 10,270,715 clauses solely to obtain a maximum width
that its caller had already measured. Wassat now reuses that width. The
fingerprint phase fell from 33 ms median to 0 ms in 13 paired runs with the
same original model. The full command took 1.017 s versus 0.958 s median in
that profiled series. Both releases took two lucky-phase dives and visited
11,828,388 watches. [Phase measurements](../../../build/wassat-sc2025-qualified-20261118/gp-profile.json)

## Verification and the argumentation control

The final release and the pre-Summle binary agreed on thirteen of fourteen
other SC2025 inputs. Each returned the same verdict seven times. Both timed
out on the remaining Stedman input at six seconds. The differential against
CaDiCaL checked 99 SAT models and 101 UNSAT proofs on 200 generated inputs.
VeriPB checked 19 SC2025 certificates and three SC2026 entries on the original
CNFs. These are per-instance measurements. The release binary is available
separately from the installed Wassat.
[Release and source hashes](../../../build/wassat-sc2025-qualified-20261118/manifest.json) ·
[Competition controls](../../../build/wassat-sc2025-qualified-20261118/final-integrated-controls-timings.json) ·
[Differential](../../../build/wassat-sc2025-qualified-20261118/differential.log) ·
[Certificates](../../../build/wassat-sc2025-qualified-20261118/certificates.json)

On the argumentation input `WS_500_16_90_70.apx_1_DS-ST`, seven unrestricted
pairs gave medians of 3.029 s before and 6.980 s after. An earlier series
went the other way. Ten more randomized triples gave 5.660 s before, 6.647 s
after, and 6.189 s in the same final executable with Summle and block-CSP
disabled. Local search won five, eight and seven races respectively. In the
first profiled triple all three local-search winners took exactly 24,430,239
flips. The block-CSP stage took 0–1 ms and the input failed the Summle gate.
Holding the work to 16,000 conflicts on one thread gave 0.410 s before and
0.406 s after over eleven pairs. The latest unrestricted slowdown is visible.
These experiments do not resolve a consistent timing cost attributable to
either new specialist.
[Randomized triples](../../../build/wassat-stable-20261118/ws-ablation.json) ·
[Fixed-work pairs](../../../build/wassat-stable-20261118/fixed.json)

The two SC2025 queries on this graph differ by the sign of one unit clause.
Each argument has a complementary Boolean variable. Eliminating those
complements and duplicate clauses reduces 1,000 variables and 13,501 clauses to
500 variables and 4,501 clauses. A solution selects an independent set that
attacks every unselected argument. The quotient gave two models in 1.810 s
and 0.884 s in exploratory Wassat runs. Both lifted assignments satisfied
every original clause. A graph search that inserted vertices and removed
conflicting selections came within three to six uncovered vertices over six
10,000-move trials. Thirty bounded searches per query that fixed a sample
of a near-solution also missed both models. The graph search remains an
experiment.
[Checked quotient models](../../../build/wassat-stable-20261118/pilot.json) ·
[Graph search](../../../build/wassat-stable-20261118/walk.log) ·
[Bounded repair](../../../build/wassat-stable-20261118/repair.json)

## What transferred from the other solvers

**Symmetry.** Satsuma implements iterative symmetry fixing and binary cuts
along a stabilizer chain. Its `fix` command reduced six competition inputs
to an empty clause. Appending Wassat’s DRAT suffix to Satsuma’s ASCII SR prefix
gave six proofs accepted by `dsr-trim --forward` against the original CNFs.
Wassat’s native capacity command also proves each of these inputs. On SC2025
`homer11` its proof was 5,204 bytes, compared with 17,534 bytes for the
composed SR proof. On `MVRoundRobin_n14_d10_v2` the composed proof was
3,316,955 bytes. Satsuma and Tactix both carry MIT licenses. The competition
archive for LymphoSAT supplied the code examined in the audit; the audit found
no permissive license covering the generated specialists.
[Symmetry paper](https://doi.org/10.4230/LIPIcs.SAT.2026.4) ·
[Proof composition results](../../../build/wassat-satsuma-20261118/results.json) ·
[Satsuma license](https://github.com/markusa4/satsuma/blob/main/LICENSE) ·
[Tactix license](https://github.com/ai-ar-research/Tactix/blob/b42e4709252827adf7b95def95e9dea90df9016f/LICENSE)

**Restart duration.** The CP paper treats a long Luby restart as multiple
base conflict budgets. Its controller normalizes decisions and conflicts per
segment, dampens reward for longer intervals and accounts for exploration
using cumulative segments. The Wassat benchmark applies this decision/conflict
policy to EVSIDS and VMTF. One proof-producing solver retains clauses between
root restarts. The paper evaluated VSIDS and CHB in Kissat’s stable mode.
[Paper and equations](https://doi.org/10.4230/LIPIcs.CP.2026.39) ·
[Policy driver](../benchmarks/restart_policy.py) · [Wassat kernel](../benchmarks/restart_policy.w)

At 16,384 conflicts on eleven SC2025 inputs and 32,768 on sixteen more,
duration-aware UCB, ordinary UCB and round robin each solved five of 27.
On `x9-06099`, duration-aware UCB and round robin found a checked model
in 12,094 conflicts, while ordinary UCB exhausted 32,768. On `170223547`
ordinary UCB found a checked model in 30,174 conflicts and the other policies
exhausted their budgets. Each policy also produced independently checked DRAT
proofs for both generated pigeonhole controls. The policy remains available
as a benchmark. These results gave no aggregate gain to justify enabling it
in normal search. The conflict caps make these bounded comparisons.
[First cohort](../../../build/wassat-duration-20261118/verified/comparisons.json) ·
[Second cohort and proof controls](../../../build/wassat-duration-20261118/verified/extra.json)

Run the comparison from the repository root.

```sh
bin/tungsten compile bits/tungsten-wassat/benchmarks/restart_policy.w --out /tmp/wassat-restart-policy --release --lto --fast
python3 bits/tungsten-wassat/benchmarks/restart_policy.py --kernel /tmp/wassat-restart-policy instance.cnf
```

**Circuit and domain structure.** Tactix separates strategy from proof rules.
Its circuit strategies motivate proposing gate equivalences and checking each
one on the input. The IEEE paper’s abstract describes cone-local queries and
retaining proven outputs across resets; full-text access was unavailable.
Wassat’s circuit-cone work records independent original-clause proofs and
preserves completed equalities across slices. Bel’s Pyramid illustrates why
constructive restrictions can accelerate model search while requiring a
separate argument to justify UNSAT. Wassat’s signed-domain proposer follows
that distinction by checking witnesses and exporting a shortage proof only
when the original clauses establish it.
[Tactix paper](https://arxiv.org/abs/2610.24369) ·
[IEEE abstract](https://ieeexplore.ieee.org/abstract/document/11751530) ·
[Wassat circuit measurements](circuit-cones-2026-11-17.md) ·
[Bel’s Pyramid](https://github.com/acmihal/bel_pyramid)

The local LymphoSAT comparison covers all 400 SC2026 instances. Its Wassat
series is the historical v93 run at 60 seconds. The official series used
5,000 seconds on competition machines. The measurements above are separate
release runs. [Interactive comparison](sc2026-lymphosat-wassat.html) ·
[LymphoSAT results](https://c.mov/lymphosat/) ·
[Competition proceedings](https://repositum.tuwien.at/handle/20.500.12708/232006) ·
[SAtRes competition report](https://satres.eu/news/2026-07-28-floc/)
