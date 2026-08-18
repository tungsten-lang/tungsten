# Class-scoped embedded `ll` kernels: a typed `fn` whose body is a single
# ll heredoc, INSIDE a class body, compiles to a class-mangled raw-ABI
# kernel that sibling methods call by bare name through the raw path (no
# dispatch, no boxing). COMPILE-ONLY, like every embedded body — this spec
# runs on the compiled engine only.

+ KernelHost
  fn __spec_k_combine(a, b) (i64 i64) i64
    ll <<~IR
      %two = shl i64 %a, 1
      %s = add i64 %two, %b
      ret i64 %s
    IR

  fn __spec_guarded_raw(seed) (i64) i64
    ll <<~IR
      ret i64 %seed
    IR

  on arm64
    fn __spec_guarded_raw(seed) (i64) i64
      asm <<~ASM
        mov x0, #22
        ret
      ASM

  -> combine(x, y)
    __spec_k_combine(x ## i64, y ## i64)

  -> guarded_raw(x)
    __spec_guarded_raw(x ## i64)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

h = KernelHost.new
check("class_kernel.combine", h.combine(20, 2), 42)
check("class_kernel.zero_left", h.combine(0, 7), 7)
check("class_kernel.negative", h.combine(0 - 4, 3), 0 - 5)
check("class_kernel.guarded_raw_override", h.guarded_raw(11), 22)
<< "embedded_class_kernel_spec: all checks passed"
