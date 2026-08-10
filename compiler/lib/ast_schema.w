# ast_schema.w — slab-AST schema (PR #2 Phase 3).
#
# Defines stable kind IDs, exact field widths, and legacy layout-class
# metadata used by W_PACKED_NODE handles and AST:Store.
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
# Exact widths come directly from the ordered ivar declarations in ast.w;
# allocation therefore has no rounding or per-node header.

# === Legacy layout classes ===
#
# These values remain in the 2-bit handle field as descriptive width
# buckets and preserve the stable AST ABI. Storage is exact-width: the
# generated width table allocates precisely the declared field count in
# one word-addressed arena, so these classes no longer select a slab.
#
#   SC_2  = 1-2 declared fields
#   SC_4  = 3 declared fields
#   SC_8  = 4-8 declared fields
#   SC_16 = reserved

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
KIND_TYPE_ASCRIPTION    = 148 ## i64

KIND_MAX = 148 ## i64

# BEGIN GENERATED AST ABI
# Generated by scripts/gen_ast_schema.rb from ast.w. Do not edit.
# The KIND_* numeric registry above is stable and remains hand-assigned.

AST_SCHEMA_ABI_VERSION = 2 ## i64
AST_SCHEMA_HASH = 48780547159910 ## i64

KIND_ID_TABLE = {
  :nil_lit             => KIND_NIL_LIT,
  :self_ref            => KIND_SELF_REF,
  :view_base           => KIND_VIEW_BASE,
  :view_value          => KIND_VIEW_VALUE,
  :return_nil          => KIND_RETURN_NIL,
  :and                 => KIND_AND,
  :array               => KIND_ARRAY,
  :assign              => KIND_ASSIGN,
  :begin               => KIND_BEGIN,
  :binary_op           => KIND_BINARY_OP,
  :block               => KIND_BLOCK,
  :bool                => KIND_BOOL,
  :break               => KIND_BREAK,
  :byte_array          => KIND_BYTE_ARRAY,
  :byte_array_interp   => KIND_BYTE_ARRAY_INTERP,
  :call                => KIND_CALL,
  :case                => KIND_CASE,
  :case_arm            => KIND_CASE_ARM,
  :case_value          => KIND_CASE_VALUE,
  :char                => KIND_CHAR,
  :cidr4               => KIND_CIDR4,
  :class_def           => KIND_CLASS_DEF,
  :codepoint           => KIND_CODEPOINT,
  :color               => KIND_COLOR,
  :compound_assign     => KIND_COMPOUND_ASSIGN,
  :currency            => KIND_CURRENCY,
  :cvar                => KIND_CVAR,
  :date                => KIND_DATE,
  :datetime            => KIND_DATETIME,
  :decimal             => KIND_DECIMAL,
  :duration            => KIND_DURATION,
  :encoded             => KIND_ENCODED,
  :extern_fn           => KIND_EXTERN_FN,
  :extern_lib          => KIND_EXTERN_LIB,
  :field_decl          => KIND_FIELD_DECL,
  :float               => KIND_FLOAT,
  :fn_def              => KIND_FN_DEF,
  :go                  => KIND_GO,
  :gpu_kernel_def      => KIND_GPU_KERNEL_DEF,
  :hash_literal        => KIND_HASH_LITERAL,
  :if                  => KIND_IF,
  :in_test             => KIND_IN_TEST,
  :int                 => KIND_INT,
  :ip4                 => KIND_IP4,
  :ivar                => KIND_IVAR,
  :key                 => KIND_KEY,
  :lambda_arity        => KIND_LAMBDA_ARITY,
  :layout_def          => KIND_LAYOUT_DEF,
  :magic_constant      => KIND_MAGIC_CONSTANT,
  :map_op              => KIND_MAP_OP,
  :method_def          => KIND_METHOD_DEF,
  :module_def          => KIND_MODULE_DEF,
  :month               => KIND_MONTH,
  :multi_assign        => KIND_MULTI_ASSIGN,
  :next                => KIND_NEXT,
  :not                 => KIND_NOT,
  :on_guard            => KIND_ON_GUARD,
  :or                  => KIND_OR,
  :parallel_with       => KIND_PARALLEL_WITH,
  :param               => KIND_PARAM,
  :parg                => KIND_PARG,
  :passthrough         => KIND_PASSTHROUGH,
  :print               => KIND_PRINT,
  :program             => KIND_PROGRAM,
  :puts                => KIND_PUTS,
  :quantity            => KIND_QUANTITY,
  :raise               => KIND_RAISE,
  :range               => KIND_RANGE,
  :rational            => KIND_RATIONAL,
  :regex               => KIND_REGEX,
  :regex_capture       => KIND_REGEX_CAPTURE,
  :rescue_expr         => KIND_RESCUE_EXPR,
  :return              => KIND_RETURN,
  :safe_nav            => KIND_SAFE_NAV,
  :schedule_def        => KIND_SCHEDULE_DEF,
  :string              => KIND_STRING,
  :string_interp       => KIND_STRING_INTERP,
  :super               => KIND_SUPER,
  :superscript         => KIND_SUPERSCRIPT,
  :symbol              => KIND_SYMBOL,
  :symbol_array        => KIND_SYMBOL_ARRAY,
  :target_and          => KIND_TARGET_AND,
  :target_designator   => KIND_TARGET_DESIGNATOR,
  :target_not          => KIND_TARGET_NOT,
  :target_or           => KIND_TARGET_OR,
  :time                => KIND_TIME,
  :trait_def           => KIND_TRAIT_DEF,
  :trait_include       => KIND_TRAIT_INCLUDE,
  :typed_array         => KIND_TYPED_ARRAY,
  :typed_array_new     => KIND_TYPED_ARRAY_NEW,
  :unary_op            => KIND_UNARY_OP,
  :use                 => KIND_USE,
  :uuid                => KIND_UUID,
  :var                 => KIND_VAR,
  :view_access         => KIND_VIEW_ACCESS,
  :view_decl           => KIND_VIEW_DECL,
  :view_field          => KIND_VIEW_FIELD,
  :when                => KIND_WHEN,
  :while               => KIND_WHILE,
  :with                => KIND_WITH,
  :word_array          => KIND_WORD_ARRAY,
  :wvalue              => KIND_WVALUE,
  :yield               => KIND_YIELD,
  :cidr_match          => KIND_CIDR_MATCH,
  :regex_match         => KIND_REGEX_MATCH,
  :namespace_decl      => KIND_NAMESPACE_DECL,
  :ivars_decl          => KIND_IVARS_DECL,
  :file                => KIND_FILE,
  :map                 => KIND_MAP,
  :calc                => KIND_CALC,
  :class_ref           => KIND_CLASS_REF,
  :recase              => KIND_RECASE,
  :gvar                => KIND_GVAR,
  :view_field_var      => KIND_VIEW_FIELD_VAR,
  :ip6                 => KIND_IP6,
  :cidr6               => KIND_CIDR6,
  :type_ascription     => KIND_TYPE_ASCRIPTION,
}

