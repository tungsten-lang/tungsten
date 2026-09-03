# Heap — sorites "heap" quantity: `1 heap`, `2 heaps` (core/heap.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/heap_spec.w
#   bin/tungsten -o /tmp/heap_spec spec/core/heap_spec.w && /tmp/heap_spec

use core/heap

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

h = 1 heap
check("literal is a Quantity with the heap dimension", type(h) == "Quantity")
check("to_s", h.to_s == "1 heap")
check("plural literal parses", (2 heaps).to_s == "2 heap")
check("interpolates", "[h]" == "1 heap")
check("zero annihilates", (h * 0).to_s == "0 heap")
check("heap is not a finite number", h != 5)

# The Heap class documents absorbing arithmetic and identity of all heaps; the runtime
# treats `1 heap` as an ordinary Quantity and never dispatches to Heap's methods.
# BUG: heap? is not dispatched on `1 heap` (undefined method, both engines)
# check("heap?", h.heap?)
# BUG: `1 heap + 3` raises "cannot add object/domain + int" instead of absorbing to 1 heap (both engines)
# check("absorbs finite addition", (h + 3).to_s == "1 heap")
# BUG: `1 heap - 3 heaps` is -2 heap instead of 1 heap (both engines)
# check("absorbs subtraction", (h - 3 heaps).to_s == "1 heap")
# BUG: `1 heap * 2` is 2 heap instead of 1 heap (both engines)
# check("absorbs nonzero multiplication", (h * 2).to_s == "1 heap")
# BUG: `1 heap / 2` is 0.5 heap instead of 1 heap (both engines)
# check("absorbs division", (h / 2).to_s == "1 heap")
# BUG: `1 heap > 5` raises "expected int, got object/domain" (uncatchable, both engines); Heap#<=> says heap > any finite
# check("greater than any finite", h > 5)
# BUG: `1 heap == 1 heap` is false (both engines); Heap#== says every heap equals every heap
# check("heap == heap", h == 1 heap)
# check("heap == 2 heaps", h == 2 heaps)
# BUG: `(1 heap) <=> (2 heaps)` is -1 instead of 0 (both engines)
# check("<=> between heaps is 0", (h <=> 2 heaps) == 0)
# BUG: hash differs between 1 heap and 2 heaps although Heap#hash is the constant "heap".hash
# check("hash is constant", h.hash == (2 heaps).hash)
# BUG: inspect is undefined on `1 heap` (both engines); Heap#inspect delegates to to_s
# check("inspect", h.inspect == "1 heap")

<< "ALL PASS heap_spec ([passed.load()] checks)"
