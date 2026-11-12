# `metabench exec`: run one command as a measured child. It polls the child's
# CPU time and kills the process group once a limit is reached, and writes a
# one-line JSON report with the exact resource usage. Adapters run their tool
# through it, so a run is priced by the tool alone.
use core/file
use proc
use format

+ Exec
  # Runs `argv`; kills the child after `kill_s` CPU seconds (nil: never). The
  # report goes to `report_path`. Returns the exit status of the child (128 + signal after a signal).
  -> .run(argv, kill_s, report_path)
    started = Proc.now_ms()
    child = Child.spawn(argv)
    meter = Meter.new(child.pid)
    limit_ns = nil
    if kill_s != nil
      seconds = kill_s.to_f ## f64
      scaled = seconds * 1000000000.0 ## f64
      limit_ns = scaled.to_i
    killed = false
    while !meter.exited?
      cpu = meter.cpu_ns
      if limit_ns != nil && cpu != nil && cpu >= limit_ns && !killed
        child.kill
        killed = true
      Proc.sleep_ms(2)
    final = meter.final
    ended = nil
    while ended == nil
      ended = child.poll
      Proc.sleep_ms(1) if ended == nil
    Exec.report(report_path, ended, final, killed, Proc.now_ms() - started)
    ended.signal == 0 ? ended.code : 128 + ended.signal

  -> .report(path, ended, final, killed, wall_ms)
    fields = []
    fields.push("\"cpu_s\":" + Format.trimmed(ended.cpu_s, 6))
    fields.push("\"user_s\":" + Format.trimmed(ended.user_s, 6))
    fields.push("\"sys_s\":" + Format.trimmed(ended.sys_s, 6))
    fields.push("\"wall_s\":" + Format.trimmed(Exit.seconds(wall_ms * 1000), 3))
    ["instr_retired", "cycles"].each -> (key)
      fields.push("\"" + key + "\":" + (final.key?(key) ? final[key].to_s : "null"))
    fields.push("\"max_rss_kb\":" + (ended.max_rss_bytes / 1024).to_s)
    fields.push("\"exit\":" + ended.code.to_s)
    fields.push("\"signal\":" + ended.signal.to_s)
    fields.push("\"killed\":" + (killed ? "true" : "false"))
    write_file(path, "{" + fields.join(",") + "}\n")
