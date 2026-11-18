# A bounded refutation specialist for the exact comparison-miter layout.
# Simulation is a proposal mechanism only. Every alias is checked by two
# Wassat assumption queries, and every successful search returns a complete
# original-variable RUP derivation. SAT-shaped and unsupported inputs fall
# through; this module never turns a failed equivalence query into a verdict.
# The caller owns the optional cancellation cell and must cancel it at a wall
# deadline to interrupt an in-flight SAT query. Clock checks alone run between
# queries and inside circuit scans. Local assumption results never publish to
# this cell; only a coordinator may publish a complete original-CNF result.

use circuit_cone_refine

-> wassat_cone_checkpoint(formula, max_conflicts = 1000000, deadline = 0, conflict_budget = nil, conflict_limit = 0, conflict_slot = 0)
  { "formula": formula, "max_conflicts": max_conflicts, "deadline": deadline,
    "conflict_budget": conflict_budget, "conflict_limit": conflict_limit,
    "conflict_slot": conflict_slot, "ready": false, "finished": false,
    "internal_index": 0, "round": 0, "output_index": 0, "internal_done": false,
    "slice_end": 0 }

-> wassat_cone_resume(checkpoint, stop = nil, max_queries = 0)
  return checkpoint["result"] if checkpoint["finished"]
  previous = checkpoint["result"] == nil ? 0 : checkpoint["result"]["queries"]
  checkpoint["slice_end"] = max_queries > 0 ? previous + max_queries : 0
  result = wassat_cone_search(checkpoint["formula"], checkpoint["max_conflicts"], checkpoint["deadline"], false, stop,
    checkpoint["conflict_budget"], checkpoint["conflict_limit"], checkpoint["conflict_slot"], checkpoint)
  checkpoint["result"] = result
  checkpoint["finished"] = true unless result["stopped"]
  checkpoint["finished"] = true if checkpoint["deadline"] > 0 && clock_ms() >= checkpoint["deadline"]
  wassat_cone_checkpoint_release(checkpoint) if checkpoint["finished"]
  result

# Explicit disposal is also available when a coordinator abandons an unfinished
# checkpoint after another arm wins. Round slices must retain their storage.
-> wassat_cone_checkpoint_release(checkpoint)
  return 0 if checkpoint["storage_released"] == true
  wassat_cone_retry_release(checkpoint["workspace"]) if checkpoint["ready"]
  checkpoint["storage_released"] = true
  checkpoint["finished"] = true
  0

-> wassat_cone_slice_done(checkpoint, result)
  checkpoint != nil && checkpoint["slice_end"] > 0 && result["queries"] >= checkpoint["slice_end"]

