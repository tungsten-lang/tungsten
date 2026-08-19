# Emitter analysis — declarations, metadata, call contracts, and cache policy.

-> filter_runtime_decls(decls, used_fns)
  lines = decls.split("\n")
  out = StringBuffer(decls.size())
  i = 0
  while i < lines.size()
    line = lines[i]
    if line != ""
      name = runtime_decl_name(line)
      if name != nil && used_fns[name] == true
        out << line
        out << "\n"
    i += 1
  out.to_s()

-> function_attr_text(frame_pointers, host_fn_attrs, preserve_debug_frames = false)
  out = StringBuffer(160)
  out << "nounwind"
  if host_fn_attrs != nil && host_fn_attrs != ""
    out << " "
    out << host_fn_attrs
  if frame_pointers
    # `nounwind` lets LLVM drop unwind tables, so emitted fns get no
    # .eh_frame CFI — fine on macOS (backtrace() walks frame pointers) but
    # fatal on Linux, where glibc's backtrace()/_Unwind_Backtrace can only
    # step through frames that carry CFI. Without it the unwind dies at the
    # first Tungsten frame and outer fn-meta frames never show. `uwtable`
    # forces async unwind tables (matching clang's Linux default) so
    # --frame-pointers yields a full backtrace on both platforms.
    out << " uwtable \"frame-pointer\"=\"all\""
  if preserve_debug_frames
    out << " noinline \"disable-tail-calls\"=\"true\""
  out.to_s()

-> function_attr_group_id(attr_groups, attr_text)
  ids = attr_groups[:ids]
  existing = ids[attr_text]
  if existing != nil
    return existing
  texts = attr_groups[:texts]
  id = texts.size()
  ids[attr_text] = id
  texts.push(attr_text)
  id

-> emit_function_attr_groups(attr_groups)
  texts = attr_groups[:texts]
  if texts == nil || texts.size() == 0
    return ""
  out = StringBuffer(texts.size() * 180 + 16)
  out << "\n"
  i = 0
  while i < texts.size()
    out << "attributes #"
    out << i.to_s()
    out << " = { "
    out << texts[i]
    out << " }\n"
    i += 1
  out.to_s()

-> call_prefix(inst)
  prefix = "call"
  if wire_get(inst, :src_line) != nil
    prefix = "notail call"
  cc = wire_get(inst, :call_conv)
  if cc != nil && cc != ""
    prefix = prefix + " " + cc
  prefix

-> range_metadata_suffix(inst, llvm_type)
  low = wire_get(inst, :range_low)
  high = wire_get(inst, :range_high)
  if low == nil || high == nil
    return ""
  ", !range !{" + llvm_type + " " + low.to_s() + ", " + llvm_type + " " + high.to_s() + "}"

# TBAA (type-based alias analysis) tags for typed-array access. The WArray
# header (start/size/slots-ptr) and the element data occupy disjoint memory —
# no byte is ever accessed as both — so tagging header loads and element
# loads/stores with distinct sibling TBAA types lets LLVM's LICM hoist the
# invariant header derefs (slots ptr @+16, start @+4) out of a hot loop that
# only reads/writes elements. This is sound even when the array is grown
# inside the loop: `push`/`unshift`/`clear` realloc via a runtime CALL, which
# is a memory barrier LICM will not hoist across, and any inline header store
# is untagged (may-alias-all), so the header load stays pinned exactly where a
# realloc could move slots/start. Node definitions are emitted once per module
# in emit_artifact (tbaa_metadata_defs()). IDs are high to avoid colliding with
# LLVM's auto-numbering of inline (!range) metadata.
-> tbaa_header_suffix()
  ", !tbaa !31416"
-> tbaa_elem_suffix()
  ", !tbaa !31417"
# Object instance-variable slots (WObject payload @ +8 + offset*8) are a distinct
# memory kind from array headers and array element data — an object and an array
# are always separate allocations, so an ivar load never aliases an array store.
# A dedicated TBAA type lets LICM/GVN hoist a `self.field` read across an array
# element store in the same loop (e.g. `arr[i] = self.base + i`). Field-vs-field
# is left may-alias (one scalar tag), which is all we need. `- data` view-field
# access stays UNTAGGED (may-alias-all) so a field reinterpreted through a view is
# never split into two disjoint types.
-> tbaa_ivar_suffix()
  ", !tbaa !31421"
# ebits (element type/width, header byte @+1) is fixed at allocation and never
# changes for an array's lifetime — unlike start/size/slots which realloc moves.
# So an ebits load is genuinely invariant: !invariant.load lets LLVM hoist the
# poly-array kind check out of a hot loop (and even across calls), collapsing
# per-access dispatch on an untyped receiver to a single check.
-> invariant_load_suffix()
  ", !invariant.load !31419"
-> tbaa_metadata_defs()
  o = StringBuffer(256)
  o << "\n!31414 = !{!\"tungsten_tbaa_root\"}\n"
  o << "!31415 = !{!\"warray_data\", !31414}\n"
  o << "!31418 = !{!\"warray_header\", !31414}\n"
  o << "!31416 = !{!31418, !31418, i64 0}\n"
  o << "!31417 = !{!31415, !31415, i64 0}\n"
  o << "!31419 = !{}\n"
  o << "!31420 = !{!\"object_field\", !31414}\n"
  o << "!31421 = !{!31420, !31420, i64 0}\n"
  # Guarded-i48 branch weights: the runtime/bigint arm is the exception.
  # LLVM uses these for block layout (cold code sinks out of the loop
  # body) and register allocation (spills move into the cold block); the
  # CPU's dynamic predictor is unaffected, so a bigint-phase accumulator
  # that takes the "unlikely" arm every pass pays nothing extra.
  o << "!31411 = !{!\"branch_weights\", i32 2000, i32 1}\n"
  o << "!31412 = !{!\"branch_weights\", i32 1, i32 2000}\n"
  o.to_s()

