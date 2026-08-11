# counter_rates.w — Per-function IPC / miss-rate table from counter
# folded stacks.
#
# `flame --counters` (the "rates" set) records instructions and cycles
# alongside the miss families, all attributed to the same sampled
# stacks. That pairing is what turns raw event counts into rates: for
# each function we can divide its miss events by its own instructions —
# misses per kilo-instruction (MPKI) — and its instructions by its own
# cycles (IPC). Raw counts say where events happened; rates say which
# code is actually cache-hostile, independent of how hot it is.
#
# Input is the { metric_name => folded_text } dict the sampler returns
# (after sidemap rewriting), so the math keys off the same self-count
# convention the analyzer displays: a function's count is the events
# attributed to samples where it was the leaf frame.

in Tungsten:Flame

+ CounterRates

  # Render the per-function rates table. Requires the "instructions"
  # and "cycles" metrics (the rates template records both); every other
  # metric present becomes a per-kilo-instruction column. Returns "" if
  # the required metrics are missing or empty — callers skip printing.
  -> .report(folded_by_metric, top_n, color)
    if !folded_by_metric.has_key?("instructions") || !folded_by_metric.has_key?("cycles")
      return ""
    inst = self.self_counts(folded_by_metric["instructions"])
    cyc = self.self_counts(folded_by_metric["cycles"])
    inst_counts = inst[0]
    inst_total = inst[1]
    cyc_counts = cyc[0]
    cyc_total = cyc[1]
    if inst_total == 0 || cyc_total == 0
      return ""

    # Miss columns: every metric except the two denominators, in the
    # dict's slot order.
    miss_names = []
    folded_by_metric.keys().each -> (mname)
      if mname != "instructions" && mname != "cycles"
        miss_names.push(mname)
    miss_counts = []
    mi = 0
    while mi < miss_names.size()
      miss_counts.push(self.self_counts(folded_by_metric[miss_names[mi]]))
      mi = mi + 1

    bold  = color ? "\e[1m" : ""
    dim   = color ? "\e[2m" : ""
    reset = color ? "\e[0m" : ""
    fn_color = color ? "\e[38;5;67m" : ""

    # Rank functions by self instructions.
    ranked = []
    inst_counts.keys().each -> (fname)
      ranked.push([fname, inst_counts[fname]])
    j = 1
    while j < ranked.size()
      kp = ranked[j]
      k = j - 1
      while k >= 0 && ranked[k][1] < kp[1]
        ranked[k + 1] = ranked[k]
        k = k - 1
      ranked[k + 1] = kp
      j = j + 1

    name_w = 36
    out = []
    out.push("")
    out.push("  " + bold + "Counter rates (per function, self counts)" + reset)
    header = "  " + self.pad_right("function", name_w) + self.pad_left("inst%", 7) + self.pad_left("IPC", 7)
    mi = 0
    while mi < miss_names.size()
      header = header + self.pad_left(self.column_label(miss_names[mi]), 11)
      mi = mi + 1
    out.push(header)

    limit = top_n
    if limit > ranked.size()
      limit = ranked.size()
    i = 0
    while i < limit
      fname = ranked[i][0]
      fn_inst = ranked[i][1]
      line = "  " + fn_color + self.pad_right(self.truncate(fname, name_w - 1), name_w) + reset
      line = line + self.pad_left(self.fmt_x10(fn_inst * 1000 / inst_total), 6) + "%"
      fn_cyc = cyc_counts.has_key?(fname) ? cyc_counts[fname] : 0
      line = line + self.pad_left(fn_cyc > 0 ? self.fmt_x100(fn_inst * 100 / fn_cyc) : "-", 7)
      mi = 0
      while mi < miss_names.size()
        mpair = miss_counts[mi]
        mc = mpair[0]
        fn_miss = mc.has_key?(fname) ? mc[fname] : 0
        line = line + self.pad_left(self.fmt_x100(fn_miss * 100000 / fn_inst), 11)
        mi = mi + 1
      out.push(line)
      i = i + 1

    # Whole-profile totals row.
    tline = "  " + bold + self.pad_right("(all sampled)", name_w) + self.pad_left("100.0", 6) + "%"
    tline = tline + self.pad_left(self.fmt_x100(inst_total * 100 / cyc_total), 7)
    mi = 0
    while mi < miss_names.size()
      mpair = miss_counts[mi]
      tline = tline + self.pad_left(self.fmt_x100(mpair[1] * 100000 / inst_total), 11)
      mi = mi + 1
    tline = tline + reset
    out.push(tline)
    out.push("  " + dim + "IPC = instructions/cycles; miss columns are events per kilo-instruction (self)" + reset)
    out.join("\n")

  # Leaf self-counts for one folded text: [ { fn => count }, total ].
  # Leaf normalization mirrors the analyzer: drop " + N" offsets, strip
  # the "lib`" prefix, skip kevent/poll wait stacks.
  -> .self_counts(folded_text)
    counts = {}
    total = 0
    if folded_text == nil
      return [counts, 0]
    lines = folded_text.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        if sp != nil
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
          if !stack.include?("kevent") && !stack.include?("poll")
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
            if counts.has_key?(leaf)
              counts[leaf] = counts[leaf] + count
            else
              counts[leaf] = count
            total = total + count
      i = i + 1
    [counts, total]

  # Short column labels for the known metric names; anything else keeps
  # its own name with a /KI suffix.
  -> .column_label(metric_name)
    if metric_name == "L1-dcache-load-misses"
      return "L1d-ld/KI"
    if metric_name == "L1-dcache-store-misses"
      return "L1d-st/KI"
    if metric_name == "LLC-load-misses"
      return "L2-ld/KI"
    if metric_name == "memsys-loads"
      return "mem-ld/KI"
    if metric_name == "dTLB-misses"
      return "dTLB/KI"
    if metric_name == "L2-TLB-data-misses"
      return "L2TLB/KI"
    metric_name + "/KI"

  # "1234" (a value scaled x10) -> "123.4"
  -> .fmt_x10(x10)
    whole = x10 / 10
    frac = x10 - whole * 10
    whole.to_s() + "." + frac.to_s()

  # "1234" (a value scaled x100) -> "12.34"
  -> .fmt_x100(x100)
    whole = x100 / 100
    frac = x100 - whole * 100
    frac_s = frac.to_s()
    if frac < 10
      frac_s = "0" + frac_s
    whole.to_s() + "." + frac_s

  -> .pad_left(s, w)
    out = s.to_s()
    while out.size() < w
      out = " " + out
    out

  -> .pad_right(s, w)
    out = s.to_s()
    while out.size() < w
      out = out + " "
    out

  -> .truncate(s, w)
    if s.size() <= w
      return s
    s.slice(0, w - 2) + ".."
