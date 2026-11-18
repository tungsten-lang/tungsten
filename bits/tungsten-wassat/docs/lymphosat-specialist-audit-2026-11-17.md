# LymphoSAT specialist audit

Goal: evaluate every specialist individually against current Wassat, identify
what we can learn or improve, and identify improvements to LymphoSAT itself.

The authoritative inventory is the official Green competition source archive,
SHA-256 `7bc2ad3278197261cee221fd8c2dd583069821213f31d63e6873495000713c70`.
It contains 126 specialist entries in both the unverified and verified bundles.
Both select identical specialist and matcher archives; dispatcher verification
policy is assessed separately. Source availability does not establish a
permissive license for generated specialists; this review copies no code.

A completed review must inspect the matcher and actual algorithm/validation
paths, identify current Wassat call sites or an evidenced gap, distinguish
certificate support from an unchecked verdict, and give concrete improvement
ideas for each implementation. Metadata and family names alone do not count.
Performance claims require comparable measurements; static opportunities are
labelled as hypotheses. Current working files, not old audit binaries, define
what Wassat has.

**Verification caveat (review75):** the original verified dispatch function accepts an unchecked-assertion proof because VeriPB exits0 while reporting `UNDER ASSERTIONS UNSATISFIABLE`. A direct original-function replay on a satisfiable PHNF fixture returned UNSAT; matcher selection was bypassed. Accepted-proof counts here require unconditional `VERIFIED UNSATISFIABLE` and exclude those assertions.

Machine-readable source inventory: `build/lymphosat-specialist-audit-20261117/inventory.json`.
Individual review records live beside that inventory. **All 126 specialists reviewed.** The table tracks coverage and detailed notes. Current
checkpoint: `build/lymphosat-specialist-audit-20261117/checkpoint-126.json`.

## Findings across families

| Opportunity | Evidence | What Wassat can reuse |
|---|---|---|
| Certify existing counting shortcuts | Coloring, Hall, relay and configuration workers share the same capacity inequality. On a nine-vertex clique the independent proof used 2,785 bytes and the original used 151,276. | Keep the actual pair and choice clause IDs as the decoder runs. Emit one capacity proof per resource. [Derivation and measurements](polynomial-clique-capacity-certificate-2026-11-17.md) |
| Solve the arithmetic before completing the Boolean model | The SC2025 Summle target 8638 took 0.132 s for a checked direct-worker model. Across five instrumented runs, Boolean completion took 56.2 ms median, parsing 38.6 ms and arithmetic 10.9 ms. | Recover operand words and operation guards, use subset DP, and pass its witness to existing Wassat propagation. [Phase measurements](../../../build/lymphosat-specialist-audit-20261117/115-phase-profile.json) |
| Export parity dependencies | The Tseitin worker certified an actual SC2025 graph within the six-second replay window. Two synthetic contradictions received rejected certificates. The XOR-chain worker independently passed the flipped-endpoint control. | Keep equation provenance in existing parity recovery. Check the resulting proof on the original input before counting a win. See reviews 56, 68, 122 and 125. |
| Extend domain recovery | Random CSP, RB, station repacking and subgraph isomorphism use related finite-domain search with different signed, compact and merged encodings. | Reuse Wassat’s domain and repair engines. Extend the decoder, verify each forbidden value pair and replay lifted models. See reviews 36, 89, 92, 109 and 112. |
| Prove local induction steps once | Stone and grid theorem-proving both propagate a predicate through an acyclic dependency graph. The XOR-ordering families can likewise lift locally proved Boolean relations to a smaller formula. | Retain source clauses while building the dependency graph. Derive each local implication and restrict the final proof to the target’s ancestors. See reviews 69, 70, 111, 119 and 126. |

Direct replays also found false UNSAT on satisfiable relational-dependency, rooks and SatCoin controls. The rooks proof was accepted by the original verified dispatch function after matcher bypass because its checker exited successfully under assertions. These tests establish behavior on the recorded inputs. They do not establish that a competition run selected the same path. [Counterexamples and checker results](../../../build/lymphosat-specialist-audit-20261117/93-96-probes-results.json) · [SatCoin replay](../../../build/lymphosat-specialist-audit-20261117/98-direct-results.json)

## Individual reviews

| # | Family | Selected specialist | Review |
|---:|---|---|---|
| 1 | `01-integer-programming` | `peqnp-relaxed-rowpair-boundary` | Reviewed — partial Wassat coverage |
| 2 | `algebra` | `bilinear-unit-repair` | Reviewed — partial Wassat coverage |
| 3 | `algorithm-equivalence-checking` | `binary-xor-proof-cdcl-61742` | Reviewed — recognizer repaired; certificate gap remains |
| 4 | `alloy-vpn-models` | `agent-alloy-vpn-models-5128` | Reviewed — generic overlap / witness-reuse gap |
| 5 | `antibandwidth` | `agent-antibandwidth-duplex-sat` | Reviewed — substantial but bounded overlap: linear permutation search |
| 6 | `auto-correlation` | `ordered-labs-local-search-bcp` | Reviewed — dedicated LABS/peak-autocorrelation specialist missing |
| 7 | `automata-synchronization` | `sync-word-structure-solver` | Reviewed — partial: Wassat constructs checked Cerny-pattern words, but lacks random-DFA search and specialized UNSAT proofs |
| 8 | `battleship` | `modular-battleship-cover` | Reviewed — substantial generic covering overlap and a fast count obstruction |
| 9 | `binary-pigeon-hole` | `binary-pigeonhole-certified-counter` | Reviewed — binary-domain decoder missing; explicit-choice counting overlap only |
| 10 | `binary-tree-parity` | `structural-binary-tree-parity` | Reviewed — substantial equivalent; Wassat checks stronger XOR recovery conditions |
| 11 | `brent-equations` | `brent-structural-sls-02` | Reviewed — generic SLS overlap; neither active path is a Brent tensor specialist |
| 12 | `circuit-equialence-checking` | `rup-tree-cec-specialist` | Reviewed — generic overlap plus Wassat circuit specialists; LymphoSAT mainly bounded tree DPLL |
| 13 | `circuit-minimization` | `agent-circuit-minimization-cover-sat` | Reviewed — substantial equivalent: Wassat decodes signed counter covers more generally |
| 14 | `clique-coloring` | `clique-color-pigeonhole-veripb` | Reviewed — same clique-color obstruction; Wassat broader fast recognition but lacks exported PB proof |
| 15 | `clique-formulas` | `partitioned-clique-pigeonhole-veripb` | Reviewed — substantial equivalent: generic Wassat AMO clique-cover counting |
| 16 | `clique-width` | `agent-clique-width-cdcl-hinted` | Reviewed — dedicated clique-width constructor missing; treewidth is a different graph invariant |
| 17 | `clustered-random` | `clustered-table-closure-lbd-rup` | Reviewed — generic overlap; dedicated repeated-tuple resolution closure missing |
| 18 | `coloring-clique` | `structural-clique-coloring-sat` | Reviewed — same obstruction as review14; LymphoSAT has SAT construction and a different CP proof |
| 19 | `coloring-mycielski-graph` | `mycielski-pr-shadow-edge-solver` | Reviewed — same Mycielski mathematics; complementary encodings and certificate gap |
| 20 | `core-based-generator` | `ncc-longlink-sat-repair` | Reviewed — substantial bounded equivalent: Wassat already projects split cores and completes binary residuals |
| 21 | `cover` | `steiner-cap-direct-search` | Reviewed — counter/cover overlap; no dedicated affine cap constructor found |
| 22 | `cryptography-ascon` | `ascon-two-byte-mask-rup` | Reviewed — substantial exhaustive-search equivalent; Wassat checks cases, LymphoSAT exports unchecked-by-default PB cases |
| 23 | `cryptography-cbmc` | `agent-cryptography-cbmc-miter-trimmed-v2` | Reviewed — generic CDCL overlap; Wassat already has byte/table structure that LymphoSAT leaves experimental |
| 24 | `cryptography-simon` | `simon32-permuted-key-search` | Reviewed — dedicated recovered constant-key Feistel word search missing |
| 25 | `design-debugging` | `design-debugging-prefix-up-hybrid-cdcl` | Reviewed — generic root propagation/CDCL equivalent; prefix streaming and residual reuse differ |
| 26 | `diagnosis` | `diag-v19-time595` | Reviewed — substantial generic preprocessing/CDCL overlap; diagnosis semantics mostly unused |
| 27 | `discrete-logarithm` | `dislog-structure-bsgs-uprop` | Reviewed — dedicated modular-exponentiation decoder and bounded discrete-log kernel missing |
| 28 | `edge-matching` | `agent-edge-matching-holten-reconstructor` | Reviewed — substantial compact grid-relation equivalent; separate Holten constructor missing |
| 29 | `edit-distance` | `cluster-edit-mto-reconstructor` | Reviewed — dedicated cluster-partition search missing; cardinality decoding infrastructure overlaps |
| 30 | `equivalence-chain-principle` | `fmlachain-equiv-count-invariant` | Reviewed — leaf-count invariant and PB export missing; generic choice/count reasoning is not equivalent |
| 31 | `erdos-discrepancy` | `edp3-prefix-constructor` | Reviewed — no equivalent verified discrepancy sequence or direct progression-state constructor found |
| 32 | `fdmus` | `fdmus-relation-rup-v23` | Reviewed — dedicated three-copy relation abstraction missing; generic AIG/circuit reasoning overlaps |
| 33 | `fermat` | `fermat-structure-pollard-rho` | Reviewed — substantial existing Fermat/Pollard-rho worker; different encoding recovery and budgets |
| 34 | `fixed-shape-random` | `agent-fixed-shape-random-multiseed` | Reviewed — generic projection/search components exist; no equivalent private-gadget MUS projector found |
| 35 | `floodit-puzzle` | `floodit-direct-v13` | Reviewed — no dedicated Flood-It component search found; current planner workers solve other state spaces |
| 36 | `fpga-routing` | `agent-fpga-routing-contracted-bv` | Reviewed — one-hot coloring/counting overlaps strongly; general bit-domain/permutation contraction missing |
| 37 | `genurq` | `xor-genurq-direct` | Reviewed — substantial XOR overlap; nonlinear relation conditioning differs from free-coordinate enumeration |
| 38 | `gf3-sat` | `gf3-linear-detector` | Reviewed — dedicated GF(3) decoder/elimination missing; ternary Latin CSP is not this four-ary linear system |
| 39 | `glassy-gen` | `glassy-positional-bp-sls` | Reviewed — generic weighted SLS overlaps; positional planted-model extraction and BP seeds missing |
| 40 | `graceful-production` | `agent-graceful-production-watched-positive` | Reviewed — substantial equivalent positive-first greedy dive already exists; production-variable decoder absent on both active paths |
| 41 | `grandtour-puzzle` | `agent-grandtour-hall-pb` | Reviewed — related capacity/matching refuters exist; general Hall-subset extraction and PB export missing |
| 42 | `greentao` | `agent-greentao-transversal-probsat` | Reviewed — dedicated arithmetic-hypergraph solver already exists; sparse transversal seeds are complementary |
| 43 | `hamiltonian-cycle` | `modular-hcp-cyclecover` | Reviewed — other Hamiltonian workers exist; this modular arc/counter decoder and residue-aware 2-factor search are missing |
| 44 | `hanoi` | `agent-hanoi-direct-action-plan` | Reviewed — dedicated factored-Hanoi action reconstruction missing; generic propagation/CDCL completion overlaps |
| 45 | `heule-nol` | `nol-lshape-witness-repair` | Reviewed — three-color hypergraph recoloring missing; existing two-color NAE and binary-domain workers are different |
| 46 | `hgen` | `hgen-solver-v22b` | Reviewed — strong generic SLS/CDCL/SCC overlap; probSAT schedule is an algorithm variant rather than a missing semantic family decoder |
| 47 | `hidoku` | `hidoku-arc-pb` | Reviewed — substantial existing path-cover refutation; PB export, transposed layouts and constructive SAT add coverage |
| 48 | `hypertree-decomposition` | `kakuro-dual-hypertree-separator` | Reviewed — dedicated hypertree/dual-separator constructor missing; treewidth refutation concerns a different invariant |
| 49 | `independent-set` | `structured-independent-set-bdd` | Reviewed — same independent-set/counting mathematics; Wassat has bounded exact refutation, LymphoSAT adds constructive word-graph SAT |
| 50 | `independent-set-reconfiguration` | `isreconf-queen-path-8291` | Reviewed — substantial existing token-jumping decoder/search; compact near-full queen states add a useful specialization |
| 51 | `influence-maximization` | `agent-influence-greedy-swap-anneal` | Reviewed — dedicated deterministic threshold-diffusion seed search missing; cardinality/circuit infrastructure overlaps |
| 52 | `interval-matching` | `hall-certified-interval-matching` | Reviewed — aggregate AMO counting already exists; arbitrary Hall-deficient subsets and checked PB export extend it |
| 53 | `karatsuba-multiplication` | `karatsuba-seed-extender` | Reviewed — generic seeded completion overlaps; neither calibrated factors nor the current canonical decoder give general Espresso-Karatsuba recovery |
| 54 | `knights-problem` | `knight-hcp-structural-tour-solver` | Reviewed — substantial distance-pruned tour equivalent already exists; sparse/dense/CP encoding recovery adds coverage |
| 55 | `ktf` | `agent-ktf-cost-level-search` | Reviewed — quota/conflict-cover components overlap; weighted multi-skill option-level team decoder/search missing |
| 56 | `long-learned-clauses` | `exact-cardinality-shadow-sls` | Reviewed — same signed-cardinality parity shadow; Gaussian dependency subsets and PB proof export add capability |
| 57 | `maximum-constraint-partition` | `agent-balanced-partition-lowbit-rup` | Reviewed — substantial equal-sum circuit/weight-recovery equivalent; exact cardinality DP and low-bit proof export add capability |
| 58 | `md5-equivalence-checking` | `agent-md5-yosys-cdcl-12272` | Reviewed — active algorithm is generic compact CDCL; no active MD5 semantic specialist, and printed-model correctness bug reproduced |
| 59 | `mechanical-master-key` | `lockchart-greedy-repair-modeler` | Reviewed — substantial existing key-chart domain search and assumption repair; larger charts and richer initialization/moves extend coverage |
| 60 | `minimal-superpermutation` | `superpermutation-word-extender` | Reviewed — dedicated word/occurrence constructor and coverage-choice proof missing; generic domain/model completion only overlaps |
| 61 | `minimum-disagreement-parity` | `xor-mdp-syndrome-mitm` | Reviewed — substantial and stronger exact Wassat MDP coverage; syndrome MITM offers an alternative SAT algorithm and broader candidate grammar |
| 62 | `modcircuits` | `modcircuits-direct-mod3-rup` | Reviewed — generic CDCL/SLS overlap plus two fixed circuit netlists; dedicated input-derived bounded circuit synthesis missing |
| 63 | `mosoi-289` | `block-csp-sls-rect-289` | Reviewed — generic exact block-CSP already covers the regular shape within caps; mixed small-arity domain SLS and rectangle structure add capability |
| 64 | `multiplier-circuits` | `structural-multiplier-factor-dag` | Reviewed — substantial existing multiplier recovery/factor/evaluate lane; broader gate grouping and wide bounded factoring add coverage |
| 65 | `multiplier-verification` | `ite-multiplier-assumption-proof-003` | Reviewed — existing ITE congruence and retained-query machinery; bounded global ROBDD decoding is missing |
| 66 | `mutilated-chessboard` | `hall-mutilated-chessboard-counter` | Reviewed — plain per-component balance already exists; mixed Sinz/resource-only Hall proof broadens coverage |
| 67 | `oddball-weighing` | `oddball-ternary-direct` | Reviewed — selectable ternary-signature constructor already exists; forced-row decoding and its parity check add coverage |
| 68 | `or_randxor` | `or-randxor-gauss-pbp` | Reviewed — GF2 elimination already exists; distributed OR-pair quotient decoder and PB parity lift are missing |
| 69 | `ordering-principle` | `ordering-principle-rup-eliminator` | Reviewed — dedicated ordering-principle decoder/elimination proof missing; generic CDCL handles tiny controls |
| 70 | `ordering-principle-xor` | `xorified-sparse-ordering-eliminator` | Reviewed — XOR lifting and sparse-order elimination are missing; generic GF2 is not this nonlinear quotient |
| 71 | `p-center` | `root-rup-pcenter` | Reviewed — existing watched root propagation and failed-literal proof preprocessing already cover the central method |
| 72 | `pebbling` | `PebbleCDCL` | Reviewed — generic CDCL/proof deletion already exists; active reference does not decode pebbling structure |
| 73 | `petrinet-concurrency` | `graph-coloring-clique-proof-solver` | Reviewed — existing clique/capacity mathematics and domain search overlap; list-domain coloring and PB export add coverage |
| 74 | `philips` | `philips-input-cube-rup` | Reviewed — bounded signed AND/XOR exhaustive refutation already exists; reference adds a different certified input-cube path |
| 75 | `phnf` | `phnf-csp-transversal` | Reviewed — existing block-CSP/domain search overlaps; reference exact-search indexing and unchecked assertions invalidate its UNSAT path |
| 76 | `pigeon-hole` | `agent-pigeon-hole-8315` | Reviewed — plain and signed relativized PHP counting already exist; chain/Ternary-capacity decoding and exported PB add coverage |
| 77 | `planning` | `agent-planning-cdcl-v8` | Reviewed — generic CDCL/binary propagation/probing already present; no planning semantics in active reference |
| 78 | `product-configuration` | `shallow-config-rup-cdcl` | Reviewed — generic shallow CDCL/preprocessing already covered; parser can publish a false SAT result on valid comments |
| 79 | `profitable-robust-production` | `agent-prp-min-positive-bcp-52931` | Reviewed — dedicated Picat arg-min template proposal missing; generic watched/cover infrastructure already exists |
| 80 | `purdom-instances` | `purdom-bproof-rup-05` | Reviewed — existing multiplier factor/model and weight theorem overlap; shuffled generator recovery and smaller-input proof add coverage |
| 81 | `pythagorean-triples` | `pythagorean-nae-color-repair` | Reviewed — generic weighted SLS and bounded NAE engines already exist; cube-aware merged NAE repair extends admission |
| 82 | `railway-safety` | `railway-circuit-repair-sls-19420` | Reviewed — circuit decoding/simulation exists; general incremental primary-space SLS and target repair add capability |
| 83 | `ramsey` | `ramsey-incidence-cdcl-checked` | Reviewed — new binary four-color incidence/constructive opportunity; classic two-color bounds already exist; unchecked degree12 premise is unsound |
| 84 | `ramsey-numbers` | `ramsey-r44-cp-symmetry` | Reviewed — same computed R(4,4)<=18/parity mathematics already exists; explicit RED/CP certificate is missing in Wassat |
| 85 | `ramseycube` | `cube-c4-template-solver` | Reviewed — checked forbidden-subgraph core/template capability missing; clique Ramsey bounds are a different family |
| 86 | `random` | `random-ksat-v14` | Reviewed — generic CDCL/SLS already substantial; explicit per-k exponential-break ProbSAT is a distinct candidate policy |
| 87 | `random-circuits` | `lookup-circuit-csp-avx-v3` | Reviewed — small-table pruning and circuit engines exist; larger multioutput table GAC/search adds distinct coverage |
| 88 | `random-clustered` | `cluster-weighted-search-plus-multiplier` | Reviewed — generic weighted SLS and factor-then-lift already exist; this adds a distinct contiguous-unit multiplier layout |
| 89 | `random-csp` | `frb-pattern-csp-repair` | Reviewed — domain search already exists; signed/compact pattern decoding and merged relation recovery extend coverage |
| 90 | `random-mus` | `agent-random-mus-7006` | Reviewed — generic hybrid overlap; no active MUS-specific mathematical algorithm |
| 91 | `random-planted-solution` | `planted-3sat-hybrid-v14` | Reviewed — generic hybrid and frozen-fringe repair exist; polynomial weighted ProbSAT adds a distinct move policy |
| 92 | `rbsat` | `agent-rbsat-csp-breakout` | Reviewed — weighted domain/tabu search already present; signed choices and domains33..63extend current admission |
| 93 | `register-allocation` | `clique-hall-register-allocation` | Reviewed — Coloring-clique detector exists. Polynomial certificate demonstrated. |
| 94 | `relational-dependencies` | `closure-cardinality-mvd-ads` | Reviewed — New opportunity for a cardinality-constrained Horn specialist. |
| 95 | `relativized-pigeon-hole` | `rphp-structural-cp-proof` | Reviewed — Signed relay counting exists. Certificate and constructive SAT repair extend it. |
| 96 | `rooks` | `rook-cardinality-clash` | Reviewed — Wassat already checks the overlapping-support condition missed here. |
| 97 | `sat-x` | `three-cube-witness-propagator` | Reviewed — Arithmetic witness lifting exists. Wide decimal primaries are an extension. |
| 98 | `satcoin` | `satcoin-nonce-rup-dpll` | Reviewed — SatCoin evaluation exists. Interval-proof generation needs an implication check. |
| 99 | `set-covering` | `weighted-scpc-cdcl` | Reviewed — Exact independent-cover solver exists. Weighted local search complements it. |
| 100 | `sgen` | `signed-sgen-exactcover-cp` | Reviewed — Cardinality and exact-cover primitives exist. Signed three-partition decoding is distinct. |
| 101 | `sgen-balanced` | `balanced-3cnf-rup-cdcl` | Reviewed — Generic CDCL overlap. The runtime filter recognizes a random design. |
| 102 | `sliding-puzzle` | `compact-24-puzzle-ida-modeler` | Reviewed — Compact sliding-puzzle solver exists. Slack in the move bound is the opportunity. |
| 103 | `social-golfer` | `agent-social-golfer-table-context` | Reviewed — Design-theoretic overlap. Table and pair-context SAT construction is separate. |
| 104 | `software-bmc` | `cbmc-flat-portfolio-fullmodel-rup` | Reviewed — Flat watched CDCL overlaps. Circuit justification and output compaction are useful. |
| 105 | `software-verification` | `rup-cdcl-software-verification-structural` | Reviewed — Certified CDCL and control probing largely overlap. |
| 106 | `sorting-networks` | `snw-cdcl-rup-phase` | Reviewed — Input-derived comparator search exists. Proof-mode phase hints are complementary. |
| 107 | `ssp-0` | `peqnp-ssp-mitm-boundary` | Reviewed — Weighted selection and adder recovery overlap. Boundary meet-in-the-middle is new. |
| 108 | `st-connectivity-principle` | `crossing-sequence-stconn-rup` | Reviewed — Same planar obstruction. Bounded-width resolution supplies a certificate. |
| 109 | `station-repacking` | `fcc-repacking-solver-v16` | Reviewed — Domain search exists. Component-local proof search and repair broaden it. |
| 110 | `stedman-triples` | `agent-stedman-transition-templates` | Reviewed — Compact Stedman search exists. Direct and pattern encodings extend coverage. |
| 111 | `stone` | `stone-direct-rup` | Reviewed — DAG-induction proof compiler is a distinct opportunity. |
| 112 | `subgraph-isomorphism` | `signed-sgi-csp-ordered-embedding` | Reviewed — McSplit exists. Signed and binary-coded domains expand the decoder. |
| 113 | `subsumptiontest` | `majority-flip-rup-cdcl` | Reviewed — Search-policy overlap. No direct subsumption calculus in the active worker. |
| 114 | `sum-of-3-cubes` | `sum-cubes-bitblast-modeler` | Reviewed — Arithmetic target recovery and model lifting already exist. |
| 115 | `summle` | `summle-structural-dp` | Reviewed — New input-derived arithmetic-puzzle specialist is warranted by an SC2025 replay. |
| 116 | `tensors` | `tensor-slice-rank-beam` | Reviewed — Tensor witness lifting exists. Slice-space search adds a general method. |
| 117 | `test-configuration` | `satch2ways-edge-cover-20` | Reviewed — Capacity counting overlaps. Pair-interaction decoding and SAT construction add coverage. |
| 118 | `testpattern-generation` | `rup-probed-testpattern-cdcl` | Reviewed — Root probing and certified CDCL overlap. Proof-carrying binary implications are useful. |
| 119 | `theorem-proving` | `grid-rup-conflict-prover` | Reviewed — A reusable descent-proof recognizer is missing. |
| 120 | `tree-decomposition` | `sv-treewidth-order-heuristic` | Reviewed — Complementary treewidth results. Wassat has lower bounds and this worker finds orders. |
| 121 | `trigonometric-functions` | `agent-trigonometric-functions-26040` | Reviewed — Generic circuit-tuned CDCL. No trigonometric identity decoder. |
| 122 | `tseitin-formulas` | `tseitin-xor-specialist` | Reviewed — Substantial XOR/Tseitin overlap. Exported algebraic proof is the main addition. |
| 123 | `uniform-random` | `uniform-random-probsat-sls` | Reviewed — Generic SLS overlap. Width-specific stochastic policies can diversify it. |
| 124 | `waerden` | `ap-hitting-threaded-cdcl-rup` | Reviewed — Arithmetic hypergraph coloring exists. Hitting-set proof search is complementary. |
| 125 | `xor-chain` | `xor-chain-linear-pb` | Reviewed — XOR recovery exists. Compact arithmetic certificates transfer well. |
| 126 | `xor_op` | `xor-op-cdcl-veripb` | Reviewed — Parity primitives exist. Quotienting an ordering formula and lifting its proof are distinct. |

## Completed reviews

### 1. 0–1 integer programming (PEQNP)

LymphoSAT reconstructs a Boolean selector vector and arithmetic accumulator
boundaries. It joins half-assignments using either two recovered row sums or
the actual boundary bits, then validates complete candidates against CNF.
Its relaxed coefficients are filters, not proofs. It returns SAT or UNKNOWN.

Wassat has **partial coverage**, not an equivalent general specialist:
`solver.w::wassat_peqnp_seed` stores one 40-bit assignment and propagates it;
`WASSAT_BACKDOOR_TABLES=0` disables that path. The ordinary solver and final
original-CNF model check remain available. The main opportunity is an
input-derived decoder and adaptive boundary meet-in-the-middle search using
Wassat's packed propagation infrastructure.

A direct-specialist probe establishes a parser defect: adding a legal DIMACS
comment between clauses makes LymphoSAT's parser stop early; it reports SAT
for the parsed prefix of a contradictory formula. The returned model fails an
original clause. The same clean formula returns UNKNOWN, and installed Wassat
returns UNSAT on both. This tiny probe bypasses the statistical matcher, so it
is **not** a reproduced top-level portfolio false answer. The verified wrapper
would check the original file, reject the model and currently stop with UNKNOWN
instead of trying the fallback. Strict comment/count/terminator handling and
continuing after checker rejection are concrete improvements.

Other opportunities: choose arithmetic splits by boundary size, rank row pairs
by candidate discrimination, replace fixed candidate truncation with an adaptive
work allowance, and share immutable propagation indices between workers. Their
speed benefit has not been measured.

Evidence: `build/lymphosat-specialist-audit-20261117/reviews/001-01-integer-programming.json`
and `01-parser-probes/{results,wassat-results}.json` in that audit directory.
The record gives exact source paths and inspected ranges.

### 2. Algebra / group-ring units

LymphoSAT eliminates the parity layer of a dense AND circuit to recover
GF(2) equations in products `x_i*y_j`. Fixing either support vector makes the
other linear; it combines sparse enumeration, fixed Gardam support templates,
alternating linear solves and quadratic repair. Its simultaneous-flip
linearization omits a quadratic term, so checking the true residual before
accepting a repair is essential and implemented. Every SAT model is checked
against the parsed original clauses; UNSAT is unsupported.

Wassat has **partial coverage**: its strong canonical N=93 lane derives the
published witness from group operations rather than storing support indices,
but exact dimensions and ordered-schema checks exclude larger Hantzsche–Wendt
and Soelberg cases. Its disjoint-pair affine solver is not a replacement for
general overlapping bilinear search. Keep the existing cheap construction first
and consider a general bilinear decoder/repair fallback for broader coverage.

LymphoSAT could benefit from the group-derived construction and normalization
orbit, structural rather than numbering-dependent recovery, and sparse/lazy
elimination storage. Its `XorBasis` currently preallocates a quadratic-size
bit matrix, including unused pivot rows. Residual incidence and low-rank updates
are further performance hypotheses. A historical N=93 comparison is documented
in `green-lymphosat-comparison-2026-07-29.md`; it does not establish present
whole-family superiority for either solver.

Evidence: `build/lymphosat-specialist-audit-20261117/reviews/002-algebra.json`.

### 3. Algorithm equivalence / sorting implementations

LymphoSAT uses a conventional first-UIP CDCL engine, focused by recovered
output-XOR/miter cones. It emits VeriPB RUP additions/deletions; disabled
failed-literal and mux-lemma experiments are not production capabilities.
Wassat already has a more semantic weak-order enumeration lane, but that lane
is fast-only and its incomplete recognizer has a **reproduced correctness
defect**: changing12 XOR-output signs in a real3325-variable/12330-clause
formula preserves clause counts; installed fast mode says UNSAT while the
ordinary proof route finds a model independently checked against every clause.
A direct release probe of the current source confirms the word-sort lane itself
returns true on both the original and this satisfiable mutation.

The intended weak-order argument is useful, but missing XOR/OR and comparison
macro checks must be repaired before counting this as sound equivalent coverage.
An exported high-level certificate is also missing. LymphoSAT could learn the
word/rank abstraction from Wassat, while Wassat can use miter-guided proof search
where abstraction fails. Indexing definitions avoids LymphoSAT's repeated full
clause scans per output bit. Neither source justifies a universal speed claim.

Evidence: `build/lymphosat-specialist-audit-20261117/reviews/003-algorithm-equivalence-checking.json`
and its `03-suffix-probe/` counterexample, original-model replay and direct probe.

### 4. Alloy VPN models

LymphoSAT is mainly CDCL plus complete stored model witnesses. Hash-indexed
bitsets and a special VPN8 variable-removal adjustment are validated against
all original clauses, and rejected cache hits restore prior assignments.
The interesting signed literal/clause color-refinement transfer exists in an
offline tool; the default runtime carries its resulting known witnesses rather
than discovering mappings for arbitrary new variants.

Wassat overlaps in ordinary CDCL, binary propagation, phase handling, model
checking and proof output; it has no evidenced equivalent Alloy decoder or
signed-WL witness transfer. Its exact-one symmetry lane is a different method.
Useful work is input-derived relational/cardinality recovery or bounded verified
phase transfer, rather than adding another per-instance witness table.

LymphoSAT improvements include runtime ambiguity-aware transfer, general
variable correspondence instead of the fixed4252 adjustment, and proof-memory
reclamation. Its matcher's `clauses_seen==1000000` is a sampled-prefix count, not
the formula's true clause count; clause-order sensitivity deserves separate
transformation tests. No fresh speed or cache-hit-rate claim is made here.

Evidence: `build/lymphosat-specialist-audit-20261117/reviews/004-alloy-vpn-models.json`.

### 5. antibandwidth

Construct Cuthill–McKee-style BFS orders, alternating low/high label placements and reversals. For n<=140 try bounded recent-window DFS; otherwise/afterwards run squared-deficit swap annealing and min-conflicts repair. Complete a one-per-row labeling by auxiliary propagation and check every parsed original clause.

**Wassat coverage:** permutation_walk.w implements the same linear-distance permutation abstraction. It infers a graph and width by propagation snapshots from anchor assignments, uses weighted-deficit tabu swaps over fixed incidence buffers, completes auxiliaries and checks the original model. Admission caps n at256, variables200000 and clauses500000 and keeps a10s optional-worker phase. cyclic_walk is circular distance, so it is related infrastructure, not a substitute for this linear family.

**Learn for Wassat:** Add bounded graph-aware BFS/alternating-label initial permutations alongside random restarts; compare them under the same work allowance rather than assuming better coverage. Try recent-window admissibility pruning for small n: a new position cannot contain a neighbor of any vertex in the previous w-1 positions. LymphoSAT truncates candidates, so its DFS is a heuristic, not an UNSAT certificate. Compare squared-deficit and dynamically weighted linear penalties; retain the original-CNF guard when graph recovery is incomplete.

**Improve LymphoSAT:** Reuse fixed incidence and scratch buffers for swap deltas: current loops allocate/sort/deduplicate affected-edge vectors repeatedly. Wassat already does this with flat reusable arrays. Use propagation-derived constraints to support encodings not exposing the expected boundary binaries; validate widths and symmetric graph relations before search. Replace fixed70s DFS and size-based search slices with a shared cooperative work/time budget; avoid presenting the capped DFS as exhaustive. Use dynamic edge weights/tabu aspiration to escape repeated local traps, and retain best states across annealing/min-conflict stages. Benefit is a hypothesis pending comparable runs.

**Certificates and evidence:** SAT-only; all misses return UNKNOWN. No UNSAT proof or complete antibandwidth decision procedure. Source/call-site comparison. No new same-host benchmark or universal performance ranking. Detailed source references: `build/lymphosat-specialist-audit-20261117/reviews/005-antibandwidth.json`.

### 6. auto-correlation

Search directly over spins s_i in{-1,+1}; maintain every aperiodic correlation C_k. Flip updates touch at most two products per lag, O(n) per proposal. Penalize squared excess above an inferred peak bound, focus on bad lags, anneal/restart, then propagate spin assignments through CNF and validate complete models.

**Wassat coverage:** No dedicated correlation arrays, lag-flip update or LABS decoder found in current library. Generic projected circuit search, CNF local search and counter/cardinality infrastructure provide reusable components, not equivalent O(n) spin-objective search.

**Learn for Wassat:** Build a clean-room input-derived lag/product decoder and exact peak/cardinality-bound recovery, then use O(n) correlation updates with final original-model replay. Recover the primary-variable mapping from XOR/product incidence rather than fixed1..n order, reusing circuit/cardinality decoding infrastructure. Use complement/reversal/alternating-sign symmetries as candidate orbits, then satisfy any original symmetry-breaking constraints through replay; do not assume all transformations preserve an arbitrary CNF.

**Improve LymphoSAT:** Fix empty-clause parsing. A reproduced tiny direct-entry probe appends an empty clause to an accepted ordered-shaped CNF; the solver still returns SAT because lines beginning0 are skipped. The verified outer checker would reject this. Recover the exact peak bound rather than infer it from all unit clauses; redundant units can alter the heuristic and trigger early UNKNOWN. Replace ordered-prefix assumptions with graph-derived product mapping. On candidate extension failure, explore more candidates at that goal instead of advancing immediately to a looser goal. Reuse occurrence indices across candidates; the actual code already has occurrence-queue propagation, contrary to the notebook limitation saying repeated full-clause propagation. Update that documentation.

**Certificates and evidence:** SAT-only. The goal is guessed from unit count and searched over a range; failure/early low-goal rejection is UNKNOWN, never a proof of UNSAT. Parsed-formula model checks exist but the parser discards empty clauses. No real LABS timing comparison, and no claim that a low inferred goal proves UNSAT. Detailed source references: `build/lymphosat-specialist-audit-20261117/reviews/006-auto-correlation.json`.

### 7. automata-synchronization

Try a closed-form Cerny synchronizing word; otherwise beam search over subset images using pair-automaton distances, then local binary-word search. For UNSAT, recursively derive bad-pair/bad-subset clauses and log hinted VeriPB RUP using original selector/transition/final-clique clause IDs.

**Wassat coverage:** automata_sync.w recovers both transitions with a stricter complete clause grammar and exact header equations. It tries the two fixed Cerny-pattern words and padding, simulates images, and the CLI checks the whole model. It does not implement general power-automaton beam search or direct bad-subset UNSAT certificates.

**Learn for Wassat:** Keep the cheap constructive candidate first, then add pair-distance-guided subset search for random DFAs that fixed words miss. Add bad-subset refutation with exact original clause-ID provenance. Hints matter for checking cost; do not relabel an unhinted proof as a hinted format. Separate a verified necessary transition subset for refutation from a complete decoder used for exact semantic claims; SAT still requires full-model validation.

**Improve LymphoSAT:** Use antichains of minimal bad subsets and reuse stronger subset clauses for supersets; retain masks/provenance so hints remain valid. Delete unreachable old-layer proof clauses or develop a compact symbolic Cerny invariant instead of expanding huge subset proofs; notebook reports severe proof-size growth, not reproduced here. Add cooperative node/memory/time limits to proof generation, not only search widths and Q/L caps; reuse pair-distance tables between successive beam widths. Validate all original clause maps and parser counts before emitting proof IDs; relaxed search recognition alone is insufficient to authorize UNSAT.

**Certificates and evidence:** Full original-CNF SAT-model checks. Specialized UNSAT proof emission exists: Cerny up to25states and random Q<=180/L<=80. Fresh controlled probes independently verify both Cerny and random-style subset proofs with native VeriPB3.0.2, plus the SAT model on a length4 Cerny instance. These tiny direct probes bypass the feature matcher and establish certificate replay, not competition-scale performance. Detailed source references: `build/lymphosat-specialist-audit-20261117/reviews/007-automata-synchronization.json`.

### 8. battleship

Greedy line coverage and min-conflicts repair over one chosen residue per column; optionally allow a missing forbidden pair. For square full-exclusion cases, emit a cutting-planes proof of cardinality equality and incompatible occupied adjacent columns. For n<=5 low-column cases, use a tree-like RUP line-hitting refutation. Disabled CDCL code is not counted as active.

**Wassat coverage:** covering.w exactly recognizes positive covering rows plus negative conflict pairs and performs bounded complete DFS, usable for these CNFs inside its2048-variable/200000-node limits. threshold_cover.w::wassat_cover_bound_unsat derives an overlap-aware global coverage bound, specifically documented for battleship13x13. CLI enables these specialized refutations only with proof_mode NONE. affine_design.w is a different encoded-design obstruction and is not counted as the same modular battleship solver.

**Learn for Wassat:** Add modular residue-level SAT proposals rather than search only Boolean covering variables; reconstruct and check all original clauses. Add a certificate path for the square overlap argument. Group cardinalities plus pair-specific overlap can handle composite orders where a global minimum-overlap bound becomes zero. Exploit forced occupied group pairs or a weighted overlap tree instead of only a global least overlap; prove the necessary group occupancy before subtracting its overlap.

