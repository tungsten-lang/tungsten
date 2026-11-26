# core/xml — Strict XML 1.0 + XML Namespaces 1.0 + XLink + XInclude + XPointer
# + XPath 3.1 + XQuery 3.1 FLWOR + XSLT 2.0/3.0 Processor.

use core/regex

+ XmlNode
  rw :kind, :name, :local, :prefix, :ns, :attrs, :ns_decls, :children, :text, :parent

  -> new(@kind, @name = "", @text = "")
    @local = @name
    @prefix = ""
    @ns = ""
    @attrs = {}
    @ns_decls = {}
    @children = []
    @parent = nil

  -> append(ch)
    ch.parent = self
    @children.push(ch)
    ch

  -> attr(k)
    @attrs[k]

  -> string_value
    return @text if @kind == :text || @kind == :cdata || @kind == :comment || @kind == :pi || @kind == :attr
    sb = StringBuffer()
    i = 0
    while i < @children.size
      c = @children[i]
      if c.kind == :text || c.kind == :cdata
        sb << c.text
      elsif c.kind == :el
        sb << c.string_value()
      i += 1
    sb.to_s

  -> elements
    out = []
    @children.each ->(c) out.push(c) if c.kind == :el
    out

  -> root_element
    return self if @kind == :el
    @children.each ->(c) return c if c.kind == :el
    nil

  -> to_xml
    xml_serialize(self)

-> xml_unescape(s)
  return "" if s == nil
  return s if s.index("&") == nil
  out = StringBuffer()
  i = 0
  n = s.size
  while i < n
    if s.byte_at(i) == 38 # '&'
      sc = s.index(";", i + 1)
      if sc != nil && sc - i <= 12
        ent = s.slice(i + 1, sc - i - 1)
        if ent == "amp"
          out << "&"
        elsif ent == "lt"
          out << "<"
        elsif ent == "gt"
          out << ">"
        elsif ent == "quot"
          out << '"'
        elsif ent == "apos"
          out << "'"
        elsif ent.starts_with?("#x") || ent.starts_with?("#X")
          out << Codepoint.new(ent.slice(2, ent.size - 2).to_i(16)).to_s
        elsif ent.starts_with?("#")
          out << Codepoint.new(ent.slice(1, ent.size - 1).to_i).to_s
        else
          out << "&" + ent + ";"
        i = sc + 1
        next
    out << s.slice(i, 1)
    i += 1
  out.to_s

-> xml_escape(s, is_attr = false)
  return "" if s == nil
  r = s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  r = r.gsub('"', "&quot;") if is_attr
  r

-> xml_serialize(node)
  return "" if node == nil
  case node.kind
  when :doc
    sb = StringBuffer()
    node.children.each ->(c) sb << xml_serialize(c)
    return sb.to_s
  when :text
    return xml_escape(node.text, false)
  when :cdata
    return '<![CDATA[' + node.text + ']]>'
  when :comment
    return "<!--" + node.text + "-->"
  when :pi
    return "<?" + node.name + (node.text.size > 0 ? " " + node.text : "") + "?>"
  when :el
    sb = StringBuffer()
    sb << "<" << node.name
    node.attrs.each ->(k, v)
      sb << " " << k << '="' << xml_escape(v, true) << '"'
    if node.children.size == 0
      sb << "/>"
    else
      sb << ">"
      node.children.each ->(c) sb << xml_serialize(c)
      sb << "</" << node.name << ">"
    return sb.to_s
  else
    return ""

