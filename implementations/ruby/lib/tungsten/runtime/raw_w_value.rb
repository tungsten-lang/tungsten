# frozen_string_literal: true

module Tungsten
  module Runtime
    class RawWValue
      attr_reader :bits, :raw

      def initialize(bits, raw = nil)
        @bits = bits.to_i
        @raw = raw || format("u0x%016X", @bits)
      end

      def ==(other)
        case other
        when RawWValue
          bits == other.bits
        when Integer
          bits == other
        else
          false
        end
      end

      alias eql? ==

      def hash
        bits.hash
      end

      def inspect
        raw
      end

      def to_s
        raw
      end
    end
  end
end
