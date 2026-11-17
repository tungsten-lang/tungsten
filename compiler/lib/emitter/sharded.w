# Balanced multi-shard LLVM IR emission for parallel native `.ll -> .o` codegen.
#
# Standard single-module `emit_artifact` remains unchanged (preserving
# `stage 1 .ll == stage 2 .ll` and `--ll` output). When `link_binary` compiles
# a large non-LTO native program (`-O0`..`-O3`), `emit_sharded_ir_modules`
# partitions the already-rendered functions in contiguous source order across K
# independent LLVM IR modules using `hidden` symbol visibility so `clang -c`
# optimizes all K shards in parallel and caches each shard `.o` by content.

-> shard_decl_param_types(f)
  parts = []
  if f[:extra_params] != nil
    i = 0
    while i < f[:extra_params].size()
      parts.push(f[:extra_params][i][:type])
      i += 1
  if f[:params] != nil
    i = 0
    while i < f[:params].size()
      parts.push("i64")
      i += 1
  parts.join(", ")

-> shard_embedded_ll_alwaysinline?(f)
  if f[:embedded_ll] == nil
    return false
  if env("TUNGSTEN_EMBEDDED_LL_INLINE") == "0"
    return false
  f[:embedded_ll].index("; tungsten:alwaysinline") != nil && f[:embedded_ll].index("; tungsten:noinline") == nil

-> shard_rewrite_define_linkage(text, replacement)
  if text.starts_with?("define internal ")
    return replacement + text.slice(16, text.size() - 16)
  idx = text.index("\ndefine internal ")
  if idx != nil
    return text.slice(0, idx + 1) + replacement + text.slice(idx + 17, text.size() - idx - 17)
  text

-> shard_replace_first(text, needle, replacement)
  idx = text.index(needle)
  if idx == nil
    return text
  nlen = needle.size()
  text.slice(0, idx) + replacement + text.slice(idx + nlen, text.size() - idx - nlen)

-> shard_rewrite_shared_decls(decls_out)
  out = shard_replace_first(decls_out, "define i64 @__w_bigint_sqr4_locked_exact(", "define linkonce_odr hidden i64 @__w_bigint_sqr4_locked_exact(")
  shard_replace_first(out, "define i64 @__w_bigint_sqr5_locked_exact(", "define linkonce_odr hidden i64 @__w_bigint_sqr5_locked_exact(")

-> shard_extract_seams_decls(seams_str)
  if seams_str == nil || seams_str == ""
    return ""
  out = StringBuffer(512)
  lines = seams_str.split("\n")
  li = 0
  while li < lines.size()
    ln = lines[li]
    if ln.starts_with?("define ")
      lp = ln.index("(")
      rp = lp != nil ? ln.index(")", lp) : nil
      if lp != nil && rp != nil
        prefix = ln.slice(7, lp - 7)
        raw_params = ln.slice(lp + 1, rp - lp - 1).strip()
        ptypes = []
        if raw_params != ""
          raw_parts = raw_params.split(",")
          pi = 0
          while pi < raw_parts.size()
            tok = raw_parts[pi].strip()
            sp = tok.index(" ")
            if sp != nil
              ptypes.push(tok.slice(0, sp))
            elsif tok != ""
              ptypes.push(tok)
            pi += 1
        out << "declare "
        out << prefix
        out << "("
        out << ptypes.join(", ")
        out << ") nounwind\n"
    li += 1
  out.to_s()

