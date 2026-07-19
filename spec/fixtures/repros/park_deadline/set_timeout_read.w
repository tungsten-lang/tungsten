# Boxed-Socket read deadline: Socket#set_timeout(ms) + Socket#read must
# return nil once the timeout expires with no data — even under a
# PERSISTENT scheduler (the park-deadline sweep fix, see park_deadline.w).
#
# Before the fix pair this hung twice over: set_timeout was a documented
# no-op on the non-blocking runtime sockets (SO_RCVTIMEO never fires on a
# non-blocking fd — see bits/tungsten-forge/lib/server.w), and even a
# parked deadline was never swept in persistent mode. Now set_timeout is
# recorded on the WSocket and w_socket_read parks with it as a deadline;
# expiry surfaces as a nil read — the same "connection is done" signal a
# peer close produces, which is exactly what a keep-alive server loop
# wants for reaping idle clients.
#
# Compiled-only: Socket / go / ccall are compiled-runtime builtins.

+ IdleReader
  -> .start(port)
    go -> IdleReader.run(port)

  -> .run(port)
    sock = Socket.connect("127.0.0.1", port)
    << "set-timeout-read: connected"
    sock.set_timeout(1500)
    << "set-timeout-read: reading with 1500ms timeout"
    chunk = sock.read(4096)
    if chunk == nil
      << "set-timeout-read: nil (deadline fired)"
    else
      << "set-timeout-read: UNEXPECTED data"
    pmode_off = 0 ## i64
    ccall("w_scheduler_set_persistent", pmode_off)

listener = Socket.listen("127.0.0.1", 18472, 8)
pmode_on = 1 ## i64
ccall("w_scheduler_set_persistent", pmode_on)
IdleReader.start(18472)
<< "set-timeout-read: main done, entering persistent scheduler"
