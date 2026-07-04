# analyzer.w — Folded-stack profile analyzer.
#
# Takes a folded-stacks file path, a top_n cutoff, a category set name
# ("general" / "lexer" / "ruby" / "external"), an optional focus function
# name (empty string to auto-pick the top function when >40% self), and a
# color flag. Prints a profile breakdown — Top Functions, caller/callee
# breakdown, category bars — to stdout.
#
# Invoked by:
#   - flame.w's legacy FLAME_MODE=display path (called from runner.rb)
#   - flame.w's pure-Tungsten dispatch (stages B-F of the runner port)

in Tungsten:Flame

+ FlameAnalyzer

  -> .display(stacks_file, top_n, category_set, focus_in, color)
    focus = focus_in

    bold  = color ? "\e[1m" : ""
    dim   = color ? "\e[2m" : ""
    reset = color ? "\e[0m" : ""

    # Format a percentage from count/total using integer math (avoids BigDecimal sci notation)
    -> fmt_pct(n, total_n)
      pct_x10 = n * 1000 / total_n
      whole = pct_x10 / 10
      frac = pct_x10 - whole * 10
      s = whole.to_s() + "." + frac.to_s()
      while s.size() < 5
        s = " " + s
      s

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
        stacks.push({ stack: stack, count: count })
        total = total + count
        if stack.includes?("kevent") || stack.includes?("poll")
          idle = idle + count
      i = i + 1

    active = total - idle
    if active == 0
      << "No active samples."
      return

    # Count leaf-only (self time) for top functions
    leaf_counts = {}
    i = 0
    while i < stacks.size()
      entry = stacks[i]
      stack = entry[:stack]
      count = entry[:count]
      if !stack.includes?("kevent") && !stack.includes?("poll")
        frames = stack.split(";")
        leaf = frames.last()
        plus_idx = leaf.rindex(" + ")
        if plus_idx
          rest = leaf.slice(plus_idx + 3, leaf.size())
          if rest.size() > 0 && rest.to_i().to_s() == rest
            leaf = leaf.slice(0, plus_idx)
        backtick = leaf.rindex("`")
        if backtick
          leaf = leaf.slice(backtick + 1, leaf.size())
        if leaf_counts.has_key?(leaf)
          leaf_counts[leaf] = leaf_counts[leaf] + count
        else
          leaf_counts[leaf] = count
      i = i + 1

    # Filter out infrastructure frames
    infra_names = ["start", "main", "dyld", "_pthread", "Thread_", "DispatchQueue", "_ctx_start", "g_body_entry"]
    filtered = {}
    leaf_counts.keys().each -> (func_name)
      skip = false
      j = 0
      while j < infra_names.size()
        if func_name.includes?(infra_names[j])
          skip = true
          break
        j = j + 1
      if !skip
        filtered[func_name] = leaf_counts[func_name]

    # Sort by count descending — build sorted pairs
    sorted_fns = []
    filtered.keys().each -> (func_name)
      sorted_fns.push([func_name, filtered[func_name]])

    j = 1
    while j < sorted_fns.size()
      key_pair = sorted_fns[j]
      k = j - 1
      while k >= 0 && sorted_fns[k][1] < key_pair[1]
        sorted_fns[k + 1] = sorted_fns[k]
        k = k - 1
      sorted_fns[k + 1] = key_pair
      j = j + 1

    # Categorize samples
    -> matches_general(frame)
      if frame.includes?("w_method_call") || frame.includes?("w_method_dispatch") || frame.includes?("call_closure")
        return "method call"
      if frame.includes?("GC_") || frame.includes?("w_gc_") || frame.includes?("w_alloc") || frame.includes?("malloc") || frame.includes?("realloc") || frame.includes?("calloc") || frame.includes?("w_array_push")
        return "allocation"
      if frame.includes?("w_str_") || frame.includes?("w_string") || frame.includes?("strlen") || frame.includes?("memcpy") || frame.includes?("memmove") || frame.includes?("w_strbuf")
        return "string ops"
      if frame.includes?("w_int") || frame.includes?("w_add") || frame.includes?("w_sub") || frame.includes?("w_mul")
        return "integer ops"
      if frame.includes?("w_eq") || frame.includes?("w_cmp") || frame.includes?("w_lt") || frame.includes?("w_gt")
        return "comparison"
      if frame.includes?("w_hash") || frame.includes?("w_map") || frame.includes?("w_dict") || frame.includes?("w_table")
        return "hash/map"
      if frame.includes?("libsystem_kernel")
        return "syscall"
      nil

    -> matches_lexer(frame)
      if frame.includes?("tokenize")
        return "tokenize"
      if frame.includes?("w_str_") || frame.includes?("w_string") || frame.includes?("strlen") || frame.includes?("memcpy") || frame.includes?("memmove") || frame.includes?("w_strbuf")
        return "string ops"
      if frame.includes?("w_method_call") || frame.includes?("w_method_dispatch") || frame.includes?("call_closure")
        return "method call"
      if frame.includes?("GC_") || frame.includes?("w_gc_") || frame.includes?("w_alloc") || frame.includes?("malloc") || frame.includes?("realloc") || frame.includes?("calloc") || frame.includes?("w_array_push")
        return "allocation"
      if frame.includes?("w_eq") || frame.includes?("w_cmp") || frame.includes?("w_lt") || frame.includes?("w_gt")
        return "comparison"
      if frame.includes?("w_hash") || frame.includes?("w_map") || frame.includes?("w_dict") || frame.includes?("w_table")
        return "hash/map"
      if frame.includes?("w_int") || frame.includes?("w_add") || frame.includes?("w_sub") || frame.includes?("w_mul")
        return "integer ops"
      nil

    -> matches_ruby(frame)
      if frame.includes?("(garbage collection)") || frame.includes?("GC")
        return "gc"
      if frame.includes?("Tungsten::Lexer#") || frame.includes?("Tungsten::Parser#") || frame.includes?("parse_with_file")
        return "parse/lex"
      if frame.includes?("Tungsten::Interpreter#evaluate") || frame.includes?("Tungsten::Interpreter#visit_") || frame.includes?("Tungsten::Interpreter#call_") || frame.includes?("Tungsten::Interpreter#invoke_block") || frame.includes?("Tungsten::Interpreter#run")
        return "interpreter"
      if frame.includes?("Tungsten::Environment#")
        return "environment"
      if frame.includes?("Array#") || frame.includes?("Hash#") || frame.includes?("String#") || frame.includes?("Enumerable#")
        return "ruby core"
      if frame.includes?("Kernel#require")
        return "require"
      nil

    -> matches_external(frame)
      if frame.includes?("malloc") || frame.includes?("realloc") || frame.includes?("calloc") || frame.includes?("free") || frame.includes?("operator new")
        return "allocation"
      if frame.includes?("GC") || frame.includes?("mark") || frame.includes?("sweep")
        return "gc"
      if frame.includes?("vm_") || frame.includes?("rb_") || frame.includes?("Py") || frame.includes?("objc_msgSend") || frame.includes?("swift_")
        return "runtime/vm"
      if frame.includes?("libsystem_kernel") || frame.includes?("kevent") || frame.includes?("poll") || frame.includes?("futex") || frame.includes?("epoll")
        return "syscall"
      if frame.includes?("strlen") || frame.includes?("strcmp") || frame.includes?("memcpy") || frame.includes?("memmove") || frame.includes?("memset")
        return "string ops"
      if frame.includes?("pthread") || frame.includes?("mutex") || frame.includes?("lock")
        return "locking"
      nil

    cat_samples = {}
    i = 0
    while i < stacks.size()
      entry = stacks[i]
      stack = entry[:stack]
      count = entry[:count]
      if !stack.includes?("kevent") && !stack.includes?("poll")
        frames = stack.split(";")
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

    j = 1
    while j < sorted_cats.size()
      key_pair = sorted_cats[j]
      k = j - 1
      while k >= 0 && sorted_cats[k][1] < key_pair[1]
        sorted_cats[k + 1] = sorted_cats[k]
        k = k - 1
      sorted_cats[k + 1] = key_pair
      j = j + 1

    # Print breakdown
    << ""
    << "  " + bold + "Profile Breakdown" + reset + "  " + dim + "(" + active.to_s() + " active / " + idle.to_s() + " idle samples)" + reset
    << ""

    << "  " + bold + "Top Functions" + reset
    i = 0
    limit = top_n
    if limit > sorted_fns.size()
      limit = sorted_fns.size()
    while i < limit
      func_name = sorted_fns[i][0]
      n = sorted_fns[i][1]
      pct_str = fmt_pct(n, active)
      fn_color = color ? "\e[38;5;67m" : ""
      << "    " + bold + pct_str + "%" + reset + "  " + fn_color + func_name + reset
      i = i + 1

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
        stack = entry[:stack]
        count = entry[:count]
        if !stack.includes?("kevent") && !stack.includes?("poll")
          frames = stack.split(";")
          fi = 0
          while fi < frames.size()
            frame = frames[fi]
            plus_idx = frame.rindex(" + ")
            if plus_idx
              rest = frame.slice(plus_idx + 3, frame.size())
              if rest.size() > 0 && rest.to_i().to_s() == rest
                frame = frame.slice(0, plus_idx)
            backtick = frame.rindex("`")
            if backtick
              frame = frame.slice(backtick + 1, frame.size())

            if frame == focus
              focus_total = focus_total + count
              if fi > 0
                caller_frame = frames[fi - 1]
                bt = caller_frame.rindex("`")
                if bt
                  caller_frame = caller_frame.slice(bt + 1, caller_frame.size())
                p_idx = caller_frame.rindex(" + ")
                if p_idx
                  r = caller_frame.slice(p_idx + 3, caller_frame.size())
                  if r.size() > 0 && r.to_i().to_s() == r
                    caller_frame = caller_frame.slice(0, p_idx)
                if callers.has_key?(caller_frame)
                  callers[caller_frame] = callers[caller_frame] + count
                else
                  callers[caller_frame] = count
              if fi < frames.size() - 1
                callee_frame = frames[fi + 1]
                bt = callee_frame.rindex("`")
                if bt
                  callee_frame = callee_frame.slice(bt + 1, callee_frame.size())
                p_idx = callee_frame.rindex(" + ")
                if p_idx
                  r = callee_frame.slice(p_idx + 3, callee_frame.size())
                  if r.size() > 0 && r.to_i().to_s() == r
                    callee_frame = callee_frame.slice(0, p_idx)
                if callees.has_key?(callee_frame)
                  callees[callee_frame] = callees[callee_frame] + count
                else
                  callees[callee_frame] = count
            fi = fi + 1
        i = i + 1

      -> sort_pairs(pairs)
        j = 1
        while j < pairs.size()
          key_pair = pairs[j]
          k = j - 1
          while k >= 0 && pairs[k][1] < key_pair[1]
            pairs[k + 1] = pairs[k]
            k = k - 1
          pairs[k + 1] = key_pair
          j = j + 1
        pairs

      fn_color = color ? "\e[38;5;67m" : ""

      if callers.keys().size() > 0
        caller_pairs = []
        callers.keys().each -> (c)
          caller_pairs.push([c, callers[c]])
        caller_pairs = sort_pairs(caller_pairs)

        << "  " + bold + "Callers of " + reset + fn_color + focus + reset
        ci = 0
        c_limit = 8
        if c_limit > caller_pairs.size()
          c_limit = caller_pairs.size()
        while ci < c_limit
          pct_str = fmt_pct(caller_pairs[ci][1], focus_total)
          << "    " + bold + pct_str + "%" + reset + "  " + fn_color + caller_pairs[ci][0] + reset
          ci = ci + 1

      if callees.keys().size() > 0
        callee_pairs = []
        callees.keys().each -> (c)
          callee_pairs.push([c, callees[c]])
        callee_pairs = sort_pairs(callee_pairs)

        << "  " + bold + "Callees of " + reset + fn_color + focus + reset
        ci = 0
        c_limit = 8
        if c_limit > callee_pairs.size()
          c_limit = callee_pairs.size()
        while ci < c_limit
          pct_str = fmt_pct(callee_pairs[ci][1], focus_total)
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

        pct_str = fmt_pct(n, active)
        cat_str = cat
        while cat_str.size() < 12
          cat_str = cat_str + " "

        << "  " + bar + "  " + bold + pct_str + "%" + reset + "  " + cat_str + "  " + dim + "(" + n.to_s() + ")" + reset
      i = i + 1

    << ""

  # Compact per-metric Top-N section. Used by flame.w to render
  # secondary metrics (e.g., "Top Branch Misses") without caller/callee
  # + category bars that .display emits for the primary metric.
  -> .display_top_only(stacks_file, top_n, label, color)
    bold  = color ? "\e[1m" : ""
    reset = color ? "\e[0m" : ""
    fn_color = color ? "\e[38;5;67m" : ""

    -> tpfmt_pct(n, t)
      pct_x10 = n * 1000 / t
      whole = pct_x10 / 10
      frac = pct_x10 - whole * 10
      s = whole.to_s() + "." + frac.to_s()
      while s.size() < 5
        s = " " + s
      s

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
        if !stack.includes?("kevent") && !stack.includes?("poll")
          frames = stack.split(";")
          leaf = frames.last()
          plus_idx = leaf.rindex(" + ")
          if plus_idx
            rest = leaf.slice(plus_idx + 3, leaf.size())
            if rest.size() > 0 && rest.to_i().to_s() == rest
              leaf = leaf.slice(0, plus_idx)
          backtick = leaf.rindex("`")
          if backtick
            leaf = leaf.slice(backtick + 1, leaf.size())
          if leaf_counts.has_key?(leaf)
            leaf_counts[leaf] = leaf_counts[leaf] + count
          else
            leaf_counts[leaf] = count
          total = total + count
      i = i + 1

    if total == 0
      << "  " + bold + "Top " + label + reset + "  (no samples)"
      return

    sorted = []
    leaf_counts.keys().each -> (func_name)
      sorted.push([func_name, leaf_counts[func_name]])
    j = 1
    while j < sorted.size()
      kp = sorted[j]
      k = j - 1
      while k >= 0 && sorted[k][1] < kp[1]
        sorted[k + 1] = sorted[k]
        k = k - 1
      sorted[k + 1] = kp
      j = j + 1

    << ""
    << "  " + bold + "Top " + label + reset
    limit = top_n
    if limit > sorted.size()
      limit = sorted.size()
    i = 0
    while i < limit
      pct = tpfmt_pct(sorted[i][1], total)
      << "    " + bold + pct + "%" + reset + "  " + fn_color + sorted[i][0] + reset
      i = i + 1
