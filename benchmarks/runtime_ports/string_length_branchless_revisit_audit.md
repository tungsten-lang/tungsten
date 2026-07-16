# String/Symbol `size` / `length` branchless-direct revisit

Status: **checked `size`/`length` source bodies and their prerequisite public
identity repair are validated and retained**. The branchless body also passed
the 1.10 gate, but was not selected because it showed no repeatable speed win
and couples correctness to the current uint32 length ABI.

Matched detached roots (all `f62869b`):

- native baseline: `/tmp/tungsten-string-length-revisit-baseline`
- checked direct candidate: `/tmp/tungsten-string-length-revisit-direct`
- branchless direct candidate and this evidence package:
  `/tmp/tungsten-string-length-revisit-branchless`
- public-class old control: `/tmp/tungsten-string-class-identity-old`

The checked body was merged surgically into `/Users/erik/tungsten`; main's
newer Array, Mmap, numeric, loader, and interpreter work was preserved. The
matched-root package remains the causal A/B evidence.

## Preserved observable behavior

The native `w_ic_string_length` occupies the shared 0xF9 String/Symbol IC
table under both `size` and `length`. It ignores surplus positional
arguments, obtains a stored UTF-8 byte count through `w_str_data`, and returns
`w_int((int64_t)len)`. This is byte length, not Unicode scalar count.
Embedded NUL bytes count normally.

String and Symbol differ only in WValue bit zero and otherwise share the same
inline/slab/heap representation. Rope dispatch canonicalizes to String before
the source method runs; the canonical `w_string_byte_length` helper also
defensively flattens a rope before calling `w_str_data`.

The neutral public fixture inherited from the representation-aware study pins
17 cases: empty/nonempty inline Strings, multibyte UTF-8, inline NUL, slab
ASCII/UTF-8, heap/NUL-heap, fresh and warmed ropes, and the corresponding
inline/slab/heap/NUL/UTF-8 Symbols including a Symbol made from a flattened
rope. It expects `"é".size == 2`, `"ééé".size == 6`, and preserves all 80
bytes in the NUL-bearing heap fixture.

The tree-walker fixture separately calls `to_sym` first on a fresh rope and
then checks both its length and full content. This caught an independent seam:
the direct interpreter bridge previously passed the generic rope pointer to
`w_str_to_sym`, whose implementation only sets bit zero. All three matched
interpreter overlays now call `w_rope_flatten` first; that helper is identity
for ordinary String/Symbol values.

Both source candidates intentionally keep independent `size` and `length`
bodies. Calling one from the other would add another public lookup to one
benchmark leg. Both rely on the runtime's name-only fallback to preserve the
old wrapper's ignored surplus arguments. Blocks retain the existing compiled
implicit-result iteration behavior and are ignored by the tree walker, as they
were at the native/interpreter boundary.

## Candidate A: canonical helper plus checked boxing

The direct reference candidate calls
`ccall_nobox("w_string_byte_length", self)`, performs the complete signed-i48
range check, directly tags a fitting result, and retains cold
`ccall("w_int", n)` for a hypothetical wider value. It remains correct if the
stored-length ABI later widens.

## Candidate B: canonical helper plus branchless exact tagging

The new candidate calls the **same canonical helper**, then returns:

```tungsten
tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
wvalue_from_bits((tag | n) ## i64)
```

There is no range branch, payload mask, or cold `w_int` edge.

This is exact under the current runtime contract:

| representation reaching the helper | stored length source | maximum |
|---|---|---:|
| inline modes 0..5 | WValue bits 1..3 | 5 |
| slab mode 6 | primary slot byte 1 | 255 (constructors use at most 61) |
| heap mode 7 | `WString.len` | 2^32-1 |
| rope | flatten, then one of the above; `WRope.total_len` is `uint32_t` | 2^32-1 |

Therefore `n` is in `[0, 2^32-1]`, wholly inside the nonnegative signed-i48
payload range `[0, 2^47-1]`. OR-ing it into the `0xFFFA` Integer tag cannot
alter tag bits, and no sign-extension or mask is needed. It produces the same
immediate WValue that `w_int(n)` produces on the native path.

The static runner pins all premises: `WString.len` and
`WRope.total_len` must remain `uint32_t`, slab reads must still source
`slot[1]`, and the canonical helper must still return the stored `len` as
`int64_t`. It also requires the branchless and checked roots to be byte-for-
byte identical in the interpreter, loader, compiler anchor, and runtime; only
the Tungsten boxing bodies may differ.

### Deliberate caveat