kind_id_table = KIND_ID_TABLE
kind_sym_table_data = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, :nil_lit, :self_ref, :view_base, :view_value, :return, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, :and, :array, :assign, :begin, :binary_op, :block, :bool, :break, :byte_array, :byte_array_interp, :call, :case, :case_arm, :case_value, :char, :cidr4, :class_def, :codepoint, :color, :compound_assign, :currency, :cvar, :date, :datetime, :decimal, :duration, :encoded, :extern_fn, :extern_lib, :field_decl, :float, :fn_def, :go, :gpu_kernel_def, :hash_literal, :if, :in_test, :int, :ip4, :ivar, :key, :lambda_arity, :layout_def, :magic_constant, :map_op, :method_def, :module_def, :month, :multi_assign, :next, nil, :not, :on_guard, :or, :parallel_with, :param, :parg, :passthrough, :print, :program, :puts, :quantity, :raise, :range, :rational, :regex, :regex_capture, :rescue_expr, :return, :safe_nav, :schedule_def, nil, :string, :string_interp, :super, :superscript, :symbol, :symbol_array, :target_and, :target_designator, :target_not, :target_or, :time, :trait_def, :trait_include, :typed_array, :typed_array_new, :unary_op, :use, :uuid, :var, :view_access, nil, :view_decl, :view_field, nil, :when, :while, :with, :word_array, :wvalue, :yield, :cidr_match, :regex_match, :namespace_decl, :ivars_decl, :file, :map, :calc, :class_ref, :recase, :gvar, :view_field_var, :ip6, :cidr6, :type_ascription]