-> shard_split_globals(globals_str)
  shard0 = StringBuffer(globals_str.size() + 64)
  others = StringBuffer(globals_str.size() + 64)
  lbr = "\["
  rbr = "]"
  lines = globals_str.split("\n")
  li = 0
  while li < lines.size()
    ln = lines[li]
    if ln == ""
      shard0 << "\n"
      others << "\n"
    elsif ln.index(" = internal constant ") != nil
      shard0 << ln
      shard0 << "\n"
      others << ln
      others << "\n"
    elsif ln.starts_with?("@.ic = internal thread_local global ")
      shard0 << shard_replace_first(ln, " = internal thread_local global ", " = hidden thread_local global ")
      shard0 << "\n"
      others << "@.ic = external hidden thread_local global "
      others << lbr
      others << "0 x "
      others << lbr
      others << "24 x i8"
      others << rbr
      others << rbr
      others << ", align 8\n"
    elsif ln.index(" = internal thread_local global i64 0, align 8") != nil
      eq = ln.index(" = internal thread_local global ")
      lhs = ln.slice(0, eq)
      shard0 << lhs
      shard0 << " = hidden thread_local global i64 0, align 8\n"
      others << lhs
      others << " = external hidden thread_local global i64, align 8\n"
    elsif ln.index(" = internal global ") != nil
      eq = ln.index(" = internal global ")
      lhs = ln.slice(0, eq)
      rest = ln.slice(eq + 19, ln.size() - eq - 19)
      sp = rest.index(" ")
      ty = sp != nil ? rest.slice(0, sp) : rest
      align_sfx = rest.ends_with?(", align 8") ? ", align 8" : ""
      shard0 << lhs
      shard0 << " = hidden global "
      shard0 << rest
      shard0 << "\n"
      others << lhs
      others << " = external hidden global "
      others << ty
      others << align_sfx
      others << "\n"
    elsif ln.index(" = private constant ") != nil
      eq = ln.index(" = private constant ")
      lhs = ln.slice(0, eq)
      rest = ln.slice(eq + 20, ln.size() - eq - 20)
      rb = rest.index("]")
      ty = rb != nil ? rest.slice(0, rb + 1) : rest
      shard0 << lhs
      shard0 << " = hidden constant "
      shard0 << rest
      shard0 << "\n"
      others << lhs
      others << " = external hidden constant "
      others << ty
      others << ", align 16\n"
    else
      shard0 << ln
      shard0 << "\n"
      others << ln
      others << "\n"
    li += 1
  {shard0: shard0.to_s(), others: others.to_s()}

-> shard_split_strings_out(strings_str)
  if strings_str == nil || strings_str == ""
    return {ptr_strings: "", shard0_slab: "", others_slab: ""}
  marker = strings_str.index("\n; Static string slab: ")
  if marker == nil
    return {ptr_strings: strings_str + "\n", shard0_slab: "", others_slab: ""}
  ptr_part = marker > 0 ? strings_str.slice(0, marker) + "\n\n" : ""
  slab_part = strings_str.slice(marker + 1, strings_str.size() - marker - 1)
  shard0_slab = shard_replace_first(slab_part, "\n@__static_slab = private constant ", "\n@__static_slab = hidden constant ") + "\n"
  lbr = "\["
  rbr = "]"
  others_slab = "@__static_slab = external hidden constant " + lbr + "0 x i8" + rbr + ", align 8\n\n"
  {ptr_strings: ptr_part, shard0_slab: shard0_slab, others_slab: others_slab}

-> shard_first_at_name(line)
  at = line.index("@")
  if at == nil
    return nil
  n = line.size()
  k = at + 1
  if k >= n
    return nil
  if line.byte_at(k) == 34
    qend = line.index("\"", k + 1)
    if qend == nil
      return nil
    return line.slice(k + 1, qend - k - 1)
  e = k
  while e < n
    b = line.byte_at(e)
    if b <= 32 || b == 40 || b == 41 || b == 44 || b == 59 || b == 91 || b == 93 || b == 123 || b == 125 || b == 34
      break
    e += 1
  e > k ? line.slice(k, e - k) : nil

-> shard_collect_at_refs(text, out_set)
  if text == nil || text == ""
    return out_set
  n = text.size()
  cur = 0
  while cur < n
    pos = text.index("@", cur)
    if pos == nil
      break
    k = pos + 1
    if k >= n
      break
    if text.byte_at(k) == 34
      qend = text.index("\"", k + 1)
      if qend == nil
        cur = k + 1
      else
        if qend > k + 1
          out_set[text.slice(k + 1, qend - k - 1)] = true
        cur = qend + 1
    else
      e = k
      while e < n
        b = text.byte_at(e)
        if b <= 32 || b == 40 || b == 41 || b == 44 || b == 59 || b == 91 || b == 93 || b == 123 || b == 125 || b == 34
          break
        e += 1
      if e > k
        out_set[text.slice(k, e - k)] = true
      cur = e
  out_set

