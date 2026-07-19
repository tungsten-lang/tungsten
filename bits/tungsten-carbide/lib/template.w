# Carbide::Template — the V in MVC: a compile-once/render-many
# mustache-style template engine.
#
#   t = Template.compile("<h1>{{title}}</h1>{{#each tasks}}<li>{{this.title}}</li>{{/each}}")
#   t.render({title: "Tasks", tasks: [{title: "buy milk"}]})
#
# Syntax (v1 — deliberately small; no partials/layouts/filters yet):
#   {{name}}            interpolate params[:name], HTML-escaped
#   {{{name}}}          interpolate raw (no escaping)
#   {{#if name}}...{{/if}}     render body when the value is truthy
#                              (anything but nil/false)
#   {{#each items}}...{{/each}} render body once per array element;
#                              inside, {{this}} is the element and
#                              {{this.field}} reads a hash element's
#                              :field (params names still resolve)
#
# Design notes:
#   - Mustache-style {{ }} on purpose: Tungsten's own string
#     interpolation is [expr] inside double quotes, so a bracket-based
#     template syntax would collide with the host language. Braces are
#     inert in .w string literals.
#   - Compile once, render many: Template.compile parses the source to
#     a node tree (hashes with :kind/:name/:children); render walks it
#     with a symbol-keyed params hash. Params keys are symbols
#     ({name: "x"}), matching Model attributes.
#   - Escaping: {{name}} HTML-escapes & < > " ' (the five XSS-relevant
#     ASCII specials); {{{name}}} skips escaping. Literal template text
#     passes through verbatim.
#   - Error behavior: Template.compile returns NIL for a malformed
#     template — unterminated {{ tag, empty {{}}, unknown {{#block}} or
#     {{/close}}, unclosed or mismatched {{#if}}/{{#each}}. No
#     exceptions (identical behavior in both engines beats raise/rescue
#     divergence — same convention as Model.find). Callers must check.
#   - Missing values render as "" ({{name}} with no :name), an absent
#     {{#if}} value is falsy, and an absent/non-array {{#each}} value
#     renders nothing.
#   - UTF-8: scanning is byte-wise (String#size counts bytes), which is
#     UTF-8-transparent — multi-byte sequences contain no ASCII bytes,
#     so template text and values pass through byte-identical. Keep
#     variable NAMES ASCII (name handling assumes ASCII word bytes).
#
# Top-level (no `in` namespace): namespaced bit classes are unreachable
# from consumers and specs — same convention as route.w / controller.w.

