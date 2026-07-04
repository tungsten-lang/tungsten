require "support/to_node"

module Tungsten::AST
  describe Tungsten::Printer do
    def self.it_prints(source, expected = source)
      it "prints #{source.inspect}" do
        ast = Tungsten::Parser.parse(source)
        result = ast.to_s
        expect(result).to eq(expected)
      end
    end

    def self.it_roundtrips(source)
      it "roundtrips #{source.inspect}" do
        ast = Tungsten::Parser.parse(source)
        printed = ast.to_s
        # Idempotency: printing the printed output should be identical
        ast2 = Tungsten::Parser.parse(printed)
        expect(ast2.to_s).to eq(printed)
      end
    end

    # ── Literals ─────────────────────────────────────────────────────

    it_prints "nil"
    it_prints "true"
    it_prints "false"
    it_prints "1"
    it_prints "42"
    it_prints ":name"
    it_prints "[1, 2, 3]"
    it_prints "[]"

    it_prints '"hello"'
    it_prints '"hello [name]"'

    it_prints "« »"
    it_prints "« ff 00 a5 »"
    it_roundtrips "« ff 00 a5 »"

    # ── Variables ────────────────────────────────────────────────────

    it_prints "foo"
    it_prints "@name"

    # ── Operators ────────────────────────────────────────────────────

    it_prints "1 + 2"
    it_prints "1 - 2"
    it_prints "1 * 2"
    it_prints "1 / 2"
    it_prints "1 ** 2"
    it_prints "1 % 2"
    it_prints "1 == 2"
    it_prints "1 != 2"
    it_prints "1 < 2"
    it_prints "1 <= 2"
    it_prints "1 > 2"
    it_prints "1 >= 2"
    it_prints "1 && 2"
    it_prints "1 || 2"
    it_prints "!true"

    # ── Assignment ───────────────────────────────────────────────────

    it_prints "x = 1"
    it_prints "x = 1 + 2"

    # ── Calls ────────────────────────────────────────────────────────

    # foo() is parsed as Call with no args, same as bare "foo" — parens not preserved
    it_prints "foo()", "foo"
    it_prints "foo(1)"
    it_prints "foo(1, 2)"
    it_prints "foo.bar"
    it_prints "foo.bar(1)"

    # ── Print / Write ────────────────────────────────────────────────

    it_prints '<< "hello"'
    it_prints '<< 1 + 2', '<< 1 + 2'

    # ── Control flow ─────────────────────────────────────────────────

    it_prints "if x\n  1"
    it_prints "if x\n  1\nelse\n  2"
    it_prints "while x\n  1"

    # ── Definitions ──────────────────────────────────────────────────

    it_prints "-> foo\n  1"
    it_prints "-> foo(x)\n  1"
    it_prints "-> foo(x, y)\n  x + y"

    it_prints "+ Dog\n  -> bark\n    \"woof\""
    it_prints "+ Dog < Animal\n  -> bark\n    \"woof\""

    it_prints "trait Greetable\n  -> greet\n    \"hi\""
    it_prints "module Math\n  -> add(a, b)\n    a + b"

    # ── Keywords ─────────────────────────────────────────────────────

    it_prints "return"
    it_prints "return 1"
    it_prints "break"
    it_prints "break 1"
    it_prints "next"
    it_prints "yield"
    it_prints "yield 1"

    it_prints 'use "foo"'
    it_prints "is Greetable"

    # ── Case ─────────────────────────────────────────────────────────

    it_prints "case x\nwhen 1\n  \"one\""

    # ── Begin/rescue ─────────────────────────────────────────────────

    it_prints "begin\n  1\nrescue\n  2"

    # ── Round-trip tests (idempotency) ───────────────────────────────

    it_roundtrips "x = 1 + 2"
    it_roundtrips '<< "hello world"'
    it_roundtrips "if x > 0\n  1\nelse\n  2"
    it_roundtrips "-> foo(x, y)\n  x + y"
    it_roundtrips "+ Dog\n  -> bark\n    \"woof\""
    it_roundtrips "trait Greetable\n  -> greet\n    \"hi\""
    it_roundtrips "[1, 2, 3]"
    it_roundtrips "while x > 0\n  x = x - 1"
    it_roundtrips "return 42"
    it_roundtrips "begin\n  1\nrescue\n  2"
  end
end
