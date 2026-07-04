# xctrace_xml.w — Parse xctrace XML export into folded stacks.
#
# xctrace's `--xpath ...time-sample...` export produces XML where each
# <row> is one sample. The cp-user-callstack column is a <kperf-bt>
# element that's either an inline definition (`id="N"`) with a child
# <text-addresses> holding space-separated decimal address values, or
# a reference (`ref="N"`) pointing back to an earlier inline.
#
# This module:
#   1. Scans the XML once, building a dict mapping kperf-bt id → addresses.
#   2. Walks <row>s, resolves each row's user-stack reference.
#   3. Emits folded format with addresses as frame names. (No
#      symbolication yet — that's a clean follow-up using `atos -o BIN`.)
#
# Output: same format PerfScript.collapse produces, so the analyzer
# treats both Linux and macOS sources identically.

in Tungsten:Flame

+ XctraceXml

  -> .collapse(xml_text, binary_path)
    # 1. Build id → addresses dict from inline kperf-bt blocks.
    addrs_by_id = XctraceXml.parse_kperf_bts(xml_text)

    # 2. Walk rows, accumulate folded stacks (still as hex addresses).
    folded = {}
    rows_text = xml_text
    cur = 0
    while true
      row_start = XctraceXml.find_from(rows_text, "<row>", cur)
      if row_start == nil
        break
      row_end = XctraceXml.find_from(rows_text, "</row>", row_start)
      if row_end == nil
        break
      row = rows_text.slice(row_start, row_end - row_start)
      cur = row_end + 6

      addrs = XctraceXml.row_user_stack(row, addrs_by_id)
      if addrs != nil && addrs.size() > 0
        folded_stack = XctraceXml.reverse(addrs).join(";")
        if folded.has_key?(folded_stack)
          folded[folded_stack] = folded[folded_stack] + 1
        else
          folded[folded_stack] = 1

    # 3. Symbolicate via atos. Collect every unique address that appears
    #    in any folded stack, run `atos -o BIN` in one batch, build a
    #    dict, then rewrite each folded stack with symbol names.
    sym = XctraceXml.symbolicate(folded.keys(), binary_path)

    out = []
    keys = XctraceXml.sort_strings(folded.keys())
    i = 0
    while i < keys.size()
      raw_stack = keys[i]
      frames = raw_stack.split(";")
      symbolic = []
      fi = 0
      while fi < frames.size()
        addr = frames[fi]
        if sym.has_key?(addr)
          symbolic.push(sym[addr])
        else
          symbolic.push(addr)
        fi = fi + 1
      out.push(symbolic.join(";") + " " + folded[raw_stack].to_s())
      i = i + 1
    out.join("\n")

  # Collect unique addresses from folded-stack keys, run atos once, return
  # a dict mapping address-string → symbol-name. Addresses that atos can't
  # resolve (kernel, system libs without dSYMs) stay out of the dict so
  # the caller falls back to the raw hex.
  -> .symbolicate(stack_keys, binary_path)
    result = {}
    if binary_path == nil || binary_path == ""
      return result
    # Gather unique addresses
    addr_set = {}
    i = 0
    while i < stack_keys.size()
      frames = stack_keys[i].split(";")
      fi = 0
      while fi < frames.size()
        addr_set[frames[fi]] = true
        fi = fi + 1
      i = i + 1
    addrs = addr_set.keys()
    if addrs.size() == 0
      return result
    # Build batch atos command
    bin_q = Builder.shell_quote(binary_path)
    cmd = "atos -o " + bin_q
    j = 0
    while j < addrs.size()
      cmd = cmd + " " + addrs[j]
      j = j + 1
    out_text = capture(cmd + " 2>/dev/null")
    if out_text == nil
      return result
    lines = out_text.split("\n")
    # Each line is either a symbol like "name (in BIN) (file:line)" or the
    # address itself if atos couldn't resolve. Strip the trailing parens.
    k = 0
    while k < lines.size() && k < addrs.size()
      line = lines[k].strip()
      if line.size() > 0 && !line.starts_with?("0x")
        # Strip " (in ...)" and any trailing " (...)"
        paren = line.index(" (")
        if paren != nil
          line = line.slice(0, paren)
        if line.size() > 0
          result[addrs[k]] = line
      k = k + 1
    result

  # Multi-metric collapse over the kdebug-counters-with-time-sample schema.
  # `metric_names` maps slot index N to a user-facing metric label.
  # Apple's PMC export duplicates the values (8 events → 16 columns), so
  # we only read the first n_metrics slots.
  #
  # Counter values are cumulative per-(thread, core). When a thread moves
  # cores, the new core's counter reading isn't comparable to the prior
  # one — we treat that as "no baseline yet" and start fresh for that key.
  -> .collapse_counters(xml_text, binary_path, metric_names)
    addrs_by_id = XctraceXml.parse_kperf_bts(xml_text)
    n_metrics = metric_names.size()

    # Per-(thread:core) previous counter snapshot.
    prev_vals = {}

    # Per-metric stack → cumulative-delta dict.
    folded_by_metric = {}
    i = 0
    while i < n_metrics
      folded_by_metric[metric_names[i]] = {}
      i = i + 1

    # Track thread-state ids that correspond to "Running". The XML
    # exports only the first occurrence of a given state with its label;
    # subsequent rows reference the id via `<thread-state ref="N"/>`.
    running_ids = {}

    cur = 0
    while true
      row_start = XctraceXml.find_from(xml_text, "<row>", cur)
      if row_start == nil
        break
      row_end = XctraceXml.find_from(xml_text, "</row>", row_start)
      if row_end == nil
        break
      row = xml_text.slice(row_start, row_end - row_start)
      cur = row_end + 6

      ts_key = XctraceXml.extract_tag_key(row, "<thread-state")
      if row.includes?("fmt=\"Running\"")
        running_ids[ts_key] = true

      if running_ids.has_key?(ts_key)
        thread_key = XctraceXml.extract_tag_key(row, "<thread")
        core_key   = XctraceXml.extract_tag_key(row, "<core")
        pmc_vals   = XctraceXml.extract_pmc_values(row)
        if pmc_vals.size() >= n_metrics
          addrs = XctraceXml.row_user_stack(row, addrs_by_id)
          key = thread_key + ":" + core_key
          if addrs != nil && addrs.size() > 0 && prev_vals.has_key?(key)
            prev = prev_vals[key]
            folded_stack = XctraceXml.reverse(addrs).join(";")
            m = 0
            while m < n_metrics
              delta = pmc_vals[m] - prev[m]
              if delta > 0
                metric = metric_names[m]
                fd = folded_by_metric[metric]
                if fd.has_key?(folded_stack)
                  fd[folded_stack] = fd[folded_stack] + delta
                else
                  fd[folded_stack] = delta
              m = m + 1
          prev_vals[key] = pmc_vals

    # Symbolicate all unique addresses across every metric in one batch.
    all_keys = []
    mi = 0
    while mi < n_metrics
      fd = folded_by_metric[metric_names[mi]]
      fd.keys().each -> (k)
        all_keys.push(k)
      mi = mi + 1
    sym = XctraceXml.symbolicate(all_keys, binary_path)

    result = {}
    mi = 0
    while mi < n_metrics
      name = metric_names[mi]
      fd = folded_by_metric[name]
      keys = XctraceXml.sort_strings(fd.keys())
      lines = []
      ki = 0
      while ki < keys.size()
        k = keys[ki]
        frames = k.split(";")
        symbolic = []
        fri = 0
        while fri < frames.size()
          addr = frames[fri]
          if sym.has_key?(addr)
            symbolic.push(sym[addr])
          else
            symbolic.push(addr)
          fri = fri + 1
        lines.push(symbolic.join(";") + " " + fd[k].to_s())
        ki = ki + 1
      result[name] = lines.join("\n")
      mi = mi + 1
    result

  # Find the first `<thread...>` or `<core...>` opening tag in `row` and
  # return its `id="..."` or `ref="..."` value as a string. Returns "?"
  # if neither attribute is present.
  -> .extract_tag_key(row, tag_prefix)
    pos = row.index(tag_prefix)
    if pos == nil
      return "?"
    gt = XctraceXml.find_from(row, ">", pos)
    if gt == nil
      return "?"
    tag = row.slice(pos, gt - pos + 1)
    id_idx = tag.index("id=\"")
    ref_idx = tag.index("ref=\"")
    val_start = nil
    if id_idx != nil
      val_start = id_idx + 4
    elsif ref_idx != nil
      val_start = ref_idx + 5
    if val_start == nil
      return "?"
    rest = tag.slice(val_start, tag.size() - val_start)
    q = rest.index("\"")
    if q == nil
      return "?"
    rest.slice(0, q)

  # Parse the text content of a `<pmc-events>VALUES</pmc-events>` element
  # into a list of integers. Returns empty list if not present.
  -> .extract_pmc_values(row)
    pos = row.index("<pmc-events")
    if pos == nil
      return []
    gt = XctraceXml.find_from(row, ">", pos)
    if gt == nil
      return []
    close = XctraceXml.find_from(row, "</pmc-events>", gt)
    if close == nil
      return []
    text = row.slice(gt + 1, close - gt - 1)
    out = []
    parts = text.split(" ")
    pi = 0
    while pi < parts.size()
      p = parts[pi].strip()
      if p.size() > 0
        out.push(p.to_i())
      pi = pi + 1
    out

  # Walk all `<kperf-bt id="N" ...><text-addresses ...>A B C</text-addresses>...</kperf-bt>`
  # blocks and return { N => [A, B, C] }.
  -> .parse_kperf_bts(xml)
    result = {}
    cur = 0
    while true
      ks = XctraceXml.find_from(xml, "<kperf-bt id=\"", cur)
      if ks == nil
        break
      id_start = ks + 14  # past "<kperf-bt id=\""
      id_end = XctraceXml.find_from(xml, "\"", id_start)
      if id_end == nil
        break
      id_str = xml.slice(id_start, id_end - id_start)

      # Find <text-addresses ...>ADDRS</text-addresses> inside this kperf-bt
      ta_open = XctraceXml.find_from(xml, "<text-addresses", id_end)
      gt = (ta_open != nil) ? XctraceXml.find_from(xml, ">", ta_open) : nil
      ta_close = (gt != nil) ? XctraceXml.find_from(xml, "</text-addresses>", gt) : nil
      if ta_close == nil
        cur = id_end + 1
      else
        addrs_str = xml.slice(gt + 1, ta_close - gt - 1)
        addrs = []
        parts = addrs_str.split(" ")
        pi = 0
        while pi < parts.size()
          p = parts[pi].strip()
          if p.size() > 0 && p != "0"
            addrs.push("0x" + XctraceXml.dec_to_hex(p))
          pi = pi + 1
        result[id_str] = addrs
        cur = ta_close + 16

    result

  # For a <row>...</row> chunk, return the user-stack as a list of
  # address strings, or nil if unresolvable.
  -> .row_user_stack(row, addrs_by_id)
    # First check for an inline kperf-bt with text-addresses — these
    # ARE the user-stack (the inline form). Take the LAST one in the
    # row (kernel comes first, user second).
    bts = XctraceXml.all_kperf_refs(row)
    if bts.size() == 0
      return nil
    last = bts[bts.size() - 1]
    if addrs_by_id.has_key?(last)
      addrs_by_id[last]
    else
      nil

  # Return the list of every kperf-bt id or ref string in `row`.
  -> .all_kperf_refs(row)
    refs = []
    cur = 0
    while true
      pos = XctraceXml.find_from(row, "<kperf-bt", cur)
      if pos == nil
        break
      # Look for id="N" or ref="N"
      gt = XctraceXml.find_from(row, ">", pos)
      if gt == nil
        break
      tag = row.slice(pos, gt - pos + 1)
      id_idx = tag.index("id=\"")
      ref_idx = tag.index("ref=\"")
      val_start = nil
      if id_idx != nil
        val_start = id_idx + 4
      elsif ref_idx != nil
        val_start = ref_idx + 5
      if val_start != nil
        rest = tag.slice(val_start, tag.size() - val_start)
        q = rest.index("\"")
        if q != nil
          refs.push(rest.slice(0, q))
      cur = gt + 1
    refs

  # Find `needle` in `haystack` starting from `start`, returning the
  # byte position or nil. Tungsten's .index doesn't accept a start offset.
  -> .find_from(haystack, needle, start)
    rest = haystack.slice(start, haystack.size() - start)
    pos = rest.index(needle)
    pos != nil ? start + pos : nil

  -> .reverse(arr)
    out = []
    i = arr.size() - 1
    while i >= 0
      out.push(arr[i])
      i = i - 1
    out

  -> .sort_strings(xs)
    arr = []
    i = 0
    while i < xs.size()
      arr.push(xs[i])
      i = i + 1
    j = 1
    while j < arr.size()
      key = arr[j]
      k = j - 1
      while k >= 0 && arr[k] > key
        arr[k + 1] = arr[k]
        k = k - 1
      arr[k + 1] = key
      j = j + 1
    arr

  -> .dec_to_hex(dec_str)
    n = dec_str.to_i()
    if n == 0
      return "0"
    out = ""
    while n > 0
      d = n % 16
      c = "0"
      if d == 0
        c = "0"
      elsif d == 1
        c = "1"
      elsif d == 2
        c = "2"
      elsif d == 3
        c = "3"
      elsif d == 4
        c = "4"
      elsif d == 5
        c = "5"
      elsif d == 6
        c = "6"
      elsif d == 7
        c = "7"
      elsif d == 8
        c = "8"
      elsif d == 9
        c = "9"
      elsif d == 10
        c = "a"
      elsif d == 11
        c = "b"
      elsif d == 12
        c = "c"
      elsif d == 13
        c = "d"
      elsif d == 14
        c = "e"
      elsif d == 15
        c = "f"
      out = c + out
      n = n / 16
    out
