# jsc — compile a JavaScript file to a native binary through the Tungsten compiler.
#
#   tools/jsc.sh file.js -o out [--release]
#
# This program is the Tungsten compiler with one addition: when JSC_JS names a
# JavaScript file, the program being compiled (runtime/main.w, the JS runtime) gets
# the translated script appended as Tungsten AST (compiler program_ast_hook). No
# Tungsten source text is generated. JSC_DUMP=1 prints the analysis summary, JSC_DUMP=2 the generated Tungsten AST.

use ../../../compiler/lib/driver_modules
use ../frontend/parser
use ../analyze
use ../translate/translate

-> jsc_hook(ast, path)
  js = env("JSC_JS")
  return ast if js == nil || js == ""
  src = read_file(js)
  if src == nil
    ccall("w_eputs", "jsc: cannot read " + js)
    exit(2)
  p = JsParser.new(src, false)
  prog = nil
  begin
    prog = p.parse_program()
  rescue e
    ccall("w_eputs", "jsc: " + js + ": SyntaxError: " + (p.error == nil ? e.to_s : p.error.to_s))
    exit(1)
  an = JaAnalysis.new(prog, false).run
  t = JsTranslator.new(an)
  partial = env("JSC_PARTIAL") == "1"
  lim = env("JSC_LIMIT")
  nodes = t.program(partial, lim == nil || lim == "" ? -1 : lim.to_i)
  if env("JSC_DUMP") == "1" || partial
    ccall("w_eputs", "jsc: " + an.stats.to_s + " translated=" + t.translated.to_s + " ic_words=" + t.ic_words.to_s)
  if partial
    hist = {}
    t.errors.each ->(er) hist[er[1]] = (hist[er[1]] == nil ? 0 : hist[er[1]]) + 1
    ks = hist.keys.sort_by(->(k) 0 - hist[k])
    ks.each ->(k) ccall("w_eputs", "jsc: unsupported " + hist[k].to_s + " " + k.to_s)
  if env("JSC_DUMP") == "2" && nodes != nil
    nodes.each ->(x) ccall("w_eputs", ast_to_tree(x, ""))
  if nodes == nil || (t.errors.size > 0 && !partial)
    t.errors.each ->(er)
      ccall("w_eputs", "jsc: " + js + ": function " + er[0].to_s + ": unsupported: " + er[1].to_s)
    exit(1)
  exprs = [ta_set("JS_IC", ta_typed_array("i64", t.ic_words))]
  ast.expressions.each ->(x) exprs.push(x)
  nodes.each ->(x) exprs.push(x)
  Tungsten:AST:Program.new(exprs)

program_ast_hook[:fn] = ->(ast, path) jsc_hook(ast, path)

use ../../../compiler/tungsten_driver
