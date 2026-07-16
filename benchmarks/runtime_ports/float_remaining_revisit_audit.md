# Remaining Float leaf relaxed revisit

Status: **retain all five methods** as of 2026-07-15. The revised candidate
passed the full build/IR/correctness gate and two fresh, independently rebuilt
ten-observation campaigns. Every method's paired median was at most 1.10 in
both campaigns. The retained production delta is now integrated in the shared
tree at loader epoch `v16`; the measurements below remain the isolated
seven-file candidate-over-baseline evidence. Artifact hashes below identify
the measured isolated package; the shared runner and this audit were then
rebased only for the combined production table/epoch and integration note.

## Matched roots

- Baseline: `/tmp/tungsten-float-remaining-baseline`, detached at `f62869b`.
- Candidate: `/tmp/tungsten-float-remaining-candidate`, detached at `f62869b`.
- Both roots first receive the already-retained Float state only:
  `to_f`, `abs`, `nan?`, and `infinite?` source bodies; their four removed C
  IC rows; the Float bootstrap anchor; narrow call-name autoload; cache epoch;
  and the interpreter's exact positive-Float `wvalue_from_bits` bridge.
- The measured candidate delta is therefore only `floor`, `ceil`, `round`,
  `sqrt`, and `sq` plus the support required after those five IC rows vanish.

## Semantic triage

| Method | Historical Float IC | Source candidate | Semantic result |
|---|---|---|---|
| `floor` | `w_int((int64_t)floor(w_as_double(r)))` | `w_int(w_numeric_to_i64(Math.floor(self)))`, with the inner result raw | sound on the same target/toolchain |
| `ceil` | `w_int((int64_t)ceil(w_as_double(r)))` | `w_int(w_numeric_to_i64(Math.ceil(self)))`, with the inner result raw | sound on the same target/toolchain |
| `round` | `w_int((int64_t)round(w_as_double(r)))` | `w_int(w_numeric_to_i64(Math.round(self)))`, with the inner result raw | sound on the same target/toolchain |
| `sqrt` | `w_box_double(sqrt(w_as_double(r)))` | `Math.sqrt(self)` | exact wrapper equivalence |
| `sq` | shared `w_mul(r, r)` | `self * self` | exact operator equivalence |

The existing hidden `Float#floor/#ceil/#round` bodies were a real semantic
blocker as written: `Math.floor`, `Math.ceil`, and `Math.round` return Float,
whereas the public Float ICs return Integer. The candidate corrects the bodies
instead of exposing that mismatch. The source-level
`ccall_nobox("w_numeric_to_i64", ...)` states the same
dynamic-double-to-`int64_t` boundary as the old handlers. Revised lowering
recognizes only this exact Math composition and emits raw libm plus LLVM
`fptosi`, avoiding the otherwise redundant box/callback/unbox chain. Outer
`w_int` preserves the old checked i48/heap-BigInt boxing at INT64 boundaries.

Converting NaN, infinity, or an out-of-range double to signed integer is not a
portable mathematical contract in C. Tungsten's existing contract is the
behavior of its compiled target/toolchain. The candidate intentionally routes
those values through the same libm operation and LLVM conversion emitted for
the historical C cast on this target. Keeping the path raw also avoids an
intermediate NaN-box canonicalization. The fixture includes canonical
quiet/signaling NaN inputs, two public raw positive NaN payloads, both
infinities, both finite extremes, `+2^63`, `-2^63`, and both i48 boundaries to
detect any actual divergence.

`sqrt` preserves `-0`; both paths use the same libm operation and canonical
Float boxer, so negative finite inputs and every NaN become the same canonical
NaN. `sq` uses the exact runtime numeric multiply in both paths, including
overflow to infinity and NaN canonicalization. Defining `sq` directly on
Float avoids loading Number merely to inherit its identical one-line body.

