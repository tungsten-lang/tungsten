# frozen_string_literal: true

module Tungsten
  class StringBuffer
    def initialize(capacity = 0)
      @str = String.new(encoding: Encoding::UTF_8, capacity: capacity)
    end

    def append(value)
      str = value.to_s
      str = str.encode(Encoding::UTF_8) unless str.encoding == Encoding::UTF_8
      @str << str
      self
    end
    alias << append

    def to_s
      @str.dup.freeze
    end

    def length
      @str.length
    end
    alias size length

    def byte_size
      @str.bytesize
    end

    def [](index)
      @str[index]
    end

    def clear
      @str.clear
      self
    end

    def empty?
      @str.empty?
    end

    def ==(other)
      case other
      when StringBuffer then @str == other.to_s
      when String then @str == other
      else false
      end
    end

    def inspect
      "StringBuffer(#{@str.inspect})"
    end
  end
end
