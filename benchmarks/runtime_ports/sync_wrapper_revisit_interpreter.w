# Tree-walker routing proof for the three synchronization source facades.
# Atomic and Channel deliberately enter through native ccall factories; Thread
# uses the interpreter's synchronous Thread.new model.

-> fail(name, got, expected)
  << "FAIL [name]: got=[got] expected=[expected]"
  exit(1)

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

-> check(name, got, expected)
  if got != expected
    fail(name, got, expected)

atomic = ccall("w_atomic_new", 3)
check("Atomic public class_name parity", atomic.class_name, "Unknown")
check("Atomic#get", atomic.get, 3)
check("Atomic#cas", atomic.cas(3, 9), true)
check("Atomic#cas surplus rejected", surplus_rejected?(->() atomic.cas(9, 10, 91, 92)), true)
check("Atomic#set", atomic.set(5), 5)
check("Atomic#increment", atomic.increment, 6)
check("Atomic#decrement", atomic.decrement, 5)
check("Atomic#add old value", atomic.add(4), 5)
check("Atomic#add state", atomic.get, 9)

channel = ccall("w_chan_new", 1)
check("Channel public class_name parity", channel.class_name, "Unknown")
check("Channel#send", channel.send(17), nil)
check("Channel#recv", channel.recv, 17)
check("Channel#send surplus rejected", surplus_rejected?(->() channel.send(19, 91, 92)), true)
channel.send(19)
check("Channel#recv value", channel.recv, 19)
check("Channel#close", channel.close, nil)
check("Channel#recv closed", channel.recv, nil)

thread = Thread.new ->
  4
check("Thread#join/0", thread.join, 4)
check("Thread#join/1", thread.join(0), true)
# Thread#join is a native leaf with no source body: neither engine checks
# its arity (compiled dynamic dispatch is unchecked by design), so surplus
# arguments are still tolerated here.
check("Thread#join/1 surplus", thread.join(0, 91, 92), true)
check("Thread#alive?", thread.alive?, false)
check("Thread#kill", thread.kill, nil)

<< "PASS interpreter synchronization-wrapper routing"
