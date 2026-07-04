# frozen_string_literal: true

module Tungsten
  class MAC < Literal
    def self.parse(text) = new(text)

    def initialize(value)
      @value =
        case value
        when ::Array
          value.map(&:to_i)
        else
          parse_bytes(value.to_s)
        end
      raise Tungsten::Error, "invalid MAC address" unless @value.size == 6 && @value.all? { |byte| byte.between?(0, 255) }
    end

    def to_s = @value.map { |byte| "%02x" % byte }.join(":")
    alias inspect to_s

    def byte(index)
      idx = index.to_i
      idx.between?(0, 5) ? @value[idx] : nil
    end
    alias [] byte

    def bytes = @value.dup
    def multicast? = (byte(0) & 0x01) != 0
    def unicast? = !multicast?
    def local? = (byte(0) & 0x02) != 0
    def universal? = !local?
    def broadcast? = @value.all? { |byte| byte == 0xff }

    private

    def parse_bytes(text)
      if text.match?(/\A[0-9a-f]{2}([:-])[0-9a-f]{2}(?:\1[0-9a-f]{2}){4}\z/i)
        return text.split(/[:-]/).map { |part| part.to_i(16) }
      end
      if text.match?(/\A[0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}\z/i)
        return text.delete(".").scan(/../).map { |part| part.to_i(16) }
      end
      []
    end
  end
end
