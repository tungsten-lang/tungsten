# ast_schema.w — slab-AST schema (PR #2 Phase 3).
#
# Defines the kind IDs and size-class assignments that the slab-AST
# runtime (`runtime/runtime.{c,h}` arena helpers) uses for encoding
# W_PACKED_NODE WValues.
#
# Per-kind field offsets (F_<KIND>_<FIELD>) live inline next to the
# constructors in `compiler/lib/ast.w` — staged that way so each
# kind's offsets land in the same PR as its constructor rewrite,
# keeping diffs reviewable.
#
# Kind IDs are stable once assigned (the schema hash includes them).
# New kinds must APPEND, not renumber. Renaming a kind name in code
# is fine; renaming the ID is a cache-invalidating change and must
# bump the schema hash automatically via `kind_id_for_name`.
#
# Size class assignment uses the constructor's field count:
#   0     data fields -> SC_2  (allocated packed node, no readable fields)
#   1-2   data fields -> SC_2  (16 B, 2 slots)
#   3     data fields -> SC_4  (32 B, 4 slots)
#   4-6   data fields -> SC_8  (64 B, 8 slots)
#   7+    data fields -> SC_16 (128 B, 16 slots) - no kinds currently
#
# When line/col are stored in the slab (a future migration step), kinds
# with 2 data fields + line + col would no longer fit in SC_2 and would
# need promotion to SC_4. That decision lives with each constructor's
# field offset assignment in ast.w.

# === Size classes ===
#
# Named by slot count (8 B per slot). Numeric value is the 2-bit
# size_class field in W_PACKED_NODE; assignment is fixed by current
# bit layout so SC_4 must stay 0 and SC_8 must stay 1.
#
#   SC_2  =  2 slots = 16 B    leaf-shaped 1-2-slot kinds (var, symbol, …)
#   SC_4  =  4 slots = 32 B    3-slot kinds (int, binary_op, assign, …)
#   SC_8  =  8 slots = 64 B    4-6-slot kinds (call, if, method_def, …)
#   SC_16 = 16 slots = 128 B   reserved for 7+-slot kinds (none currently)

SC_2  = 0 ## i64
SC_4  = 1 ## i64
SC_8  = 2 ## i64
SC_16 = 3 ## i64

# === Kind IDs (33..141; 0..32 reserved for compact tier) ===
#
# 0 is reserved (means "no kind / not a slab node"). Kinds are
# grouped by category (literals, vars, control flow, ...) but
# numerically assigned in alphabetical order so the table reads
# the same as `grep -oE 'node:\s*:\w+' compiler/lib/ast.w | sort -u`.

