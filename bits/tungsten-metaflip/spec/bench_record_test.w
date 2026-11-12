# Round trip of the benchmark run record (lib/metaflip/bench/record.w): field
# order, number formats, nulls, nested traces, escapes, unknown keys, torn
# lines and the identity key. Prints FAIL lines and exits 1 on a mismatch.
use core/file
use core/system
use ../lib/metaflip/bench/record
use ../lib/metaflip/bench/format

counts = {"checks" => 0, "failures" => 0}

-> expect(counts, label, got, want)
  counts["checks"] += 1
  if got != want
    counts["failures"] += 1
    << "FAIL " + label + ": got " + got.to_s + " want " + want.to_s

rec = {"schema" => 1, "experiment" => "eé", "algo" => "metaflip/V0", "variant" => "V0", "task" => "9x9x9@perminov486", "index" => 4, "seed" => 1004, "status" => "ok", "error" => nil, "target_rank" => 485, "start_rank" => 486, "budget_cpu_s" => ~60.5, "hit" => true, "tool_hit" => true, "exact" => true, "best_rank" => 485, "cpu_s_total" => ~12.3456786, "cpu_s_tree" => ~12.4, "cpu_s_to_hit" => ~12.3456786, "wall_s_total" => ~13.0, "load1" => ~13.919921875, "proposals_total" => 246843, "proposals_to_hit" => 246843, "flips_total" => 233730, "flips_to_hit" => nil, "trace" => [[~0.0037, 6259, 6088, 486], [~12.34, 246843, nil, 485]], "instr_retired" => 123456789012345, "cycles" => nil, "max_rss_kb" => 3200, "scheme_sha256" => "ab12", "exit_code" => 0, "signal" => nil, "host" => "h\"x\\y", "commit" => "4a19059", "tool" => "wide_rect_walk", "zz_extra" => "kept", "aa_extra" => 7}
line = Record.encode(rec)
expect(counts, "one line", line.include?("\n"), false)
expect(counts, "field order starts with schema", line.starts_with?("{\"schema\":1,\"experiment\":"), true)
expect(counts, "float trimmed", line.include?("\"budget_cpu_s\":60.5,"), true)
expect(counts, "six decimals rounded", line.include?("\"cpu_s_total\":12.345679,"), true)
expect(counts, "load has three decimals", line.include?("\"load1\":13.92,"), true)
expect(counts, "nulls stay null", line.include?("\"error\":null,"), true)
expect(counts, "nested trace", line.include?("\"trace\":\[\[0.0037,6259,6088,486\],\[12.34,246843,null,485\]\],"), true)
expect(counts, "big integer", line.include?("\"instr_retired\":123456789012345,"), true)
expect(counts, "extra keys follow in insertion order", line.ends_with?("\"zz_extra\":\"kept\",\"aa_extra\":7}"), true)
back = Record.parse(line)
expect(counts, "round trip is stable", Record.encode(back), line)
expect(counts, "escapes survive", back["host"], "h\"x\\y")
expect(counts, "unicode survives", back["experiment"], "eé")
expect(counts, "trace survives", back["trace"][1][3], 485)
expect(counts, "null inside a trace", back["trace"][1][2], nil)
expect(counts, "key", Record.key(back), "eé|metaflip/V0|9x9x9@perminov486|1004")

expect(counts, "non-finite floats become null", Record.value_json(Stats.inf(), 6), "null")
expect(counts, "integers", Record.value_json(-12, 6), "-12")
expect(counts, "booleans", Record.value_json(false, 6), "false")
expect(counts, "strings are escaped", Record.value_json("a\nb", 6), "\"a\\nb\"")

# A file with a torn last line and a foreign line.
path = env("TMPDIR") == nil ? "/tmp/bench_record_test.jsonl" : env("TMPDIR") + "/bench_record_test.jsonl"
File.rm(path) if File.exists?(path)
expect(counts, "append", Record.append(path, rec), true)
expect(counts, "append again", Record.append(path, back), true)
ccall("__w_append_file", path, "{\"not\":\"a record\"}\n")
ccall("__w_append_file", path, "{\"schema\":1,\"exp")
expect(counts, "loading skips the torn and the foreign line", Record.load(path).size, 2)
File.rm(path)
expect(counts, "a missing file has no records", Record.load(path).size, 0)

bad = false
begin
  Record.parse("{\"schema\":2,\"experiment\":\"x\"}")
rescue e
  bad = true
expect(counts, "schema 2 is rejected", bad, true)

if counts["failures"] > 0
  << "FAIL " + counts["failures"].to_s + " of " + counts["checks"].to_s + " record checks"
  exit(1)
<< "PASS bench record: " + counts["checks"].to_s + " checks"
