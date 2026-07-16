# Matched-root public-dispatch workload for the small Atomic, Channel, and
# Thread source facades. There is deliberately no `use` and every receiver
# comes from a uniquely named C fixture, so the candidate must exercise the
# opaque method-name autoload path rather than a class-reference shortcut.

DEFAULT_WARMUP = 100_000

-> fail_check(name, got, expected)
  << "FAIL [name]: got=[got] expected=[expected]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, got, expected)

-> atomic_fixture(initial)
  ccall("w_syncwrap_atomic_fixture", initial)

-> release_atomic(value)
  ccall("w_syncwrap_release_atomic", value)

-> ref_atomic_cas(value, expected, desired)
  ccall("w_syncwrap_ref_atomic_cas", value, expected, desired)

-> ref_atomic_get(value)
  ccall("w_syncwrap_ref_atomic_get", value)

-> ref_atomic_set(value, replacement)
  ccall("w_syncwrap_ref_atomic_set", value, replacement)

-> ref_atomic_increment(value)
  ccall("w_syncwrap_ref_atomic_increment", value)

-> ref_atomic_decrement(value)
  ccall("w_syncwrap_ref_atomic_decrement", value)

-> ref_atomic_add(value, delta)
  ccall("w_syncwrap_ref_atomic_add", value, delta)

-> channel_fixture(capacity)
  ccall("w_syncwrap_channel_fixture", capacity)

-> ref_channel_send(channel, value)
  ccall("w_syncwrap_ref_channel_send", channel, value)

-> ref_channel_recv(channel)
  ccall("w_syncwrap_ref_channel_recv", channel)

-> ref_channel_close(channel)
  ccall("w_syncwrap_ref_channel_close", channel)

-> channel_reopen(channel)
  ccall("w_syncwrap_channel_reopen", channel)

-> channel_closed(channel)
  ccall("w_syncwrap_channel_closed", channel)

-> release_channel(channel)
  ccall("w_syncwrap_release_channel", channel)

-> dead_thread_fixture(result)
  ccall("w_syncwrap_dead_thread_fixture", result)

-> release_dead_thread(thread)
  ccall("w_syncwrap_release_dead_thread", thread)

-> live_thread_fixture
  ccall("w_syncwrap_live_thread_fixture")

-> ref_thread_join(thread)
  ccall("w_syncwrap_ref_thread_join", thread)

-> ref_thread_join_timeout(thread, milliseconds)
  ccall("w_syncwrap_ref_thread_join_timeout", thread, milliseconds)

-> ref_thread_alive(thread)
  ccall("w_syncwrap_ref_thread_alive", thread)

-> ref_thread_kill(thread)
  ccall("w_syncwrap_ref_thread_kill", thread)

-> join_release_live_thread(thread)
  ccall("w_syncwrap_join_release_live_thread", thread)

-> thread_cpu_ns
  ccall_nobox("w_syncwrap_thread_cpu_ns") ## i64

