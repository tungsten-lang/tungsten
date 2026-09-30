# Tex: the few things the paper build scripts read out of LaTeX sources, with plain string
# operations (no regular expressions).
#
#   Tex.cited_keys(text)      the keys of every \cite, \citep, \citet*, \cite[see][p. 2]{a, b}
#                             command, first-seen order, each once
#   Tex.strip_comments(text)  the text with every unescaped `%` comment removed (the newline stays)
#   Tex.references(text)      the files a source names: [\input, \include, \includegraphics,
#                             pgfplots `table {...}` and \bibliography arguments], see below
#   Tex.todo_lines(text)      the 1-based numbers of the lines that use \todo
#   Tex.abstract(text)        the text of the abstract environment
#
# Used by papers/scripts/{mkbib,pack_arxiv,make_arxiv_md}.w.  The originals are the three
# Python scripts of the same names, which use `re` for all of it.
#
# Everything works on byte offsets (String#index, #slice, #byte_at); the characters that matter
# to LaTeX ({ } [ ] \ %) are ASCII.
+ Tex
  # ---- lexical helpers -----------------------------------------------------------------

  # Bytes of \s in the sources: space, tab, newline, carriage return, form feed, vertical tab.
  -> .space_byte?(b)
    b == 32 || (b >= 9 && b <= 13)

  -> .lowercase_byte?(b)
    b >= 97 && b <= 122

  # The offset of the first byte at or after `pos` that is not white space (text.size at the end).
  -> .skip_space(text, pos)
    pos += 1 while pos < text.size && Tex.space_byte?(text.byte_at(pos))
    pos

  # `[...]` at `pos` (an optional argument): the offset after its `]`; `pos` itself when no
  # bracketed group starts there (or it never closes).
  -> .skip_optional(text, pos)
    return pos if pos >= text.size || text.byte_at(pos) != 91
    close = text.index("]", pos + 1)
    close == nil ? pos : close + 1

  # Any number of `[...]` groups in a row.
  -> .skip_optionals(text, pos)
    after = Tex.skip_optional(text, pos)
    return pos if after == pos
    Tex.skip_optionals(text, after)

  # `{...}` at `pos`: [contents, offset after the `}`], or nil when there is no brace group there.
  # The group ends at the first `}` (LaTeX arguments here never nest); `at_least` is the fewest
  # bytes it may hold.
  -> .brace_group(text, pos, at_least)
    return nil if pos >= text.size || text.byte_at(pos) != 123
    close = text.index("}", pos + 1)
    return nil if close == nil || close - pos - 1 < at_least
    [text.slice(pos + 1, close - pos - 1), close + 1]

  # ---- citations -----------------------------------------------------------------------

  # \cite, then lowercase letters, an optional `*`, optional `[...]` arguments and a `{...}`
  # group starting at `at` (the offset of the backslash): [keys text, offset after the group] or nil.
  -> .cite_at(text, at)
    pos = at + 5
    pos += 1 while pos < text.size && Tex.lowercase_byte?(text.byte_at(pos))
    pos += 1 if pos < text.size && text.byte_at(pos) == 42
    Tex.brace_group(text, Tex.skip_optionals(text, pos), 0)

  # The keys cited in `text`: each `,`-separated name of every citation command, stripped, in
  # first-seen order, each once.  `\cite{}` cites the empty key (which no entry has).
  -> .cited_keys(text)
    keys = []
    seen = {}
    at = text.index("\\cite")
    while at != nil
      found = Tex.cite_at(text, at)
      if found == nil
        at = text.index("\\cite", at + 1)
      else
        names = found[0] == "" ? [""] : found[0].split(",")
        names.each -> (name)
          key = name.strip
          unless seen.key?(key)
            seen[key] = true
            keys.push(key)
        at = text.index("\\cite", found[1])
    keys
