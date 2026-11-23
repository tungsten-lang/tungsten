# Method/function parameter binding & dispatch:
# - `*rest` combined with 2+ keyword params (instance, static, top-level, +block)
# - optional parameter before `&` block parameter (instance, static, top-level)
# - typed machine-int parameter coercion across compiled & interpreted engines
# - arbitrary classes do not hijack global `file?` / `read_file` / `write_file`

-> check(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# 1. *rest + 2+ keyword params
+ Opts
  -> add(*names, type: nil, default: nil)
    names.join(",") + "|" + type.to_s + "|" + default.to_s

  -> mix(first, *mid, last, type: nil, default: nil)
    first.to_s + "/" + mid.join(",") + "/" + last.to_s + "|" + type.to_s + "|" + default.to_s

  -> with_blk(*names, flag: false, &)
    res = yield
    names.join(",") + "|" + flag.to_s + "|" + res.to_s

  -> .sadd(*names, type: nil, default: nil)
    names.join(",") + "|" + type.to_s + "|" + default.to_s

-> tadd(*names, type: nil, default: nil)
  names.join(",") + "|" + type.to_s + "|" + default.to_s

o = Opts.new
check("inst *rest + 1 kwarg", o.add("--a", type: :int) == "--a|int|")
check("inst *rest + 2 pos + 2 kwargs", o.add("--a", "-b", type: :int, default: 3) == "--a,-b|int|3")
check("inst *rest + 2 pos + 0 kwargs", o.add("--a", "-b") == "--a,-b||")
check("inst *rest + 0 pos + 1 kwarg", o.add(type: :str) == "|str|")
check("inst *rest + 0 args", o.add() == "||")
check("inst leading+*rest+trailing+kwargs", o.mix("h", "m1", "m2", "t", type: :int, default: 7) == "h/m1,m2/t|int|7")
check("inst *rest + kwarg + block", (o.with_blk("x", "y", flag: true) -> 42) == "x,y|true|42")
check("static *rest + kwargs", Opts.sadd("--a", "-b", type: :int, default: 5) == "--a,-b|int|5")
check("top-level *rest + kwargs", tadd("--a", "-b", type: :int, default: 9) == "--a,-b|int|9")

# 2. Optional parameter before `&`
+ Runner
  -> run(label, fragment = nil, &)
    out = "noblock"
    if block?
      out = (yield()).to_s
    label + "|" + fragment.to_s + "|" + out

  -> .srun(label, fragment = nil, &)
    out = "noblock"
    if block?
      out = (yield()).to_s
    label + "|" + fragment.to_s + "|" + out

-> trun(label, fragment = nil, &)
  out = "noblock"
  if block?
    out = (yield()).to_s
  label + "|" + fragment.to_s + "|" + out

r = Runner.new
# Run twice in a loop to also exercise the IC hit path
i = 0
while i < 3
  check("inst opt before & omitted ([i])", (r.run("x") -> 2) == "x||2")
  check("inst opt before & supplied ([i])", (r.run("x", "f") -> 2) == "x|f|2")
  check("inst opt before & no block ([i])", r.run("x", "f") == "x|f|noblock")
  i += 1
check("static opt before & omitted", (Runner.srun("x") -> 3) == "x||3")
check("top-level opt before & omitted", (trun("x") -> 4) == "x||4")

# 3. Typed machine-int parameter coercion
-> clear_low(x) (i64) i64
  x & (x - 1)

-> to_u64(x) (u64) u64
  x

-> to_i64(x) (i64) i64
  x

check("typed (i64) coerces BigInt", clear_low((1 << 70) | 12) == 8)
check("typed (u64) wraps BigInt", to_u64((1 << 70) | 44) == 44)
check("typed (i64) wraps signed bit 63", to_i64(1 << 63) == -(1 << 63))

# 4. Arbitrary class does not hijack global file?/read_file/write_file
+ Unrelated
  -> .bar
    1

file_hijack_raised = false
begin
  Unrelated.file?("VERSION")
rescue err
  file_hijack_raised = true
check("Unrelated.file? raises instead of hijacking global file?", file_hijack_raised)

read_hijack_raised = false
begin
  Unrelated.read_file("VERSION")
rescue err
  read_hijack_raised = true
check("Unrelated.read_file raises instead of hijacking global read_file", read_hijack_raised)

check("File.file? still works", File.file?("VERSION"))
check("bare file? still works", file?("VERSION"))

# 5. Conditional parameter reassignment inside begin/ensure and multi_assign
-> cond_reassign_in_begin(x, flag)
  begin
    if flag
      x = 99
    x
  ensure
    nil

-> cond_swap_params(a, b, flag)
  if flag
    a, b = b, a
  a * 10 + b

check("param reassigned conditionally in begin (false branch)", cond_reassign_in_begin(7, false) == 7)
check("param reassigned conditionally in begin (true branch)", cond_reassign_in_begin(7, true) == 99)
check("params swapped conditionally via multi_assign (false)", cond_swap_params(1, 2, false) == 12)
check("params swapped conditionally via multi_assign (true)", cond_swap_params(1, 2, true) == 21)