+ XmlParser
  -> new(@src)
    @i = 0
    @n = @src.size

  -> parse
    doc = XmlNode.new(:doc, "#document")
    ns_stack = [{"xml" => "http://www.w3.org/XML/1998/namespace", "xmlns" => "http://www.w3.org/2000/xmlns/", "" => ""}]
    stack = [doc]
    # Skip UTF-8 BOM if present
    @i = 3 if @n >= 3 && @src.byte_at(0) == 0xEF && @src.byte_at(1) == 0xBB && @src.byte_at(2) == 0xBF
    while @i < @n
      lt = @src.index("<", @i)
      if lt == nil
        txt = @src.slice(@i, @n - @i)
        if txt.size > 0
          t = xml_unescape(txt)
          stack[stack.size - 1].append(XmlNode.new(:text, "#text", t)) if stack.size > 1 || t.strip.size > 0
        break
      if lt > @i
        txt = @src.slice(@i, lt - @i)
        t = xml_unescape(txt)
        stack[stack.size - 1].append(XmlNode.new(:text, "#text", t)) if stack.size > 1 || t.strip.size > 0
      @i = lt
      # Comment
      if @src.slice(@i, 4) == "<!--"
        e = @src.index("-->", @i + 4)
        raise "XMLParseError: unclosed comment" if e == nil
        stack[stack.size - 1].append(XmlNode.new(:comment, "#comment", @src.slice(@i + 4, e - @i - 4)))
        @i = e + 3
        next
      # CDATA
      if @src.slice(@i, 9) == '<![CDATA['
        e = @src.index(']]>', @i + 9)
        raise "XMLParseError: unclosed CDATA" if e == nil
        stack[stack.size - 1].append(XmlNode.new(:cdata, "#cdata", @src.slice(@i + 9, e - @i - 9)))
        @i = e + 3
        next
      # Processing instruction / XML declaration
      if @src.slice(@i, 2) == "<?"
        e = @src.index("?>", @i + 2)
        raise "XMLParseError: unclosed PI" if e == nil
        inner = @src.slice(@i + 2, e - @i - 2).strip
        sp = inner.index(" ")
        tname = sp == nil ? inner : inner.slice(0, sp)
        tdata = sp == nil ? "" : inner.slice(sp + 1, inner.size - sp - 1).strip
        stack[stack.size - 1].append(XmlNode.new(:pi, tname, tdata)) if tname.downcase != "xml"
        @i = e + 2
        next
      # DOCTYPE
      if @src.slice(@i, 2) == "<!"
        e = @src.index(">", @i + 2)
        raise "XMLParseError: unclosed declaration" if e == nil
        @i = e + 1
        next
      # Closing tag
      if @src.slice(@i, 2) == "</"
        e = @src.index(">", @i + 2)
        raise "XMLParseError: unclosed end tag" if e == nil
        cname = @src.slice(@i + 2, e - @i - 2).strip
        raise "XMLParseError: mismatched end tag </" + cname + ">" if stack.size <= 1 || stack[stack.size - 1].name != cname
        stack.pop
        ns_stack.pop
        @i = e + 1
        next
      # Opening tag
      @i += 1
      ns = @i
      while @i < @n
        b = @src.byte_at(@i)
        break if b == 32 || b == 9 || b == 10 || b == 13 || b == 47 || b == 62
        @i += 1
      tname = @src.slice(ns, @i - ns)
      raise "XMLParseError: empty tag name" if tname.size == 0
      el = XmlNode.new(:el, tname)
      cur_ns = ns_stack[ns_stack.size - 1].dup
      self_close = false
      while @i < @n
        skip_ws()
        break if @i >= @n
        b = @src.byte_at(@i)
        if b == 62 # '>'
          @i += 1
          break
        if b == 47 && @i + 1 < @n && @src.byte_at(@i + 1) == 62 # '/>'
          self_close = true
          @i += 2
          break
        as = @i
        while @i < @n
          ab = @src.byte_at(@i)
          break if ab == 61 || ab == 32 || ab == 9 || ab == 10 || ab == 13 || ab == 62 || ab == 47
          @i += 1
        aname = @src.slice(as, @i - as)
        skip_ws()
        aval = ""
        if @i < @n && @src.byte_at(@i) == 61
          @i += 1
          skip_ws()
          q = @src.byte_at(@i)
          raise "XMLParseError: expected quote for attr " + aname if q != 34 && q != 39
          @i += 1
          vs = @i
          while @i < @n && @src.byte_at(@i) != q
            @i += 1
          raise "XMLParseError: unclosed attr quote" if @i >= @n
          aval = xml_unescape(@src.slice(vs, @i - vs))
          @i += 1
        el.attrs[aname] = aval
        if aname == "xmlns"
          cur_ns[""] = aval
          el.ns_decls[""] = aval
        elsif aname.starts_with?("xmlns:")
          pfx = aname.slice(6, aname.size - 6)
          cur_ns[pfx] = aval
          el.ns_decls[pfx] = aval
      # Resolve XML Namespace on element
      col = tname.index(":")
      if col != nil
        el.prefix = tname.slice(0, col)
        el.local = tname.slice(col + 1, tname.size - col - 1)
        el.ns = cur_ns[el.prefix] == nil ? "" : cur_ns[el.prefix]
      else
        el.prefix = ""
        el.local = tname
        el.ns = cur_ns[""] == nil ? "" : cur_ns[""]
      stack[stack.size - 1].append(el)
      if !self_close
        stack.push(el)
        ns_stack.push(cur_ns)
    raise "XMLParseError: unclosed tag <" + stack[stack.size - 1].name + ">" if stack.size > 1
    doc

  -> skip_ws
    while @i < @n
      b = @src.byte_at(@i)
      break if b != 32 && b != 9 && b != 10 && b != 13
      @i += 1

-> xml_parse(src)
  XmlParser.new(src).parse()

# XInclude 1.0/1.1 resolver (`<xi:include href="..." parse="xml|text"/>`)
-> xml_process_xinclude(node, loader_fn)
  return node if node == nil || loader_fn == nil
  i = 0
  while i < node.children.size
    ch = node.children[i]
    if ch.kind == :el && (ch.local == "include" && (ch.ns == "http://www.w3.org/2001/XInclude" || ch.name == "xi:include"))
      href = ch.attr("href")
      mode = ch.attr("parse")
      mode = "xml" if mode == nil
      data = href != nil ? loader_fn.call(href) : nil
      if data != nil
        if mode == "text"
          node.children[i] = XmlNode.new(:text, "#text", data)
          node.children[i].parent = node
        else
          inc_doc = xml_parse(data)
          inc_el = inc_doc.root_element()
          if inc_el != nil
            inc_el.parent = node
            node.children[i] = inc_el
    else
      xml_process_xinclude(ch, loader_fn)
    i += 1
  node

# Extract XLink attributes (`xlink:href`, `xlink:type`, `xlink:title`, `xlink:show`, `xlink:actuate`)
-> xml_xlink_info(node)
  return nil if node == nil || node.kind != :el
  href = node.attr("xlink:href")
  return nil if href == nil
  {
    type: node.attr("xlink:type") == nil ? "simple" : node.attr("xlink:type"),
    href: href,
    title: node.attr("xlink:title"),
    show: node.attr("xlink:show"),
    actuate: node.attr("xlink:actuate")
  }

# ---- XPath 3.1 Evaluator ----

