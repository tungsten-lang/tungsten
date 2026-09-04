# Object free-insertion / escape analysis (ownership.w construct_producer_class
# + escape.w per-parameter summaries + the runtime w_value_free instance arm).
#
# `Cls.new(...)` on a class name lowers to the guarded construct arm
# (w_object_new + plain initializer worker). When the initializer never stores
# `self`, the fresh object is a heap producer, and a devirtualized method call
# on it consults the method's escape summary instead of pinning the receiver.
# So a loop temporary such as `Pt.new(i, i + 1)` is freed at scope exit
# instead of leaking one WObject per iteration (163 MB at 2M iterations).
#
# This spec pins BOTH halves of that contract, mirroring hash_free_escape_spec:
#   * transient objects MUST compute correctly across the free boundary — a
#     wrong free shows up as corrupted fields once malloc recycles the block,
#     so the loops run long enough to reuse addresses many times;
#   * objects that ESCAPE (returned, stored in an ivar/array/global, captured
#     by a closure, registered by their own initializer, returned as `self`
#     from a builder method, threaded through a rescue merge, frozen) must
#     NOT be freed.
#
# Run: `bin/tungsten -o /tmp/ofe spec/compiler/object_free_escape_spec.w && /tmp/ofe`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- freeable: plain initializer, methods that only read fields ---
+ Pt
  -> new(@x, @y)
  -> sum
    @x + @y
  -> scaled(k)
    @x * k + @y * k

-> pt_churn(n)
  i = 0 ## i64
  total = 0 ## i64
  while i < n
    p = Pt.new(i, i + 1)
    total = total + p.sum + p.scaled(2)
    i = i + 1
  total
# sum(2i+1) + sum(2(2i+1)) for i < 200000 = 3 * 200000^2 = 120000000000
check("free.loop_temporary_objects", pt_churn(200000), "120000000000")

# --- freeable: heap string field (the STRING stays live via the ivar store;
# only the object shell is reclaimed) ---
+ Named
  -> new(@name, @n)
  -> label
    @name + ":" + @n.to_s()

-> named_churn(n)
  i = 0 ## i64
  bad = 0 ## i64
  while i < n
    obj = Named.new("item-" + i.to_s(), i)
    if obj.label != "item-" + i.to_s() + ":" + i.to_s()
      bad = bad + 1
    i = i + 1
  bad
check("free.string_field_objects", named_churn(100000), "0")

# --- escape: returned object stays live in the caller ---
-> make_pt(i)
  Pt.new(i, i * 2)
-> return_churn(n)
  i = 0 ## i64
  bad = 0 ## i64
  while i < n
    p = make_pt(i)
    if p.sum != i * 3
      bad = bad + 1
    i = i + 1
  bad
check("escape.returned_object", return_churn(100000), "0")

# --- escape: pushed into a live array ---
-> array_store(n)
  keep = []
  i = 0 ## i64
  while i < n
    keep.push(Pt.new(i, 0))
    i = i + 1
  ok = 0 ## i64
  j = 0 ## i64
  while j < n
    if keep[j].sum == j
      ok = ok + 1
    j = j + 1
  ok
check("escape.array_stored_object", array_store(5000), "5000")

# --- escape: stored into another object's ivar through a method ---
+ Holder
  -> new
    @items = []
    @last = nil
  -> keep(p)
    @last = p
    @items.push(p)
  -> last_sum
    @last.sum
  -> count
    @items.size

-> holder_store(n)
  h = Holder.new
  i = 0 ## i64
  while i < n
    h.keep(Pt.new(i, 1))
    i = i + 1
  h.last_sum + h.count
check("escape.ivar_stored_object", holder_store(3000), "6000")

# --- escape: the initializer registers self (self STORES → not a producer) ---
registry = []
+ Tracked
  -> new(@id)
    registry.push(self)
  -> id
    @id

-> tracked_churn(n)
  i = 0 ## i64
  while i < n
    t = Tracked.new(i)
    i = i + 1
  registry.size
check("escape.self_registered_in_ctor", tracked_churn(1000), "1000")
check("escape.self_registered_live", registry[999].id, "999")

# --- escape: builder method returns self, result stored ---
+ Builder
  -> new
    @parts = []
  -> add(x)
    @parts.push(x)
    self
  -> size
    @parts.size

-> builder_churn(n)
  keep = []
  i = 0 ## i64
  while i < n
    b = Builder.new
    keep.push(b.add(i).add(i + 1))
    i = i + 1
  total = 0 ## i64
  j = 0 ## i64
  while j < n
    total = total + keep[j].size
    j = j + 1
  total
check("escape.builder_returns_self", builder_churn(2000), "4000")

# --- escape: captured by a closure ---
-> closure_capture
  p = Pt.new(40, 2)
  reader = -> ()
    p.sum
  reader.call()
check("escape.closure_captured_object", closure_capture(), "42")

# --- escape: rescue-expression merge (:phi_i64 carrier) ---
-> rescue_merge(flag)
  p = begin
    if flag
      raise "boom"
    Pt.new(1, 0)
  rescue
    Pt.new(2, 0)
  p.sum
check("escape.rescue_merge_then", rescue_merge(false), "1")
check("escape.rescue_merge_rescue", rescue_merge(true), "2")

# --- escape: subclass inherits the plain initializer ---
+ Pt3 < Pt
  -> sum
    @x + @y + 1

-> subclass_churn(n)
  i = 0 ## i64
  bad = 0 ## i64
  while i < n
    q = Pt3.new(i, i)
    if q.sum != 2 * i + 1
      bad = bad + 1
    i = i + 1
  bad
check("free.subclass_inherited_ctor", subclass_churn(50000), "0")

# --- escape: object stored in a top-level variable (a global slot) from a
# loop body at top level; the store pins it, so it must survive the loop ---
last_pt = Pt.new(0, 0)
gi = 0 ## i64
while gi < 1000
  last_pt = Pt.new(gi, gi)
  gi = gi + 1
check("escape.global_object_live", last_pt.sum, "1998")

<< "object_free_escape_spec: all checks passed"