KIND_AND                = 33   ## i64
KIND_ARRAY              = 34   ## i64
KIND_ASSIGN             = 35   ## i64
KIND_BEGIN              = 36   ## i64
KIND_BINARY_OP          = 37   ## i64
KIND_BLOCK              = 38   ## i64
KIND_BOOL               = 39   ## i64
KIND_BREAK              = 40   ## i64
KIND_BYTE_ARRAY         = 41   ## i64
KIND_BYTE_ARRAY_INTERP  = 42  ## i64
KIND_CALL               = 43  ## i64
KIND_CASE               = 44  ## i64
KIND_CASE_ARM           = 45  ## i64
KIND_CASE_VALUE         = 46  ## i64
KIND_CHAR               = 47  ## i64
KIND_CIDR4              = 48  ## i64
KIND_CLASS_DEF          = 49  ## i64
KIND_CODEPOINT          = 50  ## i64
KIND_COLOR              = 51  ## i64
KIND_COMPOUND_ASSIGN    = 52  ## i64
KIND_CURRENCY           = 53  ## i64
KIND_CVAR               = 54  ## i64
KIND_DATE               = 55  ## i64
KIND_DATETIME           = 56  ## i64
KIND_DECIMAL            = 57  ## i64
KIND_DURATION           = 58  ## i64
KIND_ENCODED            = 59  ## i64
KIND_EXTERN_FN          = 60  ## i64
KIND_EXTERN_LIB         = 61  ## i64
KIND_FIELD_DECL         = 62  ## i64
KIND_FLOAT              = 63  ## i64
KIND_FN_DEF             = 64  ## i64
KIND_GO                 = 65  ## i64
KIND_GPU_KERNEL_DEF     = 66  ## i64
KIND_HASH_LITERAL       = 67  ## i64
KIND_IF                 = 68  ## i64
KIND_IN_TEST            = 69  ## i64
KIND_INT                = 70  ## i64
KIND_IP4                = 71  ## i64
KIND_IVAR               = 72  ## i64
KIND_KEY                = 73  ## i64
KIND_LAMBDA_ARITY       = 74  ## i64
KIND_LAYOUT_DEF         = 75  ## i64
KIND_MAGIC_CONSTANT     = 76  ## i64
KIND_MAP_OP             = 77  ## i64
KIND_METHOD_DEF         = 78  ## i64
KIND_MODULE_DEF         = 79  ## i64
KIND_MONTH              = 80  ## i64
KIND_MULTI_ASSIGN       = 81  ## i64
KIND_NEXT               = 82  ## i64
KIND_NIL_LIT            = 15  ## i64
KIND_NOT                = 84  ## i64
KIND_ON_GUARD           = 85  ## i64
KIND_OR                 = 86  ## i64
KIND_PARALLEL_WITH      = 87  ## i64
KIND_PARAM              = 88  ## i64
KIND_PARG               = 89  ## i64
KIND_PASSTHROUGH        = 90  ## i64
KIND_PRINT              = 91  ## i64
KIND_PROGRAM            = 92  ## i64
KIND_PUTS               = 93  ## i64
KIND_QUANTITY           = 94  ## i64
KIND_RAISE              = 95  ## i64
KIND_RANGE              = 96  ## i64
KIND_RATIONAL           = 97  ## i64
KIND_REGEX              = 98  ## i64
KIND_REGEX_CAPTURE      = 99  ## i64
KIND_RESCUE_EXPR        = 100  ## i64
KIND_RETURN_NIL         = 19   ## i64
KIND_RETURN             = 101  ## i64
KIND_SAFE_NAV           = 102  ## i64
KIND_SCHEDULE_DEF       = 103  ## i64
KIND_SELF_REF           = 16  ## i64
KIND_STRING             = 105  ## i64
KIND_STRING_INTERP      = 106  ## i64
KIND_SUPER              = 107  ## i64
KIND_SUPERSCRIPT        = 108  ## i64
KIND_SYMBOL             = 109  ## i64
KIND_SYMBOL_ARRAY       = 110  ## i64
KIND_TARGET_AND         = 111  ## i64
KIND_TARGET_DESIGNATOR  = 112  ## i64
KIND_TARGET_NOT         = 113  ## i64
KIND_TARGET_OR          = 114  ## i64
KIND_TIME               = 115  ## i64
KIND_TRAIT_DEF          = 116  ## i64
KIND_TRAIT_INCLUDE      = 117  ## i64
KIND_TYPED_ARRAY        = 118  ## i64
KIND_TYPED_ARRAY_NEW    = 119  ## i64
KIND_UNARY_OP           = 120  ## i64
KIND_USE                = 121  ## i64
KIND_UUID               = 122  ## i64
KIND_VAR                = 123  ## i64
KIND_VIEW_ACCESS        = 124  ## i64
KIND_VIEW_BASE          = 17  ## i64
KIND_VIEW_DECL          = 126  ## i64
KIND_VIEW_FIELD         = 127  ## i64
KIND_VIEW_VALUE         = 18  ## i64
KIND_WHEN               = 129  ## i64
KIND_WHILE              = 130  ## i64
KIND_WITH               = 131  ## i64
KIND_WORD_ARRAY         = 132 ## i64
KIND_WVALUE             = 133 ## i64
KIND_YIELD              = 134 ## i64
KIND_CIDR_MATCH         = 135 ## i64
KIND_REGEX_MATCH        = 136 ## i64
KIND_NAMESPACE_DECL     = 137 ## i64
KIND_IVARS_DECL         = 138 ## i64
# Per-file root: holds the source buffer that child node slices are
# interpreted against, eliminating the need for a file_id field in
# every packed slice. Walker context: source-buffer-attached at entry,
# restored at exit. Distinct from Program (Program is the body-of-
# expressions inside; File is the file as a unit of compilation with
# its path and source attached).
KIND_FILE               = 139 ## i64

