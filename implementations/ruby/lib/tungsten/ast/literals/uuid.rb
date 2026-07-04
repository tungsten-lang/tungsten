require "uuidtools"

module Tungsten::AST
  class UUID < Value
    def initialize(value)
      @value = UUIDTools::UUID.parse(value.to_s)
    end
  end
end
