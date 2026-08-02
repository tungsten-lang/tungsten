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
escaping.

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
pagination, or validate venue-specific constraints. Complex custom objects
should be assembled from structural helpers until they have a stable public
representation suitable for a dedicated renderer.
