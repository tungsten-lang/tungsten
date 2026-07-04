# frozen_string_literal: true

module Tungsten
  class ByteArray
    include Enumerable

    attr_reader :bytes

    def initialize(bytes = [])
      @bytes = bytes.dup
      @bytes.each { |b| validate_byte!(b) }
      @frozen = false
    end

    def length
      @bytes.length
    end
    alias size length

    def [](index)
      @bytes[index]
    end

    def []=(index, value)
      raise Tungsten::Error, "can't modify frozen ByteArray" if @frozen
      validate_byte!(value)
      @bytes[index] = value
    end

    def <<(value)
      raise Tungsten::Error, "can't modify frozen ByteArray" if @frozen
      if value.is_a?(ByteArray)
        @bytes.concat(value.bytes)
      else
        validate_byte!(value)
        @bytes << value
      end
      self
    end

    def +(other)
      case other
      when ByteArray then ByteArray.new(@bytes + other.bytes)
      when Integer
        validate_byte!(other)
        ByteArray.new(@bytes + [ other ])
      else raise Tungsten::Error, "can only concatenate ByteArray with ByteArray or Integer"
      end
    end

    def ==(other)
      other.is_a?(ByteArray) && @bytes == other.bytes
    end
    alias eql? ==

    def hash
      @bytes.hash
    end

    def each(&block)
      @bytes.each(&block)
    end

    def slice(start, length = nil)
      sliced = length ? @bytes[start, length] : @bytes[start]
      return sliced if sliced.is_a?(Integer)
      ByteArray.new(sliced || [])
    end

    def empty?
      @bytes.empty?
    end

    def freeze
      @frozen = true
      @bytes.freeze
      super
    end

    def frozen?
      @frozen
    end

    def to_s
      hex = @bytes.map { |b| b.to_s(16).rjust(2, "0") }.join(" ")
      @bytes.empty? ? "« »" : "« #{hex} »"
    end

    def inspect
      to_s
    end

    def hex
      @bytes.map { |b| b.to_s(16).rjust(2, "0") }.join(" ")
    end

    def to_a
      @bytes.dup
    end

    private

    def validate_byte!(value)
      raise Tungsten::Error, "byte value #{value} out of range (0-255)" unless value.is_a?(Integer) && value >= 0 && value <= 255
    end
  end
end
