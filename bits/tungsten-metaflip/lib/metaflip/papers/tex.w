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
# Used by tungsten-lang/papers/scripts/{mkbib,pack_arxiv,make_arxiv_md}.w.  The originals are the three
# Python scripts of the same names, which use `re` for all of it.
#
# Everything works on byte offsets (String#index, #slice, #byte_at); the characters that matter
# to LaTeX ({ } [ ] \ %) are ASCII.
use ../gf2/textx

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

  # ---- comments, references, todos, abstract ---------------------------------------------

  # The text with every unescaped `%` comment removed, up to the end of its line (the newline stays):
  # re.sub(r'(?m)(?<!\\)%.*$', '', text).
  -> .strip_comments(text)
    out = []
    text.split("\n").each -> (line)
      cut = nil
      from = 0
      while cut == nil
        at = line.index("%", from)
        break if at == nil
        if at == 0 || line.byte_at(at - 1) != 92
          cut = at
        else
          from = at + 1
      out.push(cut == nil ? line : line.slice(0, cut))
    out.join("\n")

  # The arguments that follow `needle` (then, when `spaces`, white space; when `optional`, one `[...]` group; when
  # `spaces`, white space again) in `{...}` groups of at least one byte, in order, without overlap.
  -> .collect(text, needle, optional, spaces)
    found = []
    at = text.index(needle)
    while at != nil
      pos = at + needle.size
      pos = Tex.skip_space(text, pos) if spaces
      pos = Tex.skip_optional(text, pos) if optional
      pos = Tex.skip_space(text, pos) if spaces
      group = Tex.brace_group(text, pos, 1)
      if group != nil
        found.push(group[0])
        at = text.index(needle, group[1])
      else
        at = text.index(needle, at + 1)
    found

  # The files a source names, as [reference, extensions to try] in the order the pack script looks at them: every \input
  # (`.tex`), \include (`.tex`), \includegraphics (as is, `.pdf`, `.png`, `.jpg`), pgfplots `table [...] {file}` (as is)
  # and \bibliography (`.bib`; the argument may list several files). Comments are not looked at.
  -> .references(text)
    clean = Tex.strip_comments(text)
    refs = []
    [["\\input", false, false, [".tex"]], ["\\include", false, false, [".tex"]],
     ["\\includegraphics", true, false, ["", ".pdf", ".png", ".jpg"]], ["table", true, true, [""]],
     ["\\bibliography", false, false, [".bib"]]].each -> (pattern)
      Tex.collect(clean, pattern[0], pattern[1], pattern[2]).each -> (argument)
        argument.split(",").each -> (name)
          refs.push([name.strip, pattern[3]])
    refs

  # The 1-based numbers of the lines that use \todo (the macro's own definition and comment lines excluded).
  -> .todo_lines(text)
    found = []
    Textx.splitlines(text).each_with_index -> (line, i)
      if line.index("\\todo") != nil
        trimmed = line.slice(Tex.skip_space(line, 0), line.size)
        found.push(i + 1) if !trimmed.starts_with?("\\newcommand") && !trimmed.starts_with?("%")
    found

  # The text between \begin{abstract} and \end{abstract}, stripped; nil when there is none.
  -> .abstract(text)
    open = "\\begin{abstract}"
    start = text.index(open)
    stop = text.index("\\end{abstract}")
    return nil if start == nil || stop == nil
    text.slice(start + open.size, stop - start - open.size).strip
