#!/usr/bin/env ruby
# frozen_string_literal: true

# Post-codegen injection: per-Interpreter args-array pool.
#
# Spinel emits a fresh sp_PolyArray for every method call via
# evaluate_args (≈ 1 alloc per call site, each ~448 bytes including
# the data buffer). For a full compile of compiler/tungsten.w that's
# hundreds of thousands of allocations and the dominant remaining
# driver of macOS jetsam pressure once Environment is pooled.
#
# We can't pool this from the Ruby side: spinel's local-var type
# inference would type `values = @args_pool.pop` as sp_RbVal (the
# pool stores PolyArrays in a poly array) which mismatches the
# `values.push(...)` call sites and the sp_PolyArray * return type.
# Patching the C output directly sidesteps the type-system entirely:
# we know sp_PolyArray* is the right type and we know the lifetime
# (lv_args dies at call_w_method exit), so we just wire it up.

if ARGV.length != 1
  warn "usage: inject_args_pool.rb <stage0.c>"
  exit 1
end

path = ARGV[0]
src  = File.read(path)
orig = src.dup

# 1. Inject the pool before evaluate_args' forward declaration. This remains
#    stable across backends that omit the old optional FFI-externs section.
#    The runtime array declarations are available by this point, and the pool
#    helpers are `static inline` so the compiler can fold them into call sites.
declaration_re = /^static sp_PolyArray \* sp_Interpreter_evaluate_args\([^\n]*\);\n/
declaration = src.match(declaration_re)
unless declaration
  warn "inject_args_pool: evaluate_args declaration not found in #{path}"
  exit 1
end

pool_block = <<~'C'
  /* ---- args-array pool (post-codegen injection) ----
     Recycles the sp_PolyArray that evaluate_args produces on every
     interpreter method call. Bounded at 4 K live entries — matches
     the Environment pool's cap and the deepest observed call depth
     in stage 0 has been ~hundreds. */
  #define SP_ARGS_POOL_CAP 4096
  static sp_PolyArray *sp_args_pool_data[SP_ARGS_POOL_CAP];
  static int sp_args_pool_count = 0;
  static inline sp_PolyArray *sp_args_alloc(void) {
    if (sp_args_pool_count > 0) {
      sp_PolyArray *a = sp_args_pool_data[--sp_args_pool_count];
      a->len = 0;
      return a;
    }
    return sp_PolyArray_new();
  }
  static inline void sp_args_release(sp_PolyArray *a) {
    if (a == NULL) return;
    if (sp_args_pool_count >= SP_ARGS_POOL_CAP) return;
    a->len = 0;
    sp_args_pool_data[sp_args_pool_count++] = a;
  }
C

src.insert(declaration.begin(0), "#{pool_block}\n")

# 2. Replace evaluate_args' fresh allocation with a pool pop.
#    There is exactly one `lv_values = sp_PolyArray_new();` inside
#    sp_Interpreter_evaluate_args' body, immediately after the
#    locals init. We scope the replacement to that function so any
#    unrelated `sp_PolyArray_new()` call elsewhere is untouched.
# Match on function name + `) {` (the definition, not the `;` forward
# decl) with a wildcard param list, so upstream re-typing a parameter
# (e.g. call_node mrb_int -> sp_RbVal between bootstrap baselines)
# doesn't break the injector. `[^)]*` is safe — no spinel param type
# contains a literal ')'.
fn_def_re = /static sp_PolyArray \* sp_Interpreter_evaluate_args\([^)]*\) \{/
fn_match = src.match(fn_def_re)
raise "evaluate_args definition not found" unless fn_match
fn_start = fn_match.begin(0)

# Find the function's opening brace, then the matching close. The
# body is short and contains no nested function definitions so a
# simple brace-balance walk is reliable.
brace_open = src.index("{", fn_start)
fn_end = nil
depth = 0
i = brace_open
while i < src.length
  c = src[i]
  if c == "{"
    depth += 1
  elsif c == "}"
    depth -= 1
    if depth.zero?
      fn_end = i
      break
    end
  end
  i += 1
end
raise "evaluate_args body unterminated" unless fn_end

body = src[brace_open..fn_end]
new_body = body.sub("lv_values = sp_PolyArray_new();",
                    "lv_values = sp_args_alloc();")
raise "evaluate_args alloc site not found" if new_body == body
src[brace_open..fn_end] = new_body

# 3. Insert sp_args_release(lv_args) before each
#    `SP_GC_RESTORE(); return _t...;` pair inside
#    sp_Interpreter_call_w_method. There are two such returns: the
#    early-return for nil-method, and the main return after pool
#    push-back. We must NOT patch the body of call_w_method_from_nodes
#    (which sits right after) — its lv_args is the intermediate
#    PolyArray*, but it's already covered because call_w_method itself
#    will release it on entry/exit cycles. The from_nodes wrapper has
#    no lv_args local of its own, so the substitution can't false-
#    positive there.
# Same wildcard-param match as evaluate_args above — robust to the
# call_node param being typed mrb_int (bs7) or sp_RbVal (bs8+).
fn2_def_re = /static sp_RbVal sp_Interpreter_call_w_method\([^)]*\) \{/
fn2_match = src.match(fn2_def_re)
raise "call_w_method definition not found" unless fn2_match
fn2_start = fn2_match.begin(0)
brace_open2 = src.index("{", fn2_start)
fn2_end = nil
depth = 0
i = brace_open2
while i < src.length
  c = src[i]
  if c == "{"
    depth += 1
  elsif c == "}"
    depth -= 1
    if depth.zero?
      fn2_end = i
      break
    end
  end
  i += 1
end
raise "call_w_method body unterminated" unless fn2_end

body2 = src[brace_open2..fn2_end]
# Inject release before SP_GC_RESTORE(); return _t... pattern. We
# only match returns whose value is an _tNNN temp (the compiler's
# generated return tag) to avoid catching macro-internal RESTOREs.
# Older generated functions restore the GC frame and return a temporary on one
# line; current ones emit plain return statements because the restore is
# handled by the runtime configuration. Support both shapes.
patched2 = body2.gsub(/(SP_GC_RESTORE\(\);\s*return _t\d+;)/m,
                      "sp_args_release(lv_args); \\1")
if patched2 == body2
  patched2 = body2.gsub(/^(\s*)(return\s+[^;]+;)$/) do
    "#{$1}sp_args_release(lv_args);\n#{$1}#{$2}"
  end
end
if patched2 == body2
  raise "call_w_method: no return path patched"
end
src[brace_open2..fn2_end] = patched2

if src == orig
  warn "inject_args_pool: no changes made (already patched?)"
  exit 0
end

File.write(path, src)
puts "inject_args_pool: patched #{path} (+#{(src.length - orig.length)} bytes)"