# Per-loop latch metadata (lowering stamps the latch :br):
#   novec:true   — loop-vectorizer opt-out for masked-index while loops
#                  (lowering/analysis.w loop_masked_array_index?)
#   unroll_count — `llvm.loop.unroll.count N` for carry-intrinsic loops
#                  (lowering/analysis.w loop_has_carry_intrinsic?); the
#                  carry flag spills across the back-edge (llvm.org
#                  #74493) and LLVM won't unroll these on its own —
#                  unrolling amortizes the spill (+25% for multi-limb add,
#                  +8% for multiply-accumulate on Apple M5). Vectorization stays
#                  ENABLED for these: novec measured neutral-to-harmful.
# Each marked latch gets its OWN distinct self-referential !llvm.loop node:
# LLVM uses the node as the loop's identity, and sharing one node across loops
# measurably degrades the unroller's output (6.7B vs 8.5B ops/s on the masked
# reduce). IDs run upward from 31423, above the fixed TBAA block; allocation
# follows render order, which is deterministic, so stage identity holds. The
# state is a top-level container mutated in place (rebinding a top-level name
# from a function shadows instead of writing through — see detect_target_memo).
novec_md_state = {kinds: [], refs: {}}

-> latch_loop_md_ref(kind, unroll_count = 0)
  ks = novec_md_state[:kinds]
  k = ks.size()
  ks.push([kind, unroll_count])
  (31423 + k * 2).to_s()

-> latch_loop_md_ref_for(inst, kind, unroll_count = 0)
  cached = novec_md_state[:refs][inst]
  if cached != nil
    return cached
  latch_loop_md_ref(kind, unroll_count)

# One shared novec tuple plus a distinct loop node and, when applicable, an
# unroll-count tuple per marked latch. Per-loop tuples allow different tuning
# counts in one emitter process without sharing loop identity. Rendered AFTER
# all functions (emit_artifact's final concat), so the list is final. Emits
# nothing when no loop was marked.
-> novec_loop_md_defs()
  ks = novec_md_state[:kinds]
  n = ks.size()
  if n == 0
    return ""
  o = StringBuffer(64)
  any_novec = false
  i = 0
  while i < n
    kind = ks[i][0]
    if kind == :novec || kind == :both
      any_novec = true
    i += 1
  if any_novec
    o << "!31422 = !{!\"llvm.loop.vectorize.enable\", i1 false}\n"
  i = 0
  while i < n
    entry = ks[i]
    kind = entry[0]
    unroll_count = entry[1]
    id = (31423 + i * 2).to_s()
    unroll_id = (31424 + i * 2).to_s()
    if kind == :both
      o << "!" + unroll_id + " = !{!\"llvm.loop.unroll.count\", i32 " + unroll_count.to_s() + "}\n"
      o << "!" + id + " = distinct !{!" + id + ", !31422, !" + unroll_id + "}\n"
    elsif kind == :unroll
      o << "!" + unroll_id + " = !{!\"llvm.loop.unroll.count\", i32 " + unroll_count.to_s() + "}\n"
      o << "!" + id + " = distinct !{!" + id + ", !" + unroll_id + "}\n"
    else
      o << "!" + id + " = distinct !{!" + id + ", !31422}\n"
    i += 1
  o.to_s()

# Scoped no-alias metadata for fused elementwise workers (lowering stamps the
# loop's source loads / output store with ewscope:<site-id> — see
# fuse_ew_emit_range_loop). The output is the site's fresh malloc, provably
# disjoint from every source, but TBAA can't express it (all elements are
# warray_data), so without this -O3 versions the loop behind per-source
# runtime overlap checks. Per site: one distinct scope in a shared domain,
# referenced through a scope-list node; the store carries `!alias.scope`
# (it writes inside the scope) and the loads carry `!noalias` (they never
# touch the scope's memory). IDs live at 300000+ — far above the TBAA block
# and the novec range (31423+k), which would need ~270k stamped loops to
# collide. Deterministic: sites are numbered in lowering order and the map
# fills in render order.
ewscope_md_state = {ids: {}}

-> ewscope_list_id(sid)
  cached = ewscope_md_state[:ids][sid]
  if cached != nil
    return cached
  k = ewscope_md_state[:ids].size()
  list_id = (300001 + k * 2).to_s()
  ewscope_md_state[:ids][sid] = list_id
  list_id

-> ewscope_store_suffix(inst)
  if wire_get(inst, :ewscope) == nil
    return ""
  ", !alias.scope !" + ewscope_list_id(wire_get(inst, :ewscope))

-> ewscope_load_suffix(inst)
  if wire_get(inst, :ewscope) == nil
    return ""
  ", !noalias !" + ewscope_list_id(wire_get(inst, :ewscope))

-> ewscope_md_defs()
  n = ewscope_md_state[:ids].size()
  if n == 0
    return ""
  o = StringBuffer(96)
  o << "!299999 = distinct !{!299999, !\"tungsten.fusedew\"}\n"
  i = 0
  while i < n
    scope_id = (300000 + i * 2).to_s()
    list_id = (300001 + i * 2).to_s()
    o << "!" + scope_id + " = distinct !{!" + scope_id + ", !299999}\n"
    o << "!" + list_id + " = !{!" + scope_id + "}\n"
    i += 1
  o.to_s()

# Process-local rendered-function cache. Lowered Core functions attached from
# the incremental cache are immutable, but release `compile-batch` used to
# render the same bodies into LLVM text for every entry program. Keep the
# complete module monolithic for FullLTO and reuse only the per-function text.
#
# Functions that allocate render-order metadata ids deliberately bypass this
# cache: their text depends on the functions emitted before them. Debug builds
# also bypass it so source backtrace/call-site emission stays on the simplest
# possible path. Raw string-pointer dependencies are captured on a miss and
# replayed on a hit before emit_string_constants runs.
function_emit_cache_state = {
  entries: {},
  persistent_dir: nil,
  persistent_identity: nil,
  hits: 0,
  misses: 0,
  bypasses: 0
}