**Improve LymphoSAT:** Resolve hash collisions by exact line comparison. The SAT detector currently equates64-bit line hashes; square proof mapping separately checks exact clauses, and SAT replay protects models, but the small RUP path should not rely on hashing as semantic equality. Use Wassat-style generic conflict-cover propagation for non-square residuals and irregular forbidden-pair sets rather than only modular repair. Investigate a checkable blocking-set lower-bound certificate for non-square cases; do not assert the prime affine-plane2n-1 bound blindly for composite moduli. Share one global search budget across all omitted-pair trials instead of granting the full slice per pair; keep missing-pair relaxations outside full-exclusion UNSAT rules.

**Certificates and evidence:** SAT candidates checked against every original clause. Explicit VeriPB cutting-planes square proofs and bounded small RUP proofs; missing-pair square cases conservatively return UNKNOWN. Fresh controlled probes independently verify square n3 and composite n4 cutting-planes proofs and an n3/m4 tree RUP proof; the n3/m5 SAT model checks every clause. These tiny direct probes bypass the feature matcher; no competition performance comparison is claimed. Detailed source references: `build/lymphosat-specialist-audit-20261117/reviews/008-battleship.json`.

## Sorting recognizer repair status

The review3 defect is repaired in source. XOR and OR groups now undergo full
semantic checks, and each comparator macro must imply an independently built
unsigned-greater-than relation in two bounded local assumption queries. Every
original macro clause participates; unsupported references or an unfinished
proof decline recognition. This repairs all previously unchecked macro regions,
rather than special-casing the12-sign counterexample.

Five focused examples pass compiled and interpreted; two native full-miter
examples cover four count-preserving SAT mutations with independent models.
ASAN covers the runtime and every generated LLVM function, including the real
canonical formula and five real semantic mutations. The fixed private full CLI
returns checked SAT models for all five mutations. All ten canonical controls
retain their previous recognition (nine refutations, one n=9 decline).
The installed binary remains unchanged, and an exported global proof remains
a separate gap. Evidence: `build/lymphosat-specialist-audit-20261117/03-suffix-probe/repair-result.json`.

### 9. binary-pigeon-hole

Enumerate all codes, recover common allowed domain, construct distinct-code SAT assignment when possible. Otherwise introduce bit-pattern indicator variables, derive pigeon ALOs by binary trie RUP, per-code AMOs and a cutting-planes cardinality contradiction.

**Underlying structure:** P distinct bit-vectors must occupy H shared allowed codes. P>H is impossible. The bit-domain grammar matters: ordinary one-hot pigeonhole recognition does not see these wide clauses.

**Wassat coverage:** coloring.w and capacity_clique.w reason over explicit choice literals and pairwise exclusions. They do not recover binary-encoded code indicators. Generic CDCL remains available; that is not equivalent domain coverage.

**Learn for Wassat:** Recover binary domains from complete clause grammar and apply P>H before generic CDCL. Create a shared certificate backend for decoded indicators, clique AMOs and global cardinality sums; full model replay protects SAT lifting.

**Improve LymphoSAT:** Publish proof atomically and check stream completion; emit_proof currently returns void and main reports UNSAT even if output cannot be written. Restrict the refutation to H+1 pigeons when P is larger; share code-prefix trie work and track proof size rather than repeatedly expand all pairs. Support variable-renamed/interleaved bit blocks by recovered incidence rather than contiguous half-clause positions, while checking every required exclusion.

**Certificates and evidence:** Full parsed-CNF SAT check; exported VeriPB extension/RUP/CP proof. Both controlled UNSAT proofs independently verified this turn. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/009-binary-pigeon-hole.json`.

### 10. binary-tree-parity

Bitset Gaussian elimination plus complete enumeration of up to24 free variables, back-substitution and full-CNF SAT replay. No UNSAT publication.

**Underlying structure:** A complete same-parity set of four ternary forbidden assignments is one GF2 equation. Three clauses alone are not that equation. LymphoSAT overrestricts candidates because it does not require distinct patterns or prove the missing row from binary clauses; the final SAT check prevents false SAT, but satisfiable inputs can be missed.

**Wassat coverage:** portfolio.w::wassat_xor_arm_body supports complete2..24-variable parity blocks and near-complete ternary blocks only with three distinct patterns plus a uniquely owned signed binary subclause proving the missing row. It compresses participating coordinates, limits dense elimination to8192 variables, checks original models, polls deadlines and bounds free-variable enumeration by134217728 literal visits. Its GF2 refutations are fast-only rather than exported DRAT.

**Learn for Wassat:** Translate residual binary clauses into affine free coordinates to solve them without2^d full-CNF rescans. Investigate Gray-code basis updates and incremental residual-clause counts under a shared literal-work budget.

**Improve LymphoSAT:** Require complete, distinct parity patterns or a checked implication for the missing clause before treating rows as logical consequences. Compress actual participating variables and bound literal visits, not only24 free variables; poll cancellation throughout enumeration. Preserve SAT-only status unless the recovered equations become certified consequences and their inconsistency has a checkable proof.

**Certificates and evidence:** SAT-only full parsed-clause validation. Inconsistent extracted rows or exhausted search return UNKNOWN. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/010-binary-tree-parity.json`.

### 11. brent-equations

Active rank>=19 path is generic min-break/max-make CNF stochastic search, sparse-zero starts, random restarts and occurrence-based clause counts; all successful assignments are replayed. An optional rank9 CDCL UNSAT experiment requires SOLVER_ENABLE_CDCL_UNSAT=1 and is off by default.

**Underlying structure:** Brent constraints for3x3 matrix multiplication are729 trilinear GF2 coefficient equations. With two coefficient blocks fixed, the third is linear. The active implementation does not exploit this structure; a rank number inferred from clause counts is only a heuristic.

**Wassat coverage:** WassatSls already provides generic configuration-checking/weighted CNF search and native occurrence updates. model_circuit.w supplies candidate gate lifting infrastructure. No general input-derived Brent coefficient decoder/search was found; tensor5 stored witness tables are not that capability.

**Learn for Wassat:** Decode alpha/beta/gamma primary coefficients and residual tensor equations; alternate linear solves for one block and structured repairs of another. Try an explicitly constructed rank27 schoolbook3x3 scheme, and canceling rank-one pairs for larger compatible ranks overGF2; lift auxiliaries and check streamliners and all CNF clauses. Use tensor residual scores rather than Tseitin clause scores; profile decoding, linear repair and model lifting separately.

**Improve LymphoSAT:** Replace clause-count rank inference with checked coefficient/gate reconstruction. Guard clause widths: choices[8]/best[8] are fixed arrays while the parser accepts wider clauses. This is a source-level bounds risk, not a reproduced runtime defect here. Reuse incremental make/break values and shared work/deadline budgets instead of repeated candidate occurrence rescans.

**Certificates and evidence:** SAT models checked against parsed CNF. Do not credit disabled CDCL proof code as active default UNSAT coverage. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/011-brent-equations.json`.

### 12. circuit-equialence-checking

Generic greedy/SLS model search plus occurrence-triggered unit propagation and bounded tree DPLL. Small<=1000-variable formulas get an initial120s DPLL slice; medium<=30000 can get540s. Leaf and branch refutations emit negated decision-path RUP clauses, stored in memory until proof publication. There is no clause learning in this DPLL search.

**Underlying structure:** Tree resolution is complete without budgets, but it does not exploit miter equivalence or circuit cones. Large unsupported UNSAT cases receive model search only, then UNKNOWN.

**Wassat coverage:** General CDCL/DRAT already overlaps or exceeds the generic fallback. circuit_miters.w has sorting and arithmetic semantic refuters, wide_circuit.w bounded exhaustive primary-input simulation, byte_relations.w byte-cube reasoning and circuit_cones.w local assumption queries. These are bounded/encoding-specific and do not imply every CEC case is covered.

**Learn for Wassat:** Reuse miter-local structural queries and emit checked lemmas through the existing proof backend; a second generic tree DPLL engine adds little. Measure semantic decoder admission, local cone refutation cost and proof replay independently on each CEC encoding.

**Improve LymphoSAT:** Recover actual gates and primary inputs, prove local equivalences and share learned consequences rather than repeatedly explore a tree. Stream proofs with bounded buffered state and check output publication; charge all preliminary SLS/DPLL slices against one budget. Route unsupported large UNSAT structures quickly to the fallback rather than spend a generic model-search slice without a family-specific mechanism.

**Certificates and evidence:** Full parsed-clause SAT check and a tree RUP proof on completed bounded refutations. Proof output stream completion is not checked before UNSAT. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/012-circuit-equialence-checking.json`.

### 13. circuit-minimization

Weighted randomized greedy cover construction, followed by selected-item swaps minimizing uncovered rows. Complete chosen primaries, unit-propagate auxiliaries by repeated full scans, default remaining variables false, and replay parsed clauses. No UNSAT path.

**Underlying structure:** The effective problem is fixed-cardinality set cover hidden behind a binary popcount circuit, rather than general circuit minimization. Selection-space moves avoid paying for every auxiliary Boolean flip.

**Wassat coverage:** counter_cover/decoder.w reconstructs signed aliases, complete XOR/carry definitions, adder weights and target output bits from actual clauses; search.w maintains fixed reusable swap buffers and updates only affected incidences. It lifts gates and checks every original clause. CLI scout and portfolio admit a bounded2s worker with memory checks. quota_cover.w handles Sinz-counter quotas; count_cover.w is a distinct fast-only bounded refuter, not the same SAT algorithm.

**Learn for Wassat:** Compare LymphoSAT row weighting and randomized starts with current incremental selection-space search on identical decoded covers. Consider adaptive weighting of persistently uncovered rows, while keeping incident-only updates and the existing cancellation budget.

**Improve LymphoSAT:** Recover signed adder trees and count outputs from checked gate definitions instead of memorized row counts and target64. Use an occurrence queue for auxiliary propagation and update uncovered/loss/gain caches only for swapped incidences; current code rebuilds the whole uncovered list each move. Preserve empty clauses and strict literal/header validation before claiming a model satisfies the original input.

**Certificates and evidence:** SAT-only parsed-CNF model check. The parser discards empty clauses, so its check is not a strict original-input check in that case; this is source inspection, not a newly reproduced defect. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/013-circuit-minimization.json`.

### 14. clique-coloring

Introduce slot-color indicators by redundant extensions, derive each slot color ALO and pairwise same-color slot exclusions, then eliminate color subsets by RUP. UNSAT only.

**Underlying structure:** A graph cannot contain a clique on c+1 distinct vertices and simultaneously be c-colorable. Slot-color indicators project the graph/choice encoding to pigeonhole.

**Wassat coverage:** coloring.w::wassat_clique_coloring_unsat checks required slot/color/edge implications, with arbitrary clause literal ordering and extra clauses allowed; permits c<k rather than onlyk=c+1, within vertex/work caps. It requires both choice widths>3, so tinyc2 probes lie outside this Wassat recognizer. CLI uses the refutation only outside proof mode. Column alignment still depends on sorted variable order.

**Learn for Wassat:** Export a slot-color projection proof for the existing checked obstruction so proof mode can use it. Unify clique/choice counting certificates across binary PHP, clique-coloring and partitioned-clique formulas.

**Improve LymphoSAT:** Replace exponential2^c subset RUP elimination with polynomial per-color AMO cutting-planes aggregation, as the binary-PHP/counting specialist already demonstrates. Accept a checked contradictory core plus arbitrary additional clauses; decode slot/color permutations instead of insisting on the full exact template. Bound c before1<<c and check proof stream completion; if q>c select c+1 slots to keep certificate small.

**Certificates and evidence:** Explicit VeriPB extension/RUP proof. Independently checked on n4/q3/c2 and n6/q5/c4 toy formulas this turn. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/014-clique-coloring.json`.

### 15. clique-formulas

Verify every pair within each recovered all-slot resource group is explicitly forbidden. If there are fewer groups than slots, derive each group AMO with a pbc/RUP subproof and sum these with slot ALOs in cutting planes. UNSAT only.

**Underlying structure:** Each slot demands at least one selected literal, while a verified group clique permits at most one. K slots and G<K complete exclusion groups contradict by counting.

**Wassat coverage:** coloring.w::wassat_amo_cover_or_rphp_unsat builds full and inter-choice exclusion graphs on actual literals, checks complete components, and counts covered choice clauses versus resources. It supports signed choices and partial covered subsets, so the central argument is already present more generally. Refutation is fast-only, without exported PB certificate.

**Learn for Wassat:** Attach the short per-clique AMO subproof and cardinality-sum certificate to Wassat's actual checked witness groups. Retain exact provenance for original choice-clause and exclusion IDs when recognizing a refutable subset.

**Improve LymphoSAT:** Use actual-variable conflict components instead of assumed common sorted vertex columns; allow unequal-width/signed choices and extra nonessential variables when a checked witness core suffices. If K<=G, seek a matching/transversal SAT construction and validate all original clauses; never infer satisfiability from the absence of this count contradiction alone. Share the certificate machinery with other PHP specialists and check close/write failures after proof output.

**Certificates and evidence:** Exported pbc/RUP/CP VeriPB proof; two controlled templates independently verified this turn. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/015-clique-formulas.json`.

### 16. clique-width

Search a linear growing-vertex prefix order, grouping prefix vertices by equal neighborhoods in the suffix. Memoize failed exact integer prefix masks with bounded node counts; strict solution becomes a full candidate derivation assignment. If that fails, greedy order supplies CDCL phases. Every direct/CDCL SAT candidate is checked; all internal UNSAT outcomes become UNKNOWN.

**Underlying structure:** Clique-width labels group vertices with the same future adjacency behavior. Restricting to a linear growing component can miss solutions requiring branching graph expressions; failure is not a clique-width lower-bound proof. Exact-key unordered_set equality resolves hash collisions, so hash-only memoization is not a defect here.

**Wassat coverage:** No dedicated clique-width derivation decoder/constructor was found in current Wassat sources. treewidth.w decodes a treewidth bound and graph minor and is mathematically different; it must not be credited as this specialist. Generic CDCL and domain search overlap only at Boolean search.

**Learn for Wassat:** Add a strict clique-width encoding decoder and neighborhood-type prefix constructor with original-CNF model lifting. Explore modular decomposition/twin contraction and branching partition merges beyond the linear-prefix restriction; retain generic CDCL as fallback rather than another separate implementation. Compress unused declared variable ranges and profile graph recovery, prefix states, construction and model replay separately.

**Improve LymphoSAT:** Apply a shared deadline during hint construction; node limits of5M/40M/80M do not bound elapsed time or failed-mask memory tightly. Guard mask width before signed1<<n/1<<v operations or use checked multiword masks; runtime does not prove n fits the integer mask. Recover block/edge semantics independent of clause order, and accept standard comments after the DIMACS header. Current token-int parser can stop on such comments. Broaden from growing-prefix to branching derivations and module/twin reductions, preserving full-CNF validation for every candidate. The CDCL reduce_db routine sorts candidates but actually deletes none and only raises its limit; implement bounded safe reduction or reuse the outer fallback.

**Certificates and evidence:** SAT-only full parsed-clause validation; no exported UNSAT proof. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/016-clique-width.json`.

### 17. clustered-random

probSAT-style break-weighted clause search, followed by CDCL with watched blockers, first-UIP, bounded failed-literal probing for small4-CNF and LBD/activity reduction. Before CDCL, saturate each forbidden-row table by resolving two child patterns that differ in one coordinate; every derived clause is logged as RUP. Proof events including deletions are held until buffered output.

**Underlying structure:** Repeated absolute tuples are small CSP tables. If both values of an absent coordinate are forbidden for a partial assignment, that partial assignment is forbidden: a local resolution closure can expose binary/unit consequences before global search. However the packed table key stores the fourth variable above bit52 in64 bits, truncating it to12 bits and merging distinct supports.

**Wassat coverage:** Generic SLS, first-UIP/CDCL, LBD retention, preprocessing probing/strengthening/BVE and proof streaming already exist. portfolio XOR recovery handles a special type of table but is not arbitrary forbidden-table saturation; domain_sparse.w is one-hot domain search, not repeatedBoolean-tuple closure. No direct equivalent per-tuple prime-implicate prepass was found.

**Learn for Wassat:** Add a budgeted complete small-table closure before global search; keep exact tuple equality and parent clause IDs for every resolvent. Compare table-level min-conflicts scoring with clause-weighted SLS where each tuple contributes several forbidden clauses. Benchmark closure cost and reductions separately from CDCL so improvements are attributed to the structural step.

**Improve LymphoSAT:** Fix tuple_key: a four-variable tuple cannot be packed as4+4*16 bits in64 bits. Use a full tuple equality key or hash plus exact comparison; even the fourth ID differing by4096 currently collides. Keep independent proof checking as the release qualification gate; the unverified dispatcher trusts this false UNSAT. Stream proof additions/deletions instead of keeping all historical learned clauses/events alive; document that closure and LBD reduction are now active despite stale Remaining Things To Try text.

**Certificates and evidence:** SAT assignments replay parsed original clauses; RUP/deletion proof output checks fclose. Reproduced false UNSAT from merged tables; independent VeriPB rejects the emitted proof. A correct same-table UNSAT control verifies. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/017-clustered-random.json`.

### 18. coloring-clique

For k<=c and n>=k, construct clique vertices0..k-1 with distinct colors and validate all parsed clauses. For k>c, introduce selector-and-color conjunctions z[p,v,a], derive one selected conjunction per slot and a per-color AMO via pairwise RUP and pbc, then sum in CP.

**Underlying structure:** Same graph k-clique/c-color obstruction as review14; this independently selected archive specialist uses finer conjunction variables and polynomial CP aggregation instead of exponential color-subset RUP. Its detector alone is not a sound certificate because missing edge/color constraints can make the input SAT.

**Wassat coverage:** coloring.w::wassat_clique_coloring_unsat already checks necessary explicit column exclusions, edge-forcing implications and every edge/color exclusion. It supports k>c within caps and permits strengthening clauses; no exported PB proof and no equivalent direct arbitrary-k<=c graph-model constructor is identified. This is the same central capability reviewed at14, not a second missing UNSAT family.

**Learn for Wassat:** Use the polynomial per-color counting proof idea for existing checked Wassat witnesses, preferably coarser slot-color indicators to reduce pairwise work. Add a cheap checked SAT graph/color proposal when the recovered formula genuinely permits k<=c; arbitrary extra constraints still require original-model replay.

**Improve LymphoSAT:** Check every required exclusion and edge/color implication before reporting UNSAT, or require the emitted proof to pass an independent checker before trusting the verdict. Recover blocks and edges from incidence rather than fixed contiguous vertex-major indexing and exact positive-clause order. Use coarser slot-color indicators and only c+1 selected slots when k is larger, reducing quadratic(k*n) conjunction conflicts. Share this specialist with review14's recognizer/proof backend to avoid duplicate incompatible assumptions.

**Certificates and evidence:** Full SAT model check; exported VeriPB extension/RUP/pbc/CP proof. Reproduced false UNSAT after deleting one required color-conflict clause, with explicit SAT witness and rejected proof; full template control verifies. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/018-coloring-clique.json`.

### 19. coloring-mycielski-graph

Add color-swap redundancy witnesses fixing apex color; recursively copy old edges onto shadows by RUP, obtain a clique in the strengthened proof state and branch on its vertices first using CDCL. The hint guard counts ternaries and dimensions rather than checking all actual hint implications before adding them. Full emitted proof is the independent justification.

**Underlying structure:** A Mycielski construction raises chromatic number by one: recolor old vertices of the apex color with their paired shadows' colors to obtain a coloring of the preceding graph using one fewer color. Original Mycielski graphs are triangle-free beyond the edge base; the clique used here exists after certified strengthening, not in the original graph.

**Wassat coverage:** mycielski.w proves the same recursive chromatic lower bound using checked apex/shadow neighborhoods. Its decoder targets ternary XOR-coded threeBoolean-coordinate vertex labels, consistent signed edge complements and a common palette of up to8 codes, not the large one-hot hinted encodings. Caps512vertices,10000vars,40000clauses and a50ms/2Mvisit budget; CLI fast-only. Thus mathematical equivalence does not establish identical instance coverage.

**Learn for Wassat:** Extend graph recovery to one-hot direct Mycielski domains and retain the existing neighborhood-checked recursive layer witness. Export a checked color-recoloring or RED/PB proof so existing semantic fast refutations can operate in proof mode. Share one graph-layer representation across compact-coordinate and one-hot encodings; derive actual missing hint lemmas rather than require memorized full-hint dimensions.

**Improve LymphoSAT:** Replace count-based full-hint guards with actual checked color symmetry and edge-copy prerequisites; duplicate unrelated ternaries cannot establish RUP. Generate missing RED/PR helper implications for partial-hint cases instead of returning UNKNOWN solely on a dimension/count whitelist. Reconstruct graph/domain permutations to support shuffled direct encodings; retain proof provenance for each recovered edge and color. Preserve empty clauses and declared input counts. Delete obsolete proof layers or use direct cardinality refutation of the strengthened clique to reduce verifier memory; notebook memory claims remain unmeasured here.

**Certificates and evidence:** RED color swaps, recursive RUP copied edges and learned RUP proof. Notebook real-instance timings/checks were not independently repeated here. Parser skips empty clauses and ignores declared count; do not describe parsed-clause model validation as universally strict original-input validation. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/019-coloring-mycielski-graph.json`.

### 20. core-based-generator

Set each long-clause payload literal false and its final link literal true. Occurrence-queue propagation fills auxiliaries; if residual clauses have width<=2, iterative SCC2-SAT completes them. Otherwise generic minimum-break/make repair starts from the hint. A hint contradiction is UNKNOWN, not UNSAT. All published models replay parsed clauses.

**Underlying structure:** Split all-sign core gadgets can leave a deleted forbidden assignment encoded by a long payload/link clause. The orientation is a candidate witness of that missing row, not a universally implied assignment. Recovering the split-chain/link DAG can allow deterministic completion and compact proofs of actual contradictory cores.

**Wassat coverage:** resolution_cover.w already resolves original split-chain clauses into support<=20 Boolean core rows, identifies complete forbidden covers or the unique missing assignment, propagates entailed values and completes a binary residual by iterative Kosaraju with a compact active-variable map and full original-CNF replay. The worker is bounded to2Mvariables/8Mclauses, at most12projection rounds,64chain steps,15s/400Mticks and residual262144activevars/1Mclauses. Default prefix admission favors repetitive width4+ clauses, so narrow3-CNF chains may require explicit WASSAT_RESOLUTION_COVER=1. It lacks exported global DRAT; it is stronger logically than LymphoSAT's last-literal orientation heuristic, but does not prove equivalent admission or performance on every NCC instance.

**Learn for Wassat:** Compare LymphoSAT's cheap long-clause orientation proposal with Wassat's stronger entailed missing-row derivation. A proposal may help narrow3-CNF cases currently excluded by automatic admission, but must pass whole-CNF validation. Broaden admission for supported split-chain cores based on a cheap measured prefix/degree witness; retain the exact original-clause resolution checks. Export the existing chain/core count and propagation refutations with parent provenance; residual2-SAT completion and compact node allocation already exist and should be reused.

**Improve LymphoSAT:** Identify link literals from chain incidence rather than the final literal position; long-clause literal permutation currently changes the hint. Reconstruct and solve the link DAG so an unlucky orientation can be changed instead of immediately returning UNKNOWN. Store signed literals in occurrence entries and update cached make/break values; current flip/candidate routines repeatedly rescan clauses. Use a count type wide enough for all long clauses. Charge parse, propagation, residual graph construction and repair to one cooperative deadline; the current repair budget mainly subtracts parse time. Support standard post-header comments and verify the declared clause count without assuming sanitized input.

**Certificates and evidence:** SAT-only, full parsed-model validation; no active UNSAT proof. Notebook prototypes whose huge proofs did not finish checking are excluded from capabilities. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/020-core-based-generator.json`.

Correction: the original review20 missed the existing `resolution_cover.w` worker. The coverage and recommendations above supersede the earlier missing-capability claim.

### 21. cover

Infer a target by assigning prefixes of primary variables false and propagating non-hyperedge clauses. Search independent point sets with greedy maximal extension, recursive two-copy seeds, destroy/rebuild and small fixed-cardinality repair. A checked explicit112-point construction is tried for729points. Above a size-based cutoff, smallv<=27 gets bounded primary DPLL with RUP; larger cases decline.

**Underlying structure:** Setting a point variable false selects it; each positive triple forbids selecting all three. The complement is a triple-hitting set bounded by the cardinality encoding. In affine F3 systems, no three selected points sum to zero. The112-point construction combines80weight3 vectors supported on ten design blocks and32full-support parity vectors; it is accepted only if every recovered triple checks. Prefix propagation is a target heuristic, not a proof of exact counter semantics.

**Wassat coverage:** counter_cover.w searches selections behind signed binary adders, quota_cover.w handles Sinz quotas and count_cover.w performs bounded cover counting over complete monotone gates, at most63inputs/4096vars. These provide partial complement/hitting-set infrastructure but do not constitute a Steiner/affine-cap decoder or the729point construction. covering.w and cover_split.w expect positive rows plus negative binary conflicts; the triple/cardinality family is not that exact grammar.

**Learn for Wassat:** Recover primary triples and exact signed cardinality semantics, then search the much smaller cap/hitting-set space and replay original CNF models. Use input-derived affine coordinates or a checked isomorphism before applying finite-geometry constructions; a correct cap remains only a SAT proposal until auxiliary/model replay succeeds. Reuse count_cover for bounded small complements where its checked gate grammar applies; avoid inventing another generic Boolean solver.

**Improve LymphoSAT:** Replace positional prefix target inference with exact counter decoding; arbitrary extra assertions or reordered point IDs can make prefix feasibility unrepresentative. Validate the Steiner pair uniqueness used by the third[x][y] acceleration; repeated pairs currently overwrite that table. Full cap replay protects SAT but search can miss candidates. Update only incident triple counts when swapping points rather than rebuilding every score each move; reuse buffers across greedy/destroy cycles. Use a cooperative deadline inside target inference and proof search as well as cap repair. The2Mnode cap alone does not tightly bound repeated full-clause propagation. Treat size cutoff tables as search policy only; do not suppress valid cap search on a nonisomorphic hypergraph solely because it has the same point count.

**Certificates and evidence:** SAT candidates lifted by full propagation and every parsed original clause checked. Bounded small UNSAT tree proofs use actual original clauses rather than trusting cap tables. ControlledAG(2,3) k4 SAT and k5 UNSAT tested; k5 proof independently verifies. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/021-cover.json`.

### 22. cryptography-ascon

Two watched-literal workers try62x62alphanumeric byte pairs and check complete false-filled models. Default then emits all65536full16bit blocking clauses and a binary RUP reduction tree without checking the leaves; optional ASCON_PRECHECK_ALL_PAIRS enables exhaustive RUP checks. Otherwise an input-derived sleep up to479s staggers verifier load before proof emission.

**Underlying structure:** A16free-bit circuit can be exhaustively evaluated or refuted by a complete assignment case split. Alphanumeric failure alone does not imply byte-domain exhaustion. Leaf clauses must be consequences of original CNF; the outer verifier is doing essential computation/correctness work in the default path.

**Wassat coverage:** crypto_circuits.w::wassat_ascon_preimage_unsat? already recovers6..16free circuit bits, validates every accepted circuit definition, and exhaustively evaluates64candidates per word across bounded workers. It only returns a fast refutation if no prefix assignment survives. Admission uses100k..250kvars/200k..600kclauses and fixed first/last clause checks. It does not export a proof or publish the surviving prefix as a complete SAT model.

**Learn for Wassat:** Export checked assignment blockers and a case-combination proof for the existing exhaustive bit-parallel worker, recording original gate provenance. Retain a surviving bit assignment as a SAT proposal, lift the remaining circuit/auxiliary variables and validate all original clauses; try other survivors if the first fails. Recover byte mirrors from checked equalities rather than fixed34..65, and choose enumeration order by constraints instead of assuming base62 witnesses.

**Improve LymphoSAT:** Enable checked exhaustion before UNSAT by default; proof emission alone cannot justify trusting the unverified dispatcher. Eliminate the fixed structural stagger sleep in favor of outer verifier-resource scheduling or measured proof-memory admission. Use bit-parallel gate evaluation to batch candidates, then validate RUP leaf obligations or provide a circuit-aware certificate; avoid making the checker repeat most of the search. Check all byte-assignment return values and proof stream completion; derive the actual free-variable/mirror map from clauses.

**Certificates and evidence:** SAT model replay. Explicit RUP case tree exists, but default UNSAT claims can be false: controlled zero-byte SAT shape returnsUNSAT and VeriPB rejects its first unsupported leaf. Optional precheck returnsUNKNOWN on the same case. The source README already acknowledges this risk. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/022-cryptography-ascon.json`.

### 23. cryptography-cbmc

Conventional watched CDCL with same-order binary fast path, first-UIP/minimization, stable increasing restart intervals and miter-literal priority for large ELE. At UNSAT, recursively mark learned dependencies needed by the root conflict and all current trail reasons, then emit only marked learned RUP clauses in chronological order. Actual search does not compose AES byte tables; tools/notes propose that future path.

**Underlying structure:** CBMC AES miter equivalence can expose byte S-box/T-table composition and linear GF2 arithmetic, but the active specialist mainly changes branching and proof size. Dependency trimming concerns which learned consequences are needed for a checked proof, not a new AES decision argument.

**Wassat coverage:** Wassat already has CDCL/minimization/restarts and DRAT/WRAT proof paths. byte_relations.w validates gates and equality-cube byte tables, canonicalizes congruence/linear groups and proves arithmetic substitutions with local CDCL queries before symbolic miter evaluation. It is fast-only and capped2s; flat validation rejects clauses wider than65, so ELE257literal miters are outside this worker. circuit_cones supplies complementary bounded local proof queries, not universal AES coverage.

**Learn for Wassat:** Consider dependency trimming as an optional proof postprocessor using stored hint parents; measure output/checking reduction against extra dependency/memory cost rather than retaining all clauses in the live solver. Compare focused miter-literal priority against current structural cones on actual supported AES shapes under identical budgets. Extend checked byte reasoning to wide residual assertions and export its local semantic lemmas into the global certificate stream.

**Improve LymphoSAT:** Promote actual table composition and input-byte/output-byte equivalence lemmas from tools into a bounded checked algorithm instead of duplicating more genericCDCL tuning. Use iterative dependency marking to avoid deep recursive mark_needed stacks; stream or externally compact historical proof data for memory control. Preserve empty clauses, standard comments and exact input counts; require successful proof completion/flush before UNSAT. Document active vs reverted experiments clearly: reduction/binary graph alternatives and TRY_ALL miter expansions are not default capabilities.

**Certificates and evidence:** SAT candidates replay loaded clauses. Dependency-trimmed VeriPB proof is emitted on completed refutations. Two small PHP controls independently verify the active trimming path; no new AES-scale proof or runtime comparison. Parser drops empty clauses and stops at post-header comments, and final proof I/O completion is not propagated to the UNSAT verdict. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/023-cryptography-cbmc.json`.

### 24. cryptography-simon

Enumerate32bit keys, default up to4threads, simulate the32bit Feistel recurrence with primary/permuted key halves, reconstruct all160variables per round and check the entire parsedCNF before SAT. Timeout570s is polled every2^20keys per thread; exhaustion and timeout both returnUNKNOWN. Stops at first word-level endpoint match even if that candidate later fails original-model replay.

**Underlying structure:** Lnext=((rol1L AND rol8L) XOR rol2L XOR R XOR Kround), Rnext=L. The second key word is a permutation of the same32unknown bits, not independent key entropy. Enumeration bypasses Tseitin clauses, but naive independent-key MITM does not follow from this correlated schedule. One/two-round endpoint cases allow direct algebraic key recovery; longer cases need validated stronger reasoning or faster exhaustive batches.

**Wassat coverage:** No dedicated SIMON/constant-key Feistel decoder or word-level scanner was found. crypto_circuits.w has bounded ASCON bit-parallel evaluation, model_circuit.w generic candidate lifting and portfolio.w an input-derived xorshift32word circuit search, which is a different recurrence. GenericCDCL/XOR support is useful infrastructure but not equivalent direct Feistel simulation.

**Learn for Wassat:** Add a checked recurrence proposal decoder with signed key-permutation recovery, direct word simulation and complete auxiliary/model reconstruction. Use bitsliced batches: key bitplanes make the permuted key a plane reordering rather than32per-key bit operations; reuse the existing bit-parallel circuit infrastructure. Use direct endpoint algebra for trivial round counts and explore round-boundary constraints for larger cases. Establish a valid state/key split before claiming a meet-in-the-middle reduction.

**Improve LymphoSAT:** Continue searching after a word-level endpoint match fails the originalCNF check; an incomplete detector or extra constraints can invalidate the first candidate while a later one is SAT. Recover complemented key equalities and actual gate semantics instead of relying on fixed numbering and a single-bit round-key clue. Bound total threads and poll shared cancellation/time at smaller work intervals; distinguish timeout from completed key-domain exhaustion in diagnostics. Use bitplanes/vectorized simulation and cache/derive permuted-key words efficiently. Benefit requires measured throughput and full model validation.

**Certificates and evidence:** SAT-only full literal-bounds and complete original parsed-clause model check. No checkable exhaustive-miss proof, and timeout must not be called a completed exhaustive scan. Exact generated1round/key0 and16round/key13 cases reconstruct independently checked complete models. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/024-cryptography-simon.json`.

### 25. design-debugging

Read clauses sequentially, collapse duplicates/tautologies, simplify against permanent root assignments and propagate immediately. A contradictory prefix emits a constant-size RUP contradiction. Otherwise transfer the simplified watch database and root assignments into CDCL rather than parse again. Hybrid branching uses short low-order positive trials on>=200kvariable residuals, then activity order after10conflicts/2000decisions/3Mpropagations. SAT is checked by rereading the original file.

**Underlying structure:** Hardware debugging formulas often collapse under fixed scenario/observation units. A contradiction in any original prefix refutes the full valid CNF because later clauses only strengthen it; no hardware-level explanation is needed for that case. An unfinished root propagation is not a refutation.

**Wassat coverage:** Wassat has native strict DIMACS parsing, root propagation, lucky/light scouts, CDCL and proof streaming. CLI currently reads/maps and validates/materializes the full input before solver arenas and scouts, so it is not the same combined prefix parser/UP pipeline. Strict whole-input validation is an existing contract and should be retained if propagation is moved earlier.

**Learn for Wassat:** Profile root-dominated hardware cases by parsing, root propagation, residual load and proof checking; consider a streamed root simplifier whose unresolved database transfers to the normal solver. After an early logical contradiction, validate the remaining DIMACS syntax/counts without constructing unnecessary search storage, preserving the whole-input validation contract. Measure short low-order positive trials on the actual reduced residual rather than route solely by original variable count; reuse existing scout infrastructure.

**Improve LymphoSAT:** Validate header kind/counts, literal bounds and complete integer tokens; proof of a prefix does not excuse accepting malformed input under a strict parser contract. Use a shared deadline during parsing/root propagation and final reread; current residual time checks do not bound all early work. Track proof stream errors and close completion before UNSAT publication. Replace forty brittle profile buckets with a cheap adaptive root-propagation signal where the fallback cost is low; retain semantic gates for any future circuit-level refuter.

**Certificates and evidence:** RUP original-prefix/learned proofs and final reread of original SAT clauses. Fresh prefix and transferred residual UNSAT proofs pass VeriPB; transferred SAT model checks. The scanner does not enforce declared counts/bounds or strict token syntax; output stream failure is not checked before verdict. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/025-design-debugging.json`.

### 26. diagnosis

RootUP,2000conflict CDCL phase, up to two10s failed-literal/common-implication/hyperbinary probe rounds, cost<=10 BVE for up to5rounds, then CDCL with3s probing inprocessing at growing50k..200kconflict intervals. Negative initial polarity, LBD/EMA and Luby restarts, learned deletion. Reverse elimination reconstruction is checked against retained original clauses.

**Underlying structure:** Model-based diagnosis often has six component states per time step, signal transitions and health/cardinality constraints. The active specialist exploits this mainly through a layout-dependent branching boost; its reduction/search is generic propositional reasoning. Common implications from both v polarities need supporting clauses before a RUP unit can be logged.

**Wassat coverage:** Wassat preprocessing already has failed literals, SCC equivalence, subsumption/strengthening, BVE and model reconstruction with proof provenance. Hyperbinary learning from long-clause reasons exists but WASSAT_HBR defaults0; it is not equivalent to LymphoSAT's enabled two-polarity common-implication units. Generic exact-one domain workers require checked simpler grammars and are not a recovered diagnosis component/time model.

**Learn for Wassat:** Compare bounded common-implication unit extraction with the existing optionalHBR path, logging both supporting implication clauses and controlling graph growth. Evaluate a branching boost for checked component-state domains after root simplification; replace the maximum-variable-ID flatness heuristic with incidence/transition structure. Recover component/time factorization and health/cardinality semantics for a finite-domain trace constructor or separator algorithm; do not count another genericCDCL copy as diagnosis specialization.

**Improve LymphoSAT:** Check complete EO support before using domain semantics; the current6positive-literal check is only a branching cue. Preserve empty clauses and finish parsing/validating all original clauses rather than returning early on contradictory units; fail cleanly on bounds/token errors. Handle empty BVE resolvents as a logged contradiction instead of silently skipping them, and keep reduced-clause reason provenance for inprocessing. Use checked proof open/write/close results. Compact the append-only arena and retain only necessary reconstruction/proof data when memory grows; do not inherit an arbitrary process-size assumption.

**Certificates and evidence:** Legacy VeriPB2.0 u/RUP logging (accepted by native3.0.2 on a fresh PHP5/4 control); SAT reconstructs and verifies retained parsed clauses. Empty clauses are discarded and contradictory-unit parsing can stop early, so the parser/checker boundary remains weaker than strict original-input replay. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/026-diagnosis.json`.

### 27. discrete-logarithm

Baby-step giant-step over0<=x<2^k with128bit modular multiplication and extended-Euclid modular inverse. Reconstruct each selected square-and-multiply state/product word, seed exponent and units, occurrence-propagate auxiliaries and replay every parsed clause; all failures returnUNKNOWN.

**Underlying structure:** Let m=ceil(sqrt(2^k)). Store a^j for0<=j<m, then find r*(a^(-m))^i in that table, yielding x=i*m+j subject to the bounded exponent check. This is an input-derived arithmetic reduction rather than SAT search; it requires invertibility for the giant-step inverse. Resource use scales with the square root of the exponent range, not the CNF variable count.

