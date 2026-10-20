# sampler.w — Profile a compiled binary, command, PID, or Ruby run and return
# folded stacks.
#
# Linux: shells `perf record -g --call-graph fp` for `duration` seconds,
# then `perf script` text → PerfScript.collapse → folded stacks.
#
# macOS: shells `xctrace record` with the bundled counters template,
# exports the kdebug-counters-with-pmi-sample table as XML, and
# XctraceXml.collapse_counters turns it into per-metric folded stacks.
# When the counters table is missing (unsupported PMC event, Developer
# mode off), the stock Time Profiler template supplies stacks only.
# When Xcode/Instruments (`xctrace`) is not installed at all, falls back
# to macOS's built-in `/usr/bin/sample` + SampleCollapse.

use folded
use sample_collapse

in Tungsten:Flame

+ Sampler

  # Returns a dict { metric_name => folded_text } so flame.w can render
  # per-metric sections. Single-metric flows return one key ("cycles"
  # on Linux, "samples" on macOS). Multi-event extension fills more.
  -> .profile(bin_path, duration, rate, counter_set)
    self.profile_cmd([bin_path], duration, rate, counter_set, false)

  -> .profile(bin_path, duration, rate, counter_set, alloc)
    self.profile_cmd([bin_path], duration, rate, counter_set, alloc)

  # Same contract, but the target is a full command line (binary + args):
  # the launched process is whatever argv describes, and symbolication
  # keys off argv[0].
  -> .profile_cmd(argv, duration, rate, counter_set)
    self.profile_cmd(argv, duration, rate, counter_set, false)

  -> .profile_cmd(argv, duration, rate, counter_set, alloc)
    alloc_on = alloc || (env("TUNGSTEN_FLAME_ALLOC") != nil && env("TUNGSTEN_FLAME_ALLOC") != "")
    os = self.os_name()
    if os == "Linux"
      if counter_set != ""
        << "sampler: --counters is macOS-only (Instruments PMC templates); using perf cycles"
      self.profile_linux(argv, duration, rate, alloc_on)
    elsif os == "Darwin"
      if counter_set != ""
        self.profile_macos_counters(argv, duration, rate, counter_set, alloc_on)
      else
        self.profile_macos(argv, duration, rate, alloc_on)
    else
      << "sampler: unsupported OS: " + os
      {}

  # Attach to an existing process `pid` for `duration` seconds.
  -> .profile_pid(pid, duration, rate, counter_set)
    os = self.os_name()
    if os == "Linux"
      if counter_set != ""
        << "sampler: --counters is macOS-only (Instruments PMC templates); using perf cycles"
      self.profile_linux_pid(pid, duration, rate)
    elsif os == "Darwin"
      self.profile_macos_pid(pid, duration, rate, counter_set)
    else
      << "sampler: unsupported OS: " + os
      {}

  # Profile the Ruby implementation (`implementations/ruby`) running
  # `source_path` via StackProf (or a stdlib `backtrace_locations` sampler
  # fallback when the `stackprof` gem is unavailable).
  # `phase_mode` is "general", "lex", "parse", or "execution".
  -> .profile_ruby(source_path, passthrough, duration, rate, phase_mode)
    tmpdir = self.mktmpdir()
    script_path = tmpdir + "/ruby_prof.rb"
    folded_path = tmpdir + "/ruby.folded"
    root = Tungsten:Flame:Builder.project_root()
    hz = (rate != nil && rate > 0) ? rate : 1000
    interval_us = 1000000 / hz
    if interval_us < 100
      interval_us = 100

    rb = []
    rb.push("$LOAD_PATH.unshift(\"" + Tungsten:Flame:Folded.json_escape(root) + "/implementations/ruby/lib\")")
    rb.push("require 'tungsten'")
    rb.push("src_path = ARGV.shift")
    rb.push("folded_out = ARGV.shift")
    rb.push("dur = ARGV.shift.to_f")
    rb.push("mode = ARGV.shift")
    rb.push("code = File.read(src_path)")
    rb.push("ast = (mode == 'execution') ? Tungsten.parse_with_file(code, src_path) : nil")
    rb.push("run_once = proc do")
    rb.push("  case mode")
    rb.push("  when 'lex'")
    rb.push("    Tungsten::Lexer.new(code, file: src_path).tokenize")
    rb.push("  when 'parse'")
    rb.push("    Tungsten.parse_with_file(code, src_path)")
    rb.push("  when 'execution'")
    rb.push("    Tungsten::Interpreter.new.evaluate(ast)")
    rb.push("  else")
    rb.push("    Tungsten::Interpreter.new.run(code, file_path: src_path)")
    rb.push("  end")
    rb.push("end")
    rb.push("require 'timeout'")
    rb.push("has_stackprof = begin; require 'stackprof'; true; rescue LoadError; false; end")
    rb.push("saved_out = $stdout.dup")
    rb.push("null_out = File.open(File::NULL, 'w')")
    rb.push("if has_stackprof")
    rb.push("  data = StackProf.run(mode: :wall, interval: " + interval_us.to_s() + ", raw: true) do")
    rb.push("    $stdout.reopen(null_out)")
    rb.push("    begin")
    rb.push("      Timeout.timeout(dur) do")
    rb.push("        loop { run_once.call }")
    rb.push("      end")
    rb.push("    rescue Timeout::Error, SystemExit")
    rb.push("    ensure")
    rb.push("      $stdout.reopen(saved_out)")
    rb.push("    end")
    rb.push("  end")
    rb.push("  File.open(folded_out, 'w') do |f|")
    rb.push("    $stdout.reopen(f)")
    rb.push("    begin")
    rb.push("      StackProf::Report.new(data).print_stackcollapse")
    rb.push("    ensure")
    rb.push("      $stdout.reopen(saved_out)")
    rb.push("    end")
    rb.push("  end")
    rb.push("else")
    rb.push("  stacks = Hash.new(0)")
    rb.push("  stop = false")
    rb.push("  main_th = Thread.current")
    rb.push("  sampler = Thread.new do")
    rb.push("    until stop")
    rb.push("      locs = main_th.backtrace_locations")
    rb.push("      if locs && !locs.empty?")
    rb.push("        frames = locs.reverse.map { |l| l.label || l.base_label || 'unknown' }")
    rb.push("        stacks[frames.join(';')] += 1")
    rb.push("      end")
    rb.push("      sleep(" + interval_us.to_s() + ".0 / 1_000_000.0)")
    rb.push("    end")
    rb.push("  end")
    rb.push("  $stdout.reopen(null_out)")
    rb.push("  begin")
    rb.push("    Timeout.timeout(dur) do")
    rb.push("      loop { run_once.call }")
    rb.push("    end")
    rb.push("  rescue Timeout::Error, SystemExit")
    rb.push("  ensure")
    rb.push("    stop = true")
    rb.push("    sampler.join")
    rb.push("    $stdout.reopen(saved_out)")
    rb.push("  end")
    rb.push("  File.write(folded_out, stacks.keys.sort.map { |k| k.to_s + ' ' + stacks[k].to_s }.join(\"\\n\"))")
    rb.push("end")
    write_file(script_path, rb.join("\n") + "\n")

    cmd_argv = ["ruby", script_path, source_path, folded_path, duration.to_s(), phase_mode]
    pi = 0
    while pi < passthrough.size()
      cmd_argv.push(passthrough[pi])
      pi = pi + 1
    cmd = self.quote_argv(cmd_argv)
    system(cmd + " 2>/dev/null")
    folded_text = read_file(folded_path)
    self.rmtree(tmpdir)
    result = {}
    if folded_text != nil && folded_text.strip().size() > 0
      result["samples"] = folded_text
    result

  # Counter-set table: name -> [template filename, slot-ordered metric names].
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

  -> .counters_duration(duration)
    if duration <= 3
      return duration
    << "sampler: capping the counters recording at 3s (requested " + duration.to_s() + "s; PMI sampling exports ~50-100K rows/s per busy core)"
    3

  -> .has_xctrace?()
    system("xcrun --find xctrace >/dev/null 2>&1")

  # PMC-counters profiling via the counters-profile table.
  -> .profile_macos_counters(argv, duration, rate, counter_set, alloc_on)
    info = self.counter_set_info(counter_set)
    if info == nil
      << "sampler: unknown counter set: " + counter_set + " (expected rates, cache, or stalls)"
      return {}
    if !self.has_xctrace?()
      << "sampler: xctrace not found (Xcode/Instruments not installed); falling back to /usr/bin/sample (stacks only)"
      return self.profile_macos_sample(argv, duration, alloc_on)
    tmpdir = self.mktmpdir()
    bin_path = argv[0]
    template = __DIR__ + "/xctrace/" + info[0]
    if !file?(template)
      << "sampler: template not found: " + template
      self.rmtree(tmpdir)
      return {}
    trace_path = self.record_trace(tmpdir, template, argv, self.counters_duration(duration), alloc_on)
    if trace_path == nil
      self.rmtree(tmpdir)
      return self.profile_macos_time_profiler(argv, duration, false)
    xml_text = self.export_table(trace_path, "counters-profile")
    if xml_text.size() == 0
      << "sampler: no counters-profile table in the trace (unsupported PMC event for this chip, or Developer mode off: `sudo DevToolsSecurity -enable`); falling back to Time Profiler (stacks only, no counter rates)"
      self.rmtree(tmpdir)
      return self.profile_macos_time_profiler(argv, duration, false)
    base = bin_path.split("/").last
    proc_marker = "(" + base + ", pid:"
    load_addr = self.parse_load_address(tmpdir + "/target.out", bin_path)
    self.rmtree(tmpdir)
    Tungsten:Flame:XctraceXml.collapse_counter_profile(xml_text, bin_path, load_addr, info[1], proc_marker)

  -> .quote_argv(argv)
    out = ""
    i = 0
    while i < argv.size()
      out = out + " " if i > 0
      out = out + Tungsten:Flame:Builder.shell_quote(argv[i])
      i = i + 1
    out

  -> .profile_linux(argv, duration, rate, alloc_on)
    tmpdir = self.mktmpdir()
    perf_data = tmpdir + "/perf.data"
    tgt_out = tmpdir + "/target.out"
    cmd_q = self.quote_argv(argv)
    pd_q = Tungsten:Flame:Builder.shell_quote(perf_data)
    tgt_q = Tungsten:Flame:Builder.shell_quote(tgt_out)
    rate_s = (rate == nil ? "99" : rate.to_s())
    duration_s = duration.to_s()
    env_prefix = alloc_on ? "TUNGSTEN_ALLOC_PROFILE=1 " : ""
    rec_cmd = env_prefix + "perf record -F " + rate_s + " -g --call-graph fp -o " + pd_q + " -- timeout " + duration_s + "s " + cmd_q + " >" + tgt_q + " 2>&1"
    if !system(rec_cmd)
      << "sampler: perf record failed"
      self.rmtree(tmpdir)
      return {}
    if alloc_on
      self.print_alloc_report(read_file(tgt_out))
    script_text = capture("perf script -i " + pd_q + " 2>/dev/null")
    self.rmtree(tmpdir)
    if script_text == nil || script_text.size() == 0
      << "sampler: perf script returned no output"
      return {}
    result = {}
    result["cycles"] = Tungsten:Flame:PerfScript.collapse(script_text)
    result

  -> .profile_linux_pid(pid, duration, rate)
    tmpdir = self.mktmpdir()
    perf_data = tmpdir + "/perf.data"
    pd_q = Tungsten:Flame:Builder.shell_quote(perf_data)
    rate_s = (rate == nil ? "99" : rate.to_s())
    duration_s = duration.to_s()
    rec_cmd = "perf record -F " + rate_s + " -g --call-graph fp -p " + pid.to_s() + " -o " + pd_q + " -- sleep " + duration_s + " 2>/dev/null"
    if !system(rec_cmd)
      << "sampler: perf record -p " + pid.to_s() + " failed"
      self.rmtree(tmpdir)
      return {}
    script_text = capture("perf script -i " + pd_q + " 2>/dev/null")
    self.rmtree(tmpdir)
    if script_text == nil || script_text.size() == 0
      << "sampler: perf script returned no output"
      return {}
    result = {}
    result["cycles"] = Tungsten:Flame:PerfScript.collapse(script_text)
    result

  -> .profile_macos(argv, duration, rate, alloc_on)
    if !self.has_xctrace?()
      return self.profile_macos_sample(argv, duration, alloc_on)
    tmpdir = self.mktmpdir()
    bin_path = argv[0]
    template = __DIR__ + "/xctrace/flame-counters.tracetemplate"
    if !file?(template)
      << "sampler: template not found: " + template
      self.rmtree(tmpdir)
      return self.profile_macos_sample(argv, duration, alloc_on)
    trace_path = self.record_trace(tmpdir, template, argv, self.counters_duration(duration), alloc_on)
    if trace_path == nil
      self.rmtree(tmpdir)
      return self.profile_macos_time_profiler(argv, duration, false)
    xml_text = self.export_table(trace_path, "kdebug-counters-with-pmi-sample")
    if xml_text.size() == 0
      xml_text = self.export_table(trace_path, "kdebug-counters-with-time-sample")
    if xml_text.size() == 0
      << "sampler: no counters table in the trace (unsupported PMC event for this chip, or Developer mode off: `sudo DevToolsSecurity -enable`); falling back to Time Profiler (stacks only)"
      self.rmtree(tmpdir)
      return self.profile_macos_time_profiler(argv, duration, false)
    metric_names = self.counter_labels(template, ["branches", "branch-misses", "L1-dcache-load-misses", "LLC-load-misses", "L1d-long-latency", "dTLB-load-misses", "L1-icache-load-misses", "L2-TLB-data-misses"])
    load_addr = self.parse_load_address(tmpdir + "/target.out", bin_path)
    self.rmtree(tmpdir)
    Tungsten:Flame:XctraceXml.collapse_counters(xml_text, bin_path, load_addr, metric_names)

  # Stacks-only fallback: the stock Time Profiler template, or `/usr/bin/sample`
  # when xctrace / Instruments is unavailable.
  -> .profile_macos_time_profiler(argv, duration, alloc_on)
    if !self.has_xctrace?()
      return self.profile_macos_sample(argv, duration, alloc_on)
    tmpdir = self.mktmpdir()
    bin_path = argv[0]
    trace_path = self.record_trace(tmpdir, "Time Profiler", argv, duration, alloc_on)
    if trace_path == nil
      self.rmtree(tmpdir)
      return self.profile_macos_sample(argv, duration, false)
    xml_text = self.export_table(trace_path, "time-sample")
    if xml_text.size() == 0
      self.rmtree(tmpdir)
      return self.profile_macos_sample(argv, duration, false)
    load_addr = self.parse_load_address(tmpdir + "/target.out", bin_path)
    self.rmtree(tmpdir)
    result = {}
    result["samples"] = Tungsten:Flame:XctraceXml.collapse(xml_text, bin_path, load_addr)
    result

  # Zero-Xcode macOS fallback: launch `argv` in the background and sample it
  # with `/usr/bin/sample`, which ships in base macOS without Xcode/Instruments.
  -> .profile_macos_sample(argv, duration, alloc_on)
    tmpdir = self.mktmpdir()
    sample_file = tmpdir + "/sample.txt"
    tgt_out = tmpdir + "/target.out"
    cmd_q = self.quote_argv(argv)
    sf_q = Tungsten:Flame:Builder.shell_quote(sample_file)
    tgt_q = Tungsten:Flame:Builder.shell_quote(tgt_out)
    env_prefix = alloc_on ? "TUNGSTEN_ALLOC_PROFILE=1 " : ""
    sh_cmd = "(" + env_prefix + "exec " + cmd_q + " >" + tgt_q + " 2>&1) & pid=$!; /usr/bin/sample $pid " + duration.to_s() + " 1 -mayDie -file " + sf_q + " >/dev/null 2>&1; kill $pid 2>/dev/null; wait $pid 2>/dev/null"
    system(sh_cmd)
    if alloc_on
      self.print_alloc_report(read_file(tgt_out))
    sample_text = read_file(sample_file)
    self.rmtree(tmpdir)
    if sample_text == nil || sample_text.size() == 0
      << "sampler: /usr/bin/sample produced no output"
      return {}
    folded = Tungsten:Flame:SampleCollapse.collapse(sample_text)
    if folded == ""
      return {}
    result = {}
    result["samples"] = folded
    result

  # Attach to a live PID on macOS: use xctrace when `--counters` is requested
  # and xctrace is available; otherwise use `/usr/bin/sample`, which resolves
  # symbols directly from the live process without needing DYLD_PRINT_SEGMENTS.
  -> .profile_macos_pid(pid, duration, rate, counter_set)
    if counter_set != "" && self.has_xctrace?()
      info = self.counter_set_info(counter_set)
      if info != nil
        template = __DIR__ + "/xctrace/" + info[0]
        if file?(template)
          tmpdir = self.mktmpdir()
          trace_path = tmpdir + "/flame.trace"
          trace_q = Tungsten:Flame:Builder.shell_quote(trace_path)
          tpl_q = Tungsten:Flame:Builder.shell_quote(template)
          log_q = Tungsten:Flame:Builder.shell_quote(tmpdir + "/xctrace.log")
          dur = self.counters_duration(duration)
          system("xctrace record --template " + tpl_q + " --time-limit " + dur.to_s() + "s --output " + trace_q + " --attach " + pid.to_s() + " > " + log_q + " 2>&1")
          if file?(trace_path + "/form.template")
            xml_text = self.export_table(trace_path, "counters-profile")
            self.rmtree(tmpdir)
            if xml_text.size() > 0
              proc_marker = "pid: " + pid.to_s() + ")"
              return Tungsten:Flame:XctraceXml.collapse_counter_profile(xml_text, "", "", info[1], proc_marker)
          else
            self.rmtree(tmpdir)
    tmpdir = self.mktmpdir()
    sample_file = tmpdir + "/sample.txt"
    sf_q = Tungsten:Flame:Builder.shell_quote(sample_file)
    system("/usr/bin/sample " + pid.to_s() + " " + duration.to_s() + " 1 -mayDie -file " + sf_q + " >/dev/null 2>&1")
    sample_text = read_file(sample_file)
    self.rmtree(tmpdir)
    if sample_text == nil || sample_text.size() == 0
      << "sampler: could not sample pid " + pid.to_s()
      return {}
    folded = Tungsten:Flame:SampleCollapse.collapse(sample_text)
    if folded == ""
      return {}
    result = {}
    result["samples"] = folded
    result

  -> .record_trace(tmpdir, template, argv, duration)
    self.record_trace(tmpdir, template, argv, duration, false)

  -> .record_trace(tmpdir, template, argv, duration, alloc_on)
    trace_path = tmpdir + "/flame.trace"
    bin_q = self.quote_argv(argv)
    trace_q = Tungsten:Flame:Builder.shell_quote(trace_path)
    tpl_q = Tungsten:Flame:Builder.shell_quote(template)
    log_path = tmpdir + "/xctrace.log"
    log_q = Tungsten:Flame:Builder.shell_quote(log_path)
    tgt_q = Tungsten:Flame:Builder.shell_quote(tmpdir + "/target.out")
    alloc_env = ""
    if alloc_on || (env("TUNGSTEN_FLAME_ALLOC") != nil && env("TUNGSTEN_FLAME_ALLOC") != "")
      alloc_env = " --env TUNGSTEN_ALLOC_PROFILE=1"
    rec_cmd = "xctrace record --template " + tpl_q + " --time-limit " + duration.to_s() + "s --output " + trace_q + " --env DYLD_PRINT_SEGMENTS=1" + alloc_env + " --target-stdout " + tgt_q + " --launch -- " + bin_q + " > " + log_q + " 2>&1"
    system(rec_cmd)
    if alloc_env != ""
      self.print_alloc_report(read_file(tmpdir + "/target.out"))
    if !file?(trace_path + "/form.template")
      << "sampler: xctrace record failed (" + template.split("/").last + ")"
      log_text = read_file(log_path)
      if log_text != nil && log_text.strip().size() > 0
        << log_text.strip()
      return nil
    trace_path

  # Parse and print `TALLOC <kind> <count> <bytes>` lines emitted by the
  # Tungsten C runtime when `TUNGSTEN_ALLOC_PROFILE=1` is set. Filters empty
  # tokens from `split(" ")` because runtime.c pads columns with spaces.
  -> .print_alloc_report(tgt_text)
    if tgt_text == nil
      return
    << ""
    << "  Allocations (runtime, whole run)"
    shown = 0
    tgt_text.split("\n").each -> (ln)
      if ln.starts_with?("TALLOC ")
        parts = ln.split(" ").select -> (p) p.size() > 0
        if parts.size() >= 4
          << "    " + Tungsten:Flame:Folded.pad_right(parts[1], 15) + "  count=" + parts[2] + "  bytes=" + parts[3]
          shown += 1
    if shown == 0
      << "    (no TALLOC lines — child exited abnormally or runtime predates --alloc)"

  -> .export_table(trace_path, schema)
    trace_q = Tungsten:Flame:Builder.shell_quote(trace_path)
    xpath = "/trace-toc/run\[@number=\"1\"\]/data/table\[@schema=\"" + schema + "\"\]"
    xpath_q = Tungsten:Flame:Builder.shell_quote(xpath)
    xml_text = capture("xctrace export --input " + trace_q + " --xpath " + xpath_q + " 2>/dev/null")
    if xml_text == nil || !xml_text.include?("<row>")
      return ""
    xml_text

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
      if line.include?("Kernel mapped ") && line.ends_with?("/" + bin_path.split("/").last)
        seen_map = true
      i = i + 1
    ""

  -> .os_name()
    capture("uname -s").strip()

  -> .mktmpdir()
    capture("mktemp -d -t tungsten-flame").strip()

  -> .rmtree(dir)
    if dir != nil && dir != "" && dir != "/" && (dir.include?("tungsten-flame") || dir.starts_with?("/tmp/") || dir.starts_with?("/var/"))
      system("rm -rf " + Tungsten:Flame:Builder.shell_quote(dir))

  -> .basename_noext(path)
    slash = path.rindex("/")
    base = slash != nil ? path.slice(slash + 1, path.size() - slash - 1) : path
    dot = base.rindex(".")
    dot != nil ? base.slice(0, dot) : base
