# Native-memory-safe cooperative cancellation for in-process race arms.
#
# Layout:
#   cell[0]  nonzero once cancellation has been published
#   cell[1]  first decisive status (1 SAT, -1 UNSAT), or 0 for cancellation
#
# A decisive worker writes its result payload first, wins cell[1] with a C11
# compare-exchange, then release-publishes cell[0]. An acquire read observing
# cell[0] therefore also observes the winner's status and payload. Competing
# decisive workers cannot overwrite the first status. Nondecisive cancellation
# (deadline or exhausted aggregate budget) only raises cell[0], so it can stop
# workers without claiming or corrupting a concurrently completed verdict.

-> wassat_stop_load(cell) (i64[]) i64
  ccall("__w_arr_load_acq", cell, 0)

-> wassat_stop_requested?(cell)
  cell != nil && wassat_stop_load(cell) != 0

-> wassat_stop_status(cell)
  return 0 if cell == nil
  ccall("__w_arr_load_acq", cell, 1)

-> wassat_stop_publish(cell, status) (i64[] i64) i64
  return 0 unless status == 1 || status == 0 - 1
  won = ccall("__w_arr_compare_exchange", cell, 1, 0, status)
  if won == 1
    z = ccall("__w_arr_store_rel", cell, 0, 1)
  won

-> wassat_stop_cancel(cell) (i64[]) i64
  ccall("__w_arr_store_rel", cell, 0, 1)
  0
