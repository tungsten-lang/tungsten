use ../../compiler/lib/emitter

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

inst = {op: :setjmp, temp: "%sj", buf: "%buf"}
posix = render_instruction(inst, {}, {}, nil, "", true, false)
windows = render_instruction(inst, {}, {}, nil, "", false, true)

check("posix uses _setjmp", posix == "%sj = call i32 @_setjmp(ptr %buf)")
check("windows uses setjmp", windows == "%sj = call i32 @setjmp(ptr %buf)")

decls = declare_runtime()
check("declares _setjmp returns_twice", decls.include?("declare i32 @_setjmp(ptr) nounwind returns_twice"))
check("declares setjmp returns_twice", decls.include?("declare i32 @setjmp(ptr) nounwind returns_twice"))

check("detect windows triple", emit_target_is_windows({llvm_triple: "x86_64-w64-windows-gnu"}))
check("detect mingw triple", emit_target_is_windows({llvm_triple: "x86_64-w64-mingw32"}))
check("posix triple", !emit_target_is_windows({llvm_triple: "aarch64-apple-darwin"}))
