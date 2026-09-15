# Experimental residual ranker v1

`model-v1.mfl` is a local synthetic-data MLP, not a rank oracle or a
third-party decomposition corpus. It predicts the smallest observed synthetic
recipe length (an upper bound). Only its ordering is used; no model prediction
can prune as an exact bound or admit a tensor.

Architecture: 18 standardized features -> 24 ReLU units -> one linear output.
The sorted mode descriptors are the unfolding rank and the normalized histogram
of matrix ranks 0..4 over every nonzero slice combination. No factor-density,
parent identity, removed-recipe, or future-outcome features are inputs.

Training and assessment: `tools/learned_residual_completion.py` and
`tools/LEARNED-RESIDUAL-AUDIT-2026-09-14.md`. Synthetic rows were split by the
entire basis/mode-invariant feature vector; real seed windows never trained.
The offline real recovery benchmark tied popcount at 150/300 and was slower,
although learned-only same-rank representations occurred. Neither the offline
audit nor the subsequent native correctness tests established a rank or
composition gain. The public flag and runtime integration were removed:
production strategies must earn automatic use, not become opt-in switches.

The native model/search source remains here solely for research and matched
testing. Nothing under this directory is imported by `bin/metaflip` or shipped
in its `lib` runtime asset. The normal refinement pipeline is unchanged.

Provenance:

- Original audited training source SHA-256:
  `c8c10724b8f01d4a89c6c7a21d07bbfaa4396d87b6c871af0718e8f6e0c91747`
- Original JSON model SHA-256:
  `072123bbb652681b2364955e51b4a077a3d10d3a94462e62a6a609223f72af60`
- Native MFLR1 SHA-256:
  `98706ff9184e1f6ac62ce8c38f9986664fa5d45ea864a7794c018c5731d1f46e`
- Export: `python3 tools/export_learned_residual.py MODEL.json OUTPUT.mfl`

Format: header `MFLR1 sorted-slice-ranks 18 24 1`, followed by exactly 517 finite
decimal numbers, one per line: mean[18], scale[18], row-major w1[18,24], b1[24],
w2[24,1], b2[1]. Magnitudes must be <1e6 and scales >=1e-6. Export and inference
are tested against the independent Python model. This research fixture is
10,840 bytes; training datasets and search archives are not bundled.
