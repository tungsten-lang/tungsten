# PORT-REPORT: GF(2) scheme foundation library and the Tungsten tensor verifier

Branch `port/scheme` (worktree `/Users/erik/tungsten-mf-port-scheme`), base `1010f8c0e`.
Toolchain: `/Users/erik/tungsten/bin/tungsten` (run from the worktree with `BIT_HOME=<worktree>/bits`),
`python3` 3.14.7, `ruby` 4.0.6, Apple M5 Max, machine shared and heavily loaded during the runs
(load average 25-60), so every wall time below carries CPU time next to it.

Status: library, tool, tests, fixtures and parity harness complete and committed. Timing table:
section 4 (filled from `spec/verify_tensor_parity_test.py time`; see "Open items" if it still says PENDING).

## 1. Files

Library (`bits/tungsten-metaflip/lib/metaflip/gf2/`), every file documents its API in its header:

| file | what |
|---|---|
| `bits.w` | `Metaflip:Gf2:Bits`: popcount, low/high bit index, set-bit positions, remap (negative entry drops a bit), transpose, from_positions, Integer <-> 64-bit limb conversion, lowercase hex format/parse, raw-pointer byte scanners, `release` |
| `packed.w` | `Metaflip:Gf2:Packed` (a scheme as `i64[]` limb arrays), `Metaflip:Gf2:Defect`, and the two independent exactness gates: dense table (Ruby formulation) and sparse hash table (Python `exact` formulation); both name the first wrong coefficient (row-major `(a, b)`, with expected and actual `w` masks) |
| `scheme.w` | `Metaflip:Gf2:Scheme`: n, m, p and parallel `us/vs/ws` Integer-mask Arrays; strict MFW1 reader (`parse`, `read`), canonical `blob`, `sha256`, `density`, `sorted`, `cleaned` (mmc `clean`), `terms`, shape keys, `cyclic_shift`, `transpose`, `oriented(perm)`, `oriented_to(target)` (verify_cofactor_mergers `orient`), `orient_as` (mmc), `naive`, `defect/exact?/verify(gate)`, `pack`, `release` |
| `tensor_verifier.w` | `Metaflip:Gf2:TensorVerifier`: port of `MetaflipTensorVerifier` (`dimensions`, `infer_shape`, `expand_path`, `read`, `verify_text`, `verify`, `main`) + `read_scheme` (any certificate format -> Scheme) |

Tool: `bits/tungsten-metaflip/tools/verify_tensor.w` (5 code lines around `TensorVerifier.main`).
Options as `verify_tensor.rb` (`--shape`, shape inference from the path, one or more certificates, same JSON,
same `Tensor verification failed: ...` on stderr + exit 1, `-h`, `-v`, `--opt=value`, `--`) plus
`--gate dense|sparse|both` (default both), `--strict` (canonical MFW1 = Python `read_blob` rule),
`--batch LISTFILE` (one path per line, optional TAB + `NxMxP`) and `--keep-going`.

Tests and evidence tools (`bits/tungsten-metaflip/spec/`): `gf2_scheme_test.w`, `verify_tensor_test.w`,
`gf2_scheme_parse_parity.w` (argv driver), `verify_tensor_parity_test.py` (corpus / mutate / fuzz /
parse-fuzz / time), `fixtures/gf2_scheme/` (147 files, 1.26 MB, none over 200 KB; `generate.py` rebuilds
all of it from the Python/Ruby originals). Docs: a short section in `bits/tungsten-metaflip/README.md`
and a bullet in `lib/metaflip/README.md`. Also `PORT-BLOCKERS.md` (five findings).

## 2. Lines of code (`wc -l`, code = without comments and blank lines)

| | original | port |
|---|---|---|
| verifier tool | `tools/verify_tensor.rb` 103 (91 code) | `tools/verify_tensor.w` 32 (5) + `tensor_verifier.w` 588 (463) |
| MFW1 IO + gate | `read_blob`, `blob` 16; `exact` 14 (`spec/*_parity_test.py`) | `scheme.w` 472 (313) + `packed.w` 544 (411) |
| bit helpers | `bits`, `popcount`, `remap`, `T`, `Alg` orientation moves in `tools/mmc_gf2_alg.py` (about 90 of its 685) | `bits.w` 368 (221) |
| total | about 225 (about 200 code) | 2,004 (1,413 code) |

