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
  shard0_weight = (seams_str.size() + fn_meta_out.size() + call_site_out.size()) / 4
  target_per_shard = (total_fn_bytes + shard0_weight) / nshards
  if target_per_shard < 32768
    target_per_shard = 32768

  owner_shard = Array.new(nfns)
  fn_decl_lines = Array.new(nfns)
  alwaysinline_bodies = StringBuffer(1024)
  cur_shard = 0
  cur_bytes = shard0_weight
  i = 0
  while i < nfns
    f = fns[i]
    txt = texts[i]
    if f[:embedded_asm] != nil
      owner_shard[i] = 0
      fn_decl_lines[i] = "declare " + f[:return_type] + " @" + f[:name] + "(" + shard_decl_param_types(f) + ") nounwind\n"
    elsif shard_embedded_ll_alwaysinline?(f)
      owner_shard[i] = -1
      fn_decl_lines[i] = nil
      alwaysinline_bodies << shard_rewrite_define_linkage(txt, "define linkonce_odr hidden ")
      alwaysinline_bodies << "\n"
    else
      owner_shard[i] = cur_shard
      cur_bytes = cur_bytes + txt.size()
      if cur_shard < nshards - 1 && cur_bytes >= target_per_shard
        cur_shard = cur_shard + 1
        cur_bytes = 0
      cc = ""
      if f[:call_conv] != nil && f[:call_conv] != ""
        cc = f[:call_conv] + " "
      if f[:llvm_internal] == true
        fn_decl_lines[i] = "declare hidden " + cc + f[:return_type] + " @" + f[:name] + "(" + shard_decl_param_types(f) + ") nounwind\n"
      elsif f[:name] == "main"
        fn_decl_lines[i] = nil
      else
        fn_decl_lines[i] = "declare " + cc + f[:return_type] + " @" + f[:name] + "(" + shard_decl_param_types(f) + ") nounwind\n"
    i += 1

  actual_shards = cur_shard + 1
  if actual_shards < 2
    return nil

  header = shard_plan[:header]
  seams_decls = shard_extract_seams_decls(seams_str)
  shared_decls = shard_rewrite_shared_decls(shard_plan[:decls_out])
  globals_pair = shard_split_globals(shard_plan[:globals_str])
  strings_parts = shard_split_strings_out(shard_plan[:strings_str])
  ptr_strings = strings_parts[:ptr_strings]
  shard0_slab = strings_parts[:shard0_slab]
  others_slab = strings_parts[:others_slab]

  alwaysinline_str = alwaysinline_bodies.to_s()
  tail_md_str = shard_plan[:tail_md_str]

  modules = []
  s = 0
  while s < actual_shards
    est = (total_fn_bytes / actual_shards) + shared_decls.size() + globals_pair[:others].size() + tail_md_str.size() + 65536
    if s == 0
      est = est + shard0_slab.size() + seams_str.size() + fn_meta_out.size() + call_site_out.size()
    buf = StringBuffer(est)
    buf << header
    if s > 0 && seams_decls != ""
      buf << seams_decls
    buf << shared_decls
    if s == 0
      buf << globals_pair[:shard0]
      buf << ptr_strings
      buf << shard0_slab
    else
      buf << globals_pair[:others]
      buf << ptr_strings
      buf << others_slab
    i = 0
    while i < nfns
      if owner_shard[i] != s && owner_shard[i] >= 0 && fn_decl_lines[i] != nil
        buf << fn_decl_lines[i]
      i += 1
    buf << "\n"
    if alwaysinline_str != ""
      buf << alwaysinline_str
    i = 0
    while i < nfns
      if owner_shard[i] == s
        f = fns[i]
        txt = texts[i]
        if f[:embedded_asm] == nil && (f[:llvm_internal] == true || f[:embedded_ll] != nil)
          buf << shard_rewrite_define_linkage(txt, "define hidden ")
        else
          buf << txt
        buf << "\n"
      i += 1
    if s == 0
      buf << seams_str
      buf << fn_meta_out
      buf << call_site_out
      buf << llvm_used_out
    buf << tail_md_str
    modules.push(buf.to_s())
    s += 1

  modules
