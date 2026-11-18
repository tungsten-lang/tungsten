# Keep complete declarations in file order. Numeric-family specs frequently
# select one more failure from the same immutable fixture.
PROOF_SOURCE_BLOCKS = {}

-> proof_source_blocks(path)
  blocks = PROOF_SOURCE_BLOCKS[path]
  if blocks != nil
    return blocks
  blocks = []
  lines = nil
  File.read(path).split("\n").each -> (line)
    if !line.empty?() && !line.starts_with?(" ")
      words = line.split(" ")
      prefix = ["@\[simp]", "@\[auto]"].include?(words[0]) ? 1 : 0
      if ["+", "->", "def", "theorem", "lemma", "axiom", "opaque", "structure", "inductive", "import"].include?(words[prefix])
        lines = []
        blocks.push([words[prefix + 1], lines])
    if lines != nil && !line.starts_with?("#axioms")
      lines.push(line)
  PROOF_SOURCE_BLOCKS[path] = blocks
  blocks

-> proof_declarations(path, names)
  selected = []
  proof_source_blocks(path).each -> (block)
    if names.include?(block[0])
      selected.push(block[1].join("\n"))
  if selected.size != names.size
    raise "proof selection missed a declaration"
  if selected.empty?()
    return ""
  selected.join("\n") + "\n"
