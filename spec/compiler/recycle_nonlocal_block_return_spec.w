# A method containing a `return` inside a block uses one setjmp/catch/exit
# funnel. Recycle cleanup must still be path-sensitive: the non-local transfer
# unwinds parent and block allocations at runtime, normal returns clean their
# live compile-time prefix before joining the exit, and a later function-body
# allocation must never be referenced from the catch path where it does not
# dominate.

-> check_nonlocal_recycle(name, got, want)
  if got != want
    << "FAIL nonlocal recycle " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)
  << "PASS nonlocal recycle " + name

-> nonlocal_recycle_fn(take_return)
  before = [] ## recycle
  before.push(40)
  [2].each -> (item)
    block_scratch = {} ## recycle
    block_scratch["item"] = item
    if take_return
      return before[0] + block_scratch["item"]

  # This temp is deliberately after the possible longjmp. It cannot dominate
  # the shared catch/exit return and must be cleaned only on the normal path.
  later = {} ## recycle
  later["value"] = before[0] + 3
  later["value"]

-> nonlocal_recycle_early(early)
  # The dormant block return is enough to create the shared exit funnel.
  [1].each -> (item)
    if false
      return item
  if early
    return 11
  later = [] ## recycle
  later.push(31)
  later[0]

+ NonlocalRecycleProbe
  -> run(take_return)
    before = {} ## recycle
    before["value"] = 40
    [2].each -> (item)
      block_scratch = [] ## recycle
      block_scratch.push(item)
      if take_return
        return before["value"] + block_scratch[0]
    later = [] ## recycle
    later.push(before["value"] + 4)
    later[0]

check_nonlocal_recycle("function nonlocal", nonlocal_recycle_fn(true), 42)
check_nonlocal_recycle("function normal", nonlocal_recycle_fn(false), 43)
check_nonlocal_recycle("normal early prefix", nonlocal_recycle_early(true), 11)
check_nonlocal_recycle("normal late allocation", nonlocal_recycle_early(false), 31)

probe = NonlocalRecycleProbe.new()
check_nonlocal_recycle("method nonlocal", probe.run(true), 42)
check_nonlocal_recycle("method normal", probe.run(false), 44)

# Repeated transfers would leave duplicate pool entries if either the block or
# parent allocation were recycled both before and after the longjmp.
i = 0
while i < 16
  nonlocal_recycle_fn(true)
  probe.run(true)
  i += 1

first_array = [] ## recycle
second_array = [] ## recycle
check_nonlocal_recycle("array pool distinct",
                       wvalue_bits(first_array) != wvalue_bits(second_array), true)
first_hash = {} ## recycle
second_hash = {} ## recycle
check_nonlocal_recycle("hash pool distinct",
                       wvalue_bits(first_hash) != wvalue_bits(second_hash), true)

<< "PASS nonlocal block-return recycle cleanup"