# Fused pipeline nodes. `map` is a per-element stream→stream stage
# ({source, fn, kind}; kind ∈ :map/:select/:reject). `calc` is a known
# fusable computation ({op, source, type_intent}) — elementwise when
# source is nil (a map's fn, e.g. :sq → x*x), or a terminal reduce/
# detect wrapping a map chain (e.g. :sum/:min/:detect). Both are SC_4
# (3 data fields). See lowering/calls.w for the single-loop fusion.
KIND_MAP                = 140 ## i64
KIND_CALC               = 141 ## i64

# PascalCase identifier (T_NAME). Parser emits this instead of Var
# so the interpreter and lowering route through class-resolution
# (autoload-aware) rather than the variable lookup eval_var uses.
KIND_CLASS_REF          = 142 ## i64

# `recase [expr]` — re-run the enclosing case. Carries an optional subject
# expression in slot 0 (nil for bare `recase`). Modeled on KIND_RETURN.
KIND_RECASE             = 143 ## i64

# `$name` — a global variable, distinct from :var (lexically scoped,
# barriered at fn/method boundaries) and :ivar (per-instance). Reads and
# writes always resolve to one process-wide store regardless of which
# function/method body they appear in — see GVar in ast.w.
KIND_GVAR               = 144 ## i64

# `var$field` — a postfix view-decl field read against an EXPLICIT receiver
# (any named variable carrying a known `- data` struct layout), as opposed to
# :view_field / bare `$field`, which read against the implicit `__self`
# pointer inside a class method. Carries (@receiver, @field). See
# ViewFieldVar in ast.w.
KIND_VIEW_FIELD_VAR     = 145 ## i64

# IPv6 address / CIDR literals (::1, 2001:db8::1, 2001:db8::/32). Slab-stored
# string like Ip4/Cidr4; lower_ipv6 / lower_cidr6 / the interpreter parse it.
KIND_IP6                = 146 ## i64
KIND_CIDR6              = 147 ## i64

KIND_MAX = 147 ## i64

# === Symbol → KIND lookup (used by Phase 4 ast.w constructors) ===
#
# Maps a kind symbol (e.g. `:int`) to its integer KIND_INT.  This is
# the only function in the schema that the parser/builder code calls
# at construction time; downstream lowering uses the integer directly
# via `w_node_kind(wnode)`.
#
# Implemented as a module-level hash so a single lookup costs one
# hash_get (constant additions, lazy-built once per process). Returns
# -1 for unknown kinds.

