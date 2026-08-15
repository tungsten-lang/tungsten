
-> kind_is_inline(k)
  # Kinds whose schema entry maps a field to OFFSET_INLINE (256) — i.e.
  # the data lives in the W_PACKED_NODE's 32-bit offset bits, no arena
  # slot. Listed alphabetically; cross-check against ast_schema.w's
  # slab_offset_table_data when adding new inline kinds.
  if k == :char
    return true
  if k == :codepoint
    return true
  if k == :color
    return true
  if k == :lambda_arity
    return true
  if k == :parg
    return true
  if k == :regex_capture
    return true
  if k == :superscript
    return true
  false

-> bit_width_of(n)
  if n <= 0
    return 0
  bits = 0
  v = n
  while v > 0
    v = v >> 1
    bits = bits + 1
  bits

# --ast-stats: dump slab AST node counts after a compile. Wrapped in a
# function so the ccall_nobox is not at module top level (the C VM
# stage 0 that runs this during bootstrap is touchy about top-level
# ccall_nobox). The 0 is a placeholder — ccall_nobox has no zero-arg form.
# Recursively tally AST node kinds into `counts` (kind symbol -> count).
-> count_kinds(node, counts)
  k = ast_kind(node)
  if k == nil
    return nil
  if counts[k] == nil
    counts[k] = 0
  counts[k] = counts[k] + 1
  if k == :var
    g_ast_stats_varnames[node.name] = true
  kids = ast_children(node)
  if kids.size() == 2
    k1 = ast_kind(kids[0])
    k2 = ast_kind(kids[1])
    if g_ast_stats_same_kind[k] == nil
      g_ast_stats_same_kind[k] = {total: 0, same: 0}
    g_ast_stats_same_kind[k][:total] = g_ast_stats_same_kind[k][:total] + 1
    if k1 == k2
      g_ast_stats_same_kind[k][:same] = g_ast_stats_same_kind[k][:same] + 1
  parent_offset = ccall("w_node_offset_extern", node)
  parent_sclass = ccall_nobox("w_node_size_class_extern", node)
  i = 0
  while i < kids.size()
    kid = kids[i]
    kid_kind = ast_kind(kid)
    if kind_is_inline(kid_kind)
      g_ast_stats_meta[:child_inline] = g_ast_stats_meta[:child_inline] + 1
    else
      kid_sclass = ccall_nobox("w_node_size_class_extern", kid)
      kid_offset = ccall("w_node_offset_extern", kid)
      delta = parent_offset - kid_offset
      if kid_sclass != parent_sclass
        g_ast_stats_meta[:cross_arena] = g_ast_stats_meta[:cross_arena] + 1
        abs_delta = delta
        if abs_delta < 0
          abs_delta = 0 - abs_delta
        cbucket = bit_width_of(abs_delta)
        if g_ast_stats_delta_cross[cbucket] == nil
          g_ast_stats_delta_cross[cbucket] = 0
        g_ast_stats_delta_cross[cbucket] = g_ast_stats_delta_cross[cbucket] + 1
      else
        if delta < 0
          g_ast_stats_meta[:negative_delta] = g_ast_stats_meta[:negative_delta] + 1
        else
          g_ast_stats_meta[:same_arena_real] = g_ast_stats_meta[:same_arena_real] + 1
          bucket = bit_width_of(delta)
          if g_ast_stats_delta[bucket] == nil
            g_ast_stats_delta[bucket] = 0
          g_ast_stats_delta[bucket] = g_ast_stats_delta[bucket] + 1
    count_kinds(kid, counts)
    i += 1
  nil

-> dump_ast_stats
  ccall_nobox("w_ast_stats_dump", 0)
  << "--- AST stats: nodes by kind (loaded parse tree) ---"
  ks = g_ast_stats_counts.keys()
  i = 0
  while i < ks.size()
    << "KINDCOUNT " + ks[i].to_s() + " " + g_ast_stats_counts[ks[i]].to_s()
    i += 1
  << "DISTINCT var_names " + g_ast_stats_varnames.keys().size().to_s()
  << "--- AST stats: parent->child edges ---"
  << "META same_arena_real " + g_ast_stats_meta[:same_arena_real].to_s()
  << "META cross_arena " + g_ast_stats_meta[:cross_arena].to_s()
  << "META child_inline " + g_ast_stats_meta[:child_inline].to_s()
  << "META negative_delta " + g_ast_stats_meta[:negative_delta].to_s()
  bks = g_ast_stats_delta.keys()
  i = 0
  while i < bks.size()
    << "DELTA_BITS " + bks[i].to_s() + " " + g_ast_stats_delta[bks[i]].to_s()
    i += 1
  << "--- AST stats: cross-layout-class |delta| histogram ---"
  cbks = g_ast_stats_delta_cross.keys()
  i = 0
  while i < cbks.size()
    << "DELTA_CROSS_BITS " + cbks[i].to_s() + " " + g_ast_stats_delta_cross[cbks[i]].to_s()
    i += 1
  << "--- AST stats: 2-child same-kind by parent kind ---"
  sks = g_ast_stats_same_kind.keys()
  i = 0
  while i < sks.size()
    pk = sks[i]
    rec = g_ast_stats_same_kind[pk]
    << "SAMEKIND " + pk.to_s() + " " + rec[:same].to_s() + "/" + rec[:total].to_s()
    i += 1