-> function_emit_cache_configure_persistent(dir, identity)
  function_emit_cache_state[:persistent_dir] = dir
  function_emit_cache_state[:persistent_identity] = identity
  nil

-> function_emit_disk_cache_enabled?
  function_emit_cache_state[:persistent_dir] != nil && function_emit_cache_state[:persistent_identity] != nil && env("TUNGSTEN_FUNCTION_EMIT_DISK_CACHE") != "0" && runtime_identity() == "compiled-runtime"

-> function_emit_cache_persistent_path(key)
  if !function_emit_disk_cache_enabled?
    return nil
  function_emit_cache_state[:persistent_dir] + "/core-render-v1-" + function_emit_cache_state[:persistent_identity] + "-" + wyhash64_hex_string(key) + ".twc"

-> function_emit_cache_persistent_valid?(entry, key)
  if type(entry) != "Hash" || entry[:version] != "core-render-v1" || entry[:key] != key || type(entry[:functions]) != "Hash"
    return false
  names = entry[:functions].keys()
  i = 0
  while i < names.size()
    name = names[i]
    item = entry[:functions][name]
    if type(name) != "String" || type(item) != "Hash" || item[:name] != name || type(item[:text]) != "String" || type(item[:ptr_ids]) != "Array"
      return false
    j = 0
    while j < item[:ptr_ids].size()
      if type(item[:ptr_ids][j]) != "Int" || item[:ptr_ids][j] < 0
        return false
      j += 1
    i += 1
  true

-> function_emit_cache_load_persistent(key)
  path = function_emit_cache_persistent_path(key)
  if path == nil
    return nil
  entry = ccall("w_core_cache_read", path)
  if function_emit_cache_persistent_valid?(entry, key)
    return entry
  nil

-> function_emit_cache_publish(bucket)
  if bucket == nil || bucket[:dirty] != true || !function_emit_disk_cache_enabled?
    return nil
  entry = {
    version: "core-render-v1",
    key: bucket[:key],
    functions: bucket[:functions]
  }
  if ccall("w_core_cache_write", function_emit_cache_persistent_path(bucket[:key]), entry) == true
    bucket[:persistent_status] = :stored
    bucket[:dirty] = false
  else
    bucket[:persistent_status] = :store_failed
  nil

-> function_emit_cache_field(value)
  text = value == nil ? "" : value.to_s()
  text.size().to_s() + ":" + text

-> function_emit_cache_module_key(mod, frame_pointers, host_fn_attrs, arm64_target, windows_target, preserve_debug_frames, fp_flags)
  out = StringBuffer(256)
  out << "rendered-core-function-v2"
  fields = [
    mod[:incremental_core_cache_key],
    mod[:llvm_datalayout],
    mod[:llvm_triple],
    host_fn_attrs,
    frame_pointers,
    arm64_target,
    windows_target,
    preserve_debug_frames,
    mod[:no_static_slab] == true,
    fp_flags
  ]
  i = 0
  while i < fields.size()
    out << function_emit_cache_field(fields[i])
    i += 1
  out.to_s()

-> function_emit_cache_bucket(mod, frame_pointers, host_fn_attrs, arm64_target, windows_target, preserve_debug_frames, fp_flags)
  key = function_emit_cache_module_key(mod, frame_pointers, host_fn_attrs, arm64_target, windows_target, preserve_debug_frames, fp_flags)
  function_emit_cache_bucket_for_key(key, :core, nil)

-> function_emit_cache_bucket_for_key(key, scope, library_paths)
  bucket = function_emit_cache_state[:entries][key]
  if bucket == nil || bucket[:key] != key
    functions = {}
    persistent_status = :disabled
    if function_emit_disk_cache_enabled?
      persistent = function_emit_cache_load_persistent(key)
      if persistent != nil
        functions = persistent[:functions]
        persistent_status = :hit
      else
        persistent_status = :miss
    bucket = {key: key, scope: scope, library_paths: library_paths, functions: functions, dirty: false, persistent_status: persistent_status}
    function_emit_cache_state[:entries][key] = bucket
  elsif bucket[:persistent_status] != :stored
    bucket[:persistent_status] = :memory
  bucket[:scope] = scope
  bucket[:library_paths] = library_paths
  bucket

-> function_emit_cache_strings_digest(mod, count)
  if count == nil || count < 0 || count > mod[:strings].size()
    return nil
  out = StringBuffer(count * 12)
  i = 0
  while i < count
    out << function_emit_cache_field(mod[:strings][i][:text])
    i += 1
  wyhash64_hex_string(out.to_s())

-> function_emit_library_cache_bucket(mod, frame_pointers, host_fn_attrs, arm64_target, windows_target, preserve_debug_frames, fp_flags)
  paths = mod[:library_reachability_paths]
  if paths == nil || paths.size() == 0 || env("TUNGSTEN_LIBRARY_FUNCTION_EMIT_CACHE") == "0"
    return nil
  string_count = mod[:incremental_library_cache_compact_string_count]
  strings_digest = function_emit_cache_strings_digest(mod, string_count)
  if string_count == nil || string_count == 0 || strings_digest == nil
    return nil
  out = StringBuffer(320)
  out << "rendered-library-function-v2"
  out << function_emit_cache_field(function_emit_cache_module_key(mod, frame_pointers, host_fn_attrs, arm64_target, windows_target, preserve_debug_frames, fp_flags))
  out << function_emit_cache_field(mod[:incremental_library_cache_key])
  out << function_emit_cache_field(string_count)
  out << function_emit_cache_field(strings_digest)
  function_emit_cache_bucket_for_key(out.to_s(), :library, paths)

-> function_emit_cache_candidate?(f, bucket)
  if bucket[:scope] == :core
    return (f[:incremental_core_frozen] == true || f[:incremental_core_candidate] == true) && f[:name] != "main"
  if bucket[:scope] == :library
    paths = bucket[:library_paths]
    return paths != nil && paths[f[:source_path]] == true && f[:is_toplevel] != true && f[:name] != "main"
  false

