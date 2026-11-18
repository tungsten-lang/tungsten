# The run record: one JSON object per line of a `<algo>.<variant>.jsonl` file
# (schema 1, described in bench/README.md). A record in memory is a Hash with
# string keys; encoding fixes the field order and the number formats.
use core/json
use core/file
use stats
use format

+ Record
  # Fields in file order; extra keys follow in insertion order.
  -> .fields()
    ["schema", "experiment", "algo", "variant", "task", "index", "seed", "status", "error", "target_rank", "start_rank", "budget_cpu_s", "hit", "tool_hit", "exact", "best_rank", "cpu_s_total", "cpu_s_tree", "cpu_s_to_hit", "wall_s_total", "load1", "proposals_total", "proposals_to_hit", "flips_total", "flips_to_hit", "trace", "instr_retired", "cycles", "max_rss_kb", "scheme_sha256", "exit_code", "signal", "host", "commit", "tool"]

  # Digits after the point of the float fields; other floats use six.
  -> .decimals(key) (String)
    if key == "load1" || key == "budget_cpu_s"
      return 3
    6

  # One JSON value; floats with `decimals` digits, trailing zeros dropped.
  -> .value_json(v, decimals)
    kind = type(v)
    if kind == "Nil"
      return "null"
    if kind == "Boolean"
      if v
        return "true"
      return "false"
    if kind == "Int" || kind == "BigInt"
      return v.to_s
    if kind == "Float" || kind == "Decimal"
      x = v.to_f ## f64
      if x != x || x == Stats.inf() || x == 0.0 - Stats.inf()
        return "null"
      return Format.trimmed(x, decimals)
    if kind == "String"
      return JSON.encode_string(v)
    parts = []
    v.each -> (item)
      parts.push(Record.value_json(item, decimals))
    "\[" + parts.join(",") + "\]"

  # The record as one JSON line (without the newline).
  -> .encode(rec)
    order = Record.fields()
    keys = []
    order.each -> (key)
      keys.push(key) if rec.key?(key)
    rec.keys.each -> (key)
      keys.push(key) if !order.include?(key)
    parts = []
    keys.each -> (key)
      parts.push(JSON.encode_string(key) + ":" + Record.value_json(rec[key], Record.decimals(key)))
    "{" + parts.join(",") + "}"

  # The record of one JSON line; raises when the line is not a schema-1 record.
  -> .parse(line)
    rec = JSON.parse(line)
    if type(rec) != "Hash" || rec["schema"] != 1
      raise "not a schema 1 record"
    ["experiment", "algo", "task", "seed", "status"].each -> (key)
      raise "record without " + key if !rec.key?(key)
    rec

  # The identity of a run within one experiment.
  -> .key(rec)
    rec["experiment"] + "|" + rec["algo"] + "|" + rec["task"] + "|" + rec["seed"].to_s

  # Appends the record to a JSONL file; false when the write failed.
  -> .append(path, rec)
    line = Record.encode(rec) + "\n"
    if File.exists?(path) && File.size(path) > 0
      file = File.open(path, "rb")
      begin
        file.seek(-1, 2)
        line = "\n" + line if file.read(1) != "\n"
      ensure
        file.close()
    ccall("__w_append_file", path, line)

  # The complete records of a JSONL file, in order. A line that is torn or not
  # a record (the file may end inside a write) is skipped.
  -> .load(path)
    records = []
    text = read_file(path)
    if text == nil
      return records
    lines = text.split("\n")
    skipped = 0 ## i64
    complete = lines.size
    if !text.ends_with?("\n")
      complete -= 1
    i = 0 ## i64
    while i < complete
      if lines[i] != ""
        begin
          records.push(Record.parse(lines[i]))
        rescue e
          skipped += 1
      i += 1
    records