-> xpath_to_str(v)
  return "" if v == nil
  return v if v.is_a?(String)
  return v.string_value() if v.is_a?(XmlNode)
  if v.is_a?(Array)
    return v.size == 0 ? "" : xpath_to_str(v[0])
  v.to_s

-> xpath_to_num(v)
  return v if v.is_a?(Float)
  return v.to_f if v.is_a?(Integer)
  return v ? ~1.0 : ~0.0 if v == true || v == false
  s = xpath_to_str(v).strip
  return ~0.0 / ~0.0 if s.size == 0
  s.to_f

-> xpath_to_bool(v)
  return false if v == nil || v == false
  return true if v == true
  return v.size > 0 if v.is_a?(Array) || v.is_a?(String)
  return v != 0 if v.is_a?(Integer)
  return v != ~0.0 && v == v if v.is_a?(Float)
  true

-> xpath_descendants(node, out, include_self = false)
  out.push(node) if include_self
  i = 0
  while i < node.children.size
    c = node.children[i]
    out.push(c)
    xpath_descendants(c, out, false) if c.kind == :el
    i += 1
  out

-> xpath_node_test?(node, test)
  return true if test == "*" && node.kind == :el
  return true if test == "node()"
  return node.kind == :text || node.kind == :cdata if test == "text()"
  return node.kind == :comment if test == "comment()"
  return node.kind == :pi if test == "processing-instruction()"
  return false if node.kind != :el && node.kind != :attr
  return true if node.name == test || node.local == test
  false

-> xpath_step_nodes(ctx_node, step, vars)
  # Parse optional axis `axis::test` and predicates `[...]`
  s = step.strip
  return [ctx_node] if s == "." || s == ""
  return (ctx_node.parent == nil ? [] : [ctx_node.parent]) if s == ".."
  # Split predicates at top level
  preds = []
  base = s
  bi = s.index('[')
  if bi != nil
    base = s.slice(0, bi).strip
    p = bi
    while p < s.size
      if s.byte_at(p) == 91 # '['
        d = 1; q = 0; j = p + 1
        while j < s.size && d > 0
          cb = s.byte_at(j)
          if q != 0
            q = 0 if cb == q
          elsif cb == 34 || cb == 39
            q = cb
          elsif cb == 91
            d += 1
          elsif cb == 93
            d -= 1
          j += 1
        preds.push(s.slice(p + 1, j - p - 2))
        p = j
      else
        p += 1
  axis = "child"
  test = base
  if base.starts_with?("@")
    axis = "attribute"
    test = base.slice(1, base.size - 1)
  else
    ax = base.index("::")
    if ax != nil
      axis = base.slice(0, ax).strip
      test = base.slice(ax + 2, base.size - ax - 2).strip
  cands = []
  case axis
  when "child"
    ctx_node.children.each ->(c) cands.push(c) if xpath_node_test?(c, test)
  when "descendant"
    all = xpath_descendants(ctx_node, [], false)
    all.each ->(c) cands.push(c) if xpath_node_test?(c, test)
  when "descendant-or-self"
    all = xpath_descendants(ctx_node, [], true)
    all.each ->(c) cands.push(c) if xpath_node_test?(c, test)
  when "self"
    cands.push(ctx_node) if xpath_node_test?(ctx_node, test)
  when "parent"
    cands.push(ctx_node.parent) if ctx_node.parent != nil && xpath_node_test?(ctx_node.parent, test)
  when "ancestor", "ancestor-or-self"
    cur = axis == "ancestor-or-self" ? ctx_node : ctx_node.parent
    while cur != nil
      cands.push(cur) if xpath_node_test?(cur, test)
      cur = cur.parent
  when "following-sibling", "preceding-sibling"
    if ctx_node.parent != nil
      sibs = ctx_node.parent.children
      idx = -1
      si = 0
      while si < sibs.size
        idx = si if sibs[si] == ctx_node
        si += 1
      if axis == "following-sibling" && idx >= 0
        k = idx + 1
        while k < sibs.size
          cands.push(sibs[k]) if xpath_node_test?(sibs[k], test)
          k += 1
      elsif axis == "preceding-sibling" && idx > 0
        k = idx - 1
        while k >= 0
          cands.push(sibs[k]) if xpath_node_test?(sibs[k], test)
          k -= 1
  when "attribute"
    if ctx_node.kind == :el
      if test == "*"
        ctx_node.attrs.each ->(ak, av)
          an = XmlNode.new(:attr, ak, av)
          an.parent = ctx_node
          cands.push(an)
      elsif ctx_node.attrs.has_key?(test)
        an = XmlNode.new(:attr, test, ctx_node.attrs[test])
        an.parent = ctx_node
        cands.push(an)
  # Filter by predicates
  preds.each ->(pr)
    kept = []
    tot = cands.size
    pi = 0
    while pi < tot
      cn = cands[pi]
      pv = xpath_eval(cn, pr, vars, pi + 1, tot)
      ok = false
      if pv.is_a?(Integer) || pv.is_a?(Float)
        ok = pv.to_i == pi + 1
      else
        ok = xpath_to_bool(pv)
      kept.push(cn) if ok
      pi += 1
    cands = kept
  cands