-> function_emit_cache_select_bucket(f, core_bucket, library_bucket)
  if core_bucket != nil && function_emit_cache_candidate?(f, core_bucket)
    return core_bucket
  if library_bucket != nil && function_emit_cache_candidate?(f, library_bucket)
    return library_bucket
  nil

-> function_emit_cache_safe?(f)
  bi = 0
  while bi < f[:blocks].size()
    instrs = f[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if wire_get(inst, :ewscope) != nil
        return false
      if wire_kind(inst) == :br
        unroll_count = wire_get(inst, :unroll_count)
        if wire_get(inst, :novec) == true || (unroll_count != nil && unroll_count > 0)
          return false
      ii += 1
    bi += 1
  true

-> function_emit_cache_merge_ptr_ids(used_ptr_ids, ptr_ids)
  i = 0
  while i < ptr_ids.size()
    used_ptr_ids[ptr_ids[i]] = true
    i += 1
  nil
-> emit_function_with_cache(f, string_wvs, slab_info, used_ptr_ids, frame_pointers, host_fn_attrs, attr_groups, arm64_target, windows_target, preserve_debug_frames, cache_bucket)
  if cache_bucket == nil || !function_emit_cache_candidate?(f, cache_bucket)
    function_emit_cache_state[:bypasses] = function_emit_cache_state[:bypasses] + 1
    return emit_function(f, string_wvs, slab_info, used_ptr_ids, frame_pointers, host_fn_attrs, attr_groups, arm64_target, windows_target, preserve_debug_frames)

  # All ordinary functions in one module use the same attribute text. On a
  # cache hit emit_function does not get a chance to intern it, so do that
  # before lookup; the resulting numeric id is identical to an uncached emit.
  if f[:embedded_ll] == nil && f[:embedded_asm] == nil && attr_groups != nil
    function_attr_group_id(attr_groups, function_attr_text(frame_pointers, host_fn_attrs, preserve_debug_frames))

  entry = cache_bucket[:functions][f[:name]]
  if entry != nil && entry[:name] == f[:name]
    function_emit_cache_merge_ptr_ids(used_ptr_ids, entry[:ptr_ids])
    function_emit_cache_state[:hits] = function_emit_cache_state[:hits] + 1
    return entry[:text]

  if !function_emit_cache_safe?(f)
    function_emit_cache_state[:bypasses] = function_emit_cache_state[:bypasses] + 1
    return emit_function(f, string_wvs, slab_info, used_ptr_ids, frame_pointers, host_fn_attrs, attr_groups, arm64_target, windows_target, preserve_debug_frames)

  local_ptr_ids = {}
  rendered = emit_function(f, string_wvs, slab_info, local_ptr_ids, frame_pointers, host_fn_attrs, attr_groups, arm64_target, windows_target, preserve_debug_frames)
  ptr_ids = local_ptr_ids.keys()
  function_emit_cache_merge_ptr_ids(used_ptr_ids, ptr_ids)
  cache_bucket[:functions][f[:name]] = {name: f[:name], text: rendered, ptr_ids: ptr_ids}
  cache_bucket[:dirty] = true
  function_emit_cache_state[:misses] = function_emit_cache_state[:misses] + 1
  rendered

-> direct_range_metadata_suffix(llvm_type, low, high)
  ", !range !{" + llvm_type + " " + low.to_s() + ", " + llvm_type + " " + high.to_s() + "}"

-> wvalue_int_range_metadata_suffix(low, high)
  low_bits = (w_tag_int + low) ## i64
  high_bits = (w_tag_int + high) ## i64
  direct_range_metadata_suffix("i64", machine_i64_box(low_bits), machine_i64_box(high_bits))

-> wvalue_bool_range_metadata_suffix()
  direct_range_metadata_suffix("i64", w_false, w_true + 1)

-> wvalue_char_range_metadata_suffix()
  # Char WValues are the 0xFFFC tag with subtype 11 (bits 47..46).
  subtype_span = 70368744177664
  low_bits = (w_tag_char + subtype_span * 3) ## i64
  high_bits = (w_tag_char + subtype_span * 4) ## i64
  direct_range_metadata_suffix("i64", machine_i64_box(low_bits), machine_i64_box(high_bits))

-> wvalue_bool_call?(name)
  name in ("w_bool" "w_eq" "w_neq" "w_eq_lit" "w_neq_lit" "w_lt" "w_gt" "w_lte" "w_gte" "__w_eq_fast" "__w_neq_fast" "__w_eq_lit_fast" "__w_neq_lit_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "__w_eq0_big_fast" "__w_lt0_big_fast" "__w_gt0_big_fast" "__w_lte0_big_fast" "__w_gte0_big_fast" "__w_streq_fast" "__w_streq2_fast" "w_hash_has_key" "__w_file_exists" "__w_write_file" "w_ipv4_in_cidr")

-> known_call_range_metadata_suffix(inst, llvm_type)
  suffix = range_metadata_suffix(inst, llvm_type)
  if suffix != ""
    return suffix
  if llvm_type == "i64"
    name = wire_get(inst, :name)
    if name == "w_truthy"
      return direct_range_metadata_suffix("i64", 0, 2)
    if name == "w_box_char"
      return wvalue_char_range_metadata_suffix()
    if wvalue_bool_call?(name)
      return wvalue_bool_range_metadata_suffix()
  ""

-> w_int_call_with_range(temp, raw, low, high)
  temp + " = call i64 @w_int(i64 " + raw + ")" + wvalue_int_range_metadata_suffix(low, high)

# Lowering sets this bit only for an exact source-class receiver whose own
# method table contains the one-argument target. Native and unknown receivers
# retain the established pointer-plus-count dispatch ABI.
-> scalar_source_one_call?(inst)
  wire_kind(inst) == :call_method_i64 && wire_get(inst, :args) != nil && wire_sequence_size(wire_get(inst, :args)) == 1 && wire_get(inst, :scalar_source_argc1) == true

-> scalar_source_two_call?(inst)
  wire_kind(inst) == :call_method_i64 && wire_get(inst, :args) != nil && wire_sequence_size(wire_get(inst, :args)) == 2 && wire_get(inst, :scalar_source_argc2) == true

-> scalar_source_call?(inst)
  scalar_source_one_call?(inst) || scalar_source_two_call?(inst)

# Return the runtime function names that an instruction will reference when rendered.
-> runtime_fns_for_inst(inst, string_wvs = nil)
  case wire_kind(inst)
  when :call_direct_i64, :call_direct_i128, :call_direct_void, :call_direct_ptr
    # w_node_field_store renders as inline slab IR when the offset is a
    # literal, and that IR calls the array-freeze helper directly — the
    # helper never appears as an instruction, so declare it alongside.
    if wire_get(inst, :name) == "w_node_field_store"
      return ["w_node_field_store", "w_ast_freeze_if_array"]
    [wire_get(inst, :name)]
  when :slab_alloc_init
    # The intrinsic's emitted IR calls w_node_alloc (cap-exhausted slow
    # path) and w_ast_freeze_if_array (field freeze pre-pass) as raw
    # strings — neither appears as a :call_direct instruction.
    ["w_node_alloc", "w_ast_freeze_if_array"]
  when :call_direct_i64_ptr1, :call_direct_void_ptr1
    [wire_get(inst, :name)]
  when :bigint_literal_i64
    ["w_bigint_literal_cached"]
  when :call_libm_f64
    [wire_get(inst, :name)]
  when :call_num_to_f64
    ["w_num_to_f64"]
  when :call_loc_set_col
    ["__w_loc_set_col"]
  when :call_reuse_or_new_array
    ["w_array_reuse_or_new_empty"]
  when :call_reuse_or_new_hash
    ["w_hash_reuse_or_new"]
  when :call_reuse_or_new_typed
    ["w_array_reuse_or_new"]
  when :call_fused_out_reuse
    ["w_fused_out_reuse_or_new"]
  when :call_reuse_or_new_strbuf
    ["w_strbuf_reuse_or_new"]
  when :call_reuse_and_drain_or_new_hash
    ["w_hash_reuse_and_drain_or_new"]
  when :call_recycle_or_new_array
    ["w_array_recycle_or_new_empty"]
  when :call_recycle_or_new_hash
    ["w_hash_recycle_or_new"]
  when :call_recycle_or_new_typed
    ["w_array_recycle_or_new"]
  when :call_recycle_or_new_strbuf
    ["w_strbuf_recycle_or_new"]
  when :call_recycle_array
    ["w_array_recycle_public"]
  when :call_recycle_hash
    ["w_hash_recycle"]
  when :call_recycle_typed
    ["w_array_recycle"]
  when :call_recycle_strbuf
    ["w_strbuf_recycle"]
  when :cleanup_push_array
    ["w_cleanup_push", "w_array_recycle_public"]
  when :cleanup_push_hash
    ["w_cleanup_push", "w_hash_recycle"]
  when :cleanup_push_typed
    ["w_cleanup_push", "w_array_recycle"]
  when :cleanup_push_strbuf
    ["w_cleanup_push", "w_strbuf_recycle"]
  when :cleanup_pop
    ["w_cleanup_pop"]

  when :puts_i64
    ["w_puts"]
  when :print_i64
    ["w_print"]
  when :argv_init
    ["w_argv_init"]

  when :string_i64
    ["w_string"]
  when :symbol_i64
    ["w_string", "w_str_to_sym"]
  when :view_load_byte, :view_load_bit
    # Dynamic byte/bit views still produce language Integers directly.
    ["w_int"]
  when :view_load_field, :view_store_field, :view_load_inline_byte, :view_load_inline_elem, :view_store_inline_elem
    # Named fields stay in their declared machine representation; lowering
    # inserts boxing only when the value crosses a WValue boundary.
    []
  when :register_unit
    if string_wvs != nil && string_wvs[wire_get(inst, :str_id)] != nil
      ["w_register_unit_wv"]
    else
      ["w_string", "w_register_unit_wv"]

  when :class_new, :builtin_class_init
    if string_wvs != nil && string_wvs[wire_get(inst, :name_str_id)] != nil
      ["w_class_new_wv"]
    else
      ["w_string", "w_class_new_wv"]
  when :class_add_method
    splat_method = wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
    range_method = wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
    add_name = splat_method ? "w_class_add_method_splat_wv" : (range_method ? "w_class_add_method_range_wv" : "w_class_add_method_wv")
    if string_wvs != nil && string_wvs[wire_get(inst, :method_str_id)] != nil
      [add_name]
    else
      ["w_string", add_name]
  when :class_add_static_method
    splat_method = wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
    range_method = wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
    add_name = splat_method ? "w_class_add_static_method_splat_wv" : (range_method ? "w_class_add_static_method_range_wv" : "w_class_add_static_method_wv")
    if string_wvs != nil && string_wvs[wire_get(inst, :method_str_id)] != nil
      [add_name]
    else
      ["w_string", add_name]
  when :class_add_ivar
    if string_wvs != nil && string_wvs[wire_get(inst, :ivar_str_id)] != nil
      ["w_class_add_ivar_wv"]
    else
      ["w_string", "w_class_add_ivar_wv"]

  when :ivar_get
    if string_wvs != nil && string_wvs[wire_get(inst, :str_id)] != nil
      ["w_ivar_get_wv"]
    else
      ["w_string", "w_ivar_get_wv"]
  when :ivar_set
    if string_wvs != nil && string_wvs[wire_get(inst, :str_id)] != nil
      ["w_ivar_set_wv"]
    else
      ["w_string", "w_ivar_set_wv"]

  when :call_method_i64
    runtime_fns = []
    argc = 0
    if wire_get(inst, :args) != nil
      argc = wire_sequence_size(wire_get(inst, :args))
    if argc == 0
      runtime_fns.push("w_method_call_cached_0")
    elsif scalar_source_one_call?(inst)
      runtime_fns.push("w_method_call_cached_1")
    elsif scalar_source_two_call?(inst)
      runtime_fns.push("w_method_call_cached_2")
    else
      runtime_fns.push("w_method_call_cached")
    if wire_get(inst, :construct_fn) != nil
      runtime_fns.push("w_object_new")
    runtime_fns
  when :closure_new
    ["w_closure_new_a"]
  when :free_value
    ["w_value_free"]

  when :memo_init
    ["w_memo_init"]
  when :memo_call0_i64
    ["__w_memo_call0_i64"]
  when :memo_call1_i64
    ["__w_memo_call1_i64"]
  when :memo_call2_i64
    ["__w_memo_call2_i64"]

  when :setjmp
    # POSIX uses _setjmp (matching the runtime's _longjmp) while Windows uses
    # setjmp. Keep both declarations through filtering; render_instruction
    # selects the target-correct symbol.
    ["setjmp", "_setjmp"]

  when :const_decimal
    ["w_decimal"]
  when :const_currency
    ["w_currency"]
  when :const_quantity
    ["w_quantity"]
  when :const_duration_ns
    ["w_duration_ns"]
  when :const_duration_months_ms
    ["w_duration_months_ms"]
  when :const_uuid
    ["w_uuid_from_hex"]
  when :const_date
    ["w_date"]
  when :const_ipv4
    ["w_ipv4"]
  when :const_ipv6
    ["w_ipv6_from_string"]
  when :const_rational
    ["w_rational"]
  when :const_char
    ["w_box_char"]
  when :const_color
    ["w_color"]
  when :type_class_register
    ["w_type_class_register_wv"]
  when :node_kind_class_register
    ["w_node_kind_class_register_wv"]

  when :add_i48_checked, :sub_i48_checked, :mul_i48_checked
    [wire_get(inst, :rt_fallback)]
  when :add_i48_guarded, :sub_i48_guarded, :mul_i48_guarded
    [wire_get(inst, :rt_fallback)]
  else
    nil

# -- Emit a complete LLVM IR artifact --

# -- Call-site metadata table for runtime column-level error reporting --
#
# Companion to the fn-meta table: records (file, line, col) for every
# method-dispatch site that carries source-loc info. The lowering splits
# each such call into its own basic block labelled `cs.<ic_id>.ret`; we
# emit `blockaddress(@fn, %cs.N.ret)` as the lookup key. At error time,
# the innermost PC captured by `backtrace()` should land on (or right
# after) that block's first instruction, so the runtime can resolve
# the exact dispatch that failed.

-> collect_call_sites(mod)
  sites = []
  files = {}
  next_file_id = 0
  fi = 0
  while fi < mod[:functions].size()
    f = mod[:functions][fi]
    fn_path = f[:source_path]
    if fn_path == nil
      fn_path = "<unknown>"
    bi = 0
    while bi < f[:blocks].size()
      blk = f[:blocks][bi]
      ii = 0
      while ii < blk[:instructions].size()
        inst = blk[:instructions][ii]
        if wire_get(inst, :src_line) != nil
          ret_label = nil
          site_ic_id = nil
          if wire_kind(inst) == :call_method_i64
            site_ic_id = wire_get(inst, :ic_id)
            ret_label = "cs." + site_ic_id.to_s() + ".ret"
          elsif wire_kind(inst) in (:call_direct_void :call_direct_i64) && wire_get(inst, :loc_site_id) != nil
            ret_label = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
          if ret_label != nil
            file_id = files[fn_path]
            if file_id == nil
              file_id = next_file_id
              files[fn_path] = file_id
              next_file_id = next_file_id + 1
            col_val = wire_get(inst, :src_col)
            if col_val == nil
              col_val = 0
            sites.push({
              fn_name: f[:name],
              ret_label: ret_label,
              ic_id: site_ic_id,
              file_id: file_id,
              line: wire_get(inst, :src_line),
              col: col_val
            })
        ii += 1
      bi += 1
    fi += 1
  {sites: sites, files: files}

-> emit_call_site_table(mod)
  info = collect_call_sites(mod)
  sites = info[:sites]
  files = info[:files]
  out = StringBuffer(sites.size() * 120 + 512)
  lbr = "\["
  rbr = "]"

  # One private constant per unique source file path. Ids are assigned
  # first-seen, so the hash's insertion order IS id order (spec §4.2.3).
  file_keys = files.keys()
  fi = 0
  while fi < file_keys.size()
    k = file_keys[fi]
    bl = utf8_byte_length(k) + 1
    out << "@.wcs.file."
    out << fi.to_s()
    out << " = private unnamed_addr constant "
    out << lbr
    out << bl.to_s()
    out << " x i8"
    out << rbr
    out << " c\""
    out << escape_llvm_string(k)
    out << "\\00\", align 1\n"
    fi += 1
  if file_keys.size() > 0
    out << "\n"

  # The call-site array.
  out << "@__w_call_site = constant "
  out << lbr
  out << sites.size().to_s()
  out << " x { ptr, ptr, i32, i32 }"
  out << rbr
  if sites.size() == 0
    out << " zeroinitializer\n"
  else
    out << " "
    out << lbr
    out << "\n"
    si = 0
    while si < sites.size()
      s = sites[si]
      out << "  { ptr, ptr, i32, i32 } { ptr blockaddress(@"
      out << s[:fn_name]
      out << ", %"
      out << s[:ret_label]
      out << "), ptr @.wcs.file."
      out << s[:file_id].to_s()
      out << ", i32 "
      out << s[:line].to_s()
      out << ", i32 "
      out << s[:col].to_s()
      out << " }"
      if si < sites.size() - 1
        out << ","
      out << "\n"
      si += 1
    out << rbr
    out << "\n"
  out << "@__w_call_site_count = constant i32 "
  out << sites.size().to_s()
  out << "\n\n"

  # IC-site companion table, indexed by IC slot id. The blockaddress keys
  # above are only reliable at -O0 (LLVM may fold a blockaddress no
  # indirectbr consumes, collapsing it to the function entry); slot ids
  # survive every optimization level. w_method_call_slow records the
  # missing slot, and the no-method error path maps it back to
  # (file, line, col) through this table via __w_ic_base().
  max_ic = -1
  si = 0
  while si < sites.size()
    s_ic = sites[si][:ic_id]
    if s_ic != nil && s_ic > max_ic
      max_ic = s_ic
    si += 1
  if max_ic >= 0
    rows = []
    ri = 0
    while ri <= max_ic
      rows.push(nil)
      ri += 1
    si = 0
    while si < sites.size()
      s = sites[si]
      if s[:ic_id] != nil
        rows[s[:ic_id]] = s
      si += 1
    out << "@__w_ic_site = constant "
    out << lbr
    out << rows.size().to_s()
    out << " x { ptr, i32, i32 }"
    out << rbr
    out << " "
    out << lbr
    out << "\n"
    ri = 0
    while ri < rows.size()
      r = rows[ri]
      if r == nil
        out << "  { ptr, i32, i32 } { ptr null, i32 0, i32 0 }"
      else
        out << "  { ptr, i32, i32 } { ptr @.wcs.file."
        out << r[:file_id].to_s()
        out << ", i32 "
        out << r[:line].to_s()
        out << ", i32 "
        out << r[:col].to_s()
        out << " }"
      if ri < rows.size() - 1
        out << ","
      out << "\n"
      ri += 1
    out << rbr
    out << "\n"
    out << "@__w_ic_site_count = constant i32 "
    out << rows.size().to_s()
    out << "\n\n"
    # Per-thread IC base accessor: @.ic is thread_local, so slot ADDRESSES
    # cannot appear in a constant initializer and differ per thread. The
    # runtime subtracts this thread's base to recover the slot index.
    out << "define ptr @__w_ic_base() nounwind {\nentry:\n  ret ptr @.ic\n}\n\n"

  out.to_s()

# -- Function metadata table for runtime backtrace formatting --
#
# Emits a sorted-at-init `__w_fn_meta` array of {ptr fn, ptr file, ptr name,
# i32 line, i32 kind} rows — one per lowered function. Runtime walks the C
# backtrace, binary-searches by PC, and prints e.g. `Foo#bar (game.w:54)`
# instead of the mangled `__wy_…` symbol. All metadata is sourced from
# fields the lowering already attaches to each fn dict (:source_method,
# :source_class, :source_path, :source_line, :source_kind), so this pass
# is a read-only consumer.

-> fn_meta_kind_to_int(kind)
  if kind == :method
    1
  elsif kind == :static_method
    2
  elsif kind == :fn_def
    3
  elsif kind == :block
    4
  elsif kind == :entry
    5
  elsif kind == :static_wrapper
    6
  else
    0

-> fn_meta_display_name(f)
  name = f[:source_method]
  if name == nil
    name = f[:original_name]
  if name == nil
    name = f[:name]
  klass = f[:source_class]
  kind = f[:source_kind]
  if klass != nil && klass != ""
    if kind in (:static_method :static_wrapper)
      klass + "." + name
    else
      klass + "#" + name
  elsif kind == :block
    "block in " + name
  else
    name

-> emit_fn_meta_table(mod)
  fns = mod[:functions]
  out = StringBuffer(fns.size() * 200 + 256)
  lbr = "\["
  rbr = "]"

  # Per-fn private string constants for display name + source file.
  i = 0
  while i < fns.size()
    f = fns[i]
    display = fn_meta_display_name(f)
    file_str = f[:source_path]
    if file_str == nil
      file_str = "<unknown>"
    name_bl = utf8_byte_length(display) + 1
    file_bl = utf8_byte_length(file_str) + 1

    out << "@.wfm."
    out << i.to_s()
    out << ".n = private unnamed_addr constant "
    out << lbr
    out << name_bl.to_s()
    out << " x i8"
    out << rbr
    out << " c\""
    out << escape_llvm_string(display)
    out << "\\00\", align 1\n"

    out << "@.wfm."
    out << i.to_s()
    out << ".f = private unnamed_addr constant "
    out << lbr
    out << file_bl.to_s()
    out << " x i8"
    out << rbr
    out << " c\""
    out << escape_llvm_string(file_str)
    out << "\\00\", align 1\n"
    i += 1
  if fns.size() > 0
    out << "\n"

  # The meta table itself.
  out << "@__w_fn_meta = constant "
  out << lbr
  out << fns.size().to_s()
  out << " x { ptr, ptr, ptr, i32, i32 }"
  out << rbr
  if fns.size() == 0
    out << " zeroinitializer\n"
  else
    out << " "
    out << lbr
    out << "\n"
    i = 0
    while i < fns.size()
      f = fns[i]
      line = f[:source_line]
      if line == nil
        if f[:source_kind] == :entry
          line = 1
        else
          line = 0
      kind_int = fn_meta_kind_to_int(f[:source_kind])
      out << "  { ptr, ptr, ptr, i32, i32 } { ptr @"
      out << f[:name]
      out << ", ptr @.wfm."
      out << i.to_s()
      out << ".f, ptr @.wfm."
      out << i.to_s()
      out << ".n, i32 "
      out << line.to_s()
      out << ", i32 "
      out << kind_int.to_s()
      out << " }"
      if i < fns.size() - 1
        out << ","
      out << "\n"
      i += 1
    out << rbr
    out << "\n"
  out << "@__w_fn_meta_count = constant i32 "
  out << fns.size().to_s()
  out << "\n\n"

  out.to_s()

-> emit_stacktrace_llvm_used(has_ic_site = false)
  if has_ic_site
    return "@llvm.used = appending global \[6 x ptr] \[ptr @__w_fn_meta, ptr @__w_fn_meta_count, ptr @__w_call_site, ptr @__w_call_site_count, ptr @__w_ic_site, ptr @__w_ic_site_count], section \"llvm.metadata\"\n\n"
  "@llvm.used = appending global \[4 x ptr] \[ptr @__w_fn_meta, ptr @__w_fn_meta_count, ptr @__w_call_site, ptr @__w_call_site_count], section \"llvm.metadata\"\n\n"

-> address_taken_function_for_inst(inst)
  op = wire_kind(inst)
  if op in (:class_add_method :class_add_static_method :closure_new)
    return wire_get(inst, :fn_name)
  if op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
    return wire_get(inst, :fn_name)
  nil

-> collect_address_taken_functions(mod)
  taken = {}
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        fname = address_taken_function_for_inst(instrs[ii])
        if fname != nil
          taken[fname] = true
        ii += 1
      bi += 1
    fi += 1
  taken

-> internal_fastcc_candidate?(func, address_taken)
  if func[:incremental_core_candidate] == true || func[:incremental_core_frozen] == true
    return false
  if func[:llvm_internal] != true
    return false
  if func[:is_toplevel] == true
    return false
  if func[:return_type] != "i64"
    return false
  if address_taken[func[:name]] == true
    return false
  true

-> fastcc_direct_call_op?(op)
  op in (:call_direct_i64 :call_direct_i128 :call_direct_void :call_direct_ptr :call_direct_i64_ptr1 :call_direct_void_ptr1)

-> apply_fastcc_plan(mod)
  if env("TUNGSTEN_LLVM_FASTCC") != "1"
    mod[:fastcc_count] = 0
    return nil

  address_taken = collect_address_taken_functions(mod)
  fastcc_names = {}
  count = 0
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if internal_fastcc_candidate?(func, address_taken)
      func[:call_conv] = "fastcc"
      fastcc_names[func[:name]] = true
      count += 1
    fi += 1

  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if fastcc_direct_call_op?(wire_kind(inst)) && fastcc_names[wire_get(inst, :name)] == true
          wire_set(inst, :call_conv, "fastcc")
        ii += 1
      bi += 1
    fi += 1

  mod[:fastcc_count] = count
  nil

# A direct external call has one physical LLVM contract per symbol. Before
# declarations are rendered, reject WIRE that asks the same symbol to return a
# different type or accept a different physical argument list. This catches
# the historical "first call wins" behavior in ccall_needed, where a later
# mismatch survived lowering and failed only in LLVM (or linked with a wrong C
# ABI when the declaration lived in another translation unit).
-> wire_direct_call_contract(inst)
  op = wire_kind(inst)
  return_type = nil
  arg_types = []
  if op == :call_direct_i64
    return_type = "i64"
  elsif op == :call_direct_i128
    return_type = "i128"
  elsif op == :call_direct_void
    return_type = "void"
  elsif op == :call_direct_ptr
    return_type = "ptr"
  elsif op == :call_direct_i64_ptr1
    return "i64(ptr)"
  elsif op == :call_direct_void_ptr1
    return "void(ptr)"
  else
    return nil

  args = wire_get(inst, :args)
  declared_types = wire_get(inst, :arg_types)
  i = 0
  while i < wire_sequence_size(args)
    arg_type = nil
    if declared_types != nil && i < wire_sequence_size(declared_types)
      arg_type = wire_sequence_get(declared_types, i)
    if arg_type == nil || arg_type == ""
      arg_type = "i64"
    arg_types.push(arg_type)
    i += 1
  return_type + "(" + arg_types.join(",") + ")"

-> wire_fn_hash_get(fn_hashes, source)
  entry = fn_hashes[source]
  if entry == nil || entry[:source] == nil || entry[:source].size() != source.size() || entry[:source] != source
    return nil
  entry[:hash]

-> wire_hash_symbol_get(hash_symbols, hash)
  entry = hash_symbols[hash]
  if entry == nil || entry[:hash] == nil || entry[:hash].size() != hash.size() || entry[:hash] != hash
    return nil
  entry[:symbol]

-> wire_symbol_origins(mod, symbol)
  out = []
  hashes = mod[:fn_hashes]
  symbols = mod[:fn_hash_symbols]
  if hashes == nil || symbols == nil
    return out
  names = hashes.keys()
  i = 0
  while i < names.size()
    hash = wire_fn_hash_get(hashes, names[i])
    if wire_hash_symbol_get(symbols, hash) == symbol
      out.push(names[i] + "=" + hash)
    i += 1
  out

-> verify_wire_call_contracts(mod)
  contracts = {}
  target_details = {}
  tfi = 0
  while tfi < mod[:functions].size()
    target_func = mod[:functions][tfi]
    target_name = target_func[:original_name]
    if target_name == nil
      target_name = target_func[:name]
    target_arity = 0
    if target_func[:params] != nil
      target_arity = target_func[:params].size()
    target_details[target_func[:name]] = target_name + "/" + target_arity.to_s()
    tfi += 1
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instructions = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instructions.size()
        inst = instructions[ii]
        contract = wire_direct_call_contract(inst)
        if contract != nil && wire_get(inst, :name) != nil
          prior = contracts[wire_get(inst, :name)]
          if prior != nil && prior[:contract] != contract
            prior_name = prior[:function]
            current_name = func[:original_name]
            if current_name == nil
              current_name = func[:name]
            target_detail = target_details[wire_get(inst, :name)]
            if target_detail == nil
              target_detail = "external"
            origins = wire_symbol_origins(mod, wire_get(inst, :name))
            origin_detail = ""
            if origins.size() > 0
              origin_detail = "; origins " + origins.join(", ")
            return "WIRE call contract mismatch for @" + wire_get(inst, :name) + " (" + target_detail + origin_detail + "): " + prior[:contract] + " in @" + prior_name + " vs " + contract + " in @" + current_name
          current_name = func[:original_name]
          if current_name == nil
            current_name = func[:name]
          contracts[wire_get(inst, :name)] = {contract: contract, function: current_name}
        ii += 1
      bi += 1
    fi += 1
  nil
