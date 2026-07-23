# Child-process control: spawn / poll / wait / kill.
#
# For coordinators that manage worker fleets — portfolio solvers, build
# farms — where `system` is unusable: it collapses the exit status to a
# boolean, blocks until completion, and cannot address the child again.
# Each child runs in its OWN process group, so kill reaches the child and
# its descendants and never the parent.
#
#   p = Process.spawn(["solver", "problem.cnf", "--fast"])   # argv, no shell
#   p.pid                    # > 0
#   p.poll                   # nil while running, else exit code
#   p.wait                   # block; exit code (256+signal if signaled)
#   p.kill                   # TERM the group
#   p.kill(9)                # KILL the group
#   p.alive?
#
# Exit codes pass through unchanged — SAT-conventional 10/20 work directly.
# Compiled programs only: the runtime externs are not in the interpreter's
# ccall whitelist.

+ Process
  -> new(@pid)
    @status = nil

  # Spawn argv (an Array of strings) directly — no shell interpretation.
  # Raises when the spawn fails.
  -> .spawn(argv)
    pid = ccall("__w_proc_spawn", argv)
    raise "process spawn failed for [argv[0]] ([pid])" if pid <= 0
    Process.new(pid)

  -> pid
    @pid

  # Non-blocking: nil while running, else the exit code (256+signal when
  # signal-terminated). The code is cached; later calls return it again.
  -> poll
    return @status unless @status == nil
    r = ccall("__w_proc_wait", @pid, 0)
    return nil if r == -1
    raise "wait failed for pid [@pid]" if r == -2
    @status = r
    r

  # Block until exit; returns the exit code (256+signal when signaled).
  -> wait
    return @status unless @status == nil
    r = ccall("__w_proc_wait", @pid, 1)
    raise "wait failed for pid [@pid]" if r == -2
    @status = r
    r

  # Signal the child's process group. Default TERM; already-reaped children
  # return false.
  -> kill(sig = 15)
    return false unless @status == nil
    ccall("__w_proc_kill", @pid, sig)

  -> alive?
    return false unless @status == nil
    # a zombie answers signal 0; reap it first
    r = self.poll
    r == nil
