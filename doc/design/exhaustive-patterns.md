# Item 11: exhaustive field patterns

Proposal, not implemented syntax. Extend `case` with an explicit closed schema
and named-field patterns. The schema owns the set of variants and field names;
ordinary open classes do not become exhaustive just because subclasses happen
to be absent from one executable.

For a small schema `Expr` with exactly `Literal(value)`, `Add(left, right)`,
and `Negate(operand)`, the complete visitor would read:

```w
-> evaluate(node)
  case node ## exhaustive(Expr)
  when Expr:Literal(value: n)
    n
  when Expr:Add(left: a, right: b)
    evaluate(a) + evaluate(b)
  when Expr:Negate(operand: x)
    -evaluate(x)
```

This removes three things compiler passes repeat today: a kind switch, manual
field lookups, and the assumption that someone remembered every new kind.
`value: n` binds `n`; `value: _` explicitly ignores it. Bindings are local to
that arm. Unmentioned fields are allowed so adding metadata does not force
changes in every visitor; misspelled field names are errors. Patterns never
invoke constructors, `===`, getters, or arbitrary user code.

For Tungsten's compiler, generate the schema from `ast_schema.w` and
`wire_instruction_schema.json`. The proposed AST arm
`when Tungsten:AST:BinaryOp(left: a, right: b, op: operator)` would lower to one
packed-kind check followed by fixed-index reads. The proposed WIRE arm
`when WIRE:AddI64(lhs: a, rhs: b)` would similarly use its generated field
ordinals. These facade names are part of the proposal, not existing APIs.

Rules:

- Every schema kind needs an unguarded arm. A guarded arm does not establish
  total coverage unless an unguarded arm for that variant follows it.
- Duplicate/unreachable unguarded arms and incompatible scrutinee/schema facts
  are errors. A dynamic scrutinee receives one checked schema membership test.
- `else` is forbidden on an exhaustive case: new variants must trigger a
  diagnostic. Ordinary `case` keeps its current fallback behavior.
- A new schema variant produces an error listing missing variants and a
  suggested arm skeleton. Nested patterns get their own coverage analysis;
  version 1 supports only one variant layer and named bindings.
- Schema identity and version are part of incremental-cache keys. Unknown
  runtime versions are rejected before reading layout-dependent fields.

Start with one small compiler visitor and a generated coverage checker. Add
parser nodes for PatternCase/VariantPattern/FieldBinding, then lower using
existing kind and field operations. Validate missing/duplicate/guarded arms,
field typos, scope leakage, malformed packed handles and stage-1/stage-2
identity. Full AST visitors must enumerate the actual schema; the three-arm
example above is not an exhaustive AST visitor.