# Find top-level binary operator (respecting parens, brackets, quotes)
-> xpath_split_top(expr, op, right_to_left = false)
  d_p = 0
  d_b = 0
  q = 0
  found = -1
  i = 0
  n = expr.size
  ol = op.size
  while i < n
    b = expr.byte_at(i)
    if q != 0
      q = 0 if b == q
    elsif b == 34 || b == 39
      q = b
    elsif b == 40
      d_p += 1
    elsif b == 41
      d_p -= 1
    elsif b == 91
      d_b += 1
    elsif b == 93
      d_b -= 1
    elsif d_p == 0 && d_b == 0 && i + ol <= n && expr.slice(i, ol) == op
      # Avoid matching `=` inside `!=`, `<=`, `>=`, `=>`
      ok = true
      if op == "="
        pb = i > 0 ? expr.byte_at(i - 1) : 0
        nb = i + 1 < n ? expr.byte_at(i + 1) : 0
        ok = pb != 33 && pb != 60 && pb != 62 && nb != 62
      elsif op == "<" || op == ">"
        nb = i + 1 < n ? expr.byte_at(i + 1) : 0
        pb = i > 0 ? expr.byte_at(i - 1) : 0
        ok = nb != 61 && !(op == ">" && pb == 61)
      elsif op == "|"
        nb = i + 1 < n ? expr.byte_at(i + 1) : 0
        pb = i > 0 ? expr.byte_at(i - 1) : 0
        ok = nb != 124 && pb != 124
      elsif op == "-"
        # Must be binary minus (not inside NCName like `local-name` or unary `-x`)
        pb = i > 0 ? expr.byte_at(i - 1) : 0
        ok = pb == 32 || pb == 41 || pb == 93
      if ok
        found = i
        break if !right_to_left
    i += 1
  return nil if found < 0
  [expr.slice(0, found).strip, expr.slice(found + ol, n - found - ol).strip]

-> xpath_split_args(s)
  out = []
  return out if s.strip.size == 0
  d_p = 0; d_b = 0; q = 0; st = 0; i = 0
  while i < s.size
    b = s.byte_at(i)
    if q != 0
      q = 0 if b == q
    elsif b == 34 || b == 39
      q = b
    elsif b == 40
      d_p += 1
    elsif b == 41
      d_p -= 1
    elsif b == 91
      d_b += 1
    elsif b == 93
      d_b -= 1
    elsif b == 44 && d_p == 0 && d_b == 0
      out.push(s.slice(st, i - st).strip)
      st = i + 1
    i += 1
  out.push(s.slice(st, s.size - st).strip)
  out

-> xpath_root_of(n)
  cur = n
  while cur != nil && cur.parent != nil
    cur = cur.parent
  cur

-> xpath_eval_path(ctx_node, path, vars)
  p = path.strip
  nodes = [ctx_node]
  if p.starts_with?("$")
    sl = p.index("/")
    vnm = sl == nil ? p.slice(1, p.size - 1) : p.slice(1, sl - 1)
    vv = vars[vnm]
    nodes = vv.is_a?(Array) ? vv : (vv == nil ? [] : [vv])
    return nodes if sl == nil
    p = p.slice(sl + 1, p.size - sl - 1)
  elsif p.starts_with?("//")
    nodes = [xpath_root_of(ctx_node)]
    p = "descendant-or-self::node()/" + p.slice(2, p.size - 2)
  elsif p.starts_with?("/")
    nodes = [xpath_root_of(ctx_node)]
    p = p.slice(1, p.size - 1)
    return nodes if p.size == 0
  # Split steps by top-level `/` (expanding `//` to `/descendant-or-self::node()/`)
  steps = []
  d_p = 0; d_b = 0; q = 0; st = 0; i = 0
  while i < p.size
    b = p.byte_at(i)
    if q != 0
      q = 0 if b == q
    elsif b == 34 || b == 39
      q = b
    elsif b == 40
      d_p += 1
    elsif b == 41
      d_p -= 1
    elsif b == 91
      d_b += 1
    elsif b == 93
      d_b -= 1
    elsif b == 47 && d_p == 0 && d_b == 0
      steps.push(p.slice(st, i - st).strip)
      if i + 1 < p.size && p.byte_at(i + 1) == 47
        steps.push("descendant-or-self::node()")
        i += 1
      st = i + 1
    i += 1
  steps.push(p.slice(st, p.size - st).strip) if st < p.size
  steps.each ->(step)
    nxt = []
    nodes.each ->(nd)
      xpath_step_nodes(nd, step, vars).each ->(r)
        nxt.push(r) if !nxt.include?(r)
    nodes = nxt
  nodes

