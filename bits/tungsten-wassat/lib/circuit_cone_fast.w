# The portfolio owns a private stop cell for each round and joins this boxed
# worker before scoring/reallocation. The checkpoint retains proved aliases,
# proof steps and exact conflict charges; only an interrupted query is retried.

use circuit_cone_search

-> wassat_cone_fast_bytes(nv)
  wassat_cone_memory_bytes(nv)

-> wassat_cone_fast_plan(formula, window_ms = 45000, retention_bytes = 0)
  raise "negative cone retention reservation" if retention_bytes < 0
  return nil if window_ms <= 0 || !wassat_cone_candidate(formula)
  { "state": nil, "slices": 0,
    "scratch": wassat_cone_fast_bytes(formula["nvars"]) + retention_bytes,
    "retain_output_queries": retention_bytes > 0, "retention_bytes": retention_bytes,
    "deadline": 0, "window_ms": window_ms }

-> wassat_cone_fast_arm(plan, local_stop, stop, res, base, nv)
  res[base + nv + 6] = clock_ms()
  result = wassat_cone_resume(plan["state"], local_stop)
  res[base + nv + 4] = result["conflicts"]
  res[base + nv + 5] = clock_ms()
  if result["status"] == -1 && !wassat_stop_requested?(local_stop) && !wassat_stop_requested?(stop)
    res[base] = -1
    z = wassat_stop_publish(stop, -1)
  # Preserve diagnostics even if an unrelated arm continues beyond this phase.
  wassat_cone_fast_profile(plan) if env("WASSAT_CONE_PROFILE_QUERIES") == "1"
  0

-> wassat_cone_fast_profile(plan)
  state = plan["state"]
  result = state["result"]
  return 0 if result == nil
  wassat_prof_note("race.comparison_cones elapsed_ms=[clock_ms() - plan["deadline"] + plan["window_ms"]] stopped=[result["stopped"]] slices=[plan["slices"]] finished=[state["finished"]] recognized=[result["recognized"]] status=[result["status"]] nominees=[result["nominees"]] aliases=[result["internal_proved"]] unresolved=[result["unresolved"]] unresolved_measured=[result["recognized"] && !result["stopped"]] conflicts=[result["conflicts"]] queries=[result["queries"]]")
  if env("WASSAT_PROFILE") == "1"
    cache = state["ready"] == true ? state["workspace"]["retry_cache"] : nil
    if cache != nil
      wassat_prof_note("race.comparison_cones.retention reservation=[cache["max_bytes"]] peak_bytes=[cache["peak_bytes"]] resident_bytes=[cache["bytes"]] declined=[cache["declined"]] hits=[cache["hits"]] peak_entries=[cache["peak"]]")
    result["stages"].each -> (stage)
      wassat_prof_note("race.comparison_cones.stage [stage]")
  0
