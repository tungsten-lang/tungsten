# sampler.w — Profile a compiled binary and return folded stacks.
#
# Linux: shells `perf record -g --call-graph fp` for `duration` seconds,
# then `perf script` text → PerfScript.collapse → folded stacks.
#
# macOS: shells `xctrace record` with the bundled counters template,
# exports the kdebug-counters-with-time-sample table as XML, and
# XctraceXml.collapse_counters turns it into per-metric folded stacks.
#
# Returns the folded-stack text as a string, or nil on failure.

in Tungsten:Flame

+ Sampler

  # Returns a dict { metric_name => folded_text } so flame.w can render
  # per-metric sections. Single-metric flows return one key ("cycles"
  # on Linux, "samples" on macOS). Multi-event extension fills more.
  # `counter_set` selects the PMC event set: "" is the default sampling
  # path; "rates" / "cache" / "stalls" pick a bundled tracetemplate and
  # collapse the per-thread counters-profile deltas instead (macOS only).
  -> .profile(bin_path, duration, rate, counter_set)
    self.profile_cmd([bin_path], duration, rate, counter_set)

  # Same contract, but the target is a full command line (binary + args):
  # the launched process is whatever argv describes, and symbolication
  # keys off argv[0].
  -> .profile_cmd(argv, duration, rate, counter_set)
    os = self.os_name()
    if os == "Linux"
      if counter_set != ""
        << "sampler: --counters is macOS-only (Instruments PMC templates); using perf cycles"
      self.profile_linux(argv, duration, rate)
    elsif os == "Darwin"
      if counter_set != ""
        self.profile_macos_counters(argv, duration, rate, counter_set)
      else
        self.profile_macos(argv, duration, rate)
    else
      << "sampler: unsupported OS: " + os
      {}

  # Counter-set table: name -> [template filename, slot-ordered metric
  # names]. Slot order MUST match the event order in the template (see
  # lib/xctrace/generate-templates.py, which builds the .tracetemplate
  # files from these same event lists).
  -> .counter_set_info(set_name)
    if set_name == "rates"
      return ["flame-counters-rates.tracetemplate", ["instructions", "cycles", "L1-dcache-load-misses", "L1-dcache-store-misses", "LLC-load-misses", "memsys-loads", "dTLB-misses", "L2-TLB-data-misses"]]
    if set_name == "cache"
      return ["flame-counters-cache.tracetemplate", ["branches", "branch-misses", "L1-dcache-load-misses", "L1-icache-misses", "LLC-load-misses", "dTLB-misses", "iTLB-misses", "L2-TLB-data-misses"]]
    if set_name == "stalls"
      return ["flame-counters-stalls.tracetemplate", ["frontend-stall-cycles", "backend-stall-cycles", "L2-TLB-instr-misses"]]
    nil

  # PMC-counters profiling via the counters-profile table. Unlike the
  # default path's kdebug-counters-with-time-sample table (cumulative
  # per-core readings), counters-profile rows are per-thread interval
  # DELTAS that Instruments already differenced at context-switch
  # boundaries — so a row's counts belong to that row's thread and
  # stack, with no cross-thread double counting and no bleed-in from
  # other processes sharing the core. The table carries every process
  # on the system, so the collapse filters rows to the target process
  # by name.
  -> .profile_macos_counters(argv, duration, rate, counter_set)
    info = self.counter_set_info(counter_set)
    if info == nil
      << "sampler: unknown counter set: " + counter_set + " (expected rates, cache, or stalls)"
      return {}
    tmpdir = self.mktmpdir()
    bin_path = argv[0]
    trace_path = tmpdir + "/flame.trace"
    template = __DIR__ + "/xctrace/" + info[0]
    if !file?(template)
      << "sampler: template not found: " + template
      return {}
    bin_q = self.quote_argv(argv)
    trace_q = Tungsten:Flame:Builder.shell_quote(trace_path)
    tpl_q = Tungsten:Flame:Builder.shell_quote(template)
    log_path = tmpdir + "/xctrace.log"
    log_q = Tungsten:Flame:Builder.shell_quote(log_path)
    target_out = tmpdir + "/target.out"
    tgt_q = Tungsten:Flame:Builder.shell_quote(target_out)
    rec_cmd = "xctrace record --template " + tpl_q + " --time-limit " + duration.to_s() + "s --output " + trace_q + " --env DYLD_PRINT_SEGMENTS=1 --target-stdout " + tgt_q + " --launch -- " + bin_q + " > " + log_q + " 2>&1"
    system(rec_cmd)
    if !file?(trace_path + "/form.template")
      << "sampler: xctrace record failed"
      log_text = read_file(log_path)
      if log_text != nil && log_text.strip().size() > 0
        << log_text.strip()
      return {}
    xpath = "/trace-toc/run\[@number=\"1\"\]/data/table\[@schema=\"counters-profile\"\]"
    xpath_q = Tungsten:Flame:Builder.shell_quote(xpath)
    xml_text = capture("xctrace export --input " + trace_q + " --xpath " + xpath_q + " 2>/dev/null")
    if xml_text == nil || xml_text.size() == 0
      << "sampler: xctrace export produced no XML"
      return {}
    # Rows for every process on the machine are in this table; filter to
    # threads whose name column carries "(<binary basename>, pid:".
    base = bin_path.split("/").last
    proc_marker = "(" + base + ", pid:"
    load_addr = self.parse_load_address(target_out, bin_path)
    Tungsten:Flame:XctraceXml.collapse_counter_profile(xml_text, bin_path, load_addr, info[1], proc_marker)

  -> .quote_argv(argv)
    out = ""
    i = 0
    while i < argv.size()
      out = out + " " if i > 0
      out = out + Tungsten:Flame:Builder.shell_quote(argv[i])
      i = i + 1
    out

  -> .profile_linux(argv, duration, rate)
    tmpdir = self.mktmpdir()
    perf_data = tmpdir + "/perf.data"
    cmd_q = self.quote_argv(argv)
    pd_q = Tungsten:Flame:Builder.shell_quote(perf_data)
    rate_s = (rate == nil ? "99" : rate.to_s())
    duration_s = duration.to_s()
    rec_cmd = "perf record -F " + rate_s + " -g --call-graph fp -o " + pd_q + " -- timeout " + duration_s + "s " + cmd_q + " 2>/dev/null"
    if !system(rec_cmd)
      << "sampler: perf record failed"
      return {}
    script_text = capture("perf script -i " + pd_q + " 2>/dev/null")
    if script_text == nil || script_text.size() == 0
      << "sampler: perf script returned no output"
      return {}
    result = {}
    result["cycles"] = Tungsten:Flame:PerfScript.collapse(script_text)
    result

  -> .profile_macos(argv, duration, rate)
    tmpdir = self.mktmpdir()
    bin_path = argv[0]
    trace_path = tmpdir + "/flame.trace"
    template = __DIR__ + "/xctrace/flame-counters.tracetemplate"
    if !file?(template)
      << "sampler: template not found: " + template
      return {}
    bin_q = self.quote_argv(argv)
    trace_q = Tungsten:Flame:Builder.shell_quote(trace_path)
    tpl_q = Tungsten:Flame:Builder.shell_quote(template)
    log_path = tmpdir + "/xctrace.log"
    log_q = Tungsten:Flame:Builder.shell_quote(log_path)
    # DYLD_PRINT_SEGMENTS makes dyld print every image's segment map to
    # the target's stderr (captured via --target-stdout). That gives us
    # the main binary's ASLR load address, which atos needs (-l) to
    # symbolicate the runtime addresses in the trace.
    target_out = tmpdir + "/target.out"
    tgt_q = Tungsten:Flame:Builder.shell_quote(target_out)
    rec_cmd = "xctrace record --template " + tpl_q + " --time-limit " + duration.to_s() + "s --output " + trace_q + " --env DYLD_PRINT_SEGMENTS=1 --target-stdout " + tgt_q + " --launch -- " + bin_q + " > " + log_q + " 2>&1"
    system(rec_cmd)
    # xctrace exits nonzero when it kills a still-running target at the
    # time limit, even though the recording is valid — so ignore the exit
    # status and judge success by the presence of the .trace bundle.
    if !file?(trace_path + "/form.template")
      << "sampler: xctrace record failed"
      log_text = read_file(log_path)
      if log_text != nil && log_text.strip().size() > 0
        << log_text.strip()
      return {}
    # kdebug-counters-with-time-sample carries stacks paired with PMC
    # values (one set of N counter readings per sample). The slot order
    # follows the order events were added to the tracetemplate.
    xpath = "/trace-toc/run\[@number=\"1\"\]/data/table\[@schema=\"kdebug-counters-with-time-sample\"\]"
    xpath_q = Tungsten:Flame:Builder.shell_quote(xpath)
    xml_text = capture("xctrace export --input " + trace_q + " --xpath " + xpath_q + " 2>/dev/null")
    if xml_text == nil || xml_text.size() == 0
      << "sampler: xctrace export produced no XML"
      return {}

    # Slot mapping for the user's flame-counters.tracetemplate. Indexes
    # match the order events were added to the template:
    #   0 INST_BRANCH, 1 BRANCH_MISPRED_NONSPEC, 2 L1D_CACHE_MISS_LD,
    #   3 PL2_CACHE_MISS_LD, 4 ARM_L1D_CACHE_LMISS_RD,
    #   5 L1D_TLB_MISS, 6 L1I_CACHE_MISS_DEMAND, 7 L2_TLB_MISS_DATA.
    metric_names = ["branches", "branch-misses", "L1-dcache-load-misses", "LLC-load-misses", "L1d-long-latency", "dTLB-load-misses", "L1-icache-load-misses", "L2-TLB-data-misses"]
    load_addr = self.parse_load_address(target_out, bin_path)
    Tungsten:Flame:XctraceXml.collapse_counters(xml_text, bin_path, load_addr, metric_names)

  # Parse the main binary's __TEXT load address out of a
  # DYLD_PRINT_SEGMENTS log. dyld prints "Kernel mapped <path>" followed
  # by the segment map; the first "__TEXT (r.x) 0xSTART->0xEND" line
  # after that is the load address atos wants. Returns "" if absent.
  -> .parse_load_address(log_path, bin_path)
    text = read_file(log_path)
    if text == nil
      return ""
    lines = text.split("\n")
    seen_map = false
    i = 0
    while i < lines.size()
      line = lines[i]
      if seen_map && line.include?("__TEXT")
        h = line.index("0x")
        if h != nil
          rest = line.slice(h, line.size() - h)
          arrow = rest.index("->")
          if arrow != nil
            return rest.slice(0, arrow)
        return ""
      # dyld prints the ABSOLUTE target path; bin_path may be relative
      # (external-command mode launches `./bin/foo`), so match on the
      # trailing path component.
      if line.include?("Kernel mapped ") && line.ends_with?("/" + bin_path.split("/").last)
        seen_map = true
      i = i + 1
    ""

  -> .os_name()
    capture("uname -s").strip()

  -> .mktmpdir()
    capture("mktemp -d -t tungsten-flame").strip()

  -> .basename_noext(path)
    slash = path.rindex("/")
    base = slash != nil ? path.slice(slash + 1, path.size() - slash - 1) : path
    dot = base.rindex(".")
    dot != nil ? base.slice(0, dot) : base