# ── Incremental compile cache ─────────────────────────────────────────────
# `tungsten compile` / `-o` re-lowered and re-linked byte-identical inputs
# every run (identical self-compile retires an identical 53.6B instructions).
# Cache the final binary + sidemap keyed by (compiler binary identity,
# codegen-relevant flags, entry path) and validated by the loader's
# (path, mtime_ns) manifest of every file the build read — the same
# freshness rule the ruby AST cache uses. Compiled-runtime only (the C VM
# lacks the w_executable_path ccall, and bootstrap stages must not share
# entries across compiler binaries — exe path+mtime is part of the
# identity). TUNGSTEN_INCREMENTAL=0 disables (the PGO post-step sets it:
# a cache hit would skip the very work being profiled).

-> incremental_cache_enabled?
  if env("TUNGSTEN_INCREMENTAL") == "0"
    return false
  runtime_identity() == "compiled-runtime"

-> incremental_env_s(name)
  v = env(name)
  if v == nil
    return ""
  v

# Split the emitted module and compile the parts with parallel clang -c.
# Returns the space-joined .o paths, or nil for "use the single-TU path"
# (missing toolchain, or any split/compile failure). Uses Homebrew LLVM's
# llvm-split + clang: llvm-split without -preserve-locals promotes module-
# local symbols so partitions distribute (with it, every function glued to
# the shared globals lands in one partition and nothing parallelizes), and
# its bitcode output needs a matching-version clang to read.
-> parallel_codegen_objects(ll_path, verbose)
  llvm_prefix = driver_homebrew_prefix("llvm")
  if llvm_prefix == ""
    return nil
  llvm_bin = llvm_prefix + "/bin"
  if !file?(llvm_bin + "/llvm-split") || !file?(llvm_bin + "/clang")
    return nil
  parts = 14
  prefix = ll_path + ".part"
  q_ll = dev_runtime_shell_quote(ll_path)
  q_prefix = dev_runtime_shell_quote(prefix)
  if system(dev_runtime_shell_quote(llvm_bin + "/llvm-split") + " -j " + parts.to_s() + " -o " + q_prefix + " " + q_ll) != true
    return nil
  # Stale part objects from a previous run would satisfy the existence
  # check below even when a clang job fails (sh's bare `wait` exits 0
  # regardless of job status) — clear them so every .o linked was
  # produced by THIS spawn. Each job also touches a .ok marker AFTER its
  # clang succeeds; requiring the marker rejects truncated objects from
  # jobs killed mid-write, which still leave a .o on disk.
  system("rm -f " + q_prefix + "*.o " + q_prefix + "*.ok")
  flags = profile_opt_flag() + " " + debug_compile_flag() + " " + march_flags() + " -fmerge-all-constants "
  on macos
    flags = flags + "-fveclib=Darwin_libsystem_m "
  cmd = StringBuffer(1024)
  objs = StringBuffer(512)
  i = 0
  while i < parts
    part = prefix + i.to_s()
    if !file?(part)
      return nil
    cmd << dev_runtime_shell_quote(llvm_bin + "/clang")
    cmd << " "
    cmd << flags
    cmd << "-c -x ir "
    cmd << dev_runtime_shell_quote(part)
    cmd << " -o "
    cmd << dev_runtime_shell_quote(part + ".o")
    cmd << " && touch "
    cmd << dev_runtime_shell_quote(part + ".ok")
    cmd << " & "
    objs << dev_runtime_shell_quote(part + ".o")
    objs << " "
    i += 1
  cmd << "wait"
  if system(cmd.to_s()) != true
    return nil
  i = 0
  while i < parts
    if !file?(prefix + i.to_s() + ".o") || !file?(prefix + i.to_s() + ".ok")
      return nil
    i += 1
  # Success: the split bitcode inputs and job markers served their purpose;
  # only the .o files feed the link. Leaving parts behind leaked ~15 files
  # per build when ll_path is a stable (--ll / source-adjacent) location.
  i = 0
  while i < parts
    system("rm -f " + dev_runtime_shell_quote(prefix + i.to_s()) + " " + dev_runtime_shell_quote(prefix + i.to_s() + ".ok"))
    i += 1
  objs.to_s()

# Runtime source (path, mtime_ns) rows for the incremental manifest. The
# cached binary embeds the runtime archive, whose PATH is stable across
# runtime-source edits (dev_runtime_archive_path hashes config, not
# content) and whose rebuild happens AFTER the cache probe — so a touched
# runtime source must invalidate cached binaries here, over exactly the
# file set the archive's own freshness check watches.
-> incremental_runtime_entries
  runtime_dir = resolve_runtime_dir
  ev = runtime_event_source
  runtime_root = dev_runtime_source_identity(runtime_dir, runtime_identity())
  gt = file?(runtime_root + "/generated/bigint_thresholds.h") ? "present" : "absent"
  bases = dev_runtime_base_files(ev, gt, tls_runtime_source())
  entries = []
  bi = 0
  while bi < bases.size()
    p = runtime_root + "/" + bases[bi]
    mt = file_mtime_ns(p)
    if mt != nil
      entries.push([p, mt])
    bi += 1
  entries

-> incremental_abs_path(p)
  if p.starts_with?("/")
    return p
  pwd = capture("pwd -P 2>/dev/null").strip()
  if pwd == ""
    return p
  pwd + "/" + p