**Wassat coverage:** No BSGS/discrete-log or general modular-exponentiation CNF decoder was found in current Wassat library. multiplier/circuit routines offer checked arithmetic/gate infrastructure, crypto_circuits.w handles other bounded circuits and model_circuit.w lifts proposed primary assignments, but those are not this arithmetic algorithm.

**Learn for Wassat:** Build a strict selector/comparator modular-exponentiation proposal decoder and share exact modular arithmetic kernels across number-theory families. Use bounded BSGS for appropriate exponent sizes, with a memory/work admission based on m and actual group order when known; validate every lifted model. Where group-order factors are available, investigate Pohlig–Hellman or a memory-bounded group discrete-log method rather than allocate sqrt(2^k)entries blindly. Noninvertible bases need a separately justified gcd-reduction path.

**Improve LymphoSAT:** Replace clause-order/occurrence-order extraction with checked gate and vector incidence; input renaming or additional units can otherwise spoil the decoded parameters. Add deadlines and allocation/work limits before ceil_sqrt_u64 and reserve: the square-root routine increments linearly and k63can request billions of table entries. Construct quotient/remainder auxiliary words directly or use watched propagation to reduce repeated clause rescans. If one arithmetic exponent fails extra CNF constraints, search other equivalent exponents in range rather than stop at the first logarithm. For noninvertible bases, use a mathematically justified gcd-stripping algorithm and validate recovered exponents; do not just remove the inverse guard.

**Certificates and evidence:** SAT-only complete parsed-clause model check and final modular arithmetic equality. Fresh function-level tests compare all75950small invertible-base bounded cases against brute force, plus a near2^64modulus witness; no full CNF reconstruction test was run. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/027-discrete-logarithm.json`.

### 28. edge-matching

Compact: enumerate orientation tuples under one placement, recover a square piece-adjacency grid, embed it by degree/constrained DFS, choose compatible placements/orientations, and check the CNF. Holten: decode row-major gridline/TileExistence/NoColor blocks, extract rotations using first-cell clearing constraints, try tilei in originalcelli with hint colors, orient by MRV search, fill auxiliaries through propagation/greedy completion and verify allclauses. Oldb1904 remains unsupported despite matcher admission.

**Underlying structure:** Two placement partitions express one tile per cell and one cell per tile; local edge-color relations encode compatible orientations. Recovering a grid from incidence reduces a Boolean search to graph embedding plus small domain matching. Holten identity placement is a generator-order candidate, not a theorem that every edge-matching puzzle has that placement.

**Wassat coverage:** edge_matching.w already recovers two checked placement partitions (either order and a missing final group), exact-one edge-color domains and local placement tuples, reconstructs an unlabeled square grid by corner distances with explicit edge checks, and searches checked placements. It is SAT-only, with complete CLI model replay, caps256cells/50kvars/1Mclauses/8colors/8options/1Mnodes. Its homogeneous-incidence partition can swap mathematical cell/piece roles; the shared compact abstraction should not be mislabeled as missing merely because variable names differ. No matching large Holten feature-cardinality/NoColor/identity constructor was found.

**Learn for Wassat:** Reuse the compact placement/edge relation representation for any additional decoding, and compare constructor coverage rather than add another generic edge-matching engine. Add a separately gated Holten candidate decoder with original-CNF replay; identity tile placement may be a cheap first proposal but general matching must remain available when ordering changes. Use grid distance coordinates and checked graph isomorphisms to reduce placement search where the recovered topology determines a small symmetry orbit; preserve orientation/domain constraints.

**Improve LymphoSAT:** Replace recursive grid embedding with distance-coordinate reconstruction when the recovered graph is an exact square grid; Wassat already validates a corner-distance embedding. Avoid colors^4times alltiles/full-local-clause enumeration in Holten extraction; prune partial four-edge assignments with local relations and reuse flattened tuple buffers. Auxiliary completion already uses an occurrence queue, but its greedy decision loop rescans from the first clause each time. Maintain unresolved-clause state/indices or decode counters directly. Recover tile correspondence from hints/local pattern relations rather than rely solely on originaltileID=cellID; test literal, variable and clause permutations. Apply the deadline consistently in positive/exact-group collection and other whole-formula loops; unsupportedb1904 should decline before expensive generic collection where possible.

**Certificates and evidence:** SAT-only every loaded original clause checked; every detector/search miss isUNKNOWN. Header-size and520sdeadline guards bound intended scope, but some collection loops have no time polls. Notebook real-family timings were not independently repeated. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/028-edge-matching.json`.

## Checkpoint at28reviews

Reviews21–28 add source comparisons for cap search, ASCON, CBMC, SIMON,
design debugging, diagnosis, discrete logarithm and edge matching. The NCC
review20 was corrected after finding the existing resolution-chain worker
under a different name; its original missing-capability conclusion is superseded.
Current-source focused checks pass:9resolution-cover,10binary-residual and
6compact-edge-matching examples. The latter checks complete models, role order,
missing-group recovery, unsupported relations and bounded-search decline.

Controlled source probes add six accepted UNSAT proofs (one cap, two CBMC
trimming, two design-debugging and one diagnosis), six complete SAT models,
and a75950case BSGS kernel comparison plus one64bit modulus check. They also
reproduce ASCON's documented unchecked-exhaustion falseUNSAT on a synthetic
zero-byte SAT input; enabling its exhaustive precheck returnsUNKNOWN. These
direct probes do not establish top-level matcher admission or real-family
performance. No installed Wassat binary or solver implementation changed in
this checkpoint.

### 29. edit-distance

Search vertex partitions with singleton/all-in-one/component/random starts, improving vertex moves and cluster merges. Minimize pair disagreement with the recovered graph. Evaluate every parsed counter block from edit literals and reconstruct all auxiliary bits; publish only a complete original-clause model. Try only strict global best-cost partitions, with a90s/5000restart/staleness budget. NoUNSAT path.

**Underlying structure:** This is cluster editing, not string edit distance: pair variable istrue iff its endpoints share a cluster. Transitivity enforces a disjoint union of cliques; edit cost is graph disagreement. Each inducedP3requires at least one edge toggle; an edge-disjointP3packing gives a checkable lower bound and a three-way branching rule.

**Wassat coverage:** No input-derived cluster-partition move/merge constructor or inducedP3editing decoder was found. counter_rewrite.w checks and replaces a closed exact-count unary-adder suffix; counter_cover.w reconstructs signed aliases/binary adders; quota_cover.w handles Sinz quotas. Those are useful cardinality components, not equivalent graph-partition optimization. partition_circuit.w solves numeric equal-sum partition, which is a different meaning of partition.

**Learn for Wassat:** Decode signed edit pairs and cardinality constraints, then search partitions directly with incremental cluster-neighbor counts and full original-CNF lifting. Add edge-disjoint or fractional inducedP3packing bounds; each original transitivity clause can become a signed edit-demand clause. Export the bound through checked counter/PB reasoning before using it forUNSAT. Use branching on an inducedP3for small edit budgets, with shared node/time limits and clause-level proof provenance.

**Improve LymphoSAT:** Recover the actual edit bound and counter outputs instead of trying a full model only when unconstrained graph cost improves. Try alternative equal-cost partitions when model lifting fails; extra CNF assertions can distinguish partitions with the same edit count. Maintain move/merge gains incrementally rather than rebuild std::set/map labels and rescan allvertices/clusters for each move; add split/swap neighborhoods. Topologically schedule counter blocks once and reuse model buffers; preserve empty clauses and strict original-input validation. Generalize the pair/transitivity and counter decoding beyond exact clause order while keeping every published model checked.

**Certificates and evidence:** SAT-only complete parsed-clause model validation. Fresh3vertex remainder/carry/ordinary-counter fixture produces a complete independently checked model. Parser discards empty clauses and omits declared-count/bounds checks; no broad parser/family correctness claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/029-edit-distance.json`.

### 30. equivalence-chain-principle

For each gate/layer, enumerate complete involutive child matchings, prove a PB local nonincrease bound by pbc and matching-case RUP, and chain it into a global upper bound on true leaves. Final boundary units contradict that bound. Implication chains, SAT variants and any template mismatch returnUNKNOWN. Proof deletes obsolete global/gate bound constraints.

**Underlying structure:** Shared symmetric swap selectors with onechoice perchild define an involutive permutation, so each phase preserves the multiset of leaf truth values. With d=4 there are f^2initial true leaves and f^4-f^2final demanded true leaves. Odd-depth instances have different initial/final exponents; the generated boundary clauses and the exact count contradiction must be used rather than blindly assuming both exponents d/2. Dropping don't-care units in implication chains invalidates this specific count argument.

**Wassat coverage:** Wassat has generic one-hot/clique/resource counting and circuit/counter infrastructure, but no current FmlaEquivChain decoder or local-to-global conserved-leaf PB proof was found. relay_count.w counts a different pigeonhole-through-relays obstruction; threshold_cover.w bounds demands over supports, not a chain of checked involutive leaf permutations. Unqualified historical implication-chain experiments are not current qualified coverage.

**Learn for Wassat:** Recover checked leaf layers, one-hot symmetric swap selectors and guarded update equalities; use count preservation only after all necessary premises are validated. Implement a common PB certificate interface for local conserved quantities and compose it across layers, retaining original clause IDs. Keep equivalence and implication-chain semantics separate; a game/strategy or Boolean-function invariant for implication chains needs its own proof and qualification.

**Improve LymphoSAT:** Replace factorial/involution matching expansion with a checked polynomial extension-based conservation argument: linearize selector-and-leaf products, use row/column exactly-one sums and project source/destination counts. This is a proof-design proposal that still needs independent replay. Allow a certified contradictory template subset with strengthening clauses and recovered permutations instead of requiring exact literal/clause order. Bound matching generation, proof size, memory and walltime before constructing allcases; f<=16does not make the number of involutions small. Infer n algebraically from the linear variable-count equation instead of scanning up to1M candidates, and make odd-depth boundary counts explicit in diagnostics.

**Certificates and evidence:** Explicit VeriPB pbc/RUP/CP proof after exact whole-formula comparison. Fresh d2/f3, d3/f3 and d4/f2 two-formula controls all verify; changed boundary declines. No new proof replay of the largef8archive instance or speed claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/030-equivalence-chain-principle.json`.

### 31. erdos-discrepancy

Use a fixed published13000term sequence prefix, explicitly verify every relevant homogeneous progression partial sum has absolute value<=3, assign the firstNprimary sign variables, run at most20full-CNF propagation passes to fill auxiliaries and replay every clause. The repair_sequence and mu3code are unused in main; no online extension algorithm is active.

**Underlying structure:** The constraint is |sum_{i=1}^m x_(i*d)|<=3for everyd,m withmd<=N. A verified finite witness solves all unrestricted shorter prefixes, but extra CNF assertions still need fullmodel checks. The archive sequence is not completely multiplicative even after normalizingx1; that shortcut must not be assumed.

**Wassat coverage:** No EDP3 progression decoder, lag/prefix automaton constructor or checked sequence witness was found in current Wassat. GenericSLS, finite-domain/NAE and counter routines can support a new constructor but do not encode these arithmetic progression constraints. A numeric13000substring in backdoor.w is an unrelated witness-table integer, not evidence of discrepancy coverage.

**Learn for Wassat:** Recover progression/sign variables and automaton states from input clauses, then build a checkable sign-sequence candidate and lift all auxiliary states directly. Develop constraint-driven prefix extension or signed-progression repair with incremental partial-sum updates; measure it against genericCNFSLS rather than count the fixed prefix as a general solver. If reusing a public finite witness, establish data licensing/provenance separately and independently recheck all progressions before it becomes a SAT proposal.

**Improve LymphoSAT:** Decode actual progression automata instead of relying solely on declared variable count and primary1..Nlayout. Replace20whole-CNF passes with direct automaton-state filling or an occurrence queue and a shared deadline; sorted clause order should not determine completion success. Make sequence resource location explicit relative to the executable/package, and keep its hash/provenance with the bundle. Remove or clearly separate unused experimental repair/mu3 code; it is not active capability. For longer lengths, use a verified extension/construction and full checks. Complete multiplicativity is an optional restrictive search model, not a property of the existing sequence.

**Certificates and evidence:** SAT-only parsed-original model replay. Independently checked all homogeneous progression sums for the full13000terms:maximum3; SHA/progression evidence in31-sequence-check.json. No full competition CNF auxiliary reconstruction run. Sequence data source availability is not a redistribution license grant. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/031-erdos-discrepancy.json`.

### 32. fdmus

Propagate8state truth-triple masks across corresponding signedAND gates, enumerate prime implicates over each corresponding triple, and log them as RUP. If final forced output triple is excluded, emit a direct contradiction. Otherwise inject the same lemmas before BVE/BSS/CDCL. The inherited fallback has separate correctness defects: empty resolvents are discarded and SAT reconstruction/original validation is absent.

**Underlying structure:** Abstract each corresponding node by a subset of{0,1}^3. Complement permutes these states; a copiedAND maps a Cartesian product of parent relations coordinatewise. Ignoring inter-parent correlations enlarges the result, so excluded triples remain impossible. This relational abstraction can prove more than ordinary copy equality while avoiding enumeration of all independent primary bits; missing correlations explain fallback cases.

**Wassat coverage:** Wassat has exact AIG sweeping, bounded dependency-circuit enumeration and byte/signed congruence. Pure aig_miter_run requires consecutive AND definitions followed only by units, while FDMUS contains cross-copy equivalence binaries; equality congruence is not the same8state three-copy abstract domain. No equivalent cross-copy relation propagation or systematic prime-implicate injection was found. GenericCDCL remains the checked fallback.

**Learn for Wassat:** Add a clean-room finite-relation domain over corresponding copied nodes, using exact original-gate clauses and equality/unit provenance. Validate/log derived small relational lemmas through local assumption proofs or a qualified RUP backend before sharing them with the main solver; semantic consequence does not automatically mean arbitrary clauses are RUP. Use selected joint-node relations only where the single-node abstraction loses useful correlations; cap region size and measure lemma benefit versus cost.

**Improve LymphoSAT:** Preserve empty clauses/resolvents through preprocessing and immediately emit the justified contradiction rather than drop them. Store a reverse elimination stack, reconstruct eliminated variables and validate every original clause before any SAT publication. Stream checked proof I/O errors to the verdict and validate all DIMACS bounds/comments/counts; FastReader can stop at a post-header comment. Find corresponding nodes by recovered structural signatures rather than equal contiguous blocks, and emit only relation clauses required by the final contradiction or useful for the fallback. For difficult cases, refine correlations selectively instead of replacing the entire abstraction with a full exponentialBDD.

**Certificates and evidence:** Fast path exports legacyVeriPB2.0RUP and a fresh18variable three-copy proof independently verifies. However fallback SAT is unchecked: contradictory units incorrectly produceSAT, and an eliminated-variable SAT case prints an invalid model. Both tiny direct probes are independently replayed against original clauses; top-level matcher admission is not established. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/032-fdmus.json`.

### 33. fermat

Deterministic seven-base64bit Miller-Rabin, small-prime trial division and bounded Floyd Pollard-rho using unsigned128bit modular multiplication. Convert a proper factor pair u*v=N to a=(u+v)/2,b=(v-u)/2; check a*a-b*b=N and word bounds. Seed primary words, repeatedly propagate fullCNF, false-fill unused variables and check every parsed clause. SAT-only; one factor pair tried.

**Underlying structure:** For oddN, a^2-b^2=(a-b)(a+b), so proper odd divisor pairs give integer square-difference witnesses. PrimeN still has the trivial1*N representation; this specialist excludes factor1 and may decline a satisfiable unrestricted square-difference instance. Input constraints, bit widths and the actual encoding decide which representations qualify.

**Wassat coverage:** Wassat already has canonical square/subtract recovery, bounded Pollard-rho factorization, occurrence-queue propagation and full original-CNF model validation in fermat.w, called directly by the CLI. It validates complete parity/carry tables for a unique recovered target, supports widths4..61, trials through997 and4rho rounds of32768steps. The current overflow-safe modular multiplication is repeated add/double and can be a kernel hotspot; it lacks the early Miller-Rabin prime filter. ToughSAT factor recovery is an additional separate encoding path, not proof of coverage of this PEQNP comparator layout.

**Learn for Wassat:** Compare the PEQNP final-comparator recovery with the existing checked subtract-block decoder; retain them as separate candidate sources with complete model replay. Profile the current add/double modular product, then consider a shared overflow-safe wide-product/Montgomery kernel and deterministic Miller-Rabin filter before rho. Existing rho coverage must be credited rather than duplicated. Try factor swaps/signs and additional divisor pairs when the first lifted candidate fails extra input constraints; factorization alone does not satisfy the CNF.

**Improve LymphoSAT:** Use occurrence-queue propagation and reusable model buffers instead of repeated whole-CNF scans. Validate the full DIMACS token stream, including empty clauses and declared bounds; final replay is only as strong as the clauses retained by the parser. Recover/check arithmetic gates more generally than positional final80clauses, and avoid O(width*nvars) equality-set probing. Use shared elapsed/work budgets and cancellation throughout rho, recovery and lifting;199*200000rho iterations is not a portable time bound. Consider batched-GCD Brent rho, measured against Floyd; distinguish algorithmic proposal from an established speed gain.

**Certificates and evidence:** Full parsed-clause SAT replay, with a permissive line-based parser that discards empty clauses and does not enforce counts/bounds. Direct unmodified-source kernel matches primality on0..100000 and returns valid pairs for7738small odd composites plus3wide composites, including balanced1e18-scale cases. Kernel tests are not a full PEQNP model-lifting or speed test. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/033-fermat.json`.

### 34. fixed-shape-random

Each selector chooses one of two sides with up to12clauses and4private aux variables. Enumerate minimal unsatisfiable aux-clause subsets to project each side to primary clauses, and enumerate aux witnesses as primary-requirement terms. Distribute the OR of the two side projections by pairwise clause union. Multi-seed projected-CNF local search, weighted block search and bounded CSP search propose primary assignments; fill selector/aux witnesses, undo normalization and verify both normalized and originalCNF. NoUNSAT publication.

**Underlying structure:** For clauses (p_i OR A_i(y)) with privatey, existential projection is the conjunction, over aux-unsatisfiable subsetsU, of OR_(i in U)p_i. Minimal subsets suffice. A private selector makes the block projection F0(x)OR F1(x), whose CNF clauses are unions of one clause from each side. Private scopes are necessary: eliminating an auxiliary shared between blocks independently is unsound.

**Wassat coverage:** projected_sls.w performs SCC-equivalence substitution before existing SLS, not this existential MUS block projection. selector_latin_decode.w has private-selector resolution for Latin-specific structure; generic preprocessing/BVE and model lifting can be reused. No equivalent detector plus exact small-aux projection and structured reconstruction for these random gadgets was found. Wassat quad-block lifting handles a different positive-clause quadrant construction, not this Boolean function.

**Learn for Wassat:** Build a shared checked private-component projection interface: detect local auxiliary scopes, derive the exact small-primary relation and retain a witness table for model lifting. Compare resolution/BVE, truth-table elimination and MUS-derived projection by output size, not only auxiliary count; share equivalent projected clauses and retain original provenance. Search projected primary relations directly with incremental affected-block scores and lift every successful assignment through original clauses.

**Improve LymphoSAT:** Compute aux satisfiability for all clause subsets once, or generate minimal hitting requirements from aux assignments, rather than rerunning all assignments for every subset and every minimality check. Deduplicate and subsume projected clauses across blocks; retain compact DNF witness terms when pairwise CNF distribution grows. Use a shared deadline across all phases: the current sequential search allowances sum to589seconds before parsing/projection/lifting, leaving little headroom under a600second outer limit. Parameterize the300primary partition and recover connected private scopes instead of depending on occurrence counts4/24 and exact9variable block layout. Accept standard comments throughout DIMACS and validate all trailing tokens; keep full original-model replay after fuzzy normalization.

**Certificates and evidence:** SAT-only complete original-model replay. An unmodified-source function harness checks256random paired gadgets:24576truth-assignment comparisons,60861lifted satisfying terms and1087minimal cores all agree with independent exhaustive aux enumeration. This validates local projection/lifting, not full300-primary competition search or arbitrary normalization. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/034-fixed-shape-random.json`.

### 35. floodit-puzzle

Collapse monochromatic grid components and maintain the flooded region/frontier with CSR adjacency. Try two/three-step greedy lookahead, BFS-distance scoring, randomized greedy, beam widths10..320 and iterative deepening when slack<=20. Simulate the sequence to fill all color/flood/adjacency variables. Default path checks simulated invariants only, skips all original-clause replay and can publish a model that violates unread suffix clauses. SAT-only.

**Underlying structure:** After monochromatic contraction, one color move absorbs all frontier components of that color. The maximum component-graph distance from the flooded region is a valid remaining-move lower bound: each newly absorbed component is at most one graph edge beyond the old region, because adjacent contracted components have different colors. Search failure is not an UNSAT proof, particularly for greedy/beam phases.

**Wassat coverage:** No Flood-It grid/color-layer decoder, monochromatic component constructor or frontier color-sequence search was found by source/name/semantic searches. Existing reconfiguration/planning and finite-domain search are reusable infrastructure but solve different state-transition models and are not equivalent family specialists. Generic full-CNF validation already provides the safety boundary needed for any new SAT proposal.

**Learn for Wassat:** Add an input-derived grid/layer decoder and direct component-frontier search, then reconstruct all time-layer variables and replay every original clause before accepting SAT. Use canonical flooded-component bitsets, state deduplication/dominance and an admissible graph-distance bound in bounded beam/A*or IDA*search; share remaining time across strategies. Profile extraction, component construction, move evaluation, state copying and streamed full-model validation separately.

**Improve LymphoSAT:** Validate every original clause after constructing a candidate. A prefix simulator does not certify arbitrary unread clauses; reread/mmap-stream the full input without materializing it if memory is the concern. Only skip full replay after a complete checked encoding comparison, not a partial structural extraction. Reject malformed/extra constraints rather than silently ignore them. Reuse allocated FloodState buffers across randomized restarts; init currently allocates fresh storage repeatedly. Use explicit move/deep-copy ownership for beam states and measure allocation costs. Deduplicate beam states reached by different color sequences; prune no-progress moves and poll one shared deadline in every greedy and verification phase. Recover all starting cells consistently; search initializes one start component while simulation uses all initial cells. General multi-source variants need a shared semantics.

**Certificates and evidence:** NoUNSAT certificate. Controlled2x2/K3/T3prefix gives a valid complete41variable model; appending an empty clause after the extraction prefix produces the same SAT verdict and an independently falsified final clause. This tiny direct prefix probe lies outside the top-level matcher and does not establish a failure on a competition encoding or in the verified outer portfolio. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/035-floodit-puzzle.json`.

### 36. fpga-routing

One-hot: recover groups, seek a clique with globally consistent color transports, export per-color AMO/PBcounting proof; otherwise graph/raw-domain model search. Bit-vectors: recover allowed raw codes and aligned tables, classify constraints as allowed-permutation equalities or forbidden-permutation inequalities, contract equality components with permutation union-find, search quotient domains, unmap colors and solve original residual clauses. For a quotient clique, extract a bounded original-clause core and run proof-loggingCDCL; genericCDCL remains finalfallback. Older uncontractedCSP path is disabled unless ENABLE_BV_CSP.

**Underlying structure:** An equality x_b=pi(x_a)transports colors through a component. Consistent transports let many bit groups become one finite-domain variable; within-component inequalities prune colors. A clique of arbitrary forbidden permutations alone need not require k+1colors: inconsistent edge labeling can admit a k-color assignment. One-hot proof checks alignment; bit-core refutation is justified by actual original-subsetCDCL, not the abstract clique alone. A nonidentity equality cycle may still have fixed-point colors, so rejecting every nonidentity transport cycle is conservative incompleteness rather than a valid contradiction.

**Wassat coverage:** coloring.w already verifies one-hot AMO-clique counting across resource/choice components, and domain_walk/domain_sparse search explicit one-hot finite domains. Those substantially overlap the one-hot mathematical argument; Wassat currently lacks its exported PBcertificate. No general2..4bit allowed-code table decoder or permutation-valued union-find was found. coloring.w::wassat_try_quad_block_lift is a positive quadrant/selector transformation and is not a binary bit-domain routing decoder. Generic Boolean SCC substitution only contracts bit-level equivalences, not arbitrary whole-domain color permutations.

**Learn for Wassat:** Unify bit-encoded finite-domain recovery with the binary-pigeonhole and routing families, retaining allowed-code tables and every original-clause constraint. Add permutation-valued equality contraction with root-domain restrictions and reversible model lifting; compare it against bit-SCC preprocessing and genericCDCL on identical inputs. Attach a common checked AMO/counting certificate backend to existing Wassat one-hot recognition. Preserve cycle-consistency checks before interpreting permutation exclusions as ordinary coloring. For quotient obstructions, certify the actual original core or transport lemmas; graph shape alone is insufficient.

**Improve LymphoSAT:** For an equality cycle, intersect the root domain with fixed points of the induced permutation and continue when nonempty, instead of declining on every nonidentity cycle. Propagate component domains and compact sparse quotient constraints before stochastic search; handle general small-domain relations when they do not fit one allowed/forbidden permutation. Use a single global deadline/proof budget: repeated clique-core attempts,45/70second component search, residual completion and540second finalCDCL currently have independent allowances. Cache recovered groups/tables between the UNSAT and SAT BitVectorCSPSolver passes; main reconstructs this work twice. Make parser/header/literal validation and proof I/O errors explicit. Keep final original-model replay even when group recovery or projected search succeeds.

**Certificates and evidence:** Fresh independent VeriPB replay accepts one-hotK4/3color760B,2bitK4/3code448B and a true contracted5group-to4component core457B. A twisted one-hotK4has a verified SAT model. Removing one edge from the contracted obstruction exercises the default permutation search and original residual lifting with a verified SAT model. All tiny direct probes bypass feature admission and are not performance evidence. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/036-fpga-routing.json`.

### 37. genurq

Dense bitset RREF over all declared variables; branch over compatible allowed tuples of non-XOR relations, limited to 28 participating relation variables. At each complete tuple assignment, rebuild and solve the affine system with those variable units, zero-fill affine free coordinates and check the full parsed CNF. No UNSAT output or certificate, including an inconsistent pure-XOR system.

**Underlying structure:** A complete parity class of forbidden assignments is exactly one GF(2) equation. A half table with one assignment swapped is generally not affine and must remain a relation. Conditioning its coordinates reduces the rest to linear algebra. The nonlinear-variable count and affine nullity are different parameters: one can be small while the other is large.

**Wassat coverage:** portfolio.w already detects complete distinct parity tables of width 2..24 plus conservatively justified near-ternary tables, compresses participating coordinates and performs incremental GF(2) elimination. It can refute inconsistent consequences on its fast path and enumerates up to 24 free coordinates under a 134217728 literal-visit bound for checked SAT proposals. It does not explicitly condition nonlinear relation coordinates when affine nullity is large, so the relation-branching strategy is a distinct complementary parameterization. Generic residual/CDCL can cover misses; no equivalent dedicated half-table conditioner was found.

**Learn for Wassat:** Keep the existing XOR decoder and add optional nonlinear-coordinate conditioning, rather than create a duplicate Gaussian solver. Project residual relation literals into affine free coordinates; use incremental linear consistency and branch on the smaller nonlinear separator, with reversible row updates. Share a proof/export interface for certified XOR consequences; Wassat fast refutations and LymphoSAT SAT-only solving have different certificate capabilities.

**Improve LymphoSAT:** Reuse one echelon basis and incrementally add/undo branch units instead of rebuilding dense RREF at every leaf. Eliminate over participating coordinates, not declared nvars; use sparse rows and connected components before a dense kernel. Add work/time/memory limits during table expansion and branching. A 28-variable cap still permits exponential search and repeated full linear solves. Accept an implied XOR subsystem alongside arbitrary residual clauses, not only formulas entirely partitioned into half tables; retain complete original-CNF replay. Preserve empty clauses and strict DIMACS bounds/counts before publication.

**Certificates and evidence:** SAT-only parsed-clause replay. All 24 renamed/shuffled synthetic XOR-plus-swapped-half controls agree with exhaustive Boolean classification and yield independently checked complete models. A contradictory XOR triangle returns UNKNOWN. Parser discards empty clauses, tolerates unterminated clauses and does not validate bounds/counts; these probes do not establish strict parser soundness or official matcher admission. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/037-genurq.json`.

### 38. gf3-sat

Enumerate 8 coefficient sign vectors and 3 right-hand sides to fit each exact 81-tuple truth table, build a dense byte matrix, perform GF(3) Gaussian elimination with free values zero and back-substitute. Lift ternary values to exactly-one Boolean assignments and check every parsed original clause. Inconsistent/unsupported formulas return UNKNOWN; no proof export.

**Underlying structure:** A nonzero four-variable linear equation over GF(3) allows 27 of 81 tuples and forbids 54. Coefficients are 1 or 2; multiplying a row by 2 normalizes its first coefficient. Every permutation of three domain values is affine x->a*x+b over GF(3), since its affine group has 3*2=6 elements, equal to S3. Thus arbitrary independent value relabelings preserve this decoded family; sorted literal labels are already sufficient, contrary to the README limitation.

**Wassat coverage:** No GF(3) equation-table recovery or field-three elimination was found in current Wassat. latin_csp.w recovers three-domain Latin relations (any two values determine the third), while these are four-domain equations (any three determine the fourth); its detector rejects this grammar. Existing one-hot recovery, table validation and GF(2) kernels are useful components but not equivalent GF(3) capability.

**Learn for Wassat:** Add exact finite-field relation fitting on recovered domains, including four-ary GF(3) equations, then eliminate over the high-level variables and lift the complete Boolean model. Share one-hot partition and relation-table recovery with existing Latin/CSP workers; keep coefficient field and relation arity explicit. For larger sparse systems, peel degree-one variables and connected components, then use sparse elimination/Markowitz ordering before a dense core. Design and independently replay modular row-combination certificates before enabling UNSAT; ordinary integer PB sums do not automatically justify arithmetic modulo three.

**Improve LymphoSAT:** Correct the README value-permutation limitation: all ternary relabelings are affine and current exhaustive coefficient fitting already handles them. Generalize checked equation scopes beyond arity four and permit a certified affine subsystem with residual constraints; search free coordinates only under a shared budget. Bound matrix dimensions, coefficient-fitting work and elapsed time before allocation/elimination; sparse fill-in should determine when to switch to dense storage. Use a strict token-stream DIMACS parser and preserve whole-input validation; accept valid clause wrapping/order without losing constraints. Retain original block and row-operation provenance to support future proof export instead of returning a bare inconsistency.

**Certificates and evidence:** SAT-only complete clause replay. Six fully variable-renamed, literal/clause-shuffled five-domain systems return independently checked complete models. A three-row inconsistent system on six domains returns UNKNOWN. The line-based parser is not a general multiline/multiple-clause DIMACS parser; it retains empty lines as empty clauses and decoder rejects them. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/038-gf3-sat.json`.

### 39. glassy-gen

Damped sum-product belief propagation for 80 iterations with clipped log-likelihood ratios, global-complement scoring and greedy likelihood refinement propose verified models or SLS seeds. Two concurrent SLS schedules use probSAT/WalkSAT and weighted repair, first-position/majority/random/BP starts, bounded flips per restart and a common 595-second search deadline. Enhanced schedule reserves up to 12 seconds for near-solution depth repair. The separate CDCL class is unused by main; no UNSAT output.

**Underlying structure:** For a planted distribution, literal truth positions carry statistical information beyond clause satisfiability. The score is the sum of log weights of each clause truth pattern; message passing approximates marginals in that factor model. It is a heuristic and may lose its signal under independent literal-order shuffling. A leading-literal candidate is only a model proposal; verifying every clause makes it safe even when the generator assumption is wrong.

**Wassat coverage:** Wassat already has native CCAnr-family configuration-checking and clause-weighted SLS, packed clause state, incremental weighted scores, shared stopping and phase-seeded walking. No leading-literal planted witness extractor or position-aware BP likelihood seed was found. Its MDP worker recovers noisy parity equations and is a different planted problem. Reuse existing model search and phase injection rather than add another generic SLS/CDCL implementation.

**Learn for Wassat:** Add cheap raw-clause planted candidate generators followed by full validation; run them before any normalization that destroys literal-position information. Experiment with a clean-room factor-graph seed generator and feed candidates into existing walk_from_phase/CDCL target phases. Keep learned distribution parameters and training provenance explicit. Ablate first-block order, clause shuffle, literal shuffle and held-out generator variants; measure seed quality, BP cost and downstream flips rather than attribute generic SLS wins to mathematical decoding.

**Improve LymphoSAT:** Use one deadline including parsing, BP, likelihood cleanup and output verification; main currently starts its 595-second budget only after those phases. Precompute probSAT break-weight tables instead of calling pow per candidate in every enhanced flip; measure this alongside repeated Clock::now and occurrence scans before choosing a change. Maintain incremental break/make or weighted scores as Wassat already does; avoid repeated occurrence traversal for all three candidates. Coalesce repeated-variable occurrence positions into one clause mask for likelihood deltas. Padding binary/unit clauses is logically equivalent, but independent single-position delta sums are not the joint variable-flip likelihood change. Share cancellation with bounded depth repair so a model found by the other thread does not leave a losing repair branch running to its deadline. Remove or separate unused CDCL code; it is not active solver capability. Validate strict DIMACS counts and termination as well as literal bounds.

**Certificates and evidence:** Every reported SAT model is checked against the parsed equivalent 3-CNF. A generated 24-variable/112-clause first-block control and a clause-shuffled control both give independently checked models; the latter confirms the positional-BP path in its diagnostic. These are not authentic random-regular glassy instances or evidence of published train/hidden success rates. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/039-glassy-gen.json`.

### 40. graceful-production

For every unassigned variable try true and propagate; on immediate conflict undo only that decision and its consequences, then try false. If both fail, return UNKNOWN without changing earlier choices. Full clause scan before SAT. Buffered parse/output and pre-reserved vector watch lists reduce overhead; no CDCL, global backtracking or UNSAT proof.

**Underlying structure:** Despite the name, this is production scheduling, not graceful graph labeling. The specialist README describes bounded daily unit outputs, target totals and monotonic daily totals/minima. The active implementation exploits encoding luckiness through positive phases rather than reconstructing those arithmetic variables. One-step opposite-branch repair is incomplete: a wrong earlier commitment can make both later branches fail although another earlier choice yields a model.

**Wassat coverage:** Wassat already implements precisely this ascending positive-first/one-decision-repair dive, alongside negative and reverse-order dives. Both full-core lucky_dive and compact wassat_flat_lucky_dive exist; raw/preprocessed portfolio arms and large-input compact admission are current call sites. It also uses packed watch arrays, literal-work budgets and full original-model checking. Eligibility and preceding negative dives can affect application cost, so algorithmic equivalence is not a competition performance guarantee. No dedicated production-variable arithmetic constructor was found; permutation_walk is graph labeling and unrelated.

**Learn for Wassat:** Credit the existing positive greedy path; profile actual production inputs to determine whether admission, watch initialization, negative-first ordering or model output dominates. If justified by paired evidence, prioritize the positive dive on a checked production-like profile with the same shared work ceiling; preserve existing controls and race behavior. A separate high-level production decoder could infer bounded outputs and monotone sum/min constraints, construct candidates mathematically and lift auxiliaries, but neither active implementation currently supplies that decoder.

**Improve LymphoSAT:** Replace per-literal vector watch objects with compact arrays/pools and measure parsing, attachment, propagation and output separately. Add an explicit shared watch/time budget and cancellation during parsing/greedy propagation; the current implementation can run until external termination. Treat the greedy near-model as phases for an existing generic fallback instead of declaring the family solved when local repair misses. Recover actual production variables and monotonic arithmetic constraints rather than rely only on variable order/positive phase; retain full original-clause validation. Validate all header/literal bounds, declared counts and token termination; the current buffered parser overwrites the declared clause count and assumes well-formed tokens.

**Certificates and evidence:** SAT-only full parsed-CNF validation. A direct two-variable fixture confirms positive-branch rollback and a valid model; a satisfiable four-variable fixture demonstrates UNKNOWN after an earlier greedy commitment. An empty-clause control declines. Current Wassat flat-lucky focused checks all pass:17examples cover roots, opposite dives, watch capacity/admission and bounded interruption. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/040-graceful-production.json`.

### 41. grandtour-puzzle

Build a row-to-column incidence graph, run Hopcroft-Karp, and extract deficient rows and their neighbor columns by alternating reachability from unmatched rows. Emit row constraints, proposed pairwise column conflicts as RUP, column AMOs by all-subset cutting-planes aggregation (column size<=18), then a final row/capacity sum. Runtime returns UNSAT after writing the proposed proof without locally replaying RUP. No SAT path.

**Underlying structure:** Hall's condition requires |N(U)|>=|U| for every set of rows U when each row selects a distinct capacity-one column. A deficient subset yields a short counting witness; total component or whole-system counts can miss such subsets. The argument requires actual entailed row demands and actual column capacities, not merely a plausible support/incidence graph.

**Wassat coverage:** matching_balance.w checks exact-one edge-incidence components for unequal bipartition sizes and validates all required pair exclusions; matching_parity.w handles odd closed components after checked propagation/binary resolution. coloring.w checks complete AMO resource cliques covering disjoint choices and aggregate capacity. These overlap the mathematical infrastructure but do not perform arbitrary Hall-subset matching or recover this ASSAT arc/complement grammar. Current fast refutations lack the exported PBcertificate. The coloring helper also requires choices of residual width>=3, unlike the tiny two-choice probe.

**Learn for Wassat:** Add a shared bipartite row/resource matching interface with explicit provenance for every demanded row and every resource AMO. Extract a minimal Hall witness instead of relying only on global totals. Generalize signed-literal complement/implication recovery and checked reachability-row derivation, then reuse common counting certificates across PHP, routing and Grand Tour. Check/log every necessary RUP premise before using Hall deficiency as a trusted fast verdict; a file of hoped-for RUP steps is only a proof proposal.

**Improve LymphoSAT:** Validate required row and pair-exclusion consequences before returning UNSAT. The reproduced missing-column-conflict case shows the detector does not establish these premises. Replace exponential all-subset AMO aggregation with a qualified polynomial PB/pbc clique derivation and share it with other counting specialists. Recover signed units and structural node layers instead of hard-coded upper-half intervals of length50/60; preserve a complete proof for every inferred row. Bound matching recursion, column recovery and proof size with a shared deadline, and check proof write/close failures before publishing. Retain empty clauses and declared-count/bounds validation so original proof IDs refer to the actual input stream.

