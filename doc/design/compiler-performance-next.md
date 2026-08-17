# Compiler performance: next tranches

This branch evaluates ten compiler-throughput changes independently. Each
tranche must preserve generated LLVM for representative inputs, retain exact
self-hosting fixed point where it applies, pass focused checks, and earn its
place with matched `--release --native --fast --no-debug` measurements. A
negative or noise-flat experiment is documented and reverted rather than
silently accumulated.

## Target probe cache

Target layout, function attributes, and native Arm CPU flags previously
started three short-lived compiler subprocesses for every independent compile.
They now use one exact-key process cache followed by a checksummed, atomic disk
record in the compiler cache directory. Disk entries expire on the next local
civil day. `TUNGSTEN_TARGET_CACHE=0` disables both levels;
`TUNGSTEN_TARGET_DISK_CACHE=0` retains only process memoization.

The key includes the selected C compiler, cross target, resolved architecture
arguments, and the corresponding target environment. A configuration change
therefore misses immediately; the one-day lifetime bounds changes to an
auto-selected compiler without adding a compiler-version subprocess on every
lookup. Malformed or incomplete records fail closed.

Eight alternating full self-compile pairs were noise-flat end to end: median
wall time was 3.9172 s disabled and 3.9148 s warm (-0.06%), while the target
detection stage itself fell from a 46 ms median to 0 ms. On the intended
many-process workload, ten alternating blocks of fifteen tiny native compiles
(150 per mode) took 26.0202 s disabled versus 15.5718 s warm, a 40.15%
reduction (173.5 ms to 103.8 ms per compile).
