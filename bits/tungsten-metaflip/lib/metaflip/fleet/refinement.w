# Durable intake + bounded background batches. Disk tickets retain overflow;
# only one low-priority native child (at most two jobs) runs at a time. Hashes
# locate immutable objects; full bytes and tensor identity are still checked.
use refinement_worker
use core/system

-> ffrf_counter(path) (String) i64
  raw = File.read_prefix(path, 32)
  if raw == nil
    return 0
  value = ffw_parse_decimal_i64(raw.strip()) ## i64
  if value < 0 || value > 1000000000000
    return 0
  value

+ MetaflipRefinement
  ro :submitted, :completed, :duplicates, :failures, :outputs, :cross_shape, :last_identity, :last_kind

  -> new(root, executable, runtime = "")
    @root = root
    @executable = executable
    @runtime = runtime
    @compose_submitted = 0
    @compose_completed = 0
    @compose_failures = 0
    @compose_deferred = 0
    @wide_status = 0
    @wide_saved = 0
    @transform_submitted = 0
    @transform_completed = 0
    @transform_failures = 0
    @transform_status = 0
    @transform_delta = 0
    @transform_enabled = 1
    if env("METAFLIP_WIDE_TRANSFORMS") == "0"
      @transform_enabled = 0
    @compose_poll_ms = 0
    @compose_limit = ffrf_composition_limit()
    @budget_request = i64[2]
    @budget_blocked = 0
    @composing = 0
    @enabled = 1
    if env("METAFLIP_REFINEMENT") == "0"
      @enabled = 0
    @submitted = 0
    @completed = 0
    @duplicates = 0
    @failures = 0
    @outputs = 0
    @cross_shape = 0
    @last_identity = ""
    @last_kind = ""
    @thread = nil
    @batch_first = 0
    @batch_last = 0
    @retry_at = 0
    @next_poll_ms = 0
    @next_read_ms = 0
    @stopped = 0
    @records = []
    @record_index = 0
    @record_job = 0
    @cache = []
    @cache_meta = i64[64]
    @cache_count = 0
    @cache_cursor = 0
    @capacity = ffrf_capacity()
    @work = i64[ffmc_scratch_words(@capacity)]
    @parity = i64[4096]
    @meta = i64[4]
    @us = i64[@capacity]
    @vs = i64[@capacity]
    @ws = i64[@capacity]
    if @enabled != 0
      directories = ["objects", "tasks", "by-id", "results"]
      directory_index = 0 ## i64
      while directory_index < directories.size()
        if ffls_ensure_dir(root + "/" + directories[directory_index]) != 1
          @enabled = 0
          @failures += 1
        directory_index += 1
      if @enabled != 0
        @submitted = ffrf_counter(root + "/submitted")
        # Recover a ticket committed immediately before a coordinator crash.
        while File.exists?(root + "/tasks/" + (@submitted+1).to_s())
          @submitted += 1
        @completed = ffrf_counter(root + "/consumed")
        if @completed > @submitted
          @enabled = 0
          @failures += 1
        # A crash can land after the last ticket but before its dedup index.
        # Earlier successful tickets already have their index; repair the
        # single in-flight tail without scanning an unbounded history.
        if @submitted > 0
          tail = File.read_prefix(root + "/tasks/" + @submitted.to_s(), 66)
          if tail != nil && ffrf_hash_valid(tail.strip()) == 1
            tail_path = root + "/by-id/" + tail.strip()
            if !File.exists?(tail_path)
              if ffrf_atomic(tail_path, @submitted.to_s() + "\n", "intake") != 1
                @failures += 1
        z = ccall("__w_unlink", root + "/stop")

  -> pending()
    @submitted - @completed

  -> read_composition()
    @compose_completed = ffbc_counter(@root + "/composition/consumed") + ffbc_counter(@root + "/composition/mixed/consumed")
    @compose_submitted = ffbc_counter(@root + "/composition/submitted") + ffbc_counter(@root + "/composition/mixed/submitted")
    @compose_failures = ffbc_counter(@root + "/composition/failures") + ffbc_counter(@root + "/composition/mixed/failures")
    @compose_deferred = ffmd_deferred(@root)
    @transform_submitted = ffbc_counter(@root + "/composition/transforms/submitted")
    @transform_completed = ffbc_counter(@root + "/composition/transforms/consumed")
    @transform_failures = ffbc_counter(@root + "/composition/transforms/failures")
    last_transform = File.read_prefix(@root + "/composition/transforms/last", 32)
    if last_transform != nil
      parts = last_transform.strip().split(" ")
      if parts.size() == 2
        status = ffpk_decimal(parts[0]) ## i64
        delta = ffpk_decimal(parts[1]) ## i64
        if status >= 1 && status <= 3 && delta >= 0 && delta <= 16384
          @transform_status = status
          @transform_delta = delta
    last_wide = File.read_prefix(@root + "/composition/cleanup/last", 32)
    if last_wide != nil
      fields = last_wide.strip().split(" ")
      if fields.size() == 2
        status = ffpk_decimal(fields[0]) ## i64
        saved = ffpk_decimal(fields[1]) ## i64
        if status >= 1 && status <= 3 && saved >= 0 && saved <= 16384
          @wide_status = status
          @wide_saved = saved
    1

  -> remember(n, m, p, rank)
    slot = @cache_cursor
    if @cache_count < 16
      @cache.push(i64[3*@capacity])
      slot = @cache_count
      @cache_count += 1
    z = ffrf_copy(@cache[slot], @work, @capacity, rank)
    @cache_meta[4*slot] = n
    @cache_meta[4*slot+1] = m
    @cache_meta[4*slot+2] = p
    @cache_meta[4*slot+3] = rank
    @cache_cursor = (slot + 1) % 16
    1

  # Return 1 only after a durable ticket exists, 0 for a full-term duplicate
  # or disabled intake, and -1 for an explicit failure. No rank-only filter.
  -> submit(state, n, m, p)
    if @enabled == 0 || @stopped != 0
      return 0
    rank = state[7] ## i64
    if ffw_valid(state) != 1 || rank < 1 || rank > @capacity || rank > state[4]
      @failures += 1
      return 0-1
    i = 0 ## i64
    while i < rank
      @work[i] = state[state[47]+i]
      @work[@capacity+i] = state[state[48]+i]
      @work[2*@capacity+i] = state[state[49]+i]
      i += 1
    if ffrf_exact(@work, @capacity, rank, n, m, p, @parity) != 1
      @failures += 1
      return 0-1
    z = ffrf_sort(@work, @capacity, rank)
    slot = 0 ## i64
    while slot < @cache_count
      if @cache_meta[4*slot] == n && @cache_meta[4*slot+1] == m && @cache_meta[4*slot+2] == p && @cache_meta[4*slot+3] == rank && ffrf_same(@cache[slot], @work, @capacity, rank) == 1
        @duplicates += 1
        return 0
      slot += 1
    identity = ffrf_store(@root, @work, @capacity, rank, n, m, p, "intake")
    if identity == ""
      @failures += 1
      return 0-1
    marker = File.read_prefix(@root + "/by-id/" + identity, 32)
    if marker != nil
      ticket = ffw_parse_decimal_i64(marker.strip()) ## i64
      bound = File.read_prefix(@root + "/tasks/" + ticket.to_s(), 66)
      if ticket < 1 || ticket > @submitted || bound == nil || bound.strip() != identity
        @failures += 1
        return 0-1
      @duplicates += 1
      z = self.remember(n, m, p, rank)
      return 0
    next_ticket = @submitted + 1
    if ffrf_atomic(@root + "/tasks/" + next_ticket.to_s(), identity + "\n", "intake") != 1
      @failures += 1
      return 0-1
    @submitted = next_ticket
    if ffrf_atomic(@root + "/submitted", next_ticket.to_s() + "\n", "intake") != 1
      @failures += 1
    if ffrf_atomic(@root + "/by-id/" + identity, next_ticket.to_s() + "\n", "intake") != 1
      @failures += 1
    z = self.remember(n, m, p, rank)
    1

  -> poll(now_ms)
    if @enabled == 0 || now_ms < @next_poll_ms
      return 0
    @next_poll_ms = now_ms + 25
    if @thread != nil && !@thread.alive?()
      z = @thread.join(0)
      @thread = nil
      request_ok = ffrf_budget_request(@root, @budget_request) ## i64
      deferred = request_ok == 1 && @budget_request[0] >= @batch_first && @budget_request[0] <= @batch_last ## bool
      if @composing == 0 && !File.exists?(@root + "/results/" + @batch_last.to_s()) && @stopped == 0 && !deferred
        @failures += 1
        @retry_at = now_ms + 1000
      @composing = 0
      @compose_poll_ms = 0
    if @runtime != "" && now_ms >= @compose_poll_ms
      z = self.read_composition() ## i64
      request_ok = ffrf_budget_request(@root, @budget_request) ## i64
      @budget_blocked = 0
      if @compose_limit != 0 && request_ok == 1 && @budget_request[1] > 0 && @compose_submitted - @compose_completed + @budget_request[1] > @compose_limit
        @budget_blocked = 1
      @compose_poll_ms = now_ms + 1000
    # A completed batch can be consumed while stopped. Never relaunch work
    # whose manifests exist but whose candidates have not yet been drained.
    if @thread == nil && @stopped == 0 && @budget_blocked == 0 && @completed < @submitted && now_ms >= @retry_at && !File.exists?(@root + "/results/" + (@completed+1).to_s())
      @batch_first = @completed+1
      @batch_last = @batch_first+1
      if @batch_last > @submitted
        @batch_last = @submitted
      arguments = " --refine-batch " + ffls_shell_quote(@root) + " " + @batch_first.to_s() + " " + @batch_last.to_s()
      if @runtime != ""
        arguments = arguments + " " + ffls_shell_quote(@runtime)
      command = "exec nice -n 10 " + ffls_shell_quote(@executable) + arguments + " > " + ffls_shell_quote(@root + "/worker.log") + " 2>&1"
      @thread = Thread.new ->
        system(command)
      @retry_at = now_ms + 100
    elsif @thread == nil && @runtime != "" && @stopped == 0 && (@budget_blocked != 0 || @completed >= @submitted) && (@compose_completed < @compose_submitted || @compose_deferred != 0 || (@transform_enabled != 0 && @transform_completed < @transform_submitted && !File.exists?(@root + "/composition/transforms/error"))) && now_ms >= @retry_at && !File.exists?(@root + "/composition/error") && !File.exists?(@root + "/composition/mixed/error")
      @composing = 1
      command = "exec nice -n 10 " + ffls_shell_quote(@executable) + " --compose-batch " + ffls_shell_quote(@root) + " 4 > " + ffls_shell_quote(@root + "/worker.log") + " 2>&1"
      @thread = Thread.new ->
        system(command)
      @retry_at = now_ms + 1000
    1

  -> finish_record()
    if @record_job == 0
      return 1
    if ffrf_atomic(@root + "/consumed", @record_job.to_s() + "\n", "intake") != 1
      @failures += 1
      return 0
    @completed = @record_job
    @record_job = 0
    # Each result line is a private split copy. No caller keeps these lines
    # (identity/kind are separate split copies); clear does not free elements.
    i = 0 ## i64
    while i < @records.size()
      ccall("w_value_free_w", @records[i])
      i += 1
    @records.clear()
    @record_index = 0
    1

  -> read_record()
    if @record_job != 0
      return 1
    if @completed >= @submitted
      return 0
    now_ms = ccall("__w_clock_ms") ## i64
    if now_ms < @next_read_ms
      return 0
    job = @completed+1
    raw = File.read_prefix(@root + "/results/" + job.to_s(), 32769)
    if raw == nil
      @next_read_ms = now_ms + 25
      return 0
    lines = raw.strip().split("\n")
    header = lines[0].split(" ")
    ticket = File.read_prefix(@root + "/tasks/" + job.to_s(), 66)
    if raw.size() > 32768 || header.size() != 4 || header[0] != "MFR_RESULT1" || ticket == nil
      @failures += 1
      return 0
    count = ffw_parse_decimal_i64(header[3]) ## i64
    if header[1] != job.to_s() || header[2] != ticket.strip() || count < 0 || count > 140 || lines.size() != count+1
      @failures += 1
      return 0
    @records.clear()
    i = 0 ## i64
    while i < count
      @records.push(lines[i+1])
      i += 1
    @record_job = job
    @record_index = 0
    1

  # Drain at most eight records per call. Other shapes stay in the immutable
  # cross-shape artifact archive. A matching candidate is copied into caller
  # storage and exact-checked again, then can enter ordinary seed admission.
  -> take_into(state, n, m, p, capacity, seed, dslack, cycles, workq, wanderq)
    if @enabled == 0
      return 0
    inspected = 0 ## i64
    while inspected < 8
      if self.read_record() != 1
        return 0
      if @record_index >= @records.size()
        if self.finish_record() != 1
          return 0
        inspected += 1
      else
        fields = @records[@record_index].split(" ")
        if fields.size() != 2 || ffrf_load(@root, fields[0], @work, @capacity, @meta, @parity) != 1
          @failures += 1
          return 0-1
        @record_index += 1
        @outputs += 1
        inspected += 1
        if @meta[0] != n || @meta[1] != m || @meta[2] != p
          @cross_shape += 1
        else
          rank = @meta[3] ## i64
          if rank > capacity
            @failures += 1
            return 0-1
          i = 0 ## i64
          while i < rank
            @us[i] = @work[i]
            @vs[i] = @work[@capacity+i]
            @ws[i] = @work[2*@capacity+i]
            i += 1
          loaded = 0 ## i64
          if n == m && m == p
            loaded = ffw_init_terms_cap(state, @us, @vs, @ws, rank, n, capacity, seed, dslack, cycles, workq, wanderq)
          else
            loaded = ffr_init_terms_cap(state, @us, @vs, @ws, rank, n, m, p, capacity, seed, dslack, cycles, workq, wanderq)
          if loaded != rank
            @failures += 1
            return 0-1
          @last_identity = fields[0]
          @last_kind = fields[1]
          return rank
    0

  -> transform_fields()
    " wide_transform_enabled=" + @transform_enabled.to_s() + " wide_transform_submitted=" + @transform_submitted.to_s() + " wide_transform_completed=" + @transform_completed.to_s() + " wide_transform_pending=" + (@transform_submitted - @transform_completed).to_s() + " wide_transform_failures=" + @transform_failures.to_s() + " wide_transform_status=" + @transform_status.to_s() + " wide_transform_delta=" + @transform_delta.to_s()

  -> status_fields()
    " refine=" + @enabled.to_s() + " refine_submitted=" + @submitted.to_s() + " refine_completed=" + @completed.to_s() + " refine_pending=" + self.pending().to_s() + " refine_duplicates=" + @duplicates.to_s() + " refine_outputs=" + @outputs.to_s() + " refine_cross_shape=" + @cross_shape.to_s() + " refine_failures=" + @failures.to_s() + " refine_blocked=" + @budget_blocked.to_s() + " compose_limit=" + @compose_limit.to_s() + " compose_submitted=" + @compose_submitted.to_s() + " compose_completed=" + @compose_completed.to_s() + " compose_pending=" + (@compose_submitted - @compose_completed).to_s() + " compose_deferred=" + @compose_deferred.to_s() + " compose_failures=" + @compose_failures.to_s() + " compose_wide_status=" + @wide_status.to_s() + " compose_wide_saved=" + @wide_saved.to_s() + self.transform_fields()

  -> status_row()
    if @enabled == 0
      return "refinement off; failures " + @failures.to_s()
    wide = "idle"
    if @wide_status == 1
      wide = "fixed"
    elsif @wide_status == 2
      wide = "work-limited"
    elsif @wide_status == 3
      wide = "verify-limited"
    "refine " + @completed.to_s() + "/" + @submitted.to_s() + "; compose " + @compose_completed.to_s() + "/" + @compose_submitted.to_s() + "; pending " + (self.pending() + @compose_submitted - @compose_completed + @transform_submitted - @transform_completed).to_s() + "; deferred " + @compose_deferred.to_s() + "; blocked " + @budget_blocked.to_s() + "; wide " + wide + "/-" + @wide_saved.to_s() + "; transforms " + @transform_completed.to_s() + "/" + @transform_submitted.to_s() + "; failures " + (@failures + @compose_failures + @transform_failures).to_s()

  -> stop()
    @stopped = 1
    if @enabled == 0
      return 1
    z = write_file(@root + "/stop", "stop\n")
    if @thread != nil
      if !@thread.join(5000)
        @failures += 1
        return 0
      @thread = nil
    if @runtime != ""
      z = self.read_composition()
    1
