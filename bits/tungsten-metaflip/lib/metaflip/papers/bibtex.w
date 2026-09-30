# Bibtex: split a .bib file into its entries and print them the way the papers' bibliography
# wants them (papers/scripts/mkbib.w; original: papers/scripts/mkbib.py).
#
#   Bibtex.entries(raw)          Hash key => entry text, for every `@type{key, ...}` block of a file
#   Bibtex.print_ready(key, block, notes)
#                                the entry without comment lines and `note` fields, plus the public
#                                note `notes[key]` when there is one
#   Bibtex.render(cited, entries) the entries of the cited keys, sorted by key, blank line apart
#
# A block starts at an `@` in the first column and runs to the next such `@`.  Lines that begin
# with `%` are comments (section headers of a master file fall at the end of the previous block);
# a `note = {...}` field on one line is a verification memo for the authors, not for readers.
+ BibtexError < Error

+ Bibtex
  # Bytes of \w in an entry type: letters, digits, underscore.
  -> .word_byte?(b)
    (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95

  # The file cut before every newline that is followed by `@` (the newline goes, the `@` stays).
  -> .blocks(raw)
    pieces = []
    start = 0
    at = raw.index("\n@")
    while at != nil
      pieces.push(raw.slice(start, at - start))
      start = at + 1
      at = raw.index("\n@", start)
    pieces.push(raw.slice(start, raw.size - start))
    pieces

  # The key of a block that starts `@type{key,`; nil for any other block (the header comments of
  # a file, say).  The key is everything up to the first comma, at least one byte.
  -> .key_of(block)
    return nil unless block.starts_with?("@")
    pos = 1
    pos += 1 while pos < block.size && Bibtex.word_byte?(block.byte_at(pos))
    return nil if pos == 1 || pos >= block.size || block.byte_at(pos) != 123
    comma = block.index(",", pos + 1)
    return nil if comma == nil || comma == pos + 1
    block.slice(pos + 1, comma - pos - 1)

  # key => trimmed block for every entry of `raw`; a repeated key keeps its last block.
  -> .entries(raw)
    found = {}
    Bibtex.blocks(raw).each -> (block)
      key = Bibtex.key_of(block)
      found[key] = block.strip unless key == nil
    found

  # True for a line `note = {...}` (any indentation, spaces around `=`) that closes its brace
  # on the same line.
  -> .note_line?(line)
    text = line.ltrim
    return false unless text.starts_with?("note")
    rest = text.slice(4, text.size - 4).ltrim
    return false unless rest.starts_with?("=")
    rest = rest.slice(1, rest.size - 1).ltrim
    rest.starts_with?("{") && rest.index("}") != nil

  # `block` without its `%` comment lines and its one-line `note` fields, closed by "\n}".  A
  # trailing comma before the closing brace is dropped, and the public form of the note, when
  # `notes` has one for `key`, is added last.
  -> .print_ready(key, block, notes)
    kept = block.split("\n").select -> (line)
      !line.starts_with?("%") && !Bibtex.note_line?(line)
    text = kept.join("\n").rtrim
    raise BibtexError.new("entry " + key + " does not end with a closing brace") unless text.ends_with?("}")
    body = text.slice(0, text.size - 1).rtrim
    body = body.slice(0, body.size - 1) if body.ends_with?(",")
    body += ",\n  note = {" + notes[key] + "}" if notes.key?(key)
    body + "\n}"

  # The print-ready text of every cited key that some entry has, sorted by key, separated by a
  # blank line, ending with a newline.
  -> .render(cited, entries, notes)
    ready = {}
    entries.keys.each -> (key)
      ready[key] = Bibtex.print_ready(key, entries[key], notes)
    found = cited.select -> (key)
      ready.key?(key)
    found.sort.map(-> (key) ready[key]).join("\n\n") + "\n"
