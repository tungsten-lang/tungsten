use seeds
use directed
use tui
use ../rect/campaign

-> ffws_thread(st, scratch, steps, stop, slack, elapsed, lane)
  Thread.new ->
    started = ccall("__w_clock_ms") ## i64
    z = ffws_work(st,scratch,steps,stop,slack)
    elapsed[lane] = ccall("__w_clock_ms") - started
    true

-> ffws_directed_thread(st, scratch, context, steps, stop, slack, elapsed, lane)
  Thread.new ->
    started=ccall("__w_clock_ms")
    result=ffwd_work(st,scratch,context,steps,stop,slack)
    if result<1
      context[20]=1
      stop[0]=1
    elapsed[lane]=ccall("__w_clock_ms")-started
    true

-> ffws_directed_fields(contexts, lane, budget)
  if lane<0
    return " directed_lanes=0"
  c=contexts[lane]
  " directed_lanes=1 directed_mode="+c[0].to_s()+" directed_steps="+budget.to_s()+" directed_legal="+c[9].to_s()+" directed_inverse="+c[10].to_s()+" directed_tabu="+c[11].to_s()+" directed_novel_hashes="+c[12].to_s()+" directed_repeat_hashes="+c[13].to_s()+" directed_no_edge="+c[16].to_s()+" directed_escapes="+c[17].to_s()+" directed_resets="+c[18].to_s()

