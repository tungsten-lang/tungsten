# cinder/driver — End-to-end Cinder `.ll` / `.w` -> `.o` -> Native Executable Driver.
#
# Compiles `.ll` IR directly to Mach-O 64 `.o` (macOS ARM64) or ELF64 `.o` (Linux x86_64 / AArch64)
# in pure Tungsten, and links executables directly with the OS linker (`ld` on macOS,
# `ld.lld` / `ld` on Linux) — ZERO `clang`, `opt`, `llc`, or `as` subprocesses!

use ./jit_mem
use ./opt_config
use ./ll_a64
use ./ll_x64
use ./lto

-> cinder_shq(s)
  "'" + s.gsub("'", "'\\''") + "'"

-> cinder_default_target
  os = cinder_host_os()
  arch = cinder_host_arch()
  if os == "macos"
    return "arm64-apple-macosx14.0.0"
  if arch == "x86_64"
    return "x86_64-unknown-linux-gnu"
  "aarch64-unknown-linux-gnu"

# Parse & validate a target triple into `[arch, os, norm_triple]` (`arch`: "arm64"|"x86_64", `os`: "macos"|"linux"),
# or print an error and return nil for unsupported architectures/OSes!
-> cinder_parse_target(target_triple)
  tgt = target_triple == "" ? cinder_default_target() : target_triple.strip().downcase()
  arch = ""
  if tgt.starts_with?("arm64") || tgt.starts_with?("aarch64")
    arch = "arm64"
  elsif tgt.starts_with?("x86_64") || tgt.starts_with?("amd64")
    arch = "x86_64"
  else
    ccall("w_eputs", "cinder: unsupported target architecture in triple: " + target_triple)
    return nil
  os = ""
  if tgt.index("apple") != nil || tgt.index("darwin") != nil || tgt.index("macos") != nil
    os = "macos"
  elsif tgt.index("linux") != nil
    os = "linux"
  else
    ccall("w_eputs", "cinder: unsupported target OS in triple: " + target_triple)
    return nil
  if arch == "x86_64" && os == "macos"
    ccall("w_eputs", "cinder: unsupported target combination (Mach-O x86_64 emitter unavailable): " + target_triple)
    return nil
  [arch, os, tgt]

# Verify executable linking is supported for the requested target triple on this host.
-> cinder_validate_exe_target(target_triple)
  pt = cinder_parse_target(target_triple)
  return nil if pt == nil
  h_os = cinder_host_os()
  h_arch = cinder_host_arch()
  h_arch = "arm64" if h_arch == "aarch64"
  if pt[0] != h_arch || pt[1] != h_os
    ccall("w_eputs", "cinder: cannot link executable for target '" + pt[2] + "' on host '" + h_arch + "-" + h_os + "' (no cross-linker/runtime available; use -c to emit an object file)")
    return nil
  pt

