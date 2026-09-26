# Coordinator-only packed intake and checked result adoption. One native
# low-priority child shares the existing bounded transform/composition FIFO.
use seeds
use ../composition/worker

-> ffpr_seed_path(state_root, n, slot) (String i64 i64)
  state_root + "/banks/gf2/" + n.to_s() + "x" + n.to_s() + "x" + n.to_s() + "/packed-feedback/" + slot.to_s() + ".mfw"

# Four distinct full representations per live packed square. These are only
# future seed offers; startup must verify each complete tensor again.
-> ffpr_spool(state_root, blob, rank, n, m, p) (String String i64 i64 i64 i64) i64
  if state_root == "" || n != m || m != p || n < 8 || n > 16 || rank > 8190
    return 1
  target = 0-1 ## i64
  worst = 0 ## i64
  slot = 0 ## i64
  while slot < 4
    path = ffpr_seed_path(state_root,n,slot)
    old = File.read_prefix(path,12632129)
    if old == blob
      return 1
    if old == nil
      if target < 0
        target = slot
        worst = 16385
    elsif worst < 16385
      header = old.split("\n")[0].split(" ")
      if header.size() != 5 || header[0] != "MFW1"
        return 0
      old_rank = ffpk_decimal(header[4]) ## i64
      if old_rank < 1 || old_rank > 8190
        return 0
      if old_rank > worst
        target = slot
        worst = old_rank
    slot += 1
  if rank > worst
    return 1
  directory = state_root + "/banks/gf2/" + n.to_s() + "x" + n.to_s() + "x" + n.to_s() + "/packed-feedback"
  if !File.mkdir_p(directory)
    return 0
  ffrf_atomic(ffpr_seed_path(state_root,n,target),blob,"packed-spool")

