# wasm/jit — the optimizing tier: LLVM IR from the interpreter's register code.
#
# Choice (vs. a hand-written baseline JIT): the register code is already a 3-address
# machine over frame slots, so each function translates op by op into LLVM IR with one
# alloca per slot; clang -O2 (mem2reg, GVN, LICM, the vectorizers, AArch64 isel) turns that
# into native code close to what a C compiler emits for the same loops, with no code
# generator of ours to maintain. The cost is latency (clang runs for tens to hundreds of
# milliseconds), which the interpreter hides: compilation runs on a background thread
# after instantiation and the finished functions are swapped in at the next call boundary
# by patching their OP_ENTER into OP_JIT. Without a clang the engine just keeps
# interpreting.
#
# Compiled ABI: i64 @wjN(ptr ctx, ptr fp) — args in fp[0..], results written back there,
# 0 or a trap code returned. ctx: [0] memory base, [1] memory size, [2] globals base,
# [3] call depth. Functions are compiled when every op is in the supported set and every
# direct callee is compiled too (calls to imports, call_indirect, references, SIMD and
# OP_EXT keep a function in the interpreter).

W_JIT_ON = [true]
W_JIT_DEPTH = 5000

+ WJit
  rw :thread, :path, :funcs, :done, :ptrs, :failed, :ms

  -> new
    @thread = nil
    @path = nil
    @funcs = []
    @done = false
    @ptrs = nil
    @failed = false
    @ms = 0

-> w_jit_cc
  cc = Env["TUNGSTEN_CC"]
  return cc if cc != nil && cc.size > 0
  cands = ["/opt/homebrew/opt/llvm/bin/clang", "/usr/bin/clang"]
  i = 0
  while i < cands.size
    return cands[i] if File.exist?(cands[i])
    i += 1
  nil

# Op lengths (words incl. opcode) for the ops the JIT understands; 0 = unsupported.
-> w_jit_len(op)
  return 1 if op == OP_NOP || op == OP_RET
  return 2 if op == OP_JMP || op == OP_TRAP || op == OP_CHK64
  return 3 if op == OP_JZ || op == OP_JNZ || op == OP_CALL || op == OP_MOV || op == OP_MOV2 || op == OP_CONST || op == OP_GGET || op == OP_GSET || op == OP_GGET2 || op == OP_GSET2 || op == OP_MSIZE
  return 4 if op == OP_CONST2 || op == OP_RET_CALL || op == OP_MFILL || op == OP_MCOPY
  return 5 if op == OP_ENTER || op == OP_SELECT || op == OP_SELECT2
  return 4 if op >= OP_ADD32 && op <= OP_GES64 && !w_jit_unary?(op)
  return 3 if op >= OP_ADD32 && op <= OP_EXT16S64
  return 4 if op >= OP_ADDI32 && op <= OP_GESI64
  return 4 if op >= OP_JEQ && op <= OP_JGESI64
  return 3 if op >= OP_FABS32 && op <= OP_FSQRT32
  return 4 if op >= OP_FADD32 && op <= OP_FGE32
  return 3 if op >= OP_FABS64 && op <= OP_FSQRT64
  return 4 if op >= OP_FADD64 && op <= OP_FGE64
  return 3 if op >= OP_TRUNC_F32_S32 && op <= OP_PROMOTE
  return 4 if op >= OP_LD32 && op <= OP_ST128
  0

-> w_jit_unary?(op)
  op == OP_CLZ32 || op == OP_CTZ32 || op == OP_CLZ64 || op == OP_CTZ64 || op == OP_POPCNT || op == OP_EQZ || (op >= OP_WRAP && op <= OP_EXT16S64)

# EXT sub-ops that change control flow (throw, rethrow, tail calls out of the instance)
# cannot be upcalled from compiled code.
-> w_jit_ext_ok?(sub)
  sub != 0x08 && sub != 0x09 && sub != 0x0a && sub != 0x12 && sub != 0x13 && sub != 0x15

# The length of the op at pc for the JIT, or 0 if unsupported.
-> w_jit_op_len(code, pc)
  op = code[pc]
  return code[pc + 2] + 4 if op == OP_BR_TABLE
  return 4 if op == OP_CALL_IMPORT
  return 6 if op == OP_CALL_IND
  return (w_jit_ext_ok?(code[pc + 2]) ? code[pc + 1] : 0) if op == OP_EXT
  return 0 if op == OP_LD128 || op == OP_ST128 || op == OP_MOV2 || op == OP_CONST2 || op == OP_SELECT2 || op == OP_GGET2 || op == OP_GSET2
  w_jit_len(op)

# Which defined functions (indices into m.fentry) can be compiled. Calls to functions that
# stay interpreted, imports, call_indirect and OP_EXT go through an upcall into the driver.
-> w_jit_plan(m)
  n = m.fentry.size
  ok = []
  code = m.code
  k = 0
  while k < n
    meta = m.fentry[k]
    good = meta.handlers.size == 0 && meta.fsize < 4000
    pc = meta.entry
    while pc < meta.stop && good
      l = w_jit_op_len(code, pc)
      good = false if l == 0
      pc += l
    ok.push(good)
    k += 1
  ok

-> w_jit_index_of(m, entry)
  lo = 0
  hi = m.fentry.size - 1
  while lo <= hi
    mid = (lo + hi) / 2
    e = m.fentry[mid].entry
    return mid if e == entry
    if e < entry
      lo = mid + 1
    else
      hi = mid - 1
  -1

