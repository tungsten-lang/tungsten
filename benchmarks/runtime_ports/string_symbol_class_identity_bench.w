use core/string_native

DEFAULT_ITERS = 10_000_000
DEFAULT_WARMUP = 250_000

-> fixture(index)
  ccall("w_strlen_fixture", index)

# Benchmark-only source facades are registered under the real internal keys.
# Their names deliberately differ from the public Unknown identity, making the
# old runtime observably wrong while letting old/fixed execute the same loop.
+ AtomicIdentityFacade
+ ThreadIdentityFacade
+ ChannelIdentityFacade

-> value_for(stratum)
  if stratum == "string.class"
    return fixture(1)
  if stratum == "symbol.class"
    return fixture(10)
  if stratum == "atomic.class"
    atomic = Atomic.new(0)
    ccall("w_class_identity_register_facade", 0x01, AtomicIdentityFacade)
    return atomic
  if stratum == "thread.class"
    thread = Thread.new ->
      1
    ccall("w_thread_join", thread)
    ccall("w_class_identity_register_facade", 0x81, ThreadIdentityFacade)
    return thread
  if stratum == "channel.class"
    channel = Channel.new(1)
    ccall("w_class_identity_register_facade", 0x84, ChannelIdentityFacade)
    return channel
  << "unknown identity stratum [stratum]"
  exit(2)

# Three arguments keep this clock-bearing body outside the compiler's
# <=2-argument pure memoization rule. Normalize every returned class pointer
# against the same process's pre-clock result: the stable checksum is zero in
# both builds, but every public .class result remains live. A scalar receiver
# keeps Array indexing out of this very small guard measurement; correctness
# fixtures separately cover all String/Symbol representations. Raw xor/or
# avoids equality dispatch, a conditional, and a boxed increment.
-> time_public_class(value, iters, run_id)
  expected_bits = wvalue_bits(value.class) ## i64
  mismatch = 0 ## i64
  i = 0 ## i64
  started = ccall_nobox("w_strlen_thread_cpu_ns") ## i64
  while i < iters
    mismatch = (mismatch | (wvalue_bits(value.class) ^ expected_bits)) ## i64
    i += 1
  [ccall_nobox("w_strlen_thread_cpu_ns") - started, mismatch]

-> public_class_label(value)
  ccall("w_class_identity_class_label", value.class)

args = argv()
if args.size() >= 2 && args[0] == "probe"
  stratum = args[1]
  << "IDENTITY_PROBE|[stratum]|[public_class_label(value_for(stratum))]"
  exit(0)
if args.size() < 4 || args[0] != "bench"
  << "usage: string-symbol-class-identity-bench probe STRATUM | bench STRATUM ITERS WARMUP"
  exit(2)
stratum = args[1]
value = value_for(stratum)
time_public_class(value, args[3].to_i, 0)
result = time_public_class(value, args[2].to_i, 1)
<< "IDENTITY_RESULT|[stratum]|[result[0]]|[args[2]]|[result[1]]"
