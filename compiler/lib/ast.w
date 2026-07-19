# AST node constructor functions.
#
# Constructors return W_PACKED_NODE WValues backed by the runtime
# node arenas. Field data lives in slab slots according to
# ast_schema.w; sparse metadata and post-parse annotations are stored
# through ast_get/ast_set helpers.
#
# Field indexing follows constructor parameter order: the i-th
# parameter is stored at slab slot i.

use ast_schema
use ../../core/ast_body

# === AST:Node class ===
#
# Tungsten class registered for dispatch_key 0xE3 (W_PACKED with
# subtype W_PACKED_NODE = 3). Method calls on any W_PACKED_NODE
# WValue route here, so `node.receiver` / `node.kind` / etc. work
# uniformly across all slab-AST kinds.
#
# `in Tungsten:AST` below puts the kind subclasses (Program, Int, …)
# into the `Tungsten:AST:` namespace automatically. The parent
# itself (Node) is also declared bare inside that namespace,
# resolving to Tungsten:AST:Node.
#
# Field accessors flow through method_missing (defined in the
# generated section below) which delegates to ast_get / ast_set.

in Tungsten:AST

+ Node
  -> kind
    ast_kind(self)

  # Field setters — mirror the materialized getters so call sites can
  # write `node.field = v` instead of `ast_set(node, :field, v)`. Each
  # routes through ast_set, which dispatches slab-slot vs sparse-meta
  # internally, so one body covers both storage classes.
  -> loc=(value)
    ast_set(self, :loc, value)
  -> loc_end=(value)
    ast_set(self, :loc_end, value)
  -> left=(value)
    ast_set(self, :left, value)
  -> right=(value)
    ast_set(self, :right, value)
  -> operand=(value)
    ast_set(self, :operand, value)
  -> receiver=(value)
    ast_set(self, :receiver, value)
  -> default=(value)
    ast_set(self, :default, value)
  -> return_type=(value)
    ast_set(self, :return_type, value)
  -> param_types=(value)
    ast_set(self, :param_types, value)
  -> typed_overload=(value)
    ast_set(self, :typed_overload, value)
  -> type_params=(value)
    ast_set(self, :type_params, value)
  -> type_constraints=(value)
    ast_set(self, :type_constraints, value)
  -> type_args=(value)
    ast_set(self, :type_args, value)
  -> parent_type_args=(value)
    ast_set(self, :parent_type_args, value)
  -> trait_type_args=(value)
    ast_set(self, :trait_type_args, value)
  -> from_fn=(value)
    ast_set(self, :from_fn, value)
  -> from_kwargs=(value)
    ast_set(self, :from_kwargs, value)
  -> axis_name=(value)
    ast_set(self, :axis_name, value)
  -> reuse_safe=(value)
    ast_set(self, :reuse_safe, value)
  -> recycle_safe=(value)
    ast_set(self, :recycle_safe, value)
  -> drain_safe=(value)
    ast_set(self, :drain_safe, value)
  -> stack_safe=(value)
    ast_set(self, :stack_safe, value)
  -> name=(value)
    ast_set(self, :name, value)
  -> value=(v)
    ast_set(self, :value, v)
  -> raw=(v)
    ast_set(self, :raw, v)
  -> params=(value)
    ast_set(self, :params, value)
  -> body=(value)
    ast_set(self, :body, value)
  -> expressions=(value)
    ast_set(self, :expressions, value)
  -> type_hint=(value)
    ast_set(self, :type_hint, value)
  -> lowering_analysis=(value)
    ast_set(self, :lowering_analysis, value)
  -> calls_impure_ccall=(value)
    ast_set(self, :calls_impure_ccall, value)

  # Source location — `:loc` is a fully tagged W_PACKED_LOCATION
  # WValue in FileOffset mode: file_id + a byte-into-@chars offset
  # (see the Location class below for why line/col need a per-file
  # table to reconstruct, and why that table is keyed by codepoint
  # rather than raw bytes). Sentinel `raw == 0` still works: any
  # tagged Location has bit 49 set and is non-zero. Until a kind's
  # schema carries a `:loc` slot, ast_get falls through to the sparse
  # store and yields nil, so these are safe to call on every kind.
  -> loc
    raw = ast_get(self, :loc)
    if raw == nil
      return nil
    if raw == 0
      return nil
    raw

  -> line
    location_line(ast_get(self, :loc))

  -> col
    location_col(ast_get(self, :loc))

  # End-of-span accessors (AST task #9). `:loc_end` is a second
  # packed W_PACKED_LOCATION carrying the *exclusive* end position
  # of this node's source range. Same encoding as `:loc`; absent /
  # zero means "no end recorded" and span_length falls back to 1.
  -> loc_end
    raw = ast_get(self, :loc_end)
    if raw == nil
      return nil
    if raw == 0
      return nil
    raw

  -> end_line
    location_line(ast_get(self, :loc_end))

  -> end_col
    location_col(ast_get(self, :loc_end))

  # Caret-underline width for error rendering. Returns 1 when no
  # end_loc is recorded or when the span crosses lines — the caret
  # always points at the start; multi-line ranges aren't underlined.
  -> span_length
    sl = line
    if sl == nil
      return 1
    el = end_line
    if el == nil
      return 1
    if sl != el
      return 1
    sc = col
    ec = end_col
    if ec <= sc
      return 1
    ec - sc

  -> amount
    ast_get(self, :amount)
  -> args
    ast_get(self, :args)
  -> arms
    ast_get(self, :arms)
  -> attribute
    ast_get(self, :attribute)
  -> bindings
    ast_get(self, :bindings)
  -> block
    ast_get(self, :block)
  -> block_param
    ast_get(self, :block_param)
  -> body
    ast_get(self, :body)
  -> capabilities
    ast_get(self, :capabilities)
  -> cidr
    ast_get(self, :cidr)
  -> class_role
    ast_get(self, :class_role)
  -> condition
    ast_get(self, :condition)
  -> conditions
    ast_get(self, :conditions)
  -> count
    ast_get(self, :count)
  -> declarations
    ast_get(self, :declarations)
  -> default
    ast_get(self, :default)
  -> directives
    ast_get(self, :directives)
  -> element_type
    ast_get(self, :element_type)
  -> elements
    ast_get(self, :elements)
  -> else_body
    ast_get(self, :else_body)
  -> elsif_clauses
    ast_get(self, :elsif_clauses)
  -> encoding
    ast_get(self, :encoding)
  -> ensure_body
    ast_get(self, :ensure_body)
  -> entries
    ast_get(self, :entries)
  -> exclusive
    ast_get(self, :exclusive)
  -> expression
    ast_get(self, :expression)
  -> expressions
    ast_get(self, :expressions)
  -> fallback
    ast_get(self, :fallback)
  -> field
    ast_get(self, :field)
  -> field_type
    ast_get(self, :field_type)
  -> format
    ast_get(self, :format)
  -> from
    ast_get(self, :from)
  # `func` is the per-element function of pipeline Map nodes (KIND_MAP slot
  # 1). Without an explicit accessor, `node.func` resolves through dynamic
  # dispatch, which found the schema field under the C VM but NOT under the
  # compiled compiler — the autoload walker then saw pipeline-stage calls
  # (`/sq`) on one host only.
  -> func
    ast_get(self, :func)
  -> guard
    ast_get(self, :guard)
  -> index
    ast_get(self, :index)
  -> is_class_method
    ast_get(self, :is_class_method)
  -> ivar_assign
    ast_get(self, :ivar_assign)
  -> kernel
    ast_get(self, :kernel)
  -> keyword
    ast_get(self, :keyword)
  -> left
    ast_get(self, :left)
  -> lhs
    ast_get(self, :lhs)
  -> lib_name
    ast_get(self, :lib_name)
  -> name
    ast_get(self, :name)
  -> namespace
    ast_get(self, :namespace)
  -> number_str
    ast_get(self, :number_str)
  -> op
    ast_get(self, :op)
  -> operand
    ast_get(self, :operand)
  -> options
    ast_get(self, :options)
  -> param_types
    ast_get(self, :param_types)
  -> typed_overload
    ast_get(self, :typed_overload)
  -> params
    ast_get(self, :params)
  -> parts
    ast_get(self, :parts)
  -> path
    ast_get(self, :path)
  -> pattern
    ast_get(self, :pattern)
  -> predicate
    ast_get(self, :predicate)
  -> prefix
    ast_get(self, :prefix)
  -> raw
    ast_get(self, :raw)
  -> receiver
    ast_get(self, :receiver)
  -> regex
    ast_get(self, :regex)
  -> rescue_body
    ast_get(self, :rescue_body)
  -> rescue_var
    ast_get(self, :rescue_var)
  -> return_type
    ast_get(self, :return_type)
  -> rgba
    ast_get(self, :rgba)
  -> right
    ast_get(self, :right)
  -> size
    ast_get(self, :size)
  -> source
    ast_get(self, :source)
  -> splat
    ast_get(self, :splat)
  -> subject
    ast_get(self, :subject)
  -> suffix
    ast_get(self, :suffix)
  -> superclass
    ast_get(self, :superclass)
  -> symbols
    ast_get(self, :symbols)
  -> target
    ast_get(self, :target)
  -> targets
    ast_get(self, :targets)
  -> then_body
    ast_get(self, :then_body)
  -> to
    ast_get(self, :to)
  -> type_hint
    ast_get(self, :type_hint)
  -> type_hints
    ast_get(self, :type_hints)
  -> unit
    ast_get(self, :unit)
  -> value
    ast_get(self, :value)
  -> values
    ast_get(self, :values)
  -> variant
    ast_get(self, :variant)
  -> view_name
    ast_get(self, :view_name)
  -> whens
    ast_get(self, :whens)
  -> words
    ast_get(self, :words)

  -> method_missing(name)
    ast_get(self, name)

  -> method_missing_set(name, value)
    ast_set(self, name, value)

