require "support/to_node"

module Tungsten::AST
  describe Tungsten::Parser do
    def self.it_parses(string, nodes, **options)
      it "parses #{string.inspect}", options do
        result = described_class.parse(string)
        nodes = [nodes] unless nodes.is_a?(::Array)
        expect(result).to eq(List.new nodes)
      end
    end

    it_parses "nil",   Nil.new

    it_parses "true",  true.boolean
    it_parses "false", false.boolean

    it_parses "1",     1.int
    it_parses "+1",    1.int
    it_parses "(1)",   1.int
    it_parses "-1",   -1.int

    it_parses "1.0",   1.decimal
    it_parses "+1.0",  1.decimal
    it_parses "(1.0)", 1.decimal
    it_parses "-1.0", -1.decimal

    it_parses "#ff0000", ColorLiteral.new(255, 0, 0, 255)
    it_parses "#f008", ColorLiteral.new(255, 0, 0, 136)

    it_parses "~1.0",      1.float
    it_parses "~1.0e0",    1.float
    it_parses "~1.0e+0",   1.float
    it_parses "~1.0e-0",   1.float
    it_parses "~1.0e-1", 0.1.float

    it_parses "[]",       [].array
    it_parses "[1, 2]",   [1.int, 2.int].array

    it_parses "foo",            "foo".var
    it_parses "foo()",          "foo".call
    it_parses "foo(1)",         "foo".call(1.int)
    it_parses "foo 1",          "foo".call(1.int)
    it_parses "foo 1\n",        "foo".call(1.int)
    it_parses "foo 1;",         "foo".call(1.int)
    it_parses "foo 1, 2",       "foo".call(1.int,   2.int)
    it_parses "foo ~1.0, ~2.0", "foo".call(1.float, 2.float)
    it_parses "foo(1 + 2)",     "foo".call(BinaryOp.new(1.int, :"+", 2.int))

    # it_parses "foo (1 + 2), 3", "foo".call([BinaryOp.new(1.int, :"+", 2.int), 3.int])

    it_parses "foo +1",         Call.new(nil, "foo", [1.int])
    it_parses "foo !false",     Call.new(nil, "foo", [Not.new(false.boolean)])

    it_parses "foo + 1",        BinaryOp.new("foo".var, :+, 1.int)
    # it_parses "foo.bar.baz",    Call.new(Call.new("foo".call, "bar"), "baz")

    %i[==].each do |op|
      it_parses "1 #{op} 2", BinaryOp.new(1.int,   op, 2.int)
      it_parses "n #{op} 2", BinaryOp.new("n".var, op, 2.int)
    end

    # comparison
    %i[< <= > >=].each do |op|
      it_parses "1 #{op} 2", BinaryOp.new(1.int,   op, 2.int)
      it_parses "n #{op} 2", BinaryOp.new("n".var, op, 2.int)
    end

    # math and bit math
    %i[+ - * / % | & ^ ** << >>].each do |op|
      it_parses "a #{op} 1",  BinaryOp.new("a".var, op, 1.int)
      it_parses "1 #{op} 2",  BinaryOp.new(1.int,   op, 2.int)
      it_parses "a #{op}= 1", AssignOp.new("a".var, op, 1.int)
    end

    it_parses "a++", AssignOp.new("a".var, :+, 1.int)
    it_parses "a--", AssignOp.new("a".var, :-, 1.int)

    it_parses "true  ? 1 + 2 : 4", If.new(true.boolean,  BinaryOp.new(1.int, :"+", 2.int), 4.int)
    it_parses "false ? 1 + 2 : 4", If.new(false.boolean, BinaryOp.new(1.int, :"+", 2.int), 4.int)

    it_parses <<~EOF, ClassDef.new("Class", [BinaryOp.new(1.int, :"+", 1.int)], "Superclass")
      + Class < Superclass
        1 + 1
    EOF

    it_parses <<~EOF, ClassDef.new("Bits", [BinaryOp.new(1.int, :"+", 1.int)], nil, class_role: "Controller")
      + Bits[Controller]
        1 + 1
    EOF

    # class with class role — no body
    it "parses class with class role" do
      result = described_class.parse("+ Bits[Controller]\n  -> index\n    1").first
      expect(result).to be_a(ClassDef)
      expect(result.name).to eq("Bits")
      expect(result.class_role).to eq("Controller")
      expect(result.superclass).to be_nil
    end

    # class without class role or superclass (unchanged)
    it "parses class without class role or superclass" do
      result = described_class.parse("+ Dog\n  -> speak\n    1").first
      expect(result).to be_a(ClassDef)
      expect(result.name).to eq("Dog")
      expect(result.class_role).to be_nil
      expect(result.superclass).to be_nil
    end

    # A class role annotation [role] may be combined with a superclass, in
    # either order (the compiler's slab-AST node classes use `< Node [slab]`).
    it "parses class role before the superclass" do
      result = described_class.parse("+ Foo [slab] < Baz\n  -> x\n    1").first
      expect(result).to be_a(ClassDef)
      expect(result.class_role).to eq("slab")
      expect(result.superclass).to eq("Baz")
    end

    it "parses class role after the superclass" do
      result = described_class.parse("+ File < Node [slab]\n  -> x\n    1").first
      expect(result).to be_a(ClassDef)
      expect(result.class_role).to eq("slab")
      expect(result.superclass).to eq("Node")
    end

    # `when X then return/break/next` — control flow in an inline `then` body
    # (the compiler's ast_schema.w uses `when KIND_CALL then return SC_8`).
    it "parses control flow in a when-then body" do
      result = described_class.parse("case k\nwhen 1 then return 2\nwhen 3 then return 4\n").first
      expect(result).to be_a(CaseExpr)
      expect(result.whens.first.last).to be_a(Return)
    end

    # `x in (A B C)` — a space-separated membership tuple. Elements must parse
    # as separate values, not as a paren-less call `A(B C)` (compiler/lib/
    # parser.w uses `tok_type(...) in (T_NEWLINE T_TYPE_HINT)`).
    it "parses a space-separated `in` tuple as distinct elements" do
      result = described_class.parse("x in (A B C)\n").first
      expect(result).to be_a(InTest)
      expect(result.elements.length).to eq(3)
      expect(result.elements.map { |e| e.is_a?(Call) && !e.args.empty? }).to all(be false)
    end

    # A multi-line hash/array literal whose continuation lines are indented
    # deeper than the body must not be read as a nested block (the lexer
    # suppresses indentation inside (...)/[...]/{...}).
    it "parses a multi-line hash literal with deeper-indented continuations" do
      code = "-> f(x)\n  emit(y, {op: :c,\n    r: 1,\n    a: 2})\n  z\n"
      result = described_class.parse(code).first
      expect(result).to be_a(Def)
    end

    # A string literal whose content starts with `>` (after `<<` etc.) must not
    # be misread as the `"> ` operator (the compiler's metal_emitter.w emits
    # `out << ">;\n"`).
    it "parses a string starting with > after <<" do
      result = described_class.parse(%(out << ">;b"\n)).first
      expect(result).to be_a(BinaryOp)
      expect(result.operator).to eq(:<<)
      expect(result.right).to be_a(StringLiteral)
      expect(result.right.value).to eq(">;b")
    end

    # it_parses "-> foo(arg1)",                    Def.new("foo", ["arg1".var], nil)
    # it_parses "-> foo(arg1); end",               Def.new("foo", ["arg1".var], nil)
    # it_parses "-> foo(arg1, arg2)",              Def.new("foo", ["arg1".var, "arg2".var], nil)
    # it_parses "-> foo(arg1, arg2); end",         Def.new("foo", ["arg1".var, "arg2".var], nil)
    # it_parses "-> foo(\narg1); end",             Def.new("foo", ["arg1".var], nil)
    # it_parses "-> foo(\narg1\n); end",           Def.new("foo", ["arg1".var], nil)
    # it_parses "-> foo(\narg1\n,\narg2\n)",       Def.new("foo", ["arg1".var, "arg2".var], nil)

    # it_parses "-> []",      Def.new(:"[]", [], nil)
    # it_parses "-> self.[]", Def.new(:"[]", [], nil, "self".var)

    # it_parses "-> [](x)",   Def.new(:"[]", ["x".var], nil)

    # it_parses "-> foo", Def.new("foo", [], nil)
    # it_parses <<~END,   Def.new("foo", [], [1.int])
    #   -> foo
    #     1
    # END

    # it_parses <<~END, Def.new("downto", ["n".var], [1.int])
    #   -> downto(n)
    #     1
    # END

    # it_parses <<~END, Def.new("foo", [], [1.int, 2.int])
    #   -> foo
    #     1; 2
    # END

    # it_parses <<~END, Def.new("foo", ["n".var], Call.new(nil, "foo", [Call.new("n".var, :"-", [1.int])]))
    #   -> foo(n)
    #     foo(n - 1)
    # END

    it "parses -> .foo as a class method" do
      result = described_class.parse("-> .foo\n  1")
      defn = result.list[0]
      expect(defn).to be_a(Def)
      expect(defn.name).to eq("foo")
      expect(defn.receiver).to be_a(Var)
      expect(defn.receiver.name).to eq("self")
    end

    it "allows soft keyword names for keyword parameters" do
      result = described_class.parse("-> .rescue_from(error_class, with:)\n  with")
      defn = result.list[0]
      expect(defn.args[1].name).to eq("with")
      expect(defn.args[1].keyword).to be(true)
      expect(defn.body.first).to eq("with".var)
    end

    it "parses equals-introduced inline method bodies" do
      result = described_class.parse("-> .before_save(method_name) = callbacks.push(method_name)")
      defn = result.list[0]
      expect(defn.name).to eq("before_save")
      expect(defn.body.first).to be_a(Call)
      expect(defn.body.first.name).to eq("push")
    end

    it "parses type words as method names" do
      result = described_class.parse("-> string(name) = name")
      defn = result.list[0]
      expect(defn).to be_a(Def)
      expect(defn.name).to eq("string")
    end

    it "parses a return annotation before an indented method body" do
      result = described_class.parse("-> .tanh(x) f64\n  x")
      defn = result.list[0]
      expect(defn.return_type).to eq(:f64)
      expect(defn.body.first).to eq("x".var)
    end

    it "raises error for old -> self.method syntax" do
      expect {
        described_class.parse("-> self.foo")
      }.to raise_error(Tungsten::Error, /use '-> \.method_name' for class methods/)
    end

    # it_parses <<~END, Def.new("add", ["a".var, "b".var], [Call.new("a".var, :"+", ["b".var])])
    #   -> add(a, b)
    #     a + b
    # END

    # it_parses <<~END, Def.new("foo", [], ["a".call])
    #   -> foo
    #     a
    # END

    # it_parses <<~END, Def.new("foo", ["a".var], ["a".var])
    #   -> foo(a)
    #     a
    # END

    # it_parses <<~END, Def.new("foo", [], [Assign.new("a".var, 1.int), "a".var])
    #   -> foo
    #     a = 1
    #     a
    # END

    # it_parses <<-END, Def.new("foo", [], [Assign.new("a".var, 1.int), Call.new(nil, "a", [], Block.new)])
    #   -> foo
    #     a = 1
    #     a {}
    # END

    # it_parses <<~END, Def.new("foo", [], [Assign.new("a".var, 1.int), Call.new(nil, "x", [], Block.new([], ["a".var]))])
    #   -> foo
    #     a = 1
    #     x { a }
    # END

    # it_parses <<~END, Def.new("foo", [], [Call.new(nil, "x", [], Block.new(["a".var], ["a".var]))])
    #   -> foo
    #     x { |a| a }
    # END

    # %i[== +@ -@].each do |op|
    #   it_parses "-> #{op}; end;", Def.new(op, [], nil)
    # end

    it "parses with loop with single binding" do
      code = "with i in 0..2\n  i"
      result = described_class.parse(code)
      node = result.first
      expect(node).to be_a(With)
      expect(node.bindings.size).to eq(1)
      expect(node.bindings[0][0]).to eq("i".var)
      expect(node.bindings[0][1]).to be_a(RangeLiteral)
    end

    it "parses with loop with multiple bindings" do
      code = "with i in 0..2, j in 0..3\n  i"
      result = described_class.parse(code)
      node = result.first
      expect(node).to be_a(With)
      expect(node.bindings.size).to eq(2)
      expect(node.bindings[0][0]).to eq("i".var)
      expect(node.bindings[1][0]).to eq("j".var)
    end

    # %w[] and %i[] word/symbol arrays
    it_parses '%w[foo bar baz]', ArrayLiteral.new([StringLiteral.new("foo"), StringLiteral.new("bar"), StringLiteral.new("baz")])
    it_parses '%w[hello]',       ArrayLiteral.new([StringLiteral.new("hello")])
    it_parses '%w[]',            ArrayLiteral.new([])
    it_parses '%i[foo bar baz]', ArrayLiteral.new([Symbol.new("foo"), Symbol.new("bar"), Symbol.new("baz")])
    it_parses '%i[hello]',       ArrayLiteral.new([Symbol.new("hello")])
    it_parses '%i[]',            ArrayLiteral.new([])

    # suffix rescue
    it "parses suffix rescue" do
      result = described_class.parse("foo rescue nil")
      node = result.first
      expect(node).to be_a(Begin)
      expect(node.body).to be_a(List)
    end

    # magic constants
    it "parses __LINE__" do
      result = described_class.parse("__LINE__")
      node = result.first
      expect(node).to be_a(MagicConstant)
      expect(node.value).to eq(:__LINE__)
    end

    it "parses __FILE__" do
      result = described_class.parse("__FILE__")
      node = result.first
      expect(node).to be_a(MagicConstant)
      expect(node.value).to eq(:__FILE__)
    end

    it "parses __DIR__" do
      result = described_class.parse("__DIR__")
      node = result.first
      expect(node).to be_a(MagicConstant)
      expect(node.value).to eq(:__DIR__)
    end

    # global variables
    it "parses global variable" do
      result = described_class.parse("$debug")
      node = result.first
      expect(node).to be_a(GlobalVar)
      expect(node.name).to eq("$debug")
    end

    it "parses global variable assignment" do
      result = described_class.parse("$count = 0")
      node = result.first
      expect(node).to be_a(Assign)
      expect(node.name).to be_a(GlobalVar)
    end

    it "parses regex literals" do
      node = described_class.parse("/^--(.+)$/").first
      expect(node).to be_a(RegexLiteral)
      expect(node.pattern).to eq("^--(.+)$")
      expect(node.options).to eq("")
    end

    it "parses regex captures in regex arrow bodies" do
      node = described_class.parse("case arg\n  /^--(.+)$/ => $1\n").first
      expect(node).to be_a(CaseExpr)
      expect(node.whens.first.last).to be_a(GlobalVar)
      expect(node.whens.first.last.name).to eq("$1")
    end

    it "parses regex match as a binary operator" do
      node = described_class.parse("/^--(.+)$/ =~ arg && $1").first
      expect(node).to be_a(And)
      expect(node.left).to be_a(BinaryOp)
      expect(node.left.operator).to eq(:"=~")
      expect(node.right).to be_a(GlobalVar)
      expect(node.right.name).to eq("$1")
    end

    # alias
    it "parses alias" do
      result = described_class.parse("alias new_name old_name")
      node = result.first
      expect(node).to be_a(Alias)
      expect(node.to).to eq("new_name")
      expect(node.from).to eq("old_name")
    end

    # %w[= < <= > >= != + - * / % & | ^ **]

    # ['bar', :'+', :'-', :'*', :'/', :'<', :'<=', :'==', :'>', :'>=', :'%', :'|', :'&', :'^', :'**'].each do |name|
    #   it_parses "foo.#{name}",      Call.new("foo".call, name)
    #   it_parses "foo.#{name} 1, 2", Call.new("foo".call, name, [1.int, 2.int])
    # end

    # ── Crystal-inspired tests ──────────────────────────────────────

    # if/elsif/else (from Crystal's parser_spec)
    it "parses if with elsif" do
      code = "if x\n  1\nelsif y\n  2\nelse\n  3"
      result = described_class.parse(code).first
      expect(result).to be_a(If)
      # elsif becomes nested If (wrapped in List by If.new)
      expect(result.else_block.first).to be_a(If)
    end

    # A full-line comment between an if/elsif body and the following
    # elsif/else must not detach the continuation (regression: the comment
    # used to emit a premature DEDENT + stray NL, yielding "unexpected elsif").
    it "parses elsif after a comment line" do
      code = "if x\n  1\n# a comment\nelsif y\n  2\n"
      result = described_class.parse(code).first
      expect(result).to be_a(If)
      expect(result.else_block.first).to be_a(If)
    end

    it "parses else after a comment line" do
      code = "if x\n  1\n# a comment\nelse\n  2\n"
      result = described_class.parse(code).first
      expect(result).to be_a(If)
      expect(result.else_block).not_to be_nil
    end

    it "parses elsif after a comment following a nested-if elsif body" do
      code = "if a\n  1\nelsif b\n  if c\n    2\n  d\n# comment\nelsif e\n  3\n"
      result = described_class.parse(code).first
      expect(result).to be_a(If)
    end

    # unless
    it "parses unless" do
      result = described_class.parse("unless x\n  1").first
      expect(result).to be_a(If)
      expect(result.condition).to be_a(Not)
    end

    it "parses unless with else" do
      result = described_class.parse("unless x\n  1\nelse\n  2").first
      expect(result).to be_a(If)
      expect(result.condition).to be_a(Not)
    end

    # suffix forms (Crystal: "1 if 3", "1 unless 3", "1 while 3")
    it_parses "1 if true",      If.new(true.boolean, 1.int)
    it_parses "1 unless true",  If.new(true.boolean, nil, 1.int)

    it "parses suffix while" do
      result = described_class.parse("1 while true").first
      expect(result).to be_a(While)
    end

    # return/next/break with suffix
    it "parses return with suffix if" do
      result = described_class.parse("return 1 if true").first
      expect(result).to be_a(If)
      expect(result.then_block.first).to be_a(Return)
    end

    it "parses break if true" do
      result = described_class.parse("break if true").first
      expect(result).to be_a(If)
      expect(result.then_block.first).to be_a(Break)
    end

    # method chaining
    it "parses method chain" do
      result = described_class.parse("foo.bar.baz").first
      expect(result).to be_a(Call)
      expect(result.name).to eq("baz")
      expect(result.obj).to be_a(Call)
      expect(result.obj.name).to eq("bar")
    end

    it "parses pipeline receiver shorthand" do
      result = described_class.parse("items |> .drop(1)").first
      expect(result).to be_a(Call)
      expect(result.obj).to eq("items".var)
      expect(result.name).to eq("drop")
      expect(result.args).to eq([1.int])
    end

    it "parses pipeline self receiver shorthand" do
      result = described_class.parse("value |> self.to_i").first
      expect(result).to be_a(Call)
      expect(result.obj).to eq("value".var)
      expect(result.name).to eq("to_i")
      expect(result.args).to eq([])
    end

    it "parses leading pipeline continuation lines" do
      defn = described_class.parse("-> f\n  value\n  |> .to_s").first
      expect(defn.body.list.length).to eq(1)
      expect(defn.body.first).to be_a(Call)
      expect(defn.body.first.name).to eq("to_s")
      expect(defn.body.first.obj).to eq("value".var)
    end

    it "parses indented dot continuation chains" do
      result = described_class.parse("items\n  .drop(1)\n  .take(2)").first
      expect(result).to be_a(Call)
      expect(result.name).to eq("take")
      expect(result.obj).to be_a(Call)
      expect(result.obj.name).to eq("drop")
      expect(result.obj.obj).to eq("items".var)
    end

    it "parses indented self continuation chains" do
      result = described_class.parse("items\n  self.drop(1)").first
      expect(result).to be_a(Call)
      expect(result.name).to eq("drop")
      expect(result.obj).to eq("items".var)
    end

    it "parses leading-dot receiver shorthand" do
      result = described_class.parse(".commands[:help]").first
      expect(result).to be_a(Call)
      expect(result.name).to eq("[]")
      expect(result.obj).to be_a(Call)
      expect(result.obj.obj).to eq("self".var)
      expect(result.obj.name).to eq("commands")
    end

    it "parses spaced keyword args after positional args" do
      result = described_class.parse("middleware.use Middleware:Session, store: config.session_store").first
      expect(result).to be_a(Call)
      expect(result.args.length).to eq(2)
      expect(result.args.last).to be_a(HashLiteral)
    end

    it "parses fat-arrow hash args without braces" do
      result = described_class.parse("self.class.exists?(field => value)").first
      expect(result).to be_a(Call)
      expect(result.name).to eq("exists?")
      expect(result.args.first).to be_a(HashLiteral)
      expect(result.args.first.entries.first).to eq(["field".var, "value".var])
    end

    it "parses splat block params and splat call args" do
      result = described_class.parse("define_singleton_method(name) -> (*args)\n  query_fn.call(*args)").first
      expect(result.block.args.first.name).to eq("args")
      expect(result.block.body.first.args.first).to be_a(Splat)
    end

    it "keeps infix star after a variable as multiplication" do
      result = described_class.parse("i * 8").first
      expect(result).to eq(BinaryOp.new("i".var, :*, 8.int))
    end

    # not
    it_parses "!true", Not.new(true.boolean)

    # and/or
    it_parses "1 && 2", And.new(1.int, 2.int)
    it_parses "1 || 2", Or.new(1.int, 2.int)

    # return/next/break
    it "parses return" do
      expect(described_class.parse("return").first).to be_a(Return)
    end

    it "parses return with value" do
      result = described_class.parse("return 1").first
      expect(result).to be_a(Return)
      expect(result.value).to eq(1.int)
    end

    it "parses next" do
      expect(described_class.parse("next").first).to be_a(Next)
    end

    it "parses break" do
      expect(described_class.parse("break").first).to be_a(Break)
    end

    # yield
    it "parses yield with args" do
      result = described_class.parse("yield 1").first
      expect(result).to be_a(Yield)
      expect(result.args).to eq([1.int])
    end

    # class with body
    it "parses class with methods" do
      code = "+ Foo\n  -> bar\n    1"
      result = described_class.parse(code).first
      expect(result).to be_a(ClassDef)
      expect(result.name).to eq("Foo")
      expect(result.body.first).to be_a(Def)
    end

    # class with inheritance
    it "parses class with superclass" do
      code = "+ Foo < Bar\n  -> baz\n    1"
      result = described_class.parse(code).first
      expect(result.superclass).to eq("Bar")
    end

    # while
    it "parses while" do
      result = described_class.parse("while true\n  1").first
      expect(result).to be_a(While)
      expect(result.condition).to eq(true.boolean)
    end

    it "parses until" do
      result = described_class.parse("until true\n  1").first
      expect(result).to be_a(Until)
      expect(result.condition).to eq(true.boolean)
    end

    # blocks — inline brace
    it "parses inline brace block" do
      result = described_class.parse("foo.each ->(x) { x }").first
      expect(result).to be_a(Call)
      expect(result.block).to be_a(Block)
    end

    # blocks — multiline
    it "parses multiline block" do
      result = described_class.parse("foo.each ->(x)\n  x").first
      expect(result).to be_a(Call)
      expect(result.block).to be_a(Block)
      expect(result.block.args.first.name).to eq("x")
    end

    # precedence (Crystal: 2 * 3 + 4 * 5)
    it "parses operator precedence" do
      result = described_class.parse("2 * 3 + 4 * 5").first
      expect(result).to be_a(BinaryOp)
      expect(result.operator).to eq(:+)
      expect(result.left).to be_a(BinaryOp)
      expect(result.left.operator).to eq(:*)
      expect(result.right).to be_a(BinaryOp)
      expect(result.right.operator).to eq(:*)
    end

    # grouping
    it "parses grouped expression" do
      result = described_class.parse("2 * (3 + 4)").first
      expect(result).to be_a(BinaryOp)
      expect(result.operator).to eq(:*)
      expect(result.right).to be_a(BinaryOp)
      expect(result.right.operator).to eq(:+)
    end

    # condition-less case
    it "parses condition-less case" do
      code = "case\nwhen x > 10\n  1\nelse\n  2"
      result = described_class.parse(code).first
      expect(result).to be_a(CaseExpr)
      expect(result.receiver).to be_nil
    end

    it "parses bare when chain" do
      code = "when x > 10\n  1\nwhen x > 5\n  2\nelse\n  3"
      result = described_class.parse(code).first
      expect(result).to be_a(CaseExpr)
      expect(result.receiver).to be_nil
      expect(result.whens.length).to eq(2)
      expect(result.else_body).not_to be_empty
    end

    it "parses bare when with inline bodies" do
      code = "when n == 0 \"zero\"\nwhen n == 1 \"one\"\nelse \"many\""
      result = described_class.parse(code).first
      expect(result).to be_a(CaseExpr)
      expect(result.receiver).to be_nil
      expect(result.whens.length).to eq(2)
      expect(result.whens.map { |conditions, _| conditions.length }).to eq([1, 1])
      expect(result.else_body.first).to eq(StringLiteral.new("many"))
    end

    # case with receiver
    it "parses case with receiver" do
      code = "case x\nwhen 1\n  \"one\""
      result = described_class.parse(code).first
      expect(result).to be_a(CaseExpr)
      expect(result.receiver).not_to be_nil
    end

    it "parses arrow case arms inside call parens" do
      code = "set_defaults(case @environment\n  \"development\" => true\n  => false\n)"
      result = described_class.parse(code).first
      expect(result).to be_a(Call)
      expect(result.args.first).to be_a(CaseExpr)
      expect(result.args.first.whens.length).to eq(1)
      expect(result.args.first.else_body.first).to eq(false.boolean)
    end

    it "parses semicolon sequences in arrow case bodies" do
      result = described_class.parse("case x\n  1 => touch(); \"done\"").first
      body = result.whens.first.last
      expect(body).to be_a(List)
      expect(body.last).to eq(StringLiteral.new("done"))
    end

    it "parses comma-separated arrow case patterns" do
      result = described_class.parse("case kind\n  :a, :b => \"hit\"").first
      expect(result.whens.length).to eq(1)
      expect(result.whens.first.first.length).to eq(2)
    end

    it "parses ro defaults" do
      result = described_class.parse("ro :commands { install: :ok }").first
      expect(result).to be_a(Call)
      expect(result.name).to eq("ro")
      expect(result.args).to eq([Symbol.new("commands")])
      expect(result.default).to be_a(HashLiteral)
    end

    # trait
    it "parses trait" do
      code = "trait Foo\n  -> bar\n    1"
      result = described_class.parse(code).first
      expect(result).to be_a(TraitDef)
      expect(result.name).to eq("Foo")
    end

    # is
    it "parses is" do
      result = described_class.parse("is Foo").first
      expect(result).to be_a(Is)
      expect(result.trait_name).to eq("Foo")
    end

    it "parses data declaration after trait include in class body" do
      result = described_class.parse(<<~TUNGSTEN).first
        + Array
          is Enumerable

          - data
              u8 flags
              u8[3] _pad
            * w64[] items
      TUNGSTEN

      expect(result).to be_a(ClassDef)
      expect(result.body[0]).to be_a(Is)
      expect(result.body[1]).to be_a(Nil)
    end

    it "parses data declaration with backing struct name in class body" do
      result = described_class.parse(<<~TUNGSTEN).first
        + Array
          - data (WArray)
              u8 flags
              u8[3] _pad
            * w64[] items
      TUNGSTEN

      expect(result).to be_a(ClassDef)
      expect(result.body[0]).to be_a(Nil)
    end

    # begin/rescue
    it "parses begin/rescue" do
      code = "begin\n  1\nrescue e\n  2"
      result = described_class.parse(code).first
      expect(result).to be_a(Begin)
      expect(result.rescue_var).to eq("e")
    end

    # begin/ensure
    it "parses begin/ensure" do
      code = "begin\n  1\nensure\n  2"
      result = described_class.parse(code).first
      expect(result).to be_a(Begin)
    end

    # parent pointers
    it "sets parent pointers after parsing" do
      ast = described_class.parse("x = 1 + 2")
      assign = ast.first
      expect(assign.parent).to eq(ast)
      expect(assign.value.parent).to eq(assign)
    end

    # quantity literals
    it_parses "5 m",      QuantityLiteral.new(5.int, "m")
    it_parses "5m",       QuantityLiteral.new(5.int, "m")
    it_parses "2x",       QuantityLiteral.new(2.int, "x")
    it_parses "3.14 kg",  QuantityLiteral.new(3.14.decimal, "kg")
    it_parses "100 km",   QuantityLiteral.new(100.int, "km")
    it_parses "~1.5 m",   QuantityLiteral.new(1.5.float, "m")

    it "parses inch unit" do
      result = described_class.parse("12 in")
      expect(result.first).to be_a(QuantityLiteral)
      expect(result.first.number).to eq(12.int)
      expect(result.first.unit_string).to eq("in")
    end

    it "parses compound unit m/s" do
      result = described_class.parse("5 m/s")
      expect(result.first).to be_a(QuantityLiteral)
      expect(result.first.number).to eq(5.int)
      expect(result.first.unit_string).to eq("m/s")
    end

    it "parses compound unit m/s^2" do
      result = described_class.parse("9 m/s^2")
      expect(result.first).to be_a(QuantityLiteral)
      expect(result.first.unit_string).to eq("m/s^2")
    end

    it "parses compound unit with middle dot" do
      result = described_class.parse("5 kg\u00b7m/s^2")
      expect(result.first).to be_a(QuantityLiteral)
      expect(result.first.unit_string).to eq("kg\u00b7m/s^2")
    end

    it "does not treat identifier with parens as unit" do
      result = described_class.parse("5\nfoo(1)")
      expect(result.first).to eq(5.int)
    end

    # Byte array literals
    it_parses "« »",           ByteArrayLiteral.new([])
    it_parses "« ff 00 a5 »", ByteArrayLiteral.new([255, 0, 165])
    it_parses "« 0b11001100 »", ByteArrayLiteral.new([204])

    it "parses byte array with interpolation" do
      result = described_class.parse("« ff [x] 00 »")
      node = result.first
      expect(node).to be_a(ByteArrayInterpolation)
      expect(node.parts.size).to eq(3)
      expect(node.parts[0]).to be_a(ByteArrayLiteral)
      expect(node.parts[0].value).to eq([255])
      expect(node.parts[2]).to be_a(ByteArrayLiteral)
      expect(node.parts[2].value).to eq([0])
    end

    # Key literals
    it_parses '#[CTRL+D]', KeyLiteral.new("CTRL+D")
    it_parses '#[ctrl+d]', KeyLiteral.new("ctrl+d")
    it_parses '#[C-d]',    KeyLiteral.new("C-d")
    it_parses '#[F1]',     KeyLiteral.new("F1")
    it_parses '#[A]',      KeyLiteral.new("A")
    it_parses '#[CTRL]',   KeyLiteral.new("CTRL")

    it "parses quantity in arithmetic" do
      result = described_class.parse("5 m + 3 m")
      expect(result.first).to be_a(BinaryOp)
      expect(result.first.left).to eq(QuantityLiteral.new(5.int, "m"))
      expect(result.first.right).to eq(QuantityLiteral.new(3.int, "m"))
    end

    # Namespace declarations
    it_parses "in Tungsten",           Nil.new
    it_parses "in Tungsten:Forge",     Nil.new
    it_parses "in Tungsten:Forge:H2",  Nil.new
  end
end
