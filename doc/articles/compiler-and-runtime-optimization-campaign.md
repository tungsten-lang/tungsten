# Profiling and Optimizing the Self-Hosted Tungsten Compiler and Runtime

Because Tungsten's compiler (`compiler/tungsten.w`) and standard library (`core/`) are written in Tungsten, every improvement to the language's runtime representations, standard library primitives, or mid-end/backend passes compounds twice: once in user programs, and again in the compiler itself when building Stage 2.

This article documents a multi-round, profile-guided optimization campaign across the C runtime (`runtime/runtime.c`), the native standard library (`core/`), and the self-hosted WIRE compiler pipeline (`compiler/lib/`), along with the pitfalls we hit when optimizing `-O0` (`--dev`) vs. `-O3 --lto` (`--release`) builds and ten concrete areas where Tungsten should improve next.

---

## 1. String Interning and Unified Symbol/AST Tables

### The bottleneck

In the slab AST (`doc/articles/slab-ast-design.md`), single-string leaf nodes (`:var`, `:ivar`, `:cvar`, `:symbol`, `:string`) store a 32-bit intern ID in the `WValue` handle payload (`sentinel 257`) instead of allocating an arena slot. A full self-compile of `compiler/tungsten.w` reads leaf node strings (`w_ast_intern_str_of`) over 42,000 times and interns thousands of identifiers and symbols.

Profiling `runtime/runtime.c` exposed four redundancies in the original interning path:

1. **Byte-at-a-time FNV-1a hashing (`w_intern_hash_bytes`):** Every identifier hash walked one byte per loop iteration even though `runtime/wvalue.h` already ships 8-byte bulk `w_hash_wyhash`.
2. **No SSO-5 fast path for AST leaves or `w_str_to_sym`:** Strings and symbols up to 5 UTF-8 bytes fit inline in a single 64-bit `WValue` (`W_TAG_STRINGSYM | (len << 1) | is_sym | (bytes << 4)`), yet `w_ast_intern_node` and `w_str_to_sym` still hashed and probed the global intern table for `"i"`, `"x"`, `"n"`, and `"ok"`.
3. **Unmemoized `w_ast_intern_str_of`:** `WInternEntry` stored raw `char *bytes` and `uint32_t len`, so every `ast_get(node, :name)` call on a `>5`-byte identifier called `w_string(e->bytes)` from scratch — re-probing the string slab or allocating a heap `WString`.
4. **Duplicate symbol table (`g_sym_table` vs. `g_intern_table`):** `w_str_to_sym` maintained a separate open-addressed table (`g_sym_table`) that `malloc`ed a `WSymbol` header and `strdup`ed the bytes a second time, even when the string was already interned in `g_intern_table`.

### The fix

- **8-byte `wyhash` + `first_word` probe guard:** `w_intern_hash_bytes` now delegates directly to `w_hash_wyhash(p, n)`, and `WInternEntry` stores `uint64_t first_word` (the first up-to-8 bytes loaded via `w_hash_read_le64`) so probe collisions reject mismatched entries in one register compare before calling `memcmp`.
- **Cached `str_wval` and `sym_wval` on `WInternEntry`:** Each `WInternEntry` caches both its materialized `WValue` string (`str_wval`, slab-backed for 6–61 bytes or immortally heap-backed for `>61` bytes) and its `WSymbol` (`sym_wval`). `w_ast_intern_str_of` and `w_str_to_sym` are now $O(1)$ field reads after first materialization.
- **Inline SSO-5 bypass:** `w_str_to_sym` converts any inline string (`mode <= 5`) into its symbol `WValue` via a single bitwise OR (`str | 1ULL`), and `w_ast_intern_node` packs `<=5`-byte leaves without touching `g_intern_table`.

---

## 2. Eliminating Subprocess Spawns in Host Target Detection

### The bottleneck