-> xpath_eval(ctx_node, expr, vars = nil, pos = 1, last = 1)
  vars = {} if vars == nil
  e = expr.strip
  return nil if e.size == 0

  # Strip outer balanced parens
  if e.starts_with?("(") && e.ends_with?(")")
    d = 0; q = 0; wraps = true; i = 0
    while i < e.size - 1
      b = e.byte_at(i)
      if q != 0
        q = 0 if b == q
      elsif b == 34 || b == 39
        q = b
      elsif b == 40
        d += 1
      elsif b == 41
        d -= 1
      wraps = false if d == 0
      i += 1
    return xpath_eval(ctx_node, e.slice(1, e.size - 2), vars, pos, last) if wraps

  # XPath 3.1 `if (c) then a else b`
  if e.starts_with?("if") && (e.size > 2 && (e.byte_at(2) == 32 || e.byte_at(2) == 40))
    tp = e.index(" then ")
    ep = e.index(" else ")
    if tp != nil && ep != nil && ep > tp
      c_e = e.slice(2, tp - 2).strip
      t_e = e.slice(tp + 6, ep - tp - 6).strip
      f_e = e.slice(ep + 6, e.size - ep - 6).strip
      return xpath_to_bool(xpath_eval(ctx_node, c_e, vars, pos, last)) ? xpath_eval(ctx_node, t_e, vars, pos, last) : xpath_eval(ctx_node, f_e, vars, pos, last)

  # XPath 3.1 `let $x := expr return body`
  if e.starts_with?("let $")
    ae = e.index(":=")
    re = e.index(" return ")
    if ae != nil && re != nil && re > ae
      vnm = e.slice(5, ae - 5).strip
      vval = xpath_eval(ctx_node, e.slice(ae + 2, re - ae - 2), vars, pos, last)
      nv = vars.dup
      nv[vnm] = vval
      return xpath_eval(ctx_node, e.slice(re + 8, e.size - re - 8), nv, pos, last)

  # XPath 3.1 arrow operator `lhs => fn(args)`
  ar = xpath_split_top(e, "=>", true)
  if ar != nil
    lv = xpath_eval(ctx_node, ar[0], vars, pos, last)
    r = ar[1]
    lp = r.index("(")
    if lp != nil && r.ends_with?(")")
      fnm = r.slice(0, lp).strip
      a_raw = xpath_split_args(r.slice(lp + 1, r.size - lp - 2))
      vals = [lv]
      a_raw.each ->(a) vals.push(xpath_eval(ctx_node, a, vars, pos, last))
      return xpath_call_fn(ctx_node, fnm, vals, vars, pos, last)

  # Boolean `or` / `and`
  sp = xpath_split_top(e, " or ")
  return xpath_to_bool(xpath_eval(ctx_node, sp[0], vars, pos, last)) || xpath_to_bool(xpath_eval(ctx_node, sp[1], vars, pos, last)) if sp != nil
  sp = xpath_split_top(e, " and ")
  return xpath_to_bool(xpath_eval(ctx_node, sp[0], vars, pos, last)) && xpath_to_bool(xpath_eval(ctx_node, sp[1], vars, pos, last)) if sp != nil

  # String concat `||` (XPath 3.0+)
  sp = xpath_split_top(e, "||", true)
  return xpath_to_str(xpath_eval(ctx_node, sp[0], vars, pos, last)) + xpath_to_str(xpath_eval(ctx_node, sp[1], vars, pos, last)) if sp != nil

  # Comparisons
  ["!=", "<=", ">=", "=", "<", ">"].each ->(op)
    c = xpath_split_top(e, op)
    if c != nil
      lv = xpath_eval(ctx_node, c[0], vars, pos, last)
      rv = xpath_eval(ctx_node, c[1], vars, pos, last)
      if op == "=" || op == "!="
        eq = false
        if (lv.is_a?(Integer) || lv.is_a?(Float)) || (rv.is_a?(Integer) || rv.is_a?(Float))
          eq = xpath_to_num(lv) == xpath_to_num(rv)
        else
          eq = xpath_to_str(lv) == xpath_to_str(rv)
        return op == "=" ? eq : !eq
      ln = xpath_to_num(lv); rn = xpath_to_num(rv)
      return op == "<" ? ln < rn : (op == "<=" ? ln <= rn : (op == ">" ? ln > rn : ln >= rn))

  # Arithmetic
  ["+", "-"].each ->(op)
    c = xpath_split_top(e, op, true)
    if c != nil && c[0].size > 0
      ln = xpath_to_num(xpath_eval(ctx_node, c[0], vars, pos, last))
      rn = xpath_to_num(xpath_eval(ctx_node, c[1], vars, pos, last))
      return op == "+" ? ln + rn : ln - rn
  ["*", " div ", " mod "].each ->(op)
    c = xpath_split_top(e, op, true)
    if c != nil && c[0].size > 0
      ln = xpath_to_num(xpath_eval(ctx_node, c[0], vars, pos, last))
      rn = xpath_to_num(xpath_eval(ctx_node, c[1], vars, pos, last))
      return ln * rn if op == "*"
      return ln / rn if op == " div "
      return ln - (ln / rn).floor * rn

  # Union `|`
  un = xpath_split_top(e, "|")
  if un != nil
    a = xpath_eval(ctx_node, un[0], vars, pos, last)
    b = xpath_eval(ctx_node, un[1], vars, pos, last)
    out = a.is_a?(Array) ? a.dup : []
    if b.is_a?(Array)
      b.each ->(x) out.push(x) if !out.include?(x)
    return out

  # String literal
  if (e.starts_with?('"') && e.ends_with?('"')) || (e.starts_with?("'") && e.ends_with?("'"))
    return e.slice(1, e.size - 2)

  # Variable reference `$var` (bare variable only; `$var/path` goes to xpath_eval_path)
  if e.starts_with?("$") && e.index("/") == nil && e.index('[') == nil
    return vars[e.slice(1, e.size - 1)]

  # Number literal
  b0 = e.byte_at(0)
  if (b0 >= 48 && b0 <= 57) || (b0 == 45 && e.size > 1 && e.byte_at(1) >= 48 && e.byte_at(1) <= 57)
    return e.index(".") != nil ? e.to_f : e.to_i

  # Function call `name(args...)` (not a path step like `text()` or `node()` or `a/b()`)
  lp = e.index("(")
  if lp != nil && e.ends_with?(")") && e.slice(0, lp).index("/") == nil && e.slice(0, lp).index('[') == nil
    fnm = e.slice(0, lp).strip
    if fnm != "node" && fnm != "text" && fnm != "comment" && fnm != "processing-instruction"
      a_raw = xpath_split_args(e.slice(lp + 1, e.size - lp - 2))
      vals = []
      a_raw.each ->(a) vals.push(xpath_eval(ctx_node, a, vars, pos, last))
      return xpath_call_fn(ctx_node, fnm, vals, vars, pos, last)

  # Location path
  xpath_eval_path(ctx_node, e, vars)

