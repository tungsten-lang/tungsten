module Tungsten::AST
  class StringInterpolation < Node
    attr_accessor :parts

    def initialize(parts = [])
      @parts = parts
    end

    def children
      @parts.each { |part| yield part if part.is_a?(Node) }
    end
  end
end
