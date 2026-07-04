module Tungsten::AST
  class ByteArrayInterpolation < Node
    attr_accessor :parts

    def initialize(parts = [])
      @parts = parts
    end

    def children
      @parts.each { |part| yield part if part.is_a?(Node) }
    end
  end
end