# Large factors have no current Metal kernel. Keep GPU capability explicit;
# every requested CPU lane gets a private state and scratch. Checkpoints use
# MFW1, never truncated integer masks. Only the coordinator writes them.
-> ffws_run(n, root, seed_path, best_path, status_path, workers, steps, rounds, seconds, naive, nonce, slack, quiet, tui, gpu, cycle_fields, cycle_caption, cycle_deadline) (i64 String String String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 String String i64) i64
  directed_mode=0 ## i64
  directed_option=Env.get("METAFLIP_WIDE_DIRECTED")
  if directed_option!=nil && directed_option!="" && directed_option!="0"
    if directed_option=="partners"
      directed_mode=1
    elsif directed_option=="nonbacktracking"
      directed_mode=2
    elsif directed_option=="tabu"
      directed_mode=3
    else
      << "metaflip: METAFLIP_WIDE_DIRECTED must be 0, partners, nonbacktracking, or tabu"
      return 2
  directed_lane=0-1 ## i64
  if directed_mode>0
    directed_lane=workers-1
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
  starts = [best]
  start_ranks = i64[4]
  start_ranks[0]=rank
  if naive == 0 && seed_path == "" && workers > 1
    paths = ffws_packaged_paths(root,n)
    p = 0 ## i64
    while p < paths.size()
      data = i64[words]
      candidate = ffws_checked_load(root+"/"+paths[p],data,words,n,parity) ## i64
      if candidate < 1
        << "metaflip: invalid packaged large-square seed"
        return 2
      z = ffws_bank_add(starts,start_ranks,data,candidate,stride,rank)
      p += 1
    variant = 0 ## i64
    while variant < 3 && starts.size() < 4
      data = i64[words]
      candidate = ffws_composed_seed(data,n,root,0,variant) ## i64
      if candidate < 1 || ffpk_exact(data,words,candidate,n,n,n,parity,n*n*stride,0) != 1
        << "metaflip: invalid composed large-square seed"
        return 2
      z = ffws_bank_add(starts,start_ranks,data,candidate,stride,rank)
      variant += 1
  states = []
  scratch = []
  contexts = []
  lane = 0 ## i64
  while lane < workers
    door = lane % starts.size() ## i64
    seed_rank = start_ranks[door] ## i64
    cap = seed_rank+64 ## i64
    if cap > 8192
      cap=8192
    state = i64[ffws_words(n,cap)]
    if ffws_init(state,n,cap,starts[door],seed_rank,19071+nonce+lane*104729) != 1
      return 2
    states.push(state)
    scratch.push(i64[12*stride])
    if lane==directed_lane
      context=i64[ffwd_words(state,65536)]
      if ffwd_init(state,context,directed_mode,65536)!=1
        return 2
      contexts.push(context)
    else
      contexts.push(i64[1])
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
  # Only joined workers feed the presentation snapshots. The render path
  # never races a worker mutating its packed tensor, ranks or counters.
  lanes = i64[workers*9]
  worker_elapsed = i64[workers]
  lane = 0
  while lane < workers
    state = states[lane]
    lanes[lane*9] = state[5]
    lanes[lane*9+1] = state[4]
    lanes[lane*9+3] = 0-1
    lanes[lane*9+4] = start
    lanes[lane*9+5] = start
    lanes[lane*9+6] = state[11]
    lane += 1
  rank_levels = i64[256]
  rank_ticks = i64[256]
  bits_levels = i64[256]
  bits_ticks = i64[256]
  rank_count = 0 ## i64
  bits_count = 0 ## i64
  timeline_times = i64[256]
  timeline_ranks = i64[256]
  timeline_count = ffrc_timeline_push(timeline_times,timeline_ranks,0,0,rank) ## i64
  drops = 0 ## i64
  ties = 0 ## i64
  accepted = 0 ## i64
  rejected = 0 ## i64
  sequence = 0 ## i64
  last_status = 0-1 ## i64
  stop_requested = 0 ## i64
  next_requested = 0 ## i64
  failure = 0 ## i64
  round = 0 ## i64
  moves = 0 ## i64
  last_render = 0 ## i64
  directed_steps=steps ## i64
  if workers>1
    directed_steps=steps / 32
    if directed_steps<1
      directed_steps=1
  directed_fields=ffws_directed_fields(contexts,directed_lane,directed_steps)
  directed_caption=""
  if directed_lane>=0
    directed_caption=" directed w"+directed_lane.to_s()+"="+directed_option
  tensor = n.to_s()+"x"+n.to_s()
  seed_fields = " seed_count="+starts.size().to_s()+" reference_rank="+ffws_reference_rank(n).to_s()
  if tui != 0
    z = ccall("w_term_raw_enable")
    << "\e[2J\e[H"
  elsif quiet == 0
    << "metaflip wide: tensor="+tensor+" backend=packed-cpu cpu_lanes="+workers.to_s()+" gpu_supported=0 best_rank="+rank.to_s()+seed_fields+directed_fields
  while round < rounds && stop[0] == 0
    now = ccall("__w_clock_ms") ## i64
    if (seconds > 0 && now-start >= seconds*1000) || (cycle_deadline > 0 && now >= cycle_deadline) || ccall("__w_interrupted") != 0
      break
    threads = []
    lane = 0
    while lane < workers
      if lane==directed_lane
        threads.push(ffws_directed_thread(states[lane],scratch[lane],contexts[lane],directed_steps,stop,slack,worker_elapsed,lane))
      else
        threads.push(ffws_thread(states[lane],scratch[lane],steps,stop,slack,worker_elapsed,lane))
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
        sequence += 1
        status = "mode=wide-cpu tensor="+tensor+" backend=packed-cpu rank="+rank.to_s()+" bits="+density.to_s()+" cpu_lanes="+workers.to_s()+" cpu_moves="+moves.to_s()+" gpu_requested="+gpu.to_s()+" gpu_supported=0 gpu_moves=0 round="+round.to_s()+" producer_state=running stop_requested="+stop_requested.to_s()+seed_fields+directed_fields+cycle_fields+"\n"
        if ffrf_atomic(status_path,status,"wide") != 1
          failure=1
          stop[0]=1
        else
          last_status=now
        if tui != 0
          rank_count=ffrc_level_push(rank_levels,rank_ticks,rank_count,rank)
          bits_count=ffrc_level_push(bits_levels,bits_ticks,bits_count,density)
          width=ccall("w_term_cols") ## i64
          if width < 40
            width=40
          rows=ffws_frame_rows(n,rank,density,moves,workers,round,(now-start) / 1000,gpu,failure,sequence,last_status,now,drops,ties,accepted,rejected,slack,lanes,rank_levels,rank_ticks,rank_count,bits_levels,bits_ticks,bits_count,timeline_times,timeline_ranks,timeline_count,cycle_caption+directed_caption,width,ffws_reference_rank(n),starts.size())
          z = ffrc_render(rows)
        elsif quiet == 0
          << "WIDE_STATUS "+status.strip()
      if alive != 0
        z = ccall("__w_sleep_ms",5)
    lane = 0
    moves=0
    accepted=0
    rejected=0
    changed=0 ## i64
    while lane < workers
      joined=ffrc_thread_join_release(threads[lane])
      state=states[lane]
      moves += state[7]
      accepted += state[8]
      rejected += state[9]
      at=lane*9 ## i64
      duration=worker_elapsed[lane] ## i64
      if duration < 1
        duration=1
      lanes[at+3]=(state[7]-lanes[at+2])*1000 / duration
      now=ccall("__w_clock_ms")
      if state[5] < lanes[at] || (state[5] == lanes[at] && state[11] < lanes[at+6])
        lanes[at+4]=now
      lanes[at]=state[5]
      lanes[at+1]=state[4]
      lanes[at+2]=state[7]
      lanes[at+5]=now
      lanes[at+6]=state[11]
      lanes[at+7]=state[8]
      lanes[at+8]=state[9]
      if state[5] < rank || (state[5] == rank && state[11] < density)
        proposed=ffws_export(state,trial,1) ## i64
        proposed=ffpk_canonicalize(trial,words,proposed,stride)
        if proposed < 1 || ffpk_exact(trial,words,proposed,n,n,n,parity,n*n*stride,0) != 1
          failure=1
          stop[0]=1
        else
          if proposed < rank
            drops += 1
          else
            ties += 1
          rank=proposed
          timeline_count=ffrc_timeline_push(timeline_times,timeline_ranks,timeline_count,(now-start) / 1000,rank)
          density=0
          i=0
          while i < rank*3*stride
            best[i]=trial[i]
            density += popcount(trial[i])
            i += 1
          changed=1
      lane += 1
    # Read experimental counters only after every worker has joined. Match
    # its next epoch to baseline worker time instead of making the cohort
    # wait for the same number of more expensive legal proposals.
    if directed_lane>=0
      c=contexts[directed_lane]
      if c[20]!=0
        failure=1
      if workers>1
        baseline_ms=0 ## i64
        lane=0
        while lane<workers
          if lane!=directed_lane
            baseline_ms+=worker_elapsed[lane]
          lane+=1
        target=baseline_ms / (workers-1) ## i64
        if target<1
          target=1
        if target>50
          target=50
        elapsed=worker_elapsed[directed_lane] ## i64
        if elapsed<1
          elapsed=1
        directed_steps=directed_steps*target / elapsed
        if directed_steps<1
          directed_steps=1
        if directed_steps>steps
          directed_steps=steps
      directed_fields=ffws_directed_fields(contexts,directed_lane,directed_steps)
    if changed != 0 && ffrf_atomic(best_path,ffpk_blob(best,rank,n,n,n),"wide") != 1
      failure=1
      stop[0]=1
    round += 1
  if ccall("__w_interrupted") != 0
    stop_requested=1
  if tui != 0
    z=ccall("w_term_raw_disable")
  status="mode=wide-cpu tensor="+tensor+" backend=packed-cpu rank="+rank.to_s()+" bits="+density.to_s()+" cpu_lanes="+workers.to_s()+" cpu_moves="+moves.to_s()+" gpu_supported=0 gpu_moves=0 round="+round.to_s()+" producer_state=stopped stop_requested="+stop_requested.to_s()+" next_requested="+next_requested.to_s()+" exact_rejects="+failure.to_s()+seed_fields+directed_fields+cycle_fields+"\n"
  if ffrf_atomic(status_path,status,"wide") != 1
    failure=1
  if quiet == 0
    << "WIDE_RESULT "+status.strip()
  if failure != 0
    return 2
  0