Running `bin/tungsten -e "<< 1 + 1"` with a cold target-probe cache took **136 ms**, even though parsing, lowering, and executing the expression took under 20 ms. Tracing `compiler/lib/host_cache.w` showed why: on macOS, `detect_host_arch` and `detect_host_cpu` called `capture("sysctl -n hw.optional.arm64 2>/dev/null")` and `capture("sysctl -n machdep.cpu.brand_string 2>/dev/null")`, each of which spawned `/bin/sh -c` + `/usr/sbin/sysctl` via `popen()`.

### The fix

We exposed `sysctlbyname_int(name)` and `sysctlbyname_str(name)` in `runtime/runtime.c` (backed by `<sys/sysctl.h>` `sysctlbyname`) and wired `compiler/lib/host_cache.w` to query the kernel directly in-process. Cold target-detection latency dropped from **136 ms to 23 ms (5.9× faster)** with zero child processes spawned.

---

## 3. Native Core Migrations: Keeping Hot Loops in LLVM IR

Across `core/`, many methods on packed value types (`Int`, `Float`, `Rational`, `IPv4`, `String`) originally crossed the FFI boundary via `ccall("w_...")`. Because `ccall` targets an external C symbol, LLVM cannot inline across it in non-LTO (`bin/tungsten file.w`) builds, cannot hoist loop-invariant checks out of callers, and must spill registers across the C ABI boundary.

Using Tungsten's `$value` raw-word view and `wvalue_from_bits` zero-cost rebox intrinsic (both of which the tree-walking interpreter also supports via `eval_gvar` and `eval_intrinsic`), we migrated the hot paths into pure Tungsten:

| Module | Migrated / Fast-Pathed Methods | Mechanism |
| :--- | :--- | :--- |
| [`core/float.w`](../../core/float.w) | `nan?`, `infinite?`, `finite?`, `zero?`, `positive?`, `negative?`, `abs` | Direct bit-manipulation on biased IEEE-754 `WValue` (`$value - 0x0001000000000000`) |
| [`core/ipv4.w`](../../core/ipv4.w) | `address`, `prefix`, `octets`, `loopback?`, `private?`, `multicast?`, `link_local?`, `unspecified?`, `broadcast?` | Inline bitfield extraction on `W_PACKED_IPV4` (`0xFFFE` tag, subtype 5) |
| [`core/numeric/rational.w`](../../core/numeric/rational.w) | `numerator`, `denominator` | Inline extraction of 25-bit signed numerator and 20-bit unsigned denominator on `W_PACKED_RATIONAL` (`($value >> 45) & 0x7FFFF == 0x7FFF2`), falling back to `ccall` for heap `WBigRational` |
| [`core/numeric/int.w`](../../core/numeric/int.w) | `divmod`, `tdiv`, `tmod`, `tdivmod`, `fdiv`, `fmod`, `fdivmod`, `cdiv`, `cmod`, `cdivmod`, `divexact`, `divisible?`, `congruent?`, `isqrt_rem`, `perfect_square?`, `popcount`, `hamdist` | Inline 48-bit signed immediate guard (`(($value >> 48) & 0xFFFF) == 0xFFFA`) with hardware `sdiv`/`srem`/`ctpop`/`sqrt`, falling back to `w_bigint_*` on overflow or `BigInt` operands |
| [`core/string.w`](../../core/string.w) | `ascii_only?`, `valid_utf8?`, `index`, `rindex`, `include?`, `starts_with?`, `ends_with?`, `byte_at` | SSO-5 bit extraction (`mode <= 5`) + SWAR 8-byte ASCII/UTF-8 validation + Crochemore–Perrin Two-Way substring search (`str_find_bytes`) |
| [`core/regex.w`](../../core/regex.w) | `match?`, `index`, `=~`, `match`, `scan` | Literal prefix + 3-way anchor (`^`, `\z`, `$`) extraction at compile time; unanchored literal-prefix patterns prefilter candidate start offsets with `str_find_bytes` before entering the Thompson/Pike VM |

---

## 4. Optimizing the Self-Hosted Compiler Pipeline (`compiler/lib/`)

On a cold self-compile of `compiler/tungsten.w` (4,935 functions, ~298,000 WIRE instructions), time is split across six main stages:

```text
load+parse (9%) → lowering to wire (53%) → cfg+ssa (4%) → escape + free insertion (14%) → content hash (8%) → emit llvm ir (12%)
```

### 4.1 AST & WIRE Kind Dispatch (`ast_schema.w`, `wire.w`)

Every compiler pass begins its per-node or per-instruction loop with `ast_kind(node)` or `wire_kind(inst)`. Previously, `ast_kind(node)` called `ccall_nobox("w_node_kind_extern", node)` to extract the integer kind ID and then indexed a 200-element Tungsten `Array` (`ast_kind_id_to_symbol[id]`), and `wire_kind(inst)` did the same on a 274-element `wire_kind_id_to_symbol` array (~600,000 array lookups per self-compile).

We moved both symbol tables into lazy-initialized static C arrays in `runtime/runtime.c` (`w_node_kind_sym_extern` and `w_wire_kind_sym_extern`) and `implementations/c/src/node_arena.c`. Each call now returns the pre-interned `WValue` symbol directly from a C array read with zero Tungsten array bounds/tag checks.

### 4.2 Inline Canonical Switch Keys (`@__w_switch_canonical_fast`)

Tungsten compiles `case` statements with symbol or string literal arms into a single LLVM `switch i64` instruction using compile-time SSO-5 or slab `WValue` keys. Because a runtime symbol/string might live on the heap even when its byte length is $\le 5$, the lowered switch preamble called `@w_switch_canonical(subj)` on every `case` evaluation.

In the compiler, 90%+ of switched symbols (`:var`, `:call`, `:int`, `:br`, `:phi`, etc.) are $\le 5$ bytes and already in canonical SSO-5 form. We injected a private `alwaysinline` LLVM IR helper `@__w_switch_canonical_fast(i64 %v)` (`compiler/lib/emitter/primitives.w`) that checks `((v >> 1) & 7) <= 5` in three register instructions and returns `%v` immediately, calling `@w_switch_canonical` only on the cold slab/heap path.

### 4.3 Lowering Hot Paths (`naming.w`, `literals.w`, `assign.w`, `types.w`)

- **Identifier & Register Name Memoization ([`compiler/lib/naming.w`](../../compiler/lib/naming.w)):** `llvm_safe_name(name)` and `llvm_param_reg(name)` were called tens of thousands of times on the same parameter names (`self`, `ctx`, `node`, `wfn`, `inst`, `i`), allocating `name.chars()` and `"%." + safe` on every call. Caching `llvm_safe_name_cache` and `llvm_param_reg_cache` turned 95%+ of calls into a single hash hit, while routing `utf8_byte_length(s)` directly to `ccall_nobox("w_string_byte_length", s)` on the native runtime avoided `s.chars()` allocations across 35,000 string/symbol literal lowerings.
- **SSO-5 Literal Text Caching ([`compiler/lib/lowering/literals.w`](../../compiler/lib/lowering/literals.w)):** `lower_string` and `lower_symbol` computed `wvalue_literal_text(sso5_wvalue(s))` (which boxes a 64-bit unsigned integer into a `WBigInt`, formats hex via `w_int_to_hex_str`, and prepends `"u0x"`) on every short string or symbol literal (~18,800 sites per compile). Caching `sso5_str_text_cache[s]` and `sso5_sym_text_cache[s]` eliminated all repeated `WBigInt` hex formatting.
- **Fast-Pathing `lower_var` ([`compiler/lib/lowering/assign.w`](../../compiler/lib/lowering/assign.w)):** `lower_var` is called 33,934 times per self-compile. Guarding `build_defines[name]` on `build_defines.size() > 0`, skipping raw machine-int/float storage predicates when `raw_type == nil`, deferring `top_level_var_types[name]` until `top_level_vars[name] == true`, and emitting `emit_wire_load_i64` directly instead of `emit_wire_dynamic_2` removed 4 hash lookups and 2 helper calls per local variable read.

### 4.4 Ownership, Escape, and Free Insertion (`ownership.w`, `escape.w`)

