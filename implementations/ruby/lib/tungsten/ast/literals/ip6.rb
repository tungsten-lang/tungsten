require "ipaddr"

module Tungsten::AST
  class IP6 < Value
    def initialize(value)
      @value = IPAddr.new(value.to_s)
    end

    def eval_in(interp)
      interp.visit_ip6(self)
    end
  end
end
