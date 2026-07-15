# Integer#to_i public source-port trial — rejected

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

The source identity is modestly faster, but neither important path clears the
strict 0.97 migration threshold. Production remains on the C IC. The isolated
roots, public benchmark, thread clock, raw observations, and candidate diff
remain under `/tmp/tungsten-int-to-i`.