+ WIr
  rw :out, :n, :fsize, :plan

  -> new(@fsize)
    @out = []
    @n = 0

  -> t
    @n += 1
    "%t" + @n.to_s

  -> line(s)
    @out.push("  " + s + "\n")

  -> label(s)
    @out.push(s + ":\n")

  -> slot(i)
    "%s" + i.to_s

  -> ld(i)
    v = t()
    line(v + " = load i64, ptr " + slot(i))
    v

  -> st(i, v)
    line("store i64 " + v + ", ptr " + slot(i))

  -> f32(v)
    a = t()
    line(a + " = trunc i64 " + v + " to i32")
    b = t()
    line(b + " = bitcast i32 " + a + " to float")
    b

  -> from_f32(v)
    a = t()
    line(a + " = bitcast float " + v + " to i32")
    b = t()
    line(b + " = zext i32 " + a + " to i64")
    b

  -> f64(v)
    a = t()
    line(a + " = bitcast i64 " + v + " to double")
    a

  -> from_f64(v)
    a = t()
    line(a + " = bitcast double " + v + " to i64")
    a

  -> mask32(v)
    a = t()
    line(a + " = and i64 " + v + ", 4294967295")
    a

  -> sext32(v)
    a = t()
    line(a + " = trunc i64 " + v + " to i32")
    b = t()
    line(b + " = sext i32 " + a + " to i64")
    b

  -> canon(v, ft, sfx)
    r = t()
    line(r + " = call " + ft + " @llvm.canonicalize." + sfx + "(" + ft + " " + v + ")")
    r

  -> mem
    v = t()
    line(v + " = load ptr, ptr %memv")
    v

  -> msize
    v = t()
    line(v + " = load i64, ptr %msizev")
    v

  -> reload_mem
    a = t()
    line(a + " = load i64, ptr %membase.p")
    b = t()
    line(b + " = inttoptr i64 " + a + " to ptr")
    line("store ptr " + b + ", ptr %memv")
    c = t()
    line(c + " = load i64, ptr %msize.p")
    line("store i64 " + c + ", ptr %msizev")

  -> zext1(c)
    a = t()
    line(a + " = zext i1 " + c + " to i64")
    a

-> w_ir_cmp_pred(c)
  ["eq", "ne", "ult", "ugt", "ule", "uge", "slt", "sgt", "sle", "sge", "slt", "sgt", "sle", "sge"][c]

# IR for one function (meta) of module m; nil if the translation hits something unsupported.
-> w_jit_func_ir(m, k, plan)
  meta = m.fentry[k]
  code = m.code
  ir = WIr.new(meta.fsize)
  ir.plan = plan
  # jump targets
  targets = {}
  pc = meta.entry
  while pc < meta.stop
    op = code[pc]
    if op == OP_JMP
      targets[code[pc + 1]] = true
    elsif op == OP_JZ || op == OP_JNZ
      targets[code[pc + 2]] = true
    elsif op >= OP_JEQ && op <= OP_JGESI64
      targets[code[pc + 3]] = true
    elsif op == OP_BR_TABLE
      j = 0
      while j <= code[pc + 2]
        targets[code[pc + 3 + j]] = true
        j += 1
    pc += w_jit_op_len(code, pc)
  ir.out.push("define i64 @wj" + k.to_s + "(ptr %ctx, ptr %fp) {\nentry:\n")
  fs = meta.fsize
  i = 0
  while i < fs
    ir.line("%s" + i.to_s + " = alloca i64")
    i += 1
  ir.line("%membase.p = getelementptr i64, ptr %ctx, i64 0")
  ir.line("%membase.i = load i64, ptr %membase.p")
  ir.line("%mem0 = inttoptr i64 %membase.i to ptr")
  ir.line("%msize.p = getelementptr i64, ptr %ctx, i64 1")
  ir.line("%msize0 = load i64, ptr %msize.p")
  ir.line("%memv = alloca ptr")
  ir.line("%msizev = alloca i64")
  ir.line("store ptr %mem0, ptr %memv")
  ir.line("store i64 %msize0, ptr %msizev")
  ir.line("%glob.p = getelementptr i64, ptr %ctx, i64 2")
  ir.line("%glob.i = load i64, ptr %glob.p")
  ir.line("%glob = inttoptr i64 %glob.i to ptr")
  ir.line("%depth.p = getelementptr i64, ptr %ctx, i64 3")
  ir.line("%depth = load i64, ptr %depth.p")
  ir.line("%depth1 = add i64 %depth, 1")
  ir.line("store i64 %depth1, ptr %depth.p")
  ir.line("%deep = icmp ugt i64 %depth1, " + W_JIT_DEPTH.to_s)
  ir.line("br i1 %deep, label %trap9, label %body")
  ir.label("body")
  # params in, locals zeroed
  ps = meta.param_slots
  nl = 0
  meta.lslot.each ->(s) nl = s + 1 if s + 1 > nl
  i = 0
  while i < fs
    if i < ps
      ir.line("%a" + i.to_s + ".p = getelementptr i64, ptr %fp, i64 " + i.to_s)
      ir.line("%a" + i.to_s + " = load i64, ptr %a" + i.to_s + ".p")
      ir.st(i, "%a" + i.to_s)
    else
      ir.st(i, "0")
    i += 1
  pc = meta.entry
  fell = true
  while pc < meta.stop
    if targets.has_key?(pc)
      ir.line("br label %L" + pc.to_s) if fell
      ir.label("L" + pc.to_s)
    fell = true
    op = code[pc]
    nxt = pc + w_jit_op_len(code, pc)
    res = w_jit_op(ir, m, code, pc, op, nxt, meta)
    if res == nil
      << "jit: unsupported op " + op.to_s if Env["WASM_JIT_DEBUG"] != nil
      return nil
    if res == 0
      # unconditional transfer: next code is unreachable unless a label
      fell = false
      if nxt < meta.stop && !targets.has_key?(nxt)
        ir.label("U" + nxt.to_s)
        fell = true
    pc = nxt
  ir.line("br label %ret") if fell
  # exits
  ir.label("ret")
  ir.line("store i64 %depth, ptr %depth.p")
  n = meta.result_slots
  i = 0
  while i < n
    v = ir.ld(i)
    ir.line("%r" + i.to_s + ".p = getelementptr i64, ptr %fp, i64 " + i.to_s)
    ir.line("store i64 " + v + ", ptr %r" + i.to_s + ".p")
    i += 1
  ir.line("ret i64 0")
  [1, 2, 3, 4, 5, 9].each ->(c)
    ir.label("trap" + c.to_s)
    ir.line("store i64 %depth, ptr %depth.p")
    ir.line("ret i64 " + c.to_s)
  ir.out.push("}\n")
  ir.out.join("")

