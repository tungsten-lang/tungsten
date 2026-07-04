RSpec.describe Tungsten::Interpreter do
  def run(code)
    Tungsten::Interpreter.new.run(code)
  end

  def output(code)
    capture(:stdout) { run(code) }.chomp
  end

  def capture(stream)
    stream = stream.to_s
    captured = StringIO.new
    previous =
      case stream
      when "stdout" then $stdout
      when "stderr" then $stderr
      else
        raise ArgumentError, "unsupported stream #{stream.inspect}"
      end

    case stream
    when "stdout" then $stdout = captured
    when "stderr" then $stderr = captured
    end

    yield
    captured.string
  ensure
    case stream
    when "stdout" then $stdout = previous
    when "stderr" then $stderr = previous
    end
  end

  it "evaluates integers" do
    expect(run("42")).to eq(42)
  end

  it "evaluates large prefixed integer literals exactly" do
    expect(run("0xE7037ED1A0B428DB")).to eq(0xE703_7ED1_A0B4_28DB)
    expect(run("0xFFFFFFFFFFFFFFFF")).to eq(0xFFFF_FFFF_FFFF_FFFF)
  end

  it "tests primality with Int#prime? across magnitude tiers" do
    # lookup + small screen
    expect(run("97.prime?")).to eq(true)
    expect(run("91.prime?")).to eq(false) # 7 * 13
    expect(run("1.prime?")).to eq(false)
    # wheel trial division
    expect(run("1000003.prime?")).to eq(true)
    expect(run("999999937.prime?")).to eq(true)
    # Miller-Rabin (> 2e9)
    expect(run("2147483647.prime?")).to eq(true)  # 2^31 - 1
    expect(run("1000000000039.prime?")).to eq(true)
    # BigInt path (> 2^64)
    expect(run("18446744073709551557.prime?")).to eq(true)   # largest prime < 2^64
    expect(run("29348493939585849493.prime?")).to eq(false)  # composite
    expect(run("170141183460469231731687303715884105727.prime?")).to eq(true) # 2^127 - 1
    # BPSW range (> 3.317e24, past Miller-Rabin determinism): strong Lucas
    expect(run("3317044064679887385962123.prime?")).to eq(true)            # prime just past Sinclair bound
    expect(run("1000000000000000000000000000057.prime?")).to eq(true)      # 10^30 + 57, prime
    expect(run("1000000000000074000000000001369.prime?")).to eq(false)     # product of two ~10^15 primes
  end

  it "decodes raw wvalue symbols from emitted LLVM immediates" do
    expect(run("u0xFFF9073656C6966B == :files")).to eq(true)
  end

  it "decodes raw boxed integers from emitted LLVM immediates" do
    expect(run("u0xFFFA000000000001")).to eq(1)
  end

  it "keeps raw object-space values as raw wvalues instead of mis-decoding them as doubles" do
    expect(run("u0x0000000000000010")).to eq(Tungsten::Runtime::RawWValue.new(0x0000_0000_0000_0010))
  end

  it "evaluates arithmetic" do
    expect(run("1 + 2")).to eq(3)
    expect(run("10 - 3")).to eq(7)
    expect(run("4 * 5")).to eq(20)
    expect(run("10 / 2")).to eq(5)
    expect(run("10 % 3")).to eq(1)
    expect(run("2 ** 8")).to eq(256)
  end

  it "evaluates parenthesized expressions" do
    expect(run("(1 + 2) * 3")).to eq(9)
  end

  it "evaluates variables" do
    expect(run("x = 5\nx + 1")).to eq(6)
  end

  it "applies machine integer type hints on assignment" do
    expect(run("x = 18446744073709551615 ## i64\nx")).to eq(-1)
    expect(run("x = -1 ## u64\nx")).to eq(18_446_744_073_709_551_615)
    expect(run("x = 340282366920938463463374607431768211456 ## u128\nx")).to eq(0)
  end

  it "evaluates multi-assignment" do
    expect(run("a, b = [1, 2]\na + b")).to eq(3)
    expect(run("a, b, c = [10, 20, 30]\nb")).to eq(20)
  end

  it "multi-assigns from method return" do
    expect(run("a, b = \"hello world\".split(\" \")\nb")).to eq("world")
  end

  it "multi-assigns with fewer values than targets" do
    expect(run("a, b, c = [1, 2]\nc")).to eq(nil)
  end

  it "multi-assigns with more values than targets" do
    expect(run("a, b = [1, 2, 3]\nb")).to eq(2)
  end

  it "multi-assigns with splat" do
    code = "a, *rest, b = \"1 2 3 4\".split(\" \")\n"
    expect(run(code + "rest")).to eq(["2", "3"])
    expect(run(code + "a")).to eq("1")
    expect(run(code + "b")).to eq("4")
  end

  it "multi-assigns with splat at end" do
    expect(run("a, *rest = [1, 2, 3, 4]\na")).to eq(1)
    expect(run("a, *rest = [1, 2, 3, 4]\nrest")).to eq([2, 3, 4])
  end

  it "multi-assigns with splat and insufficient values" do
    expect(run("a, *rest, b = [1, 2]\nrest")).to eq([])
    expect(run("a, *rest, b = [1, 2]\na")).to eq(1)
    expect(run("a, *rest, b = [1, 2]\nb")).to eq(2)
  end

  it "maps with /method" do
    expect(run("[1, 2, 3]/sq")).to eq([1, 4, 9])
    expect(run("[1, 2, 3]/add(1)")).to eq([2, 3, 4])
  end

  it "chains /method operators" do
    expect(run("[1, 2, 3]/sq/add(1)")).to eq([2, 5, 10])
    expect(run("[1, 2, 3]/sqrt/sq/to_i")).to eq([1, 2, 3])
  end

  it "map-reduces with /method:op" do
    expect(run("[1, 2, 3]/sq:+")).to eq(14)
  end

  it "maps with /method on a variable" do
    expect(run("list = [1, 2, 3]\nlist/sq")).to eq([1, 4, 9])
  end

  it "prints with <<" do
    expect(output("<< 42")).to eq("42")
    expect(output("x = 10\n<< x + 5")).to eq("15")
  end

  it "evaluates comparisons" do
    expect(run("1 < 2")).to eq(true)
    expect(run("3 == 3")).to eq(true)
    expect(run("1 > 2")).to eq(false)
  end

  it "evaluates booleans and nil" do
    expect(run("true")).to eq(true)
    expect(run("false")).to eq(false)
    expect(run("nil")).to eq(nil)
  end

  it "evaluates unary minus" do
    expect(run("-5")).to eq(-5)
  end

  it "evaluates negation" do
    expect(run("!true")).to eq(false)
    expect(run("!false")).to eq(true)
  end

  it "evaluates if when true" do
    expect(run("if true\n  42")).to eq(42)
  end

  it "evaluates if when false with no else" do
    expect(run("if false\n  42")).to eq(nil)
  end

  it "evaluates if/else taking then branch" do
    expect(run("if true\n  1\nelse\n  2")).to eq(1)
  end

  it "evaluates if/else taking else branch" do
    expect(run("if false\n  1\nelse\n  2")).to eq(2)
  end

  it "evaluates elsif taking first branch" do
    code = "x = 1\nif x == 1\n  10\nelsif x == 2\n  20\nelse\n  30"
    expect(run(code)).to eq(10)
  end

  it "evaluates elsif taking middle branch" do
    code = "x = 2\nif x == 1\n  10\nelsif x == 2\n  20\nelse\n  30"
    expect(run(code)).to eq(20)
  end

  it "evaluates elsif falling through to else" do
    code = "x = 99\nif x == 1\n  10\nelsif x == 2\n  20\nelse\n  30"
    expect(run(code)).to eq(30)
  end

  it "evaluates elsif with no else when all false" do
    code = "x = 99\nif x == 1\n  10\nelsif x == 2\n  20"
    expect(run(code)).to eq(nil)
  end

  it "evaluates multiple elsif branches" do
    code = "x = 3\nif x == 1\n  10\nelsif x == 2\n  20\nelsif x == 3\n  30\nelse\n  40"
    expect(run(code)).to eq(30)
  end

  it "evaluates suffix if when true" do
    expect(output("<< 42 if true")).to eq("42")
  end

  it "evaluates suffix if when false" do
    expect(output("<< 42 if false")).to eq("")
  end

  it "evaluates unless when false (executes body)" do
    expect(run("unless false\n  42")).to eq(42)
  end

  it "evaluates unless when true (skips body)" do
    expect(run("unless true\n  42")).to eq(nil)
  end

  it "evaluates suffix unless" do
    expect(output("<< 42 unless false")).to eq("42")
    expect(output("<< 42 unless true")).to eq("")
  end

  it "evaluates while loops" do
    code = "i = 0\nwhile i < 5\n  i += 1\ni"
    expect(run(code)).to eq(5)
  end

  it "evaluates until loops" do
    code = "i = 0\nuntil i == 5\n  i += 1\ni"
    expect(run(code)).to eq(5)
  end

  it "evaluates && and ||" do
    expect(run("true && false")).to eq(false)
    expect(run("true && 42")).to eq(42)
    expect(run("nil || 99")).to eq(99)
    expect(run("1 || 99")).to eq(1)
  end

  it "evaluates compound assignment" do
    expect(run("x = 10\nx += 5\nx")).to eq(15)
    expect(run("x = 10\nx -= 3\nx")).to eq(7)
    expect(run("x = 10\nx *= 2\nx")).to eq(20)
  end

  it "evaluates ++ and --" do
    expect(run("x = 0\nx++\nx")).to eq(1)
    expect(run("x = 5\nx--\nx")).to eq(4)
    expect(run("x = 0\nx++\nx++\nx++\nx")).to eq(3)
  end

  it "evaluates break in while" do
    code = "i = 0\nwhile true\n  break if i == 3\n  i += 1\ni"
    expect(run(code)).to eq(3)
  end

  it "does not re-evaluate statically true while conditions" do
    ["true", "1 == 1"].each do |condition_source|
      code = "i = 0\nwhile #{condition_source}\n  break if i == 3\n  i += 1\ni"
      ast = Tungsten::Parser.parse(code)
      while_node = ast.list.find { |node| node.is_a?(Tungsten::AST::While) }
      condition_evals = 0
      interpreter = described_class.new
      original_evaluate = interpreter.method(:evaluate)

      interpreter.define_singleton_method(:evaluate) do |node|
        condition_evals += 1 if node.equal?(while_node.condition)
        original_evaluate.call(node)
      end

      expect(interpreter.evaluate(ast)).to eq(3)
      expect(condition_evals).to eq(0)
    end
  end

  it "evaluates next in while" do
    code = <<~W
      i = 0
      sum = 0
      while i < 5
        i += 1
        next if i % 2 == 0
        sum += i
      sum
    W
    expect(run(code)).to eq(9)
  end

  it "evaluates next in until" do
    code = <<~W
      i = 0
      sum = 0
      until i == 5
        i += 1
        next if i % 2 == 0
        sum += i
      sum
    W
    expect(run(code)).to eq(9)
  end

  it "evaluates break from yielded block inside while" do
    code = <<~W
      -> each3(a, b, c)
        yield a
        yield b
        yield c

      i = 0
      while true
        each3(1, 2, 3) -> (n)
          break if n == 2
        i += 1
      i
    W
    expect(run(code)).to eq(0)
  end

  it "evaluates ternary" do
    expect(run("true ? 1 : 2")).to eq(1)
    expect(run("false ? 1 : 2")).to eq(2)
  end

  it "defines and calls a method" do
    expect(run("-> add(a, b)\n  a + b\nadd(3, 4)")).to eq(7)
  end

  it "calls methods with space syntax" do
    expect(run("-> double(x)\n  x * 2\ndouble 5")).to eq(10)
  end

  it "returns last expression from method" do
    expect(run("-> five\n  5\nfive")).to eq(5)
  end

  it "handles explicit return" do
    expect(run("-> early(x)\n  return x if x > 10\n  0\nearly(42)")).to eq(42)
  end

  it "handles return falling through" do
    expect(run("-> early(x)\n  return x if x > 10\n  0\nearly(5)")).to eq(0)
  end

  it "uses default parameter values" do
    expect(run("-> greet(n = 42)\n  n\ngreet")).to eq(42)
  end

  it "overrides default parameter values" do
    expect(run("-> greet(n = 42)\n  n\ngreet(99)")).to eq(99)
  end

  it "handles recursion" do
    expect(run("-> fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\nfib(10)")).to eq(55)
  end

  it "captures closure environment" do
    expect(run("-> make_adder(n)\n  -> add(x)\n    x + n\n  add\nadder = make_adder(10)\nadder(5)")).to eq(15)
  end

  it "calls method with side effects" do
    expect(output("-> say(msg)\n  << msg\nsay(42)")).to eq("42")
  end

  it "handles multiple arguments" do
    expect(run("-> calc(a, b, c)\n  a + b * c\ncalc(1, 2, 3)")).to eq(7)
  end

  it "yields to a block" do
    expect(output("-> repeat(n)\n  i = 0\n  while i < n\n    yield i\n    i += 1\nrepeat(3) -> (i)\n  << i")).to eq("0\n1\n2")
  end

  it "yield returns block value to caller" do
    expect(run("-> apply(x)\n  yield x\nresult = apply(10) -> (n)\n  n * 2\nresult")).to eq(20)
  end

  it "yields without arguments" do
    expect(output("-> twice\n  yield\n  yield\ntwice ->\n  << 42")).to eq("42\n42")
  end

  it "next in block skips to next yield" do
    expect(output("-> each3(a, b, c)\n  yield a\n  yield b\n  yield c\neach3(1, -2, 3) -> (n)\n  next if n < 0\n  << n")).to eq("1\n3")
  end

  it "block captures caller scope" do
    expect(output("x = 10\n-> repeat(n)\n  i = 0\n  while i < n\n    yield i\n    i += 1\nrepeat(2) -> (i)\n  << i + x")).to eq("10\n11")
  end

  it "raises error on yield without block" do
    expect { run("-> bad\n  yield\nbad") }.to raise_error(Tungsten::Error, /without a block/)
  end

  # Phase 1: Arrays, ranges, chars, receiver dispatch

  it "evaluates array literals" do
    expect(run("[1, 2, 3]")).to eq([1, 2, 3])
  end

  it "evaluates nested arrays" do
    expect(run("[[1], [2, 3]]")).to eq([[1], [2, 3]])
  end

  it "evaluates empty array" do
    expect(run("[]")).to eq([])
  end

  it "evaluates ranges" do
    expect(run("(1..5).to_a")).to eq([1, 2, 3, 4, 5])
    expect(run("(1...5).to_a")).to eq([1, 2, 3, 4])
  end

  it "calls methods on receivers" do
    expect(run("[3, 1, 2].sort")).to eq([1, 2, 3])
    expect(run("[1, 2, 3].size")).to eq(3)
  end

  it "calls receiver methods with blocks" do
    expect(run("[1, 2, 3].map -> (x)\n  x * 2")).to eq([2, 4, 6])
  end

  it "auto-binds block params by order of first reference" do
    expect(run("[1, 2, 3].map { x * 2 }")).to eq([2, 4, 6])
    expect(run("total = 0\n[1, 2, 3].each { total = total + x }\ntotal")).to eq(6)
  end

  it "auto-binds multiple block params in reference order" do
    expect(run("[1, 2, 3, 4].reduce(0) { acc + x }")).to eq(10)
  end

  it "calls receiver methods with arguments" do
    expect(run("[1, 2, 3].push(4)")).to eq([1, 2, 3, 4])
  end

  it "does not use cached implicit self dispatch after a local function appears" do
    code = <<~W
      + Thing
        -> value
          1
        -> run
          i = 0
          out = 0
          while i < 2
            if i == 1
              value = ->()
                2
            out += value()
            i += 1
          out
      Thing().run
    W
    expect(run(code)).to eq(3)
  end

  it "does not use cached implicit self dispatch after an outer function appears" do
    code = <<~W
      + Thing
        -> value
          1
        -> run
          value()
      first = Thing().run
      value = ->()
        2
      second = Thing().run
      first * 10 + second
    W
    expect(run(code)).to eq(12)
  end

  it "chains method calls" do
    expect(run("[3, 1, 2].sort.size")).to eq(3)
  end

  it "indexes arrays with []" do
    expect(run("[10, 20, 30][1]")).to eq(20)
  end

  # Phase 2: Strings

  it "evaluates string literals" do
    expect(run('"hello"')).to eq("hello")
  end

  it "evaluates string escape sequences" do
    expect(run('"hello\nworld"')).to eq("hello\nworld")
  end

  it "evaluates string interpolation" do
    expect(run("x = 42\n\"val: [x]\"")).to eq("val: 42")
  end

  it "evaluates string interpolation with expressions" do
    expect(run("x = 3\n\"x + 1 = [x + 1]\"")).to eq("x + 1 = 4")
  end

  it "evaluates string interpolation with multiple parts" do
    expect(run("a = 1\nb = 2\n\"[a] + [b] = [a + b]\"")).to eq("1 + 2 = 3")
  end

  it "concatenates strings with +" do
    expect(run('"hello" + " " + "world"')).to eq("hello world")
  end

  it "calls methods on strings" do
    expect(run('"hello".size')).to eq(5)
    expect(run('"hello".upcase')).to eq("HELLO")
  end

  # Phase 3: Object model and classes

  it "defines and instantiates a class" do
    code = <<~W
      + Dog
        -> new(@name)
        -> name
          @name
      d = Dog("Rex")
      d.name
    W
    expect(run(code)).to eq("Rex")
  end

  it "restores class definition self after class body errors" do
    interpreter = described_class.new
    initial_self_stack = interpreter.instance_variable_get(:@self_stack).dup

    expect do
      interpreter.run("+ Broken\n  missing_method()")
    end.to raise_error(Tungsten::Error)

    expect(interpreter.instance_variable_get(:@self_stack)).to eq(initial_self_stack)
  end

  it "does not leak class mutations from isolated evaluation" do
    interpreter = described_class.new
    interpreter.run("+ Thing\n  -> value\n    1")

    interpreter.evaluate_isolated("+ Thing\n  -> value\n    2\n  -> extra\n    3")

    expect(interpreter.run("Thing().value")).to eq(1)
    expect { interpreter.run("Thing().extra") }.to raise_error(Tungsten::Error)
  end

  it "handles inheritance" do
    code = <<~W
      + Animal
        -> speak
          "..."
      + Dog < Animal
        -> speak
          "woof"
      Dog().speak
    W
    expect(run(code)).to eq("woof")
  end

  it "inherits methods from superclass" do
    code = <<~W
      + Animal
        -> speak
          "..."
      + Dog < Animal
      Dog().speak
    W
    expect(run(code)).to eq("...")
  end

  it "accesses instance variables" do
    code = <<~W
      + Point
        -> new(@x, @y)
        -> x
          @x
        -> y
          @y
      p = Point(3, 4)
      p.x + p.y
    W
    expect(run(code)).to eq(7)
  end

  it "evaluates lazy ro defaults" do
    code = <<~W
      + Commands
        ro :commands { install: :ok }

      Commands.new.commands
    W
    expect(run(code)).to eq({ "install" => :ok })
  end

  # Phase 4: Hashes

  it "evaluates hash literals" do
    expect(run("{ one: 1, two: 2 }")).to eq({ "one" => 1, "two" => 2 })
  end

  it "evaluates empty hash" do
    expect(run("{}")).to eq({})
  end

  it "calls methods on hashes" do
    expect(run("{ a: 1, b: 2 }.size")).to eq(2)
  end

  it "indexes hashes with []" do
    expect(run("h = { name: \"erik\" }\nh[\"name\"]")).to eq("erik")
  end

  it "indexes hashes with indifferent string and symbol keys" do
    expect(run("h = { name: \"erik\" }\n[h[\"name\"], h[:name]]")).to eq(["erik", "erik"])
  end

  # Phase 5: case/when

  it "evaluates case/when" do
    code = "x = 2\ncase x\nwhen 1\n  10\nwhen 2\n  20\nelse\n  30"
    expect(run(code)).to eq(20)
  end

  it "evaluates case/when falling to else" do
    code = "x = 99\ncase x\nwhen 1\n  10\nwhen 2\n  20\nelse\n  30"
    expect(run(code)).to eq(30)
  end

  it "evaluates case/when with range" do
    code = "x = 5\ncase x\nwhen (1..3)\n  \"low\"\nwhen (4..6)\n  \"mid\"\nelse\n  \"high\""
    expect(run(code)).to eq("mid")
  end

  it "evaluates case/when with multiple conditions" do
    code = "x = 3\ncase x\nwhen 1, 2, 3\n  \"found\"\nelse\n  \"nope\""
    expect(run(code)).to eq("found")
  end

  it "catches returns inside case/when arms" do
    code = <<~W
      -> f(x)
        case x
        when 1
          return 2
        else
          3
      f(1)
    W
    expect(run(code)).to eq(2)
  end

  it "evaluates regex arrow case captures" do
    code = <<~W
      arg = "--name=value"
      case arg
        /^--(.+)=(.+)$/ => [$1.to_sym, $2]
        => []
    W
    expect(run(code)).to eq([:name, "value"])
  end

  it "evaluates regex match operator captures" do
    code = <<~W
      arg = "--name=value"
      if /^--(.+)=(.+)$/ =~ arg then [$1.to_sym, $2]
    W
    expect(run(code)).to eq([:name, "value"])
  end

  it "caches literal receiver case lookups on the ast node" do
    ast = Tungsten::Parser.parse("x = :b\ncase x\nwhen :a, :b\n  20\nelse\n  30")
    case_node = ast[1]
    interp = Tungsten::Interpreter.new

    expect(interp.evaluate(ast)).to eq(20)
    lookup = case_node.instance_variable_get(:@literal_case_lookup)

    expect(lookup).to be_a(Hash)
    expect(lookup[Symbol][:a]).to equal(case_node.whens[0][1])
    expect(lookup[Symbol][:b]).to equal(case_node.whens[0][1])
  end

  it "falls back to linear matching when a cached literal case misses by exact class" do
    code = "x = 1.0\ncase x\nwhen 1\n  \"int\"\nelse\n  \"nope\""
    expect(run(code)).to eq("int")
  end

  it "evaluates bare when chain" do
    code = "x = 2\nwhen x == 1\n  \"a\"\nwhen x == 2\n  \"b\"\nelse\n  \"c\""
    expect(run(code)).to eq("b")
  end

  it "evaluates bare when with inline bodies" do
    code = <<~CODE
      -> bottles(n)
        when n == 0 "no more bottles"
        when n == 1 "1 bottle"
        else "[n] bottles"

      bottles(2)
    CODE

    expect(run(code)).to eq("2 bottles")
  end

  # Phase 6: begin/rescue/ensure

  it "raises errors" do
    expect { run('raise "oops"') }.to raise_error(Tungsten::Error, "oops")
  end

  it "handles begin/rescue" do
    code = "begin\n  raise \"oops\"\nrescue err\n  err"
    expect(run(code)).to eq("oops")
  end

  it "rescues native runtime errors inside begin/rescue" do
    code = "begin\n  1 / 0\nrescue err\n  err"
    expect(run(code)).to eq("division by zero")
  end

  it "handles begin/rescue without variable" do
    code = "begin\n  raise \"oops\"\nrescue\n  42"
    expect(run(code)).to eq(42)
  end

  it "handles begin/ensure" do
    code = "x = 0\nbegin\n  x = 1\nensure\n  x = 99\nx"
    expect(run(code)).to eq(99)
  end

  it "handles begin/rescue/ensure" do
    code = "x = 0\nbegin\n  raise \"oops\"\nrescue err\n  x = 1\nensure\n  x = x + 10\nx"
    expect(run(code)).to eq(11)
  end

  it "evaluates symbols" do
    expect(run(":hello")).to eq(:hello)
    expect(run(":foo")).to eq(:foo)
  end

  # Tuples

  it "evaluates tuple literals" do
    expect(run("(1, 2, 3)")).to eq([1, 2, 3])
    expect(run("(1, 2, 3)")).to be_frozen
  end

  it "indexes tuples" do
    expect(run("(10, 20, 30)[1]")).to eq(20)
  end

  it "calls methods on tuples" do
    expect(run("(1, 2, 3).size")).to eq(3)
  end

  # Domain literals

  it "evaluates dates" do
    expect(run("2024-01-15")).to be_a(Tungsten::Date)
    expect(run("2024-01-15").to_s).to eq("2024-01-15")
  end

  it "evaluates IP addresses" do
    expect(run("192.168.1.1")).to be_a(Tungsten::IP4)
    expect(run("192.168.1.1").to_s).to eq("192.168.1.1")
  end

  it "evaluates decimals" do
    expect(run("1.5")).to eq(BigDecimal("1.5"))
  end

  it "sets instance variables in methods" do
    code = <<~W
      + Counter
        -> new
          @count = 0
        -> inc
          @count = @count + 1
        -> count
          @count
      c = Counter()
      c.inc
      c.inc
      c.inc
      c.count
    W
    expect(run(code)).to eq(3)
  end

  # Index assignment

  it "assigns to array indices" do
    expect(run("a = [1, 2, 3]\na[0] = 99\na[0]")).to eq(99)
  end

  it "assigns to hash keys" do
    expect(run("h = {}\nh[\"x\"] = 42\nh[\"x\"]")).to eq(42)
  end

  # Super

  it "calls super" do
    code = <<~W
      + Animal
        -> speak
          "..."
      + Dog < Animal
        -> speak
          "woof: " + super
      Dog().speak
    W
    expect(run(code)).to eq("woof: ...")
  end

  it "calls super with args" do
    code = <<~W
      + Base
        -> calc(x)
          x * 2
      + Child < Base
        -> calc(x)
          super(x) + 1
      Child().calc(5)
    W
    expect(run(code)).to eq(11)
  end

  # Modules

  it "defines modules with methods" do
    code = <<~W
      module Greetable
        -> greet
          "hello"
      Greetable.greet
    W
    expect(run(code)).to eq("hello")
  end

  # Splat

  it "collects splat args" do
    expect(run("-> foo(a, *rest)\n  rest\nfoo(1, 2, 3)")).to eq([2, 3])
  end

  it "splats array in call" do
    expect(run("-> add(a, b)\n  a + b\narr = [3, 4]\nadd(*arr)")).to eq(7)
  end

  it "splats in array literal" do
    expect(run("a = [2, 3]\n[1, *a, 4]")).to eq([1, 2, 3, 4])
  end

  # Ivar compound assignment

  it "compound assigns instance variables" do
    code = <<~W
      + Counter
        -> new
          @count = 0
        -> inc
          @count += 1
        -> count
          @count
      c = Counter()
      c.inc
      c.inc
      c.inc
      c.count
    W
    expect(run(code)).to eq(3)
  end

  it "compound assigns locals inside while loops" do
    code = <<~W
      i = 0
      total = 0
      while i < 5
        total += i
        i += 1
      total
    W
    expect(run(code)).to eq(10)
  end

  it "uses updated methods after a class is redefined" do
    code = <<~W
      + Greeter
        -> greet
          "one"
      first = Greeter().greet
      + Greeter
        -> greet
          "two"
      first + ":" + Greeter().greet
    W
    expect(run(code)).to eq("one:two")
  end

  # WObject introspection

  it "calls to_s on objects" do
    expect(run("+ Foo\nFoo().to_s")).to eq("#<Foo>")
  end

  it "calls class on objects (returns the class object)" do
    klass = run("+ Foo\nFoo().class")
    expect(klass).to be_a(Tungsten::Runtime::WClass)
    expect(klass.name).to eq("Foo")
  end

  it "calls class_name on objects (returns the name string)" do
    expect(run("+ Foo\nFoo().class_name")).to eq("Foo")
  end

  it "calls class on primitives (returns the auto-stub WClass)" do
    expect(run("4.class").name).to eq("Integer")
    expect(run('"hi".class').name).to eq("String")
  end

  it "calls class_name on primitives" do
    expect(run("4.class_name")).to eq("Integer")
    expect(run('"hi".class_name')).to eq("String")
  end

  it "calls class on a class — returns the Class singleton" do
    klass = run("Integer.class")
    expect(klass).to be_a(Tungsten::Runtime::WClass)
    expect(klass.name).to eq("Class")
    # Fixpoint: Class.class == Integer.class == 4.class.class.class
    expect(run("Class.class").name).to eq("Class")
    expect(run("4.class.class").name).to eq("Class")
    expect(run("4.class.class.class").name).to eq("Class")
  end

  it "calls class_name on a class — returns 'Class'" do
    expect(run("Integer.class_name")).to eq("Class")
    expect(run("Class.class_name")).to eq("Class")
  end

  it "calls .name on a class — returns the class's own name" do
    expect(run("Integer.name")).to eq("Integer")
    expect(run("Class.name")).to eq("Class")
  end

  it "calls nil? on objects" do
    expect(run("+ Foo\nFoo().nil?")).to eq(false)
  end

  it "checks is_a? against class hierarchy" do
    code = <<~W
      + Animal
      + Dog < Animal
      d = Dog()
      (d.is_a?("Dog"), d.is_a?("Animal"), d.is_a?("Cat"))
    W
    expect(run(code)).to eq([true, true, false])
  end

  it "evaluates with loop" do
    code = <<~W
      result = 0
      with i in 0..4
        result += i
      result
    W
    expect(run(code)).to eq(10)
  end

  it "evaluates with loop with multiple bindings" do
    code = <<~W
      result = 0
      with i in 0..2, j in 0..2
        result += 1
      result
    W
    expect(run(code)).to eq(9)
  end

  it "evaluates break in with loop" do
    code = <<~W
      result = 0
      with i in 0..9
        break if i == 3
        result += 1
      result
    W
    expect(run(code)).to eq(3)
  end

  it "evaluates next in with loop" do
    code = <<~W
      result = 0
      with i in 0..4
        next if i % 2 == 0
        result += i
      result
    W
    expect(run(code)).to eq(4)
  end

  it "checks respond_to?" do
    code = <<~W
      + Foo
        -> bar
          1
      f = Foo()
      (f.respond_to?("bar"), f.respond_to?("baz"))
    W
    expect(run(code)).to eq([true, false])
  end

  # Runtime builtins

  it "puts prints to stdout" do
    expect(output('puts("hello")')).to eq("hello")
    expect(output('puts(1, 2, 3)')).to eq("1\n2\n3")
  end

  it "prints rich literals and interpolation consistently together" do
    code = <<~W
      name = "Math"
      puts(#[CTRL+C])
      puts(15%)
      puts(£5.25)
      puts(2h15m)
      puts(9.8m/s^2)
      puts("hello [name]")
    W

    expect(output(code)).to eq("Ctrl+C\n15%\n£5.25\n2h15m\n9.8 m/s²\nhello Math")
  end

  it "reports rich literal runtime types consistently together" do
    code = <<~W
      puts(#[CTRL+C].type)
      puts(15%.type)
      puts(£5.25.type)
      puts(2h15m.type)
      puts((9.8m/s^2).type)
    W

    expect(output(code)).to eq("Key\nPercentage\nCurrency\nDuration\nQuantity")
  end

  it "print outputs without newline" do
    out = capture(:stdout) { run('print("ab")') }
    expect(out).to eq("ab")
  end

  it "exit terminates with code" do
    expect { run("exit(1)") }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    expect { run("exit") }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
  end

  it "read_file and write_file work" do
    require "tempfile"
    f = Tempfile.new("tungsten_test")
    path = f.path
    f.close
    run("write_file(\"#{path}\", \"hello\")")
    expect(run("read_file(\"#{path}\")")).to eq("hello")
    File.delete(path)
  end

  it "argv returns arguments" do
    expect(run("argv")).to be_an(Array)
  end

  it "keeps argv and ARGV on interpreter-owned user arguments" do
    interp = Tungsten::Interpreter.new(argv: [ "one", "--two", 3 ])

    expect(interp.run("argv()")).to eq([ "one", "--two", "3" ])
    expect(interp.run("ARGV")).to eq([ "one", "--two", "3" ])
  end

  it "returns a fresh argv array from argv()" do
    interp = Tungsten::Interpreter.new(argv: [ "one" ])

    interp.run('argv().push("two")')

    expect(interp.run("argv()")).to eq([ "one" ])
  end

  it "gets reads from stdin" do
    allow($stdin).to receive(:gets).and_return("hello\n")
    expect(run("gets")).to eq("hello")
  end

  it "type returns type name" do
    expect(run('42.type')).to eq("Integer")
    expect(run('"hi".type')).to eq("String")
    expect(run('[1].type')).to eq("Array")
    expect(run('true.type')).to eq("Boolean")
    expect(run('nil.type')).to eq("Nil")
    expect(run(':foo.type')).to eq("Symbol")
    expect(run('{}.type')).to eq("Hash")
  end

  it "type works on WObjects" do
    expect(run("+ Foo\nFoo().type")).to eq("Foo")
  end

  it "starts_with? and ends_with? work" do
    expect(run('"hello".starts_with?("hel")')).to eq(true)
    expect(run('"hello".starts_with?("xyz")')).to eq(false)
    expect(run('"hello".ends_with?("llo")')).to eq(true)
    expect(run('"hello".ends_with?("xyz")')).to eq(false)
  end

  it "replace substitutes all occurrences" do
    expect(run('"foo bar foo".replace("foo", "baz")')).to eq("baz bar baz")
  end

  it "map_with_index passes index" do
    code = <<~W
      [10, 20, 30].map_with_index -> (item, i)
        i
    W
    expect(run(code)).to eq([0, 1, 2])
  end

  it "to_s converts to string" do
    expect(run("42.to_s")).to eq("42")
  end

  it "to_i converts to integer" do
    expect(run('"42".to_i')).to eq(42)
    expect(run("2.9.to_i")).to eq(2)
    expect(run("-2.9.to_i")).to eq(-2)
  end

  it "user-defined method overrides builtin puts" do
    code = <<~W
      -> puts(x)
        x * 2
      puts(21)
    W
    expect(run(code)).to eq(42)
  end

  # use statement

  it "loads and evaluates a .w file with use" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "helper.w"), "-> double(x)\n  x * 2\n")
      main = File.join(dir, "main.w")
      File.write(main, "use \"helper\"\ndouble(21)")

      interp = Tungsten::Interpreter.new
      source = File.read(main)
      expect(interp.run(source, file_path: main)).to eq(42)
    end
  end

  it "prevents double-loading with use" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "counter.w"), "count += 1\n")
      main = File.join(dir, "main.w")
      File.write(main, "count = 0\nuse \"counter\"\nuse \"counter\"\ncount")

      interp = Tungsten::Interpreter.new
      source = File.read(main)
      expect(interp.run(source, file_path: main)).to eq(1)
    end
  end

  # %w[] and %i[] word/symbol arrays

  it "evaluates %w[] word arrays" do
    expect(run('%w[foo bar baz]')).to eq(["foo", "bar", "baz"])
  end

  it "evaluates empty %w[]" do
    expect(run('%w[]')).to eq([])
  end

  it "evaluates %i[] symbol arrays" do
    expect(run('%i[foo bar baz]')).to eq([:foo, :bar, :baz])
  end

  it "evaluates empty %i[]" do
    expect(run('%i[]')).to eq([])
  end

  # suffix rescue

  it "evaluates suffix rescue when no error" do
    expect(run("42 rescue 0")).to eq(42)
  end

  it "evaluates suffix rescue when error" do
    expect(run('raise "oops" rescue 99')).to eq(99)
  end

  # magic constants

  it "evaluates __LINE__" do
    expect(run("__LINE__")).to be_a(Integer)
  end

  it "evaluates __FILE__ without file_path" do
    expect(run("__FILE__")).to eq("(eval)")
  end

  it "evaluates __FILE__ with file_path" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.w")
      File.write(path, "__FILE__")
      interp = Tungsten::Interpreter.new
      expect(interp.run(File.read(path), file_path: path)).to eq(File.expand_path(path))
    end
  end

  it "evaluates __DIR__ without file_path" do
    expect(run("__DIR__")).to eq(Dir.pwd)
  end

  # global variables

  it "assigns and reads global variables" do
    expect(run("$count = 42\n$count")).to eq(42)
  end

  it "compound assigns global variables" do
    expect(run("$count = 10\n$count += 5\n$count")).to eq(15)
  end

  it "global variables are nil by default" do
    expect(run("$undefined")).to eq(nil)
  end

  # alias

  it "aliases a function" do
    code = <<~W
      -> double(x)
        x * 2
      alias dbl double
      dbl(21)
    W
    expect(run(code)).to eq(42)
  end

  it "resolves use paths relative to current file" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      sub = File.join(dir, "lib")
      Dir.mkdir(sub)
      File.write(File.join(sub, "math.w"), "-> triple(x)\n  x * 3\n")
      main = File.join(dir, "main.w")
      File.write(main, "use \"lib/math\"\ntriple(10)")

      interp = Tungsten::Interpreter.new
      source = File.read(main)
      expect(interp.run(source, file_path: main)).to eq(30)
    end
  end

  describe "quantity literals" do
    it "creates a quantity" do
      result = run("5 m")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("5 m")
    end

    it "creates a quantity without space" do
      result = run("5m")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("5 m")
    end

    it "adds same-unit quantities" do
      result = run("5 m + 3 m")
      expect(result.to_s).to eq("8 m")
    end

    it "adds custom-unit quantities" do
      result = run("2 x + 3 x")
      expect(result.to_s).to eq("5 x")
    end

    it "adds custom foo units" do
      result = run("1 foo + 3 foo")
      expect(result.to_s).to eq("4 foo")
    end

    it "auto-converts compatible known units" do
      result = run("1 ft + 12 in")
      expect(result.value).to be_within(0.0001).of(2.0)
      expect(result.unit.symbol).to eq("ft")
    end

    it "raises on dimension mismatch" do
      expect { run("2 m + 2 lb") }.to raise_error(Tungsten::DimensionError)
    end

    it "reports mass dimension for lbs in mismatch error" do
      expect { run("2 m + 2 lbs") }.to raise_error(Tungsten::DimensionError, /mass \(lbs\)/)
    end

    it "exponentiates quantities with **" do
      result = run("c = 299792458 m/s\nc ** 2")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to eq(299792458**2)
      expect(result.unit.symbol).to eq("m²/s²")
    end

    it "simplifies kg·m²/s² to J (E=mc²)" do
      result = run("m = 1 kg\nc = 299792458 m/s\nm·c²")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.unit.symbol).to eq("J")
    end

    it "simplifies cm³ to mL" do
      result = run("1 cm * 1 cm * 1 cm")
      expect(result.unit.symbol).to eq("mL")
      expect(result.value).to eq(1)
    end

    it "multiplies quantities to produce compound units" do
      result = run("5 m * 3 m")
      expect(result.value).to eq(15)
      expect(result.unit.symbol).to eq("m²")
    end

    it "divides quantities to produce compound units" do
      result = run("100 m / 10 s")
      expect(result.value).to eq(10)
      expect(result.unit.symbol).to eq("m/s")
    end

    it "multiplies scalar by quantity" do
      result = run("3 * 5 m")
      expect(result.to_s).to eq("15 m")
    end

    it "converts with .to()" do
      result = run("(5 km).to(\"m\")")
      expect(result.value).to be_within(0.01).of(5000.0)
      expect(result.unit.symbol).to eq("m")
    end

    it "gets value with .value" do
      expect(run("(5 m).value")).to eq(5)
    end

    it "gets unit string with .unit" do
      expect(run("(5 m).unit")).to eq("m")
    end

    it "reports type as Quantity" do
      expect(run("(5 m).type")).to eq("Quantity")
    end

    it "subtracts same-unit quantities" do
      result = run("10 kg - 3 kg")
      expect(result.to_s).to eq("7 kg")
    end

    it "compares quantities" do
      expect(run("5 m > 3 m")).to eq(true)
      expect(run("1 m < 2 m")).to eq(true)
      expect(run("5 m == 5 m")).to eq(true)
    end

    it "creates compound unit from literal" do
      result = run("10 m/s")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to eq(10)
      expect(result.unit.symbol).to eq("m/s")
    end

    it "accepts unicode superscript exponents" do
      result = run("25 m\u00b2 / 5 m")
      expect(result.to_s).to eq("5 m")
    end

    it "outputs unicode superscripts" do
      result = run("5 m * 3 m")
      expect(result.to_s).to eq("15 m\u00b2")
    end

    it "simplifies m/s^2 via unicode input" do
      result = run("9 m/s\u00b2")
      expect(result.unit.symbol).to eq("m/s\u00b2")
    end

    it "resolves long-form unit names" do
      result = run("5 meters")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to eq(5)
      expect(result.to_s).to eq("5 meters")
    end

    it "resolves singular long-form names" do
      result = run("1 meter")
      expect(result.to_s).to eq("1 meter")
    end

    it "preserves long-form plural in addition" do
      result = run("2 meters + 3 meters")
      expect(result.to_s).to eq("5 meters")
    end

    it "preserves left operand display form in mixed addition" do
      result = run("2 meters + 3 m")
      expect(result.to_s).to eq("5 meters")
    end

    it "auto-converts long-form compatible units" do
      result = run("5 meters + 3 feet")
      expect(result.value).to be_within(0.0001).of(5.9144)
      expect(result.to_s).to include("meters")
    end

    it "resolves long-form names for other units" do
      expect(run("10 seconds").to_s).to eq("10 seconds")
      expect(run("2 pounds").to_s).to eq("2 pounds")
      expect(run("3 inches").to_s).to eq("3 inches")
    end

    it "resolves irregular plurals" do
      expect(run("6 feet").to_s).to eq("6 feet")
    end

    it "creates °C quantities" do
      result = run("5 °C + 10 °C")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to eq(15)
      expect(result.to_s).to eq("15 °C")
    end

    it "converts °F to °C" do
      result = run("(32 °F).to(\"°C\")")
      expect(result.value).to be_within(0.01).of(0.0)
    end

    it "converts °C to °F" do
      result = run("(100 °C).to(\"°F\")")
      expect(result.value).to be_within(0.01).of(212.0)
    end

    it "converts Rankine to Kelvin" do
      result = run("(491.67 °R).to(\"K\")")
      expect(result.value).to be_within(0.01).of(273.15)
    end

    it "accepts °Ra alias for Rankine" do
      result = run("(491.67 °Ra).to(\"K\")")
      expect(result.value).to be_within(0.01).of(273.15)
    end

    it "converts Delisle to °C" do
      result = run("(0 °De).to(\"°C\")")
      expect(result.value).to be_within(0.01).of(100.0)
      result2 = run("(150 °De).to(\"°C\")")
      expect(result2.value).to be_within(0.01).of(0.0)
    end

    it "converts Newton scale to °C" do
      result = run("(33 °N).to(\"°C\")")
      expect(result.value).to be_within(0.01).of(100.0)
    end

    it "converts Réaumur to °C" do
      result = run("(80 °Ré).to(\"°C\")")
      expect(result.value).to be_within(0.01).of(100.0)
    end

    it "accepts °Re and °r aliases for Réaumur" do
      result = run("(80 °Re).to(\"°C\")")
      expect(result.value).to be_within(0.01).of(100.0)
      result2 = run("(80 °r).to(\"°C\")")
      expect(result2.value).to be_within(0.01).of(100.0)
    end

    it "converts Rømer to °C" do
      result = run("(60 °Rø).to(\"°C\")")
      expect(result.value).to be_within(0.01).of(100.0)
      result2 = run("(7.5 °Rø).to(\"°C\")")
      expect(result2.value).to be_within(0.01).of(0.0)
    end

    # Binary data
    it "handles bits and octets" do
      expect(run("8 b").to_s).to eq("8 b")
      expect(run("(8 b).to(\"B\")").value).to be_within(0.01).of(1.0)
      expect(run("1 o").to_s).to eq("1 o")
    end

    # Time
    it "handles days and fortnights" do
      expect(run("(1 d).to(\"s\")").value).to be_within(0.01).of(86400.0)
      expect(run("(1 fortnight).to(\"d\")").value).to be_within(0.01).of(14.0)
    end

    # Mass
    it "handles tonnes and stones" do
      expect(run("(1 t).to(\"kg\")").value).to be_within(0.01).of(1000.0)
      expect(run("(1 st).to(\"lb\")").value).to be_within(0.1).of(14.0)
    end

    it "handles daltons" do
      result = run("5 Da + 3 Da")
      expect(result.to_s).to eq("8 Da")
    end

    # Length
    it "handles astronomical units" do
      result = run("1 au")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("1 au")
    end

    it "handles parsecs and light years" do
      expect(run("1 pc").to_s).to eq("1 pc")
      expect(run("1 ly").to_s).to eq("1 ly")
    end

    it "handles nautical miles" do
      expect(run("(1 nmi).to(\"m\")").value).to be_within(0.01).of(1852.0)
    end

    # Area
    it "handles acres and hectares" do
      expect(run("1 ac").to_s).to eq("1 ac")
      expect(run("1 ha").to_s).to eq("1 ha")
    end

    # Volume
    it "handles litres" do
      expect(run("1 L").to_s).to eq("1 L")
      expect(run("(1 L).to(\"gal\")").value).to be_within(0.001).of(0.264172)
    end

    it "handles prefixed litres" do
      result = run("(1000 ml).to(\"L\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    it "handles volume long-form aliases" do
      expect(run("5 gallons").to_s).to eq("5 gallons")
      expect(run("2 pints").to_s).to eq("2 pints")
    end

    # Pressure
    it "handles bar and atm" do
      expect(run("(1 atm).to(\"Pa\")").value).to be_within(0.01).of(101325.0)
      expect(run("(1 bar).to(\"Pa\")").value).to be_within(0.01).of(100000.0)
    end

    # Energy
    it "handles electronvolts with prefixes" do
      result = run("(1 keV).to(\"eV\")")
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    # Electromagnetism
    it "handles coulombs and ohms" do
      expect(run("5 C + 3 C").to_s).to eq("8 C")
      expect(run("5 ohms").to_s).to eq("5 ohms")
    end

    it "handles tesla" do
      expect(run("1 T").to_s).to eq("1 T")
    end

    # Radioactivity
    it "handles becquerels and sieverts" do
      expect(run("100 Bq").to_s).to eq("100 Bq")
      result = run("(1 mSv).to(\"Sv\")")
      expect(result.value).to be_within(1e-6).of(0.001)
    end

    # Angle
    it "handles degrees and radians" do
      expect(run("90 deg").to_s).to eq("90 deg")
      expect(run("1 rad").to_s).to eq("1 rad")
    end

    # Photometry
    it "handles lumens and lux" do
      expect(run("100 lm").to_s).to eq("100 lm")
      expect(run("500 lx").to_s).to eq("500 lx")
    end

    # Custom dimension units
    it "handles unconvertible time units" do
      expect(run("5 beat + 3 beat").to_s).to eq("8 beats")
      expect(run("10 frames").to_s).to eq("10 frames")
      expect { run("5 beat + 5 s") }.to raise_error(Tungsten::DimensionError)
    end

    # Typographic
    it "handles em and en units" do
      expect(run("1 em + 1 en").to_s).to eq("1.5 em")
      expect(run("2 qquad").to_s).to eq("2 qquad")
    end

    # Multi-word units
    it "handles light years" do
      result = run("5 light years")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("5 light years")
    end

    it "handles nautical miles as multi-word" do
      result = run("10 nautical miles")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("10 nautical miles")
    end

    it "handles fluid ounces" do
      result = run("8 fl oz")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("8 fl oz")
    end

    it "handles metric tons" do
      result = run("2 metric tons")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("2 metric tons")
    end

    # Unicode symbol aliases
    it "handles ℃ and ℉" do
      result = run("100 ℃")
      expect(result).to be_a(Tungsten::Quantity)
    end

    it "handles ℧ as siemens" do
      result = run("5 ℧")
      expect(result).to be_a(Tungsten::Quantity)
    end

    # Cask units
    it "handles wine cask units" do
      expect(run("1 hogshead").to_s).to eq("1 hogshead")
      expect(run("2 firkins").to_s).to eq("2 firkins")
      expect(run("1 butt").to_s).to eq("1 butt")
    end

    # Apothecary units
    it "handles apothecary units" do
      expect(run("1 ℈").to_s).to eq("1 ℈")
      expect(run("1 ℥").to_s).to eq("1 ℥")
    end

    # New prefixes
    it "handles quecto and quetta prefixes" do
      result = run("(1 Qm).to(\"m\")")
      expect(result.value).to be_within(1e20).of(1e30)
    end

    it "handles μ prefix" do
      result = run("(1 μm).to(\"m\")")
      expect(result.value).to be_within(1e-9).of(1e-6)
    end

    # New units
    it "handles warhol fame unit" do
      result = run("1 kilowarhol | warhol")
      expect(result.value).to eq(1000)
    end

    it "handles altuve length unit" do
      result = run("1 altuve")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("1 altuve")
    end

    it "handles barrel volume unit" do
      result = run("1 barrel")
      expect(result).to be_a(Tungsten::Quantity)
    end

    it "handles stere volume unit" do
      result = run("(1 stere).to(\"L\")")
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "handles millihelen beauty unit" do
      result = run("5 millihelens + 3 millihelens")
      expect(result.to_s).to eq("8 millihelens")
    end

    it "handles nit illuminance unit" do
      result = run("100 nit")
      expect(result).to be_a(Tungsten::Quantity)
    end

    it "handles data rate units" do
      result = run("(8 bps).to(\"Bps\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    it "simplifies ft * ft to sqft" do
      result = run("10 ft * 10 ft")
      expect(result.value).to eq(100)
      expect(result.unit.symbol).to eq("sqft")
    end

    it "simplifies sqft / ft to ft" do
      result = run("100 sqft / 10 ft")
      expect(result.value).to eq(10)
      expect(result.unit.symbol).to eq("ft")
    end

    it "handles quantity minus percentage" do
      result = run("100 m - 10%")
      expect(result.value).to be_within(0.01).of(90.0)
      expect(result.unit.symbol).to eq("m")
    end

    it "handles quantity plus percentage" do
      result = run("100 m + 25%")
      expect(result.value).to be_within(0.01).of(125.0)
    end
  end

  describe "currency literals" do
    it "creates a currency from prefix symbol" do
      result = run("$10")
      expect(result).to be_a(Tungsten::Currency)
      expect(result.to_s).to eq("$10.00")
    end

    it "creates a currency with decimal" do
      result = run("$10.50")
      expect(result).to be_a(Tungsten::Currency)
      expect(result.to_s).to eq("$10.50")
    end

    it "creates euro currency" do
      result = run("\u20AC100")
      expect(result).to be_a(Tungsten::Currency)
      expect(result.symbol).to eq("\u20AC")
    end

    it "adds same currencies" do
      result = run("$10 + $5")
      expect(result.to_s).to eq("$15.00")
    end

    it "subtracts same currencies" do
      result = run("$20 - $8")
      expect(result.to_s).to eq("$12.00")
    end

    it "multiplies currency by scalar" do
      result = run("$10 * 3")
      expect(result.to_s).to eq("$30.00")
    end

    it "divides currency by scalar" do
      result = run("$30 / 3")
      expect(result.to_s).to eq("$10.00")
    end

    it "scalar times currency via coerce" do
      result = run("5 * $10")
      expect(result.to_s).to eq("$50.00")
    end

    it "applies percentage discount to currency" do
      result = run("$100 - 15%")
      expect(result.value).to eq(BigDecimal("85"))
    end

    it "applies percentage markup to currency" do
      result = run("$100 + 10%")
      expect(result.value).to eq(BigDecimal("110"))
    end

    it "evaluates chained percentage on currency" do
      result = run("$10.50 - 15% + 8.25%")
      # $10.50 × 0.85 = $8.925, then × 1.0825 ≈ $9.661...
      expect(result.value.to_f).to be_within(0.01).of(9.66)
    end

    it "creates suffix currency (cents)" do
      result = run("25¢")
      expect(result).to be_a(Tungsten::Currency)
      expect(result.to_s).to eq("25¢")
    end

    it "reports type as Currency" do
      expect(run("$10.type")).to eq("Currency")
    end
  end

  describe "unicode operators and constants" do
    it "uses · as multiplication" do
      expect(run("a = 3\nb = 4\na·b")).to eq(12)
    end

    it "uses ⋅ as multiplication" do
      expect(run("a = 5\nb = 6\na⋅b")).to eq(30)
    end

    it "uses × as multiplication" do
      expect(run("a = 7\nb = 8\na×b")).to eq(56)
    end

    it "uses ÷ as division" do
      expect(run("a = 20\nb = 4\na÷b")).to eq(5)
    end

    it "uses ∕ as division" do
      expect(run("a = 15\nb = 3\na∕b")).to eq(5)
    end

    it "uses superscript as exponentiation" do
      expect(run("x = 5\nx²")).to eq(25)
      expect(run("x = 2\nx³")).to eq(8)
      expect(run("x = 3\nx⁰")).to eq(1)
    end

    it "combines · and superscript: m·c²" do
      expect(run("m = 1\nc = 299_792_458\ne = m·c²\ne")).to eq(299_792_458**2)
    end

    it "evaluates π" do
      expect(run("π")).to be_within(0.0001).of(Math::PI)
    end

    it "evaluates τ" do
      expect(run("τ")).to be_within(0.0001).of(Math::PI * 2)
    end

    it "evaluates ϕ (golden ratio)" do
      expect(run("ϕ")).to be_within(0.0001).of((1 + Math.sqrt(5)) / 2.0)
    end

    it "evaluates ℯ (Euler's number)" do
      expect(run("ℯ")).to be_within(0.0001).of(Math::E)
    end

    it "evaluates ∞" do
      expect(run("∞")).to eq(Float::INFINITY)
    end

    it "evaluates ℎ (Planck constant) as Quantity" do
      result = run("ℎ")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-40).of(6.62607015e-34)
    end

    it "evaluates ℏ (reduced Planck constant) as Quantity" do
      result = run("ℏ")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-40).of(1.054571817e-34)
    end

    it "uses constants in expressions" do
      expect(run("r = 5\n2 * π * r")).to be_within(0.001).of(2 * Math::PI * 5)
    end
  end

  describe "percentage literals" do
    it "creates a percentage" do
      result = run("15%")
      expect(result).to be_a(Tungsten::Percentage)
      expect(result.to_s).to eq("15%")
    end

    it "adds percentages" do
      result = run("20% + 5%")
      expect(result.to_s).to eq("25%")
    end

    it "subtracts percentages" do
      result = run("20% - 5%")
      expect(result.to_s).to eq("15%")
    end

    it "applies percentage to integer (calculator style)" do
      expect(run("100 - 15%")).to be_within(0.01).of(85.0)
      expect(run("100 + 10%")).to be_within(0.01).of(110.0)
    end

    it "reports type as Percentage" do
      expect(run("15%.type")).to eq("Percentage")
    end

    it "keeps space-separated % as modulo" do
      expect(run("10 % 3")).to eq(1)
    end
  end

  describe "new units and physical constants" do
    # Force
    it "converts lbf to N" do
      result = run("(1 lbf).to(\"N\")")
      expect(result.value).to be_within(0.001).of(4.448)
    end

    it "converts kgf to N" do
      result = run("(1 kgf).to(\"N\")")
      expect(result.value).to be_within(0.001).of(9.807)
    end

    # Energy
    it "converts cal to J" do
      result = run("(1 cal).to(\"J\")")
      expect(result.value).to be_within(0.001).of(4.1868)
    end

    it "converts kcal to J" do
      result = run("(1 kcal).to(\"J\")")
      expect(result.value).to be_within(0.1).of(4186.8)
    end

    it "converts BTU to J" do
      result = run("(1 BTU).to(\"J\")")
      expect(result.value).to be_within(0.1).of(1055.06)
    end

    it "converts kWh to J" do
      result = run("(1 kWh).to(\"J\")")
      expect(result.value).to be_within(1.0).of(3600000.0)
    end

    # Power
    it "converts hp to W" do
      result = run("(1 hp).to(\"W\")")
      expect(result.value).to be_within(0.1).of(745.7)
    end

    # Pressure
    it "converts 760 torr to 1 atm" do
      result = run("(760 torr).to(\"atm\")")
      expect(result.value).to be_within(0.001).of(1.0)
    end

    it "converts mmHg to Pa" do
      result = run("(1 mmHg).to(\"Pa\")")
      expect(result.value).to be_within(0.01).of(133.322)
    end

    # Cooking
    it "converts 3 tsp to 1 tbsp" do
      result = run("(3 tsp).to(\"tbsp\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    # Nautical
    it "converts knot to m/s" do
      result = run("(1 knot).to(\"m/s\")")
      expect(result.value).to be_within(0.001).of(0.514)
    end

    it "converts fathom to ft" do
      result = run("(1 fathom).to(\"ft\")")
      expect(result.value).to be_within(0.01).of(6.0)
    end

    # Angle
    it "converts 100 gon to 90 deg" do
      result = run("(100 gon).to(\"deg\")")
      expect(result.value).to be_within(0.01).of(90.0)
    end

    it "converts 1 turn to 360 deg" do
      result = run("(1 turn).to(\"deg\")")
      expect(result.value).to be_within(0.01).of(360.0)
    end

    # Astronomy
    it "handles solar mass unit" do
      result = run("1 solarmass")
      expect(result).to be_a(Tungsten::Quantity)
    end

    # Typography
    it "converts 72 point to 1 in" do
      result = run("(72 point).to(\"in\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    # Mass extras
    it "converts 5 carat to 1 g" do
      result = run("(5 carat).to(\"g\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    # Viscosity
    it "converts poise to centipoise" do
      result = run("(10 P).to(\"cP\")")
      expect(result.value).to be_within(0.1).of(1000.0)
    end

    # Radioactivity
    it "converts 100 rem to 1 Sv" do
      result = run("(100 rem).to(\"Sv\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    # Information dimension
    it "converts 8 b to 1 B" do
      result = run("(8 b).to(\"B\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    it "converts 1024 KiB to 1 MiB" do
      result = run("(1024 KiB).to(\"MiB\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    it "handles TiB unit" do
      result = run("1 TiB")
      expect(result).to be_a(Tungsten::Quantity)
    end

    # Auto-prefix composition
    it "auto-resolves kB as 1000 bytes" do
      result = run("(1 kB).to(\"B\")")
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "auto-resolves MHz" do
      result = run("(1 MHz).to(\"Hz\")")
      expect(result.value).to be_within(0.01).of(1e6)
    end

    it "auto-resolves kPa" do
      result = run("(1 kPa).to(\"Pa\")")
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "auto-resolves mg as milligram" do
      result = run("(1000 mg).to(\"g\")")
      expect(result.value).to be_within(0.01).of(1.0)
    end

    # Physical constants
    it "has speed of light as Quantity" do
      result = run("c")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to eq(299_792_458)
    end

    it "computes E=mc² with constant c" do
      result = run("m = 1 kg\ne = m·c²\ne")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.unit.symbol).to eq("J")
    end

    it "has gravitational constant" do
      result = run("G")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-15).of(6.67430e-11)
    end

    it "has Stefan-Boltzmann constant" do
      result = run("σ")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-14).of(5.670374419e-8)
    end

    it "has elementary charge" do
      result = run("e₀")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-25).of(1.602176634e-19)
    end

    it "has gas constant" do
      result = run("R")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(0.001).of(8.314462618)
    end

    it "has Avogadro constant" do
      result = run("Nₐ")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e17).of(6.02214076e23)
    end

    it "has Boltzmann constant" do
      result = run("kB")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-29).of(1.380649e-23)
    end

    it "has vacuum permittivity" do
      result = run("ε₀")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-18).of(8.8541878188e-12)
    end

    it "has vacuum permeability" do
      result = run("μ₀")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(1e-12).of(1.25663706127e-6)
    end

    it "has standard gravity" do
      result = run("g₀")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(0.001).of(9.80665)
    end
  end

  describe "unit conversion operators" do
    it "converts units with | operator" do
      result = run("42 km | miles")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(0.1).of(26.1)
    end

    it "converts units with » operator" do
      result = run("42 km » miles")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value).to be_within(0.1).of(26.1)
    end

    it "converts after arithmetic with |" do
      result = run("5 kg + 3 kg | lb")
      expect(result.value).to be_within(0.1).of(17.64)
    end

    it "converts to compound units with |" do
      result = run("100 km/h | m/s")
      expect(result.value).to be_within(0.1).of(27.78)
    end

    it "converts inside string interpolation" do
      result = run('"[42 km | miles]"')
      expect(result).to include("miles")
    end

    it "converts temperature with |" do
      result = run("100 °C | °F")
      expect(result.value).to be_within(0.1).of(212.0)
    end

    it "raises on incompatible conversion" do
      expect { run("5 kg | m") }.to raise_error(Tungsten::DimensionError)
    end

    it "preserves bitwise OR for non-Quantity" do
      expect(run("5 | 3")).to eq(7)
    end

    it "raises when » used without Quantity" do
      expect { run("5 » m") }.to raise_error(Tungsten::Error)
    end

    it "converts with per syntax" do
      result = run("1 mph | meters per second")
      expect(result.value.to_f).to be_within(0.001).of(0.44704)
    end
  end

  describe "square and cubic modifiers" do
    it "parses square meters" do
      result = run("10 square meters")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("10 square meters")
    end

    it "parses cubic feet" do
      result = run("1 cubic ft")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.to_s).to eq("1 cubic ft")
    end

    it "converts between square units" do
      result = run("100 square feet | square meters")
      expect(result.value.to_f).to be_within(0.01).of(9.29)
    end

    it "converts cubic cm to liters" do
      result = run("1000 cubic cm | L")
      expect(result.value.to_f).to be_within(0.01).of(1.0)
    end
  end

  describe "multi-unit decomposition" do
    it "decomposes seconds into h, min, s" do
      result = run("90061 s | [h, min, s]")
      expect(result).to be_a(Array)
      expect(result.map { |q| q.value.to_i }).to eq([25, 1, 1])
    end

    it "decomposes with non-clean values" do
      result = run("10000 s | [h, min, s]")
      expect(result).to be_a(Array)
      expect(result[0].value).to eq(2)
      expect(result[1].value).to eq(46)
      expect(result[2].value.to_i).to eq(40)
    end
  end

  describe "time unit completeness" do
    it "has week" do
      result = run("1 week | d")
      expect(result.value.to_f).to be_within(0.01).of(7.0)
    end

    it "has month" do
      result = run("1 month")
      expect(result).to be_a(Tungsten::Quantity)
    end

    it "has year" do
      result = run("1 year | d")
      expect(result.value.to_f).to be_within(0.01).of(365.2425)
    end

    it "has decade" do
      result = run("1 decade | years")
      expect(result.value.to_f).to be_within(0.01).of(10.0)
    end

    it "has millennium" do
      result = run("1 millennium | years")
      expect(result.value.to_f).to be_within(0.01).of(1000.0)
    end

    it "supports plural aliases" do
      result = run("2 weeks | d")
      expect(result.value.to_f).to be_within(0.01).of(14.0)
    end

    it "supports abbreviations" do
      expect(run("1 wk").to_s).to eq("1 wk")
      expect(run("1 yr").to_s).to eq("1 yr")
    end
  end

  describe "currency / currency" do
    it "returns scalar when dividing same currencies" do
      result = run("$10 / $5")
      expect(result).to eq(2)
    end

    it "returns float for non-integer division" do
      result = run("$10 / $3")
      expect(result).to be_within(0.01).of(3.33)
    end

    it "raises on incompatible currency division" do
      expect { run("$10 / €5") }.to raise_error(Tungsten::Error)
    end
  end

  describe "date + quantity arithmetic" do
    it "adds weeks to date" do
      result = run("2026-01-01 + 3 weeks")
      expect(result).to be_a(Tungsten::Date)
      expect(result.to_s).to eq("2026-01-22")
    end

    it "adds days to date" do
      result = run("2026-01-01 + 30 d")
      expect(result.to_s).to eq("2026-01-31")
    end

    it "subtracts days from date" do
      result = run("2026-01-01 - 1 d")
      expect(result.to_s).to eq("2025-12-31")
    end

    it "subtracts two dates returning duration" do
      result = run("2026-03-01 - 2026-01-01")
      expect(result).to be_a(Tungsten::Quantity)
      expect(result.value.to_f).to be_within(0.1).of(59.0)
    end

    it "adds time to datetime" do
      result = run("2026-01-01T12:00:00 + 30 min")
      expect(result.to_s).to include("12:30")
    end

    it "raises on non-time quantity" do
      expect { run("2026-01-01 + 5 kg") }.to raise_error(Tungsten::DimensionError)
    end
  end

  describe "key literals" do
    it "evaluates #[CTRL+D] to a Key" do
      result = run('#[CTRL+D]')
      expect(result).to be_a(Tungsten::Key)
      expect(result.ctrl?).to eq(true)
      expect(result.codepoint).to eq(100)
    end

    it "returns kitty sequence" do
      expect(run('#[CTRL+D].kitty')).to eq("\e[100;5u")
    end

    it "returns legacy encoding" do
      expect(run('#[CTRL+D].legacy')).to eq("\x04")
    end

    it "returns bytes" do
      expect(run('#[CTRL+D].bytes')).to eq([4])
    end

    it "returns name" do
      expect(run('#[CTRL+D].name')).to eq("Ctrl+D")
    end

    it "returns display" do
      expect(run('#[CTRL+D].display')).to eq("\u2303D")
    end

    it "printable? is false for modified key, true for plain letter" do
      expect(run('#[CTRL+D].printable?')).to eq(false)
      expect(run('#[A].printable?')).to eq(true)
    end

    it "functional? is false for letter, true for F-key" do
      expect(run('#[A].functional?')).to eq(false)
      expect(run('#[F1].functional?')).to eq(true)
    end

    it "modifier? is true for modifier-only key" do
      expect(run('#[CTRL].modifier?')).to eq(true)
      expect(run('#[CTRL+D].modifier?')).to eq(false)
    end

    it "all formats evaluate equally" do
      expect(run('#[CTRL+D] == #[ctrl+d]')).to eq(true)
      expect(run('#[CTRL+D] == #[C-d]')).to eq(true)
    end

    it "parses key sequences" do
      result = run('#[S-t u n g]')
      expect(result).to be_a(Array)
      expect(result.size).to eq(4)
      expect(result.first).to be_a(Tungsten::Key)
      expect(result.first.shift?).to eq(true)
    end

    it "returns nil for legacy on SHIFT+ENTER" do
      expect(run('#[SHIFT+ENTER].legacy')).to eq(nil)
    end

    it "combines keys with +" do
      result = run('#[CTRL] + #[D]')
      expect(result).to be_a(Tungsten::Key)
      expect(result.ctrl?).to eq(true)
      expect(result.codepoint).to eq(100)
    end

    it "strips modifier with -" do
      result = run('#[CTRL+D] - #[CTRL]')
      expect(result).to be_a(Tungsten::Key)
      expect(result.ctrl?).to eq(false)
      expect(result.codepoint).to eq(100)
    end

    it "combines modifier + modifier" do
      result = run('#[CTRL] + #[SHIFT]')
      expect(result).to be_a(Tungsten::Key)
      expect(result.ctrl?).to eq(true)
      expect(result.shift?).to eq(true)
      expect(result.modifier?).to eq(true)
    end

    it "from_kitty parses CSI u sequence" do
      result = run('from_kitty("\e[100;5u")')
      expect(result).to be_a(Tungsten::Key)
      expect(result.ctrl?).to eq(true)
      expect(result.codepoint).to eq(100)
    end

    it "from_legacy parses byte" do
      result = run("from_legacy(4)")
      expect(result).to be_a(Tungsten::Key)
      expect(result.ctrl?).to eq(true)
      expect(result.codepoint).to eq(100)
    end

    it "round-trips through kitty" do
      expect(run('from_kitty(#[CTRL+D].kitty) == #[CTRL+D]')).to eq(true)
    end

    it "displays all modifier symbols" do
      expect(run('#[CTRL+ALT+SHIFT+SUPER+A].display')).to eq("\u2303\u2325\u21E7\u2318A")
    end

    it "canonical order for name" do
      expect(run('#[CTRL+ALT+SHIFT+A].name')).to eq("Ctrl+Alt+Shift+A")
    end

    it "reports type as Key" do
      expect(run('#[CTRL+D].type')).to eq("Key")
      expect(run('type(#[CTRL+D])')).to eq("Key")
    end

    it "raises on unknown key" do
      expect { run('#[BLORP]') }.to raise_error(Tungsten::Error, /unknown key/)
    end

    it "raises when adding two base keys" do
      expect { run('#[A] + #[B]') }.to raise_error(Tungsten::Error, /cannot add two base keys/)
    end

    it "SHIFT+ENTER kitty sequence" do
      expect(run('#[SHIFT+ENTER].kitty')).to eq("\e[13;2u")
    end

    it "inspect returns canonical form" do
      result = run('#[CTRL+D]')
      expect(result.inspect).to eq("#[CTRL+D]")
    end
  end

  describe "duration literals" do
    it "evaluates a compact duration" do
      result = run("2h30m")
      expect(result).to be_a(Tungsten::Duration)
      expect(result.seconds).to eq(Rational(9000))
    end

    it "evaluates an ISO 8601 duration" do
      result = run("PT1H30M")
      expect(result).to be_a(Tungsten::Duration)
      expect(result.seconds).to eq(Rational(5400))
    end

    it "displays a duration" do
      expect(run("2h30m").to_s).to eq("2h30m")
    end

    it "adds durations together" do
      result = run("1h30m + 2h45m")
      expect(result).to be_a(Tungsten::Duration)
      expect(result.to_s).to eq("4h15m")
    end

    it "subtracts durations" do
      result = run("2h30m - 1h15m")
      expect(result.to_s).to eq("1h15m")
    end

    it "multiplies duration by scalar" do
      result = run("1h30m * 2")
      expect(result.to_s).to eq("3h")
    end

    it "divides duration by scalar" do
      result = run("4h30m / 3")
      expect(result.to_s).to eq("1h30m")
    end

    it "divides duration by duration" do
      result = run("6h30m / 1h30m")
      expect(result).to eq(Rational(13, 3))
    end

    it "produces a negative duration" do
      result = run("2h30m - 3h30m")
      expect(result).to be_a(Tungsten::Duration)
      expect(result.seconds).to eq(Rational(-3600))
    end

    it "adds whole-day duration to date" do
      result = run("2026-01-01 + 2d")
      expect(result).to be_a(Tungsten::Date)
      expect(result.to_s).to eq("2026-01-03")
    end

    it "adds sub-day duration to date, promoting to datetime" do
      result = run("2026-01-01 + 1d12h")
      expect(result).to be_a(Tungsten::DateTime)
      expect(result.to_s).to include("2026-01-02")
      expect(result.to_s).to include("12:00")
    end

    it "adds duration to datetime" do
      result = run("2026-01-01T12:00:00 + 2h30m")
      expect(result).to be_a(Tungsten::DateTime)
      expect(result.to_s).to include("14:30")
    end

    it "subtracts duration from date" do
      result = run("2026-01-10 - 3d")
      expect(result).to be_a(Tungsten::Date)
      expect(result.to_s).to eq("2026-01-07")
    end

    it "subtracts sub-day duration from date, promoting to datetime" do
      result = run("2026-01-10 - 3d12h")
      expect(result).to be_a(Tungsten::DateTime)
      expect(result.to_s).to include("2026-01-06")
      expect(result.to_s).to include("12:00")
    end

    it "compares durations" do
      expect(run("1h30m > 1h15m")).to eq(true)
      expect(run("30m15s < 1h30m")).to eq(true)
    end

    it "adds nominal months to date with end-of-month clamping" do
      result = run("2026-01-31 + P1M")
      expect(result).to be_a(Tungsten::Date)
      expect(result.to_s).to eq("2026-02-28")
    end

    it "adds nominal years to date across leap year" do
      result = run("2024-02-29 + P1Y")
      expect(result).to be_a(Tungsten::Date)
      expect(result.to_s).to eq("2025-02-28")
    end

    it "adds months and days together" do
      result = run("P1M + P15D")
      expect(result).to be_a(Tungsten::Duration)
      expect(result.months).to eq(1)
      expect(result.seconds).to eq(Rational(15 * 86400))
    end

    it "subtracts months from date" do
      result = run("2026-03-31 - P1M")
      expect(result).to be_a(Tungsten::Date)
      expect(result.to_s).to eq("2026-02-28")
    end

    it "handles ISO duration with months and time" do
      result = run("2026-01-15T10:00:00 + P1MT2H")
      expect(result).to be_a(Tungsten::DateTime)
      expect(result.to_s).to include("2026-02-15")
      expect(result.to_s).to include("12:00")
    end
  end

  describe "byte arrays" do
    it "creates a byte array literal" do
      result = run("« ff 00 a5 »")
      expect(result).to be_a(Tungsten::ByteArray)
      expect(result.bytes).to eq([255, 0, 165])
    end

    it "creates an empty byte array" do
      result = run("« »")
      expect(result).to be_a(Tungsten::ByteArray)
      expect(result.bytes).to eq([])
    end

    it "supports binary prefix" do
      result = run("« 0b11001100 »")
      expect(result).to be_a(Tungsten::ByteArray)
      expect(result.bytes).to eq([204])
    end

    it "supports interpolation with integer" do
      expect(run("x = 255\n« [x] »")).to eq(Tungsten::ByteArray.new([255]))
    end

    it "supports interpolation with byte array splice" do
      expect(run("head = « ff d8 »\n« [head] ff e0 »")).to eq(Tungsten::ByteArray.new([255, 216, 255, 224]))
    end

    it "supports length" do
      expect(run("« ff 00 a5 ».length")).to eq(3)
    end

    it "supports index access" do
      expect(run("« ff 00 a5 »[0]")).to eq(255)
    end

    it "supports concatenation" do
      expect(run("« ff » + « 00 »")).to eq(Tungsten::ByteArray.new([255, 0]))
    end

    it "supports append" do
      expect(run("x = « ff »\nx << « 00 »\nx")).to eq(Tungsten::ByteArray.new([255, 0]))
    end

    it "supports equality" do
      expect(run("« ff 00 » == « ff 00 »")).to eq(true)
      expect(run("« ff 00 » == « ff 01 »")).to eq(false)
    end

    it "supports empty?" do
      expect(run("« ».empty?")).to eq(true)
      expect(run("« ff ».empty?")).to eq(false)
    end

    it "reports type as ByteArray" do
      expect(run("« ff ».type")).to eq("ByteArray")
    end

    it "converts to string representation" do
      expect(run("« ff 00 ».to_s")).to eq("« ff 00 »")
    end

    it "String#bytes returns ByteArray" do
      result = run('"hello".bytes')
      expect(result).to be_a(Tungsten::ByteArray)
      expect(result.bytes).to eq([104, 101, 108, 108, 111])
    end

    it "ByteArray constructor from array" do
      result = run("ByteArray([255, 0, 165])")
      expect(result).to be_a(Tungsten::ByteArray)
      expect(result.bytes).to eq([255, 0, 165])
    end

    it "ByteArray constructor with size" do
      result = run("ByteArray(3)")
      expect(result).to be_a(Tungsten::ByteArray)
      expect(result.bytes).to eq([0, 0, 0])
    end

    it "raises on out-of-range interpolation value" do
      expect { run("x = 256\n« [x] »") }.to raise_error(Tungsten::Error, /out of range/)
    end

    it "raises on out-of-range constructor value" do
      expect { run("ByteArray([256])") }.to raise_error(Tungsten::Error, /out of range/)
    end
  end

  describe "string buffer" do
    it "creates via constructor" do
      result = run("StringBuffer()")
      expect(result).to be_a(Tungsten::StringBuffer)
    end

    it "supports append and to_s" do
      code = "sb = StringBuffer()\nsb.append(\"hello\")\nsb.append(\" world\")\nsb.to_s"
      expect(run(code)).to eq("hello world")
    end

    it "supports length" do
      code = "sb = StringBuffer()\nsb.append(\"hello\")\nsb.length"
      expect(run(code)).to eq(5)
    end

    it "supports empty?" do
      expect(run("StringBuffer().empty?")).to eq(true)
    end

    it "reports type as StringBuffer" do
      expect(run("StringBuffer().type")).to eq("StringBuffer")
    end

    it "supports clear" do
      code = "sb = StringBuffer()\nsb.append(\"hello\")\nsb.clear\nsb.empty?"
      expect(run(code)).to eq(true)
    end

    it "supports byte_size" do
      code = "sb = StringBuffer()\nsb.append(\"hello\")\nsb.byte_size"
      expect(run(code)).to eq(5)
    end
  end

  describe "path values" do
    it "creates via constructor" do
      result = run('Path("/usr/bin")')
      expect(result).to be_a(Tungsten::PathValue)
      expect(result.to_s).to eq("/usr/bin")
    end

    it "supports parent" do
      expect(run('Path("/usr/bin").parent.to_s')).to eq("/usr")
    end

    it "supports name" do
      expect(run('Path("/usr/bin/ruby").name')).to eq("ruby")
    end

    it "supports stem" do
      expect(run('Path("/usr/bin/test.rb").stem')).to eq("test")
    end

    it "supports extension" do
      expect(run('Path("/usr/bin/test.rb").extension')).to eq(".rb")
    end

    it "supports absolute?" do
      expect(run('Path("/usr/bin").absolute?')).to eq(true)
      expect(run('Path("relative").absolute?')).to eq(false)
    end

    it "supports segments" do
      expect(run('Path("/usr/bin/ruby").segments')).to eq(["usr", "bin", "ruby"])
    end

    it "supports / for joining" do
      expect(run('Path("/usr") / "bin"')).to eq(Tungsten::PathValue.new("/usr/bin"))
    end

    it "reports type as Path" do
      expect(run('Path("/tmp").type')).to eq("Path")
    end

    it "supports home_relative?" do
      expect(run('Path("~/docs").home_relative?')).to eq(true)
      expect(run('Path("/tmp").home_relative?')).to eq(false)
    end
  end

  describe "math notation" do
    it "reads x' as the same-named property on the first argument" do
      code = <<~CODE
        + Point
          -> new(@x, @y) ro

          -> dx/1
            x - x'

        << Point(7, 0).dx(Point(3, 0))
      CODE
      expect(output(code)).to eq("4")
    end

    it "reads Δx as x - x' and √ as sqrt" do
      code = <<~CODE
        + Point
          -> new(@x, @y, @z) ro

          -> distance/1
            √(Δx² + Δy² + Δz²)

        << Point(3, 4, 0).distance(Point(0, 0, 0))
      CODE
      expect(output(code)).to eq("5.0")
    end

    it "prefers a defined Δ variable over the delta reading" do
      code = <<~CODE
        -> f
          Δt = 42
          Δt + 1

        << f
      CODE
      expect(output(code)).to eq("43")
    end

    it "swaps variables with <>" do
      code = <<~CODE
        a = 1
        b = 2
        a <> b
        << a
        << b
      CODE
      expect(output(code)).to eq("2\n1")
    end

    it "computes √ of a literal" do
      expect(output("<< √16")).to eq("4.0")
    end

    it "accepts type names as method names after a dot" do
      expect(Tungsten::Parser.parse("Tensor.bf16")).not_to be_nil
    end
  end
end