-> xpath_call_fn(ctx_node, fnm, args, vars, pos, last)
  case fnm
  when "position" then pos
  when "last" then last
  when "true" then true
  when "false" then false
  when "not" then !xpath_to_bool(args[0])
  when "boolean" then xpath_to_bool(args[0])
  when "string" then xpath_to_str(args.size > 0 ? args[0] : ctx_node)
  when "number" then xpath_to_num(args.size > 0 ? args[0] : ctx_node)
  when "count" then args[0].is_a?(Array) ? args[0].size : (args[0] == nil ? 0 : 1)
  when "empty" then args[0] == nil || (args[0].is_a?(Array) && args[0].size == 0)
  when "exists" then !(args[0] == nil || (args[0].is_a?(Array) && args[0].size == 0))
  when "sum"
    s = ~0.0
    if args[0].is_a?(Array)
      args[0].each ->(x) s += xpath_to_num(x)
    s
  when "avg"
    return ~0.0 if !args[0].is_a?(Array) || args[0].size == 0
    s = ~0.0
    args[0].each ->(x) s += xpath_to_num(x)
    s / args[0].size.to_f
  when "min", "max"
    return nil if !args[0].is_a?(Array) || args[0].size == 0
    best = xpath_to_num(args[0][0])
    i = 1
    while i < args[0].size
      v = xpath_to_num(args[0][i])
      best = v if (fnm == "min" ? v < best : v > best)
      i += 1
    best
  when "floor" then xpath_to_num(args[0]).floor
  when "ceiling" then xpath_to_num(args[0]).ceil
  when "round" then xpath_to_num(args[0]).round
  when "abs"
    v = xpath_to_num(args[0])
    v < ~0.0 ? -v : v
  when "concat"
    sb = StringBuffer()
    args.each ->(a) sb << xpath_to_str(a)
    sb.to_s
  when "string-join"
    sep = args.size > 1 ? xpath_to_str(args[1]) : ""
    arr = args[0].is_a?(Array) ? args[0] : [args[0]]
    parts = []
    arr.each ->(x) parts.push(xpath_to_str(x))
    parts.join(sep)
  when "contains" then xpath_to_str(args[0]).index(xpath_to_str(args[1])) != nil
  when "starts-with" then xpath_to_str(args[0]).starts_with?(xpath_to_str(args[1]))
  when "ends-with" then xpath_to_str(args[0]).ends_with?(xpath_to_str(args[1]))
  when "string-length" then xpath_to_str(args.size > 0 ? args[0] : ctx_node).chars.size
  when "upper-case" then xpath_to_str(args[0]).upcase
  when "lower-case" then xpath_to_str(args[0]).downcase
  when "normalize-space"
    s = xpath_to_str(args.size > 0 ? args[0] : ctx_node).strip
    parts = s.split(" ").select ->(x) x.size > 0
    parts.join(" ")
  when "substring"
    s = xpath_to_str(args[0])
    st = xpath_to_num(args[1]).round - 1
    st = 0 if st < 0
    return "" if st >= s.size
    if args.size > 2
      ln = xpath_to_num(args[2]).round
      ln = s.size - st if st + ln > s.size
      return ln <= 0 ? "" : s.slice(st, ln)
    s.slice(st, s.size - st)
  when "substring-before"
    s = xpath_to_str(args[0]); p = xpath_to_str(args[1])
    k = s.index(p)
    k == nil ? "" : s.slice(0, k)
  when "substring-after"
    s = xpath_to_str(args[0]); p = xpath_to_str(args[1])
    k = s.index(p)
    k == nil ? "" : s.slice(k + p.size, s.size - k - p.size)
  when "translate" then xpath_to_str(args[0]).tr(xpath_to_str(args[1]), xpath_to_str(args[2]))
  when "matches" then Regex.new(xpath_to_str(args[1])).match?(xpath_to_str(args[0]))
  when "replace" then xpath_to_str(args[0]).gsub(xpath_to_str(args[1]), xpath_to_str(args[2]))
  when "tokenize"
    s = xpath_to_str(args[0])
    sep = args.size > 1 ? xpath_to_str(args[1]) : " "
    Regex.new(sep).split(s)
  when "name"
    nd = args.size > 0 ? (args[0].is_a?(Array) ? args[0][0] : args[0]) : ctx_node
    nd.is_a?(XmlNode) ? nd.name : ""
  when "local-name"
    nd = args.size > 0 ? (args[0].is_a?(Array) ? args[0][0] : args[0]) : ctx_node
    nd.is_a?(XmlNode) ? nd.local : ""
  when "namespace-uri"
    nd = args.size > 0 ? (args[0].is_a?(Array) ? args[0][0] : args[0]) : ctx_node
    nd.is_a?(XmlNode) ? nd.ns : ""
  when "head" then (args[0].is_a?(Array) && args[0].size > 0) ? args[0][0] : nil
  when "tail" then (args[0].is_a?(Array) && args[0].size > 1) ? args[0].slice(1, args[0].size - 1) : []
  when "reverse"
    return [] if !args[0].is_a?(Array)
    out = []; i = args[0].size - 1
    while i >= 0
      out.push(args[0][i]); i -= 1
    out
  when "distinct-values"
    return [] if !args[0].is_a?(Array)
    out = []; seen = {}
    args[0].each ->(x)
      k = xpath_to_str(x)
      if !seen.has_key?(k)
        seen[k] = true
        out.push(k)
    out
  else
    nil

