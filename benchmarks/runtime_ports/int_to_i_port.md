# Integer#to_i public source-port trial — retained

The candidate added an exact `Integer#to_i { self }` source body and removed
the native identity handler from the real Integer IC table. Baseline and
candidate binaries were compiled from separate current-source roots and linked
against their corresponding runtimes; this measured the public native IC
against the public source method rather than a benchmark-only C wrapper.

Exact checks covered 16 signed-i48 values including both boundaries, identical
WValue bits, one and three surplus arguments, source autoload, receiver
stability, and the established trailing-block passthrough behavior. Both
paths produced identical values and checksums.

An initial 10-pair wall-clock campaign was badly scheduler-noisy and landed at
parity: 0.995 varying / 1.011 inferred. The deciding campaign used a C bridge
to `CLOCK_THREAD_CPUTIME_ID`, 15 alternating pairs, and 50,000,000 calls per
leg:

| path | paired-ratio median | aggregate ratio | wins |
|---|---:|---:|---:|
| varying receiver from Array | 0.98917 | 0.99431 | 9/15 |
| compiler-inferred Integer | 0.98103 | 0.98578 | 10/15 |

The source identity was modestly faster, but neither important path cleared the
historical 0.97 migration threshold, so that campaign initially left production
on the C IC.

## Relaxed 10% revisit (2026-07-15)

The user-selected migration budget is now source/C <= 1.10. Two fresh,
independent campaigns each used 12 alternating baseline/candidate process pairs,
50,000,000 calls per stratum, and `CLOCK_THREAD_CPUTIME_ID` so concurrent
search processes could not charge scheduler delay to one implementation.

| campaign | path | C ns/call | source ns/call | paired-ratio median |
|---|---|---:|---:|---:|
| 1 | varying receiver from Array | 9.4604 | 9.4225 | 0.9974 |
| 1 | compiler-inferred Integer | 4.0055 | 3.9903 | 0.9974 |
| 2 | varying receiver from Array | 9.6222 | 9.4711 | 0.9806 |
| 2 | compiler-inferred Integer | 4.1531 | 3.9442 | 0.9682 |

Across all 24 pairs, median paired ratios were 0.9951 for varying receivers and
0.9840 for inferred Integers. The exact source body is simply `self`; emitted
LLVM is `ret i64 %__self`, and the handler-free binary is 32 bytes smaller.
Using `$value` instead is incorrect at the negative signed-i48 boundary.

All 16 signed-i48 identities, one/many surplus arguments, trailing-block
passthrough, no-use autoload, interpreted identity, and the reindexed `to_f`,
`chr`, `gcd`, `times`, `sqrt`, `each`, prime-family, and `lcm` native rows pass.
The compiler entry point explicitly imports `core/integer` for first-generation
bootstrap safety: an older compiler does not yet know the new `to_i` autoload
trigger, but must still be able to build and link the first handler-free
compiler. The source implementation and C-IC removal are retained.
