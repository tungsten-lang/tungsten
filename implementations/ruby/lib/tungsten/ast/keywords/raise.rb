module Tungsten::AST
  class Raise < Node
    attr_accessor :value

    def initialize(value = nil)
      @value = value
    end

    def ==(other)
      super && other.value == value
    end
  end
end