The port is about 7x larger because it is more: two gates instead of one each, a strict and a lenient reader,
64-bit limb kernels, explicit memory release (no GC), `--batch/--gate/--strict`, and long header
documentation (about 30% of the lines are comments). Tests: 396 + 246 + 30 lines of Tungsten,
765 lines of Python harness, 334 lines of fixture generator.

## 3. Parity with the originals (real data, counts)

All commands from the worktree root; `CORPUS=/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work/port-corpus`,
`BIN` = `bin/tungsten -o verify_tensor bits/tungsten-metaflip/tools/verify_tensor.w --release`,
`H=bits/tungsten-metaflip/spec/verify_tensor_parity_test.py`.

1. **Whole corpus, 1,087 tensors** (shapes 2x4x17 ... 28x32x32, ranks 94 ... 14,271):
   `python3 $H corpus --corpus $CORPUS --binary ./verify_tensor --out DIR`
   Ruby `verify_tensor.rb` (one process per file), Python `read_blob` + `exact`, and Tungsten (one `--batch`
   process per mode) produce identical records `{exact, shape, rank, density, sha256}`:
   Python == Ruby **1087 of 1087**; Tungsten default (both gates) == Ruby **1087 of 1087**;
   `--gate dense` **1087/1087**; `--gate sparse` **1087/1087**; `--strict` **1087/1087**. Ruby accepted 1087 of 1087.
   (25 files carry a permuted shape in their header versus `corpus.tsv`, e.g. `7x16x12` for `7x12x16`; the
   header shape is used, as any consumer must.)
2. **Mutations, 210 sampled tensors** (all corpus tensors up to 400 KB, seed 1):
   `python3 $H mutate --corpus $CORPUS --binary ./verify_tensor --samples 210`
   4,169 certificates (210 originals + 3,959 mutants, 20 kinds). Semantic mutants (bit flip in u, v, w;
   dropped term; duplicated term; C in the transposed public layout; wrong rank; wrong shape; zero factor;
   out-of-range factor): rejected by Ruby, Python, Tungsten and Tungsten `--strict` in every case.
   All four implementations agree on **2,699 of 2,699** accept/reject verdicts (originals + semantic mutants +
   uppercase hex). Text-level mutants where the originals themselves disagree (unsorted rows, CRLF, blank line,
   comment line, trailing space, missing final newline, leading zero, a cancelling pair of extra terms: Ruby
   accepts, Python rejects) are reproduced exactly: Tungsten default == Ruby and `--strict` == Python on
   **4,169 of 4,169** certificates.
3. **Byte-level fuzz of the certificate reader** (whitespace of every kind including NUL/VT/FF, tokens, lines,
   case, headers, three formats, walk-generated exact schemes, random inexact schemes):
   `python3 $H fuzz --corpus $CORPUS --binary ./verify_tensor --cases 8000 --seed 2`
   **8000 of 8000**: Tungsten under each of the three gates equals Ruby in exit status, stdout and stderr byte for
   byte, and `--strict` equals Python's verdict (Ruby accepts 1,424, Python 144, both 144). Earlier runs with previous
   binaries: 6,000 + 800 + 300 cases, all equal.
4. **Strict reader alone** against `read_blob` (`spec/gf2_scheme_parse_parity.w`):
   `python3 $H parse-fuzz --corpus $CORPUS --parse-binary ./gf2_scheme_parse_parity --cases 20000 --seed 7`
   20,000 damaged canonical files: both accept 3,008 (same rank, same digest), both reject 16,827,
   documented deviations 165 (below), **unexplained 0**.
