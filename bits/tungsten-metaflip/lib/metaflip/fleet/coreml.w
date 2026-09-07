# Optional asynchronous advisory ranking. The helper never writes schemes or
# decides exactness. Bank slots are reseeded in place, so use two bounded
# snapshot pools: neither pending inference nor ready advice aliases the banks.
use coreml_features
use ../paths
use ../cli

# String#to_f accepts numeric prefixes. Reject malformed advisory output before
# conversion, including NaN/Inf and trailing junk. Range is checked afterward.
-> ffcm_numeric_score(text) (String) i64
  if text.size() < 1 || text.size() > 64
    return 0
  i = 0 ## i64
  if text.slice(i, 1) == "+" || text.slice(i, 1) == "-"
    i += 1
  digits = 0 ## i64
  while i < text.size() && ffcli_decimal_digit(text.slice(i, 1)) >= 0
    digits += 1
    i += 1
  if i < text.size() && text.slice(i, 1) == "."
    i += 1
    while i < text.size() && ffcli_decimal_digit(text.slice(i, 1)) >= 0
      digits += 1
      i += 1
  if digits == 0
    return 0
  if i < text.size() && (text.slice(i, 1) == "e" || text.slice(i, 1) == "E")
    i += 1
    if i < text.size() && (text.slice(i, 1) == "+" || text.slice(i, 1) == "-")
      i += 1
    exponent_digits = 0 ## i64
    while i < text.size() && ffcli_decimal_digit(text.slice(i, 1)) >= 0
      exponent_digits += 1
      i += 1
    if exponent_digits == 0
      return 0
  if i == text.size()
    return 1
  0

+ MetaflipCoreML
  ro :uses, :batches, :failures

  -> new(model, helper, workers, compute, directory, tag)
    @request = directory + "/coreml-request.tsv"
    @response = directory + "/coreml-response.tsv"
    @stop = @request + ".stop"
    @tag = tag
    @epoch = 0
    @pending = []
    @ready = []
    @pending_pool = []
    @ready_pool = []
    @scores = f64[64]
    @used = i64[64]
    @features = f64[16]
    @last_submit = 0 - 2000
    @last_poll = 0 - 100
    @frontier = 0
    @pending_since = 0
    @live = 1
    @uses = 0
    @batches = 0
    @failures = 0
    @choices = 0
    @cursor = 0
    # A reused run tag must not replay a prior process's response or stop file.
    z = write_file(@request, "")
    z = write_file(@response, "")
    z = ccall("__w_unlink", @stop)
    command = "exec " + ffls_shell_quote(helper) + " --model " + ffls_shell_quote(model) + " --workers " + workers.to_s() + " --compute " + ffls_shell_quote(compute) + " --serve " + ffls_shell_quote(@request) + " " + ffls_shell_quote(@response) + " --poll-us 10000 > " + ffls_shell_quote(directory + "/coreml.log") + " 2>&1"
    @thread = Thread.new ->
      system(command)

  -> invalidate()
    @pending.clear()
    @ready.clear()
    @frontier = 0
    @epoch += 1
    0

  -> poll(near1, near2, frontier, now_ms)
    if @live == 0
      return 0
    if !@thread.alive?
      @live = 0
      @pending.clear()
      @ready.clear()
      @failures += 1
      << "metaflip CoreML: helper exited; continuing unguided (see coreml.log)"
      return 0
    if @frontier != frontier
      z = self.invalidate()
      @frontier = frontier
    if @pending.size() > 0 && now_ms - @last_poll >= 100
      @last_poll = now_ms
      raw = read_file(@response)
      if raw != nil && raw != ""
        lines = raw.strip().split("\n")
        header = lines[0].split("\t")
        count = @pending.size()
        epoch_text = @epoch.to_s()
        count_text = count.to_s()
        if header.size() == 3 && header[0] == "epoch" && header[1] == epoch_text && header[2] == count_text && lines.size() == count + 1
          valid = 1
          score_limit = 1000000000.0 ## f64
          score_floor = 0.0 - score_limit ## f64
          i = 0
          while i < count
            fields = lines[i + 1].split("\t")
            if fields.size() != 2
              valid = 0
            if fields.size() == 2
              if fields[0] != i.to_s()
                valid = 0
              score = 0.0 ## f64
              if ffcm_numeric_score(fields[1]) == 1
                score = fields[1].to_f()
              else
                valid = 0
              if !(score > score_floor && score < score_limit)
                valid = 0
              @scores[i] = score
              @used[i] = 0
            i += 1
          @ready.clear()
          if valid == 1
            i = 0
            while i < count
              @ready.push(@pending[i])
              i += 1
            previous_pool = @ready_pool
            @ready_pool = @pending_pool
            @pending_pool = previous_pool
            @batches += 1
          if valid == 0
            @failures += 1
          @pending.clear()
      if @pending.size() > 0 && now_ms - @pending_since > 30000
        @pending.clear()
        @failures += 1
    if @pending.size() == 0 && now_ms - @last_submit >= 2000
      @epoch += 1
      @last_submit = now_ms
      @pending_since = now_ms
      # Rotate through both debts, rather than letting a full
      # near1 bank permanently hide near2 from a bounded model batch.
      total = near1.size() + near2.size()
      if total == 0
        return 0
      rows = ""
      count = 0
      i = 0
      limit = total
      if limit > 64
        limit = 64
      while i < limit
        slot = (@cursor + i) % total
        candidate = nil
        if slot < near1.size()
          candidate = near1[slot]
        if slot >= near1.size()
          candidate = near2[slot - near1.size()]
        # Reuse a maximum of 128 state buffers across arbitrarily many batches.
        if count >= @pending_pool.size()
          @pending_pool.push(i64[candidate.size()])
        snapshot = @pending_pool[count]
        loaded = ffw_reseed_from(snapshot, candidate, @epoch * 67 + count)
        if loaded > 0 && ffcm_features(snapshot, frontier, @features) == 16
          if count > 0
            rows = rows + "\n"
          column = 0
          while column < 16
            if column > 0
              rows = rows + "\t"
            rows = rows + @features[column].to_s()
            column += 1
          @pending.push(snapshot)
          count += 1
        i += 1
      @cursor = (@cursor + limit) % total
      if count > 0
        body = "epoch\t" + @epoch.to_s() + "\t" + count.to_s() + "\n" + rows + "\n"
        if ffn_atomic_write(@request, body, @tag) == 0
          @pending.clear()
          @failures += 1
    1

  -> take(debt, frontier)
    if @live == 0 || frontier != @frontier || @ready.size() == 0
      return nil
    @choices += 1
    # Only one quarter of natural lease renewals consult the model. All other
    # islands retain their existing exploration, door and work-zone policy.
    if @choices % 4 != 0
      return nil
    best = 0 - 1
    i = 0
    while i < @ready.size()
      if @used[i] == 0 && ffw_best_rank(@ready[i]) == frontier + debt
        if best < 0 || @scores[i] > @scores[best]
          best = i
      i += 1
    if best < 0
      return nil
    @used[best] = 1
    candidate = @ready[best]
    # Never let the advisory model bypass the GF(2) certificate gate.
    if ffw_verify_best_exact(candidate, ffw_n(candidate)) != 1
      @failures += 1
      return nil
    @uses += 1
    candidate

  -> stop()
    z = write_file(@stop, "stop\n")
    z = ffn_thread_join_bounded(@thread, 5000)
    @live = 0
    << "METAFLIP_COREML batches=" + @batches.to_s() + " seed_uses=" + @uses.to_s() + " failures=" + @failures.to_s()
    z
