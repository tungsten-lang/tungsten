# wasm/gc — GC proposal objects: struct/array/i31 instructions (OP_EXT slow path) and casts.

-> w_ext_gc(ex, inst, sub, code, o, fp)
  w_trap_code(99)

-> w_eval_const_gc(inst, r, sub, st)
  w_trap_code(99)
