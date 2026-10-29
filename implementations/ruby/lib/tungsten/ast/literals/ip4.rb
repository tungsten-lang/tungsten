require "ipaddr"

module Tungsten::AST
  class IP4 < Value
    def initialize(value)
      @value = IPAddr.new(value.to_s)
    end

    def eval_in(interp)
      interp.visit_ip4(self)
    end
  end
end
