# sampler.w — Profile a compiled binary and return folded stacks.
#
# Linux: shells `perf record -g --call-graph fp` for `duration` seconds,
# then `perf script` text → PerfScript.collapse → folded stacks.
#
# macOS: stub. Unblocked when task #12 (xctrace_xml.w) lands — that
# parser will consume the .trace bundle's schemas and emit folded
# stacks the same way PerfScript.collapse does for perf.
#
# Returns the folded-stack text as a string, or nil on failure.

in Tungsten:Flame

+ Sampler

  # Returns a dict { metric_name => folded_text } so flame.w can render
  # per-metric sections. Single-metric flows return one key ("cycles"
  # on Linux, "samples" on macOS). Multi-event extension fills more.
  -> .profile(bin_path, duration, rate)
    os = Sampler.os_name()
    if os == "Linux"
      Sampler.profile_linux(bin_path, duration, rate)
    elsif os == "Darwin"
      Sampler.profile_macos(bin_path, duration, rate)
    else
      << "sampler: unsupported OS: " + os
      {}

  -> .profile_linux(bin_path, duration, rate)
    tmpdir = Sampler.mktmpdir()
    perf_data = tmpdir + "/perf.data"
    bin_q = Builder.shell_quote(bin_path)
    pd_q = Builder.shell_quote(perf_data)
    rate_s = (rate == nil ? "99" : rate.to_s())
    duration_s = duration.to_s()
    rec_cmd = "perf record -F " + rate_s + " -g --call-graph fp -o " + pd_q + " -- timeout " + duration_s + "s " + bin_q + " 2>/dev/null"
    if !system(rec_cmd)
      << "sampler: perf record failed"
      return {}
    script_text = capture("perf script -i " + pd_q + " 2>/dev/null")
    if script_text == nil || script_text.size() == 0
      << "sampler: perf script returned no output"
      return {}
    result = {}
    result["cycles"] = PerfScript.collapse(script_text)
    result

  -> .profile_macos(bin_path, duration, rate)
    tmpdir = Sampler.mktmpdir()
    trace_path = tmpdir + "/flame.trace"
    template = __DIR__ + "/xctrace/flame-counters.tracetemplate"
    if !file?(template)
      << "sampler: template not found: " + template
      return {}
    bin_q = Builder.shell_quote(bin_path)
    trace_q = Builder.shell_quote(trace_path)
    tpl_q = Builder.shell_quote(template)
    rec_cmd = "xctrace record --template " + tpl_q + " --time-limit " + duration.to_s() + "s --output " + trace_q + " --launch -- " + bin_q + " >/dev/null 2>&1"
    if !system(rec_cmd)
      << "sampler: xctrace record failed"
      return {}
    # kdebug-counters-with-time-sample carries stacks paired with PMC
    # values (one set of N counter readings per sample). The slot order
    # follows the order events were added to the tracetemplate.
    ob = "["
    cb = "]"
    xpath = "/trace-toc/run" + ob + "@number=\"1\"" + cb + "/data/table" + ob + "@schema=\"kdebug-counters-with-time-sample\"" + cb
    xpath_q = Builder.shell_quote(xpath)
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
    XctraceXml.collapse_counters(xml_text, bin_path, metric_names)

  -> .os_name()
    capture("uname -s").strip()

  -> .mktmpdir()
    capture("mktemp -d -t tungsten-flame").strip()

  -> .basename_noext(path)
    slash = path.rindex("/")
    base = slash != nil ? path.slice(slash + 1, path.size() - slash - 1) : path
    dot = base.rindex(".")
    dot != nil ? base.slice(0, dot) : base
