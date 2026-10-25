# Carbide::Template — the V in MVC: a compile-once/render-many
# mustache-style template engine.
#
#   t = Template.compile("<h1>{{title}}</h1>{{#each tasks}}<li>{{this.title}}</li>{{/each}}")
#   t.render({title: "Tasks", tasks: [{title: "buy milk"}]})
#
# Syntax (v1 — deliberately small; no layouts/filters yet):
#   {{name}}            interpolate params[:name], HTML-escaped
#   {{{name}}}          interpolate raw (no escaping)
#   {{#if name}}...{{/if}}     render body when the value is truthy
#                              (anything but nil/false)
#   {{#each items}}...{{/each}} render body once per array element;
#                              inside, {{this}} is the element and
#                              {{this.field}} reads a hash element's
#                              :field (params names still resolve)
#   {{> name}}          include a registered partial (Template.register),
#                       rendered against the CURRENT params/context
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
#   - Partials ({{> name}}) compose templates by name through a shared
#     class-level registry (Template.register/partial/clear_partials — a
#     class var, hierarchy-shared like Model's store). A partial renders
#     against the caller's params/context, so {{> row}} inside {{#each}}
#     sees {{this}}. An unregistered partial renders "" (inert, like a
#     missing {{var}}); a self-/mutually-recursive partial bottoms out at
#     a fixed nesting depth rather than hanging (verified both engines).
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

  # --- Partial registry (compose templates by name) ---
  #
  # A {{> name}} tag includes a registered partial, rendered against the
  # SAME params/context as the point of inclusion (mustache semantics).
  # Register once, include from any number of parents:
  #
  #   Template.register("row", "<li>{{this.name}}</li>")
  #   list = Template.compile("<ul>{{#each items}}{{> row}}{{/each}}</ul>")
  #   list.render({items: [{name: "a"}, {name: "b"}]})
  #     # "<ul><li>a</li><li>b</li></ul>"
  #
  # register compiles the source and stores the Template, returning it (or
  # nil when the source is malformed — same contract as .compile). An
  # unregistered {{> name}} renders "" (a missing partial is inert, not an
  # error — same convention as a missing {{var}}). The registry is one
  # shared table (class vars are hierarchy-shared, like Model's store);
  # clear_partials resets it for spec isolation.
  @@partials = {}

  -> .register(name, source)
    tpl = Template.compile(source)
    if tpl != nil
      @@partials[name] = tpl
    tpl

  -> .partial(name)
    @@partials[name]

  -> .clear_partials
    @@partials = {}

  # Source string -> flat token list (node-shaped hashes), or nil on a
  # lexically malformed template.
  -> .tokenize(source)
    tokens = []
    n = source.size
    cursor = 0
    failed = false
    done = false
    while !done
      pos = -1
      i = cursor
      while i + 1 < n
        if source.byte_at(i) == 123 && source.byte_at(i + 1) == 123
          pos = i
          i = n
        else
          i = i + 1
      if pos < 0
        if cursor < n
          if cursor == 0
            tokens.push({kind: :text, value: source})
          else
            tokens.push({kind: :text, value: source.slice(cursor, n - cursor)})
        done = true
      else
        if pos > cursor
          tokens.push({kind: :text, value: source.slice(cursor, pos - cursor)})
        if pos + 2 < n && source.byte_at(pos + 2) == 123
          close = -1
          j = pos + 3
          while j + 2 < n
            if source.byte_at(j) == 125 && source.byte_at(j + 1) == 125 && source.byte_at(j + 2) == 125
              close = j
              j = n
            else
              j = j + 1
          if close < 0
            failed = true
            done = true
          else
            s0 = pos + 3
            s1 = close
            while s0 < s1 && source.byte_at(s0) <= 32
              s0 = s0 + 1
            while s1 > s0 && source.byte_at(s1 - 1) <= 32
              s1 = s1 - 1
            if s0 == s1
              failed = true
              done = true
            else
              name = source.slice(s0, s1 - s0)
              tokens.push(Template.make_var_tok(name, true))
              cursor = close + 3
        else
          close = -1
          j = pos + 2
          while j + 1 < n
            if source.byte_at(j) == 125 && source.byte_at(j + 1) == 125
              close = j
              j = n
            else
              j = j + 1
          if close < 0
            failed = true
            done = true
          else
            s0 = pos + 2
            s1 = close
            while s0 < s1 && source.byte_at(s0) <= 32
              s0 = s0 + 1
            while s1 > s0 && source.byte_at(s1 - 1) <= 32
              s1 = s1 - 1
            inner = ""
            if s1 > s0
              inner = source.slice(s0, s1 - s0)
            tok = Template.classify(inner)
            if tok == nil
              failed = true
              done = true
            else
              tokens.push(tok)
              cursor = close + 2
    result = tokens
    if failed
      result = nil
    result

  -> .make_name_node(base_kind, name)
    if name == "this"
      if base_kind == :open_if
        {kind: :open_if, node_kind: :if_this, sym: nil}
      else
        {kind: :open_each, node_kind: :each_this, sym: nil}
    elsif name.starts_with?("this.")
      sym = name.slice(5, name.size - 5).to_sym
      if base_kind == :open_if
        {kind: :open_if, node_kind: :if_field, sym: sym}
      else
        {kind: :open_each, node_kind: :each_field, sym: sym}
    else
      sym = name.to_sym
      if base_kind == :open_if
        {kind: :open_if, node_kind: :if, sym: sym}
      else
        {kind: :open_each, node_kind: :each, sym: sym}

  -> .make_var_tok(name, raw)
    if name == "this"
      {kind: :var_this, raw: raw}
    elsif name.starts_with?("this.")
      {kind: :var_field, sym: name.slice(5, name.size - 5).to_sym, raw: raw}
    else
      {kind: :var, sym: name.to_sym, raw: raw}

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
        tok = Template.make_name_node(:open_if, name)
    elsif inner.starts_with?("#each ")
      name = inner.slice(6, inner.size - 6).strip
      if name != ""
        tok = Template.make_name_node(:open_each, name)
    elsif inner.starts_with?(">")
      name = inner.slice(1, inner.size - 1).strip
      if name != ""
        tok = {kind: :partial, name: name}
    elsif inner.starts_with?("#") || inner.starts_with?("/")
      tok = nil
    elsif inner != ""
      tok = Template.make_var_tok(inner, false)
    tok

  # Token list -> node tree (children arrays), or nil on unclosed /
  # mismatched blocks.
  -> .parse(tokens)
    root = {kind: :root, children: []}
    stack = [root]
    failed = false
    i = 0
    while i < tokens.size
      tok = tokens[i]
      top = stack[stack.size - 1]
      kind = tok[:kind]
      if kind == :open_if || kind == :open_each
        node = {kind: tok[:node_kind], sym: tok[:sym], children: []}
        top[:children].push(node)
        stack.push(node)
      elsif kind == :close_if
        tk = top[:kind]
        if stack.size < 2 || (tk != :if && tk != :if_field && tk != :if_this)
          failed = true
        else
          stack.pop
      elsif kind == :close_each
        tk = top[:kind]
        if stack.size < 2 || (tk != :each && tk != :each_field && tk != :each_this)
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
    if !s.include?("&") && !s.include?("<") && !s.include?(">") && !s.include?("\"") && !s.include?("'")
      return s
    n = s.size
    out = []
    run_start = 0
    i = 0
    while i < n
      b = s.byte_at(i)
      if b == 38 || b == 60 || b == 62 || b == 34 || b == 39
        if i > run_start
          out.push(s.slice(run_start, i - run_start))
        if b == 38
          out.push("&amp;")
        elsif b == 60
          out.push("&lt;")
        elsif b == 62
          out.push("&gt;")
        elsif b == 34
          out.push("&quot;")
        else
          out.push("&#39;")
        run_start = i + 1
      i = i + 1
    if n > run_start
      out.push(s.slice(run_start, n - run_start))
    out.join("")

  # --- rendering ---

  # Render with a symbol-keyed params hash. Reusable: one compiled
  # Template renders any number of times with different params.
  -> render(params = {})
    out = []
    render_into(@nodes, params, nil, 0, out)
    out.join("")

  # depth bounds partial-include nesting so a self-/mutually-recursive
  # partial bottoms out at 50 levels instead of hanging the render.
  -> render_into(nodes, params, this_val, depth, out)
    n = nodes.size
    i = 0
    while i < n
      node = nodes[i]
      kind = node[:kind]
      if kind == :text
        out.push(node[:value])
      elsif kind == :var
        v = params[node[:sym]]
        if v != nil
          s = v.to_s
          if node[:raw]
            out.push(s)
          else
            out.push(Template.escape_html(s))
      elsif kind == :var_field
        if type(this_val) == "Hash"
          v = this_val[node[:sym]]
          if v != nil
            s = v.to_s
            if node[:raw]
              out.push(s)
            else
              out.push(Template.escape_html(s))
      elsif kind == :var_this
        if this_val != nil
          s = this_val.to_s
          if node[:raw]
            out.push(s)
          else
            out.push(Template.escape_html(s))
      elsif kind == :if
        v = params[node[:sym]]
        if v != nil && v != false
          render_into(node[:children], params, this_val, depth, out)
      elsif kind == :if_field
        if type(this_val) == "Hash"
          v = this_val[node[:sym]]
          if v != nil && v != false
            render_into(node[:children], params, this_val, depth, out)
      elsif kind == :if_this
        if this_val != nil && this_val != false
          render_into(node[:children], params, this_val, depth, out)
      elsif kind == :each || kind == :each_field || kind == :each_this
        v = nil
        if kind == :each
          v = params[node[:sym]]
        elsif kind == :each_field
          if type(this_val) == "Hash"
            v = this_val[node[:sym]]
        else
          v = this_val
        if type(v) == "Array"
          children = node[:children]
          vn = v.size
          j = 0
          while j < vn
            render_into(children, params, v[j], depth, out)
            j = j + 1
      elsif kind == :partial
        pt = Template.partial(node[:name])
        if pt != nil && depth < 50
          render_into(pt.nodes, params, this_val, depth + 1, out)
      i = i + 1

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
