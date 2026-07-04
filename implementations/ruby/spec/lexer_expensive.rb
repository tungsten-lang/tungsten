describe Tungsten::Lexer, order: :defined do
  class << self
    def it_lexes(string, type, value=nil)
      it "lexes #{string}" do
        lexer = described_class.new(string)
        token = lexer.next_token

        expect(token.type).to  eq(type)
        expect(token.value).to eq(value)
      end
    end

    def it_lexes_all(name, string, *types)
      it "lexes #{name}" do
        lexer = described_class.new(string)

        while token = lexer.next_token
          break if token.type == :EOF

          expect(token.type).to eq(types.shift)
        end
      end
    end

    def lexes(name, sym)
      define_singleton_method(:"it_lexes_#{name}") do |*args|
        args = args.first if args.first.is_a? Array
        args.each do |arg|
          it_lexes arg, sym, arg
        end
      end
    end
  end

  lexes "times", :TIME

  times = []

  (0..23).each do |hour|
    (0..59).each do |min|
      times << "%02d:%02d" % [hour, min]

      (0..59).each do |sec|
        times << "%02d:%02d:%02d" % [hour, min, sec]
      end
    end
  end

  puts
  puts "testing #{times.size} times"

  it_lexes_times times
end
