# translate/unit — unit mode (PLAN.md 1.4, milestone 5): the translated functions of a
# script compiled as a unit that a running host loads (runtime/units.w).
#
# A unit defines no classes and has no runtime of its own. While a script is translated
# in unit mode a JtUnit is installed as JT_UNIT[0] (translate/build.w), and everything the
# translated code takes from the host goes through the unit's context (unit/prelude.w):
#
#   - runtime calls become jsu_cN(ctx, k, …): a call of the host's closure for entry k,
#     named "js_add/2" and so on in the manifest;
#   - host values are slots: global and lexical cells, JS:Code descriptors, literal
#     shapes, template objects, JS_HOLE and the other constants, the inline-cache table;
#   - strings longer than five bytes are slots too (a string literal is an index into
#     the program's own string slab, which means nothing in the host);
#   - every jsd_N and jsf_N takes ctx first.
#
# Inline caches: the four runtime entries that take a site's word index into the
# program's JS_IC (js_getp, js_setp, js_call_method, js_new) are called as their _t
# forms with the unit's own table. jsu_init(ctx) answers a closure over ctx per entry.

JSU_ABI = 1

use ../runtime/unit_id

# Position of the inline-cache word index in each runtime entry that takes one.
JSU_IC_ARG = {"js_getp" => 2, "js_setp" => 3, "js_call_method" => 2, "js_new" => 1}

# Entries every context has at these indices: the slow paths of the prelude's fast forms.
JSU_FIXED = ["js_add/2", "js_sub/2", "js_mul/2", "js_lt/2", "js_gt/2", "js_le/2", "js_ge/2", "js_seq/2", "js_truthy/1", "js_getp_t/4", "js_setp_t/5", "js_call/8", "js_gget/1"]

# Runtime calls that go through the prelude's fast form jsu_<name> (inline lanes for
# numbers, booleans, cached properties, plain globals, and calls of compiled functions,
# which go straight to their entries).
JSU_FAST = {"js_add" => 2, "js_sub" => 2, "js_mul" => 2, "js_lt" => 2, "js_gt" => 2, "js_le" => 2, "js_ge" => 2, "js_seq" => 2, "js_truthy" => 1, "js_call" => 8, "js_gget" => 1}

# Names translated code reads as host values.
JSU_CONSTS = {"JSR" => true, "JS_HOLE" => true, "JS_NULL" => true, "JS_NO_ARGS" => true, "JS_ITER_DONE" => true}