-> kind_id_for_name(sym)
  v = kind_id_table[sym]
  return -1 if v == nil
  v

-> kind_sym_for_id(kind_id)
  return nil if kind_id < 0 || kind_id > KIND_MAX
  kind_sym_table_data[kind_id]

OFFSET_INLINE = 256 ## i64
OFFSET_INTERN = 257 ## i64

slab_offset_table_data = {
  KIND_NIL_LIT              => {},
  KIND_SELF_REF             => {},
  KIND_VIEW_BASE            => {},
  KIND_VIEW_VALUE           => {},
  KIND_RETURN_NIL           => {},
  KIND_AND                  => {:left => 0, :right => 1},
  KIND_ARRAY                => {:elements => 0},
  KIND_ASSIGN               => {:target => 0, :value => 1, :type_hint => 2},
  KIND_BEGIN                => {:body => 0, :rescue_var => 1, :rescue_body => 2, :ensure_body => 3},
  KIND_BINARY_OP            => {:left => 0, :op => 1, :right => 2},
  KIND_BLOCK                => {:params => 0, :body => 1, :loc => 2, :loc_end => 3},
  KIND_BOOL                 => {:value => 0},
  KIND_BREAK                => {},
  KIND_BYTE_ARRAY           => {:values => 0},
  KIND_BYTE_ARRAY_INTERP    => {:parts => 0},
  KIND_CALL                 => {:receiver => 0, :name => 1, :args => 2, :block => 3, :loc => 4, :loc_end => 5},
  KIND_CASE                 => {:whens => 0, :else_body => 1},
  KIND_CASE_ARM             => {:pattern => 0, :guard => 1, :body => 2},
  KIND_CASE_VALUE           => {:subject => 0, :arms => 1, :else_body => 2},
  KIND_CHAR                 => {:value => OFFSET_INLINE},
  KIND_CIDR4                => {:value => 0},
  KIND_CLASS_DEF            => {:name => 0, :superclass => 1, :body => 2, :class_role => 3},
  KIND_CODEPOINT            => {:value => OFFSET_INLINE},
  KIND_COLOR                => {:rgba => OFFSET_INLINE},
  KIND_COMPOUND_ASSIGN      => {:target => 0, :op => 1, :value => 2},
  KIND_CURRENCY             => {:amount => 0, :prefix => 1, :suffix => 2},
  KIND_CVAR                 => {:name => OFFSET_INTERN},
  KIND_DATE                 => {:value => 0},
  KIND_DATETIME             => {:value => 0},
  KIND_DECIMAL              => {:value => 0},
  KIND_DURATION             => {:raw => 0},
  KIND_ENCODED              => {:value => 0, :encoding => 1},
  KIND_EXTERN_FN            => {:name => 0, :return_type => 1, :param_types => 2},
  KIND_EXTERN_LIB           => {:lib_name => 0, :declarations => 1},
  KIND_FIELD_DECL           => {:name => 0, :field_type => 1},
  KIND_FLOAT                => {:value => 0},
  KIND_FN_DEF               => {:name => 0, :params => 1, :body => 2, :type_hints => 3, :loc => 4, :loc_end => 5},
  KIND_GO                   => {:body => 0},
  KIND_GPU_KERNEL_DEF       => {:name => 0, :params => 1, :body => 2, :attribute => 3, :type_hints => 4, :loc => 5, :loc_end => 6},
  KIND_HASH_LITERAL         => {:entries => 0},
  KIND_IF                   => {:condition => 0, :then_body => 1, :elsif_clauses => 2, :else_body => 3},
  KIND_IN_TEST              => {:lhs => 0, :elements => 1},
  KIND_INT                  => {:value => 0, :format => 1, :raw => 2},
  KIND_IP4                  => {:value => 0},
  KIND_IVAR                 => {:name => OFFSET_INTERN},
  KIND_KEY                  => {:value => 0},
  KIND_LAMBDA_ARITY         => {:value => OFFSET_INLINE},
  KIND_LAYOUT_DEF           => {:kernel => 0, :variant => 1, :directives => 2, :loc => 3, :loc_end => 4},
  KIND_MAGIC_CONSTANT       => {:name => 0, :loc => 1, :loc_end => 2},
  KIND_MAP_OP               => {:name => 0},
  KIND_METHOD_DEF           => {:name => 0, :params => 1, :body => 2, :type_hints => 3, :is_class_method => 4, :loc => 5, :loc_end => 6},
  KIND_MODULE_DEF           => {:name => 0, :body => 1},
  KIND_MONTH                => {:value => 0},
  KIND_MULTI_ASSIGN         => {:targets => 0, :value => 1},
  KIND_NEXT                 => {},
  KIND_NOT                  => {:operand => 0},
  KIND_ON_GUARD             => {:predicate => 0, :capabilities => 1, :body => 2},
  KIND_OR                   => {:left => 0, :right => 1},
  KIND_PARALLEL_WITH        => {:bindings => 0, :body => 1},
  KIND_PARAM                => {:name => 0, :default => 1, :ivar_assign => 2, :keyword => 3, :block_param => 4, :splat => 5},
  KIND_PARG                 => {:index => OFFSET_INLINE},
  KIND_PASSTHROUGH          => {:expression => 0, :value => 1},
  KIND_PRINT                => {:value => 0},
  KIND_PROGRAM              => {:expressions => 0},
  KIND_PUTS                 => {:value => 0},
  KIND_QUANTITY             => {:number_str => 0, :unit => 1},
  KIND_RAISE                => {:value => 0, :loc => 1, :loc_end => 2},
  KIND_RANGE                => {:from => 0, :to => 1, :exclusive => 2},
  KIND_RATIONAL             => {:value => 0},
  KIND_REGEX                => {:pattern => 0, :options => 1},
  KIND_REGEX_CAPTURE        => {:index => OFFSET_INLINE},
  KIND_RESCUE_EXPR          => {:body => 0, :fallback => 1},
  KIND_RETURN               => {:value => 0},
  KIND_SAFE_NAV             => {:receiver => 0, :name => 1, :args => 2, :block => 3, :loc => 4, :loc_end => 5},
  KIND_SCHEDULE_DEF         => {:kernel => 0, :variant => 1, :directives => 2, :loc => 3, :loc_end => 4},
  KIND_STRING               => {:value => OFFSET_INTERN},
  KIND_STRING_INTERP        => {:parts => 0},
  KIND_SUPER                => {:args => 0},
  KIND_SUPERSCRIPT          => {:value => OFFSET_INLINE},
  KIND_SYMBOL               => {:value => OFFSET_INTERN},
  KIND_SYMBOL_ARRAY         => {:symbols => 0},
  KIND_TARGET_AND           => {:left => 0, :right => 1},
  KIND_TARGET_DESIGNATOR    => {:name => 0},
  KIND_TARGET_NOT           => {:expression => 0},
  KIND_TARGET_OR            => {:left => 0, :right => 1},
  KIND_TIME                 => {:value => 0},
  KIND_TRAIT_DEF            => {:name => 0, :body => 1},
  KIND_TRAIT_INCLUDE        => {:name => 0},
  KIND_TYPED_ARRAY          => {:element_type => 0, :size => 1},
  KIND_TYPED_ARRAY_NEW      => {:element_type => 0, :size => 1},
  KIND_UNARY_OP             => {:op => 0, :operand => 1},
  KIND_USE                  => {:path => 0},
  KIND_UUID                 => {:value => 0},
  KIND_VAR                  => {:name => OFFSET_INTERN},
  KIND_VIEW_ACCESS          => {:view_name => 0, :index => 1},
  KIND_VIEW_DECL            => {:name => 0, :kind => 1, :count => 2},
  KIND_VIEW_FIELD           => {:field => 0},
  KIND_WHEN                 => {:conditions => 0, :body => 1},
  KIND_WHILE                => {:condition => 0, :body => 1},
  KIND_WITH                 => {:bindings => 0, :body => 1},
  KIND_WORD_ARRAY           => {:words => 0},
  KIND_WVALUE               => {:value => 0, :raw => 1},
  KIND_YIELD                => {:args => 0},
  KIND_CIDR_MATCH           => {:subject => 0, :cidr => 1},
  KIND_REGEX_MATCH          => {:regex => 0, :subject => 1},
  KIND_NAMESPACE_DECL       => {:namespace => 0},
  KIND_IVARS_DECL           => {:entries => 0},
  KIND_FILE                 => {:path => 0, :source => 1, :body => 2},
  KIND_MAP                  => {:source => 0, :func => 1, :kind => 2},
  KIND_CALC                 => {:op => 0, :source => 1, :type_intent => 2},
  KIND_CLASS_REF            => {:name => OFFSET_INTERN},
  KIND_RECASE               => {:value => 0},
  KIND_GVAR                 => {:name => OFFSET_INTERN},
  KIND_VIEW_FIELD_VAR       => {:receiver => 0, :field => 1},
  KIND_IP6                  => {:value => 0},
  KIND_CIDR6                => {:value => 0},
  KIND_TYPE_ASCRIPTION      => {:expression => 0, :type_hint => 1},
}

