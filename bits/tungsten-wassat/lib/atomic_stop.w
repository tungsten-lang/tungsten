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

# ---- sequential mode --------------------------------------------------------
#
# `--sequential` (or WASSAT_SEQUENTIAL=1) keeps at most one runnable thread:
# every worker is started and waited for before its creator does anything
# else, so the process uses one core however many workers a stage names. The
# workers themselves are unchanged, which keeps their allocation and dispatch
# discipline; only the waiting moves.

-> wassat_sequential?
  env("WASSAT_SEQUENTIAL") == "1"

# For a worker bounded by its own work or deadline: wait for it now. The
# handle stays valid, and a later join returns at once.
-> wassat_seq_wait(handle)
  return handle if handle == nil
  z = handle.join if wassat_sequential?
  handle

# For a worker that otherwise runs until somebody raises `cell`: give it
# `window_ms` (zero: until its own bound), cancel it there, and re-arm the
# cell unless a verdict was published while it ran. Only for callers already
# in sequential mode, where no other worker can be reading the cell.
-> wassat_seq_turn(handle, cell, window_ms)
  return handle if handle == nil
  cancelled = false
  if window_ms > 0 && cell != nil && !wassat_stop_requested?(cell)
    finished = handle.join(window_ms)
    unless finished
      cancelled = true
      z = wassat_stop_cancel(cell)
  z = handle.join
  if cancelled && wassat_stop_status(cell) == 0
    z = ccall("__w_arr_store_rel", cell, 0, 0)
  handle