**Certificates and evidence:** Fresh3row/2column proof passes independent VeriPB (318B); balanced3x3declines. Removing all column exclusions leaves an explicit satisfying all-arcs witness, but direct specialist still returns UNSAT with an invalid318Bproof; VeriPB rejects its first derived conflict. Tiny direct probe does not establish matcher admission or a verified-portfolio wrong verdict. Exhaustive kernel comparison on every bipartite graph with1..4rows/columns independently checks maximum matching size and deficient-neighbor witnesses. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/041-grandtour-puzzle.json`.

### 42. greentao

For shorter positive clauses, greedily build a sparse false-color hitting set of negative scopes while banning choices that would make a positive scope allfalse. Try12seeds and repair partial failures; then biased random restarts with weighted min-delta/probSAT repair and bounded depth finishing near<=4violations. Medium asymmetric1000..6000variable cases reserve remaining time after a240second SLS slice for phase-guided CDCL. All successful candidates are checked against every clause; no UNSAT output.

**Underlying structure:** Let F be the false-color set. Every all-negative clause requires F to hit its scope, while no all-positive scope may be contained in F. This is a constrained hypergraph transversal problem, whether or not the scopes are arithmetic progressions. Different positive/negative progression lengths break color-complement symmetry unless the actual signed scope sets match. Prime-index structure could supply modular seeds, but it is not decoded by this active specialist.

**Wassat coverage:** arithmetic_coloring.w already extracts monochromatic scopes, validates APs in index or first-prime values (plus Schur/Pythagorean/Ramsey), and uses bounded exact high-level search. Default backend is native two-watch monochromatic propagation, with count/scan alternatives, complete SAT replay and fast-only UNSAT. Limits include700elements/200k scopes and a50ms CLI budget. Prime-value recognition starts at2 and does not try stripped-prime offsets or arbitrary relabelings. Wassat weightedSLS and phase-guided bounded repair already overlap generic stochastic/CDCL pieces; no matching sparse-transversal initializer was found.

**Learn for Wassat:** Add the sparse constrained-transversal initializer as a model seed for existing native SLS, with incident-only updates and complete model replay. Broaden checked prime/AP value recovery to small-prime offsets or a recovered value map, and distinguish mathematical recognition from generic monotone-hypergraph search. Combine near-model exchange chains/ejection neighborhoods with the existing exact threat propagator; only adopt a schedule after paired held-out measurements against current SLS/arith workers.

**Improve LymphoSAT:** Maintain cover/danger/ban scores incrementally or with a priority queue; current greedy seed repeatedly rescans all uncovered scopes and all candidate occurrences. Update weighted break/make scores rather than rescan every candidate occurrence, and reuse buffers across restarts as current Wassat already does. Include seed construction and bounded repair DFS in one shared deadline; their inner loops currently lack elapsed-time polling. Recover prime/AP structure for modular constructions only when validated, rather than label all sorted monotone hypergraphs as Green-Tao. Use an existing CDCL completion engine with shared phase transfer/budgets rather than another standalone engine; keep its SAT-only certificate boundary explicit. Remove unused matcher regions or wire and qualify them; metadata declarations are not active admission.

**Certificates and evidence:** SAT-only complete parsed-clause replay, with strict declared clause count and bounds but permissive SATLIB trailer handling. Two fresh actual-prime3/4APfixtures, one with first two primes stripped, yield independently checked full models. Existing Wassat arithmetic-coloring6focused examples pass; these exercise AP/Schur/Ramsey and symmetry controls, not prime-offset competition instances. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/042-greentao.json`.

### 43. hamiltonian-cycle

First try eight embedded FHCP Hamiltonian tour seeds selected by vertex count; validate every vertex and consecutive recovered directed edge, assign counter orbits and replay CNF. Otherwise generate randomized undirected degree-two covers with degree propagation and one-decision rollback; extract cycles and retain covers satisfying inferred mod60/105/420residues. Orient the distinguished cycle both ways, lift counter labels, whole-CNF propagate/false-fill and replay. Up to5k/20kattempts and outer560seconds. GenericSLS code is disabled by literal false; no UNSAT path.

**Underlying structure:** A degree-two cover is a disjoint union of cycles, not necessarily one Hamiltonian cycle. Counter successors constrain ordinary cycles to return to their starting label; a distinguished root closure has a different residue condition. The source uses maximum modulus inferred from width, but actual Boolean successor orbits can have shorter periods or a transient prefix. Exhausting all1408counter states confirms widths7/8/10have zero-seed periods20/5/20rather than60/105/420and some states have one-step tails. Therefore width-based divisibility is a conservative proposal filter, not the complete orbit characterization. Additional clauses remain authoritative.

**Wassat coverage:** Wassat has checked graph-specific Hamiltonian search in stedman.w and knight_tour.w and generic exact-one block CSP. Stedman decodes call/type transitions with compact labels; knight tour decodes a position/square matrix. Neither recovers these reverse-paired arc variables and mixed-radix counters, nor searches cycle covers with residue-aware repair. Circular graph-label swapping in cyclic_walk.w is a different problem. Stored witness tables are not equivalent to an input-derived general constructor.

**Learn for Wassat:** Add a clean-room reverse-arc/counter transition decoder and calculate actual permitted successor orbits from validated gates; use full-CNF lifting as the final SAT gate. Search degree-two covers with cycle-merging2opt/alternating-edge moves and residue-aware gains instead of repeatedly drawing unrelated covers. For cubic graphs, exploit the complement relationship between a2factor and a perfect matching; consider a qualified matching/blossom initializer, then repair cycle structure. Share bounded original-CNF completion and model checks with existing tour workers; keep data-backed tour reuse separate from algorithmic family coverage and licensing.

**Improve LymphoSAT:** Replace full state/degree vector copies at each trial edge with an undo trail and maintain undecided-edge candidates incrementally. Compute valid cycle-state orbits, including shorter periods and transient exclusions, rather than infer all constraints from bit width alone. Add deadline/cancellation checks inside2factor construction, graph recovery and model propagation; the outer attempt loop does not bound one long attempt. Reuse watched/occurrence propagation instead of repeated whole-CNF passes and repeated labels/model allocations. Recover reverse arcs structurally, validate duplicate directed arcs and counter gates, and avoid assuming odd/even variable pairs or the first-clause offset. Keep embedded known-tour data provenance/license explicit; it is a checked finite witness proposal, not evidence that randomized search solves the full family. Validate strict DIMACS termination/bounds/counts and retain empty clauses.

**Certificates and evidence:** SAT-only full parsed-CNF replay. Fresh60variable six-cycle with exact successor truth tables and exempt root-incoming closure gives an independently checked model through randomized cover recovery, without any six-vertex stored seed. An unmodified-source kernel tests all128+256+1024counter states and a genuine degree-two propagation/cycle extraction control. No full FHCP benchmark replay or stored-seed success-rate claim. Parser drops empty clauses, does not enforce counts/bounds and can loop on truncated clauses. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/043-hamiltonian-cycle.json`.

### 44. hanoi

Generate the canonical recursive three-peg plan, independently simulate stacks to choose moved disk and actual source/destination support objects, then assert every action-choice literal. Run watched propagation/CDCL on originalCNF with those root assumptions for30seconds; if unsuccessful, rebuild unrestricted guidedCDCL for550seconds. Wide action variables get activity/phase boosts, with restart constants keyed partly by nvars4968/1931and wide polarity. Every SAT candidate passes original clause replay; internal contradictions become UNKNOWN.

**Underlying structure:** For a single tower on three pegs, movingn disks needs2^n-1moves by induction: move the n-1tower aside, move the largest disk, then move the small tower onto it. The encoding's object is the disk/peg directly supporting a disk, so an action source/destination is not always a peg. Recovering this support chain, action identity and time order is the central semantic work. A plan proposal is safe with full CNF completion/replay; a horizon lower-bound UNSAT claim would additionally require a complete checked transition contract and a proof.

**Wassat coverage:** No equivalent Hanoi action-triple/time-path/support-chain constructor was found. Wassat reconfiguration.w decodes token jumps between graph independent sets, which is a different state space; block_csp.w requires every Boolean variable in positive exact-one domains and does not match mixed state/action auxiliaries. Existing Stedman/knight workers already demonstrate the reusable pattern of semantic primary assumptions, bounded original-CNF completion and full model replay, while generic Wassat CDCL supplies a stronger shared fallback than this small standalone engine.

**Learn for Wassat:** Implement an input-derived action/support/time decoder and canonical plan generator, then feed its assumptions to existing bounded original-CNF completion. Share signed domain identity and temporal-state matching infrastructure across planning specialists; distinguish disk-support objects from peg positions in the lifted model. For noncanonical states, generate a verified state-space plan or bidirectional symbolic search; for longer horizons, handle legal padding explicitly rather than assume the optimal horizon template.

**Improve LymphoSAT:** Replace the dense(3T)^2group-edge matrix with sparse group-pair incidence counters/DSU; the current memory cost grows quadratically in the exponentially growing horizon. Guard disk count and shifted2^n before arithmetic/allocation; cap recovery work and share a deadline with completion/fallback. Emit state variables directly from simulated supports where the transition encoding is validated, using propagation only for remaining auxiliaries. Reuse an existing heap-based/reducing CDCL engine; current branch selection scans all variables and the learned database is never reduced. Use structural cost/admission features rather than exact nvars4968/1931restart tuning; measure plan recovery, propagation and fallback separately. Validate DIMACS bounds/counts/termination and retain mandatory original-model replay after every structural proposal.

**Certificates and evidence:** Two independently generated four-disk/15step CNFs, including arbitrary variable renaming, sign flips and clause/literal shuffling, activate the direct decoder and produce complete checked654variable3948clause models. An independent canonical support/stack simulation supplies a full witness and validates all generated clauses before either run. These are controlled factored planning fixtures, not competition-scale timing or general Hanoi variants. NoUNSAT certificate. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/044-hanoi.json`.

### 45. heule-nol

For exactly473declared groups, first try six global permutations of an embedded473entry witness; then force hints and repair at the high-level cell-color level. Other supported sizes use greedy/random recoloring. Incremental per-edge color counts and a dense bad-edge list score the six possible recolorings of a violated triple. Every candidate is lifted to one color per active cell, all inactive cells false, and replayed against parsedCNF. SAT-only, default585second local-search allowance.

**Underlying structure:** With positive cell domains and negative color nogoods, selecting one true color per cell is sufficient because turning other color bits false cannot violate negative clauses; positive hints must be respected. A complete three-color block on a triple forbids exactly monochromatic colorings. A single observed color clause is weaker: treating it as all three prohibitions overrestricts search, which can miss SAT even though final model replay protects publication. Geometry-specific No-L constructions are a separate opportunity; the active algorithm is a colored hypergraph search plus finite stored witness.

**Wassat coverage:** Wassat arithmetic_coloring/NAE workers solve two-color monochromatic hypergraphs, not three-color domains. domain_sparse_decode.w supports AMO-free positive domains only with negative binary exclusions, and domain_walk handles binary-domain CSP moves; neither accepts these negative ternary nogoods. latin_csp.w requires complete Latin relation tables, a different relation than three forbidden monochromatic tuples. Generic weightedSLS remains available but is not equivalent high-level recoloring. No dedicated No-L geometry/witness constructor was found.

**Learn for Wassat:** Generalize the existing domain-search infrastructure to small-arity forbidden color tuples, preserving one selected value per cell and incident-only score updates. Recover and validate L-shape geometry before applying a mathematical grid construction; independently derive a compact rule or bounded row/frontier DP rather than replicate the stored473color table. Retain each actual forbidden color mask when projecting clauses; partial-color variants need a general colored hyperedge relation rather than an all-colors assumption.

**Improve LymphoSAT:** Check completeness of color-clause blocks or keep their actual forbidden-color masks; the reproduced partial-block SAT miss shows current search is unnecessarily restrictive. Use fixed six-move scratch and selection instead of allocating/sorting a vector on every local move; maintain cached incident delta scores when useful. Recover domains/colors from clause incidence instead of consecutive triples and color indices modulo3, and recover geometry independent of variable numbering. Track data provenance/license separately from solver code before redistributing the embedded witness; measure constructive-rule coverage separately from table reuse. Use a single deadline including parsing, witness checks and verification; normalize clauses, retain empty clauses and validate DIMACS bounds/counts.

**Certificates and evidence:** Fresh three-cell/full-three-color fixture gives a complete checked SAT model. A partial color block with all cells fixed to another color has an independently checked SAT witness but returns UNKNOWN, reproducing the overrestriction. Unmodified recoloring kernel matches independent full recomputation for all729six-cell colorings and13122recolor moves. No full size11grid or stored-witness performance replay. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/045-heule-nol.json`.

### 46. hgen

Binary-majority path proposes an iterative-Tarjan2SAT model, checks the fullCNF, then uses proof-logging first-UIPCDCL with binary implication lists, blockers, heapVSIDS, minimization, phase saving, Luby restarts and learned-clause deletion. Other paths run incremental critical-variable/break counts and table-driven probSAT with zero-break priority, mixed-width exponents, biased clause selection and alternating random/best-plus5..20percent-noise restarts. PAWS-like weights affect which unsatisfied clause is selected, not the break scores. SAT always checked; UNSAT only from the CDCL branch.

**Underlying structure:** A satisfiable binary subsystem does not imply satisfiability of its longer residual clauses, so the SCC model must be replayed and misses completed by search. Random/regular kSAT has no exact reduction supplied by this implementation. Break-based probability and configuration-checking weighted-make/break search explore different landscapes; observed generator-specific rankings cannot be assumed to transfer across families.

**Wassat coverage:** Wassat already has native CCAnr-style weighted scores, configuration checking, incremental critical-clause state, best-assignment retention, phase exchange and bounded repair. preprocess.w has iterative binary-SCC substitution with proof provenance; the general solver already has binary-specialized propagation, firstUIP, minimization, LBD/database control and proof modes. No HGen-specific mathematical decoder is missing because this active specialist supplies none. Its unweighted break/probSAT exponent portfolio is a useful alternative to benchmark within existing infrastructure, not a reason to duplicate a solver.

**Learn for Wassat:** Experiment with a bounded table-driven probSAT arm sharing parsed storage, verification and cancellation; compare partial restarts and clause-selection weights independently from exponent choices. Profile normalized fixed-occurrence kernels against current CCAnr on paired random/structured controls; keep the current default until independent held-out results justify a change. Recover community structure only if the input actually supports useful separator/block reasoning; a family name or clause count is not a mathematical specialist.

**Improve LymphoSAT:** Normalize repeated/tautological clauses and validate strict DIMACS, including empty clauses, bounds and all trailing content, before constructing critical-variable bookkeeping or proof IDs. Guard psG clause width before its fixed16score array; the runtime parser accepts wider input even though matcher targets widths2..4. Reuse bounded learned storage or compact reclaimed literals: deletion marks clauses but never reclaims litpool, and its100Mliteral guard does not bound all watch/reason/metadata memory. Poll cancellation/time inside propagation, conflict chains, minimization and reduction; checking only selected outer conflict boundaries does not bound one long phase. Keep proof write/flush failures in the verdict path; early root-proof fopen results are unchecked and the general proof stream close status is ignored. Separate named-version broker evidence from actual source (selected v22b payload still labels itself v20); independently reproduce any claimed gains before promotion.

**Certificates and evidence:** Independent VeriPB accepts a pure binary contradiction proof126B and mixed4pigeon/3hole proof223B. SCC and pure3SLS SAT controls give complete checked models. On120normalized mixed3/4clauses,3000random flips have3001complete independent state recomputations confirming counts, critical variables, unsatisfied list/index and break scores. This does not qualify long-run minimization/deletion/restart behavior or the README broker results. Parser drops empty clauses and stops after its declared nonempty clause count; retained-clause replay is not strict whole-input validation. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/046-hgen.json`.

### 47. hidoku

Direct path: high-level arc consistency over value-to-cell domains, clue/negative-unit restrictions and cell/value singleton exclusion. On contradiction, export per-cell pairwise RUP AMOs, polynomial PBclique aggregation, each-value occurrence RUPs, total-capacity-to-per-value AMOs, then RUP deletions and contradiction. SAT path tries16serpentine symmetry/reversal candidates, then bounded clue-aware DFS up to64cells with Chebyshev reachability and onward-degree ordering; full-primary clause filtering precedes auxiliaryDPLL and complete replay. A direct<=36cell fallback adds value AMOs and runs bounded tree-RUPDPLL. GenericProofDPLL is unused by main.

**Underlying structure:** Bidirectional value supports plus at least one occupied cell force every value1..Mto occur. At-most-one value percell gives total occupancy<=M, so Mnonempty value columns must each have exactly one placement. This permits value uniqueness even without explicit value-ALO/AMO clauses. One missing cell ALO does not invalidate this argument when the other necessary premises remain. Arc consistency is incomplete for Hamiltonian-path/all-different puzzles; path construction and complete search address different cases.

**Wassat coverage:** path_cover.w already implements the central occupancy/uniqueness/arc-consistency refutation, checking all cell ALOs, every within-cell exclusion through original binary implication reachability, and predecessor/successor supports independent of board geometry. It filters both axes and validates cancellation/work limits. Current scope:width<=64,vars<=32768,clauses<=65536,4Mwork, plus primary/auxiliary ratio admission; CLI/scout chooses width from max_clause_size. It is fast-only, cell-major, refutation-only and stricter about all cell ALOs. No equivalent exported PBproof or Hidoku serpentine/clue-aware model constructor was found. Knight-tour search has different graph/layout semantics.

**Learn for Wassat:** Attach a checked common PBcapacity certificate to existing path-cover recognition, retaining actual AMO/support clause provenance; this polynomial clique aggregation is also useful for Grand Tour's exponential AMO proof. Add transpose/incidence-based primary-axis recovery and constructive king-grid path proposals, then reuse bounded original-CNF completion. Retain Wassat's explicit premise checks before any fast UNSAT verdict; an externally rejected proof proposal is not equivalent to internally established contradiction. For stronger all-different filtering, use bounded Hall matching or interval/clue reachability with independently checked explanations; AC fixed points alone do not settle the puzzle.

**Improve LymphoSAT:** Validate required AMO consequences before publishing UNSAT, or explicitly return only a proof proposal until replay succeeds. The missing-AMO SAT control reproduces the boundary. Slice proofs to needed cells/values and derive capacities lazily; the full scaffolding has cubic-in-cell-count pair/RUP volume, which can be very large at20x20. Reuse watched propagation and shared time/node budgets in auxiliary completion; current AuxDPLL is unbounded and repeatedly scans the wholeCNF. Use queued support updates and all-different matching rather than full domain sweeps where profiling justifies it; keep large-board clue search separately bounded. Generalize the checked support graph beyond fixed king geometry only after recovering actual adjacency; preserve original-clause filtering for every SAT candidate. Strictly retain empty clauses, bounds/counts and complete token termination; check proof write/close failures and distinguish verifier-gated proof proposals from trusted verdicts.

**Certificates and evidence:** Three fresh3x3proofs independently pass VeriPB: normal/transposed nonadjacent clues and one missing cell ALO, about14.1kB each. Normal/transposed clue-free fixtures yield complete checked models. Removing all cell AMOs leaves an explicit all-primary-true SAT witness, but direct worker emits UNSAT; VeriPB rejects its first assumed AMO. Tiny direct probes outside matcher do not establish verified-portfolio wrong verdicts. Current Wassat path-cover11examples pass, including a removed-AMO-premise regression. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/047-hidoku.json`.

### 48. hypertree-decomposition

Turn original hyperedges into dual graph vertices and degree-two original vertices into dual edges. Recursively choose width<=Wseparator covers for boundary edges, branch on uncovered edge endpoints, prune by a greedy matching lower bound and prefer balanced components. Bounded500/800cover and160/240additional-separator candidates; memoized failed component/boundary masks. Convert a found hypertree to an elimination order and row covers, compute filled arcs and permission closure including pure-improved transitive arcs, fill prefix-counter auxiliaries, then check every original clause. SAT-only, nominal520second search deadline.

**Underlying structure:** Hypertree width counts selected original hyperedges covering a bag, not ordinary primal-graph bag size. In the2regular case a boundary original vertex is a dual edge and covering the boundary becomes a dual-vertex-cover problem. A valid hypertree additionally needs original-hyperedge containment, connected occurrence subtrees and the special condition relating a node's cover to vertices occurring below it; a generic covered-bag decomposition is insufficient. The source correctly treats p as permission closure rather than exact bag membership. On bipartite dual graphs, maximum matching gives an exact minimum boundary vertex-cover size; a single minimum cover cannot replace separator-choice search without a completeness argument.

**Wassat coverage:** No current Wassat hypertree cover/permission decoder or2regular dual-separator constructor was found. treewidth.w decodes ordinary graph elimination and proves lower bounds via checked minors/exact bounded search; its bounds cannot be transferred directly to hyperedge-cover width. Existing counter/finite-domain/model-completion components are reusable, but generic CDCL or a graph treewidth recognizer is not equivalent family capability.

**Learn for Wassat:** Implement a checked hypergraph/cover/order decoder and2regular dual graph constructor; preserve permission semantics and validate every original gate/counter clause in lifting. For a verified bipartite dual graph, use maximum matching to strengthen the greedy boundary-cover lower bound and guide cover branching. Retain multiple admissible covers when separator balance depends on the choice. Share separator-state search with explicit work/memory budgets and exact-mask keys, plus an independent hypertree witness validator before expensive CNF lifting. Generalize beyond degree-two incidence by solving boundary hyperedge-cover subproblems directly; do not reinterpret arbitrary hypergraphs as ordinary dual graphs.

**Improve LymphoSAT:** Bound failed-mask cache memory and recursive inner cover enumeration, not just a clock every2048decomposition calls; capped candidate enumeration means a miss is heuristic. Recognize bipartiteness and use stronger matching/cover bounds where valid; decompose boundary components and reuse bitset work buffers. Use incrementally maintained permission/arc queues rather than repeated all-node closure sweeps; profile this separately from separator search and counter filling. Check full encoder contracts or maintain robust candidate-only semantics; stride/count layout recovery is not a semantic equivalence proof. Give alternate decompositions/orders a chance when the first found witness fails original-CNF lifting; current solver stops after one root decomposition. Validate DIMACS format/counts/bounds, offset representation and trailing tokens; keep full original-model replay and never turn capped search failure into UNSAT.

**Certificates and evidence:** SAT-only complete retained-CNF model replay; no UNSAT export. On every simple dual graph with3..5vertices, no isolated vertex and at least2edges, widths1..3give2439requests. Actual unmodified separator kernel returns1777witnesses, all independently validated for width, coverage, running intersection and hypertree special condition;662misses remain UNKNOWN, not proven infeasible. This is not a full CNF decoder/permission/totalizer replay or competition runtime test. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/048-hypertree-decomposition.json`.

### 49. independent-set

Recognize binary-word adjacent-transposition distance-two path/cycle graphs by exact edges and count, preserving Hamming weight. Current n8/n9 paths first use four embedded finite independent-set tables; other n<=9 cases use exact complement-clique searches by weight layer. Z-channel confusability graphs use minimum-degree greedy restarts up to1024vertices. Generic fallback is bounded complement maximum-clique search with coloring bounds. Retain exactly K vertices, fill the saturating one-hot prefix counter and replay all clauses. SAT-only; insufficient stored/constructed set or exact alpha<K returns UNKNOWN.

**Underlying structure:** An independent set is a code avoiding the recovered confusability relation. Transpositions preserve Hamming weight, so independence numbers sum across layers. Z-channel adjacent words satisfy max(number of1to0,number of0to1)<=1. A clean seed construction groups words by sum((i+1)*bit_i) modulo n+1: every confusable pair changes checksum by nonzero signed i or i-j, hence every class is independent and some class has size at least ceil(2^n/(n+1)). This construction is a seed, not an optimum or a demonstrated improvement over the existing heuristic. Stored witnesses establish only achievable cardinalities.

**Wassat coverage:** threshold_cover.w already decodes demand supports from counter circuits and computes exact independent-set bounds with packed62bit component search, clique-cover pruning, negative-unit filtering and directed-support reductions. It refutes instead of retaining SAT witnesses, within <=4Mvars/16Mclauses, component<=1240 and3Mnode limits, with a default3sfast-only CLI arm. count_cover.w is a related monotone-circuit count refuter, not a word-graph SAT constructor. Existing packed search should be extended to retain witnesses rather than duplicated.

**Learn for Wassat:** Retain independent-set witnesses in the existing packed exact kernel, then lift actual recovered BDD states and check original clauses. Recognize genuine graph symmetries/weight layers and solve independent components separately; exact edge validation should precede any specialized bound. Use independently derived checksum classes as deterministic Z-channel seeds, followed by bounded exchanges; measure against current greedy search before adopting. Add shared proof provenance for exact component bounds if refutations are to enter proof mode.

**Improve LymphoSAT:** Replace repeated aux_count and layer_var prefix summation with monotone arithmetic inversion and precomputed offsets. Reuse bitsets and fixed scratch in clique search instead of repeatedly copying/filtering vectors; maintain greedy degrees incrementally. Separate stored-witness coverage from exact search and mathematical upper bounds; K above a table length is not an infeasibility result. Charge minimum32greedy restarts, parsing, graph recovery and verification to one cancellable budget; validate strict DIMACS counts, bounds and empty clauses.

**Certificates and evidence:** Fresh N8/K2 BDD fixture yields a complete checked model; N8/K5 has alpha4 and returns UNKNOWN. Independent physical transposition/Z-distance checks cover32720graph pairs; six small layer-alpha comparisons agree with brute force; all323words in four stored sets satisfy physical confusability exclusions. Independently derived checksum classes pass319486directed neighbor checks for n2..12. No table data copied into Wassat and no optimum/performance claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/049-independent-set.json`.

### 50. independent-set-reconfiguration

n<=50 enumerates size-k independent sets, caches token-jump neighbors, builds reverse distances and searches an exact-length self-avoiding path. For large row-major q-by-q queen graphs with k=q-1, encode one column per occupied row plus missing-row/column holes; removing a queen leaves four possible row/column hole intersections, three new cells. Use bidirectional BFS or randomized exact-length paths. Intermediate regimes use randomized self-avoiding paths and greedy tails. Lift one path, run30whole-CNF propagation passes, false-fill and replay every parsed clause. No UNSAT path.

**Underlying structure:** A token jump replaces exactly one selected vertex while preserving independence. Exact requested length with no repeated state differs from shortest reachability; an early target cannot generally be padded. For q-1nonattacking queens there is exactly one missing row and column, giving a compact complete move neighborhood after a removal. This compression generalizes only when the checked conflict graph actually supplies the required clique partitions.

**Wassat coverage:** reconfiguration.w already decodes repeated graphs/endpoints, searches native packed TJ states with A* and an admissible missing-token bound, tries longer randomized simple paths, lifts/replays original CNF and polls bounded resources. Earliest-depth state dedup is shortest-reachability search, not complete history-sensitive exact-length search; shorter goals decline then try walks. Exhaustion can refute only after reconfiguration_verify.w checks actual transition/add/remove/frame/AMO premises. Existing arm has <=512vertices,<=128states,131072visited cap and default2sbudget. Missing additions are compact queen-hole states, longer supported horizons and complete bounded exact-length small-graph search.

**Learn for Wassat:** Reuse the current decoder and model lifter with a checked queen-hole state representation; generalize to near-full occupations of verified row/column clique partitions. For small configuration graphs, combine reverse-distance pruning with exact-length self-avoiding search while retaining history in completeness claims. Keep refutation premises separate from candidate-only geometry recognition and preserve current transition verifier.

**Improve LymphoSAT:** Bound independent-set enumeration, reverse BFS, neighbor cache memory and their inner loops; the8sDFS timer does not cover preparatory work. Replace30whole-CNF sweeps with queued propagation and bounded original-CNF completion; retry alternate paths if one valid graph path fails extra clauses. Recover repeated graphs independently of exact clause order, verify unique complete queen attacks and support general vertex permutations. Use one deadline through parsing, recovery, BFS/walk, lifting and replay; retain empty clauses and validate headers/counts/literal bounds.

**Certificates and evidence:** Independent enumeration over64four-vertex graphs checks2688small exact-length requests;1248returned paths all satisfy endpoints/cardinality/independence/TJ/uniqueness. Eighty-eight q4/k3queen compact controls agree with independent configuration BFS; these bypass the large-board main admission. A full C5/two-jump encoding produces a complete checked30variable model. Current Wassat reconfiguration21examples pass. Unused CDCL helper is not credited as active certification. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/050-independent-set-reconfiguration.json`.

### 51. influence-maximization

Evaluate progressive threshold activation to a least fixed point with Python integer bitsets. Greedily add seeds, improve with exact one-swaps, use randomized restricted candidate lists and20kstep annealing. Every promising seed runs full-CNF UP, false-fill and complete parsed-clause replay; failed seeds are cached and search continues. Default540s starts after parsing/recovery. SAT-only.

**Underlying structure:** Monotone progressive activation has a unique least fixed point, so asynchronous closure and synchronous closure agree eventually. Fixed point can exceed a bounded time-horizon target; full CNF replay must remain the publication gate. Arbitrary deterministic fixed thresholds can have synergistic marginal gains and need not be submodular, so the classical greedy1-1/e guarantee cannot be assumed. Removing a seed requires recomputing least activation or valid provenance: cycles must not self-support.

**Wassat coverage:** No dedicated recovered diffusion graph, finite-time threshold simulation or target-set selection worker was found. counter_cover.w offers incremental fixed-budget cover swaps and signed cardinality decoding; count_cover.w is a bounded monotone-circuit count refuter. model_circuit.w and sorting/gate infrastructure can support checked model lifting but are not a temporal influence optimizer.

**Learn for Wassat:** Build a checked threshold/time-layer decoder and optimize seed sets in the recovered domain; validate every candidate against original CNF. Use event-queued threshold crossing and incremental addition trials; seed removal needs fresh closure or sound activation provenance. Exploit threshold-one source-SCC structure for constructive seeds and resistant inactive cores for lower bounds, respecting whether the requested target is partial or full activation. Reuse existing fixed-budget swap infrastructure and a shared candidate/model-completion budget rather than another generic Boolean engine.

**Improve LymphoSAT:** Validate gate semantics, threshold symmetry, cardinality outputs and time horizon instead of sorted-support prefix ranks and variable-position targets. Handle empty/all-seed budgets before selecting add/remove candidates; direct boundary probes currently throw IndexError. Use queued propagation for model completion and bounded closure/trial caches; profile recovery, diffusion scoring and auxiliary completion separately. Start the deadline before parse/recovery and poll one-swap/annealing inner loops; preserve strict DIMACS bounds/counts/empty clauses.

**Certificates and evidence:** On all64directed three-node graphs,64threshold triples and eight seed sets,32768comparisons show both closure kernels agree with independent synchronous fixed points. Two direct boundary searches k=0 and k=N with every candidate rejected raise IndexError in annealing; not a reproduced full-main/matcher defect. Independent17variable threshold/budget/spread encoding yields a complete checked model. No UNSAT certification or performance claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/051-influence-maximization.json`.

### 52. interval-matching

Build group/resource incidence and run Hopcroft-Karp. If deficient, alternating reachability extracts Hall subset U with |N(U)|<|U|. Derive resource AMOs by polynomial cutting-planes recurrence from actual pair-clause IDs, use literal axioms for singleton resources, and sum with original ALOs. Full matching returns UNKNOWN; no SAT construction. Despite its name, the matching kernel is general bipartite matching, not interval greedy.

**Underlying structure:** Every group demands a selected value; each checked resource clique permits at most one. A Hall-deficient subset contradicts this even when total resources exceed total groups. Unlike the earlier Grand Tour proposal, this worker checks all required clique premises before proof publication. Contiguous numbering is a decoding restriction, not part of Hall theory.

**Wassat coverage:** coloring.w::wassat_amo_cover_or_rphp_unsat checks signed choices and complete exclusion components but uses aggregate covered-row/resource counts. It misses proper Hall subsets with globally sufficient capacity in the tested controls. matching_balance.w uses special signed-incidence invariants, not arbitrary Hall matching. Existing resource recognition can feed a shared matching/certificate layer; no need to duplicate another family-specific graph decoder.

**Learn for Wassat:** Extend existing checked choice/resource incidence with bounded Hopcroft-Karp and alternating Hall witness extraction. Attach shared polynomial PBclique aggregation using original pair/ALO IDs; reuse it across Grand Tour, Hidoku and pigeonhole workers. If actual interval/convex structure is recovered, specialize matching and deficient interval extraction; do not infer intervals just from contiguous variable IDs. Keep complete clique checks and independent replay before promoting an UNSAT path to proof mode.

**Improve LymphoSAT:** Recover arbitrary row/value permutations and supported size-two ALOs instead of contiguous long rows; maintain polarity and exact clause provenance. Bound graph construction, matching/recursion and proof volume under one cancellable memory/work budget. Validate strict DIMACS and proof write/flush/close completion; parser currently lacks full bounds/count/termination guards. After a full matching, try a matching-derived candidate with original-CNF auxiliary completion, while allowing extra original constraints to reject it.

**Certificates and evidence:** Four independently accepted VeriPB proofs: Hall6/5with8total groups and40resources, signed/shuffled equivalent, singleton-assisted obstruction, and deletion of an irrelevant conflict. Removing a required K6clique pair causes UNKNOWN. Full-matching control also declines. Wassat aggregate helper returns0 on normal/signed Hall-subset cases; this is a helper coverage comparison, not a whole-solver wrong answer or competition result. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/052-interval-matching.json`.

### 53. karatsuba-multiplication

Try three fixed operand pairs in both orientations when widths fit; each trial copies the formula, appends operand units and runs25sCDCL, with a complete original-clause model check. Then generic min-break/max-make local search for3s and first-UIPCDCL for585s. All internal UNSAT outcomes become UNKNOWN. Fixed seed success is model reuse through a finisher, not input-derived factorization.

**Underlying structure:** Factoring CNF requires a*b=T with width/nontriviality restrictions and auxiliary circuit constraints. Recovering the target and arithmetic blocks allows bounded number-theoretic factorization; enumerating a few calibrated operand pairs does not solve that mathematical problem in general. Espresso-minimized multiplier/adder relations may require local truth-table/relation recovery rather than ordinary two-input gate matching. Learned clauses while seed units are appended are seed-conditional and must never be reused as unconditional consequences without guarding assumptions.

**Wassat coverage:** fermat.w already recovers a target from canonical square-difference and a separate canonical ToughSAT output-tail encoding, applies bounded Pollard-rho/factorization and checks lifted models. Its equal-width/constant/tail contracts do not cover arbitrary Espresso-Karatsuba blocks or this odd-operand signature. backdoor.w already has stored-candidate finishers, which should not be credited as general arithmetic recovery. Existing CDCL/SLS substantially covers the generic fallback.

**Learn for Wassat:** Extend checked arithmetic relation recovery to minimized block truth tables, recover actual fixed product bits and reuse bounded factorization/model lifting. Use one incremental assumption-capable completion engine for factor candidates, keeping seed-dependent learned clauses guarded or local. Measure block detection, target recovery, integer factoring and auxiliary completion independently on unseen operand values and variable permutations.

**Improve LymphoSAT:** Replace three calibrated pairs with input-derived target factorization and verified operand/gate layout recovery; report table/seed reuse separately from general coverage. Share parsed storage and root propagation across seeds. Six25sseed trials plus3sSLS and585sCDCL can exceed the intended competition allowance. Use a decision heap instead of scanning every variable, incremental SLS break scores and reclaimed learned storage instead of retaining deleted clause vectors indefinitely. Poll time within propagation/analysis and strict-parse all bounds, counts and terminators. Preserve conservative no-UNSAT policy unless a replayable proof is produced.

**Certificates and evidence:** Fresh generic four-variable SAT control has a complete original-CNF model, independently checked and brute-forced. Contradictory units return UNKNOWN after the generic3sSLS slice. These controls do not qualify the calibrated seed path or a real Karatsuba factor recovery. No proof is emitted and no competition timings independently reproduced. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/053-karatsuba-multiplication.json`.

### 54. knights-problem

Read stored closed tours for even n12..30, try dihedral symmetries/reversal and, for dense matrices, cyclic alignment against units. Sparse/CP paths try valid2opt segment reversals; sparse additionally takes a deterministic randomized multi-step2opt walk. Distance-pruned path recovers missing small position rows and corner-deleted graph. Lift one tour at a time, use up to1000whole-CNF UP passes plus bounded20000node/80depth auxiliary search, false-fill and replay all parsed clauses. SAT-only; large reachability auxiliary layer remains unsupported.

**Underlying structure:** Closed knight tours are Hamiltonian cycles in the knight graph. A2opt reversal preserves a cycle exactly when both replacement edges are legal; geometric symmetries/reversal preserve legality but need not satisfy auxiliary symmetry/order restrictions. Graph isomorphism helps reuse a stored geometric witness but is unnecessary when search can operate on the actual recovered graph. A finite tour table is not a constructive generator for all sizes.

**Wassat coverage:** knight_tour.w already recovers the distance-pruned signed position/square support and corner-deleted graph, constructs a tour directly via bounded Warnsdorff DFS with reserved final endpoint, completes a compact residual and replays all original clauses. It needs no tour table or board isomorphism, supports even sides6..30,2Mvars/5Mclauses and bounded search/completion. Sparse directed-arc, dense bijective and CP decoder variants are complementary coverage; generic Hamiltonian workers do not by themselves establish those encoder contracts.

**Learn for Wassat:** Add checked sparse directed-arc and dense matrix front ends feeding the existing table-free tour search and original-CNF residual lifter. Retain and block a failed primary tour when auxiliary order constraints reject it; try legal2opt moves or restart from residual-derived no-goods instead of stopping at one candidate. For huge reachability encodings, decode actual auxiliary semantics and assign them from the tour directly, with streamed full-input replay and bounded indexing. Share exact-one incidence recovery and candidate completion across Hamiltonian, knight and path-cover families.

**Improve LymphoSAT:** Replace stored tours with direct graph search or an independently derived scalable construction; keep witness-data provenance distinct from algorithm source. Bound all isomorphism DFS, WL preprocessing, initial symmetry trials, CP mutations and auxiliary completion under one shared clock; the sparse540sclock begins only after potentially expensive initial phases. Cache parsed residuals/learned candidate no-goods instead of copying full assignments and rescanning wholeCNF at each repair branch. Strictly retain empty clauses and reject out-of-range literals; read_cnf currently drops empty clauses and filters out-of-range literals, so parsed-model replay alone is insufficient whole-input validation. Check support signs and complete incidences before geometry assumptions; keep original-CNF replay as the final model gate.

**Certificates and evidence:** An independently generated12x12sparse directed-arc/exact-one encoding880vars/5320clauses receives a complete checked model. All10stored tours/4740square entries,160symmetry/reversal variants and541legal2opt mutations independently satisfy permutation and closing knight-edge checks. Four full/corner-deleted isomorphism controls pass adjacency replay. Current Wassat knight-tour six examples pass. No CP/bij/distance decoder competition replay and no stored-tour data copied. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/054-knights-problem.json`.

