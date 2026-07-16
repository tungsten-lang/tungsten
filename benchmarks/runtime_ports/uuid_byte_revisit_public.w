# Matched-root public benchmark for UUID#byte. Compile this identical source
# once against the clean native baseline and once against the source-port root.

use ../../core/uuid

DEFAULT_ITERS = 30_000_000
WARMUP_ITERS = 300_000
UUID_COUNT = 8
UUID_MASK = UUID_COUNT - 1

-> build_uuids
  [UUID.parse("00112233-4455-6677-8899-aabbccddeeff"),
   UUID.parse("ffeeddcc-bbaa-9988-7766-554433221100"),
   UUID.parse("00010203-0405-0607-0809-0a0b0c0d0e0f"),
   UUID.parse("f0e0d0c0-b0a0-9080-7060-504030201000"),
   UUID.parse("01234567-89ab-cdef-0123-456789abcdef"),
   UUID.parse("deadbeef-cafe-babe-8000-000000000001"),
   UUID.parse("ffffffff-ffff-ffff-ffff-ffffffffffff"),
   UUID.parse("00000000-0000-0000-0000-000000000000")]

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

-> run_correctness(values)
  uuid = values[0]
  expected = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
              0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]
  i = 0
  while i < 16
    check("byte [i]", uuid.byte(i), expected[i])
    i += 1

  indexes = [-281474976710656, -17, -1, 16, 17, 281474976710656]
  i = 0
  while i < indexes.size
    check("bound [i]", uuid.byte(indexes[i]), nil)
    i += 1

  # w_to_i64 intentionally retains the native helper's low-64-bit BigInt
  # behavior. Pin both valid and invalid wrapped indexes.
  two64 = 18446744073709551616
  check("BigInt wrap 0", uuid.byte(two64), 0x00)
  check("BigInt wrap 15", uuid.byte(two64 + 15), 0xff)
  check("BigInt wrap invalid", uuid.byte(two64 + 16), nil)
  check("negative BigInt wrap 0", uuid.byte(0 - two64), 0x00)

  # Existing source wrappers accept and ignore surplus arguments; moving the
  # storage load must not accidentally tighten public call behavior.
  check("surplus argument", uuid.byte(1, "ignored"), 0x11)
  check("version consumer", uuid.version, :v6)
  check("variant consumer", uuid.variant, :rfc4122)
  check("receiver type", type(uuid), "UUID")
  check("receiver stable", uuid.to_s, "00112233-4455-6677-8899-aabbccddeeff")
  << "PASS UUID#byte exact bytes/bounds/BigInt/arity/representation"

-> time_hot(values, iters)
  checksum = 0
  i = 0
  start = ccall_nobox("w_bench_thread_cpu_ns") ## i64
  while i < iters
    checksum += values[(i >> 4) & UUID_MASK].byte(i & 15)
    i += 1
  elapsed = ccall_nobox("w_bench_thread_cpu_ns") - start
  [elapsed, checksum]

-> time_fallback(uuid, indexes, iters)
  checksum = 0
  i = 0
  start = ccall_nobox("w_bench_thread_cpu_ns") ## i64
  while i < iters
    if uuid.byte(indexes[i & 3]) == nil
      checksum += 1
    i += 1
  elapsed = ccall_nobox("w_bench_thread_cpu_ns") - start
  [elapsed, checksum]

-> emit_sample(name, result, calls)
  << "SAMPLE|[name]|[result[0]]|[result[0] * 1.0 / calls]|[result[1]]"

args = argv()
mode = args.size > 0 ? args[0] : "check"
values = build_uuids()

if mode == "check"
  run_correctness(values)
  exit(0)
if mode == "fatal-float"
  values[0].byte(1.5)
  exit(99)

iters = args.size > 1 ? args[1].to_i : DEFAULT_ITERS
if iters <= 0
  << "iterations must be positive"
  exit(2)

if mode == "hot"
  time_hot(values, WARMUP_ITERS)
  emit_sample("uuid.hot", time_hot(values, iters), iters)
  exit(0)
if mode == "fallback"
  indexes = [281474976710656, -281474976710656,
             281474976710657, -281474976710657]
  time_fallback(values[0], indexes, WARMUP_ITERS)
  emit_sample("uuid.fallback", time_fallback(values[0], indexes, iters), iters)
  exit(0)

<< "unknown mode [mode]"
exit(2)
