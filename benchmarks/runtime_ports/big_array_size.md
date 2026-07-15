# BigArray `size` static migration preparation

Status: **rejected after correctness and two balanced timing campaigns**.
Production `core/big_array.w`, `runtime/runtime.c`, and the installed IC table
remain untouched.

## Audit cut

The current ledger already covers the plausible Integer/BigInt, Float,
String, StringBuffer, Hash-size, Array-leaf, Array-join, Array-uniq, and
Array-compact/dup ports. The remaining IC groups were narrowed as follows:

- Array `count`/search and typed math retain SIMD/threaded kernels; replacing
  them with source loops would knowingly discard the important fast strata.
- Array `take`/`drop`/`reverse`/`copy` can be translated, but their observable
  output capacity depends on `w_array_new_empty`'s recycle-pool state. Exact
  presizing is therefore not representation-equivalent, leaving no clear
  source accelerator beyond the C loop.
- Hash `keys`/`values`/`merge!` need direct sparse-table traversal; source
  `each` adds closure dispatch and cannot see empty/tombstone slots directly.
- String and Regex candidates are byte-scanning/libc/regex-engine operations,
  not good source migrations without a new primitive that merely relocates C.
- Thread, Channel, Socket, and Mmap mutation/I/O methods are inherently native.
  Mmap `size` looks like a leaf, but `Mmap` currently lacks a compiler
  `type_dispatch_key` entry and a source view layout, so it is a wider plumbing
  change than BigArray.
- SmallArray leaves are narrow-field loads with no 64-bit checked-boxing call;
  prior Array/Hash/StringBuffer leaf results make a 3% win unlikely.

That leaves BigArray `size` and `cap` as the only uncovered leaves with a new
optimization lever. `size` is selected first because it is the common loop and
view-consumer query, and its C path contains the extra `w_big_array_size`
layer; `cap` can reuse this design only if `size` clears both gates.

## Why this candidate

`BigArray#size` is the best uncovered leaf after cross-checking the current
runtime-port ledger. The C route is
`w_ic_big_array_size -> w_big_array_size -> w_int(header.size)`. BigArray
already has an exact source view of `WBigArray`, and its source methods are
registered on dispatch key `0x92`, so no new runtime bridge or class plumbing
is required.

The literal v1 source port performs the signed 64-bit field load and uses the
normal raw-i64 return boundary. V2 then makes the common path smaller: it
constructs the exact `0xFFFA` i48 WValue in source and calls `w_int` only when
the signed value lies outside i48. This is materially different from the
already-rejected Array/Hash leaf loads, which had no out-of-line 64-bit boxing
call to remove.

## Semantic traps pinned by the harness

- `WBigArray` has an implicit generic-object type byte. The existing source
  layout intentionally starts at C offset 1; `$size` must therefore land at C
  offset 16 through the compiler's implicit-byte adjustment.
- The source layout spells `size` as `u64`, while C stores `int64_t`. V1 and v2
  immediately ascribe the load to `i64`; otherwise a return would use `w_u64`
  and would disagree with the C handler for a negative raw header.
- Values inside i48 must have identical immediate bits. Both positive and
  negative i64 overflow must be canonical one-limb BigInts with the same sign
  and value as `w_int`.
- Ordinary constructors maintain nonnegative size, but the exported low-level
  `w_big_array_view` bridge can manufacture any signed length. Benchmark-only
  fixtures therefore cover negative values and both signed endpoints rather
  than relying only on the high-level invariant.
- The installed native handler ignores extra positional arguments. A trailing
  block on the no-block method follows the compiler's call-site surface and
  yields nil for the zero-size fixture; correctness checks pin both behaviors.
- `size` remains readable and unchanged; it has no closed/mutation state.
- The unique C wrapper has ordinary source arity, whereas the real installed IC
  uses the native cached-dispatch branch. Even a winning unique-name result is
  insufficient: a production-shaped public trial must remove only the
  BigArray `size` IC entry and compare the real public call.

## Gate and result

`run_big_array_size.sh` first checks WIRE shape and exact C/v1/v2/public
behavior. Its balanced C/W/W/C timing has two independently gated strata:

1. `inline`: sizes from zero through `2^32` and the positive i48 edge, with no
   allocation in the returned value.
2. `overflow`: positive sizes above i48 through `INT64_MAX`; each one-limb
   BigInt is consumed and freed inside the timed leg so a long run is bounded.

Both strata must have median `W/C <= 0.97`, and an independent rebuild/repeat
must remain below `1.00`. Run v1 first as the literal control, then v2. If v2
wins the unique gate, prepare an isolated root that adds the body to
`core/big_array.w` and removes only `{WN_size, w_ic_big_array_size}` before the
public-dispatch campaign.

The WIRE/release gate passed after two harness-only corrections: raw bit
annotations were moved out of multi-argument calls, and the forbidden-call
regex was narrowed so it did not match the candidate function's own name. All
16 signed-i64 fixtures then matched the C/public results, including exact i48
bits, signed BigInt limb representation, extra arguments, trailing-block
surface, and unchanged receiver headers.

V1's ten balanced samples measured `0.972` for inline/i48 values and `1.048`
for overflow, so the literal source translation was rejected. V2 measured
`1.005` inline and `0.979` overflow; it also failed both-strata retention and
received no repeat or public-method trial. The C `size` IC remains installed.

Static inspection command (does not compile or time):

```sh
STATIC_ONLY=1 benchmarks/runtime_ports/run_big_array_size.sh
```

One language/tooling wish exposed here is a checked machine-integer boxing
intrinsic (semantically `w_int`, but lowered with an inline i48 fast path). It
would avoid hand-writing NaN-box tag constants while preserving the exact
BigInt fallback; this preparation does not change syntax.
