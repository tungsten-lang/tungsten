# UUID#byte source-port trial — rejected

## Decision

Do not move `UUID#byte` from its C storage helper into `core/uuid.w` yet.
The implementation is exact and consistently a little faster, but neither of
the two long thread-CPU campaigns cleared the required `candidate/C <= 0.97`
hot-path gate. Production was not modified.

## Candidate

The isolated implementation gives UUID its actual `u8[16]` view and replaces
`ccall("w_uuid_byte", self, index)` with a `w_to_i64` conversion, one
`(index & -16) != 0` bounds test, a direct inline byte load, and inline Int
tagging. `w_to_i64` intentionally preserves Int/BigInt acceptance,
non-integer failure, and the existing low-64-bit behavior of very large
BigInts.

The compiled hot body contains one `w_to_i64` call, one mask/range branch, one
`i8` load, and inline `0xFFFA` tagging. It contains no `w_uuid_byte` call. The
interpreter still crosses the C storage boundary because it has no raw heap
view; its narrow `$bytes[index]` bridge calls the existing helper.

## Optimization sequence

1. V1: direct view load after `w_to_i64`, with separate negative and upper
   bounds.
2. V2: decode immediate Ints in source, then fall back to `w_to_i64`.
3. V3: combine the immediate-Int tag and 0..15 range check into one mask.
4. V4: keep the smaller V1 conversion path but combine both signed bounds into
   `(raw_index & -16) != 0`.
5. V5: invert V3 so the valid immediate-Int edge falls through. It did not
   improve the smoke median.

The extra immediate-Int branch/code size was not worthwhile at this dispatch
scale. V1/V4 were the best compact forms, but still missed the strict gate.

## Exactness evidence

- Compiled correctness covered all 16 bytes of
  `00112233-4455-6677-8899-aabbccddeeff`, negative and upper bounds,
  positive/negative BigInt bounds, `2^64 -> low i64 zero`, surplus arguments,
  version/variant consumers, and receiver stability.
- No-explicit-use compiled autoload passed.
- A rebuilt candidate compiler's tree walk passed the same byte, bounds,
  BigInt, surplus-argument, receiver-stability, and autoload checks.
- C and source Float-index subprocesses both exited 1 with
  `runtime error: expected int, got numeric`.
- The benchmark used distinct C, V1, and public candidate selectors/call sites
  so inline caches could not contaminate one another.

Isolated artifacts remain under `/tmp/tungsten-uuid-byte-candidate`, including
the benchmark, clock bridge, runner, compiled/interpreter specs, raw results,
and exact candidate patch.

## Performance evidence

Timing used per-thread CPU time and ABBA ordering. Each campaign had 15 pairs,
30,000,000 valid-index calls per leg, and 5,000,000 BigInt-fallback calls per
fallback leg. The decision uses the median of paired ratios.

| campaign/path | C median ns | candidate median ns | paired ratio | result |
|---|---:|---:|---:|---|
| A, public valid indexes | 14.1174 | 13.8317 | 0.9814 | skip |
| A, compact V1 | 14.1174 | 13.7191 | 0.9769 | skip |
| A, BigInt fallback | 8.0256 | 7.7316 | 0.9673 | no regression |
| B, public valid indexes | 13.9674 | 13.7737 | 0.9856 | skip |
| B, compact V1 | 13.9674 | 13.6134 | 0.9779 | skip |
| B, BigInt fallback | 8.0859 | 7.6526 | 0.9600 | no regression |

Both independent hot campaigns miss 0.97; the modest 1.4–2.3% speedup is not
enough to justify replacing the native IC.
