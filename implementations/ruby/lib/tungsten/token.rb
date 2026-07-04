module Tungsten
  class Token
    attr_accessor :type, :value
    attr_accessor :file, :row, :col

    ASSIGNMENT_OPERATORS = %i[+= -= *= /= //= %= |= &= ^= **= <<= >>= ||= &&=]

    def initialize
      @type = nil

      @row = @col = 0
    end

    def comma?
      @type == :","
    end

    def keyword?(sym)
      @type == :KEYWORD && @value == sym
    end

    def location
      @location ||= Location.new(file, row, col)
    end

    def location=(loc)
      @location = loc
    end

    def reset_location
      @location = nil
    end

    def type?(sym)
      @type == sym
    end

    def to_s
      "<Token #{@row}:#{@col} #{type.inspect}#{ value ? ", " + value.to_s : "" }>"
    end

    def inspect
      to_s
    end

    def suffix?
      @type == :KEYWORD && %i[if unless while until rescue ensure].include?(@value)
    end

    def whitespace?
      @type == :SP || @type == :NL
    end

    # &+= &-= &*= ?
    def assignment_operator?
      ASSIGNMENT_OPERATORS.include?(type)
    end

    def assignment_operators
      ASSIGNMENT_OPERATORS
    end
  end
end
