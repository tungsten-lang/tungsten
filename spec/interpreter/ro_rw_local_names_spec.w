# Parameters and locals named `ro` / `rw` read as plain variables.
#
# The parser always reads a bare `ro` / `rw` as a zero-argument call, so the
# accessor marker after a constructor (`-> new(@x) rw`) parses. The compiled
# lowering resolves such a call to the local of that name (lowering/calls.w);
# the interpreter raised "Undefined method 'rw'" instead, which broke
# `Raster#fill_rect` (its kernel `raster_rect` takes `rw, rh`) on
# `bin/tungsten run --interpret`.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)
  << "PASS [name]"

-> typed_sum(rw, ro) (i64 i64) i64
  rw + ro

-> untyped_scale(rw)
  rw * 2

-> local_names
  ro = 5
  rw = ro + 1
  [ro, rw]

+ Box
  -> new(@width, @label) ro

  -> area(rw, rh)
    rw * rh + @width

check("typed params named rw, ro", typed_sum(3, 4), 7)
check("untyped param named rw", untyped_scale(5), 10)
check("locals named ro, rw", local_names(), [5, 6])
b = Box.new(2, "b")
check("ro marker still declares readers", b.width, 2)
check("method param named rw", b.area(3, 4), 14)
r = Raster.new(4, 3, 0)
r.fill_rect(1, 1, 2, 1, 255)
check("Raster#fill_rect (kernel params rw, rh)", r.get(1, 1) + r.get(2, 1) + r.get(0, 1) + r.get(1, 0), 510)

<< "ALL PASS ro_rw_local_names_spec"
