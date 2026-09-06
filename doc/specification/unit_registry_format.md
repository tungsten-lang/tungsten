# External unit registry

`data/unit_registry.json` is the language-neutral source of unit definitions.
`scripts/gen_units.rb` reads it without loading the Ruby interpreter. The Ruby
engine is another reader. `data/units.tsv` preserves the legacy numeric IDs;
it is an ABI ledger, not a second set of physical definitions.

The JSON schema identifier is `tungsten.units/v1`. Numeric factors, offsets,
and prefix multipliers are strings containing an integer or `numerator/denominator`.
Denominators are positive. No floating-point JSON numbers or executable
expressions are accepted for conversion constants. Existing measured values
retain their stored rational approximation; the format does not make them exact
physical measurements.

Each `units` record contains:

- `symbol`: exact, case-sensitive Unicode spelling.
- `dimension`: `powers`, an eight-integer vector in the declared `axes` order,
  and `semantic`, a sparse map of semantic-tag exponents.
- `factor` and `offset`: canonical value = input × factor + offset.
- `prefixable`: `none`, `si`, `binary`, or `both`.
- `kind`: `unit`, `physical_constant`, `nominal_unit`, `reference_quantity`,
  `reference_scale`, `contextual_unit`, or `contextual_reference`.

`prefixes` defines symbolic SI, long SI, and binary prefixes. Explicit override
lists retain established language conventions. `aliases` maps spellings to
canonical names. `compounds` records contain `symbol`, exact `scale`, and an
`expression` built from atomic names and their prefixes using multiplication,
division, and integer powers. These expand compositionally; for example,
`{"symbol":"Hz","scale":"1/1","expression":"cycle/s"}` preserves cycle as
a semantic numerator. Compound definitions take precedence over an atomic
compatibility record of the same name. Compound expressions use the atomic
namespace, so self-recursive compound expansion is impossible.

`dimensions` and `dimension_names` contain public dimension names and labels.
`pluralizable` records the existing spelling policy. `legacy_symbols` explicitly
lists legacy spellings that retain symbolic rather than defined conversions.
Ordering of unit and prefix entries is significant for generated numeric IDs;
append new entries and preserve the legacy ledger. Existing aliases and exact
names win over generated prefixes.

Descriptions, etymology, history, defining sources, dates, and measured/exact
status live in `data/unit_metadata.tsv`. The optional reference density table
lives separately in `data/substance_densities.json` because material densities
are contextual reference values, not unit definitions. The extracted table
preserves historical estimates and playful entries; it supplies no general
temperature, pressure, uncertainty, or calibration model.

## Loading boundaries

Generate compiler/runtime tables and lexer names with
`ruby scripts/gen_units.rb --write`; verify with `--check`. Generate external
documentation with `ruby scripts/gen_units_catalog.rb`. Neither command derives
definitions from the Ruby implementation. Native binaries retain generated
conversion tables and require no registry file for ordinary quantity arithmetic.
Changing physical definitions requires regeneration and a toolchain rebuild.

The compiler and reference lexer load `data/unit_names.txt` once when the lexer
module initializes. This is compile-time startup work for programs being compiled,
and process startup work for the REPL. Token scans only query the frozen hash.
Adding a name here alone recognizes a spelling; it does not define a conversion
or semantic dimension. Unknown names retain the language's custom-unit behavior.

Path precedence is `TUNGSTEN_UNIT_NAMES`, then `TUNGSTEN_ROOT/data/unit_names.txt`,
then `../data/unit_names.txt` relative to the compiler executable, then the
development working directory's `data/unit_names.txt`. Explicit overrides fail
if missing or unreadable, without selecting a different registry silently.

The name file is UTF-8 with one exact spelling per line. LF and CRLF are accepted;
empty lines are ignored. Duplicates, surrounding whitespace, ASCII control
characters, `%`, and the keyword `in` are rejected. Bounds are 1 MiB per file and
1,024 bytes per name. Validation runs once during module initialization. An empty
registry fails. Case and Unicode spelling are preserved; compatibility
normalization would incorrectly conflate meaningful symbols.

Release packages must contain the definition JSON, names, metadata, density
references, and legacy ID ledger. Release validation invokes the extracted
compiler from another working directory to check data discovery.
The REPL finds metadata using the explicit install root, executable-relative
data directory, or development working directory, in that order; the release
smoke check verifies both lexing and external etymology/history from elsewhere.

The standalone Ruby gem's `rake build` prerequisite copies these shared inputs
and the neutral reader into the gem. Repository execution reads the original
files; installed gems use the packaged copies. Neither path obtains definitions
or documentation from Ruby source code.