KIND_ID_TABLE = {
  :and               => KIND_AND,
  :array             => KIND_ARRAY,
  :assign            => KIND_ASSIGN,
  :begin             => KIND_BEGIN,
  :binary_op         => KIND_BINARY_OP,
  :block             => KIND_BLOCK,
  :bool              => KIND_BOOL,
  :break             => KIND_BREAK,
  :byte_array        => KIND_BYTE_ARRAY,
  :byte_array_interp => KIND_BYTE_ARRAY_INTERP,
  :call              => KIND_CALL,
  :case              => KIND_CASE,
  :case_arm          => KIND_CASE_ARM,
  :case_value        => KIND_CASE_VALUE,
  :char              => KIND_CHAR,
  :cidr4             => KIND_CIDR4,
  :class_def         => KIND_CLASS_DEF,
  :codepoint         => KIND_CODEPOINT,
  :color             => KIND_COLOR,
  :compound_assign   => KIND_COMPOUND_ASSIGN,
  :currency          => KIND_CURRENCY,
  :cvar              => KIND_CVAR,
  :date              => KIND_DATE,
  :datetime          => KIND_DATETIME,
  :decimal           => KIND_DECIMAL,
  :duration          => KIND_DURATION,
  :encoded           => KIND_ENCODED,
  :extern_fn         => KIND_EXTERN_FN,
  :extern_lib        => KIND_EXTERN_LIB,
  :field_decl        => KIND_FIELD_DECL,
  :float             => KIND_FLOAT,
  :fn_def            => KIND_FN_DEF,
  :go                => KIND_GO,
  :gpu_kernel_def    => KIND_GPU_KERNEL_DEF,
  :gvar              => KIND_GVAR,
  :hash_literal      => KIND_HASH_LITERAL,
  :if                => KIND_IF,
  :in_test           => KIND_IN_TEST,
  :int               => KIND_INT,
  :ip4               => KIND_IP4,
  :ip6               => KIND_IP6,
  :cidr6             => KIND_CIDR6,
  :ivar              => KIND_IVAR,
  :key               => KIND_KEY,
  :lambda_arity      => KIND_LAMBDA_ARITY,
  :layout_def        => KIND_LAYOUT_DEF,
  :magic_constant    => KIND_MAGIC_CONSTANT,
  :map_op            => KIND_MAP_OP,
  :method_def        => KIND_METHOD_DEF,
  :module_def        => KIND_MODULE_DEF,
  :month             => KIND_MONTH,
  :multi_assign      => KIND_MULTI_ASSIGN,
  :next              => KIND_NEXT,
  :nil_lit           => KIND_NIL_LIT,
  :not               => KIND_NOT,
  :on_guard          => KIND_ON_GUARD,
  :or                => KIND_OR,
  :parallel_with     => KIND_PARALLEL_WITH,
  :param             => KIND_PARAM,
  :parg              => KIND_PARG,
  :passthrough       => KIND_PASSTHROUGH,
  :print             => KIND_PRINT,
  :program           => KIND_PROGRAM,
  :puts              => KIND_PUTS,
  :quantity          => KIND_QUANTITY,
  :raise             => KIND_RAISE,
  :range             => KIND_RANGE,
  :rational          => KIND_RATIONAL,
  :recase            => KIND_RECASE,
  :regex             => KIND_REGEX,
  :regex_capture     => KIND_REGEX_CAPTURE,
  :rescue_expr       => KIND_RESCUE_EXPR,
  :return_nil        => KIND_RETURN_NIL,
  :return            => KIND_RETURN,
  :safe_nav          => KIND_SAFE_NAV,
  :schedule_def      => KIND_SCHEDULE_DEF,
  :self_ref          => KIND_SELF_REF,
  :string            => KIND_STRING,
  :string_interp     => KIND_STRING_INTERP,
  :super             => KIND_SUPER,
  :superscript       => KIND_SUPERSCRIPT,
  :symbol            => KIND_SYMBOL,
  :symbol_array      => KIND_SYMBOL_ARRAY,
  :target_and        => KIND_TARGET_AND,
  :target_designator => KIND_TARGET_DESIGNATOR,
  :target_not        => KIND_TARGET_NOT,
  :target_or         => KIND_TARGET_OR,
  :time              => KIND_TIME,
  :trait_def         => KIND_TRAIT_DEF,
  :trait_include     => KIND_TRAIT_INCLUDE,
  :typed_array       => KIND_TYPED_ARRAY,
  :typed_array_new   => KIND_TYPED_ARRAY_NEW,
  :unary_op          => KIND_UNARY_OP,
  :use               => KIND_USE,
  :uuid              => KIND_UUID,
  :var               => KIND_VAR,
  :view_access       => KIND_VIEW_ACCESS,
  :view_base         => KIND_VIEW_BASE,
  :view_decl         => KIND_VIEW_DECL,
  :view_field        => KIND_VIEW_FIELD,
  :view_field_var    => KIND_VIEW_FIELD_VAR,
  :view_value        => KIND_VIEW_VALUE,
  :when              => KIND_WHEN,
  :while             => KIND_WHILE,
  :with              => KIND_WITH,
  :word_array        => KIND_WORD_ARRAY,
  :wvalue            => KIND_WVALUE,
  :yield             => KIND_YIELD,
  :cidr_match        => KIND_CIDR_MATCH,
  :regex_match       => KIND_REGEX_MATCH,
  :namespace_decl    => KIND_NAMESPACE_DECL,
  :ivars_decl        => KIND_IVARS_DECL,
  :file              => KIND_FILE,
  :map               => KIND_MAP,
  :calc              => KIND_CALC,
  :class_ref         => KIND_CLASS_REF,
}

-> kind_id_for_name(sym)
  v = KIND_ID_TABLE[sym]
  if v == nil
    return -1
  v

