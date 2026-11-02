# spec: compiled -- exercises Interpreter directly; nesting interpreters is unsupported
use spec
use ../lib/hashing
use ../lib/interpreter

describe "Interpreter native disposal hints" ->
  it "keeps values owned by interpreter environments alive" ->
    interp = Interpreter.new
    code = "a = i8\[2]\na\[0] = 7\nb = a\nz = ccall(\"w_value_free_w\", a)\n\[z, b\[0], a.size]"
    expect(interp.run(code)).to eq([0, 7, 2])

  it "accepts disposal of nil" ->
    interp = Interpreter.new
    expect(interp.run("ccall(\"w_value_free_w\", nil)")).to eq(0)

spec_summary
