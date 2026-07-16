# Mmap wrapper source-port revisit

Status: retained. All ten typed-view wrappers passed compiled/interpreted
correctness, exact WIRE/LLVM ABI checks, isolated autoload checks, and two
independently rebuilt 10-sample timing campaigns at
`candidate / native <= 1.10`. The four controls remain native.

Matched roots, both based on `f62869bff0fc22fdc0a3179c82fb5da158d987d6`:

- `/tmp/tungsten-mmap-wrapper-revisit-baseline`
- `/tmp/tungsten-mmap-wrapper-revisit-candidate`

## Static result

| Public method | Source spelling | Representation result | Static decision |
|---|---|---|---|
| `byte_at(index)` | none | receiver, index, and result are boxed, but source dispatch pads a missing argument with nil before the body runs | native / skip: source changes the dedicated `Mmap#byte_at requires 1 argument` fatal diagnostic into the primitive's integer-conversion error |
| `as_u8` | `ccall("__w_mmap_as_typed", self, 8)` | fixed raw element encoding | benchmark candidate |
| `as_u16` | same, `16` | fixed raw element encoding | benchmark candidate |
| `as_u32` | same, `32` | fixed raw element encoding | benchmark candidate |
| `as_u64` | same, `64` | fixed raw element encoding | benchmark candidate |
| `as_i8` | same, `108` | exact historical runtime encoding | benchmark candidate |
| `as_i16` | same, `116` | exact historical runtime encoding | benchmark candidate |
| `as_i32` | same, `32` | intentionally preserves the old handler's value, even though other array constructors have richer signed encodings | benchmark candidate |
| `as_i64` | same, `64` | intentionally preserves the old handler's value | benchmark candidate |
| `as_f32` | same, `-32` | fixed raw element encoding | benchmark candidate |
| `as_f64` | same, `-64` | fixed raw element encoding | benchmark candidate |
| `[]` | none | lower byte primitive itself is safe, but an opaque Mmap can cross a parameter or unknown native-return boundary | native / skip: a sound name gate would load Mmap into essentially every indexed program |
| `close` | none | lower close primitive itself is safe, but opaque receiver autoload has the same provenance problem | native / skip: broad `close` would affect sockets, files, channels, and user classes; exact-producer-only behavior would regress opaque boundaries |
| `view_at` | none | current handler decodes two arguments with unchecked signed-48 payload extraction, accepts only immediate Integer or a fixed Symbol set for `ebits`, and uses fatal errors for invalid type/name before calling a mixed boxed/raw primitive | native / skip: numeric coercion widens behavior; pass-through boxes corrupt the raw ABI; a source decoder would duplicate the IC and still cannot express exact fatal behavior cleanly |

This leaves exactly four native rows in the candidate Mmap IC table, in the
order `close`, `byte_at`, `[]`, `view_at`. The ten typed-view handlers and their
now-unused interned names are absent.

## Raw ABI boundary

The native `as_*` handlers used a C `int` parameter while generic Tungsten
`ccall` declarations and arguments are LLVM i64. Relying on the target ABI to
read only a low subregister would be an unsafe source port even for constants.
The isolated candidate therefore changes only the lower primitive signature
from

```c
WValue __w_mmap_as_typed(WValue mmap, int element_bits)
```

to

```c
WValue __w_mmap_as_typed(WValue mmap, int64_t element_bits)
```

and declares it explicitly as `(i64, i64) -> i64` in the emitter. The value is
still narrowed only where the implementation already computes its internal
`int abs_bits`; public behavior is unchanged. The heavy gate requires each
source body to contain one direct call, no dynamic call or integer nanobox, and
the exact second LLVM argument `8,16,32,64,108,116,32,64,-32,-64`.

## Language pressure points (no syntax changed)

- Typed foreign declarations such as `(WValue, i64) -> WValue` would make a
  mixed boxed/raw boundary explicit in Tungsten instead of splitting the
  contract across a C prototype, emitter declaration, and interpreter bridge.
- A source-visible missing-argument sentinel or argument-count query would let
  `byte_at` preserve the native distinction between omission and explicit nil.
- Return/receiver type metadata for native calls would let the loader prove
  that an opaque value is an Mmap or BigArray, avoiding broad call-name
  heuristics for common methods such as `[]`, `close`, and `size`.

## Autoload design

The candidate keeps the already-retained `size` trigger separate and adds one
one-shot ten-name `as_*` trigger which schedules both Mmap and BigArray.

The second class is necessary because the returned view is opaque native data
and BigArray's `size`, `cap`, and `empty?` leaves now live in source. It is
scheduled from the public `as_*` call, not by treating dormant
`__w_mmap_as_typed` calls inside `core/mmap.w` as factories. The latter design
would make any unrelated Mmap load pull BigArray/Enumerable even when no typed
view is used.

There is deliberately no `byte_at`, `[]`, `close`, or `view_at` call-name
trigger. Independent no-import programs using an unknown C Mmap factory and
only those methods must continue through the retained native rows without any
`__w_Mmap_*` source function in WIRE. The heavy runner records fresh compile
wall time and binary size for all four controls, making future accidental
autoload expansion visible rather than merely asserting it in prose.

Exact `File.mmap` and `ccall("__w_file_mmap", ...)` producer triggers remain.
Independent no-use programs also cover unknown native factories for every
individual `as_*` spelling, every retained native control, and the opaque
BigArray result.
The loader cache epoch advances from `loader-ast-v16` to `loader-ast-v17`
because the loaded AST closure changes.

