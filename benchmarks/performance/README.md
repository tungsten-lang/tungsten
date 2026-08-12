# Performance CI

The Performance GitHub workflow measures the base and candidate revisions on
the same Blacksmith VM. Each primitive receives a three-second warmup and three
independent, calibrated samples. `scripts/performance-ci.py` writes the raw
samples, medians, median absolute deviations, runner identity, revision, and
build profile to JSON.

A candidate regresses when its median falls below the baseline by more than the
larger of ten percent or three baseline median absolute deviations. A baseline
whose band exceeds twenty-five percent is rejected as too noisy. Comparisons
also stop when the Blacksmith label, OS, architecture, CPU model, or allocated
logical CPU count differs; results from unlike runner generations are never
silently compared.

Long-term files live in `baselines/`. To refresh them, manually dispatch the
Performance workflow with `update_baselines` enabled. The update job uses the
`performance-baselines` GitHub environment, which should have required
reviewers configured, and opens a pull request containing the new JSON. Review
the hardware identities, all samples, calculated bands, and deltas before
merging that PR. Repository Actions settings must also allow GitHub Actions to
create pull requests; if that permission is disabled, the benchmark artifacts
remain downloadable but the update job will fail before changing the branch.