+ JtUnit
  rw :t, :rt, :rt_list, :slots, :slot_list, :ic_slot, :entries

  -> new(@t)
    @rt = {}
    @rt_list = []
    @slots = {}
    @slot_list = []
    @entries = []
    @ic_slot = slot("ic", "", 0)
    slot("epoch", "", nil)
    JSU_FIXED.each ->(k) rt_index(k.slice(0, k.index("/")), k.slice(k.index("/") + 1, k.size - k.index("/") - 1).to_i)

  # The slot for a host value (kind: str, gcell, lcell, code, shape, tmpl, const, ic).
  -> slot(kind, key, data)
    k = kind + ":" + key
    i = @slots[k]
    if i == nil
      i = @slot_list.size
      @slots[k] = i
      @slot_list.push([kind, key, data])
    i

  -> slot_value(i)
    Tungsten:AST:Call.new(nil, "wvalue_from_bits", [Tungsten:AST:Call.new(nil, "jsu_k", [Tungsten:AST:Var.new("ctx"), ta_int(i)])])

  -> rt_index(name, n)
    k = name + "/" + n.to_s
    i = @rt[k]
    if i == nil
      i = @rt_list.size
      ccall("w_eputs", "jsc: more than 512 runtime entries") if i >= 512
      @rt[k] = i
      @rt_list.push(k)
    i

  # A runtime call through the context.
  -> rt_call(name, args)
    n = args.size
    Tungsten:AST:Call.new(nil, "jsu_c" + n.to_s, [Tungsten:AST:Var.new("ctx"), ta_int(rt_index(name, n))] + args)

  -> call(name, args)
    if name.starts_with?("jsd_") || name.starts_with?("jsf_")
      return Tungsten:AST:Call.new(nil, name, [Tungsten:AST:Var.new("ctx")] + args)
    if JSU_FAST[name] == args.size
      return Tungsten:AST:Call.new(nil, "jsu_" + name.slice(3, name.size - 3), [Tungsten:AST:Var.new("ctx")] + args)
    if (name == "js_getp" && args.size == 3) || (name == "js_setp" && args.size == 4)
      # fast forms with the unit's cache table: jsu_getp(ctx, o, key, table, k) / jsu_setp
      xs = [Tungsten:AST:Var.new("ctx")] + args.slice(0, args.size - 1) + [slot_value(@ic_slot), args[args.size - 1]]
      return Tungsten:AST:Call.new(nil, name == "js_getp" ? "jsu_getp" : "jsu_setp", xs)
    p = JSU_IC_ARG[name]
    if p != nil
      # the _t form takes (… table, k …) where the call had (… k …)
      xs = []
      i = 0
      while i < args.size
        xs.push(slot_value(@ic_slot)) if i == p
        xs.push(args[i])
        i += 1
      return rt_call(name + "_t", xs)
    rt_call(name, args)

  -> var(name)
    return slot_value(slot("const", name, nil)) if JSU_CONSTS[name] == true
    if name.starts_with?("JSG_")
      nm = @t.glist[name.slice(4, name.size - 4).to_i]
      return slot_value(slot("gcell", nm, nil))
    if name.starts_with?("JSL_")
      nm = @t.llist[name.slice(4, name.size - 4).to_i]
      return slot_value(slot("lcell", nm, nil))
    if name.starts_with?("JSC_")
      return slot_value(slot("code", name.slice(4, name.size - 4), nil))
    if name.starts_with?("JSS_")
      j = name.slice(4, name.size - 4).to_i
      return slot_value(slot("shape", j.to_s, @t.lit_shapes[j]))
    if name.starts_with?("JSTO_")
      j = name.slice(5, name.size - 5).to_i
      return slot_value(slot("tmpl", j.to_s, @t.templates[j]))
    nil

  -> str(s)
    slot_value(slot("str", s, s))

  # A runtime class's new (a unit knows no host class).
  -> new_obj(cls, args)
    return rt_call("js_env_new", args) if cls == "JS:Env"
    return rt_call("js_envn_new", args) if cls == "JS:EnvN"
    return rt_call("js_private_name_new", args) if cls == "JS:PrivateName"
    ccall("w_eputs", "jsc: unit: no runtime constructor for " + cls)
    rt_call("js_tier0_only", [ta_int(-1)])

  # Other sends are core methods on unit values (Arrays) and compile to code in the unit.
  -> send(recv, name, args)
    nil

  # The unit's jsu_init(ctx): an Array of [index, closure, …], one closure per entry,
  # over ctx. The host calls a closure's code directly with its captures (runtime/units.w):
  # entry(captures, f, this, argc, a0, a1, a2, a3, more), so no symbol of the unit is ever
  # looked up but jsu_init (identical functions may share one body: content-hash dedup).
  -> init_defs
    ps = ["f", "this", "argc", "a0", "a1", "a2", "a3", "more"]
    els = []
    i = 0
    while i < @entries.size
      n = @entries[i]
      # (the script's entry is its jsd_0: it has no function object)
      en = (n == 0 ? "jsd_" : "jsf_") + n.to_s
      els.push(ta_int(n))
      els.push(Tungsten:AST:Block.new(ps, [Tungsten:AST:Call.new(nil, en, [Tungsten:AST:Var.new("ctx")] + ps.map(->(p) Tungsten:AST:Var.new(p)))]))
      i += 1
    [Tungsten:AST:MethodDef.new("jsu_init", [Tungsten:AST:Param.new("ctx")], [Tungsten:AST:Array.new(els)])]

  # The manifest (JSON) runtime/units.w reads to fill the context.
  -> manifest(ic_words, nfuncs)
    out = ["{\"abi\": " + JSU_ABI.to_s + ", \"engine\": \"" + JSU_ENGINE_ID + "\", \"funcs\": " + nfuncs.to_s + ", \"ic\": " + ic_words.to_s + ",\n\"rt\": \["]
    i = 0
    while i < @rt_list.size
      out.push((i > 0 ? "," : "") + jsu_json_str(@rt_list[i]))
      i += 1
    out.push("],\n\"entries\": \[" + @entries.map(->(e) e.to_s).join(",") + "],\n\"slots\": \[")
    i = 0
    while i < @slot_list.size
      s = @slot_list[i]
      kind = s[0]
      d = "null"
      if kind == "shape"
        d = "\[" + s[2].map(->(k) jsu_json_str(k)).join(",") + "]"
      elsif kind == "tmpl"
        cooked = s[2].list.map(->(q) q.str == nil ? "null" : jsu_json_str(q.str))
        raw = s[2].list.map(->(q) jsu_json_str(q.a))
        d = "\[\[" + cooked.join(",") + "], \[" + raw.join(",") + "]]"
      elsif kind == "ic"
        d = ic_words.to_s
      out.push((i > 0 ? ",\n" : "\n") + "\[" + jsu_json_str(kind) + ", " + jsu_json_str(s[1]) + ", " + d + "]")
      i += 1
    out.push("]}\n")
    out.join("")

-> jsu_json_str(s)
  o = "\""
  i = 0
  n = s.size
  while i < n
    c = s.byte_at(i)
    if c == 34
      o = o + "\\\""
    elsif c == 92
      o = o + "\\\\"
    elsif c == 10
      o = o + "\\n"
    elsif c == 13
      o = o + "\\r"
    elsif c == 9
      o = o + "\\t"
    elsif c < 32
      h = "0123456789abcdef"
      o = o + "\\u00" + h.slice(c >> 4, 1) + h.slice(c & 15, 1)
    else
      # (whole UTF-8 sequences copy through byte by byte)
      o = o + s.slice(i, 1) if c < 128
      if c >= 128
        j = i + 1
        while j < n && (s.byte_at(j) & 192) == 128
          j += 1
        o = o + s.slice(i, j - i)
        i = j - 1
    i += 1
  o + "\""

# Strings a unit may write as literals: five bytes or fewer, ASCII (immediate values).
-> jsu_inline_str?(s)
  return false if s.size > 5
  i = 0
  while i < s.size
    return false if s.byte_at(i) >= 128
    i += 1
  true
