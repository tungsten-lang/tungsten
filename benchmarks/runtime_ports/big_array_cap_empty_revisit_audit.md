# BigArray `cap` / `empty?` relaxed-gate revisit

Status: completed on 2026-07-15. The guarded CHECK_ONLY pass and two independent
ten-observation campaigns passed. The executable runner still defaults to
`ALLOW_HEAVY=0` and stops after its static audit unless explicitly released.

## Isolated roots

- Baseline: `/tmp/tungsten-bigarray-cap-empty-baseline`
- Candidate: `/tmp/tungsten-bigarray-cap-empty-candidate`
- Both are detached worktrees at `f62869bff0fc22fdc0a3179c82fb5da158d987d6`.
- Shared production `/Users/erik/tungsten` was never edited by this task.

Both roots include the already-retained BigArray `size` source port and its
minimal loader/interpreter/type support. This makes the measured delta exactly
the `cap` and `empty?` migration: the baseline retains their two C IC handlers,
while the candidate removes them.

The baseline WIRE still contains a generated `cap` data-field accessor and an
inherited `Enumerable#empty?` body. That is expected: its native IC table wins
before type-class dispatch. The gate distinguishes those bodies (`ivar_get`
and generic method dispatch) from the candidate's explicit raw view loads;
their mere presence is not evidence that the baseline stopped using C.

## Candidate implementation

`BigArray#cap` copies the retained `BigArray#size` signed-i48 box:

1. Load `$cap` and explicitly annotate it `i64`.
2. For `-2^47 <= cap <= 2^47-1`, construct the canonical immediate word as
   `0xFFFA000000000000 | (cap & 0x0000FFFFFFFFFFFF)`.
3. Otherwise call `w_int(cap)` so positive and negative overflow headers keep
   their canonical BigInt representation.

The explicit signed annotation is required. The Tungsten view declares
`size/cap` as `u64`, while `WBigArray` stores both as `int64_t`; treating a
negative raw header as unsigned would break the lower-bound test and boxing.

`BigArray#empty?` loads raw `$size`, compares it with zero, returns canonical
`true` only for zero, and returns canonical `false` for every nonzero header.
Negative headers are invalid collection states but are deliberately tested:
the removed C handler also considered them nonempty, so the source query must
not silently impose a validity policy.

## Layout and IC audit

The source data view begins after BigArray's generic-subtag discriminator. The
compiler's implicit-type-byte adjustment maps its fields to the locked C
layout:

- `WBigArray.size`: C offset 16
- `WBigArray.cap`: C offset 24

Candidate runtime changes remove only `w_ic_big_array_size` (common retained
state), `w_ic_big_array_cap`, and `w_ic_big_array_empty`. The remaining table is
contiguous and reindexed as follows:

| Index | Name | Handler |
| ---: | --- | --- |
| 0 | `WN_idx` | `w_ic_big_array_idx` |
| 1 | `WN_idxset` | `w_ic_big_array_idxset` |
| 2 | `WN_get` | `w_ic_big_array_get` |
| 3 | `WN_set` | `w_ic_big_array_set` |
| 4 | `WN_push` | `w_ic_big_array_push` |
| 5 | `WN_subview` | `w_ic_big_array_subview` |

The public `w_big_array_size` storage helper remains; removing a public query
from the dynamic IC table does not authorize deleting a direct C ABI used by
other code.

## Exactness coverage

The fixture creates real `WBigArray` views and then writes `cap` independently
of `size`. This avoids enormous allocations and separates the two query
semantics. Cases cover:

- ordinary `0`, `1`, `7`, `255`, `2^32-1`, and `2^32` capacities;
- both immediate endpoints (`-2^47`, `2^47-1`);
- both first overflow values (`-2^47-1`, `2^47`);
- `INT64_MIN` and `INT64_MAX`;
- zero size with nonzero/overflow cap;
- positive and negative nonzero sizes with zero or unrelated cap;
- exact immediate bits, BigInt signed-limb representation, and Bool bits;
- receiver header stability and `W_FLAG_VIEW` preservation;
- one and four surplus positional arguments (the old C handlers ignored all);
- zero-cap trailing-block passthrough and the historical Bool `each` fatal
  surface for `empty?` with a trailing block.

`BigArray.new` normalizes nonpositive capacity to 8, so it cannot represent the
synthetic negative boundary corpus. That is why representation tests use the
view fixture and direct raw header overwrite.

## Autoload and interpreter dependencies

Once `cap`/`empty?` have source bodies, values returned without a class
reference must still register BigArray's type class. The isolated loader:

- scans both `ccall` and `ccall_rawargs`;
- maps exactly `w_big_array_new`, `w_big_array_view`,
  `w_big_array_subview`, and `w_big_array_view_range` to `BigArray`;
- does not prefix-match (for example, `w_big_array_size` returns Integer).

Four no-`use` specs test those names independently. The subview/range specs get
their seed from deliberately unmapped `w_bace_seed`, preventing another mapped
factory from masking a missing hook.

The tree walker needs three narrow pieces already required by retained
`BigArray#size`: `w_int` identity for arbitrary-precision interpreter integers,
a raw `w_big_array_view` fixture bridge, and native class-name refinement for
generic-subtag values that otherwise appear as `Object`. The runtime type name
must therefore report `BigArray`; scalar `$size/$cap` access itself was already
allowlisted through `w_native_data_field`. Its focused spec covers boundary
boxing, zero/nonzero booleans, and surplus arguments. Trailing-block parity is
checked only in the compiled release binaries because the tree walker's
passthrough-block model is not the compiled dynamic-dispatch surface.