# Translate one op. Returns true (falls through), false (does not fall through), nil (unsupported).
-> w_jit_op(ir, m, code, pc, op, nxt, meta)
  a1 = code[pc + 1]
  a2 = op == OP_NOP || op == OP_RET ? 0 : code[pc + 2]
  a3 = code[pc + 3]
  if op == OP_NOP || op == OP_ENTER
    return 1
  if op == OP_RET
    ir.line("br label %ret")
    return 0
  if op == OP_JMP
    ir.line("br label %L" + a1.to_s)
    return 0
  if op == OP_TRAP
    c = a1
    if c == 1 || c == 5
      ir.line("br label %trap" + c.to_s)
    else
      ir.line("ret i64 " + c.to_s)
    return 0
  if op == OP_JZ || op == OP_JNZ
    v = ir.ld(a1)
    c = ir.t()
    ir.line(c + " = icmp " + (op == OP_JZ ? "eq" : "ne") + " i64 " + v + ", 0")
    ir.line("br i1 " + c + ", label %L" + a2.to_s + ", label %F" + pc.to_s)
    ir.label("F" + pc.to_s)
    return 1
  if op >= OP_JEQ && op <= OP_JGESI64
    imm = op >= OP_JEQI
    cm = imm ? op - OP_JEQI : op - OP_JEQ
    x = ir.ld(a1)
    y = imm ? a2.to_s : ir.ld(a2)
    if cm >= 6 && cm <= 9
      x = ir.sext32(x)
      y = imm ? w_sext32(a2).to_s : ir.sext32(y)
    c = ir.t()
    ir.line(c + " = icmp " + w_ir_cmp_pred(cm) + " i64 " + x + ", " + y)
    ir.line("br i1 " + c + ", label %L" + a3.to_s + ", label %F" + pc.to_s)
    ir.label("F" + pc.to_s)
    return 1
  if op == OP_BR_TABLE
    v = ir.ld(a1)
    n = a2
    s = "switch i64 " + v + ", label %L" + code[pc + 3 + n].to_s + " \["
    j = 0
    while j < n
      s = s + " i64 " + j.to_s + ", label %L" + code[pc + 3 + j].to_s
      j += 1
    ir.line(s + " ]")
    return 0
  if op == OP_MOV
    ir.st(a1, ir.ld(a2))
    return 1
  if op == OP_CONST
    ir.st(a1, a2.to_s)
    return 1
  if op == OP_SELECT
    c = ir.t()
    ir.line(c + " = icmp ne i64 " + ir.ld(code[pc + 4]) + ", 0")
    x = ir.ld(a2)
    y = ir.ld(a3)
    r = ir.t()
    ir.line(r + " = select i1 " + c + ", i64 " + x + ", i64 " + y)
    ir.st(a1, r)
    return 1
  if op == OP_GGET || op == OP_GSET
    g = ir.t()
    ir.line(g + " = getelementptr i64, ptr %glob, i64 " + ((op == OP_GGET ? a2 : a1) * 2).to_s)
    if op == OP_GGET
      v = ir.t()
      ir.line(v + " = load i64, ptr " + g)
      ir.st(a1, v)
    else
      ir.line("store i64 " + ir.ld(a2) + ", ptr " + g)
    return 1
  if op == OP_MSIZE
    r = ir.t()
    ir.line(r + " = lshr i64 " + ir.msize + ", " + a2.to_s)
    ir.st(a1, r)
    return 1
  if op == OP_CHK64
    c = ir.t()
    ir.line(c + " = icmp slt i64 " + ir.ld(a1) + ", 0")
    ir.line("br i1 " + c + ", label %trap5, label %F" + pc.to_s)
    ir.label("F" + pc.to_s)
    return 1
  if op == OP_CALL_IMPORT
    ft = m.func_type(a1)
    return w_jit_upcall_ir(ir, pc, a2, ft.param_slots, ft.result_slots, false)
  if op == OP_CALL_IND
    ft = W_TYPES.types[a2]
    p = ir.t()
    ir.line(p + " = getelementptr i64, ptr %fp, i64 " + code[pc + 4].to_s)
    ir.line("store i64 " + ir.ld(code[pc + 4]) + ", ptr " + p)
    return w_jit_upcall_ir(ir, pc, a3, ft.param_slots, ft.result_slots, false)
  if op == OP_EXT
    return w_jit_upcall_ir(ir, pc, 0, 0, 0, true)
  if op == OP_CALL && !ir.plan[w_jit_index_of(m, a1)]
    callee = m.fentry[w_jit_index_of(m, a1)]
    return w_jit_upcall_ir(ir, pc, a2, callee.param_slots, callee.result_slots, false)
  if op == OP_RET_CALL && !ir.plan[w_jit_index_of(m, a1)]
    return -1
  if op == OP_CALL || op == OP_RET_CALL
    ci = w_jit_index_of(m, a1)
    return -1 if ci < 0
    callee = m.fentry[ci]
    base = op == OP_CALL ? a2 : a3
    np = callee.param_slots
    j = 0
    while j < np
      p = ir.t()
      ir.line(p + " = getelementptr i64, ptr %fp, i64 " + (base + j).to_s)
      ir.line("store i64 " + ir.ld(base + j) + ", ptr " + p)
      j += 1
    cf = ir.t()
    ir.line(cf + " = getelementptr i64, ptr %fp, i64 " + base.to_s)
    r = ir.t()
    ir.line(r + " = call i64 @wj" + ci.to_s + "(ptr %ctx, ptr " + cf + ")")
    c = ir.t()
    ir.line(c + " = icmp ne i64 " + r + ", 0")
    ir.line("br i1 " + c + ", label %P" + pc.to_s + ", label %K" + pc.to_s)
    ir.label("P" + pc.to_s)
    ir.line("store i64 %depth, ptr %depth.p")
    ir.line("ret i64 " + r)
    ir.label("K" + pc.to_s)
    # results back into slots (for a tail call: into 0.., then return)
    nr = callee.result_slots
    j = 0
    while j < nr
      p = ir.t()
      ir.line(p + " = getelementptr i64, ptr %fp, i64 " + (base + j).to_s)
      v = ir.t()
      ir.line(v + " = load i64, ptr " + p)
      ir.st(op == OP_CALL ? base + j : j, v)
      j += 1
    if op == OP_RET_CALL
      ir.line("br label %ret")
      return 0
    return 1
  if op >= OP_LD32 && op <= OP_LD32S64
    w_jit_load(ir, op, a1, a2, a3, pc)
    return 1
  if op >= OP_ST32 && op <= OP_ST16
    w_jit_store(ir, op, a1, a2, a3, pc)
    return 1
  if op == OP_MFILL || op == OP_MCOPY
    d = ir.ld(a1)
    b = ir.ld(a2)
    n = ir.ld(a3)
    e = ir.t()
    ir.line(e + " = add i64 " + d + ", " + n)
    c = ir.t()
    ir.line(c + " = icmp ugt i64 " + e + ", " + ir.msize)
    ir.line("br i1 " + c + ", label %trap5, label %F" + pc.to_s)
    ir.label("F" + pc.to_s)
    dp = ir.t()
    ir.line(dp + " = getelementptr i8, ptr " + ir.mem + ", i64 " + d)
    if op == OP_MFILL
      bt = ir.t()
      ir.line(bt + " = trunc i64 " + b + " to i8")
      ir.line("call void @llvm.memset.p0.i64(ptr " + dp + ", i8 " + bt + ", i64 " + n + ", i1 false)")
    else
      e2 = ir.t()
      ir.line(e2 + " = add i64 " + b + ", " + n)
      c2 = ir.t()
      ir.line(c2 + " = icmp ugt i64 " + e2 + ", " + ir.msize)
      ir.line("br i1 " + c2 + ", label %trap5, label %G" + pc.to_s)
      ir.label("G" + pc.to_s)
      sp = ir.t()
      ir.line(sp + " = getelementptr i8, ptr " + ir.mem + ", i64 " + b)
      ir.line("call void @llvm.memmove.p0.p0.i64(ptr " + dp + ", ptr " + sp + ", i64 " + n + ", i1 false)")
    return 1
  w_jit_arith(ir, op, a1, a2, a3, pc)

