# frozen_string_literal: true

require "json"
require "set"

# Data reader shared by build tools and the Ruby engine. No interpreter or
# language implementation is loaded here; all physical definitions are data.
module TungstenUnitRegistry
  AXES = %w[length mass time current temperature substance luminosity information].freeze
  Dimension = Struct.new(*AXES.map(&:to_sym), :customs) do
    def to_a = AXES.map { |axis| public_send(axis) }
  end
  Value = Struct.new(:dimension, :factor, :offset, keyword_init: true)

  class UniqueObject < Hash
    def []=(key, value)
      raise ArgumentError, "duplicate JSON key #{key.inspect}" if key?(key)
      super
    end
  end

  def self.rational(value)
    unless value.is_a?(String) && value.match?(/\A-?\d+(?:\/[1-9]\d*)?\z/)
      raise ArgumentError, "expected an exact integer or rational string, got #{value.inspect}"
    end
    Rational(value)
  end

  def self.read(path)
    # UniqueObject rejects duplicates itself, including on JSON versions that
    # otherwise warn and discard earlier values before returning the object.
    JSON.parse(File.read(path, encoding: "utf-8"), object_class: UniqueObject, allow_duplicate_key: true)
  rescue JSON::ParserError, ArgumentError => e
    raise ArgumentError, "#{path}: #{e.message}"
  end

  class Document
    attr_reader :data, :units, :compounds, :aliases, :prefixes, :prefixable, :binary_prefixable

    def initialize(path)
      @data = TungstenUnitRegistry.read(path)
      raise ArgumentError, "unsupported unit registry schema" unless data["schema"] == "tungsten.units/v1"
      raise ArgumentError, "incorrect dimension axes" unless data["axes"] == AXES
      @units = index(data.fetch("units"))
      @compounds = index(data.fetch("compounds"))
      @aliases = data.fetch("aliases")
      @prefixes = data.fetch("prefixes").transform_values { |p| p.transform_values { |v| TungstenUnitRegistry.rational(v) } }
      @prefixable = Set.new(units.select { |_, u| %w[si both].include?(u.fetch("prefixable")) }.keys + data.fetch("si_prefixable_overrides"))
      @binary_prefixable = Set.new(units.select { |_, u| %w[binary both].include?(u.fetch("prefixable")) }.keys + data.fetch("binary_prefixable_overrides"))
      @cache = {}
      units.each_value do |u|
        dimension(u.fetch("dimension"))
        raise ArgumentError, "invalid prefix policy for #{u['symbol']}" unless %w[none si binary both].include?(u['prefixable'])
        raise ArgumentError, "invalid kind for #{u['symbol']}" unless %w[unit contextual_reference reference_quantity reference_scale physical_constant contextual_unit nominal_unit].include?(u['kind'])
        raise ArgumentError, "zero unit factor for #{u['symbol']}" if TungstenUnitRegistry.rational(u.fetch("factor")).zero?
        TungstenUnitRegistry.rational(u.fetch("offset"))
      end
      aliases.each do |name, target|
        validate_name(name)
        raise ArgumentError, "unknown alias target #{target.inspect}" unless units.key?(target) || compounds.key?(target)
      end
      (prefixable | binary_prefixable).each do |name|
        raise ArgumentError, "unknown prefixable unit #{name}" unless units.key?(name)
      end
      compounds.each_key { |name| resolve(name) }
    rescue ArgumentError, KeyError => e
      raise ArgumentError, "#{path}: #{e.message}"
    end

    def dimension(record)
      powers, semantic = record.fetch("powers"), record.fetch("semantic")
      unless powers.size == 8 && powers.all? { |v| v.is_a?(Integer) && (-128..127).cover?(v) } &&
             semantic.is_a?(Hash) && semantic.all? { |k, v| k.is_a?(String) && !k.empty? && v.is_a?(Integer) && v != 0 && (-128..127).cover?(v) }
        raise ArgumentError, "invalid dimension #{record.inspect}"
      end
      Dimension.new(*powers, semantic)
    end

    # The compound grammar is deliberately small: products and quotients of
    # atomic names (including prefixes), with integer powers. Compound records
    # cannot recursively refer to other compound records.
    def resolve(name, atomic: false)
      key = [name, atomic]
      return @cache[key] if @cache.key?(key)
      canonical = aliases.fetch(name, name)
      result = if !atomic && compounds.key?(canonical)
                 row = compounds.fetch(canonical)
                 base = resolve(row.fetch("expression"), atomic: true)
                 Value.new(dimension: base.dimension, factor: base.factor * TungstenUnitRegistry.rational(row.fetch("scale")), offset: base.offset)
               elsif units.key?(canonical)
                 row = units.fetch(canonical)
                 Value.new(dimension: dimension(row.fetch("dimension")), factor: TungstenUnitRegistry.rational(row.fetch("factor")), offset: TungstenUnitRegistry.rational(row.fetch("offset")))
               else
                 resolve_prefix_or_expression(name, atomic)
               end
      @cache[key] = result
    end

    private

    def validate_name(name)
      unless name.is_a?(String) && !name.empty? && name == name.strip && !name.match?(/[\x00-\x1f\x7f]/)
        raise ArgumentError, "invalid unit name #{name.inspect}"
      end
    end

    def index(rows)
      rows.each_with_object({}) do |row, hash|
        name = row.fetch("symbol")
        validate_name(name)
        raise ArgumentError, "duplicate unit #{name.inspect}" if hash.key?(name)
        hash[name] = row
      end
    end

    def combine(left, right, sign)
      semantic = left.dimension.customs.dup
      right.dimension.customs.each { |name, power| semantic[name] = semantic.fetch(name, 0) + sign * power }
      semantic.reject! { |_, power| power.zero? }
      Value.new(dimension: Dimension.new(*left.dimension.to_a.zip(right.dimension.to_a).map { |a, b| a + sign * b }, semantic),
                factor: left.factor * right.factor**sign, offset: 0)
    end

    def resolve_prefix_or_expression(name, atomic)
      if name.start_with?("(") && name.end_with?(")")
        return resolve(name[1...-1], atomic: atomic)
      end
      if data.fetch("legacy_symbols").include?(name)
        return Value.new(dimension: Dimension.new(*Array.new(8, 0), {name => 1}), factor: 1, offset: 0)
      end
      normalized = name.gsub(/[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]+/) { |s| "^" + s.tr("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻", "0123456789+-") }
      return resolve(normalized, atomic: atomic) if normalized != name
      %w[si long binary].each do |system|
        prefixes.fetch(system).each do |prefix, multiplier|
          next unless name.start_with?(prefix)
          base = name.delete_prefix(prefix)
          base = aliases.fetch(base, base) if system == "long"
          eligible = system == "binary" ? binary_prefixable : prefixable
          next unless eligible.include?(base) || (!atomic && system == "si" && compounds.key?(base))
          value = resolve(base, atomic: atomic)
          return Value.new(dimension: value.dimension, factor: value.factor * multiplier,
                           offset: !atomic && compounds.key?(base) ? value.offset : 0)
        end
      end
      if name.include?("/")
        left, right = name.split("/", 2)
        return combine(resolve(left, atomic: atomic), resolve(right, atomic: atomic), -1)
      end
      if name.match?(/[*·]/)
        return name.split(/[*·]/).map { |part| resolve(part, atomic: atomic) }.reduce { |a, b| combine(a, b, 1) }
      end
      if (match = /\A(.+)\^(-?\d+)\z/.match(name))
        base, power = resolve(match[1], atomic: atomic), Integer(match[2])
        return Value.new(dimension: Dimension.new(*base.dimension.to_a.map { |v| v * power }, base.dimension.customs.transform_values { |v| v * power }), factor: base.factor**power, offset: 0)
      end
      return Value.new(dimension: Dimension.new(*Array.new(8, 0), {}), factor: 1, offset: 0) if name == "1"
      raise ArgumentError, "undefined registry unit #{name.inspect}"
    end
  end
end