Every five historical handlers ignores its argument vector and count. The
public fixture therefore checks zero, one, and three surplus arguments across
all 32 representations. Rounding methods' trailing blocks retain the existing
implicit-result-`each` behavior with bounded counts `1/2/2` for receiver 1.5.
`sqrt` and `sq` return Float, so their trailing-block path must fail with the
same status in both roots.

## Runtime and loading delta

The baseline Float IC table contains exactly seven retained rows after the
earlier four migrations:

`to_i, to_s, sqrt, ceil, floor, round, sq`.

The candidate table contains exactly `to_i, to_s`. It removes only the four
Float-specific C functions and Float's row using shared `w_ic_num_sq`;
`w_ic_num_sq` itself and Decimal's row remain intact.

Candidate autoload extends the existing one-shot Float call-name gate with
`sqrt`, `ceil`, `floor`, `round`, and `sq`. A name gate is necessary: a Float
can enter through a parameter or arbitrary native call with no sound receiver
shape in the AST. The loader cache advances from isolated epoch v10 to v11.
The compiler retains its explicit Float bootstrap anchor so the stage-0
compiler can build the first runtime after the handlers disappear.

The only new interpreter boundary is `w_int`: compiled source uses it to box a
raw signed i64, while the tree walker already represents integers with
arbitrary precision, so its exact mirror is checked identity. Math intrinsics,
`w_numeric_to_i64`, Float primitive-class dispatch, and multiplication already
have interpreter paths.

## Prepared proof

`float_remaining_public_ref.c` constructs 32 Float cases spanning:

- signed zero, signed minimum/maximum subnormal, and signed minimum normal;
- fractions around zero and all positive/negative half ties through 2.5;
- ordinary nonintegral values;
- the positive/negative i48 boundaries and values just beyond them;
- `+2^63`, `-2^63`, both maximum finite values, and both infinities;
- normally boxed quiet/signaling NaNs and dispatch-safe raw positive
  quiet/signaling NaN payloads.

It computes references with the historical C expressions, not by calling the
public methods. The source workload has no `use` directive, so baseline calls
must hit C ICs while candidate calls must autoload Float. Separate literal and
unknown-native-factory files prove both autoload routes, and a tree-walker file
checks exact rounding type/value, signed zero, infinity, NaN, surplus args,
and square/root behavior.

The full gate used one common bootstrap to build fresh matched compilers and
asserted:

- baseline WIRE/LLVM contains none of the five Float source bodies;
- candidate rounding bodies lower their explicit Math/conversion composition
  to raw `floor`/`ceil`/`round`, `fptosi`, and `w_int`, with no intermediate
  Float box, generic numeric callback, or method fallback;
- candidate `sqrt` calls only `w_math_sqrt`, and `sq` only `w_mul`;
- each timed function retains exactly one public cached zero-argument dispatch
  and two direct `CLOCK_THREAD_CPUTIME_ID` reads;
- all compiled, autoload, block, and interpreter checks pass.

Each campaign has ten balanced `B/C/C/B` or `C/B/B/C` observations per
method, 40 million public calls per leg, one million warmup calls, internal
thread CPU time, and exact checksum equality. Run a fresh second compiler
campaign with `REPEAT=1`; retain a method only if its paired median is at most
1.10 in both campaigns. `ONLY=floor` (or another method) permits a narrow
retest or selective decision if the five methods split.

The first attempted timing run stopped after one floor observation when the
ceil checksum guard caught an invalid hot-corpus choice: `2^47 - 0.25` ceils
to heap BigInt `2^47`, so checksumming its raw WValue observes allocation
addresses and the loop performs millions of allocations. That representation
boundary remains in the 32-case correctness proof but was replaced by minimum
positive normal only in ceil's allocation-free timing corpus. The aborted
attempt is not a campaign and contributes no retention samples.