# Lowercase alias for KIND_ID_TABLE. The C VM bootstrap parses an
# uppercase top-level identifier followed by [] as a method call on a
# (nonexistent) class, so `KIND_ID_TABLE[sym]` works only inside
# function bodies the C VM never reaches during stage-0 interpretation
# of ast.w/ast_schema.w (it works for kind_id_for_name today because
# stage 0 doesn't call it; everything routes through ast_kind which
# uses the Hash :node fast path). ast_children needs a kind_id at
# runtime under stage 0, so it uses this lowercase alias directly.
kind_id_table = KIND_ID_TABLE

# Reverse lookup: kind_id (i64) → kind symbol. Used by ast_kind when the
# input is a bare W_PACKED_NODE WValue (no hash side carrying :node).
# Hardcoded array indexed by kind_id; built one-for-one with the
# KIND_X = N integer constants above. Position 0 is unused (no KIND has
# id 0; kinds are 33..142 (0..32 reserved for compact tier)). Any future kind addition MUST extend this
# array in sync with KIND_ID_TABLE — the schema_hash check catches a
# missing entry as a cache invalidation; production behavior would be
# nil-from-table when a runtime W_PACKED_NODE's kind bits are out of
# range.

kind_sym_table_data = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, :nil_lit, :self_ref, :view_base, :view_value, :return, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, :and, :array, :assign, :begin, :binary_op, :block, :bool, :break, :byte_array, :byte_array_interp, :call, :case, :case_arm, :case_value, :char, :cidr4, :class_def, :codepoint, :color, :compound_assign, :currency, :cvar, :date, :datetime, :decimal, :duration, :encoded, :extern_fn, :extern_lib, :field_decl, :float, :fn_def, :go, :gpu_kernel_def, :hash_literal, :if, :in_test, :int, :ip4, :ivar, :key, :lambda_arity, :layout_def, :magic_constant, :map_op, :method_def, :module_def, :month, :multi_assign, :next, nil, :not, :on_guard, :or, :parallel_with, :param, :parg, :passthrough, :print, :program, :puts, :quantity, :raise, :range, :rational, :regex, :regex_capture, :rescue_expr, :return, :safe_nav, :schedule_def, nil, :string, :string_interp, :super, :superscript, :symbol, :symbol_array, :target_and, :target_designator, :target_not, :target_or, :time, :trait_def, :trait_include, :typed_array, :typed_array_new, :unary_op, :use, :uuid, :var, :view_access, nil, :view_decl, :view_field, nil, :when, :while, :with, :word_array, :wvalue, :yield, :cidr_match, :regex_match, :namespace_decl, :ivars_decl, :file, :map, :calc, :class_ref, :recase, :gvar, :view_field_var, :ip6, :cidr6]

-> kind_sym_for_id(kind_id)
  # NOTE: stage 0 C VM can't dispatch methods (like .size()) on
  # uppercase top-level identifiers — they parse as method calls on
  # an undefined class. So compare against a literal constant instead
  # of `kind_sym_table_data.size()`. The constant must track the table
  # length: 148 entries (indices 0..32 reserved for compact tier + KIND_AND..KIND_CIDR6 = 33..147).
  if kind_id < 0 || kind_id > KIND_MAX
    return nil
  kind_sym_table_data[kind_id]

# === Slab field offset table ===
#
# Maps (kind_id, field_sym) → integer slot index in the slab node.
# Built positionally from compiler/lib/ast.w constructor signatures:
# the i-th parameter is stored at slot i. Sites not in this table
# (parser-added flags like :reuse_safe, line/col, etc.) fall back
# to hash access via the helpers in ast.w.
#
# Coverage: covers the 14 highest-frequency kinds from Phase 1.0
# (~93% of node allocations during self-compile per
# scratch/phase_1_0_kind_counts.txt). Long-tail kinds fall back to
# hash; safe under the hybrid scaffolding.
#
# Special offset 256 (OFFSET_INLINE) marks "payload lives in the
# W_PACKED_NODE's 32-bit offset bits, not in a slab slot". Used by
# the 5 inline-encoded kinds — :char/:lambda_arity/:superscript
# carry it on :value, :parg/:regex_capture carry it on :index.
# ast_get checks for this sentinel after schema lookup and
# short-circuits to w_node_offset_extern.

OFFSET_INLINE = 256 ## i64

