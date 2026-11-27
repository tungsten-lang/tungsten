# Tungsten Garbage Collector (mark-and-sweep, generational, parallel mark, concurrent sweep).
#
# Disabled by default with zero mutator or allocation overhead when off.
# Enable with `GC.enable`, pause automatic collection with `GC.disable`,
# trigger collections explicitly with `GC.start`, `GC.minor`, or `GC.major`,
# and pin long-lived boot structures with `GC.keep(obj)` or `GC.keep_all`.

+ GC
  -> .enable
    ccall("w_gc_enable")

  -> .disable
    ccall("w_gc_disable")

  -> .enabled?
    ccall("w_gc_enabled_p")

  -> .tracking?
    ccall("w_gc_tracking_p")

  -> .start(full_mark = true)
    ccall("w_gc_start", full_mark)

  -> .collect(full_mark = true)
    ccall("w_gc_start", full_mark)

  -> .minor
    ccall("w_gc_minor")

  -> .major
    ccall("w_gc_major")

  -> .wait_sweep
    ccall("w_gc_wait_sweep")

  -> .keep(value)
    ccall("w_gc_keep", value)

  -> .keep_all
    ccall("w_gc_keep_all")

  -> .count
    ccall("w_gc_count")

  -> .stat
    ccall("w_gc_stats")

  -> .stats
    ccall("w_gc_stats")

  -> .young_threshold
    ccall("w_gc_young_threshold_get")

  -> .young_threshold=(bytes)
    ccall("w_gc_young_threshold_set", bytes)

  -> .old_threshold
    ccall("w_gc_old_threshold_get")

  -> .old_threshold=(bytes)
    ccall("w_gc_old_threshold_set", bytes)