-> check_atomic
  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#get plain", public.get, ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#get surplus", public.get(91, 92), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(3)
  reference = atomic_fixture(3)
  check("Atomic#cas plain", public.cas(3, 9), ref_atomic_cas(reference, 3, 9))
  check("Atomic#cas state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(3)
  reference = atomic_fixture(3)
  check("Atomic#cas surplus", public.cas(3, 9, 91, 92), ref_atomic_cas(reference, 3, 9))
  check("Atomic#cas surplus state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#set plain", public.set(7), ref_atomic_set(reference, 7))
  check("Atomic#set state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#set surplus", public.set(7, 91, 92), ref_atomic_set(reference, 7))
  check("Atomic#set surplus state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#increment plain", public.increment, ref_atomic_increment(reference))
  check("Atomic#increment state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#increment surplus", public.increment(91, 92), ref_atomic_increment(reference))
  check("Atomic#increment surplus state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#decrement plain", public.decrement, ref_atomic_decrement(reference))
  check("Atomic#decrement state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#decrement surplus", public.decrement(91, 92), ref_atomic_decrement(reference))
  check("Atomic#decrement surplus state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#add plain", public.add(3), ref_atomic_add(reference, 3))
  check("Atomic#add state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  public = atomic_fixture(4)
  reference = atomic_fixture(4)
  check("Atomic#add surplus", public.add(3, 91, 92), ref_atomic_add(reference, 3))
  check("Atomic#add surplus state", ref_atomic_get(public), ref_atomic_get(reference))
  release_atomic(public)
  release_atomic(reference)

  value = atomic_fixture(2)
  hits = 0
  value.get -> hits += 1
  check("Atomic#get trailing block", hits, 2)
  release_atomic(value)

  value = atomic_fixture(0)
  hits = 0
  value.set(2) -> hits += 1
  check("Atomic#set trailing block", hits, 2)
  release_atomic(value)

  value = atomic_fixture(1)
  hits = 0
  value.increment -> hits += 1
  check("Atomic#increment trailing block", hits, 2)
  release_atomic(value)

  value = atomic_fixture(3)
  hits = 0
  value.decrement -> hits += 1
  check("Atomic#decrement trailing block", hits, 2)
  release_atomic(value)

  value = atomic_fixture(2)
  hits = 0
  value.add(1) -> hits += 1
  check("Atomic#add trailing block", hits, 2)
  release_atomic(value)

-> check_channel
  public = channel_fixture(1)
  reference = channel_fixture(1)
  check("Channel#send plain return", public.send(17), ref_channel_send(reference, 17))
  check("Channel#send plain value", ref_channel_recv(public), ref_channel_recv(reference))
  release_channel(public)
  release_channel(reference)

  public = channel_fixture(1)
  reference = channel_fixture(1)
  check("Channel#send surplus return", public.send(19, 91, 92), ref_channel_send(reference, 19))
  check("Channel#send surplus value", ref_channel_recv(public), ref_channel_recv(reference))
  release_channel(public)
  release_channel(reference)

  public = channel_fixture(1)
  reference = channel_fixture(1)
  ref_channel_send(public, 23)
  ref_channel_send(reference, 23)
  check("Channel#recv plain", public.recv, ref_channel_recv(reference))
  release_channel(public)
  release_channel(reference)

  public = channel_fixture(1)
  reference = channel_fixture(1)
  ref_channel_send(public, 29)
  ref_channel_send(reference, 29)
  check("Channel#recv surplus", public.recv(91, 92), ref_channel_recv(reference))
  release_channel(public)
  release_channel(reference)

  public = channel_fixture(1)
  reference = channel_fixture(1)
  ref_channel_close(public)
  ref_channel_close(reference)
  check("Channel#recv closed", public.recv, ref_channel_recv(reference))
  release_channel(public)
  release_channel(reference)

  public = channel_fixture(1)
  reference = channel_fixture(1)
  check("Channel#close plain return", public.close, ref_channel_close(reference))
  check("Channel#close plain state", channel_closed(public), channel_closed(reference))
  release_channel(public)
  release_channel(reference)

  public = channel_fixture(1)
  reference = channel_fixture(1)
  check("Channel#close surplus return", public.close(91, 92), ref_channel_close(reference))
  check("Channel#close surplus state", channel_closed(public), channel_closed(reference))
  release_channel(public)
  release_channel(reference)

  value = channel_fixture(1)
  ref_channel_send(value, 2)
  hits = 0
  value.recv -> hits += 1
  check("Channel#recv trailing block", hits, 2)
  release_channel(value)

-> check_thread
  public = dead_thread_fixture(7)
  reference = dead_thread_fixture(7)
  check("Thread#join/0", public.join, ref_thread_join(reference))
  release_dead_thread(public)
  release_dead_thread(reference)

  public = dead_thread_fixture(7)
  reference = dead_thread_fixture(7)
  check("Thread#join/1", public.join(0), ref_thread_join_timeout(reference, 0))
  release_dead_thread(public)
  release_dead_thread(reference)

  public = dead_thread_fixture(7)
  reference = dead_thread_fixture(7)
  check("Thread#join/1 surplus", public.join(0, 91, 92), ref_thread_join_timeout(reference, 0))
  release_dead_thread(public)
  release_dead_thread(reference)

  public = dead_thread_fixture(7)
  reference = dead_thread_fixture(7)
  check("Thread#alive? plain", public.alive?, ref_thread_alive(reference))
  release_dead_thread(public)
  release_dead_thread(reference)

  public = dead_thread_fixture(7)
  reference = dead_thread_fixture(7)
  check("Thread#alive? surplus", public.alive?(91, 92), ref_thread_alive(reference))
  release_dead_thread(public)
  release_dead_thread(reference)

  public = live_thread_fixture()
  reference = live_thread_fixture()
  check("Thread#alive? live", public.alive?, ref_thread_alive(reference))
  ref_thread_kill(public)
  ref_thread_kill(reference)
  join_release_live_thread(public)
  join_release_live_thread(reference)

  public = live_thread_fixture()
  reference = live_thread_fixture()
  check("Thread#kill plain", public.kill, ref_thread_kill(reference))
  join_release_live_thread(public)
  join_release_live_thread(reference)

  public = live_thread_fixture()
  reference = live_thread_fixture()
  check("Thread#kill surplus", public.kill(91, 92), ref_thread_kill(reference))
  join_release_live_thread(public)
  join_release_live_thread(reference)

  value = dead_thread_fixture(2)
  hits = 0
  value.join -> hits += 1
  check("Thread#join/0 trailing block", hits, 2)
  release_dead_thread(value)

-> run_correctness
  check_atomic()
  check_channel()
  check_thread()
  << "PASS synchronization wrappers: values, mutation, surplus args, and successful trailing-block passthrough"

-> fatal_atomic_bool_block
  value = atomic_fixture(1)
  value.cas(1, 1) -> nil
  << "FAIL Atomic bool trailing block unexpectedly returned"
  exit(9)

-> fatal_atomic_cas_missing0
  value = atomic_fixture(1)
  value.cas
  << "FAIL Atomic#cas/0 unexpectedly returned"
  exit(9)

-> fatal_atomic_cas_missing1
  value = atomic_fixture(1)
  value.cas(1)
  << "FAIL Atomic#cas/1 unexpectedly returned"
  exit(9)

-> fatal_channel_nil_block
  value = channel_fixture(1)
  ref_channel_close(value)
  value.recv -> nil
  << "FAIL Channel#recv nil trailing block unexpectedly returned"
  exit(9)

-> fatal_channel_send_missing
  value = channel_fixture(1)
  value.send
  << "FAIL Channel#send/0 unexpectedly returned"
  exit(9)

-> fatal_thread_bool_block
  value = dead_thread_fixture(1)
  value.alive? -> nil
  << "FAIL Thread#alive? trailing block unexpectedly returned"
  exit(9)

-> fatal_thread_nil_block
  value = live_thread_fixture()
  value.kill -> nil
  << "FAIL Thread nil trailing block unexpectedly returned"
  exit(9)

-> time_atomic_cas(iters)
  value = atomic_fixture(0)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += wvalue_bits(value.cas(0, 0)) & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_atomic(value)
  [elapsed, checksum]

-> time_atomic_get(iters)
  value = atomic_fixture(7)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += value.get & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_atomic(value)
  [elapsed, checksum]

-> time_atomic_set(iters)
  value = atomic_fixture(0)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += value.set(7) & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_atomic(value)
  [elapsed, checksum]

-> time_atomic_increment(iters)
  value = atomic_fixture(0)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += value.increment & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_atomic(value)
  [elapsed, checksum]

-> time_atomic_decrement(iters)
  value = atomic_fixture(0)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += value.decrement & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_atomic(value)
  [elapsed, checksum]

-> time_atomic_add(iters)
  value = atomic_fixture(0)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += value.add(1) & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_atomic(value)
  [elapsed, checksum]

-> time_channel_send(iters)
  value = channel_fixture(1)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    value.send(i & 0xFF)
    checksum += ref_channel_recv(value)
    i += 1
  elapsed = thread_cpu_ns() - started
  release_channel(value)
  [elapsed, checksum]

-> time_channel_recv(iters)
  value = channel_fixture(iters)
  i = 0
  while i < iters
    ref_channel_send(value, i & 0xFF)
    i += 1
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += value.recv
    i += 1
  elapsed = thread_cpu_ns() - started
  release_channel(value)
  [elapsed, checksum]

-> time_channel_close(iters)
  value = channel_fixture(1)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    value.close
    checksum += channel_closed(value)
    channel_reopen(value)
    i += 1
  elapsed = thread_cpu_ns() - started
  release_channel(value)
  [elapsed, checksum]

-> time_thread_join0(iters)
  value = dead_thread_fixture(7)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += value.join
    i += 1
  elapsed = thread_cpu_ns() - started
  release_dead_thread(value)
  [elapsed, checksum]

-> time_thread_join1(iters)
  value = dead_thread_fixture(7)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += wvalue_bits(value.join(0)) & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_dead_thread(value)
  [elapsed, checksum]

-> time_thread_alive(iters)
  value = dead_thread_fixture(7)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += wvalue_bits(value.alive?) & 0xFF
    i += 1
  elapsed = thread_cpu_ns() - started
  release_dead_thread(value)
  [elapsed, checksum]

-> time_thread_kill(iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    value = live_thread_fixture()
    value.kill
    join_release_live_thread(value)
    checksum += i & 1
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_once(kind, iters)
  if kind == "atomic.cas"
    return time_atomic_cas(iters)
  if kind == "atomic.get"
    return time_atomic_get(iters)
  if kind == "atomic.set"
    return time_atomic_set(iters)
  if kind == "atomic.increment"
    return time_atomic_increment(iters)
  if kind == "atomic.decrement"
    return time_atomic_decrement(iters)
  if kind == "atomic.add"
    return time_atomic_add(iters)
  if kind == "channel.send"
    return time_channel_send(iters)
  if kind == "channel.recv"
    return time_channel_recv(iters)
  if kind == "channel.close"
    return time_channel_close(iters)
  if kind == "thread.join0"
    return time_thread_join0(iters)
  if kind == "thread.join1"
    return time_thread_join1(iters)
  if kind == "thread.alive"
    return time_thread_alive(iters)
  if kind == "thread.kill"
    return time_thread_kill(iters)
  << "unknown synchronization wrapper benchmark [kind]"
  exit(2)

args = argv()
mode = args.size() > 0 ? args[0] : "check"
if mode == "check"
  run_correctness()
  exit(0)
if mode == "fatal-atomic-bool-block"
  fatal_atomic_bool_block()
  exit(9)
if mode == "fatal-atomic-cas-missing0"
  fatal_atomic_cas_missing0()
  exit(9)
if mode == "fatal-atomic-cas-missing1"
  fatal_atomic_cas_missing1()
  exit(9)
if mode == "fatal-channel-nil-block"
  fatal_channel_nil_block()
  exit(9)
if mode == "fatal-channel-send-missing"
  fatal_channel_send_missing()
  exit(9)
if mode == "fatal-thread-bool-block"
  fatal_thread_bool_block()
  exit(9)
if mode == "fatal-thread-nil-block"
  fatal_thread_nil_block()
  exit(9)
if mode != "bench" || args.size() < 3
  << "usage: sync-wrapper-revisit bench KIND POSITIVE_ITERS [WARMUP]"
  exit(2)

kind = args[1]
iters = args[2].to_i
warmup = args.size() > 3 ? args[3].to_i : DEFAULT_WARMUP
if iters <= 0 || warmup <= 0
  << "iteration counts must be positive"
  exit(2)
run_once(kind, warmup)
result = run_once(kind, iters)
<< "RESULT|[kind]|[result[0]]|[result[1]]"
