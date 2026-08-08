# Offline Wassat formula-router trainer

`train_router.w` is a compiled, offline model comparison and export tool. It
uses Koala during training but emits a standalone nested-comparison function;
the Wassat solver does not acquire a Koala runtime dependency.

## Build and run

```sh
bin/tungsten -o /tmp/wassat-router-train \
  bits/tungsten-wassat/benchmarks/train_router.w

/tmp/wassat-router-train training.csv /tmp/wassat_formula_router.w
```

The output path is optional. Source is written only when the
validation-selected model is a shallow `DecisionTreeClassifier` and clears the
conservative gate below. Exit status 2 means training completed but no source
was eligible for export.

## CSV contract

The format is deliberately unquoted CSV: no field may contain a comma or
quote. The exact header is exposed as `TRAINING_CSV_COLUMNS` and
`training_csv_header()` in `router_dataset.py`:

```text
instance_sha256,family_id,split,label,utility,weight,nvars,nclauses,nlits,used_vars,max_clause,units,binary,ternary,width4,width5_7,width8_plus,positive_literals,negative_literals,horn_clauses,dual_horn_clauses,all_positive_clauses,all_negative_clauses,variable_degree_max,variable_degree_p50,variable_degree_p90,variable_degree_p99,clause_span_sum,exact_one_sketch_candidates,exact_one_sketch_pair_coverage_ppm,exact_one_sketch_full_groups,binary_graph_edges,binary_graph_vertices,binary_graph_degree_max,variable_occurrence_top1_ppm,variable_occurrence_top10_ppm,variable_occurrence_hhi_ppm
```

- `instance_sha256`: unique 64-character lowercase SHA-256.
- `family_id`: leakage group. A family appearing in more than one split is a
  hard error.
- `split`: exactly `train`, `validation`, or `test`.
- `label`: binary Integer arm id. Arm 0 is baseline/disabled; arm 1 is the
  treatment.
- `utility`: finite signed paired delta `baseline PAR-2 - treatment PAR-2`.
  Positive favours treatment; negative favours baseline. A treatment label
  requires positive utility. A baseline label may retain a small positive
  delta when the conservative material-improvement threshold was not met.
- `weight`: finite positive sample/importance weight.
- Remaining columns: nonnegative Integer static features in exactly
  `router_dataset.py::FEATURE_NAMES` order.

Every validation/test label must occur in train. Each instance occurs once.
`router_labels.py` derives this binary schema from paired interventions using
median PAR-2, majority solve status, and an explicit material-improvement
threshold. Passive portfolio winners never become labels.

Utility and weight fields accept ordinary decimal or scientific notation,
including the exponent notation Python uses for sufficiently small deltas.

### Bounded structural features

The v2 tail is deliberately deterministic and integer-only:

- The exact-one sketch retains the first 4096 all-positive clauses in DIMACS
  order whose width is 2 through 16 and whose variables are distinct. A fixed
  two-hash, 2^22-bit Bloom sketch records every all-negative, non-loop binary
  pair. `exact_one_sketch_pair_coverage_ppm` is the floor-scaled fraction of
  required candidate pairs found in the sketch, and
  `exact_one_sketch_full_groups` counts candidates with complete sketch
  coverage. Candidate work is bounded by 4096 groups and 120 probes per group.
  Bloom collisions can overestimate coverage, while the candidate cap can omit
  later groups; this is a routing signal, not a recognizer or proof.
- The binary graph is an undirected clause-occurrence multigraph. Every
  non-loop binary clause contributes one edge, duplicate clauses remain
  parallel edges, and sign is ignored. The features report edge and incident
  vertex counts plus maximum occurrence degree. This needs one array indexed
  by the already-declared DIMACS variable bound and no adjacency set.
- Occurrence concentration uses all literal occurrences, including duplicate
  literals. Top-1 share, top-10 share, and Herfindahl concentration are floored
  after multiplication by 1,000,000, so every `*_ppm` feature is in
  `[0, 1000000]`.