-> incremental_cache_slot(file_path, out_path, identity)
  dir = compiler_cache_dir()
  if dir == nil
    return nil
  if system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
    return nil
  # Hash ABSOLUTE paths AND the full identity into the slot name: verbatim
  # paths overflowed NAME_MAX on deep trees (every store failed "File name
  # too long"), relative invocations from two projects must not share a
  # slot, and folding the identity in keeps differently-configured builds
  # (--dev vs default, -D defines, env knobs) in separate slots — two
  # concurrent writers can then never pair one config's manifest with the
  # other's binary. The identity line in the manifest stays as a self-check.
  key = incremental_abs_path(file_path) + "__" + incremental_abs_path(out_path) + "|" + identity
  dir + "/irbin-" + wyhash64_hex_string(key)

# Freshness is mtime-based for source manifests, while the identity covers the
# compiler/linker executables, target flags, optional features, and ambient SDK
# paths. `tungsten --clear-cache` remains the escape hatch for a tool that lies
# about both its contents and filesystem identity.
-> incremental_identity(file_path, out_path)
  exe = ccall("w_executable_path")
  em = file_mtime_ns(exe)
  if em == nil
    return nil
  runtime_kind = runtime_identity()
  cc_identity = dev_runtime_cc_identity(host_c_compiler(), runtime_kind)
  ar_identity = dev_runtime_ar_identity(archive_tool(), runtime_kind)
  if cc_identity == nil || ar_identity == nil
    return nil
  defs = ""
  # Sorted deliberately (NOT an iteration-order workaround): -D flags may
  # arrive in any order across invocations, and the cache identity string
  # must not change when they do.
  dk = build_defines.keys().sort()
  dki = 0
  while dki < dk.size()
    defs = defs + dk[dki] + "=" + build_defines[dk[dki]] + ";"
    dki += 1
  ra = runtime_archive == nil ? "" : runtime_archive
  ram = ""
  if ra != ""
    ramv = file_mtime_ns(ra)
    ram = ramv == nil ? "missing" : ramv.to_s()
  ["irbin-v5", incremental_abs_path(file_path), incremental_abs_path(out_path), exe, em.to_s(), cc_identity, ar_identity, release_mode.to_s(), debug_enabled.to_s(), cpu_target_mode, march_flags(), dev_mode.to_s(), fast_mode.to_s(), math_mode.to_s(), frame_pointers.to_s(), intern_algo, no_lto.to_s(), explicit_lto.to_s(), cross_target, cross_sysroot, ra, ram, incremental_env_s("SDKROOT"), incremental_env_s("MACOSX_DEPLOYMENT_TARGET"), incremental_env_s("CPATH"), incremental_env_s("C_INCLUDE_PATH"), incremental_env_s("CPLUS_INCLUDE_PATH"), incremental_env_s("LIBRARY_PATH"), incremental_env_s("PKG_CONFIG_PATH"), incremental_env_s("PKG_CONFIG_LIBDIR"), incremental_env_s("TLS"), incremental_env_s("TUNGSTEN_TLS"), incremental_env_s("TUNGSTEN_TLS_CFLAGS"), incremental_env_s("TUNGSTEN_TLS_LDFLAGS"), incremental_env_s("TUNGSTEN_GPU_DIALECTS"), incremental_env_s("TUNGSTEN_CLANG_OPT"), incremental_env_s("TUNGSTEN_MARCH_ARGS"), incremental_env_s("TUNGSTEN_CARRY_UNROLL"), incremental_env_s("TUNGSTEN_FREE"), incremental_env_s("TUNGSTEN_PARAM_INFER"), incremental_env_s("TUNGSTEN_DEMOTE_TOP_LEVEL"), incremental_env_s("TUNGSTEN_MIMALLOC"), incremental_env_s("TUNGSTEN_LLVM_FASTCC"), incremental_env_s("TUNGSTEN_PARALLEL_CODEGEN"), incremental_env_s("TUNGSTEN_CORE_REACHABILITY"), incremental_env_s("TUNGSTEN_LAZY_CONTENT_HASH"), incremental_env_s("TUNGSTEN_DYNAMIC_EXPORTS"), incremental_env_s("TUNGSTEN_C_INCLUDES"), incremental_env_s("TUNGSTEN_DEFINES"), incremental_env_s("TUNGSTEN_SERVICE_BINDINGS"), incremental_env_s("BIT_HOME"), incremental_env_s("TUNGSTEN_ROOT"), incremental_env_s("TUNGSTEN_CC"), incremental_env_s("TUNGSTEN_AR"), incremental_env_s("TUNGSTEN_SYMBOL_PREFIX_HEX"), defs].join("|")

# Content-addressed final-link cache. The early irbin cache deliberately keys
# source and output paths so it can skip every compiler phase. This cache keys
# the actual emitted LLVM instead, after lowering/emission have established
# that two builds are semantically the same link input.
-> link_artifact_cache_dependency_identity
  rows = []
  runtime = incremental_runtime_entries()
  i = 0
  while i < runtime.size()
    rows.push(runtime[i][0] + ":" + runtime[i][1].to_s())
    i += 1

  # Companions are linked only when referenced, but including every existing
  # source is a cheap conservative invalidation rule and avoids duplicating the
  # feature-gating logic here. Missing optional files are represented too.
  runtime_dir = resolve_runtime_dir()
  companions = ["ssmr_witness.c", "lexchar_tables.c", "unicode_tables.c", "blas_bridge.c",
                "sparse_bridge.c", "metal.m", "graphics.m", "hid_bridge.m",
                "sci_io_native.c", "tensor_bridge.c", "openblas_bridge.c",
                zstd_runtime_source()]
  i = 0
  while i < companions.size()
    path = runtime_dir + companions[i]
    mt = file_mtime_ns(path)
    rows.push(path + ":" + (mt == nil ? "missing" : mt.to_s()))
    i += 1
  rows.join("|")

