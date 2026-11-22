# wasm/kernels — LLVM IR leaf kernels for the interpreter: IEEE float arithmetic on bit
# patterns, conversions with wasm's trap/saturation rules, bit counts, unsigned compares and
# unaligned little-endian memory access. All are alwaysinline, so a typed caller compiles to
# the bare instruction. Floats travel as their bits in i64 (f32 zero-extended).
#
# Compile-only (embedded IR has no interpreter path); the engine itself is compiled.

fn wk_f32_add(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fadd float %fx, %fy
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_add(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fadd double %fx, %fy
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_sub(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fsub float %fx, %fy
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_sub(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fsub double %fx, %fy
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_mul(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fmul float %fx, %fy
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_mul(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fmul double %fx, %fy
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_div(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fdiv float %fx, %fy
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_div(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fdiv double %fx, %fy
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_min(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = call float @llvm.minimum.f32(float %fx, float %fy)
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_min(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = call double @llvm.minimum.f64(double %fx, double %fy)
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_max(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = call float @llvm.maximum.f32(float %fx, float %fy)
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_max(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = call double @llvm.maximum.f64(double %fx, double %fy)
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_sqrt(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fx = bitcast i32 %x to float
    %r = call float @llvm.sqrt.f32(float %fx)
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_sqrt(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %r = call double @llvm.sqrt.f64(double %fx)
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_ceil(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fx = bitcast i32 %x to float
    %r = call float @llvm.ceil.f32(float %fx)
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_ceil(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %r = call double @llvm.ceil.f64(double %fx)
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_floor(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fx = bitcast i32 %x to float
    %r = call float @llvm.floor.f32(float %fx)
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_floor(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %r = call double @llvm.floor.f64(double %fx)
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_trunc(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fx = bitcast i32 %x to float
    %r = call float @llvm.trunc.f32(float %fx)
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_trunc(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %r = call double @llvm.trunc.f64(double %fx)
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_nearest(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fx = bitcast i32 %x to float
    %r = call float @llvm.roundeven.f32(float %fx)
    %ri = bitcast float %r to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_f64_nearest(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %r = call double @llvm.roundeven.f64(double %fx)
    %ri = bitcast double %r to i64
    ret i64 %ri
  IR

fn wk_f32_eq(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fcmp oeq float %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f64_eq(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fcmp oeq double %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f32_ne(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fcmp une float %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f64_ne(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fcmp une double %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f32_lt(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fcmp olt float %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f64_lt(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fcmp olt double %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f32_gt(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fcmp ogt float %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f64_gt(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fcmp ogt double %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f32_le(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fcmp ole float %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f64_le(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fcmp ole double %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f32_ge(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %y = trunc i64 %b to i32
    %fx = bitcast i32 %x to float
    %fy = bitcast i32 %y to float
    %r = fcmp oge float %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_f64_ge(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %fx = bitcast i64 %a to double
    %fy = bitcast i64 %b to double
    %r = fcmp oge double %fx, %fy
    %rz = zext i1 %r to i64
    ret i64 %rz
  IR

fn wk_chk_f32_s32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fs = bitcast i32 %x to float
    %f = fpext float %fs to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp oge double %t, 0xC1E0000000000000
    %h = fcmp olt double %t, 0x41E0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f32_s32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = bitcast i32 %x to float
    %r = call i32 @llvm.fptosi.sat.i32.f32(float %f)
    %rz = zext i32 %r to i64
    ret i64 %rz
  IR

fn wk_chk_f32_u32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fs = bitcast i32 %x to float
    %f = fpext float %fs to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp ogt double %t, 0xBFF0000000000000
    %h = fcmp olt double %t, 0x41F0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f32_u32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = bitcast i32 %x to float
    %r = call i32 @llvm.fptoui.sat.i32.f32(float %f)
    %rz = zext i32 %r to i64
    ret i64 %rz
  IR

fn wk_chk_f32_s64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fs = bitcast i32 %x to float
    %f = fpext float %fs to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp oge double %t, 0xC3E0000000000000
    %h = fcmp olt double %t, 0x43E0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f32_s64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = bitcast i32 %x to float
    %r = call i64 @llvm.fptosi.sat.i64.f32(float %f)
    ret i64 %r
  IR

fn wk_chk_f32_u64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %fs = bitcast i32 %x to float
    %f = fpext float %fs to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp ogt double %t, 0xBFF0000000000000
    %h = fcmp olt double %t, 0x43F0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f32_u64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = bitcast i32 %x to float
    %r = call i64 @llvm.fptoui.sat.i64.f32(float %f)
    ret i64 %r
  IR

fn wk_chk_f64_s32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp ogt double %t, 0xC1E0000000200000
    %h = fcmp olt double %t, 0x41E0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f64_s32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %r = call i32 @llvm.fptosi.sat.i32.f64(double %f)
    %rz = zext i32 %r to i64
    ret i64 %rz
  IR

fn wk_chk_f64_u32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp ogt double %t, 0xBFF0000000000000
    %h = fcmp olt double %t, 0x41F0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f64_u32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %r = call i32 @llvm.fptoui.sat.i32.f64(double %f)
    %rz = zext i32 %r to i64
    ret i64 %rz
  IR

fn wk_chk_f64_s64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp oge double %t, 0xC3E0000000000000
    %h = fcmp olt double %t, 0x43E0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f64_s64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %r = call i64 @llvm.fptosi.sat.i64.f64(double %f)
    ret i64 %r
  IR

fn wk_chk_f64_u64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %t = call double @llvm.trunc.f64(double %f)
    %nan = fcmp uno double %f, %f
    %l = fcmp ogt double %t, 0xBFF0000000000000
    %h = fcmp olt double %t, 0x43F0000000000000
    %ok = and i1 %l, %h
    %r1 = select i1 %ok, i64 0, i64 2
    %r = select i1 %nan, i64 1, i64 %r1
    ret i64 %r
  IR

fn wk_sat_f64_u64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %r = call i64 @llvm.fptoui.sat.i64.f64(double %f)
    ret i64 %r
  IR

fn wk_cvt_s32_f32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = sitofp i32 %x to float
    %ri = bitcast float %f to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_cvt_u32_f32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = uitofp i32 %x to float
    %ri = bitcast float %f to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_cvt_s64_f32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = sitofp i64 %a to float
    %ri = bitcast float %f to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_cvt_u64_f32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = uitofp i64 %a to float
    %ri = bitcast float %f to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_cvt_s32_f64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = sitofp i32 %x to double
    %ri = bitcast double %f to i64
    ret i64 %ri
  IR

fn wk_cvt_u32_f64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = uitofp i32 %x to double
    %ri = bitcast double %f to i64
    ret i64 %ri
  IR

fn wk_cvt_s64_f64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = sitofp i64 %a to double
    %ri = bitcast double %f to i64
    ret i64 %ri
  IR

fn wk_cvt_u64_f64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = uitofp i64 %a to double
    %ri = bitcast double %f to i64
    ret i64 %ri
  IR

fn wk_demote(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %f = bitcast i64 %a to double
    %g = fptrunc double %f to float
    %ri = bitcast float %g to i32
    %rz = zext i32 %ri to i64
    ret i64 %rz
  IR

fn wk_promote(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %f = bitcast i32 %x to float
    %g = fpext float %f to double
    %ri = bitcast double %g to i64
    ret i64 %ri
  IR

fn wk_clz32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %c = call i32 @llvm.ctlz.i32(i32 %x, i1 false)
    %r = zext i32 %c to i64
    ret i64 %r
  IR

fn wk_ctz32(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %c = call i32 @llvm.cttz.i32(i32 %x, i1 false)
    %r = zext i32 %c to i64
    ret i64 %r
  IR

fn wk_clz64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = call i64 @llvm.ctlz.i64(i64 %a, i1 false)
    ret i64 %c
  IR

fn wk_ctz64(a) (i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = call i64 @llvm.cttz.i64(i64 %a, i1 false)
    ret i64 %c
  IR

-> wk_popcnt(a) (i64) i64
  popcount(a)

fn wk_rotl32(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %n = trunc i64 %b to i32
    %c = call i32 @llvm.fshl.i32(i32 %x, i32 %x, i32 %n)
    %r = zext i32 %c to i64
    ret i64 %r
  IR

fn wk_rotr32(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %x = trunc i64 %a to i32
    %n = trunc i64 %b to i32
    %c = call i32 @llvm.fshr.i32(i32 %x, i32 %x, i32 %n)
    %r = zext i32 %c to i64
    ret i64 %r
  IR

fn wk_rotl64(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = call i64 @llvm.fshl.i64(i64 %a, i64 %a, i64 %b)
    ret i64 %c
  IR

fn wk_rotr64(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = call i64 @llvm.fshr.i64(i64 %a, i64 %a, i64 %b)
    ret i64 %c
  IR

fn wk_lshr64(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %n = and i64 %b, 63
    %c = lshr i64 %a, %n
    ret i64 %c
  IR

fn wk_udiv64(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = udiv i64 %a, %b
    ret i64 %c
  IR

fn wk_urem64(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = urem i64 %a, %b
    ret i64 %c
  IR

fn wk_ult(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = icmp ult i64 %a, %b
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn wk_ugt(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = icmp ugt i64 %a, %b
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn wk_ule(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = icmp ule i64 %a, %b
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn wk_uge(a, b) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %c = icmp uge i64 %a, %b
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn wk_ld8u(m, a) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i8, ptr %q, align 1
    %r = zext i8 %v to i64
    ret i64 %r
  IR

fn wk_ld8s(m, a) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i8, ptr %q, align 1
    %r = sext i8 %v to i64
    ret i64 %r
  IR

fn wk_ld16u(m, a) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i16, ptr %q, align 1
    %r = zext i16 %v to i64
    ret i64 %r
  IR

fn wk_ld16s(m, a) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i16, ptr %q, align 1
    %r = sext i16 %v to i64
    ret i64 %r
  IR

fn wk_ld32u(m, a) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i32, ptr %q, align 1
    %r = zext i32 %v to i64
    ret i64 %r
  IR

fn wk_ld32s(m, a) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i32, ptr %q, align 1
    %r = sext i32 %v to i64
    ret i64 %r
  IR

fn wk_ld64(m, a) (u8[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i64, ptr %q, align 1
    ret i64 %v
  IR

fn wk_st8(m, a, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %t = trunc i64 %v to i8
    store i8 %t, ptr %q, align 1
    ret i64 0
  IR

fn wk_st16(m, a, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %t = trunc i64 %v to i16
    store i16 %t, ptr %q, align 1
    ret i64 0
  IR

fn wk_st32(m, a, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %t = trunc i64 %v to i32
    store i32 %t, ptr %q, align 1
    ret i64 0
  IR

fn wk_st64(m, a, v) (u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    store i64 %v, ptr %q, align 1
    ret i64 0
  IR

fn wk_ld128(m, a, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %v = load i128, ptr %q, align 1
    %sp = inttoptr i64 %s to ptr
    %sq = getelementptr i64, ptr %sp, i64 %d
    store i128 %v, ptr %sq, align 8
    ret i64 0
  IR

fn wk_st128(m, a, s, d) (u8[] i64 i64[] i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %q = getelementptr i8, ptr %p, i64 %a
    %sp = inttoptr i64 %s to ptr
    %sq = getelementptr i64, ptr %sp, i64 %d
    %v = load i128, ptr %sq, align 8
    store i128 %v, ptr %q, align 1
    ret i64 0
  IR

fn wk_memmove(m, d, s, n) (u8[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %dq = getelementptr i8, ptr %p, i64 %d
    %sq = getelementptr i8, ptr %p, i64 %s
    call void @llvm.memmove.p0.p0.i64(ptr %dq, ptr %sq, i64 %n, i1 false)
    ret i64 0
  IR

fn wk_memcpy2(dm, d, sm, s, n) (u8[] i64 u8[] i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %dm to ptr
    %dq = getelementptr i8, ptr %p, i64 %d
    %p2 = inttoptr i64 %sm to ptr
    %sq = getelementptr i8, ptr %p2, i64 %s
    call void @llvm.memmove.p0.p0.i64(ptr %dq, ptr %sq, i64 %n, i1 false)
    ret i64 0
  IR

fn wk_memset(m, d, v, n) (u8[] i64 i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    %p = inttoptr i64 %m to ptr
    %dq = getelementptr i8, ptr %p, i64 %d
    %b = trunc i64 %v to i8
    call void @llvm.memset.p0.i64(ptr %dq, i8 %b, i64 %n, i1 false)
    ret i64 0
  IR
