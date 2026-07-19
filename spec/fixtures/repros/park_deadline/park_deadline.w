# Repro: with a PERSISTENT scheduler, a goroutine parked on a socket with a
# deadline (w_socket_park_until) must be woken when the deadline expires.
#
# Before the fix, the cooperative scheduler's idle path polled the event
# loop with timeout -1 in persistent mode (runtime.c, w_scheduler_run), so
# g_wake_expired_deadlines never ran unless some fd became ready — a parked
# deadline on a quiet socket silently never fired and this program hung
# forever. After the fix the poll timeout is clamped to the nearest pending
# park deadline, so the read below returns 0 (timed out) at ~2s.
#
# Shape: main opens a listener that never accepts/sends, flips the scheduler
# to persistent (server mode, as Socket#serve_http does), and spawns a
# goroutine that connects (the backlog completes the handshake) and then
# reads with a 2s deadline. No data ever arrives, so only the deadline can
# wake the goroutine.
#
# Compiled-only: Socket / go / ccall are compiled-runtime builtins.

+ Prober
  # `go` closure capture only works for the enclosing frame's PARAMS
  # (see bits/tungsten-forge/lib/server.w) — spawn from a param-taking method.
  -> .start(port)
    go -> Prober.probe(port)

  -> .probe(port)
    p = port ## i64
    fd = ccall_nobox("w_socket_connect_fd", "127.0.0.1", p)
    << "park-deadline: connected"
    len = 64 ## i64
    buf = ccall_nobox("w_raw_malloc", len)
    secs = 2 ## i64
    dl = ccall_nobox("__w_deadline_ticks_after_seconds", secs)
    << "park-deadline: parking with 2s deadline"
    n = ccall_nobox("w_socket_read_fd_until", fd, buf, len, dl)
    if n == 0
      << "park-deadline: fired"
    else
      << "park-deadline: UNEXPECTED read of " + n.to_s + " bytes"
    # Let the (persistent) scheduler exit so main can return cleanly.
    pmode_off = 0 ## i64
    ccall("w_scheduler_set_persistent", pmode_off)

listener = Socket.listen("127.0.0.1", 18471, 8)
pmode_on = 1 ## i64
ccall("w_scheduler_set_persistent", pmode_on)
Prober.start(18471)
<< "park-deadline: main done, entering persistent scheduler"
