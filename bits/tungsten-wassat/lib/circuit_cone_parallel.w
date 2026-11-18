# A bounded cone worker beside an existing serial solver. The coordinator
# joins every worker before inspecting results, detaching cells or publishing
# output. Only complete original-formula results can win the common stop cell.

use circuit_cone_search

-> wassat_cone_parallel_serial(solver, cap, stop, output, winner)
  result = solver.solve_budget(cap)
  output.push(result)
  if result["status"] == 1 || result["status"] == -1
    won = wassat_stop_publish(stop, result["status"])
    winner[0] = 1 if won == 1
  0

-> wassat_cone_parallel_arm(formula, cap, deadline, local_stop, stop, budget, limit, output, winner)
  result = wassat_cone_search(formula, cap, deadline, false, local_stop, budget, limit, 2)
  output.push(result)
  if result["status"] == -1 && !wassat_stop_requested?(local_stop)
    won = wassat_stop_publish(stop, -1)
    winner[0] = 2 if won == 1
  0

# nil declines admission and leaves the serial solver untouched. cap=0 has
# the public meaning unlimited; the specialist still has its own 1M ceiling.
# A private cancellation cell gives the specialist a wall limit without
# cancelling ordinary search when only that specialist's time expires.
-> wassat_cone_parallel_solve(solver, formula, cap, window_ms = 30000)
  return nil if window_ms <= 0 || !wassat_cone_candidate(formula)
  raise "negative cone race conflict limit" if cap < 0
  before = solver.unknown_result["conflicts"]
  stop = i64[2]; local_stop = i64[2]; winner = i64[1]
  budget = cap > 0 ? i64[3] : nil
  cone_cap = cap > 0 && cap < 1000000 ? cap : 1000000
  solver.set_stop_cell(stop)
  solver.set_shared_conflict_budget(budget, cap, 1)
  serial_output = []; cone_output = []
  serial_handle = nil; cone_handle = nil
  deadline = clock_ms() + window_ms
  begin
    cone_handle = Thread.new -> wassat_cone_parallel_arm(formula, cone_cap, deadline, local_stop, stop, budget, cap, cone_output, winner)
    serial_handle = Thread.new -> wassat_cone_parallel_serial(solver, cap, stop, serial_output, winner)
    remaining = deadline - clock_ms()
    remaining = 1 if remaining < 1
    finished = serial_handle.join(remaining)
    # A normal answer cancels the cone worker immediately; a timed-out cone
    # worker alone cannot stop ordinary search. Join it before waiting longer.
    z = wassat_stop_cancel(local_stop)
    z = cone_handle.join
    z = serial_handle.join unless finished
  ensure
    z = wassat_stop_cancel(local_stop)
    z = wassat_stop_cancel(stop)
    z = cone_handle.join if cone_handle != nil
    z = serial_handle.join if serial_handle != nil
    solver.set_stop_cell(nil)
    solver.set_shared_conflict_budget(nil, 0, 0)
  raise "cone race lost a worker result" unless serial_output.size == 1 && cone_output.size == 1
  result = serial_output[0]
  cone = cone_output[0]
  conflicts = budget == nil ? result["conflicts"] - before + cone["conflicts"] : ccall("__w_arr_load_acq", budget, 0)
  result["conflicts"] = conflicts
  { "result": result, "cone": cone, "cone_won": winner[0] == 2,
    "conflicts": conflicts, "budget": budget }
