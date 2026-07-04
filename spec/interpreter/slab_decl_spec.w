# Interpreter-path spec for the slab-declaration AST family (I7).
#
# The build always takes the COMPILED path, so the tree-walking interpreter
# (`bin/tungsten run` / `-e` / `--repl`) silently rotted: it crashed with
# `Unknown AST node type` on any class using a `- data` / `- ivars` block,
# a view/extern/gpu/schedule declaration, or an `in Namespace` prefix. The
# interpreter now no-ops the structural kinds and registers `- data` struct
# fields as ivar accessors, mirroring the compiled pipeline.
#
# Run THROUGH THE INTERPRETER: `bin/tungsten run spec/interpreter/slab_decl_spec.w`.
# (Running it compiled would not exercise the interpreter arms this guards.)

in Geometry

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name

# `- data` struct block: each field becomes an ivar accessor at runtime.
+ Pt
  - data
    field x
    field y
  -> new(@x, @y)
  -> manhattan
    x + y

# `- ivars` slab-layout block: declarative; the constructor populates @label.
+ Tagged
  - ivars
    @label w64
  -> new(@label)
  -> tag
    @label

p = Geometry:Pt.new(3, 4)
check("data.accessors", p.x == 3 && p.y == 4)
check("data.method", p.manhattan == 7)

t = Geometry:Tagged.new(42)
check("ivars.decl", t.tag == 42)

# `in Namespace` qualifies the class names above (Geometry:Pt / Geometry:Tagged);
# reaching this line at all proves the namespace_decl arm no longer crashes.
check("namespace.decl", true)