W_TAG_INT = -1688849860263936
W_INT_MASK = 281474976710655

# Call back into the driver for the op at pc (calls the interpreter keeps, imports,
# call_indirect, OP_EXT). Args at base..base+np are flushed to the frame and results
# reloaded; for OP_EXT (all) the whole frame is flushed and reloaded.
-> w_jit_upcall_ir(ir, pc, base, np, nr, all)
  lo = all ? 0 : base
  hi = all ? ir.fsize : base + np
  j = lo
  while j < hi
    p = ir.t()
    ir.line(p + " = getelementptr i64, ptr %fp, i64 " + j.to_s)
    ir.line("store i64 " + ir.ld(j) + ", ptr " + p)
    j += 1
  ccp = ir.t()
  ir.line(ccp + " = getelementptr i64, ptr %ctx, i64 4")
  cci = ir.t()
  ir.line(cci + " = load i64, ptr " + ccp)
  cc = ir.t()
  ir.line(cc + " = inttoptr i64 " + cci + " to ptr")
  clp = ir.t()
  ir.line(clp + " = getelementptr i64, ptr %ctx, i64 5")
  clo = ir.t()
  ir.line(clo + " = load i64, ptr " + clp)
  sbp = ir.t()
  ir.line(sbp + " = getelementptr i64, ptr %ctx, i64 6")
  sb = ir.t()
  ir.line(sb + " = load i64, ptr " + sbp)
  fpi = ir.t()
  ir.line(fpi + " = ptrtoint ptr %fp to i64")
  df = ir.t()
  ir.line(df + " = sub i64 " + fpi + ", " + sb)
  idx = ir.t()
  ir.line(idx + " = lshr i64 " + df + ", 3")
  bfp = ir.t()
  ir.line(bfp + " = or i64 " + idx + ", " + W_TAG_INT.to_s)
  r = ir.t()
  ir.line(r + " = call i64 " + cc + "(i64 " + clo + ", i64 " + (pc | W_TAG_INT).to_s + ", i64 " + bfp + ")")
  v = ir.t()
  ir.line(v + " = and i64 " + r + ", " + W_INT_MASK.to_s)
  c = ir.t()
  ir.line(c + " = icmp ne i64 " + v + ", 0")
  ir.line("br i1 " + c + ", label %P" + pc.to_s + ", label %K" + pc.to_s)
  ir.label("P" + pc.to_s)
  ir.line("store i64 %depth, ptr %depth.p")
  ir.line("ret i64 " + v)
  ir.label("K" + pc.to_s)
  lo = all ? 0 : base
  hi = all ? ir.fsize : base + nr
  j = lo
  while j < hi
    p = ir.t()
    ir.line(p + " = getelementptr i64, ptr %fp, i64 " + j.to_s)
    x = ir.t()
    ir.line(x + " = load i64, ptr " + p)
    ir.st(j, x)
    j += 1
  ir.reload_mem
  1