slab_field_type_table_data = {
  KIND_NIL_LIT              => {},
  KIND_SELF_REF             => {},
  KIND_VIEW_BASE            => {},
  KIND_VIEW_VALUE           => {},
  KIND_RETURN_NIL           => {},
  KIND_AND                  => {:left => :ast, :right => :ast},
  KIND_ARRAY                => {:elements => :ast},
  KIND_ASSIGN               => {:target => :ast, :value => :ast, :type_hint => :ast},
  KIND_BEGIN                => {:body => :ast, :rescue_var => :ast, :rescue_body => :ast, :ensure_body => :ast},
  KIND_BINARY_OP            => {:left => :ast, :op => :w64, :right => :ast},
  KIND_BLOCK                => {:params => :ast, :body => :ast, :loc => :w64, :loc_end => :w64},
  KIND_BOOL                 => {:value => :w64},
  KIND_BREAK                => {},
  KIND_BYTE_ARRAY           => {:values => :ast},
  KIND_BYTE_ARRAY_INTERP    => {:parts => :ast},
  KIND_CALL                 => {:receiver => :ast, :name => :w64, :args => :ast, :block => :ast, :loc => :w64, :loc_end => :w64},
  KIND_CASE                 => {:whens => :ast, :else_body => :ast},
  KIND_CASE_ARM             => {:pattern => :ast, :guard => :ast, :body => :ast},
  KIND_CASE_VALUE           => {:subject => :ast, :arms => :ast, :else_body => :ast},
  KIND_CHAR                 => {:value => :inline},
  KIND_CIDR4                => {:value => :w64},
  KIND_CLASS_DEF            => {:name => :w64, :superclass => :w64, :body => :ast, :class_role => :w64},
  KIND_CODEPOINT            => {:value => :inline},
  KIND_COLOR                => {:rgba => :inline},
  KIND_COMPOUND_ASSIGN      => {:target => :ast, :op => :w64, :value => :ast},
  KIND_CURRENCY             => {:amount => :w64, :prefix => :w64, :suffix => :w64},
  KIND_CVAR                 => {:name => :w64},
  KIND_DATE                 => {:value => :w64},
  KIND_DATETIME             => {:value => :w64},
  KIND_DECIMAL              => {:value => :w64},
  KIND_DURATION             => {:raw => :w64},
  KIND_ENCODED              => {:value => :w64, :encoding => :w64},
  KIND_EXTERN_FN            => {:name => :w64, :return_type => :w64, :param_types => :w64},
  KIND_EXTERN_LIB           => {:lib_name => :ast, :declarations => :ast},
  KIND_FIELD_DECL           => {:name => :w64, :field_type => :ast},
  KIND_FLOAT                => {:value => :w64},
  KIND_FN_DEF               => {:name => :w64, :params => :ast, :body => :ast, :type_hints => :ast, :loc => :w64, :loc_end => :w64},
  KIND_GO                   => {:body => :ast},
  KIND_GPU_KERNEL_DEF       => {:name => :w64, :params => :ast, :body => :ast, :attribute => :ast, :type_hints => :ast, :loc => :w64, :loc_end => :w64},
  KIND_HASH_LITERAL         => {:entries => :ast},
  KIND_IF                   => {:condition => :ast, :then_body => :ast, :elsif_clauses => :ast, :else_body => :ast},
  KIND_IN_TEST              => {:lhs => :ast, :elements => :ast},
  KIND_INT                  => {:value => :w64, :format => :w64, :raw => :w64},
  KIND_IP4                  => {:value => :w64},
  KIND_IVAR                 => {:name => :w64},
  KIND_KEY                  => {:value => :w64},
  KIND_LAMBDA_ARITY         => {:value => :inline},
  KIND_LAYOUT_DEF           => {:kernel => :w64, :variant => :w64, :directives => :ast, :loc => :w64, :loc_end => :w64},
  KIND_MAGIC_CONSTANT       => {:name => :w64, :loc => :w64, :loc_end => :w64},
  KIND_MAP_OP               => {:name => :w64},
  KIND_METHOD_DEF           => {:name => :w64, :params => :ast, :body => :ast, :type_hints => :ast, :is_class_method => :w64, :loc => :w64, :loc_end => :w64},
  KIND_MODULE_DEF           => {:name => :w64, :body => :ast},
  KIND_MONTH                => {:value => :w64},
  KIND_MULTI_ASSIGN         => {:targets => :ast, :value => :ast},
  KIND_NEXT                 => {},
  KIND_NOT                  => {:operand => :ast},
  KIND_ON_GUARD             => {:predicate => :ast, :capabilities => :ast, :body => :ast},
  KIND_OR                   => {:left => :ast, :right => :ast},
  KIND_PARALLEL_WITH        => {:bindings => :ast, :body => :ast},
  KIND_PARAM                => {:name => :w64, :default => :ast, :ivar_assign => :w64, :keyword => :w64, :block_param => :w64, :splat => :w64},
  KIND_PARG                 => {:index => :inline},
  KIND_PASSTHROUGH          => {:expression => :ast, :value => :ast},
  KIND_PRINT                => {:value => :ast},
  KIND_PROGRAM              => {:expressions => :ast},
  KIND_PUTS                 => {:value => :ast},
  KIND_QUANTITY             => {:number_str => :w64, :unit => :w64},
  KIND_RAISE                => {:value => :ast, :loc => :w64, :loc_end => :w64},
  KIND_RANGE                => {:from => :ast, :to => :ast, :exclusive => :w64},
  KIND_RATIONAL             => {:value => :w64},
  KIND_REGEX                => {:pattern => :w64, :options => :w64},
  KIND_REGEX_CAPTURE        => {:index => :inline},
  KIND_RESCUE_EXPR          => {:body => :ast, :fallback => :ast},
  KIND_RETURN               => {:value => :ast},
  KIND_SAFE_NAV             => {:receiver => :ast, :name => :w64, :args => :ast, :block => :ast, :loc => :w64, :loc_end => :w64},
  KIND_SCHEDULE_DEF         => {:kernel => :w64, :variant => :w64, :directives => :ast, :loc => :w64, :loc_end => :w64},
  KIND_STRING               => {:value => :w64},
  KIND_STRING_INTERP        => {:parts => :ast},
  KIND_SUPER                => {:args => :ast},
  KIND_SUPERSCRIPT          => {:value => :inline},
  KIND_SYMBOL               => {:value => :w64},
  KIND_SYMBOL_ARRAY         => {:symbols => :ast},
  KIND_TARGET_AND           => {:left => :ast, :right => :ast},
  KIND_TARGET_DESIGNATOR    => {:name => :w64},
  KIND_TARGET_NOT           => {:expression => :ast},
  KIND_TARGET_OR            => {:left => :ast, :right => :ast},
  KIND_TIME                 => {:value => :w64},
  KIND_TRAIT_DEF            => {:name => :w64, :body => :ast},
  KIND_TRAIT_INCLUDE        => {:name => :w64},
  KIND_TYPED_ARRAY          => {:element_type => :w64, :size => :ast},
  KIND_TYPED_ARRAY_NEW      => {:element_type => :w64, :size => :ast},
  KIND_UNARY_OP             => {:op => :w64, :operand => :ast},
  KIND_USE                  => {:path => :w64},
  KIND_UUID                 => {:value => :w64},
  KIND_VAR                  => {:name => :w64},
  KIND_VIEW_ACCESS          => {:view_name => :ast, :index => :w64},
  KIND_VIEW_DECL            => {:name => :w64, :kind => :w64, :count => :w64},
  KIND_VIEW_FIELD           => {:field => :w64},
  KIND_WHEN                 => {:conditions => :ast, :body => :ast},
  KIND_WHILE                => {:condition => :ast, :body => :ast},
  KIND_WITH                 => {:bindings => :ast, :body => :ast},
  KIND_WORD_ARRAY           => {:words => :ast},
  KIND_WVALUE               => {:value => :w64, :raw => :w64},
  KIND_YIELD                => {:args => :ast},
  KIND_CIDR_MATCH           => {:subject => :ast, :cidr => :ast},
  KIND_REGEX_MATCH          => {:regex => :ast, :subject => :ast},
  KIND_NAMESPACE_DECL       => {:namespace => :w64},
  KIND_IVARS_DECL           => {:entries => :ast},
  KIND_FILE                 => {:path => :w64, :source => :w64, :body => :ast},
  KIND_MAP                  => {:source => :ast, :func => :ast, :kind => :w64},
  KIND_CALC                 => {:op => :w64, :source => :ast, :type_intent => :w64},
  KIND_CLASS_REF            => {:name => :w64},
  KIND_RECASE               => {:value => :ast},
  KIND_GVAR                 => {:name => :w64},
  KIND_VIEW_FIELD_VAR       => {:receiver => :ast, :field => :w64},
  KIND_IP6                  => {:value => :w64},
  KIND_CIDR6                => {:value => :w64},
  KIND_TYPE_ASCRIPTION      => {:expression => :ast, :type_hint => :w64},
}