`ownership_pass` runs in parallel across 8 deterministic worker threads, whereas `free_insertion_pass` and `escape_pass` run sequentially on the main thread:

- **Shifting Pre-Scans into Parallel `ownership_analyze` ([`compiler/lib/ownership.w`](../../compiler/lib/ownership.w)):** Previously, `free_insertion_pass` sequentially called `loop_carried_releases`, `owned_slot_releases`, and `int_temp_releases` on every function, each of which walked all basic blocks and instructions just to discover that 85%+ of functions have no `store_i64` of owned values, no loop arithmetic, or no boxed integer arithmetic. We recorded `has_setjmp`, `has_store_i64`, `has_loop_arith`, `has_int_arith`, and `has_direct_call` on `func[:ownership]` during the parallel `ownership_analyze` pass so `free_insertion_pass` skips inapplicable sub-passes in $O(1)$.
- **Filtering Use-Map Allocations ([`compiler/lib/ownership.w`](../../compiler/lib/ownership.w)):** In `int_temp_releases` and `owned_slot_releases`, `record_use(uses, reg, loc)` previously allocated a `uses[reg]` array for *every* register operand of *every* instruction in the function, even though `uses[reg]` is only ever queried for registers in `arith_set` (for `int_temp_releases`) or `tracked_use` (for `owned_slot_releases`). Filtering `uses` population by those sets eliminated tens of thousands of dead array/hash allocations per compile.
- **Zero-Parameter Fast Path in `escape_analyze` ([`compiler/lib/escape.w`](../../compiler/lib/escape.w)):** For 0-parameter functions (including `main`, which has 24,098 instructions in `compiler/tungsten.w`), parameter escape derivation is vacuous — the only output needed is `pure: !has_side_effects`. Adding a dedicated 0-parameter loop that checks only for side effects and `break`s on the first side-effecting instruction cut `escape` time by **14.1%**.

### 4.5 Content Hash and LLVM IR Emitter (`content_hash.w`, `emitter/`)

- **Precomputed Opcode Tokens & Fast-Pathed Instructions ([`compiler/lib/content_hash.w`](../../compiler/lib/content_hash.w)):** Precomputed `canonical_op_tokens` (`"o1"`..`"o279"`) indexed by `w_wire_kind_extern(inst)` and added dedicated arms in `encode_inst` for `:call_loc_set_col` (48,660 sites), `:cleanup_pop`, `:icmp_ne_zero`, `:inttoptr_i64`, `:ptr_to_i64`, `:i64_to_ptr`, `:ivar_get_idx`, and `:ivar_set_idx`, avoiding ~1.2M failed `wire_get` probes in the generic fallback.
- **Direct Buffer Emission ([`compiler/lib/emitter/instructions.w`](../../compiler/lib/emitter/instructions.w)):** Added `:call_loc_set_col`, `:phi_ssa`, `:string_i64`, and `:symbol_i64` (~77,000 instructions per self-compile) to `append_instruction_direct`, writing directly into the function `StringBuffer` without allocating temporary per-instruction `String`s, and reordered `render_instruction` to try `render_runtime_instruction` before `render_numeric_instruction`.
- **Allocation-Free Call Contract Verification ([`compiler/lib/emitter/analysis.w`](../../compiler/lib/emitter/analysis.w)):** Removed an unconditional `arg_types = []` allocation that ran on all ~298,000 WIRE instructions at the top of `wire_direct_call_contract(inst)`, precomputed 0..8 `i64`-arg call contract descriptors, and deferred `target_details` string concatenation to the error path.

### 4.6 Measured Results (Stage 2 Cold Self-Compile, Interleaved A/B)

Across the final four-tranche compiler pass alone (measured on 5 interleaved `before`/`after` pairs with `TUNGSTEN_CORE_DISK_CACHE=0 TUNGSTEN_FUNCTION_EMIT_CACHE=0`):