The optimization is ABI-coupled. If any observable stored length becomes
wider than signed i48, this candidate must gain a checked fallback or be
discarded. The static gate is designed to fail on the obvious width changes,
but a new representation or helper semantic also requires revisiting this
proof. The checked candidate does not carry that limitation.

Some existing constructors cast an incoming `size_t` to the uint32 header.
For an impractical input above 4 GiB, the native wrapper already reports the
stored/truncated header after `w_str_data`; the branchless candidate matches
that current observable result. This package does not claim those oversized
constructors are otherwise safe.

## Shared migration mechanics

Both candidates remove only `w_ic_string_length` and its two IC rows. The
runner parses the remaining 36 handlers and all contiguous name assignments
0..35 exactly.

Because String/Symbol values can arrive through parameters, argv/native calls,
or rope-producing expressions, both candidates retain the sound one-shot
loader gate for call names `size` and `length`, plus the self-host's explicit
`core/string_native` anchor. The one-shot work remains wholly inside
`@string_length_unresolved`, so the explicit self-host import makes its
steady-state per-call cost zero.

One post-loader seam also needs recognition. `lower_method_call` rewrites
`collection.map/select/reject/count(:name)` into a per-element call whose name
comes from the literal Symbol. That effective `size`/`length` call is absent
from the source AST the loader sees. The candidate loader mirrors the lowerer's
full predicate exactly: one literal Symbol argument, no block, the same four
iterator names, and receiver kind in
`range/array/var/call/map/calc`. Pipeline syntax is already represented by a
Call in `Map.func` and is visited normally; the lowering symbol-to-proc branch
is the only data-derived method-name synthesis after the loader walk. The cache
epoch is bumped to `loader-ast-v11`.

Eight isolated no-use programs exercise map/select/reject/count × size/length.
Each obtains a one-string WArray from the benchmark-only
`w_strlen_one_string_array` C helper, whose body uses `w_array_new_empty` and
`w_array_push`. The custom helper name is deliberately absent from the
loader's exact native-result map; directly spelling `w_array_new_empty` would
autoload Array in the integrated compiler and mask this regression. There is
no array literal, import, or explicit target call. Candidate WIRE must contain
both String length source targets, baseline WIRE must contain neither, and no
variant may contain an Array source body. Four earlier native/rope/Symbol
fixtures remain, for twelve no-use gates in total.

The load-impact probes measure the conservative false-positive class load in
non-String user code. The control program must emit no String length
definitions; each candidate size/length probe must emit exactly two.

The tree walker routes Symbol `size`/`length` through the shared String
class and canonicalizes a rope before entering a method declared by String.
The baseline parity overlay uses the canonical native helper directly. Its
direct `to_sym` path, and both candidate paths, flatten before setting the
Symbol bit. The branchless candidate needs no additional length interpreter
bridge beyond `w_string_byte_length`.

### Public class identity repair carried by this package

String and Symbol intentionally share method-dispatch key 0xF9. The old
`w_class_of` also treated that slot as public type identity, so registering the
source String class made `:symbol.class` return String while `type` and
`class_name` still returned Symbol.

The retained repair separates public identity from the existing method-facade
table. A 512-entry `WPublicClassEntry` cache uses the normal dispatch key plus
bit zero as its index; that one extra bit distinguishes String from Symbol at
0xF9 without adding a tag branch to every query. Each entry stores both the
final public WValue (including real `nil`) and a resolved byte, so cached nil is
not confused with the zero-initialized unresolved state. Class creation
refreshes exact String/Symbol entries. Generic type-class registration does
not publish its source facade: because several representation keys admit
wrong-name aliases, it invalidates both payload-parity pages and lets the next
cold miss require that a facade name agree with `__w_type`. That miss then
caches the matching class, a new stub, or nil. The hot path is one resolved
test and one value return; normal method dispatch still uses `g_type_class`
unchanged.

The same distinction applies to three opaque synchronization handles:

| handle | internal dispatch key | public `type` / `class_name` | historical `.class` |
|---|---:|---|---|
| Atomic | 0x01 | `Unknown` | `nil` unless `Unknown` is explicitly declared |
| Thread | 0x81 | `Unknown` | `nil` unless `Unknown` is explicitly declared |
| Channel | 0x84 | `Unknown` | `nil` unless `Unknown` is explicitly declared |

Those keys are method facades, not public class identity. Facade registration
therefore does not populate their public-cache entries. The first query caches
nil; a later explicit `+ Unknown` declaration replaces those nil entries with
that exact class, while no Unknown class is lazily synthesized.