### 55. ktf

High-level randomized gain/cost greedy upgrades and deficit-directed DFS over option levels. Remaining-component availability and cheapest-deficit repair bounds prune; at most96branches/node. Objective tail is a UP oracle with all absent primaries false, or inferred weighted cost pruning. Full-CNF queued propagation, false-fill and replay protect SAT. After540sstructural search, primary-decision CDCL projects auxiliaries through reasons and logs RUP toward a575sfinal deadline; only this fallback can publish UNSAT.

**Underlying structure:** Team formation is conflict-constrained multicover with a cost budget. Replacing one component option by a higher level is monotone only when its skill set contains the old option and costs are ordered appropriately. A conflict-connected component is not necessarily a clique, so forcing at most one option can exclude valid teams. A per-skill cheapest-repair bound is admissible only with validated costs and true availability; summing bounds over skills double-counts agents unless a valid packing/dual argument justifies it. Tail UP on all currently absent agents false can prematurely reject nonmonotone constraints that future choices would repair.

**Wassat coverage:** quota_cover.w already decodes complete Sinz-counter quotas and searches an exact-size unweighted selection with incident weighted deficits; its reducer deliberately excludes arbitrary costs/upper bounds and conflicts. covering.w handles explicit positive rows and general negative-binary conflicts, but only one-hit coverage without a weighted objective. counter_cover.w decodes signed adder counts and fixed-budget cover swaps, not multi-skill conflict-component levels. These pieces should be unified around checked constraints rather than treated as an already equivalent KTF specialist.

**Learn for Wassat:** Add a checked totalizer/weighted-budget team decoder feeding generalized conflict-aware multicover search. Use validated nested/Pareto-dominating option sets for compressed levels; otherwise update both removed and added skill contributions and retain general conflicts. Strengthen lower bounds with small deficit packing or a feasible LP-dual weighting of skills, avoiding double-counted agents. Reuse root propagation, candidate completion and proof engine under a shared budget; project reason-derived primary no-goods only with replayable provenance.

**Improve LymphoSAT:** Verify conflict cliques and nested cover/cost order before level compression;64pair controls show exactly where current deficit update fails. Validate weighted tail semantics instead of block-position bit costs; unproved cost pruning must remain candidate-only and can harm completeness. Do not set future eligible agents false in a partial-feasibility oracle unless monotonicity makes that safe. Keep unchosen variables unassigned or derive a relaxation. Bound component size before uint8level storage, DFS recursion, repeated assignment allocation, primary scans and unbounded learned clauses; share time through parse/recovery and proof completion. Check proof open/write/flush/close before reporting UNSAT; root and general code currently publish independently of stream success. Preserve strict DIMACS counts and bounds.

**Certificates and evidence:** Fresh independently generated three-agent quota/conflict CNF gives a complete checked9variable model through actual main. Direct actual fallback CDCL produces accepted109Broot and125Bnonroot contradiction proofs, bypassing KTF recognition and540sSAT phase. All64pairs of three-skill cover sets confirm apply_upgrade exactly on27nested pairs and stale deficits on37nonnested pairs. This establishes an unchecked kernel assumption, not a published falseSAT: full CNF replay remains required. No multiblock-cost decoding or long-run projected-CDCL qualification. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/055-ktf.json`.

### 56. long-learned-clauses

Recover signed exact-cardinality equations, reduce them modulo2 and perform dense bitset Gaussian elimination with dependency bitsets. A contradictory subset yields lower/upper PBconstraints by RUP plus polynomial cutting-planes division: arity3pairs divideby2, exact2of4triples divideby3. Sum each side of the dependent equations, divideby2 and combine rounded cuts to contradiction. Consistent or unsupported cases use incremental raw-CNF min-break/max-make WalkSAT and complete parsed-model replay.

**Underlying structure:** Signed exact-k implies XOR of underlying variables equals k plus complemented-literal parity. Any GF2dependency cancels every variable an even number of times; an odd right side is contradictory. Summing matching lower/upper exact constraints leaves complementary even coefficients, and division rounding exposes the odd parity as a PBcontradiction. This can use a proper subset of a connected equation component. Consistent parity is only a necessary condition for the original cardinalities and does not establish SAT.

**Wassat coverage:** parity_sum.w already extracts parity consequences from complete truth-table supports, including these five/ten-clause signed exact-cardinality blocks, and separately binomial cardinality clauses. It peels lone-variable equations and sums entire connected components, explicitly not Gaussian elimination; proper contradictory subsets can be missed. portfolio.w also has bounded complete-XOR elimination/model enumeration, a different dispatcher/capability path. No common PBcertificate export for the signed-cardinality parity dependency was found; fast-only parity_sum has no clausal proof.

**Learn for Wassat:** Reuse existing checked truth-table/cardinality recovery, adding bounded compressed-coordinate GF2elimination and exact dependency witnesses after the linear-time component pass. Export the dependency with shared PBexact-bound aggregation; prove only the selected core and preserve original clause IDs. For consistent systems, express candidates in free affine coordinates and score true cardinality residuals, rather than flipping Tseitin/raw CNF indiscriminately. Keep damaged blocks as explicit residual constraints and retain valid recovered equations from unaffected supports instead of rejecting the whole structural path.

**Improve LymphoSAT:** Accept a checked contradictory subset plus arbitrary additional clauses; whole-input width/count grammar unnecessarily forfeits valid cores. Compress participating variables and bound both basis and dependency-bitset memory/work; dense declared-ID Gaussian allocation can dominate a small actual system. Guard time through recovery, elimination and proof generation rather than start only at SLS; use shared cancellation and resource accounting. Maintain incremental break values instead of rescanning all occurrences for every candidate and allocating tie vectors at each flip. Preserve original empty clauses, validate declared counts/bounds/terminators and check proof stream close/write status before publishing UNSAT.

**Certificates and evidence:** Four fresh proofs independently pass VeriPB: signed triple odd shadow, same contradictory core plus an extra equation hiding whole-component cancellation, signed quadruple shadow and signed/clause-shuffled triple. All six-variable classifications independently exhaustive. Two consistent triple/quadruple controls yield complete checked models. Original strict empty-clause validation remains absent in parser; generic SLS is not proof of consistent-shadow feasibility. Current Wassat helper comparison recorded separately. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/056-long-learned-clauses.json`.

### 57. maximum-constraint-partition

For N/2selected primaries, swap each selected element with one anchor and each unselected element with one pivot to recover relative weights. Normalize by the minimum and solve exact-cardinality half-sum using bitset DP, with divide-and-conquer reconstruction. Lift one selected set, fully propagate and replay all retained clauses. If DP fails, extract a backward low-bit cone by maximum-variable clause buckets and run bounded proof-logging CDCL on that actual clause subset, then full-CNF CDCL. Only actual CDCL refutation publishes UNSAT; guessed weights/DPfailure alone cannot do so.

**Underlying structure:** For a genuine additive difference D(S)=2*sum(S)-total, a balanced swap changes D by twice the weight difference. Recovered weights are defined up to a common offset; that offset cancels precisely because both sides have N/2items. Normalized odd total blocks equal sums. Sampling is only a candidate model, not a proof of circuit semantics. A refuted subset of actual original clauses suffices to refute the whole input regardless of whether numeric variable order found the intended cone. DP is pseudo-polynomial in target sum, not polynomial in encoded bit width.

**Wassat coverage:** partition_circuit.w already checks bounded three-input truth tables, reads equal-sum output pairs, evaluates64one-hot inputs in parallel, infers positive weights and constructs an equal-size partition by sorted pairing plus a two-selected/two-unselected exchange. It replays all original clauses and never refutes from its heuristic arithmetic. Limits include512primaries,200kvars,800kclauses,30output bits, weights<=262143,4Mwork and a default50msCLI slice. LymphoSAT adds balanced-swap recovery valid when one-hot assignments violate a cardinality prefix, an exact pseudo-polynomial DP candidate search, and actual low-bit RUP proof export.

**Learn for Wassat:** Retain current fast batched sampling and pair exchange, then add bounded cardinality-bitset DP when target size makes it affordable. Use balanced swaps when structural/cardinality assertions prevent one-hot evaluation; verify additional independent samples and every lifted candidate. Run a small proof-backed query on the actual low-bit cone after an odd-total hint; share the existing query/proof infrastructure instead of treating sampled arithmetic as a refutation. Normalize by a common offset and gcd where valid, and select meet-in-the-middle, sparse DP or bitset DP from measured target/state size.

**Improve LymphoSAT:** Use queued propagation or a recovered topological evaluator across swaps instead of repeatedly rescanning the entire prefix. Bound target sum, multiplication/allocation sizes, DP reconstruction work, proof storage and elapsed time before allocating; conflict caps alone do not bound wall time. Find reconstruction splits with word-level set-bit/intersection work instead of scalar0..sum scans and repeated full DP allocations. Preserve level-zero original/learned units on cancel_until(0); current code clears the whole trail, which can lose constraints and completeness. Stream checked proofs and reclaim learned storage; preserve strict DIMACS empty clauses/counts/bounds/termination and check proof close/write completion.

**Certificates and evidence:** Fresh independently generated20item/8bit full-adder circuits both pass: balanced all-one weights produce a complete1629variable model; odd total produces an accepted7901BRUPproof from the extracted low-bit subset, checked against full6434clause input. Kernel exhaustive4368weight vectors yields295872cardinality/sum comparisons and101064independently validated reconstructions. Current Wassat partition seven examples pass. These tests do not establish competition speed, hidden larger sums or full-CDCL restart correctness. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/057-maximum-constraint-partition.json`.

### 58. md5-equivalence-checking

The actual main always constructs CDCLSolver, solves, verifies and returns; the earlier backward-justification Solver and12attempt loop are unreachable. Active solver has linked watch arrays over flat clauses, first-UIP learning, phase saving, lazy activity heap plus monotonically scanned initial decisions and a200kconflict/560snominal cap. No restarts, learned deletion or proof output. All failures become UNKNOWN. Stored-unit/nonunit verification precedes model printing, but inconsistent unknown defaults break this guard.

**Underlying structure:** A Yosys miter asks for a Boolean assignment witnessing some permitted circuit mismatch; its name alone does not imply that asserting equality is UNSAT or that an MD5 cryptanalytic procedure is needed. The active code is generic SAT search. Topological gate simulation, local comparison cones and repeated-frame structure could construct models with less watch state, but no such semantic path runs here. The README two-conflict/large-scale timings are unreplicated training observations, not evidence from this audit.

**Wassat coverage:** Wassat already has native flat/packed CDCL, binary-specialized propagation, phase/activity control, learned reductions, proof modes and original-model replay. solver.w backjump preserves the root prefix and reinserts unassigned variables into the heap; model verification consumes the same signed model representation that is printed. Lucky propagation dives and bounded scout address easy structured circuit SAT. model_circuit.w offers bounded truth-table construction; circuit_cones.w checks a specific topologicalAND/one-direction-miter grammar but is currently opt-in and capped2Mvars/8Mclauses. wide_circuit.w is4096varfinite refutation, byte_relations.w a bounded refuter. None should be called general large sequential MD5 model construction.

**Learn for Wassat:** Treat this worker as a compact generic-engine comparison, not a missing MD5 mathematical specialist; compare parser/watch/propagation/model-output memory and time on identical frozen inputs. Recover topological gates and repeated-frame interfaces for a direct SAT model constructor, preserving complete original-CNF replay. Use candidate mismatch cones and streaming gate evaluation to avoid building full generic watch state when a checked semantic construction succeeds; preserve generic fallback for unsupported cases. Retain explicit boundary tests for output/verifier assignment identity and root-unit preservation before any engine change is promoted.

**Improve LymphoSAT:** Preserve the level-zero trail on backjump; reinsert all unassigned variables into a complete decision structure rather than only bumped conflict variables. Require complete assignment or materialize exactly one common default completion before both verify and print. The reproduced unknown=-1 default mismatch currently emits a rejected model. Remove or clearly quarantine unreachable justification code so documentation describes the actual submitted path. Validate literal bounds, arithmetic/offset capacities, header tokens and trailing unterminated literals; sorted-max numbering is a restrictive parser gate, not semantic correctness. Poll wall time independently of conflicts modulo1024 and include parse/watch initialization. Bound learned storage and stale heap entries; no restart/deletion limits resident growth. Separate model construction, verification and output costs in benchmark reports, and independently reproduce train timing before changing defaults.

**Certificates and evidence:** On CNF(-x1) AND(x2 OR x3) AND(x2 OR -x3), actual main prints SAT model(+x1,+x2,-x3), violating the original negative unit. Formula itself is SAT; this is an invalid witness, not a falseUNSAT or an independently established wrong SAT/UNSAT classification. Kernel confirms one conflict, cancelUntil(0)clears root x1, verify treats unknown -1asfalse, while printModel treats -1astrue. The exact probe is outside the narrow feature matcher. Valid sorted SAT control passes; root contradiction, unsorted nonunits and empty clause decline. No large actual MD5 formula replay or outer-portfolio reproduction. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/058-md5-equivalence-checking.json`.

### 59. mechanical-master-key

Search directly over key cuts. Small charts K<=60 use cell annealing, two-move/depth-five repair and a whole-code fallback. Large charts greedily choose depth partitions by covered forbidden lock/key pairs, then weighted incremental min-conflicts with legal cell moves, whole-key replacements and whole-column reoptimization in smaller regimes. Per-lock depth counts determine accepted cuts; only zero-violation candidates are lifted to all key, lock-OR and mismatch variables and checked against every retained clause. SAT-only, nominal 580 seconds across search slices.

**Underlying structure:** A lock admits a key exactly when every key coordinate belongs to the union of authorized depths at that coordinate. Every unauthorized pair must be separated in at least one coordinate. Thus columns form a separating partition system, coupled by adjacent-depth geometry. Greedy independent columns can be useful proposals but are not a complete construction. Any forbidden key must have a different complete cut from each authorized key; a clique in that required-distinctness graph larger than the number of legal jump-constrained codes gives a necessary infeasibility bound, requiring checked encoding premises and a certificate before publication.

**Wassat coverage:** keychart.w already recovers four-depth domains and lock supports, verifies the complete support pattern across all coordinates and witness implications, and uses weighted finite-domain search with cached exact move deltas. It lifts a proposal or repairs near models using incremental primary assumptions, failed-core relaxation, a reused CDCL arena and full original-model replay. Bounds include K,L<=64, positions<=16, 50000 variables and 100000 clauses. Its i64 counts avoid this byte overflow. Admission is an additional raw-artifact arm with CPU/memory/rounding gates. Missing extensions are larger charts, general depths, greedy separating-column seeds and whole-key/column neighborhoods.

**Learn for Wassat:** Extend the checked decoder and existing worker to larger charts and variable depth counts under measured memory/work budgets. Add greedy separating-column initialization and whole-key/column neighborhoods, reusing current exact delta caches and assumption repair. Combine incident-only committed updates with cached candidate deltas; profile initialization, move scoring, committed refresh and CNF repair separately. Build checked required-distinctness/clique bounds against the legal-code count for small geometries, with shared counting/PB export rather than a dimension-based verdict.

**Improve LymphoSAT:** Use counts wide enough for every authorized key or reject unsupported cardinalities; the 256-key direct control reproduces wraparound. Validate all OR supports, primary layout and jump premises; gcd stride can be a multiple of the true stride and is only a candidate layout. Replace the blanket D3/P4 refusal with bounded search or a checked proof path; a fresh SAT chart demonstrates that size alone is not infeasibility. Avoid mutating/reverting the full incident state for every candidate when cached delta formulas suffice. Reuse low-DFS scratch rather than allocating a large seen array at each node. Reject P>8 before fixed eight-position arrays are used, and use one deadline including greedy initialization, inner repair loops, parsing and model replay. Strictly validate DIMACS bounds/counts/termination.

**Certificates and evidence:** Independent three-key/two-lock D4/P2 CNF receives a complete checked model. An independently witnessed SAT D3/P4 chart returns UNKNOWN through the dimension-only refusal. For 10000 random move attempts, 4657 legal moves and periodic weight bumps match full recomputation of counts, masks, bad pairs and weighted scores. With 256 authorized keys in one bucket, uint8 counts wrap: independent violation count is one but incremental total is zero. This is a direct kernel boundary, not a reproduced full-main false SAT; final CNF replay remains mandatory. Five current Wassat key-chart tests pass. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/059-mechanical-master-key.json`.

### 60. minimal-superpermutation

Try one stored n4 length-33 word or a portfolio of n5 prefixes, encode all word bits and force occurrence variables false when an actual binary implication disagrees with the word. Whole-CNF scanning DPLL fills remaining variables and replays every retained clause. If every candidate fails without timeout and an explicit first-word-forbid clause exists, CoverageProof branches over actual positive coverage clauses, propagates with watches and emits bottom-up decision-blocking RUP clauses. It publishes UNSAT only after exhausting the coverage choices and closing the proof stream successfully. Older ProofDpll/ProofCdcl classes are inactive.

**Underlying structure:** An n-symbol word of length L has at most L-n+1 permutation windows. The n4 candidate contains all 24 permutations; n5 lengths 21/26 cannot contain all 120 and are partial-coverage/cardinality problems whose exact target must be decoded. Coverage-choice branching is complete for its selected actual ALO clauses: every Boolean model must choose at least one literal from each. If all selected rows become satisfied without a propagation contradiction, the prover stops inconclusively, not with a published SAT model. Forbidding a known word alone is not an UNSAT argument; the exhaustive original-clause proof supplies that argument.

**Wassat coverage:** No current Wassat semantic superpermutation word/occurrence decoder or constructor was found. block_csp.w requires every variable in a complete small exact-one block, unlike occurrence and PB auxiliary variables; domain_walk.w handles verified binary exclusions rather than general substring coverage. model_circuit.w and the generic solver can lift or search Boolean candidates but do not construct high-coverage words or extract permutation-choice branching. Existing backdoor finishers are generic infrastructure, not evidenced input-derived word coverage.

**Learn for Wassat:** Recover actual alphabet/position encodings, occurrence implications and full/partial coverage targets, then search words directly with rolling permutation-window scores. Use independently derived recursive overlap constructions as seeds and de Bruijn/overlap graph paths for general high-coverage search; validate streamliners and auxiliary completion against original clauses. Reuse a bounded original-CNF completion/proof engine after fixing word bits and propagate contradicted occurrence leaves through a shared index. For uniqueness/lower bounds, retain actual coverage choices and emit conflict-derived no-goods with clause provenance; shared prefix-state memoization may reduce repeated proof subtrees.

**Improve LymphoSAT:** Replace exact declared-variable tables and stored prefixes with input-derived layouts and independently generated candidates; distinguish partial n5 targets from full superpermutation requirements. Bound the aggregate candidate schedule: seven n5 candidates can each receive60s, followed by480s proof search, while n4 can receive540s completion plus480s proof search. Maintain queued watched propagation for SAT extension and a persistent qhead in coverage proof search instead of rescanning/replaying all assigned literals at every recursive node. Compress decision no-goods using actual reason cores and share repeated occurrence-prefix states; the accepted fresh proof is still34.7MB. Parse DIMACS as a token stream with counts and empty clauses preserved. Current line parser drops empty clauses and ignores content after the first zero on a line.

**Certificates and evidence:** Independent one-hot n4/L33 full-coverage CNF (852 variables, 3871 clauses) receives a complete checked model. Forbid a separately generated recursive-overlap word: actual main emits 632904 blocking clauses, a 34747386-byte proof independently accepted by VeriPB. This validates the worker/proof path on a full constructed encoding, outside the narrow matcher, not all original flat/tree/binary variants. Kernel checks 960 symbol-encoding round trips and candidate coverage: n4 reaches24/24; n5 portfolios reach15 and19 distinct permutations, not120. No stored words copied into Wassat. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/060-minimal-superpermutation.json`.

### 61. minimum-disagreement-parity

Dense GF2 elimination prefers nonprimary pivots, expresses scores as affine primary functions, derives score-space parity checks and seeks a low-weight target-syndrome support. Meet-in-the-middle stores the minimum weight per right-half syndrome; split caps are floor(t/2) and floor(t/2)+2 in both orientations, followed by four deterministic permutations. Solve primary equations for one found score vector, reconstruct XOR auxiliaries, greedily complete the suffix and replay every retained clause. SAT-only; inconsistency and search misses return UNKNOWN.

**Underlying structure:** Scores e=A*x+b lie in an affine code, so every left-nullspace row H imposes H*e=H*b. Finding a low-weight score vector is syndrome decoding; parity-check satisfaction is sufficient for membership in that affine image when the recovered linear system is complete. A fixed capped split omits supports concentrated on one side, and finitely many random permutations do not establish exhaustive nonexistence. A single sorted-prefix threshold probe does not prove an arbitrary suffix depends only on Hamming weight. Free nonprimary dimensions must be retained or explicitly declined during reconstruction.

**Wassat coverage:** mdp.w already validates the generator XOR/counter grammar, reconstructs samples and supports n8..36 in multiples of four with tolerance n/4 or one less. It now has an exact two-basis pigeonhole decoder, not merely the older ISD described in its header, plus deterministic ISD fallback, bounded CDCL model completion and full original-clause replay. Two bases cover all low-error cases by splitting errors in the first basis versus remaining samples, with at most four shared basis coordinates enumerated separately; excessive overlap/rank failure declines. It can refute a strict or weakened system in fast mode, while proof mode falls through without a certificate. One shortened XOR variant is treated conservatively through strict samples. LymphoSAT MITM is an alternative SAT search, not a missing MDP family.

**Learn for Wassat:** Compare bounded syndrome MITM with current two-basis and ISD searches on identical recovered samples; choose from estimated combination counts and rank rather than family labels. Compress participating coordinates and parity-check dimension before allocating a syndrome table, and enumerate one side incrementally instead of materializing both support lists. Generalize checked score/counter recovery only with explicit semantics, while retaining candidate-only handling for relaxed shapes. Export parity-check derivations and exact low-weight exclusion certificates to close the existing fast-only UNSAT proof gap.

**Improve LymphoSAT:** Guard missing nonprimary pivots consistently and assign free affine coordinates explicitly; the unrelated-XOR control currently crashes. Validate complete counter semantics instead of assuming sorted-prefix UP identifies a symmetric weight threshold; guard suffix length before reading prefix_end+1. Bound combination counts, hash memory and time before enumeration. N62/t12 can imply billions of supports despite small fixed scalar limits; there is currently no shared deadline. Retain alternative syndrome supports or use bounded backtracking when the first candidate fails extra clauses or greedy auxiliary completion. Remove repeated XOR-block copies, use compressed/sparse elimination and preserve strict DIMACS bounds/counts/termination. Never turn capped MITM failure into UNSAT.

**Certificates and evidence:** Fresh N4/one-error CNF yields a complete checked model; four unavoidable disagreements with threshold1 returns UNKNOWN. Add an unrelated satisfiable free-auxiliary XOR component: actual main segfaults, reproduced under ASan as a null read during reconstruction. Source reconstruction omits the has[p] guard that score reduction uses before accessing a basis row. The augmented formula is satisfiable; this is a direct worker robustness defect outside matcher, not a false verdict.1280 independent-column syndrome requests agree with brute force and return303 valid supports; an unbalanced one-split miss is recovered by permuted retry. Eight current Wassat MDP checks pass with the required test CLI path set. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/061-minimum-disagreement-parity.json`.

### 62. modcircuits

For two recognized shapes, assign fixed nine-gate or eleven-gate netlists, output selectors and optional residue-code choices; complete by UP and replay. Otherwise run a short proof-logging CDCL on small formulas, raw-CNF local search initialized one-hot, unit simplification, bounded large-neighborhood CDCL repair, simplified SAT-only CDCL and final original-CNF proof CDCL. Local search uses ordinary single-bit flips after one-hot initialization. Only a logged original-formula refutation is published as UNSAT; conditional repair UNSAT is not promoted.

**Underlying structure:** Bounded Boolean circuit synthesis chooses topological sources and allowed gate truth tables so every input assignment produces the requested output relation. Auto-encoding also chooses residue codes. Fixed netlists are finite constructive proposals, not a general synthesizer. An input-derived solver could evaluate small truth tables as bitsets, modify source/function choices atomically and exploit shared subexpressions while honoring the actual gate library and symmetry constraints. Fixed-circuit evaluation and synthesis are opposite directions of reasoning. The exact converter convention for the stored type bits must be recovered before independently claiming what these netlists compute.

**Wassat coverage:** Wassat already has native CDCL/proof modes, CCAnr weighted local search, one-hot domain walks, bounded block-CSP and fixed-circuit truth-table/model-lifting infrastructure. block_csp requires every variable to belong to a small complete domain; synthesis truth bits and per-assignment auxiliaries violate that generic contract. No dedicated gate-selector/type/residue-code synthesis decoder or semantic MOD3 network constructor was found. model_circuit.w evaluates recovered fixed functions, not variable gate functions selected by a synthesis instance. A second generic engine or copied netlist is not equivalent new mathematical coverage.

**Learn for Wassat:** Decode actual selector groups, allowed truth-table functions, per-assignment evaluation clauses, output targets and residue-code constraints. Search circuit structures directly with bitset truth tables and incremental fanout recomputation; use atomic source/function/code changes and shared-subexpression reuse. Construct modular finite-state/addition networks independently, then map them into the checked synthesis grammar and let original-CNF completion validate gate bounds and streamliners. For lower bounds, derive a checked abstraction or export exhaustive synthesis/CDCL evidence; failure to find a proposed network is not an impossibility proof.

**Improve LymphoSAT:** Replace exact-count fixed-netlist proposals with semantic decoding, validated gate library recovery and bounded structure search; keep model replay for every proposal. Maintain one-hot selector legality throughout domain moves, rather than only at initialization, with incremental residual scores for non-domain constraints. Use wider clause true counts or bound widths: SLS saturates initial counts at255 but subsequent byte updates can wrap on long clauses. Reuse watched propagation and assumption-based repair instead of repeated full-CNF scans, formula copies and solver reconstruction; bound learned/proof literal storage as well as clause counts. Check proof flush/close completion before publishing UNSAT, and charge all parsing, detection, initialization and slice overshoots to one shared deadline. Preserve empty clauses and strict token/count/bounds validation; simplify only with model/proof provenance retained for original-input replay.

**Certificates and evidence:** Actual main emits accepted126Bbinary and109Broot contradiction proofs on fresh generic controls; a generic SAT control has a complete checked model. No original MOD3 synthesis CNF or direct fixed-netlist lift was replayed. Exploratory direct-mask truth-table interpretations did not recover a MOD3 relation under assumed conventions; this is an unqualified hypothesis test, not evidence the reference netlists are wrong. All SAT publication paths check parsed clauses, but the line parser discards empty clauses and trailing content after zero, so strict whole-input validation is missing. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/062-modcircuits.json`.

### 63. mosoi-289

Random-restart domain local search assigns exactly one of four values to each block, seeds units and chooses a domain from an unsatisfied clause. It evaluates all three replacement colors by rescanning incident original clauses, updates a Boolean satisfaction cache/unsatisfied list, and uses low-probability noise or a random worsening move. Every returned one-hot model is checked against all parsed clauses. SAT-only, default25second search timer; no active debugged-counter proof path.

**Underlying structure:** The regular geometry asks for a grid with no monochromatic rectangle. For each column, sum binom(color-class size,2); over all columns this is at most colors*binom(rows,2), because any row pair can repeat a given color at most once. Balanced class sizes minimize the per-column demand: this excludes a20x20four-color grid (at least800 pair/color uses versus capacity760). A clean16x16construction indexes rows(a,b) and columns(s,t) over F4 and uses color=a*s+b+t: distinct rows agree at only one slope, and a fixed color then fixes t. These are input-derived opportunities only after complete grid/rectangle premises are checked. The active worker itself uses neither construction nor bound.

**Wassat coverage:** block_csp.w already handles complete exact-one domains of widths2..24, binary exclusions and arbitrary residual clauses through bounded DFS, within10000vars/300blocks/400kclauses and residual caps. Thus standard289cell/four-value semantics can fit, though exact DFS is not the same search policy as LymphoSAT domain SLS. domain_walk.w currently specializes binary exclusions rather than quaternary residual nogoods. The transformed positive-K4 plus sequential upper-bound pattern described in the README matches ais.w mathematics: each verified K4 needs at least3true vertices, and the full counter is checked. Actual debugged competition formulas were not replayed, so compatibility remains conditional on that grammar.

**Learn for Wassat:** Generalize current finite-domain local search to small mixed-polarity residual clauses/colored hyperedges, preserving real forbidden tuples and full model replay. Recover complete rectangle geometry and use independently derived finite-field seeds plus incremental row-pair/color collision scores; investigate bounded extension from16x16 to larger grids. Export the checked rectangle pair-count inequality and reuse AIS/counter certificates for transformed K4 lower bounds rather than add another generic solver. Share this small-arity domain engine with the No-L multi-color hypergraph opportunity from review45.

**Improve LymphoSAT:** Require a genuine ALO for each forced-one-hot domain or include an all-false value where allowed; the fresh missing-ALO SAT miss reproduces the overrestriction. Identify an ALO by sorted block arithmetic instead of scanning every block for every width-four clause, reducing avoidable quadratic recognition. Precompute residual forbidden-tuple structure and update incident costs incrementally rather than re-evaluate each original clause for every candidate color. Recover and validate grid incidence before applying rectangle-specific constructions/bounds; a four-valued CNF profile is not sufficient. Bound initialization and long incidence scans under the same cancellable timer; validate actual DIMACS clause counts, numeric parsing and headers as well as bounds/termination.

**Certificates and evidence:** Independent3x3rectangle CNF receives a complete checked36variable model. An accepted two-block formula missing the first ALO has an explicit SAT model with all first-block variables false, but the worker spends25seconds and returns UNKNOWN because its projection forces one true value there. Independently derived F4seed passes all14400rectangle checks. Existing Wassat block-CSP focused result is recorded separately. No geometry implementation, exported count proof or competition timing claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/063-mosoi-289.json`.

### 64. multiplier-circuits

Pack a target into unsigned128bits; trial small primes, test twelve fixed Miller-Rabin bases, recursively Pollard-rho factor, enumerate divisors fitting the proposed operand widths, evaluate the gate DAG and replay every original retained clause. Full model replay protects SAT even if target/layout recovery is wrong. No UNSAT publication. rho restarts and recursive factorization have no deadline; target0 has no terminating factor_rec case.

**Underlying structure:** For an actual unsigned multiplier a*b=T, a width-compatible divisor pair gives candidate primaries and a topological evaluator fixes auxiliaries. A sampled/generic gate DAG is only a proposal unless its arithmetic semantics are proved; final replay remains required. Four clauses need not define a unique output for every input: derive_gate chooses0 when both outputs remain allowed. Fixed-base Miller-Rabin is not unconditionally deterministic over the whole advertised126bit range. Arithmetic128bit operations avoid mul_mod addition overflow, but termination and primality qualification are separate obligations.

**Wassat coverage:** multiplier.w already recognizes complete distinct four-row AND/XOR tables, recovers a contiguous complete bipartite primary partial-product graph, packs sink units in output-ID order, searches bounded divisors and evaluates/replays the original model. It has a zero-target case, operand widths<=62, a signed target range, gate cap200000 and at most1048576trial candidates. It is stricter than generic DAG inference and does not accept three-input mux or arbitrary OR tables. fermat.w separately has bounded Pollard-rho for its canonical formats. LymphoSAT adds max-output grouping independent of group adjacency, generic2/3input candidate tables and wider integer factoring; a shared checked/bounded arithmetic service is preferable to a duplicate engine.

**Learn for Wassat:** Extend the existing model-only gate decoder to checked small truth tables and output-group indexing, preserving actual unit/gate provenance. Recover product-bit order from validated circuit structure rather than unit order, and operand partitions from the partial-product graph rather than literal position. Share bounded wide modular arithmetic/factorization with the Fermat/ToughSAT lane, with explicit probable-prime versus certified-prime status and a total work budget. Keep original-CNF replay and fallback on factorization misses; only separately proved arithmetic semantics can justify a factor-based UNSAT path.

**Improve LymphoSAT:** Handle target0 before recursive factorization and distinguish infeasible widths from exhausted search; the fresh zero-product control is satisfiable. Do not describe twelve fixed bases as deterministic for arbitrary126bit values; the explicit composite counterexample passes this implementation. Use a qualified range or certified factor/primality procedure. Make rho restarts, recursion, divisor enumeration and modular products honor one deadline/work budget; guard operand widths before128bit shifts. Validate or deliberately retain all satisfying outputs of a relation when a four-clause group is not functional; choosing one default can miss SAT. Accept standard DIMACS comments, bounds/counts and safe terminators. Current stoi-token parser cannot read comments and lacks complete literal/header validation. Use faster bounded modular multiplication where measured beneficial and skip duplicate divisor orientations; never trade a larger integer range for unbounded foreground work.

**Certificates and evidence:** Fresh2x2multiplication CNF with product6 gives a complete checked model. Reordered units of a product3formula are misread as12 and return UNKNOWN despite an independently checked1*3model. Zero-product formula has an independent0*1model but fails to terminate within a2sexternal guard; the child was killed and reaped, not observed returning UNKNOWN. Integer kernel matches5001small primality classifications and328349modular products, but labels composite318665857834031151167461 as prime; direct division by399165290221 establishes compositeness. This can suppress valid width-fitting divisor candidates, not create an UNSAT claim. Current Wassat multiplier checks are recorded separately. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/064-multiplier-circuits.json`.

### 65. multiplier-verification

Compose each signed ITE into a canonical ROBDD using unique nodes and cached operations, capped at one million nodes and nominal2.5seconds per order. A nonzero root union gives primary values, then full CNF expansion/replay. Exact zero only guides an original-CNF CDCL proof, not an unsupported BDD verdict. After BDD misses,64-lane smoke/random simulation precedes retained root-assumption CDCL: unconditional learned RUP clauses persist across root queries and a learned negative root unit discharges each assumption. No learned-clause deletion in this internal CDCL.

**Underlying structure:** The miter asserts that at least one output difference is true. If every represented Boolean difference is the zero function, the original CNF is contradictory once definitions are valid. ROBDD equality is functional equivalence beyond local gate congruence, but variable ordering can dominate size. Assumptions must be discharged with unconditional consequences; an assumed root cannot be logged as an unconditional original axiom.

**Wassat coverage:** gate_closure.w already recognizes core ITE clauses, constants, signed congruence and structural duplication. circuit_miters.w mainly decodes AIG gates and finite arithmetic/Gray forms; wide_circuit.w is capped AND/parity enumeration. miter_eval.w contains specialized bit-lane kernels, not global canonical ITE functions. circuit_cones.w already preserves unconditional learned lemmas across local assumptions and can supply proof-query infrastructure, but its current AND-oriented decoder does not accept this six-clause ITE grammar. Thus core query/proof ideas overlap, while a generic bounded ROBDD/ITE decoder adds coverage.

**Learn for Wassat:** Add checked small truth-table/ITE decoding and a budgeted ROBDD candidate lane; reuse original-CNF cone/query proof infrastructure rather than a second CDCL implementation. Retain unconditional consequences across output-root queries and derive explicit root exclusions; preserve assumption-core provenance. Profile BDD node/cache growth, variable-order failures, proof generation and independent verification separately; structural hashing alone cannot replace functional canonicalization.

**Improve LymphoSAT:** Use one shared cancellation/work budget across parse, seven BDD orders, simulation, proof CDCL and model replay. Poll an operation counter rather than cache-size divisibility: cache hits or early returns can skip the nominal deadline check. Avoid reserving million-entry unique/cache tables for every tiny order and release failed-order storage promptly. Add bounded learned-clause reduction and checked/atomic proof publication; output stream completion is not validated. Validate disjoint primary/output IDs, unique definitions, all root references and strict DIMACS counts; keep original model/proof checking as the final authority.

**Certificates and evidence:** Fresh signed-ITE zero miter gives an accepted181B main-path proof; a private include harness calls the retained-assumption method on the same original formula and gives an accepted207B proof. A nonzero miter gives a complete valid model. Random signed-ITE kernel checks160networks against2560independent primary valuations:106valid SAT models and54exact zero miters. Current Wassat gate-closure12/12 and miter-assignment3/3 pass. No assertion that actual competition multiplier inputs or BDD timeout path were replayed. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/065-multiplier-verification.json`.

### 66. mutilated-chessboard

Sum original demand ALOs and derived resource AMOs; for degree3 derive AMO from three pairs divided by2, and degree4 from four triple bounds divided by3. The resulting capacity inequality is contradictory when demand exceeds resources. Proof text is accumulated in Python lists. No SAT construction or arbitrary Hall-subset search.

**Underlying structure:** A matching can cover at most one demand per resource, so a verified subset S with |S|>|N(S)| is infeasible. Bipartite exact-one incidence further implies each connected component has equal side sizes. Aggregating independently oriented components globally can hide opposite imbalances; the fresh disjoint-K3,2 control demonstrates this miss.

**Wassat coverage:** matching_balance.w already implements the exact-one edge-incidence invariant per connected component, allowing widths1..32 within4096vars/50000clauses and a CLI20ms budget. It requires checked pairwise AMOs on every participating row, stronger premises than demand-ALO/resource-AMO Hall counting. coloring.w has broader signed explicit-choice/resource-clique capacity counting for widths>=3; it does not directly decode Sinz groups. matching_parity.w handles related odd closed components with implication-certified exclusions. Existing mathematics should be unified with sequential-AMO decoding and exported PB certificates rather than duplicated.

**Learn for Wassat:** Share one Hall/resource-capacity certificate engine with earlier pigeonhole/cover specialists, retaining actual original clause IDs. Decode complete Sinz AMOs into certified resource bounds and generalize polynomial pairwise-AMO aggregation beyond degree4. Use component contradictions first, then bounded Hall subsets/matching search; a successful matching can seed a SAT model but still needs full-CNF lifting.

**Improve LymphoSAT:** Check per-component imbalance or choose a Hall core instead of comparing globally oriented color totals. Recover groups independent of clause order and support unit/singleton demand/resource constraints. Preserve empty clauses and strict declared counts/terminators; parser drops zeros and empty clauses, so proof IDs can diverge on malformed/nonstandard input. Stream checked proof records and bound memory/work; current all-in-memory proof lists scale with generated arithmetic.

**Certificates and evidence:** Plain K3,2 incidence emits an accepted399B proof. Mixed K4,3 with one pairwise and two Sinz resource groups emits an accepted1350B proof. Removing the final Sinz overflow clause is rejected. Two oppositely oriented imbalanced components return UNKNOWN although each is independently UNSAT. Current Wassat matching-balance9/9 pass, including per-component cancellation controls. These tiny direct inputs bypass the feature matcher. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/066-mutilated-chessboard.json`.

