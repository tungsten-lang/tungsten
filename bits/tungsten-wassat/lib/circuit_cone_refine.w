# Counterexample-guided proposal refinement. A retained counterexample must
# separate its queried pair in the original complete circuit before it can
# alter signatures. It has no role in proving an equality or UNSAT.

use circuit_cone_sim

-> wassat_cone_refined_round(decoded, aliases, workspace, nominees, proof, result, total_cap, deadline, budget, stop = nil)
  i = 0
  patterns = []
  left = []
  right = []
  while (i < nominees["count"] || !patterns.empty?) && result["conflicts"] < total_cap
    return false if wassat_cone_stopped(stop, deadline)
    if patterns.size == 64 || (i >= nominees["count"] && !patterns.empty?)
      word = 16 + nominees["refinements"]
      return false unless wassat_cone_refine(decoded, nominees, patterns, left, right, word, deadline, stop)
      patterns = []; left = []; right = []
      # All previously proved aliases remain valid. Regenerated classes may
      # expose a better representative among formerly colliding functions.
      i = 0
    else
      a = wassat_cone_representative(nominees["left"][i], aliases)
      b = wassat_cone_representative(nominees["right"][i], aliases)
      if a != b
        av = wassat_cone_abs(a); bv = wassat_cone_abs(b)
        y = av > bv ? av : bv
        rhs = av > bv ? bv : av
        rhs = 0 - rhs if (a < 0) != (b < 0)
        if wassat_cone_known_difference(nominees["different"], y, rhs)
          result["different_skipped"] += 1
          i += 1
          next
        cap = total_cap - result["conflicts"]
        cap = budget if cap > budget
        cap = wassat_cone_budget_left(workspace, cap)
        return true if cap <= 0
        capture = nominees["refinements"] < 16
        query = wassat_cone_prove(decoded, aliases, workspace, y, rhs, cap, deadline, capture, stop)
        result["queries"] += 1
        result["separated"] += 1 if query["separated"]
        if query["separated"]
          known = wassat_cone_known_difference(nominees["different"], y, rhs, true)
        result["conflicts"] += query["conflicts"]
        result["decisions"] += query["decisions"]
        result["props"] += query["props"]
        if query["equivalent"]
          aliases[y] = rhs
          result["internal_proved"] += 1
          query["drat"].each -> (line)
            proof.append(line)
            proof.append("\n")
        elsif query["counterexample"] != nil
          patterns.push(query["counterexample"])
          left.push(y); right.push(rhs)
      i += 1
  true

# Process each topological position once. Earlier refinement restarted the
# entire sweep after each batch, re-querying many already disproved functions.
# New signatures may change future representatives; old proved aliases remain
# valid, and every newly accepted equality still needs both native refutations.
-> wassat_cone_streamed_round(decoded, aliases, workspace, nominees, proof, result, total_cap, deadline, stop = nil, batch_size = 64)
  raise "invalid streamed refinement batch size" if batch_size < 1 || batch_size > 64
  cursor = decoded["inputs"]
  i = 0
  patterns = []; left = []; right = []
  while i < nominees["count"] && result["conflicts"] < total_cap
    return false if wassat_cone_stopped(stop, deadline)
    original_y = nominees["left"][i]
    raise "streamed cone cursor moved backward" unless original_y > cursor
    cursor = original_y
    a = wassat_cone_representative(original_y, aliases)
    b = wassat_cone_representative(nominees["right"][i], aliases)
    if a != b
      av = wassat_cone_abs(a); bv = wassat_cone_abs(b)
      y = av > bv ? av : bv
      rhs = av > bv ? bv : av
      rhs = 0 - rhs if (a < 0) != (b < 0)
      cap = total_cap - result["conflicts"]
      cap = 128 if cap > 128
      cap = wassat_cone_budget_left(workspace, cap)
      return true if cap <= 0
      capture = nominees["refinements"] < 16
      query = wassat_cone_prove(decoded, aliases, workspace, y, rhs, cap, deadline, capture, stop)
      result["queries"] += 1
      result["separated"] += 1 if query["separated"]
      result["conflicts"] += query["conflicts"]
      result["decisions"] += query["decisions"]
      result["props"] += query["props"]
      return false if wassat_cone_stopped(stop, deadline)
      if query["equivalent"]
        aliases[y] = rhs
        result["internal_proved"] += 1
        query["drat"].each -> (line)
          proof.append(line); proof.append("\n")
      elsif query["counterexample"] != nil
        patterns.push(query["counterexample"])
        left.push(y); right.push(rhs)
    i += 1
    if patterns.size == batch_size
      word = 16 + nominees["refinements"]
      return false unless wassat_cone_refine(decoded, nominees, patterns, left, right, word, deadline, stop)
      patterns = []; left = []; right = []
      # Nominations are sorted by their original gate. Find the first future
      # position after rebuilding classes; never restart at an earlier gate.
      low = 0; high = nominees["count"]
      while low < high
        middle = (low + high) / 2
        if nominees["left"][middle] <= cursor
          low = middle + 1
        else
          high = middle
      i = low
  true