## Performance protocol

`run_big_array_cap_empty_revisit.sh` prepares fresh matched candidate compilers
and release/LTO binaries from the baseline and candidate runtime source. It
uses `CLOCK_THREAD_CPUTIME_ID`, adjacent alternating BASE/CAND order, ten
observations by default, and fresh caches/builds for two independent campaigns.

Seven strata are gated separately:

1. `cap.inline.valid`
2. `cap.inline.synthetic`
3. `cap.overflow.positive`
4. `cap.overflow.negative`
5. `empty.zero`
6. `empty.nonzero.positive`
7. `empty.nonzero.negative`

For every stratum in every campaign, both the ratio of build medians and the
median paired ratio must be at most `1.10`. The maximum paired ratio is printed
as a noise diagnostic but is not a retention gate. Checksums must match. A
passing first campaign never excuses a failing independent repeat.

When the heavy lane is available:

```sh
cd /tmp/tungsten-bigarray-cap-empty-candidate
ALLOW_HEAVY=1 CHECK_ONLY=1 \
  benchmarks/runtime_ports/run_big_array_cap_empty_revisit.sh

ALLOW_HEAVY=1 RUNS=10 CAMPAIGNS=2 GATE=1.10 \
  benchmarks/runtime_ports/run_big_array_cap_empty_revisit.sh
```

Integrate each method independently. If only one method passes all of its
strata and repeat, keep the other C handler and reindex from that mixed table.
The production loader is already beyond this isolated cache version, so any
accepted result must be merged as narrow hunks; do not copy the isolated
loader/interpreter/runtime files wholesale over the shared worktree.

## Measured result

Decision: retain both `BigArray#cap` and `BigArray#empty?` source methods. Every
stratum passed `<= 1.10` in both independently rebuilt campaigns.

CHECK_ONLY and both campaign compilers were byte-identical:

```text
f76591e8ff858316c0d897e363ebda5d8d6daa13b080380f58ffb05ad17fc3fb
```

Campaign 1:

| Stratum | Native ns | Source ns | Ratio of medians | Paired median | Pair max | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `cap.inline.valid` | 9.000 | 9.000 | 1.000 | 1.000 | 1.000 | PASS |
| `cap.inline.synthetic` | 9.000 | 9.000 | 1.000 | 1.000 | 1.000 | PASS |
| `cap.overflow.positive` | 27.000 | 26.000 | 0.963 | 0.964 | 1.130 | PASS |
| `cap.overflow.negative` | 26.000 | 24.000 | 0.923 | 0.943 | 1.042 | PASS |
| `empty.zero` | 8.000 | 8.000 | 1.000 | 1.000 | 1.000 | PASS |
| `empty.nonzero.positive` | 8.000 | 8.000 | 1.000 | 1.000 | 1.000 | PASS |
| `empty.nonzero.negative` | 8.000 | 8.000 | 1.000 | 1.000 | 1.000 | PASS |

Campaign 2:

| Stratum | Native ns | Source ns | Ratio of medians | Paired median | Pair max | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `cap.inline.valid` | 9.000 | 9.000 | 1.000 | 1.000 | 1.000 | PASS |
| `cap.inline.synthetic` | 9.000 | 9.000 | 1.000 | 1.000 | 1.000 | PASS |
| `cap.overflow.positive` | 26.000 | 25.000 | 0.962 | 0.961 | 1.040 | PASS |
| `cap.overflow.negative` | 25.500 | 25.500 | 1.000 | 1.000 | 1.120 | PASS |
| `empty.zero` | 8.000 | 8.000 | 1.000 | 1.000 | 1.000 | PASS |
| `empty.nonzero.positive` | 8.000 | 8.000 | 1.000 | 1.000 | 1.000 | PASS |
| `empty.nonzero.negative` | 8.000 | 8.000 | 1.000 | 1.000 | 1.000 | PASS |

The 1.130 positive-overflow maximum in campaign 1 and 1.120
negative-overflow maximum in campaign 2 were individual-pair diagnostics. The
predeclared retention rule gates ratio-of-medians and paired median, both of
which passed comfortably; allocator/scheduler noise in one pair does not
override the ten-pair result.

CHECK_ONLY evidence:

- candidate `cap` WIRE contains a view-field load, signed boundary compares,
  48-bit mask/or immediate boxing, and a cold direct `w_int` call;
- candidate `empty?` WIRE contains one view-field load and raw integer compare,
  with no equality helper or dynamic method call;
- baseline WIRE has its expected shadowed generated `cap` accessor and generic
  inherited `empty?`, while baseline runtime retains the native IC handlers;
- release/LTO baseline and candidate outputs matched for every signed-i64 cap
  boundary, exact Int/BigInt/Bool representation, zero and positive/negative
  nonzero sizes, surplus arguments, trailing-block surfaces, view identity,
  and receiver-header stability;
- the `new`, `view`, `subview`, and `view_range` no-`use` factory programs each
  autoloaded independently and passed;
- the candidate tree walker passed immediate/BigInt boundaries, zero/nonzero
  Bool results, and surplus-argument behavior.
