# Exact native-result autoload probe. No public synchronization selector is
# called: the WIRE class definitions must come solely from the loader's exact
# factory-result map, not from method-name gates.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

# `w_atomic_new`/`w_chan_new` take a WValue, and a ccall int LITERAL crosses
# raw by design (see lowering/calls.w's ARGUMENT ABI note) — nest the boxing
# ccall. Both entry points began validating the argument in 3e84d832
# ("complete signed i64 atomics"); before that a raw 1 was silently read as a
# denormal double and stored as 0.
atomic = ccall("w_atomic_new", ccall("w_int", 1))
channel = ccall("w_chan_new", ccall("w_int", 1))
worker = -> ()
  4
thread = ccall("w_thread_spawn_slots", worker)

check("Atomic public class_name parity", ccall("w_class_name", atomic), "Unknown")
check("Channel public class_name parity", ccall("w_class_name", channel), "Unknown")
check("Thread public class_name parity", ccall("w_class_name", thread), "Unknown")
check("Atomic private support kind", ccall("w_sync_handle_kind_support", atomic), 1)
check("Thread private support kind", ccall("w_sync_handle_kind_support", thread), 2)
check("Channel private support kind", ccall("w_sync_handle_kind_support", channel), 3)
check("Thread direct primitive result", ccall("w_thread_join_release", thread), 4)

<< "PASS exact synchronization factory autoload"
