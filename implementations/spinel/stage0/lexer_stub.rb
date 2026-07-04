# frozen_string_literal: true

module Tungsten
  class Lexer
    attr_accessor :file
    # The lexer_adapter ivar lives on Parser (Parser#initialize binds
    # it to a fresh CodepointLexer when Tungsten.codepoint_lexer?).
    # Declaring it on the Lexer parent so the spinel-generated
    # sp_Lexer struct has the slot, which lets Lexer-class methods
    # (next_token + skip_* below) read it via self->iv_lexer_adapter
    # without erroring at codegen. At runtime every reachable
    # instance is a Parser, so the field is always populated.
    attr_accessor :lexer_adapter
    attr_accessor :token

    KEYWORDS = %w[
      if unless while until rescue ensure else elsif when then begin case class module return break next on yield super use
      with alias raise true false nil is
    ].freeze

    TYPE_NAMES = %w[
      any bool boolean byte char decimal f32 f64 float i8 i16 i32 i64 int integer key nil number object path ptr string
      symbol u8 u16 u32 u64 uint void w32 w64
    ].freeze

    TYPE_NAME_PATTERN = TYPE_NAMES.join("|").freeze
    TYPE_HINT_START = /## +(?=(?:any|bool|boolean|byte|char|decimal|f32|f64|float|i8|i16|i32|i64|int|integer|key|nil|number|object|path|ptr|string|symbol|u8|u16|u32|u64|uint|void|w32|w64)\b|[a-z]\w*:)/.freeze

    FLOAT = /[+-]?(?:\d[\d_]*\.\d[\d_]*|\d[\d_]*(?:[eE][+-]?\d[\d_]*)|\d[\d_]*\.\d[\d_]*(?:[eE][+-]?\d[\d_]*)?)/.freeze
    RATIONAL = /[+-]?\d[\d_]*\/\d[\d_]*/.freeze
    DECIMAL = /[+-]?\d[\d_]*(?:\.\d[\d_]*)?[A-Z][A-Za-z0-9_]*/.freeze
    CIDR6 = /[0-9A-Fa-f:]+\/\d{1,3}/.freeze
    IP6 = /[0-9A-Fa-f:]*:[0-9A-Fa-f:]*/.freeze
    CIDR4 = /\d{1,3}(?:\.\d{1,3}){3}\/\d{1,2}/.freeze
    IP4 = /\d{1,3}(?:\.\d{1,3}){3}/.freeze
    MAC = /[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}/.freeze
    UUID = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/.freeze
    DATETIME = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?/.freeze
    TIME = /\d{2}:\d{2}(?::\d{2})?/.freeze
    DATE = /\d{4}-\d{2}-\d{2}/.freeze
    WEEK = /\d{4}-W\d{2}/.freeze
    INVALID_WEEK = /\d{4}-W\d{2}/.freeze
    MONTH = /\d{4}-\d{2}/.freeze
    CURRENCY = /(?:[$]|EUR|GBP|JPY|INR|CNY)?\d+(?:\.\d+)?(?:[$]|EUR|GBP|JPY|INR|CNY)?/.freeze
    DURATION = /P?[0-9A-Za-z]+/.freeze
    UNIT_STRING = /[A-Za-z][A-Za-z0-9_]*/.freeze
    DURATION_ORDER = %w[y mo w d h m s ms us ns].freeze

    # Token-stream skip helpers. The full Tungsten Lexer defines
    # these (see implementations/ruby/lib/tungsten/lexer.rb) but
    # stage0 swaps the full lexer for this stub and the
    # CodepointLexer adapter — so Parser, which inherits from
    # Lexer, ends up with no skip_space etc. Parser bodies call
    # them as bare self-methods because in the full-Ruby path
    # they resolve up through Lexer.
    #
    # Each method forwards to @lexer_adapter where the real
    # implementation lives. The forwarding shape mirrors
    # Parser#string / Parser#rest / Parser#next_token already in
    # the bundle. Without these, parse_expression_suffix's call
    # to `skip_space` no-ops (emits 0), the AST stays empty,
    # and stage 0 silently exits 0 on every input.
    def next_token
      @token = @lexer_adapter.next_token
    end

    def skip_space
      next_token while @token.type == :SP
    end

    def skip_indent
      next_token while @token.type == :INDENT
    end

    def skip_newline
      next_token while @token.type == :NL
    end

    def skip_whitespace
      next_token while @token.type == :SP || @token.type == :NL
    end

    def skip_whitespace_all
      loop do
        case @token.type
        when :SP, :NL, :INDENT, :DEDENT
          next_token
        else
          break
        end
      end
    end

    def skip_dedent
      next_token if @token.type == :DEDENT
    end

    def next_token_skip_indent
      next_token
      skip_indent
    end

    def next_token_skip_space
      next_token
      skip_space
    end

    def next_token_skip_newline
      next_token
      skip_newline
    end

    def next_token_skip_whitespace
      next_token
      skip_whitespace
    end

    def next_token_skip_whitespace_all
      next_token
      skip_whitespace_all
    end
  end
end