slab_offset_table_data = {
  KIND_AND               => {:left => 0, :right => 1},
  KIND_ARRAY             => {:elements => 0},
  KIND_ASSIGN            => {:target => 0, :value => 1, :type_hint => 2},
  KIND_BEGIN             => {:body => 0, :rescue_var => 1, :rescue_body => 2, :ensure_body => 3},
  KIND_BINARY_OP         => {:left => 0, :op => 1, :right => 2},
  KIND_BLOCK             => {:params => 0, :body => 1, :loc => 2, :loc_end => 3},
  KIND_BOOL              => {:value => 0},
  KIND_BREAK             => {},
  KIND_BYTE_ARRAY        => {:values => 0},
  KIND_BYTE_ARRAY_INTERP => {:parts => 0},
  KIND_CALL              => {:receiver => 0, :name => 1, :args => 2, :block => 3, :loc => 4, :loc_end => 5},
  KIND_CASE              => {:whens => 0, :else_body => 1},
  KIND_CASE_ARM          => {:pattern => 0, :guard => 1, :body => 2},
  KIND_CASE_VALUE        => {:subject => 0, :arms => 1, :else_body => 2},
  KIND_CHAR              => {:value => 256},
  KIND_CIDR4             => {:value => 0},
  KIND_CLASS_DEF         => {:name => 0, :superclass => 1, :body => 2, :class_role => 3},
  KIND_CODEPOINT         => {:value => 256},
  KIND_COLOR             => {:rgba => 256},
  KIND_COMPOUND_ASSIGN   => {:target => 0, :op => 1, :value => 2},
  KIND_CURRENCY          => {:amount => 0, :prefix => 1, :suffix => 2},
  KIND_CVAR              => {:name => 257},
  KIND_DATE              => {:value => 0},
  KIND_DATETIME          => {:value => 0},
  KIND_DECIMAL           => {:value => 0},
  KIND_DURATION          => {:raw => 0},
  KIND_ENCODED           => {:value => 0, :encoding => 1},
  KIND_EXTERN_FN         => {:name => 0, :return_type => 1, :param_types => 2},
  KIND_EXTERN_LIB        => {:lib_name => 0, :declarations => 1},
  KIND_FIELD_DECL        => {:name => 0, :field_type => 1},
  KIND_FLOAT             => {:value => 0},
  KIND_FN_DEF            => {:name => 0, :params => 1, :body => 2, :type_hints => 3, :loc => 4, :loc_end => 5},
  KIND_GO                => {:body => 0},
  KIND_GPU_KERNEL_DEF    => {:name => 0, :params => 1, :body => 2, :attribute => 3, :type_hints => 4, :loc => 5, :loc_end => 6},
  KIND_GVAR              => {:name => 257},
  KIND_HASH_LITERAL      => {:entries => 0},
  KIND_IF                => {:condition => 0, :then_body => 1, :elsif_clauses => 2, :else_body => 3},
  KIND_IN_TEST           => {:lhs => 0, :elements => 1},
  KIND_INT               => {:value => 0, :format => 1, :raw => 2},
  KIND_IP4               => {:value => 0},
  KIND_IP6               => {:value => 0},
  KIND_CIDR6             => {:value => 0},
  KIND_IVAR              => {:name => 257},
  KIND_KEY               => {:value => 0},
  KIND_LAMBDA_ARITY      => {:value => 256},
  KIND_LAYOUT_DEF        => {:kernel => 0, :variant => 1, :directives => 2, :loc => 3, :loc_end => 4},
  KIND_MAGIC_CONSTANT    => {:name => 0, :loc => 1, :loc_end => 2},
  KIND_MAP_OP            => {:name => 0},
  KIND_METHOD_DEF        => {:name => 0, :params => 1, :body => 2, :type_hints => 3, :is_class_method => 4, :loc => 5, :loc_end => 6},
  KIND_MODULE_DEF        => {:name => 0, :body => 1},
  KIND_MONTH             => {:value => 0},
  KIND_MULTI_ASSIGN      => {:targets => 0, :value => 1},
  KIND_NEXT              => {},
  KIND_NIL_LIT           => {},
  KIND_NOT               => {:operand => 0},
  KIND_ON_GUARD          => {:predicate => 0, :capabilities => 1, :body => 2},
  KIND_OR                => {:left => 0, :right => 1},
  KIND_PARALLEL_WITH     => {:bindings => 0, :body => 1},
  KIND_PARAM             => {:name => 0, :default => 1, :ivar_assign => 2, :keyword => 3, :block_param => 4, :splat => 5},
  KIND_PARG              => {:index => 256},
  KIND_PASSTHROUGH       => {:expression => 0, :value => 1},
  KIND_PRINT             => {:value => 0},
  KIND_PROGRAM           => {:expressions => 0},
  KIND_PUTS              => {:value => 0},
  KIND_QUANTITY          => {:number_str => 0, :unit => 1},
  KIND_RAISE             => {:value => 0, :loc => 1, :loc_end => 2},
  KIND_RANGE             => {:from => 0, :to => 1, :exclusive => 2},
  KIND_RATIONAL          => {:value => 0},
  KIND_RECASE            => {:value => 0},
  KIND_REGEX             => {:pattern => 0, :options => 1},
  KIND_REGEX_CAPTURE     => {:index => 256},
  KIND_RESCUE_EXPR       => {:body => 0, :fallback => 1},
  KIND_RETURN_NIL        => {},
  KIND_RETURN            => {:value => 0},
  KIND_SAFE_NAV          => {:receiver => 0, :name => 1, :args => 2, :block => 3, :loc => 4, :loc_end => 5},
  KIND_SCHEDULE_DEF      => {:kernel => 0, :variant => 1, :directives => 2, :loc => 3, :loc_end => 4},
  KIND_SELF_REF          => {},
  KIND_STRING            => {:value => 257},
  KIND_STRING_INTERP     => {:parts => 0},
  KIND_SUPER             => {:args => 0},
  KIND_SUPERSCRIPT       => {:value => 256},
  KIND_SYMBOL            => {:value => 257},
  KIND_SYMBOL_ARRAY      => {:symbols => 0},
  KIND_TARGET_AND        => {:left => 0, :right => 1},
  KIND_TARGET_DESIGNATOR => {:name => 0},
  KIND_TARGET_NOT        => {:expression => 0},
  KIND_TARGET_OR         => {:left => 0, :right => 1},
  KIND_TIME              => {:value => 0},
  KIND_TRAIT_DEF         => {:name => 0, :body => 1},
  KIND_TRAIT_INCLUDE     => {:name => 0},
  KIND_TYPED_ARRAY       => {:element_type => 0, :size => 1},
  KIND_TYPED_ARRAY_NEW   => {:element_type => 0, :size => 1},
  KIND_UNARY_OP          => {:op => 0, :operand => 1},
  KIND_USE               => {:path => 0},
  KIND_UUID              => {:value => 0},
  KIND_VAR               => {:name => 257},
  KIND_VIEW_BASE         => {},
  KIND_VIEW_VALUE        => {},
  KIND_VIEW_ACCESS       => {:view_name => 0, :index => 1},
  KIND_VIEW_DECL         => {:name => 0, :kind => 1, :count => 2},
  KIND_VIEW_FIELD        => {:field => 0},
  KIND_VIEW_FIELD_VAR    => {:receiver => 0, :field => 1},
  KIND_WHEN              => {:conditions => 0, :body => 1},
  KIND_WHILE             => {:condition => 0, :body => 1},
  KIND_WITH              => {:bindings => 0, :body => 1},
  KIND_WORD_ARRAY        => {:words => 0},
  KIND_WVALUE            => {:value => 0, :raw => 1},
  KIND_YIELD             => {:args => 0},
  KIND_CIDR_MATCH        => {:subject => 0, :cidr => 1},
  KIND_REGEX_MATCH       => {:regex => 0, :subject => 1},
  KIND_NAMESPACE_DECL    => {:namespace => 0},
  KIND_IVARS_DECL        => {:entries => 0},
  KIND_FILE              => {:path => 0, :source => 1, :body => 2},
  KIND_MAP               => {:source => 0, :func => 1, :kind => 2},
  KIND_CALC              => {:op => 0, :source => 1, :type_intent => 2},
  KIND_CLASS_REF         => {:name => 257},
}

