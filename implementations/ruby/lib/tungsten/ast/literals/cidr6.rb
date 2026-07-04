require "ipaddr"

module Tungsten::AST
  class CIDR6 < Value
    def initialize(value)
      @value = IPAddr.new(value.to_s)
    end
  end
end