| Phase | Before (min / med) | After (min / med) | Change (min / med) |
| :--- | :--- | :--- | :--- |
| `lowering to wire` | `0.822s` / `0.854s` | **`0.765s` / `0.835s`** | **`-6.9%` / `-2.2%`** |
| `escape` | `0.064s` / `0.065s` | **`0.055s` / `0.061s`** | **`-14.1%` / `-6.2%`** |
| `free insertion` | `0.161s` / `0.165s` | **`0.142s` / `0.151s`** | **`-11.8%` / `-8.5%`** |
| `emit llvm ir` | `0.180s` / `0.190s` | **`0.161s` / `0.172s`** | **`-10.6%` / `-9.5%`** |
| **TOTAL COMPILE TIME** | `1.486s` / `1.545s` | **`1.395s` / `1.492s`** | **`-6.1%` / `-3.4%`** |

---

## 5. Two instructive traps we hit along the way

1. **`case` statements that silently desugar to linear `if/elsif` chains:**
   In `compiler/lib/lowering/control_flow.w`, `lower_case_value_switch` only emits an $O(1)$ `switch_i64` when every `when` arm has a single-value literal pattern (`pk == :symbol || pk == :string || pk == :int`) and a single-statement non-branching body (`case_switch_simple_body?`). Any `case` that uses multi-pattern arms (`when :a, :b`) or multi-statement bodies (such as `escape_analyze`, `runtime_fns_for_inst`, and `append_instruction_direct`) falls back to a sequential `if/elsif` chain! Adding 15 low-frequency opcodes to the *first* `when` arm of `escape_analyze`, or placing a 25-element `if op == :a || op == :b ...` guard at the top of a function, forced every common instruction to evaluate 15–25 extra branches before matching. Placing rare opcodes at the *bottom* of the `case` (just before `else`) and keeping linear pre-filters to the top 6 opcodes turned a regression into a 14% win.
2. **Untyped receiver method calls in compiler helpers:**
   Replacing `name.chars()` in `llvm_safe_name(name)` with a `while i < n` loop calling `name.byte_at(i)` slowed down `-O0` (`--dev`) builds and the Stage-0 C VM because `name` is an untyped parameter (`:any`), so `name.byte_at(i)` lowered to dynamic `w_method_dispatch(name, "byte_at", i)` on *every byte*. Memoizing `llvm_safe_name(name)` in `llvm_safe_name_cache` avoided per-byte work altogether across all engines.

---

## 6. Follow-Up Campaign: Tackling the Next Ten Improvements

After completing Tranches 1–4, we evaluated and implemented all ten follow-up items across the compiler and C runtime:

### 6.1 Generalizing `lower_case_value_switch` for Multi-Pattern & Multi-Statement Arms ([`compiler/lib/lowering/control_flow.w`](../../compiler/lib/lowering/control_flow.w))
- **Change:** Relaxed `case_switch_simple_body?` to permit multi-statement arm bodies (`1 <= body.size() <= 8`) and nested `:if` expressions, added `:break`, `:next`, `:recase`, `:multi_assign`, `:on_guard`, `:go`, and `:with` to statement-position tail handling in `lower_if_expr_body` and `lower_body_value`, and added structural equivalence (`case_switch_body_equiv?`) so consecutive `CaseArm`s deserialized from multi-pattern `when :a, :b, :c` clauses share a single basic block `:label` in `switch_i64` instead of duplicating basic blocks. Also deduplicated `switch_i64` successor edges in [`compiler/lib/cfg.w`](../../compiler/lib/cfg.w) and registered `__w_switch_canonical_fast` / `w_switch_canonical` as pure non-retaining builtins in [`compiler/lib/escape.w`](../../compiler/lib/escape.w) and [`compiler/lib/ownership.w`](../../compiler/lib/ownership.w).

