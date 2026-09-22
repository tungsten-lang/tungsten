# Accessor methods synthesized from `ro` / `rw` declarations — a class-body
# `ro :a, :b`, `rw :c`, or the constructor's trailing marker — must carry the
# declaring line as their source location. They used to be built without a
# `loc`, so the function map (backtraces, profiles) placed every generated
# accessor, and the marker-stripped constructor itself, on line 0.
#
# Run:
#   bin/tungsten -o /tmp/accessor-loc spec/compiler/accessor_declaration_loc_spec.w
#   /tmp/accessor-loc

use ../../compiler/lib/ast
use ../../compiler/lib/lexer
use ../../compiler/lib/parser
use ../../compiler/lib/error_formatter
use ../../compiler/lib/lowering

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s() + ", want " + want.to_s()
    exit(1)
  << "PASS " + name

-> parse(source)
  lexer = Lexer.new(source)
  count = lexer.tokenize()
  parser = Parser.new(count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file)
  parser.set_chars(lexer.chars).parse()

source = ["+ Lamp", "  ro :watts, :lumens", "  rw :dimmer", "", "  -> new(@id, @room) ro", "", "  -> describe", "    id", ""].join("\n")

program = parse(source)
klass = program.expressions[0]
body = klass.body

# The pure class-body expansion keeps the declaration's position on every
# method it synthesizes (getter and setter alike).
ro_decl = body[0]
check("ro declaration line", ro_decl.line, 2)
ro_methods = class_body_accessor_methods(ro_decl)
check("ro expands to two getters", ro_methods.size(), 2)
check("ro getter name", ro_methods[0].name, "watts")
check("ro getter line", ro_methods[0].line, 2)
check("ro second getter line", ro_methods[1].line, 2)
check("ro getter col", ro_methods[0].col, ro_decl.col)

rw_decl = body[1]
rw_methods = class_body_accessor_methods(rw_decl)
check("rw expands to getter and setter", rw_methods.size(), 2)
check("rw setter name", rw_methods[1].name, "dimmer=")
check("rw getter line", rw_methods[0].line, 3)
check("rw setter line", rw_methods[1].line, 3)

# The shared builder propagates the whole span and the defining file.
ctor = body[2]
built = accessor_method_def("id", [], [Tungsten:AST:Ivar.new("@id")], ctor)
check("builder copies line", built.line, ctor.line)
check("builder copies end line", built.end_line, ctor.end_line)
check("builder copies source path", built.source_path, ctor.source_path)

# End to end through lowering: every function the class produces is placed on
# the line of the declaration that produced it, including the constructor
# that carried the trailing marker.
mod = lower_ast(program, "accessor_declaration_loc_spec.w")
lines = {}
i = 0
while i < mod[:functions].size()
  func = mod[:functions][i]
  if func[:source_class] == "Lamp"
    lines[func[:source_method]] = func[:source_line]
  i += 1
check("lowered watts line", lines["watts"], 2)
check("lowered lumens line", lines["lumens"], 2)
check("lowered dimmer getter line", lines["dimmer"], 3)
check("lowered dimmer setter line", lines["dimmer="], 3)
check("lowered trailing-marker id line", lines["id"], 5)
check("lowered trailing-marker room line", lines["room"], 5)
check("lowered constructor keeps its line", lines["new"], 5)
check("lowered ordinary method line", lines["describe"], 7)
<< "accessor_declaration_loc_spec: all checks passed"
