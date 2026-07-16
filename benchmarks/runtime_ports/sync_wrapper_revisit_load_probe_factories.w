# Exact native-result provenance load probe. It calls no public synchronization
# selector, so candidate-only facade emission comes solely from factory maps.

atomic = ccall("w_atomic_new", 1)
channel = ccall("w_chan_new", 1)
worker = -> ()
  4
thread = ccall("w_thread_spawn_slots", worker)
result = ccall("w_thread_join_release", thread)
<< result
