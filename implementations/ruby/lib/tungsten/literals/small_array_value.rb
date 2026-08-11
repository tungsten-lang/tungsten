# frozen_string_literal: true

module Tungsten
  # Ruby tree-walker representation of the runtime's fixed-size packed array.
  # Element stores retain the native tier's coercion and out-of-bounds rules;
  # structural growth remains forbidden while in-place element replacement is
  # allowed.
  class SmallArrayValue < Array
    ELEMENT_TYPES = {
      "bool" => [:bool, 1],
      "u1" => [:bool, 1],
      "u4" => [:unsigned, 4],
      "i4" => [:signed, 4],
      "u8" => [:unsigned, 8],
      "i8" => [:signed, 8],
      "u16" => [:unsigned, 16],
      "i16" => [:signed, 16],
      "u32" => [:unsigned, 32],
      "i32" => [:signed, 32],
      "u64" => [:unsigned, 64],
      "i64" => [:signed, 64],
      "w64" => [:value, 64],
      "f16" => [:float, 16],
      "bf16" => [:float, 16],
      "f32" => [:float, 32],
      "f64" => [:float, 64],
      "f8_e4m3" => [:float, 8],
      "f8_e5m2" => [:float, 8],
      "f4_e2m1" => [:float, 4]
    }.freeze
    EBITS_NAMES = {
      1 => "u1", 4 => "u4", -4 => "i4", 8 => "u8", 108 => "i8",
      16 => "u16", 116 => "i16", 32 => "u32", 33 => "i32",
      64 => "u64", 65 => "w64", 66 => "i64", -16 => "f16",
      -32 => "f32", -64 => "f64", -104 => "f4_e2m1",
      -108 => "f8_e4m3", -109 => "f8_e5m2", -116 => "bf16"
    }.freeze

    attr_reader :element_type

    def initialize(element_type, count)
      unless count.is_a?(Integer)
        raise Tungsten::Error, "SmallArray size must be an Integer"
      end
      unless count.between?(0, 255)
        raise Tungsten::Error, "SmallArray size must be 0..255"
      end

      type_name = element_type.is_a?(Integer) ? EBITS_NAMES[element_type] : element_type.to_s
      @storage_kind, @element_bits = ELEMENT_TYPES[type_name]
      raise Tungsten::Error, "SmallArray has an unsupported element type" unless @storage_kind

      @element_type = type_name.to_sym
      super(count, default_value)
    end

    def cap = size

    def []=(index, value)
      position = Integer(index)
      position += size if position.negative?
      return value unless position.between?(0, size - 1)

      super(position, coerce(value))
      value
    end

    def push(*) = structural_mutation!
    def <<(*) = structural_mutation!
    def pop(*) = structural_mutation!
    def shift(*) = structural_mutation!
    def unshift(*) = structural_mutation!
    def insert(*) = structural_mutation!
    def concat(*) = structural_mutation!
    def clear(*) = structural_mutation!
    def delete(*) = structural_mutation!
    def delete_at(*) = structural_mutation!
    def slice!(*) = structural_mutation!

    private

    def default_value
      case @storage_kind
      when :value then nil
      when :bool then false
      when :float then 0.0
      else 0
      end
    end

    def coerce(value)
      case @storage_kind
      when :value
        value
      when :bool
        !value.nil? && value != false
      when :float
        value.to_f
      when :unsigned
        value.to_i & ((1 << @element_bits) - 1)
      when :signed
        modulus = 1 << @element_bits
        result = value.to_i & (modulus - 1)
        result >= (modulus >> 1) ? result - modulus : result
      end
    end

    def structural_mutation!
      raise Tungsten::Error, "SmallArray has fixed size"
    end
  end
end
