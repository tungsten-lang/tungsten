# wasm/simd_exec — SIMD execution: one LLVM IR kernel per 0xFD instruction, operating on
# the interpreter's stack in place (a v128 is two i64 slots; kernels load/store <N x T>
# vectors at the slot addresses). wvop dispatches OP_VOP by the instruction's sub-opcode.
#
# Swizzle/shuffle use AArch64 TBL (llvm.aarch64.neon.tbl1/tbl2): this engine targets arm64.
# Relaxed SIMD picks one deterministic behaviour: fused multiply-add for madd, the
# saturating conversions for relaxed_trunc, IEEE minimum/maximum for relaxed min/max.

fn wv_add_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = add <16 x i8> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_add_sat_s_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.sadd.sat.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_add_sat_u_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.uadd.sat.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = sub <16 x i8> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_sat_s_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.ssub.sat.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_sat_u_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.usub.sat.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_min_s_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.smin.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_min_u_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.umin.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_max_s_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.smax.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_max_u_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.umax.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_avgr_u_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %xa = zext <16 x i8> %va to <16 x i16>
    %xb = zext <16 x i8> %vb to <16 x i16>
    %s1 = add <16 x i16> %xa, %xb
    %s2 = add <16 x i16> %s1, <i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1>
    %s3 = lshr <16 x i16> %s2, <i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1, i16 1>
    %r = trunc <16 x i16> %s3 to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_add_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = add <8 x i16> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_add_sat_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.sadd.sat.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_add_sat_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.uadd.sat.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = sub <8 x i16> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_sat_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.ssub.sat.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_sat_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.usub.sat.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_min_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.smin.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_min_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.umin.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_max_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.smax.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_max_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = call <8 x i16> @llvm.umax.v8i16(<8 x i16> %va, <8 x i16> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_avgr_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %xa = zext <8 x i16> %va to <8 x i32>
    %xb = zext <8 x i16> %vb to <8 x i32>
    %s1 = add <8 x i32> %xa, %xb
    %s2 = add <8 x i32> %s1, <i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1>
    %s3 = lshr <8 x i32> %s2, <i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1>
    %r = trunc <8 x i32> %s3 to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_mul_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %r = mul <8 x i16> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_add_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %r = add <4 x i32> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %r = sub <4 x i32> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_mul_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %r = mul <4 x i32> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_min_s_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %r = call <4 x i32> @llvm.smin.v4i32(<4 x i32> %va, <4 x i32> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_min_u_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %r = call <4 x i32> @llvm.umin.v4i32(<4 x i32> %va, <4 x i32> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_max_s_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %r = call <4 x i32> @llvm.smax.v4i32(<4 x i32> %va, <4 x i32> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_max_u_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %r = call <4 x i32> @llvm.umax.v4i32(<4 x i32> %va, <4 x i32> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_add_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %r = add <2 x i64> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sub_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %r = sub <2 x i64> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_mul_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %r = mul <2 x i64> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_eq_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp eq <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ne_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp ne <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_slt_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp slt <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ult_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp ult <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sgt_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp sgt <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ugt_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp ugt <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sle_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp sle <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ule_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp ule <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sge_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp sge <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_uge_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %c = icmp uge <16 x i8> %va, %vb
    %r = sext <16 x i1> %c to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_eq_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp eq <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ne_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp ne <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_slt_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp slt <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ult_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp ult <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sgt_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp sgt <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ugt_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp ugt <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sle_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp sle <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ule_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp ule <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sge_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp sge <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_uge_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = icmp uge <8 x i16> %va, %vb
    %r = sext <8 x i1> %c to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_eq_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp eq <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ne_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp ne <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_slt_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp slt <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ult_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp ult <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sgt_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp sgt <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ugt_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp ugt <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sle_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp sle <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ule_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp ule <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sge_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp sge <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_uge_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = icmp uge <4 x i32> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_eq_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %c = icmp eq <2 x i64> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_ne_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %c = icmp ne <2 x i64> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_slt_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %c = icmp slt <2 x i64> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sgt_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %c = icmp sgt <2 x i64> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sle_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %c = icmp sle <2 x i64> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cmp_sge_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %c = icmp sge <2 x i64> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_oeq_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp oeq <4 x float> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_une_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp une <4 x float> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_olt_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp olt <4 x float> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_ogt_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp ogt <4 x float> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_ole_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp ole <4 x float> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_oge_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp oge <4 x float> %va, %vb
    %r = sext <4 x i1> %c to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_oeq_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp oeq <2 x double> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_une_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp une <2 x double> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_olt_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp olt <2 x double> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_ogt_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp ogt <2 x double> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_ole_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp ole <2 x double> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fcmp_oge_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp oge <2 x double> %va, %vb
    %r = sext <2 x i1> %c to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_and(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %r = and <2 x i64> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_or(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %r = or <2 x i64> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_xor(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %r = xor <2 x i64> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_andnot(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %nb = xor <2 x i64> %vb, <i64 -1, i64 -1>
    %r = and <2 x i64> %va, %nb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_not(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %r = xor <2 x i64> %va, <i64 -1, i64 -1>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fadd_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = fadd <4 x float> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fsub_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = fsub <4 x float> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fmul_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = fmul <4 x float> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fdiv_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = fdiv <4 x float> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fmin_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = call <4 x float> @llvm.minimum.v4f32(<4 x float> %va, <4 x float> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fmax_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = call <4 x float> @llvm.maximum.v4f32(<4 x float> %va, <4 x float> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_pmin_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp olt <4 x float> %vb, %va
    %r = select <4 x i1> %c, <4 x float> %vb, <4 x float> %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_pmax_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %c = fcmp olt <4 x float> %va, %vb
    %r = select <4 x i1> %c, <4 x float> %vb, <4 x float> %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fadd_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = fadd <2 x double> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fsub_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = fsub <2 x double> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fmul_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = fmul <2 x double> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fdiv_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = fdiv <2 x double> %va, %vb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fmin_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = call <2 x double> @llvm.minimum.v2f64(<2 x double> %va, <2 x double> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fmax_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = call <2 x double> @llvm.maximum.v2f64(<2 x double> %va, <2 x double> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_pmin_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp olt <2 x double> %vb, %va
    %r = select <2 x i1> %c, <2 x double> %vb, <2 x double> %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_pmax_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %c = fcmp olt <2 x double> %va, %vb
    %r = select <2 x i1> %c, <2 x double> %vb, <2 x double> %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rmin_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = call <4 x float> @llvm.minimum.v4f32(<4 x float> %va, <4 x float> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rmax_f32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %r = call <4 x float> @llvm.maximum.v4f32(<4 x float> %va, <4 x float> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rmin_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = call <2 x double> @llvm.minimum.v2f64(<2 x double> %va, <2 x double> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rmax_f64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %r = call <2 x double> @llvm.maximum.v2f64(<2 x double> %va, <2 x double> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ceil_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x float> @llvm.ceil.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_floor_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x float> @llvm.floor.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_trunc_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x float> @llvm.trunc.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_nearest_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x float> @llvm.roundeven.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fabs_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x float> @llvm.fabs.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fneg_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = fneg <4 x float> %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sqrt_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x float> @llvm.sqrt.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ceil_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %r = call <2 x double> @llvm.ceil.v2f64(<2 x double> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_floor_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %r = call <2 x double> @llvm.floor.v2f64(<2 x double> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_trunc_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %r = call <2 x double> @llvm.trunc.v2f64(<2 x double> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_nearest_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %r = call <2 x double> @llvm.roundeven.v2f64(<2 x double> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fabs_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %r = call <2 x double> @llvm.fabs.v2f64(<2 x double> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_fneg_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %r = fneg <2 x double> %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_sqrt_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %r = call <2 x double> @llvm.sqrt.v2f64(<2 x double> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_abs_i8(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %r = call <16 x i8> @llvm.abs.v16i8(<16 x i8> %va, i1 false)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_neg_i8(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %r = sub <16 x i8> zeroinitializer, %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_abs_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %r = call <8 x i16> @llvm.abs.v8i16(<8 x i16> %va, i1 false)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_neg_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %r = sub <8 x i16> zeroinitializer, %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_abs_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %r = call <4 x i32> @llvm.abs.v4i32(<4 x i32> %va, i1 false)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_neg_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %r = sub <4 x i32> zeroinitializer, %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_abs_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %r = call <2 x i64> @llvm.abs.v2i64(<2 x i64> %va, i1 false)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_neg_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %r = sub <2 x i64> zeroinitializer, %va
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_popcnt_i8(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %r = call <16 x i8> @llvm.ctpop.v16i8(<16 x i8> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_q15mulr_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %xa = sext <8 x i16> %va to <8 x i32>
    %xb = sext <8 x i16> %vb to <8 x i32>
    %m = mul <8 x i32> %xa, %xb
    %m2 = add <8 x i32> %m, <i32 16384, i32 16384, i32 16384, i32 16384, i32 16384, i32 16384, i32 16384, i32 16384>
    %m3 = ashr <8 x i32> %m2, <i32 15, i32 15, i32 15, i32 15, i32 15, i32 15, i32 15, i32 15>
    %m4 = call <8 x i32> @llvm.smin.v8i32(<8 x i32> %m3, <8 x i32> <i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767>)
    %r = trunc <8 x i32> %m4 to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rq15mulr_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %xa = sext <8 x i16> %va to <8 x i32>
    %xb = sext <8 x i16> %vb to <8 x i32>
    %m = mul <8 x i32> %xa, %xb
    %m2 = add <8 x i32> %m, <i32 16384, i32 16384, i32 16384, i32 16384, i32 16384, i32 16384, i32 16384, i32 16384>
    %m3 = ashr <8 x i32> %m2, <i32 15, i32 15, i32 15, i32 15, i32 15, i32 15, i32 15, i32 15>
    %m4 = call <8 x i32> @llvm.smin.v8i32(<8 x i32> %m3, <8 x i32> <i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767>)
    %r = trunc <8 x i32> %m4 to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_narrow_s_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = shufflevector <8 x i16> %va, <8 x i16> %vb, <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %m1 = call <16 x i16> @llvm.smax.v16i16(<16 x i16> %c, <16 x i16> <i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128, i16 -128>)
    %m2 = call <16 x i16> @llvm.smin.v16i16(<16 x i16> %m1, <16 x i16> <i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127, i16 127>)
    %r = trunc <16 x i16> %m2 to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_narrow_u_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %c = shufflevector <8 x i16> %va, <8 x i16> %vb, <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %m1 = call <16 x i16> @llvm.smax.v16i16(<16 x i16> %c, <16 x i16> <i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0, i16 0>)
    %m2 = call <16 x i16> @llvm.smin.v16i16(<16 x i16> %m1, <16 x i16> <i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255, i16 255>)
    %r = trunc <16 x i16> %m2 to <16 x i8>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_narrow_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = shufflevector <4 x i32> %va, <4 x i32> %vb, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %m1 = call <8 x i32> @llvm.smax.v8i32(<8 x i32> %c, <8 x i32> <i32 -32768, i32 -32768, i32 -32768, i32 -32768, i32 -32768, i32 -32768, i32 -32768, i32 -32768>)
    %m2 = call <8 x i32> @llvm.smin.v8i32(<8 x i32> %m1, <8 x i32> <i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767, i32 32767>)
    %r = trunc <8 x i32> %m2 to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_narrow_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %c = shufflevector <4 x i32> %va, <4 x i32> %vb, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %m1 = call <8 x i32> @llvm.smax.v8i32(<8 x i32> %c, <8 x i32> <i32 0, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0>)
    %m2 = call <8 x i32> @llvm.smin.v8i32(<8 x i32> %m1, <8 x i32> <i32 65535, i32 65535, i32 65535, i32 65535, i32 65535, i32 65535, i32 65535, i32 65535>)
    %r = trunc <8 x i32> %m2 to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_low_s_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %h = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %r = sext <8 x i8> %h to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_high_s_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %h = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %r = sext <8 x i8> %h to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_low_u_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %h = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %r = zext <8 x i8> %h to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_high_u_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %h = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %r = zext <8 x i8> %h to <8 x i16>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_low_s_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %h = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %r = sext <4 x i16> %h to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_high_s_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %h = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
    %r = sext <4 x i16> %h to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_low_u_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %h = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %r = zext <4 x i16> %h to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_high_u_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %h = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
    %r = zext <4 x i16> %h to <4 x i32>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_low_s_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %h = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %r = sext <2 x i32> %h to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_high_s_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %h = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 2, i32 3>
    %r = sext <2 x i32> %h to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_low_u_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %h = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %r = zext <2 x i32> %h to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_ext_high_u_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %h = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 2, i32 3>
    %r = zext <2 x i32> %h to <2 x i64>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_low_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %ha = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %hb = shufflevector <16 x i8> %vb, <16 x i8> poison, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %xa = sext <8 x i8> %ha to <8 x i16>
    %xb = sext <8 x i8> %hb to <8 x i16>
    %r = mul <8 x i16> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_high_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %ha = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %hb = shufflevector <16 x i8> %vb, <16 x i8> poison, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %xa = sext <8 x i8> %ha to <8 x i16>
    %xb = sext <8 x i8> %hb to <8 x i16>
    %r = mul <8 x i16> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_low_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %ha = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %hb = shufflevector <16 x i8> %vb, <16 x i8> poison, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
    %xa = zext <8 x i8> %ha to <8 x i16>
    %xb = zext <8 x i8> %hb to <8 x i16>
    %r = mul <8 x i16> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_high_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %ha = shufflevector <16 x i8> %va, <16 x i8> poison, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %hb = shufflevector <16 x i8> %vb, <16 x i8> poison, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
    %xa = zext <8 x i8> %ha to <8 x i16>
    %xb = zext <8 x i8> %hb to <8 x i16>
    %r = mul <8 x i16> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_low_s_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %ha = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %hb = shufflevector <8 x i16> %vb, <8 x i16> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %xa = sext <4 x i16> %ha to <4 x i32>
    %xb = sext <4 x i16> %hb to <4 x i32>
    %r = mul <4 x i32> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_high_s_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %ha = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
    %hb = shufflevector <8 x i16> %vb, <8 x i16> poison, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
    %xa = sext <4 x i16> %ha to <4 x i32>
    %xb = sext <4 x i16> %hb to <4 x i32>
    %r = mul <4 x i32> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_low_u_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %ha = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %hb = shufflevector <8 x i16> %vb, <8 x i16> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %xa = zext <4 x i16> %ha to <4 x i32>
    %xb = zext <4 x i16> %hb to <4 x i32>
    %r = mul <4 x i32> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_high_u_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %ha = shufflevector <8 x i16> %va, <8 x i16> poison, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
    %hb = shufflevector <8 x i16> %vb, <8 x i16> poison, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
    %xa = zext <4 x i16> %ha to <4 x i32>
    %xb = zext <4 x i16> %hb to <4 x i32>
    %r = mul <4 x i32> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_low_s_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %ha = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %hb = shufflevector <4 x i32> %vb, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %xa = sext <2 x i32> %ha to <2 x i64>
    %xb = sext <2 x i32> %hb to <2 x i64>
    %r = mul <2 x i64> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_high_s_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %ha = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 2, i32 3>
    %hb = shufflevector <4 x i32> %vb, <4 x i32> poison, <2 x i32> <i32 2, i32 3>
    %xa = sext <2 x i32> %ha to <2 x i64>
    %xb = sext <2 x i32> %hb to <2 x i64>
    %r = mul <2 x i64> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_low_u_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %ha = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %hb = shufflevector <4 x i32> %vb, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %xa = zext <2 x i32> %ha to <2 x i64>
    %xb = zext <2 x i32> %hb to <2 x i64>
    %r = mul <2 x i64> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extmul_high_u_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x i32>, ptr %pvb, align 8
    %ha = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 2, i32 3>
    %hb = shufflevector <4 x i32> %vb, <4 x i32> poison, <2 x i32> <i32 2, i32 3>
    %xa = zext <2 x i32> %ha to <2 x i64>
    %xb = zext <2 x i32> %hb to <2 x i64>
    %r = mul <2 x i64> %xa, %xb
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extadd_s_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %x = sext <16 x i8> %va to <16 x i16>
    %e = shufflevector <16 x i16> %x, <16 x i16> poison, <8 x i32> <i32 0, i32 2, i32 4, i32 6, i32 8, i32 10, i32 12, i32 14>
    %o = shufflevector <16 x i16> %x, <16 x i16> poison, <8 x i32> <i32 1, i32 3, i32 5, i32 7, i32 9, i32 11, i32 13, i32 15>
    %r = add <8 x i16> %e, %o
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extadd_u_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %x = zext <16 x i8> %va to <16 x i16>
    %e = shufflevector <16 x i16> %x, <16 x i16> poison, <8 x i32> <i32 0, i32 2, i32 4, i32 6, i32 8, i32 10, i32 12, i32 14>
    %o = shufflevector <16 x i16> %x, <16 x i16> poison, <8 x i32> <i32 1, i32 3, i32 5, i32 7, i32 9, i32 11, i32 13, i32 15>
    %r = add <8 x i16> %e, %o
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extadd_s_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %x = sext <8 x i16> %va to <8 x i32>
    %e = shufflevector <8 x i32> %x, <8 x i32> poison, <4 x i32> <i32 0, i32 2, i32 4, i32 6>
    %o = shufflevector <8 x i32> %x, <8 x i32> poison, <4 x i32> <i32 1, i32 3, i32 5, i32 7>
    %r = add <4 x i32> %e, %o
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extadd_u_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %x = zext <8 x i16> %va to <8 x i32>
    %e = shufflevector <8 x i32> %x, <8 x i32> poison, <4 x i32> <i32 0, i32 2, i32 4, i32 6>
    %o = shufflevector <8 x i32> %x, <8 x i32> poison, <4 x i32> <i32 1, i32 3, i32 5, i32 7>
    %r = add <4 x i32> %e, %o
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_dot_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <8 x i16>, ptr %pvb, align 8
    %xa = sext <8 x i16> %va to <8 x i32>
    %xb = sext <8 x i16> %vb to <8 x i32>
    %m = mul <8 x i32> %xa, %xb
    %e = shufflevector <8 x i32> %m, <8 x i32> poison, <4 x i32> <i32 0, i32 2, i32 4, i32 6>
    %o = shufflevector <8 x i32> %m, <8 x i32> poison, <4 x i32> <i32 1, i32 3, i32 5, i32 7>
    %r = add <4 x i32> %e, %o
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rdot_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %xa = sext <16 x i8> %va to <16 x i16>
    %xb = sext <16 x i8> %vb to <16 x i16>
    %m = mul <16 x i16> %xa, %xb
    %e = shufflevector <16 x i16> %m, <16 x i16> poison, <8 x i32> <i32 0, i32 2, i32 4, i32 6, i32 8, i32 10, i32 12, i32 14>
    %o = shufflevector <16 x i16> %m, <16 x i16> poison, <8 x i32> <i32 1, i32 3, i32 5, i32 7, i32 9, i32 11, i32 13, i32 15>
    %r = add <8 x i16> %e, %o
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shl_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 7
    %ct = trunc i64 %cm to i8
    %ins = insertelement <16 x i8> poison, i8 %ct, i64 0
    %spl = shufflevector <16 x i8> %ins, <16 x i8> poison, <16 x i32> zeroinitializer
    %r = shl <16 x i8> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_s_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 7
    %ct = trunc i64 %cm to i8
    %ins = insertelement <16 x i8> poison, i8 %ct, i64 0
    %spl = shufflevector <16 x i8> %ins, <16 x i8> poison, <16 x i32> zeroinitializer
    %r = ashr <16 x i8> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_u_i8(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 7
    %ct = trunc i64 %cm to i8
    %ins = insertelement <16 x i8> poison, i8 %ct, i64 0
    %spl = shufflevector <16 x i8> %ins, <16 x i8> poison, <16 x i32> zeroinitializer
    %r = lshr <16 x i8> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shl_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 15
    %ct = trunc i64 %cm to i16
    %ins = insertelement <8 x i16> poison, i16 %ct, i64 0
    %spl = shufflevector <8 x i16> %ins, <8 x i16> poison, <8 x i32> zeroinitializer
    %r = shl <8 x i16> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_s_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 15
    %ct = trunc i64 %cm to i16
    %ins = insertelement <8 x i16> poison, i16 %ct, i64 0
    %spl = shufflevector <8 x i16> %ins, <8 x i16> poison, <8 x i32> zeroinitializer
    %r = ashr <8 x i16> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_u_i16(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 15
    %ct = trunc i64 %cm to i16
    %ins = insertelement <8 x i16> poison, i16 %ct, i64 0
    %spl = shufflevector <8 x i16> %ins, <8 x i16> poison, <8 x i32> zeroinitializer
    %r = lshr <8 x i16> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shl_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 31
    %ct = trunc i64 %cm to i32
    %ins = insertelement <4 x i32> poison, i32 %ct, i64 0
    %spl = shufflevector <4 x i32> %ins, <4 x i32> poison, <4 x i32> zeroinitializer
    %r = shl <4 x i32> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_s_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 31
    %ct = trunc i64 %cm to i32
    %ins = insertelement <4 x i32> poison, i32 %ct, i64 0
    %spl = shufflevector <4 x i32> %ins, <4 x i32> poison, <4 x i32> zeroinitializer
    %r = ashr <4 x i32> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_u_i32(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 31
    %ct = trunc i64 %cm to i32
    %ins = insertelement <4 x i32> poison, i32 %ct, i64 0
    %spl = shufflevector <4 x i32> %ins, <4 x i32> poison, <4 x i32> zeroinitializer
    %r = lshr <4 x i32> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shl_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 63
    %ct = add i64 %cm, 0
    %ins = insertelement <2 x i64> poison, i64 %ct, i64 0
    %spl = shufflevector <2 x i64> %ins, <2 x i64> poison, <2 x i32> zeroinitializer
    %r = shl <2 x i64> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_s_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 63
    %ct = add i64 %cm, 0
    %ins = insertelement <2 x i64> poison, i64 %ct, i64 0
    %spl = shufflevector <2 x i64> %ins, <2 x i64> poison, <2 x i32> zeroinitializer
    %r = ashr <2 x i64> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shr_u_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %cnt64 = load i64, ptr %pb, align 8
    %cm = and i64 %cnt64, 63
    %ct = add i64 %cm, 0
    %ins = insertelement <2 x i64> poison, i64 %ct, i64 0
    %spl = shufflevector <2 x i64> %ins, <2 x i64> poison, <2 x i32> zeroinitializer
    %r = lshr <2 x i64> %va, %spl
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_any_true(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %o = call i64 @llvm.vector.reduce.or.v2i64(<2 x i64> %va)
    %c = icmp ne i64 %o, 0
    %rz = zext i1 %c to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_all_true_i8(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %c = icmp ne <16 x i8> %va, zeroinitializer
    %a1 = call i1 @llvm.vector.reduce.and.v16i1(<16 x i1> %c)
    %rz = zext i1 %a1 to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_bitmask_i8(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %c = icmp slt <16 x i8> %va, zeroinitializer
    %bi = bitcast <16 x i1> %c to i16
    %rz = zext i16 %bi to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_all_true_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %c = icmp ne <8 x i16> %va, zeroinitializer
    %a1 = call i1 @llvm.vector.reduce.and.v8i1(<8 x i1> %c)
    %rz = zext i1 %a1 to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_bitmask_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %c = icmp slt <8 x i16> %va, zeroinitializer
    %bi = bitcast <8 x i1> %c to i8
    %rz = zext i8 %bi to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_all_true_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %c = icmp ne <4 x i32> %va, zeroinitializer
    %a1 = call i1 @llvm.vector.reduce.and.v4i1(<4 x i1> %c)
    %rz = zext i1 %a1 to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_bitmask_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %c = icmp slt <4 x i32> %va, zeroinitializer
    %bi = bitcast <4 x i1> %c to i4
    %rz = zext i4 %bi to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_all_true_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %c = icmp ne <2 x i64> %va, zeroinitializer
    %a1 = call i1 @llvm.vector.reduce.and.v2i1(<2 x i1> %c)
    %rz = zext i1 %a1 to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_bitmask_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %c = icmp slt <2 x i64> %va, zeroinitializer
    %bi = bitcast <2 x i1> %c to i2
    %rz = zext i2 %bi to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_bitselect(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <2 x i64>, ptr %pvc, align 8
    %m1 = and <2 x i64> %va, %vc
    %nc = xor <2 x i64> %vc, <i64 -1, i64 -1>
    %m2 = and <2 x i64> %vb, %nc
    %r = or <2 x i64> %m1, %m2
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_laneselect265(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <2 x i64>, ptr %pvc, align 8
    %m1 = and <2 x i64> %va, %vc
    %nc = xor <2 x i64> %vc, <i64 -1, i64 -1>
    %m2 = and <2 x i64> %vb, %nc
    %r = or <2 x i64> %m1, %m2
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_laneselect266(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <2 x i64>, ptr %pvc, align 8
    %m1 = and <2 x i64> %va, %vc
    %nc = xor <2 x i64> %vc, <i64 -1, i64 -1>
    %m2 = and <2 x i64> %vb, %nc
    %r = or <2 x i64> %m1, %m2
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_laneselect267(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <2 x i64>, ptr %pvc, align 8
    %m1 = and <2 x i64> %va, %vc
    %nc = xor <2 x i64> %vc, <i64 -1, i64 -1>
    %m2 = and <2 x i64> %vb, %nc
    %r = or <2 x i64> %m1, %m2
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_laneselect268(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x i64>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <2 x i64>, ptr %pvc, align 8
    %m1 = and <2 x i64> %va, %vc
    %nc = xor <2 x i64> %vc, <i64 -1, i64 -1>
    %m2 = and <2 x i64> %vb, %nc
    %r = or <2 x i64> %m1, %m2
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rmadd_f32(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <4 x float>, ptr %pvc, align 8
    %r = call <4 x float> @llvm.fma.v4f32(<4 x float> %va, <4 x float> %vb, <4 x float> %vc)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rnmadd_f32(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <4 x float>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <4 x float>, ptr %pvc, align 8
    %na = fneg <4 x float> %va
    %r = call <4 x float> @llvm.fma.v4f32(<4 x float> %na, <4 x float> %vb, <4 x float> %vc)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rmadd_f64(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <2 x double>, ptr %pvc, align 8
    %r = call <2 x double> @llvm.fma.v2f64(<2 x double> %va, <2 x double> %vb, <2 x double> %vc)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rnmadd_f64(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <2 x double>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <2 x double>, ptr %pvc, align 8
    %na = fneg <2 x double> %va
    %r = call <2 x double> @llvm.fma.v2f64(<2 x double> %na, <2 x double> %vb, <2 x double> %vc)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rdot_add(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %pvc = getelementptr i64, ptr %sp, i64 %c
    %vc = load <4 x i32>, ptr %pvc, align 8
    %xa = sext <16 x i8> %va to <16 x i32>
    %xb = sext <16 x i8> %vb to <16 x i32>
    %m = mul <16 x i32> %xa, %xb
    %e = shufflevector <16 x i32> %m, <16 x i32> poison, <8 x i32> <i32 0, i32 2, i32 4, i32 6, i32 8, i32 10, i32 12, i32 14>
    %o = shufflevector <16 x i32> %m, <16 x i32> poison, <8 x i32> <i32 1, i32 3, i32 5, i32 7, i32 9, i32 11, i32 13, i32 15>
    %p = add <8 x i32> %e, %o
    %e2 = shufflevector <8 x i32> %p, <8 x i32> poison, <4 x i32> <i32 0, i32 2, i32 4, i32 6>
    %o2 = shufflevector <8 x i32> %p, <8 x i32> poison, <4 x i32> <i32 1, i32 3, i32 5, i32 7>
    %q = add <4 x i32> %e2, %o2
    %r = add <4 x i32> %q, %vc
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_swizzle(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rswizzle(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %r = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %va, <16 x i8> %vb)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_shuffle(s, d, a, b, lo, hi) (i64[] i64 i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pvb = getelementptr i64, ptr %sp, i64 %b
    %vb = load <16 x i8>, ptr %pvb, align 8
    %i0 = insertelement <2 x i64> poison, i64 %lo, i64 0
    %i1 = insertelement <2 x i64> %i0, i64 %hi, i64 1
    %idx = bitcast <2 x i64> %i1 to <16 x i8>
    %r = call <16 x i8> @llvm.aarch64.neon.tbl2.v16i8(<16 x i8> %va, <16 x i8> %vb, <16 x i8> %idx)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_splat_i8(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pa = getelementptr i64, ptr %sp, i64 %a
    %x = load i64, ptr %pa, align 8
    %xt = trunc i64 %x to i8
    %ins = insertelement <16 x i8> poison, i8 %xt, i64 0
    %r = shufflevector <16 x i8> %ins, <16 x i8> poison, <16 x i32> zeroinitializer
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_splat_i16(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pa = getelementptr i64, ptr %sp, i64 %a
    %x = load i64, ptr %pa, align 8
    %xt = trunc i64 %x to i16
    %ins = insertelement <8 x i16> poison, i16 %xt, i64 0
    %r = shufflevector <8 x i16> %ins, <8 x i16> poison, <8 x i32> zeroinitializer
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_splat_i32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pa = getelementptr i64, ptr %sp, i64 %a
    %x = load i64, ptr %pa, align 8
    %xt = trunc i64 %x to i32
    %ins = insertelement <4 x i32> poison, i32 %xt, i64 0
    %r = shufflevector <4 x i32> %ins, <4 x i32> poison, <4 x i32> zeroinitializer
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_splat_i64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pa = getelementptr i64, ptr %sp, i64 %a
    %x = load i64, ptr %pa, align 8
    %xt = add i64 %x, 0
    %ins = insertelement <2 x i64> poison, i64 %xt, i64 0
    %r = shufflevector <2 x i64> %ins, <2 x i64> poison, <2 x i32> zeroinitializer
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_splat_f32(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pa = getelementptr i64, ptr %sp, i64 %a
    %x = load i64, ptr %pa, align 8
    %xt = trunc i64 %x to i32
    %xf = bitcast i32 %xt to float
    %ins = insertelement <4 x float> poison, float %xf, i64 0
    %r = shufflevector <4 x float> %ins, <4 x float> poison, <4 x i32> zeroinitializer
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_splat_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pa = getelementptr i64, ptr %sp, i64 %a
    %x = load i64, ptr %pa, align 8
    %xt = add i64 %x, 0
    %xf = bitcast i64 %xt to double
    %ins = insertelement <2 x double> poison, double %xf, i64 0
    %r = shufflevector <2 x double> %ins, <2 x double> poison, <2 x i32> zeroinitializer
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_i8_sext(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %e = extractelement <16 x i8> %va, i64 %b
    %e32 = sext i8 %e to i32
    %rz = zext i32 %e32 to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_i8_zext(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %e = extractelement <16 x i8> %va, i64 %b
    %rz = zext i8 %e to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_i16_sext(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %e = extractelement <8 x i16> %va, i64 %b
    %e32 = sext i16 %e to i32
    %rz = zext i32 %e32 to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_i16_zext(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %e = extractelement <8 x i16> %va, i64 %b
    %rz = zext i16 %e to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_i32_zext(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %e = extractelement <4 x i32> %va, i64 %b
    %rz = zext i32 %e to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_i64(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %e = extractelement <2 x i64> %va, i64 %b
    %rz = add i64 %e, 0
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_f32_f(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %e = extractelement <4 x float> %va, i64 %b
    %ei = bitcast float %e to i32
    %rz = zext i32 %ei to i64
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_extract_f64_f(s, d, a, b) (i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %e = extractelement <2 x double> %va, i64 %b
    %ei = bitcast double %e to i64
    %rz = add i64 %ei, 0
    %pd = getelementptr i64, ptr %sp, i64 %d
    store i64 %rz, ptr %pd, align 8
    ret i64 0
  IR

fn wv_replace_i8(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <16 x i8>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %x = load i64, ptr %pb, align 8
    %xt = trunc i64 %x to i8
    %r = insertelement <16 x i8> %va, i8 %xt, i64 %c
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_replace_i16(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <8 x i16>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %x = load i64, ptr %pb, align 8
    %xt = trunc i64 %x to i16
    %r = insertelement <8 x i16> %va, i16 %xt, i64 %c
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_replace_i32(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %x = load i64, ptr %pb, align 8
    %xt = trunc i64 %x to i32
    %r = insertelement <4 x i32> %va, i32 %xt, i64 %c
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_replace_i64(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x i64>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %x = load i64, ptr %pb, align 8
    %xt = add i64 %x, 0
    %r = insertelement <2 x i64> %va, i64 %xt, i64 %c
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_replace_f32(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %x = load i64, ptr %pb, align 8
    %xt = trunc i64 %x to i32
    %xf = bitcast i32 %xt to float
    %r = insertelement <4 x float> %va, float %xf, i64 %c
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_replace_f64(s, d, a, b, c) (i64[] i64 i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %pb = getelementptr i64, ptr %sp, i64 %b
    %x = load i64, ptr %pb, align 8
    %xt = add i64 %x, 0
    %xf = bitcast i64 %xt to double
    %r = insertelement <2 x double> %va, double %xf, i64 %c
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cvt_s_f32x4(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %r = sitofp <4 x i32> %va to <4 x float>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cvt_u_f32x4(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %r = uitofp <4 x i32> %va to <4 x float>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_tsat_s_i32x4(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x i32> @llvm.fptosi.sat.v4i32.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_tsat_u_i32x4(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x i32> @llvm.fptoui.sat.v4i32.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rtrunc_s_i32x4(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x i32> @llvm.fptosi.sat.v4i32.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rtrunc_u_i32x4(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %r = call <4 x i32> @llvm.fptoui.sat.v4i32.v4f32(<4 x float> %va)
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_tsat_s_zero(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %h = call <2 x i32> @llvm.fptosi.sat.v2i32.v2f64(<2 x double> %va)
    %r = shufflevector <2 x i32> %h, <2 x i32> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_tsat_u_zero(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %h = call <2 x i32> @llvm.fptoui.sat.v2i32.v2f64(<2 x double> %va)
    %r = shufflevector <2 x i32> %h, <2 x i32> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rtrunc_s_zero(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %h = call <2 x i32> @llvm.fptosi.sat.v2i32.v2f64(<2 x double> %va)
    %r = shufflevector <2 x i32> %h, <2 x i32> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_rtrunc_u_zero(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %h = call <2 x i32> @llvm.fptoui.sat.v2i32.v2f64(<2 x double> %va)
    %r = shufflevector <2 x i32> %h, <2 x i32> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cvt_low_s_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %h = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %r = sitofp <2 x i32> %h to <2 x double>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_cvt_low_u_f64(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x i32>, ptr %pva, align 8
    %h = shufflevector <4 x i32> %va, <4 x i32> poison, <2 x i32> <i32 0, i32 1>
    %r = uitofp <2 x i32> %h to <2 x double>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_demote_zero(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <2 x double>, ptr %pva, align 8
    %h = fptrunc <2 x double> %va to <2 x float>
    %r = shufflevector <2 x float> %h, <2 x float> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <4 x float> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_promote_low(s, d, a) (i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %sp = inttoptr i64 %s to ptr
    %pva = getelementptr i64, ptr %sp, i64 %a
    %va = load <4 x float>, ptr %pva, align 8
    %h = shufflevector <4 x float> %va, <4 x float> poison, <2 x i32> <i32 0, i32 1>
    %r = fpext <2 x float> %h to <2 x double>
    %pd = getelementptr i64, ptr %sp, i64 %d
    store <2 x double> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wvop(stk, fp, d, a, b, c, sub, code) (i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  case sub
  when 13
    wv_shuffle(stk, fp + d, fp + a, fp + b, code[c], code[c + 1])
  when 14
    wv_swizzle(stk, fp + d, fp + a, fp + b)
  when 15
    wv_splat_i8(stk, fp + d, fp + a)
  when 16
    wv_splat_i16(stk, fp + d, fp + a)
  when 17
    wv_splat_i32(stk, fp + d, fp + a)
  when 18
    wv_splat_i64(stk, fp + d, fp + a)
  when 19
    wv_splat_f32(stk, fp + d, fp + a)
  when 20
    wv_splat_f64(stk, fp + d, fp + a)
  when 21
    wv_extract_i8_sext(stk, fp + d, fp + a, b)
  when 22
    wv_extract_i8_zext(stk, fp + d, fp + a, b)
  when 23
    wv_replace_i8(stk, fp + d, fp + a, fp + b, c)
  when 24
    wv_extract_i16_sext(stk, fp + d, fp + a, b)
  when 25
    wv_extract_i16_zext(stk, fp + d, fp + a, b)
  when 26
    wv_replace_i16(stk, fp + d, fp + a, fp + b, c)
  when 27
    wv_extract_i32_zext(stk, fp + d, fp + a, b)
  when 28
    wv_replace_i32(stk, fp + d, fp + a, fp + b, c)
  when 29
    wv_extract_i64(stk, fp + d, fp + a, b)
  when 30
    wv_replace_i64(stk, fp + d, fp + a, fp + b, c)
  when 31
    wv_extract_f32_f(stk, fp + d, fp + a, b)
  when 32
    wv_replace_f32(stk, fp + d, fp + a, fp + b, c)
  when 33
    wv_extract_f64_f(stk, fp + d, fp + a, b)
  when 34
    wv_replace_f64(stk, fp + d, fp + a, fp + b, c)
  when 35
    wv_cmp_eq_i8(stk, fp + d, fp + a, fp + b)
  when 36
    wv_cmp_ne_i8(stk, fp + d, fp + a, fp + b)
  when 37
    wv_cmp_slt_i8(stk, fp + d, fp + a, fp + b)
  when 38
    wv_cmp_ult_i8(stk, fp + d, fp + a, fp + b)
  when 39
    wv_cmp_sgt_i8(stk, fp + d, fp + a, fp + b)
  when 40
    wv_cmp_ugt_i8(stk, fp + d, fp + a, fp + b)
  when 41
    wv_cmp_sle_i8(stk, fp + d, fp + a, fp + b)
  when 42
    wv_cmp_ule_i8(stk, fp + d, fp + a, fp + b)
  when 43
    wv_cmp_sge_i8(stk, fp + d, fp + a, fp + b)
  when 44
    wv_cmp_uge_i8(stk, fp + d, fp + a, fp + b)
  when 45
    wv_cmp_eq_i16(stk, fp + d, fp + a, fp + b)
  when 46
    wv_cmp_ne_i16(stk, fp + d, fp + a, fp + b)
  when 47
    wv_cmp_slt_i16(stk, fp + d, fp + a, fp + b)
  when 48
    wv_cmp_ult_i16(stk, fp + d, fp + a, fp + b)
  when 49
    wv_cmp_sgt_i16(stk, fp + d, fp + a, fp + b)
  when 50
    wv_cmp_ugt_i16(stk, fp + d, fp + a, fp + b)
  when 51
    wv_cmp_sle_i16(stk, fp + d, fp + a, fp + b)
  when 52
    wv_cmp_ule_i16(stk, fp + d, fp + a, fp + b)
  when 53
    wv_cmp_sge_i16(stk, fp + d, fp + a, fp + b)
  when 54
    wv_cmp_uge_i16(stk, fp + d, fp + a, fp + b)
  when 55
    wv_cmp_eq_i32(stk, fp + d, fp + a, fp + b)
  when 56
    wv_cmp_ne_i32(stk, fp + d, fp + a, fp + b)
  when 57
    wv_cmp_slt_i32(stk, fp + d, fp + a, fp + b)
  when 58
    wv_cmp_ult_i32(stk, fp + d, fp + a, fp + b)
  when 59
    wv_cmp_sgt_i32(stk, fp + d, fp + a, fp + b)
  when 60
    wv_cmp_ugt_i32(stk, fp + d, fp + a, fp + b)
  when 61
    wv_cmp_sle_i32(stk, fp + d, fp + a, fp + b)
  when 62
    wv_cmp_ule_i32(stk, fp + d, fp + a, fp + b)
  when 63
    wv_cmp_sge_i32(stk, fp + d, fp + a, fp + b)
  when 64
    wv_cmp_uge_i32(stk, fp + d, fp + a, fp + b)
  when 65
    wv_fcmp_oeq_f32(stk, fp + d, fp + a, fp + b)
  when 66
    wv_fcmp_une_f32(stk, fp + d, fp + a, fp + b)
  when 67
    wv_fcmp_olt_f32(stk, fp + d, fp + a, fp + b)
  when 68
    wv_fcmp_ogt_f32(stk, fp + d, fp + a, fp + b)
  when 69
    wv_fcmp_ole_f32(stk, fp + d, fp + a, fp + b)
  when 70
    wv_fcmp_oge_f32(stk, fp + d, fp + a, fp + b)
  when 71
    wv_fcmp_oeq_f64(stk, fp + d, fp + a, fp + b)
  when 72
    wv_fcmp_une_f64(stk, fp + d, fp + a, fp + b)
  when 73
    wv_fcmp_olt_f64(stk, fp + d, fp + a, fp + b)
  when 74
    wv_fcmp_ogt_f64(stk, fp + d, fp + a, fp + b)
  when 75
    wv_fcmp_ole_f64(stk, fp + d, fp + a, fp + b)
  when 76
    wv_fcmp_oge_f64(stk, fp + d, fp + a, fp + b)
  when 77
    wv_not(stk, fp + d, fp + a)
  when 78
    wv_and(stk, fp + d, fp + a, fp + b)
  when 79
    wv_andnot(stk, fp + d, fp + a, fp + b)
  when 80
    wv_or(stk, fp + d, fp + a, fp + b)
  when 81
    wv_xor(stk, fp + d, fp + a, fp + b)
  when 82
    wv_bitselect(stk, fp + d, fp + a, fp + b, fp + c)
  when 83
    wv_any_true(stk, fp + d, fp + a)
  when 94
    wv_demote_zero(stk, fp + d, fp + a)
  when 95
    wv_promote_low(stk, fp + d, fp + a)
  when 96
    wv_abs_i8(stk, fp + d, fp + a)
  when 97
    wv_neg_i8(stk, fp + d, fp + a)
  when 98
    wv_popcnt_i8(stk, fp + d, fp + a)
  when 99
    wv_all_true_i8(stk, fp + d, fp + a)
  when 100
    wv_bitmask_i8(stk, fp + d, fp + a)
  when 101
    wv_narrow_s_i8(stk, fp + d, fp + a, fp + b)
  when 102
    wv_narrow_u_i8(stk, fp + d, fp + a, fp + b)
  when 103
    wv_ceil_f32(stk, fp + d, fp + a)
  when 104
    wv_floor_f32(stk, fp + d, fp + a)
  when 105
    wv_trunc_f32(stk, fp + d, fp + a)
  when 106
    wv_nearest_f32(stk, fp + d, fp + a)
  when 107
    wv_shl_i8(stk, fp + d, fp + a, fp + b)
  when 108
    wv_shr_s_i8(stk, fp + d, fp + a, fp + b)
  when 109
    wv_shr_u_i8(stk, fp + d, fp + a, fp + b)
  when 110
    wv_add_i8(stk, fp + d, fp + a, fp + b)
  when 111
    wv_add_sat_s_i8(stk, fp + d, fp + a, fp + b)
  when 112
    wv_add_sat_u_i8(stk, fp + d, fp + a, fp + b)
  when 113
    wv_sub_i8(stk, fp + d, fp + a, fp + b)
  when 114
    wv_sub_sat_s_i8(stk, fp + d, fp + a, fp + b)
  when 115
    wv_sub_sat_u_i8(stk, fp + d, fp + a, fp + b)
  when 116
    wv_ceil_f64(stk, fp + d, fp + a)
  when 117
    wv_floor_f64(stk, fp + d, fp + a)
  when 118
    wv_min_s_i8(stk, fp + d, fp + a, fp + b)
  when 119
    wv_min_u_i8(stk, fp + d, fp + a, fp + b)
  when 120
    wv_max_s_i8(stk, fp + d, fp + a, fp + b)
  when 121
    wv_max_u_i8(stk, fp + d, fp + a, fp + b)
  when 122
    wv_trunc_f64(stk, fp + d, fp + a)
  when 123
    wv_avgr_u_i8(stk, fp + d, fp + a, fp + b)
  when 124
    wv_extadd_s_i16(stk, fp + d, fp + a)
  when 125
    wv_extadd_u_i16(stk, fp + d, fp + a)
  when 126
    wv_extadd_s_i32(stk, fp + d, fp + a)
  when 127
    wv_extadd_u_i32(stk, fp + d, fp + a)
  when 128
    wv_abs_i16(stk, fp + d, fp + a)
  when 129
    wv_neg_i16(stk, fp + d, fp + a)
  when 130
    wv_q15mulr_i16(stk, fp + d, fp + a, fp + b)
  when 131
    wv_all_true_i16(stk, fp + d, fp + a)
  when 132
    wv_bitmask_i16(stk, fp + d, fp + a)
  when 133
    wv_narrow_s_i16(stk, fp + d, fp + a, fp + b)
  when 134
    wv_narrow_u_i16(stk, fp + d, fp + a, fp + b)
  when 135
    wv_ext_low_s_i16(stk, fp + d, fp + a)
  when 136
    wv_ext_high_s_i16(stk, fp + d, fp + a)
  when 137
    wv_ext_low_u_i16(stk, fp + d, fp + a)
  when 138
    wv_ext_high_u_i16(stk, fp + d, fp + a)
  when 139
    wv_shl_i16(stk, fp + d, fp + a, fp + b)
  when 140
    wv_shr_s_i16(stk, fp + d, fp + a, fp + b)
  when 141
    wv_shr_u_i16(stk, fp + d, fp + a, fp + b)
  when 142
    wv_add_i16(stk, fp + d, fp + a, fp + b)
  when 143
    wv_add_sat_s_i16(stk, fp + d, fp + a, fp + b)
  when 144
    wv_add_sat_u_i16(stk, fp + d, fp + a, fp + b)
  when 145
    wv_sub_i16(stk, fp + d, fp + a, fp + b)
  when 146
    wv_sub_sat_s_i16(stk, fp + d, fp + a, fp + b)
  when 147
    wv_sub_sat_u_i16(stk, fp + d, fp + a, fp + b)
  when 148
    wv_nearest_f64(stk, fp + d, fp + a)
  when 149
    wv_mul_i16(stk, fp + d, fp + a, fp + b)
  when 150
    wv_min_s_i16(stk, fp + d, fp + a, fp + b)
  when 151
    wv_min_u_i16(stk, fp + d, fp + a, fp + b)
  when 152
    wv_max_s_i16(stk, fp + d, fp + a, fp + b)
  when 153
    wv_max_u_i16(stk, fp + d, fp + a, fp + b)
  when 155
    wv_avgr_u_i16(stk, fp + d, fp + a, fp + b)
  when 156
    wv_extmul_low_s_i16(stk, fp + d, fp + a, fp + b)
  when 157
    wv_extmul_high_s_i16(stk, fp + d, fp + a, fp + b)
  when 158
    wv_extmul_low_u_i16(stk, fp + d, fp + a, fp + b)
  when 159
    wv_extmul_high_u_i16(stk, fp + d, fp + a, fp + b)
  when 160
    wv_abs_i32(stk, fp + d, fp + a)
  when 161
    wv_neg_i32(stk, fp + d, fp + a)
  when 163
    wv_all_true_i32(stk, fp + d, fp + a)
  when 164
    wv_bitmask_i32(stk, fp + d, fp + a)
  when 167
    wv_ext_low_s_i32(stk, fp + d, fp + a)
  when 168
    wv_ext_high_s_i32(stk, fp + d, fp + a)
  when 169
    wv_ext_low_u_i32(stk, fp + d, fp + a)
  when 170
    wv_ext_high_u_i32(stk, fp + d, fp + a)
  when 171
    wv_shl_i32(stk, fp + d, fp + a, fp + b)
  when 172
    wv_shr_s_i32(stk, fp + d, fp + a, fp + b)
  when 173
    wv_shr_u_i32(stk, fp + d, fp + a, fp + b)
  when 174
    wv_add_i32(stk, fp + d, fp + a, fp + b)
  when 177
    wv_sub_i32(stk, fp + d, fp + a, fp + b)
  when 181
    wv_mul_i32(stk, fp + d, fp + a, fp + b)
  when 182
    wv_min_s_i32(stk, fp + d, fp + a, fp + b)
  when 183
    wv_min_u_i32(stk, fp + d, fp + a, fp + b)
  when 184
    wv_max_s_i32(stk, fp + d, fp + a, fp + b)
  when 185
    wv_max_u_i32(stk, fp + d, fp + a, fp + b)
  when 186
    wv_dot_i16(stk, fp + d, fp + a, fp + b)
  when 188
    wv_extmul_low_s_i32(stk, fp + d, fp + a, fp + b)
  when 189
    wv_extmul_high_s_i32(stk, fp + d, fp + a, fp + b)
  when 190
    wv_extmul_low_u_i32(stk, fp + d, fp + a, fp + b)
  when 191
    wv_extmul_high_u_i32(stk, fp + d, fp + a, fp + b)
  when 192
    wv_abs_i64(stk, fp + d, fp + a)
  when 193
    wv_neg_i64(stk, fp + d, fp + a)
  when 195
    wv_all_true_i64(stk, fp + d, fp + a)
  when 196
    wv_bitmask_i64(stk, fp + d, fp + a)
  when 199
    wv_ext_low_s_i64(stk, fp + d, fp + a)
  when 200
    wv_ext_high_s_i64(stk, fp + d, fp + a)
  when 201
    wv_ext_low_u_i64(stk, fp + d, fp + a)
  when 202
    wv_ext_high_u_i64(stk, fp + d, fp + a)
  when 203
    wv_shl_i64(stk, fp + d, fp + a, fp + b)
  when 204
    wv_shr_s_i64(stk, fp + d, fp + a, fp + b)
  when 205
    wv_shr_u_i64(stk, fp + d, fp + a, fp + b)
  when 206
    wv_add_i64(stk, fp + d, fp + a, fp + b)
  when 209
    wv_sub_i64(stk, fp + d, fp + a, fp + b)
  when 213
    wv_mul_i64(stk, fp + d, fp + a, fp + b)
  when 214
    wv_cmp_eq_i64(stk, fp + d, fp + a, fp + b)
  when 215
    wv_cmp_ne_i64(stk, fp + d, fp + a, fp + b)
  when 216
    wv_cmp_slt_i64(stk, fp + d, fp + a, fp + b)
  when 217
    wv_cmp_sgt_i64(stk, fp + d, fp + a, fp + b)
  when 218
    wv_cmp_sle_i64(stk, fp + d, fp + a, fp + b)
  when 219
    wv_cmp_sge_i64(stk, fp + d, fp + a, fp + b)
  when 220
    wv_extmul_low_s_i64(stk, fp + d, fp + a, fp + b)
  when 221
    wv_extmul_high_s_i64(stk, fp + d, fp + a, fp + b)
  when 222
    wv_extmul_low_u_i64(stk, fp + d, fp + a, fp + b)
  when 223
    wv_extmul_high_u_i64(stk, fp + d, fp + a, fp + b)
  when 224
    wv_fabs_f32(stk, fp + d, fp + a)
  when 225
    wv_fneg_f32(stk, fp + d, fp + a)
  when 227
    wv_sqrt_f32(stk, fp + d, fp + a)
  when 228
    wv_fadd_f32(stk, fp + d, fp + a, fp + b)
  when 229
    wv_fsub_f32(stk, fp + d, fp + a, fp + b)
  when 230
    wv_fmul_f32(stk, fp + d, fp + a, fp + b)
  when 231
    wv_fdiv_f32(stk, fp + d, fp + a, fp + b)
  when 232
    wv_fmin_f32(stk, fp + d, fp + a, fp + b)
  when 233
    wv_fmax_f32(stk, fp + d, fp + a, fp + b)
  when 234
    wv_pmin_f32(stk, fp + d, fp + a, fp + b)
  when 235
    wv_pmax_f32(stk, fp + d, fp + a, fp + b)
  when 236
    wv_fabs_f64(stk, fp + d, fp + a)
  when 237
    wv_fneg_f64(stk, fp + d, fp + a)
  when 239
    wv_sqrt_f64(stk, fp + d, fp + a)
  when 240
    wv_fadd_f64(stk, fp + d, fp + a, fp + b)
  when 241
    wv_fsub_f64(stk, fp + d, fp + a, fp + b)
  when 242
    wv_fmul_f64(stk, fp + d, fp + a, fp + b)
  when 243
    wv_fdiv_f64(stk, fp + d, fp + a, fp + b)
  when 244
    wv_fmin_f64(stk, fp + d, fp + a, fp + b)
  when 245
    wv_fmax_f64(stk, fp + d, fp + a, fp + b)
  when 246
    wv_pmin_f64(stk, fp + d, fp + a, fp + b)
  when 247
    wv_pmax_f64(stk, fp + d, fp + a, fp + b)
  when 248
    wv_tsat_s_i32x4(stk, fp + d, fp + a)
  when 249
    wv_tsat_u_i32x4(stk, fp + d, fp + a)
  when 250
    wv_cvt_s_f32x4(stk, fp + d, fp + a)
  when 251
    wv_cvt_u_f32x4(stk, fp + d, fp + a)
  when 252
    wv_tsat_s_zero(stk, fp + d, fp + a)
  when 253
    wv_tsat_u_zero(stk, fp + d, fp + a)
  when 254
    wv_cvt_low_s_f64(stk, fp + d, fp + a)
  when 255
    wv_cvt_low_u_f64(stk, fp + d, fp + a)
  when 256
    wv_rswizzle(stk, fp + d, fp + a, fp + b)
  when 257
    wv_rtrunc_s_i32x4(stk, fp + d, fp + a)
  when 258
    wv_rtrunc_u_i32x4(stk, fp + d, fp + a)
  when 259
    wv_rtrunc_s_zero(stk, fp + d, fp + a)
  when 260
    wv_rtrunc_u_zero(stk, fp + d, fp + a)
  when 261
    wv_rmadd_f32(stk, fp + d, fp + a, fp + b, fp + c)
  when 262
    wv_rnmadd_f32(stk, fp + d, fp + a, fp + b, fp + c)
  when 263
    wv_rmadd_f64(stk, fp + d, fp + a, fp + b, fp + c)
  when 264
    wv_rnmadd_f64(stk, fp + d, fp + a, fp + b, fp + c)
  when 265
    wv_laneselect265(stk, fp + d, fp + a, fp + b, fp + c)
  when 266
    wv_laneselect266(stk, fp + d, fp + a, fp + b, fp + c)
  when 267
    wv_laneselect267(stk, fp + d, fp + a, fp + b, fp + c)
  when 268
    wv_laneselect268(stk, fp + d, fp + a, fp + b, fp + c)
  when 269
    wv_rmin_f32(stk, fp + d, fp + a, fp + b)
  when 270
    wv_rmax_f32(stk, fp + d, fp + a, fp + b)
  when 271
    wv_rmin_f64(stk, fp + d, fp + a, fp + b)
  when 272
    wv_rmax_f64(stk, fp + d, fp + a, fp + b)
  when 273
    wv_rq15mulr_i16(stk, fp + d, fp + a, fp + b)
  when 274
    wv_rdot_i8(stk, fp + d, fp + a, fp + b)
  when 275
    wv_rdot_add(stk, fp + d, fp + a, fp + b, fp + c)
  else
    0
  0

fn wv_l8x8s(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %v = load <8 x i8>, ptr %q, align 1
    %r = sext <8 x i8> %v to <8 x i16>
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_l8x8u(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %v = load <8 x i8>, ptr %q, align 1
    %r = zext <8 x i8> %v to <8 x i16>
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_l16x4s(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %v = load <4 x i16>, ptr %q, align 1
    %r = sext <4 x i16> %v to <4 x i32>
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_l16x4u(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %v = load <4 x i16>, ptr %q, align 1
    %r = zext <4 x i16> %v to <4 x i32>
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_l32x2s(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %v = load <2 x i32>, ptr %q, align 1
    %r = sext <2 x i32> %v to <2 x i64>
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_l32x2u(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %v = load <2 x i32>, ptr %q, align 1
    %r = zext <2 x i32> %v to <2 x i64>
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_lsplat8(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %x = load i8, ptr %q, align 1
    %i = insertelement <16 x i8> poison, i8 %x, i64 0
    %r = shufflevector <16 x i8> %i, <16 x i8> poison, <16 x i32> zeroinitializer
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_lsplat16(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %x = load i16, ptr %q, align 1
    %i = insertelement <8 x i16> poison, i16 %x, i64 0
    %r = shufflevector <8 x i16> %i, <8 x i16> poison, <8 x i32> zeroinitializer
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_lsplat32(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %x = load i32, ptr %q, align 1
    %i = insertelement <4 x i32> poison, i32 %x, i64 0
    %r = shufflevector <4 x i32> %i, <4 x i32> poison, <4 x i32> zeroinitializer
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_lsplat64(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %x = load i64, ptr %q, align 1
    %i = insertelement <2 x i64> poison, i64 %x, i64 0
    %r = shufflevector <2 x i64> %i, <2 x i64> poison, <2 x i32> zeroinitializer
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_lzero32(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %x = load i32, ptr %q, align 1
    %r = insertelement <4 x i32> zeroinitializer, i32 %x, i64 0
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_lzero64(m, ea, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %x = load i64, ptr %q, align 1
    %r = insertelement <2 x i64> zeroinitializer, i64 %x, i64 0
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_llane8(m, ea, s, d, v, lane) (u8[] i64 i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %pv = getelementptr i64, ptr %sp, i64 %v
    %vv = load <16 x i8>, ptr %pv, align 8
    %x = load i8, ptr %q, align 1
    %r = insertelement <16 x i8> %vv, i8 %x, i64 %lane
    store <16 x i8> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_llane16(m, ea, s, d, v, lane) (u8[] i64 i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %pv = getelementptr i64, ptr %sp, i64 %v
    %vv = load <8 x i16>, ptr %pv, align 8
    %x = load i16, ptr %q, align 1
    %r = insertelement <8 x i16> %vv, i16 %x, i64 %lane
    store <8 x i16> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_llane32(m, ea, s, d, v, lane) (u8[] i64 i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %pv = getelementptr i64, ptr %sp, i64 %v
    %vv = load <4 x i32>, ptr %pv, align 8
    %x = load i32, ptr %q, align 1
    %r = insertelement <4 x i32> %vv, i32 %x, i64 %lane
    store <4 x i32> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_llane64(m, ea, s, d, v, lane) (u8[] i64 i64[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %pv = getelementptr i64, ptr %sp, i64 %v
    %vv = load <2 x i64>, ptr %pv, align 8
    %x = load i64, ptr %q, align 1
    %r = insertelement <2 x i64> %vv, i64 %x, i64 %lane
    store <2 x i64> %r, ptr %pd, align 8
    ret i64 0
  IR

fn wv_slane8(m, ea, s, d, lane) (u8[] i64 i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %vv = load <16 x i8>, ptr %pd, align 8
    %x = extractelement <16 x i8> %vv, i64 %lane
    store i8 %x, ptr %q, align 1
    ret i64 0
  IR

fn wv_slane16(m, ea, s, d, lane) (u8[] i64 i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %vv = load <8 x i16>, ptr %pd, align 8
    %x = extractelement <8 x i16> %vv, i64 %lane
    store i16 %x, ptr %q, align 1
    ret i64 0
  IR

fn wv_slane32(m, ea, s, d, lane) (u8[] i64 i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %vv = load <4 x i32>, ptr %pd, align 8
    %x = extractelement <4 x i32> %vv, i64 %lane
    store i32 %x, ptr %q, align 1
    ret i64 0
  IR

fn wv_slane64(m, ea, s, d, lane) (u8[] i64 i64[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %mp = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %mp, i64 %ea
    %sp = inttoptr i64 %s to ptr
    %pd = getelementptr i64, ptr %sp, i64 %d
    %vv = load <2 x i64>, ptr %pd, align 8
    %x = extractelement <2 x i64> %vv, i64 %lane
    store i64 %x, ptr %q, align 1
    ret i64 0
  IR

-> w_ext_simd_mem(ex, inst, sub, code, o, fp)
  mem = inst.mems[code[o]]
  stk = ex.stk
  data = mem.data
  if sub == 11
    ea = w_ea(ex, mem, stk[fp + code[o + 1]], code[o + 3], 16)
    wk_st128(data, ea, stk, fp + code[o + 2])
    return nil
  if sub >= 88 && sub <= 91
    n = 1 << (sub - 88)
    ea = w_ea(ex, mem, stk[fp + code[o + 1]], code[o + 3], n)
    v = fp + code[o + 2]
    lane = code[o + 4]
    if sub == 88
      wv_slane8(data, ea, stk, v, lane)
    elsif sub == 89
      wv_slane16(data, ea, stk, v, lane)
    elsif sub == 90
      wv_slane32(data, ea, stk, v, lane)
    else
      wv_slane64(data, ea, stk, v, lane)
    return nil
  d = fp + code[o + 1]
  addr = stk[fp + code[o + 2]]
  off = code[o + 3]
  if sub == 0
    wk_ld128(data, w_ea(ex, mem, addr, off, 16), stk, d)
  elsif sub >= 1 && sub <= 6
    ea = w_ea(ex, mem, addr, off, 8)
    if sub == 1
      wv_l8x8s(data, ea, stk, d)
    elsif sub == 2
      wv_l8x8u(data, ea, stk, d)
    elsif sub == 3
      wv_l16x4s(data, ea, stk, d)
    elsif sub == 4
      wv_l16x4u(data, ea, stk, d)
    elsif sub == 5
      wv_l32x2s(data, ea, stk, d)
    else
      wv_l32x2u(data, ea, stk, d)
  elsif sub == 7
    wv_lsplat8(data, w_ea(ex, mem, addr, off, 1), stk, d)
  elsif sub == 8
    wv_lsplat16(data, w_ea(ex, mem, addr, off, 2), stk, d)
  elsif sub == 9
    wv_lsplat32(data, w_ea(ex, mem, addr, off, 4), stk, d)
  elsif sub == 10
    wv_lsplat64(data, w_ea(ex, mem, addr, off, 8), stk, d)
  elsif sub == 92
    wv_lzero32(data, w_ea(ex, mem, addr, off, 4), stk, d)
  elsif sub == 93
    wv_lzero64(data, w_ea(ex, mem, addr, off, 8), stk, d)
  elsif sub >= 84 && sub <= 87
    n = 1 << (sub - 84)
    ea = w_ea(ex, mem, addr, off, n)
    lane = code[o + 4]
    v = fp + code[o + 5]
    if sub == 84
      wv_llane8(data, ea, stk, d, v, lane)
    elsif sub == 85
      wv_llane16(data, ea, stk, d, v, lane)
    elsif sub == 86
      wv_llane32(data, ea, stk, d, v, lane)
    else
      wv_llane64(data, ea, stk, d, v, lane)
  nil