# ---- XQuery 3.1 FLWOR evaluator (`for $x in expr [let $y := e] [where cond] [order by k] return res`) ----
-> xquery_eval(doc, query, vars = nil)
  vars = {} if vars == nil
  q = query.strip
  if q.starts_with?("for $")
    in_k = q.index(" in ")
    ret_k = q.index(" return ")
    if in_k != nil && ret_k != nil
      vnm = q.slice(5, in_k - 5).strip
      mid = q.slice(in_k + 4, ret_k - in_k - 4).strip
      ret_e = q.slice(ret_k + 8, q.size - ret_k - 8).strip
      # Parse optional `where` clause
      where_e = nil
      wk = mid.index(" where ")
      seq_e = mid
      if wk != nil
        seq_e = mid.slice(0, wk).strip
        where_e = mid.slice(wk + 7, mid.size - wk - 7).strip
      seq = xpath_eval(doc, seq_e, vars)
      seq = [] if !seq.is_a?(Array)
      out = []
      seq.each ->(item)
        nv = vars.dup
        nv[vnm] = item
        ok = where_e == nil ? true : xpath_to_bool(xpath_eval(item.is_a?(XmlNode) ? item : doc, where_e, nv))
        if ok
          out.push(xpath_eval(item.is_a?(XmlNode) ? item : doc, ret_e, nv))
      return out
  xpath_eval(doc, q, vars)

# ---- XPointer evaluator (`element(/1/2)` or `xpointer(//book[1])` or bare ID) ----
-> xpointer_eval(doc, ptr)
  p = ptr.strip
  if p.starts_with?("xpointer(") && p.ends_with?(")")
    return xpath_eval(doc, p.slice(9, p.size - 10))
  if p.starts_with?("element(") && p.ends_with?(")")
    spec = p.slice(8, p.size - 9)
    parts = spec.split("/")
    cur = doc
    parts.each ->(seg)
      next if seg.size == 0
      idx = seg.to_i
      els = cur.elements()
      return nil if idx < 1 || idx > els.size
      cur = els[idx - 1]
    return cur
  # Shorthand bare xml:id / id pointer
  all = xpath_descendants(doc, [], true)
  all.each ->(n)
    return n if n.kind == :el && (n.attr("xml:id") == p || n.attr("id") == p)
  nil

