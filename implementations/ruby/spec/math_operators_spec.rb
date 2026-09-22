require "support/to_node"

module Tungsten::AST
  describe "mathematical operators" do
    %w[regex codepoint].each do |mode|
      context "with the #{mode} lexer" do
        around do |example|
          previous = ENV["TUNGSTEN_LEXER"]
          ENV["TUNGSTEN_LEXER"] = mode
          example.run
        ensure
          previous ? ENV["TUNGSTEN_LEXER"] = previous : ENV.delete("TUNGSTEN_LEXER")
        end

        def parse(source)
          Tungsten::Parser.parse(source).first
        end

        it "constructs composition without evaluating either operand" do
          node = parse("f ∘ g")
          expect(node).to be_a(Def)
          call = node.body.first
          expect(call.name).to eq("f")
          expect(call.args.first.name).to eq("g")
          expect(parse("(->(x) x + 1) ∘ g").body.first.obj).to be_a(Def)
        end

        it "does not capture or overwrite source names with generated temporaries" do
          code = <<~W
            -> compose(__composition_arg, other)
              __composition_arg ∘ other
            f = ->(x) x + 10
            g = ->(x) x * 3
            compose(f, g).call(4)
          W
          expect(Tungsten::Interpreter.new.run(code)).to eq(22)
          expect(Tungsten::Interpreter.new.run("__comparison_2_3 = 77\n1 < 2 < 3\n__comparison_2_3")).to eq(77)
        end

        it "rejects calls with arguments and noncallable composition operands" do
          ["f(1) ∘ g", "f ∘ obj.g(1)", "1 ∘ g", "f ∘ true"].each do |source|
            expect { parse(source) }.to raise_error(Tungsten::Error, /composition requires/)
          end
        end

        it "short circuits comparison chains with one saved middle operand" do
          node = parse("a() <= b() < c()")
          expect(node).to be_a(And)
          expect(node.left.right).to be_a(Assign)
          expect(node.left.right.value.name).to eq("b")
          expect(node.right.left).to eq(node.left.right.name)
          expect(node.right.right.name).to eq("c")
          expect(parse("(a < b) < c")).to be_a(BinaryOp)
          expect(parse("a < b < c < d").right).to be_a(And)
        end

        it "uses right associated tetration at power precedence" do
          node = parse("2 ↑↑ 3 ↑↑ 2")
          expect(node.name).to eq("tetrate")
          expect(node.args.first.name).to eq("tetrate")
          expect(parse("1 + 2 ↑↑ 3").right.name).to eq("tetrate")
        end

        it "keeps membership evaluation order and set precedence" do
          node = parse("item() ∈ collection()")
          expect(node).to be_a(Begin)
          expect(node.body.first.value.name).to eq("item")
          expect(node.body.last.name).to eq("include?")
          expect(parse("a ∪ b ∩ c").args.first.name).to eq("intersect")
          expect(parse("a ⊆ b").name).to eq("subset?")
          expect(parse("x ∉ a").body.last).to be_a(Not)
        end
      end
    end
  end
end
