# jsn/jit — Pure-Tungsten Speculative Optimizing ARM64 JIT Compiler for Blade JS.
#
# Compiles both:
#   1. Hot JS functions (standard 8-arg entry + optional unboxed fast recursive entry)
#   2. Hot `for` / `while` loops via On-Stack Replacement (OSR) with runtime type/shape feedback
#
# Optimizations (all general-purpose, guarded, 100% spec-exact with fallback/deopt):
#   - Unboxed int32 (W registers) and IEEE-754 f64 (D registers) arithmetic & loop counters
#   - Fused ARM64 `madd`, `fmadd`, `fmsub`, `fsqrt`, `fabs`, `frintm/p/z`
#   - Intra-procedural Escape Analysis + Scalar Replacement for object literals & closures
#   - Guarded monomorphic & 4-way polymorphic method/function inlining (PIC -> inline)
#   - Loop-invariant TypedArray, Array, GlobalCell, and Shape guard hoisting
#   - Redundant Shape Guard Elimination within basic blocks
#   - Direct dense Array `push`, `[]`, `.length`, and inlined `map`/`filter`/`reduce`/`forEach`
#   - Unboxed fast self-recursion entry with overflow fallback

in JS

# Keep all IC arrays, shapes, strings, cells referenced by JITted code alive (per-realm when a realm is active).
JIT_CODE_KEEP = []
-> jit_keep(v)
  r = JS_REALM[0]
  if r != nil && r.jit_keep != nil
    r.jit_keep.push(v)
  else
    JIT_CODE_KEEP.push(v)
  v
JIT_OSR_CACHE = {}   # loop JsNode 47-bit ptr key -> osr_fp or false
JIT_ENABLED = [Env.get("BLADE_JS_JIT", "1") != "0"]
JIT_DEBUG = [Env.get("BLADE_JS_JIT_DEBUG", "") == "1"]

# Thresholds
JIT_FN_THRESHOLD = 4
JIT_OSR_THRESHOLD = 16

# Fixed stack frame slots (above saved callee-saved regs 0..159)
JF_SLOT_ARG0  = 160   # OSR: locals_ptr | Fn: f_bits
JF_SLOT_THIS  = 168   # this_bits
JF_SLOT_ENV   = 176   # env_bits (fe)
JF_SLOT_EXTRA = 184   # OSR: fobj_bits  | Fn: argc_raw

# OSR return codes
OSR_DONE   = 0
OSR_DEOPT  = 1
OSR_RETURN = 2

+ JitLoopCtx
  rw :l_break, :l_cont, :label
  -> new(@l_break, @l_cont, @label)
    nil

+ JitCompiler
  rw :a, :info, :jf, :is_osr, :tmp_base, :tmp_depth, :max_tmp, :l_deopt, :l_ret
  rw :loops, :inline_env, :known_shapes, :hoisted_tas, :hoisted_arrs, :hoisted_cells
  rw :ta_info_slot, :osr_deopt_lbl, :in_loop_depth
  rw :free_gprs, :hoisted_arr_regs, :hoisted_ta_regs, :hoisted_epoch, :bounded_idx, :hoisted_shapes
  rw :block_prop_fp, :block_written_props, :block_prop_counts, :block_const_fp, :next_prop_fp, :cold_stubs
  rw :fast_entry_off, :repeat_entry_off, :is_slim_epilogue, :bounded_ta_set, :bounded_mod_ta, :sh_spill_slots
  rw :promoted_rw, :promoted_rw_list, :promoted_owner, :promoted_other_lis, :promoted_bail_lbl
  rw :slim_g_hi, :slim_f_hi, :mono_arr_shape, :mono_arr_num, :d_bias_reg, :prom_cached_fns

  -> new(@info)
    @a = JS:A64.new(512)
    @jf = @info.jf
    @is_osr = @info.is_osr
    @tmp_depth = 0
    @max_tmp = 0
    @loops = []
    @inline_env = nil      # nil, or Hash: JaBinding -> [:reg_x, r] | [:reg_w, r] | [:reg_d, r] | [:slot, vslot] | [:this_reg, r]
    @known_shapes = {}     # lidx -> [shape_bits, ptr_known]
    @hoisted_tas = {}      # lidx -> [off_ptr, off_len, kind]
    @hoisted_arrs = {}     # lidx -> [off_slots, off_len]
    @hoisted_cells = {}    # cell_bits -> expected_val_bits
    @hoisted_arr_regs = {} # lidx -> [slots_reg_or_nil, len_reg_or_nil]
    @hoisted_ta_regs = {}  # lidx -> [ptr_reg_or_nil, len_reg_or_nil]
    @hoisted_shapes = {}   # shape_bits -> callee-saved GPR holding shape_bits
    @sh_spill_slots = {}   # shape_bits -> positive SP offset (1 LDR instead of 3 movz/movk!)
    @block_prop_fp = {}    # "bli:sl" -> caller-saved FP reg (d18..d31) for read-only properties in pure blocks!
    @block_written_props = nil
    @block_prop_counts = nil
    @block_const_fp = {}   # f64_bits -> caller-saved FP reg (d18..d31) for hoisted loop FP literals!
    @next_prop_fp = R_D18
    @cold_stubs = []       # Out-of-line slow-path stubs emitted AFTER epilogue (ZERO taken branches in hot loops!)
    @fast_entry_off = -1
    @repeat_entry_off = -1
    @is_slim_epilogue = false
    @bounded_ta_set = {}   # "idx_lidx:ta_lidx" -> true (0 <= idx < ta.len guaranteed)
    @bounded_mod_ta = {}   # "div_lidx:ta_lidx" -> true (0 < div <= ta.len guaranteed)
    @promoted_rw = {}      # "ali:prop" -> dreg
    @promoted_rw_list = nil
    @promoted_owner = -1
    @promoted_other_lis = nil
    @promoted_bail_lbl = nil
    @slim_g_hi = R_X28
    @slim_f_hi = R_D15
    @mono_arr_shape = {}   # arr_li -> shape_bits (all elements 0..len-1 verified to have exact shape!)
    @mono_arr_num = {}     # shape_bits -> true (all inline slots of every instance in fn verified numeric!)
    @d_bias_reg = nil      # R_D15 when pinned to W_DOUBLE_BIAS (2^48) for zero-FMOV SIMD unboxing/boxing!
    @prom_cached_fns = {}  # JaFunc -> shared cached JS:Function across unrolled copies!
    @hoisted_epoch = false
    @bounded_idx = {}      # idx_lidx -> container_lidx (guaranteed 0 <= idx < container.len)
    @in_loop_depth = 0
    @i53_acc_li = -1       # active loop-promoted 64-bit integer accumulator local idx (or -1)
    @i53_acc_reg = nil     # callee-saved GPR holding @i53_acc_li during loop
    @i53_acc_bail = nil    # bail label (e.g. if charCodeAt OOB / non-int array elem)
    @inv_indexof = {}      # "sli:needle" -> GPR holding hoisted indexOf result inside loop
    @inv_str_ascii = {}    # sli -> [r_ptr, r_len_or_nil, bounded_mask_or_m1] for hoisted ASCII charCodeAt!
    @no_ovf_p1_li = -1     # loop induction local proven <= 2147483645 so `i + 1` cannot overflow i32!
    @unroll_i_li = -1      # induction local with deferred increment during 4x unrolling
    @unroll_i_off = 0      # constant offset (0..3) added on reads of @unroll_i_li!
    @i53_defer_const = nil # [accumulated_const_i64] deferred across 4x unrolled i53 loop!
    @i53_defer_regs = nil  # [[r_cap_gpr, count], ...] loop-invariant int32 regs deferred across 4x i53 loop!
    @i53_cur_body = nil    # current loop body AST inside can_2lane_4x!
    @str_cc_ics = {}       # JsNode -> i64[3] IC [str_bits, ascii_ptr, byte_len]
    @str_io_ics = {}       # JsNode -> i64[3] IC [str_bits, needle_bits, res_i64]
    # Compute unused callee-saved GPRs from R_X22..R_X28 for hoisting pointers/limits!
    used_gprs = {}
    @info.reg_gpr.values.each ->(r) used_gprs[r] = true
    @free_gprs = []
    rg = R_X22
    while rg <= R_X28
      @free_gprs.push(rg) if !used_gprs[rg]
      rg += 1
    ccall("w_value_free_w", used_gprs)
    # Layout after local spills
    sp = @info.frame_size - 128
    # Reserve 16 bytes per hoisted TypedArray + 16 bytes per hoisted Array / read-only param Array
    @info.ta_invariants.keys.each ->(li)
      @hoisted_tas[li] = [sp, sp + 8, @info.ta_invariants[li]]
      r_ptr = @free_gprs.size > 0 ? @free_gprs.pop : nil
      r_len = @free_gprs.size > 0 ? @free_gprs.pop : nil
      @hoisted_ta_regs[li] = [r_ptr, r_len]
      sp += 16
    @info.arr_invariants.keys.each ->(li)
      @hoisted_arrs[li] = [sp, sp + 8]
      r_sl = @free_gprs.size > 0 ? @free_gprs.pop : nil
      r_ln = @free_gprs.size > 0 ? @free_gprs.pop : nil
      @hoisted_arr_regs[li] = [r_sl, r_ln]
      sp += 16
    @info.param_arrs.keys.each ->(li)
      if @hoisted_arrs[li] == nil
        @hoisted_arrs[li] = [sp, sp + 8]
        r_sl = @free_gprs.size > 0 ? @free_gprs.pop : nil
        r_ln = @free_gprs.size > 0 ? @free_gprs.pop : nil
        @hoisted_arr_regs[li] = [r_sl, r_ln]
        sp += 16
    @ta_info_slot = sp
    sp += 32
    @tmp_base = sp
    @info.frame_size = ((sp + 192 + 15) / 16) * 16
    @l_deopt = @a.new_label
    @l_ret = @a.new_label

  # ---- Temp stack helpers (fixed SP-relative slots, never mutates SP!) ----

  -> push_x(reg)
    off = @tmp_base + @tmp_depth * 8
    @tmp_depth += 1
    @max_tmp = @tmp_depth if @tmp_depth > @max_tmp
    @a.str_x(reg, R_SP, off)
    off

  -> pop_x(reg)
    @tmp_depth -= 1
    off = @tmp_base + @tmp_depth * 8
    @a.ldr_x(reg, R_SP, off)
    nil

  -> push_w(reg)
    off = @tmp_base + @tmp_depth * 8
    @tmp_depth += 1
    @max_tmp = @tmp_depth if @tmp_depth > @max_tmp
    @a.str_w(reg, R_SP, off)
    off

  -> pop_w(reg)
    @tmp_depth -= 1
    off = @tmp_base + @tmp_depth * 8
    @a.ldr_w(reg, R_SP, off)
    nil

  -> push_d(dreg)
    off = @tmp_base + @tmp_depth * 8
    @tmp_depth += 1
    @max_tmp = @tmp_depth if @tmp_depth > @max_tmp
    @a.str_d(dreg, R_SP, off)
    off

  -> pop_d(dreg)
    @tmp_depth -= 1
    off = @tmp_base + @tmp_depth * 8
    @a.ldr_d(dreg, R_SP, off)
    nil

  # ---- Runtime call helpers ----
  # Calls JIT_RT_TBL[rt_idx] with captures=0 in x0, args already in x1..xN. Result in x0.
  -> call_rt(rt_idx)
    @a.movz_x(R_X0, 0)
    @a.ldr_x(R_X16, R_X19, rt_idx * 8)
    @a.blr(R_X16)
    nil

  # ---- Prologue & Epilogue ----

  -> emit_prologue
    fs = @info.frame_size
    if fs <= 4095
      @a.sub_i(R_SP, R_SP, fs)
    else
      @a.mov_imm64(R_X16, fs)
      @a.sub_r(R_SP, R_SP, R_X16)
    @a.stp_x(R_FP, R_LR, R_SP, 0)
    @a.mov_sp(R_FP, R_SP)
    @a.stp_x(R_X19, R_X20, R_SP, 16)
    @a.stp_x(R_X21, R_X22, R_SP, 32)
    @a.stp_x(R_X23, R_X24, R_SP, 48)
    @a.stp_x(R_X25, R_X26, R_SP, 64)
    @a.stp_x(R_X27, R_X28, R_SP, 80)
    @a.stp_d(R_D8,  R_D9,  R_SP, 96)
    @a.stp_d(R_D10, R_D11, R_SP, 112)
    @a.stp_d(R_D12, R_D13, R_SP, 128)
    @a.stp_d(R_D14, R_D15, R_SP, 144)
    # Pin x19 = JIT_RT_TBL, x20 = 2^48, x21 = 0xFFF0000000000001
    rt_ptr = jit_rt_init()
    @a.mov_imm64(R_X19, rt_ptr)
    @a.mov_imm64(R_X20, 281474976710656)
    @a.mov_imm64(R_X21, -4503599627370495)   # 0xFFF0000000000001 signed
    nil

  -> emit_slim_prologue
    fs = @info.frame_size
    if fs <= 4095
      @a.sub_i(R_SP, R_SP, fs)
    else
      @a.mov_imm64(R_X16, fs)
      @a.sub_r(R_SP, R_SP, R_X16)
    @a.stp_x(R_FP, R_LR, R_SP, 0)
    @a.mov_sp(R_FP, R_SP)
    if @slim_g_hi >= R_X22
      @a.stp_x(R_X22, R_X23, R_SP, 32)
      @a.stp_x(R_X24, R_X25, R_SP, 48) if @slim_g_hi >= R_X24
      @a.stp_x(R_X26, R_X27, R_SP, 64) if @slim_g_hi >= R_X26
      @a.str_x(R_X28, R_SP, 80) if @slim_g_hi >= R_X28
    if @slim_f_hi >= R_D8
      @a.stp_d(R_D8,  R_D9,  R_SP, 96)
      @a.stp_d(R_D10, R_D11, R_SP, 112) if @slim_f_hi >= R_D10
      @a.stp_d(R_D12, R_D13, R_SP, 128) if @slim_f_hi >= R_D12
      @a.stp_d(R_D14, R_D15, R_SP, 144) if @slim_f_hi >= R_D14
    nil

  -> emit_epilogue
    if @is_slim_epilogue
      if @slim_f_hi >= R_D8
        @a.ldp_d(R_D14, R_D15, R_SP, 144) if @slim_f_hi >= R_D14
        @a.ldp_d(R_D12, R_D13, R_SP, 128) if @slim_f_hi >= R_D12
        @a.ldp_d(R_D10, R_D11, R_SP, 112) if @slim_f_hi >= R_D10
        @a.ldp_d(R_D8,  R_D9,  R_SP, 96)
      if @slim_g_hi >= R_X22
        @a.ldr_x(R_X28, R_SP, 80) if @slim_g_hi >= R_X28
        @a.ldp_x(R_X26, R_X27, R_SP, 64) if @slim_g_hi >= R_X26
        @a.ldp_x(R_X24, R_X25, R_SP, 48) if @slim_g_hi >= R_X24
        @a.ldp_x(R_X22, R_X23, R_SP, 32)
    else
      @a.ldp_d(R_D14, R_D15, R_SP, 144)
      @a.ldp_d(R_D12, R_D13, R_SP, 128)
      @a.ldp_d(R_D10, R_D11, R_SP, 112)
      @a.ldp_d(R_D8,  R_D9,  R_SP, 96)
      @a.ldp_x(R_X27, R_X28, R_SP, 80)
      @a.ldp_x(R_X25, R_X26, R_SP, 64)
      @a.ldp_x(R_X23, R_X24, R_SP, 48)
      @a.ldp_x(R_X21, R_X22, R_SP, 32)
      @a.ldp_x(R_X19, R_X20, R_SP, 16)
    @a.ldp_x(R_FP, R_LR, R_SP, 0)
    fs = @info.frame_size
    if fs <= 4095
      @a.add_i(R_SP, R_SP, fs)
    else
      @a.mov_imm64(R_X16, fs)
      @a.add_r(R_SP, R_SP, R_X16)
    @a.ret
    nil

  # ---- WValue Boxing / Unboxing Primitives ----

  # Unbox WValue double in `xr` -> `dr`. Branches to `l_slow` if not a number.
  -> emit_unbox_f64(dr, xr, l_slow)
    @a.sub_r(R_X15, xr, R_X20)
    @a.cmp_r(R_X15, R_X21)
    @a.b_cond(CC_HS, l_slow)
    @a.fmov_d_x(dr, R_X15)
    nil

  # Unbox WValue -> exact int32 in `wr` (rejecting NaN, non-int, -0.0, out-of-i32).
  -> emit_unbox_exact_i32(wr, xr, l_slow)
    @a.sub_r(R_X15, xr, R_X20)
    @a.cmp_r(R_X15, R_X21)
    @a.b_cond(CC_HS, l_slow)
    # Reject -0.0 (0x8000000000000000)
    @a.mov_imm64(R_X14, -9223372036854775807 - 1)
    @a.cmp_r(R_X15, R_X14)
    @a.b_cond(CC_EQ, l_slow)
    @a.fmov_d_x(R_D16, R_X15)
    @a.fcvtzs_w_d(wr, R_D16)
    @a.scvtf_d_w(R_D17, wr)
    @a.fcmp_d(R_D16, R_D17)
    @a.b_cond(CC_NE, l_slow)
    nil

  # Box int32 in `wr` -> WValue double in `xr` (never NaN, 3 instructions!)
  -> emit_box_i32(xr, wr)
    @a.scvtf_d_w(R_D16, wr)
    @a.fmov_x_d(xr, R_D16)
    @a.add_r(xr, xr, R_X20)
    nil

  # Queue a cold slow-path stub to be emitted after the function epilogue (preserving @tmp_depth!).
  -> add_cold_stub(fn_body)
    td = @tmp_depth
    @cold_stubs.push([td, fn_body])
    nil

  -> emit_cold_stubs
    i = 0
    while i < @cold_stubs.size
      st = @cold_stubs[i]
      saved_td = @tmp_depth
      @tmp_depth = st[0]
      st[1].call()
      @tmp_depth = saved_td
      i += 1
    nil

  # Box f64 in `dr` -> WValue double in `xr` (4 straight-line insns, 0 taken branches; NaN stub out-of-line!).
  -> emit_box_f64(xr, dr)
    l_nan = @a.new_label
    l_done = @a.new_label
    @a.fmov_x_d(xr, dr)
    @a.add_r(xr, xr, R_X20)
    @a.fcmp_d(dr, dr)
    @a.b_cond(CC_VS, l_nan)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_nan)
      @a.ldr_x(xr, R_X19, RT_K_NAN_BITS * 8)
      @a.b(l_done)
    add_cold_stub(cb)
    nil

  # Box f64 in `dr` known not-NaN -> WValue double in `xr`.
  -> emit_box_f64_nonan(xr, dr)
    @a.fmov_x_d(xr, dr)
    @a.add_r(xr, xr, R_X20)
    nil

  # Convert double in `dr` -> JS ToInt32 in `wr` via ARMv8.3-A hardware `FJCVTZS Wd, Dn`!
  # Single instruction, 0 branches, 100.000% exact ECMAScript ToInt32 for ALL 2^64 doubles!
  -> emit_f64_to_i32(wr, dr)
    @a.fjcvtzs_w_d(wr, dr)
    nil

  # ---- Local Slot Load / Store ----

  -> load_slot_i32(dst_w, slot)
    r = @info.reg_gpr[slot]
    if r != nil
      if slot == @unroll_i_li && @unroll_i_off > 0
        @a.add_wi(dst_w, r, @unroll_i_off)
      else
        @a.mov_w(dst_w, r)
    else
      @a.ldr_w(dst_w, R_SP, @info.spill_off[slot])
    nil

  -> store_slot_i32(slot, src_w)
    r = @info.reg_gpr[slot]
    if r != nil
      @a.mov_w(r, src_w)
    else
      @a.str_w(src_w, R_SP, @info.spill_off[slot])
    nil

  -> load_slot_f64(dst_d, slot)
    r = @info.reg_fpr[slot]
    if r != nil
      @a.fmov_d(dst_d, r)
    else
      @a.ldr_d(dst_d, R_SP, @info.spill_off[slot])
    nil

  -> store_slot_f64(slot, src_d)
    r = @info.reg_fpr[slot]
    if r != nil
      @a.fmov_d(r, src_d)
    else
      @a.str_d(src_d, R_SP, @info.spill_off[slot])
    nil

  -> load_slot_any(dst_x, slot)
    ty = @info.types[slot]
    if ty == JT_I32
      load_slot_i32(R_X14, slot)
      emit_box_i32(dst_x, R_X14)
      return nil
    if ty == JT_F64
      load_slot_f64(R_D16, slot)
      emit_box_f64(dst_x, R_D16)
      return nil
    r = @info.reg_gpr[slot]
    if r != nil
      @a.mov_r(dst_x, r)
    else
      @a.ldr_x(dst_x, R_SP, @info.spill_off[slot])
    nil

  -> store_slot_any(slot, src_x)
    ty = @info.types[slot]
    if ty == JT_I32
      emit_unbox_exact_i32(R_X14, src_x, @l_deopt)
      store_slot_i32(slot, R_X14)
      return nil
    if ty == JT_F64
      emit_unbox_f64(R_D16, src_x, @l_deopt)
      store_slot_f64(slot, R_D16)
      return nil
    r = @info.reg_gpr[slot]
    if r != nil
      @a.mov_r(r, src_x)
    else
      @a.str_x(src_x, R_SP, @info.spill_off[slot])
    @known_shapes.delete(slot)
    nil

  # Store all live locals back into `[locals_ptr + i*8]` (for OSR exit / deopt).
  -> emit_osr_writeback(skip_sra = true)
    @a.ldr_x(R_X13, R_SP, JF_SLOT_ARG0)
    i = 0
    while i < @jf.nlocals
      ty = @info.types[i]
      if ty == JT_I32
        load_slot_i32(R_X14, i)
        emit_box_i32(R_X12, R_X14)
        @a.str_x(R_X12, R_X13, i * 8)
      elsif ty == JT_F64
        load_slot_f64(R_D16, i)
        emit_box_f64(R_X12, R_D16)
        @a.str_x(R_X12, R_X13, i * 8)
      elsif ty == JT_ANY
        load_slot_any(R_X12, i)
        @a.str_x(R_X12, R_X13, i * 8)
      elsif ty == JT_SRA_RX
        # When last exec missed (caps[31] < 0), materialize JS_NULL into locals[i]!
        caps_p = jit_arr_slots_ptr(wvalue_bits(@info.sra_rxs[i]) ## i64)
        l_skip_rx = @a.new_label
        @a.mov_imm64(R_X9, caps_p)
        @a.ldr_x(R_X10, R_X9, 248)
        @a.cmp_wi(R_X10, 0)
        @a.b_cond(CC_GE, l_skip_rx)
        @a.ldr_x(R_X12, R_X19, RT_K_NULL_BITS * 8)
        @a.str_x(R_X12, R_X13, i * 8)
        @a.bind(l_skip_rx)
      i += 1
    nil

  # ---- Compile Full Function ----
  -> compile_fn
    # Special fast path: self-recursive numeric function (e.g. fib(n))
    if @info.fast_rec
      return compile_fast_rec_fn()
    # Dual entry:
    #   offset 0 (code.jit_fp): standard entry called from Tungsten (sets x19..x21, calls l_fast_entry)
    #   @fast_entry_off (code.jit_fast_fp): JIT-to-JIT entry assuming x19..x21 are ALREADY pinned!
    l_fast_entry = @a.new_label
    @a.stp_pre(R_FP, R_LR, R_SP, -48)
    @a.stp_x(R_X19, R_X20, R_SP, 16)
    @a.str_x(R_X21, R_SP, 32)
    rt_ptr = jit_rt_init()
    @a.mov_imm64(R_X19, rt_ptr)
    @a.mov_imm64(R_X20, 281474976710656)
    @a.mov_imm64(R_X21, -4503599627370495)   # 0xFFF0000000000001 signed
    @a.bl(l_fast_entry)
    @a.ldr_x(R_X21, R_SP, 32)
    @a.ldp_x(R_X19, R_X20, R_SP, 16)
    @a.ldp_post(R_FP, R_LR, R_SP, 48)
    @a.ret

    @a.bind(l_fast_entry)
    @fast_entry_off = @a.pos * 4
    # 3-instruction native stack-overflow guard (prevents SIGBUS on deep/infinite JIT recursion!)
    l_sp_ok = @a.new_label
    @a.ldr_x(R_X9, R_X19, RT_K_SP_LIMIT * 8)
    @a.mov_sp(R_X10, R_SP)
    @a.cmp_r(R_X10, R_X9)
    @a.b_cond(CC_HS, l_sp_ok)
    @a.movz_x(R_X0, 6)    # JSR_SLOW -> bounces to Tier 0 which throws RangeError
    @a.ret
    @a.bind(l_sp_ok)
    # Candidate for counted-loop call-hoisting (`jit_repeat_fp`, x7 = repeat count >= 1):
    # pure leaf void function with <= 3 read-only params & 1 param array!
    can_repeat_cand = false
    if !@info.uses_calls && !@info.uses_env && !@jf.uses_this && !@jf.arrow && @jf.params.size <= 3 && @info.param_arrs.size == 1 && !stmts_have_return?(@jf.node.b)
      can_repeat_cand = true
      rpi = 0
      while rpi < @jf.params.size && can_repeat_cand
        rpb = @jf.params[rpi]
        if rpb.lidx >= 0
          @jf.node.b.each ->(bst) can_repeat_cand = false if stmt_writes_local?(bst, rpb.lidx)
        rpi += 1
    if can_repeat_cand
      @a.movz_x(R_X7, 1)
      @repeat_entry_off = @a.pos * 4
    @is_slim_epilogue = true
    # Compute tightest callee-saved GPR/FPR bounds for slim prologue!
    if !@info.has_loop && @info.reg_gpr.size == 0 && @info.reg_fpr.size == 0 && @hoisted_arr_regs.size == 0 && @hoisted_ta_regs.size == 0
      @slim_g_hi = 0
      @slim_f_hi = 0
    else
      @slim_g_hi = R_X28
      # Only save d14..d15 if >= 7 FPR locals or a loop needs R_D15 scratch
      @slim_f_hi = R_D15
    emit_slim_prologue()
    needs_sloppy_this = @jf.uses_this && !@jf.strict && !@jf.arrow
    # Save standard entry args only when needed (or save repeat count in unused JF_SLOT_ARG0!)
    if @info.uses_env || @info.uses_calls
      @a.str_x(R_X0, R_SP, JF_SLOT_ARG0)
    elsif can_repeat_cand
      @a.str_x(R_X7, R_SP, JF_SLOT_ARG0)
    @a.str_x(R_X1, R_SP, JF_SLOT_THIS) if @jf.uses_this
    @a.str_x(R_X2, R_SP, JF_SLOT_EXTRA) if needs_sloppy_this || @info.uses_calls
    # Extract f.@env (ivar 3, offset 32 of WObject; x0 = ptr | 4)
    if @info.uses_env || @info.uses_calls
      @a.sub_i(R_X9, R_X0, 4)
      @a.ldr_x(R_X9, R_X9, 32)
      @a.str_x(R_X9, R_SP, JF_SLOT_ENV)
    # Fast inline WObject guard for sloppy `this`: skips RT_SLOPPY_THIS & x3..x6 spills on 99.9% of method calls!
    if needs_sloppy_this
      l_sloppy_ok = @a.new_label
      l_sloppy_call = @a.new_label
      @a.sub_i(R_X9, R_X1, 4)
      @a.tst_wobj_bad(R_X9)
      @a.b_cond(CC_NE, l_sloppy_call)
      @a.cbz_x(R_X9, l_sloppy_call)
      @a.bind(l_sloppy_ok)
      cb_sl = ->()
        @a.bind(l_sloppy_call)
        @a.str_x(R_X2, R_SP, @tmp_base)
        @a.str_x(R_X3, R_SP, @tmp_base + 8)
        @a.str_x(R_X4, R_SP, @tmp_base + 16)
        @a.str_x(R_X5, R_SP, @tmp_base + 24)
        @a.str_x(R_X6, R_SP, @tmp_base + 32)
        @a.ldr_x(R_X1, R_SP, JF_SLOT_THIS)
        call_rt(RT_SLOPPY_THIS)
        @a.str_x(R_X0, R_SP, JF_SLOT_THIS)
        @a.ldr_x(R_X2, R_SP, @tmp_base)
        @a.ldr_x(R_X3, R_SP, @tmp_base + 8)
        @a.ldr_x(R_X4, R_SP, @tmp_base + 16)
        @a.ldr_x(R_X5, R_SP, @tmp_base + 24)
        @a.ldr_x(R_X6, R_SP, @tmp_base + 32)
        @a.b(l_sloppy_ok)
      add_cold_stub(cb_sl)
    # Mark parameter slots so we don't pointlessly zero-initialize them before binding!
    param_set = {}
    pi = 0
    while pi < @jf.params.size
      pb = @jf.params[pi]
      param_set[pb.lidx] = true if pb.lidx >= 0
      pi += 1
    # Bind simple parameters directly from x3..x6!
    l_fn_slow = @a.new_label
    r_argc = R_X2
    i = 0
    while i < @jf.params.size
      pb = @jf.params[i]
      if pb.lidx >= 0
        @a.mov_r(R_X9, R_X3 + i)
        @a.cmp_i(r_argc, i)
        @a.csel_x(R_X9, R_X9, R_XZR, CC_GT)
        if @info.param_ints[pb.lidx]
          # Unbox read-only integer loop-bound param ONCE in prologue (fallback to tier 0 if non-int32!)
          emit_unbox_exact_i32(R_X10, R_X9, l_fn_slow)
          store_slot_i32(pb.lidx, R_X10)
        elsif @info.param_nums[pb.lidx]
          # Unbox read-only numeric param ONCE in prologue (fallback to tier 0 if non-number!)
          emit_unbox_f64(R_D16, R_X9, l_fn_slow)
          store_slot_f64(pb.lidx, R_D16)
        else
          store_slot_any(pb.lidx, R_X9)
      i += 1
    # Guard global TypedArray constructors for @info.local_tas ONCE at entry (zero mutations on fallback!)
    if @info.local_tas.size > 0
      r_cur = js_realm()
      ta_names = ["Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array", "Uint32Array", "Float32Array", "Float64Array"]
      checked_tk = {}
      @info.local_tas.values.each ->(tk)
        if !checked_tk[tk] && tk >= 0 && tk < ta_names.size
          checked_tk[tk] = true
          tnm = ta_names[tk]
          ctor_v = r_cur.intrinsics[tnm]
          gcell = r_cur.global.get_own(tnm)
          if ctor_v == nil
            @a.b(l_fn_slow)
          else
            # Verify global cell for tnm still equals intrinsic ctor_v
            b_ta = @jf.analysis.funcs[0].scope.names[tnm]
            if b_ta != nil && b_ta.global?
              tc = wk_cell(b_ta)
              jit_keep(tc)
              jit_keep(ctor_v)
              @a.mov_imm64(R_X9, (wvalue_bits(tc) ## i64) - 4)
              @a.ldr_x(R_X10, R_X9, 8)
              @a.mov_imm64(R_X11, wvalue_bits(ctor_v) ## i64)
              @a.cmp_r(R_X10, R_X11)
              @a.b_cond(CC_NE, l_fn_slow)
            else
              @a.b(l_fn_slow)
    # Guard JS_EPOCH ONCE at entry if needed for string/array intrinsics, and hoist epoch if body is pure!
    if @info.needs_entry_epoch || (@info.has_loop && @jf.node.b.is_a?(Array))
      all_ep_pure = @jf.node.b.is_a?(Array)
      if all_ep_pure
        ei_chk = 0
        while ei_chk < @jf.node.b.size && all_ep_pure
          all_ep_pure = false if !osr_loop_pure_epoch?(@jf.node.b[ei_chk])
          ei_chk += 1
      if @info.needs_entry_epoch || all_ep_pure
        ep_now = JS_EPOCH[0]
        @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
        @a.ldr_x(R_X10, R_X9, 0)
        @a.mov_imm64(R_X11, ep_now)
        @a.cmp_r(R_X10, R_X11)
        @a.b_cond(CC_NE, l_fn_slow)
        @hoisted_epoch = true if all_ep_pure
    # Initialize non-parameter locals to undefined (0), deduplicating coalesced registers!
    zeroed_gprs = {}
    i = 0
    while i < @jf.nlocals
      if !param_set[i]
        ty = @info.types[i]
        if ty == JT_ANY || ty == JT_I32
          r = @info.reg_gpr[i]
          if r != nil
            if !zeroed_gprs[r]
              @a.movz_x(r, 0)
              zeroed_gprs[r] = true
          elsif ty == JT_ANY
            @a.str_x(R_XZR, R_SP, @info.spill_off[i])
          else
            @a.str_w(R_XZR, R_SP, @info.spill_off[i])
        elsif ty == JT_F64
          r = @info.reg_fpr[i]
          if r != nil
            @a.fmov_d_x(r, R_XZR)
          else
            @a.str_x(R_XZR, R_SP, @info.spill_off[i])
      i += 1
    # Guard & hoist read-only dense Array parameters ONCE in prologue (fallback to tier 0 if non-dense!)
    @info.param_arrs.keys.each ->(li)
      h = @hoisted_arrs[li]
      load_slot_any(R_X9, li)
      @a.lsr_xi(R_X10, R_X9, 48)
      @a.movz_x(R_X11, 0xFFF4)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_fn_slow)
      @a.and_x_ptr47(R_X9, R_X9)
      @a.ldrb(R_X10, R_X9, 2)
      @a.cmp_wi(R_X10, 1)
      @a.b_cond(CC_NE, l_fn_slow)
      @a.ldr_w(R_X10, R_X9, 4)   # start == 0
      @a.cbnz_w(R_X10, l_fn_slow)
      @a.ldr_x(R_X10, R_X9, 16)  # slots ptr
      @a.str_x(R_X10, R_SP, h[0])
      ar = @hoisted_arr_regs[li]
      @a.mov_r(ar[0], R_X10) if ar != nil && ar[0] != nil
      @a.ldrsw(R_X10, R_X9, 8)   # size
      @a.str_x(R_X10, R_SP, h[1])
      @a.mov_r(ar[1], R_X10) if ar != nil && ar[1] != nil
    # Hoist observed warm monomorphic shapes into free GPRs (or 1-LDR stack spill slots when GPRs are full)!
    mono_sh = 0
    if @jf.node.b.is_a?(Array)
      mc = {}
      collect_warm_shape_uses(@jf.node.b, mc)
      sh_sp_idx = 0
      n_sh = 0
      mc.values.each ->(e)
        if e[2] && e[0] != 0
          mono_sh = e[0]
          n_sh += 1
          if @hoisted_shapes[e[0]] == nil && @sh_spill_slots[e[0]] == nil
            if @free_gprs.size > 0
              rg = @free_gprs.pop
              @a.mov_imm64(rg, e[0])
              @hoisted_shapes[e[0]] = rg
            elsif sh_sp_idx < 4
              off = @ta_info_slot + sh_sp_idx * 8
              @a.mov_imm64(R_X9, e[0])
              @a.str_x(R_X9, R_SP, off)
              @sh_spill_slots[e[0]] = off
              sh_sp_idx += 1
      # If function has a read-only dense Array param, no non-Math calls, and one unique element shape:
      # verify ONCE in prologue that every arr[0..len-1] has `mono_sh` (else JSR_SLOW -> tier 0, zero mutations)!
      if mono_sh != 0 && @info.param_arrs.size == 1 && @hoisted_shapes[mono_sh] != nil
        all_pure = true
        si = 0
        while si < @jf.node.b.size && all_pure
          all_pure = false if !osr_loop_pure_epoch?(@jf.node.b[si])
          si += 1
        if all_pure
          arr_li = @info.param_arrs.keys[0]
          ar = @hoisted_arr_regs[arr_li]
          r_sh = @hoisted_shapes[mono_sh]
          if ar != nil && ar[0] != nil && ar[1] != nil
            l_chk = @a.new_label
            l_chk_ok = @a.new_label
            @a.movz_x(R_X9, 0)
            @a.cmp_r(R_X9, ar[1])
            @a.b_cond(CC_GE, l_chk_ok)
            @a.bind(l_chk)
            @a.ldr_x_idx(R_X10, ar[0], R_X9)
            @a.sub_i(R_X11, R_X10, 4)
            @a.tst_wobj_bad(R_X11)
            @a.b_cond(CC_NE, l_fn_slow)
            @a.ldr_x(R_X12, R_X11, 8)
            @a.cmp_r(R_X12, r_sh)
            @a.b_cond(CC_NE, l_fn_slow)
            @a.add_i(R_X9, R_X9, 1)
            @a.cmp_r(R_X9, ar[1])
            @a.b_cond(CC_LT, l_chk)
            @a.bind(l_chk_ok)
            @mono_arr_shape[arr_li] = mono_sh
            # Check if ALL non-array params are numeric, no object/global leaks, and all member writes are f64!
            # If so, verify ONCE that all inline slots of arr[0..len-1] are numbers -> enables zero-tag-check
            # pure SIMD FP loads (`ldr d; sub d, d, d17`) AND 100% sound jit_repeat_fp!
            sh_obj = wvalue_from_bits(mono_sh)
            n_keys = sh_obj.is_a?(JS:Shape) ? sh_obj.key_list.size : 99
            num_ok = !@info.uses_calls && !@info.uses_env && !@jf.uses_this && n_keys > 0 && n_keys <= sh_obj.inline && stmts_pure_num_obj_fn?(@jf.node.b)
            if num_ok
              pi_chk = 0
              while pi_chk < @jf.params.size && num_ok
                pli = @jf.params[pi_chk].lidx
                if pli >= 0 && pli != arr_li
                  pty = @info.types[pli]
                  num_ok = false if pty != JT_F64 && pty != JT_I32
                pi_chk += 1
            if num_ok
              l_num_done = @a.new_label
              l_num_lp = @a.new_label
              @a.movz_x(R_X9, 0)
              @a.cmp_r(R_X9, ar[1])
              @a.b_cond(CC_GE, l_num_done)
              @a.bind(l_num_lp)
              @a.ldr_x_idx(R_X10, ar[0], R_X9)
              @a.sub_i(R_X11, R_X10, 4)
              ski = 0
              while ski < n_keys
                @a.ldr_x(R_X12, R_X11, (sh_obj.ibase + ski + 1) * 8)
                @a.sub_r(R_X15, R_X12, R_X20)
                @a.cmp_r(R_X15, R_X21)
                @a.b_cond(CC_HS, l_fn_slow)
                ski += 1
              @a.add_i(R_X9, R_X9, 1)
              @a.cmp_r(R_X9, ar[1])
              @a.b_cond(CC_LT, l_num_lp)
              @a.bind(l_num_done)
              @mono_arr_num[mono_sh] = true
            elsif can_repeat_cand
              @repeat_entry_off = -1
      @repeat_entry_off = -1 if can_repeat_cand && @mono_arr_shape.size == 0
      # Hoist up to 3 FP literal constants (e.g. `1.00000001`, `0.0000001`, `0.01`) into free callee-saved FPRs ONCE!
      avail_fc = 7 - @info.reg_fpr.size   # leaves R_D15 free for scratch!
      if avail_fc >= 1
        fcs = []
        @jf.node.b.each ->(st) collect_fp_consts(st, fcs)
        fci = 0
        while fci < fcs.size && fci < avail_fc && fci < 3
          freg = R_D14 - fci
          @a.mov_imm64(R_X9, fcs[fci])
          @a.fmov_d_x(freg, R_X9)
          @block_const_fp[fcs[fci]] = freg
          fci += 1
    # Pin caller-saved R_D17 = W_DOUBLE_BIAS (2^48) in leaf functions for zero-FMOV SIMD stores!
    # Leaves R_D15 100% free for zero-spill FP binary ops in gen_expr_f64!
    if !@info.uses_calls && @info.has_loop
      @a.fmov_d_x(R_D17, R_X20)
      @d_bias_reg = R_D17
    # Body
    n = @jf.node
    if @jf.arrow && n.has?(F_EXPR_BODY)
      gen_expr_any(n.b)
      @a.b(@l_ret)
    else
      emit_hoist_functions(n.b)
      l_repeat_body = nil
      if can_repeat_cand && @repeat_entry_off >= 0
        l_repeat_body = @a.new_label
        @a.bind(l_repeat_body)
      gen_stmts(n.b)
      if l_repeat_body != nil
        @a.ldr_x(R_X9, R_SP, JF_SLOT_ARG0)
        @a.sub_i(R_X9, R_X9, 1)
        @a.str_x(R_X9, R_SP, JF_SLOT_ARG0)
        @a.cbnz_x(R_X9, l_repeat_body)
      @a.movz_x(R_X0, 0)   # return undefined
    @a.bind(@l_ret)
    emit_epilogue()
    @a.bind(l_fn_slow)
    @a.movz_x(R_X0, 6)     # JSR_SLOW -> cleanly delegate to wk_call_tier0 (zero mutations happened!)
    emit_epilogue()
    @a.bind(@l_deopt)
    @a.movz_x(R_X0, 0)
    emit_epilogue()
    emit_cold_stubs()
    @a.finalize

  # ---- Compile Fast Self-Recursive Numeric Function (e.g. fib(n)) ----
  # Standard entry checks: argc >= 1, a0 is exact int32, global cell == f.
  # Calls `l_fast(w0) -> x0 (sign-extended i32, or 0x8000000000000000 on overflow)`.
  # If guard fails or int32 overflows, falls back seamlessly to `l_f64(d0) -> d0`!
  -> compile_fast_rec_fn
    l_fast = @a.new_label
    l_f64 = @a.new_label
    l_slow_entry = @a.new_label
    ret_e = jit_inline_return_expr(@jf)
    self_b = @jf.binding

    # === Standard JS entry: (x0=f, x1=this, x2=argc, x3=a0, ...) ===
    @a.stp_pre(R_FP, R_LR, R_SP, -48)
    @a.stp_x(R_X19, R_X20, R_SP, 16)
    @a.stp_x(R_X21, R_X22, R_SP, 32)
    @a.mov_imm64(R_X19, jit_rt_init())
    @a.mov_imm64(R_X20, 281474976710656)    # W_DOUBLE_BIAS
    @a.ldr_x(R_X21, R_X19, RT_K_SP_LIMIT * 8)   # stack guard limit kept live in x21 across recursion
    # Check global cell still holds `f` (if global)
    if @info.fast_rec_cell != nil
      jit_keep(@info.fast_rec_cell)
      cptr = (wvalue_bits(@info.fast_rec_cell) ## i64) - 4
      @a.mov_imm64(R_X9, cptr)
      @a.ldr_x(R_X10, R_X9, 8)              # cell.@fast
      @a.cmp_r(R_X10, R_X0)
      @a.b_cond(CC_NE, l_slow_entry)
    # Check argc >= 1
    @a.cmp_i(R_X2, 1)
    @a.b_cond(CC_LT, l_slow_entry)
    # Check a0 (x3) is a number
    @a.sub_r(R_X9, R_X3, R_X20)
    @a.mov_imm64(R_X10, -4503599627370495)  # 0xFFF0000000000001
    @a.cmp_r(R_X9, R_X10)
    @a.b_cond(CC_HS, l_slow_entry)
    # Check if exact int32 (and not -0.0)
    @a.fmov_d_x(R_D0, R_X9)
    @a.fcvtzs_w_d(R_X11, R_D0)
    @a.scvtf_d_w(R_D1, R_X11)
    @a.fcmp_d(R_D0, R_D1)
    @a.b_cond(CC_NE, l_f64)
    # Call fast i32 recursive kernel!
    @a.mov_w(R_X0, R_X11)
    @a.bl(l_fast)
    # Check overflow sentinel (bit 62 != bit 63, or compare against 0x4000000000000000)
    @a.mov_imm64(R_X10, 0x4000000000000000)
    @a.cmp_r(R_X0, R_X10)
    @a.b_cond(CC_EQ, l_f64)
    # Box i32 result in w0 -> x0
    @a.scvtf_d_w(R_D0, R_X0)
    @a.fmov_x_d(R_X0, R_D0)
    @a.add_r(R_X0, R_X0, R_X20)
    @a.ldp_x(R_X21, R_X22, R_SP, 32)
    @a.ldp_x(R_X19, R_X20, R_SP, 16)
    @a.ldp_post(R_FP, R_LR, R_SP, 48)
    @a.ret

    # === Fallback: f64 / slow via wk_call ===
    @a.bind(l_f64)
    @a.bind(l_slow_entry)
    # Note: for non-int32 or overflow or rebound global, delegate cleanly to tier 0 wk_call!
    # We reconstruct a call to a helper that runs wk_call directly.
    @a.ldp_x(R_X21, R_X22, R_SP, 32)
    @a.ldp_x(R_X19, R_X20, R_SP, 16)
    @a.ldp_post(R_FP, R_LR, R_SP, 48)
    # Return sentinel JSR_SLOW (6) so js_dispatch runs wk_call!
    @a.movz_x(R_X0, 6)
    @a.ret

    # === Unboxed i32 recursive kernel: l_fast(w0) -> x0 (sign-extended i32, or 0x4000000000000000 on overflow) ===
    @a.bind(l_fast)
    l_frec_sp_ok = @a.new_label
    @a.mov_sp(R_X10, R_SP)
    @a.cmp_r(R_X10, R_X21)
    @a.b_cond(CC_HS, l_frec_sp_ok)
    @a.mov_imm64(R_X0, 0x4000000000000000)
    @a.ret
    @a.bind(l_frec_sp_ok)
    emit_fast_rec_body(ret_e, self_b, l_fast)
    @a.finalize

  # Emit ultra-tight ARM64 for `n < 2 ? n : fib(n-1) + fib(n-2)` and general 1-arg recursive i32 exprs!
  -> emit_fast_rec_body(e, self_b, l_fast)
    # Fast-path recognition for `cond ? base_expr : rec_expr` (zero stack frame on base case!)
    if e.kind == :cond && !fast_rec_has_call?(e.a, self_b) && !fast_rec_has_call?(e.b, self_b)
      l_rec = @a.new_label
      emit_fast_rec_branch_false(e.a, l_rec)
      emit_fast_rec_leaf(e.b, R_X0)
      @a.ret
      @a.bind(l_rec)
      @a.stp_pre(R_FP, R_LR, R_SP, -32)
      @a.stp_x(R_X19, R_X20, R_SP, 16)
      @a.mov_w(R_X19, R_X0)    # save param n in w19
      emit_fast_rec_eval(e.c, self_b, l_fast)
      @a.ldp_x(R_X19, R_X20, R_SP, 16)
      @a.ldp_post(R_FP, R_LR, R_SP, 32)
      @a.ret
      return nil
    @a.stp_pre(R_FP, R_LR, R_SP, -32)
    @a.stp_x(R_X19, R_X20, R_SP, 16)
    @a.mov_w(R_X19, R_X0)
    emit_fast_rec_eval(e, self_b, l_fast)
    @a.ldp_x(R_X19, R_X20, R_SP, 16)
    @a.ldp_post(R_FP, R_LR, R_SP, 32)
    @a.ret
    nil

  -> fast_rec_has_call?(e, self_b)
    return false if e == nil
    return true if e.kind == :call
    return fast_rec_has_call?(e.a, self_b) || fast_rec_has_call?(e.b, self_b) if e.kind == :binary
    return fast_rec_has_call?(e.a, self_b) || fast_rec_has_call?(e.b, self_b) || fast_rec_has_call?(e.c, self_b) if e.kind == :cond
    false

  -> emit_fast_rec_leaf(e, dst)
    if e.kind == :num
      @a.mov_imm32(dst, e.a.to_i)
    elsif e.kind == :ident
      @a.mov_w(dst, R_X0) if dst != R_X0
    elsif e.kind == :binary
      emit_fast_rec_leaf(e.a, R_X9)
      emit_fast_rec_leaf(e.b, R_X10)
      if e.str == "+"
        @a.add_w(dst, R_X9, R_X10)
      elsif e.str == "-"
        @a.sub_w(dst, R_X9, R_X10)
    nil

  -> emit_fast_rec_branch_false(cond, l_false)
    if cond.kind == :binary
      op = cond.str
      if cond.a.kind == :ident && cond.b.kind == :num && cond.b.a.to_i >= 0 && cond.b.a.to_i <= 4095
        @a.cmp_wi(R_X0, cond.b.a.to_i)
      else
        emit_fast_rec_leaf(cond.a, R_X9)
        emit_fast_rec_leaf(cond.b, R_X10)
        @a.cmp_w(R_X9, R_X10)
      cc = op == "<" ? CC_GE : (op == "<=" ? CC_GT : (op == ">" ? CC_LE : (op == ">=" ? CC_LT : (op == "===" || op == "==" ? CC_NE : CC_EQ))))
      @a.b_cond(cc, l_false)
      return nil
    @a.cbz_w(R_X0, l_false)
    nil

  # Evaluate recursive expression with param n saved in w19; result in x0 (or overflow sentinel).
  -> emit_fast_rec_eval(e, self_b, l_fast)
    if e.kind == :num
      @a.mov_imm32(R_X0, e.a.to_i)
      @a.sxtw(R_X0, R_X0)
      return nil
    if e.kind == :ident
      @a.sxtw(R_X0, R_X19)
      return nil
    if e.kind == :call
      # Evaluate argument into w0, call l_fast
      arg = e.list[0]
      if arg.kind == :binary && arg.a.kind == :ident && arg.b.kind == :num && arg.b.a.to_i >= 0 && arg.b.a.to_i <= 4095
        if arg.str == "-"
          @a.sub_wi(R_X0, R_X19, arg.b.a.to_i)
        elsif arg.str == "+"
          @a.add_wi(R_X0, R_X19, arg.b.a.to_i)
        else
          emit_fast_rec_eval(arg, self_b, l_fast)
      else
        emit_fast_rec_eval(arg, self_b, l_fast)
      @a.bl(l_fast)
      return nil
    if e.kind == :binary && (e.str == "+" || e.str == "-")
      l_ovf = @a.new_label
      l_done = @a.new_label
      emit_fast_rec_eval(e.a, self_b, l_fast)
      # Propagate overflow sentinel from left
      @a.mov_imm64(R_X10, 0x4000000000000000)
      @a.cmp_r(R_X0, R_X10)
      @a.b_cond(CC_EQ, l_done)
      @a.mov_r(R_X20, R_X0)   # save left result in x20
      emit_fast_rec_eval(e.b, self_b, l_fast)
      @a.mov_imm64(R_X10, 0x4000000000000000)
      @a.cmp_r(R_X0, R_X10)
      @a.b_cond(CC_EQ, l_done)
      if e.str == "+"
        @a.adds_w(R_X0, R_X20, R_X0)
      else
        @a.subs_w(R_X0, R_X20, R_X0)
      @a.b_cond(CC_VS, l_ovf)
      @a.sxtw(R_X0, R_X0)
      @a.b(l_done)
      @a.bind(l_ovf)
      @a.mov_imm64(R_X0, 0x4000000000000000)
      @a.bind(l_done)
      return nil
    if e.kind == :cond
      l_else = @a.new_label
      l_end = @a.new_label
      @a.mov_w(R_X0, R_X19)
      emit_fast_rec_branch_false(e.a, l_else)
      emit_fast_rec_eval(e.b, self_b, l_fast)
      @a.b(l_end)
      @a.bind(l_else)
      emit_fast_rec_eval(e.c, self_b, l_fast)
      @a.bind(l_end)
      return nil
    @a.mov_imm64(R_X0, 0x4000000000000000)
    nil

  # ---- Compile OSR Loop ----
  # Entry signature: i64 osr(i64 locals_ptr, i64 env_bits, i64 this_bits, i64 fobj_bits)
  # Returns: 0 = loop finished normally, 1 = deopt (locals written back), 2 = return (rv in locals[nlocals])
  -> compile_osr(act)
    emit_prologue()
    @a.str_x(R_X0, R_SP, JF_SLOT_ARG0)
    @a.str_x(R_X1, R_SP, JF_SLOT_ENV)
    @a.str_x(R_X2, R_SP, JF_SLOT_THIS)
    @a.str_x(R_X3, R_SP, JF_SLOT_EXTRA)

    # Load all live locals from [locals_ptr + i*8] into registers/spill slots.
    # Before mutating anything, if any entry guard fails, return OSR_DEOPT immediately!
    l_entry_deopt = @a.new_label
    @a.mov_r(R_X13, R_X0)   # x13 = locals_ptr
    i = 0
    while i < @jf.nlocals
      ty = @info.types[i]
      if ty == JT_I32
        @a.ldr_x(R_X9, R_X13, i * 8)
        emit_unbox_exact_i32(R_X10, R_X9, l_entry_deopt)
        store_slot_i32(i, R_X10)
      elsif ty == JT_F64
        @a.ldr_x(R_X9, R_X13, i * 8)
        emit_unbox_f64(R_D16, R_X9, l_entry_deopt)
        store_slot_f64(i, R_D16)
      elsif ty == JT_ANY
        @a.ldr_x(R_X9, R_X13, i * 8)
        r = @info.reg_gpr[i]
        if r != nil
          @a.mov_r(r, R_X9)
        else
          @a.str_x(R_X9, R_SP, @info.spill_off[i])
      i += 1

    # Hoist loop-invariant TypedArray metadata (raw_ptr, len) and verify kind + not detached!
    @hoisted_tas.keys.each ->(li)
      h = @hoisted_tas[li]
      off_ptr = h[0]
      off_len = h[1]
      want_kind = h[2]
      ta_out = i64[4]
      jit_keep(ta_out)
      load_slot_any(R_X1, li)
      @a.mov_imm64(R_X2, wvalue_bits(ta_out) ## i64)
      call_rt(RT_TA_INFO)
      @a.cmp_i(R_X0, 2)   # true == 2
      @a.b_cond(CC_NE, l_entry_deopt)
      @a.mov_imm64(R_X9, jit_i64_ptr(ta_out))
      @a.ldr_x(R_X10, R_X9, 16)  # kind
      @a.cmp_i(R_X10, want_kind)
      @a.b_cond(CC_NE, l_entry_deopt)
      @a.ldr_x(R_X10, R_X9, 0)   # raw_ptr
      @a.str_x(R_X10, R_SP, off_ptr)
      tr = @hoisted_ta_regs[li]
      @a.mov_r(tr[0], R_X10) if tr != nil && tr[0] != nil
      @a.ldr_x(R_X10, R_X9, 8)   # len
      @a.str_x(R_X10, R_SP, off_len)
      @a.mov_r(tr[1], R_X10) if tr != nil && tr[1] != nil

    # Hoist loop-invariant Array metadata (slots_ptr, len) for dense plain arrays
    @hoisted_arrs.keys.each ->(li)
      h = @hoisted_arrs[li]
      load_slot_any(R_X9, li)
      # Verify W_TAG_ARRAY (0xFFF4) and aflags == 1 and start == 0
      @a.lsr_xi(R_X10, R_X9, 48)
      @a.movz_x(R_X11, 0xFFF4)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_entry_deopt)
      @a.and_x_ptr47(R_X9, R_X9)
      @a.ldrb(R_X10, R_X9, 2)
      @a.cmp_wi(R_X10, 1)
      @a.b_cond(CC_NE, l_entry_deopt)
      @a.ldr_w(R_X10, R_X9, 4)   # start == 0
      @a.cbnz_w(R_X10, l_entry_deopt)
      @a.ldr_x(R_X10, R_X9, 16)  # slots ptr
      @a.str_x(R_X10, R_SP, h[0])
      ar = @hoisted_arr_regs[li]
      @a.mov_r(ar[0], R_X10) if ar != nil && ar[0] != nil
      @a.ldrsw(R_X10, R_X9, 8)   # size
      @a.str_x(R_X10, R_SP, h[1])
      @a.mov_r(ar[1], R_X10) if ar != nil && ar[1] != nil

    # Hoist JS_EPOCH[0] check ONCE at OSR entry if the loop makes NO mutating calls!
    if osr_loop_pure_epoch?(@info.loop_node)
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_entry_deopt)
      @hoisted_epoch = true

    # Hoist up to 2 observed polymorphic call-site shape addresses into free GPRs!
    if @free_gprs.size > 0
      poly_shs = []
      collect_poly_shapes(@info.loop_node, poly_shs)
      pi = 0
      while pi < poly_shs.size && @free_gprs.size > 0
        sh = poly_shs[pi]
        sb = wvalue_bits(sh) ## i64
        if @hoisted_shapes[sb] == nil
          jit_keep(sh)
          rg = @free_gprs.pop
          @a.mov_imm64(rg, sb)
          @hoisted_shapes[sb] = rg
        pi += 1

    # Hoist SRA closure factory cell identity checks ONCE before the loop!
    @info.sra_clos.values.each ->(sc)
      cell = wk_cell(sc.factory_binding)
      jit_keep(cell)
      jit_keep(sc.factory_fn)
      cptr = (wvalue_bits(cell) ## i64) - 4
      @a.mov_imm64(R_X9, cptr)
      @a.ldr_x(R_X10, R_X9, 8)   # cell.@fast
      @a.mov_imm64(R_X11, wvalue_bits(sc.factory_fn) ## i64)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_entry_deopt)
      @hoisted_cells[wvalue_bits(cell) ## i64] = wvalue_bits(sc.factory_fn) ## i64

    # Hoist up to 3 FP literal constants into unused callee-saved FPRs ONCE at OSR entry!
    avail_osr_fc = 7 - @info.reg_fpr.size
    if avail_osr_fc >= 1
      fcs = []
      collect_fp_consts(@info.loop_node, fcs)
      fci = 0
      while fci < fcs.size && fci < avail_osr_fc && fci < 3
        freg = R_D14 - fci
        @a.mov_imm64(R_X9, fcs[fci])
        @a.fmov_d_x(freg, R_X9)
        @block_const_fp[fcs[fci]] = freg
        fci += 1

    # Emit the OSR loop body (test -> body -> update -> repeat)
    s = @info.loop_node
    @in_loop_depth = 1
    if s.kind == :for
      gen_for_loop(s, false)   # init already ran in tier 0!
    else
      gen_while_loop(s)
    @in_loop_depth = 0

    # Normal loop exit: write back all locals and return OSR_DONE (0)
    emit_osr_writeback()
    @a.movz_x(R_X0, OSR_DONE)
    emit_epilogue()

    # Return statement inside OSR loop: save rv (x0) at locals[nlocals], write back, return OSR_RETURN (2)
    @a.bind(@l_ret)
    @a.ldr_x(R_X13, R_SP, JF_SLOT_ARG0)
    @a.str_x(R_X0, R_X13, @jf.nlocals * 8)
    emit_osr_writeback()
    @a.movz_x(R_X0, OSR_RETURN)
    emit_epilogue()

    # Mid-loop deopt: write back current locals and return OSR_DEOPT (1)
    @a.bind(@l_deopt)
    emit_osr_writeback()
    @a.movz_x(R_X0, OSR_DEOPT)
    emit_epilogue()

    # Entry guard deopt (nothing mutated yet): return OSR_DEOPT (1) immediately
    @a.bind(l_entry_deopt)
    @a.movz_x(R_X0, OSR_DEOPT)
    emit_epilogue()
    emit_cold_stubs()

    @a.finalize

  # ---- Statements ----

  -> emit_hoist_functions(stmts)
    return nil if stmts == nil
    i = 0
    while i < stmts.size
      s = stmts[i]
      if s.kind == :function_decl && s.str != nil
        jf = s.x
        b = jf.binding
        code = wk_code(jf)
        jit_keep(code)
        if jf.single != nil
          r = jf.single_ref
          if r == nil
            r = JaRef.new(jf.single, jf.def_scope)
            jf.single_ref = r
          emit_read_binding_any(r.binding, R_X2, r)
        elsif jf.free.size == 0
          @a.movz_x(R_X2, 0)
        else
          @a.ldr_x(R_X2, R_SP, JF_SLOT_ENV)
        @a.mov_imm64(R_X1, wvalue_bits(code) ## i64)
        call_rt(RT_CLOSURE)
        emit_write_binding(b, R_X0, true)
      i += 1
    nil

  # Recognize `var a = []; for (var i = 0; i < LIMIT; i++) a.push(val_e);` where `a` is a fresh unaliased local array!
  # Pre-reserves exact capacity ONCE via RT_ARR_NEW_EMPTY_CAP and writes directly into `a->slots[i]` in a 2x-unrolled loop!
  -> try_gen_prereserved_push_loop(s0, s1)
    return false if @is_osr || @in_loop_depth > 0 || @free_gprs.size < 1
    return false if s0 == nil || s1 == nil || s0.kind != :var_decl || s0.list.size != 1 || s1.kind != :for
    d0 = s0.list[0]
    return false if d0 == nil || d0.a.kind != :ident || d0.b == nil || d0.b.kind != :array || d0.b.list.size != 0
    ali = local_idx(d0.a)
    return false if ali < 0 || @info.types[ali] != JT_ANY
    # Verify loop: `for (var i = 0; i < LIMIT; i++) a.push(val_e);`
    return false if s1.a == nil || s1.b == nil || s1.c == nil || s1.b.kind != :binary || s1.b.str != "<"
    return false if s1.c.kind != :update || s1.c.str != "++" || s1.c.a.kind != :ident
    li = local_idx(s1.b.a)
    return false if li < 0 || li == ali || li != local_idx(s1.c.a) || @info.types[li] != JT_I32
    ri = @info.reg_gpr[li]
    return false if ri == nil
    init_rhs = nil
    if s1.a.kind == :var_decl && s1.a.list.size == 1 && local_idx(s1.a.list[0].a) == li
      init_rhs = s1.a.list[0].b
    elsif s1.a.kind == :assign && s1.a.str == "=" && local_idx(s1.a.a) == li
      init_rhs = s1.a.b
    return false if init_rhs == nil || init_rhs.kind != :num || init_rhs.a != ~0.0
    lim_kind = 0
    lim_val = 0
    lim_reg = nil
    eb = s1.b.b
    if eb.kind == :num && jit_int32_lit?(eb) && eb.a.to_i > 0 && eb.a.to_i <= 4194304
      lim_kind = 1
      lim_val = eb.a.to_i
    elsif eb.kind == :ident
      lli = local_idx(eb)
      if lli >= 0 && lli != li && lli != ali && @info.types[lli] == JT_I32 && @info.reg_gpr[lli] != nil
        lim_kind = 2
        lim_reg = @info.reg_gpr[lli]
    return false if lim_kind == 0
    st = s1.d
    st = st.list[0] if st.is_a?(JsNode) && st.kind == :block && st.list.size == 1
    return false if !st.is_a?(JsNode) || st.kind != :expr_stmt || st.a == nil
    ce = st.a
    return false if ce.kind != :call || ce.a.kind != :member || ce.a.has?(F_COMPUTED) || ce.a.b.str != "push" || ce.list.size != 1
    return false if local_idx(ce.a.a) != ali
    val_e = ce.list[0]
    return false if !can_i32?(val_e) || node_refs_local?(val_e, ali) || stmt_writes_local?(val_e, li) || !osr_loop_pure_epoch?(val_e)
    l_slow = @a.new_label
    l_done = @a.new_label
    l_head = @a.new_label
    l_epi = @a.new_label
    l_fin = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    if lim_kind == 2
      @a.cmp_wi(lim_reg, 0)
      @a.b_cond(CC_LE, l_slow)
      @a.mov_imm32(R_X9, 4194304)
      @a.cmp_w(lim_reg, R_X9)
      @a.b_cond(CC_GT, l_slow)
      emit_box_i32(R_X1, lim_reg)
    else
      @a.mov_imm32(R_X9, lim_val)
      emit_box_i32(R_X1, R_X9)
    call_rt(RT_ARR_NEW_EMPTY_CAP)
    @a.fmov_d_x(R_D17, R_X20) if @d_bias_reg == R_D17
    @a.cbz_x(R_X0, l_slow)
    store_slot_any(ali, R_X0)
    r_slots = @free_gprs.pop
    borrowed_lim = nil
    if lim_kind == 1 && lim_val > 4095 && @free_gprs.size > 0
      borrowed_lim = @free_gprs.pop
      @a.mov_imm32(borrowed_lim, lim_val)
      lim_reg = borrowed_lim
    @a.and_x_ptr47(R_X9, R_X0)
    @a.ldr_x(r_slots, R_X9, 16)
    @a.movz_x(ri, 0)
    emit_counted_cmp_p1_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_GE, l_epi)
    @a.bind(l_head)
    gen_expr_i32(val_e)
    emit_box_i32(R_X0, R_X0)
    @a.str_x_idx(R_X0, r_slots, ri)
    @a.add_wi(ri, ri, 1)
    gen_expr_i32(val_e)
    emit_box_i32(R_X0, R_X0)
    @a.str_x_idx(R_X0, r_slots, ri)
    @a.add_wi(ri, ri, 1)
    emit_counted_cmp_p1_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_LT, l_head)
    @a.bind(l_epi)
    emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_GE, l_fin)
    gen_expr_i32(val_e)
    emit_box_i32(R_X0, R_X0)
    @a.str_x_idx(R_X0, r_slots, ri)
    @a.add_wi(ri, ri, 1)
    @a.bind(l_fin)
    load_slot_any(R_X9, ali)
    @a.and_x_ptr47(R_X9, R_X9)
    @a.str_w(ri, R_X9, 8)
    @a.bind(l_done)
    @free_gprs.push(borrowed_lim) if borrowed_lim != nil
    @free_gprs.push(r_slots)
    cb = ->()
      @a.bind(l_slow)
      gen_stmt(s0)
      gen_stmt(s1)
      @a.b(l_done)
    add_cold_stub(cb)
    true

  # Branchless `if (i32_a op i32_b) c++;` -> ZERO branch mispredictions (e.g. prime counting in sieve)!
  -> try_gen_branchless_if_inc(s)
    return false if s.c != nil || s.a == nil || s.b == nil
    st = s.b
    st = st.list[0] if st.is_a?(JsNode) && st.kind == :block && st.list.size == 1
    return false if !st.is_a?(JsNode) || st.kind != :expr_stmt || st.a == nil
    u = st.a
    return false if u.kind != :update || u.str != "++" || u.a.kind != :ident
    cli = local_idx(u.a)
    return false if cli < 0 || @info.types[cli] != JT_I32
    rc = @info.reg_gpr[cli]
    return false if rc == nil
    cond = s.a
    return false if cond.kind != :binary
    op = cond.str
    return false if op != "===" && op != "!==" && op != "<" && op != "<=" && op != ">" && op != ">="
    return false if !can_i32?(cond.a) || !can_i32?(cond.b) || stmt_writes_local?(cond, cli)
    # Overflow guard BEFORE condition evaluation (cmn rc, #1 -> V=1 iff rc == 0x7FFFFFFF; touches ZERO scratch regs!)
    @a.adds_wi(R_XZR, rc, 1)
    @a.b_cond(CC_VS, @l_deopt)
    ra = peek_i32_reg(cond.a)
    rb = peek_i32_reg(cond.b)
    if cond.b.kind == :num && jit_small_int_lit?(cond.b, 4095) && cond.b.a.to_i >= 0
      if ra != nil
        @a.cmp_wi(ra, cond.b.a.to_i)
      else
        gen_expr_i32(cond.a)
        @a.cmp_wi(R_X0, cond.b.a.to_i)
    elsif cond.b.kind == :num && jit_int32_lit?(cond.b)
      if ra != nil
        @a.mov_imm32(R_X9, cond.b.a.to_i)
        @a.cmp_w(ra, R_X9)
      else
        gen_expr_i32(cond.a)
        @a.mov_imm32(R_X9, cond.b.a.to_i)
        @a.cmp_w(R_X0, R_X9)
    elsif rb != nil
      if ra != nil
        @a.cmp_w(ra, rb)
      else
        gen_expr_i32(cond.a)
        @a.cmp_w(R_X0, rb)
    else
      gen_expr_i32(cond.a)
      push_w(R_X0)
      gen_expr_i32(cond.b)
      pop_w(R_X9)
      @a.cmp_w(R_X9, R_X0)
    cc = CC_EQ
    if op == "!=="
      cc = CC_NE
    elsif op == "<"
      cc = CC_LT
    elsif op == "<="
      cc = CC_LE
    elsif op == ">"
      cc = CC_GT
    elsif op == ">="
      cc = CC_GE
    @a.cinc_w(rc, rc, cc)
    true

  -> gen_stmts(list)
    return nil if list == nil
    i = 0
    while i < list.size
      if i + 1 < list.size && try_gen_prereserved_push_loop(list[i], list[i + 1])
        i += 2
      else
        gen_stmt(list[i])
        i += 1
    nil

  -> gen_stmt(s)
    return nil if s == nil
    k = s.kind
    if k == :expr_stmt
      gen_expr_void(s.a)
    elsif k == :var_decl
      i = 0
      while i < s.list.size
        d = s.list[i]
        b = d.a.x.binding
        if d.b != nil
          emit_assign_to_binding(b, d.b, s.str != "var")
        elsif s.str != "var"
          @a.movz_x(R_X0, 0)
          emit_write_binding(b, R_X0, true)
        i += 1
    elsif k == :block
      gen_stmts(s.list)
    elsif k == :if
      if try_gen_branchless_if_inc(s)
        return nil
      l_else = @a.new_label
      l_end = @a.new_label
      gen_cond_branch(s.a, s.c != nil ? l_else : l_end, false)
      saved_shapes = @known_shapes.dup
      gen_stmt(s.b)
      if s.c != nil
        @a.b(l_end)
        @a.bind(l_else)
        @known_shapes = saved_shapes.dup
        gen_stmt(s.c)
      @a.bind(l_end)
      @known_shapes = {}
    elsif k == :return
      if s.a == nil
        @a.movz_x(R_X0, 0)
      else
        gen_expr_any(s.a)
      @a.b(@l_ret)
    elsif k == :throw
      gen_expr_any(s.a)
      @a.mov_r(R_X1, R_X0)
      call_rt(RT_THROW)
    elsif k == :for
      gen_for_loop(s, true)
    elsif k == :while
      gen_while_loop(s)
    elsif k == :do_while
      gen_do_while_loop(s)
    elsif k == :break
      ctx = find_loop(s.str)
      @a.b(ctx.l_break) if ctx != nil
    elsif k == :continue
      ctx = find_loop(s.str)
      @a.b(ctx.l_cont) if ctx != nil
    elsif k == :empty || k == :debugger || k == :function_decl
      nil
    nil

  -> find_loop(lbl)
    i = @loops.size - 1
    while i >= 0
      return @loops[i] if lbl == nil || @loops[i].label == lbl
      i -= 1
    nil

  -> collect_poly_shapes(n, out)
    return nil if !n.is_a?(JsNode) || out.size >= 4
    if n.kind == :call && n.a.is_a?(JsNode) && n.a.kind == :member && !n.a.has?(F_COMPUTED) && n.x.is_a?(Array) && n.x.size >= 2
      q = 0
      while q < n.x.size && out.size < 4
        sh = n.x[q]
        out.push(sh) if sh.is_a?(JS:Shape) && !out.include?(sh)
        q += 2
    collect_poly_shapes(n.a, out)
    collect_poly_shapes(n.b, out)
    collect_poly_shapes(n.c, out)
    collect_poly_shapes(n.d, out)
    if n.list.is_a?(Array)
      n.list.each ->(x) collect_poly_shapes(x, out)
    nil

  # Can JS_EPOCH[0] be mutated inside statement/expr `n`? (True only if it contains non-pure calls/assignments to prototypes.)
  -> osr_loop_pure_epoch?(n)
    return true if !n.is_a?(JsNode)
    k = n.kind
    return false if k == :new
    if k == :call
      # Pure Math.* calls, arr.push(pure), and inlineable pure poly method calls cannot change JS_EPOCH!
      c = n.a
      if c.is_a?(JsNode) && c.kind == :member && !c.has?(F_COMPUTED)
        return true if c.a.is_a?(JsNode) && c.a.kind == :ident && c.a.str == "Math"
        if c.b.str == "push" && n.list.size == 1
          return osr_loop_pure_epoch?(c.a) && osr_loop_pure_epoch?(n.list[0])
        if (c.b.str == "indexOf" || c.b.str == "charCodeAt") && n.list.size == 1
          sli = local_idx(c.a)
          return osr_loop_pure_epoch?(n.list[0]) if sli >= 0 && @info.str_locals[sli]
        if c.b.str == "round" && c.a.is_a?(JsNode) && c.a.kind == :ident && c.a.str == "Math"
          return true
        if n.x.is_a?(Array) && n.x.size >= 2 && n.list.size == 0
          ok = true
          q = 0
          while q < n.x.size
            sh = n.x[q]
            fn = n.x[q + 1]
            if !sh.is_a?(JS:Shape) || !fn.is_a?(JS:Function) || fn.code == nil || !fn.code.node.is_a?(JaFunc)
              ok = false
            else
              tjf = fn.code.node
              re = jit_inline_return_expr(tjf)
              ok = false if re == nil || tjf.free.size > 0 || tjf.params.size != 0 || !poly_inline_expr_ok?(re, sh)
            q += 2
          return osr_loop_pure_epoch?(c.a) if ok
      return false
    return false if !osr_loop_pure_epoch?(n.a) || !osr_loop_pure_epoch?(n.b) || !osr_loop_pure_epoch?(n.c) || !osr_loop_pure_epoch?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return false if !osr_loop_pure_epoch?(n.list[i])
        i += 1
    true

  -> gen_for_loop(s, run_init)
    if run_init && s.a != nil
      if s.a.kind == :var_decl
        gen_stmt(s.a)
      else
        gen_expr_void(s.a)
    # Canonical counted loop inversion (`for (i = ...; i < LIMIT; i++)`):
    # Eliminates `b.vs` overflow branch, hoists constant limit into a free GPR,
    # reduces 3 branches/iter to 1 single back-edge `cmp + b.lt`, and enables
    # loop bounds-check elimination for `arr[i]` / `ta[i]`!
    if try_gen_step_or_le_for_loop(s, run_init)
      return nil
    if try_gen_counted_for_loop(s, run_init)
      return nil
    @known_shapes = {}
    l_head = @a.new_label
    l_cont = @a.new_label
    l_brk = @a.new_label
    @loops.push(JS:JitLoopCtx.new(l_brk, l_cont, nil))
    @in_loop_depth += 1
    @a.bind(l_head)
    if s.b != nil
      gen_cond_branch(s.b, l_brk, false)
    gen_loop_body_stmt(s.d)
    @a.bind(l_cont)
    gen_expr_void(s.c) if s.c != nil
    @a.b(l_head)
    @a.bind(l_brk)
    @in_loop_depth -= 1
    @loops.pop
    @known_shapes = {}
    nil

  -> stmt_writes_local?(n, target_li)
    return false if !n.is_a?(JsNode)
    k = n.kind
    if k == :assign && n.a.is_a?(JsNode) && n.a.kind == :ident
      return true if local_idx(n.a) == target_li
    elsif k == :update && n.a.is_a?(JsNode) && n.a.kind == :ident
      return true if local_idx(n.a) == target_li
    elsif k == :var_decl && n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        d = n.list[i]
        return true if d.is_a?(JsNode) && local_idx(d.a) == target_li && d.b != nil
        return true if stmt_writes_local?(d.b, target_li)
        i += 1
      return false
    return true if stmt_writes_local?(n.a, target_li) || stmt_writes_local?(n.b, target_li) || stmt_writes_local?(n.c, target_li) || stmt_writes_local?(n.d, target_li)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if stmt_writes_local?(n.list[i], target_li)
        i += 1
    false

  -> stmts_pure_num_obj_fn?(stmts)
    return false if stmts == nil
    i = 0
    while i < stmts.size
      return false if !node_pure_num_obj?(stmts[i])
      i += 1
    true

  -> node_pure_num_obj?(n)
    return true if n == nil || !n.is_a?(JsNode)
    k = n.kind
    return false if k == :object || k == :array || k == :new || k == :fn_decl || k == :fn_expr || k == :arrow
    if k == :ident && n.x != nil && n.x.binding != nil && n.x.binding.global?
      return n.str == "Math"
    if k == :assign && n.a != nil && n.a.kind == :member
      return false if n.a.has?(F_COMPUTED)
      op = n.str
      return false if !(op == "=" || op == "+=" || op == "-=" || op == "*=" || op == "/=")
      return false if !can_f64?(n.b)
    return false if !node_pure_num_obj?(n.a) || !node_pure_num_obj?(n.b) || !node_pure_num_obj?(n.c) || !node_pure_num_obj?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return false if !node_pure_num_obj?(n.list[i])
        i += 1
    true

  -> stmts_have_return?(stmts)
    return false if stmts == nil
    i = 0
    while i < stmts.size
      return true if stmt_has_return?(stmts[i])
      i += 1
    false

  -> stmt_has_return?(n)
    return false if n == nil || !n.is_a?(JsNode)
    k = n.kind
    return false if k == :fn_decl || k == :fn_expr || k == :arrow
    return true if k == :return
    return true if stmt_has_return?(n.a) || stmt_has_return?(n.b) || stmt_has_return?(n.c) || stmt_has_return?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if stmt_has_return?(n.list[i])
        i += 1
    false

  -> stmt_single_call(n)
    return nil if n == nil || !n.is_a?(JsNode)
    if n.kind == :block && n.list.is_a?(Array) && n.list.size == 1
      n = n.list[0]
    return nil if n == nil || n.kind != :expr_stmt || n.a == nil || n.a.kind != :call
    n.a

  -> arg_loop_inv?(e, li)
    return false if e == nil || !e.is_a?(JsNode)
    return true if e.kind == :num
    if e.kind == :ident
      ali = local_idx(e)
      return ali >= 0 && ali != li
    false

  # Emit constant ASCII bytes of `str` into [ptr_reg + 0 .. str.size-1] using 4-byte str_w & strb!
  -> emit_const_ascii_stores(ptr_reg, str)
    n = str.size
    off = 0
    while off + 4 <= n
      w = str.byte_at(off) | (str.byte_at(off + 1) << 8) | (str.byte_at(off + 2) << 16) | (str.byte_at(off + 3) << 24)
      @a.mov_imm32(R_X11, w)
      @a.str_w(R_X11, ptr_reg, off)
      off += 4
    while off < n
      @a.movz_x(R_X11, str.byte_at(off))
      @a.strb(R_X11, ptr_reg, off)
      off += 1
    nil

  # Check if `s` writes to `arr[...]` or calls a method on `arr` (so `arr` cannot be hoisted read-only in loop).
  -> stmt_mutates_arr?(n, arr_li)
    return false if !n.is_a?(JsNode)
    k = n.kind
    if k == :assign
      return true if local_idx(n.a) == arr_li
      if n.a.is_a?(JsNode) && n.a.kind == :member && local_idx(n.a.a) == arr_li
        return true
    elsif k == :update
      if n.a.is_a?(JsNode) && n.a.kind == :member && local_idx(n.a.a) == arr_li
        return true
    elsif k == :new
      return true
    elsif k == :call
      # Any call other than pure Math / str.indexOf / str.charCodeAt could alias & mutate arr!
      c = n.a
      is_pure = false
      if c.is_a?(JsNode) && c.kind == :member && !c.has?(F_COMPUTED)
        is_pure = true if c.a.is_a?(JsNode) && c.a.kind == :ident && c.a.str == "Math"
        if (c.b.str == "indexOf" || c.b.str == "charCodeAt") && n.list.size == 1
          sli = local_idx(c.a)
          is_pure = true if sli >= 0 && @info.str_locals[sli]
      return true if !is_pure
    return true if stmt_mutates_arr?(n.a, arr_li) || stmt_mutates_arr?(n.b, arr_li) || stmt_mutates_arr?(n.c, arr_li) || stmt_mutates_arr?(n.d, arr_li)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if stmt_mutates_arr?(n.list[i], arr_li)
        i += 1
    false

  # Counted `<=` or variable-step (`j += step`) `for` loops:
  #   - `for (var i = 1; i <= n; i++) { ... }` (float_math, sieve count!) -> 2x/4x unrolled, zero b.vs, BCE!
  #   - `for (var j = i * i; j <= n; j += i) buf[j] = 1;` (sieve inner!) -> promotes f64 `j` to i32 GPR, 2x unrolled, zero b.vs, BCE!
  -> try_gen_step_or_le_for_loop(s, run_init)
    return false if s.b == nil || s.c == nil || s.b.kind != :binary
    op = s.b.str
    return false if op != "<=" && op != "<"
    is_le = op == "<="
    li = local_idx(s.b.a)
    return false if li < 0 || stmt_writes_local?(s.d, li)
    # Classify update: `i++` (step_reg == nil) or `j += step_local` (step_reg != nil)
    step_reg = nil
    if s.c.kind == :update && s.c.str == "++" && local_idx(s.c.a) == li
      return false if !is_le   # `<` with `i++` is handled by full try_gen_counted_for_loop!
    elsif s.c.kind == :assign && s.c.str == "+=" && local_idx(s.c.a) == li && s.c.b.kind == :ident
      sli = local_idx(s.c.b)
      return false if sli < 0 || sli == li || @info.types[sli] != JT_I32 || @info.reg_gpr[sli] == nil || stmt_writes_local?(s.d, sli)
      step_reg = @info.reg_gpr[sli]
    else
      return false
    # Allow JT_I32 induction var in GPR, OR promote a JT_F64 `j += step` induction var (e.g. `var j = i * i`) into a free GPR!
    promo_f64_j = false
    ri = nil
    if @info.types[li] == JT_I32
      ri = @info.reg_gpr[li]
      return false if ri == nil
    elsif @info.types[li] == JT_F64 && step_reg != nil && @free_gprs.size > 0
      promo_f64_j = true
    else
      return false
    # Classify limit: i32 literal or JT_I32 register local
    lim_kind = 0
    lim_val = 0
    lim_reg = nil
    eb = s.b.b
    if eb.kind == :num && jit_int32_lit?(eb) && eb.a.to_i >= 0 && eb.a.to_i < 2147483647
      lim_kind = 1
      lim_val = eb.a.to_i
    elsif eb.kind == :ident
      lli = local_idx(eb)
      if lli >= 0 && lli != li && @info.types[lli] == JT_I32 && @info.reg_gpr[lli] != nil && !stmt_writes_local?(s.d, lli)
        lim_kind = 2
        lim_reg = @info.reg_gpr[lli]
    return false if lim_kind == 0
    promo_j_gpr = nil
    if promo_f64_j
      promo_j_gpr = @free_gprs.pop
      ri = promo_j_gpr
    borrowed_gpr = nil
    if lim_kind == 1 && lim_val > 4095 && @free_gprs.size > 0
      borrowed_gpr = @free_gprs.pop
      @a.mov_imm32(borrowed_gpr, lim_val)
      lim_reg = borrowed_gpr
    saved_shapes = @known_shapes.dup
    l_head = @a.new_label
    l_cont = @a.new_label
    l_fast_brk = @a.new_label
    l_brk = @a.new_label
    cc_exit = is_le ? CC_GT : CC_GE
    cc_back = is_le ? CC_LE : CC_LT
    l_slow = @a.new_label
    need_slow = false
    # If `j` was JT_F64 (`var j = i * i`), unbox exact int32 into `ri` at entry (else fallback to exact f64 loop!)
    if promo_f64_j
      load_slot_f64(R_D0, li)
      @a.fcvtzs_w_d(ri, R_D0)
      @a.scvtf_d_w(R_D16, ri)
      @a.fcmp_d(R_D0, R_D16)
      @a.b_cond(CC_NE, l_slow)
      need_slow = true
    # Entry guard: skip loop if already past limit
    emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, cc_exit, l_brk)
    # Check overflow safety & TypedArray BCE at loop entry!
    bce_tas = []
    if lim_kind == 2 && @hoisted_tas.size > 0 && @promoted_owner < 0
      lim_li = local_idx(eb)
      collect_ta_bce_cands(s.d, li, lim_li, bce_tas)
    if step_reg != nil
      @a.cmp_wi(step_reg, 0)
      @a.b_cond(CC_LE, l_slow)
      # Verify lim <= 2147483646 - step_reg -> guarantees `j + step` NEVER overflows i32 (ZERO b.vs inside loop!)
      @a.mov_imm32(R_X9, 2147483646)
      @a.sub_w(R_X9, R_X9, step_reg)
      if lim_kind == 2
        @a.cmp_w(lim_reg, R_X9)
      else
        @a.mov_imm32(R_X10, lim_val)
        @a.cmp_w(R_X10, R_X9)
      @a.b_cond(CC_GT, l_slow)
      need_slow = true
    elsif is_le && lim_kind == 2
      @a.mov_imm32(R_X9, 2147483645)
      @a.cmp_w(lim_reg, R_X9)
      @a.b_cond(CC_GT, l_slow)
      need_slow = true
    if bce_tas.size > 0
      @a.cmp_wi(ri, 0)
      @a.b_cond(CC_LT, l_slow)
      bi = 0
      while bi < bce_tas.size
        tli = bce_tas[bi]
        tr = @hoisted_ta_regs[tli]
        if tr != nil && tr[1] != nil
          @a.cmp_w(lim_reg, tr[1])
        else
          @a.ldr_x(R_X9, R_SP, @hoisted_tas[tli][1])
          @a.cmp_w(lim_reg, R_X9)
        @a.b_cond(is_le ? CC_GE : CC_GT, l_slow)
        bi += 1
      lim_li = local_idx(eb)
      bce_tas.each ->(tli)
        @bounded_ta_set[li.to_s + ":" + tli.to_s] = true
        @bounded_mod_ta[lim_li.to_s + ":" + tli.to_s] = true if lim_li >= 0
      need_slow = true
    # Temporarily expose promoted `j` as JT_I32 in `ri` while generating fast loop body!
    if promo_f64_j
      @info.types[li] = JT_I32
      @info.reg_gpr[li] = ri
    old_no_ovf = @no_ovf_p1_li
    @no_ovf_p1_li = li if step_reg == nil && is_le && (lim_kind == 2 || lim_val <= 2147483645)
    body_sz = !stmt_has_cf_or_loop?(s.d) ? stmt_size_count(s.d) : 999
    can_unroll4 = step_reg == nil && is_le && body_sz <= 22
    can_unroll2 = step_reg == nil && is_le && !can_unroll4 && body_sz <= 26
    can_step_unroll2 = step_reg != nil && is_le && lim_kind == 2 && body_sz <= 10
    @loops.push(JS:JitLoopCtx.new(l_fast_brk, l_cont, nil))
    @in_loop_depth += 1
    if can_unroll4
      # 4x unrolled `<=` loop: while (i + 3 <= lim) { 4 bodies }; epilogue `while (i <= lim)`!
      l_epi4 = @a.new_label
      l_epi_lp = @a.new_label
      r_lim3 = @free_gprs.size > 0 ? @free_gprs.pop : nil
      if lim_reg != nil
        @a.cmp_wi(lim_reg, 3)
        @a.b_cond(CC_LT, l_epi4)
        @a.sub_wi(r_lim3 != nil ? r_lim3 : R_X9, lim_reg, 3)
      else
        @a.b(l_epi4) if lim_val < 3
        @a.mov_imm32(r_lim3 != nil ? r_lim3 : R_X9, lim_val - 3)
      @a.cmp_w(ri, r_lim3 != nil ? r_lim3 : R_X9)
      @a.b_cond(CC_GT, l_epi4)
      # Check if body is pure JT_F64 assignments (zero possible deopt mid-4-iters -> safe to defer `ri += 4`!)
      defer_i4 = false
      if bce_tas.size == 0 && @no_ovf_p1_li == li && osr_loop_pure_epoch?(s.d)
        bsts = s.d.kind == :block ? s.d.list : [s.d]
        all_f64_pure = bsts.size > 0
        bi4 = 0
        while bi4 < bsts.size && all_f64_pure
          bs = bsts[bi4]
          if bs.kind == :expr_stmt && bs.a != nil && bs.a.kind == :assign && bs.a.a.kind == :ident
            tli = local_idx(bs.a.a)
            all_f64_pure = false if tli < 0 || @info.types[tli] != JT_F64 || !can_f64?(bs.a.b)
          else
            all_f64_pure = false
          bi4 += 1
        defer_i4 = all_f64_pure
      @a.bind(l_head)
      if defer_i4
        @unroll_i_li = li
        @unroll_i_off = 0
        gen_loop_body_stmt(s.d)
        @unroll_i_off = 1
        gen_loop_body_stmt(s.d)
        @unroll_i_off = 2
        gen_loop_body_stmt(s.d)
        @unroll_i_off = 3
        gen_loop_body_stmt(s.d)
        @unroll_i_li = -1
        @unroll_i_off = 0
        @a.add_wi(ri, ri, 4)
      else
        gen_loop_body_stmt(s.d)
        @a.add_wi(ri, ri, 1)
        gen_loop_body_stmt(s.d)
        @a.add_wi(ri, ri, 1)
        gen_loop_body_stmt(s.d)
        @a.add_wi(ri, ri, 1)
        gen_loop_body_stmt(s.d)
        @a.add_wi(ri, ri, 1)
      if r_lim3 != nil
        @a.cmp_w(ri, r_lim3)
      else
        if lim_reg != nil
          @a.sub_wi(R_X9, lim_reg, 3)
        else
          @a.mov_imm32(R_X9, lim_val - 3)
        @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_LE, l_head)
      @free_gprs.push(r_lim3) if r_lim3 != nil
      @a.bind(l_epi4)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_GT, l_fast_brk)
      @a.bind(l_epi_lp)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      @a.add_wi(ri, ri, 1)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_LE, l_epi_lp)
    elsif can_unroll2
      # For `<=`: `i + 1 <= lim` is identical to `i < lim`!
      l_epilogue = @a.new_label
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_GE, l_epilogue)
      @a.bind(l_head)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_LT, l_head)
      @a.bind(l_epilogue)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_GT, l_fast_brk)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      @a.add_wi(ri, ri, 1)
    elsif can_step_unroll2
      # 2x unrolled variable-step `j <= lim; j += step` loop (ZERO b.vs, ZERO BCE!)
      l_epilogue = @a.new_label
      @a.cmp_w(lim_reg, step_reg)
      @a.b_cond(CC_LT, l_epilogue)
      @a.sub_w(R_X9, lim_reg, step_reg)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_GT, l_epilogue)
      @a.bind(l_head)
      gen_loop_body_stmt(s.d)
      @a.add_w(ri, ri, step_reg)
      gen_loop_body_stmt(s.d)
      @a.add_w(ri, ri, step_reg)
      @a.sub_w(R_X9, lim_reg, step_reg)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_LE, l_head)
      @a.bind(l_epilogue)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, CC_GT, l_fast_brk)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      @a.add_w(ri, ri, step_reg)
    else
      @a.bind(l_head)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      if step_reg != nil
        @a.add_w(ri, ri, step_reg)
      else
        @a.add_wi(ri, ri, 1)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, -1, cc_back, l_head)
    @a.bind(l_fast_brk)
    @no_ovf_p1_li = old_no_ovf
    if promo_f64_j
      @info.types[li] = JT_F64
      @info.reg_gpr.delete(li)
      @a.scvtf_d_w(R_D0, ri)
      store_slot_f64(li, R_D0)
    @a.bind(l_brk)
    @in_loop_depth -= 1
    @loops.pop
    if bce_tas.size > 0
      lim_li = local_idx(eb)
      bce_tas.each ->(tli)
        @bounded_ta_set.delete(li.to_s + ":" + tli.to_s)
        @bounded_mod_ta.delete(lim_li.to_s + ":" + tli.to_s) if lim_li >= 0
    if need_slow
      cb = ->()
        @a.bind(l_slow)
        l_uhead = @a.new_label
        l_ucont = @a.new_label
        @loops.push(JS:JitLoopCtx.new(l_brk, l_ucont, nil))
        @a.bind(l_uhead)
        gen_cond_branch(s.b, l_brk, false)
        gen_loop_body_stmt(s.d)
        @a.bind(l_ucont)
        gen_expr_void(s.c)
        @a.b(l_uhead)
        @loops.pop
      add_cold_stub(cb)
    @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
    @free_gprs.push(promo_j_gpr) if promo_j_gpr != nil
    @known_shapes = saved_shapes
    true

  # Detect & compile a counted loop calling a monomorphic numeric mutating prototype method:
  #   `for (var i = 0; i < n; i++) s += p.step(1, -1);`
  # Promotes `p`'s fields & `s` into 64-bit integer registers across a 2x-unrolled loop (ZERO calls/memory)!
  -> try_gen_hoisted_method_loop(s, li, ri, lim_kind, lim_val, lim_reg, lim_container)
    return false if @in_loop_depth > 1 || @promoted_owner >= 0 || @i53_acc_li >= 0
    st = s.d
    st = st.list[0] if st.is_a?(JsNode) && st.kind == :block && st.list.size == 1
    return false if !st.is_a?(JsNode) || st.kind != :expr_stmt || st.a == nil
    acc_li = -1
    call_e = nil
    if st.a.kind == :assign && st.a.str == "+=" && st.a.a.kind == :ident && st.a.b.kind == :call
      acc_li = local_idx(st.a.a)
      call_e = st.a.b
      return false if acc_li < 0 || acc_li == li
      acc_ty = @info.types[acc_li]
      return false if acc_ty != JT_F64 && acc_ty != JT_ANY
      return false if acc_ty == JT_F64 && @info.reg_fpr[acc_li] == nil
    else
      return false
    return false if call_e.a == nil || call_e.a.kind != :member || call_e.a.has?(F_COMPUTED)
    rli = local_idx(call_e.a.a)
    return false if rli < 0 || rli == li || rli == acc_li || @info.types[rli] != JT_ANY
    # Inspect observed monomorphic receiver shape & target function from call_e.x
    return false if !call_e.x.is_a?(Array) || call_e.x.size != 2
    sh = call_e.x[0]
    fn = call_e.x[1]
    return false if !sh.is_a?(JS:Shape) || !fn.is_a?(JS:Function) || fn.code == nil || !fn.code.node.is_a?(JaFunc)
    tjf = fn.code.node
    return false if tjf.dynamic || tjf.free.size > 0 || tjf.params.size != call_e.list.size || tjf.params.size > 2
    return false if !tjf.node.b.is_a?(Array) || tjf.node.b.size < 2 || tjf.node.b.size > 5
    # Verify all call args are small int32 literals!
    arg_vals = []
    ai = 0
    while ai < call_e.list.size
      ae = call_e.list[ai]
      if ae.kind == :num && jit_small_int_lit?(ae, 65536)
        arg_vals.push(ae.a.to_i)
      elsif ae.kind == :unary && ae.str == "-" && ae.a.kind == :num && jit_small_int_lit?(ae.a, 65536)
        arg_vals.push(0 - ae.a.a.to_i)
      else
        return false
      ai += 1
    # Verify method body: 1..4 `this.prop += param/lit` or `-=` statements + final `return this.p0 + this.p1`!
    stmts = tjf.node.b
    updates = []      # [prop_name, slot_enc, delta_i64]
    prop_slots = {}   # prop_name -> slot_enc
    prop_order = []
    ui = 0
    while ui < stmts.size - 1
      us = stmts[ui]
      return false if us.kind != :expr_stmt || us.a == nil || us.a.kind != :assign || (us.a.str != "+=" && us.a.str != "-=")
      lhs = us.a.a
      return false if lhs.kind != :member || lhs.has?(F_COMPUTED) || lhs.a.kind != :this
      pn = lhs.b.str
      sl = sh.slot_of(pn)
      return false if sl < 0 || (sh.attrs_of(pn) & (ATTR_ACCESSOR | ATTR_W)) != ATTR_W
      enc = sl < sh.inline ? (sh.ibase + sl) : (0 - (sl - sh.inline) - 1)
      rhs = us.a.b
      delta = nil
      if rhs.kind == :ident && rhs.x != nil && rhs.x.binding != nil
        pi = tjf.params.index(rhs.x.binding)
        delta = arg_vals[pi] if pi != nil
      elsif rhs.kind == :num && jit_small_int_lit?(rhs, 65536)
        delta = rhs.a.to_i
      return false if delta == nil
      delta = 0 - delta if us.a.str == "-="
      updates.push([pn, enc, delta])
      if prop_slots[pn] == nil
        prop_slots[pn] = enc
        prop_order.push(pn)
      ui += 1
    ret_s = stmts[stmts.size - 1]
    return false if ret_s.kind != :return || ret_s.a == nil
    ret_props = []
    re = ret_s.a
    if re.kind == :member && !re.has?(F_COMPUTED) && re.a.kind == :this
      ret_props.push(re.b.str)
    elsif re.kind == :binary && re.str == "+" && re.a.kind == :member && !re.a.has?(F_COMPUTED) && re.a.a.kind == :this && re.b.kind == :member && !re.b.has?(F_COMPUTED) && re.b.a.kind == :this
      ret_props.push(re.a.b.str)
      ret_props.push(re.b.b.str)
    else
      return false
    rpi = 0
    while rpi < ret_props.size
      rp = ret_props[rpi]
      sl = sh.slot_of(rp)
      return false if sl < 0 || (sh.attrs_of(rp) & ATTR_ACCESSOR) != 0
      if prop_slots[rp] == nil
        prop_slots[rp] = sl < sh.inline ? (sh.ibase + sl) : (0 - (sl - sh.inline) - 1)
        prop_order.push(rp)
      rpi += 1
    return false if prop_order.size == 0 || prop_order.size > 4
    # Allocate temporary registers for promoted fields (x10..x13) and accumulator (x14) — ZERO spills!
    jit_keep(sh)
    jit_keep(fn)
    l_head = @a.new_label
    l_epi = @a.new_label
    l_brk = @a.new_label
    l_slow = @a.new_label
    # Guard 0: if i >= limit, done immediately
    emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
    # Guard 1: limit <= 2097151 (guarantees exact 53-bit integer arithmetic across entire loop!)
    if lim_kind == 1
      return false if lim_val > 2097151
    elsif lim_kind == 2
      @a.mov_imm32(R_X9, 2097151)
      @a.cmp_w(lim_reg, R_X9)
      @a.b_cond(CC_GT, l_slow)
    else
      return false
    # Guard 2: JS_EPOCH unchanged
    ep_now = JS_EPOCH[0]
    @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
    @a.ldr_x(R_X10, R_X9, 0)
    @a.mov_imm64(R_X11, ep_now)
    @a.cmp_r(R_X10, R_X11)
    @a.b_cond(CC_NE, l_slow)
    # Guard 3: recv is WObject with shape == sh
    load_slot_any(R_X15, rli)
    @a.sub_i(R_X9, R_X15, 4)
    @a.tst_wobj_bad(R_X9)
    @a.b_cond(CC_NE, l_slow)
    @a.cbz_x(R_X9, l_slow)
    @a.ldr_x(R_X10, R_X9, 8)
    @a.mov_imm64(R_X11, wvalue_bits(sh) ## i64)
    @a.cmp_r(R_X10, R_X11)
    @a.b_cond(CC_NE, l_slow)
    # Guard 4: preload all touched fields of recv as exact int32 into x10..x13 (x9 = recv_ptr)
    # NOTE: Must run BEFORE unboxing `s` into x14 because emit_unbox_exact_i32 uses x14 as scratch!
    fregs = {}
    fi = 0
    while fi < prop_order.size
      pn = prop_order[fi]
      fr = R_X10 + fi
      emit_slot_load(R_X0, R_X9, prop_slots[pn])
      emit_unbox_exact_i32(fr, R_X0, l_slow)
      @a.sxtw(fr, fr)
      fregs[pn] = fr
      fi += 1
    # Guard 5: `s` (acc_li) unboxes as exact int32 -> x14
    acc_is_any = @info.types[acc_li] == JT_ANY
    if acc_is_any
      load_slot_any(R_X0, acc_li)
      emit_unbox_exact_i32(R_X14, R_X0, l_slow)
      @a.sxtw(R_X14, R_X14)
    else
      dr_s = @info.reg_fpr[acc_li]
      @a.fcvtzs_w_d(R_X14, dr_s)
      @a.scvtf_d_w(R_D16, R_X14)
      @a.fcmp_d(dr_s, R_D16)
      @a.b_cond(CC_NE, l_slow)
      @a.sxtw(R_X14, R_X14)
    # Helper closure to emit 1 iteration purely in x10..x14!
    emit_one_step = ->()
      ui2 = 0
      while ui2 < updates.size
        u = updates[ui2]
        fr = fregs[u[0]]
        dv = u[2]
        if dv > 0 && dv <= 4095
          @a.add_i(fr, fr, dv)
        elsif dv < 0 && dv >= -4095
          @a.sub_i(fr, fr, 0 - dv)
        elsif dv != 0
          @a.mov_imm64(R_X0, dv)
          @a.add_r(fr, fr, R_X0)
        ui2 += 1
      if ret_props.size == 1
        @a.add_r(R_X14, R_X14, fregs[ret_props[0]])
      else
        @a.add_r(R_X0, fregs[ret_props[0]], fregs[ret_props[1]])
        @a.add_r(R_X14, R_X14, R_X0)
    # 4x unrolled integer loop!
    l_epi_lp = @a.new_label
    if lim_kind == 2
      @a.cmp_wi(lim_reg, 4)
      @a.b_cond(CC_LT, l_epi)
      @a.sub_wi(R_X9, lim_reg, 3)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_GE, l_epi)
    else
      @a.b(l_epi) if lim_val < 4
      @a.mov_imm32(R_X9, lim_val - 3)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_GE, l_epi)
    @a.bind(l_head)
    emit_one_step.call
    emit_one_step.call
    emit_one_step.call
    emit_one_step.call
    @a.add_wi(ri, ri, 4)
    if lim_kind == 2
      @a.sub_wi(R_X9, lim_reg, 3)
    else
      @a.mov_imm32(R_X9, lim_val - 3)
    @a.cmp_w(ri, R_X9)
    @a.b_cond(CC_LT, l_head)
    @a.bind(l_epi)
    emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
    @a.bind(l_epi_lp)
    emit_one_step.call
    @a.add_wi(ri, ri, 1)
    emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_epi_lp)
    # Flush promoted fields & `s` back ONCE!
    @a.bind(l_brk)
    if acc_is_any
      @a.scvtf_d_x(R_D0, R_X14)
      emit_box_f64_nonan(R_X0, R_D0)
      store_slot_any(acc_li, R_X0)
    else
      @a.scvtf_d_x(@info.reg_fpr[acc_li], R_X14)
    load_slot_any(R_X15, rli)
    @a.sub_i(R_X9, R_X15, 4)
    fi = 0
    while fi < prop_order.size
      pn = prop_order[fi]
      fr = fregs[pn]
      @a.scvtf_d_x(R_D0, fr)
      emit_box_f64_nonan(R_X0, R_D0)
      emit_slot_store(R_X9, prop_slots[pn], R_X0)
      fi += 1
    l_done_all = @a.new_label
    @a.bind(l_done_all)
    cb = ->()
      @a.bind(l_slow)
      l_uhead = @a.new_label
      @a.bind(l_uhead)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_done_all)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      @a.b(l_uhead)
    add_cold_stub(cb)
    true

  # Find a single JT_F64 accumulator `sli` updated ONLY via `sli += expr` where `expr` is exact i64!
  -> find_i53_acc_target(body, loop_li)
    stmts = (body.is_a?(JsNode) && body.kind == :block) ? body.list : [body]
    return -1 if stmts == nil || stmts.size == 0 || stmts.size > 4
    cand = -1
    si = 0
    while si < stmts.size
      st = stmts[si]
      return -1 if st == nil
      if st.kind == :expr_stmt && st.a != nil && st.a.kind == :assign && (st.a.str == "+=" || st.a.str == "-=") && st.a.a.kind == :ident
        ali = local_idx(st.a.a)
        if ali >= 0 && ali != loop_li && @info.types[ali] == JT_F64 && @info.reg_fpr[ali] != nil && expr_can_i64_exact?(st.a.b)
          return -1 if cand >= 0 && cand != ali
          cand = ali
        else
          return -1 if cand >= 0 && node_refs_local?(st, cand)
      elsif st.kind == :var_decl
        # Pure local var decl before `s += ...` (e.g. `var k = s.indexOf("bench")`) is safe!
        return -1 if cand >= 0 && node_refs_local?(st, cand)
      elsif st.kind == :expr_stmt && st.a != nil && st.a.kind == :assign && st.a.str == "=" && st.a.a.kind == :member && !st.a.a.has?(F_COMPUTED)
        # Pure SRA object field update AFTER `s += ...` (e.g. `o.a = (i & 7)`) is safe!
        bli = local_idx(st.a.a.a)
        return -1 if bli < 0 || @info.sra_objs[bli] == nil || cand < 0 || node_refs_local?(st, cand)
      else
        return -1
      si += 1
    return -1 if cand < 0
    # Verify `cand` is not read anywhere else in `body` (except as the LHS of `cand += ...`)!
    si = 0
    while si < stmts.size
      st = stmts[si]
      if st.kind == :expr_stmt && st.a != nil && st.a.kind == :assign && local_idx(st.a.a) == cand
        return -1 if node_refs_local?(st.a.b, cand)
      else
        return -1 if node_refs_local?(st, cand)
      si += 1
    cand

  # Check if `n` can branch to @i53_acc_bail inside the loop body (e.g. unguarded charCodeAt or array read)
  -> stmt_can_i53_bail?(n)
    return false if !n.is_a?(JsNode)
    k = n.kind
    return true if k == :member && n.has?(F_COMPUTED)
    if k == :call && n.a.kind == :member && !n.a.has?(F_COMPUTED) && n.a.b.str == "charCodeAt" && n.list.size == 1
      sli = local_idx(n.a.a)
      hp = sli >= 0 ? @inv_str_ascii[sli] : nil
      # Only bail-free if charCodeAt's index is `expr & mask` proven `<= hp[2] < str.len` at loop entry!
      if hp != nil && hp[2] >= 0 && n.list[0].kind == :binary && n.list[0].str == "&" && n.list[0].b.kind == :num && jit_int32_lit?(n.list[0].b) && n.list[0].b.a.to_i >= 0 && n.list[0].b.a.to_i <= hp[2]
        return false
      return true
    return true if stmt_can_i53_bail?(n.a) || stmt_can_i53_bail?(n.b) || stmt_can_i53_bail?(n.c) || stmt_can_i53_bail?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if stmt_can_i53_bail?(n.list[i])
        i += 1
    false

  # Find loop-invariant `str_local` used in `s.charCodeAt(...)` inside `body`!
  -> collect_inv_charcode(n, out)
    return nil if !n.is_a?(JsNode) || out.size >= 1
    if n.kind == :call && n.a.kind == :member && !n.a.has?(F_COMPUTED) && n.a.b.str == "charCodeAt" && n.list.size == 1
      sli = local_idx(n.a.a)
      if sli >= 0 && @info.str_locals[sli] && !@info.written_in_loop[sli]
        found = false
        out.each ->(x) found = true if x[0] == sli
        out.push([sli, n]) if !found
    collect_inv_charcode(n.a, out)
    collect_inv_charcode(n.b, out)
    collect_inv_charcode(n.c, out)
    collect_inv_charcode(n.d, out)
    if n.list.is_a?(Array)
      n.list.each ->(x) collect_inv_charcode(x, out)
    nil

  # Find loop-invariant `str_local.indexOf("const")` calls inside `body`!
  -> collect_inv_indexof(n, out)
    return nil if !n.is_a?(JsNode) || out.size >= 2
    if n.kind == :call && n.a.kind == :member && !n.a.has?(F_COMPUTED) && n.a.b.str == "indexOf" && n.list.size == 1 && n.list[0].kind == :string
      sli = local_idx(n.a.a)
      if sli >= 0 && @info.str_locals[sli] && !@info.written_in_loop[sli]
        key = sli.to_s + ":" + n.list[0].str
        found = false
        out.each ->(x) found = true if x[0] == key
        out.push([key, n, n.a.a, n.list[0]]) if !found
    collect_inv_indexof(n.a, out)
    collect_inv_indexof(n.b, out)
    collect_inv_indexof(n.c, out)
    collect_inv_indexof(n.d, out)
    if n.list.is_a?(Array)
      n.list.each ->(x) collect_inv_indexof(x, out)
    nil

  -> try_gen_counted_for_loop(s, run_init)
    return false if s.b == nil || s.c == nil
    return false if s.b.kind != :binary || s.b.str != "<"
    return false if s.c.kind != :update || s.c.str != "++" || s.c.a.kind != :ident
    li = local_idx(s.b.a)
    return false if li < 0 || li != local_idx(s.c.a) || @info.types[li] != JT_I32
    ri = @info.reg_gpr[li]
    return false if ri == nil
    return false if stmt_writes_local?(s.d, li)
    # Classify limit:
    #   1 = small/large i32 literal (<= 2147483647)
    #   2 = register-allocated JT_I32 local not written in body
    #   3 = hoisted array.length
    #   4 = hoisted TypedArray.length
    lim_kind = 0
    lim_val = 0
    lim_reg = nil
    lim_container = -1
    temp_hoist_arr = -1
    temp_arr_gprs = nil
    l_temp_arr_slow = nil
    eb = s.b.b
    if eb.kind == :num && jit_int32_lit?(eb) && eb.a.to_i >= 0
      lim_kind = 1
      lim_val = eb.a.to_i
    elsif eb.kind == :ident
      lli = local_idx(eb)
      if lli >= 0 && lli != li && @info.types[lli] == JT_I32 && @info.reg_gpr[lli] != nil && !stmt_writes_local?(s.d, lli)
        lim_kind = 2
        lim_reg = @info.reg_gpr[lli]
    elsif eb.kind == :member && !eb.has?(F_COMPUTED) && eb.b.str == "length"
      cli = local_idx(eb.a)
      if cli >= 0 && @hoisted_arrs[cli] != nil
        lim_kind = 3
        lim_container = cli
      elsif cli >= 0 && @hoisted_tas[cli] != nil
        lim_kind = 4
        lim_container = cli
      elsif cli >= 0 && @info.types[cli] == JT_ANY && !stmt_mutates_arr?(s.d, cli) && @free_gprs.size >= 2
        # Loop-local read-only dense Array hoisting (e.g. Loop 2 of arrays_warm: `for (i=0; i<a.length; i++) s += a[i]`)!
        temp_hoist_arr = cli
        lim_kind = 3
        lim_container = cli
    return false if lim_kind == 0
    # Hoist large constant limit (> 4095) into a free GPR if available!
    borrowed_gpr = nil
    if lim_kind == 1 && lim_val > 4095 && @free_gprs.size > 0
      borrowed_gpr = @free_gprs.pop
      @a.mov_imm32(borrowed_gpr, lim_val)
      lim_reg = borrowed_gpr
    # Fast hoisted monomorphic mutating method loop (`for (i=0; i<n; i++) s += p.step(1, -1)`)!
    if temp_hoist_arr < 0 && try_gen_hoisted_method_loop(s, li, ri, lim_kind, lim_val, lim_reg, lim_container)
      @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
      return true
    # If loop-local read-only array hoisting is active, guard dense plain array ONCE before loop!
    l_temp_arr_done = nil
    if temp_hoist_arr >= 0
      l_temp_arr_slow = @a.new_label
      l_temp_arr_done = @a.new_label
      r_sl = @free_gprs.pop
      r_ln = @free_gprs.pop
      temp_arr_gprs = [r_sl, r_ln]
      load_slot_any(R_X9, temp_hoist_arr)
      @a.lsr_xi(R_X10, R_X9, 48)
      @a.movz_x(R_X11, 0xFFF4)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_temp_arr_slow)
      @a.and_x_ptr47(R_X9, R_X9)
      @a.ldrb(R_X10, R_X9, 2)
      @a.cmp_wi(R_X10, 1)
      @a.b_cond(CC_NE, l_temp_arr_slow)
      @a.ldr_w(R_X10, R_X9, 4)
      @a.cbnz_w(R_X10, l_temp_arr_slow)
      @a.ldr_x(r_sl, R_X9, 16)
      @a.ldrsw(r_ln, R_X9, 8)
      @hoisted_arrs[temp_hoist_arr] = [0, 0]
      @hoisted_arr_regs[temp_hoist_arr] = temp_arr_gprs
    # Check if i is guaranteed >= 0 inside the loop (initialized to >= 0 literal OR `outer_nonneg + K`!)
    nonneg_known = false
    if run_init && s.a != nil
      init_rhs = nil
      if s.a.kind == :var_decl && s.a.list.size == 1 && local_idx(s.a.list[0].a) == li
        init_rhs = s.a.list[0].b
      elsif s.a.kind == :assign && s.a.str == "=" && local_idx(s.a.a) == li
        init_rhs = s.a.b
      if init_rhs != nil
        if init_rhs.kind == :num && jit_int32_lit?(init_rhs) && init_rhs.a.to_i >= 0
          nonneg_known = true
        elsif init_rhs.kind == :binary && init_rhs.str == "+" && init_rhs.b.kind == :num && jit_int32_lit?(init_rhs.b) && init_rhs.b.a.to_i >= 0
          oli = local_idx(init_rhs.a)
          nonneg_known = true if oli >= 0 && @bounded_idx[oli] != nil
    saved_shapes = @known_shapes.dup
    l_head = @a.new_label
    l_cont = @a.new_label
    l_brk = @a.new_label
    # Initial entry guard: skip loop completely if i >= limit!
    emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
    # Mark bounded index if 0 <= i < container.length is guaranteed!
    old_bound = @bounded_idx[li]
    if nonneg_known && lim_container >= 0
      @bounded_idx[li] = lim_container
    # TypedArray BCE for `for (k = 0; k < n; k++)` when n is a JT_I32 local (`lim_kind == 2`):
    # If body indexes hoisted TypedArrays by `k` or `(expr % n)`, verify `n <= ta.len` ONCE at loop entry!
    bce_tas = []
    if nonneg_known && lim_kind == 2 && @hoisted_tas.size > 0 && @promoted_owner < 0
      lim_li = local_idx(eb)
      collect_ta_bce_cands(s.d, li, lim_li, bce_tas)
    l_unbce_loop = nil
    if bce_tas.size > 0
      l_unbce_loop = @a.new_label
      bi = 0
      while bi < bce_tas.size
        tli = bce_tas[bi]
        tr = @hoisted_ta_regs[tli]
        if tr != nil && tr[1] != nil
          @a.cmp_w(lim_reg, tr[1])
        else
          @a.ldr_x(R_X9, R_SP, @hoisted_tas[tli][1])
          @a.cmp_w(lim_reg, R_X9)
        @a.b_cond(CC_GT, l_unbce_loop)
        bi += 1
      # Inside fast loop, all `bce_tas` are guaranteed `0 <= k < n <= ta.len` and `0 <= (expr % n) < n <= ta.len`!
      lim_li = local_idx(eb)
      bce_tas.each ->(tli)
        @bounded_ta_set[li.to_s + ":" + tli.to_s] = true
        @bounded_mod_ta[lim_li.to_s + ":" + tli.to_s] = true if lim_li >= 0

    # Inner-loop Object Field Scalar Promotion (e.g. `a.x/y/z/m` read-only + `a.vx/vy/vz` read-write in n-body!):
    # Promotes an outer-loop shape-guarded local's numeric fields into FP registers across the inner loop,
    # with an out-of-line unpromoted fallback loop for non-numbers, shape mismatches, or aliasing (`b === a`)!
    promo = nil
    if @in_loop_depth >= 1 && @promoted_owner < 0 && bce_tas.size == 0 && temp_hoist_arr < 0 && s.d != nil && s.d.kind == :block && !stmt_has_cf_or_loop?(s.d) && osr_loop_pure_epoch?(s.d)
      promo = find_promoted_outer_obj(s.d, li)

    if promo != nil
      ali = promo[0]
      ro_fields = promo[1]
      rw_fields = promo[2]
      other_wlis = promo[3]
      l_flush_unpromo = @a.new_label
      l_unpromo_enter = @a.new_label
      old_pfp = @block_prop_fp
      old_npfp = @next_prop_fp
      old_prw = @promoted_rw
      old_prwl = @promoted_rw_list
      old_pown = @promoted_owner
      old_poth = @promoted_other_lis
      old_pbail = @promoted_bail_lbl
      ro_regs = []
      rw_regs = []
      # Preload all ro_fields and rw_fields from `ali` into FP regs before inner loop
      r_a = @info.reg_gpr[ali]
      if r_a != nil
        @a.sub_i(R_X9, r_a, 4)
      else
        load_slot_any(R_X9, ali)
        @a.sub_i(R_X9, R_X9, 4)
      is_num_a = @d_bias_reg != nil && @known_shapes[ali] != nil && @mono_arr_num[@known_shapes[ali]] == true
      fi = 0
      while fi < ro_fields.size
        f = ro_fields[fi]
        dr = @next_prop_fp
        @next_prop_fp += 1
        if is_num_a && f[1] > 0
          @a.ldr_d(dr, R_X9, (f[1] + 1) * 8)
          @a.sub_d_i64(dr, dr, @d_bias_reg)
        else
          emit_slot_load(R_X10, R_X9, f[1])
          emit_unbox_f64(dr, R_X10, l_unpromo_enter)
        ro_regs.push([f[0], f[1], dr])
        fi += 1
      fi = 0
      while fi < rw_fields.size
        f = rw_fields[fi]
        dr = @next_prop_fp
        @next_prop_fp += 1
        if is_num_a && f[1] > 0
          @a.ldr_d(dr, R_X9, (f[1] + 1) * 8)
          @a.sub_d_i64(dr, dr, @d_bias_reg)
        else
          emit_slot_load(R_X10, R_X9, f[1])
          emit_unbox_f64(dr, R_X10, l_unpromo_enter)
        rw_regs.push([f[0], f[1], dr])
        fi += 1
      @block_prop_fp = old_pfp.dup
      @promoted_rw = {}
      ro_regs.each ->(fr) @block_prop_fp[ali.to_s + ":" + fr[0]] = fr[2]
      rw_regs.each ->(fr)
        @block_prop_fp[ali.to_s + ":" + fr[0]] = fr[2]
        @promoted_rw[ali.to_s + ":" + fr[0]] = fr[2]
      @promoted_rw_list = rw_regs
      @promoted_owner = ali
      @promoted_other_lis = other_wlis
      @promoted_bail_lbl = l_flush_unpromo
      # Hoist up to 2 FP literals used in inner loop body (e.g. `0.01`) into free d18..d31 regs!
      old_cfp = @block_const_fp
      @block_const_fp = old_cfp.dup
      fconsts = []
      collect_fp_consts(s.d, fconsts)
      ci = 0
      while ci < fconsts.size && ci < 2 && @next_prop_fp <= R_D31
        fb = fconsts[ci]
        if @block_const_fp[fb] == nil
          cr = @next_prop_fp
          @next_prop_fp += 1
          @a.mov_imm64(R_X9, fb)
          @a.fmov_d_x(cr, R_X9)
          @block_const_fp[fb] = cr
        ci += 1
      @loops.push(JS:JitLoopCtx.new(l_brk, l_cont, nil))
      @in_loop_depth += 1
      @a.bind(l_head)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      @a.add_wi(ri, ri, 1)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
      # Normal inner-loop exit: box & write back promoted rw_fields ONCE!
      if rw_regs.size > 0
        if r_a != nil
          @a.sub_i(R_X9, r_a, 4)
        else
          load_slot_any(R_X9, ali)
          @a.sub_i(R_X9, R_X9, 4)
        rw_regs.each ->(fr)
          if @d_bias_reg != nil && fr[1] > 0
            @a.add_d_i64(R_D16, fr[2], @d_bias_reg)
            @a.str_d(R_D16, R_X9, (fr[1] + 1) * 8)
          else
            emit_box_f64_nonan(R_X0, fr[2])
            emit_slot_store(R_X9, fr[1], R_X0)
      @a.bind(l_brk)
      @in_loop_depth -= 1
      @loops.pop
      @block_prop_fp = old_pfp
      @block_const_fp = old_cfp
      @next_prop_fp = old_npfp
      @promoted_rw = old_prw
      @promoted_rw_list = old_prwl
      @promoted_owner = old_pown
      @promoted_other_lis = old_poth
      @promoted_bail_lbl = old_pbail
      # Emit out-of-line unpromoted fallback loop (handles aliasing `b === a`, shape changes, non-numbers!)
      cb = ->()
        @a.bind(l_flush_unpromo)
        if rw_regs.size > 0
          if r_a != nil
            @a.sub_i(R_X9, r_a, 4)
          else
            load_slot_any(R_X9, ali)
            @a.sub_i(R_X9, R_X9, 4)
          rw_regs.each ->(fr)
            emit_box_f64_nonan(R_X0, fr[2])
            emit_slot_store(R_X9, fr[1], R_X0)
        @a.bind(l_unpromo_enter)
        sv_sh = @known_shapes
        sv_pfp = @block_prop_fp
        sv_cfp = @block_const_fp
        sv_wp = @block_written_props
        sv_np = @next_prop_fp
        sv_prw = @promoted_rw
        sv_prwl = @promoted_rw_list
        sv_pown = @promoted_owner
        sv_poth = @promoted_other_lis
        sv_pbail = @promoted_bail_lbl
        @known_shapes = {}
        @block_prop_fp = {}
        @block_const_fp = {}
        @block_written_props = nil
        @next_prop_fp = R_D18
        @promoted_rw = {}
        @promoted_rw_list = nil
        @promoted_owner = -1
        @promoted_other_lis = nil
        @promoted_bail_lbl = nil
        l_uhead = @a.new_label
        @a.bind(l_uhead)
        gen_stmt(s.d)
        @a.add_wi(ri, ri, 1)
        emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_uhead)
        @known_shapes = sv_sh
        @block_prop_fp = sv_pfp
        @block_const_fp = sv_cfp
        @block_written_props = sv_wp
        @next_prop_fp = sv_np
        @promoted_rw = sv_prw
        @promoted_rw_list = sv_prwl
        @promoted_owner = sv_pown
        @promoted_other_lis = sv_poth
        @promoted_bail_lbl = sv_pbail
        @a.b(l_brk)
      add_cold_stub(cb)
      if old_bound == nil
        @bounded_idx.delete(li)
      else
        @bounded_idx[li] = old_bound
      @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
      @known_shapes = saved_shapes
      return true

    # Counted-loop Call-Hoisting (`for (var s = 0; s < N; s++) fn(inv_args...)`):
    # When body is a single static-cell call to a pure-shape leaf function with jit_repeat_fp,
    # run fn's prologue + shape/numeric guards ONCE and loop N times inside fn with zero call overhead!
    rep_call = (promo == nil && bce_tas.size == 0 && @promoted_owner < 0 && temp_hoist_arr < 0) ? stmt_single_call(s.d) : nil
    if rep_call != nil && rep_call.a != nil && rep_call.a.kind == :ident && rep_call.list.size <= 3
      rc_b = rep_call.a.x == nil ? nil : rep_call.a.x.binding
      if rc_b != nil && rc_b.global?
        rc_cell = wk_cell(rc_b)
        rc_fv = rc_cell.value
        if rc_fv.is_a?(JS:Function) && rc_fv.code != nil && rc_fv.code.nparams == rep_call.list.size
          jit_compile_and_install(rc_fv.code) if rc_fv.code.jit_state == 0 && rc_fv.code.node != @jf
          if rc_fv.code.jit_repeat_fp != 0
            all_inv = true
            ai = 0
            while ai < rep_call.list.size && all_inv
              all_inv = false if !arg_loop_inv?(rep_call.list[ai], li)
              ai += 1
            if all_inv
              jit_keep(rc_cell)
              jit_keep(rc_fv)
              l_rep_slow = @a.new_label
              # Guard global cell STILL holds rc_fv!
              cptr = (wvalue_bits(rc_cell) ## i64) - 4
              @a.mov_imm64(R_X9, cptr)
              @a.ldr_x(R_X10, R_X9, 8)
              @a.mov_imm64(R_X0, wvalue_bits(rc_fv) ## i64)
              @a.cmp_r(R_X10, R_X0)
              @a.b_cond(CC_NE, l_rep_slow)
              # Load loop-invariant args into R_X3..R_X5
              ai = 0
              while ai < rep_call.list.size
                ae = rep_call.list[ai]
                if ae.kind == :num
                  @a.mov_imm64(R_X3 + ai, wvalue_bits(ae.a) ## i64)
                else
                  load_slot_any(R_X3 + ai, local_idx(ae))
                ai += 1
              # Compute repeat count = lim - ri into R_X7 (guaranteed > 0 by entry guard!)
              if lim_kind == 1
                if lim_reg != nil
                  @a.sub_w(R_X7, lim_reg, ri)
                else
                  @a.mov_imm32(R_X7, lim_val)
                  @a.sub_w(R_X7, R_X7, ri)
              elsif lim_kind == 2
                @a.sub_w(R_X7, lim_reg, ri)
              elsif lim_kind == 3
                ar_l = @hoisted_arr_regs[lim_container]
                if ar_l != nil && ar_l[1] != nil
                  @a.sub_w(R_X7, ar_l[1], ri)
                else
                  @a.ldr_x(R_X7, R_SP, @hoisted_arrs[lim_container][1])
                  @a.sub_w(R_X7, R_X7, ri)
              else
                tr_l = @hoisted_ta_regs[lim_container]
                if tr_l != nil && tr_l[1] != nil
                  @a.sub_w(R_X7, tr_l[1], ri)
                else
                  @a.ldr_x(R_X7, R_SP, @hoisted_tas[lim_container][1])
                  @a.sub_w(R_X7, R_X7, ri)
              @a.movz_x(R_X1, 0)
              @a.movz_x(R_X2, rep_call.list.size)
              @a.mov_imm64(R_X16, rc_fv.code.jit_repeat_fp)
              @a.blr(R_X16)
              @a.cmp_i(R_X0, 6)    # JSR_SLOW -> zero mutations happened, run normal loop!
              @a.b_cond(CC_EQ, l_rep_slow)
              # Advance loop induction variable `ri = lim`!
              if lim_kind == 1
                if lim_reg != nil
                  @a.mov_w(ri, lim_reg)
                else
                  @a.mov_imm32(ri, lim_val)
              elsif lim_kind == 2
                @a.mov_w(ri, lim_reg)
              elsif lim_kind == 3
                ar_l = @hoisted_arr_regs[lim_container]
                if ar_l != nil && ar_l[1] != nil
                  @a.mov_w(ri, ar_l[1])
                else
                  @a.ldr_x(ri, R_SP, @hoisted_arrs[lim_container][1])
              else
                tr_l = @hoisted_ta_regs[lim_container]
                if tr_l != nil && tr_l[1] != nil
                  @a.mov_w(ri, tr_l[1])
                else
                  @a.ldr_x(ri, R_SP, @hoisted_tas[lim_container][1])
              @a.bind(l_brk)
              cb_rep = ->()
                @a.bind(l_rep_slow)
                l_rhead = @a.new_label
                l_rcont = @a.new_label
                @loops.push(JS:JitLoopCtx.new(l_brk, l_rcont, nil))
                @in_loop_depth += 1
                @a.bind(l_rhead)
                gen_stmt(s.d)
                @a.bind(l_rcont)
                @a.add_wi(ri, ri, 1)
                emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_rhead)
                @a.b(l_brk)
                @in_loop_depth -= 1
                @loops.pop
              add_cold_stub(cb_rep)
              if old_bound == nil
                @bounded_idx.delete(li)
              else
                @bounded_idx[li] = old_bound
              @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
              @known_shapes = saved_shapes
              return true

    # Loop StringBuilder Promotion (`for (i = 0; i < N; i++) s += expr`):
    # When a counted loop only appends to a string local `s`, accumulate into ONE StringBuffer
    # (ZERO intermediate ropes/strings!) and materialize `s = sb.to_s` once on loop exit!
    sb_info = nil
    if promo == nil && bce_tas.size == 0 && @promoted_owner < 0 && temp_hoist_arr < 0 && !stmt_has_cf_or_loop?(s.d) && osr_loop_pure_epoch?(s.d)
      sb_info = find_sb_loop_target(s.d, li)
    if sb_info != nil
      sli = sb_info[0]
      rhs = sb_info[1]
      # Ultra-fast flat-ByteArray builder for `for (i=0; i<N; i++) s += \`pre${i}suf\`` with i32 expr!
      if rhs.kind == :template && rhs.a.size == 1 && rhs.list.size == 2 && rhs.list[0].str.ascii? && rhs.list[1].str.ascii? && can_i32?(rhs.a[0])
        pre_s = rhs.list[0].str
        suf_s = rhs.list[1].str
        jit_keep(pre_s)
        jit_keep(suf_s)
        l_sb_slow = @a.new_label
        load_slot_any(R_X1, sli)
        call_rt(RT_BA_SB_NEW)
        @a.cbz_x(R_X0, l_sb_slow)
        sb_off = push_x(R_X0)
        r_iv_peek = peek_i32_reg(rhs.a[0])
        if r_iv_peek != nil && pre_s.size <= 16 && suf_s.size <= 16
          # Inline ARM64 ByteArray writer (ZERO runtime calls per iteration for 0 <= iv < 100!)
          @a.sub_i(R_X9, R_X0, 4)
          @a.ldr_x(R_X10, R_X9, 8)        # jb.@hdr (ivar 0 = i64[3])
          @a.and_x_ptr47(R_X10, R_X10)
          @a.ldr_x(R_X10, R_X10, 16)      # hdr.slots = [dst_ptr, pos, cap]
          hdr_off = push_x(R_X10)
          @a.ldr_x(R_X12, R_X10, 0)       # x12 = dst_ptr
          @a.ldr_x(R_X13, R_X10, 8)       # x13 = pos
          @a.ldr_x(R_X14, R_X10, 16)      # x14 = cap
          l_sb_grow = @a.new_label
          l_2dig = @a.new_label
          l_suf = @a.new_label
          @loops.push(JS:JitLoopCtx.new(l_brk, l_cont, nil))
          @in_loop_depth += 1
          @a.bind(l_head)
          # Bounds + 0..99 range guard (overflow or <0 or >=100 jumps to out-of-line RT_BA_SB_TPL_I32!)
          @a.add_i(R_X11, R_X13, pre_s.size + 12 + suf_s.size)
          @a.cmp_r(R_X11, R_X14)
          @a.b_cond(CC_HI, l_sb_grow)
          @a.cmp_wi(r_iv_peek, 100)
          @a.b_cond(CC_HS, l_sb_grow)
          @a.add_r(R_X15, R_X12, R_X13)   # x15 = dst_ptr + pos
          # Emit compile-time constant prefix bytes!
          emit_const_ascii_stores(R_X15, pre_s)
          @a.add_i(R_X15, R_X15, pre_s.size) if pre_s.size > 0
          # Format 0 <= r_iv_peek < 100 directly to ASCII digits!
          @a.cmp_wi(r_iv_peek, 10)
          @a.b_cond(CC_GE, l_2dig)
          @a.add_wi(R_X11, r_iv_peek, 48)
          @a.strb(R_X11, R_X15, 0)
          @a.add_i(R_X15, R_X15, 1)
          @a.b(l_suf)
          @a.bind(l_2dig)
          @a.movz_x(R_X11, 52429)
          @a.mul_w(R_X11, r_iv_peek, R_X11)
          @a.lsr_xi(R_X11, R_X11, 19)     # q = iv / 10 (exact for 0..81919)
          @a.movz_x(R_X10, 10)
          @a.mul_w(R_X10, R_X11, R_X10)
          @a.sub_w(R_X10, r_iv_peek, R_X10)  # r = iv - 10 * q
          @a.add_wi(R_X11, R_X11, 48)
          @a.strb(R_X11, R_X15, 0)
          @a.add_wi(R_X10, R_X10, 48)
          @a.strb(R_X10, R_X15, 1)
          @a.add_i(R_X15, R_X15, 2)
          @a.bind(l_suf)
          # Emit compile-time constant suffix bytes!
          emit_const_ascii_stores(R_X15, suf_s)
          @a.add_i(R_X15, R_X15, suf_s.size) if suf_s.size > 0
          @a.sub_r(R_X13, R_X15, R_X12)   # pos = ptr - dst_ptr
          @a.bind(l_cont)
          @a.add_wi(ri, ri, 1)
          emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
          # Sync pos to hdr[1] and materialize flat String!
          @a.ldr_x(R_X10, R_SP, hdr_off)
          @a.str_x(R_X13, R_X10, 8)
          @a.ldr_x(R_X1, R_SP, sb_off)
          call_rt(RT_BA_SB_FINISH)
          store_slot_any(sli, R_X0)
          @tmp_depth -= 2
          @a.bind(l_brk)
          @in_loop_depth -= 1
          @loops.pop
          cb_grow = ->()
            @a.bind(l_sb_grow)
            @a.ldr_x(R_X10, R_SP, hdr_off)
            @a.str_x(R_X13, R_X10, 8)
            @a.sxtw(R_X3, r_iv_peek)
            @a.movk_x(R_X3, 0xFFFA, 3)
            @a.ldr_x(R_X1, R_SP, sb_off)
            @a.mov_imm64(R_X2, wvalue_bits(pre_s) ## i64)
            @a.mov_imm64(R_X4, wvalue_bits(suf_s) ## i64)
            call_rt(RT_BA_SB_TPL_I32)
            @a.ldr_x(R_X10, R_SP, hdr_off)
            @a.ldr_x(R_X12, R_X10, 0)
            @a.ldr_x(R_X13, R_X10, 8)
            @a.ldr_x(R_X14, R_X10, 16)
            @a.b(l_cont)
          add_cold_stub(cb_grow)
          cb = ->()
            @a.bind(l_sb_slow)
            l_uhead = @a.new_label
            @a.bind(l_uhead)
            gen_stmt(s.d)
            @a.add_wi(ri, ri, 1)
            emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_uhead)
            @a.b(l_brk)
          add_cold_stub(cb)
          if old_bound == nil
            @bounded_idx.delete(li)
          else
            @bounded_idx[li] = old_bound
          @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
          @known_shapes = saved_shapes
          return true
        @loops.push(JS:JitLoopCtx.new(l_brk, l_cont, nil))
        @in_loop_depth += 1
        @a.bind(l_head)
        r_iv = peek_i32_reg(rhs.a[0])
        if r_iv != nil
          @a.sxtw(R_X3, r_iv)
        else
          gen_expr_i32(rhs.a[0])
          @a.sxtw(R_X3, R_X0)
        @a.movk_x(R_X3, 0xFFFA, 3)   # box signed i32 -> Tungsten Int WValue (W_TAG_INT = 0xFFFA, 2 insns!)
        @a.ldr_x(R_X1, R_SP, sb_off)
        @a.mov_imm64(R_X2, wvalue_bits(pre_s) ## i64)
        @a.mov_imm64(R_X4, wvalue_bits(suf_s) ## i64)
        call_rt(RT_BA_SB_TPL_I32)
        @a.bind(l_cont)
        @a.add_wi(ri, ri, 1)
        emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
        @a.ldr_x(R_X1, R_SP, sb_off)
        call_rt(RT_BA_SB_FINISH)
        store_slot_any(sli, R_X0)
        @tmp_depth -= 1
        @a.bind(l_brk)
        @in_loop_depth -= 1
        @loops.pop
        cb = ->()
          @a.bind(l_sb_slow)
          l_uhead = @a.new_label
          @a.bind(l_uhead)
          gen_stmt(s.d)
          @a.add_wi(ri, ri, 1)
          emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_uhead)
          @a.b(l_brk)
        add_cold_stub(cb)
        if old_bound == nil
          @bounded_idx.delete(li)
        else
          @bounded_idx[li] = old_bound
        @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
        @known_shapes = saved_shapes
        return true
      l_sb_slow = @a.new_label
      load_slot_any(R_X1, sli)
      call_rt(RT_SB_NEW)
      @a.cbz_x(R_X0, l_sb_slow)
      sb_off = push_x(R_X0)
      @loops.push(JS:JitLoopCtx.new(l_brk, l_cont, nil))
      @in_loop_depth += 1
      @a.bind(l_head)
      if rhs.kind == :template && rhs.a.size == 1 && rhs.list.size == 2 && rhs.list[0].str.ascii? && rhs.list[1].str.ascii?
        pre_s = rhs.list[0].str
        suf_s = rhs.list[1].str
        jit_keep(pre_s)
        jit_keep(suf_s)
        gen_expr_any(rhs.a[0])
        @a.mov_r(R_X3, R_X0)
        @a.ldr_x(R_X1, R_SP, sb_off)
        @a.mov_imm64(R_X2, wvalue_bits(pre_s) ## i64)
        @a.mov_imm64(R_X4, wvalue_bits(suf_s) ## i64)
        call_rt(RT_SB_APP_TPL1)
      else
        gen_expr_any(rhs)
        @a.mov_r(R_X2, R_X0)
        @a.ldr_x(R_X1, R_SP, sb_off)
        call_rt(RT_SB_APP_VAL)
      @a.bind(l_cont)
      @a.add_wi(ri, ri, 1)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
      @a.ldr_x(R_X1, R_SP, sb_off)
      call_rt(RT_SB_FINISH)
      store_slot_any(sli, R_X0)
      @tmp_depth -= 1
      @a.bind(l_brk)
      @in_loop_depth -= 1
      @loops.pop
      cb = ->()
        @a.bind(l_sb_slow)
        l_uhead = @a.new_label
        @a.bind(l_uhead)
        gen_stmt(s.d)
        @a.add_wi(ri, ri, 1)
        emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_uhead)
        @a.b(l_brk)
      add_cold_stub(cb)
      if old_bound == nil
        @bounded_idx.delete(li)
      else
        @bounded_idx[li] = old_bound
      @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
      @known_shapes = saved_shapes
      return true

    # Direct f64 Dense-Array Sum Fast Path (`for (i = 0; i < arr.length; i++) s += arr[i]`):
    # Works for BOTH JT_ANY and JT_F64 `s`, 2x unrolled, zero bounds checks, exact IEEE-754 double addition!
    fsum_st = s.d
    fsum_st = fsum_st.list[0] if fsum_st.is_a?(JsNode) && fsum_st.kind == :block && fsum_st.list.size == 1
    if lim_kind == 3 && lim_container >= 0 && @bounded_idx[li] == lim_container && @promoted_owner < 0 && fsum_st.is_a?(JsNode) && fsum_st.kind == :expr_stmt && fsum_st.a != nil && fsum_st.a.kind == :assign && fsum_st.a.str == "+=" && fsum_st.a.a.kind == :ident && fsum_st.a.b.kind == :member && fsum_st.a.b.has?(F_COMPUTED) && local_idx(fsum_st.a.b.a) == lim_container && local_idx(fsum_st.a.b.b) == li
      facc_li = local_idx(fsum_st.a.a)
      if facc_li >= 0 && facc_li != li && facc_li != lim_container && (@info.types[facc_li] == JT_ANY || @info.types[facc_li] == JT_F64)
        ar_f = @hoisted_arr_regs[lim_container]
        r_sl_f = (ar_f != nil && ar_f[0] != nil) ? ar_f[0] : nil
        if r_sl_f != nil
          l_fs_bail = @a.new_label
          l_fs_slow = @a.new_label
          l_fs_done = @a.new_label
          l_fs_epi = @a.new_label
          facc_any = @info.types[facc_li] == JT_ANY
          dr_fs = (!facc_any && @info.reg_fpr[facc_li] != nil) ? @info.reg_fpr[facc_li] : R_D2
          if facc_any
            load_slot_any(R_X0, facc_li)
            emit_unbox_f64(dr_fs, R_X0, l_fs_slow)
          elsif @info.reg_fpr[facc_li] == nil
            load_slot_f64(dr_fs, facc_li)
          emit_counted_cmp_p1_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_fs_epi)
          @a.bind(l_head)
          @a.ldr_x_idx(R_X0, r_sl_f, ri)
          @a.sub_r(R_X15, R_X0, R_X20)
          @a.cmp_r(R_X15, R_X21)
          @a.b_cond(CC_HS, l_fs_bail)
          @a.fmov_d_x(R_D0, R_X15)
          @a.fadd_d(dr_fs, dr_fs, R_D0)
          @a.add_wi(ri, ri, 1)
          @a.ldr_x_idx(R_X0, r_sl_f, ri)
          @a.sub_r(R_X15, R_X0, R_X20)
          @a.cmp_r(R_X15, R_X21)
          @a.b_cond(CC_HS, l_fs_bail)
          @a.fmov_d_x(R_D0, R_X15)
          @a.fadd_d(dr_fs, dr_fs, R_D0)
          @a.add_wi(ri, ri, 1)
          emit_counted_cmp_p1_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
          @a.bind(l_fs_epi)
          emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_fs_done)
          @a.ldr_x_idx(R_X0, r_sl_f, ri)
          @a.sub_r(R_X15, R_X0, R_X20)
          @a.cmp_r(R_X15, R_X21)
          @a.b_cond(CC_HS, l_fs_bail)
          @a.fmov_d_x(R_D0, R_X15)
          @a.fadd_d(dr_fs, dr_fs, R_D0)
          @a.add_wi(ri, ri, 1)
          @a.bind(l_fs_done)
          if facc_any
            emit_box_f64(R_X0, dr_fs)
            store_slot_any(facc_li, R_X0)
          elsif @info.reg_fpr[facc_li] == nil
            store_slot_f64(facc_li, dr_fs)
          @a.bind(l_brk)
          sv_tha_f = temp_hoist_arr
          sv_tha_gprs_f = temp_arr_gprs
          cb_fs = ->()
            if sv_tha_f >= 0
              @hoisted_arrs[sv_tha_f] = [0, 0]
              @hoisted_arr_regs[sv_tha_f] = sv_tha_gprs_f
            @a.bind(l_fs_bail)
            if facc_any
              emit_box_f64(R_X0, dr_fs)
              store_slot_any(facc_li, R_X0)
            elsif @info.reg_fpr[facc_li] == nil
              store_slot_f64(facc_li, dr_fs)
            @a.bind(l_fs_slow)
            l_uhead = @a.new_label
            @a.bind(l_uhead)
            emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
            gen_loop_body_stmt(s.d)
            @a.add_wi(ri, ri, 1)
            @a.b(l_uhead)
            if sv_tha_f >= 0
              @hoisted_arrs.delete(sv_tha_f)
              @hoisted_arr_regs.delete(sv_tha_f)
          add_cold_stub(cb_fs)
          if old_bound == nil
            @bounded_idx.delete(li)
          else
            @bounded_idx[li] = old_bound
          if temp_hoist_arr >= 0
            @a.bind(l_temp_arr_done)
            @hoisted_arrs.delete(temp_hoist_arr)
            @hoisted_arr_regs.delete(temp_hoist_arr)
            @free_gprs.push(temp_arr_gprs[0])
            @free_gprs.push(temp_arr_gprs[1])
            cb_ta = ->()
              @a.bind(l_temp_arr_slow)
              l_uhead = @a.new_label
              l_ucont = @a.new_label
              @loops.push(JS:JitLoopCtx.new(l_temp_arr_done, l_ucont, nil))
              @a.bind(l_uhead)
              gen_cond_branch(s.b, l_temp_arr_done, false)
              gen_loop_body_stmt(s.d)
              @a.bind(l_ucont)
              gen_expr_void(s.c)
              @a.b(l_uhead)
              @loops.pop
            add_cold_stub(cb_ta)
          @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
          @known_shapes = saved_shapes
          return true

    # Hoisted Counted Map Loop Fast Path:
    #   Case A: `for (i = 0; i < lim; i++) m.set(key_i32, val_num);`
    #   Case B: `for (i = 0; i < lim; i++) s += m.get(key_i32);`
    # Hoists epoch, Map shape, MapData meta_p, buckets/mask/keys/vals, and hash multiplier ONCE before the loop!
    if !@is_osr && @promoted_owner < 0 && temp_hoist_arr < 0 && (lim_kind == 1 || lim_kind == 2) && fsum_st.is_a?(JsNode) && fsum_st.kind == :expr_stmt && fsum_st.a != nil
      mp_off_hl = js_mapdata_metap_off()
      r_hl = mp_off_hl > 0 ? js_realm() : nil
      mp_hl = r_hl != nil ? r_hl.intrinsics["Map.prototype"] : nil
      if mp_hl != nil
        # Case A: `m.set(key_e, val_e)`
        if fsum_st.a.kind == :call && fsum_st.a.a.kind == :member && !fsum_st.a.a.has?(F_COMPUTED) && fsum_st.a.a.b.str == "set" && fsum_st.a.list.size == 2 && mp_hl.get_own("set") == r_hl.intrinsics["%Map_set%"] && @free_gprs.size >= 2
          mli = local_idx(fsum_st.a.a.a)
          key_e = fsum_st.a.list[0]
          val_e = fsum_st.a.list[1]
          if mli >= 0 && mli != li && @info.types[mli] == JT_ANY && can_i32?(key_e) && (can_i32?(val_e) || can_f64?(val_e)) && !stmt_writes_local?(key_e, mli) && !stmt_writes_local?(val_e, mli) && !stmt_writes_local?(key_e, li) && !stmt_writes_local?(val_e, li) && osr_loop_pure_epoch?(key_e) && osr_loop_pure_epoch?(val_e)
            map_sh = js_root_shape(mp_hl, SP_INLINE, SP_IBASE)
            jit_keep(map_sh)
            r_meta = @free_gprs.pop
            r_hmul = @free_gprs.pop
            r_bptr = @free_gprs.size >= 2 ? @free_gprs.pop : nil
            r_mask = r_bptr != nil ? @free_gprs.pop : nil
            l_ms_slow = @a.new_label
            l_ms_rt = @a.new_label
            l_ploop = @a.new_label
            l_pstep = @a.new_label
            l_pdel = @a.new_label
            l_phit = @a.new_label
            l_pmiss = @a.new_label
            # Guard epoch + Map shape + meta_p ONCE before loop!
            if !@hoisted_epoch
              ep_now = JS_EPOCH[0]
              @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
              @a.ldr_x(R_X10, R_X9, 0)
              @a.mov_imm64(R_X11, ep_now)
              @a.cmp_r(R_X10, R_X11)
              @a.b_cond(CC_NE, l_ms_slow)
            load_slot_any(R_X1, mli)
            @a.sub_i(R_X9, R_X1, 4)
            @a.tst_wobj_bad(R_X9)
            @a.b_cond(CC_NE, l_ms_slow)
            @a.ldr_x(R_X10, R_X9, 8)
            @a.mov_imm64(R_X11, wvalue_bits(map_sh) ## i64)
            @a.cmp_r(R_X10, R_X11)
            @a.b_cond(CC_NE, l_ms_slow)
            @a.ldr_x(R_X9, R_X9, 32)
            @a.sub_i(R_X9, R_X9, 4)
            @a.ldr_x(r_meta, R_X9, mp_off_hl)
            @a.and_x_lowmask(r_meta, r_meta, 48)
            @a.ldr_x(R_X13, r_meta, 8)
            @a.cbz_x(R_X13, l_ms_slow)
            if r_bptr != nil
              @a.ldr_x(r_bptr, r_meta, 0)
              @a.mov_r(r_mask, R_X13)
            @a.movz_x(r_hmul, 0xE5B9, 0)
            @a.movk_x(r_hmul, 0x1CE4, 1)
            @a.movk_x(r_hmul, 0x476D, 2)
            @a.movk_x(r_hmul, 0xBF58, 3)
            bp_r = r_bptr != nil ? r_bptr : R_X9
            mk_r = r_mask != nil ? r_mask : R_X13
            @a.bind(l_head)
            rk_hl = peek_i32_reg(key_e)
            if rk_hl != nil
              if can_i32?(val_e)
                rv_hl = peek_i32_reg(val_e)
                if rv_hl != nil
                  emit_box_i32(R_X3, rv_hl)
                else
                  gen_expr_i32(val_e)
                  emit_box_i32(R_X3, R_X0)
              else
                gen_expr_f64(val_e)
                emit_box_f64(R_X3, R_D0)
              emit_box_i32(R_X14, rk_hl)
            else
              if can_i32?(val_e)
                gen_expr_i32(val_e)
                emit_box_i32(R_X0, R_X0)
              else
                gen_expr_f64(val_e)
                emit_box_f64(R_X0, R_D0)
              v_off_hl = push_x(R_X0)
              gen_expr_i32(key_e)
              emit_box_i32(R_X14, R_X0)
              @a.ldr_x(R_X3, R_SP, v_off_hl)
              @tmp_depth -= 1
            # 1-mul 31-bit hash -> R_X15
            @a.lsr_xi(R_X15, R_X14, 32)
            @a.eor_r(R_X15, R_X14, R_X15)
            @a.mul_x(R_X15, R_X15, r_hmul)
            @a.lsr_xi(R_X15, R_X15, 32)
            @a.and_x_lowmask(R_X15, R_X15, 31)
            if r_bptr == nil
              @a.ldr_x(R_X9, r_meta, 0)
              @a.ldr_x(R_X13, r_meta, 8)
            @a.ldr_x(R_X10, r_meta, 16)
            @a.and_r(R_X11, R_X15, mk_r)
            @a.movn_x(R_X4, 0)
            @a.bind(l_ploop)
            @a.ldrsw_idx(R_X16, bp_r, R_X11)
            @a.cbz_x(R_X16, l_pmiss)
            @a.cmp_i(R_X16, 0)
            @a.b_cond(CC_LT, l_pdel)
            @a.sub_i(R_X16, R_X16, 1)
            @a.ldr_x_idx(R_X17, R_X10, R_X16)
            @a.cmp_r(R_X17, R_X14)
            @a.b_cond(CC_EQ, l_phit)
            @a.bind(l_pstep)
            @a.add_i(R_X11, R_X11, 1)
            @a.and_r(R_X11, R_X11, mk_r)
            @a.b(l_ploop)
            @a.bind(l_pdel)
            @a.cmp_i(R_X4, 0)
            @a.csel_x(R_X4, R_X11, R_X4, CC_LT)
            @a.b(l_pstep)
            @a.bind(l_phit)
            @a.ldr_x(R_X10, r_meta, 24)
            @a.str_x_idx(R_X3, R_X10, R_X16)
            @a.b(l_cont)
            @a.bind(l_pmiss)
            @a.ldr_x(R_X16, r_meta, 40)
            @a.ldr_x(R_X17, r_meta, 64)
            @a.cmp_r(R_X16, R_X17)
            @a.b_cond(CC_GE, l_ms_rt)
            @a.ldr_x(R_X5, r_meta, 48)
            @a.add_i(R_X6, R_X5, 1)
            @a.lsl_xi(R_X7, R_X6, 2)
            @a.add_i(R_X17, mk_r, 1)
            @a.add_r(R_X17, R_X17, R_X17, 1)
            @a.cmp_r(R_X7, R_X17)
            @a.b_cond(CC_GT, l_ms_rt)
            @a.str_x_idx(R_X14, R_X10, R_X16)
            @a.ldr_x(R_X7, r_meta, 24)
            @a.str_x_idx(R_X3, R_X7, R_X16)
            @a.ldr_x(R_X7, r_meta, 32)
            @a.str_w_idx(R_X15, R_X7, R_X16)
            @a.cmp_i(R_X4, 0)
            @a.csel_x(R_X7, R_X4, R_X11, CC_GE)
            @a.csel_x(R_X5, R_X5, R_X6, CC_GE)
            @a.add_i(R_X16, R_X16, 1)
            @a.str_w_idx(R_X16, bp_r, R_X7)
            @a.str_x(R_X16, r_meta, 40)
            @a.str_x(R_X5, r_meta, 48)
            @a.ldr_x(R_X7, r_meta, 56)
            @a.add_i(R_X7, R_X7, 1)
            @a.str_x(R_X7, r_meta, 56)
            @a.bind(l_cont)
            @a.add_wi(ri, ri, 1)
            emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
            @a.bind(l_brk)
            cb_ms_rt = ->()
              @a.bind(l_ms_rt)
              load_slot_any(R_X1, mli)
              @a.mov_r(R_X2, R_X14)
              call_rt(RT_MAP_SET)
              @a.fmov_d_x(R_D17, R_X20) if @d_bias_reg == R_D17
              if r_bptr != nil
                @a.ldr_x(r_bptr, r_meta, 0)
                @a.ldr_x(r_mask, r_meta, 8)
              @a.b(l_cont)
            add_cold_stub(cb_ms_rt)
            cb_ms_slow = ->()
              @a.bind(l_ms_slow)
              l_uhead = @a.new_label
              @a.bind(l_uhead)
              emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
              gen_loop_body_stmt(s.d)
              @a.add_wi(ri, ri, 1)
              @a.b(l_uhead)
            add_cold_stub(cb_ms_slow)
            @free_gprs.push(r_mask) if r_mask != nil
            @free_gprs.push(r_bptr) if r_bptr != nil
            @free_gprs.push(r_hmul)
            @free_gprs.push(r_meta)
            if old_bound == nil
              @bounded_idx.delete(li)
            else
              @bounded_idx[li] = old_bound
            @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
            @known_shapes = saved_shapes
            return true
        # Case B: `s += m.get(key_e)` (zero calls in hot loop -> all 4 table pointers + hash mul pinned in X4..X8!)
        if fsum_st.a.kind == :assign && fsum_st.a.str == "+=" && fsum_st.a.a.kind == :ident && fsum_st.a.b.kind == :call && fsum_st.a.b.a.kind == :member && !fsum_st.a.b.a.has?(F_COMPUTED) && fsum_st.a.b.a.b.str == "get" && fsum_st.a.b.list.size == 1 && mp_hl.get_own("get") == r_hl.intrinsics["%Map_get%"]
          acc_li = local_idx(fsum_st.a.a)
          mli = local_idx(fsum_st.a.b.a.a)
          key_e = fsum_st.a.b.list[0]
          rk_mg = peek_i32_reg(key_e)
          if acc_li >= 0 && acc_li != li && mli >= 0 && mli != li && mli != acc_li && @info.types[mli] == JT_ANY && (@info.types[acc_li] == JT_ANY || @info.types[acc_li] == JT_F64) && rk_mg != nil
            map_sh = js_root_shape(mp_hl, SP_INLINE, SP_IBASE)
            jit_keep(map_sh)
            l_mg_slow = @a.new_label
            l_mg_bail = @a.new_label
            l_mg_ploop = @a.new_label
            l_mg_pstep = @a.new_label
            acc_any = @info.types[acc_li] == JT_ANY
            dr_mg = (!acc_any && @info.reg_fpr[acc_li] != nil) ? @info.reg_fpr[acc_li] : R_D2
            if !@hoisted_epoch
              ep_now = JS_EPOCH[0]
              @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
              @a.ldr_x(R_X10, R_X9, 0)
              @a.mov_imm64(R_X11, ep_now)
              @a.cmp_r(R_X10, R_X11)
              @a.b_cond(CC_NE, l_mg_slow)
            load_slot_any(R_X1, mli)
            @a.sub_i(R_X9, R_X1, 4)
            @a.tst_wobj_bad(R_X9)
            @a.b_cond(CC_NE, l_mg_slow)
            @a.ldr_x(R_X10, R_X9, 8)
            @a.mov_imm64(R_X11, wvalue_bits(map_sh) ## i64)
            @a.cmp_r(R_X10, R_X11)
            @a.b_cond(CC_NE, l_mg_slow)
            @a.ldr_x(R_X9, R_X9, 32)
            @a.sub_i(R_X9, R_X9, 4)
            @a.ldr_x(R_X12, R_X9, mp_off_hl)
            @a.and_x_lowmask(R_X12, R_X12, 48)
            @a.ldr_x(R_X5, R_X12, 8)        # X5 = mask
            @a.cbz_x(R_X5, l_mg_slow)
            if acc_any
              load_slot_any(R_X0, acc_li)
              emit_unbox_f64(dr_mg, R_X0, l_mg_slow)
            elsif @info.reg_fpr[acc_li] == nil
              load_slot_f64(dr_mg, acc_li)
            @a.ldr_x(R_X4, R_X12, 0)        # X4 = bptr
            @a.ldr_x(R_X6, R_X12, 16)       # X6 = kptr
            @a.ldr_x(R_X7, R_X12, 24)       # X7 = vptr
            @a.movz_x(R_X8, 0xE5B9, 0)      # X8 = 0xBF58476D1CE4E5B9
            @a.movk_x(R_X8, 0x1CE4, 1)
            @a.movk_x(R_X8, 0x476D, 2)
            @a.movk_x(R_X8, 0xBF58, 3)
            @a.bind(l_head)
            emit_box_i32(R_X14, rk_mg)
            @a.lsr_xi(R_X15, R_X14, 32)
            @a.eor_r(R_X15, R_X14, R_X15)
            @a.mul_x(R_X15, R_X15, R_X8)
            @a.lsr_xi(R_X15, R_X15, 32)
            @a.and_r(R_X11, R_X15, R_X5)
            @a.bind(l_mg_ploop)
            @a.ldrsw_idx(R_X16, R_X4, R_X11)
            @a.cbz_x(R_X16, l_mg_bail)
            @a.cmp_i(R_X16, 0)
            @a.b_cond(CC_LT, l_mg_pstep)
            @a.sub_i(R_X16, R_X16, 1)
            @a.ldr_x_idx(R_X17, R_X6, R_X16)
            @a.cmp_r(R_X17, R_X14)
            @a.b_cond(CC_NE, l_mg_pstep)
            @a.ldr_x_idx(R_X17, R_X7, R_X16)
            @a.sub_r(R_X15, R_X17, R_X20)
            @a.cmp_r(R_X15, R_X21)
            @a.b_cond(CC_HS, l_mg_bail)
            @a.fmov_d_x(R_D0, R_X15)
            @a.fadd_d(dr_mg, dr_mg, R_D0)
            @a.add_wi(ri, ri, 1)
            emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
            if acc_any
              emit_box_f64(R_X0, dr_mg)
              store_slot_any(acc_li, R_X0)
            elsif @info.reg_fpr[acc_li] == nil
              store_slot_f64(acc_li, dr_mg)
            @a.bind(l_brk)
            cb_mg_pstep = ->()
              @a.bind(l_mg_pstep)
              @a.add_i(R_X11, R_X11, 1)
              @a.and_r(R_X11, R_X11, R_X5)
              @a.b(l_mg_ploop)
              @a.bind(l_mg_bail)
              if acc_any
                emit_box_f64(R_X0, dr_mg)
                store_slot_any(acc_li, R_X0)
              elsif @info.reg_fpr[acc_li] == nil
                store_slot_f64(acc_li, dr_mg)
              @a.bind(l_mg_slow)
              l_uhead = @a.new_label
              @a.bind(l_uhead)
              emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
              gen_loop_body_stmt(s.d)
              @a.add_wi(ri, ri, 1)
              @a.b(l_uhead)
            add_cold_stub(cb_mg_pstep)
            if old_bound == nil
              @bounded_idx.delete(li)
            else
              @bounded_idx[li] = old_bound
            @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
            @known_shapes = saved_shapes
            return true

    # Hoist loop-invariant `str_local.indexOf("const")` calls ONCE before the loop!
    hoisted_io_regs = []
    if !@is_osr && @hoisted_epoch && @free_gprs.size > 0 && !stmt_has_cf_or_loop?(s.d)
      io_cands = []
      collect_inv_indexof(s.d, io_cands)
      ici = 0
      while ici < io_cands.size && @free_gprs.size > 0
        ic_item = io_cands[ici]
        if @inv_indexof[ic_item[0]] == nil
          gen_str_indexof_i32(ic_item[1], ic_item[2], ic_item[3])
          hr = @free_gprs.pop
          @a.mov_w(hr, R_X0)
          @inv_indexof[ic_item[0]] = hr
          hoisted_io_regs.push([ic_item[0], hr])
        ici += 1

    # Promote exact integer `s += <i64_exact_expr>` accumulator into a 64-bit GPR across the loop!
    i53_li = -1
    i53_gpr = nil
    l_i53_bail = nil
    l_i53_entry_slow = nil
    hoisted_cc_regs = []
    if @i53_acc_li < 0 && @promoted_owner < 0 && @free_gprs.size > 0 && !stmt_has_cf_or_loop?(s.d)
      cand_i53 = find_i53_acc_target(s.d, li)
      if cand_i53 >= 0
        i53_li = cand_i53
        i53_gpr = @free_gprs.pop
        l_i53_bail = @a.new_label
        l_i53_entry_slow = @a.new_label
        # Verify limit <= 2097151 (guarantees exact 53-bit sum for any int32 terms!)
        if lim_kind == 1
          @a.b(l_i53_entry_slow) if lim_val > 2097151
        elsif lim_kind == 2
          @a.mov_imm32(R_X9, 2097151)
          @a.cmp_w(lim_reg, R_X9)
          @a.b_cond(CC_GT, l_i53_entry_slow)
        elsif lim_kind == 3
          ar_i53 = @hoisted_arr_regs[lim_container]
          if ar_i53 != nil && ar_i53[1] != nil
            @a.mov_imm32(R_X9, 2097151)
            @a.cmp_w(ar_i53[1], R_X9)
            @a.b_cond(CC_GT, l_i53_entry_slow)
          else
            @a.ldr_x(R_X10, R_SP, @hoisted_arrs[lim_container][1])
            @a.mov_imm32(R_X9, 2097151)
            @a.cmp_w(R_X10, R_X9)
            @a.b_cond(CC_GT, l_i53_entry_slow)
        else
          @a.b(l_i53_entry_slow)
        # Verify initial value of `s` is an exact int32 -> move into i53_gpr
        dr_acc = @info.reg_fpr[i53_li]
        @a.fcvtzs_w_d(i53_gpr, dr_acc)
        @a.scvtf_d_w(R_D16, i53_gpr)
        @a.fcmp_d(dr_acc, R_D16)
        @a.b_cond(CC_NE, l_i53_entry_slow)
        @a.sxtw(i53_gpr, i53_gpr)
        @i53_acc_li = i53_li
        @i53_acc_reg = i53_gpr
        @i53_acc_bail = l_i53_bail
        # Hoist loop-invariant ASCII string `(ptr, [len])` ONCE before loop for `s.charCodeAt(...)`!
        # When idx is `expr & mask`, verifies `mask < len` ONCE before loop -> needs ONLY 1 GPR & ZERO per-iter BCE!
        if !@is_osr && @hoisted_epoch && @free_gprs.size >= 1
          cc_cands = []
          collect_inv_charcode(s.d, cc_cands)
          if cc_cands.size == 1 && @inv_str_ascii[cc_cands[0][0]] == nil
            csli = cc_cands[0][0]
            cc_node = cc_cands[0][1]
            idx_arg = cc_node.list[0]
            bmask = -1
            if idx_arg.kind == :binary && idx_arg.str == "&" && idx_arg.b.kind == :num && jit_int32_lit?(idx_arg.b) && idx_arg.b.a.to_i >= 0 && idx_arg.b.a.to_i <= 4095
              bmask = idx_arg.b.a.to_i
            if bmask >= 0 || @free_gprs.size >= 2
              ic = @str_cc_ics[cc_node]
              if ic == nil
                ic = i64[3]
                ic[0] = 0; ic[1] = 0; ic[2] = 0
                jit_keep(ic)
                @str_cc_ics[cc_node] = ic
              ic_p = jit_arr_slots_ptr(wvalue_bits(ic) ## i64)
              r_ptr = @free_gprs.pop
              r_len = bmask >= 0 ? nil : @free_gprs.pop
              l_cc_ready = @a.new_label
              load_slot_any(R_X13, csli)
              @a.mov_imm64(R_X9, ic_p)
              @a.ldr_x(R_X10, R_X9, 0)
              @a.cmp_r(R_X13, R_X10)
              @a.b_cond(CC_EQ, l_cc_ready)
              # Populate IC once on first call, then re-verify!
              @a.mov_r(R_X1, R_X13)
              @a.movz_x(R_X9, 0)
              emit_box_i32(R_X2, R_X9)
              @a.mov_imm64(R_X3, wvalue_bits(ic) ## i64)
              call_rt(RT_STR_CHARCODE_IC)
              @a.fmov_d_x(R_D17, R_X20) if @d_bias_reg == R_D17
              load_slot_any(R_X13, csli)
              @a.mov_imm64(R_X9, ic_p)
              @a.ldr_x(R_X10, R_X9, 0)
              @a.cmp_r(R_X13, R_X10)
              @a.b_cond(CC_NE, l_i53_entry_slow)
              @a.bind(l_cc_ready)
              @a.ldr_x(r_ptr, R_X9, 8)
              if bmask >= 0
                @a.ldr_x(R_X10, R_X9, 16)
                @a.cmp_i(R_X10, bmask)
                @a.b_cond(CC_LE, l_i53_entry_slow)   # verify len > mask ONCE -> zero bounds checks inside loop!
              else
                @a.ldr_x(r_len, R_X9, 16)
              @inv_str_ascii[csli] = [r_ptr, r_len, bmask]
              hoisted_cc_regs.push([csli, r_ptr, r_len])

    # Check eligibility for 4x / 2x loop unrolling (small simple innermost loop, no break/continue/return/nested loops)!
    body_cnt = !stmt_has_cf_or_loop?(s.d) ? stmt_size_count(s.d) : 999
    can_unroll4 = (lim_kind == 1 || lim_kind == 2) && body_cnt <= 34
    can_unroll2 = !can_unroll4 && body_cnt <= 36
    # When i53_li is active AND body cannot bail mid-4-iters, use 2 independent accumulator lanes (i53_gpr + R_X14)
    # and deferred `add ri, ri, #4` -> breaks BOTH `i` and `s` 1-cycle serial chains to sub-0.6 cycles/iter!
    can_2lane_4x = can_unroll4 && i53_li >= 0 && !stmt_can_i53_bail?(s.d)
    @loops.push(JS:JitLoopCtx.new(l_brk, l_cont, nil))
    @in_loop_depth += 1
    if can_2lane_4x
      l_epi4 = @a.new_label
      l_epi_lp = @a.new_label
      if lim_reg != nil
        @a.cmp_wi(lim_reg, 4)
        @a.b_cond(CC_LT, l_epi4)
        @a.sub_wi(R_X9, lim_reg, 3)
      else
        @a.b(l_epi4) if lim_val < 4
        @a.mov_imm32(R_X9, lim_val - 3)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_GE, l_epi4)
      ri0_off = push_x(ri)
      @a.movz_x(R_X14, 0)
      @a.bind(l_head)
      @unroll_i_li = li
      @i53_defer_const = [0]
      @i53_defer_regs = []
      @i53_cur_body = s.d
      @unroll_i_off = 0
      @i53_acc_reg = i53_gpr
      gen_loop_body_stmt(s.d)
      @unroll_i_off = 1
      @i53_acc_reg = R_X14
      gen_loop_body_stmt(s.d)
      @unroll_i_off = 2
      @i53_acc_reg = i53_gpr
      gen_loop_body_stmt(s.d)
      @unroll_i_off = 3
      @i53_acc_reg = R_X14
      gen_loop_body_stmt(s.d)
      dc = @i53_defer_const[0]
      dregs = @i53_defer_regs
      @i53_defer_const = nil
      @i53_defer_regs = nil
      @i53_cur_body = nil
      @unroll_i_li = -1
      @unroll_i_off = 0
      @i53_acc_reg = i53_gpr
      @a.add_wi(ri, ri, 4)
      if lim_reg != nil
        @a.sub_wi(R_X9, lim_reg, 3)
      else
        @a.mov_imm32(R_X9, lim_val - 3)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_LT, l_head)
      @a.add_r(i53_gpr, i53_gpr, R_X14)
      if dc != 0 || dregs.size > 0
        @a.ldr_x(R_X9, R_SP, ri0_off)
        @a.sub_w(R_X9, ri, R_X9)
        @a.lsr_wi(R_X9, R_X9, 2)
        if dc != 0
          @a.mov_imm64(R_X10, dc)
          @a.madd_x(i53_gpr, R_X9, R_X10, i53_gpr)
        dri = 0
        while dri < dregs.size
          @a.sxtw(R_X10, dregs[dri][0])
          @a.mov_imm64(R_X11, dregs[dri][1])
          @a.mul_x(R_X10, R_X10, R_X11)
          @a.madd_x(i53_gpr, R_X9, R_X10, i53_gpr)
          dri += 1
      @tmp_depth -= 1
      @a.bind(l_epi4)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
      @a.bind(l_epi_lp)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      @a.add_wi(ri, ri, 1)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_epi_lp)
    elsif can_unroll4
      # 4x unrolled loop: while (i + 3 < LIMIT) { 4 bodies }; epilogue `while (i < LIMIT)`!
      l_epi4 = @a.new_label
      l_epi_lp = @a.new_label
      if lim_reg != nil
        @a.cmp_wi(lim_reg, 4)
        @a.b_cond(CC_LT, l_epi4)
        @a.sub_wi(R_X9, lim_reg, 3)
      else
        @a.b(l_epi4) if lim_val < 4
        @a.mov_imm32(R_X9, lim_val - 3)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_GE, l_epi4)
      @a.bind(l_head)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      if lim_reg != nil
        @a.sub_wi(R_X9, lim_reg, 3)
      else
        @a.mov_imm32(R_X9, lim_val - 3)
      @a.cmp_w(ri, R_X9)
      @a.b_cond(CC_LT, l_head)
      @a.bind(l_epi4)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
      @a.bind(l_epi_lp)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      @a.add_wi(ri, ri, 1)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_epi_lp)
    elsif can_unroll2
      # 2x unrolled loop: while (i + 1 < LIMIT) { body(i); i++; body(i); i++; } ; if (i < LIMIT) { body(i); i++; }
      l_epilogue = @a.new_label
      emit_counted_cmp_p1_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_epilogue)
      @a.bind(l_head)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      gen_loop_body_stmt(s.d)
      @a.add_wi(ri, ri, 1)
      emit_counted_cmp_p1_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
      @a.bind(l_epilogue)
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_brk)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      @a.add_wi(ri, ri, 1)
    else
      @a.bind(l_head)
      gen_loop_body_stmt(s.d)
      @a.bind(l_cont)
      # Safe increment: since ri < LIMIT <= 2147483647, ri + 1 NEVER overflows i32 (ZERO b.vs!)
      @a.add_wi(ri, ri, 1)
      # Single back-edge branch: cmp + b.lt l_head!
      emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_head)
    @a.bind(l_brk)
    hoisted_cc_regs.each ->(tri)
      @inv_str_ascii.delete(tri[0])
      @free_gprs.push(tri[1])
      @free_gprs.push(tri[2]) if tri[2] != nil
    if i53_li >= 0
      @a.scvtf_d_x(@info.reg_fpr[i53_li], i53_gpr)
      l_i53_done = @a.new_label
      @a.bind(l_i53_done)
      @i53_acc_li = -1
      @i53_acc_reg = nil
      @i53_acc_bail = nil
      saved_tha = temp_hoist_arr
      saved_tha_gprs = temp_arr_gprs
      cb_i53 = ->()
        if saved_tha >= 0
          @hoisted_arrs[saved_tha] = [0, 0]
          @hoisted_arr_regs[saved_tha] = saved_tha_gprs
        @a.bind(l_i53_bail)
        @a.scvtf_d_x(@info.reg_fpr[i53_li], i53_gpr)
        @a.bind(l_i53_entry_slow)
        l_uhead = @a.new_label
        @a.bind(l_uhead)
        emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_GE, l_i53_done)
        gen_loop_body_stmt(s.d)
        @a.add_wi(ri, ri, 1)
        @a.b(l_uhead)
        if saved_tha >= 0
          @hoisted_arrs.delete(saved_tha)
          @hoisted_arr_regs.delete(saved_tha)
      add_cold_stub(cb_i53)
      @free_gprs.push(i53_gpr)
    hoisted_io_regs.each ->(pair)
      @inv_indexof.delete(pair[0])
      @free_gprs.push(pair[1])
    @in_loop_depth -= 1
    @loops.pop
    if bce_tas.size > 0
      lim_li = local_idx(eb)
      bce_tas.each ->(tli)
        @bounded_ta_set.delete(li.to_s + ":" + tli.to_s)
        @bounded_mod_ta.delete(lim_li.to_s + ":" + tli.to_s) if lim_li >= 0
      # Emit out-of-line un-BCE fallback loop when `n > ta.len`!
      cb = ->()
        @a.bind(l_unbce_loop)
        l_uhead = @a.new_label
        l_ucont = @a.new_label
        @loops.push(JS:JitLoopCtx.new(l_brk, l_ucont, nil))
        @a.bind(l_uhead)
        gen_loop_body_stmt(s.d)
        @a.bind(l_ucont)
        @a.add_wi(ri, ri, 1)
        emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, CC_LT, l_uhead)
        @loops.pop
        @a.b(l_brk)
      add_cold_stub(cb)
    if old_bound == nil
      @bounded_idx.delete(li)
    else
      @bounded_idx[li] = old_bound
    if temp_hoist_arr >= 0
      @a.bind(l_temp_arr_done)
      @hoisted_arrs.delete(temp_hoist_arr)
      @hoisted_arr_regs.delete(temp_hoist_arr)
      @free_gprs.push(temp_arr_gprs[0])
      @free_gprs.push(temp_arr_gprs[1])
      cb_ta = ->()
        @a.bind(l_temp_arr_slow)
        l_uhead = @a.new_label
        l_ucont = @a.new_label
        @loops.push(JS:JitLoopCtx.new(l_temp_arr_done, l_ucont, nil))
        @a.bind(l_uhead)
        gen_cond_branch(s.b, l_temp_arr_done, false)
        gen_loop_body_stmt(s.d)
        @a.bind(l_ucont)
        gen_expr_void(s.c)
        @a.b(l_uhead)
        @loops.pop
      add_cold_stub(cb_ta)
    @free_gprs.push(borrowed_gpr) if borrowed_gpr != nil
    @known_shapes = saved_shapes
    true

  -> find_sb_loop_target(body, loop_li)
    st = body
    if st.is_a?(JsNode) && st.kind == :block
      return nil if st.list == nil || st.list.size != 1
      st = st.list[0]
    return nil if !st.is_a?(JsNode) || st.kind != :expr_stmt
    ae = st.a
    return nil if !ae.is_a?(JsNode) || ae.kind != :assign || ae.str != "+=" || !ae.a.is_a?(JsNode) || ae.a.kind != :ident
    sli = local_idx(ae.a)
    return nil if sli < 0 || sli == loop_li || @info.types[sli] != JT_ANY
    rhs = ae.b
    return nil if !rhs.is_a?(JsNode)
    # Require rhs to produce a string (:template or :string) and never read `sli` or throw!
    if rhs.kind == :template && rhs.a.size == 1 && rhs.list.size == 2 && rhs.list[0].str.ascii? && rhs.list[1].str.ascii?
      e0 = rhs.a[0]
      return [sli, rhs] if (can_i32?(e0) || can_f64?(e0) || e0.kind == :string) && !node_refs_local?(e0, sli)
    if rhs.kind == :string && rhs.str.ascii?
      return [sli, rhs]
    nil

  -> node_refs_local?(n, target_li)
    return false if !n.is_a?(JsNode)
    return local_idx(n) == target_li if n.kind == :ident
    return true if node_refs_local?(n.a, target_li) || node_refs_local?(n.b, target_li) || node_refs_local?(n.c, target_li) || node_refs_local?(n.d, target_li)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if node_refs_local?(n.list[i], target_li)
        i += 1
    false

  -> collect_fp_consts(n, out)
    return nil if !n.is_a?(JsNode) || out.size >= 4
    if n.kind == :num && !jit_int32_lit?(n)
      bits = jit_f64_bits(wvalue_bits(n.a) ## i64)
      out.push(bits) if !out.include?(bits)
    collect_fp_consts(n.a, out)
    collect_fp_consts(n.b, out)
    collect_fp_consts(n.c, out)
    collect_fp_consts(n.d, out)
    if n.list.is_a?(Array)
      n.list.each ->(x) collect_fp_consts(x, out)
    nil

  -> collect_ta_bce_cands(n, idx_li, lim_li, out)
    return nil if !n.is_a?(JsNode)
    if n.kind == :member && n.has?(F_COMPUTED)
      tli = local_idx(n.a)
      if tli >= 0 && @hoisted_tas[tli] != nil
        if local_idx(n.b) == idx_li || (lim_li >= 0 && n.b.is_a?(JsNode) && n.b.kind == :binary && n.b.str == "%" && local_idx(n.b.b) == lim_li)
          out.push(tli) if !out.include?(tli)
    collect_ta_bce_cands(n.a, idx_li, lim_li, out)
    collect_ta_bce_cands(n.b, idx_li, lim_li, out)
    collect_ta_bce_cands(n.c, idx_li, lim_li, out)
    collect_ta_bce_cands(n.d, idx_li, lim_li, out)
    if n.list.is_a?(Array)
      n.list.each ->(x) collect_ta_bce_cands(x, idx_li, lim_li, out)
    nil

  -> find_promoted_outer_obj(body, loop_li)
    return nil if @known_shapes.size == 0
    all_wprops = {}
    reads_by_li = {}
    rw_by_li = {}
    bad_li = {}
    other_wlis = {}
    unknown_wprop = {}
    has_bad = [false]
    @known_shapes.keys.each ->(k)
      reads_by_li[k] = {}
      rw_by_li[k] = {}
    promo_scan_node(body, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
    return nil if has_bad[0]
    avail = (R_D31 - @next_prop_fp) + 1
    return nil if avail < 2
    best = nil
    best_cnt = 1
    @known_shapes.keys.each ->(ali)
      if !bad_li[ali] && ali != loop_li
        ro = []
        rw = []
        reads_by_li[ali].keys.each ->(pk)
          if !all_wprops[pk] && rw_by_li[ali][pk] == nil
            ro.push([pk, reads_by_li[ali][pk]])
        rw_by_li[ali].keys.each ->(pk)
          if !unknown_wprop[pk]
            rw.push([pk, rw_by_li[ali][pk]])
        tot = ro.size + rw.size
        if tot > best_cnt && tot <= avail
          # Check all other written locals for aliasing safety
          ow = {}
          other_wlis.keys.each ->(oli) ow[oli] = true if oli != ali
          best_cnt = tot
          best = [ali, ro, rw, ow]
    best

  -> promo_scan_node(n, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
    return nil if !n.is_a?(JsNode) || has_bad[0]
    k = n.kind
    if k == :assign
      if n.a.is_a?(JsNode) && n.a.kind == :member
        if n.a.has?(F_COMPUTED)
          has_bad[0] = true
          return nil
        pk = n.a.b.str
        all_wprops[pk] = true
        li = local_idx(n.a.a)
        if li >= 0 && @known_shapes[li] != nil
          op = n.str
          ic = n.a.x
          if (op == "+=" || op == "-=" || op == "*=" || op == "/=") && ic != nil && ic[0] == @known_shapes[li] && ic[2] == 0 && ic[1] != 0 && can_f64?(n.b)
            rw_by_li[li][pk] = ic[1]
          else
            bad_li[li] = true
        elsif li >= 0
          other_wlis[li] = true
        else
          unknown_wprop[pk] = true
        promo_scan_node(n.b, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
        return nil
      elsif n.a.is_a?(JsNode) && n.a.kind == :ident
        li = local_idx(n.a)
        bad_li[li] = true if li >= 0
    elsif k == :update
      if n.a.is_a?(JsNode) && n.a.kind == :member
        has_bad[0] = true
        return nil
      elsif n.a.is_a?(JsNode) && n.a.kind == :ident
        li = local_idx(n.a)
        bad_li[li] = true if li >= 0
    elsif k == :var_decl && n.list.is_a?(Array)
      n.list.each ->(d)
        if d.is_a?(JsNode)
          li = local_idx(d.a)
          bad_li[li] = true if li >= 0
          promo_scan_node(d.b, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
      return nil
    elsif k == :member && !n.has?(F_COMPUTED)
      li = local_idx(n.a)
      if li >= 0 && @known_shapes[li] != nil
        ic = n.x
        if ic != nil && ic[0] == @known_shapes[li] && ic[2] == 0 && ic[1] != 0
          reads_by_li[li][n.b.str] = ic[1]
        else
          bad_li[li] = true
      return nil
    promo_scan_node(n.a, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
    promo_scan_node(n.b, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
    promo_scan_node(n.c, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
    promo_scan_node(n.d, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
    if n.list.is_a?(Array)
      n.list.each ->(x) promo_scan_node(x, all_wprops, reads_by_li, rw_by_li, bad_li, other_wlis, unknown_wprop, has_bad)
    nil

  -> stmt_has_cf_or_loop?(n)
    return false if !n.is_a?(JsNode)
    k = n.kind
    return true if k == :break || k == :continue || k == :return || k == :throw || k == :for || k == :while || k == :do_while || k == :switch || k == :try
    return true if stmt_has_cf_or_loop?(n.a) || stmt_has_cf_or_loop?(n.b) || stmt_has_cf_or_loop?(n.c) || stmt_has_cf_or_loop?(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        return true if stmt_has_cf_or_loop?(n.list[i])
        i += 1
    false

  -> stmt_size_count(n)
    return 0 if !n.is_a?(JsNode)
    c = 1 + stmt_size_count(n.a) + stmt_size_count(n.b) + stmt_size_count(n.c) + stmt_size_count(n.d)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        c += stmt_size_count(n.list[i])
        i += 1
    c

  # Compare (ri + 1) against LIMIT for 2x unrolled loop guard!
  -> emit_counted_cmp_p1_branch(ri, lim_kind, lim_val, lim_reg, lim_container, cc, target)
    if lim_kind == 1
      lm1 = lim_val - 1
      if lm1 <= 0
        @a.b(target) if cc == CC_GE
        return nil
      if lm1 <= 4095
        @a.cmp_wi(ri, lm1)
      else
        @a.mov_imm32(R_X9, lm1)
        @a.cmp_w(ri, R_X9)
    elsif lim_kind == 2
      @a.sub_wi(R_X9, lim_reg, 1)
      @a.cmp_w(ri, R_X9)
    elsif lim_kind == 3
      ar = @hoisted_arr_regs[lim_container]
      if ar != nil && ar[1] != nil
        @a.sub_wi(R_X9, ar[1], 1)
      else
        @a.ldr_x(R_X9, R_SP, @hoisted_arrs[lim_container][1])
        @a.sub_wi(R_X9, R_X9, 1)
      @a.cmp_w(ri, R_X9)
    else
      tr = @hoisted_ta_regs[lim_container]
      if tr != nil && tr[1] != nil
        @a.sub_wi(R_X9, tr[1], 1)
      else
        @a.ldr_x(R_X9, R_SP, @hoisted_tas[lim_container][1])
        @a.sub_wi(R_X9, R_X9, 1)
      @a.cmp_w(ri, R_X9)
    @a.b_cond(cc, target)
    nil

  -> emit_counted_cmp_branch(ri, lim_kind, lim_val, lim_reg, lim_container, cc, target)
    if lim_kind == 1
      if lim_reg != nil
        @a.cmp_w(ri, lim_reg)
      elsif lim_val <= 4095
        @a.cmp_wi(ri, lim_val)
      else
        @a.mov_imm32(R_X9, lim_val)
        @a.cmp_w(ri, R_X9)
    elsif lim_kind == 2
      @a.cmp_w(ri, lim_reg)
    elsif lim_kind == 3
      ar = @hoisted_arr_regs[lim_container]
      if ar != nil && ar[1] != nil
        @a.cmp_w(ri, ar[1])
      else
        @a.ldr_x(R_X9, R_SP, @hoisted_arrs[lim_container][1])
        @a.cmp_w(ri, R_X9)
    else
      tr = @hoisted_ta_regs[lim_container]
      if tr != nil && tr[1] != nil
        @a.cmp_w(ri, tr[1])
      else
        @a.ldr_x(R_X9, R_SP, @hoisted_tas[lim_container][1])
        @a.cmp_w(ri, R_X9)
    @a.b_cond(cc, target)
    nil

  # Loop-body Monomorphic Shape Versioning (100% sound dual-path fast/slow specialization!):
  # When a loop body `:block` reads/writes >= 2 warm monomorphic own-property ICs on local(s)
  # (e.g. `a` and `b` in n-body `step`, or `c` in position update), verify each local's shape
  # ONCE right after leading non-property var declarations, then execute the rest of the block
  # with `@known_shapes` populated (eliminating ~20 repeated tag+shape checks per iteration!).
  # If any guard misses, executes the exact same statements with `@known_shapes = {}`.
  -> gen_loop_body_stmt(body)
    if body == nil || body.kind != :block || body.list == nil || body.list.size == 0
      gen_stmt(body)
      return nil
    list = body.list
    # Count warm monomorphic own-property accesses per local in `list`
    counts = {}   # lidx -> [shape_bits, count, ok]
    collect_warm_shape_uses(list, counts)
    # Keep locals with >= 2 warm own-property accesses sharing one exact shape AND no shape-changing writes
    cands = {}
    counts.keys.each ->(li)
      e = counts[li]
      if e[2] && e[1] >= 2 && e[0] != 0
        cands[li] = e[0]
    if cands.size == 0
      gen_stmt(body)
      return nil
    # Split leading simple `var x = expr` initializers (that don't themselves depend on guarded properties)
    # from the body tail so `var b = bodies[j], dx = a.x - b.x` splits cleanly!
    # Handle `var b = bodies[j], dx = a.x - b.x` inside a single var_decl too!
    first_stmt = list[0]
    lead_stmts = 0
    lead_decls = 0
    if first_stmt.kind == :var_decl && first_stmt.list.size >= 1
      # Advance through leading declarators whose RHS has no member reads on `cands`
      q = 0
      while q < first_stmt.list.size
        d = first_stmt.list[q]
        break if expr_uses_cand_prop?(d.b, cands)
        q += 1
      lead_decls = q
      if lead_decls == first_stmt.list.size
        lead_stmts = 1
        lead_decls = 0
    # Emit leading declarations once (unconditionally)
    i = 0
    while i < lead_stmts
      gen_stmt(list[i])
      i += 1
    if lead_decls > 0
      q = 0
      while q < lead_decls
        d = first_stmt.list[q]
        b = d.a.x.binding
        if d.b != nil
          emit_assign_to_binding(b, d.b, first_stmt.str != "var")
        elsif first_stmt.str != "var"
          @a.movz_x(R_X0, 0)
          emit_write_binding(b, R_X0, true)
        q += 1
    # Check each candidate's shape ONCE; on any mismatch jump to l_slow_blk!
    l_slow_blk = @a.new_label
    l_done_blk = @a.new_label
    guard_lis = cands.keys
    # Do not guard a local that is reassigned later in the tail!
    reassigned = {}
    collect_tail_reassigned(list, lead_stmts, lead_decls, reassigned)
    active = []
    guard_lis.each ->(li) active.push(li) if !reassigned[li] && @info.types[li] == JT_ANY
    if active.size == 0
      # Emit remaining decls & stmts normally
      emit_block_tail(list, lead_stmts, lead_decls)
      return nil
    old_shapes = @known_shapes.dup
    use_promo_bail = @promoted_owner >= 0 && @promoted_bail_lbl != nil
    l_guard_fail = use_promo_bail ? @promoted_bail_lbl : l_slow_blk
    active.each ->(li)
      sh = cands[li]
      if old_shapes[li] != sh
        load_slot_any(R_X13, li)
        @a.sub_i(R_X9, R_X13, 4)
        @a.tst_wobj_bad(R_X9)
        @a.b_cond(CC_NE, l_guard_fail)
        @a.cbz_x(R_X9, l_guard_fail)
        @a.ldr_x(R_X10, R_X9, 8)
        hr = @hoisted_shapes[sh]
        if hr != nil
          @a.cmp_r(R_X10, hr)
        elsif @sh_spill_slots[sh] != nil
          @a.ldr_x(R_X11, R_SP, @sh_spill_slots[sh])
          @a.cmp_r(R_X10, R_X11)
        else
          @a.mov_imm64(R_X11, sh)
          @a.cmp_r(R_X10, R_X11)
        @a.b_cond(CC_NE, l_guard_fail)
      # Aliasing guard when outer object's writable fields are scalar-promoted!
      if use_promo_bail && li != @promoted_owner && @promoted_other_lis != nil && @promoted_other_lis[li]
        r_a = @info.reg_gpr[@promoted_owner]
        r_b = @info.reg_gpr[li]
        if r_a != nil && r_b != nil
          @a.cmp_r(r_b, r_a)
        else
          load_slot_any(R_X13, li)
          load_slot_any(R_X14, @promoted_owner)
          @a.cmp_r(R_X13, R_X14)
        @a.b_cond(CC_EQ, @promoted_bail_lbl)
      @known_shapes[li] = sh
    # Fast specialized tail (ZERO shape checks on active locals, plus read-only property FP CSE!)
    old_pfp = @block_prop_fp
    old_wprops = @block_written_props
    old_pcounts = @block_prop_counts
    old_npfp = @next_prop_fp
    wprops = {}
    pcounts = {}
    collect_tail_written_props(list, lead_stmts, lead_decls, wprops)
    collect_tail_prop_reads(list, lead_stmts, lead_decls, pcounts)
    @block_prop_fp = old_pfp.dup
    @block_written_props = wprops
    @block_prop_counts = pcounts
    # Keep outer loop's cached properties live if not written in this inner block (or if promoted rw!)
    wprops.keys.each ->(wk)
      @block_prop_fp.keys.each ->(pk)
        @block_prop_fp.delete(pk) if pk.ends_with?(":" + wk) && @promoted_rw[pk] == nil
    emit_block_tail(list, lead_stmts, lead_decls)
    @block_prop_fp = old_pfp
    @block_written_props = old_wprops
    @block_prop_counts = old_pcounts
    @next_prop_fp = old_npfp
    @a.bind(l_done_blk)
    @known_shapes = old_shapes
    # Emit slow fallback tail OUT OF LINE in @cold_stubs (0 taken branches + 0 cold bytes in hot loop!)
    if !use_promo_bail
      cb = ->()
        @a.bind(l_slow_blk)
        sv_sh = @known_shapes
        sv_pfp = @block_prop_fp
        sv_wp = @block_written_props
        sv_pc = @block_prop_counts
        sv_np = @next_prop_fp
        @known_shapes = {}
        @block_prop_fp = {}
        @block_written_props = nil
        @block_prop_counts = nil
        @next_prop_fp = R_D18
        emit_block_tail(list, lead_stmts, lead_decls)
        @known_shapes = sv_sh
        @block_prop_fp = sv_pfp
        @block_written_props = sv_wp
        @block_prop_counts = sv_pc
        @next_prop_fp = sv_np
        @a.b(l_done_blk)
      add_cold_stub(cb)
    nil

  -> collect_tail_prop_reads(list, lead_stmts, lead_decls, out)
    if lead_decls > 0
      fs = list[0]
      q = lead_decls
      while q < fs.list.size
        collect_stmt_preads(fs.list[q].b, out)
        q += 1
      i = 1
    else
      i = lead_stmts
    while i < list.size
      collect_stmt_preads(list[i], out)
      i += 1
    nil

  -> collect_stmt_preads(n, out)
    return nil if !n.is_a?(JsNode)
    if n.kind == :member && !n.has?(F_COMPUTED)
      li = local_idx(n.a)
      if li >= 0
        pk = li.to_s + ":" + n.b.str
        out[pk] = (out[pk] == nil ? 0 : out[pk]) + 1
    collect_stmt_preads(n.a, out)
    collect_stmt_preads(n.b, out)
    collect_stmt_preads(n.c, out)
    collect_stmt_preads(n.d, out)
    if n.list.is_a?(Array)
      n.list.each ->(x) collect_stmt_preads(x, out)
    nil

  -> collect_tail_written_props(list, lead_stmts, lead_decls, out)
    i = lead_decls > 0 ? 1 : lead_stmts
    while i < list.size
      collect_stmt_wprops(list[i], out)
      i += 1
    nil

  -> collect_stmt_wprops(n, out)
    return nil if !n.is_a?(JsNode)
    if n.kind == :assign && n.a.is_a?(JsNode) && n.a.kind == :member && !n.a.has?(F_COMPUTED)
      out[n.a.b.str] = true
    elsif n.kind == :update && n.a.is_a?(JsNode) && n.a.kind == :member && !n.a.has?(F_COMPUTED)
      out[n.a.b.str] = true
    collect_stmt_wprops(n.a, out)
    collect_stmt_wprops(n.b, out)
    collect_stmt_wprops(n.c, out)
    collect_stmt_wprops(n.d, out)
    if n.list.is_a?(Array)
      n.list.each ->(x) collect_stmt_wprops(x, out)
    nil

  -> emit_block_tail(list, lead_stmts, lead_decls)
    if lead_decls > 0
      fs = list[0]
      q = lead_decls
      while q < fs.list.size
        d = fs.list[q]
        b = d.a.x.binding
        if d.b != nil
          emit_assign_to_binding(b, d.b, fs.str != "var")
        elsif fs.str != "var"
          @a.movz_x(R_X0, 0)
          emit_write_binding(b, R_X0, true)
        q += 1
      i = 1
    else
      i = lead_stmts
    while i < list.size
      gen_stmt(list[i])
      i += 1
    nil

  -> expr_uses_cand_prop?(e, cands)
    return false if !e.is_a?(JsNode)
    k = e.kind
    if k == :member && !e.has?(F_COMPUTED)
      li = local_idx(e.a)
      return true if li >= 0 && cands[li] != nil
    return true if expr_uses_cand_prop?(e.a, cands) || expr_uses_cand_prop?(e.b, cands) || expr_uses_cand_prop?(e.c, cands)
    if e.list.is_a?(Array)
      i = 0
      while i < e.list.size
        return true if expr_uses_cand_prop?(e.list[i], cands)
        i += 1
    false

  -> collect_tail_reassigned(list, lead_stmts, lead_decls, out)
    # Also mark locals reassigned inside nested blocks/statements (except the leading declarators)
    if lead_decls > 0
      fs = list[0]
      q = lead_decls
      while q < fs.list.size
        li = local_idx(fs.list[q].a)
        out[li] = true if li >= 0
        collect_expr_reassigned(fs.list[q].b, out)
        q += 1
      i = 1
    else
      i = lead_stmts
    while i < list.size
      collect_stmt_reassigned(list[i], out)
      i += 1
    nil

  -> collect_stmt_reassigned(s, out)
    return nil if s == nil
    k = s.kind
    if k == :var_decl
      s.list.each ->(d)
        li = local_idx(d.a)
        out[li] = true if li >= 0
        collect_expr_reassigned(d.b, out)
    elsif k == :expr_stmt || k == :return || k == :throw
      collect_expr_reassigned(s.a, out)
    elsif k == :block
      s.list.each ->(x) collect_stmt_reassigned(x, out)
    elsif k == :if
      collect_expr_reassigned(s.a, out)
      collect_stmt_reassigned(s.b, out)
      collect_stmt_reassigned(s.c, out)
    elsif k == :for
      collect_stmt_reassigned(s.a, out) if s.a != nil && s.a.kind == :var_decl
      collect_expr_reassigned(s.a, out) if s.a != nil && s.a.kind != :var_decl
      collect_expr_reassigned(s.b, out)
      collect_expr_reassigned(s.c, out)
      collect_stmt_reassigned(s.d, out)
    elsif k == :while || k == :do_while
      collect_expr_reassigned(s.a, out)
      collect_stmt_reassigned(s.b, out)
    nil

  -> collect_expr_reassigned(e, out)
    return nil if !e.is_a?(JsNode)
    k = e.kind
    if k == :assign && e.a.kind == :ident
      li = local_idx(e.a)
      out[li] = true if li >= 0
    elsif k == :update && e.a.kind == :ident
      li = local_idx(e.a)
      out[li] = true if li >= 0
    elsif k == :call
      # Any non-Math call inside the tail could mutate arbitrary objects' shapes!
      if !(e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a.kind == :ident && e.a.a.str == "Math")
        # Conservative: invalidate all locals on general calls inside the body
        i = 0
        while i < @jf.nlocals
          out[i] = true
          i += 1
        return nil
    collect_expr_reassigned(e.a, out)
    collect_expr_reassigned(e.b, out)
    collect_expr_reassigned(e.c, out)
    if e.list.is_a?(Array)
      e.list.each ->(x) collect_expr_reassigned(x, out)
    nil

  -> collect_warm_shape_uses(list, counts)
    i = 0
    while i < list.size
      collect_stmt_shapes(list[i], counts)
      i += 1
    nil

  -> collect_stmt_shapes(s, counts)
    return nil if s == nil
    k = s.kind
    if k == :var_decl
      s.list.each ->(d) collect_expr_shapes(d.b, counts)
    elsif k == :expr_stmt || k == :return || k == :throw
      collect_expr_shapes(s.a, counts)
    elsif k == :block
      s.list.each ->(x) collect_stmt_shapes(x, counts)
    elsif k == :if
      collect_expr_shapes(s.a, counts)
      collect_stmt_shapes(s.b, counts)
      collect_stmt_shapes(s.c, counts)
    elsif k == :for
      # Descend into inner loops so outer-loop locals (like `a` in n-body) get guarded ONCE in the outer loop!
      collect_stmt_shapes(s.d, counts)
    nil

  -> collect_expr_shapes(e, counts)
    return nil if !e.is_a?(JsNode)
    k = e.kind
    if k == :member && !e.has?(F_COMPUTED)
      li = local_idx(e.a)
      if li >= 0 && @info.types[li] == JT_ANY && e.x != nil
        ic = e.x
        sh = ic[0]
        sl = ic[1]
        h  = ic[2]
        if sh != 0 && h == 0 && sl != 0
          cur = counts[li]
          if cur == nil
            counts[li] = [sh, 1, true]
          elsif cur[0] == sh
            cur[1] = cur[1] + 1
          else
            cur[2] = false
    if k == :assign && e.a.kind == :member && !e.a.has?(F_COMPUTED)
      li = local_idx(e.a.a)
      if li >= 0 && e.a.x != nil
        ic = e.a.x
        # If property write transitions shape (ic[2] != 0), disqualify!
        if ic[2] != 0
          counts[li] = [0, 0, false]
    collect_expr_shapes(e.a, counts)
    collect_expr_shapes(e.b, counts)
    collect_expr_shapes(e.c, counts)
    if e.list.is_a?(Array)
      e.list.each ->(x) collect_expr_shapes(x, counts)
    nil

  -> gen_while_loop(s)
    @known_shapes = {}
    l_head = @a.new_label
    l_brk = @a.new_label
    @loops.push(JS:JitLoopCtx.new(l_brk, l_head, nil))
    @in_loop_depth += 1
    @a.bind(l_head)
    gen_cond_branch(s.a, l_brk, false)
    gen_stmt(s.b)
    @a.b(l_head)
    @a.bind(l_brk)
    @in_loop_depth -= 1
    @loops.pop
    @known_shapes = {}
    nil

  -> gen_do_while_loop(s)
    @known_shapes = {}
    l_head = @a.new_label
    l_cont = @a.new_label
    l_brk = @a.new_label
    @loops.push(JS:JitLoopCtx.new(l_brk, l_cont, nil))
    @in_loop_depth += 1
    @a.bind(l_head)
    gen_stmt(s.a)
    @a.bind(l_cont)
    gen_cond_branch(s.b, l_head, true)
    @a.bind(l_brk)
    @in_loop_depth -= 1
    @loops.pop
    @known_shapes = {}
    nil

  # ---- Binding Helpers ----

  -> local_idx(e)
    return -1 if e == nil || e.kind != :ident || e.x == nil
    b = e.x.binding
    return -1 if b == nil || b.global? || b.slot >= 0 || b.scope.func != @jf
    b.lidx

  -> emit_assign_to_binding(b, rhs, init)
    if !b.global? && b.slot < 0 && b.scope.func == @jf
      li = b.lidx
      ty = @info.types[li]
      if ty == JT_SRA_OBJ
        # Scalar-replaced object literal: store each property expression directly into its vslot!
        sra = @info.sra_objs[li]
        i = 0
        while i < rhs.list.size
          p = rhs.list[i]
          vs = sra.field_slots[p.a.str]
          emit_store_expr_to_slot(vs, p.b)
          i += 1
        return nil
      if ty == JT_SRA_CLOS
        # Scalar-replaced closure from factory: store factory args into captured vslots!
        sc = @info.sra_clos[li]
        cell = wk_cell(sc.factory_binding)
        cb = wvalue_bits(cell) ## i64
        if @hoisted_cells[cb] != (wvalue_bits(sc.factory_fn) ## i64)
          jit_keep(cell)
          jit_keep(sc.factory_fn)
          @a.mov_imm64(R_X9, cb - 4)
          @a.ldr_x(R_X10, R_X9, 8)
          @a.mov_imm64(R_X11, wvalue_bits(sc.factory_fn) ## i64)
          @a.cmp_r(R_X10, R_X11)
          @a.b_cond(CC_NE, @l_deopt)
        i = 0
        while i < sc.cap_slots.size
          emit_store_expr_to_slot(sc.cap_slots[i], rhs.list[i])
          i += 1
        return nil
      if ty == JT_SRA_RX
        if rhs == nil || rhs.kind == :null
          caps_p = jit_arr_slots_ptr(wvalue_bits(@info.sra_rxs[li]) ## i64)
          @a.mov_imm64(R_X9, caps_p)
          @a.movn_x(R_X10, 0)
          @a.str_x(R_X10, R_X9, 248)
        else
          gen_sra_rx_exec(li, rhs)
        return nil
      emit_store_expr_to_slot(li, rhs)
      return nil
    gen_expr_any(rhs)
    emit_write_binding(b, R_X0, init)
    nil

  -> emit_store_expr_to_slot(slot, rhs)
    ty = @info.types[slot]
    if ty == JT_I32
      r = @info.reg_gpr[slot]
      if r != nil && rhs != nil
        # Direct-to-register targeting for `i`, `i + K`, `i & mask` (zero redundant movs!)
        pr = peek_i32_reg(rhs)
        if pr != nil
          @a.mov_w(r, pr) if r != pr
          return nil
        if rhs.kind == :binary && (rhs.str == "+" || rhs.str == "-") && jit_small_int_lit?(rhs.b, 4095) && rhs.b.a.to_i >= 0
          ra = peek_i32_reg(rhs.a)
          if ra != nil
            if rhs.str == "+"
              @a.adds_wi(r, ra, rhs.b.a.to_i)
            else
              @a.subs_wi(r, ra, rhs.b.a.to_i)
            @a.b_cond(CC_VS, @l_deopt)
            return nil
        if rhs.kind == :binary && rhs.str == "&" && rhs.b.kind == :num && jit_int32_lit?(rhs.b)
          m = rhs.b.a.to_i
          if m == 1 || m == 3 || m == 7 || m == 15 || m == 31 || m == 63 || m == 127 || m == 255 || m == 511 || m == 1023 || m == 2047 || m == 4095 || m == 65535
            nb = 0
            t = m
            while t > 0
              nb += 1
              t = t >> 1
            ra = peek_i32_reg(rhs.a)
            if ra != nil
              @a.and_w_lowmask(r, ra, nb)
              return nil
            if @unroll_i_li >= 0 && @unroll_i_off > 0 && local_idx(rhs.a) == @unroll_i_li && @info.reg_gpr[@unroll_i_li] != nil
              @a.add_wi(r, @info.reg_gpr[@unroll_i_li], @unroll_i_off)
              @a.and_w_lowmask(r, r, nb)
              return nil
        # Reassociate `sum = ((((sum + e1) + e2) + e3)) | 0`: compute `e1 + e2 + e3` FIRST
        # so the loop-carried dependency on `sum` is a SINGLE 1-cycle `ADD r, r, w0`!
        if rhs.kind == :binary && rhs.str == "|" && rhs.b.kind == :num && rhs.b.a == ~0.0
          inner = rhs.a
          terms = []
          found_self = false
          cur = inner
          while cur != nil && cur.kind == :binary && cur.str == "+" && exact_i32_sum_term?(cur.a) && exact_i32_sum_term?(cur.b)
            terms.push(cur.b)
            cur = cur.a
          if cur != nil && local_idx(cur) == slot && terms.size >= 1
            # Evaluate sum of `terms` in reverse order into R_X0, then ONE `add_w(r, r, R_X0)`!
            ti = terms.size - 1
            gen_expr_to_i32(terms[ti])
            ti -= 1
            while ti >= 0
              t_e = terms[ti]
              if t_e.kind == :binary && t_e.str == "*" && jit_small_int_lit?(t_e.b, 1048576) && peek_i32_reg(t_e.a) != nil
                rx = peek_i32_reg(t_e.a)
                kv = t_e.b.a.to_i
                if kv == 2
                  @a.add_w(R_X0, R_X0, rx, 1)
                elsif kv == 3
                  @a.add_w(R_X10, rx, rx, 1)
                  @a.add_w(R_X0, R_X0, R_X10)
                elsif kv == 4
                  @a.add_w(R_X0, R_X0, rx, 2)
                elsif kv == 5
                  @a.add_w(R_X10, rx, rx, 2)
                  @a.add_w(R_X0, R_X0, R_X10)
                elsif kv == 8
                  @a.add_w(R_X0, R_X0, rx, 3)
                else
                  @a.mov_imm32(R_X10, kv)
                  @a.madd_w(R_X0, rx, R_X10, R_X0)
              elsif peek_i32_reg(t_e) != nil
                @a.add_w(R_X0, R_X0, peek_i32_reg(t_e))
              else
                push_w(R_X0)
                gen_expr_to_i32(t_e)
                pop_w(R_X9)
                @a.add_w(R_X0, R_X9, R_X0)
              ti -= 1
            @a.add_w(r, r, R_X0)
            return nil
      gen_expr_i32(rhs)
      store_slot_i32(slot, R_X0)
      return nil
    if ty == JT_F64
      dr = @info.reg_fpr[slot]
      if dr != nil && rhs != nil && rhs.kind == :binary && (rhs.str == "+" || rhs.str == "-" || rhs.str == "*" || rhs.str == "/")
        da = peek_f64_reg(rhs.a)
        db = peek_f64_reg(rhs.b)
        if da != nil && db != nil
          emit_f64_op(rhs.str, dr, da, db)
          return nil
        if db != nil
          gen_expr_f64(rhs.a)
          emit_f64_op(rhs.str, dr, R_D0, db)
          return nil
        if da != nil
          gen_expr_f64(rhs.b)
          emit_f64_op(rhs.str, dr, da, R_D0)
          return nil
      gen_expr_f64(rhs)
      store_slot_f64(slot, R_D0)
      return nil
    gen_expr_any(rhs)
    store_slot_any(slot, R_X0)
    # If slot is a local TypedArray (`var buf = new Uint8Array(...)`), populate hoisted (raw_ptr, len) immediately!
    if !@is_osr && @info.local_tas[slot] != nil && @hoisted_tas[slot] != nil
      h_ta = @hoisted_tas[slot]
      ta_out = i64[4]
      jit_keep(ta_out)
      @a.mov_r(R_X1, R_X0)
      @a.mov_imm64(R_X2, wvalue_bits(ta_out) ## i64)
      call_rt(RT_TA_INFO)
      @a.mov_imm64(R_X9, jit_i64_ptr(ta_out))
      @a.ldr_x(R_X10, R_X9, 0)
      @a.str_x(R_X10, R_SP, h_ta[0])
      tr_ta = @hoisted_ta_regs[slot]
      @a.mov_r(tr_ta[0], R_X10) if tr_ta != nil && tr_ta[0] != nil
      @a.ldr_x(R_X10, R_X9, 8)
      @a.str_x(R_X10, R_SP, h_ta[1])
      @a.mov_r(tr_ta[1], R_X10) if tr_ta != nil && tr_ta[1] != nil
    # If rhs is a bounds-verified load from a homogeneous-shape read-only Array (`bodies[i]`),
    # record its exact proven shape immediately (ZERO shape checks inside nested loops!)
    if rhs.is_a?(JsNode) && rhs.kind == :member && rhs.has?(F_COMPUTED) && @mono_arr_shape.size > 0
      ali = local_idx(rhs.a)
      idx_li = local_idx(rhs.b)
      if ali >= 0 && @mono_arr_shape[ali] != nil && idx_li >= 0 && @bounded_idx[idx_li] == ali
        @known_shapes[slot] = @mono_arr_shape[ali]
    nil

  -> emit_write_binding(b, val_reg, init, ref = nil)
    if b.global?
      c = wk_cell(b)
      jit_keep(c)
      cb = wvalue_bits(c) ## i64
      if b.kind == :lexical
        @a.mov_r(R_X2, val_reg)
        @a.mov_imm64(R_X1, cb)
        if init
          @a.movz_x(R_X3, b.decl_const ? 2 : 1)
          call_rt(RT_LINIT)
        else
          call_rt(RT_LSET)
        return nil
      # Fast path: plain writable global cell (cell.@fast != 3)
      @a.mov_imm64(R_X9, cb - 4)
      @a.ldr_x(R_X10, R_X9, 8)
      @a.cmp_i(R_X10, 3)
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.b_cond(CC_EQ, l_slow)
      @a.str_x(val_reg, R_X9, 8)
      @a.b(l_done)
      @a.bind(l_slow)
      @a.mov_r(R_X2, val_reg)
      @a.mov_imm64(R_X1, cb)
      @a.movz_x(R_X3, @jf.strict ? 2 : 1)
      call_rt(RT_GSET)
      @a.bind(l_done)
      return nil
    if b.slot >= 0
      # Write to JS:Env slot (walking hops if in outer env!)
      @a.mov_r(R_X3, val_reg)
      @a.ldr_x(R_X1, R_SP, JF_SLOT_ENV)
      h = ref != nil ? wk_hops(ref) : @jf.analysis.env_hops(@jf.scope, b.scope)
      while h > 0
        @a.sub_i(R_X1, R_X1, 4)
        @a.ldr_x(R_X1, R_X1, 8)
        h -= 1
      @a.mov_imm64(R_X2, wvalue_bits(b.slot) ## i64)
      call_rt(RT_ENV_SET)
      return nil
    store_slot_any(b.lidx, val_reg)
    nil

  # ---- Condition Branching (zero materialization of true/false!) ----

  -> gen_cond_branch(e, target, branch_if_true)
    k = e.kind
    if k == :true
      @a.b(target) if branch_if_true
      return nil
    if k == :false || k == :null
      @a.b(target) if !branch_if_true
      return nil
    if k == :unary && e.str == "!"
      gen_cond_branch(e.a, target, !branch_if_true)
      return nil
    if k == :logical && e.str == "&&"
      if branch_if_true
        l_skip = @a.new_label
        gen_cond_branch(e.a, l_skip, false)
        gen_cond_branch(e.b, target, true)
        @a.bind(l_skip)
      else
        gen_cond_branch(e.a, target, false)
        gen_cond_branch(e.b, target, false)
      return nil
    if k == :logical && e.str == "||"
      if branch_if_true
        gen_cond_branch(e.a, target, true)
        gen_cond_branch(e.b, target, true)
      else
        l_skip = @a.new_label
        gen_cond_branch(e.a, l_skip, true)
        gen_cond_branch(e.b, target, false)
        @a.bind(l_skip)
      return nil
    if k == :binary
      op = e.str
      if op == "<" || op == "<=" || op == ">" || op == ">=" || op == "===" || op == "!=="
        # Fast SRA RegExp exec condition: `(m = re.exec(text)) !== null` / `m !== null`!
        if (op == "!==" || op == "===") && e.b.kind == :null
          want_match = (op == "!==") == branch_if_true
          if e.a.kind == :assign && e.a.str == "=" && local_idx(e.a.a) >= 0 && @info.types[local_idx(e.a.a)] == JT_SRA_RX
            gen_sra_rx_exec(local_idx(e.a.a), e.a.b)
            @a.cmp_wi(R_X0, 0)
            @a.b_cond(want_match ? CC_GE : CC_LT, target)
            return nil
          if local_idx(e.a) >= 0 && @info.types[local_idx(e.a)] == JT_SRA_RX
            caps_p = jit_arr_slots_ptr(wvalue_bits(@info.sra_rxs[local_idx(e.a)]) ## i64)
            @a.mov_imm64(R_X9, caps_p)
            @a.ldr_x(R_X0, R_X9, 248)
            @a.cmp_wi(R_X0, 0)
            @a.b_cond(want_match ? CC_GE : CC_LT, target)
            return nil
        # Fast i32 comparison (zero stack spills for literals & registers!)
        if can_i32?(e.a) && can_i32?(e.b)
          ra = peek_i32_reg(e.a)
          rb = peek_i32_reg(e.b)
          if e.b.kind == :num && jit_small_int_lit?(e.b, 4095) && e.b.a.to_i >= 0
            if ra != nil
              @a.cmp_wi(ra, e.b.a.to_i)
            else
              gen_expr_i32(e.a)
              @a.cmp_wi(R_X0, e.b.a.to_i)
          elsif e.b.kind == :num && jit_int32_lit?(e.b)
            if ra != nil
              @a.mov_imm32(R_X9, e.b.a.to_i)
              @a.cmp_w(ra, R_X9)
            else
              gen_expr_i32(e.a)
              @a.mov_imm32(R_X9, e.b.a.to_i)
              @a.cmp_w(R_X0, R_X9)
          elsif rb != nil
            if ra != nil
              @a.cmp_w(ra, rb)
            else
              gen_expr_i32(e.a)
              @a.cmp_w(R_X0, rb)
          else
            gen_expr_i32(e.a)
            push_w(R_X0)
            gen_expr_i32(e.b)
            pop_w(R_X9)
            @a.cmp_w(R_X9, R_X0)
          cc = i32_cmp_cc(op, branch_if_true)
          @a.b_cond(cc, target)
          return nil
        # Fast `(x % K) === 0` / `(x % K) !== 0` (e.g. `filter(x => x % 3 === 0)` — ZERO RT_MOD calls!)
        if (op == "===" || op == "!==") && e.a.kind == :binary && e.a.str == "%" && e.a.b.kind == :num && jit_int32_lit?(e.a.b) && e.a.b.a.to_i > 0 && e.b.kind == :num && e.b.a == ~0.0
          kv = e.a.b.a.to_i
          eq_zero = (op == "===") == branch_if_true
          gen_expr_any(e.a.a)
          l_slow = @a.new_label
          l_done = @a.new_label
          # Fast exact non-negative i32 check
          @a.sub_r(R_X15, R_X0, R_X20)
          @a.cmp_r(R_X15, R_X21)
          @a.b_cond(CC_HS, l_slow)
          @a.fmov_d_x(R_D16, R_X15)
          @a.fcvtzs_w_d(R_X9, R_D16)
          @a.cmp_wi(R_X9, 0)
          @a.b_cond(CC_LT, l_slow)
          @a.scvtf_d_w(R_D17, R_X9)
          @a.fcmp_d(R_D16, R_D17)
          @a.b_cond(CC_NE, l_slow)
          emit_mod_const_u31(R_X11, R_X9, kv)
          if eq_zero
            @a.cbz_w(R_X11, target)
          else
            @a.cbnz_w(R_X11, target)
          @a.bind(l_done)
          rhs_val = e.a.b.a
          cb = ->()
            @a.bind(l_slow)
            @a.mov_r(R_X1, R_X0)
            @a.mov_imm64(R_X2, wvalue_bits(rhs_val) ## i64)
            call_rt(RT_MOD)
            @a.mov_imm64(R_X2, wvalue_bits(~0.0) ## i64)
            @a.mov_r(R_X1, R_X0)
            call_rt(RT_SEQ)
            @a.cmp_i(R_X0, 2)
            @a.b_cond(eq_zero ? CC_EQ : CC_NE, target)
            @a.b(l_done)
          add_cold_stub(cb)
          return nil
        # Fast f64 comparison!
        if can_f64?(e.a) && can_f64?(e.b)
          gen_expr_f64(e.a)
          push_d(R_D0)
          gen_expr_f64(e.b)
          pop_d(R_D1)
          @a.fcmp_d(R_D1, R_D0)
          emit_f64_cmp_branch(op, branch_if_true, target)
          return nil
        # Fast `v !== undefined` / `v === undefined` (super common in map_set!)
        if (op == "===" || op == "!==") && is_undef_node?(e.b)
          gen_expr_any(e.a)
          eq_true = (op == "===") == branch_if_true
          if eq_true
            @a.cbz_x(R_X0, target)
          else
            @a.cbnz_x(R_X0, target)
          return nil
        # Fast `i < arr.length` where i is i32 and arr is a hoisted dense array or TypedArray!
        if op == "<" && can_i32?(e.a) && e.b.kind == :member && !e.b.has?(F_COMPUTED) && e.b.b.str == "length"
          bli = local_idx(e.b.a)
          if bli >= 0 && @hoisted_arrs[bli] != nil
            gen_expr_i32(e.a)
            @a.ldr_x(R_X9, R_SP, @hoisted_arrs[bli][1])
            @a.cmp_w(R_X0, R_X9)
            @a.b_cond(branch_if_true ? CC_LT : CC_GE, target)
            return nil
          if bli >= 0 && @hoisted_tas[bli] != nil
            gen_expr_i32(e.a)
            @a.ldr_x(R_X9, R_SP, @hoisted_tas[bli][1])
            @a.cmp_w(R_X0, R_X9)
            @a.b_cond(branch_if_true ? CC_LT : CC_GE, target)
            return nil
          # Also non-hoisted array.length (e.g. bodies.length inside step(bodies, dt)!)
          if bli >= 0 && @info.types[bli] == JT_ANY
            gen_expr_i32(e.a)
            @a.mov_w(R_X12, R_X0)
            load_slot_any(R_X9, bli)
            @a.lsr_xi(R_X10, R_X9, 48)
            @a.movz_x(R_X11, 0xFFF4)
            @a.cmp_r(R_X10, R_X11)
            l_slow_len = @a.new_label
            l_cmp_done = @a.new_label
            @a.b_cond(CC_NE, l_slow_len)
            @a.and_x_ptr47(R_X9, R_X9)
            @a.ldrb(R_X10, R_X9, 2)
            @a.tst_x_lowmask(R_X10, 1)
            @a.b_cond(CC_EQ, l_slow_len)
            @a.cmp_wi(R_X10, 8)
            @a.b_cond(CC_HS, l_slow_len)
            @a.ldrsw(R_X10, R_X9, 8)   # arr.size
            @a.cmp_w(R_X12, R_X10)
            @a.b_cond(branch_if_true ? CC_LT : CC_GE, target)
            @a.b(l_cmp_done)
            @a.bind(l_slow_len)
            # Slow path: box i, read .length, call RT_LT
            emit_box_i32(R_X0, R_X12)
            push_x(R_X0)
            gen_expr_any(e.b)
            @a.mov_r(R_X2, R_X0)
            pop_x(R_X1)
            call_rt(RT_LT)
            @a.cmp_i(R_X0, 2)
            @a.b_cond(branch_if_true ? CC_EQ : CC_NE, target)
            @a.bind(l_cmp_done)
            return nil
      # Generic binary comparison fallback (NEVER recurse back into gen_expr_any(e)!)
      if op == "<" || op == "<=" || op == ">" || op == ">=" || op == "===" || op == "!==" || op == "==" || op == "!="
        gen_expr_any(e.a)
        push_x(R_X0)
        gen_expr_any(e.b)
        @a.mov_r(R_X2, R_X0)
        pop_x(R_X1)
        if op == "<" || op == "<=" || op == ">" || op == ">="
          l_slow = @a.new_label
          l_done = @a.new_label
          @a.sub_r(R_X9, R_X1, R_X20)
          @a.cmp_r(R_X9, R_X21)
          @a.b_cond(CC_HS, l_slow)
          @a.sub_r(R_X10, R_X2, R_X20)
          @a.cmp_r(R_X10, R_X21)
          @a.b_cond(CC_HS, l_slow)
          @a.fmov_d_x(R_D0, R_X9)
          @a.fmov_d_x(R_D1, R_X10)
          @a.fcmp_d(R_D0, R_D1)
          emit_f64_cmp_branch(op, branch_if_true, target)
          @a.b(l_done)
          @a.bind(l_slow)
          rt = op == "<" ? RT_LT : (op == "<=" ? RT_LE : (op == ">" ? RT_GT : RT_GE))
          call_rt(rt)
          @a.cmp_i(R_X0, 2)
          @a.b_cond(branch_if_true ? CC_EQ : CC_NE, target)
          @a.bind(l_done)
          return nil
        if op == "===" || op == "!=="
          call_rt(RT_SEQ)
          eq_t = (op == "===") == branch_if_true
          @a.cmp_i(R_X0, 2)
          @a.b_cond(eq_t ? CC_EQ : CC_NE, target)
          return nil
        # == / !=
        call_rt(RT_EQ)
        eq_t = (op == "==") == branch_if_true
        @a.cmp_i(R_X0, 2)
        @a.b_cond(eq_t ? CC_EQ : CC_NE, target)
        return nil
    # General truthiness branch
    gen_expr_any(e)
    emit_truthy_branch(R_X0, target, branch_if_true)
    nil

  -> is_undef_node?(e)
    return false if e == nil || e.kind != :ident || e.str != "undefined"
    b = e.x == nil ? nil : e.x.binding
    b != nil && b.global? && b.writes == 0

  -> i32_cmp_cc(op, br_true)
    if br_true
      return CC_LT if op == "<"
      return CC_LE if op == "<="
      return CC_GT if op == ">"
      return CC_GE if op == ">="
      return CC_EQ if op == "==="
      return CC_NE
    return CC_GE if op == "<"
    return CC_GT if op == "<="
    return CC_LE if op == ">"
    return CC_LT if op == ">="
    return CC_NE if op == "==="
    CC_EQ

  # ARM64 FP flags after FCMP:
  #   <  : MI (true), PL (false — includes NaN!)
  #   <= : LS (true), HI (false — includes NaN!)
  #   >  : GT (true), LE (false — includes NaN!)
  #   >= : GE (true), LT (false — includes NaN!)
  #   ===: EQ (true), NE (false — includes NaN!)
  #   !==: NE (true — includes NaN!), EQ (false)
  -> emit_f64_cmp_branch(op, br_true, target)
    cc = CC_EQ
    if br_true
      cc = CC_MI if op == "<"
      cc = CC_LS if op == "<="
      cc = CC_GT if op == ">"
      cc = CC_GE if op == ">="
      cc = CC_EQ if op == "==="
      cc = CC_NE if op == "!=="
    else
      cc = CC_PL if op == "<"
      cc = CC_HI if op == "<="
      cc = CC_LE if op == ">"
      cc = CC_LT if op == ">="
      cc = CC_NE if op == "==="
      cc = CC_EQ if op == "!=="
    @a.b_cond(cc, target)
    nil

  -> emit_truthy_branch(reg, target, br_true)
    # Fast check: true (2) -> truthy; false (1) or nil (0) -> falsy; else call RT_TRUTHY
    l_slow = @a.new_label
    l_done = @a.new_label
    @a.cmp_i(reg, 2)
    @a.b_cond(CC_HI, l_slow)
    # reg is 0 (nil), 1 (false), or 2 (true)
    @a.b_cond(br_true ? CC_EQ : CC_NE, target)
    @a.b(l_done)
    @a.bind(l_slow)
    @a.mov_r(R_X1, reg)
    call_rt(RT_TRUTHY)
    @a.cmp_i(R_X0, 2)
    @a.b_cond(br_true ? CC_EQ : CC_NE, target)
    @a.bind(l_done)
    nil

  # ---- Type Query Helpers for Codegen ----

  -> can_i32?(e)
    return false if e == nil
    k = e.kind
    return jit_int32_lit?(e) if k == :num
    if k == :ident
      if @inline_env != nil && e.x != nil && @inline_env[e.x.binding] != nil
        iv = @inline_env[e.x.binding]
        return iv[0] == :reg_w || iv[0] == :spill_w || (iv[0] == :slot && @info.types[iv[1]] == JT_I32)
      li = local_idx(e)
      return li >= 0 && @info.types[li] == JT_I32
    if k == :binary
      op = e.str
      return true if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>"
      return true if op == "%" && can_i32?(e.a) && e.b.kind == :num && jit_int32_lit?(e.b) && e.b.a.to_i > 0
      return true if op == "+" && e.b.kind == :num && e.b.a == ~1.0 && @no_ovf_p1_li >= 0 && local_idx(e.a) == @no_ovf_p1_li
      return false
    if k == :unary
      return e.str == "~"
    if k == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        return vs != nil && @info.types[vs] == JT_I32
      if bli >= 0 && @info.sra_rxs[bli] != nil && e.b.str == "index"
        return true
      if e.b.str == "length" && e.a.kind == :member && e.a.has?(F_COMPUTED) && local_idx(e.a.a) >= 0 && @info.sra_rxs[local_idx(e.a.a)] != nil && jit_int32_lit?(e.a.b) && e.a.b.a.to_i >= 0 && e.a.b.a.to_i < 15
        return true
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      return bli >= 0 && @hoisted_tas[bli] != nil && @hoisted_tas[bli][2] <= 5   # i8/u8/u8c/i16/u16/i32 TA!
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.b.str == "indexOf" && e.list.size == 1 && !@is_osr
      sli = local_idx(e.a.a)
      return true if sli >= 0 && @info.str_locals[sli]
    false

  -> can_f64?(e)
    return true if can_i32?(e)
    return false if e == nil
    k = e.kind
    return true if k == :num
    if k == :ident
      if @inline_env != nil && e.x != nil && @inline_env[e.x.binding] != nil
        iv = @inline_env[e.x.binding]
        return iv[0] == :reg_d || (iv[0] == :slot && @info.types[iv[1]] == JT_F64)
      li = local_idx(e)
      return li >= 0 && @info.types[li] == JT_F64
    if k == :binary
      op = e.str
      return true if op == "-" || op == "*" || op == "/"
      return can_i32?(e.a) && can_i32?(e.b) if op == "%"
      return can_f64?(e.a) && can_f64?(e.b) if op == "+"
      return false
    if k == :unary
      return e.str == "-" || e.str == "+"
    if k == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        return vs != nil && @info.types[vs] == JT_F64
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      return bli >= 0 && @hoisted_tas[bli] != nil && @hoisted_tas[bli][2] <= 8
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a.kind == :ident && e.a.a.str == "Math"
      mn = e.a.b.str
      return e.list.size == 1 && (mn == "sqrt" || mn == "abs" || mn == "floor" || mn == "ceil" || mn == "trunc")
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.b.str == "charCodeAt" && e.list.size == 1 && !@is_osr
      sli = local_idx(e.a.a)
      return true if sli >= 0 && @info.str_locals[sli]
    if k == :call && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0 && @info.sra_clos[li] != nil
        sc = @info.sra_clos[li]
        re = jit_inline_return_expr(sc.inner_jf)
        return true if re != nil && e.list.size == sc.inner_jf.params.size
    false

  # ---- Void Expression (e.g. i++, h = ..., a.x += ...) ----

  -> gen_expr_void(e)
    return nil if e == nil
    k = e.kind
    if k == :update && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0 && @info.types[li] == JT_I32
        r = @info.reg_gpr[li]
        inc = e.str == "++"
        if r != nil
          if inc
            @a.adds_wi(r, r, 1)
          else
            @a.subs_wi(r, r, 1)
          @a.b_cond(CC_VS, @l_deopt)
        else
          load_slot_i32(R_X0, li)
          if inc
            @a.adds_wi(R_X0, R_X0, 1)
          else
            @a.subs_wi(R_X0, R_X0, 1)
          @a.b_cond(CC_VS, @l_deopt)
          store_slot_i32(li, R_X0)
        return nil
    if k == :assign && e.a.kind == :ident && e.str == "="
      emit_assign_to_binding(e.a.x.binding, e.b, false)
      return nil
    if k == :assign && e.a.kind == :ident && (e.str == "+=" || e.str == "-=" || e.str == "*=" || e.str == "/=")
      li = local_idx(e.a)
      # Fast loop-promoted 64-bit integer accumulator (`s += <i53_expr>` -> 1-cycle ADD X!)
      if li >= 0 && li == @i53_acc_li && @i53_acc_reg != nil && (e.str == "+=" || e.str == "-=")
        # Zero-extra-mov fast path for `s += reg + const` / `s += o.a + o.b + o.c + o.d`!
        if e.str == "+=" && e.b.kind == :binary && e.b.str == "+"
          terms = []
          csum = [0]
          collect_i64_add_terms(e.b, terms, csum)
          if terms.size == 1 && can_i32?(terms[0]) && peek_i32_reg(terms[0]) != nil
            @a.sxtw(R_X9, peek_i32_reg(terms[0]))
            if csum[0] == 0
              @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X9)
            elsif @i53_defer_const != nil
              @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X9)
              @i53_defer_const[0] = @i53_defer_const[0] + csum[0]
            elsif csum[0] > 0 && csum[0] <= 4095
              @a.add_i(R_X9, R_X9, csum[0])
              @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X9)
            elsif csum[0] < 0 && csum[0] >= -4095
              @a.sub_i(R_X9, R_X9, 0 - csum[0])
              @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X9)
            else
              @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X9)
              @a.mov_imm64(R_X9, csum[0])
              @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X9)
            return nil
        # Zero-extra-mov fast path for 1-arg additive SRA closure (`s += add(i & 255)` -> 3 insns!)
        if e.str == "+=" && e.b.kind == :call && e.b.a.kind == :ident && e.b.list.size == 1
          cli = local_idx(e.b.a)
          if cli >= 0 && @info.sra_clos[cli] != nil
            sc = @info.sra_clos[cli]
            re = jit_inline_return_expr(sc.inner_jf)
            if re != nil && re.kind == :binary && re.str == "+" && sc.inner_jf.params.size == 1 && sc.cap_slots.size == 1 && @info.types[sc.cap_slots[0]] == JT_I32
              r_cap = @info.reg_gpr[sc.cap_slots[0]]
              p0 = sc.inner_jf.params[0]
              f0 = sc.inner_jf.free.values.size == 1 ? sc.inner_jf.free.values[0] : nil
              is_p_plus_f = r_cap != nil && f0 != nil && re.a.kind == :ident && re.b.kind == :ident && ((re.a.x.binding == p0 && re.b.x.binding == f0) || (re.b.x.binding == p0 && re.a.x.binding == f0))
              if is_p_plus_f && can_i32?(e.b.list[0])
                ae = e.b.list[0]
                if ae.kind == :binary && ae.str == "&" && ae.b.kind == :num && jit_int32_lit?(ae.b) && ae.b.a.to_i >= 0 && ae.b.a.to_i <= 65535 && ((ae.b.a.to_i + 1) & ae.b.a.to_i) == 0 && (peek_i32_reg(ae.a) != nil || (@unroll_i_li >= 0 && local_idx(ae.a) == @unroll_i_li && @info.reg_gpr[@unroll_i_li] != nil))
                  nb = 0; t = ae.b.a.to_i
                  while t > 0
                    nb += 1; t = t >> 1
                  ra = peek_i32_reg(ae.a)
                  if ra != nil
                    @a.and_w_lowmask(R_X0, ra, nb)
                  else
                    @a.add_wi(R_X0, @info.reg_gpr[@unroll_i_li], @unroll_i_off)
                    @a.and_w_lowmask(R_X0, R_X0, nb)
                  # Zero-extended u16 in R_X0 -> direct 64-bit add without sxtw!
                  if @i53_defer_regs != nil && @i53_cur_body != nil && !stmt_writes_local?(@i53_cur_body, sc.cap_slots[0])
                    @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X0)
                    found_dr = false
                    dri = 0
                    while dri < @i53_defer_regs.size
                      if @i53_defer_regs[dri][0] == r_cap
                        @i53_defer_regs[dri][1] = @i53_defer_regs[dri][1] + 1
                        found_dr = true
                        break
                      dri += 1
                    @i53_defer_regs.push([r_cap, 1]) if !found_dr
                  else
                    @a.sxtw(R_X9, r_cap)
                    @a.add_r(R_X0, R_X0, R_X9)
                    @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X0)
                  return nil
        gen_expr_i64_exact(e.b)
        if e.str == "+="
          @a.add_r(@i53_acc_reg, @i53_acc_reg, R_X0)
        else
          @a.sub_r(@i53_acc_reg, @i53_acc_reg, R_X0)
        return nil
      if li >= 0 && @info.types[li] == JT_F64
        # Fused `s += x * y` -> zero-spill FMUL + FADD directly into D_s!
        if e.str == "+=" && e.b.kind == :binary && e.b.str == "*" && can_f64?(e.b.a) && can_f64?(e.b.b)
          dr = @info.reg_fpr[li]
          if @info.reg_fpr.size < 8 && @d_bias_reg != R_D15 && dr != nil && !expr_uses_d15?(e.b.b)
            # R_D15 is an unused callee-saved FP register (survives any slow call!)
            gen_expr_f64(e.b.a)
            @a.fmov_d(R_D15, R_D0)
            gen_expr_f64(e.b.b)
            @a.fmul_d(R_D0, R_D15, R_D0)
            @a.fadd_d(dr, dr, R_D0)
            return nil
          gen_expr_f64(e.b.a)
          push_d(R_D0)
          gen_expr_f64(e.b.b)
          pop_d(R_D1)
          if dr != nil
            @a.fmul_d(R_D0, R_D1, R_D0)
            @a.fadd_d(dr, dr, R_D0)
          else
            load_slot_f64(R_D2, li)
            @a.fmul_d(R_D0, R_D1, R_D0)
            @a.fadd_d(R_D0, R_D2, R_D0)
            store_slot_f64(li, R_D0)
          return nil
        gen_expr_f64(e.b)
        dr_acc = @info.reg_fpr[li]
        if dr_acc != nil
          if e.str == "+="
            @a.fadd_d(dr_acc, dr_acc, R_D0)
          elsif e.str == "-="
            @a.fsub_d(dr_acc, dr_acc, R_D0)
          elsif e.str == "*="
            @a.fmul_d(dr_acc, dr_acc, R_D0)
          else
            @a.fdiv_d(dr_acc, dr_acc, R_D0)
          return nil
        load_slot_f64(R_D1, li)
        if e.str == "+="
          @a.fadd_d(R_D0, R_D1, R_D0)
        elsif e.str == "-="
          @a.fsub_d(R_D0, R_D1, R_D0)
        elsif e.str == "*="
          @a.fmul_d(R_D0, R_D1, R_D0)
        else
          @a.fdiv_d(R_D0, R_D1, R_D0)
        store_slot_f64(li, R_D0)
        return nil
    if k == :assign && e.a.kind == :member && !e.a.has?(F_COMPUTED)
      op = e.str
      # Void scalar-replaced object field write (`o.a = (i & 7)` -> ZERO boxing!)
      if op == "="
        bli_s = local_idx(e.a.a)
        if bli_s >= 0 && @info.sra_objs[bli_s] != nil
          vs = @info.sra_objs[bli_s].field_slots[e.a.b.str]
          if vs != nil
            emit_store_expr_to_slot(vs, e.b)
            return nil
      if (op == "+=" || op == "-=" || op == "*=" || op == "/=")
        if @promoted_rw.size > 0
          bli = local_idx(e.a.a)
          dr = bli >= 0 ? @promoted_rw[bli.to_s + ":" + e.a.b.str] : nil
          if dr != nil && can_f64?(e.b)
            gen_expr_f64(e.b)
            if op == "+="
              @a.fadd_d(dr, dr, R_D0)
            elsif op == "-="
              @a.fsub_d(dr, dr, R_D0)
            elsif op == "*="
              @a.fmul_d(dr, dr, R_D0)
            else
              @a.fdiv_d(dr, dr, R_D0)
            return nil
        gen_member_set_named(e.a, op, e.b, false)
        return nil
    # Void hoisted TypedArray store (`buf[j] = 1` -> ZERO boxing!)
    if k == :assign && e.str == "=" && e.a.kind == :member && e.a.has?(F_COMPUTED)
      bli_t = local_idx(e.a.a)
      if bli_t >= 0 && @hoisted_tas[bli_t] != nil
        gen_ta_store(bli_t, e.a.b, e.b, false)
        return nil
    # Void `arr.push(x)` (skips boxing returned length!)
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.b.str == "push" && e.list.size == 1
      gen_array_push_inline(e.a.a, e.list[0], false)
      return nil
    if k == :seq
      i = 0
      while i < e.list.size
        gen_expr_void(e.list[i])
        i += 1
      return nil
    gen_expr_any(e)
    nil

  # Exact unsigned remainder `dst_w = src_x % kv` for `0 <= src_x < 2^31` and positive constant `kv >= 1`!
  # Uses power-of-2 bitmask or Hacker's Delight 64-bit magic multiply (ZERO udiv/sdiv for kv <= 32767!).
  -> emit_mod_const_u31(dst_w, src_x, kv)
    if kv <= 1
      @a.mov_imm32(dst_w, 0)
      return nil
    if (kv & (kv - 1)) == 0
      nb = 0
      t = kv
      while t > 1
        nb += 1
        t = t >> 1
      @a.and_w_lowmask(dst_w, src_x, nb)
      return nil
    if kv >= 3 && kv <= 32767
      s = 0
      t = kv
      while t > 1
        s += 1
        t = t >> 1
      sh = 32 + s
      magic = ((1 << sh) / kv) + 1
      @a.mov_imm64(R_X10, magic)
      @a.mul_x(R_X11, src_x, R_X10)
      @a.lsr_xi(R_X11, R_X11, sh)
      @a.mov_imm32(R_X10, kv)
      @a.msub_w(dst_w, R_X11, R_X10, src_x)
      return nil
    @a.mov_imm32(R_X10, kv)
    @a.udiv_w(R_X11, src_x, R_X10)
    @a.msub_w(dst_w, R_X11, R_X10, src_x)
    nil

  # ---- Lane 1: Unboxed int32 Expression Codegen -> result in w0 ----

  # If `e` is a register-resident i32 leaf (or simple spill/imm), return the register holding it
  # (loading into `scratch` if needed), without touching the temp stack! Else nil.
  -> try_i32_reg(e, scratch)
    return nil if e == nil
    k = e.kind
    if k == :num && jit_int32_lit?(e)
      @a.mov_imm32(scratch, e.a.to_i)
      return scratch
    if k == :ident
      if @inline_env != nil && e.x != nil && @inline_env[e.x.binding] != nil
        iv = @inline_env[e.x.binding]
        return iv[1] if iv[0] == :reg_w
        if iv[0] == :slot && @info.types[iv[1]] == JT_I32
          r = @info.reg_gpr[iv[1]]
          return r if r != nil
          @a.ldr_w(scratch, R_SP, @info.spill_off[iv[1]])
          return scratch
        if iv[0] == :spill_w
          @a.ldr_w(scratch, R_SP, iv[1])
          return scratch
      li = local_idx(e)
      if li >= 0 && @info.types[li] == JT_I32
        r = @info.reg_gpr[li]
        return r if r != nil
        @a.ldr_w(scratch, R_SP, @info.spill_off[li])
        return scratch
    if k == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        if vs != nil && @info.types[vs] == JT_I32
          r = @info.reg_gpr[vs]
          return r if r != nil
          @a.ldr_w(scratch, R_SP, @info.spill_off[vs])
          return scratch
    nil

  # Does `e` live directly in a callee-saved GPR without emitting any instructions?
  -> peek_i32_reg(e)
    return nil if e == nil
    if e.kind == :ident
      if @inline_env != nil && e.x != nil && @inline_env[e.x.binding] != nil
        iv = @inline_env[e.x.binding]
        return iv[1] if iv[0] == :reg_w
        return @info.reg_gpr[iv[1]] if iv[0] == :slot && @info.types[iv[1]] == JT_I32
        return nil
      li = local_idx(e)
      return nil if li == @unroll_i_li && @unroll_i_off > 0
      return @info.reg_gpr[li] if li >= 0 && @info.types[li] == JT_I32
    if e.kind == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        return @info.reg_gpr[vs] if vs != nil && @info.types[vs] == JT_I32
    nil

  # Evaluate `e` whose result is guaranteed to be truncated via ToInt32 (`expr | 0`)!
  # Because sums of int32s and products with |K| <= 2^20 never exceed 2^53 in IEEE double,
  # 32-bit wrapping arithmetic is 100% bit-for-bit identical to IEEE double + ToInt32!
  -> gen_expr_to_i32(e)
    k = e.kind
    if k == :num && jit_int32_lit?(e)
      @a.mov_imm32(R_X0, e.a.to_i)
      return nil
    if k == :binary
      op = e.str
      # Fused `a + (x * K)` -> shifted ADD (K=2,4,8), 2-op shift-add (K=3,5,9 -> 1-cycle!), or MADD!
      if op == "+" && exact_i32_sum_term?(e.a) && e.b.kind == :binary && e.b.str == "*" && jit_small_int_lit?(e.b.b, 1048576) && peek_i32_reg(e.b.a) != nil
        gen_expr_to_i32(e.a)
        rx = peek_i32_reg(e.b.a)
        kv = e.b.b.a.to_i
        if kv == 2
          @a.add_w(R_X0, R_X0, rx, 1)
        elsif kv == 3
          @a.add_w(R_X10, rx, rx, 1)
          @a.add_w(R_X0, R_X0, R_X10)
        elsif kv == 4
          @a.add_w(R_X0, R_X0, rx, 2)
        elsif kv == 5
          @a.add_w(R_X10, rx, rx, 2)
          @a.add_w(R_X0, R_X0, R_X10)
        elsif kv == 8
          @a.add_w(R_X0, R_X0, rx, 3)
        elsif kv == 9
          @a.add_w(R_X10, rx, rx, 3)
          @a.add_w(R_X0, R_X0, R_X10)
        else
          @a.mov_imm32(R_X10, kv)
          @a.madd_w(R_X0, rx, R_X10, R_X0)
        return nil
      # Fused `(x * K) + b` -> MADD W0, Wx, WK, Wb!
      if op == "+" && e.a.kind == :binary && e.a.str == "*" && can_i32?(e.a.a) && jit_small_int_lit?(e.a.b, 1048576) && can_i32?(e.b)
        rx = peek_i32_reg(e.a.a)
        if rx != nil
          gen_expr_i32(e.b)
          @a.mov_imm32(R_X10, e.a.b.a.to_i)
          @a.madd_w(R_X0, rx, R_X10, R_X0)
          return nil
        gen_expr_i32(e.a.a)
        push_w(R_X0)
        gen_expr_i32(e.b)
        pop_w(R_X9)
        @a.mov_imm32(R_X10, e.a.b.a.to_i)
        @a.madd_w(R_X0, R_X9, R_X10, R_X0)
        return nil
      # Exact int32 `+` / `-` inside `| 0` with zero-spill register targeting!
      if (op == "+" || op == "-") && exact_i32_sum_term?(e.a)
        rb = peek_i32_reg(e.b)
        if rb != nil
          gen_expr_to_i32(e.a)
          if op == "+"
            @a.add_w(R_X0, R_X0, rb)
          else
            @a.sub_w(R_X0, R_X0, rb)
          return nil
        ra = peek_i32_reg(e.a)
        if ra != nil && (exact_i32_sum_term?(e.b) || e.b.kind == :call)
          gen_expr_to_i32(e.b)
          if op == "+"
            @a.add_w(R_X0, ra, R_X0)
          else
            @a.sub_w(R_X0, ra, R_X0)
          return nil
        if e.b.kind == :num && jit_small_int_lit?(e.b, 4095) && e.b.a.to_i >= 0
          gen_expr_to_i32(e.a)
          if op == "+"
            @a.add_wi(R_X0, R_X0, e.b.a.to_i)
          else
            @a.sub_wi(R_X0, R_X0, e.b.a.to_i)
          return nil
        gen_expr_to_i32(e.a)
        push_w(R_X0)
        gen_expr_to_i32(e.b)
        pop_w(R_X9)
        if op == "+"
          @a.add_w(R_X0, R_X9, R_X0)
        else
          @a.sub_w(R_X0, R_X9, R_X0)
        return nil
      if op == "*" && exact_i32_small_term?(e.a) && jit_small_int_lit?(e.b, 1048576)
        gen_expr_to_i32(e.a)
        kv = e.b.a.to_i
        if kv == 2
          @a.lsl_wi(R_X0, R_X0, 1)
        elsif kv == 4
          @a.lsl_wi(R_X0, R_X0, 2)
        else
          @a.mov_imm32(R_X9, kv)
          @a.mul_w(R_X0, R_X0, R_X9)
        return nil
      if op == "*" && jit_small_int_lit?(e.a, 1048576) && exact_i32_small_term?(e.b)
        gen_expr_to_i32(e.b)
        kv = e.a.a.to_i
        @a.mov_imm32(R_X9, kv)
        @a.mul_w(R_X0, R_X0, R_X9)
        return nil
      if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>"
        gen_expr_i32(e)
        return nil
    # Direct scalar-replaced closure call returning exact i32 sum!
    if k == :call && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0 && @info.sra_clos[li] != nil
        sc = @info.sra_clos[li]
        re = jit_inline_return_expr(sc.inner_jf)
        if re != nil && e.list.size == sc.inner_jf.params.size
          gen_sra_closure_call_to_i32(sc, e.list)
          return nil
    # Direct polymorphic inlined numeric method call returning unboxed f64 -> ToInt32 (ZERO boxing!)
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.x.is_a?(Array) && e.x.size >= 2 && e.list.size == 0
      if gen_poly_method_inline_f64(e, e.a, e.x)
        emit_f64_to_i32(R_X0, R_D0)
        return nil
    if can_i32?(e)
      gen_expr_i32(e)
      return nil
    if can_f64?(e)
      gen_expr_f64(e)
      emit_f64_to_i32(R_X0, R_D0)
      return nil
    # Fallback: evaluate boxed, convert to int32
    gen_expr_any(e)
    @a.sub_r(R_X15, R_X0, R_X20)
    @a.cmp_r(R_X15, R_X21)
    l_slow = @a.new_label
    l_done = @a.new_label
    @a.b_cond(CC_HS, l_slow)
    @a.fmov_d_x(R_D0, R_X15)
    emit_f64_to_i32(R_X0, R_D0)
    @a.b(l_done)
    @a.bind(l_slow)
    @a.mov_r(R_X1, R_X0)
    call_rt(RT_TO_INT32)
    @a.sub_r(R_X15, R_X0, R_X20)
    @a.fmov_d_x(R_D0, R_X15)
    @a.fcvtzs_w_d(R_X0, R_D0)
    @a.bind(l_done)
    nil

  -> exact_i32_small_term?(e)
    return true if can_i32?(e)
    if e.kind == :binary && (e.str == "+" || e.str == "-")
      return can_i32?(e.a) && jit_small_int_lit?(e.b, 65536)
    false

  -> exact_i32_sum_term?(e)
    return true if can_i32?(e)
    if e.kind == :binary
      op = e.str
      return exact_i32_sum_term?(e.a) && exact_i32_sum_term?(e.b) if op == "+" || op == "-"
      return exact_i32_small_term?(e.a) && jit_small_int_lit?(e.b, 1048576) if op == "*"
      return jit_small_int_lit?(e.a, 1048576) && exact_i32_small_term?(e.b) if op == "*"
    if e.kind == :call && e.a.kind == :ident
      li = local_idx(e.a)
      return li >= 0 && @info.sra_clos[li] != nil
    false

  -> gen_sra_closure_call_to_i32(sc, arg_nodes)
    # Bind inner params to virtual regs/slots and evaluate inner return expression directly in i32!
    inner = sc.inner_jf
    re = jit_inline_return_expr(inner)
    old_env = @inline_env
    env = {}
    # Captured factory params live in sc.cap_slots
    fvals = inner.free.values
    i = 0
    while i < fvals.size
      fb = fvals[i]
      # Match parameter index in factory
      pi = fb.scope.func.params.index(fb)
      if pi != nil && pi < sc.cap_slots.size
        env[fb] = [:slot, sc.cap_slots[pi]]
      i += 1
    # Evaluate call arguments directly in callee-saved regs when possible (zero stack traffic!)
    pushed = 0
    i = 0
    while i < inner.params.size
      pb = inner.params[i]
      ae = i < arg_nodes.size ? arg_nodes[i] : nil
      pr = peek_i32_reg(ae)
      if pr != nil
        env[pb] = [:reg_w, pr]
      elsif ae != nil && can_i32?(ae)
        gen_expr_i32(ae)
        off = push_w(R_X0)
        pushed += 1
        env[pb] = [:spill_w, off]
      else
        gen_expr_any(ae)
        off = push_x(R_X0)
        pushed += 1
        env[pb] = [:spill_x, off]
      i += 1
    @inline_env = env
    gen_expr_to_i32(re)
    @inline_env = old_env
    @tmp_depth -= pushed
    nil

  -> gen_sra_closure_call_f64(sc, arg_nodes)
    inner = sc.inner_jf
    re = jit_inline_return_expr(inner)
    old_env = @inline_env
    env = {}
    fvals = inner.free.values
    i = 0
    while i < fvals.size
      fb = fvals[i]
      pi = fb.scope.func.params.index(fb)
      env[fb] = [:slot, sc.cap_slots[pi]] if pi != nil && pi < sc.cap_slots.size
      i += 1
    pushed = 0
    i = 0
    while i < inner.params.size
      pb = inner.params[i]
      ae = i < arg_nodes.size ? arg_nodes[i] : nil
      pr = peek_i32_reg(ae)
      if pr != nil
        env[pb] = [:reg_w, pr]
      elsif ae != nil && can_i32?(ae)
        gen_expr_i32(ae)
        off = push_w(R_X0)
        pushed += 1
        env[pb] = [:spill_w, off]
      else
        gen_expr_f64(ae)
        off = push_d(R_D0)
        pushed += 1
        env[pb] = [:spill_d, off]
      i += 1
    @inline_env = env
    gen_expr_f64(re)
    @inline_env = old_env
    @tmp_depth -= pushed
    nil

  # Inline 1-entry IC for `str_local.indexOf(sub)` -> i32 result in w0 (ZERO runtime calls on hit!)
  -> gen_str_indexof_i32(call_e, str_e, sub_e)
    sli = local_idx(str_e)
    if sli >= 0 && sub_e.kind == :string
      hr = @inv_indexof[sli.to_s + ":" + sub_e.str]
      if hr != nil
        @a.mov_w(R_X0, hr)
        return nil
    ic = @str_io_ics[call_e]
    if ic == nil
      ic = i64[3]
      ic[0] = 0; ic[1] = 0; ic[2] = 0
      jit_keep(ic)
      @str_io_ics[call_e] = ic
    ic_p = jit_arr_slots_ptr(wvalue_bits(ic) ## i64)
    l_miss = @a.new_label
    l_done = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_miss)
    r_s = (sli >= 0 && @info.types[sli] == JT_ANY) ? @info.reg_gpr[sli] : nil
    if r_s != nil
      @a.mov_r(R_X13, r_s)
    else
      load_slot_any(R_X13, sli)
    if sub_e.kind == :string
      jit_keep(sub_e.str)
      @a.mov_imm64(R_X14, wvalue_bits(sub_e.str) ## i64)
    else
      push_x(R_X13)
      gen_expr_any(sub_e)
      @a.mov_r(R_X14, R_X0)
      pop_x(R_X13)
    @a.mov_imm64(R_X9, ic_p)
    @a.ldr_x(R_X10, R_X9, 0)
    @a.cmp_r(R_X13, R_X10)
    @a.b_cond(CC_NE, l_miss)
    @a.ldr_x(R_X10, R_X9, 8)
    @a.cmp_r(R_X14, R_X10)
    @a.b_cond(CC_NE, l_miss)
    @a.ldr_w(R_X0, R_X9, 16)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_miss)
      @a.mov_r(R_X1, R_X13)
      @a.mov_r(R_X2, R_X14)
      @a.mov_imm64(R_X3, wvalue_bits(ic) ## i64)
      call_rt(RT_STR_INDEXOF_IC)
      @a.sub_r(R_X15, R_X0, R_X20)
      @a.fmov_d_x(R_D16, R_X15)
      @a.fcvtzs_w_d(R_X0, R_D16)
      @a.b(l_done)
    add_cold_stub(cb)
    nil

  # Inline 1-entry ASCII IC for `str_local.charCodeAt(idx)` -> u16 code unit in w0 (or branches to l_oob if OOB/slow!)
  -> gen_str_charcode_i32_fast(call_e, str_e, idx_e, l_slow_out)
    sli = local_idx(str_e)
    # Ultra-fast hoisted loop-invariant ASCII string `(ptr, [len], [bmask])` path (2-3 instructions total!)
    if sli >= 0 && @inv_str_ascii[sli] != nil
      hp = @inv_str_ascii[sli]
      skip_bc = hp[2] >= 0 && idx_e.kind == :binary && idx_e.str == "&" && idx_e.b.kind == :num && jit_int32_lit?(idx_e.b) && idx_e.b.a.to_i >= 0 && idx_e.b.a.to_i <= hp[2]
      if skip_bc || hp[1] != nil
        r_idx = peek_i32_reg(idx_e)
        if r_idx != nil
          @a.sxtw(R_X12, r_idx)
        else
          gen_expr_to_i32(idx_e)
          @a.sxtw(R_X12, R_X0)
        if !skip_bc
          @a.cmp_r(R_X12, hp[1])
          @a.b_cond(CC_HS, l_slow_out)
        @a.ldrb_idx(R_X0, hp[0], R_X12)
        return @str_cc_ics[call_e]
    ic = @str_cc_ics[call_e]
    if ic == nil
      ic = i64[3]
      ic[0] = 0; ic[1] = 0; ic[2] = 0
      jit_keep(ic)
      @str_cc_ics[call_e] = ic
    ic_p = jit_arr_slots_ptr(wvalue_bits(ic) ## i64)
    r_idx = peek_i32_reg(idx_e)
    if r_idx != nil
      @a.sxtw(R_X12, r_idx)
    else
      gen_expr_to_i32(idx_e)
      @a.sxtw(R_X12, R_X0)
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow_out)
    r_s = (sli >= 0 && @info.types[sli] == JT_ANY) ? @info.reg_gpr[sli] : nil
    if r_s != nil
      @a.mov_r(R_X13, r_s)
    else
      load_slot_any(R_X13, sli)
    @a.mov_imm64(R_X9, ic_p)
    @a.ldr_x(R_X10, R_X9, 0)
    @a.cmp_r(R_X13, R_X10)
    @a.b_cond(CC_NE, l_slow_out)
    @a.ldr_x(R_X11, R_X9, 16)         # byte_len
    @a.cmp_r(R_X12, R_X11)
    @a.b_cond(CC_HS, l_slow_out)
    @a.ldr_x(R_X10, R_X9, 8)          # ascii_ptr
    @a.ldrb_idx(R_X0, R_X10, R_X12)   # 1-cycle ASCII byte load!
    ic

  -> gen_str_charcode_f64(call_e, str_e, idx_e)
    l_miss = @a.new_label
    l_done = @a.new_label
    ic = gen_str_charcode_i32_fast(call_e, str_e, idx_e, l_miss)
    @a.scvtf_d_w(R_D0, R_X0)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_miss)
      @a.mov_r(R_X1, R_X13)
      emit_box_i32(R_X2, R_X12)
      @a.mov_imm64(R_X3, wvalue_bits(ic) ## i64)
      call_rt(RT_STR_CHARCODE_IC)
      @a.sub_r(R_X15, R_X0, R_X20)
      @a.fmov_d_x(R_D0, R_X15)
      @a.b(l_done)
    add_cold_stub(cb)
    nil

  # Check if `e` can be evaluated cleanly as an exact bounded 64-bit integer (for loop-promoted i53 accumulators!)
  -> expr_can_i64_exact?(e)
    return false if e == nil
    return true if can_i32?(e)
    k = e.kind
    if k == :binary && (e.str == "+" || e.str == "-")
      return expr_can_i64_exact?(e.a) && expr_can_i64_exact?(e.b)
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.b.str == "charCodeAt" && e.list.size == 1 && !@is_osr
      sli = local_idx(e.a.a)
      return sli >= 0 && @info.str_locals[sli] && can_i32?(e.list[0])
    if k == :call && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0 && @info.sra_clos[li] != nil
        sc = @info.sra_clos[li]
        re = jit_inline_return_expr(sc.inner_jf)
        if re != nil && e.list.size == sc.inner_jf.params.size && re.kind == :binary && (re.str == "+" || re.str == "-")
          # Check all captured slots are JT_I32 and all args are can_i32?
          ok = true
          sc.cap_slots.each ->(cs) ok = false if @info.types[cs] != JT_I32
          e.list.each ->(ae) ok = false if !can_i32?(ae)
          return ok
    if k == :member && e.has?(F_COMPUTED) && can_i32?(e.b)
      bli = local_idx(e.a)
      return bli >= 0 && @hoisted_arrs[bli] != nil
    false

  # Evaluate `e` as an exact 64-bit signed integer into R_X0 (branching to @i53_acc_bail on any miss/non-i32)!
  -> gen_expr_i64_exact(e)
    k = e.kind
    # Fold constant-only binary sums (`a + b + c + d`)!
    if k == :binary && (e.str == "+" || e.str == "-")
      # Collect additive chain with constant folding (turns `o.a + 2 + 3 + 4` into `o.a + 9`!)
      if e.str == "+"
        terms = []
        csum = [0]
        collect_i64_add_terms(e, terms, csum)
        if terms.size == 0
          @a.mov_imm64(R_X0, csum[0])
          return nil
        # Evaluate non-register term first so register terms add without spilling to stack!
        if terms.size >= 2 && peek_i32_reg(terms[0]) != nil && peek_i32_reg(terms[1]) == nil
          sw = terms[0]
          terms[0] = terms[1]
          terms[1] = sw
        if can_i32?(terms[0]) && peek_i32_reg(terms[0]) != nil
          @a.sxtw(R_X0, peek_i32_reg(terms[0]))
        else
          gen_expr_i64_exact(terms[0])
        ti = 1
        while ti < terms.size
          t_e = terms[ti]
          rt = peek_i32_reg(t_e)
          if rt != nil
            @a.sxtw(R_X9, rt)
            @a.add_r(R_X0, R_X0, R_X9)
          else
            push_x(R_X0)
            gen_expr_i64_exact(t_e)
            pop_x(R_X9)
            @a.add_r(R_X0, R_X9, R_X0)
          ti += 1
        if csum[0] > 0 && csum[0] <= 4095
          @a.add_i(R_X0, R_X0, csum[0])
        elsif csum[0] < 0 && csum[0] >= -4095
          @a.sub_i(R_X0, R_X0, 0 - csum[0])
        elsif csum[0] != 0
          @a.mov_imm64(R_X9, csum[0])
          @a.add_r(R_X0, R_X0, R_X9)
        return nil
      gen_expr_i64_exact(e.a)
      push_x(R_X0)
      gen_expr_i64_exact(e.b)
      pop_x(R_X9)
      @a.sub_r(R_X0, R_X9, R_X0)
      return nil
    if can_i32?(e)
      gen_expr_i32(e)
      @a.sxtw(R_X0, R_X0)
      return nil
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.b.str == "charCodeAt" && e.list.size == 1 && !@is_osr
      gen_str_charcode_i32_fast(e, e.a.a, e.list[0], @i53_acc_bail)
      return nil
    if k == :call && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0 && @info.sra_clos[li] != nil
        sc = @info.sra_clos[li]
        re = jit_inline_return_expr(sc.inner_jf)
        old_env = @inline_env
        env = {}
        fvals = sc.inner_jf.free.values
        fi = 0
        while fi < fvals.size
          fb = fvals[fi]
          pi = fb.scope.func.params.index(fb)
          env[fb] = [:slot, sc.cap_slots[pi]] if pi != nil && pi < sc.cap_slots.size
          fi += 1
        pushed = 0
        pi = 0
        while pi < sc.inner_jf.params.size
          pb = sc.inner_jf.params[pi]
          ae = e.list[pi]
          pr = peek_i32_reg(ae)
          if pr != nil
            env[pb] = [:reg_w, pr]
          elsif sc.inner_jf.params.size == 1 && (re.kind == :binary && (re.str == "+" || re.str == "-"))
            # 1-arg additive closure (e.g. `add(i & 255)`): keep arg in R_X10 — ZERO stack spill/reload!
            gen_expr_i32(ae)
            @a.mov_w(R_X10, R_X0)
            env[pb] = [:reg_w, R_X10]
          else
            gen_expr_i32(ae)
            off = push_w(R_X0)
            pushed += 1
            env[pb] = [:spill_w, off]
          pi += 1
        @inline_env = env
        gen_expr_i64_exact(re)
        @inline_env = old_env
        @tmp_depth -= pushed
        return nil
    if k == :member && e.has?(F_COMPUTED) && can_i32?(e.b)
      bli = local_idx(e.a)
      ar = @hoisted_arr_regs[bli]
      r_sl = (ar != nil && ar[0] != nil) ? ar[0] : R_X9
      r_idx = peek_i32_reg(e.b)
      if r_idx != nil
        @a.sxtw(R_X11, r_idx)
      else
        gen_expr_i32(e.b)
        @a.sxtw(R_X11, R_X0)
      @a.ldr_x(R_X9, R_SP, @hoisted_arrs[bli][0]) if r_sl == R_X9
      idx_li = local_idx(e.b)
      if !(idx_li >= 0 && @bounded_idx[idx_li] == bli)
        if ar != nil && ar[1] != nil
          @a.cmp_r(R_X11, ar[1])
        else
          @a.ldr_x(R_X10, R_SP, @hoisted_arrs[bli][1])
          @a.cmp_r(R_X11, R_X10)
        @a.b_cond(CC_HS, @i53_acc_bail)
      @a.ldr_x_idx(R_X10, r_sl, R_X11)
      emit_unbox_exact_i32(R_X0, R_X10, @i53_acc_bail)
      @a.sxtw(R_X0, R_X0)
      return nil
    @a.b(@i53_acc_bail)
    nil

  -> expr_const_i32_val(e)
    return nil if e == nil
    return e.a.to_i if e.kind == :num && jit_int32_lit?(e)
    if e.kind == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      return @info.sra_objs[bli].const_i32[e.b.str] if bli >= 0 && @info.sra_objs[bli] != nil
    nil

  -> collect_i64_add_terms(e, terms, csum)
    if e.kind == :binary && e.str == "+"
      collect_i64_add_terms(e.a, terms, csum)
      collect_i64_add_terms(e.b, terms, csum)
      return nil
    cv = expr_const_i32_val(e)
    if cv != nil
      csum[0] = csum[0] + cv
      return nil
    terms.push(e)
    nil

  # Evaluate expression whose type is known JT_I32 -> result in w0.
  -> gen_expr_i32(e)
    k = e.kind
    if k == :num
      @a.mov_imm32(R_X0, e.a.to_i)
      return nil
    if k == :ident
      if @inline_env != nil && e.x != nil && @inline_env[e.x.binding] != nil
        iv = @inline_env[e.x.binding]
        if iv[0] == :slot
          load_slot_i32(R_X0, iv[1])
          return nil
        if iv[0] == :spill_w
          @a.ldr_w(R_X0, R_SP, iv[1])
          return nil
        if iv[0] == :reg_w
          @a.mov_w(R_X0, iv[1])
          return nil
      li = local_idx(e)
      if li >= 0 && @info.types[li] == JT_I32
        load_slot_i32(R_X0, li)
        return nil
    if k == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        cval = @info.sra_objs[bli].const_i32[e.b.str]
        if cval != nil
          @a.mov_imm32(R_X0, cval)
          return nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        if vs != nil && @info.types[vs] == JT_I32
          load_slot_i32(R_X0, vs)
          return nil
      if bli >= 0 && @info.sra_rxs[bli] != nil && e.b.str == "index"
        caps_p = jit_arr_slots_ptr(wvalue_bits(@info.sra_rxs[bli]) ## i64)
        @a.mov_imm64(R_X9, caps_p)
        @a.ldr_x(R_X0, R_X9, 0)
        return nil
      if e.b.str == "length" && e.a.kind == :member && e.a.has?(F_COMPUTED) && local_idx(e.a.a) >= 0 && @info.sra_rxs[local_idx(e.a.a)] != nil && jit_int32_lit?(e.a.b) && e.a.b.a.to_i >= 0 && e.a.b.a.to_i < 15
        g = e.a.b.a.to_i
        caps_p = jit_arr_slots_ptr(wvalue_bits(@info.sra_rxs[local_idx(e.a.a)]) ## i64)
        @a.mov_imm64(R_X9, caps_p)
        @a.ldr_x(R_X10, R_X9, 240)
        @a.cmp_i(R_X10, g)
        @a.b_cond(CC_LT, @l_deopt)
        @a.ldr_x(R_X10, R_X9, g * 16)
        @a.ldr_x(R_X11, R_X9, g * 16 + 8)
        @a.cmp_i(R_X10, 0)
        @a.b_cond(CC_LT, @l_deopt)
        @a.sub_w(R_X0, R_X11, R_X10)
        return nil
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @hoisted_tas[bli] != nil && @hoisted_tas[bli][2] <= 5
        # Integer TypedArray element load -> direct ldrb/ldrh/ldr_w_idx into w0!
        gen_ta_load_i32(bli, e.b)
        return nil
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.b.str == "indexOf" && e.list.size == 1 && !@is_osr
      sli = local_idx(e.a.a)
      if sli >= 0 && @info.str_locals[sli]
        gen_str_indexof_i32(e, e.a.a, e.list[0])
        return nil
    if k == :binary
      op = e.str
      # `x | 0` -> gen_expr_to_i32(x)
      if op == "|" && e.b.kind == :num && e.b.a == ~0.0
        gen_expr_to_i32(e.a)
        return nil
      # `x & 255` (power-of-two mask!) -> single AND W0, W0, #mask
      if op == "&" && e.b.kind == :num && jit_int32_lit?(e.b)
        m = e.b.a.to_i
        if m == 1 || m == 3 || m == 7 || m == 15 || m == 31 || m == 63 || m == 127 || m == 255 || m == 511 || m == 1023 || m == 2047 || m == 4095 || m == 65535
          gen_expr_to_i32(e.a)
          nb = 0
          t = m
          while t > 0
            nb += 1
            t = t >> 1
          @a.and_w_lowmask(R_X0, R_X0, nb)
          return nil
      if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>"
        gen_expr_to_i32(e.a)
        push_w(R_X0)
        gen_expr_to_i32(e.b)
        pop_w(R_X9)
        if op == "|"
          @a.orr_w(R_X0, R_X9, R_X0)
        elsif op == "&"
          @a.and_w(R_X0, R_X9, R_X0)
        elsif op == "^"
          @a.eor_w(R_X0, R_X9, R_X0)
        elsif op == "<<"
          @a.lsl_w(R_X0, R_X9, R_X0)
        else
          @a.asr_w(R_X0, R_X9, R_X0)
        return nil
      # Exact non-negative `a % K` (positive int32 literal K): magic multiply, deopt if a < 0 (preserves -0.0!)
      if op == "%" && can_i32?(e.a) && e.b.kind == :num && jit_int32_lit?(e.b) && e.b.a.to_i > 0
        kv = e.b.a.to_i
        ra = peek_i32_reg(e.a)
        if ra != nil
          @a.cmp_wi(ra, 0)
          @a.b_cond(CC_LT, @l_deopt)
          @a.mov_w(R_X9, ra)
        else
          gen_expr_i32(e.a)
          @a.cmp_wi(R_X0, 0)
          @a.b_cond(CC_LT, @l_deopt)
          @a.mov_w(R_X9, R_X0)
        if kv == 1
          @a.movz_x(R_X0, 0)
        else
          emit_mod_const_u31(R_X0, R_X9, kv)
        return nil
      # Small offset like `i + 1` into an i32 slot (skip overflow check if loop guard proved i <= 2147483645!)
      if (op == "+" || op == "-") && can_i32?(e.a) && jit_small_int_lit?(e.b, 4095) && e.b.a.to_i >= 0
        if op == "+" && e.b.a.to_i == 1 && @no_ovf_p1_li >= 0 && local_idx(e.a) == @no_ovf_p1_li && @info.reg_gpr[@no_ovf_p1_li] != nil
          off_p1 = (@unroll_i_li == @no_ovf_p1_li ? @unroll_i_off : 0)
          @a.add_wi(R_X0, @info.reg_gpr[@no_ovf_p1_li], 1 + off_p1)
          return nil
        gen_expr_i32(e.a)
        if op == "+"
          @a.adds_wi(R_X0, R_X0, e.b.a.to_i)
        else
          @a.subs_wi(R_X0, R_X0, e.b.a.to_i)
        @a.b_cond(CC_VS, @l_deopt)
        return nil
    if k == :unary && e.str == "~"
      gen_expr_to_i32(e.a)
      @a.mvn_w(R_X0, R_X0)
      return nil
    gen_expr_to_i32(e)
    nil

  # ---- Lane 2: Unboxed f64 Expression Codegen -> result in d0 ----

  # Does `e` live directly in an FPR without emitting any instructions?
  -> peek_f64_reg(e)
    return nil if e == nil
    if e.kind == :num && @block_const_fp.size > 0
      bits = jit_f64_bits(wvalue_bits(e.a) ## i64)
      return @block_const_fp[bits] if @block_const_fp[bits] != nil
    if e.kind == :ident
      if @inline_env != nil && e.x != nil && @inline_env[e.x.binding] != nil
        iv = @inline_env[e.x.binding]
        return iv[1] if iv[0] == :reg_d
        return @info.reg_fpr[iv[1]] if iv[0] == :slot && @info.types[iv[1]] == JT_F64
        return nil
      li = local_idx(e)
      return @info.reg_fpr[li] if li >= 0 && @info.types[li] == JT_F64
    if e.kind == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        return @info.reg_fpr[vs] if vs != nil && @info.types[vs] == JT_F64
      if bli >= 0 && @known_shapes[bli] != nil
        pk = bli.to_s + ":" + e.b.str
        return @block_prop_fp[pk] if @block_prop_fp[pk] != nil
    nil

  # Check if `e` is a simple leaf (won't itself use R_D15 recursively).
  -> expr_uses_d15?(e)
    return false if e == nil
    k = e.kind
    return false if k == :num || k == :ident
    return expr_uses_d15?(e.a) if k == :unary
    if k == :member
      return expr_uses_d15?(e.a) || (e.has?(F_COMPUTED) && expr_uses_d15?(e.b))
    # `dx * dx`, `dy * dy`, `dz * dz` (both operands in FP regs!) take 1 insn and never touch R_D15!
    return false if k == :binary && peek_f64_reg(e.a) != nil && peek_f64_reg(e.b) != nil
    true

  -> gen_expr_f64(e)
    k = e.kind
    if k == :num
      bits = jit_f64_bits(wvalue_bits(e.a) ## i64)
      if @block_const_fp[bits] != nil
        @a.fmov_d(R_D0, @block_const_fp[bits])
        return nil
      @a.mov_imm64(R_X9, bits)
      @a.fmov_d_x(R_D0, R_X9)
      return nil
    if can_i32?(e)
      gen_expr_i32(e)
      @a.scvtf_d_w(R_D0, R_X0)
      return nil
    if k == :ident
      if @inline_env != nil && e.x != nil && @inline_env[e.x.binding] != nil
        iv = @inline_env[e.x.binding]
        if iv[0] == :slot
          load_slot_f64(R_D0, iv[1])
          return nil
        if iv[0] == :reg_d
          @a.fmov_d(R_D0, iv[1])
          return nil
        if iv[0] == :spill_d
          @a.ldr_d(R_D0, R_SP, iv[1])
          return nil
      li = local_idx(e)
      if li >= 0 && @info.types[li] == JT_F64
        load_slot_f64(R_D0, li)
        return nil
    if k == :member && !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        if vs != nil && @info.types[vs] == JT_F64
          load_slot_f64(R_D0, vs)
          return nil
      # Direct known-shape own-slot f64 load (1 LDR + unbox, PLUS read-only property CSE in d18..d31!)
      if bli >= 0 && @known_shapes[bli] != nil && e.x != nil
        ic = e.x
        if ic[0] == @known_shapes[bli] && ic[2] == 0 && ic[1] != 0
          pk = bli.to_s + ":" + e.b.str
          cached = @block_prop_fp[pk]
          if cached != nil
            @a.fmov_d(R_D0, cached)
            return nil
          r_obj = @info.reg_gpr[bli]
          if r_obj != nil
            @a.sub_i(R_X9, r_obj, 4)
          else
            load_slot_any(R_X9, bli)
            @a.sub_i(R_X9, R_X9, 4)
          if @d_bias_reg != nil && ic[1] > 0 && @mono_arr_num[@known_shapes[bli]] == true
            # Zero-tag-check, zero-FMOV pure SIMD FP load (`ldr d0; sub d0, d0, d17` = 2 insns, 0 branches!)
            @a.ldr_d(R_D0, R_X9, (ic[1] + 1) * 8)
            @a.sub_d_i64(R_D0, R_D0, @d_bias_reg)
          else
            l_sl = @a.new_label
            l_dn = @a.new_label
            emit_slot_load(R_X0, R_X9, ic[1])
            emit_unbox_f64(R_D0, R_X0, l_sl)
            @a.bind(l_dn)
            nc = @next_prop_fp - R_D18
            prw_own = @promoted_owner
            prw_ls = @promoted_rw_list
            cb = ->()
              @a.bind(l_sl)
              if prw_own >= 0 && prw_ls != nil && prw_ls.size > 0
                emit_flush_promoted_rw(prw_own, prw_ls)
              if nc > 0
                ci = 0
                while ci < nc
                  push_d(R_D18 + ci)
                  ci += 1
              @a.mov_r(R_X1, R_X0)
              call_rt(RT_TO_NUMBER)
              @a.fmov_d_x(R_D17, R_X20) if @d_bias_reg == R_D17
              if nc > 0
                ci = nc - 1
                while ci >= 0
                  pop_d(R_D18 + ci)
                  ci -= 1
              @a.sub_r(R_X15, R_X0, R_X20)
              @a.fmov_d_x(R_D0, R_X15)
              @a.b(l_dn)
            add_cold_stub(cb)
          # Cache read-only property ONLY when read >= 2 times in this block (skips useless fmov on 1-use reads!)
          if @block_written_props != nil && !@block_written_props[e.b.str] && (@block_prop_counts == nil || (@block_prop_counts[pk] != nil && @block_prop_counts[pk] >= 2)) && @next_prop_fp <= R_D31
            cr = @next_prop_fp
            @next_prop_fp += 1
            @a.fmov_d(cr, R_D0)
            @block_prop_fp[pk] = cr
          return nil
    if k == :member && e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @hoisted_tas[bli] != nil
        gen_ta_load_f64(bli, e.b)
        return nil
    if k == :unary && e.str == "-"
      gen_expr_f64(e.a)
      @a.fneg_d(R_D0, R_D0)
      return nil
    if k == :unary && e.str == "+"
      gen_expr_f64(e.a)
      return nil
    if k == :binary
      op = e.str
      if op == "+" || op == "-" || op == "*" || op == "/"
        da = peek_f64_reg(e.a)
        db = peek_f64_reg(e.b)
        # Both operands already in FP registers (`dx * dx`, `dy * dy`, `d2 * ...` -> 1 SINGLE INSN!)
        if da != nil && db != nil
          if op == "+"
            @a.fadd_d(R_D0, da, db)
          elsif op == "-"
            @a.fsub_d(R_D0, da, db)
          elsif op == "*"
            @a.fmul_d(R_D0, da, db)
          else
            @a.fdiv_d(R_D0, da, db)
          return nil
        # Right operand in FP reg (`... * mag`, `... + dy * dy`) -> ZERO stack spill!
        if db != nil
          gen_expr_f64(e.a)
          if op == "+"
            @a.fadd_d(R_D0, R_D0, db)
          elsif op == "-"
            @a.fsub_d(R_D0, R_D0, db)
          elsif op == "*"
            @a.fmul_d(R_D0, R_D0, db)
          else
            @a.fdiv_d(R_D0, R_D0, db)
          return nil
        # Left operand in FP reg (`dx * b.m`, `d2 * Math.sqrt(d2)`) -> ZERO stack spill!
        if da != nil
          gen_expr_f64(e.b)
          if op == "+"
            @a.fadd_d(R_D0, da, R_D0)
          elsif op == "-"
            @a.fsub_d(R_D0, da, R_D0)
          elsif op == "*"
            @a.fmul_d(R_D0, da, R_D0)
          else
            @a.fdiv_d(R_D0, da, R_D0)
          return nil
        # Right operand is a number literal (`... + 0.01`, `i * 0.5`, `x * 2`) -> ZERO stack spill!
        if e.b.kind == :num
          gen_expr_f64(e.a)
          if op == "*" && e.b.a == ~2.0
            @a.fadd_d(R_D0, R_D0, R_D0)
            return nil
          bits = jit_f64_bits(wvalue_bits(e.b.a) ## i64)
          @a.mov_imm64(R_X9, bits)
          @a.fmov_d_x(R_D1, R_X9)
          if op == "+"
            @a.fadd_d(R_D0, R_D0, R_D1)
          elsif op == "-"
            @a.fsub_d(R_D0, R_D0, R_D1)
          elsif op == "*"
            @a.fmul_d(R_D0, R_D0, R_D1)
          else
            @a.fdiv_d(R_D0, R_D0, R_D1)
          return nil
        # Right operand is a reg-reg binary leaf (`a + (dy * dy)` -> 2 insns, ZERO fmov d15!)
        if e.b.kind == :binary && (e.b.str == "*" || e.b.str == "+" || e.b.str == "-" || e.b.str == "/")
          rba = peek_f64_reg(e.b.a)
          rbb = peek_f64_reg(e.b.b)
          if rba != nil && rbb != nil
            gen_expr_f64(e.a)
            emit_f64_op(e.b.str, R_D1, rba, rbb)
            emit_f64_op(op, R_D0, R_D0, R_D1)
            return nil
        if @info.reg_fpr.size < 8 && @d_bias_reg != R_D15 && !expr_uses_d15?(e.b)
          # Zero-spill FP binary op using unused callee-saved R_D15 (`a.x - b.x`, `dx * dx + dy * dy`)!
          gen_expr_f64(e.a)
          @a.fmov_d(R_D15, R_D0)
          gen_expr_f64(e.b)
          if op == "+"
            @a.fadd_d(R_D0, R_D15, R_D0)
          elsif op == "-"
            @a.fsub_d(R_D0, R_D15, R_D0)
          elsif op == "*"
            @a.fmul_d(R_D0, R_D15, R_D0)
          else
            @a.fdiv_d(R_D0, R_D15, R_D0)
          return nil
        gen_expr_f64(e.a)
        push_d(R_D0)
        gen_expr_f64(e.b)
        pop_d(R_D1)
        if op == "+"
          @a.fadd_d(R_D0, R_D1, R_D0)
        elsif op == "-"
          @a.fsub_d(R_D0, R_D1, R_D0)
        elsif op == "*"
          @a.fmul_d(R_D0, R_D1, R_D0)
        else
          @a.fdiv_d(R_D0, R_D1, R_D0)
        return nil
      if op == "%"
        # Fast integer modulo when both operands are non-negative int32 (e.g. `(k + r) % n` in typed_arrays!)
        if can_i32?(e.a) && can_i32?(e.b)
          gen_i32_mod_nonneg(e.a, e.b)
          @a.scvtf_d_w(R_D0, R_X0)
          return nil
        gen_expr_any(e.a)
        push_x(R_X0)
        gen_expr_any(e.b)
        @a.mov_r(R_X2, R_X0)
        pop_x(R_X1)
        call_rt(RT_MOD)
        @a.sub_r(R_X15, R_X0, R_X20)
        @a.fmov_d_x(R_D0, R_X15)
        return nil
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.a.kind == :ident && e.a.a.str == "Math"
      if gen_math_f64(e.a.b.str, e.list)
        return nil
    if k == :call && e.a.kind == :member && !e.a.has?(F_COMPUTED) && e.a.b.str == "charCodeAt" && e.list.size == 1 && !@is_osr
      sli = local_idx(e.a.a)
      if sli >= 0 && @info.str_locals[sli]
        gen_str_charcode_f64(e, e.a.a, e.list[0])
        return nil
    if k == :call && e.a.kind == :ident
      li = local_idx(e.a)
      if li >= 0 && @info.sra_clos[li] != nil
        sc = @info.sra_clos[li]
        re = jit_inline_return_expr(sc.inner_jf)
        if re != nil && e.list.size == sc.inner_jf.params.size
          gen_sra_closure_call_f64(sc, e.list)
          return nil
    # General boxed fallback -> unbox double (or ToNumber)
    gen_expr_any(e)
    l_slow = @a.new_label
    l_done = @a.new_label
    emit_unbox_f64(R_D0, R_X0, l_slow)
    @a.b(l_done)
    @a.bind(l_slow)
    @a.mov_r(R_X1, R_X0)
    call_rt(RT_TO_NUMBER)
    @a.sub_r(R_X15, R_X0, R_X20)
    @a.fmov_d_x(R_D0, R_X15)
    @a.bind(l_done)
    nil

  # Compute `(a % b)` as i32 when `a >= 0 && b > 0`:
  #   - Zero-taken-branch fast shortcut when `0 <= a < 2*b` (`sub + csel`, 3 cycles, NO udiv!)
  #   - Out-of-line cold stub for `a >= 2*b` (`udiv + msub`) and `a < 0 || b <= 0` (`RT_MOD`)!
  -> gen_i32_mod_nonneg(ea, eb)
    rb = peek_i32_reg(eb)
    if rb != nil
      gen_expr_to_i32(ea)
      @a.mov_w(R_X9, R_X0)
      @a.mov_w(R_X0, rb)
    elsif eb.kind == :num && jit_int32_lit?(eb)
      gen_expr_to_i32(ea)
      @a.mov_w(R_X9, R_X0)
      @a.mov_imm32(R_X0, eb.a.to_i)
    else
      gen_expr_to_i32(ea)
      push_w(R_X0)
      gen_expr_to_i32(eb)
      pop_w(R_X9)     # x9 = a, x0 = b
    l_div = @a.new_label
    l_slow = @a.new_label
    l_done = @a.new_label
    @a.cmp_wi(R_X9, 0)
    @a.b_cond(CC_LT, l_slow)
    @a.cmp_wi(R_X0, 0)
    @a.b_cond(CC_LE, l_slow)
    # Fast path for 0 <= a < 2*b (ring buffer wrap `(k + r) % n` takes 0 divisions & 0 taken branches!)
    @a.sub_w(R_X10, R_X9, R_X0)
    @a.cmp_w(R_X9, R_X0)
    @a.csel_w(R_X11, R_X9, R_X10, CC_LO)
    @a.cmp_w(R_X11, R_X0)
    @a.b_cond(CC_HS, l_div)
    @a.mov_w(R_X0, R_X11)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_div)
      @a.udiv_w(R_X10, R_X9, R_X0)
      @a.msub_w(R_X0, R_X10, R_X0, R_X9)
      @a.b(l_done)
      @a.bind(l_slow)
      emit_box_i32(R_X1, R_X9)
      emit_box_i32(R_X2, R_X0)
      call_rt(RT_MOD)
      @a.sub_r(R_X15, R_X0, R_X20)
      @a.fmov_d_x(R_D16, R_X15)
      @a.fcvtzs_w_d(R_X0, R_D16)
      @a.b(l_done)
    add_cold_stub(cb)
    nil

  # Math.* inline ARM64 hardware instructions!
  -> gen_math_f64(name, args)
    if args.size == 1
      da = peek_f64_reg(args[0])
      if name == "sqrt"
        if da != nil
          @a.fsqrt_d(R_D0, da)
        else
          gen_expr_f64(args[0])
          @a.fsqrt_d(R_D0, R_D0)
        return true
      if name == "abs"
        if da != nil
          @a.fabs_d(R_D0, da)
        else
          gen_expr_f64(args[0])
          @a.fabs_d(R_D0, R_D0)
        return true
      if name == "floor"
        if da != nil
          @a.frintm_d(R_D0, da)
        else
          gen_expr_f64(args[0])
          @a.frintm_d(R_D0, R_D0)
        return true
      if name == "ceil"
        if da != nil
          @a.frintp_d(R_D0, da)
        else
          gen_expr_f64(args[0])
          @a.frintp_d(R_D0, R_D0)
        return true
      if name == "trunc"
        if da != nil
          @a.frintz_d(R_D0, da)
        else
          gen_expr_f64(args[0])
          @a.frintz_d(R_D0, R_D0)
        return true
    false

  # ---- TypedArray Fast Loads & Stores (Hoisted raw_ptr + len!) ----

  # Evaluate index expression into i32 in w0 (recognizing `(k + r) % n` directly!).
  -> gen_ta_index(idx_e)
    if idx_e.kind == :binary && idx_e.str == "%" && exact_i32_sum_term?(idx_e.a) && can_i32?(idx_e.b)
      gen_i32_mod_nonneg(idx_e.a, idx_e.b)
      return nil
    gen_expr_to_i32(idx_e)
    nil

  -> ta_idx_bounded?(bli, idx_e)
    idx_li = local_idx(idx_e)
    return true if idx_li >= 0 && (@bounded_idx[idx_li] == bli || @bounded_ta_set[idx_li.to_s + ":" + bli.to_s] == true)
    if idx_e.is_a?(JsNode) && idx_e.kind == :binary && idx_e.str == "%" && exact_i32_sum_term?(idx_e.a) && can_i32?(idx_e.b)
      div_li = local_idx(idx_e.b)
      return true if div_li >= 0 && @bounded_mod_ta[div_li.to_s + ":" + bli.to_s] == true
    false

  -> emit_ta_load_i32_op(kind, r_ptr, r_idx)
    if kind == 5
      @a.ldr_w_idx(R_X0, r_ptr, r_idx)
    elsif kind == 1 || kind == 2
      @a.ldrb_idx(R_X0, r_ptr, r_idx)
    elsif kind == 0
      @a.ldrsb_idx(R_X0, r_ptr, r_idx)
    elsif kind == 4
      @a.ldrh_idx(R_X0, r_ptr, r_idx)
    else
      @a.ldrsh_idx(R_X0, r_ptr, r_idx)
    nil

  -> gen_ta_load_i32(bli, idx_e)
    h = @hoisted_tas[bli]
    kind = h[2]
    tr = @hoisted_ta_regs[bli]
    r_idx = peek_i32_reg(idx_e)
    if r_idx != nil
      @a.sxtw(R_X11, r_idx)
    else
      gen_ta_index(idx_e)             # w0 = index
      @a.sxtw(R_X11, R_X0)
    r_ptr = (tr != nil && tr[0] != nil) ? tr[0] : R_X9
    @a.ldr_x(R_X9, R_SP, h[0]) if r_ptr == R_X9
    if ta_idx_bounded?(bli, idx_e)
      emit_ta_load_i32_op(kind, r_ptr, R_X11)
      return nil
    if tr != nil && tr[1] != nil
      @a.cmp_r(R_X11, tr[1])
    else
      @a.ldr_x(R_X10, R_SP, h[1])     # len
      @a.cmp_r(R_X11, R_X10)
    l_oob = @a.new_label
    l_done = @a.new_label
    @a.b_cond(CC_HS, l_oob)         # unsigned out-of-bounds (< 0 or >= len)
    emit_ta_load_i32_op(kind, r_ptr, R_X11)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_oob)
      @a.movz_x(R_X0, 0)
      @a.b(l_done)
    add_cold_stub(cb)
    nil

  -> gen_ta_load_f64(bli, idx_e)
    h = @hoisted_tas[bli]
    kind = h[2]
    tr = @hoisted_ta_regs[bli]
    r_idx = peek_i32_reg(idx_e)
    if r_idx != nil
      @a.sxtw(R_X11, r_idx)
    else
      gen_ta_index(idx_e)             # w0 = index
      @a.sxtw(R_X11, R_X0)
    r_ptr = (tr != nil && tr[0] != nil) ? tr[0] : R_X9
    @a.ldr_x(R_X9, R_SP, h[0]) if r_ptr == R_X9
    skip_bc = ta_idx_bounded?(bli, idx_e)
    l_oob = nil
    l_done = nil
    if !skip_bc
      if tr != nil && tr[1] != nil
        @a.cmp_r(R_X11, tr[1])
      else
        @a.ldr_x(R_X10, R_SP, h[1])     # len
        @a.cmp_r(R_X11, R_X10)
      l_oob = @a.new_label
      l_done = @a.new_label
      @a.b_cond(CC_HS, l_oob)
    if kind == 8
      @a.ldr_d_idx(R_D0, r_ptr, R_X11)       # Float64Array: LDR D0, [ptr, X11, LSL #3]
    elsif kind == 5
      @a.ldrsw_idx(R_X12, r_ptr, R_X11)      # Int32Array: LDRSW + SCVTF
      @a.scvtf_d_w(R_D0, R_X12)
    elsif kind == 6
      @a.ldr_w_idx(R_X12, r_ptr, R_X11)      # Uint32Array
      @a.ucvtf_d_w(R_D0, R_X12)
    elsif kind == 7
      @a.ldr_s_idx(R_D0, r_ptr, R_X11)       # Float32Array
      @a.fcvt_d_s(R_D0, R_D0)
    elsif kind == 1 || kind == 2
      @a.ldrb_idx(R_X12, r_ptr, R_X11)       # Uint8Array / Uint8ClampedArray
      @a.scvtf_d_w(R_D0, R_X12)
    elsif kind == 0
      @a.ldrsb_idx(R_X12, r_ptr, R_X11)      # Int8Array
      @a.scvtf_d_w(R_D0, R_X12)
    elsif kind == 3
      @a.ldrsh_idx(R_X12, r_ptr, R_X11)      # Int16Array
      @a.scvtf_d_w(R_D0, R_X12)
    elsif kind == 4
      @a.ldrh_idx(R_X12, r_ptr, R_X11)       # Uint16Array
      @a.scvtf_d_w(R_D0, R_X12)
    if !skip_bc
      @a.bind(l_done)
      cb = ->()
        @a.bind(l_oob)
        @a.mov_imm64(R_X12, 0x7FF8000000000000) # NaN (Number(undefined))
        @a.fmov_d_x(R_D0, R_X12)
        @a.b(l_done)
      add_cold_stub(cb)
    nil

  # ---- Lane 3: Boxed WValue Expression Codegen -> result in x0 ----

  -> gen_expr_any(e)
    if e == nil
      @a.movz_x(R_X0, 0)
      return nil
    k = e.kind
    if k == :num
      @a.mov_imm64(R_X0, wvalue_bits(e.a) ## i64)
      return nil
    if k == :true
      @a.movz_x(R_X0, 2)
      return nil
    if k == :false
      @a.movz_x(R_X0, 1)
      return nil
    if k == :null
      @a.ldr_x(R_X0, R_X19, RT_K_NULL_BITS * 8)
      return nil
    if k == :string
      jit_keep(e.str)
      @a.mov_imm64(R_X0, wvalue_bits(e.str) ## i64)
      return nil
    if k == :regex
      rx = js_rx_compile(e.str, e.a)
      jit_keep(rx)
      @a.mov_imm64(R_X1, wvalue_bits(rx) ## i64)
      call_rt(RT_NEW_REGEX)
      return nil
    if k == :this
      if @inline_env != nil && @inline_env[:this] != nil
        iv = @inline_env[:this]
        @a.mov_r(R_X0, iv[1]) if iv[0] == :reg_x
        @a.ldr_x(R_X0, R_SP, iv[1]) if iv[0] == :spill_x
        return nil
      if @jf.arrow
        g = @jf
        while g.arrow
          g = g.parent
        ref = e.x != nil ? JaRef.new(g.this_binding, e.x.scope) : nil
        emit_read_binding_any(g.this_binding, R_X0, ref)
        return nil
      @a.ldr_x(R_X0, R_SP, JF_SLOT_THIS)
      return nil
    if k == :ident
      gen_ident_any(e)
      return nil
    if k == :binary
      gen_binary_any(e)
      return nil
    if k == :unary
      gen_unary_any(e)
      return nil
    if k == :update
      gen_update_any(e)
      return nil
    if k == :assign
      gen_assign_any(e)
      return nil
    if k == :logical
      gen_logical_any(e)
      return nil
    if k == :cond
      l_else = @a.new_label
      l_end = @a.new_label
      gen_cond_branch(e.a, l_else, false)
      gen_expr_any(e.b)
      @a.b(l_end)
      @a.bind(l_else)
      gen_expr_any(e.c)
      @a.bind(l_end)
      return nil
    if k == :member
      if can_i32?(e) && !e.has?(F_COMPUTED) && ((local_idx(e.a) >= 0 && @info.sra_rxs[local_idx(e.a)] != nil) || (e.a.kind == :member && e.a.has?(F_COMPUTED) && local_idx(e.a.a) >= 0 && @info.sra_rxs[local_idx(e.a.a)] != nil))
        gen_expr_i32(e)
        emit_box_i32(R_X0, R_X0)
        return nil
      gen_member_get_any(e)
      return nil
    if k == :call
      gen_call_any(e)
      return nil
    if k == :new
      gen_new_any(e)
      return nil
    if k == :array
      gen_array_lit(e)
      return nil
    if k == :object
      gen_object_lit(e)
      return nil
    if k == :function || k == :arrow
      jf = e.x
      code = wk_code(jf)
      jit_keep(code)
      if jf.single != nil
        # Read single captured binding BEFORE loading R_X1 so RT_GGET/RT_ENV_GET cannot clobber R_X1!
        r = jf.single_ref
        if r == nil
          r = JaRef.new(jf.single, jf.def_scope)
          jf.single_ref = r
        emit_read_binding_any(r.binding, R_X2, r)
      elsif jf.free.size == 0
        @a.movz_x(R_X2, 0)
      else
        @a.ldr_x(R_X2, R_SP, JF_SLOT_ENV)
      @a.mov_imm64(R_X1, wvalue_bits(code) ## i64)
      call_rt(RT_CLOSURE)
      return nil
    if k == :seq
      i = 0
      while i < e.list.size - 1
        gen_expr_void(e.list[i])
        i += 1
      gen_expr_any(e.list[e.list.size - 1])
      return nil
    if k == :template
      gen_template_any(e)
      return nil
    @a.movz_x(R_X0, 0)
    nil

  -> gen_ident_any(e)
    b = e.x.binding
    if @inline_env != nil && @inline_env[b] != nil
      iv = @inline_env[b]
      if iv[0] == :slot
        load_slot_any(R_X0, iv[1])
      elsif iv[0] == :spill_w
        @a.ldr_w(R_X9, R_SP, iv[1])
        emit_box_i32(R_X0, R_X9)
      elsif iv[0] == :spill_x
        @a.ldr_x(R_X0, R_SP, iv[1])
      elsif iv[0] == :reg_x
        @a.mov_r(R_X0, iv[1])
      elsif iv[0] == :reg_w
        emit_box_i32(R_X0, iv[1])
      return nil
    if b.kind == :global && b.writes == 0 && e.str == "undefined"
      @a.movz_x(R_X0, 0)
      return nil
    emit_read_binding_any(b, R_X0, e.x)
    nil

  -> emit_read_binding_any(b, dst, ref = nil)
    if @inline_env != nil && @inline_env[b] != nil
      iv = @inline_env[b]
      if iv[0] == :slot
        load_slot_any(dst, iv[1])
      elsif iv[0] == :spill_w
        @a.ldr_w(R_X9, R_SP, iv[1])
        emit_box_i32(dst, R_X9)
      elsif iv[0] == :spill_x
        @a.ldr_x(dst, R_SP, iv[1])
      elsif iv[0] == :reg_x
        @a.mov_r(dst, iv[1]) if dst != iv[1]
      elsif iv[0] == :reg_w
        emit_box_i32(dst, iv[1])
      return nil
    if b.global?
      c = wk_cell(b)
      jit_keep(c)
      cb = wvalue_bits(c) ## i64
      @a.mov_imm64(R_X9, cb - 4)
      @a.ldr_x(dst, R_X9, 8)     # cell.@fast
      @a.cmp_i(dst, 3)           # JS_NOTPLAIN == 3
      l_done = @a.new_label
      @a.b_cond(CC_NE, l_done)
      @a.mov_imm64(R_X1, cb)
      call_rt(RT_GGET)
      @a.mov_r(dst, R_X0) if dst != R_X0
      @a.bind(l_done)
      return nil
    if b.scope.func != @jf
      if @jf.single == b
        if @is_osr
          # In OSR, JF_SLOT_ENV holds `act.env` (which may be a child JS:Env of this function),
          # whereas the single captured value `act.fe` lives in `act.fobj.@env` (JF_SLOT_EXTRA + 32).
          @a.ldr_x(R_X9, R_SP, JF_SLOT_EXTRA)
          @a.sub_i(R_X9, R_X9, 4)
          @a.ldr_x(dst, R_X9, 32)
        else
          @a.ldr_x(dst, R_SP, JF_SLOT_ENV)
        return nil
      # Env walk across hops via @up (ivar 0, offset +8)
      @a.ldr_x(R_X1, R_SP, JF_SLOT_ENV)
      h = ref != nil ? wk_hops(ref) : @jf.analysis.env_hops(@jf.scope, b.scope)
      while h > 0
        @a.sub_i(R_X1, R_X1, 4)
        @a.ldr_x(R_X1, R_X1, 8)
        h -= 1
      if b.slot < 7
        @a.sub_i(R_X1, R_X1, 4)
        @a.ldr_x(dst, R_X1, (b.slot + 1) * 8 + 8)
      else
        @a.mov_imm64(R_X2, wvalue_bits(b.slot) ## i64)
        call_rt(RT_ENV_GET)
        @a.mov_r(dst, R_X0) if dst != R_X0
      return nil
    if b.slot >= 0
      @a.ldr_x(R_X1, R_SP, JF_SLOT_ENV)
      h = ref != nil ? wk_hops(ref) : @jf.analysis.env_hops(@jf.scope, b.scope)
      while h > 0
        @a.sub_i(R_X1, R_X1, 4)
        @a.ldr_x(R_X1, R_X1, 8)
        h -= 1
      if b.slot < 7
        @a.sub_i(R_X1, R_X1, 4)
        @a.ldr_x(dst, R_X1, (b.slot + 1) * 8 + 8)
      else
        @a.mov_imm64(R_X2, wvalue_bits(b.slot) ## i64)
        call_rt(RT_ENV_GET)
        @a.mov_r(dst, R_X0) if dst != R_X0
      return nil
    if b.kind == :this
      @a.ldr_x(dst, R_SP, JF_SLOT_THIS)
      return nil
    load_slot_any(dst, b.lidx)
    nil

  # ---- Binary Operators (fast i32 -> fast f64 -> inline WValue number -> slow call) ----

  -> gen_binary_any(e)
    op = e.str
    if op == "<" || op == "<=" || op == ">" || op == ">=" || op == "===" || op == "!=="
      l_t = @a.new_label
      l_end = @a.new_label
      gen_cond_branch(e, l_t, true)
      @a.movz_x(R_X0, 1)   # false
      @a.b(l_end)
      @a.bind(l_t)
      @a.movz_x(R_X0, 2)   # true
      @a.bind(l_end)
      return nil
    if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || (op == "%" && can_i32?(e))
      gen_expr_i32(e)
      emit_box_i32(R_X0, R_X0)
      return nil
    # Fast exact 64-bit integer `(a * K + b) % M` when a, b are i32 and M > 0 int32 literal!
    # Because |a * K + b| < 2^52 (exact in IEEE double AND never overflows i64!), udiv_x + msub_x is 100% exact!
    if op == "%" && e.b.kind == :num && jit_int32_lit?(e.b) && e.b.a.to_i > 0
      if e.a.kind == :binary && e.a.str == "+" && e.a.a.kind == :binary && e.a.a.str == "*" && can_i32?(e.a.a.a) && jit_small_int_lit?(e.a.a.b, 1048576) && can_i32?(e.a.b)
        mv = e.b.a.to_i
        kv = e.a.a.b.a.to_i
        ra = peek_i32_reg(e.a.a.a)
        rb = peek_i32_reg(e.a.b)
        if ra != nil
          @a.sxtw(R_X9, ra)
        else
          gen_expr_i32(e.a.a.a)
          @a.sxtw(R_X9, R_X0)
        if rb != nil
          @a.sxtw(R_X10, rb)
        else
          push_x(R_X9)
          gen_expr_i32(e.a.b)
          @a.sxtw(R_X10, R_X0)
          pop_x(R_X9)
        @a.mov_imm64(R_X11, kv)
        @a.madd_x(R_X9, R_X9, R_X11, R_X10)     # x9 = a * K + b (exact 64-bit signed!)
        if mv >= 2 && mv <= 32767
          l_sdiv = @a.new_label
          l_mdone = @a.new_label
          @a.lsr_xi(R_X10, R_X9, 31)
          @a.cbnz_x(R_X10, l_sdiv)              # out of [0, 2^31) -> exact 64-bit sdiv cold stub
          emit_mod_const_u31(R_X0, R_X9, mv)
          @a.bind(l_mdone)
          cb = ->()
            @a.bind(l_sdiv)
            @a.mov_imm64(R_X10, mv)
            @a.sdiv_x(R_X11, R_X9, R_X10)
            @a.msub_x(R_X0, R_X11, R_X10, R_X9)
            @a.b(l_mdone)
          add_cold_stub(cb)
        else
          @a.mov_imm64(R_X10, mv)
          @a.sdiv_x(R_X11, R_X9, R_X10)
          @a.msub_x(R_X0, R_X11, R_X10, R_X9)   # x0 = (a*K + b) % M (signed, fits in i32!)
        emit_box_i32(R_X0, R_X0)
        return nil
    if can_f64?(e)
      gen_expr_f64(e)
      emit_box_f64(R_X0, R_D0)
      return nil
    # General boxed binary with inline number fast path (zero stack spills for reg/num leaves!)
    if op == "+" || op == "-" || op == "*" || op == "/"
      # Fast `x * 2` directly on boxed number (zero stack spill, 1-cycle fadd, 100% IEEE-754 exact!)
      if op == "*" && e.b.kind == :num && e.b.a == ~2.0
        gen_expr_any(e.a)
        l_slow = @a.new_label
        l_done = @a.new_label
        @a.sub_r(R_X9, R_X0, R_X20)
        @a.cmp_r(R_X9, R_X21)
        @a.b_cond(CC_HS, l_slow)
        @a.fmov_d_x(R_D0, R_X9)
        @a.fadd_d(R_D0, R_D0, R_D0)
        emit_box_f64_nonan(R_X0, R_D0)
        @a.bind(l_done)
        cb = ->()
          @a.bind(l_slow)
          @a.mov_r(R_X1, R_X0)
          @a.mov_imm64(R_X2, wvalue_bits(~2.0) ## i64)
          call_rt(RT_MUL)
          @a.b(l_done)
        add_cold_stub(cb)
        return nil
      # Fast inline ARM64 1-char ASCII string literal + non-neg i32 (`"k" + (i % 5000)`, `"k" + j` -> ZERO calls!)
      if op == "+" && e.a.kind == :string && e.a.str.ascii? && e.a.str.size == 1 && can_i32?(e.b)
        pre_s = e.a.str
        ch = pre_s.byte_at(0)
        jit_keep(pre_s)
        gen_expr_i32(e.b)
        l_cat_slow = @a.new_label
        l_cat_done = @a.new_label
        l_d2 = @a.new_label
        l_d3 = @a.new_label
        l_d4 = @a.new_label
        @a.mov_imm32(R_X9, 10000)
        @a.cmp_w(R_X0, R_X9)
        @a.b_cond(CC_HS, l_cat_slow)       # negative or >= 10000 -> cold stub!
        # Base prefix: 0xFFF9_0000_0000_0000 | (ch << 4)
        @a.movz_x(R_X9, ch << 4)
        @a.movk_x(R_X9, 0xFFF9, 3)
        @a.cmp_wi(R_X0, 10)
        @a.b_cond(CC_GE, l_d2)
        # 1 digit (0..9): total len = 2 (len<<1 = 4)
        @a.add_wi(R_X10, R_X0, 48)
        @a.lsl_xi(R_X10, R_X10, 12)
        @a.movz_x(R_X11, 4)
        @a.orr_r(R_X0, R_X9, R_X11)
        @a.orr_r(R_X0, R_X0, R_X10)
        @a.b(l_cat_done)
        # 2 digits (10..99): total len = 3 (len<<1 = 6)
        @a.bind(l_d2)
        @a.cmp_wi(R_X0, 100)
        @a.b_cond(CC_GE, l_d3)
        @a.movz_x(R_X11, 52429)
        @a.mul_w(R_X10, R_X0, R_X11)
        @a.lsr_xi(R_X10, R_X10, 19)        # q = x / 10
        @a.movz_x(R_X11, 10)
        @a.mul_w(R_X11, R_X10, R_X11)
        @a.sub_w(R_X11, R_X0, R_X11)       # r = x - 10 * q
        @a.add_wi(R_X10, R_X10, 48)
        @a.add_wi(R_X11, R_X11, 48)
        @a.lsl_xi(R_X10, R_X10, 12)
        @a.lsl_xi(R_X11, R_X11, 20)
        @a.orr_r(R_X10, R_X10, R_X11)
        @a.movz_x(R_X11, 6)
        @a.orr_r(R_X0, R_X9, R_X11)
        @a.orr_r(R_X0, R_X0, R_X10)
        @a.b(l_cat_done)
        # 3 digits (100..999): total len = 4 (len<<1 = 8)
        @a.bind(l_d3)
        @a.cmp_wi(R_X0, 1000)
        @a.b_cond(CC_GE, l_d4)
        @a.movz_x(R_X11, 41944)
        @a.mul_w(R_X12, R_X0, R_X11)
        @a.lsr_xi(R_X12, R_X12, 22)        # q0 = x / 100 (exact 0..999)
        @a.movz_x(R_X11, 100)
        @a.mul_w(R_X11, R_X12, R_X11)
        @a.sub_w(R_X13, R_X0, R_X11)       # rem = x - 100 * q0
        @a.movz_x(R_X11, 52429)
        @a.mul_w(R_X10, R_X13, R_X11)
        @a.lsr_xi(R_X10, R_X10, 19)        # q1 = rem / 10
        @a.movz_x(R_X11, 10)
        @a.mul_w(R_X11, R_X10, R_X11)
        @a.sub_w(R_X11, R_X13, R_X11)      # r = rem - 10 * q1
        @a.add_wi(R_X12, R_X12, 48)
        @a.add_wi(R_X10, R_X10, 48)
        @a.add_wi(R_X11, R_X11, 48)
        @a.lsl_xi(R_X12, R_X12, 12)
        @a.lsl_xi(R_X10, R_X10, 20)
        @a.lsl_xi(R_X11, R_X11, 28)
        @a.orr_r(R_X10, R_X10, R_X12)
        @a.orr_r(R_X10, R_X10, R_X11)
        @a.movz_x(R_X11, 8)
        @a.orr_r(R_X0, R_X9, R_X11)
        @a.orr_r(R_X0, R_X0, R_X10)
        @a.b(l_cat_done)
        # 4 digits (1000..9999): total len = 5 (len<<1 = 10)
        @a.bind(l_d4)
        @a.movz_x(R_X11, 33555)
        @a.mul_w(R_X14, R_X0, R_X11)
        @a.lsr_xi(R_X14, R_X14, 25)        # q0 = x / 1000 (exact 0..9999)
        @a.movz_x(R_X11, 1000)
        @a.mul_w(R_X11, R_X14, R_X11)
        @a.sub_w(R_X15, R_X0, R_X11)       # rem1 = x - 1000 * q0
        @a.movz_x(R_X11, 41944)
        @a.mul_w(R_X12, R_X15, R_X11)
        @a.lsr_xi(R_X12, R_X12, 22)        # q1 = rem1 / 100
        @a.movz_x(R_X11, 100)
        @a.mul_w(R_X11, R_X12, R_X11)
        @a.sub_w(R_X13, R_X15, R_X11)      # rem2 = rem1 - 100 * q1
        @a.movz_x(R_X11, 52429)
        @a.mul_w(R_X10, R_X13, R_X11)
        @a.lsr_xi(R_X10, R_X10, 19)        # q2 = rem2 / 10
        @a.movz_x(R_X11, 10)
        @a.mul_w(R_X11, R_X10, R_X11)
        @a.sub_w(R_X11, R_X13, R_X11)      # r = rem2 - 10 * q2
        @a.add_wi(R_X14, R_X14, 48)
        @a.add_wi(R_X12, R_X12, 48)
        @a.add_wi(R_X10, R_X10, 48)
        @a.add_wi(R_X11, R_X11, 48)
        @a.lsl_xi(R_X14, R_X14, 12)
        @a.lsl_xi(R_X12, R_X12, 20)
        @a.lsl_xi(R_X10, R_X10, 28)
        @a.lsl_xi(R_X11, R_X11, 36)
        @a.orr_r(R_X10, R_X10, R_X14)
        @a.orr_r(R_X10, R_X10, R_X12)
        @a.orr_r(R_X10, R_X10, R_X11)
        @a.movz_x(R_X11, 10)
        @a.orr_r(R_X0, R_X9, R_X11)
        @a.orr_r(R_X0, R_X0, R_X10)
        @a.bind(l_cat_done)
        cb_cat = ->()
          @a.bind(l_cat_slow)
          @a.sxtw(R_X2, R_X0)
          @a.movk_x(R_X2, 0xFFFA, 3)
          @a.mov_imm64(R_X1, wvalue_bits(pre_s) ## i64)
          call_rt(RT_STR_CAT_INT)
          @a.b(l_cat_done)
        add_cold_stub(cb_cat)
        return nil
      # Fast short ASCII string literal + exact i32 (`"ab" + i` -> zero-alloc inline WString via RT!)
      if op == "+" && e.a.kind == :string && e.a.str.ascii? && e.a.str.size <= 4 && can_i32?(e.b)
        pre_s = e.a.str
        jit_keep(pre_s)
        gen_expr_i32(e.b)
        @a.sxtw(R_X2, R_X0)
        @a.movk_x(R_X2, 0xFFFA, 3)
        @a.mov_imm64(R_X1, wvalue_bits(pre_s) ## i64)
        call_rt(RT_STR_CAT_INT)
        return nil
      # Zero-spill when right operand is a register-resident inline param or num literal!
      rb_x = (e.b.kind == :ident && @inline_env != nil && e.b.x != nil && @inline_env[e.b.x.binding] != nil && @inline_env[e.b.x.binding][0] == :reg_x) ? @inline_env[e.b.x.binding][1] : nil
      if rb_x != nil
        gen_expr_any(e.a)
        @a.mov_r(R_X1, R_X0)
        @a.mov_r(R_X2, rb_x)
      elsif e.b.kind == :num
        gen_expr_any(e.a)
        @a.mov_r(R_X1, R_X0)
        @a.mov_imm64(R_X2, wvalue_bits(e.b.a) ## i64)
      else
        gen_expr_any(e.a)
        push_x(R_X0)
        gen_expr_any(e.b)
        @a.mov_r(R_X2, R_X0)
        pop_x(R_X1)
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.sub_r(R_X9, R_X1, R_X20)
      @a.cmp_r(R_X9, R_X21)
      @a.b_cond(CC_HS, l_slow)
      @a.sub_r(R_X10, R_X2, R_X20)
      @a.cmp_r(R_X10, R_X21)
      @a.b_cond(CC_HS, l_slow)
      @a.fmov_d_x(R_D0, R_X9)
      @a.fmov_d_x(R_D1, R_X10)
      if op == "+"
        @a.fadd_d(R_D0, R_D0, R_D1)
      elsif op == "-"
        @a.fsub_d(R_D0, R_D0, R_D1)
      elsif op == "*"
        @a.fmul_d(R_D0, R_D0, R_D1)
      else
        @a.fdiv_d(R_D0, R_D0, R_D1)
      emit_box_f64_nonan(R_X0, R_D0)
      @a.bind(l_done)
      rt = op == "+" ? RT_ADD : (op == "-" ? RT_SUB : (op == "*" ? RT_MUL : RT_DIV))
      cb = ->()
        @a.bind(l_slow)
        call_rt(rt)
        @a.b(l_done)
      add_cold_stub(cb)
      return nil
    gen_expr_any(e.a)
    push_x(R_X0)
    gen_expr_any(e.b)
    @a.mov_r(R_X2, R_X0)
    pop_x(R_X1)
    rt = op == "%" ? RT_MOD : (op == "==" ? RT_EQ : (op == "!=" ? RT_EQ : (op == ">>>" ? RT_SHR : (op == "in" ? RT_IN : RT_INSTANCEOF))))
    call_rt(rt)
    if op == "!="
      # Flip 1 <-> 2
      @a.movz_x(R_X9, 3)
      @a.eor_r(R_X0, R_X0, R_X9)
    nil

  -> gen_unary_any(e)
    op = e.str
    if op == "!"
      l_t = @a.new_label
      l_end = @a.new_label
      gen_cond_branch(e.a, l_t, false)
      @a.movz_x(R_X0, 1)
      @a.b(l_end)
      @a.bind(l_t)
      @a.movz_x(R_X0, 2)
      @a.bind(l_end)
      return nil
    if op == "~"
      gen_expr_i32(e)
      emit_box_i32(R_X0, R_X0)
      return nil
    if op == "-" && can_f64?(e.a)
      gen_expr_f64(e.a)
      @a.fneg_d(R_D0, R_D0)
      emit_box_f64(R_X0, R_D0)
      return nil
    if op == "void"
      gen_expr_void(e.a)
      @a.movz_x(R_X0, 0)
      return nil
    if op == "typeof" && e.a.kind == :ident && e.a.x != nil && e.a.x.binding != nil && e.a.x.binding.global?
      c = wk_cell(e.a.x.binding)
      jit_keep(c)
      @a.mov_imm64(R_X1, wvalue_bits(c) ## i64)
      call_rt(RT_GTYPEOF)
      return nil
    gen_expr_any(e.a)
    @a.mov_r(R_X1, R_X0)
    call_rt(op == "-" ? RT_NEG : (op == "+" ? RT_PLUS : RT_TYPEOF))
    nil

  -> gen_update_any(e)
    t = e.a
    inc = e.str == "++"
    pre = e.has?(F_PREFIX)
    if t.kind == :ident
      li = local_idx(t)
      if li >= 0 && @info.types[li] == JT_I32
        load_slot_i32(R_X9, li)
        if inc
          @a.adds_wi(R_X10, R_X9, 1)
        else
          @a.subs_wi(R_X10, R_X9, 1)
        @a.b_cond(CC_VS, @l_deopt)
        store_slot_i32(li, R_X10)
        emit_box_i32(R_X0, pre ? R_X10 : R_X9)
        return nil
      emit_read_binding_any(t.x.binding, R_X1, t.x)
      call_rt(RT_TONUMERIC)
      push_x(R_X0)
      @a.mov_r(R_X1, R_X0)
      @a.movz_x(R_X2, inc ? 2 : 1)
      call_rt(RT_INC)
      emit_write_binding(t.x.binding, R_X0, false, t.x)
      pop_x(R_X9)
      @a.mov_r(R_X0, R_X9) if !pre
      return nil
    # Fallback for member updates
    gen_expr_any(t.a)
    push_x(R_X0)
    gen_member_get_any(t)
    @a.mov_r(R_X1, R_X0)
    call_rt(RT_TONUMERIC)
    push_x(R_X0)
    @a.mov_r(R_X1, R_X0)
    @a.movz_x(R_X2, inc ? 2 : 1)
    call_rt(RT_INC)
    pop_x(R_X10)   # old
    pop_x(R_X9)    # obj
    push_x(pre ? R_X0 : R_X10)
    @a.mov_r(R_X3, R_X0)
    @a.mov_r(R_X1, R_X9)
    if t.has?(F_COMPUTED)
      push_x(R_X1)
      push_x(R_X3)
      gen_expr_any(t.b)
      @a.mov_r(R_X2, R_X0)
      pop_x(R_X3)
      pop_x(R_X1)
    else
      jit_keep(t.b.str)
      @a.mov_imm64(R_X2, wvalue_bits(t.b.str) ## i64)
    @a.movz_x(R_X4, @jf.strict ? 2 : 1)
    call_rt(RT_SETV)
    pop_x(R_X0)
    nil

  -> gen_logical_any(e)
    l_end = @a.new_label
    gen_expr_any(e.a)
    if e.str == "&&" || e.str == "||"
      l_eval_b = @a.new_label
      off = push_x(R_X0)
      emit_truthy_branch(R_X0, l_eval_b, e.str == "&&")
      @a.ldr_x(R_X0, R_SP, off)
      @a.b(l_end)
      @a.bind(l_eval_b)
      @tmp_depth -= 1
      gen_expr_any(e.b)
    else
      # ??
      l_rhs = @a.new_label
      @a.cbz_x(R_X0, l_rhs)
      @a.ldr_x(R_X9, R_X19, RT_K_NULL_BITS * 8)
      @a.cmp_r(R_X0, R_X9)
      @a.b_cond(CC_EQ, l_rhs)
      @a.b(l_end)
      @a.bind(l_rhs)
      gen_expr_any(e.b)
    @a.bind(l_end)
    nil

  # ---- Assignments (including Fast Object Field Compound Assign `a.vx -= ...` & TypedArray Stores!) ----

  -> gen_assign_any(e)
    op = e.str
    t = e.a
    if t.kind == :ident
      b = t.x.binding
      if op == "="
        emit_assign_to_binding(b, e.b, false)
        if !b.global? && b.slot < 0 && b.scope.func == @jf
          load_slot_any(R_X0, b.lidx) if @info.types[b.lidx] != JT_SRA_OBJ && @info.types[b.lidx] != JT_SRA_CLOS && @info.types[b.lidx] != JT_SRA_RX
        return nil
      # Compound ident assign
      li = local_idx(t)
      if li >= 0 && @info.types[li] == JT_F64 && (op == "+=" || op == "-=" || op == "*=" || op == "/=")
        gen_expr_f64(e.b)
        load_slot_f64(R_D1, li)
        if op == "+="
          @a.fadd_d(R_D0, R_D1, R_D0)
        elsif op == "-="
          @a.fsub_d(R_D0, R_D1, R_D0)
        elsif op == "*="
          @a.fmul_d(R_D0, R_D1, R_D0)
        else
          @a.fdiv_d(R_D0, R_D1, R_D0)
        store_slot_f64(li, R_D0)
        emit_box_f64(R_X0, R_D0)
        return nil
      emit_read_binding_any(b, R_X0, t.x)
      push_x(R_X0)
      gen_expr_any(e.b)
      @a.mov_r(R_X2, R_X0)
      pop_x(R_X1)
      bop = op.slice(0, op.size - 1)
      rt = bop == "+" ? RT_ADD : (bop == "-" ? RT_SUB : (bop == "*" ? RT_MUL : (bop == "/" ? RT_DIV : (bop == "%" ? RT_MOD : (bop == "|" ? RT_BITOR : (bop == "&" ? RT_BITAND : (bop == "^" ? RT_BITXOR : (bop == "<<" ? RT_SHL : (bop == ">>" ? RT_SAR : RT_SHR)))))))))
      call_rt(rt)
      emit_write_binding(b, R_X0, false, t.x)
      return nil
    if t.kind == :member
      # Scalar-replaced object field write!
      if !t.has?(F_COMPUTED)
        bli = local_idx(t.a)
        if bli >= 0 && @info.sra_objs[bli] != nil
          vs = @info.sra_objs[bli].field_slots[t.b.str]
          if vs != nil
            if op == "="
              emit_store_expr_to_slot(vs, e.b)
              load_slot_any(R_X0, vs)
              return nil
      # Hoisted TypedArray element write `a[i] = val`!
      if t.has?(F_COMPUTED) && op == "="
        bli = local_idx(t.a)
        if bli >= 0 && @hoisted_tas[bli] != nil
          gen_ta_store(bli, t.b, e.b)
          return nil
      # Named property write `o.prop = v` or `o.prop += v` / `-= v` (CRITICAL for float_math!)
      if !t.has?(F_COMPUTED)
        gen_member_set_named(t, op, e.b)
        return nil
      # General computed member write `o[k] = v`
      gen_expr_any(t.a)
      push_x(R_X0)
      gen_expr_any(t.b)
      push_x(R_X0)
      if op == "="
        gen_expr_any(e.b)
        @a.mov_r(R_X3, R_X0)
        pop_x(R_X2)
        pop_x(R_X1)
      else
        # Reload obj & key from top of tmp stack
        @a.ldr_x(R_X2, R_SP, @tmp_base + (@tmp_depth - 1) * 8)
        @a.ldr_x(R_X1, R_SP, @tmp_base + (@tmp_depth - 2) * 8)
        call_rt(RT_GETV)
        push_x(R_X0)
        gen_expr_any(e.b)
        @a.mov_r(R_X2, R_X0)
        pop_x(R_X1)
        bop = op.slice(0, op.size - 1)
        call_rt(bop == "+" ? RT_ADD : (bop == "-" ? RT_SUB : (bop == "*" ? RT_MUL : (bop == "/" ? RT_DIV : (bop == "%" ? RT_MOD : (bop == "|" ? RT_BITOR : (bop == "&" ? RT_BITAND : (bop == "^" ? RT_BITXOR : (bop == "<<" ? RT_SHL : (bop == ">>" ? RT_SAR : RT_SHR))))))))))
        @a.mov_r(R_X3, R_X0)
        pop_x(R_X2)
        pop_x(R_X1)
      @a.movz_x(R_X4, @jf.strict ? 2 : 1)
      call_rt(RT_SETV)
      return nil
    @a.movz_x(R_X0, 0)
    nil

  -> gen_ta_store(bli, idx_e, val_e, need_val = true)
    h = @hoisted_tas[bli]
    kind = h[2]
    tr = @hoisted_ta_regs[bli]
    r_idx = peek_i32_reg(idx_e)
    skip_bc = ta_idx_bounded?(bli, idx_e)
    if r_idx == nil
      gen_ta_index(idx_e)
      push_w(R_X0)
    if kind == 8 || kind == 7
      gen_expr_f64(val_e)
      if r_idx != nil
        @a.sxtw(R_X11, r_idx)
      else
        pop_w(R_X11)
        @a.sxtw(R_X11, R_X11)
      r_ptr = (tr != nil && tr[0] != nil) ? tr[0] : R_X9
      @a.ldr_x(R_X9, R_SP, h[0]) if r_ptr == R_X9
      l_oob = nil
      if !skip_bc
        if tr != nil && tr[1] != nil
          @a.cmp_r(R_X11, tr[1])
        else
          @a.ldr_x(R_X10, R_SP, h[1])
          @a.cmp_r(R_X11, R_X10)
        l_oob = @a.new_label
        @a.b_cond(CC_HS, l_oob)
      if kind == 8
        @a.str_d_idx(R_D0, r_ptr, R_X11)
      else
        @a.fcvt_s_d(R_D1, R_D0)
        @a.str_s_idx(R_D1, r_ptr, R_X11)
      @a.bind(l_oob) if l_oob != nil
      emit_box_f64(R_X0, R_D0) if need_val
      return nil
    if kind == 5 || kind == 6 || kind == 0 || kind == 1 || kind == 3 || kind == 4
      rv = peek_i32_reg(val_e)
      if rv == nil
        if val_e.kind == :num && jit_int32_lit?(val_e)
          @a.mov_imm32(R_X0, val_e.a.to_i)
        else
          gen_expr_to_i32(val_e)
        rv = R_X0
      if r_idx != nil
        @a.sxtw(R_X11, r_idx)
      else
        pop_w(R_X11)
        @a.sxtw(R_X11, R_X11)
      r_ptr = (tr != nil && tr[0] != nil) ? tr[0] : R_X9
      @a.ldr_x(R_X9, R_SP, h[0]) if r_ptr == R_X9
      l_oob = nil
      if !skip_bc
        if tr != nil && tr[1] != nil
          @a.cmp_r(R_X11, tr[1])
        else
          @a.ldr_x(R_X10, R_SP, h[1])
          @a.cmp_r(R_X11, R_X10)
        l_oob = @a.new_label
        @a.b_cond(CC_HS, l_oob)
      if kind == 5 || kind == 6
        @a.str_w_idx(rv, r_ptr, R_X11)
      elsif kind == 3 || kind == 4
        @a.strh_idx(rv, r_ptr, R_X11)
      else
        @a.strb_idx(rv, r_ptr, R_X11)
      @a.bind(l_oob) if l_oob != nil
      emit_box_i32(R_X0, rv) if need_val
      return nil
    # Fallback for other TA kinds (e.g. Uint8ClampedArray rounding semantics)
    gen_expr_any(val_e)
    @a.mov_r(R_X3, R_X0)
    if r_idx != nil
      @a.mov_w(R_X11, r_idx)
    else
      pop_w(R_X11)
    emit_box_i32(R_X2, R_X11)
    load_slot_any(R_X1, bli)
    @a.movz_x(R_X4, @jf.strict ? 2 : 1)
    call_rt(RT_SETV)
    nil

  # ---- Named Property Get & Set with Inline Cache + Redundant Shape Guard Elimination! ----

  # Emit inline-cached property load of `key` on object in `obj_reg` -> result in `R_X0`.
  # Uses `node_ic` (pre-warmed by tier 0 if OSR, or fresh `i64[4]`).
  # If `bli >= 0` and `@known_shapes[bli]` already verified the exact shape of `obj_reg`
  # in this basic block, skips BOTH the instance check AND the shape check!
  -> emit_ic_get(obj_reg, key, node_ic, bli)
    jit_keep(key)
    jit_keep(node_ic)
    # Fast specialization: if node_ic is already warm with an own property (ic[0] != 0 && ic[2] == 0)!
    sh_warm = node_ic[0]
    sl_warm = node_ic[1]
    h_warm  = node_ic[2]
    if sh_warm != 0 && h_warm == 0 && sl_warm != 0
      # Check if we ALREADY verified this exact shape for local `bli`!
      if bli >= 0 && @known_shapes[bli] == sh_warm
        @a.sub_i(R_X9, obj_reg, 4)
        emit_slot_load(R_X0, R_X9, sl_warm)
        return nil
      # Guard instance + shape == sh_warm (5 instructions), then direct slot load!
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.sub_i(R_X9, obj_reg, 4)
      @a.tst_x_lowmask(R_X9, 4)
      @a.b_cond(CC_NE, l_slow)
      @a.lsr_xi(R_X10, R_X9, 48)
      @a.cbnz_x(R_X10, l_slow)
      @a.cbz_x(R_X9, l_slow)
      @a.ldr_x(R_X10, R_X9, 8)         # @shape
      @a.mov_imm64(R_X11, sh_warm)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
      emit_slot_load(R_X0, R_X9, sl_warm)
      @a.b(l_done)
      @a.bind(l_slow)
      @a.mov_r(R_X1, obj_reg)
      @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
      @a.mov_imm64(R_X3, wvalue_bits(node_ic) ## i64)
      @a.mov_imm64(R_X4, wvalue_bits(0) ## i64)
      call_rt(RT_GETP_MISS)
      @a.bind(l_done)
      return nil
    # Fast specialization for 2-shape polymorphic own-property hit (`ic[2] = old_shape | 1`, `ic[3] = old_slot`)!
    if sh_warm != 0 && (h_warm & 1) != 0 && sl_warm != 0 && node_ic[3] != 0
      sh2 = h_warm ^ 1
      sl2 = node_ic[3]
      l_chk2 = @a.new_label
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.sub_i(R_X9, obj_reg, 4)
      @a.tst_wobj_bad(R_X9)
      @a.b_cond(CC_NE, l_slow)
      @a.cbz_x(R_X9, l_slow)
      @a.ldr_x(R_X10, R_X9, 8)
      @a.mov_imm64(R_X11, sh_warm)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_chk2)
      emit_slot_load(R_X0, R_X9, sl_warm)
      @a.b(l_done)
      @a.bind(l_chk2)
      @a.mov_imm64(R_X11, sh2)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
      emit_slot_load(R_X0, R_X9, sl2)
      @a.bind(l_done)
      cb = ->()
        @a.bind(l_slow)
        @a.mov_r(R_X1, obj_reg)
        @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
        @a.mov_imm64(R_X3, wvalue_bits(node_ic) ## i64)
        @a.mov_imm64(R_X4, wvalue_bits(0) ## i64)
        call_rt(RT_GETP_MISS)
        @a.b(l_done)
      add_cold_stub(cb)
      return nil
    # Fast specialization for warm prototype-chain hit (`ic[0] != 0 && ic[2] != 0 && (ic[2] & 1) == 0 && ic[1] != 0`)!
    if sh_warm != 0 && h_warm != 0 && (h_warm & 1) == 0 && sl_warm != 0 && node_ic[3] == JS_EPOCH[0]
      l_slow = @a.new_label
      l_done = @a.new_label
      if !@hoisted_epoch
        ep_now = JS_EPOCH[0]
        @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
        @a.ldr_x(R_X10, R_X9, 0)
        @a.mov_imm64(R_X11, ep_now)
        @a.cmp_r(R_X10, R_X11)
        @a.b_cond(CC_NE, l_slow)
      @a.sub_i(R_X9, obj_reg, 4)
      @a.tst_wobj_bad(R_X9)
      @a.b_cond(CC_NE, l_slow)
      @a.cbz_x(R_X9, l_slow)
      @a.ldr_x(R_X10, R_X9, 8)
      @a.mov_imm64(R_X11, sh_warm)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
      @a.mov_imm64(R_X9, h_warm - 4)
      emit_slot_load(R_X0, R_X9, sl_warm)
      @a.bind(l_done)
      cb = ->()
        @a.bind(l_slow)
        @a.mov_r(R_X1, obj_reg)
        @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
        @a.mov_imm64(R_X3, wvalue_bits(node_ic) ## i64)
        @a.mov_imm64(R_X4, wvalue_bits(0) ## i64)
        call_rt(RT_GETP_MISS)
        @a.b(l_done)
      add_cold_stub(cb)
      return nil
    # Generic dynamic IC lookup (reads node_ic[0..3] at runtime)
    ic_ptr = jit_i64_ptr(node_ic)
    l_slow = @a.new_label
    l_done = @a.new_label
    @a.sub_i(R_X9, obj_reg, 4)
    @a.tst_x_lowmask(R_X9, 4)
    @a.b_cond(CC_NE, l_slow)
    @a.lsr_xi(R_X10, R_X9, 48)
    @a.cbnz_x(R_X10, l_slow)
    @a.cbz_x(R_X9, l_slow)
    @a.ldr_x(R_X10, R_X9, 8)           # obj.@shape
    @a.mov_imm64(R_X11, ic_ptr)
    @a.ldr_x(R_X12, R_X11, 0)          # ic[0]
    @a.cmp_r(R_X10, R_X12)
    @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X12, R_X11, 16)         # ic[2] = holder
    @a.cbnz_x(R_X12, l_slow)           # proto hit -> slow (or handled below)
    @a.ldr_x(R_X12, R_X11, 8)          # ic[1] = slot_enc
    @a.cmp_i(R_X12, 0)
    @a.b_cond(CC_LE, l_slow)           # <= 0 -> overflow/miss -> slow
    @a.add_i(R_X12, R_X12, 1)          # offset in 8-byte words = ivar + 1
    @a.ldr_x_idx(R_X0, R_X9, R_X12)    # [obj_ptr + (ivar+1)*8]
    @a.b(l_done)
    @a.bind(l_slow)
    @a.mov_r(R_X1, obj_reg)
    @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
    @a.mov_imm64(R_X3, wvalue_bits(node_ic) ## i64)
    @a.mov_imm64(R_X4, wvalue_bits(0) ## i64)
    call_rt(RT_GETP_MISS)
    @a.bind(l_done)
    nil

  # Load slot `sl_enc` from unmasked `WObject*` in `ptr_reg` -> `dst`.
  # sl_enc > 0: inline ivar `sl_enc` at offset `(sl_enc + 1) * 8`.
  # sl_enc < 0: overflow `@ext[(-sl_enc) - 1]`.
  -> emit_slot_load(dst, ptr_reg, sl_enc)
    if sl_enc > 0
      @a.ldr_x(dst, ptr_reg, (sl_enc + 1) * 8)
    else
      ext_idx = (0 - sl_enc) - 1
      @a.ldr_x(R_X14, ptr_reg, 16)          # @ext WArray WValue
      @a.and_x_ptr47(R_X14, R_X14)    # WArray*
      @a.ldr_x(R_X14, R_X14, 16)            # slots ptr
      @a.ldr_x(dst, R_X14, ext_idx * 8)
    nil

  # Store `val_reg` into slot `sl_enc` of unmasked `WObject*` in `ptr_reg`.
  -> emit_slot_store(ptr_reg, sl_enc, val_reg)
    if sl_enc > 0
      @a.str_x(val_reg, ptr_reg, (sl_enc + 1) * 8)
    else
      ext_idx = (0 - sl_enc) - 1
      @a.ldr_x(R_X14, ptr_reg, 16)
      @a.and_x_ptr47(R_X14, R_X14)
      @a.ldr_x(R_X14, R_X14, 16)
      @a.str_x(val_reg, R_X14, ext_idx * 8)
    nil

  -> gen_member_get_any(e)
    # 1. Scalar-replaced object field read!
    if !e.has?(F_COMPUTED)
      bli = local_idx(e.a)
      if bli >= 0 && @info.sra_objs[bli] != nil
        vs = @info.sra_objs[bli].field_slots[e.b.str]
        if vs != nil
          load_slot_any(R_X0, vs)
          return nil
      # 2. `.length` on a hoisted dense Array, TypedArray, or flat String!
      if e.b.str == "length"
        if bli >= 0 && @hoisted_arrs[bli] != nil
          @a.ldr_x(R_X9, R_SP, @hoisted_arrs[bli][1])
          emit_box_i32(R_X0, R_X9)
          return nil
        if bli >= 0 && @hoisted_tas[bli] != nil
          @a.ldr_x(R_X9, R_SP, @hoisted_tas[bli][1])
          emit_box_i32(R_X0, R_X9)
          return nil
        # Fast flat-String `.length` (avoids RT_GETP_MISS overhead!)
        gen_expr_any(e.a)
        @a.mov_r(R_X13, R_X0)
        l_not_str = @a.new_label
        l_len_done = @a.new_label
        @a.lsr_xi(R_X9, R_X13, 48)
        @a.movz_x(R_X10, 0xFFF9)
        @a.cmp_r(R_X9, R_X10)
        @a.b_cond(CC_NE, l_not_str)
        @a.tst_x_lowmask(R_X13, 1)
        @a.b_cond(CC_NE, l_not_str)
        @a.mov_r(R_X1, R_X13)
        call_rt(RT_STR_LEN)
        @a.bind(l_len_done)
        node_ic = wk_ic(e)
        cb = ->()
          @a.bind(l_not_str)
          emit_ic_get(R_X13, "length", node_ic, -1)
          @a.b(l_len_done)
        add_cold_stub(cb)
        return nil
      # 3. Inline-cached named property read!
      node_ic = wk_ic(e)
      if bli >= 0 && @info.types[bli] == JT_ANY && @info.reg_gpr[bli] != nil
        emit_ic_get(@info.reg_gpr[bli], e.b.str, node_ic, bli)
        return nil
      gen_expr_any(e.a)
      @a.mov_r(R_X13, R_X0)
      emit_ic_get(R_X13, e.b.str, node_ic, -1)
      return nil
    # Computed element access `o[idx]`
    bli = local_idx(e.a)
    # 4. Hoisted TypedArray element load!
    if bli >= 0 && @hoisted_tas[bli] != nil
      gen_ta_load_f64(bli, e.b)
      emit_box_f64(R_X0, R_D0)
      return nil
    # 5. Hoisted dense Array element load `shapes[j]` or `bodies[i]`!
    if bli >= 0 && @hoisted_arrs[bli] != nil && can_i32?(e.b)
      ar = @hoisted_arr_regs[bli]
      r_sl = (ar != nil && ar[0] != nil) ? ar[0] : R_X9
      r_idx = peek_i32_reg(e.b)
      if r_idx != nil
        @a.sxtw(R_X11, r_idx)
      else
        gen_expr_i32(e.b)                # w0 = idx (may clobber R_X9!)
        @a.sxtw(R_X11, R_X0)
      @a.ldr_x(R_X9, R_SP, @hoisted_arrs[bli][0]) if r_sl == R_X9
      idx_li = local_idx(e.b)
      if idx_li >= 0 && @bounded_idx[idx_li] == bli
        # Bounds-check eliminated (`0 <= idx < arr.length`): 1 SINGLE LDR!
        @a.ldr_x_idx(R_X0, r_sl, R_X11)
        return nil
      if ar != nil && ar[1] != nil
        @a.cmp_r(R_X11, ar[1])
      else
        @a.ldr_x(R_X10, R_SP, @hoisted_arrs[bli][1])  # len
        @a.cmp_r(R_X11, R_X10)
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.b_cond(CC_HS, l_slow)
      @a.ldr_x_idx(R_X0, r_sl, R_X11)
      @a.b(l_done)
      @a.bind(l_slow)
      emit_box_i32(R_X2, R_X11)
      load_slot_any(R_X1, bli)
      call_rt(RT_GETV)
      @a.bind(l_done)
      return nil
    # 6. Dynamic dense JS array fast path (e.g. `bodies[i]` inside `step(bodies, dt)`!)
    if can_i32?(e.b)
      gen_expr_any(e.a)
      push_x(R_X0)
      gen_expr_i32(e.b)                # w0 = idx
      @a.sxtw(R_X11, R_X0)
      pop_x(R_X13)                     # x13 = arr WValue
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.lsr_xi(R_X9, R_X13, 48)
      @a.movz_x(R_X10, 0xFFF4)
      @a.cmp_r(R_X9, R_X10)
      @a.b_cond(CC_NE, l_slow)
      @a.and_x_ptr47(R_X9, R_X13)
      @a.ldrb(R_X10, R_X9, 2)          # aflags
      @a.cmp_wi(R_X10, 1)              # JS_AF_ARRAY && no holes && no ext
      @a.b_cond(CC_NE, l_slow)
      @a.ldrsw(R_X10, R_X9, 8)         # size
      @a.cmp_r(R_X11, R_X10)
      @a.b_cond(CC_HS, l_slow)
      @a.ldrsw(R_X10, R_X9, 4)         # start
      @a.add_r(R_X11, R_X11, R_X10)
      @a.ldr_x(R_X9, R_X9, 16)         # slots
      @a.ldr_x_idx(R_X0, R_X9, R_X11)
      @a.b(l_done)
      @a.bind(l_slow)
      @a.mov_r(R_X1, R_X13)
      emit_box_i32(R_X2, R_X11)
      call_rt(RT_GETV)
      @a.bind(l_done)
      return nil
    # 7. General computed `o[k]`
    gen_expr_any(e.a)
    push_x(R_X0)
    gen_expr_any(e.b)
    @a.mov_r(R_X2, R_X0)
    pop_x(R_X1)
    call_rt(RT_GETV)
    nil

  -> emit_flush_promoted_rw(own_li, rw_ls)
    r_a = @info.reg_gpr[own_li]
    if r_a != nil
      @a.sub_i(R_X9, r_a, 4)
    else
      load_slot_any(R_X9, own_li)
      @a.sub_i(R_X9, R_X9, 4)
    rw_ls.each ->(fr)
      emit_box_f64(R_X12, fr[2])
      emit_slot_store(R_X9, fr[1], R_X12)
    nil

  # Named property write `o.prop = v` or `o.prop += v` / `-= v` (hot in float_math!)
  -> gen_member_set_named(t, op, rhs, need_val = true)
    key = t.b.str
    # Fast promoted writable field in inner loop (`a.vx -= ...` -> 1 single FP op!)
    if (op == "+=" || op == "-=" || op == "*=" || op == "/=") && @promoted_rw.size > 0 && can_f64?(rhs)
      bli_p = local_idx(t.a)
      dr_p = bli_p >= 0 ? @promoted_rw[bli_p.to_s + ":" + key] : nil
      if dr_p != nil
        gen_expr_f64(rhs)
        if op == "+="
          @a.fadd_d(dr_p, dr_p, R_D0)
        elsif op == "-="
          @a.fsub_d(dr_p, dr_p, R_D0)
        elsif op == "*="
          @a.fmul_d(dr_p, dr_p, R_D0)
        else
          @a.fdiv_d(dr_p, dr_p, R_D0)
        emit_box_f64_nonan(R_X0, dr_p) if need_val
        return nil
    node_ic = wk_ic(t)
    jit_keep(key)
    jit_keep(node_ic)
    sh_warm = node_ic[0]
    sl_warm = node_ic[1]
    ns_warm = node_ic[2]
    # Fast compound numeric update `a.vx -= expr` when IC is warm for an existing own slot!
    if (op == "+=" || op == "-=" || op == "*=" || op == "/=") && sh_warm != 0 && ns_warm == 0 && sl_warm != 0 && can_f64?(rhs)
      bli = local_idx(t.a)
      r_obj = (bli >= 0 && @info.types[bli] == JT_ANY) ? @info.reg_gpr[bli] : nil
      if r_obj != nil
        gen_expr_f64(rhs)
        @a.sub_i(R_X9, r_obj, 4)
      else
        gen_expr_any(t.a)
        push_x(R_X0)
        gen_expr_f64(rhs)        # d0 = rhs
        pop_x(R_X13)             # x13 = obj
        @a.sub_i(R_X9, R_X13, 4)
      if bli >= 0 && @known_shapes[bli] == sh_warm && @d_bias_reg != nil && sl_warm > 0 && @mono_arr_num[sh_warm] == true
        # Zero-tag-check, zero-FMOV pure SIMD FP read-modify-write!
        off = (sl_warm + 1) * 8
        @a.ldr_d(R_D1, R_X9, off)
        @a.sub_d_i64(R_D1, R_D1, @d_bias_reg)
        if op == "+="
          @a.fadd_d(R_D0, R_D1, R_D0)
        elsif op == "-="
          @a.fsub_d(R_D0, R_D1, R_D0)
        elsif op == "*="
          @a.fmul_d(R_D0, R_D1, R_D0)
        else
          @a.fdiv_d(R_D0, R_D1, R_D0)
        if !need_val
          @a.add_d_i64(R_D16, R_D0, @d_bias_reg)
          @a.str_d(R_D16, R_X9, off)
        else
          emit_box_f64_nonan(R_X0, R_D0)
          emit_slot_store(R_X9, sl_warm, R_X0)
        return nil
      l_slow = @a.new_label
      l_done = @a.new_label
      if !(bli >= 0 && @known_shapes[bli] == sh_warm)
        @a.tst_x_lowmask(R_X9, 4)
        @a.b_cond(CC_NE, l_slow)
        @a.lsr_xi(R_X10, R_X9, 48)
        @a.cbnz_x(R_X10, l_slow)
        @a.cbz_x(R_X9, l_slow)
        @a.ldr_x(R_X10, R_X9, 8)
        @a.mov_imm64(R_X11, sh_warm)
        @a.cmp_r(R_X10, R_X11)
        @a.b_cond(CC_NE, l_slow)
      emit_slot_load(R_X12, R_X9, sl_warm)
      emit_unbox_f64(R_D1, R_X12, l_slow)
      if op == "+="
        @a.fadd_d(R_D0, R_D1, R_D0)
      elsif op == "-="
        @a.fsub_d(R_D0, R_D1, R_D0)
      elsif op == "*="
        @a.fmul_d(R_D0, R_D1, R_D0)
      else
        @a.fdiv_d(R_D0, R_D1, R_D0)
      if !need_val && @d_bias_reg != nil && sl_warm > 0
        @a.add_d_i64(R_D16, R_D0, @d_bias_reg)
        @a.str_d(R_D16, R_X9, (sl_warm + 1) * 8)
      else
        emit_box_f64_nonan(R_X0, R_D0)
        emit_slot_store(R_X9, sl_warm, R_X0)
      @a.bind(l_done)
      nc_s = @next_prop_fp - R_D18
      prw_own = @promoted_owner
      prw_ls = @promoted_rw_list
      cb = ->()
        @a.bind(l_slow)
        @a.mov_r(R_X13, r_obj) if r_obj != nil
        if prw_own >= 0 && prw_ls != nil && prw_ls.size > 0
          emit_flush_promoted_rw(prw_own, prw_ls)
        if nc_s > 0
          ci = 0
          while ci < nc_s
            push_d(R_D18 + ci)
            ci += 1
        push_x(R_X13)
        emit_box_f64(R_X0, R_D0)
        push_x(R_X0)
        @a.mov_r(R_X1, R_X13)
        @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
        call_rt(RT_GETV)
        @a.mov_r(R_X1, R_X0)
        pop_x(R_X2)
        bop = op.slice(0, op.size - 1)
        call_rt(bop == "+" ? RT_ADD : (bop == "-" ? RT_SUB : (bop == "*" ? RT_MUL : (bop == "/" ? RT_DIV : (bop == "%" ? RT_MOD : (bop == "|" ? RT_BITOR : (bop == "&" ? RT_BITAND : (bop == "^" ? RT_BITXOR : (bop == "<<" ? RT_SHL : (bop == ">>" ? RT_SAR : RT_SHR))))))))))
        @a.mov_r(R_X3, R_X0)
        pop_x(R_X1)
        @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
        @a.mov_imm64(R_X4, wvalue_bits(node_ic) ## i64)
        @a.mov_imm64(R_X5, wvalue_bits(0) ## i64)
        @a.movz_x(R_X6, @jf.strict ? 2 : 1)
        call_rt(RT_SETP_MISS)
        @a.fmov_d_x(R_D17, R_X20) if @d_bias_reg == R_D17
        if nc_s > 0
          ci = nc_s - 1
          while ci >= 0
            pop_d(R_D18 + ci)
            ci -= 1
        @a.b(l_done)
      add_cold_stub(cb)
      return nil
    # Plain `o.prop = rhs` or general compound assign
    gen_expr_any(t.a)
    push_x(R_X0)
    if op == "="
      gen_expr_any(rhs)
    else
      @a.ldr_x(R_X1, R_SP, @tmp_base + (@tmp_depth - 1) * 8)
      @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
      call_rt(RT_GETV)
      push_x(R_X0)
      gen_expr_any(rhs)
      @a.mov_r(R_X2, R_X0)
      pop_x(R_X1)
      bop = op.slice(0, op.size - 1)
      call_rt(bop == "+" ? RT_ADD : (bop == "-" ? RT_SUB : (bop == "*" ? RT_MUL : (bop == "/" ? RT_DIV : (bop == "%" ? RT_MOD : (bop == "|" ? RT_BITOR : (bop == "&" ? RT_BITAND : (bop == "^" ? RT_BITXOR : (bop == "<<" ? RT_SHL : (bop == ">>" ? RT_SAR : RT_SHR))))))))))
    @a.mov_r(R_X12, R_X0)   # val
    pop_x(R_X13)            # obj
    # Fast inline-cached set for warm existing own slot or warm inline transition
    if sh_warm != 0 && ns_warm == 0 && sl_warm != 0
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.sub_i(R_X9, R_X13, 4)
      @a.tst_x_lowmask(R_X9, 4)
      @a.b_cond(CC_NE, l_slow)
      @a.lsr_xi(R_X10, R_X9, 48)
      @a.cbnz_x(R_X10, l_slow)
      @a.cbz_x(R_X9, l_slow)
      @a.ldr_x(R_X10, R_X9, 8)
      @a.mov_imm64(R_X11, sh_warm)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
      emit_slot_store(R_X9, sl_warm, R_X12)
      @a.mov_r(R_X0, R_X12)
      @a.b(l_done)
      @a.bind(l_slow)
      @a.mov_r(R_X1, R_X13)
      @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
      @a.mov_r(R_X3, R_X12)
      @a.mov_imm64(R_X4, wvalue_bits(node_ic) ## i64)
      @a.mov_imm64(R_X5, wvalue_bits(0) ## i64)
      @a.movz_x(R_X6, @jf.strict ? 2 : 1)
      call_rt(RT_SETP_MISS)
      @a.bind(l_done)
      return nil
    @a.mov_r(R_X1, R_X13)
    @a.mov_imm64(R_X2, wvalue_bits(key) ## i64)
    @a.mov_r(R_X3, R_X12)
    @a.mov_imm64(R_X4, wvalue_bits(node_ic) ## i64)
    @a.mov_imm64(R_X5, wvalue_bits(0) ## i64)
    @a.movz_x(R_X6, @jf.strict ? 2 : 1)
    call_rt(RT_SETP_MISS)
    nil

  # ---- Calls, Intrinsics, Polymorphic Inlining, & Array HOF Inlining ----

  -> gen_call_any(e)
    c = e.a
    # 1. Scalar-replaced closure call `f(a0, ...)`!
    if c.kind == :ident
      li = local_idx(c)
      if li >= 0 && @info.sra_clos[li] != nil
        sc = @info.sra_clos[li]
        if e.list.size == sc.inner_jf.params.size
          gen_sra_closure_call_any(sc, e.list)
          return nil

    # 2. Method calls `o.m(args)`
    if c.kind == :member && !c.has?(F_COMPUTED)
      mname = c.b.str
      # 2a. Math.* intrinsics
      if c.a.kind == :ident && c.a.str == "Math"
        if gen_math_f64(mname, e.list)
          emit_box_f64(R_X0, R_D0)
          return nil
        if mname == "round" && e.list.size == 1
          gen_expr_any(e.list[0])
          @a.mov_r(R_X1, R_X0)
          call_rt(RT_MATH_ROUND)
          return nil
      # 2b. `arr.push(x)` inline fast path (10 instructions, zero function calls!)
      if mname == "push" && e.list.size == 1
        gen_array_push_inline(c.a, e.list[0])
        return nil
      # 2b2. Guarded String/Array fast-call intrinsics (split, join, indexOf, slice, charCodeAt)!
      if (mname == "split" || mname == "indexOf" || mname == "charCodeAt") && e.list.size == 1
        rt_id = mname == "split" ? RT_STR_SPLIT_CH : (mname == "indexOf" ? RT_STR_INDEXOF : RT_STR_CHARCODE)
        gen_str_method_intrinsic(c.a, mname, e.list, rt_id)
        return nil
      if mname == "slice" && (e.list.size == 1 || e.list.size == 2)
        gen_str_method_intrinsic(c.a, mname, e.list, RT_STR_SLICE)
        return nil
      if mname == "join" && e.list.size <= 1
        gen_arr_join_intrinsic(c.a, e.list)
        return nil
      # 2b3. Guarded Map/Set fast-call intrinsics (get, set, add, has)!
      if mname == "get" && e.list.size == 1 && gen_coll_method_intrinsic(c.a, "get", e.list, :map, RT_MAP_GET)
        return nil
      if mname == "set" && e.list.size == 2 && gen_coll_method_intrinsic(c.a, "set", e.list, :map, RT_MAP_SET)
        return nil
      if mname == "add" && e.list.size == 1 && gen_coll_method_intrinsic(c.a, "add", e.list, :set, RT_SET_ADD)
        return nil
      if mname == "has" && e.list.size == 1 && gen_coll_method_intrinsic(c.a, "has", e.list, :both, RT_SET_HAS)
        return nil
      # 2b4. Guarded Promise.prototype.then & Promise.resolve intrinsics!
      if mname == "then" && (e.list.size == 1 || e.list.size == 2) && gen_prom_then_intrinsic(c.a, e.list)
        return nil
      if mname == "resolve" && e.list.size == 1 && c.a.kind == :ident && c.a.str == "Promise" && gen_prom_resolve_intrinsic(c.a, e.list[0])
        return nil
      # 2b5. Guarded String.prototype.replace & RegExp.prototype.exec intrinsics!
      if mname == "replace" && e.list.size == 2
        gen_str_method_intrinsic(c.a, "replace", e.list, RT_STR_REPLACE)
        return nil
      if mname == "exec" && e.list.size == 1 && gen_rx_exec_intrinsic(c.a, e.list[0])
        return nil
      # 2c. Inlined dense `arr.map(cb)`, `arr.filter(cb)`, `arr.reduce(cb, init)`!
      if (mname == "map" || mname == "filter" || mname == "reduce") && e.list.size >= 1
        cb_node = e.list[0]
        if (cb_node.kind == :function || cb_node.kind == :arrow) && cb_node.x.is_a?(JaFunc)
          cb_jf = cb_node.x
          if jit_inline_return_expr(cb_jf) != nil && cb_jf.free.size == 0 && !cb_jf.uses_this && cb_jf.params.size <= 3 && cb_jf.self_binding == nil
            if mname == "map" && e.list.size == 1
              gen_inline_array_map(c.a, cb_jf)
              return nil
            if mname == "filter" && e.list.size == 1
              gen_inline_array_filter(c.a, cb_jf)
              return nil
            if mname == "reduce" && e.list.size == 2
              gen_inline_array_reduce(c.a, cb_jf, e.list[1])
              return nil
      # 2d. Polymorphic method call inlining (`shapes[j].area()` with 1..4 observed shapes!)
      if e.x.is_a?(Array) && e.x.size >= 2 && e.list.size <= 2
        if gen_poly_method_inline(e, c, e.x)
          return nil
      # 2e. Standard method call with IC + direct JIT entry dispatch!
      gen_expr_any(c.a)
      push_x(R_X0)    # save receiver `this`
      node_ic = wk_ic(c)
      @a.mov_r(R_X13, R_X0)
      emit_ic_get(R_X13, mname, node_ic, -1)
      push_x(R_X0)    # save callee `f`
      gen_call_with_saved_f_this(e.list)
      return nil

    # 2f. Computed method calls `o[k](args)` — MUST preserve receiver `this = o`!
    if c.kind == :member && c.has?(F_COMPUTED)
      gen_expr_any(c.a)
      rec_off = push_x(R_X0)    # save receiver `this`
      gen_expr_any(c.b)
      @a.mov_r(R_X2, R_X0)      # key
      @a.ldr_x(R_X1, R_SP, rec_off)
      call_rt(RT_GETV)
      push_x(R_X0)              # save callee `f`
      gen_call_with_saved_f_this(e.list)
      return nil

    # 3. Direct guarded JIT call to a known function `step(bodies, 0.001)`!
    if c.kind == :ident && c.x != nil && c.x.binding != nil && c.x.binding.global? && e.list.size <= 4
      cell = wk_cell(c.x.binding)
      fv = cell.value
      if fv.is_a?(JS:Function) && fv.code != nil && fv.code.node.is_a?(JaFunc)
        target_jf = fv.code.node
        # Ensure callee is compiled too!
        if fv.code.jit_fp == 0 && fv.code.jit_state == 0 && target_jf != @jf && jit_eligible_fn?(target_jf)
          jit_compile_and_install(fv.code)
        if fv.code.jit_fp != 0
          gen_direct_jit_call(c, fv, e.list)
          return nil

    # 4. General call `f(args)`
    gen_expr_any(c)
    push_x(R_X0)        # callee f
    @a.movz_x(R_X0, 0)
    push_x(R_X0)        # this = undefined (order: push this first? Let's match gen_call_with_saved_f_this!)
    # Swap so top is f, below is this:
    pop_x(R_X9)         # 0
    pop_x(R_X10)        # f
    push_x(R_X9)        # this = nil
    push_x(R_X10)       # f
    gen_call_with_saved_f_this(e.list)
    nil

  -> gen_sra_closure_call_any(sc, arg_nodes)
    inner = sc.inner_jf
    re = jit_inline_return_expr(inner)
    old_env = @inline_env
    env = {}
    fvals = inner.free.values
    i = 0
    while i < fvals.size
      fb = fvals[i]
      pi = fb.scope.func.params.index(fb)
      env[fb] = [:slot, sc.cap_slots[pi]] if pi != nil && pi < sc.cap_slots.size
      i += 1
    pushed = 0
    i = 0
    while i < inner.params.size
      pb = inner.params[i]
      ae = i < arg_nodes.size ? arg_nodes[i] : nil
      if ae != nil && can_i32?(ae)
        gen_expr_i32(ae)
        off = push_w(R_X0)
        pushed += 1
        env[pb] = [:spill_w, off]
      else
        gen_expr_any(ae)
        off = push_x(R_X0)
        pushed += 1
        env[pb] = [:spill_x, off]
      i += 1
    @inline_env = env
    gen_expr_any(re)
    @inline_env = old_env
    @tmp_depth -= pushed
    nil

  -> simple_call_leaf?(e)
    return false if !e.is_a?(JsNode)
    k = e.kind
    return true if k == :num || k == :true || k == :false || k == :null || k == :string
    if k == :ident
      li = local_idx(e)
      return li >= 0 && (@info.types[li] == JT_ANY || @info.types[li] == JT_I32 || @info.types[li] == JT_F64)
    false

  -> emit_load_leaf_any(dst, e)
    k = e.kind
    if k == :num
      @a.mov_imm64(dst, wvalue_bits(e.a) ## i64)
    elsif k == :true
      @a.movz_x(dst, 2)
    elsif k == :false
      @a.movz_x(dst, 1)
    elsif k == :null
      @a.ldr_x(dst, R_X19, RT_K_NULL_BITS * 8)
    elsif k == :string
      jit_keep(e.str)
      @a.mov_imm64(dst, wvalue_bits(e.str) ## i64)
    else
      load_slot_any(dst, local_idx(e))
    nil

  # Direct call to a known compiled JS:Function `fv` (e.g. `step(bodies, 0.001)` or `fib(30)`!)
  -> gen_direct_jit_call(c_node, fv, arg_nodes)
    cell = wk_cell(c_node.x.binding)
    jit_keep(cell)
    jit_keep(fv)
    n = arg_nodes.size
    target_fp = fv.code.jit_fast_fp != 0 ? fv.code.jit_fast_fp : fv.code.jit_fp
    # Zero-spill fast path when all args are pure side-effect-free leaves (e.g. `step(bodies, 0.001)`!)
    all_leaf = n <= 4
    li = 0
    while li < n && all_leaf
      all_leaf = false if !simple_call_leaf?(arg_nodes[li])
      li += 1
    if all_leaf
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.mov_imm64(R_X9, (wvalue_bits(cell) ## i64) - 4)
      @a.ldr_x(R_X0, R_X9, 8)
      @a.mov_imm64(R_X10, wvalue_bits(fv) ## i64)
      @a.cmp_r(R_X0, R_X10)
      @a.b_cond(CC_NE, l_slow)
      @a.movz_x(R_X1, 0)
      @a.movz_x(R_X2, n)
      ai = 0
      while ai < n
        emit_load_leaf_any(R_X3 + ai, arg_nodes[ai])
        ai += 1
      @a.call_abs(R_X16, target_fp)
      @a.cmp_i(R_X0, 6)
      @a.b_cond(CC_EQ, l_slow)
      @a.bind(l_done)
      cb = ->()
        @a.bind(l_slow)
        @a.mov_imm64(R_X1, wvalue_bits(cell) ## i64)
        call_rt(RT_GGET)
        @a.mov_r(R_X1, R_X0)
        @a.movz_x(R_X2, 0)
        ai = 0
        while ai < n
          emit_load_leaf_any(R_X3 + ai, arg_nodes[ai])
          ai += 1
        call_rt(RT_CALL_0 + n)
        @a.b(l_done)
      add_cold_stub(cb)
      return nil
    # Evaluate args onto tmp stack
    i = 0
    while i < n
      gen_expr_any(arg_nodes[i])
      push_x(R_X0)
      i += 1
    # Check global cell still holds `fv`
    l_slow = @a.new_label
    l_done = @a.new_label
    @a.mov_imm64(R_X9, (wvalue_bits(cell) ## i64) - 4)
    @a.ldr_x(R_X0, R_X9, 8)
    @a.mov_imm64(R_X10, wvalue_bits(fv) ## i64)
    @a.cmp_r(R_X0, R_X10)
    @a.b_cond(CC_NE, l_slow)
    # Fast direct ARM64 call into target_fp(f, this=0, argc=n, a0..a3, more=0)!
    @a.movz_x(R_X1, 0)
    @a.movz_x(R_X2, n)
    @a.movz_x(R_X3, 0)
    @a.movz_x(R_X4, 0)
    @a.movz_x(R_X5, 0)
    @a.movz_x(R_X6, 0)
    @a.movz_x(R_X7, 0)
    base_off = @tmp_base + (@tmp_depth - n) * 8
    @a.ldr_x(R_X3, R_SP, base_off) if n >= 1
    @a.ldr_x(R_X4, R_SP, base_off + 8) if n >= 2
    @a.ldr_x(R_X5, R_SP, base_off + 16) if n >= 3
    @a.ldr_x(R_X6, R_SP, base_off + 24) if n >= 4
    @a.call_abs(R_X16, target_fp)
    # Check if fast_rec returned JSR_SLOW (6)
    @a.cmp_i(R_X0, 6)
    @a.b_cond(CC_EQ, l_slow)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      @a.mov_imm64(R_X1, wvalue_bits(cell) ## i64)
      call_rt(RT_GGET)
      @a.mov_r(R_X1, R_X0)
      @a.movz_x(R_X2, 0)
      @a.ldr_x(R_X3, R_SP, base_off) if n >= 1
      @a.ldr_x(R_X4, R_SP, base_off + 8) if n >= 2
      @a.ldr_x(R_X5, R_SP, base_off + 16) if n >= 3
      @a.ldr_x(R_X6, R_SP, base_off + 24) if n >= 4
      call_rt(RT_CALL_0 + n)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= n
    nil

  # Zero-boxing, zero-spill polymorphic method inliner returning unboxed f64 in R_D0!
  # Used directly by `gen_expr_to_i32` / `gen_expr_f64` (e.g. `(t + shapes[j].area()) | 0`!).
  -> gen_poly_method_inline_f64(call_e, mem_e, prof)
    npairs = prof.size / 2
    return false if npairs == 0 || npairs > 4 || call_e.list.size != 0
    targets = []
    i = 0
    while i < npairs
      sh = prof[i * 2]
      fn = prof[i * 2 + 1]
      return false if !sh.is_a?(JS:Shape) || !fn.is_a?(JS:Function) || fn.code == nil || !fn.code.node.is_a?(JaFunc)
      tjf = fn.code.node
      re = jit_inline_return_expr(tjf)
      return false if re == nil || tjf.free.size > 0 || tjf.params.size != 0
      return false if !poly_inline_expr_ok?(re, sh)
      targets.push([sh, fn, tjf, re])
      i += 1
    # Evaluate receiver into x13 (ZERO stack spill!)
    gen_expr_any(mem_e.a)
    @a.mov_r(R_X13, R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    # Guard prototype epoch unchanged (SKIP if already hoisted once at OSR loop entry!)
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    # Check receiver is a WObject instance and load its @shape into x12 (ptr stays in x9!)
    @a.sub_i(R_X9, R_X13, 4)
    @a.tst_wobj_bad(R_X9)
    @a.b_cond(CC_NE, l_slow)
    @a.cbz_x(R_X9, l_slow)
    @a.ldr_x(R_X12, R_X9, 8)
    # Dispatch across 1..4 observed shapes with register-resident CSE of `this.prop`!
    i = 0
    while i < targets.size
      t = targets[i]
      sh = t[0]
      re = t[3]
      jit_keep(sh)
      l_next = i + 1 < targets.size ? @a.new_label : l_slow
      sb = wvalue_bits(sh) ## i64
      hr = @hoisted_shapes[sb]
      if hr != nil
        @a.cmp_r(R_X12, hr)
      else
        @a.mov_imm64(R_X11, sb)
        @a.cmp_r(R_X12, R_X11)
      @a.b_cond(CC_NE, l_next)
      # Collect distinct `this.prop` keys used in `re` and preload into d2..d5 ONCE (CSE!)
      pkeys = []
      poly_collect_this_props(re, pkeys)
      pmap = {}
      q = 0
      while q < pkeys.size && q < 4
        pk = pkeys[q]
        sl = sh.slot_of(pk)
        enc = sl < sh.inline ? (sh.ibase + sl) : (0 - (sl - sh.inline) - 1)
        emit_slot_load(R_X10, R_X9, enc)
        emit_unbox_f64(R_D2 + q, R_X10, l_slow)
        pmap[pk] = R_D2 + q
        q += 1
      emit_poly_f64_reg(re, pmap, R_D0)
      @a.b(l_done) if i + 1 < targets.size
      @a.bind(l_next) if i + 1 < targets.size
      i += 1
    @a.bind(l_done)
    mname_s = mem_e.b.str
    jit_keep(mname_s)
    cb = ->()
      @a.bind(l_slow)
      rec_off = push_x(R_X13)
      @a.mov_r(R_X1, R_X13)
      @a.mov_imm64(R_X2, wvalue_bits(mname_s) ## i64)
      call_rt(RT_GETV)
      @a.mov_r(R_X1, R_X0)
      @a.ldr_x(R_X2, R_SP, rec_off)
      call_rt(RT_CALL_0)
      @tmp_depth -= 1
      l_tn = @a.new_label
      emit_unbox_f64(R_D0, R_X0, l_tn)
      @a.b(l_done)
      @a.bind(l_tn)
      @a.mov_r(R_X1, R_X0)
      call_rt(RT_TO_NUMBER)
      @a.sub_r(R_X15, R_X0, R_X20)
      @a.fmov_d_x(R_D0, R_X15)
      @a.b(l_done)
    add_cold_stub(cb)
    true

  -> poly_collect_this_props(e, out)
    return nil if e == nil
    if e.kind == :member && !e.has?(F_COMPUTED) && e.a.kind == :this
      out.push(e.b.str) if !out.include?(e.b.str)
      return nil
    if e.kind == :binary
      poly_collect_this_props(e.a, out)
      poly_collect_this_props(e.b, out)
    elsif e.kind == :unary
      poly_collect_this_props(e.a, out)
    nil

  -> poly_leaf_reg(e, pmap)
    return pmap[e.b.str] if e != nil && e.kind == :member && !e.has?(F_COMPUTED) && e.a.kind == :this && pmap[e.b.str] != nil
    nil

  -> emit_poly_f64_reg(e, pmap, dst)
    k = e.kind
    if k == :num
      @a.mov_imm64(R_X10, jit_f64_bits(wvalue_bits(e.a) ## i64))
      @a.fmov_d_x(dst, R_X10)
      return nil
    lr = poly_leaf_reg(e, pmap)
    if lr != nil
      @a.fmov_d(dst, lr) if dst != lr
      return nil
    if k == :unary && e.str == "-"
      emit_poly_f64_reg(e.a, pmap, dst)
      @a.fneg_d(dst, dst)
      return nil
    if k == :binary
      op = e.str
      ra = poly_leaf_reg(e.a, pmap)
      rb = poly_leaf_reg(e.b, pmap)
      if ra != nil && rb != nil
        emit_f64_op(op, dst, ra, rb)
        return nil
      if rb != nil
        emit_poly_f64_reg(e.a, pmap, dst)
        emit_f64_op(op, dst, dst, rb)
        return nil
      if ra != nil
        emit_poly_f64_reg(e.b, pmap, dst)
        emit_f64_op(op, dst, ra, dst)
        return nil
      if e.b.kind == :num
        emit_poly_f64_reg(e.a, pmap, dst)
        @a.mov_imm64(R_X10, jit_f64_bits(wvalue_bits(e.b.a) ## i64))
        @a.fmov_d_x(R_D1, R_X10)
        emit_f64_op(op, dst, dst, R_D1)
        return nil
      if e.a.kind == :num
        emit_poly_f64_reg(e.b, pmap, dst)
        @a.mov_imm64(R_X10, jit_f64_bits(wvalue_bits(e.a.a) ## i64))
        @a.fmov_d_x(R_D1, R_X10)
        emit_f64_op(op, dst, R_D1, dst)
        return nil
      emit_poly_f64_reg(e.a, pmap, R_D0)
      push_d(R_D0)
      emit_poly_f64_reg(e.b, pmap, R_D0)
      pop_d(R_D1)
      emit_f64_op(op, dst, R_D1, R_D0)
    nil

  -> emit_f64_op(op, dst, da, db)
    if op == "+"
      @a.fadd_d(dst, da, db)
    elsif op == "-"
      @a.fsub_d(dst, da, db)
    elsif op == "*"
      @a.fmul_d(dst, da, db)
    else
      @a.fdiv_d(dst, da, db)
    nil

  # Polymorphic speculative method inlining (`shapes[j].area()` for 1..4 observed shapes!).
  # prof = [shape0, fn0, shape1, fn1, ...].
  -> gen_poly_method_inline(call_e, mem_e, prof)
    npairs = prof.size / 2
    return false if npairs == 0 || npairs > 4
    # Verify all observed targets are simple inlineable JS:Functions with zero free vars!
    targets = []
    i = 0
    while i < npairs
      sh = prof[i * 2]
      fn = prof[i * 2 + 1]
      return false if !sh.is_a?(JS:Shape) || !fn.is_a?(JS:Function) || fn.code == nil || !fn.code.node.is_a?(JaFunc)
      tjf = fn.code.node
      re = jit_inline_return_expr(tjf)
      return false if re == nil || tjf.free.size > 0 || tjf.params.size != call_e.list.size
      return false if !poly_inline_expr_ok?(re, sh)
      targets.push([sh, fn, tjf, re])
      i += 1
    # Emit receiver evaluation
    gen_expr_any(mem_e.a)
    rec_off = push_x(R_X0)
    # Evaluate arguments (if any)
    nargs = call_e.list.size
    arg_offs = []
    i = 0
    while i < nargs
      gen_expr_any(call_e.list[i])
      arg_offs.push(push_x(R_X0))
      i += 1
    l_slow = @a.new_label
    l_done = @a.new_label
    # Guard prototype epoch unchanged (single load + compare!)
    ep_now = JS_EPOCH[0]
    @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
    @a.ldr_x(R_X10, R_X9, 0)
    @a.mov_imm64(R_X11, ep_now)
    @a.cmp_r(R_X10, R_X11)
    @a.b_cond(CC_NE, l_slow)
    # Check receiver is a WObject instance and load its @shape
    @a.ldr_x(R_X13, R_SP, rec_off)
    @a.sub_i(R_X9, R_X13, 4)
    @a.tst_x_lowmask(R_X9, 4)
    @a.b_cond(CC_NE, l_slow)
    @a.lsr_xi(R_X10, R_X9, 48)
    @a.cbnz_x(R_X10, l_slow)
    @a.cbz_x(R_X9, l_slow)
    @a.ldr_x(R_X12, R_X9, 8)     # x12 = receiver.@shape
    # Dispatch chain across the 1..4 observed shapes!
    i = 0
    while i < targets.size
      t = targets[i]
      sh = t[0]
      tjf = t[2]
      re = t[3]
      jit_keep(sh)
      l_next = i + 1 < targets.size ? @a.new_label : l_slow
      @a.mov_imm64(R_X11, wvalue_bits(sh) ## i64)
      @a.cmp_r(R_X12, R_X11)
      @a.b_cond(CC_NE, l_next)
      # Inlined method body with `this` known to have exact shape `sh` (ptr in R_X9 / rec_off)!
      emit_poly_inlined_body(re, sh, rec_off, tjf, arg_offs, l_slow)
      @a.b(l_done)
      @a.bind(l_next) if i + 1 < targets.size
      i += 1
    # Slow fallback for any 5th shape or mutated prototype
    @a.bind(l_slow)
    jit_keep(mem_e.b.str)
    @a.ldr_x(R_X1, R_SP, rec_off)
    @a.mov_imm64(R_X2, wvalue_bits(mem_e.b.str) ## i64)
    call_rt(RT_GETV)
    @a.mov_r(R_X1, R_X0)
    @a.ldr_x(R_X2, R_SP, rec_off)
    @a.ldr_x(R_X3, R_SP, arg_offs[0]) if nargs >= 1
    @a.ldr_x(R_X4, R_SP, arg_offs[1]) if nargs >= 2
    call_rt(RT_CALL_0 + nargs)
    @a.bind(l_done)
    @tmp_depth -= (1 + nargs)
    true

  # Check if method return expression only reads known own data slots of `this` + numbers/params!
  -> poly_inline_expr_ok?(e, sh)
    return false if e == nil
    k = e.kind
    return true if k == :num || k == :true || k == :false || k == :null
    if k == :member && !e.has?(F_COMPUTED) && e.a.kind == :this
      sl = sh.slot_of(e.b.str)
      return sl >= 0 && (sh.attrs_of(e.b.str) & ATTR_ACCESSOR) == 0
    if k == :binary
      op = e.str
      return (op == "+" || op == "-" || op == "*" || op == "/") && poly_inline_expr_ok?(e.a, sh) && poly_inline_expr_ok?(e.b, sh)
    if k == :unary
      return e.str == "-" && poly_inline_expr_ok?(e.a, sh)
    false

  # Emit inlined numeric method body -> boxed WValue in x0 (jumps to l_slow if any field isn't a number!).
  -> emit_poly_inlined_body(e, sh, rec_off, tjf, arg_offs, l_slow)
    emit_poly_f64(e, sh, rec_off, l_slow)
    emit_box_f64(R_X0, R_D0)
    nil

  -> emit_poly_f64(e, sh, rec_off, l_slow)
    k = e.kind
    if k == :num
      @a.mov_imm64(R_X10, jit_f64_bits(wvalue_bits(e.a) ## i64))
      @a.fmov_d_x(R_D0, R_X10)
      return nil
    if k == :member && !e.has?(F_COMPUTED) && e.a.kind == :this
      sl = sh.slot_of(e.b.str)
      enc = sl < sh.inline ? (sh.ibase + sl) : (0 - (sl - sh.inline) - 1)
      @a.ldr_x(R_X13, R_SP, rec_off)
      @a.sub_i(R_X9, R_X13, 4)
      emit_slot_load(R_X10, R_X9, enc)
      emit_unbox_f64(R_D0, R_X10, l_slow)
      return nil
    if k == :unary && e.str == "-"
      emit_poly_f64(e.a, sh, rec_off, l_slow)
      @a.fneg_d(R_D0, R_D0)
      return nil
    if k == :binary
      emit_poly_f64(e.a, sh, rec_off, l_slow)
      push_d(R_D0)
      emit_poly_f64(e.b, sh, rec_off, l_slow)
      pop_d(R_D1)
      op = e.str
      if op == "+"
        @a.fadd_d(R_D0, R_D1, R_D0)
      elsif op == "-"
        @a.fsub_d(R_D0, R_D1, R_D0)
      elsif op == "*"
        @a.fmul_d(R_D0, R_D1, R_D0)
      else
        @a.fdiv_d(R_D0, R_D1, R_D0)
    nil

  # ---- Inline Dense `arr.push(x)` (zero stack spills when arr is a register local!) ----

  -> gen_array_push_inline(arr_e, val_e, need_val = true)
    bli = local_idx(arr_e)
    r_arr = (bli >= 0 && @info.types[bli] == JT_ANY) ? @info.reg_gpr[bli] : nil
    arr_off = -1
    if r_arr == nil
      gen_expr_any(arr_e)
      arr_off = push_x(R_X0)
    gen_expr_any(val_e)
    @a.mov_r(R_X12, R_X0)                 # x12 = val
    l_slow = @a.new_label
    l_done = @a.new_label
    # Verify Array.prototype unchanged (skip if hoisted once at OSR loop entry!)
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    if r_arr != nil
      @a.mov_r(R_X13, r_arr)
    else
      @a.ldr_x(R_X13, R_SP, arr_off)
    @a.lsr_xi(R_X9, R_X13, 48)
    @a.movz_x(R_X10, 0xFFF4)
    @a.cmp_r(R_X9, R_X10)
    @a.b_cond(CC_NE, l_slow)
    @a.and_x_ptr47(R_X9, R_X13)           # x9 = WArray*
    @a.ldrb(R_X10, R_X9, 2)               # aflags
    @a.cmp_wi(R_X10, 1)                   # JS_AF_ARRAY (plain, no holes, no ext)
    @a.b_cond(CC_NE, l_slow)
    @a.ldrsw(R_X10, R_X9, 4)              # start
    @a.ldrsw(R_X11, R_X9, 8)              # size
    @a.ldrsw(R_X14, R_X9, 12)             # cap
    @a.add_r(R_X15, R_X10, R_X11)         # start + size
    @a.cmp_r(R_X15, R_X14)
    @a.b_cond(CC_GE, l_slow)              # full -> grow via RT_ARR_PUSH
    @a.ldr_x(R_X14, R_X9, 16)             # slots
    @a.str_x_idx(R_X12, R_X14, R_X15)     # slots[start + size] = val
    @a.add_wi(R_X11, R_X11, 1)            # size + 1
    @a.str_w(R_X11, R_X9, 8)              # store new size
    emit_box_i32(R_X0, R_X11) if need_val
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      if r_arr != nil
        @a.mov_r(R_X1, r_arr)
      else
        @a.ldr_x(R_X1, R_SP, arr_off)
      @a.mov_r(R_X2, R_X12)
      call_rt(RT_ARR_PUSH)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= 1 if arr_off >= 0
    nil

  # ---- Inlined Dense Higher-Order Array Methods: map / filter / reduce ----
  # Guards: epoch unchanged (Array.prototype + species untouched), receiver is dense plain array!

  -> gen_inline_array_map(arr_e, cb_jf)
    re = jit_inline_return_expr(cb_jf)
    gen_expr_any(arr_e)
    arr_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    emit_dense_array_guard(arr_off, l_slow)
    # Save x22..x26 into fixed temp slots and pin (i=x22, len=x23, arr_slots=x24, out_slots=x25, elem=x26)!
    s22 = push_x(R_X22)
    s23 = push_x(R_X23)
    s24 = push_x(R_X24)
    s25 = push_x(R_X25)
    s26 = push_x(R_X26)
    @a.ldr_x(R_X13, R_SP, arr_off)
    @a.and_x_ptr47(R_X9, R_X13)
    @a.ldrsw(R_X23, R_X9, 8)         # x23 = len
    @a.ldrsw(R_X12, R_X9, 4)         # start
    @a.ldr_x(R_X24, R_X9, 16)        # slots
    @a.add_r(R_X24, R_X24, R_X12, 3) # x24 = arr_slots + start*8
    emit_box_i32(R_X1, R_X23)
    call_rt(RT_ARR_NEW_CAP)
    out_off = push_x(R_X0)
    @a.and_x_ptr47(R_X9, R_X0)
    @a.ldr_x(R_X25, R_X9, 16)        # x25 = out->slots
    @a.movz_x(R_X22, 0)              # w22 = i = 0
    l_lp = @a.new_label
    l_end = @a.new_label
    @a.cmp_w(R_X22, R_X23)
    @a.b_cond(CC_GE, l_end)
    @a.bind(l_lp)
    @a.ldr_x_idx(R_X26, R_X24, R_X22) # x26 = arr[i] (i is zero-extended 32-bit!)
    old_env = @inline_env
    env = {}
    env[cb_jf.params[0]] = [:reg_x, R_X26] if cb_jf.params.size >= 1
    env[cb_jf.params[1]] = [:reg_w, R_X22] if cb_jf.params.size >= 2
    env[cb_jf.params[2]] = [:spill_x, arr_off] if cb_jf.params.size >= 3
    @inline_env = env
    gen_expr_any(re)                 # x0 = mapped val
    @inline_env = old_env
    @a.str_x_idx(R_X0, R_X25, R_X22) # out[i] = x0 (1 STR, ZERO stack traffic!)
    @a.add_wi(R_X22, R_X22, 1)
    @a.cmp_w(R_X22, R_X23)
    @a.b_cond(CC_LT, l_lp)
    @a.bind(l_end)
    @a.ldr_x(R_X0, R_SP, out_off)
    @a.ldr_x(R_X26, R_SP, s26)
    @a.ldr_x(R_X25, R_SP, s25)
    @a.ldr_x(R_X24, R_SP, s24)
    @a.ldr_x(R_X23, R_SP, s23)
    @a.ldr_x(R_X22, R_SP, s22)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      emit_hof_slow_call(arr_off, "map", cb_jf, nil)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= 7
    nil

  -> gen_inline_array_filter(arr_e, cb_jf)
    re = jit_inline_return_expr(cb_jf)
    gen_expr_any(arr_e)
    arr_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    emit_dense_array_guard(arr_off, l_slow)
    # Save x22..x26 into fixed temp slots and pin (i=x22, len=x23, arr_slots=x24, out=x25, elem=x26)!
    s22 = push_x(R_X22)
    s23 = push_x(R_X23)
    s24 = push_x(R_X24)
    s25 = push_x(R_X25)
    s26 = push_x(R_X26)
    @a.ldr_x(R_X13, R_SP, arr_off)
    @a.and_x_ptr47(R_X9, R_X13)
    @a.ldrsw(R_X23, R_X9, 8)         # x23 = len
    @a.ldrsw(R_X12, R_X9, 4)         # start
    @a.ldr_x(R_X24, R_X9, 16)        # slots
    @a.add_r(R_X24, R_X24, R_X12, 3) # x24 = arr_slots + start*8
    call_rt(RT_NEW_ARR)
    @a.mov_r(R_X25, R_X0)            # x25 = out (boxed WArray)
    @a.movz_x(R_X22, 0)              # w22 = i = 0
    l_lp = @a.new_label
    l_skip = @a.new_label
    l_end = @a.new_label
    @a.cmp_w(R_X22, R_X23)
    @a.b_cond(CC_GE, l_end)
    @a.bind(l_lp)
    @a.ldr_x_idx(R_X26, R_X24, R_X22)
    old_env = @inline_env
    env = {}
    env[cb_jf.params[0]] = [:reg_x, R_X26] if cb_jf.params.size >= 1
    env[cb_jf.params[1]] = [:reg_w, R_X22] if cb_jf.params.size >= 2
    env[cb_jf.params[2]] = [:spill_x, arr_off] if cb_jf.params.size >= 3
    @inline_env = env
    gen_cond_branch(re, l_skip, false)
    @inline_env = old_env
    emit_inline_push_to_reg(R_X25, R_X26)
    @a.bind(l_skip)
    @a.add_wi(R_X22, R_X22, 1)
    @a.cmp_w(R_X22, R_X23)
    @a.b_cond(CC_LT, l_lp)
    @a.bind(l_end)
    @a.mov_r(R_X0, R_X25)
    @a.ldr_x(R_X26, R_SP, s26)
    @a.ldr_x(R_X25, R_SP, s25)
    @a.ldr_x(R_X24, R_SP, s24)
    @a.ldr_x(R_X23, R_SP, s23)
    @a.ldr_x(R_X22, R_SP, s22)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      emit_hof_slow_call(arr_off, "filter", cb_jf, nil)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= 6
    nil

  -> gen_inline_array_reduce(arr_e, cb_jf, init_e)
    re = jit_inline_return_expr(cb_jf)
    gen_expr_any(arr_e)
    arr_off = push_x(R_X0)
    gen_expr_any(init_e)
    acc_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    emit_dense_array_guard(arr_off, l_slow)
    # Save x22..x26 into fixed temp slots and pin (i=x22, len=x23, arr_slots=x24, acc=x25, elem=x26)!
    s22 = push_x(R_X22)
    s23 = push_x(R_X23)
    s24 = push_x(R_X24)
    s25 = push_x(R_X25)
    s26 = push_x(R_X26)
    @a.ldr_x(R_X13, R_SP, arr_off)
    @a.and_x_ptr47(R_X9, R_X13)
    @a.ldrsw(R_X23, R_X9, 8)         # x23 = len
    @a.ldrsw(R_X12, R_X9, 4)         # start
    @a.ldr_x(R_X24, R_X9, 16)        # slots
    @a.add_r(R_X24, R_X24, R_X12, 3) # x24 = arr_slots + start*8
    @a.ldr_x(R_X25, R_SP, acc_off)   # x25 = acc
    @a.movz_x(R_X22, 0)              # w22 = i = 0
    l_lp = @a.new_label
    l_end = @a.new_label
    @a.cmp_w(R_X22, R_X23)
    @a.b_cond(CC_GE, l_end)
    @a.bind(l_lp)
    @a.ldr_x_idx(R_X26, R_X24, R_X22)
    old_env = @inline_env
    env = {}
    env[cb_jf.params[0]] = [:reg_x, R_X25] if cb_jf.params.size >= 1
    env[cb_jf.params[1]] = [:reg_x, R_X26] if cb_jf.params.size >= 2
    env[cb_jf.params[2]] = [:reg_w, R_X22] if cb_jf.params.size >= 3
    @inline_env = env
    gen_expr_any(re)
    @inline_env = old_env
    @a.mov_r(R_X25, R_X0)
    @a.add_wi(R_X22, R_X22, 1)
    @a.cmp_w(R_X22, R_X23)
    @a.b_cond(CC_LT, l_lp)
    @a.bind(l_end)
    @a.mov_r(R_X0, R_X25)
    @a.ldr_x(R_X26, R_SP, s26)
    @a.ldr_x(R_X25, R_SP, s25)
    @a.ldr_x(R_X24, R_SP, s24)
    @a.ldr_x(R_X23, R_SP, s23)
    @a.ldr_x(R_X22, R_SP, s22)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      emit_hof_slow_call(arr_off, "reduce", cb_jf, acc_off)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= 7
    nil

  -> emit_inline_push_to_reg(out_reg, val_reg)
    l_grow = @a.new_label
    l_ok = @a.new_label
    @a.and_x_ptr47(R_X9, out_reg)
    @a.ldrsw(R_X10, R_X9, 4)
    @a.ldrsw(R_X11, R_X9, 8)
    @a.ldrsw(R_X12, R_X9, 12)
    @a.add_r(R_X14, R_X10, R_X11)
    @a.cmp_r(R_X14, R_X12)
    @a.b_cond(CC_GE, l_grow)
    @a.ldr_x(R_X15, R_X9, 16)
    @a.str_x_idx(val_reg, R_X15, R_X14)
    @a.add_wi(R_X11, R_X11, 1)
    @a.str_w(R_X11, R_X9, 8)
    @a.bind(l_ok)
    cb = ->()
      @a.bind(l_grow)
      @a.mov_r(R_X2, val_reg)
      @a.mov_r(R_X1, out_reg)
      call_rt(RT_ARR_PUSH)
      @a.b(l_ok)
    add_cold_stub(cb)
    nil

  -> emit_dense_array_guard(arr_off, l_slow)
    ep_now = JS_EPOCH[0]
    @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
    @a.ldr_x(R_X10, R_X9, 0)
    @a.mov_imm64(R_X11, ep_now)
    @a.cmp_r(R_X10, R_X11)
    @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X13, R_SP, arr_off)
    @a.lsr_xi(R_X9, R_X13, 48)
    @a.movz_x(R_X10, 0xFFF4)
    @a.cmp_r(R_X9, R_X10)
    @a.b_cond(CC_NE, l_slow)
    @a.and_x_ptr47(R_X9, R_X13)
    @a.ldrb(R_X10, R_X9, 2)
    @a.cmp_wi(R_X10, 1)
    @a.b_cond(CC_NE, l_slow)
    nil

  -> emit_inline_push_to_off(out_off, val_reg)
    l_grow = @a.new_label
    l_ok = @a.new_label
    @a.ldr_x(R_X13, R_SP, out_off)
    @a.and_x_ptr47(R_X9, R_X13)
    @a.ldrsw(R_X10, R_X9, 4)
    @a.ldrsw(R_X11, R_X9, 8)
    @a.ldrsw(R_X12, R_X9, 12)
    @a.add_r(R_X14, R_X10, R_X11)
    @a.cmp_r(R_X14, R_X12)
    @a.b_cond(CC_GE, l_grow)
    @a.ldr_x(R_X15, R_X9, 16)
    @a.str_x_idx(val_reg, R_X15, R_X14)
    @a.add_wi(R_X11, R_X11, 1)
    @a.str_w(R_X11, R_X9, 8)
    @a.bind(l_ok)
    cb = ->()
      @a.bind(l_grow)
      @a.mov_r(R_X2, val_reg)
      @a.mov_r(R_X1, R_X13)
      call_rt(RT_ARR_PUSH)
      @a.b(l_ok)
    add_cold_stub(cb)
    nil

  -> emit_hof_slow_call(arr_off, mname, cb_jf, init_off)
    jit_keep(mname)
    code = wk_code(cb_jf)
    jit_keep(code)
    @a.mov_imm64(R_X1, wvalue_bits(code) ## i64)
    @a.movz_x(R_X2, 0)
    call_rt(RT_CLOSURE)
    cb_off = push_x(R_X0)
    @a.ldr_x(R_X1, R_SP, arr_off)
    @a.mov_imm64(R_X2, wvalue_bits(mname) ## i64)
    call_rt(RT_GETV)
    @a.mov_r(R_X1, R_X0)
    @a.ldr_x(R_X2, R_SP, arr_off)
    @a.ldr_x(R_X3, R_SP, cb_off)
    if init_off != nil
      @a.ldr_x(R_X4, R_SP, init_off)
      call_rt(RT_CALL_2)
    else
      call_rt(RT_CALL_1)
    @tmp_depth -= 1
    nil

  # Call with saved `[top-1] = this`, `[top] = f`.
  -> gen_call_with_saved_f_this(arg_nodes)
    n = arg_nodes.size
    if n <= 4
      i = 0
      while i < n
        gen_expr_any(arg_nodes[i])
        push_x(R_X0)
        i += 1
      base = @tmp_base + (@tmp_depth - n) * 8
      f_off = base - 8
      t_off = base - 16
      # Check if f is a JS:Function with a compiled jit_fp!
      l_slow = @a.new_label
      l_done = @a.new_label
      @a.ldr_x(R_X0, R_SP, f_off)
      @a.sub_i(R_X9, R_X0, 4)
      @a.tst_x_lowmask(R_X9, 4)
      @a.b_cond(CC_NE, l_slow)
      @a.lsr_xi(R_X10, R_X9, 48)
      @a.cbnz_x(R_X10, l_slow)
      @a.cbz_x(R_X9, l_slow)
      @a.ldrb(R_X10, R_X9, 4)         # js_kind
      @a.and_w_lowmask(R_X10, R_X10, 4)
      @a.cmp_wi(R_X10, 2)             # KIND_FUNCTION
      @a.b_cond(CC_NE, l_slow)
      @a.ldr_x(R_X10, R_X9, 24)       # f.@code (WValue ptr|4)
      @a.sub_i(R_X10, R_X10, 4)
      @a.ldr_x(R_X16, R_X10, 80)      # code.@jit_fp (ivar 9 -> offset 9*8+8 = 80!)
      # Note: jit_fp is a boxed Tungsten Int WValue (W_TAG_INT = 0xFFFC...) or 0 (raw int boxed = 0xFFFC000000000000)!
      # Wait: Tungsten boxes Int ivars with W_TAG_INT (0xFFFC << 48) + signed 48-bit payload!
      # Unbox 48-bit int: and_x_lowmask(R_X16, R_X16, 48)!
      @a.and_x_lowmask(R_X16, R_X16, 48)
      @a.cbz_x(R_X16, l_slow)
      # Direct ARM64 call to jit_fp(f, this, argc, a0..a3, more=0)!
      @a.ldr_x(R_X1, R_SP, t_off)
      @a.movz_x(R_X2, n)
      @a.movz_x(R_X3, 0)
      @a.movz_x(R_X4, 0)
      @a.movz_x(R_X5, 0)
      @a.movz_x(R_X6, 0)
      @a.movz_x(R_X7, 0)
      @a.ldr_x(R_X3, R_SP, base) if n >= 1
      @a.ldr_x(R_X4, R_SP, base + 8) if n >= 2
      @a.ldr_x(R_X5, R_SP, base + 16) if n >= 3
      @a.ldr_x(R_X6, R_SP, base + 24) if n >= 4
      @a.blr(R_X16)
      @a.cmp_i(R_X0, 6)   # JSR_SLOW from fast_rec
      @a.b_cond(CC_EQ, l_slow)
      @a.b(l_done)
      @a.bind(l_slow)
      @a.ldr_x(R_X1, R_SP, f_off)
      @a.ldr_x(R_X2, R_SP, t_off)
      @a.ldr_x(R_X3, R_SP, base) if n >= 1
      @a.ldr_x(R_X4, R_SP, base + 8) if n >= 2
      @a.ldr_x(R_X5, R_SP, base + 16) if n >= 3
      @a.ldr_x(R_X6, R_SP, base + 24) if n >= 4
      call_rt(RT_CALL_0 + n)
      @a.bind(l_done)
      @tmp_depth -= (n + 2)
      return nil
    # > 4 arguments: build Array and call RT_CALL_N
    call_rt(RT_NEW_ARR)
    a_off = push_x(R_X0)
    i = 0
    while i < n
      gen_expr_any(arg_nodes[i])
      emit_inline_push_to_off(a_off, R_X0)
      i += 1
    @a.ldr_x(R_X3, R_SP, a_off)
    @a.ldr_x(R_X1, R_SP, a_off - 8)
    @a.ldr_x(R_X2, R_SP, a_off - 16)
    call_rt(RT_CALL_N)
    @tmp_depth -= 3
    nil

  -> gen_new_any(e)
    gen_expr_any(e.a)
    f_off = push_x(R_X0)
    n = e.list.size
    if n <= 2
      ic = i64[8]
      jit_keep(ic)
      i = 0
      while i < n
        gen_expr_any(e.list[i])
        push_x(R_X0)
        i += 1
      @a.ldr_x(R_X1, R_SP, f_off)
      @a.mov_imm64(R_X2, wvalue_bits(ic) ## i64)
      @a.mov_imm64(R_X3, wvalue_bits(0) ## i64)
      @a.ldr_x(R_X4, R_SP, f_off + 8) if n >= 1
      @a.ldr_x(R_X5, R_SP, f_off + 16) if n >= 2
      call_rt(RT_NEW_0 + n)
      @tmp_depth -= (1 + n)
      return nil
    call_rt(RT_NEW_ARR)
    a_off = push_x(R_X0)
    i = 0
    while i < n
      gen_expr_any(e.list[i])
      emit_inline_push_to_off(a_off, R_X0)
      i += 1
    @a.ldr_x(R_X1, R_SP, f_off)
    @a.ldr_x(R_X2, R_SP, a_off)
    call_rt(RT_NEW_N)
    @tmp_depth -= 2
    nil

  -> gen_array_lit(e)
    call_rt(RT_NEW_ARR)
    return nil if e.list.size == 0
    a_off = push_x(R_X0)
    i = 0
    while i < e.list.size
      gen_expr_any(e.list[i])
      emit_inline_push_to_off(a_off, R_X0)
      i += 1
    @a.ldr_x(R_X0, R_SP, a_off)
    @tmp_depth -= 1
    nil

  -> gen_object_lit(e)
    ks = jit_plain_obj_keys(e)
    sh = js_lit_shape(ks)
    jit_keep(sh)
    n = e.list.size
    if n <= 6
      i = 0
      while i < n
        gen_expr_any(e.list[i].b)
        push_x(R_X0)
        i += 1
      base = @tmp_base + (@tmp_depth - n) * 8
      @a.mov_imm64(R_X1, wvalue_bits(sh) ## i64)
      @a.movz_x(R_X2, 0)
      @a.movz_x(R_X3, 0)
      @a.movz_x(R_X4, 0)
      @a.movz_x(R_X5, 0)
      @a.movz_x(R_X6, 0)
      @a.movz_x(R_X7, 0)
      @a.ldr_x(R_X2, R_SP, base) if n >= 1
      @a.ldr_x(R_X3, R_SP, base + 8) if n >= 2
      @a.ldr_x(R_X4, R_SP, base + 16) if n >= 3
      @a.ldr_x(R_X5, R_SP, base + 24) if n >= 4
      @a.ldr_x(R_X6, R_SP, base + 32) if n >= 5
      @a.ldr_x(R_X7, R_SP, base + 40) if n >= 6
      call_rt(RT_LIT)
      @tmp_depth -= n
      return nil
    call_rt(RT_NEW_ARR)
    a_off = push_x(R_X0)
    i = 0
    while i < n
      gen_expr_any(e.list[i].b)
      emit_inline_push_to_off(a_off, R_X0)
      i += 1
    @a.mov_imm64(R_X1, wvalue_bits(sh) ## i64)
    @a.ldr_x(R_X2, R_SP, a_off)
    call_rt(RT_LIT_N)
    @tmp_depth -= 1
    nil

  # Guarded String.prototype.{split, indexOf, charCodeAt, slice} fast-call intrinsic!
  # Guards: JS_EPOCH unchanged + receiver is a flat String (tag 0xFFF9, bit 0 clear).
  # Note: for `split(sep)`, also verify arg is a flat String (not a RegExp with Symbol.split!).
  -> gen_str_method_intrinsic(rec_e, mname, arg_nodes, rt_id)
    jit_keep(mname)
    gen_expr_any(rec_e)
    rec_off = push_x(R_X0)
    n = arg_nodes.size
    a0_off = -1
    a1_off = -1
    if n >= 1
      gen_expr_any(arg_nodes[0])
      a0_off = push_x(R_X0)
    if n >= 2
      gen_expr_any(arg_nodes[1])
      a1_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    # Check receiver is a flat String (`0xFFF9`, bit 0 == 0)
    @a.ldr_x(R_X1, R_SP, rec_off)
    @a.lsr_xi(R_X9, R_X1, 48)
    @a.movz_x(R_X10, 0xFFF9)
    @a.cmp_r(R_X9, R_X10)
    @a.b_cond(CC_NE, l_slow)
    @a.tst_x_lowmask(R_X1, 1)
    @a.b_cond(CC_NE, l_slow)
    if n >= 1
      @a.ldr_x(R_X2, R_SP, a0_off)
      if mname == "split"
        # Ensure separator is a flat String (if RegExp / object with Symbol.split -> slow!)
        @a.lsr_xi(R_X9, R_X2, 48)
        @a.cmp_r(R_X9, R_X10)
        @a.b_cond(CC_NE, l_slow)
        @a.tst_x_lowmask(R_X2, 1)
        @a.b_cond(CC_NE, l_slow)
    else
      @a.movz_x(R_X2, 0)
    if n >= 2
      @a.ldr_x(R_X3, R_SP, a1_off)
    elsif rt_id == RT_STR_SLICE
      @a.movz_x(R_X3, 0)
    call_rt(rt_id)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      @a.ldr_x(R_X1, R_SP, rec_off)
      @a.mov_imm64(R_X2, wvalue_bits(mname) ## i64)
      call_rt(RT_GETV)
      @a.mov_r(R_X1, R_X0)
      @a.ldr_x(R_X2, R_SP, rec_off)
      @a.ldr_x(R_X3, R_SP, a0_off) if n >= 1
      @a.ldr_x(R_X4, R_SP, a1_off) if n >= 2
      call_rt(RT_CALL_0 + n)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= (1 + n)
    nil

  # Guarded Map.prototype.{get,set,has} & Set.prototype.{add,has} fast-call intrinsic!
  -> gen_coll_method_intrinsic(rec_e, mname, arg_nodes, kind, rt_id)
    r = js_realm()
    mp = r.intrinsics["Map.prototype"]
    sp = r.intrinsics["Set.prototype"]
    return false if mp == nil || sp == nil
    if kind == :map || kind == :both
      return false if mp.get_own(mname) != r.intrinsics["%Map_" + mname + "%"]
    if kind == :set || kind == :both
      return false if sp.get_own(mname) != r.intrinsics["%Set_" + mname + "%"]
    map_sh = js_root_shape(mp, SP_INLINE, SP_IBASE)
    set_sh = js_root_shape(sp, SP_INLINE, SP_IBASE)
    jit_keep(mname)
    jit_keep(map_sh)
    jit_keep(set_sh)
    gen_expr_any(rec_e)
    rec_off = push_x(R_X0)
    n = arg_nodes.size
    a0_off = -1
    a1_off = -1
    if n >= 1
      gen_expr_any(arg_nodes[0])
      a0_off = push_x(R_X0)
    if n >= 2
      gen_expr_any(arg_nodes[1])
      a1_off = push_x(R_X0)
    l_slow = @a.new_label
    l_fast = @a.new_label
    l_done = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X1, R_SP, rec_off)
    @a.sub_i(R_X9, R_X1, 4)
    @a.tst_wobj_bad(R_X9)
    @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X10, R_X9, 8)
    if kind == :map
      @a.mov_imm64(R_X11, wvalue_bits(map_sh) ## i64)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    elsif kind == :set
      @a.mov_imm64(R_X11, wvalue_bits(set_sh) ## i64)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    else
      @a.mov_imm64(R_X11, wvalue_bits(set_sh) ## i64)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_EQ, l_fast)
      @a.mov_imm64(R_X11, wvalue_bits(map_sh) ## i64)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    @a.bind(l_fast)
    @a.ldr_x(R_X2, R_SP, a0_off) if n >= 1
    @a.ldr_x(R_X3, R_SP, a1_off) if n >= 2
    # Pure inline ARM64 open-addressed hash probe for immediate keys (Number / InlineStr <= 5B / Nil / Bool)!
    # Falls back seamlessly to l_rt (call_rt(rt_id)) for long strings, objects, NaN, BigInt, or grow/rehash!
    mp_off = js_mapdata_metap_off()
    if mp_off > 0 && (rt_id == RT_MAP_GET || rt_id == RT_SET_HAS || rt_id == RT_MAP_SET || rt_id == RT_SET_ADD)
      key_is_i32 = n >= 1 && can_i32?(arg_nodes[0])
      val_is_num = n >= 2 && (can_i32?(arg_nodes[1]) || can_f64?(arg_nodes[1]))
      l_rt = @a.new_label
      l_chk_str = @a.new_label
      l_is_zero = @a.new_label
      l_hash = @a.new_label
      l_ploop = @a.new_label
      l_pstep = @a.new_label
      l_phit = @a.new_label
      l_pmiss = @a.new_label
      # Load MapData (@internal at offset 32 of JS:Special) -> meta_p (unboxed 48-bit int) in x12, mask in x13
      @a.ldr_x(R_X9, R_X9, 32)
      @a.sub_i(R_X9, R_X9, 4)
      @a.ldr_x(R_X12, R_X9, mp_off)
      @a.and_x_lowmask(R_X12, R_X12, 48)
      @a.ldr_x(R_X13, R_X12, 8)         # x13 = mask
      @a.cbz_x(R_X13, l_rt)
      # For Map#set, verify value x3 is immediate (skip when statically known numeric!)
      if rt_id == RT_MAP_SET && !val_is_num
        l_vok = @a.new_label
        l_vstr = @a.new_label
        @a.cmp_i(R_X3, 2)
        @a.b_cond(CC_LS, l_vok)
        @a.sub_r(R_X10, R_X3, R_X20)
        @a.cmp_r(R_X10, R_X21)
        @a.b_cond(CC_LO, l_vok)
        @a.lsr_xi(R_X10, R_X3, 48)
        @a.movz_x(R_X11, 0xFFF9)
        @a.cmp_r(R_X10, R_X11)
        @a.b_cond(CC_NE, l_rt)
        @a.tst_x_lowmask(R_X3, 1)
        @a.b_cond(CC_NE, l_rt)
        @a.lsr_xi(R_X10, R_X3, 1)
        @a.and_x_lowmask(R_X10, R_X10, 3)
        @a.cmp_i(R_X10, 5)
        @a.b_cond(CC_HI, l_rt)
        @a.bind(l_vok)
      # Canonicalize key x2 -> cb in x14 (skip NaN/-0.0/string checks when key is statically exact JT_I32!)
      if key_is_i32
        @a.mov_r(R_X14, R_X2)
      else
        @a.sub_r(R_X10, R_X2, R_X20)
        @a.cmp_r(R_X10, R_X21)
        @a.b_cond(CC_HS, l_chk_str)
        # Number: reject NaN to l_rt; map -0.0 and +0.0 -> x20 (+0.0)
        @a.fmov_d_x(R_D16, R_X10)
        @a.fcmp_d(R_D16, R_D16)
        @a.b_cond(CC_VS, l_rt)
        @a.lsl_xi(R_X11, R_X10, 1)
        @a.cbz_x(R_X11, l_is_zero)
        @a.mov_r(R_X14, R_X2)
        @a.b(l_hash)
        @a.bind(l_is_zero)
        @a.mov_r(R_X14, R_X20)
        @a.b(l_hash)
        @a.bind(l_chk_str)
        l_chk_inl_str = @a.new_label
        @a.cmp_i(R_X2, 2)
        @a.b_cond(CC_HI, l_chk_inl_str)
        @a.mov_r(R_X14, R_X2)
        @a.b(l_hash)
        @a.bind(l_chk_inl_str)
        @a.lsr_xi(R_X10, R_X2, 48)
        @a.movz_x(R_X11, 0xFFF9)
        @a.cmp_r(R_X10, R_X11)
        @a.b_cond(CC_NE, l_rt)
        @a.tst_x_lowmask(R_X2, 1)
        @a.b_cond(CC_NE, l_rt)
        @a.lsr_xi(R_X10, R_X2, 1)
        @a.and_x_lowmask(R_X10, R_X10, 3)
        @a.cmp_i(R_X10, 5)
        @a.b_cond(CC_HI, l_rt)
        @a.mov_r(R_X14, R_X2)
      # 1-multiply 31-bit hash -> R_X15 (bit-exact with jmap_hash64!)
      @a.bind(l_hash)
      @a.lsr_xi(R_X15, R_X14, 32)
      @a.eor_r(R_X15, R_X14, R_X15)
      @a.movz_x(R_X10, 0xE5B9, 0)
      @a.movk_x(R_X10, 0x1CE4, 1)
      @a.movk_x(R_X10, 0x476D, 2)
      @a.movk_x(R_X10, 0xBF58, 3)
      @a.mul_x(R_X15, R_X15, R_X10)
      @a.lsr_xi(R_X15, R_X15, 32)
      @a.and_x_lowmask(R_X15, R_X15, 31)
      # Load bptr (x9), kptr (x10), idx = h & mask (x11)
      @a.ldr_x(R_X9, R_X12, 0)
      @a.ldr_x(R_X10, R_X12, 16)
      @a.and_r(R_X11, R_X15, R_X13)
      if rt_id == RT_MAP_GET || rt_id == RT_SET_HAS
        @a.bind(l_ploop)
        @a.ldrsw_idx(R_X16, R_X9, R_X11)
        @a.cbz_x(R_X16, l_pmiss)
        @a.cmp_i(R_X16, 0)
        @a.b_cond(CC_LT, l_pstep)
        @a.sub_i(R_X16, R_X16, 1)
        @a.ldr_x_idx(R_X17, R_X10, R_X16)
        @a.cmp_r(R_X17, R_X14)
        @a.b_cond(CC_EQ, l_phit)
        @a.bind(l_pstep)
        @a.add_i(R_X11, R_X11, 1)
        @a.and_r(R_X11, R_X11, R_X13)
        @a.b(l_ploop)
        @a.bind(l_phit)
        if rt_id == RT_MAP_GET
          @a.ldr_x(R_X10, R_X12, 24)
          @a.ldr_x_idx(R_X0, R_X10, R_X16)
        else
          @a.movz_x(R_X0, 2)
        @a.b(l_done)
        @a.bind(l_pmiss)
        @a.movz_x(R_X0, rt_id == RT_MAP_GET ? 0 : 1)
        @a.b(l_done)
      else
        # RT_MAP_SET or RT_SET_ADD: track first tombstone in x4 (-1 = none)
        l_pdel = @a.new_label
        @a.movn_x(R_X4, 0)
        @a.bind(l_ploop)
        @a.ldrsw_idx(R_X16, R_X9, R_X11)
        @a.cbz_x(R_X16, l_pmiss)
        @a.cmp_i(R_X16, 0)
        @a.b_cond(CC_LT, l_pdel)
        @a.sub_i(R_X16, R_X16, 1)
        @a.ldr_x_idx(R_X17, R_X10, R_X16)
        @a.cmp_r(R_X17, R_X14)
        @a.b_cond(CC_EQ, l_phit)
        @a.bind(l_pstep)
        @a.add_i(R_X11, R_X11, 1)
        @a.and_r(R_X11, R_X11, R_X13)
        @a.b(l_ploop)
        @a.bind(l_pdel)
        @a.cmp_i(R_X4, 0)
        @a.csel_x(R_X4, R_X11, R_X4, CC_LT)
        @a.b(l_pstep)
        @a.bind(l_phit)
        if rt_id == RT_MAP_SET
          @a.ldr_x(R_X10, R_X12, 24)
          @a.str_x_idx(R_X3, R_X10, R_X16)
        @a.mov_r(R_X0, R_X1)
        @a.b(l_done)
        @a.bind(l_pmiss)
        # Fresh insert if entries & bucket load factor have room, else l_rt!
        @a.ldr_x(R_X16, R_X12, 40)       # len
        @a.ldr_x(R_X17, R_X12, 64)       # keys_cap
        @a.cmp_r(R_X16, R_X17)
        @a.b_cond(CC_GE, l_rt)
        @a.ldr_x(R_X5, R_X12, 48)        # used
        @a.add_i(R_X6, R_X5, 1)          # u1 = used + 1
        @a.lsl_xi(R_X7, R_X6, 2)         # u4 = u1 * 4
        @a.add_i(R_X17, R_X13, 1)        # cap = mask + 1
        @a.add_r(R_X17, R_X17, R_X17, 1) # c3 = cap * 3
        @a.cmp_r(R_X7, R_X17)
        @a.b_cond(CC_GT, l_rt)
        # Store keys[len] = cb, vals[len] = val, hashes[len] = h32
        @a.str_x_idx(R_X14, R_X10, R_X16)
        @a.ldr_x(R_X7, R_X12, 24)
        @a.str_x_idx(rt_id == RT_MAP_SET ? R_X3 : R_X14, R_X7, R_X16)
        @a.ldr_x(R_X7, R_X12, 32)
        @a.str_w_idx(R_X15, R_X7, R_X16)
        @a.cmp_i(R_X4, 0)
        @a.csel_x(R_X7, R_X4, R_X11, CC_GE)   # slot = fdel >= 0 ? fdel : idx
        @a.csel_x(R_X5, R_X5, R_X6, CC_GE)    # nused = fdel >= 0 ? used : u1
        @a.add_i(R_X16, R_X16, 1)             # nlen = len + 1
        @a.str_w_idx(R_X16, R_X9, R_X7)       # buckets[slot] = nlen32
        @a.str_x(R_X16, R_X12, 40)            # meta[5] = nlen
        @a.str_x(R_X5, R_X12, 48)             # meta[6] = nused
        @a.ldr_x(R_X7, R_X12, 56)             # sz
        @a.add_i(R_X7, R_X7, 1)
        @a.str_x(R_X7, R_X12, 56)             # meta[7] = sz + 1
        @a.mov_r(R_X0, R_X1)
        @a.b(l_done)
      cb_rt = ->()
        @a.bind(l_rt)
        call_rt(rt_id)
        @a.b(l_done)
      add_cold_stub(cb_rt)
    else
      call_rt(rt_id)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      @a.ldr_x(R_X1, R_SP, rec_off)
      @a.mov_imm64(R_X2, wvalue_bits(mname) ## i64)
      call_rt(RT_GETV)
      @a.mov_r(R_X1, R_X0)
      @a.ldr_x(R_X2, R_SP, rec_off)
      @a.ldr_x(R_X3, R_SP, a0_off) if n >= 1
      @a.ldr_x(R_X4, R_SP, a1_off) if n >= 2
      call_rt(RT_CALL_0 + n)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= (1 + n)
    true

  # Guarded Promise.prototype.then(on_f[, on_r]) fast-call intrinsic!
  # When on_f is a zero-capture anonymous function/arrow with no self-ref/arguments/dynamic,
  # passes a pre-compiled cached JS:Function on the verified intrinsic fast path (allocating a
  # fresh closure on the cold fallback path if Promise.prototype.then was monkey-patched!).
  -> gen_prom_then_intrinsic(rec_e, arg_nodes)
    r = js_realm()
    return false if r.promise_shape == nil || !js_promise_pristine?(r)
    prom_sh = r.promise_shape
    jit_keep(prom_sh)
    jit_keep("then")
    gen_expr_any(rec_e)
    rec_off = push_x(R_X0)
    n = arg_nodes.size
    a0 = arg_nodes[0]
    cached_fn0 = nil
    code0 = nil
    if (a0.kind == :function || a0.kind == :arrow) && a0.x.is_a?(JaFunc)
      ajf = a0.x
      if ajf.free.size == 0 && !ajf.dynamic && ajf.self_binding == nil && ajf.args_binding == nil && !ajf.node.has?(F_ASYNC) && !ajf.node.has?(F_GENERATOR)
        code0 = wk_code(ajf)
        jit_compile_and_install(code0) if code0.jit_fp == 0 && code0.jit_state == 0 && jit_eligible_fn?(ajf)
        cached_fn0 = @prom_cached_fns[ajf]
        if cached_fn0 == nil
          cached_fn0 = js_closure(code0, nil)
          @prom_cached_fns[ajf] = cached_fn0
          jit_keep(code0)
          jit_keep(cached_fn0)
    a0_off = -1
    if cached_fn0 == nil
      gen_expr_any(a0)
      a0_off = push_x(R_X0)
    a1_off = -1
    if n >= 2
      gen_expr_any(arg_nodes[1])
      a1_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X1, R_SP, rec_off)
    @a.sub_i(R_X9, R_X1, 4)
    @a.tst_wobj_bad(R_X9)
    @a.b_cond(CC_NE, l_slow)
    @a.cbz_x(R_X9, l_slow)
    @a.ldr_x(R_X10, R_X9, 8)
    @a.mov_imm64(R_X11, wvalue_bits(prom_sh) ## i64)
    @a.cmp_r(R_X10, R_X11)
    @a.b_cond(CC_NE, l_slow)
    if cached_fn0 != nil
      @a.mov_imm64(R_X2, wvalue_bits(cached_fn0) ## i64)
    else
      @a.ldr_x(R_X2, R_SP, a0_off)
    if n >= 2
      @a.ldr_x(R_X3, R_SP, a1_off)
      call_rt(RT_PROM_THEN)
    elsif cached_fn0 != nil
      @a.mov_imm64(R_X3, wvalue_bits(prom_sh) ## i64)
      call_rt(RT_PROM_THEN_JIT)
    else
      @a.movz_x(R_X3, 0)
      call_rt(RT_PROM_THEN)
    @a.bind(l_done)
    tmp_slot = @tmp_base + @tmp_depth * 8
    @max_tmp = @tmp_depth + 1 if @tmp_depth + 1 > @max_tmp
    cb = ->()
      @a.bind(l_slow)
      if cached_fn0 != nil
        @a.mov_imm64(R_X1, wvalue_bits(code0) ## i64)
        @a.movz_x(R_X2, 0)
        call_rt(RT_CLOSURE)
        @a.str_x(R_X0, R_SP, tmp_slot)
        @a.ldr_x(R_X1, R_SP, rec_off)
        @a.mov_imm64(R_X2, wvalue_bits("then") ## i64)
        call_rt(RT_GETV)
        @a.mov_r(R_X1, R_X0)
        @a.ldr_x(R_X2, R_SP, rec_off)
        @a.ldr_x(R_X3, R_SP, tmp_slot)
        @a.ldr_x(R_X4, R_SP, a1_off) if n >= 2
        call_rt(RT_CALL_0 + n)
      else
        @a.ldr_x(R_X1, R_SP, rec_off)
        @a.mov_imm64(R_X2, wvalue_bits("then") ## i64)
        call_rt(RT_GETV)
        @a.mov_r(R_X1, R_X0)
        @a.ldr_x(R_X2, R_SP, rec_off)
        @a.ldr_x(R_X3, R_SP, a0_off)
        @a.ldr_x(R_X4, R_SP, a1_off) if n >= 2
        call_rt(RT_CALL_0 + n)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= (1 + (cached_fn0 == nil ? 1 : 0) + (n >= 2 ? 1 : 0))
    true

  # Guarded Promise.resolve(v) fast-call intrinsic!
  -> gen_prom_resolve_intrinsic(prom_e, val_e)
    b = prom_e.x == nil ? nil : prom_e.x.binding
    return false if b == nil || !b.global?
    r = js_realm()
    return false if r.promise_ctor == nil || !js_promise_pristine?(r)
    cell = wk_cell(b)
    jit_keep(cell)
    jit_keep(r.promise_ctor)
    jit_keep("resolve")
    gen_expr_any(val_e)
    v_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    @a.mov_imm64(R_X9, (wvalue_bits(cell) ## i64) - 4)
    @a.ldr_x(R_X10, R_X9, 8)
    @a.mov_imm64(R_X11, wvalue_bits(r.promise_ctor) ## i64)
    @a.cmp_r(R_X10, R_X11)
    @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X1, R_SP, v_off)
    call_rt(RT_PROM_RESOLVE)
    @a.bind(l_done)
    p_slot = @tmp_base + @tmp_depth * 8
    @max_tmp = @tmp_depth + 1 if @tmp_depth + 1 > @max_tmp
    cb = ->()
      @a.bind(l_slow)
      @a.mov_imm64(R_X1, wvalue_bits(cell) ## i64)
      call_rt(RT_GGET)
      @a.str_x(R_X0, R_SP, p_slot)
      @a.mov_r(R_X1, R_X0)
      @a.mov_imm64(R_X2, wvalue_bits("resolve") ## i64)
      call_rt(RT_GETV)
      @a.mov_r(R_X1, R_X0)
      @a.ldr_x(R_X2, R_SP, p_slot)
      @a.ldr_x(R_X3, R_SP, v_off)
      call_rt(RT_CALL_1)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= 1
    true

  # SRA RegExp exec helper: inline direct ARM64 BLR to rx_jit_exec on verified ASCII flat-string cache hit,
  # falling back out-of-line to RT_RX_EXEC_CAPS(re, s, caps) on miss/cold/non-ASCII; stores end in caps[31], leaves end in w0!
  -> gen_sra_rx_exec(m_li, call_e)
    caps = @info.sra_rxs[m_li]
    caps_p = jit_arr_slots_ptr(wvalue_bits(caps) ## i64)
    r = js_realm()
    js_rx_offs_init()
    off_int = JS_RX_OFFS[0]
    off_s0  = JS_RX_OFFS[1]
    off_fp  = JS_RX_OFFS[2]
    off_gl  = JS_RX_OFFS[3]
    off_st  = JS_RX_OFFS[4]
    can_direct = r.regexp_shape != nil && js_rx_pristine?(r) && off_int > 0 && off_s0 > 0 && off_fp > 0 && off_gl > 0 && off_st > 0
    gen_expr_any(call_e.a.a)
    re_off = push_x(R_X0)
    gen_expr_any(call_e.list[0])
    if !can_direct
      @a.mov_r(R_X2, R_X0)
      @a.ldr_x(R_X1, R_SP, re_off)
      @a.mov_imm64(R_X3, wvalue_bits(caps) ## i64)
      call_rt(RT_RX_EXEC_CAPS)
      @tmp_depth -= 1
      @a.sxtw(R_X0, R_X0)
      @a.mov_imm32(R_X9, -2)
      @a.cmp_w(R_X0, R_X9)
      @a.b_cond(CC_EQ, @l_deopt)
      @a.mov_imm64(R_X9, caps_p)
      @a.str_x(R_X0, R_X9, 248)
      return nil
    s_off = push_x(R_X0)
    gs_off = @tmp_base + @tmp_depth * 8
    @max_tmp = @tmp_depth + 1 if @tmp_depth + 1 > @max_tmp
    rx_sh = r.regexp_shape
    jit_keep(rx_sh)
    cache_p = jit_arr_slots_ptr(wvalue_bits(JS_RX_STR_CACHE) ## i64)
    l_slow = @a.new_label
    l_do_call = @a.new_label
    l_miss_li = @a.new_label
    l_store_end = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    # Guard re is WObject with shape == rx_sh -> x10 = re_ptr
    @a.ldr_x(R_X10, R_SP, re_off)
    @a.sub_i(R_X10, R_X10, 4)
    @a.tst_wobj_bad(R_X10)
    @a.b_cond(CC_NE, l_slow)
    @a.cbz_x(R_X10, l_slow)
    @a.ldr_x(R_X11, R_X10, 8)
    @a.mov_imm64(R_X9, wvalue_bits(rx_sh) ## i64)
    @a.cmp_r(R_X11, R_X9)
    @a.b_cond(CC_NE, l_slow)
    # Guard s matches pinned ASCII flat-string cache -> x12 = cache_p
    @a.mov_imm64(R_X12, cache_p)
    @a.ldr_x(R_X11, R_X12, 0)
    @a.cmp_r(R_X0, R_X11)
    @a.b_cond(CC_NE, l_slow)
    # Load rx = re.internal -> x13 = rx_ptr, fp -> x16
    @a.ldr_x(R_X13, R_X10, off_int)
    @a.sub_i(R_X13, R_X13, 4)
    @a.tst_wobj_bad(R_X13)
    @a.b_cond(CC_NE, l_slow)
    @a.cbz_x(R_X13, l_slow)
    @a.ldr_x(R_X16, R_X13, off_fp)
    @a.lsl_xi(R_X16, R_X16, 16)
    @a.lsr_xi(R_X16, R_X16, 16)
    @a.cbz_x(R_X16, l_slow)
    # sticky -> x4 (0 or 1), is_gs = global | sticky -> x5 (saved to gs_off)
    @a.ldr_x(R_X4, R_X13, off_st)
    @a.sub_i(R_X4, R_X4, 1)
    @a.ldr_x(R_X5, R_X13, off_gl)
    @a.sub_i(R_X5, R_X5, 1)
    @a.orr_r(R_X5, R_X5, R_X4)
    @a.str_x(R_X5, R_SP, gs_off)
    # Compute start_pos in x2
    @a.movz_x(R_X2, 0)
    @a.cbz_x(R_X5, l_do_call)
    @a.ldr_x(R_X9, R_X10, off_s0)
    emit_unbox_exact_i32(R_X2, R_X9, l_slow)
    @a.cmp_wi(R_X2, 0)
    @a.b_cond(CC_LT, l_slow)
    @a.ldr_x(R_X1, R_X12, 16)
    @a.cmp_r(R_X2, R_X1)
    @a.b_cond(CC_LE, l_do_call)
    # li > n: reset lastIndex = 0, return -1
    @a.str_x(R_X20, R_X10, off_s0)
    @a.movn_x(R_X0, 0)
    @a.b(l_store_end)
    # Direct native ARM64 call: rx_jit_exec(sp, n, li, caps_p, sticky)
    @a.bind(l_do_call)
    @a.ldr_x(R_X0, R_X12, 8)
    @a.ldr_x(R_X1, R_X12, 16)
    @a.mov_imm64(R_X3, caps_p)
    @a.blr(R_X16)
    # Update re.s0 (lastIndex) if global || sticky
    @a.ldr_x(R_X5, R_SP, gs_off)
    @a.cbz_x(R_X5, l_store_end)
    @a.ldr_x(R_X10, R_SP, re_off)
    @a.sub_i(R_X10, R_X10, 4)
    @a.cmp_wi(R_X0, 0)
    @a.b_cond(CC_LT, l_miss_li)
    @a.scvtf_d_w(R_D16, R_X0)
    @a.fmov_x_d(R_X9, R_D16)
    @a.add_r(R_X9, R_X9, R_X20)
    @a.str_x(R_X9, R_X10, off_s0)
    @a.b(l_store_end)
    @a.bind(l_miss_li)
    @a.str_x(R_X20, R_X10, off_s0)
    @a.bind(l_store_end)
    @a.mov_imm64(R_X9, caps_p)
    @a.str_x(R_X0, R_X9, 248)
    cb = ->()
      @a.bind(l_slow)
      @a.ldr_x(R_X1, R_SP, re_off)
      @a.ldr_x(R_X2, R_SP, s_off)
      @a.mov_imm64(R_X3, wvalue_bits(caps) ## i64)
      call_rt(RT_RX_EXEC_CAPS)
      @a.sxtw(R_X0, R_X0)
      @a.mov_imm32(R_X9, -2)
      @a.cmp_w(R_X0, R_X9)
      @a.b_cond(CC_EQ, @l_deopt)
      @a.b(l_store_end)
    add_cold_stub(cb)
    @tmp_depth -= 2
    nil

  # Guarded RegExp.prototype.exec(s) fast-call intrinsic!
  -> gen_rx_exec_intrinsic(rec_e, arg_e)
    r = js_realm()
    return false if r.regexp_shape == nil || r.regexp_proto == nil
    return false if r.regexp_proto.get_own("exec") != r.regexp_exec_fn
    rx_sh = r.regexp_shape
    jit_keep(rx_sh)
    jit_keep("exec")
    gen_expr_any(rec_e)
    rec_off = push_x(R_X0)
    gen_expr_any(arg_e)
    a0_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X1, R_SP, rec_off)
    @a.sub_i(R_X9, R_X1, 4)
    @a.tst_wobj_bad(R_X9)
    @a.b_cond(CC_NE, l_slow)
    @a.cbz_x(R_X9, l_slow)
    @a.ldr_x(R_X10, R_X9, 8)
    @a.mov_imm64(R_X11, wvalue_bits(rx_sh) ## i64)
    @a.cmp_r(R_X10, R_X11)
    @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X2, R_SP, a0_off)
    call_rt(RT_RX_EXEC)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      @a.ldr_x(R_X1, R_SP, rec_off)
      @a.mov_imm64(R_X2, wvalue_bits("exec") ## i64)
      call_rt(RT_GETV)
      @a.mov_r(R_X1, R_X0)
      @a.ldr_x(R_X2, R_SP, rec_off)
      @a.ldr_x(R_X3, R_SP, a0_off)
      call_rt(RT_CALL_1)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= 2
    true

  # Guarded Array.prototype.join fast-call intrinsic!
  -> gen_arr_join_intrinsic(rec_e, arg_nodes)
    jit_keep("join")
    gen_expr_any(rec_e)
    rec_off = push_x(R_X0)
    n = arg_nodes.size
    a0_off = -1
    if n >= 1
      gen_expr_any(arg_nodes[0])
      a0_off = push_x(R_X0)
    l_slow = @a.new_label
    l_done = @a.new_label
    if !@hoisted_epoch
      ep_now = JS_EPOCH[0]
      @a.ldr_x(R_X9, R_X19, RT_K_EPOCH_PTR * 8)
      @a.ldr_x(R_X10, R_X9, 0)
      @a.mov_imm64(R_X11, ep_now)
      @a.cmp_r(R_X10, R_X11)
      @a.b_cond(CC_NE, l_slow)
    @a.ldr_x(R_X1, R_SP, rec_off)
    @a.lsr_xi(R_X9, R_X1, 48)
    @a.movz_x(R_X10, 0xFFF4)
    @a.cmp_r(R_X9, R_X10)
    @a.b_cond(CC_NE, l_slow)
    @a.and_x_ptr47(R_X9, R_X1)
    @a.ldrb(R_X10, R_X9, 2)
    @a.cmp_wi(R_X10, 1)
    @a.b_cond(CC_NE, l_slow)
    if n >= 1
      @a.ldr_x(R_X2, R_SP, a0_off)
    else
      @a.movz_x(R_X2, 0)
    call_rt(RT_ARR_JOIN)
    @a.bind(l_done)
    cb = ->()
      @a.bind(l_slow)
      @a.ldr_x(R_X1, R_SP, rec_off)
      @a.mov_imm64(R_X2, wvalue_bits("join") ## i64)
      call_rt(RT_GETV)
      @a.mov_r(R_X1, R_X0)
      @a.ldr_x(R_X2, R_SP, rec_off)
      @a.ldr_x(R_X3, R_SP, a0_off) if n >= 1
      call_rt(RT_CALL_0 + n)
      @a.b(l_done)
    add_cold_stub(cb)
    @tmp_depth -= (1 + n)
    nil

  -> gen_template_any(e)
    # Fast fused 1-expr template (`pre${expr}suf` -> single RT_TPL1 call!)
    if e.a.size == 1 && e.list.size == 2
      pre_s = e.list[0].str
      suf_s = e.list[1].str
      jit_keep(pre_s)
      jit_keep(suf_s)
      gen_expr_any(e.a[0])
      @a.mov_r(R_X2, R_X0)
      @a.mov_imm64(R_X1, wvalue_bits(pre_s) ## i64)
      @a.mov_imm64(R_X3, wvalue_bits(suf_s) ## i64)
      call_rt(RT_TPL1)
      return nil
    # Build template literal via RT_TO_STRING + RT_STR_CAT
    first = true
    i = 0
    while i < e.list.size
      q = e.list[i].str
      if q != nil && q.size > 0
        jit_keep(q)
        if first
          @a.mov_imm64(R_X0, wvalue_bits(q) ## i64)
          first = false
        else
          @a.mov_r(R_X1, R_X0)
          @a.mov_imm64(R_X2, wvalue_bits(q) ## i64)
          call_rt(RT_STR_CAT)
      if i < e.a.size
        push_x(R_X0) if !first
        gen_expr_any(e.a[i])
        @a.mov_r(R_X1, R_X0)
        call_rt(RT_TO_STRING)
        if first
          first = false
        else
          @a.mov_r(R_X2, R_X0)
          pop_x(R_X1)
          call_rt(RT_STR_CAT)
      i += 1
    if first
      s = ""
      jit_keep(s)
      @a.mov_imm64(R_X0, wvalue_bits(s) ## i64)
    nil

  -> release
    if @a != nil
      @a.release
      ccall("w_value_free_w", @a)
      @a = nil
    ccall("w_value_free_w", @loops) if @loops != nil
    ccall("w_value_free_w", @known_shapes) if @known_shapes != nil
    ccall("w_value_free_w", @hoisted_tas) if @hoisted_tas != nil
    ccall("w_value_free_w", @hoisted_arrs) if @hoisted_arrs != nil
    ccall("w_value_free_w", @hoisted_cells) if @hoisted_cells != nil
    ccall("w_value_free_w", @hoisted_arr_regs) if @hoisted_arr_regs != nil
    ccall("w_value_free_w", @hoisted_ta_regs) if @hoisted_ta_regs != nil
    ccall("w_value_free_w", @hoisted_shapes) if @hoisted_shapes != nil
    ccall("w_value_free_w", @sh_spill_slots) if @sh_spill_slots != nil
    ccall("w_value_free_w", @block_prop_fp) if @block_prop_fp != nil
    ccall("w_value_free_w", @block_const_fp) if @block_const_fp != nil
    ccall("w_value_free_w", @cold_stubs) if @cold_stubs != nil
    ccall("w_value_free_w", @bounded_ta_set) if @bounded_ta_set != nil
    ccall("w_value_free_w", @bounded_mod_ta) if @bounded_mod_ta != nil
    ccall("w_value_free_w", @promoted_rw) if @promoted_rw != nil
    ccall("w_value_free_w", @mono_arr_shape) if @mono_arr_shape != nil
    ccall("w_value_free_w", @mono_arr_num) if @mono_arr_num != nil
    ccall("w_value_free_w", @prom_cached_fns) if @prom_cached_fns != nil
    ccall("w_value_free_w", @bounded_idx) if @bounded_idx != nil
    ccall("w_value_free_w", @inv_indexof) if @inv_indexof != nil
    ccall("w_value_free_w", @inv_str_ascii) if @inv_str_ascii != nil
    ccall("w_value_free_w", @str_cc_ics) if @str_cc_ics != nil
    ccall("w_value_free_w", @str_io_ics) if @str_io_ics != nil
    ccall("w_value_free_w", @free_gprs) if @free_gprs != nil
    ccall("w_value_free_w", self)
    nil

# ---- Top-Level Entry Points for Tier 0 (`walk.w`) & `js_dispatch` (`engine.w`) ----

-> jit_compile_and_install(code)
  return false if !JIT_ENABLED[0] || !jit_mem_ready?()
  return code.jit_fp != 0 if code.jit_state != 0
  jf = code.node
  if !jf.is_a?(JaFunc) || !jit_eligible_fn?(jf)
    code.jit_state = -1
    return false
  code.jit_state = -1   # prevent re-entrant compile loops
  an = JS:JitAnalyzer.new(jf, false, nil)
  info = an.analyze(nil)
  an.release
  comp = JS:JitCompiler.new(info)
  fp = comp.compile_fn()
  fast_off = comp.fast_entry_off
  rep_off = comp.repeat_entry_off
  fast_rec = info.fast_rec
  comp.release
  info.release
  if fp == 0
    return false
  code.jit_fp = fp
  code.jit_fast_fp = fast_off >= 0 ? (fp + fast_off) : fp
  code.jit_repeat_fp = rep_off >= 0 ? (fp + rep_off) : 0
  code.jit_state = 1
  ccall("w_eputs", "\[js-jit] compiled fn " + jf.name.to_s + " (" + fast_rec.to_s + ")") if JIT_DEBUG[0]
  true

# Enter a JITted JS function from `js_dispatch` / `wk_call`.
-> jit_enter_fn(code, f, this, argc, a0, a1, a2, a3, more)
  d = JS_CALL_DEPTH[0] + 1
  js_throw_range("Maximum call stack size exceeded") if d > 1200
  if d == 1 || JIT_RT_TBL[RT_K_SP_LIMIT] == 0
    JIT_RT_TBL[RT_K_SP_LIMIT] = jit_cur_sp() - 2097152
  JS_CALL_DEPTH[0] = d
  prev = JS_CUR_ACT[0]
  act = wk_act(code.node, f, nil, this, 0)
  act.argc = argc
  act.args = more
  act.a0 = a0
  act.a1 = a1
  act.a2 = a2
  act.a3 = a3
  act.caller = prev
  JS_CUR_ACT[0] = act
  res = nil
  begin
    res = wvalue_from_bits(jit_raw_call8(code.jit_fp ## i64, wvalue_bits(f) ## i64, wvalue_bits(this) ## i64, argc ## i64, wvalue_bits(a0) ## i64, wvalue_bits(a1) ## i64, wvalue_bits(a2) ## i64, wvalue_bits(a3) ## i64, wvalue_bits(more) ## i64))
  rescue ex
    JS_CALL_DEPTH[0] = d - 1
    JS_CUR_ACT[0] = prev
    wk_release(act)
    raise ex
  JS_CALL_DEPTH[0] = d - 1
  JS_CUR_ACT[0] = prev
  wk_release(act)
  return wk_call_tier0(f, this, argc, a0, a1, a2, a3, more) if js_is_slow_bits(wvalue_bits(res) ## i64) != 0
  res

# Compile & run an OSR loop directly from `wk_for` / `wk_while`.
# Returns OSR_DONE (0), OSR_DEOPT (1), or OSR_RETURN (2).
-> jit_try_osr(s, act)
  return OSR_DEOPT if !JIT_ENABLED[0] || !jit_mem_ready?()
  key = js_gc_key(wvalue_bits(s) ## i64)
  ent = JIT_OSR_CACHE[key]
  if ent == nil
    if !jit_eligible_osr_loop?(s, act)
      JIT_OSR_CACHE[key] = false
      return OSR_DEOPT
    an = JS:JitAnalyzer.new(act.f, true, s)
    info = an.analyze(act)
    an.release
    comp = JS:JitCompiler.new(info)
    fp = comp.compile_osr(act)
    comp.release
    if fp == 0
      info.release
      JIT_OSR_CACHE[key] = false
      return OSR_DEOPT
    ccall("w_eputs", "\[js-jit] OSR loop compiled in " + act.f.name.to_s + " (sra_obj=" + info.sra_objs.size.to_s + " sra_clos=" + info.sra_clos.size.to_s + " ta=" + info.ta_invariants.size.to_s + ")") if JIT_DEBUG[0]
    info.release
    ent = fp
    JIT_OSR_CACHE[key] = ent
  return OSR_DEOPT if ent == false
  fp = ent
  # Ensure locals array has an extra slot at index nlocals for OSR_RETURN value
  locs = act.locals
  nloc = act.f.nlocals
  locs.push(nil) if locs.size <= nloc
  lptr = jit_arr_slots_ptr(wvalue_bits(locs) ## i64)
  rc = jit_raw_call4(fp ## i64, lptr, wvalue_bits(act.env) ## i64, wvalue_bits(act.this) ## i64, wvalue_bits(act.fobj) ## i64)
  if rc == OSR_RETURN
    act.rv = locs[nloc]
    act.sig = WK_RETURN
  rc
