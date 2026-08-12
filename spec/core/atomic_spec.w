use core/atomic

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# Keep the receiver untyped so these calls exercise dynamic type-class
# dispatch as well as the source wrappers' native boundaries.
-> exercise(cell)
  check("atomic.load", cell.load() == 10)
  check("atomic.fetch_add.old", cell.fetch_add(5) == 10)
  check("atomic.fetch_add.new", cell.load() == 15)
  check("atomic.fetch_sub.old", cell.fetch_sub(3) == 15)
  check("atomic.fetch_sub.new", cell.load() == 12)
  check("atomic.exchange.old", cell.exchange(20) == 12)
  check("atomic.exchange.new", cell.load() == 20)
  check("atomic.compare_exchange.hit", cell.compare_exchange(20, 30))
  check("atomic.compare_exchange.miss", !cell.compare_exchange(20, 40))
  check("atomic.store", cell.store(8) == 8 && cell.load() == 8)
  check("atomic.increment", cell.increment() == 9)
  check("atomic.decrement", cell.decrement() == 8)

  # Compatibility names retain their established return values: add returns
  # the old value, while set returns the value stored.
  check("atomic.compat", cell.get() == 8 && cell.add(2) == 8 && cell.set(4) == 4 && cell.cas(4, 5))

exercise(Atomic.new(10))

wide = 1152921504606846976
wide_cell = Atomic.new(wide)
check("atomic.wide.load", wide_cell.load() == wide)
check("atomic.wide.exchange", wide_cell.exchange(1) == wide)

max_i64 = 9223372036854775807
# Spell the signed minimum without negating the out-of-range positive
# magnitude; the generic BigInt unary-negation overlay cannot represent that
# source spelling canonically.
min_i64 = -9223372036854775807 - 1
wrap_cell = Atomic.new(max_i64)
check("atomic.wrap.fetch_add", wrap_cell.fetch_add(1) == max_i64 && wrap_cell.load() == min_i64)
check("atomic.wrap.decrement", wrap_cell.decrement() == max_i64)

bad_type = false
begin
  Atomic.new("1")
rescue error
  bad_type = true
check("atomic.reject.type", bad_type)

bad_range = false
begin
  Atomic.new(9223372036854775808)
rescue error
  bad_range = true
check("atomic.reject.range", bad_range)

<< "ALL PASS atomic_spec"
