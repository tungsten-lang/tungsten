# The spec testsuite runner: executes .wast scripts (assert_return, assert_trap,
# assert_invalid, assert_malformed, assert_unlinkable, assert_exhaustion, assert_exception, ...)
#
#   bin/tungsten -o /tmp/wast --release tools/wast.w && /tmp/wast [-v] file.wast...
#
# Prints one line per file: passed/total and failures by kind.

use ../wasm

WAST_JIT = [Env["WASM_JIT_WAIT"] != nil]
W_JIT_ON[0] = WAST_JIT[0]

+ WastRunner
  rw :pass, :fail, :skip, :fails, :verbose

  -> new(@verbose)
    @pass = 0
    @fail = 0
    @skip = 0
    @fails = {}
    @modules = {}
    @registry = {}
    @current = nil
    @defs = {}
    @spectest = nil
    @file = ""

  -> note_fail(kind, msg)
    @fail += 1
    @fails[kind] = (@fails.has_key?(kind) ? @fails[kind] : 0) + 1
    << "  FAIL " + kind + ": " + msg if @verbose

  -> ok
    @pass += 1

  -> spectest
    return @spectest if @spectest != nil
    h = {}
    void = wt_func_type([], [])
    h["print"] = wasm_host_func(void, ->(args) nil)
    h["print_i32"] = wasm_host_func(wt_func_type([T_I32], []), ->(args) nil)
    h["print_i64"] = wasm_host_func(wt_func_type([T_I64], []), ->(args) nil)
    h["print_f32"] = wasm_host_func(wt_func_type([T_F32], []), ->(args) nil)
    h["print_f64"] = wasm_host_func(wt_func_type([T_F64], []), ->(args) nil)
    h["print_i32_f32"] = wasm_host_func(wt_func_type([T_I32, T_F32], []), ->(args) nil)
    h["print_f64_f64"] = wasm_host_func(wt_func_type([T_F64, T_F64], []), ->(args) nil)
    g = WGlobal.new(T_I32, false)
    g.set(666)
    h["global_i32"] = g
    g = WGlobal.new(T_I64, false)
    g.set(666)
    h["global_i64"] = g
    g = WGlobal.new(T_F32, false)
    g.set(wat_f32("666.6"))
    h["global_f32"] = g
    g = WGlobal.new(T_F64, false)
    g.set(wat_f64("666.6"))
    h["global_f64"] = g
    h["table"] = WTable.new(FUNCREF, 10, 20, false, nil)
    h["table64"] = WTable.new(FUNCREF, 10, 20, true, nil)
    h["memory"] = WMemory.new(1, 2, false, false, 16)
    h["shared_memory"] = WMemory.new(1, 1, true, false, 16)
    @spectest = h
    h

  -> resolver
    reg = @registry
    st = spectest()
    ->(mod, name)
      if mod == "spectest"
        st[name]
      elsif reg.has_key?(mod)
        reg[mod].export(name)
      else
        nil

  # Build a module's bytes from a (module ...) node: [bytes, id]
  -> module_bytes(n)
    c = WatCur.new(n.items, 1)
    if c.peek_atom == "definition"
      c.next_node()
    id = c.take_id()
    if c.peek_atom == "binary"
      c.next_node()
      bs = []
      while c.more?
        bs = bs + c.next_node().bytes
      b = ByteArray.new(bs.size)
      i = 0
      while i < bs.size
        b[i] = bs[i]
        i += 1
      return [b, id]
    if c.peek_atom == "quote"
      c.next_node()
      sb = StringBuffer.new
      while c.more?
        sb.append(w_bytes_to_s(c.next_node().bytes))
        sb.append(" ")
      src = sb.to_s
      return [wat_to_wasm(src), id]
    m = WatNode.new(0, nil, 0)
    m.items = [n.items[0]]
    while c.more?
      m.items.push(c.next_node())
    [WatEncoder.new(m).encode, id]

  -> load_module(n)
    if n.items.size > 3 && n.items[1].atom? && n.items[1].text == "instance"
      m = @defs[n.items[3].text]
      raise "unknown module definition" if m == nil
      inst = wasm_instantiate(m, resolver())
      @current = inst
      @modules[n.items[2].text] = inst
      return inst
    r = module_bytes(n)
    m = wasm_decode(r[0])
    wasm_validate(m)
    if n.items.size > 1 && n.items[1].atom? && n.items[1].text == "definition"
      @defs[r[1]] = m if r[1] != nil
      return nil
    inst = wasm_instantiate(m, resolver())
    wasm_jit_wait(m) if WAST_JIT[0]
    @current = inst
    @modules[r[1]] = inst if r[1] != nil
    inst

  -> instance_of(id)
    return @current if id == nil
    raise "unknown module " + id if !@modules.has_key?(id)
    @modules[id]

  # ---- values ----

  -> parse_value(n)
    h = n.head
    c = WatCur.new(n.items, 1)
    if h == "i32.const"
      return wat_i32(c.next_node().text) & 0xffffffff
    if h == "i64.const"
      return wat_i64(c.next_node().text)
    if h == "f32.const"
      return wat_f32(c.next_node().text)
    if h == "f64.const"
      return wat_f64(c.next_node().text)
    if h == "v128.const"
      shape = c.peek_atom
      bytes = WatEncoder.new(n).v128_const(c)
      lo = 0
      hi = 0
      k = 0
      while k < 8
        lo = (lo | (bytes[k] << (8 * k))) ## i64
        hi = (hi | (bytes[k + 8] << (8 * k))) ## i64
        k += 1
      return WV128.new(lo, hi)
    if h == "ref.null"
      return nil
    if h == "ref.extern" || h == "ref.host"
      return WExtern.new(c.next_node().text.to_i)
    raise "unknown value " + n.to_s

  -> do_action(n)
    h = n.head
    c = WatCur.new(n.items, 1)
    id = c.take_id()
    name = w_bytes_to_s(c.next_node().bytes)
    inst = instance_of(id)
    if h == "invoke"
      f = inst.export(name)
      raise "unknown export " + name if f == nil || !f.is_a?(WFunc)
      args = []
      while c.more?
        args.push(parse_value(c.next_node()))
      return wasm_call(f, args)
    if h == "get"
      g = inst.export(name)
      raise "unknown global " + name if g == nil
      return [g.get]
    raise "unknown action " + h.to_s

  # Does raw value v match expected node e (with NaN patterns)?
  -> match?(v, e)
    h = e.head
    if h == "either"
      k = 1
      while k < e.items.size
        return true if match?(v, e.items[k])
        k += 1
      return false
    c = WatCur.new(e.items, 1)
    if h == "i32.const"
      return v == (wat_i32(c.next_node().text) & 0xffffffff)
    if h == "i64.const"
      return v == wat_i64(c.next_node().text)
    if h == "f32.const"
      return float_match?(v, c.next_node().text, false)
    if h == "f64.const"
      return float_match?(v, c.next_node().text, true)
    if h == "v128.const"
      return v128_match?(v, c)
    if h == "ref.null"
      return v == nil
    if h == "ref.extern" || h == "ref.host"
      return v != nil if !c.more?
      return false if !v.is_a?(WExtern)
      return v.v == c.next_node().text.to_i
    if h == "ref.func"
      return v.is_a?(WFunc)
    if h == "ref.struct"
      return v.is_a?(WStruct)
    if h == "ref.array"
      return v.is_a?(WArray)
    if h == "ref.i31"
      return v.is_a?(Integer)
    if h == "ref.eq"
      return v.is_a?(Integer) || v.is_a?(WStruct) || v.is_a?(WArray)
    if h == "ref.any"
      return v != nil && !v.is_a?(WFunc)
    if h == "ref.exn"
      return v.is_a?(WExn)
    if h == "ref.i31_shared" || h == "ref.array_shared"
      return v != nil
    raise "unknown result " + e.to_s

  -> float_match?(v, t, wide)
    return false if !v.is_a?(Integer)
    mb = wide ? 52 : 23
    eb = wide ? 11 : 8
    expall = ((1 << eb) - 1) << mb
    quiet = 1 << (mb - 1)
    mag = wide ? (v & 0x7fffffffffffffff) : (v & 0x7fffffff)
    if t == "nan:canonical"
      return mag == (expall | quiet)
    if t == "nan:arithmetic"
      return (mag & expall) == expall && (mag & quiet) != 0
    bits = wide ? wat_f64(t) : wat_f32(t)
    bits = bits & 0xffffffff if !wide
    v == bits

  -> v128_match?(v, c)
    return false if !v.is_a?(WV128)
    shape = c.next_node().text
    lanes = 0
    width = 0
    if shape == "i8x16"
      lanes = 16
      width = 8
    elsif shape == "i16x8"
      lanes = 8
      width = 16
    elsif shape == "i32x4" || shape == "f32x4"
      lanes = 4
      width = 32
    else
      lanes = 2
      width = 64
    k = 0
    while k < lanes
      t = c.next_node().text
      bitpos = k * width
      word = bitpos < 64 ? v.lo : v.hi
      sh = bitpos % 64
      lane = width == 64 ? word : ((word >> sh) & ((1 << width) - 1))
      if shape == "f32x4"
        return false if !float_match?(lane, t, false)
      elsif shape == "f64x2"
        return false if !float_match?(lane, t, true)
      else
        want = wat_int(t)
        want = want & ((1 << width) - 1) if width < 64
        want = (want ## i64) if width == 64
        return false if lane != want
      k += 1
    true

  # ---- commands ----

  -> run_file(path)
    @file = path
    src = File.read(path)
    nodes = nil
    begin
      nodes = wat_parse(src)
    rescue e
      << "  parse error: " + e.to_s
      @fail += 1
      return nil
    nodes.each ->(n)
      begin
        command(n)
      rescue e
        note_fail("crash", n.head.to_s + " " + e.to_s + " @" + w_line_of(src, n.pos).to_s)
    nil

  -> expect_module_failure(n, kind)
    m = n.items[1]
    msg = n.items.size > 2 && n.items[2].str? ? w_bytes_to_s(n.items[2].bytes) : ""
    begin
      r = module_bytes(m)
      mod = wasm_decode(r[0])
      wasm_validate(mod)
      if kind == "unlinkable" || kind == "uninstantiable" || kind == "trap"
        wasm_instantiate(mod, resolver())
    rescue e
      if kind == "malformed" && e.is_a?(WasmMalformed)
        return ok()
      if kind == "invalid" && e.is_a?(WasmInvalid)
        return ok()
      if kind == "malformed" && e.is_a?(WasmInvalid) && m.items.size > 1 && m.items[1].atom? && m.items[1].text == "quote"
        return ok()
      if kind == "unlinkable" && e.is_a?(WasmLinkError)
        return ok()
      if (kind == "uninstantiable" || kind == "trap") && (e.is_a?(WasmTrap) || e.is_a?(WasmException))
        return ok()
      return note_fail(kind, "wrong error " + e.to_s + " (expected " + msg + ") @" + w_line_of(File.read(@file), n.pos).to_s)
    note_fail(kind, "no error (expected " + msg + ") @" + w_line_of(File.read(@file), n.pos).to_s)

  -> command(n)
    h = n.head
    if h == "module"
      load_module(n)
    elsif h == "register"
      name = w_bytes_to_s(n.items[1].bytes)
      inst = instance_of(n.items.size > 2 ? n.items[2].text : nil)
      @registry[name] = inst
    elsif h == "invoke" || h == "get"
      do_action(n)
    elsif h == "assert_return"
      a = n.items[1]
      res = nil
      begin
        res = do_action(a)
      rescue e
        return note_fail("return", a.to_s.slice(0, 80) + " raised " + e.to_s)
      exp = n.items.slice(2, n.items.size - 2)
      if res.size != exp.size
        return note_fail("return", "arity " + a.to_s.slice(0, 80))
      k = 0
      while k < exp.size
        if !match?(res[k], exp[k])
          return note_fail("return", a.to_s.slice(0, 100) + " got " + w_show(res[k]) + " want " + exp[k].to_s)
        k += 1
      ok()
    elsif h == "assert_trap" || h == "assert_exhaustion"
      a = n.items[1]
      if a.head == "module"
        return expect_module_failure(n, "trap")
      begin
        do_action(a)
      rescue e
        if h == "assert_trap" && e.is_a?(WasmTrap)
          return ok()
        if h == "assert_exhaustion" && e.is_a?(WasmExhaustion)
          return ok()
        return note_fail(h, a.to_s.slice(0, 80) + " wrong error " + e.to_s)
      note_fail(h, a.to_s.slice(0, 80) + " did not trap")
    elsif h == "assert_exception"
      begin
        do_action(n.items[1])
      rescue e
        return ok() if e.is_a?(WasmException)
        return note_fail(h, "wrong error " + e.to_s)
      note_fail(h, "no exception")
    elsif h == "assert_malformed"
      expect_module_failure(n, "malformed")
    elsif h == "assert_invalid"
      expect_module_failure(n, "invalid")
    elsif h == "assert_unlinkable"
      expect_module_failure(n, "unlinkable")
    elsif h == "assert_uninstantiable"
      expect_module_failure(n, "uninstantiable")
    else
      @skip += 1
    nil

-> w_show(v)
  return "null" if v == nil
  return "v128(" + v.lo.to_s + "," + v.hi.to_s + ")" if v.is_a?(WV128)
  return "extern(" + v.v.to_s + ")" if v.is_a?(WExtern)
  return "func" if v.is_a?(WFunc)
  v.to_s

-> w_line_of(src, pos)
  line = 1
  i = 0
  b = src.bytes
  while i < pos && i < b.size
    line += 1 if b[i] == 10
    i += 1
  line

verbose = false
files = []
ARGV.each ->(a)
  if a == "-v"
    verbose = true
  else
    files.push(a)
tp = 0
tf = 0
files.each ->(f)
  r = WastRunner.new(verbose)
  << f if verbose
  begin
    r.run_file(f)
  rescue e
    << "  runner crash: " + e.to_s
  tp += r.pass
  tf += r.fail
  fs = r.fails.keys.map(->(k) k + "=" + r.fails[k].to_s).join(" ")
  << File.basename(f) + ": " + r.pass.to_s + "/" + (r.pass + r.fail).to_s + (fs.size > 0 ? "  (" + fs + ")" : "")
<< "TOTAL " + tp.to_s + "/" + (tp + tf).to_s