-> shard_merge_ref_sets(dst, src)
  if src == nil
    return dst
  keys = src.keys()
  i = 0
  while i < keys.size()
    dst[keys[i]] = true
    i += 1
  dst

-> shard_parse_named_lines(block_str)
  items = []
  if block_str == nil || block_str == ""
    return items
  lines = block_str.split("\n")
  li = 0
  while li < lines.size()
    ln = lines[li]
    if ln != "" && !ln.starts_with?(";")
      nm = shard_first_at_name(ln)
      if nm != nil
        items.push({name: nm, line: ln + "\n"})
    li += 1
  items

-> shard_parse_shared_decls(decls_str)
  items = []
  if decls_str == nil || decls_str == ""
    return items
  lines = decls_str.split("\n")
  n = lines.size()
  li = 0
  while li < n
    ln = lines[li]
    if ln == "" || ln.starts_with?(";")
      li += 1
    elsif ln.starts_with?("define ")
      nm = shard_first_at_name(ln)
      buf = StringBuffer(512)
      buf << ln
      buf << "\n"
      li += 1
      while li < n
        bln = lines[li]
        buf << bln
        buf << "\n"
        li += 1
        if bln == "}"
          break
      btxt = buf.to_s()
      brefs = {}
      shard_collect_at_refs(btxt, brefs)
      if nm != nil
        brefs[nm] = nil
      items.push({kind: :def, name: nm, text: btxt, refs: brefs})
    else
      nm = shard_first_at_name(ln)
      # Intrinsic declarations preceding a private helper (e.g. @llvm.ctpop) are
      # ordinary single-line declarations and are kept when referenced by a kept helper.
      items.push({kind: :decl, name: nm, text: ln + "\n", refs: nil})
      li += 1
  items

-> shard_canonical_source_key(path)
  if path == nil || path == ""
    return "<unknown>"
  s1 = path.rindex("/")
  if s1 == nil
    return path
  if s1 == 0
    return path
  s2 = path.rindex("/", s1 - 1)
  if s2 == nil
    return path
  path.slice(s2 + 1, path.size() - s2 - 1)

-> shard_hex4_value(hex)
  v = 0
  i = 0
  while i < 4 && i < hex.size()
    b = hex.byte_at(i)
    d = 0
    if b >= 48 && b <= 57
      d = b - 48
    elsif b >= 97 && b <= 102
      d = b - 87
    elsif b >= 65 && b <= 70
      d = b - 55
    v = (v << 4) + d
    i += 1
  v