The first complete campaign used the initially optimized source form but
still exposed an avoidable box/callback/unbox chain around each rounding
operation. Its paired medians were floor 1.129510, ceil 1.156972, and round
1.161115 (all skip), while sqrt 1.013316 and sq 0.975850 passed. Rather than
retain the three regressions, the isolated candidate now adds a narrow
lowering peephole for exactly the source idiom
`w_numeric_to_i64(Math.floor/ceil/round(x))`. It emits raw libm followed by
LLVM `fptosi`, which is the same operation Clang emits for the old handler's
`(int64_t)` cast; the source-level outer `w_int` still performs exact boxing.
This changes the candidate, so the earlier complete campaign is diagnostic
only and contributed no final retention samples.

## Executed validation strata

All executed runs used detached matched-root HEAD
`f62869bff0fc22fdc0a3179c82fb5da158d987d6` and common bootstrap
`d0ccf3f557186992ae407a4a70de5e93a3b69b8c149e95fd6fb439776c314b78`.
The revised full `CHECK_ONLY=1` gate and both final campaigns independently
rebuilt the same compiler binaries:

- baseline: `c5e9d437bbce5a72ad02cf2c1a208e4343868f67a9d447f73240f9964f787a2f`;
- candidate: `eae747683ef38ca97296c825ab86dda9b42de715e600d75372f03d507b38c2ad`.

The revised full gate passed exact static shape, WIRE/LLVM raw-primitive
proofs, two compiled 32-encoding historical-C comparisons, zero/one/three
surplus arguments, bounded rounding block counts `1/2/2`, matching `sqrt`/`sq`
block-failure behavior, source-interpreter parity, literal autoload, and
unknown-native-factory autoload. Each hot loop retained exactly one public
cached dispatch.

Each timing row is a balanced two-baseline-leg/two-candidate-leg observation,
so the displayed median times divide the raw median sums by 80 million public
calls. `paired median` is the median of the ten individual `C/B` ratios, not
the ratio of the separately displayed time medians. `max C/B` is diagnostic;
the predeclared retention gate is the paired median.

### Final campaign A (`REPEAT=0`)

| Method | Baseline ns/call | Candidate ns/call | Paired median C/B | Max C/B | Exact checksum | Decision |
|---|---:|---:|---:|---:|---:|---|
| `floor` | 8.336884 | 8.322342 | 0.999773651 | 1.128455447 | 1310697500000 | PASS |
| `ceil` | 8.371963 | 8.316305 | 0.992069853 | 1.011502609 | 655382500000 | PASS |
| `round` | 8.317141 | 8.279473 | 0.997568485 | 1.009556554 | 1146880000000 | PASS |
| `sqrt` | 8.873622 | 9.034998 | 1.014810855 | 1.039488717 | 550230000000 | PASS |
| `sq` | 13.804933 | 13.699541 | 1.004011248 | 1.045916281 | 321050000000 | PASS |

### Final campaign B (`REPEAT=1`)

| Method | Baseline ns/call | Candidate ns/call | Paired median C/B | Max C/B | Exact checksum | Decision |
|---|---:|---:|---:|---:|---:|---|
| `floor` | 8.426520 | 8.357473 | 0.996769962 | 1.047592689 | 1310697500000 | PASS |
| `ceil` | 8.298623 | 8.341416 | 1.005734554 | 1.027997843 | 655382500000 | PASS |
| `round` | 8.448022 | 8.306979 | 0.979290014 | 1.021531498 | 1146880000000 | PASS |
| `sqrt` | 8.837910 | 9.029759 | 1.025002104 | 1.061211649 | 550230000000 | PASS |
| `sq` | 13.678861 | 13.860143 | 1.002813775 | 1.051835776 | 321050000000 | PASS |

Every raw file has exactly 50 rows: ten observations for each method, sample
numbers 1 through 10, and alternating order parity. Every observation produced
the exact checksum shown above. Campaign A's one `floor` maximum is an isolated
sample; its paired median is 0.999774, and campaign B independently returned
0.996770.

## Retention and integration guidance

