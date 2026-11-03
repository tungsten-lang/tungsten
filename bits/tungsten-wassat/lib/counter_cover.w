# Search over selections hidden behind signed aliases and binary adder trees.
# All structure is inferred from the current input. This worker is SAT-only:
# each proposal is lifted through the recovered gates and every original
# clause must pass before its complete model is published.
use counter_cover/search

# Metrics: 0 stop (cancel/deadline/work), 1 polls, 2 deadline, 3 decode work,
# 4 aliases, 5 inputs, 6 XORs, 7 scans, 8 adder steps, 9 output bits,
# 10 target count, 11 cover rows, 12 incidence entries, 13/14/15 decode/search/
# replay ms, 16 checked original clauses, 17 model found, 18 total run ms,
# 20 swaps, 21 best uncovered rows, 22 starts, 23 incidence work, 24 next poll,
# 25 arm elapsed ms, 26 published model, 27 actual row-term visits,
# 28 changed-item incidence visits. Cell 23 is a conservative work charge.
# All arrays are fixed and reused.
-> wassat_counter_cover_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_COUNTER_COVER")
  return nil if mode == "0" || System.cpu_count <= workers || wassat_race_round1_conflicts != 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 1 || nv > 100000 || nc < 1 || nc > 500000 || nl < 1 || nl > 2000000
  # A bounded distribution screen only controls admission. Full decoding and
  # every large allocation happen concurrently inside the optional worker.
  if mode != "1"
    return nil if nv < 256 || nc < 1000
    lens = formula["flat_lens"]; return nil if lens.size < nc
    binary = 0; ternary = 0; quad = 0; wide = 0; i = 0
    while i < 256
      n = lens[i * nc / 256]
      binary += 1 if n == 2; ternary += 1 if n == 3
      quad += 1 if n == 4; wide += 1 if n >= 5
      i += 1
    return nil if binary < 4 || ternary < 16 || quad < 16 || wide == 0
  scratch = 268435456 + 64 * (nv + 1) + 64 * nc + 16 * nl
  return nil unless wassat_race_memory_fits?(formula, cdcl, sls, pre, extra + scratch)
  {"counter_cover": true, "meta": i64[64], "scratch": scratch}

-> wassat_counter_cover_arm(formula, m, stop, res, base, nv)
  started = clock_ms(); res[base + nv + 6] = started
  model = wassat_counter_cover_run(formula, m, stop, started + 2000)
  if model != nil && !wassat_stop_requested?(stop)
    v = 1
    while v <= nv
      break if (v & 1023) == 0 && wassat_stop_requested?(stop)
      res[base + v] = model[v]; v += 1
    unless wassat_stop_requested?(stop)
      res[base + nv + 5] = clock_ms()
      m[26] = 1
      z = ccall("__w_arr_store_rel", res, base, 1)
      z = wassat_stop_publish(stop, 1)
  res[base + nv + 5] = clock_ms(); m[25] = res[base + nv + 5] - started
  0

-> wassat_counter_cover_profile(m, label = "race.counter_cover")
  wassat_prof_note("[label] result=[m[17]] published=[m[26]] ms=[m[25]] inputs=[m[5]] rows=[m[11]] target=[m[10]] aliases=[m[4]] xors=[m[6]] adders=[m[8]] decode_work=[m[3]] swaps=[m[20]] best_uncovered=[m[21]] starts=[m[22]] incidence_work=[m[23]] term_visits=[m[27]] item_visits=[m[28]] original_clauses=[m[16]] decode_ms=[m[13]] search_ms=[m[14]] replay_ms=[m[15]] stop=[m[0]] polls=[m[1]]")