+ Template
  ro :nodes

  -> new(@nodes)

  # Compile a template string. Returns a Template, or nil when the
  # source is malformed (see error behavior above).
  -> .compile(source)
    result = nil
    tokens = Template.tokenize(source)
    if tokens != nil
      nodes = Template.parse(tokens)
      if nodes != nil
        result = Template.new(nodes)
    result

  # Source string -> flat token list (node-shaped hashes), or nil on a
  # lexically malformed template.
  -> .tokenize(source)
    tokens = []
    rest = source
    failed = false
    done = false
    while !done
      pos = rest.index("{{")
      if pos == nil
        if rest.size > 0
          tokens.push({kind: :text, value: rest})
        done = true
      else
        if pos > 0
          tokens.push({kind: :text, value: rest.slice(0, pos)})
        tag = rest.slice(pos, rest.size - pos)
        if tag.starts_with?("{{{")
          close = tag.index("}}}")
          if close == nil
            failed = true
            done = true
          else
            name = tag.slice(3, close - 3).strip
            if name == ""
              failed = true
              done = true
            else
              tokens.push({kind: :var, name: name, raw: true})
              rest = tag.slice(close + 3, tag.size - close - 3)
        else
          close = tag.index("}}")
          if close == nil
            failed = true
            done = true
          else
            inner = tag.slice(2, close - 2).strip
            tok = Template.classify(inner)
            if tok == nil
              failed = true
              done = true
            else
              tokens.push(tok)
              rest = tag.slice(close + 2, tag.size - close - 2)
    result = tokens
    if failed
      result = nil
    result

  # One stripped tag body -> token hash, or nil for an empty/unknown tag.
  -> .classify(inner)
    tok = nil
    if inner == "/if"
      tok = {kind: :close_if}
    elsif inner == "/each"
      tok = {kind: :close_each}
    elsif inner.starts_with?("#if ")
      name = inner.slice(4, inner.size - 4).strip
      if name != ""
        tok = {kind: :open_if, name: name}
    elsif inner.starts_with?("#each ")
      name = inner.slice(6, inner.size - 6).strip
      if name != ""
        tok = {kind: :open_each, name: name}
    elsif inner.starts_with?("#") || inner.starts_with?("/")
      tok = nil
    elsif inner != ""
      tok = {kind: :var, name: inner, raw: false}
    tok

  # Token list -> node tree (children arrays), or nil on unclosed /
  # mismatched blocks.
  -> .parse(tokens)
    root = {kind: :root, name: "", children: []}
    stack = [root]
    failed = false
    i = 0
    while i < tokens.size
      tok = tokens[i]
      top = stack[stack.size - 1]
      kind = tok[:kind]
      if kind == :open_if
        node = {kind: :if, name: tok[:name], children: []}
        top[:children].push(node)
        stack.push(node)
      elsif kind == :open_each
        node = {kind: :each, name: tok[:name], children: []}
        top[:children].push(node)
        stack.push(node)
      elsif kind == :close_if
        if stack.size < 2 || top[:kind] != :if
          failed = true
        else
          stack.pop
      elsif kind == :close_each
        if stack.size < 2 || top[:kind] != :each
          failed = true
        else
          stack.pop
      else
        top[:children].push(tok)
      i = i + 1
    if stack.size != 1
      failed = true
    result = root[:children]
    if failed
      result = nil
    result

  # HTML-escape & < > " ' (byte-wise scan; UTF-8 bytes pass through).
  -> .escape_html(s)
    out = []
    i = 0
    n = s.size
    while i < n
      c = s.slice(i, 1)
      if c == "&"
        out.push("&amp;")
      elsif c == "<"
        out.push("&lt;")
      elsif c == ">"
        out.push("&gt;")
      elsif c == "\""
        out.push("&quot;")
      elsif c == "'"
        out.push("&#39;")
      else
        out.push(c)
      i = i + 1
    out.join("")

  # --- rendering ---

  # Render with a symbol-keyed params hash. Reusable: one compiled
  # Template renders any number of times with different params.
  -> render(params = {})
    render_nodes(@nodes, params, nil)

  -> render_nodes(nodes, params, this_val)
    out = []
    i = 0
    while i < nodes.size
      node = nodes[i]
      kind = node[:kind]
      if kind == :text
        out.push(node[:value])
      elsif kind == :var
        v = resolve_value(node[:name], params, this_val)
        s = stringify(v)
        if node[:raw]
          out.push(s)
        else
          out.push(Template.escape_html(s))
      elsif kind == :if
        v = resolve_value(node[:name], params, this_val)
        if v != nil && v != false
          out.push(render_nodes(node[:children], params, this_val))
      elsif kind == :each
        v = resolve_value(node[:name], params, this_val)
        if type(v) == "Array"
          j = 0
          while j < v.size
            out.push(render_nodes(node[:children], params, v[j]))
            j = j + 1
      i = i + 1
    out.join("")

  # this / this.field / params name -> value (nil when absent).
  -> resolve_value(name, params, this_val)
    v = nil
    if name == "this"
      v = this_val
    elsif name.starts_with?("this.")
      field = name.slice(5, name.size - 5)
      if type(this_val) == "Hash"
        v = this_val[field.to_sym]
    else
      v = params[name.to_sym]
    v

  # nil -> "" explicitly: nil.to_s is "nil" interpreted but "" compiled,
  # so the guard keeps both engines identical.
  -> stringify(v)
    s = ""
    if v != nil
      s = v.to_s
    s
