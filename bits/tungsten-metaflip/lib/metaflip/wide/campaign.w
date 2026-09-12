use seeds
use ../rect/campaign

-> ffws_thread(st, scratch, steps, stop, slack)
  Thread.new ->
    z = ffws_work(st,scratch,steps,stop,slack)
    true

-> ffws_bits(data, count) (i64[] i64) i64
  result = 0 ## i64
  i = 0 ## i64
  while i < count
    result += popcount(data[i])
    i += 1
  result

-> ffws_checked_load(path, data, words, n, parity) (String i64[] i64 i64 i64[]) i64
  raw = File.read_prefix(path,12632129)
  if raw == nil
    return 0
  meta = i64[4]
  rank = ffpk_parse(raw,data,words,meta,4) ## i64
  if rank < 1 || meta[0] != n || meta[1] != n || meta[2] != n
    return 0-1
  if ffpk_exact(data,words,rank,n,n,n,parity,n*n*ffpk_stride(n,n,n),0) != 1
    return 0-1
  rank

# Large factors have no current Metal kernel. Keep GPU capability explicit;
# every requested CPU lane gets a private state and scratch. Checkpoints use
# MFW1, never truncated integer masks. Only the coordinator writes them.
-> ffws_run(n, root, seed_path, best_path, status_path, workers, steps, rounds, seconds, naive, nonce, slack, quiet, tui, gpu, cycle_fields, cycle_caption, cycle_deadline) (i64 String String String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 String String i64) i64
  start = ccall("__w_clock_ms") ## i64
  stride = ffpk_stride(n,n,n) ## i64
  words = 8192*3*stride ## i64
  best = i64[words]
  trial = i64[words]
  parity = i64[n*n*stride]
  rank = 0 ## i64
  if seed_path != ""
    rank = ffws_checked_load(seed_path,best,words,n,parity)
  else
    rank = ffws_seed(best,n,root,naive)
  if rank < 1 || rank > 8190 || ffpk_exact(best,words,rank,n,n,n,parity,n*n*stride,0) != 1
    << "metaflip: large-square seed failed full tensor verification"
    return 2
  durable = ffws_checked_load(best_path,trial,words,n,parity) ## i64
  if durable < 0
    << "metaflip: invalid large-square checkpoint; refusing to overwrite it: " + best_path
    return 2
  if durable > 0 && naive == 0 && (durable < rank || (durable == rank && ffws_bits(trial,durable*3*stride) < ffws_bits(best,rank*3*stride)))
    rank = durable
    i = 0 ## i64
    while i < rank*3*stride
      best[i]=trial[i]
      i += 1
  density = ffws_bits(best,rank*3*stride) ## i64
  cap = rank+64 ## i64
  if cap > 8192
    cap = 8192
  states = []
  scratch = []
  lane = 0 ## i64
  while lane < workers
    state = i64[ffws_words(n,cap)]
    if ffws_init(state,n,cap,best,rank,19071+nonce+lane*104729) != 1
      return 2
    states.push(state)
    scratch.push(i64[12*stride])
    lane += 1
  # --naive changes the starting workers, never regresses a durable result.
  if durable > 0 && (durable < rank || (durable == rank && ffws_bits(trial,durable*3*stride) < density))
    rank = durable
    density = ffws_bits(trial,rank*3*stride)
    i = 0 ## i64
    while i < rank*3*stride
      best[i] = trial[i]
      i += 1
  if ffrf_atomic(best_path,ffpk_blob(best,rank,n,n,n),"wide") != 1
    << "metaflip: cannot write large-square checkpoint"
    return 2
  stop = i64[1]
  stop_requested = 0 ## i64
  next_requested = 0 ## i64
  failure = 0 ## i64
  round = 0 ## i64
  moves = 0 ## i64
  last_render = 0 ## i64
  tensor = n.to_s()+"x"+n.to_s()
  if tui != 0
    z = ccall("w_term_raw_enable")
    << "\e[2J\e[H"
  elsif quiet == 0
    << "metaflip wide: tensor="+tensor+" backend=packed-cpu cpu_lanes="+workers.to_s()+" gpu_supported=0 seed_rank="+rank.to_s()
  while round < rounds && stop[0] == 0
    now = ccall("__w_clock_ms") ## i64
    if (seconds > 0 && now-start >= seconds*1000) || (cycle_deadline > 0 && now >= cycle_deadline) || ccall("__w_interrupted") != 0
      break
    threads = []
    lane = 0
    while lane < workers
      threads.push(ffws_thread(states[lane],scratch[lane],steps,stop,slack))
      lane += 1
    alive = 1 ## i64
    while alive != 0
      alive = 0
      lane = 0
      while lane < workers
        if threads[lane].alive?
          alive = 1
        lane += 1
      now = ccall("__w_clock_ms")
      if ccall("__w_interrupted") != 0
        stop_requested = 1
        stop[0]=1
      if tui != 0
        key = ccall("w_input_poll",0) ## i64
        if key == 3 || key == 113 || key == 81
          stop_requested=1
          stop[0]=1
        if key == 110 || key == 78
          next_requested=1
          stop[0]=1
      if (seconds > 0 && now-start >= seconds*1000) || (cycle_deadline > 0 && now >= cycle_deadline)
        stop[0]=1
      if now-last_render >= 1000
        last_render=now
        status = "mode=wide-cpu tensor="+tensor+" backend=packed-cpu rank="+rank.to_s()+" bits="+density.to_s()+" cpu_lanes="+workers.to_s()+" cpu_moves="+moves.to_s()+" gpu_requested="+gpu.to_s()+" gpu_supported=0 gpu_moves=0 round="+round.to_s()+" producer_state=running stop_requested="+stop_requested.to_s()+cycle_fields+"\n"
        if ffrf_atomic(status_path,status,"wide") != 1
          failure=1
          stop[0]=1
        if tui != 0
          rows=["  "+ff_tui_paint("METAFLIP  "+tensor+"  packed CPU islands","1;36"),"", "  rank "+rank.to_s()+"  density "+density.to_s()+"  lanes "+workers.to_s(),"  CPU flips "+moves.to_s()+"  rounds "+round.to_s(),"  GPU: unavailable for multiword square factors", "  "+cycle_caption,"", "  n = next shape   q / Ctrl-C = checkpoint and stop"]
          z = ffrc_render(rows)
        elsif quiet == 0
          << "WIDE_STATUS "+status.strip()
      if alive != 0
        z = ccall("__w_sleep_ms",5)
    lane = 0
    moves=0
    changed=0 ## i64
    while lane < workers
      joined=ffrc_thread_join_release(threads[lane])
      state=states[lane]
      moves += state[7]
      if state[5] < rank || (state[5] == rank && state[11] < density)
        proposed=ffws_export(state,trial,1) ## i64
        proposed=ffpk_canonicalize(trial,words,proposed,stride)
        if proposed < 1 || ffpk_exact(trial,words,proposed,n,n,n,parity,n*n*stride,0) != 1
          failure=1
          stop[0]=1
        else
          rank=proposed
          density=0
          i=0
          while i < rank*3*stride
            best[i]=trial[i]
            density += popcount(trial[i])
            i += 1
          changed=1
      lane += 1
    if changed != 0 && ffrf_atomic(best_path,ffpk_blob(best,rank,n,n,n),"wide") != 1
      failure=1
      stop[0]=1
    round += 1
  if ccall("__w_interrupted") != 0
    stop_requested=1
  if tui != 0
    z=ccall("w_term_raw_disable")
  status="mode=wide-cpu tensor="+tensor+" backend=packed-cpu rank="+rank.to_s()+" bits="+density.to_s()+" cpu_lanes="+workers.to_s()+" cpu_moves="+moves.to_s()+" gpu_supported=0 gpu_moves=0 round="+round.to_s()+" producer_state=stopped stop_requested="+stop_requested.to_s()+" next_requested="+next_requested.to_s()+" exact_rejects="+failure.to_s()+cycle_fields+"\n"
  if ffrf_atomic(status_path,status,"wide") != 1
    failure=1
  if quiet == 0
    << "WIDE_RESULT "+status.strip()
  if failure != 0
    return 2
  0