## Correctness plan

The common C fixture owns a real anonymous read-only mapping with deterministic
64-byte content. The same public driver is compiled against both roots and
checks:

- `byte_at` and retained `[]` at first/interior/last indices;
- out-of-bounds exception parity;
- exact fatal diagnostics for a missing `byte_at` argument and explicit nil;
  these remain distinct because `byte_at` stays native;
- exact BigArray encoding, length, header signature, and borrowed data pointer
  behavior for all ten typed views;
- one and three ignored surplus arguments for every candidate;
- representative Integer-return and BigArray-return trailing blocks;
- closed-map errors for byte and typed-view access;
- idempotent nil-returning retained `close`;
- Symbol/immediate/surplus behavior through retained `view_at`;
- source-interpreter behavior for every candidate and all four native
  controls;
- exact File producer, exact low-level producer, unknown C producer, ten
  independently generated typed-name, BigArray-result, byte-only,
  subscript-only, close-only, and view-at-only no-use programs.

Fresh candidate WIRE and LLVM are mandatory before execution. The candidate
Mmap primitive interpreter bridge converts only the fixed source `as_*`
constant from the tree walker's boxed Integer model to the raw i64 C ABI.

## Timing result

Each of the ten `as_*` candidates is a separate selector and separate gate. It
constructs a view, then an identical C consumer reads its header and releases
only the borrowed view header outside the public call. The consumer returns a
raw i64 checksum, so boxed arithmetic cannot dilute a dispatch regression.
Fresh WIRE showed exactly one public method call per timed loop, the raw
consumer call, and no boxed `w_add` checksum path in either root.

The fixture and cleanup are outside measured intervals. Timing uses per-thread
CPU nanoseconds, identical checksums, alternating adjacent baseline/candidate
order, 10 samples, and two campaigns. Each sample uses 10,000,000 public calls;
the initial 1,000,000-call trial was discarded because its duration was too
short and because an unrelated Decimal-to-string expression corrupted the
reported derived rate. The retained runner emits only raw integer elapsed time
and checksum, then computes ns/call in awk. Each campaign rebuilds a baseline
compiler, candidate compiler, baseline release/LTO binary, and candidate
release/LTO binary from fresh caches. A method is eligible only if both its
ratio of medians and median paired ratio are at most `1.10` in both campaigns.
All ten passed independently.

| Method | Campaign 1 native/source ns | C1 median ratio / paired median | Campaign 2 native/source ns | C2 median ratio / paired median | Decision |
|---|---:|---:|---:|---:|---|
| `as_u8` | 20.665 / 20.578 | 0.996 / 1.005 | 20.706 / 20.317 | 0.981 / 0.981 | retain |
| `as_u16` | 20.546 / 20.062 | 0.976 / 0.978 | 20.213 / 20.267 | 1.003 / 1.014 | retain |
| `as_u32` | 20.776 / 21.975 | 1.058 / 1.030 | 20.646 / 20.493 | 0.993 / 1.004 | retain |
| `as_u64` | 20.913 / 20.523 | 0.981 / 0.989 | 20.092 / 21.012 | 1.046 / 1.038 | retain |
| `as_i8` | 19.695 / 20.816 | 1.057 / 1.039 | 20.386 / 19.505 | 0.957 / 0.957 | retain |
| `as_i16` | 19.968 / 20.924 | 1.048 / 0.988 | 20.872 / 20.454 | 0.980 / 0.989 | retain |
| `as_i32` | 20.065 / 20.284 | 1.011 / 1.023 | 19.858 / 19.915 | 1.003 / 0.980 | retain |
| `as_i64` | 20.898 / 20.117 | 0.963 / 1.000 | 19.558 / 20.851 | 1.066 / 1.022 | retain |
| `as_f32` | 20.109 / 20.241 | 1.007 / 0.976 | 20.513 / 20.704 | 1.009 / 0.999 | retain |
| `as_f64` | 20.164 / 20.844 | 1.034 / 1.020 | 19.952 / 21.611 | 1.083 / 1.050 | retain |

The worst retained ratio of medians was 1.083 (`as_f64`, campaign 2); the
worst paired median was 1.050. Individual pair maxima are recorded by the
runner as noise diagnostics but are not gate metrics.

The four retained-native no-use controls also stayed neutral in campaign 1:
candidate compile wall times were 0.976x (`byte_at`), 0.986x (`[]`), 1.000x
(`close`), and 0.995x (`view_at`) versus baseline, and each candidate binary
was 552--560 bytes smaller.

## Artifacts

- `benchmarks/runtime_ports/mmap_wrapper_revisit_public.w`
- `benchmarks/runtime_ports/mmap_wrapper_revisit_ref.c`
- `benchmarks/runtime_ports/run_mmap_wrapper_revisit.sh`
- `spec/compiler/mmap_wrapper_no_use_{file,native,factory,byte_at,idx,close,view_at}_spec.w`
- `spec/compiler/mmap_wrapper_bigarray_result_autoload_spec.w`
- `spec/compiler/mmap_wrapper_no_use_typed_template.w.in`
- `spec/interpreter/mmap_wrapper_revisit_spec.w`

Static command:

```sh
ALLOW_HEAVY=0 benchmarks/runtime_ports/run_mmap_wrapper_revisit.sh
```

Retained heavy command:

```sh
ALLOW_HEAVY=1 RUNS=10 CAMPAIGNS=2 \
  benchmarks/runtime_ports/run_mmap_wrapper_revisit.sh
```
