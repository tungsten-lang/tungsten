# Float#to_f / BigInt#to_i production revisit

Status: both independently rebuilt production campaigns passed every semantic,
IR, and relaxed performance gate on 2026-07-15. Retain both migrations.

## Candidate

- `Float#to_f` in `core/numeric/float.w` is exactly `self`.
- `BigInt#to_i` in `core/numeric/big_int.w` is exactly `self`.
- `core/numeric/big_int.w` explicitly imports its existing `Int` superclass;
  `Int` is not an autoload-registry entry, so source-loading BigInt without
  that dependency otherwise leaves an undefined `@class.Int` in LLVM.
- Only `w_ic_float_to_f` and `w_ic_bigint_to_i`, their public table rows,
  and the consequent table-name indices are removed from `runtime/runtime.c`.
- The integrated loader schedules Float on the first source-defined Float
  method name and nests the one-shot BigInt `to_i` schedule under the existing
  Integer leaf-method gate. Call-name gates are intentional: either receiver
  can cross a parameter or native-call boundary with no sound AST shape. The
  loader AST-cache epoch advances so an older cache cannot omit the required
  source classes.
- No interpreter change is needed. Primitive runtime-class lookup already
  autoloads both source classes before its builtin/runtime fallback.
- `compiler/tungsten.w` explicitly includes the two source classes as a
  bootstrap anchor. The previous compiler's loader cannot know the new
  call-name rule while it is compiling the first candidate compiler, and that
  candidate already links the runtime with the identity ICs removed.

The bare receiver return is the logical optimization endpoint: it preserves
all Float WValue bits and BigInt heap identity while emitting a single
`ret_i64 %__self` in WIRE and LLVM.

## Results

Both campaigns used 10 balanced four-leg observations per stratum, 40 million
public calls per leg, one million warmup calls, and per-thread CPU time. Each
reported ratio is the median of paired `(source + source) / (native + native)`
ratios; the retention ceiling was 1.10.

| Campaign | Stratum | Native ns/call | Source ns/call | Median ratio | Decision |
|---|---|---:|---:|---:|---|
| first | Float finite | 5.051948 | 4.959072 | 0.981921 | retain |
| first | Float NaN | 4.913459 | 4.973906 | 1.007306 | retain |
| first | BigInt one limb | 5.115890 | 4.879376 | 0.956808 | retain |
| first | BigInt multiple limbs | 4.971745 | 4.913713 | 0.996763 | retain |
| repeat | Float finite | 4.985175 | 4.997831 | 0.998290 | retain |
| repeat | Float NaN | 5.116031 | 5.007414 | 0.979297 | retain |
| repeat | BigInt one limb | 5.059311 | 4.942861 | 0.984043 | retain |
| repeat | BigInt multiple limbs | 5.099171 | 4.937927 | 0.967064 | retain |

All 80 paired observations carried the exact 40,000,000 identity checksum.
Raw data and compiler/bootstrap hashes are in
`/tmp/identity-leaf-first-20260715.txt` and
`/tmp/identity-leaf-repeat-20260715.txt`. The first campaign completed all raw
observations before its original macOS-awk summary formatter rejected an
unparenthesized print ternary; the table above was recomputed directly from
the complete raw file, and the corrected formatter passed the repeat.

The audit also exposed two pre-existing compiler issues outside this
migration. Assigning a heap-BigInt `to_i` result can inherit an integer type
fact and nan-unbox its pointer; implicit numeric result-`each` has the same
problem when choosing its loop count. Correctness and timing therefore consume
the public result directly through `wvalue_bits`, while the real-syntax block
parity probe breaks immediately after its first entry. Neither workaround
changes the production candidate.

## Correctness envelope

`identity_leaf_public_ref.c` constructs:

- both signed zeros;
- minimum/maximum signed subnormals;
- minimum signed normals and maximum signed finite values;
- both infinities;
- positive/negative quiet/signaling NaN inputs under normal canonical boxing,
  plus dispatch-safe raw positive quiet and signaling NaN payloads (biased raw
  negative NaNs wrap into the heap dispatch range and are not public Float
  receivers);
- 26 BigInts covering heap zero, both signs, one through four limbs, sparse
  limbs, spare capacity, and the i48/i64/128/192/256-bit boundaries.

Every case checks plain calls, one surplus argument, three surplus arguments,
and exact receiver bits. Native Float preserves its implicit-result-`each`
failure. Heap BigInt's established statement-position behavior is tested in a
helper that returns a fixed sentinel: a separate noncanonical heap BigInt
containing 2 must retain receiver identity, enter the block once, and
immediately `break` in both roots. The break bounds a pre-existing lowering
bug that nan-unboxes the heap pointer as the implicit iteration count; binding
the outer result also exposes a separate nil-as-integer type-fact bug. The
candidate tree walker separately checks its block-passing behavior.

## Gate

The runner first proves the exact identity bodies and their integrated v16
autoload/bootstrap and current-pruned IC-table shape. This source-shape audit
deliberately tolerates unrelated ports in the shared worktree. The full gate
then uses one common bootstrap to build fresh matched baseline/candidate
compilers in the same temporary path, compiles a shared no-`use` workload,
and audits exact WIRE, content-hashed LLVM, autoload, interpreter, runtime
behavior, and IC reindexing.

Static audit only (safe while another timing lane is active):

```sh
STATIC_ONLY=1 benchmarks/runtime_ports/run_identity_leaf_public.sh
```

Full proof without timing:

```sh
BOOTSTRAP_COMPILER=/absolute/path/to/common/compiler \
  CHECK_ONLY=1 benchmarks/runtime_ports/run_identity_leaf_public.sh
```

First and independent repeat campaigns after lane release:

```sh
BOOTSTRAP_COMPILER=/absolute/path/to/common/compiler \
  CHECK_ONLY=0 benchmarks/runtime_ports/run_identity_leaf_public.sh

BOOTSTRAP_COMPILER=/absolute/path/to/common/compiler \
  CHECK_ONLY=0 REPEAT=1 benchmarks/runtime_ports/run_identity_leaf_public.sh
```

Each sample is `native/source/source/native` or the reverse, summed before its
ratio, with elapsed time measured by `CLOCK_THREAD_CPUTIME_ID`. The clock
ccalls live directly in three-argument timing functions: this deliberately
bypasses the compiler's current memoization of pure functions with at most two
arguments (an unknown zero-argument ccall wrapper would otherwise cache its
first timestamp). The checksum consumes each public result directly through
`wvalue_bits`; assigning a heap `to_i` result first triggers the pre-existing
integer type-fact/nanunbox bug described above. Float finite and NaN strata,
and BigInt one-limb and multi-limb strata, are independent. The relaxed policy
retains a method only when every selected stratum is at or below `GATE=1.10`
in both independently rebuilt campaigns.