# -- AST node accessors --
#
# Polymorphic over two argument shapes:
#
#   1. A bare W_PACKED_NODE WValue — every ast_X constructor returns
#      one. Goes through slab_offset_for to a real slab slot, else
#      falls through to the C-side sparse store (w_ast_sparse_*).
#
#   2. A plain hash — most importantly lowering's `typed_value`
#      `{type:, value:}` (see pass_registry.w:140), which
#      lower_expression returns and downstream lowering reads/writes
#      through these accessors. Also: ivars_decl entries
#      `{name:, type:}` and similar small data records.
#
# The Hash branch in each accessor is load-bearing for case 2 —
# removing it (verified) breaks all of lowering. ast_kind on a
# non-`:node` hash returns nil, which callers use as the "not an
# AST node" discriminator.

# Sparse-field side-table (PR #3). Fields that aren't in
# slab_offset_table_data — :reuse_safe/:from_kwargs on hash_literal,
# :axis_name on assign, :loc/:loc_end on literal kinds without loc
# slots — live in a C-side store (runtime/runtime.c for compiled
# stages, implementations/c/src/node_arena.c for the stage-0 C VM):
# an open-addressed map from W_PACKED_NODE bits to a chain of
# (symbol, value) records. Both the node and the field symbol are
# opaque interned i64 keys, so a lookup is one hash probe + a short
# chain scan — no Tungsten Hash-of-Hashes allocation per node.
#
# Why a side-table and not extra slab slots: walk-time cache locality.
# Tree-walks pull adjacent slab bytes into L1; padding every node
# with mostly-empty sparse slots would push more bytes per node into
# the cache than the hot fields need. The side-table keeps the slab
# tight (4-8 useful slots/node) and pays the probe only when a sparse
# field is actually accessed.

-> ast_node_key(node)
  # Pre-flip this returned node[:_slab]; constructors no longer wrap,
  # so the W_PACKED_NODE itself IS the key. Plain hash literals (parser
  # tokens, error records, hash-style AST node literals in lowering.w)
  # return themselves — callers use this as a stable identity for
  # sparse-meta side-table keys.
  node

-> ast_get(node, sym)
  if node == nil
    return nil
  # Slab W_PACKED_NODE fast path first (the common case): one w_is_node tag
  # compare, versus __w_type's ~30 sequential tag tests that the old
  # `type(node) == "Hash"` guard ran on every slab access.
  if ccall_nobox("w_is_node_extern", node) == 1
    # Bare W_PACKED_NODE WValue path. Slab field via schema if mapped;
    # sparse via side-table otherwise. Use the raw kind id (not the kind
    # symbol) so slab_offset_for_id skips the symbol round-trip and the
    # type()=="Symbol" probe -- this is the hottest field-access path.
    kid = ccall_nobox("w_node_kind_extern", node)
    offset = slab_offset_for_id(kid, sym)
    if offset != nil
      # OFFSET_INLINE = 256 sentinel: int payload lives in the W_PACKED_
      # NODE's offset bits. OFFSET_INTERN = 257: offset bits hold a dense
      # id into the C-side string-intern table.
      if offset == 256
        return ccall_nobox("w_node_offset_extern", node)
      if offset == 257
        return ccall_nobox("w_ast_intern_str_of", node)
      return ccall_nobox("w_node_field_load", node, offset)
    # C-side sparse store; returns W_NIL (0) for absent, which IS nil.
    return ccall_nobox("w_ast_sparse_get", node, sym)
  if type(node) == "Hash"
    # Plain hash path: parser tokens, error records, and the small
    # number of hand-built hash AST node literals in lowering.w
    # (`ast_var(...)` etc. — they don't carry a :_slab
    # wrapper and aren't bumped through the slab arenas).
    return node[sym]
  # Non-node, non-hash: not an AST node, so no field to read. (The old code
  # fell into the slab branch here, where ast_kind returned nil and the
  # function returned nil anyway — same result, without the wasted probe.)
  nil

-> ast_set(node, sym, value)
  if node == nil
    return nil
  # Slab W_PACKED_NODE fast path first (see ast_kind): one w_is_node tag
  # compare instead of __w_type's ~30 tag tests behind `type == "Hash"`.
  if ccall_nobox("w_is_node_extern", node) == 1
    # Bare W_PACKED_NODE WValue path. Schema-mapped → slab slot; else
    # sparse-meta side-table (lazy-init inner hash on first write so
    # empty nodes don't consume any side-table storage). Raw kind id skips
    # the symbol round-trip (see ast_get).
    kid = ccall_nobox("w_node_kind_extern", node)
    offset = slab_offset_for_id(kid, sym)
    if offset != nil
      # OFFSET_INLINE (256) / OFFSET_INTERN (257) mean the field lives
      # in the offset bits. ast_set on these kinds is a no-op — the
      # value is part of the W_PACKED_NODE identity, not a mutable
      # field. Constructors (ast_char, Var.new, …) bake it in at
      # creation; a rename means constructing a replacement node.
      if offset < 256
        ccall_nobox("w_node_field_store", node, offset, value)
    else
      ccall_nobox("w_ast_sparse_set", node, sym, value)
    return value
  if type(node) == "Hash"
    node[sym] = value
    return value
  value

