# ThreadLocal — values private to one thread of execution.
#
# Each OS thread (the main thread, every Thread.new thread) sees its own value
# in each slot; goroutines share the slots of the thread (or goroutine) that
# spawned them, even when the scheduler runs them on another OS thread. A new
# Thread starts with every slot nil.
#
# The interface is an Array's, so a global cell like `STATE = [nil]` becomes
# thread-private by changing only its definition:
#
#   REALM = ThreadLocal.new(1)       # one slot, nil
#   DEPTH = ThreadLocal.new(1, 0)    # one slot, 0 on the defining thread
#   REALM[0] = r                     # this thread only
#   Thread.new -> DEPTH[0]           # nil: set it up at the top of the thread
#
# Slots are a process-wide resource (256 in all); allocate them in constants.
+ ThreadLocal
  rw :size

  -> new(n = 1, init = nil)
    @size = n
    @base = ccall("w_ctx_local_alloc", n)
    if init != nil
      i = 0
      while i < n
        ccall("w_ctx_local_set", @base + i, init)
        i += 1

  -> [](i)
    ccall("w_ctx_local_get", @base + i)

  -> []=(i, v)
    ccall("w_ctx_local_set", @base + i, v)
