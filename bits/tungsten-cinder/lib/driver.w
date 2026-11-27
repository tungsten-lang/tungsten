# cinder/driver — End-to-end Cinder `.ll` / `.w` -> `.o` -> Native Executable Driver.
#
# Compiles `.ll` IR directly to Mach-O 64 `.o` (macOS ARM64) or ELF64 `.o` (Linux x86_64 / AArch64)
# in pure Tungsten, and links executables directly with the OS linker (`ld` on macOS,
# `ld.lld` / `ld` on Linux) — ZERO `clang`, `opt`, `llc`, or `as` subprocesses!

use ./jit_mem
use ./opt_config
use ./ll_a64
use ./ll_x64

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

# Compile an LLVM IR `.ll` file directly to a binary `.o` object file (`Mach-O 64` or `ELF64`).
# Returns `[ok_bool, elapsed_ms_i64, out_bytes_i64]`.
-> cinder_compile_ll_to_obj(ll_path, obj_path, target_triple = "", opt_cfg = nil)
  t0 = (ccall_nobox("__w_clock_ns_raw") ## i64)
  src = read_file(ll_path)
  if src == nil
    ccall("w_eputs", "cinder: cannot read " + ll_path)
    return [false, 0, 0]
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  tgt = target_triple == "" ? cinder_default_target() : target_triple.downcase()
  is_x64 = tgt.starts_with?("x86_64") || tgt.starts_with?("amd64")
  is_mac = tgt.index("apple") != nil || tgt.index("darwin") != nil || tgt.index("macos") != nil
  ok = false
  nbytes = 0
  if is_x64
    w = cinder_compile_ll_x64(src, cfg)
    b = w.build_bytes()
    nbytes = b.len
    ok = b.write_file(obj_path)
  else
    w = cinder_compile_ll_a64(src, is_mac, cfg)
    b = w.build_bytes()
    nbytes = b.len
    ok = b.write_file(obj_path)
  t1 = (ccall_nobox("__w_clock_ns_raw") ## i64)
  [ok, (t1 - t0) / 1000000, nbytes]

# Inspect `.ll` text for optional Tungsten companion bridges & system libraries (matching `compiler/lib/driver/ir.w`)
-> cinder_detect_ll_link_needs(ll_text)
  needs = {
    lexchars: ll_text.index("lchs") != nil || ll_text.index("lexchars") != nil || ll_text.index("@w_lexchar_") != nil,
    unicode:  ll_text.index("@w_string_normalize") != nil || ll_text.index("@w_string_grapheme_next") != nil || ll_text.index("@w_approx_eq") != nil || ll_text.index("@w_unicode_") != nil,
    prime:    ll_text.index("@w_prime_") != nil || ll_text.index("@w_primes_") != nil || ll_text.index("@w_bigint_prime") != nil,
    blas:     ll_text.index("@w_blas_") != nil || ll_text.index("@w_array_cos_") != nil || ll_text.index("@w_array_sin_") != nil || ll_text.index("@w_array_sqrt_") != nil,
    sparse:   ll_text.index("@w_sparse_") != nil,
    wtensor:  ll_text.index("@w_tensor_") != nil,
    sci_io:   ll_text.index("@w_sci_") != nil,
    zstd:     ll_text.index("@ZSTD_decompress") != nil || ll_text.index("@w_zstd_") != nil || ll_text.index("@w_slab_init_static_zstd") != nil,
    dyn_exp:  env("TUNGSTEN_DYNAMIC_EXPORTS") == "1" || ll_text.index("@w_jit_load_object(") != nil,
    http2:    ll_text.index("@w_h2_") != nil || ll_text.index("@nghttp2_") != nil,
    tls:      ll_text.index("@SSL_CTX_") != nil || ll_text.index("@OPENSSL_") != nil
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

# Locate or query prebuilt runtime archive (`runtime.a`) and companion `.o`s in the Tungsten build store!
-> cinder_find_runtime_objects(root, needs)
  store = env("TUNGSTEN_BUILD_STORE")
  if store == nil || store == ""
    th = env("TUNGSTEN_HOME")
    if th == nil || th == ""
      hm = env("HOME")
      th = (hm != nil && hm != "") ? (hm + "/.tungsten") : (root + "/.tungsten")
    store = th + "/cache"
  comp_dir = env("TUNGSTEN_CACHE_DIR")
  if comp_dir == nil || comp_dir == ""
    comp_dir = store + "/compile"

  # Pick the newest non-LTO native `runtime*.a` in `comp_dir` matching `needs[:zstd]`!
  zstd_chk = needs[:zstd] ? "ar t \"$f\" 2>/dev/null | grep -q '^slab_zstd\\.o$' && " : ""
  probe_cmd = "sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/runtime-*.a 2>/dev/null); do if " + zstd_chk + "true; then tmp=$(mktemp -d); (cd \"$tmp\" && ar x \"$f\" runtime.o 2>/dev/null); if test -f \"$tmp/runtime.o\" && ! file \"$tmp/runtime.o\" | grep -qi bitcode; then rm -rf \"$tmp\"; echo \"$f\"; break; fi; rm -rf \"$tmp\"; fi; done'"
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
    write_file(warm_w, warm_src)
    tc = root + "/bin/tungsten-compiler"
    zflag = needs[:zstd] ? " --intern zstd" : ""
    system("TUNGSTEN_ROOT=" + cinder_shq(root) + " " + cinder_shq(tc) + " compile --no-lto" + zflag + " " + cinder_shq(warm_w) + " -o " + cinder_shq(warm_o) + " >/dev/null 2>&1")
    system("rm -f " + cinder_shq(warm_w) + " " + cinder_shq(warm_o) + " " + cinder_shq(warm_o + ".sidemap"))
    rt_a = capture(probe_cmd).strip() if rt_a == ""

  companions = []
  if needs[:lexchars]
    c_lex = capture("sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/companion-*lexchar*.o 2>/dev/null); do if ! file \"$f\" | grep -qi bitcode; then echo \"$f\"; break; fi; done'").strip()
    companions.push(c_lex) if c_lex != ""
  if needs[:unicode]
    c_uni = capture("sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/companion-*unicode*.o 2>/dev/null); do if ! file \"$f\" | grep -qi bitcode; then echo \"$f\"; break; fi; done'").strip()
    companions.push(c_uni) if c_uni != ""
  if needs[:prime]
    c_prm = capture("sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/companion-*ssmr*.o 2>/dev/null); do if ! file \"$f\" | grep -qi bitcode; then echo \"$f\"; break; fi; done'").strip()
    companions.push(c_prm) if c_prm != ""
  if needs[:blas]
    c_bls = capture("sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/companion-*blas*.o " + cinder_shq(comp_dir) + "/companion-*openblas*.o 2>/dev/null); do if ! file \"$f\" | grep -qi bitcode; then echo \"$f\"; break; fi; done'").strip()
    companions.push(c_bls) if c_bls != ""
  if needs[:wtensor]
    c_ten = capture("sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/companion-*tensor*.o 2>/dev/null); do if ! file \"$f\" | grep -qi bitcode; then echo \"$f\"; break; fi; done'").strip()
    companions.push(c_ten) if c_ten != ""
  if needs[:sci_io]
    c_sci = capture("sh -c 'for f in $(ls -t " + cinder_shq(comp_dir) + "/companion-*sci_io*.o 2>/dev/null); do if ! file \"$f\" | grep -qi bitcode; then echo \"$f\"; break; fi; done'").strip()
    companions.push(c_sci) if c_sci != ""

  [rt_a, companions]

# Link a Mach-O `.o` file directly into a macOS ARM64 executable using Apple `ld` (ZERO `clang`!)
-> cinder_link_macho(obj_path, out_path, rt_archive, companions, needs, extra_link_args = "", opt_cfg = nil)
  ld_bin = capture("xcrun --sdk macosx --find ld 2>/dev/null").strip()
  ld_bin = "/usr/bin/ld" if ld_bin == ""
  sdk = capture("xcrun --sdk macosx --show-sdk-path 2>/dev/null").strip()
  sdk_ver = env("MACOSX_DEPLOYMENT_TARGET")
  if sdk_ver == nil || sdk_ver == ""
    sdk_ver = capture("xcrun --sdk macosx --show-sdk-version 2>/dev/null").strip()
  if sdk_ver == ""
    sdk_ver = capture("sw_vers -productVersion 2>/dev/null").strip()
  sdk_ver = "14.0.0" if sdk_ver == ""

  cmd = StringBuffer(512)
  cmd << cinder_shq(ld_bin)
  cmd << " -arch arm64 -platform_version macos " + sdk_ver + " " + sdk_ver
  if sdk != ""
    cmd << " -syslibroot "
    cmd << cinder_shq(sdk)
  cmd << " -dead_strip -stack_size 0x8000000"
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
  if needs[:blas] || needs[:sparse]
    cmd << " -framework Accelerate"
  hb = capture("brew --prefix 2>/dev/null").strip()
  if hb != "" && system("test -d " + cinder_shq(hb + "/lib"))
    cmd << " -L"
    cmd << cinder_shq(hb + "/lib")
  if system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q '_mi_'")
    cmd << " -lmimalloc"
  if system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q '_SSL_'")
    ossl = capture("brew --prefix openssl@3 2>/dev/null").strip()
    if ossl != ""
      cmd << " -L" + cinder_shq(ossl + "/lib") + " -lssl -lcrypto"
  if system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q '_nghttp2_'")
    ngh = capture("brew --prefix libnghttp2 2>/dev/null").strip()
    if ngh != ""
      cmd << " -L" + cinder_shq(ngh + "/lib") + " -lnghttp2"
    else
      cmd << " -lnghttp2"
  if needs[:zstd] || system("nm -u " + cinder_shq(rt_archive) + " 2>/dev/null | grep -q '_ZSTD_'")
    zst = capture("brew --prefix zstd 2>/dev/null").strip()
    if zst != ""
      cmd << " -L" + cinder_shq(zst + "/lib") + " -lzstd"
    else
      cmd << " -lzstd"
  cmd << " -lSystem -o "
  cmd << cinder_shq(out_path)
  ok = system(cmd.to_s())
  if ok
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

# Link a `.ll` file all the way to a native executable via Cinder `.o` + OS `ld`!
-> cinder_link_ll_to_exe(ll_path, out_path, explicit_rt_objs = "", verbose = false, opt_cfg = nil)
  t0 = (ccall_nobox("__w_clock_ns_raw") ## i64)
  src = read_file(ll_path)
  if src == nil
    ccall("w_eputs", "cinder: cannot read " + ll_path)
    return false
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  needs = cinder_detect_ll_link_needs(src)
  obj_path = out_path + ".cinder.o"
  is_mac = cinder_host_os() == "macos"
  is_x64 = cinder_host_arch() == "x86_64"

  ok_obj = false
  if is_x64
    ok_obj = cinder_compile_ll_x64(src, cfg).write_file(obj_path)
  else
    ok_obj = cinder_compile_ll_a64(src, is_mac, cfg).write_file(obj_path)
  if !ok_obj
    ccall("w_eputs", "cinder: object emission failed for " + ll_path)
    return false

  t_codegen = (ccall_nobox("__w_clock_ns_raw") ## i64)
  root = cinder_tungsten_root()
  rt_a = ""
  comps = []
  extra = ""
  if explicit_rt_objs != ""
    extra = explicit_rt_objs
    rt_pair = cinder_find_runtime_objects(root, needs)
    comps = rt_pair[1]
  else
    rt_pair = cinder_find_runtime_objects(root, needs)
    rt_a = rt_pair[0]
    comps = rt_pair[1]

  ok_ld = is_mac ? cinder_link_macho(obj_path, out_path, rt_a, comps, needs, extra, cfg) : cinder_link_elf(obj_path, out_path, rt_a, comps, needs, extra, cfg)
  system("rm -f " + cinder_shq(obj_path)) if ok_ld && env("CINDER_KEEP_OBJ") != "1"
  t_end = (ccall_nobox("__w_clock_ns_raw") ## i64)
  if verbose
    cg_ms = (t_codegen - t0) / 1000000
    ld_ms = (t_end - t_codegen) / 1000000
    << "  cinder codegen: " + cg_ms.to_s() + " ms | ld: " + ld_ms.to_s() + " ms (" + cfg.summary() + ")"
  ok_ld

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

# Compile a `.w` or `.ll` input file to `.o` (`emit_obj_only = true`) or native executable!
-> cinder_compile_input(in_path, out_path, emit_obj_only = false, target_triple = "", verbose = false, opt_cfg = nil)
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  if in_path.ends_with?(".ll")
    if emit_obj_only
      res = cinder_compile_ll_to_obj(in_path, out_path, target_triple, cfg)
      if verbose && res[0]
        << "  cinder emitted " + res[2].to_s() + " bytes to " + out_path + " in " + res[1].to_s() + " ms (" + cfg.summary() + ")"
      return res[0]
    return cinder_link_ll_to_exe(in_path, out_path, "", verbose, cfg)

  root = cinder_tungsten_root()
  tc = root + "/bin/tungsten-compiler"
  tmp_ll = out_path + ".cinder.tmp.ll"
  fe_flags = cinder_frontend_flags(cfg, target_triple)
  cmd = "TUNGSTEN_LL_PATH=" + cinder_shq(tmp_ll) + " BIT_HOME=" + cinder_shq(root + "/bits") + " TUNGSTEN_ROOT=" + cinder_shq(root) + " " + cinder_shq(tc) + " compile --emit-ll" + fe_flags + " " + cinder_shq(in_path) + " --out " + cinder_shq(out_path)
  if !system(cmd)
    system("rm -f " + cinder_shq(tmp_ll))
    return false
  ok = false
  if emit_obj_only
    res = cinder_compile_ll_to_obj(tmp_ll, out_path, target_triple, cfg)
    ok = res[0]
    if verbose && ok
      << "  cinder emitted " + res[2].to_s() + " bytes to " + out_path + " in " + res[1].to_s() + " ms (" + cfg.summary() + ")"
  else
    ok = cinder_link_ll_to_exe(tmp_ll, out_path, "", verbose, cfg)
  system("rm -f " + cinder_shq(tmp_ll)) if env("CINDER_KEEP_LL") != "1"
  ok

# Stage 1 / Stage 2 machine-code determinism oracle (replaces `.ll == .ll` when skipping Clang/LLVM!):
# Compiles `in_path` (`.w` or `.ll`) twice through Cinder's full optimizer and Mach-O/ELF64 object
# emitter into independent relocatable `.o` buffers and verifies 100% byte-for-byte identity across
# machine code, `.rodata`/`.data`/`.bss`, symbol tables, string tables, and relocation records.
-> cinder_verify_stage_determinism(in_path, opt_cfg = nil, target_triple = "", verbose = false)
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  ll_path = in_path
  tmp_ll = ""
  if !in_path.ends_with?(".ll")
    root = cinder_tungsten_root()
    tc = root + "/bin/tungsten-compiler"
    tmp_ll = "/tmp/cinder_verify_" + (ccall_nobox("__w_clock_ns_raw") ## i64).to_s() + ".ll"
    fe_flags = cinder_frontend_flags(cfg, target_triple)
    cmd = "TUNGSTEN_LL_PATH=" + cinder_shq(tmp_ll) + " BIT_HOME=" + cinder_shq(root + "/bits") + " TUNGSTEN_ROOT=" + cinder_shq(root) + " " + cinder_shq(tc) + " compile --emit-ll" + fe_flags + " " + cinder_shq(in_path) + " --out " + cinder_shq(tmp_ll + ".bin")
    if !system(cmd)
      system("rm -f " + cinder_shq(tmp_ll))
      return false
    ll_path = tmp_ll

  src = read_file(ll_path)
  system("rm -f " + cinder_shq(tmp_ll)) if tmp_ll != ""
  if src == nil
    ccall("w_eputs", "cinder: cannot read " + ll_path)
    return false

  tgt = target_triple == "" ? cinder_default_target() : target_triple.downcase()
  is_x64 = tgt.starts_with?("x86_64") || tgt.starts_with?("amd64")
  is_mac = tgt.index("apple") != nil || tgt.index("darwin") != nil || tgt.index("macos") != nil

  cfg1 = cfg.clone()
  cfg2 = cfg.clone()
  b1 = is_x64 ? cinder_compile_ll_x64(src, cfg1).build_bytes() : cinder_compile_ll_a64(src, is_mac, cfg1).build_bytes()
  b2 = is_x64 ? cinder_compile_ll_x64(src, cfg2).build_bytes() : cinder_compile_ll_a64(src, is_mac, cfg2).build_bytes()

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

  << "VERIFIED stage 1 .o == stage 2 .o (" + n.to_s() + " bytes, target=" + tgt + ", -O" + cfg.opt_level.to_s() + ")" if verbose
  true