5. **Golden unit tests** (`gf2_scheme_test.w`, `verify_tensor_test.w`): bits/popcount/transpose/remap of 100+
   masks up to 1,024 bits against `mmc_gf2_alg.py`; every S3 orientation of 8 schemes (including 4x4x8 with a
   repeated dimension and 529-bit masks) against `mmc_gf2_alg` and `verify_cofactor_mergers.orient`; `clean`;
   naive schemes at 12 shapes; every rejection category on 4 bases and mutants with the coordinate, expected
   and actual mask of the first wrong entry checked against Ruby's message and an independent Python
   recomputation; 504 random schemes (exact flip walks, damaged walks, random terms) against a brute-force
   Integer reference for both gates and for the dense gate in bands of 1, 2, 7 and 100 limbs.
   Gate mutation check: breaking the dense gate's last-word compare or the sparse gate's target toggle makes
   the tests fail (crash with "internal error ... reconstructs correctly", by design).

## 4. Timing (same inputs, this machine, load average 25-60 from other sessions)

Whole corpus (3,950,582 terms, 937 MB of text) and per invocation: **PENDING**, filled below from
`python3 $H time --corpus $CORPUS --binary ./verify_tensor --runs 3` (`wall` / `cpu` seconds, median of 3
for the Tungsten and single-file cells, one pass for the Ruby/Python whole-corpus loops).

Provisional measurements taken earlier on the same inputs, unloaded-ish moments:

| input | Ruby `verify_tensor.rb` | Python `read_blob` + `exact` | Tungsten `--release` |
|---|---|---|---|
| largest tensor 28x32x32, rank 14,271 (7.2 MB), one process | 1.17 s wall (0.99 user) | 1.98 s (0.04 read_blob + 1.66 exact + 0.12 import) | dense gate only 0.07 s, sparse only 0.09 s, both 0.15 s |
| tiny tensor (Strassen), one process | 0.04-0.05 s (0.21 cold) | (interpreter + imports ~0.15 s) | 0.005-0.01 s |
| whole corpus, one process | 214.6 s (sum of 1,087 process runs, 3 concurrent) | 264.9 s (in-process loop, 3 concurrent) | 7.2 s dense / 11.3 s sparse / 15-18 s both / 21-22 s strict |

In-process phases on the largest tensor (`--release`, ms): read 2, strict parse to Integer masks 37,
lenient parse to limbs 35, density 16, Integer -> limb conversion 20, dense gate 39-57, sparse gate 60-100,
blob 31-42, SHA-256 3. Orientation of that scheme: `cyclic_shift` 57 ms, `transpose` 98 ms, `sorted` 3 ms,
`cleaned` 7 ms. Peak RSS of the whole-corpus batch: 138 MB dense, 902 MB sparse, 909 MB both, 914 MB strict.

## 5. Tests added (classification is the integrator's; suggestions)

| test | kind | runtime | suggested list |
|---|---|---|---|
| `spec/gf2_scheme_test.w` | self-test (prints `PASS gf2 scheme library`) | 0.5 s as a `--release` binary; 4-9 s through `bin/tungsten spec/gf2_scheme_test.w` (first compile included) | `native_tests.txt`, reason: interpreter never frees BigInts/typed arrays (8 GB in seconds, PORT-BLOCKERS.md 4) |
| `spec/verify_tensor_test.w` | self-test (prints `PASS verify_tensor`), also runs the tool as a process, needs `$TUNGSTEN` (or a working `bin/tungsten`) | 0.7 s binary; 5-9 s cache-run | `native_tests.txt`, same reason (also uses `Integer#chr`, compiled only) |
| `spec/gf2_scheme_parse_parity.w` | argv driver, not a `_test.w` | - | none |
| `spec/verify_tensor_parity_test.py` | Python parity/fuzz/timing driver, needs the corpus path | corpus 6 min, mutate 25 min, fuzz 8,000 cases 20 min on the loaded machine | none |

Run: `BIT_HOME=$PWD/bits TUNGSTEN=/Users/erik/tungsten/bin/tungsten /Users/erik/tungsten/bin/tungsten bits/tungsten-metaflip/spec/gf2_scheme_test.w`
(captured output must contain the PASS line and no FAIL). `metaflip_test_manifest_spec.w` will list both new
`_test.w` files as unclassified until the integrator adds them; expected.

## 6. Deviations from the originals' behaviour (and why)

