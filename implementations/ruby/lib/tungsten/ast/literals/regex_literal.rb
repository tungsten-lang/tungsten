module Tungsten::AST
  class RegexLiteral < Value
    attr_reader :pattern, :options

    def initialize(pattern, options = "")
      @pattern = pattern.to_s
      @options = options.to_s
      flags = 0
      flags |= Regexp::IGNORECASE if @options.include?("i")
      flags |= Regexp::MULTILINE if @options.include?("m")
      flags |= Regexp::EXTENDED if @options.include?("x")
      @value = Regexp.new(@pattern, flags)
    end
  end
end
