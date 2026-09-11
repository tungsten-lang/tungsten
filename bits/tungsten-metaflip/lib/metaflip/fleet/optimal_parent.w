# A bounded native parent visit for <2,2,2>: enumerate GL(2,2)^3 instead of
# attempting rank six. All 216 codes enter the existing full-tensor/dedup
# boundary, yielding 36 literal representations. Durable refinement tickets
# cache them across visits while the existing composition queue drains.
# No general classification theorem is inferred.
use refinement
use ../strategies/global_isotropy
use ../tui

-> ffop_candidate(base, code, state, us, vs, ws, capacity) (i64[] i64 i64[] i64[] i64[] i64[] i64) i64
  if code < 0 || code >= 216 || ffw_n(base) != 2 || ffw_best_rank(base) != 7
    return 0
  i = 0 ## i64
  while i < 7
    us[i] = ffw_read_best_u(base,i)
    vs[i] = ffw_read_best_v(base,i)
    ws[i] = ffw_read_best_w(base,i)
    i += 1
  word = code ## i64
  axis = 0 ## i64
  while axis < 3
    action = word % 6 ## i64
    word /= 6
    length = 0 ## i64
    if action == 1 || action == 2
      length = 1
    if action == 3 || action == 4
      length = 2
    if action == 5
      length = 3
    k = 0 ## i64
    while k < length
      source = k % 2 ## i64
      if action == 2 || action == 4
        source = 1-source
      if ffgir_apply_generator(us,vs,ws,7,2,1,axis,source,1-source) != 7
        return 0
      k += 1
    axis += 1
  if ffw_init_terms_cap(state,us,vs,ws,7,2,capacity,17+code,0,1,1,1) != 7
    return 0
  ffw_verify_best_exact(state,2)

-> ffop_run(base, best, runtime, status_path, best_path, seconds, deadline, fields, caption, tui, quiet) (i64[] i64[] String String String i64 i64 String String i64 i64) i64
  root = status_path + ".refinement"
  refinement = MetaflipRefinement.new(root,System.executable_path(),runtime)
  capacity = ffw_default_capacity(2) ## i64
  candidate = i64[ffw_state_size(capacity)]
  output = i64[ffw_state_size(capacity)]
  us = i64[7]
  vs = i64[7]
  ws = i64[7]
  cursor = 0 ## i64
  stopped = 0 ## i64
  failed = 0 ## i64
  sequence = 0 ## i64
  start = ccall("__w_clock_ms") ## i64
  last_status = 0 ## i64
  z = ccall("__w_trap_interrupts")
  if tui != 0
    z = ccall("w_term_raw_enable")
  running = 1 ## i64
  while running != 0
    now = ccall("__w_clock_ms") ## i64
    key = ccall("w_input_poll",0) ## i64
    if key == 3 || key == 113 || key == 81 || ccall("__w_interrupted") != 0
      stopped = 1
      running = 0
    if (seconds > 0 && now-start >= seconds*1000) || (deadline > 0 && now >= deadline)
      running = 0
    if running != 0
      batch = 0 ## i64
      while cursor < 216 && batch < 8
        if ffop_candidate(base,cursor,candidate,us,vs,ws,capacity) != 1 || refinement.submit(candidate,2,2,2) < 0
          failed = 1
          running = 0
          break
        cursor += 1
        batch += 1
      z = refinement.poll(now)
      z = refinement.take_into(output,2,2,2,capacity,17,0,1,1,1)
      z = refinement.take_feedback(output,2,2,2,capacity,17,0,1,1,1)
    if running == 0
      if refinement.stop() != 1
        failed = 1
    if now-last_status >= 200 || running == 0
      state = "LIVE"
      if running == 0
        state = "DONE"
      body = "schema=1 mode=optimal-parent producer_state=" + state + " tensor=2x2 sequence=" + sequence.to_s()
      body = body + " best_rank=7 target=7 record=7 record_known=1 wr_status=ties cpu_lanes=0 gpu_requested=0 gpu_ready=0 flips=0 exact_rejects=" + failed.to_s()
      body = body + " orbit_codes=" + cursor.to_s() + " orbit_total=216 stop_requested=" + stopped.to_s()
      body = body + fields + refinement.status_fields() + "\n"
      if ffrf_atomic(status_path,body,"optimal-parent") != 1
        failed = 1
        running = 0
      if tui != 0
        << "\e[?2026h\e[H" + ff_tui_bold("MetaFlip | 2x2 composition parents — rank 7 is proved optimal") + "\e[K\n" + caption + "\e[K\nGL(2,2)^3 codes " + cursor.to_s() + "/216; full-identity cached refinement, no rank-drop workers\e[K\n" + refinement.status_row() + "\e[K\nq/Ctrl-C stops the cycle\e[K\n\e[J\e[?2026l"
        flush()
      last_status = now
      sequence += 1
    if running != 0
      z = ccall("__w_sleep_ms",10)
  z = refinement.stop()
  z = ccall("w_term_raw_disable")
  body = ffw_view_text(best,best[47],best[48],best[49],0-1,ffw_best_rank(best))
  if ffrf_atomic(best_path,body,"optimal-parent") != 1 || failed != 0
    return 2
  if quiet == 0
    << "metaflip parent done: tensor=2x2 orbit_codes=" + cursor.to_s() + " refine_submitted=" + refinement.submitted.to_s() + " (verified cached parents, no rank-record claim)"
  if stopped != 0
    return 1
  0
