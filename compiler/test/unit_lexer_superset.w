use ../lib/lexer
use ../lib/error_formatter
use ../../languages/tungsten/lexers/regex

-> lexchars_link_marker
  nil

# Scan each spelling independently so apostrophes and slashes cannot interact
# with a later line and accidentally hide a mismatch. Compare semantic tokens.
names = read_file(unit_names_registry_path()).split("\n")
checked = 0
names.each -> (name)
  next if name == ""
  # Reciprocal units starting with a digit require a quoted runtime spelling.
  quoted = name[0] >= "0" && name[0] <= "9"
  source = "1 " + name + "\n2 m\n"
  if quoted
    source = "ccall(\"w_quantity_parse\", \"1\", \"" + name + "\")\n2 m\n"
  expected = RegexLexer.new(source, "unit-superset").tokenize()
  lexer = Lexer.new(source, "unit-superset")
  lexer.tokenize()
  tokens = lexer.packed_tokens()
  values = lexer.values()
  j = 0
  k = 0
  while j < tokens.size()
    type_id = (tokens[j] >> 38) & 255
    if type_id != 25
      if k >= expected.size() || type_id != lexer.type_sym_to_id(expected[k][:type]) || values[j] != expected[k][:value]
        raise "unit lexer mismatch: " + name + " at token " + k.to_s() + " expected " + expected[k].to_s() + " got " + type_id.to_s() + " " + values[j].to_s()
      k += 1
    j += 1
  if k != expected.size() || (!quoted && (expected[0][:type] != :QUANTITY || expected[0][:value] != ["1", name]))
    raise "unit was not recognized exactly: " + name
  checked += 1

# The reference lexer does not implement ASCII single-quoted literals yet.
# Check the production scanner separately: its apostrophe-phrase helper must
# neither swallow later strings nor box the raw offsets used for string scans.
source = "1 baker's dozen\n'plain'\n\"double\"\n2 sabbath day's journey\n'after'\n3 m\n"
lexer = Lexer.new(source, "unit-quote-boundaries")
lexer.tokenize()
tokens = lexer.packed_tokens()
values = lexer.values()
strings = []
quantities = []
i = 0
while i < tokens.size()
  type_id = (tokens[i] >> 38) & 255
  if type_id == 5
    strings.push(values[i])
  if type_id == 44
    quantities.push(values[i])
  i += 1
if strings != ["plain", "double", "after"] || quantities != [["1", "baker's dozen"], ["2", "sabbath day's journey"], ["3", "m"]]
  raise "unit phrases corrupted quote boundaries: " + strings.to_s() + " " + quantities.to_s()
<< "unit lexer superset: PASS " + checked.to_s() + " spellings"
