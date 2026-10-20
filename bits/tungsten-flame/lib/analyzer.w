# analyzer.w — Folded-stack profile analyzer.
#
# Takes a folded-stacks file path, a top_n cutoff, a category set name
# ("general" / "lexer" / "ruby" / "external"), an optional focus function
# name (empty string to auto-pick the top function when >40% self), a
# color flag, and the metric the folded counts measure. Prints a profile
# breakdown — Top Functions, caller/callee breakdown, category bars — to
# stdout.

use folded

in Tungsten:Flame

+ FlameAnalyzer

  # Noise threshold for Top Functions lists: an unresolved hex-only
  # leaf (frame still a raw "0x..." address) under 0.1% of `active` is
  # dropped from the list — its counts stay in every total — and
  # tallied so the caller can print an honest "(+N minor unresolved
  # frames)" note. Named frames and large hex frames always stay.
  # `sorted_pairs` is a list of [name, count]; returns
  # [kept_pairs, dropped_count].
  -> .noise_split(sorted_pairs, active)
    kept = []
    dropped = 0
    i = 0
    while i < sorted_pairs.size()
      pair = sorted_pairs[i]
      if pair[0].starts_with?("0x") && pair[1] * 1000 / active < 1
        dropped = dropped + 1
      else
        kept.push(pair)
      i = i + 1
    [kept, dropped]

  # Legacy 5-arg surface (pinned by the golden spec in
  # implementations/ruby/spec/flame_analyzer_spec.rb): assumes the folded
  # counts are time-profile samples.
  -> .display(stacks_file, top_n, category_set, focus_in, color)
    self.display_metric(stacks_file, top_n, category_set, focus_in, color, "samples")

  # Full breakdown for one metric.
  -> .display_metric(stacks_file, top_n, category_set, focus_in, color, metric)
    focus = focus_in

    unit = "samples"
    if metric != "samples" && metric != "cycles"
      unit = "events"

    bold  = color ? "\e[1m" : ""
    dim   = color ? "\e[2m" : ""
    reset = color ? "\e[0m" : ""

    folded = read_file(stacks_file)
    lines = folded.split("\n")

    # Parse folded stacks: "stack;frames count"
    stacks = []
    total = 0
    idle = 0
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        if sp
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
        else
          stack = line
          count = 0
        is_idle = Tungsten:Flame:Folded.idle_stack?(stack)
        stacks.push({ stack: stack, count: count, idle: is_idle })
        total = total + count
        if is_idle
          idle = idle + count
      i = i + 1

    active = total - idle
    if active == 0
      << "No active " + unit + "."
      return

    # Count leaf-only (self time) for top functions
    leaf_counts = {}
    i = 0
    while i < stacks.size()
      entry = stacks[i]
      if !entry[:idle]
        frames = entry[:stack].split(";")
        leaf = Tungsten:Flame:Folded.normalize_frame(frames.last())
        if leaf_counts.has_key?(leaf)
          leaf_counts[leaf] = leaf_counts[leaf] + entry[:count]
        else
          leaf_counts[leaf] = entry[:count]
      i = i + 1

    # Filter infrastructure frames out of Top Functions and sort descending.
    sorted_fns = []
    leaf_counts.keys().each -> (func_name)
      if !Tungsten:Flame:Folded.infra_leaf?(func_name)
        sorted_fns.push([func_name, leaf_counts[func_name]])
    sorted_fns = sorted_fns.sort_by -> (p) -p[1]

    # Drop sub-0.1% unresolved hex leaves from the list (not the totals).
    noise = self.noise_split(sorted_fns, active)
    sorted_fns = noise[0]
    minor_unresolved = noise[1]

    # Categorize samples
    -> matches_general(frame)
      if frame.include?("w_method_call") || frame.include?("w_method_dispatch") || frame.include?("call_closure")
        return "method call"
      if frame.include?("GC_") || frame.include?("w_gc_") || frame.include?("w_alloc") || frame.include?("malloc") || frame.include?("realloc") || frame.include?("calloc") || frame.include?("w_array_push")
        return "allocation"
      if frame.include?("w_str_") || frame.include?("w_string") || frame.include?("strlen") || frame.include?("memcpy") || frame.include?("memmove") || frame.include?("w_strbuf")
        return "string ops"
      if frame.include?("w_int") || frame.include?("w_add") || frame.include?("w_sub") || frame.include?("w_mul")
        return "integer ops"
      if frame.include?("w_eq") || frame.include?("w_cmp") || frame.include?("w_lt") || frame.include?("w_gt")
        return "comparison"
      if frame.include?("w_hash") || frame.include?("w_map") || frame.include?("w_dict") || frame.include?("w_table")
        return "hash/map"
      if frame.include?("libsystem_kernel")
        return "syscall"
      nil

    -> matches_lexer(frame)
      if frame.include?("tokenize")
        return "tokenize"
      if frame.include?("w_str_") || frame.include?("w_string") || frame.include?("strlen") || frame.include?("memcpy") || frame.include?("memmove") || frame.include?("w_strbuf")
        return "string ops"
      if frame.include?("w_method_call") || frame.include?("w_method_dispatch") || frame.include?("call_closure")
        return "method call"
      if frame.include?("GC_") || frame.include?("w_gc_") || frame.include?("w_alloc") || frame.include?("malloc") || frame.include?("realloc") || frame.include?("calloc") || frame.include?("w_array_push")
        return "allocation"
      if frame.include?("w_eq") || frame.include?("w_cmp") || frame.include?("w_lt") || frame.include?("w_gt")
        return "comparison"
      if frame.include?("w_hash") || frame.include?("w_map") || frame.include?("w_dict") || frame.include?("w_table")
        return "hash/map"
      if frame.include?("w_int") || frame.include?("w_add") || frame.include?("w_sub") || frame.include?("w_mul")
        return "integer ops"
      nil

    -> matches_ruby(frame)
      if frame.include?("(garbage collection)") || frame.include?("GC")
        return "gc"
      if frame.include?("Tungsten::Lexer#") || frame.include?("Tungsten::Parser#") || frame.include?("parse_with_file")
        return "parse/lex"
      if frame.include?("Tungsten::Interpreter#evaluate") || frame.include?("Tungsten::Interpreter#visit_") || frame.include?("Tungsten::Interpreter#call_") || frame.include?("Tungsten::Interpreter#invoke_block") || frame.include?("Tungsten::Interpreter#run")
        return "interpreter"
      if frame.include?("Tungsten::Environment#")
        return "environment"
      if frame.include?("Array#") || frame.include?("Hash#") || frame.include?("String#") || frame.include?("Enumerable#")
        return "ruby core"
      if frame.include?("Kernel#require")
        return "require"
      nil

    -> matches_external(frame)
      if frame.include?("malloc") || frame.include?("realloc") || frame.include?("calloc") || frame.include?("free") || frame.include?("operator new")
        return "allocation"
      if frame.include?("GC") || frame.include?("mark") || frame.include?("sweep")
        return "gc"
      if frame.include?("vm_") || frame.include?("rb_") || frame.include?("Py") || frame.include?("objc_msgSend") || frame.include?("swift_")
        return "runtime/vm"
      if frame.include?("libsystem_kernel") || frame.include?("kevent") || frame.include?("poll") || frame.include?("futex") || frame.include?("epoll")
        return "syscall"
      if frame.include?("strlen") || frame.include?("strcmp") || frame.include?("memcpy") || frame.include?("memmove") || frame.include?("memset")
        return "string ops"
      if frame.include?("pthread") || frame.include?("mutex") || frame.include?("lock")
        return "locking"
      nil

    cat_samples = {}
    i = 0
    while i < stacks.size()
      entry = stacks[i]
      if !entry[:idle]
        count = entry[:count]
        frames = entry[:stack].split(";")
        matched = false
        fi = frames.size() - 1
        while fi >= 0
          cat = nil
          if category_set == "lexer"
            cat = matches_lexer(frames[fi])
          elsif category_set == "ruby"
            cat = matches_ruby(frames[fi])
          elsif category_set == "external"
            cat = matches_external(frames[fi])
          else
            cat = matches_general(frames[fi])
          if cat
            if cat_samples.has_key?(cat)
              cat_samples[cat] = cat_samples[cat] + count
            else
              cat_samples[cat] = count
            matched = true
            break
          fi = fi - 1
        if !matched
          if cat_samples.has_key?("other")
            cat_samples["other"] = cat_samples["other"] + count
          else
            cat_samples["other"] = count
      i = i + 1

    # Sort categories by count descending
    sorted_cats = []
    cat_samples.keys().each -> (cat)
      sorted_cats.push([cat, cat_samples[cat]])
    sorted_cats = sorted_cats.sort_by -> (p) -p[1]

    metric_suffix = ""
    if metric != "samples"
      metric_suffix = " — " + metric
    << ""
    << "  " + bold + "Profile Breakdown" + metric_suffix + reset + "  " + dim + "(" + active.to_s() + " active / " + idle.to_s() + " idle " + unit + ")" + reset
    << ""

    << "  " + bold + "Top Functions" + reset
    i = 0
    limit = top_n
    if limit > sorted_fns.size()
      limit = sorted_fns.size()
    while i < limit
      func_name = sorted_fns[i][0]
      n = sorted_fns[i][1]
      pct_str = Tungsten:Flame:Folded.fmt_pct_padded(n, active)
      fn_color = color ? "\e[38;5;67m" : ""
      << "    " + bold + pct_str + "%" + reset + "  " + fn_color + func_name + reset
      i = i + 1
    if minor_unresolved > 0
      << "    " + dim + "(+" + minor_unresolved.to_s() + " minor unresolved frames)" + reset

    # Auto-focus: if top function is over 40% and no explicit focus, auto-set
    if focus == "" && sorted_fns.size() > 0
      top_pct_x10 = sorted_fns[0][1] * 1000 / active
      if top_pct_x10 > 400
        focus = sorted_fns[0][0]

    # Caller/callee breakdown for focused function
    if focus != ""
      << ""

      callers = {}
      callees = {}
      focus_total = 0

      i = 0
      while i < stacks.size()
        entry = stacks[i]
        if !entry[:idle]
          count = entry[:count]
          frames = entry[:stack].split(";")
          fi = 0
          while fi < frames.size()
            frame = Tungsten:Flame:Folded.normalize_frame(frames[fi])
            if frame == focus
              focus_total = focus_total + count
              if fi > 0
                caller_frame = Tungsten:Flame:Folded.normalize_frame(frames[fi - 1])
                if callers.has_key?(caller_frame)
                  callers[caller_frame] = callers[caller_frame] + count
                else
                  callers[caller_frame] = count
              if fi < frames.size() - 1
                callee_frame = Tungsten:Flame:Folded.normalize_frame(frames[fi + 1])
                if callees.has_key?(callee_frame)
                  callees[callee_frame] = callees[callee_frame] + count
                else
                  callees[callee_frame] = count
            fi = fi + 1
        i = i + 1

      fn_color = color ? "\e[38;5;67m" : ""

      if callers.keys().size() > 0
        caller_pairs = []
        callers.keys().each -> (c)
          caller_pairs.push([c, callers[c]])
        caller_pairs = caller_pairs.sort_by -> (p) -p[1]

        << "  " + bold + "Callers of " + reset + fn_color + focus + reset
        ci = 0
        c_limit = 8
        if c_limit > caller_pairs.size()
          c_limit = caller_pairs.size()
        while ci < c_limit
          pct_str = Tungsten:Flame:Folded.fmt_pct_padded(caller_pairs[ci][1], focus_total)
          << "    " + bold + pct_str + "%" + reset + "  " + fn_color + caller_pairs[ci][0] + reset
          ci = ci + 1

      if callees.keys().size() > 0
        callee_pairs = []
        callees.keys().each -> (c)
          callee_pairs.push([c, callees[c]])
        callee_pairs = callee_pairs.sort_by -> (p) -p[1]

        << "  " + bold + "Callees of " + reset + fn_color + focus + reset
        ci = 0
        c_limit = 8
        if c_limit > callee_pairs.size()
          c_limit = callee_pairs.size()
        while ci < c_limit
          pct_str = Tungsten:Flame:Folded.fmt_pct_padded(callee_pairs[ci][1], focus_total)
          << "    " + bold + pct_str + "%" + reset + "  " + fn_color + callee_pairs[ci][0] + reset
          ci = ci + 1
      else
        if callers.keys().size() > 0
          << "  " + dim + "(leaf — no callees)" + reset

    << ""

    # Print category bars
    max_n = 0
    if sorted_cats.size() > 0
      max_n = sorted_cats[0][1]
    bar_width = 30

    heat_colors = [67, 107, 186, 180, 174, 167]

    i = 0
    while i < sorted_cats.size()
      cat = sorted_cats[i][0]
      n = sorted_cats[i][1]
      pct_x10 = n * 1000 / active
      if pct_x10 >= 5
        blen = (n * bar_width / max_n)
        if blen < 1 && n > 0
          blen = 1
        bar = ""
        bi = 0
        while bi < bar_width
          if bi < blen
            if color
              heat = (bi * 6 / bar_width)
              if heat >= heat_colors.size()
                heat = heat_colors.size() - 1
              bar = bar + "\e[38;5;" + heat_colors[heat].to_s() + "m█\e[0m"
            else
              bar = bar + "█"
          else
            if color
              bar = bar + "\e[38;5;240m░\e[0m"
            else
              bar = bar + "░"
          bi = bi + 1

        pct_str = Tungsten:Flame:Folded.fmt_pct_padded(n, active)
        cat_str = Tungsten:Flame:Folded.pad_right(cat, 12)

        << "  " + bar + "  " + bold + pct_str + "%" + reset + "  " + cat_str + "  " + dim + "(" + n.to_s() + ")" + reset
      i = i + 1

    << ""

  # Compact per-metric Top-N section. Used by flame.w to render
  # secondary metrics (e.g., "Top Branch Misses") without caller/callee
  # + category bars that .display emits for the primary metric.
  -> .display_top_only(stacks_file, top_n, label, color)
    bold  = color ? "\e[1m" : ""
    dim   = color ? "\e[2m" : ""
    reset = color ? "\e[0m" : ""
    fn_color = color ? "\e[38;5;67m" : ""

    folded = read_file(stacks_file)
    lines = folded.split("\n")

    leaf_counts = {}
    total = 0
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        if sp
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
        else
          stack = line
          count = 0
        if !Tungsten:Flame:Folded.idle_stack?(stack)
          frames = stack.split(";")
          leaf = Tungsten:Flame:Folded.normalize_frame(frames.last())
          if leaf_counts.has_key?(leaf)
            leaf_counts[leaf] = leaf_counts[leaf] + count
          else
            leaf_counts[leaf] = count
          total = total + count
      i = i + 1

    if total == 0
      << "  " + bold + "Top " + label + reset + "  (no data)"
      return

    sorted = []
    leaf_counts.keys().each -> (func_name)
      if !Tungsten:Flame:Folded.infra_leaf?(func_name)
        sorted.push([func_name, leaf_counts[func_name]])
    sorted = sorted.sort_by -> (p) -p[1]

    # Drop sub-0.1% unresolved hex leaves from the list (not the totals).
    noise = self.noise_split(sorted, total)
    sorted = noise[0]
    minor_unresolved = noise[1]

    << ""
    << "  " + bold + "Top " + label + reset
    limit = top_n
    if limit > sorted.size()
      limit = sorted.size()
    i = 0
    while i < limit
      pct = Tungsten:Flame:Folded.fmt_pct_padded(sorted[i][1], total)
      << "    " + bold + pct + "%" + reset + "  " + fn_color + sorted[i][0] + reset
      i = i + 1
    if minor_unresolved > 0
      << "    " + dim + "(+" + minor_unresolved.to_s() + " minor unresolved frames)" + reset

  # Return a Hash of `{func_name => true}` for the top sampled functions in
  # `stacks_file` (both leaf-self and inclusive frames), used by `flame.w` to
  # highlight AST performance inspection findings that occur inside hot code.
  -> .hot_functions(stacks_file, top_n)
    hot = {}
    folded = read_file(stacks_file)
    if folded == nil
      return hot
    lines = folded.split("\n")
    leaf_counts = {}
    incl_counts = {}
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        if sp
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
        else
          stack = line
          count = 0
        if count > 0 && !Tungsten:Flame:Folded.idle_stack?(stack)
          frames = stack.split(";")
          leaf = Tungsten:Flame:Folded.normalize_frame(frames.last())
          if !Tungsten:Flame:Folded.infra_leaf?(leaf)
            if leaf_counts.has_key?(leaf)
              leaf_counts[leaf] = leaf_counts[leaf] + count
            else
              leaf_counts[leaf] = count
          seen = {}
          fi = 0
          while fi < frames.size()
            f = Tungsten:Flame:Folded.normalize_frame(frames[fi])
            if !seen.has_key?(f) && !Tungsten:Flame:Folded.infra_leaf?(f)
              seen[f] = true
              if incl_counts.has_key?(f)
                incl_counts[f] = incl_counts[f] + count
              else
                incl_counts[f] = count
            fi = fi + 1
      i = i + 1

    -> record_top(counts_map, n_limit, out_hot)
      pairs = []
      counts_map.keys().each -> (fn_name)
        pairs.push([fn_name, counts_map[fn_name]])
      pairs = pairs.sort_by -> (p) -p[1]
      lim = n_limit
      if lim > pairs.size()
        lim = pairs.size()
      idx = 0
      while idx < lim
        fname = pairs[idx][0]
        out_hot[fname] = true
        if fname.starts_with?("__w_")
          out_hot[fname.slice(4, fname.size() - 4)] = true
        idx = idx + 1

    record_top(leaf_counts, top_n, hot)
    record_top(incl_counts, top_n, hot)
    hot
