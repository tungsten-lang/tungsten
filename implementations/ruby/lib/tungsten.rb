# frozen_string_literal: true

require_relative "tungsten/version"
require_relative "tungsten/types"

module Tungsten
  LEXER_MODE_ENV = "TUNGSTEN_LEXER"

  # Process-wide default for compound-unit display style:
  # :slash (default, "m/s"), :dot_negative ("m·s⁻¹"), :words ("meters per second").
  # Per-Quantity preference (q.display(compound: ...)) overrides this.
  @compound_display = :slash
  class << self
    attr_accessor :compound_display
  end

  # Comma-decimal locales (fr, de, es, it, …) where users naturally write
  # `1,5 m`. The lexer canonicalizes to dot-decimal — see normalize_decimal_comma.
  COMMA_DECIMAL_LOCALES = %w[
    fr de es it pt nl pl ru sv no da fi cs sk hu ro el tr bg hr sl uk
  ].freeze

  # Heuristically detect whether the current process locale uses comma as the
  # decimal separator. Reads LC_NUMERIC, LC_ALL, then LANG.
  def self.comma_decimal_locale?
    locale = ENV["LC_NUMERIC"] || ENV["LC_ALL"] || ENV["LANG"] || ""
    return false if locale.empty? || locale.start_with?("C", "POSIX")
    code = locale.downcase.split(/[._-]/).first
    COMMA_DECIMAL_LOCALES.include?(code)
  end

  # Rewrites comma-as-decimal to dot-as-decimal in places where the comma is
  # unambiguously inside a number — digit, comma, digit with no whitespace.
  # Underscores remain valid thousands separators (`1_000_000,5`). Avoids
  # touching commas in arg lists, function calls, etc.
  def self.normalize_decimal_comma(src)
    src.gsub(/(?<=\d),(?=\d)/, ".")
  end

  class Error < StandardError
    attr_accessor :location, :source_code, :file_path, :call_stack, :name_length
  end

  DimensionError = Class.new(Error)

  # Core
  autoload :AST,                 "tungsten/ast"
  autoload :Bytecode,            "tungsten/bytecode"
  autoload :Compiler,            "tungsten/compiler"
  autoload :CodepointLexer,      "tungsten/codepoint_lexer"
  autoload :Doctor,              "tungsten/doctor"
  autoload :Environment,         "tungsten/environment"
  autoload :ErrorReporter,       "tungsten/error_reporter"
  autoload :ExampleExpectations, "tungsten/example_expectations"
  autoload :Formatter,           "tungsten/formatter"
  autoload :Interpreter,         "tungsten/interpreter"
  autoload :Lexer,               "tungsten/lexer"
  autoload :Loader,              "tungsten/loader"
  autoload :Location,            "tungsten/location"
  autoload :Node,                "tungsten/node"
  autoload :Parser,              "tungsten/parser"
  autoload :Printer,             "tungsten/printer"
  autoload :REPL,                "tungsten/repl"
  autoload :Target,              "tungsten/target"
  autoload :Token,               "tungsten/token"
  autoload :Type,                "tungsten/type"
  autoload :Visitor,             "tungsten/visitor"

  # Literals
  autoload :ByteArray,           "tungsten/literals/byte_array"
  autoload :CharValue,           "tungsten/literals/char_value"
  autoload :CIDR,                "tungsten/literals/cidr4"
  autoload :CIDR4,               "tungsten/literals/cidr4"
  autoload :Color,               "tungsten/literals/color"
  autoload :Crypto,              "tungsten/support/crypto"
  autoload :CIDR6,               "tungsten/literals/cidr6"
  autoload :Currency,            "tungsten/literals/currency"
  autoload :Calibration,         "tungsten/literals/calibration"
  autoload :CalibrationCertificate, "tungsten/literals/calibration"
  autoload :Date,                "tungsten/literals/date"
  autoload :DateTime,            "tungsten/literals/date_time"
  autoload :Digest,              "tungsten/support/crypto"
  autoload :Duration,            "tungsten/literals/duration"
  autoload :IPv4,                "tungsten/literals/ip4"
  autoload :IPv6,                "tungsten/literals/ip6"
  autoload :IP4,                 "tungsten/literals/ip4"
  autoload :IP6,                 "tungsten/literals/ip6"
  autoload :Key,                 "tungsten/literals/key"
  autoload :Literal,             "tungsten/literals/literal"
  autoload :LogQuantity,         "tungsten/literals/log_quantity"
  autoload :MAC,                 "tungsten/literals/mac"
  autoload :Measurement,         "tungsten/literals/measurement"
  autoload :Month,               "tungsten/literals/month"
  autoload :PathValue,           "tungsten/literals/path_value"
  autoload :Percentage,          "tungsten/literals/percentage"
  autoload :Quantity,            "tungsten/literals/quantity"
  autoload :Random,              "tungsten/support/crypto"
  autoload :Sandwich,            "tungsten/literals/sandwich"
  autoload :SetLiteral,          "tungsten/literals/set_literal"
  autoload :MultisetLiteral,     "tungsten/literals/set_literal"
  autoload :StringBuffer,        "tungsten/literals/string_buffer"
  autoload :Time,                "tungsten/literals/time"
  autoload :UUID,                "tungsten/literals/uuid"
  autoload :Week,                "tungsten/literals/week"

  # Support
  autoload :Units,               "tungsten/support/units"

  module Runtime
    autoload :Builtins,          "tungsten/runtime/builtins"
    autoload :RawWValue,         "tungsten/runtime/raw_w_value"
    autoload :WClass,            "tungsten/runtime/w_class"
    autoload :WObject,           "tungsten/runtime/w_object"
    autoload :WMethod,           "tungsten/runtime/w_method"
  end

  def self.parse(code)
    Parser.parse(code)
  end

  def self.lexer_mode
    mode = ENV.fetch(LEXER_MODE_ENV, "codepoint")
    mode == "reference" ? "regex" : mode
  end

  def self.codepoint_lexer?
    lexer_mode == "codepoint"
  end

  def self.regex_lexer?
    lexer_mode == "regex"
  end

  def self.lexer_class
    mode = lexer_mode
    case mode
    when "codepoint"
      CodepointLexer
    when "regex"
      Lexer
    else
      raise ArgumentError, "unknown #{LEXER_MODE_ENV}: #{mode.inspect} (expected codepoint or regex)"
    end
  end

  def self.new_lexer(code, file: nil, profile: false)
    lexer =
      if lexer_class == CodepointLexer
        CodepointLexer.new(code, profile:)
      else
        Lexer.new(code)
      end
    lexer.file = file if file
    lexer
  end

  def self.run(source)
    src = comma_decimal_locale? ? normalize_decimal_comma(source) : source
    Interpreter.new.run(src)
  end

  # Force comma-decimal parsing regardless of env locale. Useful for explicitly
  # localized input strings where you want `1,5 m` to mean 1.5 m.
  def self.run_localized(source)
    Interpreter.new.run(normalize_decimal_comma(source))
  end
end