-> ast_kind(node)
  if node == nil
    return nil
  # Cheap W_PACKED_NODE tag check first — the overwhelmingly common node
  # shape. The old `type(node) == "Hash"` guard ran __w_type's ~30
  # sequential tag tests on every slab node just to rule out Hash; a single
  # w_is_node tag compare replaces them. ast_get/ast_set do the same, and
  # this helper is called all over lowering/emitter, so the saving compounds.
  if ccall_nobox("w_is_node_extern", node) == 1
    # Bare W_PACKED_NODE WValue path. Fused extract + table lookup in C
    # avoids: (a) the w_int boxing call between w_node_kind_extern's
    # raw-int result and kind_sym_for_id's boxed param, and (b) the
    # kind_sym_for_id function-call boundary itself. `w_int` is an
    # extern (non-static-inline) function, so even -O3 -flto leaves it
    # as a real `bl _w_int` instruction in the compiled binary.
    return ccall("w_node_kind_sym", node, kind_sym_table_data)
  # Plain hash path: hand-built `{node: :foo, …}` literals in lowering.
  if type(node) == "Hash"
    return node[:node]
  # Non-node, non-hash: preserve the historical fallthrough exactly.
  ccall("w_node_kind_sym", node, kind_sym_table_data)

# AST task #5 — shallow-body accessors. Return the raw body/expressions
# Array from a Block/Program slab slot directly. Saves the kind-symbol
# extract + slab_offset_for table lookup that ast_get(node, :body)
# would do — the slot index is hardcoded from the schema. Caller MUST
# know the node kind (no validation here); use only when a preceding
# `ast_kind(x) == :block` / `== :program` check has already gated.
#
# Returns the underlying WArray verbatim — no copy, no filter.
# Iteration via `.each` then walks just the body, skipping the per-
# call out=[] alloc + per-field schema probe that ast_children does.
#
# The Hash branch handles the few intermediate AST representations
# (cache deserialization, hand-built hash nodes in lowering) that
# still pass through these accessors — without it, slot-direct load
# crashes on a non-W_PACKED_NODE WValue.
#
# Schema offsets (cross-check against ast_schema.w if changing):
#   KIND_BLOCK   => {:params => 0, :body => 1, :loc => 2}
#   KIND_PROGRAM => {:expressions => 0}
-> block_body(node)
  if type(node) == "Hash"
    return node[:body]
  ccall_nobox("w_node_field_load", node, 1)

-> program_body(node)
  if type(node) == "Hash"
    return node[:expressions]
  ccall_nobox("w_node_field_load", node, 0)

# AST task #4 — per-kind children iterators (first pass).
# Hand-coded fast paths for the two hottest kinds; the generic walker
# below stays as the fallback for every other kind. Each fast path
# skips the slab_keys_table[kid] lookup + per-field schema probe +
# per-field is_ast_node? branch that the generic walker pays.
#
# Correctness invariant: for any node N, the fast path must produce
# the *same* Array (same elements, same order) the generic walker
# would. Byte-identity catches regressions arm-by-arm.
#
# When this expands, the generator should emit one of these per
# kind (~104 total). For now: prove the dispatch + measure before
# committing to the full set.
-> ast_children_program(node)
  out = []
  exprs = program_body(node)
  if exprs != nil
    j = 0
    while j < exprs.size()
      elt = exprs[j]
      if is_ast_node?(elt)
        out.push(elt)
      j += 1
  out

-> ast_children_block(node)
  out = []
  # Block schema: {:params => 0, :body => 1, :loc => 2}. :loc is w64
  # (packed location WValue), never an AST node — skip it. :params
  # and :body are both Array<AST>.
  params = ast_get(node, :params)
  if params != nil && type(params) == "Array"
    j = 0
    while j < params.size()
      elt = params[j]
      if is_ast_node?(elt)
        out.push(elt)
      j += 1
  body = block_body(node)
  if body != nil && type(body) == "Array"
    j = 0
    while j < body.size()
      elt = body[j]
      if is_ast_node?(elt)
        out.push(elt)
      j += 1
  out

# Collect every AST child of `node` into an array.
# Replaces the `keys = node.keys(); each → recurse(node[k])` pattern
# used in metal_emitter rewriters and lowering walkers — that pattern
# can't survive the hash drop because a bare W_PACKED_NODE WValue has
# no keys() method.
#
# For single AST-node-valued fields (target, receiver, condition, …)
# the child is added once. For Array-valued fields (body, args,
# elements, …) each AST element of the array is added. Sparse fields
# carry primitives and aren't traversed.
-> ast_children(node)
  out = []
  if node == nil
    return out
  k = ast_kind(node)
  if k == nil
    return out
  # AST task #4: fast paths for the hottest kinds. The generic walker
  # below is kept as fallback + correctness oracle.
  # Leaf-kind fast returns: kinds whose only ivar is a w64 payload
  # (no AST children) short-circuit to [] directly, skipping
  # kind_id_table + slab_keys_table + per-field ast_get +
  # per-field is_ast_node?.
  #   :var    — 32,891 allocations per compiler self-compile (24%)
  #   :symbol —  7,838 allocations (5.7%)
  # Together these cover ~30% of nodes. Both are genuine leaves —
  # @name (for var) and @value (for symbol) hold string WValues,
  # never AST nodes.
  if k == :var
    return []
  if k == :symbol
    return []
  if k == :program
    return ast_children_program(node)
  if k == :block
    return ast_children_block(node)
  kid = kind_id_table[k]
  if kid == nil
    return out
  # Pre-computed per-kind keys array (fix #6 in ast.w). schema.keys()
  # used to allocate a fresh Array on every call; now it's a single
  # array lookup by kind_id.
  keys = slab_keys_table[kid]
  if keys == nil
    return out
  i = 0
  while i < keys.size()
    v = ast_get(node, keys[i])
    if v != nil
      if is_ast_node?(v)
        out.push(v)
      elsif type(v) == "Array"
        j = 0
        while j < v.size()
          elt = v[j]
          if is_ast_node?(elt)
            out.push(elt)
          j += 1
    i += 1
  out

# Render a slab AST node as an indented tree for `--ast`. Each node prints
# its kind plus inline `key=value` scalar fields on one line, then recurses
# into AST-node and Array-of-node fields beneath it. `:loc`/`:loc_end` are
# omitted to keep the dump readable. Generic over every kind via the same
# kind_id_table / slab_keys_table the lowering walkers use, so new AST kinds
# print without bespoke cases. `pad` is the running indent string.
-> ast_scalar_repr(v)
  if type(v) == "String"
    return "\"" + v + "\""
  v.to_s()

-> ast_to_tree(node, pad)
  if node == nil
    return pad + "nil\n"
  if !is_ast_node?(node)
    return pad + ast_scalar_repr(node) + "\n"
  k = ast_kind(node)
  line = pad + k.to_s()
  kid = kind_id_table[k]
  keys = nil
  if kid != nil
    keys = slab_keys_table[kid]
  rest = ""
  child_pad = pad + "  "
  grand_pad = child_pad + "  "
  if keys != nil
    # Pass 1: inline scalar fields onto the kind line.
    i = 0
    while i < keys.size()
      key = keys[i]
      if key != :loc && key != :loc_end
        v = ast_get(node, key)
        if v != nil && !is_ast_node?(v) && type(v) != "Array"
          line = line + " " + key.to_s() + "=" + ast_scalar_repr(v)
      i += 1
    # Pass 2: structural fields (single nodes and node arrays) below.
    i = 0
    while i < keys.size()
      key = keys[i]
      if key != :loc && key != :loc_end
        v = ast_get(node, key)
        if is_ast_node?(v)
          rest = rest + child_pad + key.to_s() + ":\n" + ast_to_tree(v, grand_pad)
        elsif type(v) == "Array" && v.size() > 0
          rest = rest + child_pad + key.to_s() + ":\n"
          j = 0
          while j < v.size()
            rest = rest + ast_to_tree(v[j], grand_pad)
            j += 1
      i += 1
  line + "\n" + rest

