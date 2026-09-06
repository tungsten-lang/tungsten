# frozen_string_literal: true

require "tmpdir"
require_relative "../../scripts/lib/unit_registry"

class UnitRegistryDataTest
  PATH = File.expand_path("../../data/unit_registry.json", __dir__)

  def assert_equal(expected, actual)
    raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end

  def assert_includes(text, part)
    raise "#{text.inspect} does not include #{part.inspect}" unless text.include?(part)
  end

  def refute(value)
    raise "unexpected #{value.inspect}" if value
  end

  def assert_raises(type)
    begin
      yield
    rescue type => error
      return error
    end
    raise "expected #{type}"
  end

  def test_exact_and_semantic_definitions_without_loading_an_engine
    registry = TungstenUnitRegistry::Document.new(PATH)
    assert_equal Rational(1602176634, 10**28), registry.resolve("eV").factor
    assert_equal Rational(5, 9), registry.resolve("°F").factor
    assert_equal Rational(45967, 180), registry.resolve("°F").offset
    assert_equal({"cycle" => 1}, registry.resolve("Hz").dimension.customs)
    assert_equal({"decay" => 1}, registry.resolve("Bq").dimension.customs)
    assert_equal 1024, registry.resolve("Kib").factor / registry.resolve("b").factor
    refute defined?(Tungsten::Interpreter)
  end

  def test_rejects_corrupt_definitions
    original = JSON.parse(File.read(PATH))
    changes = [
      ->(d) { d["schema"] = "unknown" },
      ->(d) { d["units"] << d["units"].first.dup },
      ->(d) { d["units"][0]["factor"] = 0.1 },
      ->(d) { d["units"][0]["factor"] = "1/0" },
      ->(d) { d["units"][0]["dimension"]["powers"] = [1] },
      ->(d) { d["aliases"]["new_alias"] = "absent_definition" },
      ->(d) { d["compounds"][0]["expression"] = "absent_definition/s" },
    ]
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, "registry.json")
      changes.each do |change|
        copy = Marshal.load(Marshal.dump(original))
        change.call(copy)
        File.write(path, JSON.generate(copy))
        error = assert_raises(ArgumentError) { TungstenUnitRegistry::Document.new(path) }
        assert_includes error.message, path
      end
      File.write(path, '{"schema":"a","schema":"b"}')
      assert_raises(ArgumentError) { TungstenUnitRegistry::Document.new(path) }
    end
  end
end

tests = UnitRegistryDataTest.new
tests.test_exact_and_semantic_definitions_without_loading_an_engine
tests.test_rejects_corrupt_definitions
puts "external unit definitions: PASS"
