# Decode, validate/compile and instantiate a .wasm with every import stubbed; then call
# zero-argument exports listed on the command line and print their results.
#   probe file.wasm [export ...]
use ../wasm

t0 = clock_ms()
bytes = File.read_bytes(ARGV[0])
m = wasm_decode(bytes)
t1 = clock_ms()
wasm_validate(m)
t2 = clock_ms()
<< "decode " + (t1 - t0).to_s + " ms, validate+compile " + (t2 - t1).to_s + " ms: " + m.funcs.size.to_s + " funcs, " + m.imports.size.to_s + " imports, " + m.exports.size.to_s + " exports, " + m.code.size.to_s + " code words"
resolver = ->(mod, name)
  imp = nil
  m.imports.each ->(i) imp = i if i.mod == mod && i.name == name
  v = nil
  if imp.kind == 0
    t = m.canon[imp.desc]
    ft = W_TYPES.types[t]
    v = wasm_host_func(t, ->(args) ft.results.map(->(r) wt_ref?(r) ? nil : 0))
  elsif imp.kind == 1
    tt = imp.desc
    v = WTable.new(tt.elem, tt.min, tt.max, tt.is64, nil)
  elsif imp.kind == 2
    mt = imp.desc
    v = WMemory.new(mt.min, mt.max, mt.shared, mt.is64, mt.page_log2)
  elsif imp.kind == 3
    g = WGlobal.new(imp.desc.type, imp.desc.mutable)
    v = g
  else
    v = WTag.new(m.canon[imp.desc])
  v
inst = wasm_instantiate(m, resolver)
<< "instantiate " + (clock_ms() - t2).to_s + " ms"
if Env["WASM_JIT_WAIT"] != nil
  t3 = clock_ms()
  ok = wasm_jit_wait(m)
  << "jit " + (ok ? m.jit.funcs.size.to_s + " functions in " + m.jit.ms.to_s + " ms" : "unavailable")
i = 1
while i < ARGV.size
  f = inst.export(ARGV[i])
  << ARGV[i] + " = " + wasm_call(f, []).to_s
  i += 1
