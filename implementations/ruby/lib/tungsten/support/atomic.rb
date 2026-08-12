# frozen_string_literal: true

module Tungsten
  # Reference-host implementation of Tungsten's sequentially consistent
  # signed-i64 Atomic cell. Ruby's Mutex supplies the ordering and exclusion
  # contract; arithmetic wraps to signed i64 like the C11 atomic operations.
  class Atomic
    MIN = -(1 << 63)
    MAX = (1 << 63) - 1
    MASK = (1 << 64) - 1

    def initialize(value)
      @mutex = Mutex.new
      @value = validate_i64(value)
    end

    def load = @mutex.synchronize { @value }

    def store(value)
      value = validate_i64(value)
      @mutex.synchronize { @value = value }
    end

    def exchange(value)
      value = validate_i64(value)
      @mutex.synchronize do
        old = @value
        @value = value
        old
      end
    end

    def compare_exchange(expected, desired)
      expected = validate_i64(expected)
      desired = validate_i64(desired)
      @mutex.synchronize do
        next false unless @value == expected

        @value = desired
        true
      end
    end

    def fetch_add(delta)
      delta = validate_i64(delta)
      @mutex.synchronize do
        old = @value
        @value = wrap_i64(old + delta)
        old
      end
    end

    def fetch_sub(delta)
      delta = validate_i64(delta)
      @mutex.synchronize do
        old = @value
        @value = wrap_i64(old - delta)
        old
      end
    end

    def increment
      @mutex.synchronize { @value = wrap_i64(@value + 1) }
    end

    def decrement
      @mutex.synchronize { @value = wrap_i64(@value - 1) }
    end

    alias get load
    alias set store
    alias cas compare_exchange
    alias add fetch_add

    private

    def validate_i64(value)
      unless value.is_a?(Integer)
        raise Tungsten::Error, "Atomic expects an Integer"
      end
      unless value.between?(MIN, MAX)
        raise Tungsten::Error, "integer is out of range for i64"
      end

      value
    end

    def wrap_i64(value)
      value &= MASK
      value > MAX ? value - (1 << 64) : value
    end
  end
end
