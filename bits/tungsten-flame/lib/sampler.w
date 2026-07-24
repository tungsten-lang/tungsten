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
  -> .profile(bin_path, duration, rate)
    self.profile_cmd([bin_path], duration, rate)

  # Same contract, but the target is a full command line (binary + args):
  # the launched process is whatever argv describes, and symbolication
  # keys off argv[0].
  -> .profile_cmd(argv, duration, rate)
    os = self.os_name()
    if os == "Linux"
      self.profile_linux(argv, duration, rate)
    elsif os == "Darwin"
      self.profile_macos(argv, duration, rate)
    else
      << "sampler: unsupported OS: " + os
      {}

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