# Collect every Array-valued field of `node` (the Array itself, not
# its elements). Used by AST rewriters that descend into bodies/
# then_body/else_body looking for nested loops — they need the Array
# to drive their own per-statement iteration.
-> ast_array_fields(node)
  out = []
  if node == nil
    return out
  k = ast_kind(node)
  if k == nil
    return out
  kid = kind_id_table[k]
  if kid == nil
    return out
  keys = slab_keys_table[kid]
  if keys == nil
    return out
  i = 0
  while i < keys.size()
    v = ast_get(node, keys[i])
    if v != nil && type(v) == "Array"
      out.push(v)
    i += 1
  out

# Predicate: is `x` an AST node?
#   - W_PACKED_NODE WValue (i64)     — every ast_X constructor returns one
#   - Hash with :node                — hand-built hash literals in lowering.w
# Returns false for tokens, error records, typed-value hashes, plain
# ints, strings, arrays — anything that isn't an AST node.
-> is_ast_node?(x)
  # Single C call handles nil + W_PACKED_NODE tag check + Hash :node
  # lookup. Hot path (W_PACKED_NODE) is 4 instructions in C; the
  # Tungsten function call boundary is the dominant cost otherwise.
  ccall_nobox("w_is_ast_node_full", x, :node) == 1

# -- Deep clone --
# Phase 5: monomorphization clones a method-def AST so the body can be
# re-lowered under a child context with a re-typed `__self`. Sharing policy:
# - Hash and Array nodes are recursively copied (so child mutations of
#   ctx[:var_types] etc. don't bleed back into the original).
# - Primitives (int, string, symbol, bool, nil, float) are immutable values
#   in Tungsten and are returned as-is — no copy needed.
# - W_PACKED_NODE WValues clone by allocating a fresh slab node of the
#   same (kind, sc), copying each schema slot (recursively deep-cloning
#   AST sub-trees), and copying the sparse-meta side-table entry.
-> ast_deep_clone(node)
  if node == nil
    return nil
  t = type(node)
  if t == "Hash"
    out = {}
    node.keys().each -> (k)
      out[k] = ast_deep_clone(node[k])
    return out
  if t == "Array"
    out = []
    node.each -> (elt)
      out.push(ast_deep_clone(elt))
    return out
  if is_ast_node?(node)
    # Bare W_PACKED_NODE branch. Allocate a new slab node, deep-copy
    # each scheme slot, then copy sparse-meta entries verbatim
    # (sparse values are line/col ints / marker bools — no AST in there).
    k = ast_kind(node)
    kid = kind_id_table[k]
    if kid == nil
      return node
    # Inline-payload kinds (KIND_PARG / KIND_CHAR / KIND_CODEPOINT /
    # KIND_REGEX_CAPTURE / KIND_LAMBDA_ARITY / KIND_SUPERSCRIPT /
    # KIND_DATE / KIND_TIME / KIND_MONTH / KIND_IP4 / KIND_COLOR …) and
    # the interned leaf kinds (KIND_VAR / KIND_IVAR / KIND_CVAR /
    # KIND_SYMBOL / KIND_STRING, sentinel 257) store their value in the
    # W_PACKED_NODE's offset bits, not in slab slots — the WValue itself
    # is immutable and self-describing. Cloning by allocating a fresh
    # slab node and walking slot 0 (which doesn't exist for inline
    # payloads) reads garbage and corrupts the clone. Return the
    # original WValue directly — every consumer treats inline node
    # values as immutable.
    sks_first = slab_keys_table[kid]
    if sks_first != nil && sks_first.size() > 0
      first_off = slab_offset_for(k, sks_first[0])
      if first_off != nil && first_off >= 256
        return node
    sc = sc_for_kind(kid)
    new_node = ccall_nobox("w_node_alloc", kid, sc)
    sk = slab_keys_table[kid]
    if sk != nil
      # Slot indices map directly to schema-key positions (the
      # schema literal in ast_schema.w is written in slot order
      # `{:field => 0, :other => 1, ...}`). Skip ast_get/ast_set's
      # nil/type/kind/sparse-meta machinery — we know node is a
      # bare W_PACKED_NODE and the field is in the schema.
      n_slots = sk.size()
      i = 0
      while i < n_slots
        v = ccall_nobox("w_node_field_load", node, i)
        ccall_nobox("w_node_field_store", new_node, i, ast_deep_clone(v))
        i += 1
    ccall_nobox("w_ast_sparse_copy", node, new_node)
    return new_node
  # Primitives (String, Symbol, Integer, Float, Boolean, …) are
  # immutable WValues — return as-is. Without this fall-through,
  # ast_deep_clone of a method-def slot-0 name string returned nil
  # and any cloned class lost its method names downstream.
  node

# Source-location view over a W_PACKED_LOCATION WValue (AST task #1).
# `:loc` holds a fully tagged WValue — W_TAG_PACKED, subtype 7, and a
# 2-bit mode (wvalue.h). Locations are constructed exclusively in
# FileOffset mode now (file_id + a byte-into-@chars offset, matching
# the lexer's own codepoint indexing — see build_line_index in
# lexer.w and the comment below): the 18-bit line / 11-bit column
# fields File mode packs directly can silently truncate on generated
# or minified sources, while a 29-bit offset covers any realistic
# file. `Location` is a read-only view, constructed on demand as
# `Location.new(node.loc)`. `@packed == 0` is the no-location sentinel
# (any valid tagged Location has bit 49 set and so is non-zero).
#
# AST task #9: an optional second packed value carries the *end*
# position of the source range. `Location.new(start_packed,
# end_packed)` builds a span; `Location.new(start_packed)` carries
# no end (end_packed defaults to 0).
#
# Line/col reconstruction: a FileOffset location only carries a byte
# offset, so recovering line/col needs a per-file lookup table. Rather
# than re-scanning the source (which would also have to re-derive the
# lexer's own codepoint indexing to agree with the offset space
# tok_off works in — @chars is a codepoint array, NOT @source's raw
# bytes, so a naive byte-offset rescan would misalign on any file
# using multi-byte characters, e.g. this compiler's own Σ/Δ/√ math
# notation), the parser registers its lexer's already-computed
# @line_at/@col_at tables (one entry per codepoint, built once during
# lexing) here, keyed by a small file_id assigned on first use. Node#line
# etc. below look up into these directly — an O(1) array read, not a
# rescan or binary search. Tables persist for the process's lifetime
# (compiles are one-shot), so nodes from a file remain resolvable
# throughout lowering, long after that file's Lexer/Parser instances
# have gone out of scope.
#
# The registry itself lives in runtime.c (w_loc_register_file /
# w_loc_line_for_offset / w_loc_col_for_offset), as a real C global —
# not a Tungsten-level Hash. That's not stylistic: a Tungsten bare
# top-level assignment turned out to be unreliable for this specific
# shape of state. Assigning to a name from inside a function body only
# mutates a *global* if that name's initial value was already
# established by top-level code guaranteed to have already run — and
# for ast.w (used from four separate files, and reached very early via
# Parser.new, before any library's own top-level statements are
# guaranteed to have executed) that guarantee doesn't hold, regardless
# of which file the top-level assignment was moved to. Symptom before
# this was found: every parsed file silently registered under
# file_id 1, and the line/col tables read back nil everywhere except
# the one call frame that had just set them locally. A real C global
# has no such ambiguity.
-> register_file_tables(path, line_at, col_at)
  ccall_nobox("w_loc_register_file", path, line_at, col_at)

