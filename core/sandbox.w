# Sandboxed execution — the runtime's gate over everything outside the
# process. Where System describes the machine, Sandbox cuts the program
# off from it.
#
# `bin/tungsten sandbox file.w` compiles the program and runs it with the
# gate latched (TUNGSTEN_SANDBOX=1). Inside, externs that reach the outside
# world are intercepted and every attempt is logged as one JSON line to
# TUNGSTEN_SANDBOX_LOG (or stderr):
#
#   blocked (raise a catchable error) — file reads/writes, read_dir, mmap,
#     rename, mkdtemp, sockets (connect/listen/accept/serve), system,
#     capture, Process spawn/wait/kill, setenv, scientific-format IO
#   stubbed (benign value, still logged) — env(name) → nil,
#     File.exist? / File.directory? → false, file size/mtime/id → nil,
#     Process alive? → false
#
# stdout/stderr, stdin, clocks, threads, and pure computation are untouched —
# a sandboxed program still prints its results.
#
# This is containment for observation (the log is the point), not a hardened
# security boundary: ccall reaches any linked symbol directly.
#
# Compiled programs only: the interpreter loads core classes from disk
# mid-run, which the gate itself would block.
+ Sandbox
  # True when the gate is latched (TUNGSTEN_SANDBOX=1 or .enable).
  -> .active?
    ccall("w_sandbox_enabled_p")

  # Latch the gate for the rest of the process. One-way: no disable.
  -> .enable
    ccall("w_sandbox_latch")

  # Number of operations blocked or stubbed so far.
  -> .attempts
    ccall("w_sandbox_attempt_count")