# Array-indexed view of slab_offset_table_data. Built once at module
# load by build_slab_offset_arr (below). Hash<int, Hash> → Array<Hash>
# lets the outer kid lookup be an O(1) array index instead of a hash
# probe — saves one Hash#[] call per ast_get / ast_set.
-> build_slab_offset_arr(hash)
  arr = [nil]
  i = 1
  while i <= KIND_MAX
    arr.push(hash[i])
    i += 1
  arr

slab_offset_table_arr = build_slab_offset_arr(slab_offset_table_data)

# Precomputed per-kind field-key arrays. The Hash#keys() call would
# otherwise allocate a fresh Array on every ast_children /
# ast_array_fields / ast_deep_clone invocation; baking it once at
# module load and indexing by kind_id avoids ~5K Array allocations
# per self-compile.
-> build_slab_keys_arr(arr)
  out = [nil]
  i = 1
  while i <= KIND_MAX
    h = arr[i]
    if h == nil
      out.push(nil)
    else
      out.push(h.keys())
    i += 1
  out

slab_keys_table = build_slab_keys_arr(slab_offset_table_arr)

-> slab_offset_for_id(kid, sym)
  # Raw integer-kind-id variant of slab_offset_for. The caller already holds
  # the kind id (from w_node_kind_extern), so this skips the type()=="Symbol"
  # probe and the kind_id_table reverse lookup that slab_offset_for pays on
  # every call. ast_get/ast_set drive slab-node field access through here --
  # ~15 probes per node in the autoload walker, the top codegen hotspot -- so
  # avoiding the symbol round-trip (node -> id -> symbol -> id) matters.
  if kid < 1 || kid > KIND_MAX
    return nil
  k = slab_offset_table_arr[kid]
  if k == nil
    return nil
  k[sym]