-> link_artifact_cache_runtime_identity(runtime_objs)
  if runtime_objs == nil
    return "runtime-source"
  if runtime_objs.index("/*.o") != nil
    # compile-batch creates this private path afresh. Its selected sources,
    # compiler, flags, and mtimes are already represented by the identity.
    return "batch-runtime-objects"
  mt = file_mtime_ns(runtime_objs)
  incremental_abs_path(runtime_objs) + ":" + (mt == nil ? "missing" : mt.to_s())

-> link_artifact_cache_slot(ll_text, runtime_objs, needs_zstd)
  if !incremental_cache_enabled?() || env("TUNGSTEN_LINK_CACHE") == "0"
    return nil
  # A path-valued C include can itself include arbitrary headers. Reusing only
  # from its own mtime would be unsound, so leave FFI builds on the ordinary
  # linker path until a depfile-backed C graph exists.
  if extra_c_includes().size() > 0
    return nil
  base = incremental_identity("", "")
  cache_dir = compiler_cache_dir()
  if base == nil || cache_dir == nil
    return nil
  if system("mkdir -p " + dev_runtime_shell_quote(cache_dir)) != true
    return nil

  flags = [onig_cflags(), onig_ldflags(), tls_cflags(), tls_ldflags(),
           http2_ldflags(), mimalloc_link_flags()]
  if needs_zstd
    flags.push(zstd_cflags())
    flags.push(zstd_ldflags())
  identity = ["link-artifact-v1", ll_text.size().to_s(),
              wyhash64_hex_string(ll_text), base,
              link_artifact_cache_runtime_identity(runtime_objs),
              link_artifact_cache_dependency_identity(), flags.join("|")].join("|")
  cache_dir + "/linkbin-" + wyhash64_hex_string(identity) + ".bin"

-> link_artifact_cache_try_reuse(slot, out_path)
  if !file?(slot)
    return false
  q_out = dev_runtime_shell_quote(out_path)
  q_tmp = dev_runtime_shell_quote(out_path + ".link-install.") + "$$"
  if system("cp -p " + dev_runtime_shell_quote(slot) + " " + q_tmp + " && mv -f " + q_tmp + " " + q_out) != true
    return false
  # Active content survives the shared seven-day cache GC window.
  system("touch " + dev_runtime_shell_quote(slot))
  true

-> link_artifact_cache_store(slot, out_path)
  nonce = clock.to_s()
  tmp = slot + ".tmp." + nonce
  if system("cp -p " + dev_runtime_shell_quote(out_path) + " " + dev_runtime_shell_quote(tmp)) != true
    return nil
  if system("mv -f " + dev_runtime_shell_quote(tmp) + " " + dev_runtime_shell_quote(slot)) != true
    system("rm -f " + dev_runtime_shell_quote(tmp))
  nil

# Valid cached slot for this identity? Reads the manifest and revalidates
# every recorded (path, mtime_ns). Any surprise → miss (rebuild).
-> incremental_manifest_valid?(slot, identity)
  manifest = read_file(slot + ".manifest")
  if manifest == nil
    return false
  lines = manifest.split("\n")
  # >= 2: identity line plus at least one file row. A store always records
  # the runtime base sources, so a rowless manifest is truncation damage.
  if lines.size() < 2 || lines[0] != identity
    return false
  i = 1
  while i < lines.size()
    line = lines[i]
    if line != ""
      tab = line.index("\t")
      if tab == nil
        return false
      mt = line.slice(0, tab)
      pathpart = line.slice(tab + 1, line.size() - tab - 1)
      cur = file_mtime_ns(pathpart)
      if cur == nil || cur.to_s() != mt
        return false
    i += 1
  if !file?(slot + ".bin")
    return false
  true

# Manifest check plus install: on success the cached binary + sidemap land
# at out_path.
-> incremental_try_reuse(slot, identity, out_path, verbose)
  if !incremental_manifest_valid?(slot, identity)
    return false
  # Install via a unique temp + rename: an out_path that is currently
  # EXECUTING keeps its inode (an in-place cp truncates it — on macOS the
  # running process dies SIGKILL from code-sign invalidation). $$ stays
  # outside the quoting so the shell expands its own pid.
  q_out = dev_runtime_shell_quote(out_path)
  q_tmp = dev_runtime_shell_quote(out_path + ".install.") + "$$"
  if system("cp -p " + dev_runtime_shell_quote(slot + ".bin") + " " + q_tmp + " && mv -f " + q_tmp + " " + q_out) != true
    return false
  if file?(slot + ".sidemap")
    system("cp -p " + dev_runtime_shell_quote(slot + ".sidemap") + " " + dev_runtime_shell_quote(out_path + ".sidemap"))
  else
    # No cached sidemap: drop any stale one a previous non-cached build
    # left beside out_path, or crash reports symbolize against old code.
    system("rm -f " + dev_runtime_shell_quote(out_path + ".sidemap"))
  true