The compiled regression registers benchmark-only source facades under all
three real keys *after* observing each handle. It requires `.class` to remain
the same `nil`, `type`/`class_name` to remain Unknown, `is_a?(facade)` to remain
false, and a facade probe method to remain dispatchable. A separate delayed
`Unknown` declaration pins the explicit-class edge before and after facade
registration. The String/Symbol portion forces source String registration and
checks exact `type`, `class_name`, benchmark-local class labels, stable class
bits, `is_a?` with name/class targets, and distinct String/Symbol classes.

The tree-walker regression covers exact String/Symbol identity and stable
interpreter class objects. It deliberately does not claim native
Atomic/Thread/Channel coverage: interpreted Thread construction is not the
compiled native-handle factory. The synchronization assertions are compiled
runtime gates.

### Known follow-up outside this isolated candidate

The same lowering symbol-to-proc rewrite can hide effective `empty?`/`to_s`
and other source-migrated class method names from their existing loader gates.
That broader issue is not created by this candidate. A future loader cleanup
should compute one effective generated method name and feed every applicable
autoload gate, instead of continuing to duplicate per-class patches.

## Prepared runner and gates

`run_string_length_branchless_revisit.sh` statically verifies matched HEADs,
the exact IC removal/reindex, direct checked body, branchless body and ABI
premises, loader epoch/gate, interpreter routes, compiler bootstrap anchor,
and every inherited fixture. This safe command performs no heavy work:

```sh
/tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_string_length_branchless_revisit.sh
```

When the exclusive build lane is available, correctness-only validation is:

```sh
STATIC_ONLY=0 CHECK_ONLY=1 \
  BOOTSTRAP_COMPILER=/path/to/one/compiler \
  /tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_string_length_branchless_revisit.sh
```

That fresh-build path uses one bootstrap for all three matched roots, copies
all workload/spec inputs to a neutral temporary directory, and then checks:

- intended direct and branchless WIRE bodies;
- one true public cached-zero dispatch and two raw thread clocks per timed body;
- all 17 semantic representations;
- fixed compiled public identity in all three roots, including the delayed
  opaque facades and explicit Unknown declaration;
- twelve no-use autoload programs, including all eight generated-name seams;
- control/size/length loader impact;
- baseline/direct/branchless tree-walker parity, including fresh-rope `to_sym`.

Only after those gates pass should two independently rebuilt campaigns run:

```sh
STATIC_ONLY=0 CHECK_ONLY=0 RUNS=10 \
  BOOTSTRAP_COMPILER=/path/to/one/compiler \
  /tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_string_length_branchless_revisit.sh

STATIC_ONLY=0 CHECK_ONLY=0 REPEAT=1 RUNS=10 \
  BOOTSTRAP_COMPILER=/path/to/one/compiler \
  /tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_string_length_branchless_revisit.sh
```

Each sample uses balanced
`baseline/direct/branchless/branchless/direct/baseline` ordering or its
reverse and `CLOCK_THREAD_CPUTIME_ID`. String uses
inline/slab/heap/warmed-rope/NUL strata; Symbol uses inline/slab/heap/NUL.
String `size`, String `length`, Symbol `size`, and Symbol `length` each
receive independent <=1.10 decisions. Retention still requires every stratum
to pass in both campaigns.

Public `.class` performance has its own runner and never enters the
size/length summaries or retention decisions. Its safe static-only invocation
is:

```sh
/tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_public_class_identity.sh
```

The correctness/IR lane is:

```sh
STATIC_ONLY=0 CHECK_ONLY=1 \
  BOOTSTRAP_COMPILER=/path/to/one/compiler \
  /tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_public_class_identity.sh
```

It builds only one fixed frontend compiler, then uses that exact executable
and the same neutral source to link once from the old runtime root and once
from the fixed baseline root. Target binaries use `--release --no-lto`, keeping
`w_class_of` external without adding profiling prologue overhead. The native
runtime archive is keyed and freshness-checked by canonical root; an untimed
semantic probe additionally proves which implementation each final binary
linked. Before any build, the runner hash-pins the complete class-cache and
public-lookup regions, replaces them with the old counterparts, and requires
the normalized runtime to equal the old runtime byte-for-byte, so an unrelated
runtime edit cannot muddy the timing.
The lane requires:

- fixed all-types and explicit-Unknown regressions to pass;
- the old runtime to fail at the exact Symbol, Atomic, Thread, Channel, and
  declared-Unknown assertions;
- old/fixed timer WIRE and extracted LLVM bodies to be identical;
- one setup and one loop `w_class_of` call, two raw thread clocks, and one raw
  xor/or accumulator, with both WIRE and final LLVM proving the order is setup
  call → start clock → consumed loop call → stop clock and with no equality
  dispatch or timed conditional;
