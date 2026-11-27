# Generational, parallel-mark, concurrent-sweep Garbage Collector spec.
# Run in both engines:
#   bin/tungsten run spec/core/gc_spec.w
#   bin/tungsten compile spec/core/gc_spec.w --out /tmp/gc-spec --no-lto && /tmp/gc-spec

+ GcSpecNode
  rw :label, :children, :meta
  -> new(@label, @children = [], @meta = {})
    nil

-> gc_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# 1. Default state is off (zero-cost no-GC path).
# Also allocate pre-GC containers while GC is off, then verify they safely
# retain young GC-tracked objects stored into them after GC.enable!
pre_arr = [nil]
pre_hash = {}
gc_check("default.disabled", !GC.enabled?)
gc_check("default.untracked", !GC.tracking?)
gc_check("default.count_zero", GC.count == 0)

# 2. Enable / disable toggles.
gc_check("enable.returns_true", GC.enable == true)
gc_check("enable.enabled", GC.enabled?)
gc_check("enable.tracking", GC.tracking?)

-> populate_pre_gc_containers(a, h)
  s = "adopted-pre-gc-" + ("p" * 80)
  a[0] = GcSpecNode.new(s, [s], {:v => s})
  h[:pre] = "hash-pre-gc-" + ("q" * 80)
  nil

populate_pre_gc_containers(pre_arr, pre_hash)
GC.minor
GC.wait_sweep
GC.major
GC.wait_sweep
gc_check("pre_gc.array_retains_young", pre_arr[0].label == "adopted-pre-gc-" + ("p" * 80))
gc_check("pre_gc.hash_retains_young", pre_hash[:pre] == "hash-pre-gc-" + ("q" * 80))

GC.disable
gc_check("disable.disabled", !GC.enabled?)
gc_check("disable.still_tracking", GC.tracking?)

GC.enable
gc_check("reenable.enabled", GC.enabled?)

# Threshold getters/setters round-trip cleanly.
orig_young = GC.young_threshold
orig_old = GC.old_threshold
GC.young_threshold = 8 * 1024 * 1024
GC.old_threshold = 32 * 1024 * 1024
gc_check("thresholds.young", GC.young_threshold == 8 * 1024 * 1024)
gc_check("thresholds.old", GC.old_threshold == 32 * 1024 * 1024)
GC.young_threshold = orig_young
GC.old_threshold = orig_old

# 3. Immortal keep arena + remembered mutable keep containers -> young refs.
keep_arr = []
keep_hash = {}
GC.keep(keep_arr)
GC.keep(keep_hash)

-> attach_young_to_keep(arr, h)
  s = "kept-young-payload-" + ("x" * 96)
  n = GcSpecNode.new(s, [1, 2, "three-" + ("y" * 64)], {:tag => "live-" + ("z" * 64)})
  arr.push(n)
  h[:entry] = [s, ->(v) s + ":" + v.to_s]
  nil

attach_young_to_keep(keep_arr, keep_hash)
GC.minor
GC.wait_sweep
GC.major
GC.wait_sweep

gc_check("keep.object_label", keep_arr[0].label == "kept-young-payload-" + ("x" * 96))
gc_check("keep.object_child", keep_arr[0].children[2] == "three-" + ("y" * 64))
gc_check("keep.object_meta", keep_arr[0].meta[:tag] == "live-" + ("z" * 64))
gc_check("keep.closure_capture", keep_hash[:entry][1].call(7) == "kept-young-payload-" + ("x" * 96) + ":7")

# 4. Generational promotion + OLD dirty-hash / mutable-object barriers.
old_hash = {:seed => "initial-" + ("a" * 80)}
old_node = GcSpecNode.new("old-root", [], {})
GC.minor
GC.wait_sweep

-> mutate_old_containers(h, node)
  i = 0
  while i < 50
    h["k" + i.to_s] = "val-" + i.to_s + "-" + ("b" * 72)
    node.children.push("child-" + i.to_s + "-" + ("c" * 72))
    i += 1
  nil