-> wassat_cone_search(formula, max_conflicts = 1000000, deadline = 0, refine = false, stop = nil, conflict_budget = nil, conflict_limit = 0, conflict_slot = 0, checkpoint = nil)
  raise "refined cone search does not support round checkpoints" if refine && checkpoint != nil
  resuming = checkpoint != nil && checkpoint["ready"] == true
  stream = checkpoint != nil && checkpoint["stream_refinement"] == true
  if stream && (resuming || checkpoint["slice_end"] > 0)
    raise "streamed refinement does not support round checkpoints"
  miss = { "recognized": false, "status": 0, "stopped": false,
    "conflicts": 0, "decisions": 0, "props": 0, "drat_text": "",
    "nominees": 0, "internal_proved": 0, "unresolved": 0,
    "refinements": 0, "counterexamples": 0, "queries": 0,
    "separated": 0, "different_skipped": 0, "stages": [] }
  return miss if max_conflicts <= 0
  if resuming
    miss = checkpoint["result"]
    miss["stopped"] = false
    decoded = checkpoint["decoded"]; nominees = checkpoint["nominees"]
    aliases = checkpoint["aliases"]; workspace = checkpoint["workspace"]; proof = checkpoint["proof"]
  else
    decoded = wassat_cone_decode(formula, deadline, stop)
    unless decoded["recognized"]
      miss["stopped"] = decoded["stopped"]
      return miss
    miss["recognized"] = true
    miss["unresolved"] = decoded["comparisons"].size
    nominees = refine || stream ? wassat_cone_sim_candidates(decoded, 32, deadline, 16, stop) : wassat_cone_sim_candidates(decoded, 16, deadline, 0, stop)
    unless nominees["recognized"]
      miss["stopped"] = nominees["stopped"]
      return miss
    miss["nominees"] = nominees["count"]
    aliases = i64[decoded["nvars"] + 1]
    workspace = wassat_cone_workspace(decoded, 16384)
    workspace["decimal_lift"] = checkpoint == nil || checkpoint["decimal_lift"] != false
    if checkpoint != nil && checkpoint["profile_queries"] == true
      workspace["query_profile"] = i64[24]
    if checkpoint != nil && checkpoint["retain_output_queries"] == true
      retention = checkpoint["retention_bytes"]
      # With a byte reservation, the four output passes bound the number of
      # distinct retry keys. Research callers without one keep the old slot cap.
      slots = retention == nil ? 1024 : 4 * decoded["comparisons"].size
      workspace["retry_cache"] = wassat_cone_retry_cache(slots, retention)
    if conflict_budget != nil
      raise "cone conflict budget needs a positive limit" if conflict_limit <= 0
      raise "cone conflict slot is outside the shared budget" if conflict_slot <= 0 || conflict_slot >= conflict_budget.size
      workspace["conflict_budget"] = conflict_budget
      workspace["conflict_limit"] = conflict_limit
      workspace["conflict_slot"] = conflict_slot
    proof = StringBuffer()
    if checkpoint != nil
      checkpoint["decoded"] = decoded; checkpoint["nominees"] = nominees
      checkpoint["aliases"] = aliases; checkpoint["workspace"] = workspace; checkpoint["proof"] = proof
      checkpoint["result"] = miss; checkpoint["ready"] = true
  if stream
    stage_ms = clock_ms()
    batch = checkpoint["stream_batch"] == nil ? 64 : checkpoint["stream_batch"]
    ok = wassat_cone_streamed_round(decoded, aliases, workspace, nominees, proof, miss, max_conflicts, deadline, stop, batch)
    miss["refinements"] = nominees["refinements"]; miss["counterexamples"] = nominees["counterexamples"]
    checkpoint["internal_done"] = true
    miss["stages"].push({ "kind": "streamed", "budget": 128,
      "ms": clock_ms() - stage_ms, "conflicts": miss["conflicts"],
      "queries": miss["queries"], "separated": miss["separated"],
      "proved": miss["internal_proved"], "refinements": miss["refinements"] })
    wassat_cone_profile_stage(workspace, miss["stages"][miss["stages"].size - 1])
    unless ok
      miss["stopped"] = true
      return miss
  elsif refine
    nominees["different"] = i64[nominees["table"].size]
    for_budget = [2, 16, 128]
    stage = 0
    while stage < for_budget.size && miss["conflicts"] < max_conflicts
      stage_ms = clock_ms()
      ok = wassat_cone_refined_round(decoded, aliases, workspace, nominees, proof, miss, max_conflicts, deadline, for_budget[stage], stop)
      miss["refinements"] = nominees["refinements"]
      miss["counterexamples"] = nominees["counterexamples"]
      miss["stages"].push({ "kind": "internal", "budget": for_budget[stage],
        "ms": clock_ms() - stage_ms, "conflicts": miss["conflicts"],
        "queries": miss["queries"], "separated": miss["separated"],
        "proved": miss["internal_proved"], "refinements": miss["refinements"],
        "different_skipped": miss["different_skipped"] })
      unless ok
        miss["stopped"] = true
        return miss
      stage += 1
    miss["refinements"] = nominees["refinements"]
    miss["counterexamples"] = nominees["counterexamples"]
  elsif checkpoint == nil || checkpoint["internal_done"] != true
    stage_ms = clock_ms()
    i = checkpoint == nil ? 0 : checkpoint["internal_index"]
    while i < nominees["count"] && miss["conflicts"] < max_conflicts
      break if wassat_cone_stopped(stop, deadline) || wassat_cone_slice_done(checkpoint, miss)
      y = nominees["left"][i]
      rhs = nominees["right"][i]
      cap = max_conflicts - miss["conflicts"]
      cap = 128 if cap > 128
      cap = wassat_cone_budget_left(workspace, cap)
      break if cap <= 0
      result = wassat_cone_prove(decoded, aliases, workspace, y, rhs, cap, deadline, false, stop)
      miss["queries"] += 1
      miss["separated"] += 1 if result["separated"]
      miss["conflicts"] += result["conflicts"]
      miss["decisions"] += result["decisions"]
      miss["props"] += result["props"]
      break if wassat_cone_stopped(stop, deadline)
      if result["equivalent"]
        aliases[y] = rhs
        miss["internal_proved"] += 1
        result["drat"].each -> (line)
          proof.append(line)
          proof.append("\n")
      i += 1
    if checkpoint != nil
      checkpoint["internal_index"] = i
      checkpoint["internal_done"] = i >= nominees["count"]
    miss["stages"].push({ "kind": "internal", "budget": 128,
      "ms": clock_ms() - stage_ms, "conflicts": miss["conflicts"],
      "queries": miss["queries"], "separated": miss["separated"],
      "proved": miss["internal_proved"], "refinements": 0 })
    wassat_cone_profile_stage(workspace, miss["stages"][miss["stages"].size - 1])
    if wassat_cone_stopped(stop, deadline) || wassat_cone_slice_done(checkpoint, miss)
      miss["stopped"] = true
      return miss
  budgets = [128, 512, 4096, 32768]
  workspace["retry_active"] = true if workspace["retry_cache"] != nil
  round = checkpoint == nil ? 0 : checkpoint["round"]
  while round < budgets.size && miss["conflicts"] < max_conflicts
    break if wassat_cone_stopped(stop, deadline)
    budget = budgets[round]
    stage_ms = clock_ms()
    i = checkpoint == nil ? 0 : checkpoint["output_index"]
    while i < decoded["comparisons"].size && miss["conflicts"] < max_conflicts
      break if wassat_cone_stopped(stop, deadline) || wassat_cone_slice_done(checkpoint, miss)
      cmp = decoded["comparisons"][i]
      a = wassat_cone_representative(cmp[3], aliases)
      b = wassat_cone_representative(cmp[4], aliases)
      if a != b
        av = wassat_cone_abs(a)
        bv = wassat_cone_abs(b)
        y = av > bv ? av : bv
        rhs = av > bv ? bv : av
        rhs = 0 - rhs if (a < 0) != (b < 0)
        cap = max_conflicts - miss["conflicts"]
        cap = budget if cap > budget
        cap = wassat_cone_budget_left(workspace, cap)
        break if cap <= 0
        result = wassat_cone_prove(decoded, aliases, workspace, y, rhs, cap, deadline, false, stop)
        miss["queries"] += 1
        miss["separated"] += 1 if result["separated"]
        miss["conflicts"] += result["conflicts"]
        miss["decisions"] += result["decisions"]
        miss["props"] += result["props"]
        break if wassat_cone_stopped(stop, deadline)
        if result["equivalent"]
          aliases[y] = rhs
          result["drat"].each -> (line)
            proof.append(line)
            proof.append("\n")
      i += 1
    miss["stages"].push({ "kind": "output", "budget": budget,
      "ms": clock_ms() - stage_ms, "conflicts": miss["conflicts"],
      "queries": miss["queries"], "separated": miss["separated"],
      "proved": miss["internal_proved"], "refinements": miss["refinements"] })
    wassat_cone_profile_stage(workspace, miss["stages"][miss["stages"].size - 1])
    if checkpoint != nil
      checkpoint["output_index"] = i
      checkpoint["round"] = round
    if wassat_cone_stopped(stop, deadline) || wassat_cone_slice_done(checkpoint, miss)
      miss["stopped"] = true
      return miss
    round += 1
    if checkpoint != nil
      checkpoint["round"] = round
      checkpoint["output_index"] = 0
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  unresolved = 0
  tail = StringBuffer()
  decoded["comparisons"].each -> (cmp)
    a = wassat_cone_representative(cmp[3], aliases)
    b = wassat_cone_representative(cmp[4], aliases)
    if a != b
      unresolved += 1
    else
      # The original gadget is a=>p&~q, b=>~p&q, (c|a|b).
      # Equal p,q therefore justify these three original-variable RUP units.
      tail.append("[0 - cmp[1]] 0\n[0 - cmp[2]] 0\n[cmp[0]] 0\n")
  miss["unresolved"] = unresolved
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  if unresolved == 0
    # The checked reduction tree and its negative root assertion now refute
    # by unit propagation, independently of the simulation signatures.
    proof.append(tail.to_s)
    proof.append("0\n")
    miss["status"] = -1
    miss["drat_text"] = proof.to_s
  elsif wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
  miss

-> wassat_cone_profile_stage(workspace, stage)
  profile = workspace["query_profile"]
  if profile != nil
    snapshot = []
    i = 0
    while i < profile.size
      snapshot.push(profile[i]); i += 1
    stage["query_profile"] = snapshot
  0