-> build_slab_table_arr(hash)
  arr = [nil]
  i = 1
  while i <= KIND_MAX
    arr.push(hash[i])
    i += 1
  arr

slab_offset_table_arr = build_slab_table_arr(slab_offset_table_data)
slab_field_type_table_arr = build_slab_table_arr(slab_field_type_table_data)

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
  return nil if kid < 1 || kid > KIND_MAX
  fields = slab_offset_table_arr[kid]
  return nil if fields == nil
  fields[sym]

-> slab_offset_for(kind, sym)
  kid = kind
  if type(kind) == "Symbol"
    kid = kind_id_table[kind]
    return nil if kid == nil
  slab_offset_for_id(kid, sym)

slab_sclass_table = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, SC_2, SC_2, SC_2, SC_2, SC_2, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, SC_2, SC_2, SC_4, SC_8, SC_4, SC_8, SC_2, SC_2, SC_2, SC_2, SC_8, SC_2, SC_4, SC_4, SC_2, SC_2, SC_8, SC_2, SC_2, SC_4, SC_4, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_4, SC_2, SC_2, SC_2, SC_8, SC_2, SC_8, SC_2, SC_8, SC_2, SC_4, SC_2, SC_2, SC_2, SC_2, SC_8, SC_4, SC_2, SC_8, SC_2, SC_2, SC_2, SC_2, nil, SC_2, SC_4, SC_2, SC_2, SC_8, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_4, SC_4, SC_2, SC_2, SC_2, SC_2, SC_2, SC_8, SC_8, nil, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, nil, SC_4, SC_2, nil, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_4, SC_4, SC_4, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2, SC_2]
slab_width_table = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 3, 4, 3, 4, 1, 0, 1, 1, 6, 2, 3, 3, 0, 1, 4, 0, 0, 3, 3, 0, 1, 1, 1, 1, 2, 3, 2, 2, 1, 6, 1, 7, 1, 4, 2, 3, 1, 0, 1, 0, 5, 3, 1, 7, 2, 1, 2, 0, 0, 1, 3, 2, 2, 6, 0, 2, 1, 1, 1, 2, 3, 3, 1, 2, 0, 2, 1, 6, 5, 0, 0, 1, 1, 0, 0, 1, 2, 1, 1, 2, 1, 2, 1, 2, 2, 2, 1, 1, 0, 2, 0, 3, 1, 0, 2, 2, 2, 1, 2, 1, 2, 2, 1, 1, 3, 3, 3, 0, 1, 0, 2, 1, 1, 2]
slab_child_offsets_table = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, [], [], [], [], [], nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, [0, 1], [0], [0, 1, 2], [0, 1, 2, 3], [0, 2], [0, 1], [], [], [0], [0], [0, 2, 3], [0, 1], [0, 1, 2], [0, 1, 2], [], [], [2], [], [], [0, 2], [], [], [], [], [], [], [], [], [0, 1], [1], [], [1, 2, 3], [0], [1, 2, 3, 4], [0], [0, 1, 2, 3], [0, 1], [], [], [], [], [], [2], [], [], [1, 2, 3], [1], [], [0, 1], [], nil, [0], [0, 1, 2], [0, 1], [0, 1], [1], [], [0, 1], [0], [0], [0], [], [0], [0, 1], [], [], [], [0, 1], [0], [0, 2, 3], [2], nil, [], [0], [0], [], [], [0], [0, 1], [], [0], [0, 1], [], [1], [], [1], [1], [1], [], [], [], [0], nil, [], [], nil, [0, 1], [0, 1], [0, 1], [0], [], [0], [0, 1], [0, 1], [], [0], [2], [0, 1], [1], [], [0], [], [0], [], [], [0]]
slab_child_keys_table = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, [], [], [], [], [], nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, [:left, :right], [:elements], [:target, :value, :type_hint], [:body, :rescue_var, :rescue_body, :ensure_body], [:left, :right], [:params, :body], [], [], [:values], [:parts], [:receiver, :args, :block], [:whens, :else_body], [:pattern, :guard, :body], [:subject, :arms, :else_body], [], [], [:body], [], [], [:target, :value], [], [], [], [], [], [], [], [], [:lib_name, :declarations], [:field_type], [], [:params, :body, :type_hints], [:body], [:params, :body, :attribute, :type_hints], [:entries], [:condition, :then_body, :elsif_clauses, :else_body], [:lhs, :elements], [], [], [], [], [], [:directives], [], [], [:params, :body, :type_hints], [:body], [], [:targets, :value], [], nil, [:operand], [:predicate, :capabilities, :body], [:left, :right], [:bindings, :body], [:default], [], [:expression, :value], [:value], [:expressions], [:value], [], [:value], [:from, :to], [], [], [], [:body, :fallback], [:value], [:receiver, :args, :block], [:directives], nil, [], [:parts], [:args], [], [], [:symbols], [:left, :right], [], [:expression], [:left, :right], [], [:body], [], [:size], [:size], [:operand], [], [], [], [:view_name], nil, [], [], nil, [:conditions, :body], [:condition, :body], [:bindings, :body], [:words], [], [:args], [:subject, :cidr], [:regex, :subject], [], [:entries], [:body], [:source, :func], [:source], [], [:value], [], [:receiver], [], [], [:expression]]

-> sc_for_kind(kind)
  return SC_2 if kind < 1 || kind > KIND_MAX
  sc = slab_sclass_table[kind]
  return SC_2 if sc == nil
  sc

-> width_for_kind(kind)
  return 0 if kind < 1 || kind > KIND_MAX
  slab_width_table[kind]

-> slab_field_type_for_id(kind, sym)
  return nil if kind < 1 || kind > KIND_MAX
  fields = slab_field_type_table_arr[kind]
  return nil if fields == nil
  fields[sym]
# END GENERATED AST ABI

-> w_ast_schema_hash_tungsten
  AST_SCHEMA_HASH
