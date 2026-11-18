# Satori session: runs commands, keeps the environment of theorems, simp
# rules, equation lemmas and induction principles, and reports results.

SATC_TOOLCHAIN_CACHE = {}

SATC_LIB_FILES = [
  "term.w", "printer.w", "checkers.w", "eval.w", "kernel.w", "derived.w",
  "lexer.w", "parser.w", "elab.w", "simp.w", "arith.w", "satbridge.w",
  "polynomial.w", "tactics.w", "pattern.w", "session.w", "satori.w"
]

-> satc_toolchain_sig(root)
  cached = SATC_TOOLCHAIN_CACHE[root]
  if cached != nil
    return cached
  sb = StringBuffer()
  sb.append("satc-v1")
  lib_dir = root + "/bits/tungsten-satori/lib/"
  SATC_LIB_FILES.each -> (fname)
    p = lib_dir + fname
    h = Digest.file64(p)
    sb.append(":")
    if h != nil
      sb.append(h.to_s)
  sig = Digest.sha256(sb.to_s)
  SATC_TOOLCHAIN_CACHE[root] = sig
  sig

-> satc_esc(s)
  if s == nil
    return ""
  n = s.size
  need = false
  i = 0
  while i < n
    b = s.byte_at(i)
    if b == 92 || b == 10 || b == 9 || b == 13
      need = true
      break
    i += 1
  if !need
    return s
  sb = StringBuffer()
  i = 0
  while i < n
    b = s.byte_at(i)
    if b == 92
      sb.append("\\\\")
    elsif b == 10
      sb.append("\\n")
    elsif b == 9
      sb.append("\\t")
    elsif b == 13
      sb.append("\\r")
    else
      sb.append(s.slice(i, 1))
    i += 1
  sb.to_s

-> satc_unesc(s)
  n = s.size
  has_bs = false
  i = 0
  while i < n
    if s.byte_at(i) == 92
      has_bs = true
      break
    i += 1
  if !has_bs
    return s
  sb = StringBuffer()
  i = 0
  while i < n
    b = s.byte_at(i)
    if b == 92 && i + 1 < n
      nb = s.byte_at(i + 1)
      if nb == 110
        sb.append("\n")
      elsif nb == 116
        sb.append("\t")
      elsif nb == 114
        sb.append("\r")
      else
        sb.append("\\")
      i += 2
    else
      sb.append(s.slice(i, 1))
      i += 1
  sb.to_s

-> satc_read_fields(text, s, e, out)
  out.clear
  tok_s = s
  i = s
  while i < e
    if text.byte_at(i) == 9
      out.push(satc_unesc(text.slice(tok_s, i - tok_s)))
      tok_s = i + 1
    i += 1
  out.push(satc_unesc(text.slice(tok_s, e - tok_s)))
  out

-> count_lines_fast(src)
  n = src.size
  if n == 0
    return 0
  bytes = ccall("w_string_bytes_view", src) ## u8[]
  cnt = 1
  i = 0
  while i < n
    if bytes[i] == 10
      cnt += 1
    i += 1
  cnt