1. `Scheme.parse` (strict MFW1) refuses negative numbers, non-positive dimensions and rows whose field count is
   not three at parse time. `read_blob` lets these through (it builds tuples of another length or with negative
   entries) and `exact` refuses them one step later, so no accept/reject decision that also needs exactness
   changes (measured: 165 documented deviations in 20,000 damaged files, 0 unexplained).
2. `verify_tensor.w` default gate is `both` (Ruby had only the dense table); output and verdicts are identical.
3. `-v/--version` prints `verify_tensor.w: version unknown` (OptionParser's default text with the tool's name).
   Long options may be abbreviated to a unique prefix among the seven this tool has, so `--s` is ambiguous here
   while Ruby (one option) accepted it as `--shape`.
4. A file that cannot be read always reports Ruby's ENOENT text (`No such file or directory @ rb_sysopen - PATH`),
   also for directories and permission errors. `--shape` is refused above 2^20 bits per matrix ("shape too large").
5. `expand_path` is lexical like `File.expand_path` (relative names against `getcwd`, `~` and `~/x` only, no `~user`).
6. Memory: the dense and sparse gates raise a clear error instead of allocating more than 2 GiB of limbs.
7. `Scheme` API is Integer-mask based with Arrays returned by value (no blocks: interpreter limitation, see
   PORT-BLOCKERS.md 5).

## 7. Blockers and workarounds

`PORT-BLOCKERS.md` (repo root; the integration branch already has one from `port/support`: concatenate, my
entry 1 duplicates its entry 5): (1) `String#to_i(16)` saturates at 2^63-1 -> hex folded into limbs by hand
(`# TODO(port)` in `bits.w`); (2) string `+` drops an embedded NUL from `0.chr` -> tests use literals;
(3) `run --interpret` does not coerce arguments to typed `(i64)` parameters -> limb helpers read 32-bit halves;
(4) no `w_value_free_w` in the interpreter and unbounded interpreter memory -> `Bits.release` guards the ccall,
tests are native; (5) `&block` on class methods is not bound under `run --interpret` -> no block APIs.
Also learned (not bugs, but they cost time; useful for the other ports): untyped locals that receive a raw
`i64` of 2^47 or more box a heap BigInt that nothing frees; a literal-base shift `1 << n` in typed code goes through
the promoting lane; `String#byte_at` costs two C calls per byte (30x slower than `raw_load_u8` over
`w_string_data_ptr`, which `Bits.text_ptr/byte` wrap and which is invalid for strings of 5 bytes or fewer);
`\{` and `\v` are not string escapes; a trailing `+` does not continue a line.

## 8. Notes for the integrator and the other ports

* `lib/metaflip/SHA256SUMS` and `manifests/runtime-sources.tsv` (`spec/runtime_manifests_test.w`) must be
  regenerated with `tungsten tools/regen_manifests.w` after merging (kept in a separate commit on this branch so it
  can be dropped and redone).
* `lib/metaflip.w` (public entry) is untouched: add `use metaflip/gf2/scheme` there if the API should be public.
* After merging `port/support`: `TensorVerifier.json_string` / `pretty_json` (about 45 lines) can be replaced by
  `Jsonx.pretty_generate`; I did not depend on it because it is not on this branch.
* API cheat sheet (details in the file headers): `Metaflip:Gf2:Scheme.parse(text)`, `.read(path)`, `.naive(n,m,p)`,
  `.from_terms`; `s.us/vs/ws`, `s.terms`, `s.density`, `s.blob`, `s.sha256`, `s.sorted`, `s.cleaned`,
  `s.cyclic_shift`, `s.transpose`, `s.oriented_to([n2,m2,p2])`, `s.defect(:both)`, `s.exact?`, `s.verify`;
  `Metaflip:Gf2:Bits.positions/popcount/remap/transpose/from_positions/to_hex/from_hex`.
  No garbage collector: loops over thousands of schemes call `scheme.release` (only for schemes whose masks
  nothing else references) and `Bits.release`.

## 9. Open items

* Section 4 whole-corpus/per-invocation table: PENDING until `final_timing.log` lands (run started; result copied here).
* Manifests regeneration commit: pending (last step, after the last edit under `lib/`).