-> incremental_store(slot, identity, out_path, sidemap_path, file_path)
  files = g_incremental[:manifest]
  if files == nil
    return nil
  parts = [identity]
  i = 0
  while i < files.size()
    parts.push(files[i][1].to_s() + "\t" + incremental_abs_path(files[i][0]))
    i += 1
  rt = incremental_runtime_entries
  ri = 0
  while ri < rt.size()
    parts.push(rt[ri][1].to_s() + "\t" + rt[ri][0])
    ri += 1
  # @gpu sidecars are emitted next to the SOURCE; recording them as rows
  # means a deleted sidecar mtimes to nil at probe time and forces the
  # rebuild that regenerates it.
  gpu_exts = [".metal", ".cu"]
  gi = 0
  while gi < gpu_exts.size()
    gp = file_path.replace(".w", gpu_exts[gi])
    gm = file_mtime_ns(gp)
    if gm != nil
      parts.push(gm.to_s() + "\t" + incremental_abs_path(gp))
    gi += 1
  # Unique staging names (concurrent writers of the same slot must never
  # interleave into one temp file) and manifest-last, atomic-rename
  # publication: a reader sees either the old pair or the new pair.
  nonce = clock.to_s()
  q_slot_bin = dev_runtime_shell_quote(slot + ".bin")
  tmp = slot + ".bin.tmp." + nonce
  if system("cp -p " + dev_runtime_shell_quote(out_path) + " " + dev_runtime_shell_quote(tmp)) != true
    return nil
  if system("mv -f " + dev_runtime_shell_quote(tmp) + " " + q_slot_bin) != true
    system("rm -f " + dev_runtime_shell_quote(tmp))
    return nil
  if file?(sidemap_path)
    system("cp -p " + dev_runtime_shell_quote(sidemap_path) + " " + dev_runtime_shell_quote(slot + ".sidemap"))
  else
    system("rm -f " + dev_runtime_shell_quote(slot + ".sidemap"))
  mtmp = slot + ".manifest.tmp." + nonce
  write_file(mtmp, parts.join("\n") + "\n")
  if system("mv -f " + dev_runtime_shell_quote(mtmp) + " " + dev_runtime_shell_quote(slot + ".manifest")) != true
    system("rm -f " + dev_runtime_shell_quote(mtmp))
  nil

-> compile_one(file_path, out_path, emit_wire, verbose, intern_algo, emit_ll_only_arg = false, quiet = false)
  if out_path == nil
    out_path = file_path.replace(".w", ".wc")

  # Cache probe: full binary path only (no --emit-wire/--emit-ll/--ll and
  # no TUNGSTEN_LL_PATH/TUNGSTEN_LL_DONE_MARKER — those flows consume
  # intermediate artifacts a cache hit would never produce).
  incr_slot = nil
  incr_id = nil
  if !emit_wire && !emit_ll_only_arg && !keep_ll && incremental_env_s("TUNGSTEN_LL_PATH") == "" && incremental_env_s("TUNGSTEN_LL_DONE_MARKER") == "" && incremental_cache_enabled?
    incr_id = incremental_identity(file_path, out_path)
    if incr_id != nil
      incr_slot = incremental_cache_slot(file_path, out_path, incr_id)
    if incr_slot != nil && incr_id != nil
      if incremental_try_reuse(incr_slot, incr_id, out_path, verbose)
        if !quiet
          << ""
          << "Built [out_path] (cache)"
        return true

  implicit_ll = uses_implicit_ll_path() ## bool
  sidemap_path = out_path + ".sidemap"
  ll_path = emit_ir(file_path, emit_wire, verbose, intern_algo, sidemap_path, emit_ll_only_arg, build_defines)

  if ll_path == nil
    return true

  if emit_ll_only_arg
    if implicit_ll && !publish_implicit_ll_path(ll_path, file_path)
      return false
    return true

  ok = link_binary(ll_path, out_path, runtime_archive, verbose)
  if implicit_ll && !publish_implicit_ll_path(ll_path, file_path)
    ok = false

  if ok
    if !quiet
      << ""
      << "Built [out_path]"
    if incr_slot != nil && incr_id != nil
      incremental_store(incr_slot, incr_id, out_path, sidemap_path, file_path)

  ok

# `run` and `-e` use the ordinary lowering/WIRE/LLVM path. Stable per-source
# output names let the existing incremental binary cache make repeated runs
# cheap; only the tiny exit-status sidecar is invocation-specific.
-> compiled_run_dir
  dir = compiler_cache_dir() + "/run"
  if system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
    raise "could not create compiled-run cache directory: [dir]"
  dir

-> compiled_run_output_path(source_path)
  identity = incremental_abs_path(source_path)
  compiled_run_dir() + "/" + wyhash64_hex_string(identity) + ".wc"

# The eval file is content-addressed, so every writer writes identical bytes;
# the temp + rename only guarantees a concurrent reader never sees a
# truncated file mid-write.
-> materialize_eval_source(code)
  dir = compiled_run_dir()
  path = dir + "/eval-" + wyhash64_hex_string(code) + ".w"
  if !file?(path) || read_file(path) != code
    tmp = path + ".tmp." + clock.to_s()
    write_file(tmp, code)
    system("mv -f " + dev_runtime_shell_quote(tmp) + " " + dev_runtime_shell_quote(path))
  path

