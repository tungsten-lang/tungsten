# Durable, machine-readable provenance for the current square-fleet best.
#
# The coordinator keeps one fixed-width i64 record and two bounded tokens
# (source and strategy).  The record is copied into the ordinary status line
# and an atomic `<best>.provenance` sidecar whenever a new exact best is
# persisted.  Numeric fields deliberately retain enough launch/restart state
# to audit a discovery without putting variable-sized strings in worker state.
#
# Record layout:
#   0 kind             0 seed, 1 recovered, 2 CPU, 3 GPU, 4 rect compose,
#                      5 late GPU, 6 late rect compose,
#                      7 global-isotropy postprocessor
#   1 worker           CPU island or GPU slot (-1 when not applicable)
#   2 strategy         CPU door, GPU role, or rectangular component
#   3 mode             CPU zone or GPU pool mode (-1 when not applicable)
#   4 round            coordinator round
#   5 replay           CPU worker moves / GPU launch nonce /
#                      rectangular composition attempt / postprocessor seed
#   6 parent_id        canonical identity of the launched/seed state
#   7 parent_rank
#   8 parent_bits
#   9 debt             parent rank minus then-current fleet rank
#  10 basin_id         CPU basin id at adoption (-1 for non-CPU events)
#  11 parent_distance  adopted/preprocessed scheme's symmetric term distance
#                      from the incumbent or parent (-1 when not measured)
#  12 best_id          canonical identity of the adopted exact scheme
#  13 best_rank
#  14 best_bits
#  15 elapsed_s

-> fflp_size() i64
  16

-> fflp_kind_name(kind) (i64)
  if kind == 0
    return "seed"
  if kind == 1
    return "recovered"
  if kind == 2
    return "cpu"
  if kind == 3
    return "gpu"
  if kind == 4
    return "rect-compose"
  if kind == 5
    return "late-gpu"
  if kind == 6
    return "late-rect-compose"
  if kind == 7
    return "global-isotropy"
  "unknown"

# Status values are separated by literal ASCII spaces.  Refuse to let a
# human-facing source label inject another key or line, and cap retained text
# so a malformed/unexpected label cannot grow the heartbeat indefinitely.
-> fflp_token(text, limit) (String i64)
  capped = limit ## i64
  if capped < 1
    return "unknown"
  if capped > 128
    capped = 128
  safe = text.replace(" ", "_").replace("\t", "_").replace("\n", "_").replace("\r", "_").replace("=", "_")
  if safe == ""
    safe = "unknown"
  if safe.size() > capped
    safe = safe.slice(0, capped)
  safe

-> fflp_set(meta, kind, worker, strategy, mode, round, nonce, parent_id, parent_rank, parent_bits, debt, basin_id, basin_distance, best_id, best_rank, best_bits, elapsed_s) i64
  if meta.size() < fflp_size()
    return 0
  meta[0] = kind
  meta[1] = worker
  meta[2] = strategy
  meta[3] = mode
  meta[4] = round
  meta[5] = nonce
  meta[6] = parent_id
  meta[7] = parent_rank
  meta[8] = parent_bits
  meta[9] = debt
  meta[10] = basin_id
  meta[11] = basin_distance
  meta[12] = best_id
  meta[13] = best_rank
  meta[14] = best_bits
  meta[15] = elapsed_s
  1

-> fflp_status_fields(meta, source, strategy_name) (i64[] String String)
  if meta.size() < fflp_size()
    return " best_source_kind=unknown best_source=unknown best_strategy=unknown"
  fields = " best_source_kind=" + fflp_kind_name(meta[0])
  fields = fields + " best_source=" + fflp_token(source, 96)
  fields = fields + " best_strategy=" + fflp_token(strategy_name, 64)
  fields = fields + " best_worker=" + meta[1].to_s()
  fields = fields + " best_strategy_code=" + meta[2].to_s() + " best_mode=" + meta[3].to_s()
  fields = fields + " best_round=" + meta[4].to_s() + " best_nonce=" + meta[5].to_s()
  if meta[0] == 2
    fields = fields + " best_worker_moves=" + meta[5].to_s()
  if meta[0] == 3 || meta[0] == 5
    fields = fields + " best_launch_nonce=" + meta[5].to_s()
  if meta[0] == 4 || meta[0] == 6
    fields = fields + " best_compose_attempt=" + meta[5].to_s()
  if meta[0] == 7
    fields = fields + " best_replay_seed=" + meta[5].to_s()
  fields = fields + " best_parent_id=" + meta[6].to_s() + " best_parent_rank=" + meta[7].to_s() + " best_parent_bits=" + meta[8].to_s()
  fields = fields + " best_debt=" + meta[9].to_s() + " best_basin=" + meta[10].to_s() + " best_distance=" + meta[11].to_s()
  fields = fields + " best_id=" + meta[12].to_s() + " best_event_rank=" + meta[13].to_s() + " best_event_bits=" + meta[14].to_s()
  fields = fields + " best_event_elapsed=" + meta[15].to_s()
  fields

-> fflp_event_body(run_tag, n, seed_nonce, meta, source, strategy_name) (String i64 i64 i64[] String String)
  body = "schema=1 event=best_adoption run_tag=" + fflp_token(run_tag, 96)
  body = body + " tensor=" + n.to_s() + "x" + n.to_s() + " cpu_seed_nonce=" + seed_nonce.to_s()
  body = body + fflp_status_fields(meta, source, strategy_name) + "\n"
  body