### 6.2 Parallel Function LLVM IR Emission & Parallel `content_hash_pass` ([`compiler/lib/emitter/parallel.w`](../../compiler/lib/emitter/parallel.w), [`compiler/lib/emitter/artifact.w`](../../compiler/lib/emitter/artifact.w), [`compiler/lib/content_hash.w`](../../compiler/lib/content_hash.w))
- **Change:** Enabled 8-thread deterministic parallel function emission whenever `mod[:preserve_debug_frames] != true` (pre-populating `attr_groups` and `llvm_param_reg`/`llvm_safe_name` caches in deterministic source order before spawning workers), and added parallel wave hashing (`content_hash_batch_worker` / `content_hash_flush_batch`) to `content_hash_pass`. Also updated [`scripts/test-parallel-function-emitter.sh`](../../scripts/test-parallel-function-emitter.sh) and [`scripts/test-parallel-midend.sh`](../../scripts/test-parallel-midend.sh) to set `TUNGSTEN_CORE_LOWER_CACHE=0` so `jobs=1, 2, 4, 8` all compile the identical full module without cold-vs-warm Core cache drift.
- **Result:** Cold self-compile `emit llvm ir` time in `--no-debug` dropped from `0.217s` to **`0.102s`** (**2.1× faster**), and in `--release` to **`0.076s`**, cutting total cold self-compile time to **`1.174s`** (`--release`) and **`1.201s`** (`--no-debug`).

### 6.3–6.4 & 6.8 WIRE Arena Record Fast Paths & Pre-Interned SSA Register Tables ([`runtime/runtime.c`](../../runtime/runtime.c), [`compiler/lib/wire.w`](../../compiler/lib/wire.w))
- **Evaluation & Change:** `WModule` (kind 264), `WFunction` (kind 265), and `WBlock` (kind 266) are already allocated directly in the C WIRE bump arena (`g_wire_arena`). However, `w_wire_field_store` (`runtime/runtime.c:23455`) lacked the inline `count <= 4` fast path that `w_wire_field_load_inline` had, causing every write to 2-field `WBlock` records (`:label`, `:instructions`) and 1–4 field WIRE instructions to touch the atomic `g_wire_field_index_cache`. We added the `count <= 4` inline fast path to `w_wire_field_store`, and pre-populated `wire_temp_names` (`"%t0".."%t4095"`) and `wire_var_slot_names` (`"%vs.0".."%vs.511"`) in [`compiler/lib/wire.w`](../../compiler/lib/wire.w) so `next_temp(f)` and `ensure_var_slot(f, ...)` return slab-interned strings via $O(1)$ array indexing without per-temp `.to_s()` or `w_str_concat` allocations.

### 6.5 Stage 2 Optimization Level Benchmark (`-O0` vs `-O1` vs `-O2` vs `-O3`) ([`bin/commands/build.w`](../../bin/commands/build.w))
- **Benchmark Results (3 runs each):**
  | Stage 2 Flag | Stage 2 Clang Build | `tungsten-repl` Image Build | Cold Self-Compile (`TOTAL`) | Cold Self-Compile (`lowering`) |
  | :--- | :---: | :---: | :---: | :---: |
  | `-O0` | `4.44s` | `10.1s` | `1.385s – 1.411s` | `0.814s – 0.839s` |
  | **`-O1` (current default)** | **`13.12s – 14.38s`** | **`27.2s`** | **`1.129s – 1.139s`** | **`0.653s – 0.659s`** |
  | `-O2` | `14.15s – 15.29s` | `33.3s` | `1.165s – 1.167s` | `0.669s – 0.693s` |
  | `-O3` | `13.90s – 14.29s` | `32.8s` | `1.140s – 1.145s` | `0.649s – 0.655s` |