# Serialize concurrent builds of one cache binary. mkdir is the portable
# atomic lock primitive (same as cache_gc.sh). A lock left behind by a
# crashed process is stolen after ~60s of waiting; after ~90s total we give
# up and proceed unlocked — a duplicate compile beats a deadlock.
-> acquire_run_lock(lock_path)
  attempts = 0
  while system("mkdir " + dev_runtime_shell_quote(lock_path) + " 2>/dev/null") != true
    attempts += 1
    if attempts == 600
      system("rmdir " + dev_runtime_shell_quote(lock_path) + " 2>/dev/null")
    if attempts > 900
      return false
    system("sleep 0.1")
  true

-> release_run_lock(lock_path)
  system("rmdir " + dev_runtime_shell_quote(lock_path) + " 2>/dev/null")
  nil

# The shared cache GC (bin/commands/cache_gc.sh) self-throttles to one sweep
# per day, so this background kick is almost always a no-op. It keeps
# run-cache binaries and eval sources bounded for users who only ever `run`.
-> kick_run_cache_gc
  script = resolve_runtime_dir + "../bin/commands/cache_gc.sh"
  if file?(script)
    system("(bash " + dev_runtime_shell_quote(script) + " " + dev_runtime_shell_quote(compiler_cache_dir()) + " >/dev/null 2>&1 &)")
  nil

# Warm-run fast path: when the incremental manifest says the slot is
# current AND that exact identity is what was last published onto the run
# binary, skip every copy and rename and exec the existing inode. macOS
# validates a binary's code signature on the first exec of fresh file
# content (~200ms); re-executing an already-validated inode costs ~4ms, so
# a warm run must not rewrite the published file at all.
-> run_cache_current?(source_path, stage, binary)
  if keep_ll || incremental_env_s("TUNGSTEN_LL_PATH") != "" || incremental_env_s("TUNGSTEN_LL_DONE_MARKER") != "" || !incremental_cache_enabled?
    return false
  id = incremental_identity(source_path, stage)
  if id == nil
    return false
  slot = incremental_cache_slot(source_path, stage, id)
  if slot == nil
    return false
  if !incremental_manifest_valid?(slot, id)
    return false
  if !file?(binary)
    return false
  read_file(binary + ".id") == id

-> publish_run_binary(source_path, stage, binary)
  if system("mv -f " + dev_runtime_shell_quote(stage) + " " + dev_runtime_shell_quote(binary)) != true
    return false
  system("mv -f " + dev_runtime_shell_quote(stage + ".sidemap") + " " + dev_runtime_shell_quote(binary + ".sidemap") + " 2>/dev/null")
  # Same guard as the compile_one probe: identity needs ccalls the stage-0
  # VM does not provide, and without the cache the .id stamp is useless.
  if incremental_cache_enabled?
    id = incremental_identity(source_path, stage)
    if id != nil
      write_file(binary + ".id", id)
  true

# Returns the child's exact exit code, or 128+signal for a signal death.
# Builds land in a sibling .stage file under the lock and are renamed onto
# the final name, so an already-running instance keeps its old inode — a
# concurrent `run` of the same script can never truncate a binary that is
# executing. The child is spawned directly from argv: no shell, no quoting,
# no job-control chatter on stderr.
-> run_compiled_program(source_path, run_args)
  binary = compiled_run_output_path(source_path)
  stage = binary + ".stage"
  lock_path = binary + ".lock"
  locked = acquire_run_lock(lock_path)
  ok = false
  begin
    if run_cache_current?(source_path, stage, binary)
      ok = true
    else
      ok = compile_one(source_path, stage, false, verbose, intern_algo, false, true)
      if ok
        ok = publish_run_binary(source_path, stage, binary)
  rescue err
    if locked
      release_run_lock(lock_path)
    raise err
  if locked
    release_run_lock(lock_path)
  if !ok
    return 1
  kick_run_cache_gc()

  child_argv = [binary]
  i = 0
  while i < run_args.size()
    child_argv.push(run_args[i])
    i += 1
  status = ccall("w_run_argv", child_argv)
  if status >= 256
    return 128 + (status - 256)
  if status < 0
    ccall("w_eputs", "run: could not execute [binary]")
    return 1
  status

# Parse the complete program and run lowering/type inference, but deliberately
# stop before CFG construction, ownership, LLVM emission, runtime compilation,
# or linking. This is the same stage-2 frontend used by executable builds, so
# `tungsten -c` cannot accept a different language from `tungsten compile`.
-> check_one(file_path, verbose = false)
  loader = Loader.new(verbose)
  ast = loader.load_program_ast(file_path)
  compile_to_wire(ast, file_path, verbose, fast_mode, math_mode, loader.manifest_files())
  gpu_preflight(ast, file_path)
  << "200 OK"
  true

# Frontend-only modes (`--lex` / `--ast`) run before the command dispatcher,
# so they need the same structured-error boundary as check/run/compile.
-> report_frontend_error(err, source_path)
  if type(err) == "Hash" && err[:rt] == :compile_error
    ccall("w_flush")
    ccall("w_eputs", emit_compile_error(err))
    return true
  if type(err) == "String"
    ccall("w_flush")
    ccall("w_eputs", format_runtime_error(err, source_path))
    return true
  false