-> w_jit_check(ir, ea, n, pc)
  e = ir.t()
  ir.line(e + " = add i64 " + ea + ", " + n.to_s)
  c = ir.t()
  ir.line(c + " = icmp ugt i64 " + e + ", " + ir.msize)
  ir.line("br i1 " + c + ", label %trap5, label %M" + pc.to_s)
  ir.label("M" + pc.to_s)
  p = ir.t()
  ir.line(p + " = getelementptr i8, ptr " + ir.mem + ", i64 " + ea)
  p

-> w_jit_load(ir, op, d, a, off, pc)
  ea = ir.t()
  ir.line(ea + " = add i64 " + ir.ld(a) + ", " + off.to_s)
  ty = "i32"
  ext = "zext"
  n = 4
  if op == OP_LD64
    ty = "i64"
    n = 8
  elsif op == OP_LD8S32 || op == OP_LD8S64
    ty = "i8"
    ext = "sext"
    n = 1
  elsif op == OP_LD8U
    ty = "i8"
    n = 1
  elsif op == OP_LD16S32 || op == OP_LD16S64
    ty = "i16"
    ext = "sext"
    n = 2
  elsif op == OP_LD16U
    ty = "i16"
    n = 2
  elsif op == OP_LD32S64
    ext = "sext"
  p = w_jit_check(ir, ea, n, pc)
  v = ir.t()
  ir.line(v + " = load " + ty + ", ptr " + p + ", align 1")
  r = v
  if ty != "i64"
    r = ir.t()
    ir.line(r + " = " + ext + " " + ty + " " + v + " to i64")
    r = ir.mask32(r) if op == OP_LD8S32 || op == OP_LD16S32
  ir.st(d, r)

-> w_jit_store(ir, op, a, v, off, pc)
  ea = ir.t()
  ir.line(ea + " = add i64 " + ir.ld(a) + ", " + off.to_s)
  ty = op == OP_ST32 ? "i32" : (op == OP_ST64 ? "i64" : (op == OP_ST8 ? "i8" : "i16"))
  n = op == OP_ST32 ? 4 : (op == OP_ST64 ? 8 : (op == OP_ST8 ? 1 : 2))
  p = w_jit_check(ir, ea, n, pc)
  x = ir.ld(v)
  if ty != "i64"
    t2 = ir.t()
    ir.line(t2 + " = trunc i64 " + x + " to " + ty)
    x = t2
  ir.line("store " + ty + " " + x + ", ptr " + p + ", align 1")

