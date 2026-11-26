# fnstats — corpus statistics for the analysis (PLAN.md M1 scale check):
#
#   fnstats file.js...
#
# Per corpus: functions by function-value class (PLAN.md 3.9), how many need no
# environment, scopes with and without an environment record, the constructs the slice
# cannot compile yet (counts per reason), and the own-property counts of object literals
# and of constructors (distinct `this.x =` names per function).

use ../frontend/parser
use ../analyze

TOT = {funcs: 0, call_only: 0, iife: 0, escaping: 0, no_captures: 0, single: 0, unsupported: 0, dynamic: 0}
REASONS = {}
SCOPES = [0, 0]
LIT_HIST = {}
CTOR_HIST = {}

-> hist_add(h, n)
  k = n > 16 ? 17 : n
  h[k] = (h[k] == nil ? 0 : h[k]) + 1
  nil

# Object literal sizes and `this.x =` names per function, by walking the AST.
-> walk_counts(n, this_names)
  return nil if n == nil
  return nil if !n.is_a?(JsNode)
  k = n.kind
  if k == :object
    hist_add(LIT_HIST, n.list.size)
  if (k == :function || k == :function_decl) && n.b.is_a?(Array)
    names = {}
    n.b.each ->(s) walk_counts(s, names)
    n.list.each ->(p) walk_counts(p, names)
    hist_add(CTOR_HIST, names.size) if names.size > 0
    return nil
  if k == :assign && n.a != nil && n.a.kind == :member && n.a.a != nil && n.a.a.kind == :this && !n.a.has?(F_COMPUTED)
    this_names[n.a.b.str] = true if this_names != nil
  walk_counts(n.a, this_names) if n.a.is_a?(JsNode)
  walk_counts(n.b, this_names) if n.b.is_a?(JsNode)
  walk_counts(n.c, this_names) if n.c.is_a?(JsNode)
  walk_counts(n.d, this_names) if n.d.is_a?(JsNode)
  [n.a, n.b, n.c, n.list].each ->(x)
    if x.is_a?(Array)
      x.each ->(y) walk_counts(y, this_names) if y.is_a?(JsNode)
  nil

-> count_scopes(an)
  seen = {}
  an.funcs.each ->(f)
    s = f.scope
    if s != nil && !seen.has_key?(s.id)
      seen[s.id] = true
      SCOPES[s.has_env? ? 1 : 0] = SCOPES[s.has_env? ? 1 : 0] + 1
  nil

-> fmt_hist(h)
  out = []
  i = 0
  while i <= 17
    out.push((i == 17 ? ">16" : i.to_s) + ":" + h[i].to_s) if h[i] != nil
    i += 1
  out.join(" ")

files = ARGV
t0 = clock_ms()
fi = 0
while fi < files.size
  path = files[fi]
  src = File.read(path)
  p = JsParser.new(src, false)
  prog = nil
  begin
    prog = p.parse_program()
  rescue e
    << "skip " + path + ": " + e.to_s
  if prog != nil
    an = JaAnalysis.new(prog, false).run
    st = an.stats
    st.each ->(k, v) TOT[k] = TOT[k] + v
    an.funcs.each ->(f)
      if f.unsupported != nil
        r = f.unsupported
        REASONS[r] = (REASONS[r] == nil ? 0 : REASONS[r]) + 1
    count_scopes(an)
    walk_counts(prog, nil)
  fi += 1
<< "files " + files.size.to_s + " in " + (clock_ms() - t0).to_s + " ms"
<< "functions " + TOT.to_s
<< "function scopes: " + SCOPES[0].to_s + " without an environment, " + SCOPES[1].to_s + " with"
<< "object literal property counts: " + fmt_hist(LIT_HIST)
<< "constructor this.x counts: " + fmt_hist(CTOR_HIST)
<< "unsupported (functions, by first reason):"
ks = REASONS.keys.sort_by(->(k) 0 - REASONS[k])
ks.each ->(k) << "  " + REASONS[k].to_s + " " + k.to_s