mutate_old_containers(old_hash, old_node)
GC.minor
GC.wait_sweep

gc_check("gen.old_hash_young_val", old_hash["k49"] == "val-49-" + ("b" * 72))
gc_check("gen.old_node_young_child", old_node.children[49] == "child-49-" + ("c" * 72))

# 4b. Escaping 4-capture closures retain all heap capture cells even when
#     malloc places cl->captures immediately before cell_0 (32B size class).
-> make_listener_closure(a, b, c)
  rt = a
  ->(ev) rt.label + ":" + b + ":" + c + ":" + ev

listeners = []
li = 0
while li < 120
  nd = GcSpecNode.new("rt-" + li.to_s + "-" + ("r" * 40), [], {})
  listeners.push(make_listener_closure(nd, "b" + li.to_s, "c" + li.to_s))
  li += 1
GC.minor
GC.wait_sweep
GC.major
GC.wait_sweep
gc_check("closure.four_capture_cells", listeners[119].call("ok") == "rt-119-" + ("r" * 40) + ":b119:c119:ok")

# 5. Churn unreachable heap strings, slices, objects, arrays, hashes, closures.
-> churn_garbage(rounds)
  keep_slice = nil
  i = 0
  while i < rounds
    parent = "0123456789abcdef" * 16 + ":" + i.to_s
    sub = parent.slice(16, 64)
    keep_slice = sub if i == rounds - 1
    tmp = GcSpecNode.new(parent, [sub, i], {:k => sub})
    fn = ->(x) tmp.label.size + x
    _ = fn.call(1)
    i += 1
  keep_slice

surviving_slice = churn_garbage(4000)
GC.major
GC.wait_sweep
st = GC.stats

gc_check("sweep.slice_view_keeps_parent", surviving_slice.size == 64 && surviving_slice.starts_with?("0123456789abcdef"))
gc_check("sweep.reclaimed_objects", st[:swept_objects] > 1000)
gc_check("sweep.reclaimed_bytes", st[:swept_bytes] > 65536)
gc_check("sweep.minor_and_major_counted", st[:minor_count] >= 2 && st[:major_count] >= 2)

# 6. Multi-threaded mutators + parallel mark + concurrent sweep.
threads = []
t = 0
while t < 4
  tid = t
  th = Thread.new ->
    acc = []
    j = 0
    while j < 600
      msg = "thr-" + tid.to_s + "-" + j.to_s + "-" + ("m" * 64)
      acc.push(msg) if (j % 100) == 0
      _ = {:drop => msg, :arr => [j, msg]}
      GC.minor if j == 300 && tid == 0
      j += 1
    acc.size
  threads.push(th)
  t += 1

sum = 0
threads.each ->(th) sum += th.join
GC.major
GC.wait_sweep
gc_check("threads.joined_cleanly", sum == 24)

# 7. Fire-and-forget Thread.new + blocking syscall retains both captured heap
#    objects and worker-stack locals across concurrent GC.minor + GC.major!
ff_done = Chan.new(4)
-> spawn_detached_worker(ch)
  payload = "detached-job-" + ("d" * 96)
  box = GcSpecNode.new(payload, [ByteArray.from_array([1, 2, 3, 4])], {:ok => payload})
  Thread.new ->
    local_buf = ByteArray.from_array([9, 8, 7])
    sleep(0.08)
    b = box.children[0]
    b.push(local_buf[0])
    ch.send(box.label + ":" + b.size.to_s + ":" + b[4].to_s)
  nil

spawn_detached_worker(ff_done)
sleep(0.015)
GC.minor
GC.wait_sweep
GC.major
GC.wait_sweep
ff_msg = ff_done.recv
gc_check("threads.detached_blocking_roots", ff_msg == "detached-job-" + ("d" * 96) + ":5:9")

GC.disable
gc_check("final.disabled", !GC.enabled?)
