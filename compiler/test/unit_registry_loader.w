use ../../languages/tungsten/lexers/known_units
use ../lib/lexer
use ../lib/error_formatter
use ../../languages/tungsten/lexers/regex

-> lexchars_link_marker
  nil

-> check_lexers
  source = "1 startup_probe\n"
  reference = RegexLexer.new(source, "snapshot").tokenize()
  production = Lexer.new(source, "snapshot")
  production.tokenize()
  first = production.packed_tokens()[0]
  if reference[0][:type] != :QUANTITY || ((first >> 38) & 255) != 44
    raise "external name did not lex as a quantity"

if !known_unit_names.frozen?()
  raise "registry is not frozen"
if !known_unit_name?("startup_probe")
  raise "missing external startup name"
if !known_unit_name?("µm")
  raise "Unicode unit spelling changed while loading"
check_lexers()

# File removal must not affect either existing or newly created lexers in the
# same process. The harness supplies a disposable copy, never the source data.
File.delete(unit_names_registry_path())
check_lexers()
if !known_unit_name?("startup_probe") || known_unit_name?("missing_probe")
  raise "membership changed after startup"
begin
  known_unit_names["new_probe"] = true
  raise "registry mutation unexpectedly succeeded"
rescue err
  if !err.to_s().include?("frozen")
    raise err
<< "unit registry snapshot: PASS"
