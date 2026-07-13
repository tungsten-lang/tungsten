# Tungsten runtime/compiler notes from native FlipFleet

The pure-Tungsten 3x3 through 7x7 fleet is operational without a new language
syntax feature.  CPU threads, shared `i64[]` state, exhaustive verification,
Metal i64 buffers/threadgroup storage, SIMD-group operations, and terminal
polling are already sufficient.

The implementation did expose several lowering/runtime issues worth fixing:

1. **Boxed integer to raw i64 coercion.** `String#to_i()` values above the
   immediate-integer range and scalar `metal_buffer_read_i64` results do not
   reliably store into typed i64 locals/arrays.  The 7x7 paths currently parse
   decimal masks in small chunks and use typed `metal_buffer_view(..., 66, ...)`
   views.  A real `String#to_i64` plus correct BigInt-to-raw lowering would
   remove both workarounds.
2. **Typed-array compound assignment.** `buffer[index] += value` can cross the
   boxed/raw boundary (`nil + int` or silent failure) in native code.  Native
   FlipFleet uses the reliable explicit form
   `buffer[index] = buffer[index] + value`.  Compound indexed writes should
   lower to the same raw load/add/store.
3. **Asynchronous child processes.** Only synchronous shell `system`/`capture`
   are currently exposed.  FlipFleet runs bounded native GPU epochs by calling
   `system` inside a Tungsten OS thread.  A `Process.spawn` handle with argv,
   cwd/env, poll/wait, exit status, and terminate would make external SAT lanes
   and failure handling safer.
   *Partially resolved 2026-07-12:* `__w_system` now spawns via
   `posix_spawn`+`waitpid` instead of libc `system(3)`.  This matters twice
   over: macOS `system()` serializes every concurrent caller on one global
   mutex (the coordinator's per-round status rename queued ~7s behind each
   GPU epoch, collapsing CPU throughput ~600x whenever the GPU was on), and
   it sets SIGINT/SIGQUIT to SIG_IGN in the parent for the child's lifetime
   (Ctrl-C killed GPU children but never the coordinator).  Runtime also
   gained `__w_trap_interrupts`/`__w_interrupted`, a cooperative
   SIGINT/SIGTERM latch the coordinator polls each round for graceful
   drain-and-save shutdown; a second signal hard-exits.
4. **Campaign-safe filesystem operations.** FlipFleet currently writes a
   run-tagged temporary file for atomic checkpoint replacement.  Native
   append, mkdir-p, unlink, exclusive create/flock, and fsync would complete
   the surface and make concurrent same-tensor best updates safely monotonic.
   `write_file` should also report short `fwrite` and `fclose` failures, not
   only open failures.
   *Partially resolved 2026-07-12:* `__w_rename` (rename(2) on boxed string
   WValues) replaced the shell `mv -f`, so atomic publish no longer forks.
5. **Terminal lifecycle.** Columns and raw key polling exist; terminal rows and
   a reliable `at_exit`/signal cleanup hook would complete the TUI surface.

The current `--secs` limit is therefore deliberately soft: the coordinator
stops scheduling CPU rounds, then ordinarily joins every finite GPU child.
`Thread#kill` cannot safely implement a hard deadline because it cancels only
the wrapper thread, not the shell subprocess or its process group.

GPU atomics are optional.  The current MITM engine enumerates on Metal, builds
its collision-preserving table on the host, and probes on Metal; at pool 700
the host table phase is about 12 ms, so device CAS is not a blocker.

An 8x8 tensor is a separate representation project: one factor occupies 64
bits, beyond the signed-i64 mask contract used by the 3x3--7x7 engines.  It
needs u64 or multiword factors rather than a parser or coordinator extension.
