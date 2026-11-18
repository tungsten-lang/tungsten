# Select complete proof/definition declarations from the source under test.
# Numeric-family specs run separately to stay within interpreter memory limits.
-> proof_declarations(path, names)
  source = ""
  taking = false
  found = 0
  File.read(path).split("\n").each -> (line)
    words = line.split(" ")
    prefix = ["@\[simp]", "@\[auto]"].include?(words[0]) ? 1 : 0
    if ["+", "->", "def", "theorem", "lemma", "axiom", "opaque", "structure", "inductive", "import"].include?(words[prefix])
      taking = names.include?(words[prefix + 1])
      if taking
        found += 1
    if taking && !line.starts_with?("#axioms")
      source += line + "\n"
  if found != names.size
    raise "proof selection missed a declaration"
  source