### 67. oddball-weighing

Default ZeroPlus search selects N canonical antipodal ternary signatures including the all-positive row0, changes row orientations/selections to drive coordinate sums to zero, then sorts rows to map balls. Forced TTF mode fixes rows1..N, rejects odd support in any coordinate, otherwise anneals orientation signs only. Matching variables pair positive and negative balls in each coordinate; signature variables are set and auxiliary UP/full parsed-CNF replay validates SAT. No UNSAT output; finite step limits but no wall-clock cancellation.

**Underlying structure:** Unknown-heavy/light outcomes require nonzero, pairwise distinct columns up to sign. A balanced weighing requires coordinate sums zero. There are P=(3^W-1)/2 antipodal classes, but at full capacity each coordinate has3^(W-1)nonzero classes, an odd number; no orientation can balance them. Thus the complete no-reference balanced geometry has N<=P-1. This is not a valid CNF refutation until its exact semantic premises are checked. Forced rows give a simpler necessary even-support test.

**Wassat coverage:** solver.w already has an input-derived ZeroPlus constructor with the same ternary-row selection/sign/balance mathematics, pair/signature lifting and UP/model replay; current eligibility requires>=5Mclauses and10000..200000vars. It uses reusable typed scratch and different bounded move policy. No explicit forced-TTF decoder/parity check was found, and N/P capacity guards should be added in both implementations. matching_parity.w already refutes suitable odd exact-one components using root units, limited binary resolution and certified exclusion paths; do not label all odd-matching reasoning missing. Default admission/caps are distinct from the explicit helper probe.

**Learn for Wassat:** Extend the existing constructor with checked forced-row orientation constraints and the even-support test; prefer one signature engine over another general SLS copy. Explore constructive balanced ternary codes and local zero-sum trades, scoring coordinate imbalance directly and lifting through actual encoding clauses. Certify the N<=P-1 no-reference bound or a forced-coordinate oddness core using checked capacity/parity premises and shared PB export. Compare annealed sign/row replacement with the existing typed-buffer search under equal work and model-validation budgets.

**Improve LymphoSAT:** Guard N against available P before indexing selected rows; the sparse-shape SAT crash is reproduced. Honor cancellation through signature initialization, candidate scoring, restarts and model lifting; step counts alone do not bound foreground latency. Recover actual row/ball/coordinate maps rather than relying on variable ranges and incomplete orientation-ALO recognition. Use incremental coordinate sums and reusable buffers instead of copying vectors for every candidate, retaining full original-CNF validation.

**Certificates and evidence:** Independent representative N3/W2 forced and selectable encodings both receive complete valid models. N3/W3 forced odd-support case returns UNKNOWN. A sparse satisfiable N3/W1/P1 shape passes runtime recognition then segfaults from reading beyond available signatures; this is outside the feature matcher and is not a complete weighing encoding. Kernel independently validates3selectable constructions,1forced construction and21full-capacity coordinate parity counts. A forced Wassat matching-parity helper with min_width2 returns0 on the odd-support fixture: related generic reasoning does not discharge this case in that invocation. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/067-oddball-weighing.json`.

### 68. or_randxor

Treat each OR pair as one GF2 coordinate and perform bitset Gaussian elimination with dependency tracking. SAT sets even pair variables false and odd representatives to a GF2 solution, then checks the whole parsed formula. UNSAT first adds RED representative-normalization units, derives direct XOR clauses by RUP, introduces parity/carry variables, derives exact sum=2*carry+rhs equations, then sums the inconsistent dependency and divides even coefficients against an odd right-hand side.

**Underlying structure:** For y_i=a_i OR b_i, expanding a three-variable XOR produces13clauses for odd parity (one width6 plus12width4) and14for even (six width5 plus eight width3). The quotient works only when every recovered block actually enforces that relation and permits the representative normalization. Counts alone are not semantic premises. GF2 inconsistency gives a set of equations whose left sides cancel and right sides sum to1; PB carry variables certify the integer parity contradiction.

**Wassat coverage:** portfolio.w already recovers complete parity blocks and narrowly certified near-ternary groups, compresses actual coordinates, runs bounded dense GF2 and checks SAT lifts. Its fast-only inconsistency is not the same exported PB parity certificate. parity_sum.w recovers explicit parity/cardinality shadows; xor_format.w handles explicit XOR syntax. Distributed OR atoms have no dedicated OR gates in these CNFs, so ordinary gate closure does not supply this decoder. Add a checked quotient to shared GF2 rather than another Gaussian engine.

**Learn for Wassat:** Validate complete distinct canonical13/14patterns or prove every required abstraction implication before accepting OR-pair GF2 rows. Reuse existing GF2 dependency tracking with a shared PB parity/carry certificate and justified OR representative normalization. Recover paired atoms and equation blocks from incidence rather than adjacent IDs/contiguous clause order. Keep full model replay and proof checking on both positive and negative candidates; a feature profile never substitutes for semantic certification.

**Improve LymphoSAT:** Reject count-compatible impostors before any UNSAT publication; the new direct false proposal has a concrete SAT witness and rejected proof. Check all distinct patterns, repeated literals, signs, pair supports, strict DIMACS counts and proof stream completion. Bound dense bitset storage, per-row dependency growth, proof size and total elapsed work; no internal resource/cancellation budget exists. Compress actually participating pairs and avoid normalizing unused declared pairs, reducing extension units and bitset dimensions.

**Certificates and evidence:** Two independently generated contradictory OR/XOR systems, including within-block permutations, each emit an accepted2977B proof. A consistent system yields a complete valid model. A count-compatible all-positive duplicate-clause impostor has an explicit all-true SAT model, yet the direct original worker reports UNSAT; VeriPB rejects its first post-normalization RUP step. This probe bypasses the narrow feature matcher and does not establish a verified-outer wrong verdict. Random GF2 kernel checks1000systems/64000assignments,478valid solutions and522valid inconsistent dependencies. Independent128valuation check confirms the13/14canonical expansions. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/068-or_randxor.json`.

### 69. ordering-principle

Choose a permutation repaired by swapping any missing triple middle that occurs earlier than both endpoints. Proof loop, however, removes active.back, reversing that guard. For each remaining vertex it emits a combined successor clause then removes eliminated-vertex literals one at a time by RUP, until two opposite successor units contradict antisymmetry. UNSAT-only; stream open checked but close/write success and elapsed work unbounded.

**Underlying structure:** A finite strict transitive relation cannot give every vertex a successor. Vertex elimination replaces a path i->z->j by i->j; antisymmetry closes i->z->i. Missing transitivity is safe when its middle is not eliminated before both endpoints. The runtime guard describes forward permutation elimination while the actual proof proceeds backward. This can invalidate a certificate without making the recovered formula satisfiable: a valid forward order still proves UNSAT.

**Wassat coverage:** No dedicated strict ordering-principle relation decoder/refuter was found in current Wassat. cyclic_order.w is a bipartite circular-bandwidth SAT proposal, a different problem. Generic CDCL, bounded variable elimination and hinted proof logging can solve tiny instances but do not supply this cubic structural theorem. The same checked high-level elimination can serve plain and sparse/XORified ordering once clause provenance is recovered.

**Learn for Wassat:** Implement a shared checked finite-order refuter with actual signed edge/row/transitivity provenance and bounded elimination. Derive each restricted successor row directly by RUP with only required antecedents, reducing proof lines; independent n5prototype cuts30steps/1010B to10steps/325B. Use sparse/min-fill predecessor replacement from review70 to limit fill and accept a checked contradictory substructure plus extra clauses.

**Improve LymphoSAT:** Make proof iteration and missing-middle guard use the same elimination direction; two accepted shapes currently emit rejected certificates. Replace combined-clause literal-by-literal shrinking with one direct RUP restricted row when all required transitivity premises hold. Bound triple enumeration, missing-list storage, greedy repair and proof size; recover row clauses without width-only classification so n<=4works. Check stream completion and strict DIMACS literal/count/empty-clause handling; tolerate valid extra constraints when a certified core suffices.

**Certificates and evidence:** Full n5 and signed-renamed/shuffled n5 proofs accepted (1010B/1067B). Three one-clause deletion probes also accepted. Two broader deletion patterns pass recognition but their1010B proofs fail VeriPB RUP. Independent forward elimination, deriving each restricted successor row directly, gives accepted325B/10step proofs for both and the complete case, compared with30original RUP steps. Thus true UNSAT, rejected original certificate, and a checked simpler construction are distinct. Wassat qualified private CLI refutes complete and one deficient case with independently checked WRAT proofs. No competition-scale replay. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/069-ordering-principle.json`.

### 70. ordering-principle-xor

Introduce y_h=XOR(odd,even) by four RED extension clauses. Lift high-level clauses lazily in small pbc subproofs using the complete rail expansion and CP pair cancellation. Sparse predecessor sets are updated by choosing the least projected fill vertex, resolving its row through transitivity/antisymmetry and then replacing each affected predecessor. Annotated RUP steps name their two parents rather than scan the whole low-level CNF. Exceptions/write failures return UNKNOWN.

**Underlying structure:** XORified clauses are a nonlinear substitution of an ordering formula, not a linear GF2 system. Equivalence definitions plus complete truth-pattern blocks permit a faithful quotient. Sparse no-minimal rows still contradict a finite strict transitive relation; elimination must propagate predecessor sets without introducing self-loops. Lazy clause lifting and parent hints keep the certificate tied to exactly the required source premises.

**Wassat coverage:** No fixed/sparse ordering-principle theorem or general XOR-substitution quotient was found in Wassat. portfolio.w handles explicit complete GF2 equations, while xor_format.w expands explicit XOR syntax; neither recovers clauses over substituted XOR atoms. Existing gate/signed-equivalence machinery and generic proof logging offer infrastructure only. Pair this decoder with review69shared high-level elimination and a reusable Boolean-substitution proof backend.

**Learn for Wassat:** Build reusable checked Boolean-pair quotient lifting for XOR and OR atoms, keeping their different semantic/normalization obligations explicit. Reuse a shared finite-order engine and min-fill predecessor updates; lift only transitivity clauses actually used. Export explicit antecedent hints from the semantic derivation to avoid repeated full-CNF propagation during proof checking.

**Improve LymphoSAT:** Normalize within-pair rail order and high-level clause order before grouping; recover pair incidence/layout rather than fixed adjacent IDs. Accept only required transitivity clauses for a checked elimination rather than insist on the entire dense skeleton. Use a total cancellation/work/memory budget during parse, grouping, dense skeleton checks, extension definitions and elimination. Generalize source degree beyond exactly3 and preserve original clause IDs under robust strict parsing; avoid dropping empty clauses before header validation.

**Certificates and evidence:** Independent n4three-predecessor encoding has24vars/248clauses: original and globally shuffled formulas emit accepted12094B/12106B proofs. Reversing each clause literal order and deleting one expansion row both decline. Wassat private CLI proves the complete tiny instance, with independently accepted55159B WRAT; proof dialects and engines differ, so bytes are descriptive, not a speed/scale comparison. Original README n38..42timings were not replayed. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/070-ordering-principle-xor.json`.

### 71. p-center

Repeated full-database unit closure and two-polarity failed-literal tests in ascending variable order. On an entailed unit, log it and restart scanning; root implied values remain internal to each propagation call rather than persist in the outer assignment. At most max(1000,4*nv) rounds, no wallclock/cancellation. Store proof lines in memory and emit only if accumulated RUP units reach contradiction. SAT inputs return UNKNOWN.

**Underlying structure:** Failed literal F AND NOT l unit-refutes implies F entails l; a sequence of such RUP units plus a final root contradiction is valid independently of p-center geometry. The underlying capacitated/facility-cover problem could justify stronger set-cover/counter bounds, but this active worker never reconstructs locations, distances, radius thresholds or center budget. Validated literal templates are safe proposals, not general mathematical specialists.

**Wassat coverage:** preprocess.w already runs root UP, occurrence-prioritized two-polarity failed-literal probes on a reusable watched trail, unconditional unit proof logging, reason chains, HBR/SCC/subsumption/BVE and tick/deadline checks. solver.w provides generic proof-covered CDCL. This is stronger reusable machinery than rescanning whole CNF for memorized candidate units; no new p-center decoder should be credited. A real specialist would share counter-cover/quota machinery after recovering actual covering/cardinality constraints.

**Learn for Wassat:** Keep the existing generic probe engine; compare occurrence/counter-aware candidate ordering under equal budgets instead of adding fixed unit templates. For actual p-center specialization, recover radius-neighborhood covering rows and center-budget counters, then reuse checked cover/capacity or model-search infrastructure. Preserve short hinted unit proofs and separate mathematical decoder coverage from an easy-UP family profile.

**Improve LymphoSAT:** Use watched/occurrence propagation, reusable rollback trails and persist genuine root closure instead of repeated assignment copies/full scans. Replace fixed literal IDs and first-negative-clause offsets with input-derived covering/counter roles. Bound total literal visits and elapsed time, not only successful-unit rounds; SAT instances can require2*nvwhole-CNF probes with no progress. Check close/flush errors in addition to stream state before destruction; publish proof atomically after completion.

**Certificates and evidence:** Fresh root contradiction110B, two-sided failed-literal contradiction126B and an explicit empty clause110B all pass VeriPB. Satisfiable control with an independent model returns UNKNOWN. Private Wassat proves both contradiction controls and solves the SAT control with a complete valid model. Current-source focused preprocessing suite is recorded separately; no fixed public template or actual p-center file replay. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/071-p-center.json`.

### 72. pebbling

Watched blockers over a uint32 arena, first-UIP with recursive minimization, heap VSIDS decay0.85, phase saving seeded by Jeroslow-Wang weighted polarity, LBD-protected clause reduction and recent-since-restart versus global LBD trigger after20conflicts. Emits buffered VeriPB v2 RUP clauses and learned deletions. Arena space is never reclaimed. The540s check occurs only every4096conflicts; long propagation/decision-only work is unbounded by it. No structural pebbling DAG/substitution recovery.

**Underlying structure:** A true pebbling contradiction says all source vertices hold, every predecessor conjunction implies its child, and a sink is false. OR-substitution hides these Horn facts behind disjunction rows and Cartesian implication clauses. Recovering the DAG/rows would permit forward semantic propagation and compact row proofs; generic CDCL can solve it without understanding that structure. Parameter timings in the README describe their runs, not a transferable improvement to Wassat.

**Wassat coverage:** solver.w already has flat typed arena/watch storage, first-UIP/minimization, saved phases, LBD-guided stable/focused schedules, tiered learned reduction, deletion proof logging and arena compaction in proof-free/DRAT modes; WRAT/LRAT use directly derived antecedent hints. preprocess.w supplies bounded BVE/subsumption absent in active reference. Copying a separate generic CDCL adds little. No dedicated input-derived pebbling-DAG/OR-substitution theorem was found; that could share the Boolean quotient/certificate infrastructure identified in reviews68/70.

**Learn for Wassat:** Recover actual source/child/sink clauses and substituted disjunction rows, then derive high-level pebbling facts with checked original-clause provenance. Measure phase weighting, restart cadence and proof-deletion cost on decoded subfamilies using existing Wassat controls, with SAT/UNSAT regression coverage; do not transfer a single tuned profile globally. Share quotient proof lifting and compact semantic row propagation instead of introducing another generic engine.

**Improve LymphoSAT:** Preserve explicit empty clauses and strict bounds/counts/terminators; fresh empty-clause input currently causes a false SAT proposal. Open/init and finish proof output for root-unit contradictions too; return a qualified failure if requested proof creation fails. Reclaim dead arena space or account for monotonic retention; check allocation/size arithmetic and full-width proof IDs. Poll cancellation during parsing, propagation and decisions, not just every4096conflicts; check fwrite/fclose results. Replace large variable-length stack buffers and platform-specific build assumptions with checked bounded reusable buffers/portable builds.

**Certificates and evidence:** Independent OR-pair substituted height4pyramid (20vars/30clauses) receives an accepted442B VeriPB proof; removing one sink negation gives a complete valid model. Contradictory root units return UNSAT without creating any proof because file opening occurs after that branch. A strict DIMACS empty clause is discarded and returns SAT with an invalid original-input model. These tiny direct cases bypass matcher admission. Private Wassat proves pyramid and both root/empty controls with accepted WRAT, and solves the SAT control. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/072-pebbling.json`.

### 73. petrinet-concurrency

Greedy dense-bitset clique search first. A checked K+1clique yields polynomial pairwise-AMO cutting-planes aggregation per color, summed with original row ALOs; intermediate proofs are deleted and fclose checked. Otherwise constrained DSATUR-style greedy colorings and min-conflicts recoloring run under585s, with neighbor/color counts and periodic conflict-list rebuild. SAT rereads every original clause and actual declared count before model publication.

**Underlying structure:** A verified K+1clique demands K+1selected colors but each color can serve at most one clique vertex. Prefix list domains only strengthen this obstruction. For SAT, negative pair constraints allow thinning any assignment to one chosen literal per positive domain. An incomplete color bundle is not a full graph edge: over-completing it can suppress SAT candidates, even though final model/proof checks prevent an incorrect publication.

**Wassat coverage:** coloring.w already checks complete color-conflict bundles and bounded clique witnesses on explicit full-width choices; AMO-cover/capacity reasoning is broader than graph coloring, fast-only without exported PB. Prefix-shortened rows/units are not identical to that recognizer and can require preprocessing or a different checked core. domain_walk.w has finite-domain tabu/weighted walks; domain_sparse_decode.w supports positive mixed-width/unit domains and negative binary exclusions without requiring AMOs, but its default large-arm plan requires first/max width8..32 and other admission caps. Reference adds a direct list-color graph policy and PB proof, not a new counting theorem.

**Learn for Wassat:** Attach polynomial AMO/capacity PB export to existing checked Wassat witnesses and actual ALO IDs, shared with prior pigeonhole/Hall reviews. Use recovered list domains and graph saturation/least-constraining-color proposals in the existing domain engine; preserve short prefix domains and actual incomplete constraints. Compare dense bitsets with sparse CSR incidence by density, profiling clique detection, candidate scoring and replay separately.

**Improve LymphoSAT:** Keep color-specific edge masks through recognition rather than strengthen any partial bundle to a full edge; after precheck failure continue a valid residual SAT search. Make initial positive row recognition independent of clause order and color/vertex numbering; recover actual signed domains. Bound dense adjacency allocation and clique search under one deadline; current clique phase precedes the585s search timer. Use sufficiently wide neighbor counts (uint16 can wrap beyond65535neighbors) and incrementally maintain the conflict set rather than4096step stale rebuilds.

**Certificates and evidence:** Independent K3/two-color and K4/three-color prefix-list encodings emit accepted386B/991B proofs. A two-color path gives a complete valid model. A partial color bundle plus duplicate preserving the global count has an explicit valid coloring but returns UNKNOWN after clique precheck rejection. Current Wassat coloring4/4focused examples pass, including partial-bundle controls. No actual Petri-net concurrency model or competition performance replay. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/073-petrinet-concurrency.json`.

### 74. philips

Depth-first branch only on the20proposed primaries. Each branch runs watched propagation on the original CNF; conflicting cubes emit their blocking RUP clauses, child proofs resolve to a parent and are deleted. If a full primary assignment does not unit-refute, return UNKNOWN; never publish SAT. Root conflict has a proof.585sdeadline sampled on leaf-count multiples, with no polling inside long propagation. No multiplier identity/arithmetic proof is recovered.

**Underlying structure:** If F AND cube unit-refutes, the negated cube is RUP. Exhausting both truth values for a variable and resolving the two clauses is a valid quantified case split even if the input heuristic was imperfect. Twenty inputs mean up to2^20leaves and roughly2^21RUP clauses: verifier database scans can dominate. A signed multiplier model is only the profile here, not a mathematical premise of the proof.

**Wassat coverage:** multiplier.w::wassat_and_xor_circuit_unsat? already explicitly targets marijn-Philips20input cases: complete signed AND/parity grouping, one checked binary target and64lane enumeration within6000vars/10000clauses. It is called by the fast CLI. This makes the family-specific existing overlap stronger than wide_circuit alone; exported cube proofs are still absent. wide_circuit.w already recovers complete signed AND/parity relations, enumerates up to24participating free inputs in64-lane batches, ignores unused declared IDs, and bounds total work/deadline; its exhaustive verdict is fast-only, not an exported case proof. circuit_cones.w already supplies retained assumption CDCL with lifted original-variable DRAT consequences. A general checked BCP backdoor/cube-certificate lane could combine these rather than repeat a fixed20-input detector. Generic gate congruence/local cuts may shrink proof dramatically before enumeration.

**Learn for Wassat:** Use existing signed gate recovery and wide simulation to propose bounded primary backdoors; export only original-CNF BCP/conflict-derived lemmas. Reuse learned lemmas across cubes and minimize contradictory assumption cores to replace repeated large truth trees. Emit explicit antecedent hints and delete resolved children; measure verifier time/bytes together with solver time. Seek local carry/weight or cone equivalences in actual multipliers before paying2^20enumeration.

**Improve LymphoSAT:** Recover actual input/definition dependencies instead of exact counts and degree20; preserve no-verdict behavior on unsupported leaves. Cache exact gate tuples rather than hash-only dedup, and bound all literal/header parsing and EOF cases. Check proof stream writes/close and poll a work counter during propagation/branching rather than only leaf multiples. Replace repeated full cube clauses with smaller conflict cores/hinted steps and shared unconditional learned clauses.

**Certificates and evidence:** Independently generated detector-shaped CNF has the exact counts1029ANDs/342parity groups/20high-incidence inputs; contradictory parity rows give an accepted289B input-cube proof. A consistent shape-compatible case has a full independent SAT witness and returns UNKNOWN. This is a dispatch/backdoor proof control, explicitly not a real Philips multiplier or the million-leaf path. Current Wassat wide-circuit12/12pass. Original README308–357MBproofs/279sverification timings were not independently replayed. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/074-philips.json`.

### 75. phnf

At<=10000rows, MRV backtracking with singleton propagation runs first. Critical bug: assign[r] stores a local domain index, but propagate uses it directly as a global choice ID in adj[ch]. Exhausted search writes a >=1unchecked assertion as its contradiction. Clique-cover fallback likewise ASSERTS each AMO instead of deriving it. SAT local min-conflicts fallback and final original-CNF replay are present, but safe SAT validation does not repair false UNSAT search/certificates.

**Underlying structure:** Choose one signed literal per row with no forbidden pair: an independent transversal. Clique-cover counting is sound only when each clique AMO is actually proved. Local row indices, global choices, and variable IDs are different coordinate systems; confusing them can prune real solutions. A single width32row also overflows/truncates the uint16domain construction, making a satisfiable row appear empty.

**Wassat coverage:** block_csp.w already has exact MRV/singleton search with the correct block_vars[row*width+local_choice] mapping, full residual checks and final model replay; it requires4..300positive exact-one blocks, widths2..24 and10000vars. Thus the9variable3row control is outside that helper admission, while the four-row extension tests the actual engine. domain_walk/sparse workers provide bounded tabu/weighted SAT search, but positive-only decoding and admission caps leave signed/larger-domain extensions. Existing coloring.w already checks signed clique-cover witnesses; exporting real proofs is the missing piece, never an asserted axiom.

**Learn for Wassat:** Normalize signed row literals into a shared finite-domain decoder and reuse existing exact/tabu search with original-CNF reconstruction. Attach checked decision/propagation reasons to exact search and derive branch-blocking clauses or reuse proof-covered CDCL; exhaustive state search alone is not an exported certificate. Share real polynomial clique-AMO/PB counting proofs from reviews66/73rather than assertions. Require unconditional verified checker status and no unchecked assumptions at every proof acceptance boundary, including process wrappers.

**Improve LymphoSAT:** Map row-local indices through row_choices before adjacency lookup; add renamed/reordered multi-row SAT controls. The new9/12variable false UNSAT cases isolate this bug. Enforce a checked domain width or use a sufficiently wide/multiword domain representation; width32SAT is currently misclassified. Replace asserted contradictions and asserted clique AMOs with checked RUP/CP derivations. Default checker exit0 does not certify a proof under assertions. Fix verified outer acceptance to reject conditional/under-assertion results even if exit0; exact original function replay confirms the hole. Poll time/cancellation during propagation and small-node scans; check proof creation/write/close and strict declared counts.

**Certificates and evidence:** Three independently SAT controls (three-row9variable A/B/Crelations B=A+1mod3,C=A; four-row extension; single width32row) all report UNSAT and write107B asserted contradictions. VeriPB exits0 but reports UNDER ASSERTIONS UNSATISFIABLE with unchecked warning, not VERIFIED. True PHP4/3also produces only that assertion. Independent rows give a complete valid SAT model. Private Wassat returns valid SAT models for the9variable and width32controls. Direct original verified run_and_maybe_return, verification enabled with native VeriPB3.0.2, accepts the false9variable UNSAT and returns20: matcher registry is bypassed, so not a profile-routed competition replay. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Current-source block-CSP helper declines the3rowfixture by its nb>=4admission gate; on the4rowextension it returns SAT in3nodes with the independently known valid model [1,-2,-3,-4,5,-6,7,-8,-9,10,-11,-12]. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/075-phnf.json`.

### 76. pigeon-hole

Plain SAT matches pigeons to distinct holes or shares one missing-exclusion pair and fully checks the model. Plain UNSAT derives polynomial per-hole AMOs then sums demand/capacity; insufficient strength returns UNKNOWN. RPHP introduces z=selected_element AND color, certifies selected count>=k and<=k-1via RED/RUP/CP. Ternary PHP derives at-most2on every larger subset from all its predecessor subsets, exponential proof volume capped25Mlines and500s checks between whole subset levels. No shared total parse/detect/certificate budget.

**Underlying structure:** Direct PHP is Mobjects versus Nresources. Missing AMO pairs change a resource capacity by its conflict-graph independence number, not merely one extra slot per affected hole; three mutually compatible pigeons can share one hole. RPHP factors through selected relays but preserves the same injection count. Complete forbidden triples imply capacity2. A polynomial extension proof can use zi=xi AND new, whose pairwise exclusion follows from triples, combine AMO(z) with the old prefix capacity2 and divide to extend the prefix. This avoids enumerating2^Mall subsets.

**Wassat coverage:** coloring.w already handles signed explicit-choice AMO-clique covers and some saturated-relay RPHP reductions. relay_count.w already directly recognizes scrambled-sign choice->relay->token injection and checks conditional quaternary exclusions under work/size caps, so the main RPHP mathematics is ALREADY present. It is fast-only and does not decode split ternary conditional-AMO/ALO chains or export RED/PB proofs. capacity_clique.w adds bounded indirect pair-conflict capacity reasoning. No complete triple-hyperclique capacity2decoder/proof was found; binary PHP/generic GF2 or arithmetic-coloring are different encodings/theorems.

**Learn for Wassat:** Export the RED selected-relay/token proof from existing checked relay_count witnesses, sharing AMO/PB machinery rather than add a second RPHP solver. Decode complete ternary capacity2groups with actual literal signs and certify them using the independently tested polynomial guarded-product construction. Add checked chain-clause projection for split ALOs/conditional conflicts and maintain original clause/definition provenance under sign renaming. Use bounded matching/independence reasoning for incomplete resource conflicts, preserving complete SAT replay and no verdict on exhausted capacity search.

**Improve LymphoSAT:** Validate actual binary/triple polarities against selected row literals; absolute-variable graph structure admits the reproduced SAT impostor. Replace exponential all-subset capacity2proofs with polynomial prefix/extension construction; fresh accepted prototype halves bytes on n9and improves asymptotic growth. Treat missing-exclusion resource capacity via actual compatible subsets rather than the number of affected holes; the three-share control is SAT. Normalize signed domains structurally instead of degree-based flip guesses; handle N<=2plain and N<=3ternary without clause-width ambiguity. Preserve empty clauses, strict counts/literal bounds/termination and add a shared deadline to Python detection, clique/matching search, large subset levels and output.

**Certificates and evidence:** Five accepted original proofs: standard PHP4/3(323B), signed shuffled functional PHP4/3(326B), ternary PHP9/4(62384B), direct and x/y-polarity-flipped RPHP4/3/2(2061B each). Standard PHP3/3and one missing AMO both yield full valid models. A checked SAT case allowing three pigeons in one hole returns UNKNOWN after an insufficient capacity proof. An all-positive-binary impostor is SAT but reports UNSAT; VeriPB rejects its proof. Independently derived polynomial capacity2proof passes VeriPB on the same ternary fixture:885derived constraints/29485B versus original1531/62384B. No Wassat integration or competition timing claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Current-source relay_count returns status-1on both canonical and x/y-flipped RPHP controls, accepting3choice clauses into2classes over4relays/8nodes. The main RPHP theorem is directly demonstrated as existing Wassat coverage, not just inferred from comments. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/076-pigeon-hole.json`.

### 77. planning

Separate binary implication lists with tagged binary reasons, arena long clauses/blocker watches, heap VSIDS/phase saving, first-UIP recursive minimization, LBD EMA restarts and learned-long-clause reduction. Iterated root failed literals run under an outer<=10s/probe cap. Proof is streamed in16MBchunks, capped4GBoutput; deleted long clauses have proof IDs. Binary conflicts allocate fresh arena clauses, and neither deleted long space nor learned binary edges are reclaimed.575ssearch deadline is sampled only on16384-decision boundaries.

**Underlying structure:** These are generic resolution/propagation techniques, not a planning-family theorem. A real planning decoder would need certified state transitions, action mutexes, time horizons and frame conditions before using reachability, distance or resource invariants. Binary density alone says nothing about those premises. The default negative phase is an action-sparsity heuristic only if actual variables represent actions; here it is simply the generic initial polarity.

**Wassat coverage:** solver.w already provides packed binary/watch propagation, typed arena/first-UIP/minimization, saved phases, LBD stable/focused schedules, proof logging and safe reduction/compaction. preprocess.w has budgeted two-polarity probes plus HBR/substitution/subsumption/BVE. Reconfiguration/cyclic-order workers cover different graph problems, not a recovered arbitrary temporal planner. Another generic CDCL implementation adds little; any planning benefit must come from actual transition/resource structure or measured bounded policy selection.

**Learn for Wassat:** Retain existing binary-native CDCL/probing infrastructure; compare family policies only after equivalent budgets and SAT/UNSAT regression checks. Recover actual time/state/action/transition scopes and verify them before reachability/distance/resource cuts or structured plan proposals. Measure implication-edge traffic, propagation stalls, learned storage and proof verifier cost independently, rather than tune a second generic engine.

**Improve LymphoSAT:** Avoid allocating a persistent arena clause for every binary conflict; reuse conflict scratch or explicit binary antecedents. Compact dead long clauses and account for never-deleted binary learned edges; preserve reason/proof identities through reclamation. Poll work/deadline in propagation and conflict-heavy search, not only decision-count modulo checks. Use a streaming tokenizer with strict bounds/count/EOF checks; the>2GBline path can split numeric tokens at fixed buffer boundaries. Check proof fwrite/fclose failures, retain bounded streaming and distinguish output budget from working memory.

**Certificates and evidence:** Five original proofs pass: root implication contradiction, two-sided failed literals, all8assignments blocked, explicit empty clause and valid post-header-comment contradiction. A generic SAT control returns a full valid model. No actual planning model, performance profile or time-layer theorem replay. Existing current-source preprocessing proof/propagation coverage was established in review71; no redundant full suite is counted here. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/077-planning.json`.

### 78. product-configuration

Small generic CDCL: watched propagation, first-UIP, activity bumps, linear scans of all variables per decision, geometric restart thresholds, no learned reduction/minimization/phase saving. add_clause allocates an nv-sized seen vector for every original and learned clause. Proof clauses are all retained in memory until UNSAT export; no search deadline/cancellation. SAT check scans only the retained prefix, so it cannot detect a silently skipped suffix.

**Underlying structure:** Shallow contradictions in implication-heavy CNF are well served by generic root closure/probing/CDCL. Product configuration would add actual feature implication/exclusion groups and quota/support reasoning after semantic recovery; this worker does not perform it. A model check is a certificate only for the complete original formula, not whatever a permissive partial parser happened to retain.

**Wassat coverage:** Wassat generic typed CDCL and bounded preprocessing already exceed this method and preserve proof/model reconstruction to the original input. quota_cover.w decodes actual aliases/row-major counters and counter_cover.w checks actual adders/cover rows; these are related reusable building blocks, not evidence that all product-feature semantics are decoded. The useful extension is a checked feature/domain/constraint view; a second simple CDCL is unnecessary.

**Learn for Wassat:** Use existing generic closure/probing for shallow implications and recover feature option/support/cardinality scopes only when their clauses are fully checked. Reuse counter/cover infrastructure and reason provenance for high-level bounds or proposals; retain original-CNF verification. Profile parse normalization, variable scans and duplicated proof storage before adding search complexity.

**Improve LymphoSAT:** Continue through standard DIMACS comments after the header, require complete termination/counts, and validate SAT against the original complete CNF. The fresh comment control is a reproduced false SAT. Reuse a stamped/touched-variable array instead of allocating and zeroing nv bytes for every clause. Stream proof output with checked completion, add one total resource/deadline budget and bounded learned-clause management. Use a heap/queue or existing solver policy rather than O(nv) every-decision scans, after actual profiling.

**Certificates and evidence:** Four clean controls emit accepted109B/126B/166B/109Bproofs (root, failed-literal, all8blocked, empty). A clean SAT control gives a complete valid model. A legal DIMACS comment between unit1and unit-1 stops the parser after the first unit: worker reports SAT with model1, violating the original formula. Private Wassat returns UNSAT with an independently accepted WRAT proof on that exact valid input. Direct tests bypass matcher selection; no competition performance claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/078-product-configuration.json`.

### 79. profitable-robust-production

Seed first selector true, all other selectors false, ten minimum bits false, first row bits false and every other row bit true. Build original watchers plus positive-clause incidence, remaining counts and a lazy min-heap; recursively choose a literal of the shortest unsatisfied all-positive clause, ordered by negative-minus-positive occurrence cost. Chronological rollback restores assignments/counts. Remaining variables are completed greedily negative-first with only current-variable retry; a later failure does not revisit earlier completion choices or min seeds. Full parsed-CNF replay guards SAT. No UNSAT output or internal deadline; pthread uses a256MBstack, not an explicit iterative search stack.

**Underlying structure:** The recovered block links selected rows to the same minimum and requires every unselected row to differ, with an ALO for selectors. All-zero selected row/minimum and all-one unselected rows give a useful canonical proposal, but other original constraints may require another selector or values. Positive-clause MRV targets demand choices rather than auxiliary Boolean noise. Fixing the seed is incomplete; successful positive closure also does not make a greedy remaining-variable assignment complete.

**Wassat coverage:** No PRP/Picat min-row decoder or shortest-positive-clause engine was found in current Wassat. model_circuit.w provides bounded model lifting; counter_cover/quota_cover handle different checked arithmetic/selection grammars, and generic CDCL already offers watched propagation, phase proposals and full model replay. A checked min/selector semantic proposal and demand-first policy add capability; the256MBrecursive stack and exact92clause/layout dependence should not be transplanted.

**Learn for Wassat:** Recover checked min/comparator/selector relations and use canonical extreme-value seeds as revisable proposals, with alternative selected rows and values. Add bounded shortest-unsatisfied-demand selection to the existing typed solver/domain infrastructure and compare it with generic branching on actual decoded PRP cases. Maintain positive counts/rollback in fixed buffers and bound lazy heap growth; separate min decoding, seed propagation, demand search, completion and full replay in profiling. Reuse input-derived arithmetic/production structure rather than force one selected row or assume all-zero/all-max satisfies all profit/boundary constraints.

**Improve LymphoSAT:** Make min seeds revisable; the alternate-selector SAT control currently returns UNKNOWN immediately. Recover roles from complete gate relations instead of fixed clause order, variable strides and a first-clause split heuristic. Use iterative bounded DFS with explicit work/cancellation checks; pthread stacksize256MBdoes not make recursion an explicit stack. Allow backtracking through remaining-variable completion and earlier positive choices when a later auxiliary constraint fails. Bound stale priority-queue entries and rollback records, check packed offset/index overflow and preserve strict original-input parsing.

