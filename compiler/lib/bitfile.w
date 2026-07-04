# Bitfile parser — reads a `Bitfile` manifest and returns a structured hash,
# preserving source line numbers on service bindings for good error messages.
#
# One Tungsten-native source of truth for the manifest, replacing the shell
# wrapper's grep/sed pipeline (bin/tungsten) and the Ruby regex scans in
# bin/commands/{build,compile}.rb. Lives in compiler/lib/ rather than a bit
# because the compiler/loader consume it at compile time and a compiler→bit
# dependency would be a bootstrap cycle (bits are built BY the compiler).
#
# Line-based: Bitfiles are line-oriented, so this avoids a dependency on the
# full lexer/parser (this module has no `use` directives). Directives:
#   name "..."                → :name
#   version "..."             → :version
#   includes ["a.c", "b.c"]   → :includes  (C files, array of strings)
#   requires ["bit", ...]     → :requires  (bit deps, array of strings)
#   Tungsten[:sym] = "bit"    → :service_bindings[sym] = {bit:, line:}
# Ignored (metadata / not compilation-relevant): tungsten, summary,
# description, license, authors, bit, external, and blank/comment lines.
# Unknown directives are silently skipped, never an error.
#
# NOTE on the char literals below: the '"', '[' and ']' characters are built
# via `.chr` (34/91/93). A `"\""` literal is an unterminated string, and a
# `[` inside a double-quoted string opens a `"[expr]"` interpolation (also
# read as unterminated) — so those three bytes can't appear in string literals.

# First double-quoted substring on a line, or nil.
-> bitfile_first_string(line)
  dq = 34.chr
  q1 = line.index(dq)
  if q1 == nil
    return nil
  rest = line.slice(q1 + 1, line.size() - q1 - 1)
  q2 = rest.index(dq)
  if q2 == nil
    return nil
  rest.slice(0, q2)

# The quoted strings inside a `[ ... ]` list on a line: ["a", "b"] → ["a", "b"].
-> bitfile_string_list(line)
  out = []
  lb = line.index(91.chr)
  rb = line.index(93.chr)
  if lb == nil || rb == nil || rb <= lb
    return out
  inner = line.slice(lb + 1, rb - lb - 1)
  parts = inner.split(",")
  i = 0
  while i < parts.size()
    s = bitfile_first_string(parts[i].strip())
    if s != nil
      out.push(s)
    i = i + 1
  out

# The binding symbol from `Tungsten[:name] = "bit"` → "name", or nil.
-> bitfile_binding_symbol(line)
  c = line.index(":")
  if c == nil
    return nil
  rest = line.slice(c + 1, line.size() - c - 1)
  rb = rest.index(93.chr)
  if rb == nil
    return nil
  rest.slice(0, rb)

# Leading non-empty whitespace-delimited token of a line (the directive name).
-> bitfile_first_token(line)
  parts = line.split(" ")
  i = 0
  while i < parts.size()
    if parts[i] != ""
      return parts[i]
    i = i + 1
  ""

# Parse the Bitfile at `path` into a structured hash. A missing/unreadable
# file yields the empty-but-shaped result (all fields present, none set), so
# callers never nil-check individual fields.
-> parse_bitfile(path)
  result = {name: nil, version: nil, includes: [], requires: [], service_bindings: {}}
  source = read_file(path)
  if source == nil
    return result
  lines = source.split("\n")
  i = 0
  while i < lines.size()
    lineno = i + 1
    line = lines[i].strip()
    i = i + 1
    if line == "" || line.starts_with?("#")
      next
    tok = bitfile_first_token(line)
    if tok == "name"
      result[:name] = bitfile_first_string(line)
    elsif tok == "version"
      result[:version] = bitfile_first_string(line)
    elsif tok == "includes"
      result[:includes] = bitfile_string_list(line)
    elsif tok == "requires"
      result[:requires] = bitfile_string_list(line)
    elsif tok.starts_with?("Tungsten")
      sym = bitfile_binding_symbol(line)
      bit = bitfile_first_string(line)
      if sym != nil && bit != nil
        result[:service_bindings][sym] = {bit: bit, line: lineno}
  result
