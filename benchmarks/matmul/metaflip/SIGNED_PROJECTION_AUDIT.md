# Signed-scheme GF(2) projection audit

This audit tests whether public exact `{−1,0,1}` schemes provide new GF(2)
restart basins. It is intentionally independent of the FlipFleet loader. The
offline parser first reconstructs every integer tensor coefficient, then
reduces signs modulo two, parity-cancels duplicate rank-one terms, transposes
the trace-dual `W` factor, and reconstructs all `n^6` GF(2) coefficients.
Distances are exact term-set symmetric differences minimized over the twelve
matrix-multiplication tensor symmetries used by basin telemetry.

## Pinned inputs and results

The `.exp` checkout is `mkauers/matrix-multiplication` commit
`12c26b29a5458e173813911fb4f2c2865fba841e`. The public JSON checkout is
`dronperminov/FastMatrixMultiplication` commit
`e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64`.

| input | source SHA-256 | projected rank/density | projection result |
|---|---|---:|---|
| `structured/555.exp` | `907d2d3328d239a302230fae67e6d847f137e7df77507ac1aef3c13676d68a30` | 93 / 1291 | exactly the checked-in Kauers-A GF(2) term set; no new door |
| `structured/k66ce4c614c48bda5-555-93-mod0.exp` | `6f37e1bfa86f9ceef6976378275d3a8af5f2d4ccf4622c9d58199d81518df894` | 93 / 1250 | exactly the checked-in Kauers-B GF(2) term set; no new door |
| `structured/666.exp` | `8d356efa699eb72ac66ff5a42bd71adfa3125ed980097517c58c9760748221dd` | 153 / 2574 | exactly the checked-in C3 GF(2) term set; no new door |
| `structured/666r153.exp` | `9c8cf3986e5e7aa1a9cf4c0c205e3c9eb05be2462f25224417947aebcc5fd213` | 153 / 2574 | the signed presentation differs, but its GF(2) projection is identical to `666.exp` and the checked-in C3 scheme |
| `4x4x4_m49_ZT.json` | `8b3d86d816f70f34b4dc47437ff1a724ebec67302dc91edc8805aae0d9789f33` | 49 / 432 | new exact best+2 basin, orbit distance 96 from rank-47/d450; serialized and admitted to the file-backed near2 inventory |
| `7x7x7_m250_ZT.json` | `c70dc17ec47606923d2f0a890c9b680fd2798bb12f373dfca70094a0ff0aecd6` | 250 / 2966 | exactly `matmul_7x7_rank250_d2966_gf2.txt`; no new door |

The canonical sorted-term payload SHA-256 values, in table order, are
`1545de975ce0ff10de38041d877e75f6de1774b28a7998bbd9e34dcab9f38d01`,
`607b8a1c341237eb773b7b70e3d4fcbe78a3a27765229e3d5b428841464b62e2`,
`996049a55bd8128be5c4f259726a63ad03dc3be56115ee4699420fbe1119baec`,
the same `996049a55bd8128be5c4f259726a63ad03dc3be56115ee4699420fbe1119baec`
digest for `666r153`,
`89163520f10686285c0d683e18288db8767d26b2843186be068f091739746ef9`,
and `6833e3c8ec1a5cf2be431f1453b51ebd091c5f424e69a9be8a6ab9b4fee04986`.

All six source schemes pass the independent integer gate before reduction,
and all six projections pass the independent GF(2) gate with zero coefficient
mismatches. None loses a term through parity compaction. The new 4×4
certificate is
`matmul_4x4_rank49_d432_signed_4x4x4_m49_zt_gf2.txt`, SHA-256
`ea68aa2b5fb8db8760c6a05a4296e07bca148941cfe3881801d5c5a526d771c2`.
Its base-case no-CSE model is 49 multiplications plus 318 additions, or 367
operations. It is a search shoulder, not a rank record.
Directed whole-scheme GF(2) isotropy descent tested the complete 36-generator
neighborhood and 256 deterministic conjugate restarts; all returned to density
432, so the checked-in presentation is already the best found in that bounded
orbit search.

## Zero-relation locality

Because two exact schemes for the same tensor have an exact-zero XOR, the
audit also decomposes each difference by exact-factor adjacency and gates
every component separately.

- Kauers-A versus the nearest nonidentical 5×5 archive image has orbit
  distance 8. The relation is exactly two independent four-term, 2↔2
  ordinary flips. This is not a new tunnel primitive.
- The keyed rank-93 5×5 projection is Kauers-B itself. Its nearest
  nonidentical archive relation has distance 186 and no independently zero
  exact-factor component.
- The 6×6 C3 projection versus `d2502` has distance 48. It is exactly twelve
  independent four-term, 2↔2 ordinary flips. Again, no new primitive.
- The signed 5×5 and 6×6 projections are respectively distance 186 and 306
  from the current density leaders. Those leader XORs have no independently
  zero exact-factor component and are too global for bounded local surgery.
- The new rank-49 4×4 projection is distance 96 from rank-47/d450. Its
  96-term XOR also has no independently zero exact-factor component. That
  makes it useful as a distant restart shoulder, but not as a directly
  replayable local move.
- The public rank-250 7×7 projection is distance 497 from the rank-247 leader,
  but it was already retained in the old-frontier inventory.

## Reproduction

```sh
python3 benchmarks/matmul/metaflip/signed_projection_audit.py \
  --source-repo /tmp/matrix-multiplication \
  --zt-repo /tmp/FastMatrixMultiplication-current

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_profile_shoulders_test.w \
  -o /tmp/flipfleet_profile_shoulders_test
/tmp/flipfleet_profile_shoulders_test
```

The shoulder test independently reloads and full-gates the rank-49
certificate, checks density 432 and raw distance 96, and verifies that a
frontier mismatch cannot mislabel it as best+2. The live coordinator loads
the profile only at startup or a frontier rebuild. It does not add a CPU
lane, GPU lane, TUI element, or hot-loop branch.