# Choose deterministic process-level parallelism for compile-batch. Each
# worker owns a disjoint contiguous source shard and therefore its own parser,
# AST/WIRE arenas, and emitter metadata counters. The parent alone compiles a
# runtime (when needed) and links, so parallel lowering does not multiply the
# runtime build or change final link order.
-> batch_parallel_job_count(file_count)
  if file_count < 2 || batch_worker_dir != nil || runtime_identity() != "compiled-runtime"
    return 1
  if emit_wire || tags_mode || ast_stats || keep_ll
    return 1
  if incremental_env_s("TUNGSTEN_LL_PATH") != "" || incremental_env_s("TUNGSTEN_LL_DONE_MARKER") != "" || incremental_env_s("TUNGSTEN_METAL_PATH") != "" || incremental_env_s("TUNGSTEN_SSA_REPORT") != ""
    return 1
  if env("TUNGSTEN_BATCH_PARALLEL") == "0"
    return 1

  requested = batch_jobs
  explicit = requested > 0
  if !explicit
    configured = env("TUNGSTEN_BATCH_JOBS")
    if configured != nil && configured != "" && configured != "auto"
      requested = configured.to_i()
      explicit = requested > 0

  if !explicit
    cpus = ccall("w_cpu_count")
    if cpus < 1
      cpus = 1
    # One worker per ~16 entries amortizes compiler startup and preserves the
    # in-worker parsed-AST/render caches. Eight was the measured knee on the
    # 150-program suite and bounds aggregate memory on larger hosts.
    requested = (file_count + 15) / 16
    if requested > cpus
      requested = cpus
    if requested > 8
      requested = 8
  if requested < 1
    requested = 1
  if requested > file_count
    requested = file_count
  if requested > 32
    requested = 32
  requested

-> batch_parallel_worker_options
  options = []
  if no_lto
    options.push("--no-lto")
  if explicit_lto
    options.push("--lto")
  if frame_pointers
    options.push("--frame-pointers")
  if release_mode
    options.push("--release")
  if debug_requested
    options.push("--debug")
  if no_debug_requested
    options.push("--no-debug")
  if native_mode
    options.push("--native")
  elsif cpu_explicit
    options.push("--cpu")
    options.push(cpu_name)
  if cross_target != ""
    options.push("--target")
    options.push(cross_target)
  if cross_sysroot != ""
    options.push("--sysroot")
    options.push(cross_sysroot)
  if dev_mode
    options.push("--dev")
  if fast_mode
    options.push("--fast")
  if math_mode == :strict
    options.push("--strict-math")
  if intern_algo != "raw"
    options.push("--intern")
    options.push(intern_algo)
  if verbose
    options.push("--verbose")
  if batch_out_dir != nil && batch_out_dir != ""
    options.push("--batch-out-dir")
    options.push(batch_out_dir)
  define_keys = build_defines.keys().sort()
  i = 0
  while i < define_keys.size()
    options.push("-D" + define_keys[i] + "=" + build_defines[define_keys[i]])
    i += 1
  options

-> batch_output_binary(source)
  if batch_out_dir != nil && batch_out_dir != ""
    name = source
    slash = name.rindex("/")
    if slash != nil
      name = name.slice(slash + 1, name.size() - slash - 1)
    if name.ends_with?(".w")
      name = name.slice(0, name.size() - 2)
    return batch_out_dir + "/" + name
  source.replace(".w", ".wc")

-> batch_parallel_files_unique?(files)
  seen = {}
  i = 0
  while i < files.size()
    prior = seen[files[i]]
    if prior != nil && prior == files[i]
      return false
    seen[files[i]] = files[i]
    i += 1
  true