**Certificates and evidence:** Private instrumentation records expected clauses from the original recognizer: two rows produce a60variable/185clause template, and the unmodified actual main returns a complete independently checked model. Adding unitNOT first-selector has an independently UP-lifted alternate second-selector SAT witness, but the fixed seed returns UNKNOWN. Swapping the first two clauses of the same template also declines. These fixtures are template-derived, explicitly not an independently implemented Picat encoder. Private Wassat finds a complete valid model for the alternate-selector case. Actual PRP benchmark timings/memory in README were not replayed. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/079-profitable-robust-production.json`.

### 80. purdom-instances

New composite products use64bit Miller-Rabin/Pollard-rho/divisor enumeration and generator simulation, mapped back by signed refinement. If recovered smaller input<=22bits and no factor pair fits, generate RUP binary gate resolvents and a no-good tree on the smaller operand. Default fast emitter skips per-leaf propagation and assumes the first negative LSB branch contradictory; PURDOM_BPROOF_CHECK=1or reverse-order uses actual BCP checks. Unsupported cases fall to generic watched CDCL/Luby with no clause deletion; optional SLS/branch modes are off. Proof writes/close and upstream recovery/factoring are not under one total deadline.

**Underlying structure:** Actual unsigned multiplication plus target units permits input-derived factor candidates. A no-fitting-factor claim needs complete qualified factorization and verified circuit equivalence; a failed heuristic factor search is insufficient. A valid original-CNF RUP tree is the final certificate even if its generator omitted internal checking. Odd product forces both operand LSBs true and lets the smaller-input tree prune its even half, but arithmetic UNSAT alone does not prove each proposed leaf is RUP. Nine first-prime Miller-Rabin bases are not deterministic for the full recovered62bit range.

**Wassat coverage:** multiplier.w already recovers complete canonical four-clause gate DAGs, checks partial-product incidence, factors within a trial budget, evaluates/replays SAT models. It also has a checked fast-only weight-conservation/no-fitting-divisor theorem for a different balanced3clauseAND/4clauseXORadder grammar; do not label all arithmetic UNSAT reasoning missing. Purdom adds signed/shuffled topology/generator recovery, unequal input widths, fwcarry/mux variants, wider factoring and a clausal smaller-input proof. circuit_cones.w retained queries and generic proof logging can supply reusable original-CNF certificates without storing a new known-product catalog.

**Learn for Wassat:** Generalize shared checked gate/signed topology recovery and operand/output maps so shuffled multiplier instances use the existing input-derived arithmetic engine. Use a reusable bounded smaller-input backdoor/query certificate path with actual learned cores and explicit antecedents; share across reviews65/74/80. Replace fixed product/factor candidate priority with recovered targets and a qualified bounded factorization service. Profile recovery refinement, factorization, gate lemma generation, tree bytes and verifier work separately; arithmetic PB weight identities may avoid exponential Btrees.

**Improve LymphoSAT:** Replace the nine-base64bitprimality claim with a proven-range deterministic base set or certified factors; retain unsplit composite/exhausted-rho status rather than calling it a prime factor. Verify the final signed clause multiset/isomorphism before using recovered arithmetic semantics, especially when40refinement rounds are exhausted. Keep checked generation or independently validate every emitted proof before unverified UNSAT publication; fast tree leaves are proposals until RUP checked. Use one deadline/work budget for shape regeneration, color refinement, rho/divisors, gate resolvents, tree generation and fallback; modulo-only polling can miss long work. Check proof completion and enforce defined widths/packed arithmetic, with no-factor conclusions only from complete factor coverage.

**Certificates and evidence:** Original generator-based fixtures cover products17and31UNSAT, new composite21SAT, and nc/nw/fwarchitectures. Nine UNSAT proofs pass VeriPB: six default plus three checked31variants; checked/default31proofs are byte-identical in all three layouts. Six complete SAT models pass (canonical and signed/clause/literal shuffled21for each layout), exercising input-derived recovery beyond fixed catalog. A direct kernel labels composite3825123056546413051as prime and wrongly reports no fitting61/31bitfactor pair, although factor149491and its cofactor fit. This62bitcase is OUTSIDE smaller-input<=22fast-proof admission, so it is a SAT/factoring coverage defect, not a reproduced active false UNSAT. Original large prime proof/verifier timings were not replayed. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Current-source direct helper constructs valid canonical product21models for nc(52vars) and nw(50vars), but returns no model for fw. Its wassat_factorize_unsat? helper declines all three product31formats. This directly confirms existing model overlap and the grammar-specific arithmetic-proof gap. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/080-purdom-instances.json`.

### 81. pythagorean-triples

Weighted min-conflicts over merged constraints, random-walk noise and age ties. Candidate scores rescan incident constraints rather than cache every variable score. When only1..4violations remain, bounded focused DFS locks each flipped variable, ranks candidates by unweighted incident improvement and repairs up to18/24flips with80k/250knodes. A deterministic seed portfolio gets up to585s, but focused repair has no wall poll. Full original parsed-CNF model check guards SAT; no UNSAT proof/output.

**Underlying structure:** Complementary monotone clauses enforce a nonmonochromatic3hyperedge. Cube-fixed endpoints leave one-sided binary color exclusions, which can destroy global complement symmetry. Merging a NAE pair reduces representation/occurrence overhead while maintaining the actual coloring objective. This is a useful syntax-level family independent of original arithmetic numbering; a mathematical Pythagorean map is unnecessary for SAT proposals, but cannot be assumed for an UNSAT theorem.

**Wassat coverage:** sls.w already has native CCAnr/configuration checking, weighting, incremental counts/scores and SAT validation. nae_count.w has exact count/XOR-based monochromatic propagation/rollback, while nae_decode.w currently requires complementary arithmetic-progression scopes and caps700vars. arithmetic_coloring.w recognizes Pythagorean/other arithmetic scopes under700element/width/work caps; renamed reduced cube binaries need not satisfy that geometry. Reference adds merged-NAE SLS/near-solution repair and broader cube syntax, not a number-theoretic Pythagorean algorithm.

**Learn for Wassat:** Separate a checked NAE/binary syntax decoder from geometric classification for SAT-only search, including signed/renamed cube residues. Reuse typed incremental scoring and the count-based hyperedge representation, then add bounded focused repair when only a few violations remain. Compare merged pair weighting versus independent clause weighting under equal move/literal budgets; preserve cube-fixed restrictions and full replay.

**Improve LymphoSAT:** Pair complementary scopes by sorted exact keys rather than adjacency and elementwise order; harmless literal permutation currently loses coverage. Poll cancellation/deadline within focused DFS and charge incident work/candidate rescans, not only recursion nodes. Cache make/break or per-variable gains and update affected incidences instead of rescanning every candidate on every flip. Validate strict DIMACS bounds/counts/EOF and recover geometry only if a later mathematical theorem actually needs it.

**Certificates and evidence:** Fresh merged-NAE plus cube-binaries and two numerical Pythagorean scopes each receive complete valid models. Reordering only the negative triple literals makes the equivalent explicit-SAT formula decline because pairing is positional. No UNSAT or competition benchmark test. Fixed candidate arrays are not a newly established overflow: active main rejects raw clauses and admitted constraints have arity<=3. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/081-pythagorean-triples.json`.

### 82. railway-safety

Original-CNF BCP fixes primaries and gate targets. Random primary assignments determine the whole DAG; a primary flip reevaluates only affected fanout events and updates mismatched targets. Descend from bad targets, score temporary primary moves near a solution, save/perturb best states, and try bounded pairs/triples/macros among up to32/64primaries.500sof up to285srestarts precede an85sraw-clause repair that rescans the complete CNF per candidate. A separate Justifier class is inactive. SAT-only, full parsed-prefix CNF replay; no UNSAT certificates.

**Underlying structure:** Tseitin auxiliaries are functions of primaries. Searching only genuine inputs preserves all gate definitions and lets the objective focus on forced outputs/residual assertions instead of breaking arbitrary auxiliaries. Exact delta evaluation and rollback are essential on reconvergent cones. A functional decoder/model replay makes this a sound proposal even without rail-safety or transition semantics; it is a general circuit model engine, not a railway safety theorem.

**Wassat coverage:** Wassat circuit.w/model_circuit.w/small_circuit.w recover bounded functional circuits and enumerate/evaluate candidate primaries; dependency_circuit.w handles checked signed dependencies independent of numbering. circuit_cone_sim.w proposes equivalences for proof-covered queries rather than repairing SAT output targets. Generic SLS works in Boolean CNF space. No general wide-OR/LUT fanout-delta target-SLS/near-solution macro-repair engine was found; that is a distinct extension worth sharing with backdoor and model lifting infrastructure.

**Learn for Wassat:** Build a shared bounded primary-space model search over checked gate DAGs, with incremental fanout target/residual scores and complete original model replay. Reuse best-state/low-mismatch SAT repairs, but profile affected cone sizes and pair/triple repair cost before choosing move policies. Use compact typed gates/CSRfanouts and per-output targets, sharing decoder/provenance with simulation and proof queries. Measure decode/BCP, initialization, fanout updates, residual scans, exact candidate scoring and final replay as separate phases.

**Improve LymphoSAT:** Parse through legal comments and require the complete declared original input; the new false SAT is a parser-prefix defect. Recover definitions by checked output support, not first-literal contiguous grouping; retain duplicate definitions as constraints instead of silently replacing their gate model. Bound per-flip cone work, recursive descents and all pair/triple/macro loops under cancellation; nested repair can overrun the outer timer. Replace raw-repair full-CNF rescans with incidence updates and cap stale/repeated reconvergent queue work. Remove inactive Justifier/dead analysis code or make its use explicit; validate all literal bounds/header counts before graph arrays.

**Certificates and evidence:** A signed OR/XOR/LUT representative gives a full valid model; root contradiction returns UNKNOWN. A legal comment between unit1and unit-1 truncates parsing and the original main reports false SAT on the original formula. Private Wassat independently refutes it. Native kernel independently recomputes100random signed OR/NOR/LUT DAGs and target scores after12800incremental/undo flips: all match. No actual million-gate SNCF replay, measured speed claim or active Justifier credit. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/082-railway-safety.json`.

### 83. ramsey

Four-valued edge min-conflicts on monochromatic triangle violations, followed by original-CNF UPauxiliary lifting/full replay. Unsupported medium formulas get generic proof-logging CDCL, graph-variable-first decisions and the optional exact12propagator. That propagator directly logs clauses as RUP from assumed counts; it does not test RUP before using them. Generic stochastic fallback is skipped after a CDCL attempt. Backtrack(0) clears root assignments, another source-level concern. Full SAT check protects positive proposals but cannot justify an unproved degree bound.

**Underlying structure:** Four-color triangle-free complete-graph coloring is different from ordinary two-color R(4,4). A clean construction needs no search: in GF16, the15nonzero elements partition into three multiplicative cosets of an order5subgroup, each sum-free under addition; coloring an edge by the coset of its XOR difference gives a three-color K16without monochromatic triangles. Replace each vertex with a two-vertex clique in a fourth color to get K32; restrict to K30as needed. Recovering graph vertices/bit meanings is still required for arbitrary renamed CNF. Degree12is legitimate only from checked exact counters or derived Ramsey premises, never histogram evidence.

**Wassat coverage:** Wassat arithmetic_coloring/nae engines are two-color scope solvers; block/domain engines require explicit choices and do not decode these two-bit four-color comparator gadgets. ramsey_bound.w ALREADY computes and checks classical two-color recurrence/parity bounds, including R(4,4)<=18. ramsey_lex.w validates complete original clique families before symmetry operations. Thus four-color binary incidence and an input-derived algebraic constructor add capability; duplicated generic CDCL or unverified exact-degree inference does not.

**Learn for Wassat:** Recover complete binary color/difference gadget semantics and graph incidence, then apply the clean GF16/K2product constructor instead of stochastic search for compatible n<=32. For renamed inputs, reconstruct complete-graph vertex stars from edge/triangle incidence and align bit coordinates/signs before full model lifting. Share multi-color hypergraph costs/repair with prior No-L/rectangle opportunities, retaining exact forbidden tuples. Use existing checked two-color Ramsey bounds and attach certificates; keep mathematical degree/counter premises explicit.

**Improve LymphoSAT:** Validate actual degree counters or independently check every proposed degree lemma as RUP before installation; the new all-positive SAT impostor is misclassified. Preserve root assignments when backtracking to0and add reason/learned-clause consistency controls before trusting generic CDCL output. Use the finite-field product seed after semantic decoding; final CNF replay remains necessary under extra constraints. Maintain exact bad-set positions/incremental color costs instead of stale lists and repeated incident triangle rescans. Use shared deadlines across initial25ssearch, incidence search, lifting and fallback, with strict parse bounds/counts and checked proof completion.

**Certificates and evidence:** Independent guarded-XOR encoding of K4four-color constraints gives full valid models both canonical and variable/clause/literal-shuffled; output confirms the incidence recovery branch is used for the shuffled fixture. A300variable65795clause all-positive SAT input meets the runtime degree/width histogram and13root units trigger assumed exact12UNSAT; VeriPB rejects the209Bproof at its first RUPstep. Private Wassat solves that same SAT input. One generic binary contradiction gives accepted128Bproof. Independently derived GF16product validates30sum-free pairs,9060triangles across K30/K32and complete models of both representative162400/198400clause encodings, matching target dimensions. These are clean representative encodings, not original competition-file replays. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/083-ramsey.json`.

### 84. ramsey-numbers

On the first18vertices, REDvertex-permutation witnesses sort17pivot incident colors; global complement plus reversal fixes the ninth edge true, forcing nine red neighbors. Under that star context, use conditional R(3,4)=9CP: R(3,3)=6gives degree>=3while avoiding a blueK4gives degree<=3in a nine-vertex graph, contradicting odd degree sum. Lift local subset constraints by sum/divide, derive the negated star and an empty RUP. Proof is streamed through Python text writes/close; no total deadline.

**Underlying structure:** For R(3,4)<=9, any avoiding graph on9vertices has red degree<=3(otherwise4red neighbors force blueK4) and red degree>=3(otherwise6blue neighbors force a monochromatic triangle by R(3,3)<=6). All9degrees equal3, giving odd degree sum27, impossible. In18vertices every pivot has at least9neighbors of one color; symmetry reduces this to one fixed neighborhood. These are derived upper bounds, not imported threshold answers. REDrequires actual automorphism of the complete original family; extra constraints can break it.

**Wassat coverage:** ramsey_bound.w already derives R(3,3)<=6,R(3,4)<=9,R(4,4)<=18from base R(2,k)<=kand even/even degree-parity refinement, and validates every original clique through ramsey_lex_check before fast refutation. ramsey_lex.w supplies complete-family automorphism checking and fast-only transposition lex leaders. Reference adds a concrete RED/RUP/CPproof and targeted pivot-star/complement reduction, not new extremal mathematics. Existing Wassat proof modes bypass the fast count until there is a suitable exported certificate.

**Learn for Wassat:** Export the existing checked recursive degree/parity theorem through a reusable PBcertificate backend with original clique provenance. Use targeted pivot-neighborhood sorting/complement witnesses to reduce proof cases, after verifying full automorphism premises. Generalize the certificate by recurrence and parity instead of creating separate hardcoded threshold workers for each Ramsey pair. Measure generation and verifier work together; proof line/variable normalization is distinct from a faster mathematical solver.

**Improve LymphoSAT:** Accept a validated induced complete18vertexcore plus extra original clauses only when symmetry witnesses also preserve those extras, or refute the isolated core and lift its proof separately. Recover renamed edge maps and normalize multiline/standard DIMACS clauses, validating declared counts before assigning proof IDs. Add shared time/memory/proof-size budgets; current subset lifting can grow exponentially beyond these fixed small contexts. Support additional derived R(3,k)cases through the general recurrence/certified degree engine rather than matcher-only detection.

**Certificates and evidence:** Full independently generated R44n18(6120clauses) yields accepted870382Bproof; n19(7752clauses) and clause/literal shuffled n19give accepted876582Bproofs. Missing one block declines. Independently checked Paley17quadratic-residue coloring satisfies every4760clause and runtime declines by n<18, as expected. Current Wassat Ramsey-bound8/8examples pass, explicitly deriving6,9,18and checking complete original clique coverage. No new speed comparison or native Wassat PBbackend implementation. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/084-ramsey-numbers.json`.

### 85. ramseycube

Map the stored349201line RUP template to the checked core; if the template is unavailable, bounded incremental DPLL builds a branch-blocking RUP proof on the core. Other inputs get deterministic noisy min-conflicts followed by small exact search. Actual FastExactSolver restores trail, clause counters and propagation queue on rollback; the older ExactSolver class is unused. SAT replay is against parsed clauses, but the parser drops empty clauses and omits literal/count bounds.

**Underlying structure:** This is a forbidden-subgraph Ramsey problem, not a monochromatic clique threshold: a coloring of K9 cannot simultaneously avoid a blue Q3 and a red C4. Q3 has48automorphisms, so8!/48=840distinct labeled edge supports on each eight-set. A checked induced K9 core makes larger instances impossible. Renaming a RUP proof through an injective literal map preserves each implication; complete original-core inclusion is the soundness premise. The finite proof establishes the bound, without providing a new closed-form extremal argument.

**Wassat coverage:** ramsey_bound.w computes classical complete-clique recurrence/parity bounds and ramsey_lex.w validates clique families. arithmetic_coloring.w also requires scopes to be cliques or checked arithmetic shapes; a cube is not a clique. None of these provides complete Q3/C4 incidence recovery or a checked cube-core proof. Generic SLS/CDCL overlap, but not this certified forbidden-subgraph kernel.

**Learn for Wassat:** Build a shared checked forbidden-subgraph decoder and induced-core mechanism, recovering edge/vertex incidence before using mathematical bounds. Generate or derive a clean local certificate rather than importing the unlicensed stored template; verify core inclusion and injective signed maps. Profile certificate generation, text expansion and checker separately; reducing verifier work/proof size matters more than shaving the measured0.2semitter. Generalize graph-color model search to forbidden subgraphs as hyperedge scopes, with complete original-CNF replay.

**Improve LymphoSAT:** Preserve empty clauses and validate literal bounds/header counts; a reproduced false SAT remains outside the top-level feature matcher claim. Recognize cores from incidence directly instead of allocating a quadratic all-variable co-occurrence matrix and enumerating every nine-subset without deadline checks. Provide a checked symmetric Q3/Q3 refutation path or return UNKNOWN as now; count fingerprints alone cannot establish the theorem. Guard uint8 clause counters outside the narrow cube grammar and detect proof read/write/close failures before publishing UNSAT. Regenerate/compact certificates and measure verification cost; proof-template replay is not an online proof search improvement.

**Certificates and evidence:** Independently enumerated K9 has36variables and7938clauses. Original and variable-renamed/clause/literal-shuffled forms each produce a strictly accepted unconditional proof,42769629/42860343bytes. Local emitter time0.26/0.17s versus verifier7.43/9.05s: verifier work dominates these private controls, not a competition speed comparison. Independently generated symmetric Q3/Q3 K8 gets a complete valid model. Empty-clause plus unit is falsely declared SAT because the empty clause is discarded; qualified private Wassat returns UNSAT with an independently checked15BWRATproof. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/085-ramseycube.json`.

### 86. random

ProbSAT selects a false clause and samples a variable proportional to cb^(-break), with cb2.06,2.85,3.7,5.1,7,9.5,13,18for increasing k. Counts/false-set positions update by signed occurrences; break is rescanned from currently true occurrences. Generic first-UIP heap-VSIDS CDCL uses phase saving, minimized RUP clauses, LBD<=2protection, fixed512conflict restarts and database deletion. Despite an old comment, actual code writes the minimized clause, not learnedFull. Deleted clause literals stay in the flat pool, which has a hard200Mword cap.

**Underlying structure:** A break-only stochastic policy estimates how much damage a move causes, suppressing high-break moves exponentially. Random kSAT density relative to an empirical/estimated transition is a scheduling heuristic; it neither proves UNSAT above a threshold nor SAT below it. This differs from CCAnr configuration checking plus weighted make-minus-break, even though both search Boolean assignments. Very high break values underflow every exponential weight, producing a degenerate first-choice branch.

**Wassat coverage:** solver.w already has typed first-UIP CDCL, phase/restart/reduction machinery and direct hinted WRAT/LRAT/DRAT output. sls.w already uses normalized flat occurrence storage, cached weighted scores, true-count/critical-variable XOR and configuration checking, with safe empty-clause intake. Policy/portfolio already route small/dense random-like shapes. No named or matching per-k cb^(-break) sampling policy was found: this specific random-SAT move distribution adds diversity, not a new generic SAT engine.

**Learn for Wassat:** Implement and compare an optional ProbSAT move rule in the shared normalized native SLS kernel, reusing counts and incrementally maintained break scores. Compare policies on held-out random kSAT using equal wall/literal budgets and multiple seeds; retain CCAnr where weighting/configuration checking wins. Use transition ratios as bounded scheduling hints alongside observed progress, never as logical facts or filename fingerprints.

**Improve LymphoSAT:** Preserve empty clauses and strict bounds/counts/EOF; original parser/modelcheck currently certifies only a weakened formula on the reproduced case. Cache per-variable break scores on count0/1/2transitions and stabilize weight sampling with relative/log weights before all weights underflow. Size the fixed128score buffer from validated clause width or reject unsupported widths, and normalize duplicate literals/tautologies before local-search bookkeeping. Compact retired clause literals and budget actual memory rather than accumulating an append-only pool until a fixed hard cap. Use progress-based restart/time policy and bounded cancellation polls during parsing/building/scanning; reuse a shared fallback rather than maintaining another generic CDCL.

**Certificates and evidence:** Original main gives two accepted tiny UNSAT proofs and three complete planted3/5/7SATmodels. Dropped empty clause produces false SAT on original UNSAT; private Wassat independently proves the original. Exact original ProbSAT kernel on100normalized random3/5/7formulas passes12800flips and217600independent break checks;20actual short ProbSAT runs produce complete valid planted models. These are controlled normalized inputs and do not qualify arbitrary duplicates/tautologies or competition performance. Wassat packed-SLS state3/3focusedexamples pass. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/086-random.json`.

### 87. random-circuits

Main first attempts AVX512primary enumeration after structural support pruning: at most30/32participating primaries and3B/6Bvector-gate budget. Byte permutation implements up to8->8tables in64lanes using1/2/4segments. A surviving lane is scalar-forward-filled and original-CNF checked. Fallback scalar CSP enqueues incident gates, enumerates compatible relation rows, propagates bits common to all rows and branches on a gate with fewest rows; selected fanins get one-step lookahead. local_repair is defined but never called. No UNSAT verdict/certificate even after exhausted search.

**Underlying structure:** A truth-table block is one multioutput functional relation, not several independent Boolean clauses. Common bits across compatible rows support propagation in both directions, and branching on a whole row respects that relation. Restricting primary enumeration to the forced-output support removes irrelevant inputs, with complete graph definitions/topological support as premises. Wassat has analogous finite circuit reasoning, but currently with different relation families/arity limits.

**Wassat coverage:** structural_pruning.w already builds exact<=6variable truth tables from contained clauses, removes inconsistent rows for up to8rounds and exports common-bit units, missing-pair binaries and phase hints. model_circuit.w decodes bounded<=3input single-output functions; dependency/wide circuit engines enumerate checked AND/parity backdoors in64-bit batches. multiplier.w also has the marijn20input64lane refuter. These are substantial shared infrastructure, but none supplies this general up-to10input/10output table decoder plus queued relational DFS or AVXbyte-table evaluator.

**Learn for Wassat:** Extend the existing exact table substrate with checked functional multioutput blocks, queued incidence propagation and row branching, rather than create another separate CSP engine. Compress primary support of asserted outputs before bounded enumeration and reuse architecture-neutral64lane circuit scheduling with optional vector table lookup backends. Normalize relation variable/sign/order and preserve residual constraints, then lift and replay every original clause for model proposals. Evaluate row-domain propagation and model enumeration under common gate/literal budgets, separately from machine-specific SIMD speed.

**Improve LymphoSAT:** Support DIMACS comments and order-independent table grouping; try all feasible shape candidates and validate full parse completion/counts. Poll each SIMD worker by its local iteration count: with two strided workers, tid1only visits odd batches and never hits batch&65535==0. Trail queue/domain state or rebuild a consistent propagation queue at branch rollback; current assignment-only undo needs broader cyclic/reconvergent differential controls before stronger invariant claims. Cache compatible row domains/support counts instead of repeatedly rescanning2^faninrows in propagation, selection and lookahead. Use an architecture fallback and feature detection before unconditional AVX512; never infer UNSAT without certified exhaustive coverage.

**Certificates and evidence:** Host ARM cannot execute the original x86AVX512kernel. A private compatibility harness disables only that header/function; original scalar decoder/CSP/main remains unchanged. On160independent random2->2multioutput circuits, exhaustive primary evaluation finds120SAT/40UNSAT; scalar worker produces120complete valid models and40UNKNOWN, no mismatches. This does not test AVX512, wide tables, large support or the full submitted performance path. Current Wassat structural-pruning11/11focusedexamples pass, including exact small-table units/binary consequences. Additional40scalar controls cover32random4->4and8random6->6circuits:37complete valid models/3correctUNKNOWN, all matching exhaustive primary evaluation. Combined200cases give157SATmodels/43expectedUNKNOWN. AVX512remains unexecuted. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/087-random-circuits.json`.

### 88. random-clustered

Generic weighted min-conflicts computes weighted make/break from occurrences, prefers zero-break choices, adds3.5%noise and retains clause weights across random restarts. Unsatisfied weights rise to1Mwith occasional smoothing; no latent cluster labels or planted structure are decoded. Multiplier proposal uses15base Miller-Rabin and Pollard-rho on a<=64bit target, requires both discovered factors to have exactly nbits, tries both operand orders, then repeated full-CNFUP must assign every declared variable. SAT-only.

**Underlying structure:** The clustered arm is a landscape heuristic rather than a mathematical cluster solver. Multiplication is better solved in operand space: factor the input-derived target and deterministically lift the circuit. Full CNF replay makes this a safe positive proposal even when the unit-run interpretation is only a guess. Requiring exactly full-width factors and complete assignment by UP are coverage restrictions, not mathematical necessities for bounded-width multiplication.

**Wassat coverage:** sls.w already supplies native weighted CCAnr with incremental scores/configuration checking, stronger shared mechanics than rescanning candidates. multiplier.w already factors checked canonical AND/XOR/OR circuits with original-CNF replay; fermat.w has bounded Pollard-rho, occurrence-driven propagation, factor swapping and a separate toughsat factoring decoder. Its toughsat layout uses leading operand clauses/constants and paired tail constraints, not this longest-unit-run layout. Thus factoring/model lifting is already present; the new admission layout and64bit target reach extend coverage rather than invent the strategy.

**Learn for Wassat:** Generalize existing factor-then-lift decoding to contiguous product-unit layouts, with bounded factorization and original-CNF validation. Keep factorization/propagation shared across multiplier and Fermat layouts; support width-fitting factor pairs and harmless unused declared variables. Compare persistent weights across restarts and zero-break preference using the existing normalized native SLS kernel, measuring against CCAnr on held-out clustered instances. For actual cluster specialization, recover variable-interaction communities/backdoors and assess whether coordinated cluster moves improve progress.

**Improve LymphoSAT:** Handle empty clauses before random search; the reproduced valid input currently crashes. Bound and poll Pollard-rho by a shared deadline/work budget; nested up-to127seeds/10000constants/200000iterations are not a practical latency contract. Allow factors with bitlength<=operandwidth, explore alternative divisor groupings when needed and distinguish unconstrained variables from failed model lifting. Use occurrence-queued propagation and cached make/break scores instead of full-CNF repeated sweeps/candidate occurrence rescans. Validate EOF/zero terminators while parsing: a failed integer extraction inside a clause currently lacks an exit check.

**Certificates and evidence:** Three independently planted3CNFcontrols get full original-worker models. A true independently encoded16x16multiplier for65521*65519,1346vars/9314clauses, gets a complete valid model; adding one unused declared variable makes the same SATformula decline because UPdoes not assign that variable. Contradictory units return UNKNOWN. An empty clause is retained but reaches c.lits[0]and crashes(SIGSEGV)in the search picker; qualified private Wassat independently proves it UNSAT. Existing Wassat multiplier5/5focusedexamples pass. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/088-random-clustered.json`.

### 89. random-csp

Dense32bit forbidden-neighbor masks drive weighted min-conflicts. Incident-only moves maintain endpoint costs/bad variables; static value tightness breaks greedy-init/move ties. Near a solution, frozen-boundary subset repair uses AC3and MRVDFS on conflicted variables, then their neighbors, with30k/80knode caps and a shared deadline. Stagnation bumps weights on violated high-level edges; restarts reset weights.500sCSPsearch precedes a generic Boolean walk until590s. shake_conflict_neighborhood and hamming_repair are defined but inactive. Full parsed-CNF model lifting protects SAT; parser drops empty clauses.

**Underlying structure:** A CNF clause over two finite-domain groups removes exactly a product of falsifying value sets, allowing merged support clauses and forbidden pairs to share one relation matrix. Compact bit patterns and signed onehot values are different representations of the same domain search. Exact local repair must retain all boundary constraints; a locally unsatisfiable frozen region says nothing conclusive about the full formula.

**Wassat coverage:** domain_walk.w already has weighted finite-domain moves, cached all-value costs, tabu diversity, deadlines and complete original-model replay on verified positive exact-one domains up to32values. domain_sparse adds CSR exclusions/root pruning up to100kvariables, still positive choices/negative binary exclusions and max32values. block_csp.w handles positive exact-one domains plus arbitrary residual clauses with bounded DFS. Missing coverage is signed/compact domain-pattern decoding and compiling merged two-group clauses to exact relations, not the core min-conflicts algorithm. Frozen-fringe CDCLrepair already exists for Boolean SLS.

**Learn for Wassat:** Build one pattern-domain abstraction for signed onehot and compact bit blocks, deriving each relation from actual clause falsifying sets. Reuse native cached value costs/CSR incidence and existing search rather than copy the slower candidate-neighbor rescans. Add bounded AC3/MRVrepair over conflict domains while fixing boundary choices, or generalize the existing failed-assumption-fringe repair to domain decisions. Infer bit-group incidence and supported domains instead of fixing every compact encoding to contiguous5bits/17patterns.

**Improve LymphoSAT:** Preserve empty clauses, validate counts/literal bounds/EOF, and poll decoding/allocation as well as search. Require strict weak ordering in repair value sorting: its a==base comparator returns true even for a==b; use an explicit preference tuple. Use sparse relation incidence instead of n*n*max_domain storage and cache all-value costs/bad-set positions. Keep inactive shake/Hamming experiments distinct from active repair; enforce shared budgets while constructing potentially quadratic masks. Compare bounded repair and restart strategies on held-out hard FRBinstances; reaching one conflict is not a guarantee that the current neighborhood contains a solution.

**Certificates and evidence:** Three full original-worker models cover ordinary onehot, signed/renamed merged support, and compact5bit/17value encodings. Exact kernel comparison checks625+625+4913=6163whole domain assignments against every CNF clause, with matching relation semantics;6000weighted incremental moves/scores and three whole-subset AC3repairs agree with exhaustive solutions. Empty clause plus a supported onehot formula yields false SAT; private Wassat independently proves the original UNSAT. Wassat focused domain walk32,sparse14and blockCSP5examples all pass. No FRBcompetition timing claim. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/089-random-csp.json`.

### 90. random-mus

SLSsamples a variable in a false clause with weight(1+make)/(1+break)^cb, rescanning occurrences; saves the best assignment as CDCLphases. Although code advertises rotating cb_values/seeds, the inner while consumes the entire SLSdeadline, so only seed1/cb2.06is reached. Generic watched-literal first-UIP CDCLuses activity scan, phase saving, growing100..5000conflict restarts and deletion of unlocked learned clauses wider than2at20kconflicts. It logs RUPand only publishes20after root conflict. Original units/empty clauses are stored without initial enqueue/empty check; final SATreplay prevents accepting an ignored empty clause.

**Underlying structure:** Minimal UNSAT means deleting any clause makes the remainder satisfiable. Each deletion model is then a critical assignment falsifying just that clause in the full formula. Finding assignments with one violated clause does not establish either unsatisfiability or minimality. This worker has no deletion/core/MUS-specific mechanism; its strongest mathematical opportunity is learning or proving restrictions from near-solution neighborhoods while retaining a complete certified refuter.

**Wassat coverage:** solver.w already supplies typed first-UIP CDCL, safe intake, phases/restarts/deletion and certificate channels; sls.w already supplies native normalized incremental search. portfolio.w freezes variables outside the best snapshot conflict fringe, solves under assumptions, and expands from failed-assumption cores, checking every resulting model. Thus generic SLSbest-phase handoff and bounded exact repair are already covered. The specific power-law make/break distribution can diversify the shared kernel, but this source adds no new MUSreasoning.

**Learn for Wassat:** Compare the make/break power-law proposal as a shared SLSpolicy with controlled seeds and cached scores. Use deletion witnesses/near-solutions to choose bounded assumption neighborhoods and targeted proof queries; never interpret a local one-conflict plateau as an UNSATproof. Share the existing certified CDCLfallback, best-snapshot storage and failed-assumption-core expansion instead of another independent generic engine.

**Improve LymphoSAT:** Give each restart an explicit move/time slice so additional seeds and cb_values are reachable; current advertised rotation never occurs. Initialize original units and detect empty clauses immediately; empty input currently loses a trivial refutation. Maintain make/break caches and use a branch heap, reusable analysis buffers and bounded proof/memory storage. Check proof stream close/write failures and enforce full DIMACS count/format validation before returning a verdict.

**Certificates and evidence:** Original worker with documented SLS_LIMIT=.02/CDCL_LIMIT=3gives three strictly accepted proofs: exact full3variable/8clause MUS, binary4clause MUS and contradictory units. All eight one-clause deletions of the3CNFMUSget complete valid models, independently demonstrating minimality. Empty clause returns UNKNOWNrather than false SAT. Time overrides are private controlled replay, not submitted default performance. No MUScompetition proof was replayed. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/090-random-mus.json`.

### 91. random-planted-solution

Flat normalized-assumed3CNFSLSmaintains true counts, critical variable and cached unweighted/weighted break. It samples(0.9+break)^(-2.06), adds weights to unsatisfied clauses and halves weights periodically, with polarity-biased starts. Near<=3/5bad clauses it exhaustively flips subsets of their at-most9/15variables and undoes failed attempts. Generic CDCLadds heapVSIDS,LBD/Lubyrestarts,deletion/compaction and periodic rephasing. It receives the FINAL SLSassignment, despite a best-phase comment and README; best storage was explicitly removed. Actual main publishes SATonly: root UNSAT and timeout both become UNKNOWN, with no proof output.

**Underlying structure:** Planting changes an ensemble, not the logical rules of a given formula. Polarity statistics/ratios may suggest a useful starting distribution or search budget but cannot establish hidden generator identity. The polynomial break law differs from review86exponential cb^(-break)and review90make-weighted law. Weighted critical-variable bookkeeping is reusable. Exhaustive local repair only proves the frozen neighborhood is unsatisfiable when it fails, not the full formula.

**Wassat coverage:** Wassat typed SLSalready caches weighted scores/criticalXORand retains true best snapshots; solver.w has stronger shared CDCL/proof infrastructure. portfolio.w already performs bounded exact best-fringe repair with assumption-core expansion, which is broader than brute-force only the initially false-clause variables. The missing specific policy is polynomial break-only ProbSAT/PAWSsampling and its parameter comparison, not phase transfer, weighting, repair or CDCLcompaction as concepts.

**Learn for Wassat:** Add break-only polynomial sampling as a shared normalized native policy beside review86exponential and CCAnr; benchmark policies with equal budgets across held-out families. Retain actual best-state phase transfer and existing assumption-core-based neighborhood expansion. Use Gray-code enumeration for truly tiny frozen neighborhoods to update one variable per candidate; charge literal visits and cancellation.

**Improve LymphoSAT:** Preserve and validate original clause boundaries, widths, empty clauses and bounds; reconstructed-triple replay currently admits reproduced false SAT. Transfer a true best snapshot or describe the endpoint honestly; the active code does not retain the advertised best assignment. Poll deadlines inside neighborhood enumeration and avoid repeatedly flipping every subset from scratch. Preserve root-level assignments when restarting an already-root CDCLstate: backtrack(0)uses a zero target when trail_lim is empty. Expose deterministic seed controls for experiments and bound memory/proof contracts rather than rely on generator ratio labels.

