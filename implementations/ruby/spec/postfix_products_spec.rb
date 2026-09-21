require "support/to_node"

module Tungsten::AST
  describe "postfix factorial and primorial" do
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

        it "desugars literal and variable suffixes" do
          expect(parse("10!")).to eq(Call.new(10.int, "factorial", []))
          expect(parse("10#")).to eq(Call.new(10.int, "primorial", []))
          expect(parse("n#")).to eq(Call.new("n".var, "primorial", []))
          expect(parse("10!.to_s")).to eq(Call.new(Call.new(10.int, "factorial", []), "to_s"))
        end

        it "accepts grouped expressions and call results" do
          sum = BinaryOp.new("a".var, :+, "b".var)
          expect(parse("(a + b)!")).to eq(Call.new(sum, "factorial", []))
          expect(parse("(a + b)#")).to eq(Call.new(sum, "primorial", []))
          expect(parse("((a + b))!")).to eq(Call.new(sum, "factorial", []))
          expect(parse("(\na + b\n)!")).to eq(Call.new(sum, "factorial", []))
          expect(parse("(\na + b\n)#")).to eq(Call.new(sum, "primorial", []))
          expect(parse("(n)!")).to eq(Call.new("n".var, "factorial", []))
          expect(parse("(n!)!")).to eq(Call.new("n!".var, "factorial", []))
          expect(parse("(list.first)!")).to eq(Call.new(Call.new("list".var, "first"), "factorial", []))
          expect(parse("(f())#")).to eq(Call.new(Call.new(nil, "f", []), "primorial", []))
          expect(parse("(a + b)!.to_s")).to eq(Call.new(Call.new(sum, "factorial", []), "to_s"))
          expect(parse("(a + b)! ** 2")).to eq(BinaryOp.new(Call.new(sum, "factorial", []), :**, 2.int))
          expect(parse("!(a + b)")).to eq(Not.new(sum))
          expect(parse("!(a + b)!")).to eq(Not.new(Call.new(sum, "factorial", [])))
        end

        it "rejects spaces and suffixes on ungrouped call results" do
          ["10 !", "n !", "(n) !", "(a + b) !", "(a + b)\t!", "(\na + b\n) !", "f()!", "f()#", "list.first#", "list[0]!", "3!#", "3#!", "n!#", "n!!", "(a + b)!#", "(a + b)#!", "(a + b)!!", "Int!", "Int#"].each do |source|
            expect { Tungsten::Parser.parse(source) }.to raise_error(Tungsten::Error), source
          end
          expect(parse("list.first!")).to eq(Call.new("list".var, "first!"))
          expect(parse("bang!()")).to eq(Call.new(nil, "bang!", []))
        end

        it "binds before arithmetic and exponentiation" do
          expect(parse("2 + 3!")).to eq(BinaryOp.new(2.int, :+, Call.new(3.int, "factorial", [])))
          expect(parse("3! ** 2")).to eq(BinaryOp.new(Call.new(3.int, "factorial", []), :**, 2.int))
          expect(parse("2 ** 3!")).to eq(BinaryOp.new(2.int, :**, Call.new(3.int, "factorial", [])))
        end

        it "preserves bang names, prefix not, comparisons, comments and hints" do
          expect(parse("sort!")).to eq("sort!".var)
          expect(parse("!false")).to eq(Not.new(false.boolean))
          expect(parse("10 != 3")).to eq(BinaryOp.new(10.int, :!=, 3.int))
          expect(parse("10 # comment")).to eq(10.int)
          expect(parse("(a + b) # comment")).to eq(BinaryOp.new("a".var, :+, "b".var))
          expect(parse("10# # comment")).to eq(Call.new(10.int, "primorial", []))
          expect(parse("10 ## i64")).to be_a(TypeHint)
        end
      end
    end
  end
end