Family and split strings remain audit metadata only. None of the v2 structural
features contains a path, filename, family id, split, published verdict, timing,
or policy outcome.

### Schema and migration

This is extractor schema 2 / `wassat-static-v2`, training CSV schema 2. The
extractor pins the semantic payload SHA-256
`6c74c4ea6a670c9ff8aab655baa60243d4f34c2869d3accd91d9924afea244ca`
in every instance record and refuses to resume a JSONL with a different
version, ordered name list, or checksum. The trainer independently pins Koala's
ordered-name checksum `730840193`, verifies it before load and train, enforces
the bounded feature maxima, and requires exported trees to carry the same
checksum.

V1 JSONL and 28-column CSV files are intentionally incompatible. Start a new
JSONL, re-extract features, rerun paired label aggregation, and retrain; do not
append v2 records to an old collector output. Existing generated 22-feature
routers retain their own checksum but cannot accept v2 vectors. No family split
assignment changes because `SPLIT_VERSION` and the family-only hash remain
unchanged.

## Models and leakage boundaries

The fixed deterministic comparison set is:

- CART depths 2, 3, and 4;
- nine-tree random forest, depth 3, seed 1729;
- linear SVC;
- multinomial/binary logistic regression;
- pure-L2 ElasticNet (`alpha = 1`, `l1_ratio = 0`), decoded to the nearest
  train label.

All receive CSV sample weights. Predictions are evaluated externally rather
than through estimator accuracy. Trees see raw arrays. Linear models see
weighted standardization fitted on train only. Candidate selection uses
validation only; no candidate record contains test metrics. After the winner
is locked, the trainer evaluates only that winner and the already-fixed
baseline on test.

Selection prioritizes mean per-family regret per weight, then row-weighted
regret, per-family and row-weighted utility capture, realized utility,
false-disable cost, family accuracy, weighted accuracy, and macro F1.
First-listed candidates win exact ties, favouring the smallest tree. This keeps
a large generator family from electing the router by row count.

The conservative baseline is the better validation result of fixed arm 0 and
the train-weighted majority label. Export additionally requires:

1. the selected model is a `DecisionTreeClassifier`;
2. validation utility capture improves by at least 0.01;
3. family utility capture and weighted accuracy do not regress;
4. false-disable cost does not increase.

The generated function requires feature-schema checksum `730840193` and exact
width 31.
Pin the exported checksum independently beside Wassat's feature construction;
passing the generated checksum helper directly would defeat the drift guard.

## Cost interpretation and limitations

For each row, predicting arm 0 realizes zero utility and predicting arm 1
realizes `weight * (baseline PAR-2 - treatment PAR-2)`. Oracle utility is the
positive part of that delta; regret is oracle minus realized utility. Choosing
a harmful treatment therefore increases regret naturally. Predicting arm 0
when the conservative label is 1 additionally records the missed positive
delta as false-disable cost.

The label deliberately includes a material-improvement threshold, whereas
realized utility retains the raw signed delta. Classification and utility can
therefore disagree on a small positive, label-0 row; both are reported and the
export gate requires no weighted-accuracy regression. This binary delta does
not encode a utility matrix for three or more arms; add per-arm counterfactual
columns before generalizing the trainer beyond 0/1.

Koala's current linear SVC materializes a full kernel matrix even for a linear
kernel, so it is quadratic in row count and memory. The forest is intentionally
small, logistic regression has a fixed epoch budget, and this trainer performs
no validation-driven hyperparameter sweep. These are deterministic comparison
baselines, not evidence that the candidate set is globally optimal.

## Synthetic regression

```sh
bin/tungsten -o /tmp/router-trainer-spec \
  bits/tungsten-wassat/benchmarks/router_trainer_spec.w
/tmp/router-trainer-spec
```

The fixture uses family-disjoint train/validation/test XOR data. It fits every
candidate, selects the depth-2 tree on validation, verifies no candidate saw
test metrics, compares the generated source byte-for-byte, and executes the
standalone router with its schema guard.