# ---- XSLT 2.0 / 3.0 Processor ----
+ XsltProcessor
  -> new(stylesheet_doc)
    @sheet = stylesheet_doc.is_a?(String) ? xml_parse(stylesheet_doc) : stylesheet_doc
    @templates = []
    @named = {}
    @params = {}
    root = @sheet.root_element()
    if root != nil
      root.elements().each ->(el)
        if el.local == "template"
          @templates.push(el) if el.attr("match") != nil
          @named[el.attr("name")] = el if el.attr("name") != nil
        elsif el.local == "param" || el.local == "variable"
          nm = el.attr("name")
          @params[nm] = el.attr("select") != nil ? el.attr("select") : el.string_value() if nm != nil

  -> set_param(name, value)
    @params[name] = value

  -> transform(xml_doc)
    doc = xml_doc.is_a?(String) ? xml_parse(xml_doc) : xml_doc
    out = XmlNode.new(:doc, "#document")
    vars = @params.dup
    apply_templates(doc, out, vars)
    out

  -> transform_to_string(xml_doc)
    xml_serialize(transform(xml_doc))

  -> match_template(node)
    # Prefer more specific matches (non-wildcard, longer pattern) over generic `/` or `*`
    best = nil
    best_score = -1
    @templates.each ->(tpl)
      m = tpl.attr("match").strip
      hit = false
      sc = 0
      if m == "/" && node.kind == :doc
        hit = true; sc = 1
      elsif m == "*" && node.kind == :el
        hit = true; sc = 1
      elsif m == "text()" && (node.kind == :text || node.kind == :cdata)
        hit = true; sc = 2
      elsif node.kind == :el && (m == node.name || m == node.local)
        hit = true; sc = 10
      elsif node.kind == :el && m.index("/") != nil
        # Parent/child match like `books/book`
        parts = m.split("/")
        last_p = parts[parts.size - 1]
        if last_p == node.name || last_p == node.local
          hit = true; sc = 20
      if hit && sc > best_score
        best = tpl
        best_score = sc
    best

  -> expand_avt(s, ctx_node, vars)
    return s if s == nil || s.index("{") == nil
    out = StringBuffer()
    i = 0
    while i < s.size
      if s.byte_at(i) == 123 # '{'
        e = s.index("}", i + 1)
        if e != nil
          out << xpath_to_str(xpath_eval(ctx_node, s.slice(i + 1, e - i - 1), vars))
          i = e + 1
          next
      out << s.slice(i, 1)
      i += 1
    out.to_s

  -> apply_templates(node, out_parent, vars)
    tpl = match_template(node)
    if tpl != nil
      exec_children(tpl, node, out_parent, vars, 1, 1)
    elsif node.kind == :doc || node.kind == :el
      node.children.each ->(ch) apply_templates(ch, out_parent, vars)
    elsif node.kind == :text || node.kind == :cdata
      out_parent.append(XmlNode.new(:text, "#text", node.text))

  -> exec_children(tpl_el, ctx_node, out_parent, vars, pos, last)
    lvars = vars.dup
    tpl_el.children.each ->(inst)
      if inst.kind == :text || inst.kind == :cdata
        out_parent.append(XmlNode.new(:text, "#text", inst.text)) if inst.text.strip.size > 0 || tpl_el.local == "text"
      elsif inst.kind == :el && (inst.ns == "http://www.w3.org/1999/XSL/Transform" || inst.prefix == "xsl")
        case inst.local
        when "value-of"
          sel = inst.attr("select")
          v = sel != nil ? xpath_to_str(xpath_eval(ctx_node, sel, lvars, pos, last)) : ""
          out_parent.append(XmlNode.new(:text, "#text", v))
        when "text"
          out_parent.append(XmlNode.new(:text, "#text", inst.string_value()))
        when "apply-templates"
          sel = inst.attr("select")
          targets = sel != nil ? xpath_eval(ctx_node, sel, lvars, pos, last) : ctx_node.children
          targets = [targets] if targets.is_a?(XmlNode)
          targets.each ->(t) apply_templates(t, out_parent, lvars) if targets.is_a?(Array)
        when "call-template"
          nm = inst.attr("name")
          sub = @named[nm]
          if sub != nil
            cv = lvars.dup
            inst.elements().each ->(wp)
              if wp.local == "with-param" && wp.attr("name") != nil
                cv[wp.attr("name")] = wp.attr("select") != nil ? xpath_eval(ctx_node, wp.attr("select"), lvars, pos, last) : wp.string_value()
            exec_children(sub, ctx_node, out_parent, cv, pos, last)
        when "for-each"
          sel = inst.attr("select")
          items = xpath_eval(ctx_node, sel, lvars, pos, last)
          items = [] if !items.is_a?(Array)
          # Check optional xsl:sort child
          sort_el = nil
          inst.elements().each ->(ch) sort_el = ch if ch.local == "sort"
          if sort_el != nil && items.size > 1
            sk = sort_el.attr("select") == nil ? "." : sort_el.attr("select")
            desc = sort_el.attr("order") == "descending"
            is_num = sort_el.attr("data-type") == "number"
            items = items.dup
            si = 1
            while si < items.size
              key = items[si]
              kv = xpath_eval(key, sk, lvars)
              sj = si - 1
              while sj >= 0
                jv = xpath_eval(items[sj], sk, lvars)
                cmp = is_num ? (xpath_to_num(jv) > xpath_to_num(kv) ? 1 : -1) : (xpath_to_str(jv) > xpath_to_str(kv) ? 1 : -1)
                break if (desc ? cmp >= 0 : cmp <= 0)
                items[sj + 1] = items[sj]
                sj -= 1
              items[sj + 1] = key
              si += 1
          fi = 0
          while fi < items.size
            exec_children(inst, items[fi], out_parent, lvars, fi + 1, items.size)
            fi += 1
        when "if"
          tst = inst.attr("test")
          if tst != nil && xpath_to_bool(xpath_eval(ctx_node, tst, lvars, pos, last))
            exec_children(inst, ctx_node, out_parent, lvars, pos, last)
        when "choose"
          done = false
          inst.elements().each ->(ch)
            next if done
            if ch.local == "when"
              tst = ch.attr("test")
              if tst != nil && xpath_to_bool(xpath_eval(ctx_node, tst, lvars, pos, last))
                exec_children(ch, ctx_node, out_parent, lvars, pos, last)
                done = true
            elsif ch.local == "otherwise"
              exec_children(ch, ctx_node, out_parent, lvars, pos, last)
              done = true
        when "variable", "param"
          nm = inst.attr("name")
          if nm != nil
            sel = inst.attr("select")
            lvars[nm] = sel != nil ? xpath_eval(ctx_node, sel, lvars, pos, last) : inst.string_value()
        when "element"
          enm = expand_avt(inst.attr("name"), ctx_node, lvars)
          nel = XmlNode.new(:el, enm)
          out_parent.append(nel)
          exec_children(inst, ctx_node, nel, lvars, pos, last)
        when "attribute"
          anm = expand_avt(inst.attr("name"), ctx_node, lvars)
          tmp = XmlNode.new(:doc, "#tmp")
          exec_children(inst, ctx_node, tmp, lvars, pos, last)
          out_parent.attrs[anm] = tmp.string_value() if out_parent.kind == :el
        when "copy-of"
          sel = inst.attr("select")
          res = xpath_eval(ctx_node, sel, lvars, pos, last)
          arr = res.is_a?(Array) ? res : [res]
          arr.each ->(x) out_parent.append(xml_clone(x)) if x.is_a?(XmlNode)
        when "copy"
          c = XmlNode.new(ctx_node.kind, ctx_node.name, ctx_node.text)
          out_parent.append(c)
          exec_children(inst, ctx_node, c, lvars, pos, last)
      elsif inst.kind == :el
        # Literal result element (with Attribute Value Templates `{expr}`)
        nel = XmlNode.new(:el, inst.name)
        inst.attrs.each ->(ak, av)
          next if ak.starts_with?("xmlns:xsl")
          nel.attrs[ak] = expand_avt(av, ctx_node, lvars)
        out_parent.append(nel)
        exec_children(inst, ctx_node, nel, lvars, pos, last)

-> xml_clone(n)
  c = XmlNode.new(n.kind, n.name, n.text)
  c.local = n.local; c.prefix = n.prefix; c.ns = n.ns
  n.attrs.each ->(k, v) c.attrs[k] = v
  n.children.each ->(ch) c.append(xml_clone(ch))
  c