# Integer, float and conversion ops (d = a1, a = a2, b = a3).
-> w_jit_arith(ir, op, d, a, b, pc)
  r = nil
  if op >= OP_ADDI32 && op <= OP_GESI64
    x = ir.ld(a)
    k = b
    if op == OP_ADDI32 || op == OP_ADDI64 || op == OP_MULI32 || op == OP_MULI64 || op == OP_ANDI || op == OP_ORI || op == OP_XORI || op == OP_SHLI32 || op == OP_SHLI64 || op == OP_SHRUI32 || op == OP_SHRUI64 || op == OP_SHRSI64
      ins = {OP_ADDI32 => "add", OP_ADDI64 => "add", OP_MULI32 => "mul", OP_MULI64 => "mul", OP_ANDI => "and", OP_ORI => "or", OP_XORI => "xor", OP_SHLI32 => "shl", OP_SHLI64 => "shl", OP_SHRUI32 => "lshr", OP_SHRUI64 => "lshr", OP_SHRSI64 => "ashr"}[op]
      r = ir.t()
      ir.line(r + " = " + ins + " i64 " + x + ", " + k.to_s)
      r = ir.mask32(r) if op == OP_ADDI32 || op == OP_MULI32 || op == OP_SHLI32
    elsif op == OP_SHRSI32
      s = ir.sext32(x)
      r = ir.t()
      ir.line(r + " = ashr i64 " + s + ", " + k.to_s)
      r = ir.mask32(r)
    else
      cm = op - OP_EQI
      y = k.to_s
      if cm >= 6 && cm <= 9
        x = ir.sext32(x)
        y = w_sext32(k).to_s
      c = ir.t()
      ir.line(c + " = icmp " + w_ir_cmp_pred(cm) + " i64 " + x + ", " + y)
      r = ir.zext1(c)
    ir.st(d, r)
    return 1
  if op >= OP_EQ && op <= OP_GES64
    x = ir.ld(a)
    y = ir.ld(b)
    cm = op - OP_EQ
    if cm >= 6 && cm <= 9
      x = ir.sext32(x)
      y = ir.sext32(y)
    c = ir.t()
    ir.line(c + " = icmp " + w_ir_cmp_pred(cm) + " i64 " + x + ", " + y)
    ir.st(d, ir.zext1(c))
    return 1
  if op == OP_EQZ
    c = ir.t()
    ir.line(c + " = icmp eq i64 " + ir.ld(a) + ", 0")
    ir.st(d, ir.zext1(c))
    return 1
  simple = {OP_ADD32 => "add", OP_SUB32 => "sub", OP_MUL32 => "mul", OP_ADD64 => "add", OP_SUB64 => "sub", OP_MUL64 => "mul", OP_AND => "and", OP_OR => "or", OP_XOR => "xor"}
  if simple.has_key?(op)
    r = ir.t()
    ir.line(r + " = " + simple[op] + " i64 " + ir.ld(a) + ", " + ir.ld(b))
    r = ir.mask32(r) if op == OP_ADD32 || op == OP_SUB32 || op == OP_MUL32
    ir.st(d, r)
    return 1
  if op == OP_SHL32 || op == OP_SHRU32 || op == OP_SHRS32 || op == OP_SHL64 || op == OP_SHRU64 || op == OP_SHRS64
    w32 = op == OP_SHL32 || op == OP_SHRU32 || op == OP_SHRS32
    x = ir.ld(a)
    x = ir.sext32(x) if op == OP_SHRS32
    n = ir.t()
    ir.line(n + " = and i64 " + ir.ld(b) + ", " + (w32 ? "31" : "63"))
    ins = (op == OP_SHL32 || op == OP_SHL64) ? "shl" : ((op == OP_SHRU32 || op == OP_SHRU64) ? "lshr" : "ashr")
    r = ir.t()
    ir.line(r + " = " + ins + " i64 " + x + ", " + n)
    r = ir.mask32(r) if w32
    ir.st(d, r)
    return 1
  if op == OP_ROTL32 || op == OP_ROTR32
    x = ir.t()
    ir.line(x + " = trunc i64 " + ir.ld(a) + " to i32")
    n = ir.t()
    ir.line(n + " = trunc i64 " + ir.ld(b) + " to i32")
    c = ir.t()
    ir.line(c + " = call i32 @llvm." + (op == OP_ROTL32 ? "fshl" : "fshr") + ".i32(i32 " + x + ", i32 " + x + ", i32 " + n + ")")
    r = ir.t()
    ir.line(r + " = zext i32 " + c + " to i64")
    ir.st(d, r)
    return 1
  if op == OP_ROTL64 || op == OP_ROTR64
    x = ir.ld(a)
    r = ir.t()
    ir.line(r + " = call i64 @llvm." + (op == OP_ROTL64 ? "fshl" : "fshr") + ".i64(i64 " + x + ", i64 " + x + ", i64 " + ir.ld(b) + ")")
    ir.st(d, r)
    return 1
  if op == OP_CLZ32 || op == OP_CTZ32
    x = ir.t()
    ir.line(x + " = trunc i64 " + ir.ld(a) + " to i32")
    c = ir.t()
    ir.line(c + " = call i32 @llvm." + (op == OP_CLZ32 ? "ctlz" : "cttz") + ".i32(i32 " + x + ", i1 false)")
    r = ir.t()
    ir.line(r + " = zext i32 " + c + " to i64")
    ir.st(d, r)
    return 1
  if op == OP_CLZ64 || op == OP_CTZ64 || op == OP_POPCNT
    r = ir.t()
    nm = op == OP_CLZ64 ? "ctlz" : (op == OP_CTZ64 ? "cttz" : "ctpop")
    ir.line(r + " = call i64 @llvm." + nm + ".i64(i64 " + ir.ld(a) + (op == OP_POPCNT ? ")" : ", i1 false)"))
    ir.st(d, r)
    return 1
  if op >= OP_DIVS32 && op <= OP_REMU32 || op >= OP_DIVS64 && op <= OP_REMU64
    w32 = op <= OP_REMU32
    x = ir.ld(a)
    y = ir.ld(b)
    sgn = op == OP_DIVS32 || op == OP_REMS32 || op == OP_DIVS64 || op == OP_REMS64
    if w32 && sgn
      x = ir.sext32(x)
      y = ir.sext32(y)
    z = ir.t()
    ir.line(z + " = icmp eq i64 " + y + ", 0")
    ir.line("br i1 " + z + ", label %trap2, label %D" + pc.to_s)
    ir.label("D" + pc.to_s)
    isdiv = op == OP_DIVS32 || op == OP_DIVU32 || op == OP_DIVS64 || op == OP_DIVU64
    if sgn
      m1 = ir.t()
      ir.line(m1 + " = icmp eq i64 " + y + ", -1")
      mn = w32 ? "-2147483648" : "-9223372036854775808"
      m2 = ir.t()
      ir.line(m2 + " = icmp eq i64 " + x + ", " + mn)
      ov = ir.t()
      ir.line(ov + " = and i1 " + m1 + ", " + m2)
      if isdiv
        ir.line("br i1 " + ov + ", label %trap3, label %E" + pc.to_s)
        ir.label("E" + pc.to_s)
      else
        # rem by -1 is 0: avoid the overflowing srem
        y2 = ir.t()
        ir.line(y2 + " = select i1 " + m1 + ", i64 1, i64 " + y)
        y = y2
    ins = isdiv ? (sgn ? "sdiv" : "udiv") : (sgn ? "srem" : "urem")
    r = ir.t()
    ir.line(r + " = " + ins + " i64 " + x + ", " + y)
    r = ir.mask32(r) if w32
    ir.st(d, r)
    return 1
  if op == OP_WRAP
    ir.st(d, ir.mask32(ir.ld(a)))
    return 1
  if op == OP_EXTS32
    ir.st(d, ir.sext32(ir.ld(a)))
    return 1
  if op >= OP_EXT8S32 && op <= OP_EXT16S64
    ty = (op == OP_EXT8S32 || op == OP_EXT8S64) ? "i8" : "i16"
    x = ir.t()
    ir.line(x + " = trunc i64 " + ir.ld(a) + " to " + ty)
    r = ir.t()
    ir.line(r + " = sext " + ty + " " + x + " to i64")
    r = ir.mask32(r) if op == OP_EXT8S32 || op == OP_EXT16S32
    ir.st(d, r)
    return 1
  # floats
  if op >= OP_FABS32 && op <= OP_FGE32
    return w_jit_float(ir, op - OP_FABS32, d, a, b, false)
  if op >= OP_FABS64 && op <= OP_FGE64
    return w_jit_float(ir, op - OP_FABS64, d, a, b, true)
  if op >= OP_TRUNC_F32_S32 && op <= OP_PROMOTE
    return w_jit_cvt(ir, op, d, a, pc)
  -1

