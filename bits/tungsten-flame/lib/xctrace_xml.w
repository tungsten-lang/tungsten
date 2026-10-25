# xctrace_xml.w — Parse xctrace XML export into folded stacks.

in Tungsten:Flame

+ XctraceXml

  -> .collapse(xml_text, binary_path, load_addr)
    # 1. Build id → addresses dict from inline kperf-bt blocks.
    addrs_by_id = self.parse_kperf_bts(xml_text)

    # 2. Walk rows, accumulate folded stacks (still as hex addresses).
    folded = {}
    row_chunks = xml_text.split("<row>")
    ri = 1
    while ri < row_chunks.size()
      chunk = row_chunks[ri]
      row_end = chunk.index("</row>")
      row = row_end != nil ? chunk.slice(0, row_end) : chunk
      ri = ri + 1

      addrs = self.row_user_stack(row, addrs_by_id)
      if addrs != nil && addrs.size() > 0
        folded_stack = addrs.reverse().join(";")
        if folded.has_key?(folded_stack)
          folded[folded_stack] = folded[folded_stack] + 1
        else
          folded[folded_stack] = 1

    # 3. Symbolicate via atos in one batch.
    sym = self.symbolicate(folded.keys(), binary_path, load_addr)

    out = []
    keys = folded.keys().sort()
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
  # a dict mapping address-string → symbol-name.
  -> .symbolicate(stack_keys, binary_path, load_addr)
    result = {}
    if binary_path == nil || binary_path == ""
      return result
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
    bin_q = Tungsten:Flame:Builder.shell_quote(binary_path)
    cmd = "atos -o " + bin_q
    if load_addr != nil && load_addr != ""
      cmd = cmd + " -l " + load_addr
    j = 0
    while j < addrs.size()
      cmd = cmd + " " + addrs[j]
      j = j + 1
    out_text = capture(cmd + " 2>/dev/null")
    if out_text == nil
      return result
    lines = out_text.split("\n")
    k = 0
    while k < lines.size() && k < addrs.size()
      line = lines[k].strip()
      if line.size() > 0 && !line.starts_with?("0x")
        paren = line.index(" (")
        if paren != nil
          line = line.slice(0, paren)
        if line.size() > 0
          result[addrs[k]] = line
      k = k + 1

    # Second pass: resolve dyld-shared-cache addresses against our own live PID.
    unresolved = []
    u = 0
    while u < addrs.size()
      if !result.has_key?(addrs[u]) && self.shared_cache_addr?(addrs[u])
        unresolved.push(addrs[u])
      u = u + 1
    if unresolved.size() > 0
      pid = self.own_pid()
      if pid != ""
        cmd2 = "atos -p " + pid
        j = 0
        while j < unresolved.size()
          cmd2 = cmd2 + " " + unresolved[j]
          j = j + 1
        out2 = capture(cmd2 + " 2>/dev/null")
        if out2 != nil
          lines2 = out2.split("\n")
          k = 0
          while k < lines2.size() && k < unresolved.size()
            name = self.parse_atos_system_line(lines2[k])
            if name != nil
              result[unresolved[k]] = name
            k = k + 1
    result

  -> .own_pid()
    capture("echo $PPID").strip()

  -> .hex_to_int(s)
    sz = s.size()
    if !s.starts_with?("0x") || sz > 14
      return 0
    n = 0
    i = 2
    while i < sz
      b = s.byte_at(i)
      d = -1
      if b >= 48 && b <= 57
        d = b - 48
      elsif b >= 97 && b <= 102
        d = b - 87
      elsif b >= 65 && b <= 70
        d = b - 55
      if d < 0
        return 0
      n = (n << 4) + d
      i = i + 1
    n

  -> .shared_cache_addr?(addr_str)
    n = self.hex_to_int(addr_str)
    n >= 6442450944 && n < 68719476736

  -> .parse_atos_system_line(line)
    s = line.strip()
    if s.size() == 0 || s.starts_with?("0x")
      return nil
    paren = s.index(" (in ")
    if paren == nil
      p2 = s.index(" (")
      if p2 != nil
        return s.slice(0, p2)
      return s
    sym = s.slice(0, paren)
    rest = s.slice(paren + 5, s.size())
    close = rest.index(")")
    if close == nil
      return sym
    lib = rest.slice(0, close)
    lib + "`" + sym

  # Multi-metric collapse over the kdebug-counters-with-*-sample schema.
  -> .collapse_counters(xml_text, binary_path, load_addr, metric_names)
    addrs_by_id = self.parse_kperf_bts(xml_text)
    n_metrics = metric_names.size()
    prev_vals = {}

    folded_by_metric = {}
    i = 0
    while i < n_metrics
      folded_by_metric[metric_names[i]] = {}
      i = i + 1

    running_ids = {}

    row_chunks = xml_text.split("<row>")
    ri = 0
    while true
      ri = ri + 1
      if ri >= row_chunks.size()
        break
      chunk = row_chunks[ri]
      row_end = chunk.index("</row>")
      row = row_end != nil ? chunk.slice(0, row_end) : chunk

      ts_key = self.extract_tag_key(row, "<thread-state")
      if row.include?("fmt=\"Running\"")
        running_ids[ts_key] = true

      if running_ids.has_key?(ts_key)
        core_key   = self.extract_tag_key(row, "<core")
        pmc_vals   = self.extract_pmc_values(row)
        if pmc_vals.size() >= n_metrics
          addrs = self.row_user_stack(row, addrs_by_id)
          key = core_key
          if addrs != nil && addrs.size() > 0 && prev_vals.has_key?(key)
            prev = prev_vals[key]
            folded_stack = addrs.reverse().join(";")
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

    # Deduplicate stack keys across metrics before symbolicating in one batch.
    seen_stacks = {}
    mi = 0
    while mi < n_metrics
      fd = folded_by_metric[metric_names[mi]]
      fd.keys().each -> (k)
        seen_stacks[k] = true
      mi = mi + 1
    sym = self.symbolicate(seen_stacks.keys(), binary_path, load_addr)

    result = {}
    mi = 0
    while mi < n_metrics
      name = metric_names[mi]
      fd = folded_by_metric[name]
      keys = fd.keys().sort()
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

  # Multi-metric collapse over the counters-profile schema.
  -> .collapse_counter_profile(xml_text, binary_path, load_addr, metric_names, proc_marker)
    xml_text = xml_text.split("←").join("-")
    n_metrics = metric_names.size()

    folded_by_metric = {}
    i = 0
    while i < n_metrics
      folded_by_metric[metric_names[i]] = {}
      i = i + 1

    thread_is_target = {}
    bt_by_id = {}

    row_chunks = xml_text.split("<row>")
    ri = 0
    while true
      ri = ri + 1
      if ri >= row_chunks.size()
        break
      chunk = row_chunks[ri]
      row_end = chunk.index("</row>")
      row = row_end != nil ? chunk.slice(0, row_end) : chunk

      is_target = self.row_thread_is_target(row, thread_is_target, proc_marker)
      frames = self.row_profile_stack(row, bt_by_id)
      if is_target && frames != nil && frames.size() > 0
        pmc_vals = self.extract_pmc_values(row)
        if pmc_vals.size() >= n_metrics
          folded_stack = frames.reverse().join(";")
          m = 0
          while m < n_metrics
            delta = pmc_vals[m]
            if delta > 0
              metric = metric_names[m]
              fd = folded_by_metric[metric]
              if fd.has_key?(folded_stack)
                fd[folded_stack] = fd[folded_stack] + delta
              else
                fd[folded_stack] = delta
            m = m + 1

    # Deduplicate stack keys across metrics before symbolicating in one batch.
    seen_stacks = {}
    mi = 0
    while mi < n_metrics
      fd = folded_by_metric[metric_names[mi]]
      fd.keys().each -> (k)
        seen_stacks[k] = true
      mi = mi + 1
    sym = self.symbolicate(seen_stacks.keys(), binary_path, load_addr)

    result = {}
    mi = 0
    while mi < n_metrics
      name = metric_names[mi]
      fd = folded_by_metric[name]
      keys = fd.keys().sort()
      lines = []
      ki = 0
      while ki < keys.size()
        k = keys[ki]
        frames2 = k.split(";")
        symbolic = []
        fri = 0
        while fri < frames2.size()
          addr = frames2[fri]
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

  -> .row_thread_is_target(row, thread_is_target, proc_marker)
    dp = row.index("<thread id=\"")
    if dp != nil
      id_s = dp + 12
      id_e = self.find_from(row, "\"", id_s)
      if id_e == nil
        return false
      tid = row.slice(id_s, id_e - id_s)
      fm = self.find_from(row, "fmt=\"", id_e)
      hit = false
      if fm != nil
        v_s = fm + 5
        v_e = self.find_from(row, "\"", v_s)
        if v_e != nil
          hit = row.slice(v_s, v_e - v_s).include?(proc_marker)
      thread_is_target[tid] = hit
      return hit
    rp = row.index("<thread ref=\"")
    if rp != nil
      r_s = rp + 13
      r_e = self.find_from(row, "\"", r_s)
      if r_e != nil
        rid = row.slice(r_s, r_e - r_s)
        if thread_is_target.has_key?(rid)
          return thread_is_target[rid]
    false

  -> .row_profile_stack(row, bt_by_id)
    dp = row.index("<tagged-backtrace id=\"")
    if dp != nil
      id_s = dp + 22
      id_e = self.find_from(row, "\"", id_s)
      if id_e == nil
        return nil
      bt_id = row.slice(id_s, id_e - id_s)
      close = self.find_from(row, "</tagged-backtrace>", id_e)
      block = close != nil ? row.slice(id_e, close - id_e) : row.slice(id_e, row.size() - id_e)
      frames = []
      cur = 0
      while true
        ap = self.find_from(block, "addr=\"", cur)
        if ap == nil
          break
        a_s = ap + 6
        a_e = self.find_from(block, "\"", a_s)
        if a_e == nil
          break
        frames.push(block.slice(a_s, a_e - a_s))
        cur = a_e + 1
      bt_by_id[bt_id] = frames
      return frames
    rp = row.index("<tagged-backtrace ref=\"")
    if rp != nil
      r_s = rp + 23
      r_e = self.find_from(row, "\"", r_s)
      if r_e != nil
        rid = row.slice(r_s, r_e - r_s)
        if bt_by_id.has_key?(rid)
          return bt_by_id[rid]
    nil

  -> .extract_tag_key(row, tag_prefix)
    pos = row.index(tag_prefix)
    if pos == nil
      return "?"
    gt = self.find_from(row, ">", pos)
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

  -> .extract_pmc_values(row)
    pos = row.index("<pmc-events")
    if pos == nil
      return []
    gt = self.find_from(row, ">", pos)
    if gt == nil
      return []
    close = self.find_from(row, "</pmc-events>", gt)
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

  -> .parse_kperf_bts(xml)
    ta_by_id = {}
    pc_by_id = {}
    result = {}
    pieces = xml.split("<kperf-bt id=\"")
    i = 1
    while i < pieces.size()
      piece = pieces[i]
      q = piece.index("\"")
      close = piece.index("</kperf-bt>")
      if q != nil && close != nil
        id_str = piece.slice(0, q)
        block = piece.slice(q, close - q)
        result[id_str] = self.block_stack(block, ta_by_id, pc_by_id)
      i = i + 1
    result

  -> .block_stack(block, ta_by_id, pc_by_id)
    pc = nil
    ip = block.index("<text-address id=\"")
    if ip != nil
      id_s = ip + 18
      id_e = self.find_from(block, "\"", id_s)
      fm = (id_e != nil) ? self.find_from(block, "fmt=\"", id_e) : nil
      if fm != nil
        v_s = fm + 5
        v_e = self.find_from(block, "\"", v_s)
        if v_e != nil
          pc = block.slice(v_s, v_e - v_s)
          pc_by_id[block.slice(id_s, id_e - id_s)] = pc
    else
      rp = block.index("<text-address ref=\"")
      if rp != nil
        r_s = rp + 19
        r_e = self.find_from(block, "\"", r_s)
        if r_e != nil
          rid = block.slice(r_s, r_e - r_s)
          if pc_by_id.has_key?(rid)
            pc = pc_by_id[rid]

    callers = []
    tp = block.index("<text-addresses id=\"")
    if tp != nil
      id_s = tp + 20
      id_e = self.find_from(block, "\"", id_s)
      gt = (id_e != nil) ? self.find_from(block, ">", id_e) : nil
      ta_close = (gt != nil) ? self.find_from(block, "</text-addresses>", gt) : nil
      if ta_close != nil
        parts = block.slice(gt + 1, ta_close - gt - 1).split(" ")
        pi = 0
        while pi < parts.size()
          p = parts[pi].strip()
          if p.size() > 0 && p != "0"
            callers.push("0x" + self.dec_to_hex(p))
          pi = pi + 1
        ta_by_id[block.slice(id_s, id_e - id_s)] = callers
    else
      rp = block.index("<text-addresses ref=\"")
      if rp != nil
        r_s = rp + 21
        r_e = self.find_from(block, "\"", r_s)
        if r_e != nil
          rid = block.slice(r_s, r_e - r_s)
          if ta_by_id.has_key?(rid)
            callers = ta_by_id[rid]

    frames = []
    if pc != nil
      frames.push(pc)
    ci = 0
    while ci < callers.size()
      c = callers[ci]
      if !(ci == 0 && pc != nil && c == pc)
        frames.push(c)
      ci = ci + 1
    frames

  -> .row_user_stack(row, addrs_by_id)
    bts = self.all_kperf_refs(row)
    if bts.size() == 0
      return self.row_tagged_stack(row, addrs_by_id)
    last = bts[bts.size() - 1]
    if addrs_by_id.has_key?(last)
      addrs_by_id[last]
    else
      nil

  -> .row_tagged_stack(row, addrs_by_id)
    tp = row.index("<tagged-backtrace ref=\"")
    if tp != nil
      r_s = tp + 23
      r_e = self.find_from(row, "\"", r_s)
      if r_e == nil
        return nil
      rid = row.slice(r_s, r_e - r_s)
      if addrs_by_id.has_key?(rid)
        return addrs_by_id[rid]
      return nil
    tp = row.index("<tagged-backtrace id=\"")
    if tp == nil
      return nil
    id_s = tp + 22
    id_e = self.find_from(row, "\"", id_s)
    if id_e == nil
      return nil
    tid2 = row.slice(id_s, id_e - id_s)
    bend = self.find_from(row, "</tagged-backtrace>", tp)
    if bend == nil
      return nil
    seg = row.slice(tp, bend - tp)
    addrs = []
    cur = 0
    while true
      ap = self.find_from(seg, "addr=\"", cur)
      if ap == nil
        break
      v_s = ap + 6
      v_e = self.find_from(seg, "\"", v_s)
      if v_e == nil
        break
      addrs.push(seg.slice(v_s, v_e - v_s))
      cur = v_e
    if addrs.size() == 0
      return nil
    addrs_by_id[tid2] = addrs
    addrs

  -> .all_kperf_refs(row)
    refs = []
    cur = 0
    while true
      pos = self.find_from(row, "<kperf-bt", cur)
      if pos == nil
        break
      gt = self.find_from(row, ">", pos)
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

  -> .find_from(haystack, needle, start)
    haystack.index(needle, start)

  -> .dec_to_hex(dec_str)
    n = dec_str.to_i()
    if n == 0
      return "0"
    digits = "0123456789abcdef"
    out = ""
    while n > 0
      d = n % 16
      out = digits.slice(d, 1) + out
      n = n / 16
    out
