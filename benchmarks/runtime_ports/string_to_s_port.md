# String/Symbol `to_s` C-to-Tungsten port

Status: **retain**. The production-shaped public dispatch is faster in every
representation stratum in two independently linked benchmark rounds.

## Candidate

`String` and `Symbol` share runtime dispatch key `0xF9`; bit 0 is the complete
type distinction. The single source body in `core/string_native.w` is:

```w
-> to_s
  wvalue_from_bits($value & -2)
```

It is identity for inline, slab, and heap Strings and clears exactly the Symbol
marker for inline and slab Symbols. Rope flattening remains in the established
cached-dispatch boundary. The optimized arm64 body is exactly:

```text
and x0, x0, #0xfffffffffffffffe
ret
```

The old `w_ic_string_to_s` wrapper and only its `w_ic_string_table` entry were
removed. The retained String IC entries were shifted without changing their
order. The loader name-gates the small native String class on `to_s` so dynamic
String/Symbol receivers register the shared source method. The tree walker
routes Symbol `to_s` through the same String class and uses a checked,
String-only raw-bit rebox bridge; compiled code still performs a zero-call i64
bit cast.

## Correctness

`string_to_s_ab.w check` compares 48 values across inline/slab/heap/rope and
inline/slab Symbol strata. Every result matches the old C body in content,
runtime type, and exact 64-bit WValue identity. Additional gates passed:

- compiled `spec/core/string_native_spec.w`, including String identity,
  Symbol low-bit clearing, and cached rope flattening;
- compiled and interpreted `spec/interpreter/string_to_s_native_spec.w`
  without an explicit `use`, exercising loader autoload and the tree-walker
  rebox;
- `spec/core/basics_spec.w`, `spec/core/base64_native_spec.w`, and
  `spec/core/thread_string_slab_spec.w`;
- C11 syntax check of `runtime/runtime.c`;
- self-host generations 7 and 8 emitted byte-identical LLVM IR:
  `e0e9d2beb7027c100ef67718394c35107a3c2123db9f823735d582cc7233df1c`.
- seven alternating self-host load+parse pairs had a 0.990 candidate/baseline
  median user-CPU ratio; linked benchmark segment sizes were identical (the
  candidate file itself differed by only 40 bytes).

## Benchmark

The harness uses `CLOCK_THREAD_CPUTIME_ID`, changing receivers, exact checksum
validation on every timed leg, alternating process order, and 5 samples of
20,000,000 calls per stratum. `__c_to_s` and `__w_to_s` provide an in-process
body control; the retention gate is the actual public method compiled from an
unchanged benchmark in the baseline and candidate trees.

Public candidate / public baseline median ratios:

| representation | build 1 | independent build 2 |
|---|---:|---:|
| inline String | 0.9160 | 0.9661 |
| slab String | 0.9244 | 0.9112 |
| heap String | 0.9049 | 0.8824 |
| rope receiver | 0.9221 | 0.9468 |
| inline Symbol | 0.8727 | 0.8444 |
| slab Symbol | 0.8828 | 0.9156 |

Every independent-build median clears the strict `<= 0.97` retention gate.
The near-identical in-process raw-body control (0.967--1.007 in build 2) shows
that the larger public win comes from replacing the vector-builtin IC route
with the arity-zero cached source-method route, not from changing semantics.

Artifacts used for the final repeat:

- baseline: `/tmp/string-to-s-baseline-repeat`
- candidate: `/tmp/string-to-s-candidate-repeat`
- raw samples: `/tmp/string-to-s-repeat-baseline.txt` and
  `/tmp/string-to-s-repeat-candidate.txt`
- fixed-point compilers: `/tmp/tungsten-string-to-s-compiler-gen7` and
  `/tmp/tungsten-string-to-s-compiler-gen8`

The retained source, reference body, correctness strata, and benchmark evidence
live beside this report so future runtime ports can rerun the same gate.