-> batch_parallel_emit(files, jobs, worker_options)
  root = capture("mktemp -d " + dev_runtime_shell_quote(implicit_ll_root() + "/batch-emit.XXXXXX") + " 2>/dev/null").strip()
  if root == ""
    return {ok: false, root: nil, jobs: [], message: "could not create parallel batch scratch directory"}
  exe = ccall("w_executable_path")
  if exe == nil || exe == ""
    return {ok: false, root: root, jobs: [], message: "compiler executable path is unavailable"}

  workers = []
  base = files.size() / jobs
  extra = files.size() % jobs
  start = 0
  wi = 0
  spawn_error = nil
  while wi < jobs && spawn_error == nil
    count = base
    if wi < extra
      count += 1
    dir = root + "/worker-" + wi.to_s()
    out_log = root + "/worker-" + wi.to_s() + ".out"
    err_log = root + "/worker-" + wi.to_s() + ".err"
    if system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
      spawn_error = "could not create worker directory " + dir
    else
      argv = [exe, "compile-batch", "--emit-ll", "--jobs", "1", "--batch-worker-dir", dir]
      oi = 0
      while oi < worker_options.size()
        argv.push(worker_options[oi])
        oi += 1
      fi = 0
      while fi < count
        argv.push(files[start + fi])
        fi += 1
      cmd = StringBuffer(256 + count * 64)
      ai = 0
      while ai < argv.size()
        if ai > 0
          cmd << " "
        cmd << dev_runtime_shell_quote(argv[ai])
        ai += 1
      cmd << " >"
      cmd << dev_runtime_shell_quote(out_log)
      cmd << " 2>"
      cmd << dev_runtime_shell_quote(err_log)
      begin
        process = Process.spawn(["/bin/sh", "-c", cmd.to_s()])
        workers.push({process: process, dir: dir, out_log: out_log, err_log: err_log, start: start, count: count})
      rescue err
        spawn_error = err.to_s()
    start += count
    wi += 1

  if spawn_error != nil
    i = 0
    while i < workers.size()
      workers[i][:process].kill()
      workers[i][:process].wait()
      i += 1
    return {ok: false, root: root, jobs: [], message: "parallel worker spawn failed: " + spawn_error}

  failed = false
  i = 0
  while i < workers.size()
    status = workers[i][:process].wait()
    workers[i][:status] = status
    if status != 0
      failed = true
    i += 1

  # Replay worker logs in source-shard order, not completion order.
  i = 0
  while i < workers.size()
    out_log = workers[i][:out_log]
    if file?(out_log)
      out_text = read_file(out_log)
      if out_text != nil && out_text != ""
        ccall("w_print", out_text)
      ccall("__w_unlink", out_log)
    err_log = workers[i][:err_log]
    if file?(err_log)
      err_text = read_file(err_log)
      if err_text != nil && err_text != ""
        ccall("w_eputs", err_text)
      ccall("__w_unlink", err_log)
    i += 1

  emitted = []
  i = 0
  while i < workers.size()
    worker = workers[i]
    li = 0
    while li < worker[:count]
      source = files[worker[:start] + li]
      ll = worker[:dir] + "/" + li.to_s() + ".ll"
      if !file?(ll) || !file?(ll + ".done")
        failed = true
      emitted.push({ll: ll, bin: batch_output_binary(source), source: source, implicit_ll: true})
      li += 1
    i += 1

  if failed
    return {ok: false, root: root, jobs: emitted, message: "one or more parallel batch workers failed"}
  {ok: true, root: root, jobs: emitted, message: nil}

# Parent-side parallel clang. Emission workers already produced .ll;
# linking them serially is the remaining wall-time tail. Each child is
# the same compiler in --batch-link-worker mode so the clang command,
# runtime archive, and companion gating stay identical to compile_one.
-> batch_parallel_link(ll_jobs, runtime_objs, jobs, verbose)
  if ll_jobs.size() < 2 || jobs < 2 || runtime_identity() != "compiled-runtime"
    return nil
  exe = ccall("w_executable_path")
  if exe == nil || exe == ""
    return nil
  root = capture("mktemp -d " + dev_runtime_shell_quote(implicit_ll_root() + "/batch-link.XXXXXX") + " 2>/dev/null").strip()
  if root == ""
    return nil

  workers = []
  base = ll_jobs.size() / jobs
  extra = ll_jobs.size() % jobs
  start = 0
  wi = 0
  spawn_error = nil
  worker_options = batch_parallel_worker_options()
  runtime_arg = ""
  if runtime_objs != nil
    runtime_arg = runtime_objs.to_s()
  while wi < jobs && spawn_error == nil
    count = base
    if wi < extra
      count += 1
    out_log = root + "/worker-" + wi.to_s() + ".out"
    err_log = root + "/worker-" + wi.to_s() + ".err"
    argv = [exe, "compile-batch", "--batch-link-worker", "--jobs", "1"]
    if runtime_arg != ""
      argv.push("--batch-runtime-objs")
      argv.push(runtime_arg)
    oi = 0
    while oi < worker_options.size()
      argv.push(worker_options[oi])
      oi += 1
    fi = 0
    while fi < count
      job = ll_jobs[start + fi]
      argv.push(job[:ll])
      argv.push(job[:bin])
      fi += 1
    cmd = StringBuffer(256 + count * 64)
    ai = 0
    while ai < argv.size()
      if ai > 0
        cmd << " "
      cmd << dev_runtime_shell_quote(argv[ai])
      ai += 1
    cmd << " >"
    cmd << dev_runtime_shell_quote(out_log)
    cmd << " 2>"
    cmd << dev_runtime_shell_quote(err_log)
    begin
      process = Process.spawn(["/bin/sh", "-c", cmd.to_s()])
      workers.push({process: process, out_log: out_log, err_log: err_log, start: start, count: count})
    rescue err
      spawn_error = err.to_s()
    start += count
    wi += 1

  if spawn_error != nil
    i = 0
    while i < workers.size()
      workers[i][:process].kill()
      workers[i][:process].wait()
      i += 1
    system("rm -rf " + dev_runtime_shell_quote(root))
    return {ok: false, failed: ll_jobs.size(), message: "parallel link spawn failed: " + spawn_error}

  failed = 0
  i = 0
  while i < workers.size()
    status = workers[i][:process].wait()
    if status != 0
      failed += 1
    out_log = workers[i][:out_log]
    if file?(out_log)
      out_text = read_file(out_log)
      if out_text != nil && out_text != ""
        ccall("w_print", out_text)
      ccall("__w_unlink", out_log)
    err_log = workers[i][:err_log]
    if file?(err_log)
      err_text = read_file(err_log)
      if err_text != nil && err_text != ""
        ccall("w_eputs", err_text)
      ccall("__w_unlink", err_log)
    i += 1
  system("rmdir " + dev_runtime_shell_quote(root) + " 2>/dev/null")
  {ok: failed == 0, failed: failed, message: nil}