- exact probe results: String→String/String, Symbol→String/Symbol, and each
  opaque handle→its old facade/nil;
- different final binary hashes, proving the selected runtime roots mattered.

The exclusive timing campaigns are:

```sh
STATIC_ONLY=0 CHECK_ONLY=0 RUNS=10 \
  BOOTSTRAP_COMPILER=/path/to/one/compiler \
  /tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_public_class_identity.sh

STATIC_ONLY=0 CHECK_ONLY=0 REPEAT=1 RUNS=10 \
  BOOTSTRAP_COMPILER=/path/to/one/compiler \
  /tmp/tungsten-string-length-revisit-branchless/benchmarks/runtime_ports/run_public_class_identity.sh
```

Each sample is old/fixed/fixed/old or its reverse under
`CLOCK_THREAD_CPUTIME_ID`. String, Symbol, Atomic, Thread, and Channel receive
independent fixed/old median-ratio decisions at <=1.10. The checksum is a
full-pointer xor normalized against each process's pre-clock result; it must
remain exactly zero, so every returned class value is live without adding an
equality call, branch, boxed increment, or Array indexing to the measured loop.

Two earlier correct implementations were rejected before retention. An early
cached-Symbol path plus three explicit opaque-key branches measured 1.312 for
String and 1.126 for Thread in its first campaign. A first table design stored
the public WValue directly but used zero as the unresolved sentinel; because
`W_NIL` is also zero, opaque handles missed the cache on every iteration and
measured roughly 14--15x native (String was also 1.120). Neither version is
retained.

The resolved-entry cache passed two independently linked campaigns; its final
post-alias-invalidation rerun measured String/Symbol at parity and the opaque
handles faster (worst fixed/old median 1.009).

| stratum | campaign 1 fixed/old | campaign 2 fixed/old | decision |
|---|---:|---:|---|
| String `.class` | 0.977 | 1.004 | retain |
| Symbol `.class` | 0.983 | 1.009 | retain |
| Atomic `.class` | 0.926 | 0.939 | retain |
| Thread `.class` | 0.881 | 0.894 | retain |
| Channel `.class` | 0.870 | 0.886 | retain |

Every correctness, causal-control, linked-runtime probe, WIRE/LLVM, checksum,
and <=1.10 performance gate passed. The identity repair is retained.

## Final String/Symbol decision (2026-07-15)

The full correctness lane passed after two tree-walker defects exposed by the
new identity fixture were fixed in every matched root: bare `type(value)` had
discarded its explicit argument, and `Symbol#is_a?` autoloaded the legacy
Symbol scaffold before reaching the exact identity helper. The latter exposed
a separate lexer ambiguity where `<=>/1 to_s` treated the following `t` as the
space-separated tonne unit; the scoped identity bypass is retained and the
syntax issue is recorded separately.

Both eight-sample campaigns independently rebuilt the three compilers and
passed every representation, no-use autoload, generated Symbol-to-proc,
identity, WIRE/LLVM, and tree-walker gate. Worst per-method paired medians were:

| campaign | checked worst/C | branchless worst/C | decision |
|---|---:|---:|---|
| first | 1.054 | 1.056 | both pass |
| repeat | 1.044 | 1.062 | both pass |

The checked source was retained. It uses the same canonical raw byte-length
helper, directly tags the signed-i48 common arm, and preserves `w_int` as the
cold widening fallback. The branchless experiment is rejected only as the
production choice: it is exact under today's `uint32_t` String/Rope headers,
but its smaller WIRE did not translate into a material timing win.

## Integrated main-tree verification

The production merge preserved main's later migrations: the loader epoch is
`loader-ast-v18`, the final String IC table contains 35 contiguous retained
handlers (`0..34`), and the previously migrated `empty?` source route remains
intact. The integrated compiler passed the 17-case public workload, expanded
public-identity suite, all twelve no-use fixtures (each with two String source
definitions and no masking Array body), compiled/interpreted
`string_native_spec`, and tree-walker parity.

Two subsequent self-host generations emitted byte-identical 13,772,879-byte
LLVM modules with SHA-256
`54ea5a49d01a499f50d2357c64203c7eb445c46c86e77ef1e48c455934c17f29`.
The full spec suite then passed every migration/compiler regression and failed
only the same five established generic-numeric controls: `complex_spec`,
`hypercomplex_mul_spec`, `matrix_spec`, `operator_overload_spec`, and
`vector_spec`. During that run, the generic harness was also corrected to link
the BigArray no-use reference helper, and the Float identity fixture stopped
using ordinary equality for NaN before its exact-bit assertion.
