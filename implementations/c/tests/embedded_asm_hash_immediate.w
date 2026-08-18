# Regression: the stage0 lexer must not treat AArch64's `#8` immediate as a
# Tungsten comment while scanning an embedded asm heredoc. Doing so hid the
# closing `]`, suppressed all later layout tokens, and made the following
# operator definition fail with an unmatched delimiter.

+ EmbeddedAsmHashImmediate
  fn __load_second(ptr) (i64) i64
    asm <<~ASM
      ldr x0, [x0, #8]
      ret
    ASM

  -> &(other)(EmbeddedAsmHashImmediate)
    self

<< "ok"