-> line_for_offset(file_id, offset)
  if file_id == nil || offset == nil
    return nil
  ccall_nobox("w_loc_line_for_offset", file_id, offset)

-> col_for_offset(file_id, offset)
  if file_id == nil || offset == nil
    return nil
  ccall_nobox("w_loc_col_for_offset", file_id, offset)

# raw: a tagged W_PACKED_LOCATION WValue (FileOffset mode) or nil/0.
-> location_line(raw)
  if raw == nil || raw == 0
    return nil
  line_for_offset(ccall_nobox("w_unbox_location_file_id_extern", raw),
                   ccall_nobox("w_unbox_location_offset_extern", raw))

-> location_col(raw)
  if raw == nil || raw == 0
    return nil
  col_for_offset(ccall_nobox("w_unbox_location_file_id_extern", raw),
                 ccall_nobox("w_unbox_location_offset_extern", raw))

+ Location
  -> new(packed, packed_end = 0)
    @packed = packed
    @packed_end = packed_end

  -> file_id
    if @packed == 0
      return nil
    ccall_nobox("w_unbox_location_file_id_extern", @packed)

  -> line
    location_line(@packed)

  -> col
    location_col(@packed)

  -> end_line
    location_line(@packed_end)

  -> end_col
    location_col(@packed_end)

  -> span_length
    sl = line
    if sl == nil
      return 1
    el = end_line
    if el == nil
      return 1
    if sl != el
      return 1
    sc = col
    ec = end_col
    if ec <= sc
      return 1
    ec - sc

  -> to_s
    if @packed == 0
      return "<no location>"
    "L#{line}:#{col}"

# Slab classes — the canonical, hand-maintained AST definitions. (Originally
# generated during the hash-AST → slab-AST migration; that generator is gone,
# so this section is now edited directly.)
#
# One slab class per AST kind. `.new(args)` inlines the
# slab_alloc_init / singleton / inline-payload body directly; no
# `ast_X` indirection. Instances are W_PACKED_NODE WValues —
# the C VM's `[slab]` role on .new dispatch (implementations/c
# commit 012f57e9) returns the body's value without wrapping in
# a TcRuntimeObject.
#
# `in Tungsten:AST` (in the hand-written head above) puts every
# class declaration below into the `Tungsten:AST:` namespace, so
# a bare `+ Program < Node` resolves to
# `+ Tungsten:AST:Program < Tungsten:AST:Node`. External callers
# use the qualified path (`Tungsten:AST:Program.new(...)`).
#
# AST:Node#method_missing replaces what used to be ~100 explicit
# `-> field; ast_get(self, :field)` accessors. Method dispatch
# on any W_PACKED_NODE routes here via dispatch_key 0xE3; the
# method-missing fallback in vm_call_body.inc forwards the
# method name (as a symbol) + args.
#
# The `in AST` directive at the top of the hand-written head
# section above already covers all declarations in this file.

# -- File (per-file root) --

+ File < Node [slab]
  - ivars
    @path  w64
    @source w64
    @body  ast

  -> .new(path, source, body)
    slab_alloc_init(KIND_FILE, SC_4, path, source, body)

# -- Program --

+ Program < Node [slab]
  - ivars
    @expressions ast

  -> .new(expressions)
    slab_alloc_init(KIND_PROGRAM, SC_2, expressions)

# -- Literals --

+ Int < Node [slab]
  - ivars
    @value w64
    @format w64
    @raw   w64

  -> .new(value, format = nil, raw = nil)
    slab_alloc_init(KIND_INT, SC_4, value, format, raw)

+ Wvalue < Node [slab]
  - ivars
    @value w64
    @raw  w64

  -> .new(value, raw = nil)
    slab_alloc_init(KIND_WVALUE, SC_2, value, raw)

+ Float < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_FLOAT, SC_2, value)

+ Decimal < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_DECIMAL, SC_2, value)

+ TypedArrayNew < Node [slab]
  - ivars
    @element_type w64
    @size        ast

  -> .new(element_type, size_expr)
    slab_alloc_init(KIND_TYPED_ARRAY_NEW, SC_2, element_type, size_expr)

+ String < Node [slab]
  - ivars
    @value w64

  # Interned inline kind (schema sentinel 257): the string content is
  # interned C-side and the dense id lives in the handle's offset bits.
  # No arena allocation; ~7.8K string literals per self-compile dedup
  # to their distinct contents.
  -> .new(value)
    ccall_nobox("w_ast_intern_node", KIND_STRING, value)

+ StringInterp < Node [slab]
  - ivars
    @parts ast

  -> .new(parts)
    slab_alloc_init(KIND_STRING_INTERP, SC_2, parts)

+ Regex < Node [slab]
  - ivars
    @pattern w64
    @options w64

  -> .new(pattern, options = "")
    slab_alloc_init(KIND_REGEX, SC_2, pattern, options)

+ RegexCapture < Node [slab]
  - ivars
    @index inline(32)

  -> .new(index)
    ccall_nobox("w_node_inline_payload", KIND_REGEX_CAPTURE, index)

+ Bool < Node [slab]
  -> .new(value)
    if value
      ccall_nobox("w_ast_bool_cached", 1)
    else
      ccall_nobox("w_ast_bool_cached", 0)

+ Nil < Node [slab]
  -> .new
    # Tag-only kind: schema is `{}`, all instances are interchangeable.
    # w_node_singleton encodes the W_PACKED_NODE bit pattern with sc=0
    # and offset=0 (reserved arena slot). No arena bump. With LTO,
    # clang inlines the helper into a single `or i64 KIND_BITS,
    # W_TAG_PACKED_BITS` and folds it through ast_nil's callers.
    ccall_nobox("w_node_singleton", KIND_NIL_LIT)

+ Symbol < Node [slab]
  - ivars
    @value w64

  # Interned inline kind (schema sentinel 257) — see String.
  -> .new(value)
    ccall_nobox("w_ast_intern_node", KIND_SYMBOL, value)

+ MagicConstant < Node [slab]
  - ivars
    @name   w64
    @loc    w64
    @loc_end w64

  -> .new(name, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_MAGIC_CONSTANT, SC_4, name, loc, loc_end)

+ Array < Node [slab]
  - ivars
    @elements ast

  -> .new(elements)
    slab_alloc_init(KIND_ARRAY, SC_2, elements)

+ ScheduleDef < Node [slab]
  - ivars
    @kernel    w64
    @variant   w64
    @directives ast
    @loc       w64
    @loc_end   w64

  -> .new(kernel_name, variant_name, directives, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_SCHEDULE_DEF, SC_8, kernel_name, variant_name, directives, loc, loc_end)

+ LayoutDef < Node [slab]
  - ivars
    @kernel    w64
    @variant   w64
    @directives ast
    @loc       w64
    @loc_end   w64

  -> .new(kernel_name, variant_name, directives, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_LAYOUT_DEF, SC_8, kernel_name, variant_name, directives, loc, loc_end)

+ HashLiteral < Node [slab]
  - ivars
    @entries ast

  -> .new(entries)
    slab_alloc_init(KIND_HASH_LITERAL, SC_2, entries)

+ ByteArray < Node [slab]
  - ivars
    @values ast

  -> .new(values)
    slab_alloc_init(KIND_BYTE_ARRAY, SC_2, values)

+ ByteArrayInterp < Node [slab]
  - ivars
    @parts ast

  -> .new(parts)
    slab_alloc_init(KIND_BYTE_ARRAY_INTERP, SC_2, parts)

