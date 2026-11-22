# Run exports of a .wasm file and time them (no imports beyond an empty resolver).
#   bin/tungsten -o /tmp/wrun --release tools/run.w && /tmp/wrun file.wasm name arg [name arg ...]
use ../wasm

t0 = clock_ms()
m = wasm_decode(File.read_bytes(ARGV[0]))
wasm_validate(m)
inst = wasm_instantiate(m, ->(a, b) nil)
<< "load+validate+compile+instantiate " + (clock_ms() - t0).to_s + " ms (" + m.funcs.size.to_s + " funcs, " + m.code.size.to_s + " code words)"
if Env["WASM_JIT_WAIT"] != nil
  t1 = clock_ms()
  ok = wasm_jit_wait(m)
  << "jit: " + (ok ? m.jit.funcs.size.to_s + " functions compiled in " + m.jit.ms.to_s + " ms (waited " + (clock_ms() - t1).to_s + " ms)" : "not available")
i = 1
while i + 1 < ARGV.size
  f = inst.export(ARGV[i])
  ft = f.sig
  arg = ARGV[i + 1].to_i
  t = clock_ms()
  r = wasm_call(f, [arg])
  dt = clock_ms() - t
  v = r[0]
  v = (v >= 2147483648 ? v - 4294967296 : v) if ft.results[0] == T_I32
  v = js_like_f64(v) if ft.results[0] == T_F64
  << ARGV[i] + "(" + arg.to_s + ") = " + v.to_s + "  " + dt.to_s + " ms"
  i += 2

-> js_like_f64(b)
  wvalue_from_bits(((b ## i64) + (0x0001000000000000 ## i64)) ## i64)
