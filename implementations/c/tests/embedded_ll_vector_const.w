# Regression: embedded-`ll` heredoc bodies are lexed as ordinary tokens by
# the bootstrap lexer (it has no heredoc form), so a body line ending in an
# inline vector constant — `... <2 x i32> <i32 1, i32 2>` — used to match
# its trailing `>` as a top-level comparison whose right-hand span is empty.
# binary_node_ast then returned bare nil with no tc_error_set, the whole
# file's bootstrap parse failed, and the VM exited 1 with no output (this
# silently killed stage 1 when such a kernel was added to core/numeric/
# big_int.w, which compiler/tungsten.w pulls in via `use`). The kernel is
# never called; it only has to survive parsing and class compilation.
+ EmbeddedLlVectorConst
  fn __shufmask_probe(rp, ap, n) (i64 i64 i64) i64
    ll <<~IR
      entry:
        %rq = inttoptr i64 %rp to ptr
        %aq = inttoptr i64 %ap to ptr
        %a = load <2 x i64>, ptr %aq, align 8
        %b = load <2 x i64>, ptr %rq, align 8
        %s = shufflevector <2 x i64> %a, <2 x i64> %b, <2 x i32> <i32 1, i32 2>
        store <2 x i64> %s, ptr %rq, align 8
        ret i64 0
    IR

<< "ok"