+ Currency < Node [slab]
  - ivars
    @amount w64
    @prefix w64
    @suffix w64

  -> .new(amount, prefix, suffix)
    slab_alloc_init(KIND_CURRENCY, SC_4, amount, prefix, suffix)

+ Quantity < Node [slab]
  - ivars
    @number_str w64
    @unit      w64

  -> .new(number_str, unit)
    slab_alloc_init(KIND_QUANTITY, SC_2, number_str, unit)

+ Duration < Node [slab]
  - ivars
    @raw w64

  -> .new(raw)
    slab_alloc_init(KIND_DURATION, SC_2, raw)

+ Uuid < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_UUID, SC_2, value)

+ Date < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    # Store the literal text in a slab slot (like Datetime). The inline
    # "days-since-epoch" encoding was never wired: the parser passes the raw
    # date STRING here, so w_node_inline_payload truncated its slab reference
    # and neither lower_date nor the interpreter could read it back — dates
    # failed everywhere. Slab storage keeps :value a real string both paths read.
    slab_alloc_init(KIND_DATE, SC_2, value)

+ Datetime < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_DATETIME, SC_2, value)

+ Time < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    # Slab-stored string (see Date above — the inline encoding was never wired).
    slab_alloc_init(KIND_TIME, SC_2, value)

+ Month < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    # Slab-stored string (see Date above — the inline encoding was never wired).
    slab_alloc_init(KIND_MONTH, SC_2, value)

+ Ip4 < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    # Slab-stored string (like Cidr4/Date) — the inline encoding truncated the
    # "a.b.c.d" literal; lower_ipv4 / the interpreter parse node.value.
    slab_alloc_init(KIND_IP4, SC_2, value)

+ Cidr4 < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_CIDR4, SC_2, value)

+ Ip6 < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    # Slab-stored string (like Ip4/Cidr4) — lower_ipv6 / the interpreter
    # parse node.value ("::1", "2001:db8::1", …) via the runtime.
    slab_alloc_init(KIND_IP6, SC_2, value)

+ Cidr6 < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_CIDR6, SC_2, value)

+ Rational < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_RATIONAL, SC_2, value)

+ Char < Node [slab]
  - ivars
    @value inline(21)

  -> .new(value)
    # Inline-encoded: codepoint (21 bits) in W_PACKED_NODE offset bits.
    # No arena bump. ast_get for :value recovers via w_node_offset_extern.
    ccall_nobox("w_node_inline_payload", KIND_CHAR, value)

+ Codepoint < Node [slab]
  - ivars
    @value inline(21)

  -> .new(value)
    # Inline-encoded: Unicode codepoint (≤ 21 bits) in W_PACKED_NODE
    # offset bits. No arena bump. ast_get for :value recovers via
    # w_node_offset_extern (same path as :char).
    ccall_nobox("w_node_inline_payload", KIND_CODEPOINT, value)

+ Key < Node [slab]
  - ivars
    @value w64

  -> .new(value)
    slab_alloc_init(KIND_KEY, SC_2, value)

+ WordArray < Node [slab]
  - ivars
    @words ast

  -> .new(words)
    slab_alloc_init(KIND_WORD_ARRAY, SC_2, words)

+ SymbolArray < Node [slab]
  - ivars
    @symbols ast

  -> .new(symbols)
    slab_alloc_init(KIND_SYMBOL_ARRAY, SC_2, symbols)

+ MapOp < Node [slab]
  - ivars
    @name w64

  -> .new(name)
    slab_alloc_init(KIND_MAP_OP, SC_2, name)

# Fused-pipeline stage node. `source` is the upstream collection (or a
# nested Map); `func` is the per-element function (a Calc for known scalar
# ops, else a Call/Block); `kind` is :map (transform), :select (keep
# where func truthy) or :reject (drop where func truthy).
+ Map < Node [slab]
  - ivars
    @source ast
    @func   ast
    @kind   w64

  -> .new(source, func, kind)
    slab_alloc_init(KIND_MAP, SC_4, source, func, kind)

# Fused-pipeline computation node. As a Map's `func` (source = nil) it is
# an elementwise op applied to the element: :sq/:cube/:sqrt/:abs/:negate/
# :recip. As a terminal wrapping a Map chain (source = the chain) it is a
# reduce (:sum/:min/:max/:product) or :detect (first matching, short-
# circuit). `type_intent` is :int/:float/:auto for op selection.
+ Calc < Node [slab]
  - ivars
    @op          w64
    @source      ast
    @type_intent w64

  -> .new(op, source, type_intent)
    slab_alloc_init(KIND_CALC, SC_4, op, source, type_intent)

+ Parg < Node [slab]
  - ivars
    @index inline(32)

  -> .new(index)
    ccall_nobox("w_node_inline_payload", KIND_PARG, index)

+ LambdaArity < Node [slab]
  - ivars
    @value inline(32)

  -> .new(value)
    ccall_nobox("w_node_inline_payload", KIND_LAMBDA_ARITY, value)

+ Superscript < Node [slab]
  - ivars
    @value inline(32)

  -> .new(value)
    ccall_nobox("w_node_inline_payload", KIND_SUPERSCRIPT, value)

+ Encoded < Node [slab]
  - ivars
    @value   w64
    @encoding w64

  -> .new(value, encoding)
    slab_alloc_init(KIND_ENCODED, SC_2, value, encoding)

+ Color < Node [slab]
  - ivars
    @rgba inline(32)

  -> .new(r, g, b, a)
    packed = (r << 24) | (g << 16) | (b << 8) | a
    ccall_nobox("w_node_inline_payload", KIND_COLOR, packed)

+ ViewDecl < Node [slab]
  - ivars
    @name w64
    @kind w64
    @count w64

  -> .new(name, kind, count)
    slab_alloc_init(KIND_VIEW_DECL, SC_8, name, kind, count)

+ FieldDecl < Node [slab]
  - ivars
    @name      w64
    @field_type ast

  -> .new(name, field_type)
    slab_alloc_init(KIND_FIELD_DECL, SC_2, name, field_type)

+ ViewAccess < Node [slab]
  - ivars
    @view_name ast
    @index    w64

  -> .new(name, index)
    slab_alloc_init(KIND_VIEW_ACCESS, SC_8, name, index)

+ ViewField < Node [slab]
  - ivars
    @field w64

  -> .new(field)
    slab_alloc_init(KIND_VIEW_FIELD, SC_2, field)

# `var$field` — a view-decl field read against an explicit receiver, e.g.
# `arr$size`. Mirrors ViewField (which reads the implicit `__self`) but
# carries the receiver expression as a child node. Lowering resolves the
# receiver's class layout and emits the same :view_load_field op.
+ ViewFieldVar < Node [slab]
  - ivars
    @receiver ast
    @field    w64

  -> .new(receiver, field)
    slab_alloc_init(KIND_VIEW_FIELD_VAR, SC_2, receiver, field)

+ ViewBase < Node [slab]
  -> .new
    ccall_nobox("w_node_singleton", KIND_VIEW_BASE)

+ ViewValue < Node [slab]
  -> .new
    ccall_nobox("w_node_singleton", KIND_VIEW_VALUE)

# -- Variables --

+ Var < Node [slab]
  - ivars
    @name w64

  # Interned inline kind (schema sentinel 257): vars are 23% of a
  # self-compile's AST (42,728 nodes, 2,690 distinct names) — the
  # single biggest win from interning. Same-named vars share one
  # handle bit-pattern; nothing renames a Var in place (renames
  # construct a new node), and the parser attaches no :loc to vars,
  # so the sparse-table aliasing this implies is unobservable.
  -> .new(name)
    ccall_nobox("w_ast_intern_node", KIND_VAR, name)

