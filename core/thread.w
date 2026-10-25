# Thread — a native OS thread (pthread).
#
# `Thread.new` takes a block and runs it on a fresh OS thread, in parallel with
# the caller. The block's captured variables are SNAPSHOTTED per thread at spawn
# time, so a `Thread.new` inside a loop safely captures the current loop value:
#
#   workers = []
#   i = 0
#   while i < n
#     wi = i
#     workers.push(Thread.new ->
#       do_work(state, wi))      # each thread gets its own wi
#     i += 1
#   workers.each ->(t) t.join    # wait for all; join returns the block's value
#
# Threads share the parent's heap, so they can cooperate through a shared array.
# For CPU-parallel work, keep the worker body allocation-free (operate on raw
# `i64[]`/`f64[]` slices, no printing) and let one thread do the I/O — that keeps
# the workers off the allocator entirely. `Thread.new`/`join`/`alive?`/`kill` are
# backed by the runtime; the bodies below are the interface (like OS/`W`).

+ Thread
  # Spawn: `Thread.new -> <block>` — the block runs on a new thread.
  -> new

  # Block until the thread finishes; returns the value the block produced.
  -> join
    ccall("w_thread_join", self)

  # Block up to `ms` milliseconds; true if it finished, false if still running.
  -> join(ms)
    ms_raw = ccall_nobox("w_numeric_to_i64", ms) ## i64
    ccall_rawargs("w_thread_join_timeout", self, ms_raw)

  # Is the thread still running?
  -> alive?
    ccall("w_thread_alive", self)

  # Request cancellation of the thread.
  -> kill
    ccall("w_thread_kill", self)
