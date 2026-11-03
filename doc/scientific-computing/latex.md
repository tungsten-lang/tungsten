# LaTeX source generation

`core/latex.w` turns Tungsten values into safe, composable LaTeX source for
papers, notes, and reports. It emits source only: it does not invoke a TeX
engine, discover packages, run BibTeX, or produce a PDF. The mathematical and
numeric types remain independent of this module.

`LaTeX.render` is available through the core autoload surface:

```tungsten
q = LaTeX.render(Rational.new(3, 8))
# => \frac{3}{8}

formula = LaTeX.fraction(
  LaTeX.symbol(:alpha_1),
  LaTeX.superscript(LaTeX.symbol(:x), 2))

equation = LaTeX.equation(formula, "eq:ratio")
reference = LaTeX.eqref("eq:ratio")
```

Rendering and composition helpers return a `LatexFragment`. Fragments can be
combined with `+`, `append`, `LaTeX.concat`, `LaTeX.join`, or an append-only
builder:

```tungsten
paper = LaTeX.builder
paper.text("Measured value: ")
paper.math(9.80665 m/s²)
paper.line(LaTeX.ref("tab:measurements"))

table = LaTeX.table(
  ["Quantity", "Value & unit"],
  [["gravity", 9.80665 m/s²], ["efficiency", 92.4%]],
  "Representative measurements",
  "tab:measurements",
  "lc")
```

## Semantic mathematics

`LatexMath` preserves construction-time meaning before lowering to a
`LatexFragment`. Its vocabulary and presentation-semantic sorts are
deliberately closed so unsupported operations fail instead of silently
acquiring the wrong meaning:

```tungsten
x = LatexMath.symbol(:x)
y = LatexMath.symbol(:y)

formula = LatexMath.product([
  LatexMath.sum([x, LatexMath.number(1)]),
  y
])

formula.concept       # "times"
formula.sort          # :scalar
formula.to_latex      # \left(x + 1\right)\,y
LaTeX.render(formula) # the same LatexFragment
```

The initial constructors are `number`, `named_constant`, `symbol`, `sum`,
`product`, `quotient`, `power`, `square_root`, `absolute_value`, `determinant`,
`cartesian_product`, `matrix_product`, and `equals`. Symbols may be scalar,
set, or matrix values; equality yields a proposition. Constructors validate
arity and sorts, and `children` returns a defensive copy. Typed leaf accessors
`number_value` and `symbol_name` let later backends traverse the tree without
parsing its rendered source.

`LaTeX.semantic(value)` / `LatexMath.from(value)` convert supported Core
scalars, symbols, and the stable subset of `Expression` nodes: constants,
variables, named constants, addition, multiplication, division, powers, square
roots, and absolute values. Strings, fragments, arbitrary objects, and other
expression operations are rejected. Escaped presentation or trusted source
cannot be retroactively declared semantic.

Sorts describe presentation semantics; they do not prove scalar-domain
membership, matrix conformability, set theory, or dimensional consistency.
MathML, generated speech, and caller-defined notation registries are not part
of this initial public contract.

## Safety model

Ordinary strings are escaped. `LaTeX.escape`, `text`, `math_text`, document
metadata, section titles, captions, and ordinary table cells protect all TeX
reserved characters. Commands, environments, labels, references, matrix
environments, and table alignments accept only narrow validated names.

`LaTeX.raw` is the explicit trust boundary for caller-supplied TeX:

```tungsten
safe = LaTeX.text("A&B_1")       # A\&B\_1
trusted = LaTeX.raw("E = mc^{2}")
```

Only use `raw` for source controlled by the program. It deliberately bypasses
escaping and carries no structured reference provenance.

## Reference and citation validation

Labels, references, equation references, and citations created through Core
helpers retain immutable provenance as fragments are appended, joined, nested
in equations/tables/sections, and wrapped by publication profiles. Validation
is opt-in and never scans TeX source:

```tungsten
body = LaTeX.concat([
  LaTeX.text("See "),
  LaTeX.eqref("eq:energy"),
  LaTeX.equation(LaTeX.raw("E=mc^{2}"), "eq:energy"),
  LaTeX.cite(["einstein1905", "review2025"])
])

document = LaTeX.profile(:arxiv).document(body)
report = LaTeX.validate(document, ["einstein1905", "review2025"])
report.raise_if_invalid
```

`LatexValidationReport` exposes `labels`, `references`, `citations`,
`duplicate_labels`, `unresolved_references`, `unresolved_citations`,
`citation_check_complete?`, `tracked_valid?`, `issues`, and
`raise_if_invalid`. The shorter `complete?` and `valid?` aliases have the same
tracked-only meaning. `scope` returns `:structured_helpers` and
`tracked_only?` is always true so callers cannot confuse the result with a
whole-TeX parser. References may precede their definitions. Repeated uses are
valid; repeated label definitions are not. Reference diagnostics retain
whether the original helper was `ref` or `eqref`.