# Scan native `.o` / `.a` files for undefined imported symbols so LTO internalization preserves them!
-> cinder_scan_native_obj_imports(obj_paths)
  refs = {}
  return refs if obj_paths == nil || obj_paths.size() == 0
  ts = (ccall_nobox("__w_clock_ns_raw") ## i64).to_s()
  tmp_out = "/tmp/cinder_nm_u_" + ts + ".txt"
  sb = StringBuffer(128)
  sb << "nm -u"
  i = 0
  while i < obj_paths.size()
    sb << " "
    sb << cinder_shq(obj_paths[i])
    i += 1
  sb << " > " + cinder_shq(tmp_out) + " 2>/dev/null"
  system(sb.to_s())
  txt = read_file(tmp_out)
  cinder_fast_unlink(tmp_out)
  return refs if txt == nil || txt == ""
  lines = txt.split("\n")
  is_mac = cinder_host_os() == "macos"
  li = 0
  while li < lines.size()
    ln = lines[li].strip()
    if ln != "" && !ln.ends_with?(":")
      # nm -u outputs either `_sym` or `U _sym` / `                 U sym`
      parts = ln.split(" ")
      sym = parts[parts.size() - 1].strip()
      if sym != "" && sym != "U"
        refs[sym] = true
        if is_mac && sym.starts_with?("_") && cinder_blen(sym) > 1
          refs[sym.slice(1, cinder_blen(sym) - 1)] = true
    li += 1
  refs

# Compile an in-memory `.ll` IR string directly to a binary `.o` object file (`Mach-O 64` or `ELF64`).
# When `embed_lto_ir` is true (`-c -flto` / `-c --lto`), embeds the `CNDRLTO1` Fat-LTO section!
-> cinder_compile_ll_str_to_obj(src, obj_path, target_triple = "", opt_cfg = nil, embed_lto_ir = false)
  t0 = clock
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  pt = cinder_parse_target(target_triple)
  return [false, 0, 0] if pt == nil
  is_x64 = pt[0] == "x86_64"
  is_mac = pt[1] == "macos"
  ok = false
  nbytes = 0
  if is_x64
    w = cinder_compile_ll_x64(src, cfg)
    w.set_lto_ir(src) if embed_lto_ir
    b = w.build_bytes()
    nbytes = b.len
    ok = b.write_file(obj_path)
  else
    w = cinder_compile_ll_a64(src, is_mac, cfg)
    w.set_lto_ir(src) if embed_lto_ir
    tb0 = clock
    b = w.build_bytes()
    tb1 = clock
    nbytes = b.len
    ok = b.write_file(obj_path)
    tb2 = clock
    if env("CINDER_PROFILE") == "1"
      ms_bb = ((tb1 - tb0) * ~1000.0).to_i()
      ms_wf = ((tb2 - tb1) * ~1000.0).to_i()
      ccall("w_eputs", "\[cinder-profile\] macho_emit (ms): build_bytes=" + ms_bb.to_s() + " write_file=" + ms_wf.to_s() + " obj_bytes=" + nbytes.to_s())
  [ok, ((clock - t0) * ~1000.0).to_i(), nbytes]

# Compile an LLVM IR `.ll` file directly to a binary `.o` object file (`Mach-O 64` or `ELF64`).
# Returns `[ok_bool, elapsed_ms_i64, out_bytes_i64]`.
-> cinder_compile_ll_to_obj(ll_path, obj_path, target_triple = "", opt_cfg = nil)
  src = read_file(ll_path)
  if src == nil
    ccall("w_eputs", "cinder: cannot read " + ll_path)
    return [false, 0, 0]
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  cinder_compile_ll_str_to_obj(src, obj_path, target_triple, cfg, cfg.lto_enabled?())

# Inspect `.ll` text for optional Tungsten companion bridges & system libraries (matching `compiler/lib/driver/ir.w`)
-> cinder_detect_ll_link_needs(ll_text)
  needs = {
    lexchars:    ll_text.index("lchs") != nil || ll_text.index("lexchars") != nil || ll_text.index("@w_lexchar_") != nil,
    unicode:     ll_text.index("@w_string_normalize") != nil || ll_text.index("@w_string_grapheme_next") != nil || ll_text.index("@w_approx_eq") != nil || ll_text.index("@w_unicode_") != nil,
    prime:       ll_text.index("@w_prime_") != nil || ll_text.index("@w_primes_") != nil || ll_text.index("@w_bigint_prime") != nil,
    blas:        ll_text.index("@w_blas_") != nil || ll_text.index("@w_array_cos_") != nil || ll_text.index("@w_array_sin_") != nil || ll_text.index("@w_array_sqrt_") != nil || ll_text.index("@w_array_exp_") != nil || ll_text.index("@w_array_log_") != nil || ll_text.index("@w_array_tan_") != nil,
    sparse:      ll_text.index("@w_sparse_") != nil,
    bridges:     ll_text.index("@w_metal_") != nil || ll_text.index("@w_gfx_") != nil || ll_text.index("@w_hid_") != nil || ll_text.index("@w_fused_gpu_run") != nil || ll_text.index("@w_gpu_") != nil,
    quartz:      ll_text.index("@w_cg_") != nil,
    media:       ll_text.index("@w_media_") != nil,
    credentials: ll_text.index("@w_cred_") != nil,
    wtensor:     ll_text.index("@w_tensor_") != nil,
    sci_io:      ll_text.index("@w_sci_") != nil,
    zstd:        ll_text.index("@ZSTD_decompress") != nil || ll_text.index("@w_zstd_") != nil || ll_text.index("@w_slab_init_static_zstd") != nil,
    gc:          ll_text.index("@w_gc_enable(") != nil,
    dyn_exp:     env("TUNGSTEN_DYNAMIC_EXPORTS") == "1" || ll_text.index("@w_jit_load_object(") != nil,
    http2:       ll_text.index("@w_h2_") != nil || ll_text.index("@nghttp2_") != nil,
    tls:         ll_text.index("@SSL_CTX_") != nil || ll_text.index("@OPENSSL_") != nil
  }
  needs

# Locate Tungsten root directory (normalized so `loader_core_source?` matches Core paths cleanly)
-> cinder_tungsten_root
  r = env("TUNGSTEN_ROOT")
  return File.expand_path(r) if r != nil && r != ""
  return File.expand_path(".") if file?("runtime/runtime.c")
  rt = ccall("w_runtime_dir")
  return File.expand_path(rt + "/..") if rt != nil && rt != ""
  File.expand_path(".")

G_CINDER_LINK_MEMO = {}

-> cinder_fnv64_hex(s)
  h = 0xCBF29CE484222325
  n = cinder_blen(s)
  i = 0
  while i < n
    h = (h ^ (s.byte_at(i) & 0xFF)) * 0x100000001B3
    i += 1
  hex = "0123456789abcdef"
  sb = StringBuffer(16)
  sh = 60
  while sh >= 0
    sb << hex.slice((h >> sh) & 15, 1)
    sh -= 4
  sb.to_s()

-> cinder_runtime_quick_stamp(root)
  st_c = File.stat(root + "/runtime/runtime.c")
  st_h = File.stat(root + "/runtime/runtime.h")
  sig = root + "|" + (st_c != nil ? (st_c.size().to_s() + ":" + st_c.mtime_ns().to_s()) : "0") + "|" + (st_h != nil ? (st_h.size().to_s() + ":" + st_h.mtime_ns().to_s()) : "0")
  cinder_fnv64_hex(sig)

-> cinder_fast_unlink(path)
  return nil if path == nil || path == ""
  ccall("__w_unlink", path) if file?(path)
  nil

# Build (once, content-addressed) and return a tiny ~1 KB Mach-O/ELF minimal runtime `.o` providing
# `g_string_slab`, `w_preflight`, zero-copy `w_slab_init_static`, and `w_slab_freeze_safe` so pure
# literal scripts link in ~18 ms without scanning the 5 MB full `runtime-*.a` archive!
-> cinder_min_slab_rt_obj(root)
  comp_dir = cinder_comp_cache_dir(root)
  c_src = "#include <stdint.h>\n#include <stdlib.h>\n#include <unistd.h>\n#include <pthread.h>\n" +
          "typedef struct { uint8_t *base; uint32_t next_slot; uint32_t page_hwm; pthread_mutex_t lock; int frozen; uint32_t static_slots; uint8_t is_static_ro; uint8_t intern_built; } WStringSlab;\n" +
          "WStringSlab g_string_slab = {0};\n" +
          "void w_preflight(void) { const char *e = getenv(\"TUNGSTEN_PREFLIGHT\"); if (e && *e) _exit(0); }\n" +
          "void w_slab_init_static(const uint8_t *data, uint32_t total_slots) {\n" +
          "  if (g_string_slab.base) return;\n" +
          "  g_string_slab.base = (uint8_t *)(uintptr_t)data;\n" +
          "  g_string_slab.next_slot = total_slots;\n" +
          "  g_string_slab.static_slots = total_slots;\n" +
          "  g_string_slab.is_static_ro = 1;\n" +
          "}\n" +
          "uint64_t w_slab_freeze_safe(void) { g_string_slab.frozen = 1; return 0; }\n"
  min_o = comp_dir + "/cinder-minrt-v2-" + cinder_fnv64_hex(c_src) + ".o"
  return min_o if file?(min_o)
  ccall("__w_mkdir_p", comp_dir)
  ts = (ccall_nobox("__w_clock_ns_raw") ## i64).to_s()
  tmp_c = "/tmp/cinder_minrt_" + ts + ".c"
  tmp_o = min_o + ".tmp." + ts
  write_file(tmp_c, c_src)
  cc_bin = env("TUNGSTEN_CC")
  cc_bin = "cc" if cc_bin == nil || cc_bin == ""
  ok = system(cinder_shq(cc_bin) + " -O3 -c " + cinder_shq(tmp_c) + " -o " + cinder_shq(tmp_o) + " >/dev/null 2>&1 && mv -f " + cinder_shq(tmp_o) + " " + cinder_shq(min_o) + " 2>/dev/null")
  cinder_fast_unlink(tmp_c)
  cinder_fast_unlink(tmp_o)
  (ok || file?(min_o)) ? min_o : ""

-> cinder_comp_cache_dir(root)
  comp_dir = env("TUNGSTEN_CACHE_DIR")
  return comp_dir if comp_dir != nil && comp_dir != ""
  store = env("TUNGSTEN_BUILD_STORE")
  if store == nil || store == ""
    th = env("TUNGSTEN_HOME")
    if th == nil || th == ""
      hm = env("HOME")
      th = (hm != nil && hm != "") ? (hm + "/.tungsten") : (root + "/.tungsten")
    store = th + "/cache"
  store + "/compile"

# Query or load cached macOS linker & runtime archive environment in < 0.05 ms (ZERO subprocesses when warm!).
# Returns `[rt_a, ld_bin, sdk, sdk_ver, rt_lib_flags, adhoc_flag]`.
-> cinder_macos_link_env(root, needs)
  comp_dir = cinder_comp_cache_dir(root)
  dep_target = env("MACOSX_DEPLOYMENT_TARGET")
  dep_key = (dep_target != nil && dep_target != "") ? dep_target : "default"
  variant = (needs[:zstd] ? "z1" : "z0") + "_" + (needs[:gc] ? "g1" : "g0") + "_" + dep_key.gsub(".", "_") + "_" + cinder_runtime_quick_stamp(root)
  stamp_path = comp_dir + "/cinder-link-v3-" + variant + ".txt"

  mem = G_CINDER_LINK_MEMO[stamp_path]
  if mem != nil && mem[0] != "" && file?(mem[0])
    return mem

  cached_txt = read_file(stamp_path)
  if cached_txt != nil
    lines = cached_txt.split("\n")
    if lines.size() >= 6 && lines[0] != "" && file?(lines[0]) && lines[1] != ""
      rec = [lines[0], lines[1], lines[2], lines[3], lines[4], lines[5]]
      G_CINDER_LINK_MEMO[stamp_path] = rec
      return rec

  # Cold probe (runs once per build store / runtime rebuild, then persisted on disk!)
  zstd_chk = needs[:zstd] ? "ar t \"$f\" 2>/dev/null | grep -q '^slab_zstd\\.o$' && " : ""
  gc_chk = needs[:gc] ? "nm -g \"$f\" 2>/dev/null | grep -q 'w_gc_register_slow' && " : "! nm -u \"$f\" 2>/dev/null | grep -q 'w_gc_register_slow' && "
  lto_chk = "nm -g \"$f\" 2>/dev/null | grep -q 'w_bigint_alloc_hot_cold' && "
  probe_cmd = "sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/runtime-*.a 2>/dev/null); do if " + zstd_chk + gc_chk + lto_chk + "true; then tmp=$(mktemp -d); (cd \"$tmp\" && ar x \"$f\" runtime.o 2>/dev/null); if test -f \"$tmp/runtime.o\" && ! file \"$tmp/runtime.o\" | grep -qi bitcode; then rm -rf \"$tmp\"; echo \"$f\"; break; fi; rm -rf \"$tmp\"; fi; done'"
  rt_a = capture(probe_cmd).strip()
  if rt_a == ""
    warm_w = "/tmp/cinder_rt_warm_" + (ccall_nobox("__w_clock_ns_raw") ## i64).to_s() + ".w"
    warm_o = warm_w + ".bin"
    warm_src = "x = \"a\"\n"
    warm_src += "if false\n  ccall(\"w_gc_enable\")\n" if needs[:gc]
    write_file(warm_w, warm_src)
    tc = root + "/bin/tungsten-compiler"
    zflag = needs[:zstd] ? " --intern zstd" : ""
    system("TUNGSTEN_BACKEND=clang TUNGSTEN_ROOT=" + cinder_shq(root) + " " + cinder_shq(tc) + " compile --no-lto" + zflag + " " + cinder_shq(warm_w) + " -o " + cinder_shq(warm_o) + " >/dev/null 2>&1")
    cinder_fast_unlink(warm_w)
    cinder_fast_unlink(warm_o)
    cinder_fast_unlink(warm_o + ".sidemap")
    rt_a = capture(probe_cmd).strip()

  ld_bin = capture("xcrun --sdk macosx --find ld 2>/dev/null").strip()
  ld_bin = "/usr/bin/ld" if ld_bin == ""
  sdk = capture("xcrun --sdk macosx --show-sdk-path 2>/dev/null").strip()
  sdk_ver = dep_target
  if sdk_ver == nil || sdk_ver == ""
    sdk_ver = capture("xcrun --sdk macosx --show-sdk-version 2>/dev/null").strip()
  if sdk_ver == ""
    sdk_ver = capture("sw_vers -productVersion 2>/dev/null").strip()
  sdk_ver = "14.0.0" if sdk_ver == ""

  lib_sb = StringBuffer(192)
  hb = capture("brew --prefix 2>/dev/null").strip()
  if hb != "" && system("test -d " + cinder_shq(hb + "/lib"))
    lib_sb << " -L" + cinder_shq(hb + "/lib")
  if rt_a != "" && system("nm -u " + cinder_shq(rt_a) + " 2>/dev/null | grep -q '_mi_'")
    lib_sb << " -lmimalloc"
  if rt_a != "" && system("nm -u " + cinder_shq(rt_a) + " 2>/dev/null | grep -q '_SSL_'")
    ossl = capture("brew --prefix openssl@3 2>/dev/null").strip()
    if ossl != ""
      lib_sb << " -L" + cinder_shq(ossl + "/lib") + " -lssl -lcrypto"
  if rt_a != "" && system("nm -u " + cinder_shq(rt_a) + " 2>/dev/null | grep -q '_nghttp2_'")
    ngh = capture("brew --prefix libnghttp2 2>/dev/null").strip()
    lib_sb << (ngh != "" ? (" -L" + cinder_shq(ngh + "/lib") + " -lnghttp2") : " -lnghttp2")
  if needs[:zstd] || (rt_a != "" && system("nm -u " + cinder_shq(rt_a) + " 2>/dev/null | grep -q '_ZSTD_'"))
    zst = capture("brew --prefix zstd 2>/dev/null").strip()
    lib_sb << (zst != "" ? (" -L" + cinder_shq(zst + "/lib") + " -lzstd") : " -lzstd")

  adhoc_flag = system(cinder_shq(ld_bin) + " -adhoc_codesign -v >/dev/null 2>&1") ? " -adhoc_codesign" : ""
  rec = [rt_a, ld_bin, sdk, sdk_ver, lib_sb.to_s(), adhoc_flag]
  if rt_a != ""
    write_file(stamp_path, rec[0] + "\n" + rec[1] + "\n" + rec[2] + "\n" + rec[3] + "\n" + rec[4] + "\n" + rec[5] + "\n")
    G_CINDER_LINK_MEMO[stamp_path] = rec
  rec

-> cinder_find_or_build_companion(comp_dir, root, needs, glob_pat, rel_src, extra_cflags)
  hit = capture("sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/" + glob_pat + " 2>/dev/null); do if ! file \"$f\" | grep -qi bitcode; then echo \"$f\"; break; fi; done'").strip()
  return hit if hit != ""
  src_full = root + "/runtime/" + rel_src
  return "" if !file?(src_full)
  out_c = comp_dir + "/cinder-comp-" + cinder_fnv64_hex(rel_src + "|" + extra_cflags + "|" + cinder_runtime_quick_stamp(root)) + ".o"
  return out_c if file?(out_c)
  cc_b = env("TUNGSTEN_CC")
  cc_b = "cc" if cc_b == nil || cc_b == ""
  gc_d = needs[:gc] ? "" : " -DW_COMPILE_NO_GC"
  ok_c = system(cinder_shq(cc_b) + " -O3 -DNDEBUG" + gc_d + " -I" + cinder_shq(root + "/runtime") + " " + extra_cflags + " -c " + cinder_shq(src_full) + " -o " + cinder_shq(out_c))
  ok_c ? out_c : ""

# Locate or query prebuilt runtime archive (`runtime.a`) and companion `.o`s in the Tungsten build store!
-> cinder_find_runtime_objects(root, needs)
  comp_dir = cinder_comp_cache_dir(root)
  is_mac = cinder_host_os() == "macos"
  rt_a = ""
  if is_mac
    rt_a = cinder_macos_link_env(root, needs)[0]
  else
    zstd_chk = needs[:zstd] ? "ar t \"$f\" 2>/dev/null | grep -q '^slab_zstd\\.o$' && " : ""
    gc_chk = needs[:gc] ? "nm -g \"$f\" 2>/dev/null | grep -q 'w_gc_register_slow' && " : "! nm -u \"$f\" 2>/dev/null | grep -q 'w_gc_register_slow' && "
    lto_chk = "nm -g \"$f\" 2>/dev/null | grep -q 'w_bigint_alloc_hot_cold' && "
    probe_cmd = "sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/runtime-*.a 2>/dev/null); do if " + zstd_chk + gc_chk + lto_chk + "true; then tmp=$(mktemp -d); (cd \"$tmp\" && ar x \"$f\" runtime.o 2>/dev/null); if test -f \"$tmp/runtime.o\" && ! file \"$tmp/runtime.o\" | grep -qi bitcode; then rm -rf \"$tmp\"; echo \"$f\"; break; fi; rm -rf \"$tmp\"; fi; done'"
    rt_a = capture(probe_cmd).strip()

  need_lex_warm = needs[:lexchars] && capture("ls -t " + cinder_shq(comp_dir) + "/companion-*lexchar*.o 2>/dev/null | head -n 1").strip() == ""
  need_uni_warm = needs[:unicode]  && capture("ls -t " + cinder_shq(comp_dir) + "/companion-*unicode*.o 2>/dev/null | head -n 1").strip() == ""
  need_prm_warm = needs[:prime]    && capture("ls -t " + cinder_shq(comp_dir) + "/companion-*ssmr*.o 2>/dev/null | head -n 1").strip() == ""
  if rt_a == "" || need_lex_warm || need_uni_warm || need_prm_warm
    # Warm the native runtime archive and any needed companion `.o`s once via `tungsten-compiler`
    warm_w = "/tmp/cinder_rt_warm_" + (ccall_nobox("__w_clock_ns_raw") ## i64).to_s() + ".w"
    warm_o = warm_w + ".bin"
    warm_src = "x = \"a\"\n"
    warm_src += "y = x.lchs()\n" if needs[:lexchars]
    warm_src += "z = ccall(\"w_string_normalize\", x, :nfc)\n" if needs[:unicode]
    warm_src += "p = 7.prime?()\n" if needs[:prime]
    warm_src += "if false\n  ccall(\"w_gc_enable\")\n" if needs[:gc]
    write_file(warm_w, warm_src)
    tc = root + "/bin/tungsten-compiler"
    zflag = needs[:zstd] ? " --intern zstd" : ""
    system("TUNGSTEN_BACKEND=clang TUNGSTEN_ROOT=" + cinder_shq(root) + " " + cinder_shq(tc) + " compile --no-lto" + zflag + " " + cinder_shq(warm_w) + " -o " + cinder_shq(warm_o) + " >/dev/null 2>&1")
    cinder_fast_unlink(warm_w)
    cinder_fast_unlink(warm_o)
    cinder_fast_unlink(warm_o + ".sidemap")
    if rt_a == ""
      rt_a = is_mac ? cinder_macos_link_env(root, needs)[0] : capture(probe_cmd).strip()

  companions = []
  if needs[:lexchars]
    c_lex = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*lexchar*.o", "lexchar_tables.c", "")
    companions.push(c_lex) if c_lex != ""
  if needs[:unicode]
    c_uni = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*unicode*.o", "unicode_tables.c", "")
    companions.push(c_uni) if c_uni != ""
  if needs[:prime]
    c_prm = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*ssmr*.o", "ssmr_witness.c", "")
    companions.push(c_prm) if c_prm != ""
  if needs[:blas]
    c_bls = is_mac ? cinder_find_or_build_companion(comp_dir, root, needs, "companion-*blas*.o", "blas_bridge.c", "-fno-finite-math-only") : cinder_find_or_build_companion(comp_dir, root, needs, "companion-*openblas*.o", "openblas_bridge.c", "")
    companions.push(c_bls) if c_bls != ""
  if needs[:sparse] && is_mac
    c_spr = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*sparse*.o", "sparse_bridge.c", "")
    companions.push(c_spr) if c_spr != ""
  if needs[:wtensor]
    c_ten = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*tensor*.o", "tensor_bridge.c", "")
    companions.push(c_ten) if c_ten != ""
  if needs[:sci_io]
    c_sci = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*sci_io*.o", "sci_io_native.c", "")
    companions.push(c_sci) if c_sci != ""
  if needs[:quartz]
    c_qtz = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*quartz*.o", "quartz.c", "")
    companions.push(c_qtz) if c_qtz != ""
  if needs[:bridges] && is_mac
    c_mtl = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*metal*.o", "metal.m", "")
    c_gfx = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*graphics*.o", "graphics.m", "")
    c_hid = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*hid_bridge*.o", "hid_bridge.m", "")
    companions.push(c_mtl) if c_mtl != ""
    companions.push(c_gfx) if c_gfx != ""
    companions.push(c_hid) if c_hid != ""
  if needs[:media]
    c_med = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*media_c*.o", "media/media.c", "")
    companions.push(c_med) if c_med != ""
    if is_mac
      c_avf = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*media_avf*.o", "media/media_avf.m", "")
      c_sys = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*media_sysdec*.o", "media/media_sysdec.m", "")
      companions.push(c_avf) if c_avf != ""
      companions.push(c_sys) if c_sys != ""
  if needs[:credentials] && is_mac
    c_crd = cinder_find_or_build_companion(comp_dir, root, needs, "companion-*credentials*.o", "credentials.m", "")
    companions.push(c_crd) if c_crd != ""

  [rt_a, companions]

# Link a Mach-O `.o` file directly into a macOS ARM64 executable using Apple `ld` (ZERO `clang`, ZERO warm probes!)
-> cinder_link_macho(obj_path, out_path, rt_archive, companions, needs, extra_link_args = "", opt_cfg = nil)
  root = cinder_tungsten_root()
  lenv = cinder_macos_link_env(root, needs)
  ld_bin = lenv[1]
  sdk = lenv[2]
  sdk_ver = lenv[3]
  rt_lib_flags = lenv[4]
  adhoc_flag = lenv[5]

  cmd = StringBuffer(512)
  cmd << cinder_shq(ld_bin)
  cmd << " -arch arm64 -platform_version macos " + sdk_ver + " " + sdk_ver
  if sdk != ""
    cmd << " -syslibroot "
    cmd << cinder_shq(sdk)
  cmd << " -dead_strip -dead_strip_dylibs -stack_size 0x8000000"
  cmd << adhoc_flag
  cmd << (needs[:dyn_exp] ? " -export_dynamic" : " -exported_symbol _main")
  cmd << " "
  cmd << cinder_shq(obj_path)
  ci = 0
  while ci < companions.size()
    cmd << " "
    cmd << cinder_shq(companions[ci])
    ci += 1
  if rt_archive != ""
    cmd << " "
    cmd << cinder_shq(rt_archive)
  if extra_link_args != ""
    cmd << " "
    cmd << extra_link_args
  if needs[:bridges]
    cmd << " -framework Metal -framework Foundation -framework AppKit -framework QuartzCore -framework CoreGraphics -framework CoreVideo -framework IOKit -framework CoreFoundation -lobjc"
  if needs[:blas] || needs[:sparse]
    cmd << " -framework Accelerate"
  if needs[:quartz]
    cmd << " -framework CoreGraphics -framework CoreText -framework ImageIO -framework CoreFoundation"
  if needs[:credentials]
    cmd << " -framework Foundation -framework Security -framework CoreFoundation -lobjc"
  if needs[:media]
    cmd << " -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework AVFoundation -framework AVFAudio -framework AudioToolbox -framework Foundation -framework CoreFoundation -lobjc"
  cmd << rt_lib_flags
  cmd << " -lSystem -o "
  cmd << cinder_shq(out_path)
  ok = system(cmd.to_s())
  if ok && adhoc_flag == ""
    system("codesign --force -s - " + cinder_shq(out_path) + " >/dev/null 2>&1")
  ok

# Link an ELF64 `.o` file directly into a Linux executable using `ld.lld` / `ld` (ZERO `clang` or `gcc`!)
-> cinder_link_elf(obj_path, out_path, rt_archive, companions, needs, extra_link_args = "", opt_cfg = nil)
  ld_bin = capture("command -v ld.lld || command -v ld 2>/dev/null").strip()
  arch = cinder_host_arch()
  multi = arch == "x86_64" ? "x86_64-linux-gnu" : "aarch64-linux-gnu"
  dyn_ld = arch == "x86_64" ? "/lib64/ld-linux-x86-64.so.2" : "/lib/ld-linux-aarch64.so.1"

  lib_dir = "/usr/lib/" + multi
  if !system("test -f " + cinder_shq(lib_dir + "/crti.o"))
    lib_dir = "/usr/lib64"
  scrt1 = system("test -f " + cinder_shq(lib_dir + "/Scrt1.o")) ? (lib_dir + "/Scrt1.o") : (lib_dir + "/crt1.o")
  crti  = lib_dir + "/crti.o"
  crtn  = lib_dir + "/crtn.o"
  is_pie = scrt1.ends_with?("Scrt1.o")

  cmd = StringBuffer(512)
  cmd << cinder_shq(ld_bin)
  cmd << (is_pie ? " -pie" : "")
  cmd << " --eh-frame-hdr -dynamic-linker "
  cmd << cinder_shq(dyn_ld)
  cmd << " -z stack-size=134217728 --gc-sections "
  if (opt_cfg != nil && !opt_cfg.debug) || env("CINDER_DETERMINISTIC") == "1"
    cmd << "--build-id=none "
  cmd << "--export-dynamic " if needs[:dyn_exp]
  cmd << cinder_shq(scrt1) + " " + cinder_shq(crti) + " "
  cmd << cinder_shq(obj_path)
  ci = 0
  while ci < companions.size()
    cmd << " " + cinder_shq(companions[ci])
    ci += 1
  if rt_archive != ""
    cmd << " " + cinder_shq(rt_archive)
  if extra_link_args != ""
    cmd << " " + extra_link_args
  cmd << " -L" + cinder_shq(lib_dir) + " -L/lib/" + multi + " -L/usr/local/lib"
  if rt_archive != "" && system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q 'mi_'")
    cmd << " -lmimalloc"
  if rt_archive != "" && system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q 'SSL_'")
    cmd << " -lssl -lcrypto"
  if rt_archive != "" && system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q 'nghttp2_'")
    cmd << " -lnghttp2"
  if needs[:zstd] || (rt_archive != "" && system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q 'ZSTD_'"))
    cmd << " -lzstd"
  if needs[:blas]
    cmd << " -lopenblas"
  libgcc = capture("clang -print-libgcc-file-name 2>/dev/null || cc -print-libgcc-file-name 2>/dev/null").strip()
  if libgcc == "" || !system("test -f " + cinder_shq(libgcc))
    libgcc = capture("find /usr/lib/gcc -name libgcc.a 2>/dev/null | head -n 1").strip()
  cmd << " -lm -lpthread -ldl -lc "
  if libgcc != ""
    cmd << cinder_shq(libgcc) + " -lc "
  cmd << cinder_shq(crtn)
  cmd << " -o " + cinder_shq(out_path)
  system(cmd.to_s())

# Link an in-memory `.ll` module string all the way to a native executable via Cinder `.o` + OS `ld`!
-> cinder_link_ll_str_to_exe(src, label_for_err, out_path, explicit_rt_objs = "", verbose = false, opt_cfg = nil, target_triple = "", external_refs = nil)
  t0 = clock
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  return false if cinder_validate_exe_target(target_triple) == nil
  root = cinder_tungsten_root()

  # When LTO is enabled (`--lto` / `-flto` / `--full-lto`), merge any C includes and the cached
  # runtime hot-boundary Fat-LTO object (`cinder-rt-lto-v1.o`), and run Whole-Program Internalization!
  eff_src = src
  extra_native_args = explicit_rt_objs
  tmp_c_objs = []
  c_inc_raw = env("TUNGSTEN_C_INCLUDES")
  lto_mods = [src]
  needs_pre = cinder_detect_ll_link_needs(src)

  if c_inc_raw != nil && c_inc_raw != ""
    c_parts = c_inc_raw.split(":")
    cpi = 0
    while cpi < c_parts.size()
      cp = c_parts[cpi].strip()
      if cp != ""
        if cp.ends_with?(".c")
          cc_bin = env("TUNGSTEN_CC")
          cc_bin = "cc" if cc_bin == nil || cc_bin == ""
          gc_def = needs_pre[:gc] ? "" : " -DW_COMPILE_NO_GC"
          merged_c_ok = false
          if cfg.lto_enabled?()
            c_ll = out_path + ".cinc" + cpi.to_s() + ".ll"
            ll_cmd = cinder_shq(cc_bin) + " -O2 -fno-vectorize -fno-slp-vectorize -DNDEBUG" + gc_def + " -I" + cinder_shq(root + "/runtime") + " -S -emit-llvm " + cinder_shq(cp) + " -o " + cinder_shq(c_ll) + " 2>/dev/null"
            if system(ll_cmd)
              c_ir = read_file(c_ll)
              cinder_fast_unlink(c_ll)
              # Merge C `.ll` directly when within Cinder's clean scalar/struct subset (no inline vector shuffle / landingpad)
              if c_ir != nil && c_ir.index("shufflevector ") == nil && c_ir.index("landingpad ") == nil && c_ir.index("getelementptr inbounds (") == nil
                lto_mods.push(c_ir)
                merged_c_ok = true
            cinder_fast_unlink(c_ll)
          if !merged_c_ok
            c_obj = out_path + ".cinc" + cpi.to_s() + ".o"
            cc_cmd = cinder_shq(cc_bin) + " -O3 -DNDEBUG" + gc_def + " -I" + cinder_shq(root + "/runtime") + " -c " + cinder_shq(cp) + " -o " + cinder_shq(c_obj)
            if !system(cc_cmd)
              ccall("w_eputs", "cinder: failed to compile TUNGSTEN_C_INCLUDES entry " + cp)
              return false
            tmp_c_objs.push(c_obj)
            extra_native_args = (extra_native_args == "" ? "" : (extra_native_args + " ")) + cinder_shq(c_obj)
        elsif cp.ends_with?(".m")
          c_obj = out_path + ".cinc" + cpi.to_s() + ".o"
          gc_def = needs_pre[:gc] ? "" : " -DW_COMPILE_NO_GC"
          cc_bin = env("TUNGSTEN_CC")
          cc_bin = "cc" if cc_bin == nil || cc_bin == ""
          cc_cmd = cinder_shq(cc_bin) + " -O3 -DNDEBUG" + gc_def + " -I" + cinder_shq(root + "/runtime") + " -c " + cinder_shq(cp) + " -o " + cinder_shq(c_obj)
          if !system(cc_cmd)
            ccall("w_eputs", "cinder: failed to compile TUNGSTEN_C_INCLUDES entry " + cp)
            return false
          tmp_c_objs.push(c_obj)
          extra_native_args = (extra_native_args == "" ? "" : (extra_native_args + " ")) + cinder_shq(c_obj)
        elsif cfg.lto_enabled?() && cp.ends_with?(".o")
          emb_ir = cinder_extract_lto_from_file(cp)
          if emb_ir != nil
            lto_mods.push(emb_ir)
          else
            extra_native_args = (extra_native_args == "" ? "" : (extra_native_args + " ")) + cinder_shq(cp)
        else
          extra_native_args = (extra_native_args == "" ? "" : (extra_native_args + " ")) + cinder_shq(cp)
      cpi += 1

  prof = env("CINDER_PROFILE") == "1"
  t_lto0 = clock
  if cfg.lto_enabled?()
    if cinder_ll_needs_rt_hot_lto?(src) && src.index("define i64 @w_bigint_alloc_hot(") == nil
      rt_hot_o = cinder_ensure_rt_hot_lto_obj(root)
      rt_hot_ir = rt_hot_o != "" ? cinder_extract_lto_from_file(rt_hot_o) : cinder_runtime_hot_lto_ir()
      lto_mods.push(rt_hot_ir) if rt_hot_ir != nil
    all_ext_refs = external_refs
    if tmp_c_objs.size() > 0
      c_refs = cinder_scan_native_obj_imports(tmp_c_objs)
      if all_ext_refs == nil
        all_ext_refs = c_refs
      else
        c_refs.keys.each ->(ck) all_ext_refs[ck] = true
    eff_src = cinder_lto_merge_modules(lto_mods, true, cfg, all_ext_refs)
  elsif lto_mods.size() > 1
    eff_src = cinder_lto_merge_modules(lto_mods, false, cfg, external_refs)
  t_lto1 = clock

  needs = cinder_detect_ll_link_needs(eff_src)
  obj_path = out_path + ".cinder.o"
  is_mac = cinder_host_os() == "macos"
  is_x64 = cinder_host_arch() == "x86_64"

  ok_obj = false
  if is_x64
    ok_obj = cinder_compile_ll_x64(eff_src, cfg).write_file(obj_path)
  else
    w = cinder_compile_ll_a64(eff_src, is_mac, cfg)
    tb0 = clock
    bb_o = w.build_bytes()
    tb1 = clock
    ok_obj = bb_o.write_file(obj_path)
    tb2 = clock
    if prof
      ms_lm = ((t_lto1 - t_lto0) * ~1000.0).to_i()
      ms_bb = ((tb1 - tb0) * ~1000.0).to_i()
      ms_wf = ((tb2 - tb1) * ~1000.0).to_i()
      ccall("w_eputs", "\[cinder-profile\] macho_emit (ms): lto_merge=" + ms_lm.to_s() + " build_bytes=" + ms_bb.to_s() + " write_file=" + ms_wf.to_s() + " obj_bytes=" + bb_o.len.to_s())
  if !ok_obj
    ccall("w_eputs", "cinder: object emission failed for " + label_for_err)
    return false

  t_codegen = clock
  rt_pair = cinder_find_runtime_objects(root, needs)
  t_rt = clock
  rt_a = rt_pair[0]
  comps = rt_pair[1]

  ok_ld = is_mac ? cinder_link_macho(obj_path, out_path, rt_a, comps, needs, extra_native_args, cfg) : cinder_link_elf(obj_path, out_path, rt_a, comps, needs, extra_native_args, cfg)
  tci = 0
  while tci < tmp_c_objs.size()
    cinder_fast_unlink(tmp_c_objs[tci])
    tci += 1
  cinder_fast_unlink(obj_path) if ok_ld && env("CINDER_KEEP_OBJ") != "1"
  t_end = clock
  if prof
    ms_frt = ((t_rt - t_codegen) * ~1000.0).to_i()
    ms_old = ((t_end - t_rt) * ~1000.0).to_i()
    ccall("w_eputs", "\[cinder-profile\] link (ms): find_rt=" + ms_frt.to_s() + " os_ld=" + ms_old.to_s())
  if verbose
    cg_ms = ((t_codegen - t0) * ~1000.0).to_i()
    ld_ms = ((t_end - t_codegen) * ~1000.0).to_i()
    << "  cinder codegen: " + cg_ms.to_s() + " ms | ld: " + ld_ms.to_s() + " ms (" + cfg.summary() + ")"
  ok_ld

# Build (once, content-addressed) and return a cached Fat-LTO `.o` (`cinder-rt-lto-v1-<hash>.o` in `<store>/compile/`)
# containing the hot BigInt allocator/release/finisher inlineable boundaries!
-> cinder_ensure_rt_hot_lto_obj(root)
  comp_dir = cinder_comp_cache_dir(root)
  ir_txt = cinder_runtime_hot_lto_ir()
  obj_path = comp_dir + "/cinder-rt-lto-v1-" + cinder_fnv64_hex(ir_txt + "|" + cinder_default_target()) + ".o"
  return obj_path if file?(obj_path)
  ccall("__w_mkdir_p", comp_dir)
  tmp_o = obj_path + ".tmp." + (ccall_nobox("__w_clock_ns_raw") ## i64).to_s()
  cfg_lto = CinderOptConfig.new(2)
  cfg_lto.lto_mode = :thin
  res = cinder_compile_ll_str_to_obj(ir_txt, tmp_o, "", cfg_lto, true)
  if res[0] && system("mv -f " + cinder_shq(tmp_o) + " " + cinder_shq(obj_path) + " 2>/dev/null")
    return obj_path
  cinder_fast_unlink(tmp_o)
  file?(obj_path) ? obj_path : ""

# Link a `.ll` file all the way to a native executable via Cinder `.o` + OS `ld`!
-> cinder_link_ll_to_exe(ll_path, out_path, explicit_rt_objs = "", verbose = false, opt_cfg = nil, target_triple = "")
  return false if cinder_validate_exe_target(target_triple) == nil
  src = read_file(ll_path)
  if src == nil
    ccall("w_eputs", "cinder: cannot read " + ll_path)
    return false
  cinder_link_ll_str_to_exe(src, ll_path, out_path, explicit_rt_objs, verbose, opt_cfg, target_triple, nil)

# Build frontend flags for `tungsten-compiler compile --emit-ll` from `CinderOptConfig`.
-> cinder_frontend_flags(cfg, target_triple = "")
  sb = StringBuffer(128)
  if target_triple != ""
    sb << " --target "
    sb << cinder_shq(target_triple)
  if cfg != nil
    sb << " --fast" if cfg.fast_math
    sb << " --strict-math" if cfg.strict_math
    if cfg.debug
      sb << " --debug"
    else
      sb << " --no-debug"
    sb << " --frame-pointers" if cfg.frame_pointers
  sb.to_s()

# Direct pure-Tungsten fast-path compiler for straight-line literal `.w` scripts (e.g. `<< "hello world"`):
#   - Parses `<< <literal>` scripts in < 0.05 ms without spawning `tungsten-compiler`.
#   - Packs all 6..61B interned string literals into a genuine 32B-slot `@__static_slab` inside
#     `__TEXT,__const` (Mach-O) / `.rodata` (ELF64) so the OS kernel mmaps it read-only from disk.
#   - Emits native `main` calling `w_preflight()`, `w_slab_init_static(@__static_slab, N)`,
#     `w_slab_freeze_safe()`, and `puts(...)` directly from `@__static_slab`.
# Returns `:ok`, `:err`, or `:fallback` (when script uses variables/calls/classes/imports/etc.).
-> cinder_try_fast_script_w(in_path, out_path, emit_obj_only, target_triple, verbose, cfg)
  return :fallback if cfg.debug || (emit_obj_only && cfg.lto_enabled?()) || env("CINDER_NO_FAST_W") == "1"
  c_inc = env("TUNGSTEN_C_INCLUDES")
  return :fallback if c_inc != nil && c_inc != ""
  w_src = read_file(in_path)
  return :fallback if w_src == nil

  t0 = (ccall_nobox("__w_clock_ns_raw") ## i64)
  out_strs = []
  n_bytes = cinder_blen(w_src)
  pos = 0
  while pos < n_bytes
    nl = pos
    while nl < n_bytes && w_src.byte_at(nl) != 10
      nl += 1
    raw_ln = w_src.slice(pos, nl - pos)
    pos = nl + 1
    # Reject indented blocks (methods, ifs, loops) immediately
    if cinder_blen(raw_ln) > 0 && (raw_ln.byte_at(0) == 32 || raw_ln.byte_at(0) == 9)
      if raw_ln.strip() != "" && !raw_ln.strip().starts_with?("#")
        return :fallback
    ln = raw_ln.strip()
    next if ln == "" || ln.starts_with?("#")
    return :fallback if !ln.starts_with?("<<")
    after = ln.slice(2, cinder_blen(ln) - 2)
    return :fallback if cinder_blen(after) > 0 && after.byte_at(0) != 32 && after.byte_at(0) != 9
    expr = after.strip()
    c_idx = ll_index_outside_quotes(expr, 35, 0)
    expr = expr.slice(0, c_idx).strip() if c_idx >= 0
    return :fallback if expr == ""

    elen = cinder_blen(expr)
    if expr.starts_with?("\"") && expr.ends_with?("\"") && elen >= 2
      sb = StringBuffer(elen)
      ei = 1
      lim = elen - 1
      while ei < lim
        b = expr.byte_at(ei)
        return :fallback if b == 34 || b == 91
        if b == 35 && ei + 1 < lim && expr.byte_at(ei + 1) == 123
          return :fallback
        if b == 92
          return :fallback if ei + 1 >= lim
          nb = expr.byte_at(ei + 1)
          if nb == 110
            sb << "\n"
          elsif nb == 116
            sb << "\t"
          elsif nb == 114
            sb << "\r"
          elsif nb == 92
            sb << "\\"
          elsif nb == 34
            sb << "\""
          elsif nb == 91
            sb << "\["
          else
            return :fallback
          ei += 2
        else
          sb << expr.slice(ei, 1)
          ei += 1
      out_strs.push(sb.to_s())
    elsif expr == "true" || expr == "false"
      out_strs.push(expr)
    elsif expr == "nil"
      out_strs.push("")
    else
      # Signed decimal integer literal (`123`, `-42`, `1_000_000`)
      di = 0
      neg = false
      if expr.byte_at(0) == 45
        neg = true
        di = 1
      return :fallback if di >= elen || elen > 16
      acc = 0
      digits = 0
      while di < elen
        db = expr.byte_at(di)
        if db == 95
          return :fallback if digits == 0 || di + 1 >= elen
        elsif db >= 48 && db <= 57
          acc = acc * 10 + (db - 48)
          digits += 1
        else
          return :fallback
        di += 1
      return :fallback if digits == 0
      out_strs.push((neg ? (0 - acc) : acc).to_s())

  pt = emit_obj_only ? cinder_parse_target(target_triple) : cinder_validate_exe_target(target_triple)
  return :err if pt == nil
  is_x64 = pt[0] == "x86_64"
  is_mac = pt[1] == "macos"
  writer = is_x64 ? Elf64Writer.new(ELF_EM_X86_64) : (is_mac ? MachO64Writer.new() : Elf64Writer.new(ELF_EM_AARCH64))

  slab_strs = []
  slab_slot_by_str = {}
  oi = 0
  while oi < out_strs.size()
    s = out_strs[oi]
    bl = cinder_blen(s)
    if bl >= 6 && bl <= 61 && slab_slot_by_str[s] == nil
      slab_slot_by_str[s] = -1
      slab_strs.push(s)
    oi += 1

  slab_res = cinder_emit_static_slab(writer, is_mac && !is_x64, slab_strs)
  total_slots = slab_res[0]
  si = 0
  while si < slab_strs.size()
    slab_slot_by_str[slab_strs[si]] = slab_res[1][si]
    si += 1

  # Emit C strings in `.rodata` / `__TEXT,__const` for `< 6` or `> 61` byte strings
  cstr_sym_by_idx = {}
  oi = 0
  while oi < out_strs.size()
    s = out_strs[oi]
    bl = cinder_blen(s)
    if bl < 6 || bl > 61
      csym = ".cstr.hw." + oi.to_s()
      off = writer.rodata.len
      writer.rodata.put_ascii(s)
      writer.rodata.put_u8(0)
      if is_mac && !is_x64
        writer.define_sym(csym, MSEC_CONST, off, MSYM_LOCAL)
      else
        writer.define_sym(csym, ESEC_RODATA, off, bl + 1, ESYM_LOCAL, ESTT_OBJECT)
      cstr_sym_by_idx[oi] = csym
    oi += 1

  if is_x64
    ax = CinderX64.new(256)
    ax.push_r(X64_RBP)
    ax.mov_rr(X64_RBP, X64_RSP)
    ax.call_sym("w_preflight")
    if total_slots > 1
      ax.addr_sym_local(X64_RDI, "__static_slab", 0)
      ax.mov_imm64(X64_RSI, total_slots)
      ax.call_sym("w_slab_init_static")
      ax.call_sym("w_slab_freeze_safe")
    oi = 0
    while oi < out_strs.size()
      s = out_strs[oi]
      sl = slab_slot_by_str[s]
      if sl != nil
        ax.addr_sym_local(X64_RDI, "__static_slab", sl * 32 + 2)
      else
        ax.addr_sym_local(X64_RDI, cstr_sym_by_idx[oi], 0)
      ax.call_sym("puts")
      oi += 1
    ax.mov_imm64(X64_RAX, 0)
    ax.pop_r(X64_RBP)
    ax.ret()
    writer.text.align_to(16, 0x90)
    writer.text.put_buf(ax.buf)
    writer.define_sym("main", ESEC_TEXT, 0, ax.byte_len(), ESYM_GLOBAL, ESTT_FUNC)
    ri = 0
    while ri < ax.rel_off.size()
      writer.add_text_reloc(ax.rel_off[ri], ax.rel_sym[ri], ax.rel_kind[ri], ax.rel_add[ri])
      ri += 1
  else
    aa = CinderA64.new(256)
    aa.stp_pre(29, 30, R_SP, -16)
    aa.mov_sp(29, R_SP)
    aa.bl_sym(is_mac ? "_w_preflight" : "w_preflight")
    if total_slots > 1
      aa.addr_sym_local(R_X0, "__static_slab", 0)
      aa.mov_imm64(R_X1, total_slots)
      aa.bl_sym(is_mac ? "_w_slab_init_static" : "w_slab_init_static")
      aa.bl_sym(is_mac ? "_w_slab_freeze_safe" : "w_slab_freeze_safe")
    oi = 0
    while oi < out_strs.size()
      s = out_strs[oi]
      sl = slab_slot_by_str[s]
      if sl != nil
        aa.addr_sym_local(R_X0, "__static_slab", sl * 32 + 2)
      else
        aa.addr_sym_local(R_X0, cstr_sym_by_idx[oi], 0)
      aa.bl_sym(is_mac ? "_puts" : "puts")
      oi += 1
    aa.movz_x(R_X0, 0)
    aa.ldp_post(29, 30, R_SP, 16)
    aa.ret()
    writer.text.align_to(8, 0)
    writer.text.put_buf(aa.buf)
    if is_mac
      writer.define_sym("main", MSEC_TEXT, 0, MSYM_GLOBAL)
    else
      writer.define_sym("main", ESEC_TEXT, 0, aa.byte_len(), ESYM_GLOBAL, ESTT_FUNC)
    ri = 0
    while ri < aa.rel_off.size()
      rk = aa.rel_kind[ri]
      if is_mac
        if rk == CREL_A64_BRANCH26
          writer.add_text_reloc_raw(aa.rel_off[ri], aa.rel_sym[ri], rk, aa.rel_add[ri])
        else
          writer.add_text_reloc(aa.rel_off[ri], aa.rel_sym[ri], rk, aa.rel_add[ri])
      else
        writer.add_text_reloc(aa.rel_off[ri], aa.rel_sym[ri], rk, aa.rel_add[ri])
      ri += 1

  if emit_obj_only
    b = writer.build_bytes()
    ok_o = b.write_file(out_path)
    t1 = (ccall_nobox("__w_clock_ns_raw") ## i64)
    if verbose && ok_o
      << "  cinder emitted " + b.len.to_s() + " bytes to " + out_path + " in " + ((t1 - t0) / 1000000).to_s() + " ms (" + cfg.summary() + ")"
    return ok_o ? :ok : :err

  obj_path = out_path + ".cinder.o"
  if !writer.write_file(obj_path)
    return :err
  t_cg = (ccall_nobox("__w_clock_ns_raw") ## i64)
  needs = {
    lexchars: false, unicode: false, prime: false, blas: false, sparse: false,
    wtensor: false, sci_io: false, zstd: false, gc: false,
    dyn_exp: env("TUNGSTEN_DYNAMIC_EXPORTS") == "1", http2: false, tls: false
  }
  root = cinder_tungsten_root()
  ok_ld = false
  if cinder_host_os() == "macos" && !needs[:dyn_exp]
    lenv = cinder_macos_link_env(root, needs)
    min_o = cinder_min_slab_rt_obj(root)
    if min_o != ""
      ld_cmd = StringBuffer(384)
      ld_cmd << cinder_shq(lenv[1])
      ld_cmd << " -arch arm64 -platform_version macos " + lenv[3] + " " + lenv[3]
      if lenv[2] != ""
        ld_cmd << " -syslibroot " + cinder_shq(lenv[2])
      ld_cmd << " -dead_strip" + lenv[5] + " -exported_symbol _main "
      ld_cmd << cinder_shq(obj_path) + " " + cinder_shq(min_o)
      ld_cmd << " -lSystem -o " + cinder_shq(out_path)
      ok_ld = system(ld_cmd.to_s())
      if ok_ld && lenv[5] == ""
        system("codesign --force -s - " + cinder_shq(out_path) + " >/dev/null 2>&1")
    else
      rt_pair = cinder_find_runtime_objects(root, needs)
      ok_ld = cinder_link_macho(obj_path, out_path, rt_pair[0], rt_pair[1], needs, "", cfg)
  else
    rt_pair = cinder_find_runtime_objects(root, needs)
    ok_ld = (cinder_host_os() == "macos") ? cinder_link_macho(obj_path, out_path, rt_pair[0], rt_pair[1], needs, "", cfg) : cinder_link_elf(obj_path, out_path, rt_pair[0], rt_pair[1], needs, "", cfg)
  cinder_fast_unlink(obj_path) if ok_ld && env("CINDER_KEEP_OBJ") != "1"
  t_end = (ccall_nobox("__w_clock_ns_raw") ## i64)
  if verbose && ok_ld
    << "  cinder direct codegen: " + ((t_cg - t0) / 1000000).to_s() + " ms | ld: " + ((t_end - t_cg) / 1000000).to_s() + " ms (" + cfg.summary() + ")"
  ok_ld ? :ok : :err

# Lower a single `.w`, `.ll`, `.c`, Fat-LTO `.o`/`.clto`, or `.a` input into LTO IR modules
# and/or native object paths!
-> cinder_collect_input_unit(p, idx, scratch_prefix, target_triple, cfg, root, lto_irs, native_objs, temp_files)
  if p.ends_with?(".ll")
    ir = read_file(p)
    if ir == nil
      ccall("w_eputs", "cinder: cannot read " + p)
      return false
    lto_irs.push(ir)
    return true

  if p.ends_with?(".w")
    tc = root + "/bin/tungsten-compiler"
    tmp_ll = scratch_prefix + ".u" + idx.to_s() + ".ll"
    fe_flags = cinder_frontend_flags(cfg, target_triple)
    cmd = "TUNGSTEN_LL_PATH=" + cinder_shq(tmp_ll) + " BIT_HOME=" + cinder_shq(root + "/bits") + " TUNGSTEN_ROOT=" + cinder_shq(root) + " " + cinder_shq(tc) + " compile --emit-ll" + fe_flags + " " + cinder_shq(p) + " --out " + cinder_shq(scratch_prefix + ".u" + idx.to_s())
    if !system(cmd)
      cinder_fast_unlink(tmp_ll)
      cinder_fast_unlink(tmp_ll + ".done")
      return false
    ir = read_file(tmp_ll)
    if env("CINDER_KEEP_LL") != "1"
      cinder_fast_unlink(tmp_ll)
      cinder_fast_unlink(tmp_ll + ".done")
    return false if ir == nil
    lto_irs.push(ir)
    return true

  if p.ends_with?(".c")
    cc_bin = env("TUNGSTEN_CC")
    cc_bin = "cc" if cc_bin == nil || cc_bin == ""
    if cfg.lto_enabled?()
      tmp_ll = scratch_prefix + ".c" + idx.to_s() + ".ll"
      ll_cmd = cinder_shq(cc_bin) + " -O2 -fno-vectorize -fno-slp-vectorize -DNDEBUG -DW_COMPILE_NO_GC -I" + cinder_shq(root + "/runtime") + " -S -emit-llvm " + cinder_shq(p) + " -o " + cinder_shq(tmp_ll) + " 2>/dev/null"
      if system(ll_cmd)
        c_ir = read_file(tmp_ll)
        cinder_fast_unlink(tmp_ll)
        if c_ir != nil && c_ir.index("shufflevector ") == nil && c_ir.index("landingpad ") == nil && c_ir.index("getelementptr inbounds (") == nil
          lto_irs.push(c_ir)
          return true
      cinder_fast_unlink(tmp_ll)
    tmp_o = scratch_prefix + ".c" + idx.to_s() + ".o"
    if !system(cinder_shq(cc_bin) + " -O3 -DNDEBUG -I" + cinder_shq(root + "/runtime") + " -c " + cinder_shq(p) + " -o " + cinder_shq(tmp_o))
      ccall("w_eputs", "cinder: failed to compile " + p)
      return false
    temp_files.push(tmp_o)
    native_objs.push(tmp_o)
    return true

  if p.ends_with?(".o") || p.ends_with?(".clto")
    if cfg.lto_enabled?() || p.ends_with?(".clto")
      ir = cinder_extract_lto_from_file(p)
      if ir != nil
        lto_irs.push(ir)
        return true
      if p.ends_with?(".clto")
        ccall("w_eputs", "cinder: invalid LTO object " + p)
        return false
    native_objs.push(p)
    return true

  if p.ends_with?(".a")
    if cfg.lto_enabled?()
      ar_res = cinder_extract_lto_from_archive(p)
      if ar_res != nil && ar_res[0].size() > 0
        ai = 0
        while ai < ar_res[0].size()
          lto_irs.push(ar_res[0][ai])
          ai += 1
        native_objs.push(p) if ar_res[1]
        return true
    native_objs.push(p)
    return true

  ccall("w_eputs", "cinder: unsupported input file: " + p)
  false

# Compile one or more `.w`, `.ll`, `.c`, Fat-LTO `.o`, or `.a` inputs into `.o` or a native executable,
# performing full Cross-File Link-Time Optimization when `cfg.lto_enabled?()` or multiple IR units are given!
-> cinder_compile_inputs(in_paths, out_path, emit_obj_only = false, target_triple = "", verbose = false, opt_cfg = nil)
  return false if in_paths == nil || in_paths.size() == 0
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  pt = emit_obj_only ? cinder_parse_target(target_triple) : cinder_validate_exe_target(target_triple)
  return false if pt == nil

  # Fast single-input path when single `.ll` or straight-line `.w` script
  if in_paths.size() == 1
    p0 = in_paths[0]
    if p0.ends_with?(".ll")
      if emit_obj_only
        res = cinder_compile_ll_to_obj(p0, out_path, target_triple, cfg)
        if verbose && res[0]
          << "  cinder emitted " + res[2].to_s() + " bytes to " + out_path + " in " + res[1].to_s() + " ms (" + cfg.summary() + ")"
        return res[0]
      return cinder_link_ll_to_exe(p0, out_path, "", verbose, cfg, target_triple)
    if p0.ends_with?(".w")
      fast_res = cinder_try_fast_script_w(p0, out_path, emit_obj_only, target_triple, verbose, cfg)
      if fast_res != :fallback
        return fast_res == :ok

  root = cinder_tungsten_root()
  lto_irs = []
  native_objs = []
  temp_files = []
  pi = 0
  while pi < in_paths.size()
    if !cinder_collect_input_unit(in_paths[pi], pi, out_path + ".cinder", target_triple, cfg, root, lto_irs, native_objs, temp_files)
      ti = 0
      while ti < temp_files.size()
        cinder_fast_unlink(temp_files[ti]); ti += 1
      return false
    pi += 1

  ok = false
  if emit_obj_only
    if lto_irs.size() == 0
      ccall("w_eputs", "cinder: -c requires at least one compilable source/LTO input")
    else
      merged = lto_irs.size() == 1 ? lto_irs[0] : cinder_lto_merge_modules(lto_irs, false, cfg)
      res = cinder_compile_ll_str_to_obj(merged, out_path, target_triple, cfg, cfg.lto_enabled?())
      ok = res[0]
      if verbose && ok
        << "  cinder emitted " + res[2].to_s() + " bytes to " + out_path + " in " + res[1].to_s() + " ms (" + cfg.summary() + ")"
  else
    extra_sb = StringBuffer(128)
    ni = 0
    while ni < native_objs.size()
      extra_sb << " " if ni > 0
      extra_sb << cinder_shq(native_objs[ni])
      ni += 1
    if lto_irs.size() == 0
      # Pure native `.o` / `.a` link without IR modules!
      if native_objs.size() > 0
        needs_def = {
          lexchars: false, unicode: false, prime: false, blas: false, sparse: false,
          wtensor: false, sci_io: false, zstd: false, gc: false,
          dyn_exp: env("TUNGSTEN_DYNAMIC_EXPORTS") == "1", http2: false, tls: false
        }
        rt_pair = cinder_find_runtime_objects(root, needs_def)
        first_o = native_objs[0]
        rest_sb = StringBuffer(128)
        ni = 1
        while ni < native_objs.size()
          rest_sb << " " if ni > 1
          rest_sb << cinder_shq(native_objs[ni])
          ni += 1
        ok = (cinder_host_os() == "macos") ? cinder_link_macho(first_o, out_path, rt_pair[0], rt_pair[1], needs_def, rest_sb.to_s(), cfg) : cinder_link_elf(first_o, out_path, rt_pair[0], rt_pair[1], needs_def, rest_sb.to_s(), cfg)
    else
      ext_refs = cinder_scan_native_obj_imports(native_objs)
      merged_exe_ir = lto_irs.size() == 1 ? lto_irs[0] : cinder_lto_merge_modules(lto_irs, cfg.lto_enabled?(), cfg, ext_refs)
      ok = cinder_link_ll_str_to_exe(merged_exe_ir, in_paths[0], out_path, extra_sb.to_s(), verbose, cfg, target_triple, ext_refs)

  ti = 0
  while ti < temp_files.size()
    cinder_fast_unlink(temp_files[ti]); ti += 1
  ok

# Compile a single `.w` or `.ll` input file to `.o` (`emit_obj_only = true`) or native executable!
-> cinder_compile_input(in_path, out_path, emit_obj_only = false, target_triple = "", verbose = false, opt_cfg = nil)
  cinder_compile_inputs([in_path], out_path, emit_obj_only, target_triple, verbose, opt_cfg)

# Stage 1 / Stage 2 machine-code determinism oracle across one or more inputs (`.w`, `.ll`, `.o`, `.a`)!
-> cinder_verify_stage_determinism_multi(in_paths, opt_cfg = nil, target_triple = "", verbose = false)
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  pt = cinder_parse_target(target_triple)
  return false if pt == nil
  root = cinder_tungsten_root()
  lto_irs = []
  native_objs = []
  temp_files = []
  scratch = "/tmp/cinder_verify_" + (ccall_nobox("__w_clock_ns_raw") ## i64).to_s()
  pi = 0
  while pi < in_paths.size()
    if !cinder_collect_input_unit(in_paths[pi], pi, scratch, target_triple, cfg, root, lto_irs, native_objs, temp_files)
      ti = 0
      while ti < temp_files.size()
        cinder_fast_unlink(temp_files[ti]); ti += 1
      return false
    pi += 1
  ti = 0
  while ti < temp_files.size()
    cinder_fast_unlink(temp_files[ti]); ti += 1
  if lto_irs.size() == 0
    ccall("w_eputs", "cinder: verify-stages found no IR/LTO units in inputs")
    return false

  tgt = pt[0]
  is_x64 = pt[1]
  is_mac = pt[2]

  cfg1 = cfg.clone()
  cfg2 = cfg.clone()
  src1 = (lto_irs.size() > 1 || cfg1.lto_enabled?()) ? cinder_lto_merge_modules(lto_irs, true, cfg1) : lto_irs[0]
  src2 = (lto_irs.size() > 1 || cfg2.lto_enabled?()) ? cinder_lto_merge_modules(lto_irs, true, cfg2) : lto_irs[0]
  b1 = is_x64 ? cinder_compile_ll_x64(src1, cfg1).build_bytes() : cinder_compile_ll_a64(src1, is_mac, cfg1).build_bytes()
  b2 = is_x64 ? cinder_compile_ll_x64(src2, cfg2).build_bytes() : cinder_compile_ll_a64(src2, is_mac, cfg2).build_bytes()

  if b1.len != b2.len
    ccall("w_eputs", "ERROR stage 1 .o (" + b1.len.to_s() + " B) != stage 2 .o (" + b2.len.to_s() + " B)")
    return false

  i = 0
  p1 = cinder_raw_u8_ptr(wvalue_bits(b1.data) ## i64)
  p2 = cinder_raw_u8_ptr(wvalue_bits(b2.data) ## i64)
  n = b1.len
  while i + 8 <= n
    if raw_load_u64(p1, i) != raw_load_u64(p2, i)
      break
    i += 8
  while i < n
    if raw_load_u8(p1, i) != raw_load_u8(p2, i)
      ccall("w_eputs", "ERROR stage 1 .o != stage 2 .o (first mismatch at byte " + i.to_s() + " of " + n.to_s() + ")")
      return false
    i += 1

  << "VERIFIED stage 1 .o == stage 2 .o (" + n.to_s() + " bytes, target=" + tgt + ", -O" + cfg.opt_level.to_s() + (cfg.lto_enabled?() ? ", lto=" + cfg.lto_mode.to_s() : "") + ")" if verbose
  true

-> cinder_verify_stage_determinism(in_path, opt_cfg = nil, target_triple = "", verbose = false)
  cinder_verify_stage_determinism_multi([in_path], opt_cfg, target_triple, verbose)
