# frozen_string_literal: true

module Tungsten
  class Literal
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def to_s = @value.to_s
    def inspect = to_s

    def ==(other)
      case other
      when Literal then @value == other.value
      else @value == other
      end
    end

    def <=>(other)
      case other
      when Literal then @value <=> other.value
      else @value <=> other
      end
    end

    def hash = @value.hash
    def eql?(other) = self.class == other.class && @value.eql?(other.value)

    private

    def method_missing(name, *args, &block)
      @value.respond_to?(name) ? @value.public_send(name, *args, &block) : super
    end

    def respond_to_missing?(name, include_private = false)
      @value.respond_to?(name, include_private) || super
    end
  end
end