Citation resolution requires an explicit Array of bibliography keys. Passing
`nil` records citations but makes the report incomplete and invalid; passing
an empty Array authoritatively marks every citation unresolved. Core does not
read bibliography files or infer keys from a profile’s bibliography resource.

Validation is exact only for structured helpers. `LaTeX.raw`, direct
`LatexFragment.new`, included files, custom macros, `autoref`/`cref`, and
package-specific citation commands are untracked. Reconstructing a fragment
from its `.source` also discards provenance. This is safer than a partial TeX
scanner whose result could be mistaken for complete validation.

## Rendered values

The initial structural renderer supports:

- integers, floating-point values, decimals, rationals, infinities, NaN, and
  scientific notation;
- symbolic `Expression` trees, including operator precedence, powers,
  fractions, common functions, named constants, and Greek identifiers;
- `Polynomial`, `PolynomialRing`, rational/finite/number fields, power-basis
  elements, and `ProjectivePoint`;
- arrays, nested arrays, vectors, numeric and sparse matrices, and geometry
  `Metric` components;
- complex values, numeric/certified intervals, and `QuadratureResult` with its
  error estimate;
- `Quantity` values and units, `Currency`, and `Percentage`.

Unknown objects fall back to escaped text rather than being treated as TeX.
Point/delta quantity annotations also use this safe text fallback because
their committed cross-engine API does not yet expose stable structured
magnitude and unit accessors. `Measurement`, `Calibration`, and legacy
`Money` objects are not structurally rendered in this tranche; use their
stable scalar constituents or an explicitly trusted fragment.

The primitive helpers cover symbols, grouping, parentheses, brackets,
absolute values, fractions, square roots, scripts, operators, commands, and
validated environments. Paper helpers cover inline/display math, equations,
align blocks, labels and references, sections, paragraphs, tables, and basic
documents.

## Publication profiles

Publication policy is kept under `core/latex/profiles/`, separate from the
generic renderer. Select a profile with a symbol or string:

```tungsten
profile = LaTeX.profile(:ieee)
body = LaTeX.section("Results", equation)
document = profile.document(body, {
  :title => "Exact symbolic results",
  :authors => ["Ada Lovelace", "Emmy Noether"],
  :abstract => "A reproducible calculation.",
  :keywords => ["symbolic algebra", "verification"],
  :bibliography => "refs/main"
})
```

The initial profiles are concise starting points:

| Profile | Class and options | Bibliography style | Profile-specific behavior |
|---|---|---|---|
| `:ieee` | `IEEEtran[conference]` | `IEEEtran` | `IEEEkeywords` environment |
| `:acm` | `acmart[sigconf]` | `ACM-Reference-Format` | one `author` command per author and `keywords` |
| `:arxiv` | `article[11pt]` | `plain` | one-inch geometry and hyperref baseline |
| `:thesis` | `report[12pt,oneside]` | `plainnat` | institution-neutral title page, degree, and institution |
| `:journal` | `article[twocolumn]` | `abbrvnat` | neutral two-column article baseline |

Supported metadata keys are `title`, `author` or `authors`, `date`,
`abstract`, `keywords`, `bibliography`, and an optional
`bibliography_style`. The thesis profile also accepts `degree` and
`institution`. Profile objects expose `document_class_fragment`,
`preamble_fragment`, `opening_fragment`, `bibliography_fragment`, and
`document`, so applications can replace or reorder parts without duplicating
the generic renderer.

Custom profile `extra_preamble` entries must already be explicit
`LatexFragment` values; ordinary strings are rejected rather than silently
treated as trusted source. Profile option and package Arrays are defensively
copied on input and output.

These profiles are deliberately not claims of submission compliance. Venue
classes, package rules, author metadata, rights blocks, bibliography policy,
and formatting requirements change and often vary by track. Review the
generated source against the exact venue or institution instructions before
submission.

To add a profile, place a small definition in `core/latex/profiles/` whose
`build` method returns a configured `LatexProfile`, load it from
`profiles.w`, and register its name in `LaTeXProfiles`. Venue-specific policy
belongs there; value rendering stays in `core/latex.w`.

## Limitations

No TeX syntax checker or external engine is invoked, so source generation does
not prove that a locally installed class/package set can compile a complete
document. The module does not run bibliography tools, manage figures, choose
pagination, or validate venue-specific constraints. Reference validation does
not inspect arbitrary TeX or external files, and semantic sorts are not a type
proof. Complex custom objects should be assembled from structural helpers
until they have a stable public representation suitable for a dedicated
renderer.