Retain `floor`, `ceil`, `round`, `sqrt`, and `sq` together with their required
support:

- correct/add the five source bodies in `core/numeric/float.w`;
- remove the four Float-specific C handlers and Float's shared `w_ic_num_sq`
  row, leaving the dense Float table exactly `to_i, to_s`;
- keep `w_ic_num_sq` itself and Decimal's row;
- integrate the narrow rounding peephole and `fptosi_f64_i64` renderer;
- extend the existing Float method-name autoload gate with the five names,
  advance the loader cache epoch to v11, and add the interpreter's exact
  `w_int` identity bridge;
- retain the guarded fixtures and runner as regression coverage.

The lowering rule must remain exact. Generalizing it to arbitrary
`w_numeric_to_i64` callers would incorrectly bypass their dynamic
Int/BigInt/Float checks. No language syntax is changed.

## Artifact integrity

- Diagnostic pre-peephole raw/log (not retention data):
  `06e8ae98e062e4f11687fcf66368ddb1fae2be806f1dbf08434298c2e3ef32ef` /
  `21645601cc13bdfc423663b3bd320e94d93b5a22b11280297fa795bdb8559236`.
- Final campaign A raw/log:
  `3570b7492c9cf72adc28c8cd623411c907cc6c703c543e674bdc99c437aa46ef` /
  `abe95d461b2a9d9bb24722706f57508c5c42b30adf2d727f9456901cded4d493`.
- Final campaign B raw/log:
  `61e423d0ebf4353fd4eedee9fc2bff54c3b66b43d074369afb4952ddc2fc6b53` /
  `457f4ad23f2ded2b725b168e6722a44d50328a6c92553ae6ed54438b0f17cad2`.
- Public workload/reference:
  `c5d4c38f12cb7fd870832f2bc66dfce70adc144d25d773d638e0462c700983ec` /
  `c6b716c08a4ba5d5ab6c64d589fb360509262df1d7ed9efa4b606e883b656037`.
- Literal/factory/interpreter fixtures:
  `80a753b4489a07b5efbab564af74b3f63f30ccc199623a1903c7e7187a463b11` /
  `6d6f50a6dd603c70ae9e1ab48f0bbc0bbf71162a1cbf264b791afa56a611516f` /
  `c201d69d85f80897a695b68575c4776b95688cc390d50679351e7f268f615a1a`.
- Runner: `6a0a7ec081f79539e6db07dd5c6abc174d2668b853084f728e98a101f5401485`.
- Baseline tracked patch from matched HEAD:
  `94ab28dbd2ad9a5f008bd4f057ac8ed264a65402f3f51626ed096fdaec043e40`.
- Candidate tracked patch from matched HEAD:
  `cf101853b3ddae6a681fb3592e8161a57144b6def6eed9c141e42f4dbb397fe9`.
- Candidate-over-baseline seven-file production delta:
  `aff3aa9516f8e08d5035de4c0ffc655ad241cffdd2a3615e8ccae3416c9f6a0a`.

Static-only audit (already passed):

```sh
cd /tmp/tungsten-float-remaining-candidate
STATIC_ONLY=1 benchmarks/runtime_ports/run_float_remaining_public.sh
```

Full correctness/IR gate after lane release:

```sh
STATIC_ONLY=0 CHECK_ONLY=1 \
  BOOTSTRAP_COMPILER=/absolute/path/to/common/compiler \
  benchmarks/runtime_ports/run_float_remaining_public.sh
```

Two independent campaigns:

```sh
STATIC_ONLY=0 CHECK_ONLY=0 \
  BOOTSTRAP_COMPILER=/absolute/path/to/common/compiler \
  benchmarks/runtime_ports/run_float_remaining_public.sh

STATIC_ONLY=0 CHECK_ONLY=0 REPEAT=1 \
  BOOTSTRAP_COMPILER=/absolute/path/to/common/compiler \
  benchmarks/runtime_ports/run_float_remaining_public.sh
```