+ MetaflipPackedRefinement
  ro :failures, :seed_uses, :last_identity

  -> new(root, executable, state_root, runtime = "")
    @root = root
    @executable = executable
    @state_root = state_root
    @runtime = runtime
    @thread = nil
    @next_poll = 0
    @next_read = 0
    @stopped = 0
    @enabled = 1
    if env("METAFLIP_REFINEMENT") == "0"
      @enabled = 0
    @failures = 0
    @seed_uses = 0
    @outputs = 0
    @cross_shape = 0
    @limited = 0
    @last_identity = ""
    @intake_submitted = 0
    @intake_completed = 0
    @transform_submitted = 0
    @transform_completed = 0
    @feedback_submitted = 0
    @feedback_completed = 0
    @narrow_completed = ffmd_count(root + "/composition/feedback/consumed")
    if @enabled != 0
      directories = ["objects", "best", "by-shape"]
      i = 0 ## i64
      while i < directories.size()
        if !File.mkdir_p(root + "/composition/" + directories[i])
          @enabled = 0
          @failures += 1
        i += 1
      if @enabled != 0
        z = ccall("__w_unlink",root + "/stop")
        z = self.counters()

  -> counters()
    @intake_submitted = ffmd_count(@root + "/composition/packed-intake/submitted")
    @intake_completed = ffmd_count(@root + "/composition/packed-intake/consumed")
    @transform_submitted = ffmd_count(@root + "/composition/transforms/submitted")
    @transform_completed = ffmd_count(@root + "/composition/transforms/consumed")
    @feedback_submitted = ffmd_count(@root + "/composition/packed-feedback/submitted")
    @feedback_completed = ffmd_count(@root + "/composition/packed-feedback/consumed")
    if @intake_completed < 0 || @intake_submitted < @intake_completed || @transform_completed < 0 || @transform_submitted < @transform_completed || @feedback_completed < 0 || @feedback_submitted < @feedback_completed
      @failures += 1
      @enabled = 0
      return 0
    1

  # Caller owns the stable slab. Full checking/cleanup happen in the child;
  # merely submitting a structurally valid representation never admits it.
  -> submit(data, words, rank, n, m, p)
    if @enabled == 0 || @stopped != 0
      return 0
    if ffpk_valid(data,words,rank,n,m,p) != 1 || ffcu_source(@root,n,m,p) != 1
      @failures += 1
      return 0-1
    stride = ffpk_stride(n,m,p) ## i64
    copy = i64[rank*3*stride]
    i = 0 ## i64
    while i < rank*3*stride
      copy[i] = data[i]
      i += 1
    rank = ffpk_canonicalize(copy,copy.size(),rank,stride)
    if rank < 1
      @failures += 1
      return 0-1
    blob = ffpk_blob(copy,rank,n,m,p)
    identity = Crypto:SHA256.hexdigest(blob)
    result = ffpf_offer(@root,"packed-intake",identity,blob,rank,n,m,p) ## i64
    if result != 1
      @failures += 1
      return 0-1
    1

  -> poll(now)
    if @enabled == 0 || @stopped != 0 || now < @next_poll
      return 0
    @next_poll = now+250
    if @thread != nil && !@thread.alive?()
      z = @thread.join(0)
      @thread = nil
    if self.counters() != 1
      return 0
    if File.exists?(@root + "/composition/transforms/error")
      @failures += 1
      @enabled = 0
      return 0
    if @thread == nil && (@intake_submitted > @intake_completed || @transform_submitted > @transform_completed || (@runtime != "" && ffcl_pending(@root) == 1))
      command = "exec nice -n 10 " + ffls_shell_quote(@executable) + " --compose-batch " + ffls_shell_quote(@root) + " 4 " + ffls_shell_quote(@runtime) + " > " + ffls_shell_quote(@root + "/worker.log") + " 2>&1"
      @thread = Thread.new ->
        system(command)
    1

  # Only call between joined epochs. Drain one outbox entry per 250ms, with
  # exact verification before a matching seed can replace a worker state.
  -> take_into(out, words, n, parity)
    now = ccall("__w_clock_ms") ## i64
    if @enabled == 0 || @stopped != 0 || now < @next_read
      return 0
    @next_read = now+250
    z = self.take_narrow()
    queue = @root + "/composition/packed-feedback/"
    submitted = ffmd_count(queue + "submitted") ## i64
    if submitted < @feedback_completed
      @failures += 1
      return 0-1
    if submitted == @feedback_completed
      return 0
    ticket = @feedback_completed+1 ## i64
    raw = ffbq_read(queue,"tasks",ticket)
    if ffpf_valid(raw) != 1
      @failures += 1
      return 0-1
    f = raw.strip().split(" ")
    if File.read_prefix(queue + "by-id/" + f[1],32) != ticket.to_s() + "\n"
      @failures += 1
      return 0-1
    blob = File.read_prefix(@root + "/composition/objects/" + f[1] + ".tensor",12632129)
    if blob == nil || Crypto:SHA256.hexdigest(blob) != f[1]
      @failures += 1
      return 0-1
    nn = ffpk_decimal(f[2]) ## i64
    mm = ffpk_decimal(f[3]) ## i64
    pp = ffpk_decimal(f[4]) ## i64
    rank = ffpk_decimal(f[5]) ## i64
    loaded = 0 ## i64
    if nn == n && mm == n && pp == n && rank <= 8190 && !File.exists?(@root + "/composition/packed-intake/by-id/" + f[1])
      meta = i64[4]
      if ffpf_load(@root,raw,out,words,meta) != rank
        @failures += 1
        return 0-1
      checked = ffpk_exact(out,words,rank,n,n,n,parity,parity.size(),20000000) ## i64
      if checked == 0-1
        @limited += 1
      elsif checked != 1
        @failures += 1
        return 0-1
      else
        loaded = rank
        @last_identity = f[1]
    elsif nn != n || mm != n || pp != n
      if ffpr_spool(@state_root,blob,rank,nn,mm,pp) != 1
        @failures += 1
        return 0-1
      @cross_shape += 1
    if ffrf_atomic(queue + "consumed",ticket.to_s() + "\n","packed-intake") != 1
      @failures += 1
      return 0-1
    @feedback_completed = ticket
    @outputs += 1
    loaded

  # Smaller descendants cross the old <=63-bit gate and seed spool. This
  # coordinator owns both outbox cursors; there is still only one child.
  -> take_narrow()
    queue = @root + "/composition/feedback/"
    submitted = ffmd_count(queue + "submitted") ## i64
    if @narrow_completed < 0 || submitted < @narrow_completed
      @failures += 1
      return 0-1
    if submitted == @narrow_completed
      return 0
    ticket = @narrow_completed+1 ## i64
    raw = ffbq_read(queue,"tasks",ticket)
    packed = i64[6*4096]
    work = i64[3*4096]
    meta = i64[4]
    parity = i64[4096]
    if ffwf_load(@root,raw,packed,work,4096,meta,parity) != 1
      @failures += 1
      return 0-1
    f = raw.strip().split(" ")
    if File.read_prefix(queue + "by-id/" + f[1],32) != ticket.to_s() + "\n"
      @failures += 1
      return 0-1
    if @state_root != "" && ((meta[0] == meta[1] && meta[1] == meta[2] && meta[0] >= 2 && meta[0] <= 7) || ffr_supported(meta[0],meta[1],meta[2]) == 1)
      if ffrf_spool_offer(@state_root,work,4096,meta[3],meta[0],meta[1],meta[2],parity,"packed-intake") < 0
        @failures += 1
        return 0-1
    if ffrf_atomic(queue + "consumed",ticket.to_s() + "\n","packed-intake") != 1
      @failures += 1
      return 0-1
    @narrow_completed = ticket
    @outputs += 1
    @cross_shape += 1
    1

  -> seed_used()
    @seed_uses += 1
    1

  -> status_fields()
    " packed_refine=" + @enabled.to_s() + " packed_intake=" + @intake_submitted.to_s() + " packed_scheduled=" + @intake_completed.to_s() + " packed_tasks=" + @transform_submitted.to_s() + " packed_completed=" + @transform_completed.to_s() + " packed_outputs=" + @outputs.to_s() + " packed_cross_shape=" + @cross_shape.to_s() + " packed_seed_uses=" + @seed_uses.to_s() + " packed_verify_limited=" + @limited.to_s() + " packed_failures=" + @failures.to_s()

  -> status_row()
    "refine " + @transform_completed.to_s() + "/" + @transform_submitted.to_s() + "; queued roots " + (@intake_submitted - @intake_completed).to_s() + "; feedback " + @outputs.to_s() + "; seeds " + @seed_uses.to_s() + "; failures " + @failures.to_s()

  -> stop()
    @stopped = 1
    if @enabled == 0 && @thread == nil
      return 1
    z = write_file(@root + "/stop","stop\n")
    if @thread != nil
      if !@thread.join(5000)
        @failures += 1
        return 0
      @thread = nil
    z = self.counters()
    1
