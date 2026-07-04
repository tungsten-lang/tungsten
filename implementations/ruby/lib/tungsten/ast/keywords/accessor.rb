module Tungsten::AST
  class Accessor < Node
    attr_accessor :field, :writable

    def initialize(field, writable: false)
      @field = field
      @writable = writable
    end

    def ==(other)
      super && other.field == field && other.writable == writable
    end
  end
end