-> slab_offset_for(kind, sym)
  # Symbol-or-int entry point (parser/builder callers pass a kind symbol).
  # Resolve to the integer id once, then share slab_offset_for_id's body.
  kid = kind
  if type(kind) == "Symbol"
    kid = kind_id_table[kind]
    if kid == nil
      return nil
  slab_offset_for_id(kid, sym)

# === KIND → size class lookup ===
#
# Initial assignment, sized to the constructors in ast.w as they
# exist today (PR #2 Phase 3 baseline). When line/col move into
# slab slots in Phase 4, kinds whose data fields + line/col exceed
# SC_4's 4 slots must promote to SC_8 — but that decision is local
# to each constructor's rewrite and reflected in this function.

-> sc_for_kind(kind)
  # SC_8: constructors with 4-6 data fields. These have enough room
  # for line/col plus their own data without spilling to SC_2.
  case kind
  when KIND_CALL           then return SC_8
  when KIND_IF             then return SC_8
  when KIND_METHOD_DEF     then return SC_8
  when KIND_FN_DEF         then return SC_8
  when KIND_CLASS_DEF      then return SC_8
  when KIND_GPU_KERNEL_DEF then return SC_8
  when KIND_SAFE_NAV       then return SC_8
  when KIND_SCHEDULE_DEF   then return SC_8
  when KIND_LAYOUT_DEF     then return SC_8
  when KIND_VIEW_DECL      then return SC_8
  when KIND_VIEW_ACCESS    then return SC_8
  when KIND_PARAM          then return SC_8

  else
    SC_4

# === Schema hash compute ===
#
# Phase 7 (loader cache) embeds this hash in the cache header and
# rejects loads when it diverges from the recompiled value. For now
# the hash is a simple checksum over (KIND_MAX, every kind ID, every
# kind's SC). Field offsets aren't included yet because they live in
# ast.w; once Phase 4 lands, add F_* contributions here.
#
# Stability rule: appending a new kind bumps the hash (new ID is
# folded in). Reassigning an existing kind's ID or SC also bumps it.
# Adding a new field offset later (Phase 4) will bump it again. All
# correct: every schema-relevant change invalidates pre-change caches.

-> w_ast_schema_hash_tungsten
  h = 1469598103934665603 ## i64   # FNV-1a 64-bit offset basis
  # Mix in KIND_MAX
  h = h ^ KIND_MAX
  h = h * 1099511628211 ## i64     # FNV prime
  # Mix in every (kind, sc) pair.
  k = 1
  while k <= KIND_MAX
    h = h ^ k
    h = h * 1099511628211 ## i64
    h = h ^ sc_for_kind(k)
    h = h * 1099511628211 ## i64
    k = k + 1
  h