# PascalCase identifier — a class/const reference, distinct from Var
# (a variable). The parser emits this for T_NAME tokens so downstream
# (lowering, interpreter, autoload pass) routes through class-resolution
# instead of variable lookup. Same slab shape as Var.
#
# Interned inline kind (schema sentinel 257) — see Var. A generic
# specialization's rename (`Foo<T>` -> `Foo$f64`) can no longer mutate
# :name in place (that's a no-op on an interned field, same as any
# other 257-kind); monomorphize.w's rewrite_generic_call_sites_in_node
# constructs a fresh ClassRef and the caller writes it back via
# ast_set/array-rebuild instead.
+ ClassRef < Node [slab]
  - ivars
    @name w64

  -> .new(name)
    ccall_nobox("w_ast_intern_node", KIND_CLASS_REF, name)

+ Ivar < Node [slab]
  - ivars
    @name w64

  # Interned inline kind (schema sentinel 257) — see Var.
  -> .new(name)
    ccall_nobox("w_ast_intern_node", KIND_IVAR, name)

+ Cvar < Node [slab]
  - ivars
    @name w64

  # Interned inline kind (schema sentinel 257) — see Var.
  -> .new(name)
    ccall_nobox("w_ast_intern_node", KIND_CVAR, name)

# `$name` — a global variable, distinct from Var (lexically scoped,
# barriered at fn/method boundaries — see environment.w) and Ivar
# (per-instance). Reads and writes of a GVar always resolve to one
# process-wide store, regardless of which function/method body they
# appear in: eval_gvar/eval_assign's :gvar branch in interpreter.w
# bypass Environment entirely, and lowering emits load_global/
# store_global unconditionally rather than gating on wfn[:name] ==
# "main" the way a bare :var's promotion to a real global does. The
# stored name includes the `$` sigil, matching Ivar's `@`-inclusive
# convention.
+ GVar < Node [slab]
  - ivars
    @name w64

  # Interned inline kind (schema sentinel 257) — see Var.
  -> .new(name)
    ccall_nobox("w_ast_intern_node", KIND_GVAR, name)

+ Self < Node [slab]
  -> .new
    ccall_nobox("w_node_singleton", KIND_SELF_REF)

# -- Assignment --

+ Assign < Node [slab]
  - ivars
    @target   ast
    @value    ast
    @type_hint ast

  -> .new(target, value, type_hint = nil)
    slab_alloc_init(KIND_ASSIGN, SC_4, target, value, type_hint)

+ CompoundAssign < Node [slab]
  - ivars
    @target ast
    @op    w64
    @value ast

  -> .new(target, op, value)
    slab_alloc_init(KIND_COMPOUND_ASSIGN, SC_4, target, op, value)

+ MultiAssign < Node [slab]
  - ivars
    @targets ast
    @value  ast

  -> .new(targets, value)
    slab_alloc_init(KIND_MULTI_ASSIGN, SC_2, targets, value)

# -- Operators --

+ BinaryOp < Node [slab]
  - ivars
    @left ast
    @op   w64
    @right ast

  -> .new(left, op, right)
    slab_alloc_init(KIND_BINARY_OP, SC_4, left, op, right)

+ UnaryOp < Node [slab]
  - ivars
    @op     w64
    @operand ast

  -> .new(op, operand)
    slab_alloc_init(KIND_UNARY_OP, SC_2, op, operand)

+ And < Node [slab]
  - ivars
    @left ast
    @right ast

  -> .new(left, right)
    slab_alloc_init(KIND_AND, SC_2, left, right)

+ Or < Node [slab]
  - ivars
    @left ast
    @right ast

  -> .new(left, right)
    slab_alloc_init(KIND_OR, SC_2, left, right)

+ Not < Node [slab]
  - ivars
    @operand ast

  -> .new(operand)
    slab_alloc_init(KIND_NOT, SC_2, operand)

+ InTest < Node [slab]
  - ivars
    @lhs     ast
    @elements ast

  -> .new(lhs, elements)
    slab_alloc_init(KIND_IN_TEST, SC_2, lhs, elements)

+ Passthrough < Node [slab]
  - ivars
    @expression ast
    @value     ast

  -> .new(expression, value)
    slab_alloc_init(KIND_PASSTHROUGH, SC_2, expression, value)

# -- Ranges --

+ Range < Node [slab]
  - ivars
    @from     ast
    @to       ast
    @exclusive w64

  -> .new(from, to, exclusive)
    slab_alloc_init(KIND_RANGE, SC_4, from, to, exclusive)

# -- Control Flow --

+ If < Node [slab]
  - ivars
    @condition    ast
    @then_body    ast
    @elsif_clauses ast
    @else_body    ast

  -> .new(condition, then_body, elsif_clauses = [], else_body = nil)
    slab_alloc_init(KIND_IF, SC_8, condition, then_body, elsif_clauses, else_body)

+ While < Node [slab]
  - ivars
    @condition ast
    @body     ast

  -> .new(condition, body)
    slab_alloc_init(KIND_WHILE, SC_2, condition, body)

+ With < Node [slab]
  - ivars
    @bindings ast
    @body    ast

  -> .new(bindings, body)
    slab_alloc_init(KIND_WITH, SC_2, bindings, body)

+ ParallelWith < Node [slab]
  - ivars
    @bindings ast
    @body    ast

  -> .new(bindings, body)
    slab_alloc_init(KIND_PARALLEL_WITH, SC_2, bindings, body)

+ Case < Node [slab]
  - ivars
    @whens    ast
    @else_body ast

  -> .new(whens, else_body = nil)
    slab_alloc_init(KIND_CASE, SC_2, whens, else_body)

+ When < Node [slab]
  - ivars
    @conditions ast
    @body      ast

  -> .new(conditions, body)
    slab_alloc_init(KIND_WHEN, SC_2, conditions, body)

+ CaseValue < Node [slab]
  - ivars
    @subject  ast
    @arms     ast
    @else_body ast

  -> .new(subject, arms, else_body = nil)
    slab_alloc_init(KIND_CASE_VALUE, SC_4, subject, arms, else_body)

+ CaseArm < Node [slab]
  - ivars
    @pattern ast
    @guard  ast
    @body   ast

  -> .new(pattern, guard, body)
    slab_alloc_init(KIND_CASE_ARM, SC_4, pattern, guard, body)

+ SafeNav < Node [slab]
  - ivars
    @receiver ast
    @name    w64
    @args    ast
    @block   ast
    @loc     w64
    @loc_end w64

  -> .new(receiver, name, args, block = nil, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_SAFE_NAV, SC_8, receiver, name, args, block, loc, loc_end)

+ RescueExpr < Node [slab]
  - ivars
    @body    ast
    @fallback ast

  -> .new(body, fallback)
    slab_alloc_init(KIND_RESCUE_EXPR, SC_2, body, fallback)

+ Break < Node [slab]
  -> .new
    ccall_nobox("w_node_singleton", KIND_BREAK)

+ Next < Node [slab]
  -> .new
    ccall_nobox("w_node_singleton", KIND_NEXT)

+ Return < Node [slab]
  - ivars
    @value ast

  -> .new(value = nil)
    slab_alloc_init(KIND_RETURN, SC_2, value)

# `recase [expr]` — re-run the enclosing case. @value holds the optional new
# subject expression (nil for bare `recase`). Modeled on Return.
+ Recase < Node [slab]
  - ivars
    @value ast

  -> .new(value = nil)
    slab_alloc_init(KIND_RECASE, SC_2, value)