# Records verified declarations of a single imported module into a DAG-deduped .satc payload.
+ SatcWriter
  ro :ok, :imp_sig_chain
  rw :thm_count, :def_count, :axiom_count, :line_count

  -> new
    @ok = true
    @imp_sb = StringBuffer()
    @imp_sig_chain = ""
    @ty_sb = StringBuffer()
    @tm_sb = StringBuffer()
    @op_sb = StringBuffer()
    @ty_map = {}
    @ty_next = 0
    @tm_buckets = {}
    @tm_next = 0
    @thm_count = 0
    @def_count = 0
    @axiom_count = 0
    @line_count = 0

  -> abort!
    @ok = false

  -> enc_ty(t)
    existing = @ty_map[t.id]
    if existing != nil
      return existing
    if t.tag == :v
      idx = @ty_next
      @ty_next += 1
      @ty_map[t.id] = idx
      @ty_sb.append("TV\t")
      @ty_sb.append(satc_esc(t.name))
      @ty_sb.append("\n")
      return idx
    na = t.args.size
    a_ids = Array.new(na)
    i = 0
    while i < na
      a_ids[i] = enc_ty(t.args[i])
      i += 1
    idx = @ty_next
    @ty_next += 1
    @ty_map[t.id] = idx
    @ty_sb.append("TC\t")
    @ty_sb.append(satc_esc(t.name))
    @ty_sb.append("\t")
    @ty_sb.append(na.to_s)
    i = 0
    while i < na
      @ty_sb.append("\t")
      @ty_sb.append(a_ids[i].to_s)
      i += 1
    @ty_sb.append("\n")
    idx

  -> enc_tm(t)
    bucket = @tm_buckets[t.h]
    if bucket != nil
      nb = bucket.size
      bi = 0
      while bi < nb
        pr = bucket[bi]
        if tm_eq(pr[0], t)
          return pr[1]
        bi += 1
    else
      bucket = []
      @tm_buckets[t.h] = bucket
    idx = 0
    case t.tag
    when :var
      ti = enc_ty(t.ty)
      idx = @tm_next
      @tm_next += 1
      @tm_sb.append("MV\t")
      @tm_sb.append(satc_esc(t.name))
      @tm_sb.append("\t")
      @tm_sb.append(ti.to_s)
      @tm_sb.append("\n")
    when :const
      ti = enc_ty(t.ty)
      idx = @tm_next
      @tm_next += 1
      @tm_sb.append("MC\t")
      @tm_sb.append(satc_esc(t.name))
      @tm_sb.append("\t")
      @tm_sb.append(ti.to_s)
      @tm_sb.append("\n")
    when :bnd
      ti = enc_ty(t.ty)
      idx = @tm_next
      @tm_next += 1
      @tm_sb.append("MB\t")
      @tm_sb.append(t.idx.to_s)
      @tm_sb.append("\t")
      @tm_sb.append(ti.to_s)
      @tm_sb.append("\n")
    when :lit
      ti = enc_ty(t.ty)
      idx = @tm_next
      @tm_next += 1
      if type(t.val) == "Array"
        @tm_sb.append("MQ\t")
        @tm_sb.append(t.val[0].to_s)
        @tm_sb.append("\t")
        @tm_sb.append(t.val[1].to_s)
        @tm_sb.append("\t")
        @tm_sb.append(ti.to_s)
        @tm_sb.append("\n")
      else
        @tm_sb.append("MI\t")
        @tm_sb.append(t.val.to_s)
        @tm_sb.append("\t")
        @tm_sb.append(ti.to_s)
        @tm_sb.append("\n")
    when :app
      ai = enc_tm(t.a)
      bi = enc_tm(t.b)
      idx = @tm_next
      @tm_next += 1
      @tm_sb.append("MA\t")
      @tm_sb.append(ai.to_s)
      @tm_sb.append("\t")
      @tm_sb.append(bi.to_s)
      @tm_sb.append("\n")
    else
      ti = enc_ty(t.ty)
      bi = enc_tm(t.b)
      idx = @tm_next
      @tm_next += 1
      @tm_sb.append("ML\t")
      @tm_sb.append(satc_esc(t.name))
      @tm_sb.append("\t")
      @tm_sb.append(ti.to_s)
      @tm_sb.append("\t")
      @tm_sb.append(bi.to_s)
      @tm_sb.append("\n")
    bucket.push([t, idx])
    idx

  -> add_import(name, sig)
    if sig == nil || sig == ""
      @ok = false
      return
    @imp_sig_chain = @imp_sig_chain + ";" + name + "=" + sig
    @imp_sb.append("IMP\t")
    @imp_sb.append(satc_esc(name))
    @imp_sb.append("\t")
    @imp_sb.append(sig)
    @imp_sb.append("\n")

  -> add_opaque(name, ty)
    ti = enc_ty(ty)
    @op_sb.append("O_OPAQUE\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\t")
    @op_sb.append(ti.to_s)
    @op_sb.append("\n")

  -> add_inductive(name, params, ctors)
    # Encode all ctor arg types before emitting the op line
    ct_ids = Array.new(ctors.size)
    ci = 0
    while ci < ctors.size
      atys = ctors[ci][1]
      aids = Array.new(atys.size)
      j = 0
      while j < atys.size
        aids[j] = enc_ty(atys[j])
        j += 1
      ct_ids[ci] = aids
      ci += 1
    @op_sb.append("O_IND\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\t")
    @op_sb.append(params.size.to_s)
    params.each -> (p)
      @op_sb.append("\t")
      @op_sb.append(satc_esc(p))
    @op_sb.append("\t")
    @op_sb.append(ctors.size.to_s)
    ci = 0
    while ci < ctors.size
      @op_sb.append("\t")
      @op_sb.append(satc_esc(ctors[ci][0]))
      aids = ct_ids[ci]
      @op_sb.append("\t")
      @op_sb.append(aids.size.to_s)
      j = 0
      while j < aids.size
        @op_sb.append("\t")
        @op_sb.append(aids[j].to_s)
        j += 1
      ci += 1
    @op_sb.append("\n")

  -> add_fields(sname, ctor_name, fields)
    @op_sb.append("O_FIELDS\t")
    @op_sb.append(satc_esc(sname))
    @op_sb.append("\t")
    @op_sb.append(satc_esc(ctor_name))
    @op_sb.append("\t")
    @op_sb.append(fields.size.to_s)
    fields.each -> (f)
      @op_sb.append("\t")
      @op_sb.append(satc_esc(f))
    @op_sb.append("\n")

  -> add_def(name, rhs)
    ri = enc_tm(rhs)
    @op_sb.append("O_DEF\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\t")
    @op_sb.append(ri.to_s)
    @op_sb.append("\n")

  -> add_axiom(name, concl, foundational)
    ci = enc_tm(concl)
    @op_sb.append("O_AXIOM\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\t")
    @op_sb.append(ci.to_s)
    @op_sb.append("\t")
    @op_sb.append(foundational ? "1" : "0")
    @op_sb.append("\n")

  -> append_thm_ref(th)
    ci = enc_tm(th.concl)
    @op_sb.append("\t")
    @op_sb.append(ci.to_s)
    @op_sb.append("\t")
    @op_sb.append(th.tags.size.to_s)
    th.tags.each -> (tg)
      @op_sb.append("\t")
      @op_sb.append(satc_esc(tg))

  -> add_thm(name, th)
    ci = enc_tm(th.concl)
    @op_sb.append("O_THM\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\t")
    @op_sb.append(ci.to_s)
    @op_sb.append("\t")
    @op_sb.append(th.tags.size.to_s)
    th.tags.each -> (tg)
      @op_sb.append("\t")
      @op_sb.append(satc_esc(tg))
    @op_sb.append("\n")

  -> add_eqns(name, eqs)
    ids = Array.new(eqs.size)
    i = 0
    while i < eqs.size
      ids[i] = enc_tm(eqs[i].concl)
      i += 1
    @op_sb.append("O_EQNS\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\t")
    @op_sb.append(eqs.size.to_s)
    i = 0
    while i < eqs.size
      @op_sb.append("\t")
      @op_sb.append(ids[i].to_s)
      tgs = eqs[i].tags
      @op_sb.append("\t")
      @op_sb.append(tgs.size.to_s)
      tgs.each -> (tg)
        @op_sb.append("\t")
        @op_sb.append(satc_esc(tg))
      i += 1
    @op_sb.append("\n")

  -> add_simp(name, th)
    ci = enc_tm(th.concl)
    @op_sb.append("O_SIMP\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\t")
    @op_sb.append(ci.to_s)
    @op_sb.append("\t")
    @op_sb.append(th.tags.size.to_s)
    th.tags.each -> (tg)
      @op_sb.append("\t")
      @op_sb.append(satc_esc(tg))
    @op_sb.append("\n")

  -> add_auto(name)
    @op_sb.append("O_AUTO\t")
    @op_sb.append(satc_esc(name))
    @op_sb.append("\n")

  -> add_say(msg)
    @op_sb.append("O_SAY\t")
    @op_sb.append(satc_esc(msg))
    @op_sb.append("\n")

  -> serialize(mod_sig)
    out = StringBuffer()
    out.append("SATC1\t")
    out.append(mod_sig)
    out.append("\t")
    out.append(@ty_next.to_s)
    out.append("\t")
    out.append(@tm_next.to_s)
    out.append("\n")
    out.append(@imp_sb.to_s)
    out.append(@ty_sb.to_s)
    out.append(@tm_sb.to_s)
    out.append(@op_sb.to_s)
    out.append("O_STATS\t")
    out.append(@thm_count.to_s)
    out.append("\t")
    out.append(@def_count.to_s)
    out.append("\t")
    out.append(@axiom_count.to_s)
    out.append("\t")
    out.append(@line_count.to_s)
    out.append("\nEND\n")
    out.to_s


