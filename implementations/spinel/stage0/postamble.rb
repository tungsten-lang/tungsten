# frozen_string_literal: true

module Tungsten
  def self.lexer_mode
    "codepoint"
  end

  def self.codepoint_lexer?
    true
  end

  def self.regex_lexer?
    false
  end

  def self.lexer_class
    CodepointLexer
  end

  def self.new_lexer(code, file: nil, profile: false)
    lexer = CodepointLexer.new(code, profile: profile)
    lexer.file = file if file
    lexer
  end

  def self.parse(code)
    Parser.parse(code)
  end

  def self.run(source, file_path = "")
    Interpreter.new.run(source, file_path)
  end
end
