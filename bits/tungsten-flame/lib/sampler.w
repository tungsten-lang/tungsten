# sampler.w — Profile a compiled binary and return folded stacks.
#
# Linux: shells `perf record -g --call-graph fp` for `duration` seconds,
# then `perf script` text → PerfScript.collapse → folded stacks.
#
# macOS: shells `xctrace record` with the bundled counters template,
# exports the kdebug-counters-with-pmi-sample table as XML, and
# XctraceXml.collapse_counters turns it into per-metric folded stacks.
# When the counters table is missing (unsupported PMC event, Developer
# mode off), the stock Time Profiler template supplies stacks only.
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
  # names]. Slot order MUST match the event order in the template. The
  # generator (lib/xctrace/generate-templates.py) picks each slot's event
  # for the host chip and writes a `.events` manifest next to the
  # template; counter_labels reads that, so the lists here are only the
  # fallback for a template without a manifest.
  -> .counter_set_info(set_name)
    if set_name == "rates"
      return self.template_info("flame-counters-rates.tracetemplate", ["instructions", "cycles", "L1-dcache-load-misses", "L1-dcache-store-misses", "LLC-load-misses", "memsys-loads", "dTLB-misses", "L2-TLB-data-misses"])
    if set_name == "cache"
      return self.template_info("flame-counters-cache.tracetemplate", ["branches", "branch-misses", "L1-dcache-load-misses", "L1-icache-misses", "LLC-load-misses", "dTLB-misses", "iTLB-misses", "L2-TLB-data-misses"])
    if set_name == "stalls"
      return self.template_info("flame-counters-stalls.tracetemplate", ["frontend-stall-cycles", "backend-stall-cycles", "L2-TLB-instr-misses"])
    nil

  -> .template_info(template_name, fallback_labels)
    [template_name, self.counter_labels(__DIR__ + "/xctrace/" + template_name, fallback_labels)]

  # Metric labels for a template, from the `.events` manifest the
  # template generator writes next to it ("label<TAB>event" per line, in
  # slot order) — the labels always match the template's slot order that
  # way. `fallback` is used when no manifest exists.
  -> .counter_labels(template_path, fallback)
    dot = template_path.rindex(".")
    stem = dot != nil ? template_path.slice(0, dot) : template_path
    path = stem + ".events"
    if !file?(path)
      return fallback
    text = read_file(path)
    if text == nil || text.size() == 0
      return fallback
    names = []
    lines = text.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i]
      i = i + 1
      if line.size() == 0
        next
      tb = line.index("\t")
      names.push(tb != nil ? line.slice(0, tb) : line)
    names.size() > 0 ? names : fallback

  # PMI sampling every 250K instructions yields ~50-100K rows/s of
  # xctrace XML per busy core — cap the counters recording so the export
  # stays tractable; the rates converge within a couple of seconds.
  -> .counters_duration(duration)
    if duration <= 3
      return duration
    << "sampler: capping the counters recording at 3s (requested " + duration.to_s() + "s; PMI sampling exports ~50-100K rows/s per busy core)"
    3

  # PMC-counters profiling via the counters-profile table. Unlike the
  # default path's kdebug-counters-with-pmi-sample table (cumulative
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
    template = __DIR__ + "/xctrace/" + info[0]
    if !file?(template)
      << "sampler: template not found: " + template
      return {}
    trace_path = self.record_trace(tmpdir, template, argv, self.counters_duration(duration))
    if trace_path == nil
      return self.profile_macos_time_profiler(argv, duration)
    xml_text = self.export_table(trace_path, "counters-profile")
    if xml_text.size() == 0
      << "sampler: no counters-profile table in the trace (unsupported PMC event for this chip, or Developer mode off: `sudo DevToolsSecurity -enable`); falling back to Time Profiler (stacks only, no counter rates)"
      return self.profile_macos_time_profiler(argv, duration)
    # Rows for every process on the machine are in this table; filter to
    # threads whose name column carries "(<binary basename>, pid:".
    base = bin_path.split("/").last
    proc_marker = "(" + base + ", pid:"
    load_addr = self.parse_load_address(tmpdir + "/target.out", bin_path)
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
    template = __DIR__ + "/xctrace/flame-counters.tracetemplate"
    if !file?(template)
      << "sampler: template not found: " + template
      return {}
    trace_path = self.record_trace(tmpdir, template, argv, self.counters_duration(duration))
    if trace_path == nil
      return self.profile_macos_time_profiler(argv, duration)
    # kdebug-counters-with-*-sample carries stacks paired with PMC values
    # (one set of N counter readings per sample). PMI-driven sampling (the
    # template sets sampleByTime false) lands the counters in
    # …-with-pmi-sample; a time-driven template uses …-with-time-sample.
    # Try both, and judge the recording by what exports rather than by
    # xctrace's exit status.
    xml_text = self.export_table(trace_path, "kdebug-counters-with-pmi-sample")
    if xml_text.size() == 0
      xml_text = self.export_table(trace_path, "kdebug-counters-with-time-sample")
    if xml_text.size() == 0
      << "sampler: no counters table in the trace (unsupported PMC event for this chip, or Developer mode off: `sudo DevToolsSecurity -enable`); falling back to Time Profiler (stacks only)"
      return self.profile_macos_time_profiler(argv, duration)
    # Slot order follows the order events were added to the template; the
    # generator's .events manifest carries it, with the hard-coded list
    # as the fallback for a template without one.
    metric_names = self.counter_labels(template, ["branches", "branch-misses", "L1-dcache-load-misses", "LLC-load-misses", "L1d-long-latency", "dTLB-load-misses", "L1-icache-load-misses", "L2-TLB-data-misses"])
    load_addr = self.parse_load_address(tmpdir + "/target.out", bin_path)
    Tungsten:Flame:XctraceXml.collapse_counters(xml_text, bin_path, load_addr, metric_names)

  # Stacks-only fallback: the stock Time Profiler template, exported
  # through the time-sample schema that XctraceXml.collapse already
  # understands. No PMC metrics, but it works without Developer mode and
  # on any chip.
  -> .profile_macos_time_profiler(argv, duration)
    tmpdir = self.mktmpdir()
    bin_path = argv[0]
    trace_path = self.record_trace(tmpdir, "Time Profiler", argv, duration)
    if trace_path == nil
      return {}
    xml_text = self.export_table(trace_path, "time-sample")
    if xml_text.size() == 0
      << "sampler: xctrace export produced no XML (Time Profiler)"
      return {}
    load_addr = self.parse_load_address(tmpdir + "/target.out", bin_path)
    result = {}
    result["samples"] = Tungsten:Flame:XctraceXml.collapse(xml_text, bin_path, load_addr)
    result

  # Record `argv` under `template` (a bundled .tracetemplate path or a
  # stock Instruments template name) for `duration` seconds into
  # <tmpdir>/flame.trace. Returns the .trace bundle path, or nil (with
  # xctrace's log echoed) when no bundle was produced.
  #
  # xctrace's exit status is ignored on purpose: it is nonzero when the
  # target is killed at the time limit and on mere "Run issues were
  # detected" warnings, both of which leave a valid trace. Success is
  # judged by the bundle here and by what it exports in the callers.
  #
  # DYLD_PRINT_SEGMENTS makes dyld print every image's segment map to
  # the target's stderr (captured via --target-stdout into
  # <tmpdir>/target.out). That gives us the main binary's ASLR load
  # address, which atos needs (-l) to symbolicate the runtime addresses
  # in the trace — see parse_load_address.
  -> .record_trace(tmpdir, template, argv, duration)
    trace_path = tmpdir + "/flame.trace"
    bin_q = self.quote_argv(argv)
    trace_q = Tungsten:Flame:Builder.shell_quote(trace_path)
    tpl_q = Tungsten:Flame:Builder.shell_quote(template)
    log_path = tmpdir + "/xctrace.log"
    log_q = Tungsten:Flame:Builder.shell_quote(log_path)
    tgt_q = Tungsten:Flame:Builder.shell_quote(tmpdir + "/target.out")
    rec_cmd = "xctrace record --template " + tpl_q + " --time-limit " + duration.to_s() + "s --output " + trace_q + " --env DYLD_PRINT_SEGMENTS=1 --target-stdout " + tgt_q + " --launch -- " + bin_q + " > " + log_q + " 2>&1"
    system(rec_cmd)
    if !file?(trace_path + "/form.template")
      << "sampler: xctrace record failed (" + template.split("/").last + ")"
      log_text = read_file(log_path)
      if log_text != nil && log_text.strip().size() > 0
        << log_text.strip()
      return nil
    trace_path

  # Export one table of run 1 as XML; "" when the table is absent or has
  # no rows. (A template naming a PMC event the chip lacks still records
  # a trace whose counters tables export as a bare schema header — the
  # row check is what tells "recorded nothing" from "recorded".)
  -> .export_table(trace_path, schema)
    trace_q = Tungsten:Flame:Builder.shell_quote(trace_path)
    xpath = "/trace-toc/run\[@number=\"1\"\]/data/table\[@schema=\"" + schema + "\"\]"
    xpath_q = Tungsten:Flame:Builder.shell_quote(xpath)
    xml_text = capture("xctrace export --input " + trace_q + " --xpath " + xpath_q + " 2>/dev/null")
    if xml_text == nil || !xml_text.include?("<row>")
      return ""
    xml_text

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
