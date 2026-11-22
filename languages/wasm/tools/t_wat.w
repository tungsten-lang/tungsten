use ../wasm

src = File.read(ARGV[0])
b = wat_to_wasm(src)
m = wasm_decode(b)
wasm_validate(m)
<< "valid; code words " + m.code.size.to_s
if ARGV.size > 1
  inst = wasm_instantiate(m, ->(a, b) nil)
  f = inst.export(ARGV[1])
  args = []
  i = 2
  while i < ARGV.size
    args.push(ARGV[i].to_i)
    i += 1
  << wasm_call(f, args)