# k: offset within FABS..FGE (abs neg ceil floor trunc nearest sqrt add sub mul div min max copysign eq ne lt gt le ge)
-> w_jit_float(ir, k, d, a, b, wide)
  ft = wide ? "double" : "float"
  sfx = wide ? "f64" : "f32"
  x = wide ? ir.f64(ir.ld(a)) : ir.f32(ir.ld(a))
  if k <= 6
    r = ir.t()
    if k == 0
      ir.line(r + " = call " + ft + " @llvm.fabs." + sfx + "(" + ft + " " + x + ")")
    elsif k == 1
      ir.line(r + " = fneg " + ft + " " + x)
    else
      nm = ["", "", "ceil", "floor", "trunc", "roundeven", "sqrt"][k]
      ir.line(r + " = call " + ft + " @llvm." + nm + "." + sfx + "(" + ft + " " + x + ")")
    r = ir.canon(r, ft, sfx) if k >= 2
    ir.st(d, wide ? ir.from_f64(r) : ir.from_f32(r))
    return 1
  y = wide ? ir.f64(ir.ld(b)) : ir.f32(ir.ld(b))
  r = ir.t()
  if k <= 13
    if k <= 10
      ir.line(r + " = " + ["fadd", "fsub", "fmul", "fdiv"][k - 7] + " " + ft + " " + x + ", " + y)
    elsif k <= 12
      ir.line(r + " = call " + ft + " @llvm." + (k == 11 ? "minimum" : "maximum") + "." + sfx + "(" + ft + " " + x + ", " + ft + " " + y + ")")
    else
      ir.line(r + " = call " + ft + " @llvm.copysign." + sfx + "(" + ft + " " + x + ", " + ft + " " + y + ")")
    r = ir.canon(r, ft, sfx) if k <= 12
    ir.st(d, wide ? ir.from_f64(r) : ir.from_f32(r))
    return 1
  pred = ["oeq", "une", "olt", "ogt", "ole", "oge"][k - 14]
  ir.line(r + " = fcmp " + pred + " " + ft + " " + x + ", " + y)
  ir.st(d, ir.zext1(r))
  1

-> w_jit_cvt(ir, op, d, a, pc)
  x = ir.ld(a)
  if op >= OP_TRUNC_F32_S32 && op <= OP_SAT_F64_U64
    j = op <= OP_TRUNC_F64_U64 ? op - OP_TRUNC_F32_S32 : op - OP_SAT_F32_S32
    src64 = j == 2 || j == 3 || j == 6 || j == 7
    sgn = j % 2 == 0
    bits = j <= 3 ? 32 : 64
    f = src64 ? ir.f64(x) : ir.f32(x)
    ft = src64 ? "double" : "float"
    if op <= OP_TRUNC_F64_U64
      # trap checks on the truncated value, in double precision
      dd = f
      if !src64
        dd = ir.t()
        ir.line(dd + " = fpext float " + f + " to double")
      tr = ir.t()
      ir.line(tr + " = call double @llvm.trunc.f64(double " + dd + ")")
      nan = ir.t()
      ir.line(nan + " = fcmp uno double " + dd + ", " + dd)
      ir.line("br i1 " + nan + ", label %trap4, label %N" + pc.to_s)
      ir.label("N" + pc.to_s)
      lo = sgn ? (bits == 32 ? (src64 ? "-2147483649.0" : "-2147483648.0") : "-9223372036854775808.0") : "-1.0"
      loc = (sgn && !(bits == 32 && src64)) ? "oge" : "ogt"
      hi = sgn ? (bits == 32 ? "2147483648.0" : "9223372036854775808.0") : (bits == 32 ? "4294967296.0" : "18446744073709551616.0")
      c1 = ir.t()
      ir.line(c1 + " = fcmp " + loc + " double " + tr + ", " + lo)
      c2 = ir.t()
      ir.line(c2 + " = fcmp olt double " + tr + ", " + hi)
      c3 = ir.t()
      ir.line(c3 + " = and i1 " + c1 + ", " + c2)
      ir.line("br i1 " + c3 + ", label %O" + pc.to_s + ", label %trap3")
      ir.label("O" + pc.to_s)
    r = ir.t()
    ir.line(r + " = call i" + bits.to_s + " @llvm.fpto" + (sgn ? "s" : "u") + "i.sat.i" + bits.to_s + "." + (src64 ? "f64" : "f32") + "(" + ft + " " + f + ")")
    if bits == 32
      z = ir.t()
      ir.line(z + " = zext i32 " + r + " to i64")
      r = z
    ir.st(d, r)
    return 1
  if op == OP_DEMOTE
    r = ir.t()
    ir.line(r + " = fptrunc double " + ir.f64(x) + " to float")
    r = ir.canon(r, "float", "f32")
    ir.st(d, ir.from_f32(r))
    return 1
  if op == OP_PROMOTE
    r = ir.t()
    ir.line(r + " = fpext float " + ir.f32(x) + " to double")
    r = ir.canon(r, "double", "f64")
    ir.st(d, ir.from_f64(r))
    return 1
  # int → float: CVT_S32_F32 .. CVT_U64_F64 (DEMOTE sits between)
  j = op <= OP_CVT_U64_F32 ? op - OP_CVT_S32_F32 : op - OP_CVT_S32_F64
  wide = op >= OP_CVT_S32_F64
  sgn = j % 2 == 0
  src = x
  it = "i64"
  if j <= 1
    it = "i32"
    src = ir.t()
    ir.line(src + " = trunc i64 " + x + " to i32")
  r = ir.t()
  ir.line(r + " = " + (sgn ? "sitofp" : "uitofp") + " " + it + " " + src + " to " + (wide ? "double" : "float"))
  ir.st(d, wide ? ir.from_f64(r) : ir.from_f32(r))
  1