+ ReturnNil < Node [slab]
  -> .new
    # Compact-tier singleton for bare `return` (no value). Shares the
    # :return symbol via kind_sym_table_data, so lowering treats it
    # identically to Return with a nil value — ast_get(:value) returns
    # nil for both (Return.new(nil)'s slot holds nil; the singleton
    # has no slot so the sparse fallback also returns nil).
    ccall_nobox("w_node_singleton", KIND_RETURN_NIL)

# -- Definitions --

+ TypedArray < Node [slab]
  - ivars
    @element_type w64
    @size        ast

  -> .new(element_type, size)
    slab_alloc_init(KIND_TYPED_ARRAY, SC_2, element_type, size)

+ ClassDef < Node [slab]
  - ivars
    @name      w64
    @superclass w64
    @body      ast
    @class_role w64

  -> .new(name, superclass, body, class_role)
    slab_alloc_init(KIND_CLASS_DEF, SC_8, name, superclass, body, class_role)

+ ModuleDef < Node [slab]
  - ivars
    @name w64
    @body ast

  -> .new(name, body)
    slab_alloc_init(KIND_MODULE_DEF, SC_2, name, body)

+ TraitDef < Node [slab]
  - ivars
    @name w64
    @body ast

  -> .new(name, body)
    slab_alloc_init(KIND_TRAIT_DEF, SC_2, name, body)

+ TraitInclude < Node [slab]
  - ivars
    @name w64

  -> .new(name)
    slab_alloc_init(KIND_TRAIT_INCLUDE, SC_2, name)

+ NamespaceDecl < Node [slab]
  - ivars
    @namespace w64

  -> .new(namespace)
    slab_alloc_init(KIND_NAMESPACE_DECL, SC_2, namespace)

+ IvarsDecl < Node [slab]
  - ivars
    @entries ast

  -> .new(entries)
    slab_alloc_init(KIND_IVARS_DECL, SC_2, entries)

+ MethodDef < Node [slab]
  - ivars
    @name           w64
    @params         ast
    @body           ast
    @type_hints     ast
    @is_class_method w64
    @loc            w64
    @loc_end        w64

  -> .new(name, params, body, type_hints = nil, is_class_method = false, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_METHOD_DEF, SC_8, name, params, body, type_hints, is_class_method, loc, loc_end)

+ FnDef < Node [slab]
  - ivars
    @name      w64
    @params    ast
    @body      ast
    @type_hints ast
    @loc       w64
    @loc_end   w64

  -> .new(name, params, body, type_hints = nil, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_FN_DEF, SC_8, name, params, body, type_hints, loc, loc_end)

+ GpuKernelDef < Node [slab]
  - ivars
    @name      w64
    @params    ast
    @body      ast
    @attribute ast
    @type_hints ast
    @loc       w64
    @loc_end   w64

  -> .new(name, params, body, attribute = "gpu", type_hints = nil, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_GPU_KERNEL_DEF, SC_8, name, params, body, attribute, type_hints, loc, loc_end)

+ Param < Node [slab]
  - ivars
    @name       w64
    @default    ast
    @ivar_assign w64
    @keyword    w64
    @block_param w64
    @splat      w64

  -> .new(name, default = nil, ivar_assign = false, keyword = false, block_param = false, splat = false)
    slab_alloc_init(KIND_PARAM, SC_8, name, default, ivar_assign, keyword, block_param, splat)

# -- Calls and Blocks --

+ Call < Node [slab]
  - ivars
    @receiver ast
    @name    w64
    @args    ast
    @block   ast
    @loc     w64
    @loc_end w64

  -> .new(receiver, name, args = [], block = nil, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_CALL, SC_8, receiver, name, args, block, loc, loc_end)

+ Block < Node [slab]
  - ivars
    @params ast
    @body   ast
    @loc    w64
    @loc_end w64

  -> .new(params, body, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_BLOCK, SC_4, params, body, loc, loc_end)

# -- I/O --

# `<< a, b, c` — print each argument on its own line. @value always holds a
# LIST of value-nodes (length 1 for the common `<< x`), mirroring how
# Call.@args stores a list in a single `ast` slot. Walkers that recurse into
# :puts must iterate the list (like the :call case iterates node.args).
+ Puts < Node [slab]
  - ivars
    @value ast

  -> .new(values)
    slab_alloc_init(KIND_PUTS, SC_2, values)

+ Print < Node [slab]
  - ivars
    @value ast

  -> .new(value)
    slab_alloc_init(KIND_PRINT, SC_2, value)

# -- Error Handling --

+ Raise < Node [slab]
  - ivars
    @value  ast
    @loc    w64
    @loc_end w64

  -> .new(value, loc = 0, loc_end = 0)
    slab_alloc_init(KIND_RAISE, SC_4, value, loc, loc_end)

+ Begin < Node [slab]
  - ivars
    @body       ast
    @rescue_var ast
    @rescue_body ast
    @ensure_body ast

  -> .new(body, rescue_var = nil, rescue_body = nil, ensure_body = nil)
    slab_alloc_init(KIND_BEGIN, SC_8, body, rescue_var, rescue_body, ensure_body)

# -- Module --

+ Use < Node [slab]
  - ivars
    @path w64

  -> .new(path)
    slab_alloc_init(KIND_USE, SC_2, path)

# -- Yield and Super --

+ Yield < Node [slab]
  - ivars
    @args ast

  -> .new(args = [])
    slab_alloc_init(KIND_YIELD, SC_2, args)

+ Super < Node [slab]
  - ivars
    @args ast

  -> .new(args = [])
    slab_alloc_init(KIND_SUPER, SC_2, args)

# -- FFI --

+ ExternLib < Node [slab]
  - ivars
    @lib_name    ast
    @declarations ast

  -> .new(lib_name, declarations)
    slab_alloc_init(KIND_EXTERN_LIB, SC_2, lib_name, declarations)

+ ExternFn < Node [slab]
  - ivars
    @name       w64
    @return_type w64
    @param_types w64

  -> .new(name, return_type, param_types)
    slab_alloc_init(KIND_EXTERN_FN, SC_4, name, return_type, param_types)

# -- Concurrency --

+ Go < Node [slab]
  - ivars
    @body ast

  -> .new(body)
    slab_alloc_init(KIND_GO, SC_2, body)

# -- Platform Guards --

+ TargetDesignator < Node [slab]
  - ivars
    @name w64

  -> .new(name)
    slab_alloc_init(KIND_TARGET_DESIGNATOR, SC_2, name)

+ TargetAnd < Node [slab]
  - ivars
    @left ast
    @right ast

  -> .new(left, right)
    slab_alloc_init(KIND_TARGET_AND, SC_2, left, right)

+ TargetOr < Node [slab]
  - ivars
    @left ast
    @right ast

  -> .new(left, right)
    slab_alloc_init(KIND_TARGET_OR, SC_2, left, right)

+ TargetNot < Node [slab]
  - ivars
    @expression ast

  -> .new(expression)
    slab_alloc_init(KIND_TARGET_NOT, SC_2, expression)

+ OnGuard < Node [slab]
  - ivars
    @predicate   ast
    @capabilities ast
    @body        ast

  -> .new(predicate, capabilities, body)
    slab_alloc_init(KIND_ON_GUARD, SC_4, predicate, capabilities, body)

# -- Synthetic match nodes --

+ RegexMatch < Node [slab]
  - ivars
    @regex  ast
    @subject ast

  -> .new(regex, subject)
    slab_alloc_init(KIND_REGEX_MATCH, SC_2, regex, subject)

+ CidrMatch < Node [slab]
  - ivars
    @subject ast
    @cidr   ast

  -> .new(subject, cidr)
    slab_alloc_init(KIND_CIDR_MATCH, SC_2, subject, cidr)