-> emit_sharded_ir_modules(shard_plan, requested_shards = 0)
  if shard_plan == nil || requested_shards < 2
    return nil
  fns = shard_plan[:functions]
  texts = shard_plan[:rendered_fn_texts]
  nfns = fns.size()
  if nfns < 192 || texts == nil || texts.size() != nfns
    return nil

  total_fn_bytes = 0
  i = 0
  while i < nfns
    f = fns[i]
    if f[:embedded_asm] == nil && !shard_embedded_ll_alwaysinline?(f)
      total_fn_bytes = total_fn_bytes + texts[i].size()
    i += 1
  if total_fn_bytes < 262144
    return nil

  nshards = requested_shards
  if total_fn_bytes < 1048576 && nshards > 4
    nshards = 4
  if nshards > 16
    nshards = 16
  if nshards < 2
    return nil

  seams_str = shard_plan[:seams_str]
  fn_meta_out = shard_plan[:fn_meta_out]
  call_site_out = shard_plan[:call_site_out]
  llvm_used_out = shard_plan[:llvm_used_out]
  worker_shards = nshards - 1

  owner_shard = Array.new(nfns)
  fn_decl_lines = Array.new(nfns)
  alwaysinline_entries = []
  file_running_bytes = {}
  bucket_memo = {}
  shard_fn_bytes = Array.new(nshards, 0)
  i = 0
  while i < nfns
    f = fns[i]
    txt = texts[i]
    if f[:embedded_asm] != nil
      owner_shard[i] = 0
      shard_fn_bytes[0] = shard_fn_bytes[0] + txt.size()
      fn_decl_lines[i] = "declare " + f[:return_type] + " @" + f[:name] + "(" + shard_decl_param_types(f) + ") nounwind\n"
    elsif shard_embedded_ll_alwaysinline?(f)
      owner_shard[i] = -1
      fn_decl_lines[i] = nil
      rewritten_ai = shard_rewrite_define_linkage(txt, "define linkonce_odr hidden ") + "\n"
      ai_refs = {}
      shard_collect_at_refs(rewritten_ai, ai_refs)
      ai_refs[f[:name]] = nil
      alwaysinline_entries.push({name: f[:name], text: rewritten_ai, refs: ai_refs})
    elsif f[:name] == "main" || f[:is_toplevel] == true
      owner_shard[i] = 0
      shard_fn_bytes[0] = shard_fn_bytes[0] + txt.size()
      if f[:name] == "main"
        fn_decl_lines[i] = nil
      else
        cc0 = (f[:call_conv] != nil && f[:call_conv] != "") ? (f[:call_conv] + " ") : ""
        vis0 = f[:llvm_internal] == true ? "hidden " : ""
        fn_decl_lines[i] = "declare " + vis0 + cc0 + f[:return_type] + " @" + f[:name] + "(" + shard_decl_param_types(f) + ") nounwind\n"
    else
      sp_key = shard_canonical_source_key(f[:source_path])
      prev_b = file_running_bytes[sp_key]
      if prev_b == nil
        prev_b = 0
      file_running_bytes[sp_key] = prev_b + txt.size()
      chunk_idx = prev_b / 196608
      bkey = chunk_idx == 0 ? sp_key : (sp_key + "#" + chunk_idx.to_s())
      assigned = bucket_memo[bkey]
      if assigned == nil
        assigned = 1 + (shard_hex4_value(wyhash64_hex_string(bkey)) % worker_shards)
        bucket_memo[bkey] = assigned
      owner_shard[i] = assigned
      shard_fn_bytes[assigned] = shard_fn_bytes[assigned] + txt.size()
      cc = ""
      if f[:call_conv] != nil && f[:call_conv] != ""
        cc = f[:call_conv] + " "
      if f[:llvm_internal] == true
        fn_decl_lines[i] = "declare hidden " + cc + f[:return_type] + " @" + f[:name] + "(" + shard_decl_param_types(f) + ") nounwind\n"
      else
        fn_decl_lines[i] = "declare " + cc + f[:return_type] + " @" + f[:name] + "(" + shard_decl_param_types(f) + ") nounwind\n"
    i += 1

  nonempty_workers = 0
  s = 1
  while s < nshards
    if shard_fn_bytes[s] > 0
      nonempty_workers += 1
    s += 1
  if nonempty_workers == 0
    return nil

  header = shard_plan[:header]
  seams_decl_items = shard_parse_named_lines(shard_extract_seams_decls(seams_str))
  shared_decl_items = shard_parse_shared_decls(shard_rewrite_shared_decls(shard_plan[:decls_out]))
  globals_pair = shard_split_globals(shard_plan[:globals_str])
  other_global_items = shard_parse_named_lines(globals_pair[:others])
  strings_parts = shard_split_strings_out(shard_plan[:strings_str])
  ptr_string_items = shard_parse_named_lines(strings_parts[:ptr_strings])
  shard0_slab = strings_parts[:shard0_slab]
  others_slab = strings_parts[:others_slab]

  base_md_str = shard_plan[:base_md_str] != nil ? shard_plan[:base_md_str] : shard_plan[:tail_md_str]
  novec_out = shard_plan[:novec_out] != nil ? shard_plan[:novec_out] : ""
  ewscope_out = shard_plan[:ewscope_out] != nil ? shard_plan[:ewscope_out] : ""
  ascope_out = shard_plan[:ascope_out] != nil ? shard_plan[:ascope_out] : ""

  modules = []
  s = 0
  while s < nshards
    if s > 0 && shard_fn_bytes[s] == 0
      s += 1
      next
    body_buf = StringBuffer(shard_fn_bytes[s] + 4096)
    i = 0
    while i < nfns
      if owner_shard[i] == s
        f = fns[i]
        txt = texts[i]
        if f[:embedded_asm] == nil && (f[:llvm_internal] == true || f[:embedded_ll] != nil)
          body_buf << shard_rewrite_define_linkage(txt, "define hidden ")
        else
          body_buf << txt
        body_buf << "\n"
      i += 1
    body_str = body_buf.to_s()

    refs = {}
    shard_collect_at_refs(body_str, refs)
    if s == 0
      shard_collect_at_refs(seams_str, refs)
      shard_collect_at_refs(fn_meta_out, refs)
      shard_collect_at_refs(call_site_out, refs)

    kept_ai_buf = nil
    if alwaysinline_entries.size() > 0
      ai_idx = 0
      while ai_idx < alwaysinline_entries.size()
        ai_entry = alwaysinline_entries[ai_idx]
        if refs[ai_entry[:name]] == true
          if kept_ai_buf == nil
            kept_ai_buf = StringBuffer(1024)
          kept_ai_buf << ai_entry[:text]
          shard_merge_ref_sets(refs, ai_entry[:refs])
        ai_idx += 1

    # Two-pass closure over shared inline helper definitions (e.g. sqr5 -> sqr4 -> runtime).
    sdi_keep = Array.new(shared_decl_items.size())
    pass = 0
    while pass < 2
      di = 0
      while di < shared_decl_items.size()
        item = shared_decl_items[di]
        if item[:kind] == :def && sdi_keep[di] != true && (item[:name] == nil || refs[item[:name]] == true)
          sdi_keep[di] = true
          shard_merge_ref_sets(refs, item[:refs])
        di += 1
      pass += 1

    est = body_str.size() + 32768
    if s == 0
      est = est + globals_pair[:shard0].size() + shard0_slab.size() + seams_str.size() + fn_meta_out.size() + call_site_out.size()
    buf = StringBuffer(est)
    buf << header

    if s > 0 && seams_decl_items.size() > 0
      si = 0
      while si < seams_decl_items.size()
        sitem = seams_decl_items[si]
        if refs[sitem[:name]] == true
          buf << sitem[:line]
        si += 1

    di = 0
    while di < shared_decl_items.size()
      item = shared_decl_items[di]
      if item[:kind] == :def
        if sdi_keep[di] == true
          buf << item[:text]
      elsif item[:name] == nil || refs[item[:name]] == true
        buf << item[:text]
      di += 1
    buf << "\n"

    if s == 0
      buf << globals_pair[:shard0]
    else
      gi = 0
      while gi < other_global_items.size()
        gitem = other_global_items[gi]
        if refs[gitem[:name]] == true
          buf << gitem[:line]
        gi += 1
      buf << "\n"

    psi = 0
    any_ptr_str = false
    while psi < ptr_string_items.size()
      pitem = ptr_string_items[psi]
      if refs[pitem[:name]] == true
        buf << pitem[:line]
        any_ptr_str = true
      psi += 1
    if any_ptr_str
      buf << "\n"

    if s == 0
      buf << shard0_slab
    elsif others_slab != "" && refs["__static_slab"] == true
      buf << others_slab

    i = 0
    while i < nfns
      if owner_shard[i] != s && owner_shard[i] >= 0 && fn_decl_lines[i] != nil && refs[fns[i][:name]] == true
        buf << fn_decl_lines[i]
      i += 1
    buf << "\n"

    if kept_ai_buf != nil
      buf << kept_ai_buf.to_s()
    buf << body_str

    if s == 0
      buf << seams_str
      buf << fn_meta_out
      buf << call_site_out
      buf << llvm_used_out

    buf << base_md_str
    if novec_out != "" && (body_str.index("!llvm.loop") != nil || body_str.index("!3142") != nil)
      buf << novec_out
    if ewscope_out != "" && (body_str.index("!alias.scope !30") != nil || body_str.index("!noalias !30") != nil)
      buf << ewscope_out
    if ascope_out != "" && body_str.index("!30000") != nil
      buf << ascope_out
    modules.push(buf.to_s())
    s += 1

  modules