# ---- driving the compile ----

# Start compiling module m in the background (once).
-> w_jit_start(m)
  return nil if !W_JIT_ON[0] || m.jit != nil || Env["WASM_NOJIT"] != nil
  j = WJit.new
  m.jit = j
  cc = w_jit_cc()
  if cc == nil
    j.failed = true
    return nil
  plan = w_jit_plan(m)
  any = false
  plan.each ->(p) any = true if p
  if !any
    j.failed = true
    return nil
  dir = (Env["TMPDIR"] == nil ? "/tmp/" : Env["TMPDIR"]) + "tungsten-wasm-jit"
  j.thread = Thread.new ->
    w_jit_build(m, j, plan, cc, dir)
  nil

-> w_jit_build(m, j, plan, cc, dir)
  t0 = clock_ms()
  sb = StringBuffer.new
  funcs = []
  k = 0
  while k < plan.size
    if plan[k]
      s = w_jit_func_ir(m, k, plan)
      if s != nil
        sb.append(s)
        funcs.push(k)
    k += 1
  # functions whose IR failed make their callers invalid: rebuild without them is rare; give up
  if funcs.size == 0
    j.failed = true
    j.done = true
    return nil
  OS.system("mkdir -p " + dir)
  base = dir + "/m" + clock_ms().to_s + "_" + funcs.size.to_s
  File.write(base + ".ll", sb.to_s)
  st = OS.system(cc + " -O2 -shared -fPIC -Wno-override-module -o " + base + ".dylib " + base + ".ll 2>" + base + ".err")
  if st != true && st != 0
    j.failed = true
    j.done = true
    return nil
  j.path = base + ".dylib"
  j.funcs = funcs
  j.ms = clock_ms() - t0
  j.done = true
  nil

# If the background compile finished, load it and patch function entries (main thread).
-> w_jit_poll(m)
  j = m.jit
  return nil if j == nil || !j.done || j.ptrs != nil || j.failed
  h = ccall("w_dlopen", j.path)
  if h == nil
    j.failed = true
    return nil
  ptrs = i64[m.fentry.size + 1]
  j.funcs.each ->(k)
    a = ccall("w_dlsym", h, "wj" + k.to_s)
    ptrs[k] = a == nil ? 0 : a
  j.ptrs = ptrs
  j.funcs.each ->(k)
    if ptrs[k] != 0
      e = m.fentry[k].entry
      m.code[e] = OP_JIT
      m.code[e + 1] = k
  nil

# Wait for the background compile (benchmarks, tests).
-> wasm_jit_wait(m)
  j = m.jit
  return false if j == nil
  j.thread.join if j.thread != nil
  w_jit_poll(m)
  j.ptrs != nil

fn wj_call(f, ctx, stk, fp) (i64 i64[] i64[] i64) i64
  ll <<~IR
    %fn = inttoptr i64 %f to ptr
    %cp = inttoptr i64 %ctx to ptr
    %sp = inttoptr i64 %stk to ptr
    %p = getelementptr i64, ptr %sp, i64 %fp
    %r = call i64 %fn(ptr %cp, ptr %p)
    ret i64 %r
  IR

fn wk_addr8(a) (u8[]) i64
  ll <<~IR
    ret i64 %a
  IR

fn wk_addr64(a) (i64[]) i64
  ll <<~IR
    ret i64 %a
  IR

W_JIT_EXC = [nil]

fn wk_cc2addr(x) (i64) i64
  ll <<~IR
    %a = ptrtoint ptr @w_closure_call_2 to i64
    ret i64 %a
  IR

# Keeps w_closure_call_2 declared in the module (it is what upcalls jump to).
-> w_jit_keep_cc2(f)
  ccall("w_closure_call_2", f, 0, 0) if f == 12345

# Set an instance's JIT context words 4..6 (upcall target, closure, stack base).
-> w_jit_ctx_init(inst, ex)
  if inst.jclo == nil
    inst.jclo = ->(pc, fp) w_jit_upcall(inst, pc, fp)
  ctx = inst.jctx
  ctx[4] = wk_cc2addr(0)
  ctx[5] = wvalue_bits(inst.jclo) ## i64
  ctx[6] = wk_addr64(ex.stk)
  nil

# An upcall from compiled code: run the call / OP_EXT at pc for the frame at slot fp.
-> w_jit_upcall(inst, pc, fp)
  ex = wasm_exec()
  m = inst.mod
  code = m.code
  op = code[pc]
  begin
    fsz = w_func_at(m, pc).fsize
    if op == OP_CALL
      f = inst.funcs[m.n_imp_funcs + w_jit_index_of(m, code[pc + 1])]
      w_call_at(ex, f, fp + code[pc + 2], fp + fsz)
    elsif op == OP_CALL_IMPORT
      w_call_at(ex, inst.funcs[code[pc + 1]], fp + code[pc + 2], fp + fsz)
    elsif op == OP_CALL_IND
      f = w_table_func(inst, code[pc + 1], ex.stk[fp + code[pc + 4]], code[pc + 2])
      w_call_at(ex, f, fp + code[pc + 3], fp + fsz)
    else
      saved = ex.top
      ex.top = fp + fsz
      w_ext(ex, inst, pc, fp, ex.csp)
      ex.top = saved
    mem = inst.mems.size > 0 ? inst.mems[0] : nil
    inst.jctx[0] = wk_addr8(mem == nil ? W_NOMEM : mem.data)
    inst.jctx[1] = mem == nil ? 0 : mem.size
    0
  rescue e
    W_JIT_EXC[0] = e
    200
