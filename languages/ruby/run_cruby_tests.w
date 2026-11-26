# languages/ruby/run_cruby_tests.w — CRuby 4.0.9 bootstraptest runner & benchmark driver.
#
# Extracts real `assert_equal` / `assert_match` / `assert_normal_exit` cases from
# `/Users/erik/src/ruby-4.0.9/bootstraptest/test_*.rb` using CRuby 4.0.9 itself so every
# `%q{...}`, `%Q(...)`, heredoc, and generated test is 100% faithful to CRuby 4.0.9,
# then runs them against Tungsten's Ruby 4.0 engine and reports per-file conformance!

use core/ruby
use core/json

CRUBY_BIN = "/Users/erik/.rubies/ruby-4.0.9/bin/ruby"
CRUBY_DIR = "/Users/erik/src/ruby-4.0.9/bootstraptest"

FILES = [
  "test_literal.rb",
  "test_literal_suffix.rb",
  "test_string.rb",
  "test_struct.rb",
  "test_attr.rb",
  "test_syntax.rb",
  "test_flow.rb",
  "test_jump.rb",
  "test_massign.rb",
  "test_exception.rb",
  "test_block.rb",
  "test_proc.rb",
  "test_class.rb",
  "test_method.rb"
]

# Extract assertions from a CRuby bootstraptest file using CRuby 4.0.9's own parser/DSL
-> extract_cases(path)
  rb_script = 'require "json"; $cases = []; ' +
    'def target_platform; "arm64-darwin"; end; ' +
    'def assert_equal(want, src, msg = nil, **kw); $cases << ["eq", want.to_s, src.to_s, msg.to_s]; end; ' +
    'def assert_match(want, src, msg = nil, **kw); $cases << ["match", want.is_a?(Regexp) ? want.source : want.to_s, src.to_s, msg.to_s]; end; ' +
    'def assert_not_match(want, src, msg = nil, **kw); $cases << ["not_match", want.is_a?(Regexp) ? want.source : want.to_s, src.to_s, msg.to_s]; end; ' +
    'def assert_normal_exit(src, msg = nil, **kw); $cases << ["exit", "", src.to_s, msg.to_s]; end; ' +
    'def assert_finish(t, src, msg = nil, **kw); $cases << ["exit", "", src.to_s, msg.to_s]; end; ' +
    'def assert_valid_syntax(src, msg = nil); $cases << ["syntax", "", src.to_s, msg.to_s]; end; ' +
    'def show_limit(a=nil,b=nil); end; ' +
    'def show_error(*a); end; ' +
    'def no_core_dump(*a); yield if block_given?; end; ' +
    'load ARGV[0]; puts JSON.generate($cases)'
  tmp = "/tmp/rb_extract_bootstrap.rb"
  File.write(tmp, rb_script)
  out = OS.capture(CRUBY_BIN + " " + tmp + " " + path + " 2>/dev/null")
  return [] if out == nil || out.strip == ""
  begin
    v = JSON.parse(out)
    return v.is_a?(Array) ? v : []
  rescue e
    return []

total_pass = 0
total_fail = 0
total_err = 0

show_fails = Env.get("SHOW_FAILS", "0") == "1"
only_file = Env.get("ONLY_FILE", "")

FILES.each ->(fn)
  next if only_file != "" && fn != only_file
  cases = extract_cases(CRUBY_DIR + "/" + fn)
  fp = 0
  ff = 0
  fe = 0
  sample_fails = []
  i = 0
  while i < cases.size
    c = cases[i]
    kind = c[0]
    want = c[1]
    src = c[2]
    ok = false
    err_s = nil
    got_s = ""
    begin
      vm = Ruby.vm
      vm.max_steps = 50000
      if kind == "syntax"
        Ruby.parse(src)
        ok = true
      else
        res = vm.eval_source(src)
        if kind == "eq"
          got_s = res == nil ? "" : vm.call_method(res, "to_s", [], {}, nil, vm.top_env).to_s
          ok = got_s == want
        elsif kind == "match"
          got_s = res == nil ? "" : vm.call_method(res, "to_s", [], {}, nil, vm.top_env).to_s
          ok = Regex.new(want).match_data(got_s) != nil
        elsif kind == "not_match"
          got_s = res == nil ? "" : vm.call_method(res, "to_s", [], {}, nil, vm.top_env).to_s
          ok = Regex.new(want).match_data(got_s) == nil
        else
          ok = true
    rescue e
      err_s = e.to_s
    if ok
      fp += 1
    elsif err_s != nil
      fe += 1
      sample_fails.push("  ERR  #" + (i + 1).to_s + ": " + err_s.slice(0, 90) + " | src=" + src.gsub("\n", "; ").slice(0, 70)) if sample_fails.size < 8
    else
      ff += 1
      sample_fails.push("  FAIL #" + (i + 1).to_s + ": got=" + got_s.slice(0, 40) + " want=" + want.slice(0, 40) + " | src=" + src.gsub("\n", "; ").slice(0, 60)) if sample_fails.size < 8
    i += 1
  total_pass += fp
  total_fail += ff
  total_err += fe
  tot = fp + ff + fe
  pct = tot > 0 ? ((fp * 100) / tot) : 0
  << fn + ": " + fp.to_s + "/" + tot.to_s + " (" + pct.to_s + "%) (fail=" + ff.to_s + " err=" + fe.to_s + ")"
  if show_fails
    sample_fails.each ->(ln) << ln

grand = total_pass + total_fail + total_err
gpct = grand > 0 ? ((total_pass * 100) / grand) : 0
<< "--------------------------------------------"
<< "CRuby 4.0.9 bootstraptest TOTAL: " + total_pass.to_s + "/" + grand.to_s + " (" + gpct.to_s + "%) (fail=" + total_fail.to_s + " err=" + total_err.to_s + ")"