- **Conclusion:** `-O1` (already configured in [`bin/commands/build.w:1275`](../../bin/commands/build.w#L1275)) is **19.2% faster (`1.23×`)** than `-O0` on self-compiles while building compiler images 6 seconds faster than `-O2`/`-O3` and avoiding `-O2` code-size expansion in the 140k-line generated compiler IR.

### 6.6 Interprocedural Parameter-Type & Return-Type Inference ([`compiler/lib/return_inference.w`](../../compiler/lib/return_inference.w), [`compiler/lib/lowering/analysis.w`](../../compiler/lib/lowering/analysis.w), [`compiler/lib/lowering.w`](../../compiler/lib/lowering.w))
- **Change:** Extended `collect_return_type_evidence` in [`compiler/lib/return_inference.w`](../../compiler/lib/return_inference.w) to traverse exhaustive `:case_value` and `:case` expressions in tail position (while recording explicit `:nil_lit` returns so functions that can return `nil` never mis-infer a non-nil return type). Extended `collect_param_type_observations` in [`compiler/lib/lowering/analysis.w`](../../compiler/lib/lowering/analysis.w) to propagate observed parameter types across 2 interprocedural rounds (`caller -> helper`), and re-ran `infer_return_types_fixed_point` with `populate_definition_var_types` after parameter observation in [`compiler/lib/lowering.w`](../../compiler/lib/lowering.w). Unannotated helper chains called with floats or typed arrays now infer both their parameter types and return types end-to-end (e.g. lowering unannotated `a * b + c` helpers directly to `@llvm.fmuladd.f64`).

### 6.7 Lightweight WIRE-Level Leaf Inliner ([`compiler/lib/compiler.w`](../../compiler/lib/compiler.w))
- **Change:** Added `wire_inline_tiny_leaves(mod)` in [`compiler/lib/compiler.w`](../../compiler/lib/compiler.w) right after SSA conversion (`--release` or `TUNGSTEN_WIRE_INLINE=1`). Single-block leaf functions returning a constant/parameter (`:passthrough`), a pure 64-bit binary ALU/bitwise op (`:add_i64`, `:sub_i64`, `:mul_i64`, `:and_i64`, `:or_i64`, `:xor_i64`, `:shl_i64`, `:ashr_i64`, `:lshr_i64`), or a fast int conversion (`:w_int_inline`, `:unbox_int_fast`) are inlined in-place at `call_direct_i64` sites before `escape_pass`, `ownership_pass`, and `content_hash_pass`.

### 6.9 Compile-Time Constant Folding for Bitwise/Shift Ops & `wvalue_from_bits` ([`compiler/lib/lowering/ops.w`](../../compiler/lib/lowering/ops.w), [`compiler/lib/lowering/calls.w`](../../compiler/lib/lowering/calls.w))
- **Change:** Lowered `wvalue_from_bits` arguments via `lower_machine_int_expression(ctx, args[0], :i64)` in [`compiler/lib/lowering/calls.w`](../../compiler/lib/lowering/calls.w), folded unary `:MINUS` on `:int` literals up to `i64::MAX` (`9223372036854775807`), and folded binary `:LSHIFT`, `:RSHIFT`, `:AMP`, `:PIPE`, `:CARET`, `:PLUS`, `:MINUS`, and `:STAR` on inline-i48 `:int` literals in both `lower_machine_int_expression` and `lower_binary_op` in [`compiler/lib/lowering/ops.w`](../../compiler/lib/lowering/ops.w).

### 6.10 Zero-Copy Array Views & Sub-64-Bit Stride Fix ([`runtime/runtime.c`](../../runtime/runtime.c))
- **Audit & Fix:** Tungsten already supports zero-copy array slices/views via `Array#slice_view(start, len)` (`w_array_view`), `arr[from..to]` (`w_array_view_range`), `BigArray#subview` (`w_big_array_subview`), `Array#view(target_type)` (`w_array_reinterpret`), `Mmap#as_typed` / `Mmap#view_at`, and `WArray.start` header offsets. Auditing `w_array_view` (`runtime/runtime.c:74231`) and `w_big_array_subview` (`runtime/runtime.c:74866`) uncovered a bug where `eb < 0 ? -eb : (eb == 65 ? 64 : eb)` was used instead of `array_storage_bits(eb)`, computing wrong byte offsets for `i8` (`ebits=108`), `i16` (`116`), `bf16` (`-116`), `fp8` (`-108`/`-109`), and `fp4` (`-104`). Replacing that expression with `array_storage_bits(eb)` (and adding the `abs_bits == 1` byte-aligned branch to `w_array_view`) fixed zero-copy `slice_view` and `subview` across all narrow element types.

---

## Round 4: Exact Ownership Gating, Parallel Debug Emission, Lowering Pre-Scan Elision, and Parallel Escape Analysis

1. **Exact Ownership Gating in `free_insertion_pass` (`compiler/lib/ownership.w`):**
   - Split `int_fresh_returns` into `int_fresh_discover(mod)` (run before the 8-thread parallel `ownership_analyze`) and `int_fresh_apply_seals(cands, fresh)` (run in `free_insertion_pass`).
   - Recorded exact per-function flags (`has_int_arith` including `int_fresh` callees, `has_heap_producer`, `has_method_reg`, and `int_fresh_known`) during the parallel `ownership_analyze` pass so `free_insertion_pass` and `module_method_table` no longer fall back to the coarse `has_direct_call` flag (which previously caused `int_temp_releases`, `owned_slot_releases`, and `module_method_table` to rescan ~90% of functions).
   - Tightened the first-block `:ret_i64` pre-filter in `int_fresh_candidate` and `fresh_heap_candidate` (`rv.byte_at(0) == 37 && rv.byte_at(1) == 116`) to reject `"%.param"` and `"%vs.0"` returns immediately.

2. **8-Thread Parallel Function Emission for Default Debug Builds (`compiler/lib/naming.w`, `compiler/lib/content_hash.w`, `compiler/lib/emitter/parallel.w`):**
   - Root-caused the previous thread-safety hazard in parallel worker sections (`content_hash_flush_batch` and `emitter_render_functions_parallel`) to concurrent cache-miss writes into the module-global `llvm_safe_name_cache` and `llvm_param_reg_cache` hashes.
   - Added `naming_cache_state = {frozen: false}` in `compiler/lib/naming.w` to freeze cache mutations while worker threads are active, enabling deterministic 8-thread function emission for default debug builds (`emit llvm ir` dropped from `0.175s` to `0.107s`, `-38.9%`).

3. **Lowering AST Pre-Scan Elision (`compiler/lib/lowering/analysis.w`, `compiler/lib/lowering/blocks.w`, `compiler/lib/lowering/definitions.w`, `compiler/lib/lowering.w`):**
   - Made `count_local_assignments` allocation-free on common AST nodes (avoiding temporary `ast_children` array allocations) and recorded `:with`/`:parallel_with` binding `:var`s so `find_reassigned_params` can fast-exit in `O(params.size())` whenever no parameter appears in `local_assignment_counts` (>95% of functions).
   - Deduplicated `find_captured_params_in_body` in `lower_method_def` and `find_reassigned_params` in `lower_class_method`, gated `find_param_machine_hints` on `reassigned.size() > 0`, and eliminated per-branch array allocations in `find_captured_params_in_node`.
   - Added `has_mut_accumulator_seed?` to `mut_accumulator_candidates` and an empty-map fast exit to `sum_chunk_var`, avoiding full-AST `mut_mark_all_dead` walks on >99% of functions.

4. **Parallel Call-Graph & Leaf/Zero-Param Analysis in `escape_pass` (`compiler/lib/escape.w`):**
   - Parallelized the per-function call-graph edge discovery and `escape_analyze` for all 0-parameter and leaf functions across 8 worker threads, leaving only the compact `pending` subset of non-leaf functions with parameters for topological ordering (`escape` dropped from `0.056s` to `0.037s`, `-33.9%`).

### Updated Cold Self-Compile Benchmarks (`compiler/tungsten.w`, 3,918 functions)

| Mode | Campaign Baseline | After Round 3 | After Round 4 (Best / Median of 3) | Total Speedup vs. Baseline |
| :--- | ---: | ---: | ---: | ---: |
| **Default (`--debug`)** | `2.456s` | `1.709s` | **`1.278s` / `1.300s`** | **`1.92x` (`-48.0%`)** |
| **`--no-debug`** | — | `1.594s` | **`1.244s` / `1.272s`** | **`-22.0%` vs. Round 3** |
| **`--release`** | — | `1.454s` | **`1.240s` / `1.241s`** | **`-14.7%` vs. Round 3** |