**Certificates and evidence:** Original main produces four complete independently valid planted models, covering all four ratio bands. It falsely reports SATfor both empty-clause-plus3CNFand contradictory units regrouped as a tautological triple; private Wassat strictly proves both originals UNSAT. Exact original SLSkernel on a normalized planted formula and the3variableMUSpasses25600flips,1506weight bumps and626smoothing operations, including complete failed-neighborhood rollback on the MUS. No full CDCLperformance qualification or planted competition replay. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/091-random-planted-solution.json`.

### 92. rbsat

Per-edge uint64forbidden rows, incident edge lists and fixed arrays maintain bad-edge positions, unweighted/weighted endpoint conflict counts. Greedy degree-ordered starts precede endpoint-value min-conflicts over a random violated edge, occasionally a third endpoint,1.8%noise and breakout increments. Candidate deltas are computed BEFORE a possible weight bump and then used to pick a move under the changed objective. Weights reset each restart; best_seen is global across restarts, so later restart stagnation may be measured against an earlier best. SATonly,585swall budget.

**Underlying structure:** One domain move preserves a signed onehot selection and can repair many Boolean nogoods together. Relation-edge weighting differs from per-forbidden-pair weighting: one edge receives one penalty even when it contains many incompatible value pairs, so it changes the optimization landscape. Complete AMOclauses are unnecessary for a positive construction over negative binary exclusions, but arbitrary units and residual clauses must still influence search to avoid premature misses.

**Wassat coverage:** domain_walk.w already performs cached weighted min-conflicts plus tabu diversity, strict exact-one decoding, units, cancellation and full replay. domain_sparse handles large positive-domain negative-binary graphs without requiring AMO, with CSRincidence and root singleton pruning. Both cap width32and require positive choice literals; block_cspalso uses positive domains with width24and arbitrary residual clauses. Signed choices and33..63value mask reach are concrete gaps, while the basic high-level search is already implemented with stronger cached scoring.

**Learn for Wassat:** Normalize per-value selection signs into the shared domain decoder and lift models through that map. Generalize masks/storage to support validated33..63value domains or multiword domains, preserving representation and memory checks. Compare relation-edge weights against per-forbidden-tuple weights and existing tabu under equal move/incident-work budgets.

**Improve LymphoSAT:** Filter domains by unit/unary constraints and include supported residuals before search; do not stop at the first relation-only assignment when full replay fails. Recompute/rerank candidate deltas after a weight bump, or explicitly choose the move before changing the objective. Reset restart-local progress baselines and cache all-value costs instead of rescanning every incidence for every candidate. Reuse review89semantic patterns/merged support and bounded AC3repair rather than maintain another narrow RBdecoder. Add bounded weight smoothing and deterministic seed controls while retaining actual clause validation.

**Certificates and evidence:** Original worker gives valid models on ordinary and signed onehot controls and a33value domain beyond Wassatcurrent32value search cap. A complete SATformula with forced domain units is detected but returns UNKNOWNbecause the chosen relation-model fails unit replay; Wassat returns a complete valid model. Merged support clauses decline, while review89handles them. Empty clause safely declines. No RBcompetition performance comparison. No comparable competition performance benchmark is claimed. Source inspection establishes coverage; proposed changes have not been implemented or measured. Detailed record: `build/lymphosat-specialist-audit-20261117/reviews/092-rbsat.json`.

### 93. register-allocation

Choice clauses partition the variables. Their literal positions define register coordinates. A graph edge requires a negative input binary for every matching coordinate. Search a dense graph for a clique of size k+1 and derive Hall clauses over every nonempty register subset. Degree computations and front deletions recur inside the unrestricted clique search.

Each of k+1 live ranges needs a register, and each register holds at most one range. The independent cutting-planes induction proves the latter directly from its pair exclusions.

**Wassat.** Wassat already extracts verified coloring and resource cliques, including subsets in larger formulas. The new proof generator is a research prototype. Carry the input clause IDs from clique discovery into a polynomial certificate emitter. At eight registers the same formula took 2,785 bytes versus 151,276 for Hall enumeration.

**Improvement to the reference worker.** Cache degrees and bound clique search. Replace subset enumeration with one capacity derivation per register. Recover coordinates from exclusions when row literals have been reordered.

**Evidence.** 4 independently accepted UNSAT proofs. 1 controlled input returned UNKNOWN. Five additional polynomial proofs from the independent generator verified, including the 30-register case. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/093-register-allocation.json)

### 94. relational-dependencies

Groups of positive and negative clauses are selected by width, count and variable range. Each mixed clause must be a two-premise Horn rule. Enumerate the small set of base variables allowed to be false. Close the remaining true bases under the implications, check the auxiliary capacity and replay the CNF. The UNSAT path branches on bases and emits RUP clauses.

For a fixed base choice the least Horn closure is contained in every extension. Exceeding a proved auxiliary upper bound excludes that branch. A binomial clause count alone cannot prove the bound.

**Wassat.** Wassat has general unit propagation, functional gate congruence and a counter/BDD worker. None of these supplies this combination of complete subset-family recognition and a small false-base search. Index each subset by combinatorial rank and require complete distinct coverage. Queue newly true Horn atoms and retain the input reasons for every capacity conflict.

**Improvement to the reference worker.** Replacing one positive subset with a duplicate preserved the feature counts and produced a false UNSAT. Detect duplicates and repeated literals before assigning a cardinality meaning, then check each logged lemma.

**Evidence.** 2 independently accepted UNSAT proofs. 1 complete model satisfied every original clause. The strict verifier criterion excluded duplicate-subset-sat-impostor. The duplicate-subset fixture is SAT. Private Wassat returned a checked model. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/094-relational-dependencies.json)

### 95. relativized-pigeon-hole

Recover primary choice rows, shared relay literals and secondary colors from signed binary and four-literal clauses. Classification by absence from width-four clauses misses width-four primary rows. A missing secondary collision supplies a full candidate with two selected relays sharing a color. On complete instances the proof combines primary at-most-one bounds, relay activation and conditional color capacities using extension variables.

Distinct primary choices force at least p active relays. Each active relay requires one of p−1 colors and two active relays cannot use the same color.

**Wassat.** Wassat relay_count already recognizes signed relayed pigeonholes using actual binary and quaternary exclusions. Its structural verdict has no exported PB proof. Attach proof IDs to relay implications and use activation-and-color indicators for certificates. Construct and replay a shared-color model when a necessary exclusion is missing.

**Improvement to the reference worker.** Identify variable roles through incidence even when primary rows have width four. Handle missing primary conflicts as well as secondary collisions. Parse DIMACS by clause terminators.

**Evidence.** 3 independently accepted UNSAT proofs. 1 complete model satisfied every original clause. 2 controlled inputs returned UNKNOWN. The signed, renamed and shuffled proof passed. Private Wassat solved the missing-primary-conflict SAT control. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/095-relativized-pigeon-hole.json)

### 96. rooks

A positive root follows a square board of primary variables. Every row needs all pairwise at-most-one clauses. Auxiliary implications are classified by their number and signs. Compute a minimum count below each auxiliary. Sum child demands at conjunction nodes and use a one-item difference at decision nodes. Emit an assertion of contradiction when root demand exceeds the row count.

Demands may be added when their primary supports are disjoint. Two different children can force exactly the same items. A split can count the tested item only when it is fresh on the relevant branch.

**Wassat.** Wassat threshold_cover tracks actual primary supports at conjunctions and decision nodes. On the overlapping example the private CLI gave a checked SAT model. On disjoint supports it gave a checked WRAT proof. Add local PB justifications to the existing support-aware demand calculation so proof mode can exploit the counting shortcut.

**Improvement to the reference worker.** Require disjoint supports, verify matching decision literals and visit every auxiliary child. Replace the unchecked assertion with a derivation. Require an unconditional checker verdict in the dispatcher.

**Evidence.** The strict verifier criterion excluded overlapping-support-sat-impostor, disjoint-support-unsat. 1 controlled input returned UNKNOWN. The original verified dispatch function returned 20 on the overlapping SAT fixture with the matcher bypassed. VeriPB reported UNDER ASSERTIONS. Direct Wassat threshold_cover declined the overlap and refuted the disjoint control. The private CLI independently produced a checked model and a checked 26-byte WRAT refutation respectively. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/096-rooks.json)

### 97. sat-x

The active layout test starts at a negative unit followed by a fixed contiguous constant block. It infers three operand positions and width from the unit prefix. Try a user-supplied decimal triple, two small triples and a finite list of published magnitudes. Propagate each proposal and complete remaining Boolean choices. A layout-specific CDCL path follows. Root propagation can emit an empty RUP on conflict.

Assigning the three operand words removes most search in a deterministic cubing circuit. The fixed word width and sign conventions determine whether an integer solution is a usable bit-vector solution.

**Wassat.** Wassat recognizes arithmetic anchors and independently searches signed operands using the target. It already lifts a proposed triple through a conditioned query. Add arbitrary-width operand serialization and clause-derived word order when a measured hard target exceeds current arithmetic search.

**Improvement to the reference worker.** Read target bits and filter candidate signs and permutations arithmetically. Index the unit pattern independently of leading clause order. Measure search-generated witnesses on unseen targets.

**Evidence.** 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/097-sat-x.json)

### 98. satcoin

Search the first 2,000 clauses for two complete 32-input equality gates with the same inputs and different constants. Bit order follows sorted variable IDs. The active DirectProof traverses nonce prefixes, stops outside the inferred interval and emits a blocking RUP at every leaf and parent. Main calls it directly without testing propagation conflicts or SAT assignments.

Two equality indicators alone place no restriction on the nonce. Every excluded prefix and every complete nonce inside the interval needs an independently established conflict before resolving back to the root.

**Wassat.** Wassat evaluates a recognized range-constrained circuit in bit-parallel batches using a narrow input layout. It has a semantic evaluator but lacks this exported interval proof. Use equality-gate incidence to find candidate input bits, then derive range restrictions and certify each rejected cube. Stop with a checked model if a nonce succeeds.

**Improvement to the reference worker.** Two unconstrained equality outputs on 32 bits triggered false UNSAT in a direct replay. The checker rejected the proof. Bound prefix expansion by the number of remaining candidates and validate leaves before writing them.

**Evidence.** 1 independently accepted UNSAT proof. The strict verifier criterion excluded equality-gates-sat. 2 controlled inputs returned UNKNOWN. The two-equality fixture has a direct satisfying assignment: all nonce bits zero, first equality true, second equality false. Its rejected proof is a false UNSAT proposal. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/098-satcoin.json)

### 99. set-covering

Requires every clause to be either a positive cover row of width at least three or a negative binary conflict. Rows can overlap. A weighted walk adds or removes selections to repair uncovered rows and conflicting edges. CDCL then branches in the uncovered row with the fewest live candidates, scoring residual coverage and conflicts, with RUP logging.

Selecting a set satisfies all its incident rows but forbids its conflict neighbors. A remaining row with one possible member forces it.

**Wassat.** Wassat covering already maintains available row counts incrementally and branches exactly on the same independent hitting-set problem. Its explicit size and node budgets limit coverage. Profile weighted repair on large rows before the exact search, sharing incidence indices and checking the model. Reuse row-based branching as a hint to the proof-producing backend.

**Improvement to the reference worker.** Trail row eligibility instead of rescanning every row on every CDCL decision. Allocate the 8/90-second search split using measured improvement and remaining runtime.

**Evidence.** 1 complete model satisfied every original clause. 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/099-set-covering.json)

### 100. sgen

Signed binary exclusions form blocks of five. A signed item in one block and two five-literal rows gives an exact-cover row. Complete signed ternary blocks of four or five support the counting path. Try a signed or monotone ternary counting proof, then bounded exact-cover DFS and repair. A five-clause SLS fallback runs only if exact-cover detection fails.

All triples on a block of size b force at least b−2 of its literals true. If covered positive and negative copies of the variables demand more true literals than variables, their lower bounds contradict one another.

**Wassat.** Wassat recognizes binomial cardinalities in parity_sum and exact-one incidence balance in matching_balance. The signed three-column search and direct cutting-planes bound add coverage. Share verified subset indexing with the Horn and capacity recognizers. Normalize signed rows before exact-cover search and pass clause IDs to the certificate emitter.

**Improvement to the reference worker.** When exact cover fails, extract a component Hall obstruction or fall through to certified Boolean search. Resolve the scope from incidences instead of assuming five-wide blocks.

**Evidence.** 1 independently accepted UNSAT proof. 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/100-sgen.json)

### 101. sgen-balanced

The runtime requires 100–500 variables, 3.3–3.8 clauses per variable, distinct triples, 8–13 occurrences per variable, near-equal polarity counts and few repeated variable pairs. Occurrence-seeded CDCL emits learned RUP clauses and proof deletions. Database reduction preserves locked reasons and binary clauses. Parent marking helpers do not implement the active streaming proof writer.

Nearly linear triple incidence and polarity balance constrain the sampling distribution. They do not imply satisfiability or supply a refutation.

**Wassat.** Wassat already has a proof-producing CDCL kernel with restart, phase and learned-clause management. No new family theorem is used here. Measure whether incidence balance predicts a useful restart or phase policy on held-out balanced instances, using the same Wassat engine.

**Improvement to the reference worker.** Use live clause utility for deletion and time the policy against unfiltered CDCL. Expose a reason for rejecting slightly perturbed incidence counts.

**Evidence.** 1 complete model satisfied every original clause. 3 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/101-sgen-balanced.json)

### 102. sliding-puzzle

Recover the two 5×5 endpoint boards, relative tile slots and action encodings from the compact transition layout. IDA* searches primitive blank moves, excludes immediate reversals and counts Manhattan distance plus two per inverted in-line tile pair. Pad a shorter trace with reversible moves and propagate it into a checked CNF model.

When Manhattan distance equals the horizon, every move must reduce distance by one. With slack, detours are possible. Overlapping linear conflicts can charge the same tile repeatedly, so summing every inversion requires care.

**Wassat.** Wassat recognizes repeated transition blocks and uses monotone DFS for the tight public 32-move case. Both workers returned complete checked models on that competition input. Keep monotone DFS for tight horizons. Use an admissible disjoint-conflict or line-removal bound for a slack-aware IDA* path, with parity and transposition pruning.

**Improvement to the reference worker.** Replace all-pairs inversion charges by a proved admissible bound whenever the threshold is used to discard paths. Validate padding against the goal timing and original CNF.

**Evidence.** 2 controlled inputs returned UNKNOWN. The original direct worker returned a checked SAT model on SC2026 puzzle32_sat (0.078 s, six-second cap, single run). The private Wassat CLI with proof output enabled returned a checked SAT model on SC2026 puzzle32_sat (0.040 s, six-second cap, single run). [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/102-sliding-puzzle.json)

### 103. social-golfer

Table recognition uses clause widths, multiplicities and a contiguous player-slot suffix. Context recognition recovers week-local meeting variables and forced first-week pairs. Select a parameter-specific schedule, relabel groups, players or weeks to satisfy the forced partition or pair constraints, propagate omitted variables and check the complete model.

Each week is a partition and each unordered player pair meets at most once. Finding a resolvable block design can replace searching over table and auxiliary bits.

**Wassat.** Wassat affine_design recovers necessary affine-plane structure for a bounded refutation. This is a different operation from constructing and relabeling a social-golfer schedule. Generate schedules from finite affine geometries or use exact-cover search over blocks, then lift either table or pair-context models from a common schedule.

**Improvement to the reference worker.** Use a graph isomorphism or constraint search to fit forced pairs and derive schedules for unseen parameters. The checked SC2026 CP example was outside the original worker’s successful coverage.

**Evidence.** 2 controlled inputs returned UNKNOWN. The original direct worker returned UNKNOWN on SC2026 SocialGolfers-6-6-7-cp_c18 (0.039 s, six-second cap, single run). The private Wassat CLI with proof output enabled timed out on SC2026 SocialGolfers-6-6-7-cp_c18 (6.011 s, six-second cap, single run). [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/103-social-golfer.json)

### 104. software-bmc

Header size selects topological trials, small capped proof probes, flat no-proof SAT trials or a conventional proof-logging solver. Propagate unit requirements backward to choose inputs, evaluate forward, then try flat watched CDCL. For huge SAT outputs, select a partial assignment that explicitly satisfies every original clause and fall back to a full verified assignment.

One selected true literal per clause is a sufficient SAT certificate. A smaller hitting set of true literals can shrink printing cost even when the internal assignment is full.

**Wassat.** Wassat already uses compact clause storage, native watches and circuit model evaluation. Compact printed witnesses would require agreement with the downstream result format. Measure parser, search, verification and serialization time separately on large BMC inputs. Try backward justification as a phase proposal and evaluate compact models only in compatible consumers.

**Improvement to the reference worker.** Share the parsed clause arena across the probe portfolio. Choose memory layouts from literal and watch counts and account for repeated full-model verification.

**Evidence.** 1 independently accepted UNSAT proof. 1 complete model satisfied every original clause. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/104-software-bmc.json)

### 105. software-verification

Ratio and span features select this worker. Internally header shape, clause width, root assignments and the remaining frontier determine the search modes. Root simplification logs reductions, then tries checked completion, greedy assignments or local repair. CDCL branches on relevant variables. Failed-literal probing requires an explicit environment switch.

Fixing an input or simplifying a Tseitin gate can determine a large cone. Failed-literal facts are valid consequences only if propagation really conflicts on the assumed branch.

**Wassat.** Wassat already has bounded control probing, circuit evaluation and a certified CDCL fallback. The root-frontier completion attempt is an additional candidate policy. Try completion on the active frontier before unrestricted CDCL, with a shared time budget and full-input replay. Compare propagation visits per accepted result.

**Improvement to the reference worker.** Distinguish enabled root reductions from opt-in failed-literal probing in evaluations. Reuse root state across completion trials and log learned implications once.

**Evidence.** 2 independently accepted UNSAT proofs. 1 complete model satisfied every original clause. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/105-software-verification.json)

### 106. sorting-networks

Initial negative binary cliques suggest channel count, and the first long auxiliary clause identifies selected depth-nine shapes. Run watched first-UIP CDCL with comparator phases, including a stored 16-channel suffix. Shape controls proof logging and time budget. Verify a SAT model and publish UNSAT only on the proof-enabled path.

Disjoint comparators in a layer sort Boolean vectors. The zero-one principle permits semantic scoring against Boolean input patterns. A suggested network can safely initialize phases.

**Wassat.** Wassat decodes comparator structure, evaluates candidate networks and completes checked CNF models. Its proof-producing generic CDCL can also consume input-derived candidate phases. Pass phases from an independently constructed near-network to certified CDCL and measure conflicts, particularly when one layer differs.

**Improvement to the reference worker.** Infer layers from complete incidence and use counterexample inputs to repair candidates. A depth-nine fingerprint alone should never suppress the only proof path.

**Evidence.** 1 independently accepted UNSAT proof. 1 complete model satisfied every original clause. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/106-sorting-networks.json)

### 107. ssp-0

Recover the long negative selector clause, mux-copy blocks and adder uses. Probe late boundaries with the zero vector and singleton choices. Enumerate suffix choices that force the boundary, reconstruct prefix weights and match complementary half-sums. Propagate the complete selection and check it against the input. A bounded Boolean walk is available on selected failure paths.

At a real addition boundary the prefix is an additive function of selected items modulo the encoded width. Enumerating two half-sums replaces enumeration of all subsets with a time–memory tradeoff.

**Wassat.** Wassat counter_cover reconstructs signed aliases and weighted adder selections. Its maintained search over selections differs from exact meet-in-the-middle at a discovered word boundary. Use the existing gate decoder to justify weights and choose a split from available memory, multiplicities and forced bits. Verify every lifted candidate.

**Improvement to the reference worker.** Infer the cut from carry dependencies. Singleton agreement alone does not prove additivity. Keep failure inconclusive and include a budget for half-sum storage.

**Evidence.** 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/107-ssp-0.json)

### 108. st-connectivity-principle

Infer grid dimensions from the variable count, regenerate the endpoint and degree clauses, then compare clause multisets. The proof worker admits width at most nine. Sweep a frontier across the grid. Enumerate local crossing patterns and derive clauses excluding forbidden reduced words by RUP. The final boundary violates the invariant. The separate generic solver is outside this main path.

The two vertex-disjoint colored paths would connect alternating boundary terminals of a rectangle. Planarity forbids that. A frontier word records enough information to prove the obstruction column by column.

**Wassat.** Wassat already checks local degree blocks, their incidences and the planar-grid obstruction in coloring.w. The existing direct verdict and a replayable sequence of frontier lemmas are different capabilities. Keep witness IDs when recovering a grid and expose a proof mode that chooses its sweep along the shorter side.

**Improvement to the reference worker.** Identify the grid by incidence to survive variable permutation. Merge frontier states with identical reduced words and budget proof size as a function of width.

**Evidence.** 1 independently accepted UNSAT proof. 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/108-st-connectivity-principle.json)

### 109. station-repacking

Two passes recover station choice clauses, signed-variable locations and binary channel interference. Connected components separate unrelated stations. Arc consistency reduces domains for weighted local search. Exact search on original domains first isolates an UNSAT component and reruns that search while streaming its proof. Remaining components use PAWS, compound moves and exact repair. SAT is checked against the original file.

Different components have independent assignments. Emptying a domain under an exhaustive set of choices proves a component impossible. Heuristic arc pruning needs reasons to appear in an original-CNF proof.

**Wassat.** Wassat already has sparse finite domains, root pruning and weighted moves. The contribution is component allocation and an independently replayable proof for one conflicting component. Exploit decomposition before allocating global walk state. Feed the smallest contradictory component into a proof-producing search using original clauses.

**Improvement to the reference worker.** Record reasons on the first pass or checkpoint the failing component to avoid two divergent searches. Carry deadlines through the replay and make allocator trimming portable.

**Evidence.** 1 independently accepted UNSAT proof. 1 complete model satisfied every original clause. On macOS the original source was built with a no-op for the Linux-only allocator trimming call. Deleting one interference edge changed checked UNSAT to checked SAT. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/109-station-repacking.json)

### 110. stedman-triples

Recover a transition table from direct one-hot rows or bit-pattern clauses and collect restrictions on node types and calls. Simulate parameter-selected stored call sequences, then try a bounded high-level DFS on at most 840 nodes with two branch orders. Complete the chosen calls and states by propagation and replay the entire formula.

A solution is a tour consistent with the deterministic transition selected at each visit. Searching calls and node types eliminates the sequence-bit auxiliaries from the main search.

**Wassat.** Wassat already decodes guarded compact transitions and searches for a Hamiltonian cycle, with a conditioned query for lifting. Both produced checked models on the SC2026 Stedman case. Generalize the input side to one-hot types and partial patterns, keeping one canonical transition graph and the existing search.

**Improvement to the reference worker.** Use reusable structural search, reachability and forced in/out-degree pruning to cover new graphs that have no stored call sequence.

**Evidence.** 2 controlled inputs returned UNKNOWN. The original direct worker returned a checked SAT model on SC2026 sted5_0x1e3-20 (0.071 s, six-second cap, single run). The private Wassat CLI with proof output enabled returned a checked SAT model on SC2026 sted5_0x1e3-20 (0.041 s, six-second cap, single run). [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/110-stedman-triples.json)

### 111. stone

Infer placement rows from long clauses, colors and distinguished source/sink rows from binaries, then identify predecessor propagation clauses and ancestors of the sink. Try a checked blue-stone model from a missing propagation condition. Otherwise traverse the ancestors and derive that every stone placed at each node is red. Delete temporary RUP lemmas once their local step is complete.

Source stones are red. Red predecessors force a red stone at every successor that lies in the checked dependency cone. At the sink, its placement choice and blue requirement contradict the induction.

**Wassat.** Wassat has circuit and Horn-like implication processing and CDCL. A reusable proof rule for universally quantified placement rows on a recovered DAG was not identified. Represent the induction predicate as a mapping from row and value to a literal. Reuse local original-clause proofs across predecessor tuples and omit vertices outside the sink cone.

**Improvement to the reference worker.** Infer arbitrarily shaped acyclic predecessor sets and memoize shared redness clauses. Check the full predecessor coverage before using a row as an induction step.

**Evidence.** 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/111-stone.json)

### 112. subgraph-isomorphism

Recover signed direct choice rows or five-bit log domains from forbidden codes and pair conflicts. An ordered-deletion embedding shortcut uses the order of suitable positive instances. Try the order shortcut, bitmask arc consistency, min-conflicts and DFS. Unsupported formulas have a generic path. The direct MAC proof is opt-in. The fallback CDCL can emit RUP proofs, and every returned embedding is replayed.

An embedding is an injective mapping that preserves required edges. Excluding a host label requires an actual incompatibility or a justified domain consequence. A guessed graph cannot establish UNSAT.

**Wassat.** Wassat McSplit checks canonical domain labels, injectivity and required conflicts on its 30-label representation. The signed/log case and ordered mapping proposal are broader. Add signed and binary-coded domain front ends to the existing embedding checks. Include the residual domain sizes after refinement in per-instance profiles.

**Improvement to the reference worker.** Allocate a single deadline across all fallbacks. Treat order recovery as an optional model proposal, and record which inequality or absence caused each domain deletion.

**Evidence.** 1 independently accepted UNSAT proof. 1 complete model satisfied every original clause. The original direct worker timed out on SC2025 SGI_30_60_20_50_3-dir.shuffled-as.sat03-114 (6.006 s, six-second cap, single run). The private Wassat CLI with proof output enabled timed out on SC2025 SGI_30_60_20_50_3-dir.shuffled-as.sat03-114 (6.016 s, six-second cap, single run). [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/112-subgraph-isomorphism.json)

### 113. subsumptiontest

Use literal frequency to compute a majority assignment. The width of the widest clause selects the local-search budget before CDCL. Start a low-break WalkSAT-style search at majority phases. The fallback prioritizes variables from clauses false under majority, branches with the opposite-majority bias and logs RUP clauses.

When a majority assignment misses few clauses, a solution may lie near a small correction set. The number of missed clauses by itself gives no UNSAT bound.

**Wassat.** Wassat already has incremental SLS, best snapshots and bounded exact repair around their unsatisfied fringe. Majority initialization can be tested independently of the engine. Try majority phases as one deterministic start and use the existing failed-assumption repair to learn which frozen variables need release.

**Improvement to the reference worker.** Choose the handoff from the number and overlap of still-false clauses. Compare against all-one, random and saved phases on new inputs.

**Evidence.** 2 independently accepted UNSAT proofs. 1 complete model satisfied every original clause. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/113-subsumptiontest.json)

### 114. sum-of-3-cubes

Infer the bit width and target from the layout of unit and circuit clauses, reject a zero or unrecognized target and propose unsigned magnitudes fitting the operands. Search small cube pairs using a cube-value hash table, then try permutations of selected published triples. Assign operand bits, propagate and try completion phases. Accept only a full satisfying assignment.

The bit-blasted predicate determines the signs and width. For signed integer search, fixing d=x+y converts the remaining pair to a quadratic with an integral square-discriminant condition.

**Wassat.** Wassat already decodes circuit anchors and searches signed values systematically, then completes the operands with a Boolean query. Both workers produced checked models on SC2025 target 87. Profile target decoding, witness generation and Boolean completion independently. Extend the signed search by residue classes and variable-width arithmetic when the target needs it.

**Improvement to the reference worker.** Recover operand signs and roles to reduce permutation trials. Cover unseen targets through algorithmic generation and report how often the bounded search succeeds by itself.

**Evidence.** 2 controlled inputs returned UNKNOWN. The original direct worker returned a checked SAT model on SC2025 sum_of_3_cubes_37_bits_87 (0.238 s, six-second cap, single run). The private Wassat CLI with proof output enabled returned a checked SAT model on SC2025 sum_of_3_cubes_37_bits_87 (0.041 s, six-second cap, single run). [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/114-sum-of-3-cubes.json)

### 115. summle

Infer target and step count from the CBMC encoding and recover contiguous 16-bit operand-index groups. The arithmetic search uses a fixed eight-number multiset. Store one expression per reachable value and used-number mask. Combine disjoint masks under the encoded addition, guarded low-word multiplication, nonnegative subtraction and exact division. Reconstruct operand slots, propagate and finish the Boolean model with bounded search.

Each input occurrence can be used once. Two expression subtrees combine precisely when their occurrence masks are disjoint. The bit-vector guards matter for multiplication overflow and for safe equivalence of DP states.

**Wassat.** Wassat has circuit execution and adder selection, but no corresponding subset-expression solver was identified. On the original target 8638 the direct worker produced a checked model, and the private proof-enabled CLI hit its six-second cap. Recover the constants and operation guards from the input, then use subset DP to propose operand selectors to an ordinary Wassat query. Profile the expression search and the cost of reading and lifting the encoding separately.

**Improvement to the reference worker.** Derive the multiset from constant words. Retain alternative backpointers when a representative for a reachable value fails side constraints, and use the observed completion cost to choose further candidates.

**Evidence.** 2 controlled inputs returned UNKNOWN. Five profiled runs on the original competition formula gave medians of 56.2 ms for Boolean completion, 38.6 ms for input parsing and 10.9 ms for the arithmetic DP. Each output was byte-identical to the independently checked model. The original direct worker returned a checked SAT model on SC2025 summle_X8638_steps7_I1-2-2-4-4-8-25-100 (0.132 s, six-second cap, single run). The private Wassat CLI with proof output enabled timed out on SC2025 summle_X8638_steps7_I1-2-2-4-4-8-25-100 (6.012 s, six-second cap, single run). [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/115-summle.json)

### 116. tensors

Decode signed three-input products and XOR groups. Use component incidence to reconstruct factors, coordinates and slice coefficients. The active algebraic path requires 5×5×5 and rank 12. Enumerate rank-one binary matrices, then beam-search subspaces containing the target slices. Group candidates by their residue modulo the current subspace, score the remaining span deficit, recover coefficients and reorder terms for symmetry-breaking clauses. A conditioned SAT query checks the model.

A rank-R tensor decomposition yields at most R rank-one matrices spanning all slices along one axis. Conversely, expressing every slice in such a span gives the coefficients along that axis.

**Wassat.** Wassat has a tensor5 model route in backdoor.w. A witness-oriented lift differs from searching subspaces of rank-one matrices reconstructed from the current tensor. Search slice spans from the decoded tensor, selecting the cheapest flattening. Cache reduced bases and score subspace deficit before Boolean completion.

**Improvement to the reference worker.** Use rank bounds from all three flattenings and adaptive beam widths. A beam miss remains inconclusive. Record algebra-search versus symmetry-ordering effort.

**Evidence.** 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/116-tensors.json)

### 117. test-configuration

Recover a fixed 46-feature layout, 967 coverage columns per row and definitions connecting indicators to feature pairs. Locate the stored list of 20 required interactions. For fewer than 20 rows emit pairwise incompatibility and row-capacity proof steps for the selected interactions. Otherwise try a stored row construction and check all clauses, including optional symmetry conditions.

A set of mutually incompatible required interactions is a lower bound on the number of test rows. A satisfying row set is a clique cover of the allowed interaction edges respecting feature implications.

**Wassat.** Wassat capacity_clique and resource_capacity already derive checked capacity bounds from explicit conflicts. The mapping from feature-pair indicators to row conflicts and a positive covering constructor add functionality. Build the interaction conflict graph from input-proved impossibilities and find any clique larger than the available row count. Use the polynomial capacity certificate from review 93.

**Improvement to the reference worker.** Discover the obstruction rather than relying on 20 fixed interactions. Search for covering rows and recheck feature implications, negative coverage and row ordering.

**Evidence.** 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/117-test-configuration.json)

### 118. testpattern-generation

The matcher uses bounded sizes and a gate-like width mix. The solver itself runs a root probing pass with caps on rounds, tested literals and added binary clauses. Temporarily assume a literal and propagate. A conflict gives a unit. Each implied literal produces a binary implication. Log these as RUP, then continue with watched CDCL and check any completed model.

If F and a unit-propagate b, then ¬a or b is RUP against F. The new clauses can shorten future Boolean propagation chains while retaining a proof.

**Wassat.** Wassat has bounded one- and two-control probing, watches and native proof generation. Selective logging of short implications can bring a structural optimization into proof mode. Select probes by fanout and track propagation visits saved per added watch. Route validated binary implications through the same proof channel as CDCL.

**Improvement to the reference worker.** Deduplicate implications with a literal-pair index. Retain a binary only when the saved future propagation is likely to repay its watch and certificate costs.

**Evidence.** 2 independently accepted UNSAT proofs. 1 complete model satisfied every original clause. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/118-testpattern-generation.json)

### 119. theorem-proving

Counts propose grid dimensions. Local co-occurrence and signed clause patterns recover paired literals, the forbidden origin and the target. Main tries the structural proof before generic CDCL. A pair of literals represents one conjunction. Derive the impossibility of successive objects from boundary or two-predecessor clauses, then contradict the target. A generic fallback tracks proof dependencies.

In a finite DAG, if every true non-origin object has an earlier true predecessor and every base case is false, no object can be true. The target requires a true object.

**Wassat.** Wassat recognizes functional gates and verifies local circuit cones. That infrastructure is adjacent to this paired-object induction. Its StConn worker proves a different planar graph theorem. Share a DAG-induction engine with Stone, parameterized by the local predicate and the original-clause proof for each transition.

**Improvement to the reference worker.** Discover a well-founded order from implications instead of requiring a rectangular count identity. Check each local transition proof and use only nodes needed for the target.

**Evidence.** 1 independently accepted UNSAT proof. 1 complete model satisfied every original clause. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/119-theorem-proving.json)

### 120. tree-decomposition

Recognize a Samer–Veith variable layout and recover input edges and precedence constraints. Candidate orderings determine fill arcs. Try randomized min-fill/min-degree orders and clique or almost-clique reductions, then bounded search and candidate improvement. Assign order and arc variables, propagate auxiliary counters and check the full CNF.

The maximum number of later neighbors in a filled elimination order bounds treewidth from above. A minor with sufficiently large minimum degree bounds it from below.

**Wassat.** Wassat treewidth already decodes a graph and performs checked contraction lower bounds. A model-building elimination-order worker covers the complementary satisfiable cases. Share one graph decoder and race bounded elimination-order construction against the existing minor bound, with independent stopping and lifting.

**Improvement to the reference worker.** Use the CNF width limit explicitly to prune orders. Cache affected neighborhood/fill updates and carry partial order constraints into every reduction.

**Evidence.** 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/120-tree-decomposition.json)

### 121. trigonometric-functions

Distribution and clause-count features select the family. Runtime biases variable ordering by input size and exposes tuning controls for phases, probing and restarts. Stream RUP proof steps from watched first-UIP CDCL with recursive clause minimization and Luby restarts. Learned-clause reduction is enabled by environment. SAT requires satisfying the original clauses.

Bit-blasted trigonometric code may contain fixed-point arithmetic and repeated gates. This worker exploits variable order and Boolean propagation, without recovering periodicity or real-valued function identities.

**Wassat.** Wassat already implements certified CDCL and gate/circuit reasoning. A low-ID decision bias is a testable search policy, distinct from a trigonometric specialist. Test a gate-depth or fanin-based bias against variable-ID bias on a variable-renamed control. Model arithmetic as the actual encoded bit-vector semantics.

**Improvement to the reference worker.** Use validated circuit roles for decision priority and measure retained clauses under the default reduction policy. Compare learnt minimization cost against propagation savings.

**Evidence.** 2 independently accepted UNSAT proofs. 1 complete model satisfied every original clause. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/121-trigonometric-functions.json)

### 122. tseitin-formulas

Group equal variable supports, recover parity patterns and attempt repairs with residual clauses. Nonlinear small-support truth tables can enter a separate polynomial path. Degree-two variable incidence selects the graph solver. For an even component, assign free cycle edges and solve tree edges bottom-up. For a parity conflict, try a PB parity-sum proof then elimination. Other paths use GF(2) elimination, polynomial reconstruction or CDCL. Validate SAT models.

Every edge occurs twice in its connected component. Summing vertex equations cancels edges, so an odd charge in any one component contradicts the CNF. General linear inconsistency has a dependency whose sum is 0=1.

**Wassat.** Wassat parity_sum already reasons component by component and checks distinct forbidden patterns. The portfolio implements bounded GF(2) elimination. A compact certificate remains a meaningful proof-mode gap. Attach verified input IDs and a dependency bitset or sparse ancestry to rows. Emit a proof for the inconsistent component only, then validate its final constraint on the original input.

**Improvement to the reference worker.** Use exact distinct pattern masks everywhere and check final proof IDs. Two tiny contradictory same-support fixtures received rejected proofs, while a chain contradiction and an actual SC2025 graph received accepted proofs.

**Evidence.** 1 independently accepted UNSAT proof. 2 complete models satisfied every original clause. The strict verifier criterion excluded unsat-control, inconsistent-ternary-xor. The original direct worker returned a verified UNSAT proof on SC2025 tseitin_n188_d3 (0.019 s, six-second cap, single run). The private Wassat CLI with proof output enabled timed out on SC2025 tseitin_n188_d3 (6.025 s, six-second cap, single run). [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/122-tseitin-formulas.json)

### 123. uniform-random

Match a broadly uniform polarity and clause-width distribution. Runtime tracks actual widths, provides an SCC-based binary SAT search, and accepts mixed 2/3 inputs. Run multiple probSAT-style workers with width-dependent noise and make/break parameters, dense unsatisfied-clause indices and independent seeds. Verify a candidate assignment. The binary search hunts a model and exhaustion does not publish UNSAT.

Flipping one variable changes only incident clauses. Weighting candidates by break count targets near-solutions while noise can escape local minima. Formula width changes the expected break distribution.

**Wassat.** Wassat already has shared incremental SLS state, weighted repair, parallel and generic proof paths. A distinct sampling policy does not justify another parser or Boolean engine. Ablate one width-conditioned proposal within Wassat SLS, with matched random seeds, flip counts, wall time and peak memory.

**Improvement to the reference worker.** Hand proven binary contradictions to a certifying 2-SAT path instead of spending the remaining budget on SLS. Share immutable occurrence memory across stochastic threads.

**Evidence.** 1 complete model satisfied every original clause. 2 synthetic runs reached the two-second wall limit. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/123-uniform-random.json)

### 124. waerden

Read monotone positive/negative clauses. The default search expects reduced instances with positive binaries, and declines larger reduced shapes. Running plain instances needs an override. Assign one color by a hitting set, maintain bans from the other color, and use greedy construction and local search. Selected reduced shapes also receive a certified CDCL phase. A proof-producing exact DFS has an explicit time switch.

A valid two-coloring intersects every required progression while excluding a fully forbidden progression of the opposite color. Palindromic quotients can shorten clauses by identifying paired positions.

**Wassat.** Wassat arithmetic_coloring already solves two-color arithmetic hypergraphs. Its vdwb route tries quadratic-residue constructions. A hitting-set-specific certified search broadens the evidence available in proof mode. Use sparse progression incidence for exact propagation and feed failed branches to a certifying backend. Estimate reduced size by the recovered quotient and actual scope widths.

**Improvement to the reference worker.** Replace fixed size and binary-presence gates with work estimates from unresolved scopes. Decompose or exploit reversal symmetries when certified by input incidences.

**Evidence.** 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/124-waerden.json)

### 125. xor-chain

Check complete ternary parity groups and paired binary parity clauses. Build the GF(2) system and retain the actual inconsistent dependency, which can be a strict subset of the input. Solve a consistent system by elimination and replay the model. For an inconsistent dependency, introduce local sum/carry witnesses, prove each parity relation and sum the resulting integer bounds. The old pairwise combination tree is outside the active proof route.

Summing exactly the conflicting rows gives even coefficient on every Boolean variable but an odd constant. Dividing the aggregate inequalities forces incompatible integer bounds.

**Wassat.** Wassat already recovers exact XOR blocks and performs parity-sum and elimination reasoning. It can use the recorded dependency as the input to a shared certificate backend. Compile proofs per participating row and charge proof size to the dependency. The endpoint-flipped and endpoint-consistent controlled cases produced a checked proof and model respectively.

**Improvement to the reference worker.** Use sparse elimination until fill grows, and avoid a second dense solve when the elimination pass can also reconstruct a model. Extend recovery to XOR cores inside mixed formulas.

**Evidence.** 1 independently accepted UNSAT proof. 1 complete model satisfied every original clause. 3 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/125-xor-chain.json)

### 126. xor_op

Group consecutive DIMACS variables into pairs. The sign patterns of four- and six-literal blocks propose antisymmetry, transitivity and predecessor clauses over pair disequality. Counts check the expected number of blocks. Run CDCL on the reduced relation variables. Lift SAT by fixing representatives and checking the original CNF. For UNSAT introduce pair-XOR definitions, derive each high-level clause by a local contradiction proof and replay reduced learned clauses.

A finite strict partial order has a minimal element. Requiring a predecessor for every element creates a descending cycle, contradicting transitivity and irreflexivity. Pair-XOR substitution hides this short semantic argument.

**Wassat.** Wassat can recover XOR gates and functional aliases. No equivalent worker was found that recognizes this relation quotient and lifts a proof of the finite-order contradiction. Generalize compact local truth-table proof lifting and recover relation variables by incidence. A direct elimination proof for minimality could avoid much of high-level CDCL.

**Improvement to the reference worker.** Index original blocks once. The proof emitter otherwise scans the entire formula for each high-level clause. Validate every distinct local forbidden pattern before trusting the proposed quotient and independently check the final proof.

**Evidence.** 1 independently accepted UNSAT proof. 2 controlled inputs returned UNKNOWN. [Review and source references](../../../build/lymphosat-specialist-audit-20261117/reviews/126-xor_op.json)