+ Session
  ro :k, :d, :elab, :theorems, :simp_rules, :simp_by_head, :simp_general, :messages, :stats, :root, :failures, :auto_rules, :auto_rule_version
  rw :prelude_mode, :quiet, :only, :no_cache, :keep_messages

  -> new(@root)
    @k = KKernel.new
    kernel_bootstrap(@k)
    @d = Derived.new(@k)
    @elab = Elab.new(@k)
    @theorems = {}
    @auto_rules = {}
    @auto_rule_version = 0
    @order = []
    @simp_rules = []
    @simp_by_head = {}
    @simp_general = []
    @eqns = {}
    @induction = {}
    @loaded = {}
    @mod_sigs = {}
    @rec = nil
    @messages = []
    @keep_messages = false
    @prelude_mode = false
    @quiet = false
    @no_cache = Env.get("SATORI_NO_CACHE") == "1"
    @stats = {"theorems" => 0, "defs" => 0, "axioms" => 0, "lines" => 0}
    @failures = 0
    @current_dir = "."
    @only = nil
    @thm_index = 0

  -> solver_path
    @root + "/bits/tungsten-wassat/bin/wassat"

  -> cache_dir
    @root + "/bits/tungsten-satori/.satori-cache"

  -> prelude_dir
    @root + "/bits/tungsten-satori/prelude"

  -> say(s)
    if @keep_messages
      @messages.push(s)
    if !@quiet
      << s
      if @rec != nil
        @rec.add_say(s)

  -> add_simp_rule(r)
    @simp_rules.push(r)
    hn = r.head_name
    if hn != nil
      arr = @simp_by_head[hn]
      if arr == nil
        arr = []
        @simp_by_head[hn] = arr
      arr.push(r)
    else
      @simp_general.push(r)

  -> add_simp_thm(name, th)
    add_simp_rule(make_rule(@d, th, name))
    if @rec != nil
      @rec.add_simp(name, th)

  -> define_const(name, rhs)
    th = @k.define(name, rhs)
    if @rec != nil
      @rec.add_def(name, rhs)
    th

  -> set_eqns(name, eqs)
    @eqns[name] = eqs
    if @rec != nil
      @rec.add_eqns(name, eqs)

  -> theorem(name)
    t = @theorems[name]
    if t != nil
      return t
    t = @k.axioms[name]
    if t != nil
      return t
    @k.defs[name]

  -> add_theorem(name, th)
    @theorems[name] = th
    @order.push(name)
    if @rec != nil
      @rec.add_thm(name, th)

  -> check_auto_rule(th)
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0
      raise "auto registration requires a closed proved theorem"
    th.tags.each -> (tag)
      if !["oracle:arith", "oracle:ring", "oracle:sat"].include?(tag) && !(@only != nil && tag.starts_with?("split:"))
        raise "auto registration excludes " + tag + "; use an explicit auto hint instead"

  -> register_auto_rule(name, th)
    check_auto_rule(th)
    @auto_rules[name] = th
    @auto_rule_version += 1
    if @rec != nil
      @rec.add_auto(name)

  # Monomorphic lemma lookup: "name.int", "name.nat", ... or polymorphic "name".
  -> lemma_at(base, ty)
    nm = base + "." + ty.name
    t = @theorems[nm]
    if t != nil
      return t
    @theorems[base]

  -> induction_thm(ty)
    if ty.tag != :c
      return nil
    t = @induction[ty.name]
    if t != nil
      return t
    if ty == TY_NAT_SINGLETON
      return @k.axiom("nat_induct")
    @k.axioms[ty.name + "_induct"]

  -> eqns_of(name)
    eqs = @eqns[name]
    if eqs != nil
      return eqs
    []

  # ---- files & .satc module caching ---------------------------------------------------

  -> load_prelude
    old = @prelude_mode
    @prelude_mode = true
    run_import("prelude")
    @prelude_mode = old

  -> run_file(path)
    src = File.read(path)
    old_dir = @current_dir
    @current_dir = path_dirname(path)
    run_source(src)
    @current_dir = old_dir

  -> run_import(name)
    if @loaded.has_key?(name)
      return
    @loaded[name] = true
    pdir = prelude_dir
    c1 = pdir + "/" + name.gsub(".", "/") + ".sat"
    found = nil
    if File.exist?(c1)
      found = c1
    else
      c2 = @current_dir + "/" + name + ".sat"
      if File.exist?(c2)
        found = c2
    if found == nil
      raise "import: cannot find " + name
    inprel = found.starts_with?(pdir)
    old_prel = @prelude_mode
    old_quiet = @quiet
    if inprel
      @prelude_mode = true
      @quiet = true
    src = File.read(found)
    can_cache = !@no_cache && (@only == nil || @prelude_mode)
    if can_cache
      src_sig = Digest.sha256(src)
      mode_tag = (@prelude_mode ? "P" : "U") + (@quiet ? "Q" : "V")
      ckey = Digest.sha256(satc_toolchain_sig(@root) + ":" + mode_tag + ":" + found + ":" + src_sig)
      satc_path = cache_dir + "/mod-" + ckey + ".satc"
      if File.exist?(satc_path)
        old_dir = @current_dir
        @current_dir = path_dirname(found)
        loaded_ok = false
        begin
          loaded_ok = satc_try_load(name, satc_path)
        rescue _e
          loaded_ok = false
        @current_dir = old_dir
        if loaded_ok
          @prelude_mode = old_prel
          @quiet = old_quiet
          return
      prev_rec = @rec
      prev_fail = @failures
      rec = SatcWriter.new
      rec.line_count = count_lines_fast(src)
      @rec = rec
      old_dir = @current_dir
      @current_dir = path_dirname(found)
      begin
        run_source(src)
      ensure
        @current_dir = old_dir
        @rec = prev_rec
      if rec.ok && @failures == prev_fail
        msig = Digest.sha256(src_sig + ":" + rec.imp_sig_chain)
        @mod_sigs[name] = msig
        begin
          cdir = cache_dir
          if !File.exist?(cdir)
            File.mkdir_p(cdir)
          File.atomic_write(satc_path, rec.serialize(msig))
        rescue _e
          0
      @prelude_mode = old_prel
      @quiet = old_quiet
      return
    old_dir = @current_dir
    @current_dir = path_dirname(found)
    begin
      run_source(src)
    ensure
      @current_dir = old_dir
      @prelude_mode = old_prel
      @quiet = old_quiet

  -> satc_try_load(mod_name, satc_path)
    text = File.read(satc_path)
    n = text.size
    if n < 12 || !text.starts_with?("SATC1\t") || !text.ends_with?("\nEND\n")
      return false
    flds = []
    pos = 0
    # Parse header: SATC1 \t mod_sig \t n_tys \t n_tms
    hend = 0
    while hend < n && text.byte_at(hend) != 10
      hend += 1
    satc_read_fields(text, 0, hend, flds)
    if flds.size < 4
      return false
    mod_sig = flds[1]
    tys = Array.new(flds[2].to_i)
    tms = Array.new(flds[3].to_i)
    ty_i = 0
    tm_i = 0
    pos = hend + 1
    saved_rec = @rec
    @rec = nil
    begin
      while pos < n
        lend = pos
        while lend < n && text.byte_at(lend) != 10
          lend += 1
        if lend > pos
          satc_read_fields(text, pos, lend, flds)
          tag = flds[0]
          if tag == "IMP"
            imp_nm = flds[1]
            exp_sig = flds[2]
            run_import(imp_nm)
            if @mod_sigs[imp_nm] != exp_sig
              @rec = saved_rec
              return false
          elsif tag == "TV"
            tys[ty_i] = ty_var(flds[1])
            ty_i += 1
          elsif tag == "TC"
            na = flds[2].to_i
            if na == 0
              tys[ty_i] = ty_con(flds[1], [])
            elsif na == 2 && flds[1] == "fun"
              tys[ty_i] = ty_fun(tys[flds[3].to_i], tys[flds[4].to_i])
            else
              targs = Array.new(na)
              j = 0
              while j < na
                targs[j] = tys[flds[3 + j].to_i]
                j += 1
              tys[ty_i] = ty_con(flds[1], targs)
            ty_i += 1
          elsif tag == "MA"
            tms[tm_i] = mk_app_raw(tms[flds[1].to_i], tms[flds[2].to_i])
            tm_i += 1
          elsif tag == "MC"
            tms[tm_i] = mk_const_raw(flds[1], tys[flds[2].to_i])
            tm_i += 1
          elsif tag == "MV"
            tms[tm_i] = mk_var(flds[1], tys[flds[2].to_i])
            tm_i += 1
          elsif tag == "MB"
            tms[tm_i] = mk_bnd(flds[1].to_i, tys[flds[2].to_i])
            tm_i += 1
          elsif tag == "ML"
            tms[tm_i] = mk_lam_raw(flds[1], tys[flds[2].to_i], tms[flds[3].to_i])
            tm_i += 1
          elsif tag == "MI"
            tms[tm_i] = mk_lit(flds[1].to_i, tys[flds[2].to_i])
            tm_i += 1
          elsif tag == "MQ"
            tms[tm_i] = mk_lit([flds[1].to_i, flds[2].to_i], tys[flds[3].to_i])
            tm_i += 1
          elsif tag == "O_THM"
            nm = flds[1]
            concl = tms[flds[2].to_i]
            ntg = flds[3].to_i
            tgs = Array.new(ntg)
            j = 0
            while j < ntg
              tgs[j] = flds[4 + j]
              j += 1
            th = @k.restore_thm(concl, tgs)
            @theorems[nm] = th
            @order.push(nm)
          elsif tag == "O_AXIOM"
            nm = flds[1]
            concl = tms[flds[2].to_i]
            fnd = flds[3] == "1"
            th = @k.new_axiom(nm, concl, fnd)
            @theorems[nm] = th
            @order.push(nm)
          elsif tag == "O_DEF"
            @k.restore_define(flds[1], tms[flds[2].to_i])
          elsif tag == "O_EQNS"
            nm = flds[1]
            neq = flds[2].to_i
            eqs = Array.new(neq)
            cursor = 3
            j = 0
            while j < neq
              concl = tms[flds[cursor].to_i]
              ntg = flds[cursor + 1].to_i
              tgs = Array.new(ntg)
              tk = 0
              while tk < ntg
                tgs[tk] = flds[cursor + 2 + tk]
                tk += 1
              eqs[j] = @k.restore_thm(concl, tgs)
              cursor = cursor + 2 + ntg
              j += 1
            @eqns[nm] = eqs
          elsif tag == "O_AUTO"
            nm = flds[1]
            register_auto_rule(nm, @theorems[nm])
          elsif tag == "O_SIMP"
            nm = flds[1]
            concl = tms[flds[2].to_i]
            ntg = flds[3].to_i
            tgs = Array.new(ntg)
            j = 0
            while j < ntg
              tgs[j] = flds[4 + j]
              j += 1
            th = @k.restore_thm(concl, tgs)
            add_simp_rule(make_rule(@d, th, nm))
          elsif tag == "O_OPAQUE"
            @k.declare_const(flds[1], tys[flds[2].to_i])
          elsif tag == "O_IND"
            nm = flds[1]
            np = flds[2].to_i
            params = Array.new(np)
            j = 0
            while j < np
              params[j] = flds[3 + j]
              j += 1
            cursor = 3 + np
            nct = flds[cursor].to_i
            cursor += 1
            ctors = Array.new(nct)
            ci = 0
            while ci < nct
              cnm = flds[cursor]
              na = flds[cursor + 1].to_i
              atys = Array.new(na)
              aj = 0
              while aj < na
                atys[aj] = tys[flds[cursor + 2 + aj].to_i]
                aj += 1
              ctors[ci] = [cnm, atys]
              cursor = cursor + 2 + na
              ci += 1
            @k.inductive(nm, params, ctors)
          elsif tag == "O_FIELDS"
            snm = flds[1]
            cnm = flds[2]
            nf = flds[3].to_i
            flist = Array.new(nf)
            j = 0
            while j < nf
              flist[j] = flds[4 + j]
              j += 1
            @elab.register_fields(snm, cnm, flist)
          elsif tag == "O_SAY"
            say(flds[1])
          elsif tag == "O_STATS"
            @stats["theorems"] = @stats["theorems"] + flds[1].to_i
            @stats["defs"] = @stats["defs"] + flds[2].to_i
            @stats["axioms"] = @stats["axioms"] + flds[3].to_i
            @stats["lines"] = @stats["lines"] + flds[4].to_i
          elsif tag == "END"
            break
        pos = lend + 1
    ensure
      @rec = saved_rec
    @mod_sigs[mod_name] = mod_sig
    true

  -> run_source(src)
    cmds = parse_program(src)
    @stats["lines"] = @stats["lines"] + count_lines_fast(src)
    nc = cmds.size
    ci = 0
    while ci < nc
      c = cmds[ci]
      cmds[ci] = nil
      @elab.reset_counter
      target = false
      if @only != nil && !@prelude_mode
        if c.kind == :theorem || (c.kind == :attr && c.body != nil && c.body.kind == :theorem)
          # Count declarations before elaboration, which itself may fail.
          @thm_index += 1
          target = @thm_index == @only
      if target
        << "⟦" + @only.to_s + "⟧"
      begin
        exec(c)
      rescue e
        @failures += 1
        if @rec != nil
          @rec.abort!
        << ("✗ line " + c.line.to_s + " (" + c.kind.to_s + " " + c.name.to_s + "): " + e.to_s)
      if target
        << "⟦/" + @only.to_s + "⟧"
      c.tactics = nil
      c.body = nil
      c.ty = nil
      ci += 1

  # ---- commands ------------------------------------------------------------------------

  -> exec(c)
    if c.text == "auto" && c.kind != :theorem
      raise "auto registration requires a proved theorem declaration"
    case c.kind
    when :import
      if @rec != nil
        cur_rec = @rec
        @rec = nil
        begin
          run_import(c.name)
        ensure
          @rec = cur_rec
        cur_rec.add_import(c.name, @mod_sigs[c.name])
      else
        run_import(c.name)
    when :inductive
      exec_inductive(c)
    when :structure
      exec_structure(c)
    when :def
      exec_def(c)
    when :axiom
      exec_axiom(c)
    when :opaque
      @elab.reset
      ty = @elab.elab_type(c.ty)
      @k.declare_const(c.name, ty)
      if @rec != nil
        @rec.add_opaque(c.name, ty)
      if !@quiet || @keep_messages
        say("✓ opaque " + c.name + " : " + ty_show(ty))
    when :theorem
      exec_theorem(c)
    when :hash
      if @rec != nil
        @rec.abort!
      exec_hash(c)
    when :attr
      exec(c.body)
    when :parse_error
      if @rec != nil
        @rec.abort!
      raise c.text
    else
      raise "unknown command"

  -> exec_inductive(c)
    @elab.reset
    params = c.params
    @elab.set_pending(c.name, params)
    ctors = []
    c.ctors.each -> (ct)
      args = []
      ct[1].each -> (a)
        args.push(@elab.elab_type(a[1]))
      ctors.push([ct[0], args])
    @elab.set_pending(nil, [])
    @k.inductive(c.name, params, ctors)
    if @rec != nil
      @rec.add_inductive(c.name, params, ctors)
      @rec.def_count = @rec.def_count + 1
    @stats["defs"] = @stats["defs"] + 1
    prefix = c.name + "_distinct_"
    @k.axioms.each -> (nm, axth)
      if nm.starts_with?(prefix)
        add_simp_thm(nm, axth)
    if !@quiet || @keep_messages
      say("✓ inductive " + c.name)

  -> exec_structure(c)
    exec_inductive(c)
    ct = c.ctors[0]
    fields = []
    ct[1].each -> (f)
      fields.push(f[0])
    info = @k.inductives[c.name]
    self_ty = ty_con(c.name, c.params.map ->(p) ty_var(p))
    arg_tys = info.ctors[0][1]
    i = 0
    while i < fields.size
      vs = []
      j = 0
      while j < arg_tys.size
        vs.push(mk_var("f" + j.to_s, arg_tys[j]))
        j += 1
      case_f = mk_lams(vs, vs[i])
      rt = arg_tys[i]
      rec = mk_const_raw(info.rec_name, ty_funs([type_of(case_f), self_ty], rt))
      pv = mk_var("p", self_ty)
      body = mk_lam(pv, mk_apps(rec, [case_f, pv]))
      pname = c.name + "." + fields[i]
      define_const(pname, body)
      xs = []
      j = 0
      while j < arg_tys.size
        xs.push(mk_var(fields[j], arg_tys[j]))
        j += 1
      lhs = mk_app(mk_const_raw(pname, ty_fun(self_ty, rt)), mk_apps(mk_const_raw(ct[0], ty_funs(arg_tys, self_ty)), xs))
      eq = eq_by_compute(lhs, xs[i])
      th = @d.gen_all(xs, eq)
      add_theorem(pname + ".mk", th)
      add_simp_thm(pname, th)
      i += 1
    @elab.register_fields(c.name, ct[0], fields)
    if @rec != nil
      @rec.add_fields(c.name, ct[0], fields)

  # ⊢ lhs = rhs when both sides evaluate to the same normal form.
  -> eq_by_compute(lhs, rhs)
    a = @k.compute(lhs, true)
    b = @k.compute(rhs, true)
    va = dest_binop(a.concl, "=")[1]
    vb = dest_binop(b.concl, "=")[1]
    if !tm_eq(va, vb)
      raise "equation does not hold by computation: " + tm_show(va) + " vs " + tm_show(vb)
    @k.trans(a, @k.sym(b))

  -> exec_def(c)
    if c.eqns.size > 0
      return exec_pattern_def(c)
    lam = c.body
    if c.binders.size > 0
      lam = ast(:lam, "", [c.body])
      lam.binders = c.binders
    @elab.reset
    @elab.type_params_from(c)
    t = @elab.elab(lam)
    if c.ty != nil
      rt = @elab.elab_type(c.ty)
      ft = rt
      i = c.binders.size - 1
      while i >= 0
        b = c.binders[i]
        bt = b.ty != nil ? @elab.elab_type(b.ty) : @elab.fresh_meta
        ft = ty_fun(bt, ft)
        i -= 1
      @elab.unify(@elab.tyof(t), ft)
    body = @elab.finalize(t, true)
    @elab.check(body)
    th = define_const(c.name, body)
    vars = []
    cur = body
    nm_avoid = [body]
    while cur.tag == :lam
      p = dest_lam_fresh(cur, nm_avoid)
      vars.push(p[0])
      nm_avoid.push(p[0])
      cur = p[1]
    if vars.size > 0
      eq = @d.ap_thm_all(th, vars)
      eq = @k.trans(eq, @d.beta_norm_conv(dest_binop(eq.concl, "=")[1]))
      eqg = @d.gen_all(vars, eq)
      set_eqns(c.name, [eqg])
      add_theorem(c.name + ".def", eqg)
    else
      set_eqns(c.name, [th])
    @stats["defs"] = @stats["defs"] + 1
    if @rec != nil
      @rec.def_count = @rec.def_count + 1
    if !@quiet || @keep_messages
      say("✓ def " + c.name + " : " + ty_show(type_of(body)))

  -> exec_pattern_def(c)
    pd = PatternDef.new(self, c)
    pd.compile
    @stats["defs"] = @stats["defs"] + 1
    if @rec != nil
      @rec.def_count = @rec.def_count + 1
    if !@quiet || @keep_messages
      say("✓ def " + c.name + " : " + ty_show(@k.const_type(c.name)))

  -> exec_axiom(c)
    r = @elab.elab_prop(c.ty, c.binders, true)
    th = @k.new_axiom(c.name, r[0], @prelude_mode)
    @theorems[c.name] = th
    @order.push(c.name)
    if @rec != nil
      @rec.add_axiom(c.name, r[0], @prelude_mode)
      @rec.axiom_count = @rec.axiom_count + 1
    if c.text == "simp"
      add_simp_thm(c.name, th)
    @stats["axioms"] = @stats["axioms"] + 1
    if !@prelude_mode && (!@quiet || @keep_messages)
      say("⚠ axiom " + c.name + " : " + tm_show(r[0]))

  -> exec_theorem(c)
    r = @elab.elab_prop(c.ty, c.binders, true)
    stmt = r[0]
    names = r[1]
    th = nil
    if @only != nil && !@prelude_mode
      if @thm_index != @only
        th = @k.admit_split(stmt, @thm_index.to_s)
        add_theorem(c.name, th)
        if c.text == "simp"
          add_simp_thm(c.name, th)
        if c.text == "auto"
          register_auto_rule(c.name, th)
        @stats["theorems"] = @stats["theorems"] + 1
        say("⋯ split " + @thm_index.to_s + " " + c.name)
        return
    if c.tactics != nil
      th = prove_with_tactics(stmt, names, c.tactics)
    elsif c.body != nil
      th = nil
      err = nil
      if c.body.kind != :lam && names.size > 0
        begin
          p0 = Prover.new(self)
          root = GoalRef.new(Goal.new([], [], stmt), nil, 0)
          p0.goals = [root]
          cur = root
          names.each -> (nm)
            cur = p0.intro1(cur, nm)
          p0.close(cur, p0.fit(cur, p0.proof_ast(cur.goal, c.body, cur.goal.concl)))
          th = root.thm
        rescue e
          err = e
          th = nil
      if th == nil
        begin
          p = Prover.new(self)
          g = Goal.new([], [], stmt)
          th = p.fit(GoalRef.new(g, nil, 0), p.proof_ast(g, c.body, stmt))
        rescue e2
          if err != nil
            raise err
          raise e2
    else
      raise "theorem without proof"
    if th.hyps.size > 0
      raise "proof leaves assumptions: " + tm_show(th.hyps[0])
    if !tm_eq(th.concl, stmt)
      raise "proved statement differs from the claim"
    if c.text == "auto"
      check_auto_rule(th)
    add_theorem(c.name, th)
    if c.text == "simp"
      add_simp_thm(c.name, th)
    if c.text == "auto"
      register_auto_rule(c.name, th)
    @stats["theorems"] = @stats["theorems"] + 1
    if @rec != nil
      @rec.thm_count = @rec.thm_count + 1
    if !@quiet || @keep_messages
      trust = ""
      if th.tags.size > 0
        trust = "   \[" + th.tags.join(", ") + "\]"
      say("✓ " + c.name + " : " + tm_show(stmt) + trust)

  -> prove_with_tactics(stmt, names, tactics)
    p = Prover.new(self)
    root = GoalRef.new(Goal.new([], [], stmt), nil, 0)
    p.goals = [root]
    cur = root
    names.each -> (nm)
      cur = p.intro1(cur, nm)
    p.run_block(tactics)
    if p.goals.size > 0
      raise "unsolved goals:\n" + p.goals[0].goal.show(@k)
    root.thm

  -> exec_hash(c)
    case c.name
    when "check"
      t = @elab.elab_term(parse_expr_toks(c.body))
      say(tm_show(t) + " : " + ty_show(type_of(t)))
    when "eval"
      t = @elab.elab_term(parse_expr_toks(c.body))
      th = @k.compute(t)
      say(tm_show(dest_binop(th.concl, "=")[1]))
    when "print"
      nm = c.body[0].text
      th = theorem(nm)
      if th == nil
        say(nm + " : " + ty_show(@k.const_type(nm)))
      else
        say(nm + " : " + tm_show(th.concl))
    when "axioms"
      nm = c.body[0].text
      th = theorem(nm)
      if th == nil
        raise "unknown theorem '" + nm + "'"
      if @only == 0 && !@prelude_mode
        # Preserve the tags visible at this point, including split declaration IDs.
        say("⋯ axioms " + nm + "   \[" + th.tags.join(", ") + "\]")
      elsif th.tags.size == 0
        say(nm + " depends only on the foundational kernel")
      else
        say(nm + " depends on: " + th.tags.join(", "))
    when "stats"
      say(stats_line)
    else
      raise "unknown command #" + c.name

  -> stats_line
    @stats["theorems"].to_s + " theorems, " + @stats["defs"].to_s + " definitions, " + @stats["axioms"].to_s + " axioms"

# Derived helper used by definitions.
+ Derived
  -> ap_thm_all(th, xs)
    t = th
    xs.each -> (x)
      t = ap_thm(t, x)
    t

+ Elab
  -> set_pending(name, params)
    @pending = name
    @pending_params = params

  -> type_params_from(c)
    @type_params = []

-> path_dirname(path)
  i = path.size - 1
  while i >= 0 && path.byte_at(i) != 47
    i -= 1
  if i < 0
    return "."
  if i == 0
    return "/"
  path.slice(0, i)
