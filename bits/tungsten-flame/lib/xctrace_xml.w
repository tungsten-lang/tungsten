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

  -> .collapse(xml_text, binary_path, load_addr)
    # 1. Build id → addresses dict from inline kperf-bt blocks.
    addrs_by_id = self.parse_kperf_bts(xml_text)

    # 2. Walk rows, accumulate folded stacks (still as hex addresses).
    # Split once (see parse_kperf_bts for why find_from scans are out).
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
        folded_stack = self.reverse(addrs).join(";")
        if folded.has_key?(folded_stack)
          folded[folded_stack] = folded[folded_stack] + 1
        else
          folded[folded_stack] = 1

    # 3. Symbolicate via atos. Collect every unique address that appears
    #    in any folded stack, run `atos -o BIN` in one batch, build a
    #    dict, then rewrite each folded stack with symbol names.
    sym = self.symbolicate(folded.keys(), binary_path, load_addr)

    out = []
    keys = self.sort_strings(folded.keys())
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
  # `load_addr` is the binary's runtime __TEXT load address ("0x...", or
  # "" when unknown) — trace addresses are ASLR-slid, so atos needs -l
  # to map them back into the binary.
  -> .symbolicate(stack_keys, binary_path, load_addr)
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

    # Second pass: addresses the main-binary atos couldn't name are
    # almost always dyld-shared-cache addresses (system libraries).
    # The shared cache is mapped at one per-boot-constant slide in
    # EVERY process, so symbolicating those addresses against our own
    # live process resolves them correctly — one batched
    # `atos -p <own pid>` call, no dSYMs or runtime helpers needed.
    # Addresses outside the cache (the profiled binary's private ASLR
    # range) echo back as bare hex and simply stay unresolved.
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

  # Our own PID. capture() runs its command via `sh -c`, so $PPID
  # inside that shell is this process.
  -> .own_pid()
    capture("echo $PPID").strip()

  # Hex "0x..." string → integer value. Returns 0 when malformed or
  # longer than 12 hex digits (2^48) — kernel pointers ("0xfffffe...")
  # would overflow boxed-Int accumulation, and no user-space address
  # we care about is that high.
  -> .hex_to_int(s)
    if !s.starts_with?("0x") || s.size() > 14
      return 0
    n = 0
    i = 2
    while i < s.size()
      c = s.slice(i, 1)
      d = nil
      if c >= "0" && c <= "9"
        d = c.to_i()
      elsif c == "a" || c == "A"
        d = 10
      elsif c == "b" || c == "B"
        d = 11
      elsif c == "c" || c == "C"
        d = 12
      elsif c == "d" || c == "D"
        d = 13
      elsif c == "e" || c == "E"
        d = 14
      elsif c == "f" || c == "F"
        d = 15
      if d == nil
        return 0
      n = n * 16 + d
      i = i + 1
    n

  # True when `addr_str` lies inside the arm64 dyld shared region
  # (base 0x180000000, well under 0x1000000000). Only these addresses
  # are safe to hand to `atos -p <own pid>`: the shared region sits at
  # one per-boot-constant slide in every process, while anything else
  # (the profiled binary, its on-disk dyld) lives at that process's
  # private ASLR slide — resolving those against our own mappings
  # could produce confidently wrong names. On non-arm64 hosts nothing
  # matches and the second pass simply never runs.
  -> .shared_cache_addr?(addr_str)
    n = self.hex_to_int(addr_str)
    n >= 6442450944 && n < 68719476736

  # One `atos -p` output line → frame name, or nil when unresolved
  # (atos echoes unresolvable addresses back as bare hex).
  #   "kevent (in libsystem_kernel.dylib) + 8"
  #     → "libsystem_kernel.dylib`kevent"
  # The lib`symbol form is the Instruments convention the analyzer
  # already strips for display (rindex("`")) while categorizers still
  # see the library name in the raw frame (e.g. libsystem_kernel →
  # the syscall category).
  -> .parse_atos_system_line(line)
    s = line.strip()
    if s.size() == 0 || s.starts_with?("0x")
      return nil
    paren = s.index(" (in ")
    if paren == nil
      # Named but no library info — keep the symbol up to any " (".
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

  # Multi-metric collapse over the kdebug-counters-with-time-sample schema.
  # `metric_names` maps slot index N to a user-facing metric label.
  # Apple's PMC export duplicates the values (8 events → 16 columns), so
  # we only read the first n_metrics slots.
  #
  # Counter values are cumulative per-(thread, core). When a thread moves
  # cores, the new core's counter reading isn't comparable to the prior
  # one — we treat that as "no baseline yet" and start fresh for that key.
  -> .collapse_counters(xml_text, binary_path, load_addr, metric_names)
    addrs_by_id = self.parse_kperf_bts(xml_text)
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
        thread_key = self.extract_tag_key(row, "<thread")
        core_key   = self.extract_tag_key(row, "<core")
        pmc_vals   = self.extract_pmc_values(row)
        if pmc_vals.size() >= n_metrics
          addrs = self.row_user_stack(row, addrs_by_id)
          key = thread_key + ":" + core_key
          if addrs != nil && addrs.size() > 0 && prev_vals.has_key?(key)
            prev = prev_vals[key]
            folded_stack = self.reverse(addrs).join(";")
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
    sym = self.symbolicate(all_keys, binary_path, load_addr)

    result = {}
    mi = 0
    while mi < n_metrics
      name = metric_names[mi]
      fd = folded_by_metric[name]
      keys = self.sort_strings(fd.keys())
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

  # Parse the text content of a `<pmc-events>VALUES</pmc-events>` element
  # into a list of integers. Returns empty list if not present.
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

  # Walk all inline `<kperf-bt id="N" ...>...</kperf-bt>` blocks and
  # return { N => [frames, leaf first] }.
  #
  # Inside a kperf-bt:
  #   - `<text-address ...>` (singular) is the sample PC — the leaf frame.
  #     Its fmt attribute already carries the hex form ("0x...").
  #   - `<text-addresses ...>` (plural) holds the caller frames as
  #     space-separated decimal values, zero-terminated. Repeated stacks
  #     share it via `<text-addresses ref="N"/>`, so inline definitions
  #     are memoized in ta_by_id / pc_by_id and refs resolved from there.
  #   - Single-frame stacks duplicate the PC in the plural list, so a
  #     leading caller equal to the PC is dropped.
  -> .parse_kperf_bts(xml)
    # Split once instead of scanning with find_from — find_from copies
    # the remaining string per call, which is O(n^2) over a multi-MB
    # export. kperf-bt blocks never nest, so each piece holds one block.
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

  # Resolve one kperf-bt block's frame list (leaf first). Memoizes any
  # inline text-address(es) definitions into pc_by_id / ta_by_id.
  -> .block_stack(block, ta_by_id, pc_by_id)
    # Leaf PC: inline `<text-address id="N" fmt="0x...">` or `<text-address ref="N"/>`.
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

    # Caller frames: inline `<text-addresses id="N" ...>VALS</...>` or ref.
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

  # For a <row>...</row> chunk, return the user-stack as a list of
  # address strings, or nil if unresolvable.
  -> .row_user_stack(row, addrs_by_id)
    # First check for an inline kperf-bt with text-addresses — these
    # ARE the user-stack (the inline form). Take the LAST one in the
    # row (kernel comes first, user second).
    bts = self.all_kperf_refs(row)
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
      pos = self.find_from(row, "<kperf-bt", cur)
      if pos == nil
        break
      # Look for id="N" or ref="N"
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
