use core/dir

# Static guard for the WValue distinction between Bool and Int.  In Tungsten,
# `false == 0` and `true != 0` are both false/true by type, not numeric truth
# aliases.  An assertion helper that accepts a Bool and tests it against 0 can
# therefore let every false assertion pass.  Untyped legacy helpers may accept
# both Bool and explicit 0/1 predicates, but must test `false` as well as 0.

-> ahst_assertion_helper?(line) (String) bool
  line.starts_with?("-> ") && line.include?("condition") && (line.include?("expect") || line.include?("assert") || line.include?("check") || line.include?("require"))

-> ahst_integer_condition_comparison?(line) (String) bool
  line.include?("condition == 0") || line.include?("condition != 0") || line.include?("condition == 1") || line.include?("condition != 1") || line.include?("0 == condition") || line.include?("0 != condition") || line.include?("1 == condition") || line.include?("1 != condition")

-> ahst_scan_file(path) (String) i64
  source = read_file(path)
  if source == nil
    << "FAIL assertion-helper guard could not read " + path
    return 1
  lines = source.split("\n")
  in_helper = false
  typed_bool = false
  failures = 0 ## i64
  i = 0 ## i64
  while i < lines.size()
    line = lines[i]
    if line.starts_with?("-> ")
      in_helper = ahst_assertion_helper?(line)
      typed_bool = in_helper && line.include?("bool")
    elsif in_helper && ahst_integer_condition_comparison?(line)
      # Bool-only helpers must use `!condition` / `condition == false`.
      # A mixed legacy helper is sound only when the same guard also rejects
      # Bool false explicitly before admitting a nonzero Int predicate.
      mixed_guard = line.include?("condition == false") || line.include?("condition != true")
      if typed_bool || !mixed_guard
        << "FAIL assertion-helper bool/int comparison " + path + ":" + (i + 1).to_s()
        failures += 1
    i += 1
  failures

-> ahst_scan_dir(path) (String) i64
  names = Dir.entries(path)
  failures = 0 ## i64
  i = 0 ## i64
  while i < names.size()
    name = names[i]
    if name.ends_with?(".w")
      failures += ahst_scan_file(path + "/" + name)
    i += 1
  failures

root = __DIR__ + "/../../.."
failures = ahst_scan_dir(__DIR__) ## i64
failures += ahst_scan_dir(root + "/benchmarks/matmul/metaflip")
if failures > 0
  exit(1)
<< "PASS assertion-helper Bool/Int static guard"
