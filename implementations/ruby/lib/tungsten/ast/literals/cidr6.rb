require "ipaddr"

module Tungsten::AST
  class CIDR6 < Value
    def initialize(value)
      @value = IPAddr.new(value.to_s)
    end

    def eval_in(interp)
      interp.visit_cidr6(self)
    end
  end
end
