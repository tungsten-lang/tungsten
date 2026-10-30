# frozen_string_literal: true

require "fileutils"

ROOT = File.expand_path("../../..", __dir__)
SPINEL_DIR = File.join(ROOT, "implementations", "spinel")
GEM_LIB = File.join(ROOT, "implementations", "ruby", "lib")
TUNGSTEN_LIB = File.join(GEM_LIB, "tungsten")

out = ARGV[0] || File.join(SPINEL_DIR, "build", "tungsten_stage0_bundle.rb")

def tungsten_file(path)
  File.join(TUNGSTEN_LIB, path)
end

def files_under(path)
  Dir[File.join(TUNGSTEN_LIB, path, "**", "*.rb")].sort
end

sources = []
sources << File.join(SPINEL_DIR, "stage0", "preamble.rb")
sources << File.join(SPINEL_DIR, "stage0", "shims.rb")

sources << tungsten_file("core_ext/module.rb")
sources << tungsten_file("core_ext/string.rb")
sources << tungsten_file("location.rb")
sources << tungsten_file("token.rb")
sources << tungsten_file("visitor.rb")
sources << File.join(SPINEL_DIR, "stage0", "lexer_stub.rb")

ast_base_files = [
  tungsten_file("ast/node.rb"),
  tungsten_file("ast/list.rb"),
  tungsten_file("ast/value.rb"),
  tungsten_file("ast/unary_expression.rb"),
  tungsten_file("ast/keyword_args.rb"),
  tungsten_file("ast/keyword_value.rb"),
  tungsten_file("ast/keywords/def.rb"),
  tungsten_file("ast/keywords/while.rb"),
  tungsten_file("ast/keywords/flip2.rb")
]
sources.concat(ast_base_files)
sources.concat(files_under("ast").reject { |path| ast_base_files.include?(path) || path.end_with?("/ast/super.rb") })

sources << tungsten_file("runtime/w_object.rb")
sources << tungsten_file("runtime/w_class.rb")
sources << tungsten_file("runtime/w_method.rb")
sources << tungsten_file("runtime/raw_w_value.rb")

sources << tungsten_file("codepoint_lexer.rb")
sources << tungsten_file("parser.rb")
sources << tungsten_file("environment.rb")
sources << tungsten_file("loader.rb")
sources << tungsten_file("interpreter.rb")
sources << File.join(SPINEL_DIR, "stage0", "postamble.rb")
sources << File.join(SPINEL_DIR, "stage0", "entrypoint.rb")

unless ENV["SPINEL_STAGE0_FULL"] == "1"
  sources = [File.join(SPINEL_DIR, "stage0", "minimal_entrypoint.rb")]
end

def filtered_source(path)
  body = File.read(path)
  body = stage0_location_source if path.end_with?("/location.rb")
  body = stage0_token_source if path.end_with?("/token.rb") && ENV["SPINEL_STAGE0_REAL_TOKEN"] != "1"
  body = stage0_token_compat(body) if path.end_with?("/token.rb") && ENV["SPINEL_STAGE0_REAL_TOKEN"] == "1"
  body = stage0_codepoint_lexer_source if path.end_with?("/codepoint_lexer.rb") && ENV["SPINEL_STAGE0_REAL_LEXER"] != "1"
  body = stage0_codepoint_lexer_compat(body) if path.end_with?("/codepoint_lexer.rb") && ENV["SPINEL_STAGE0_REAL_LEXER"] == "1"
  body = stage0_postamble_source if path.end_with?("/stage0/postamble.rb")
  body = stage0_entrypoint_source if path.end_with?("/stage0/entrypoint.rb")
  body = stage0_parser_source if path.end_with?("/parser.rb") && ENV["SPINEL_STAGE0_REAL_PARSER"] != "1"
  parser_compat = ENV["SPINEL_STAGE0_PARSER_COMPAT"] != "0"
  body = stage0_parser_compat(body) if path.end_with?("/parser.rb") &&
                                       ENV["SPINEL_STAGE0_REAL_PARSER"] == "1" &&
                                       parser_compat
  body = stage0_parser_block_compat(body) if path.end_with?("/parser.rb") &&
                                             ENV["SPINEL_STAGE0_REAL_PARSER"] == "1"
  body = stage0_environment_source if path.end_with?("/environment.rb") && ENV["SPINEL_STAGE0_REAL_ENV"] != "1"
  body = stage0_environment_compat(body) if path.end_with?("/environment.rb") && ENV["SPINEL_STAGE0_REAL_ENV"] == "1"
  full_ruby_interpreter = ENV["SPINEL_STAGE0_FULL_RUBY_INTERPRETER"] == "1"
  interpreter_compat = ENV["SPINEL_STAGE0_INTERPRETER_COMPAT"] != "0"
  body = stage0_interpreter_source if path.end_with?("/interpreter.rb") &&
                                      ENV["SPINEL_STAGE0_REAL_INTERPRETER"] != "1" &&
                                      !full_ruby_interpreter &&
                                      interpreter_compat
  body = stage0_real_interpreter_compat(body) if path.end_with?("/interpreter.rb") &&
                                                 full_ruby_interpreter &&
                                                 ENV["SPINEL_STAGE0_NO_FULL_INTERPRETER_COMPAT"] == "1" &&
                                                 interpreter_compat
  body = stage0_interpreter_raw_compat(body) if path.end_with?("/interpreter.rb") &&
                                                ENV["SPINEL_STAGE0_REAL_INTERPRETER"] == "1" &&
                                                ENV["SPINEL_STAGE0_RAW_INTERPRETER"] == "1" &&
                                                !full_ruby_interpreter &&
                                                interpreter_compat
  body = stage0_interpreter_compat(body) if path.end_with?("/interpreter.rb") &&
                                            ENV["SPINEL_STAGE0_REAL_INTERPRETER"] == "1" &&
                                            ENV["SPINEL_STAGE0_RAW_INTERPRETER"] != "1" &&
                                            !full_ruby_interpreter &&
                                            interpreter_compat
  body = stage0_full_interpreter_compat(body) if path.end_with?("/interpreter.rb") &&
                                                full_ruby_interpreter &&
                                                ENV["SPINEL_STAGE0_NO_FULL_INTERPRETER_COMPAT"] != "1" &&
                                                interpreter_compat
  body = stage0_loader_source if path.end_with?("/loader.rb") && ENV["SPINEL_STAGE0_REAL_LOADER"] != "1"
  body = stage0_loader_compat(body) if path.end_with?("/loader.rb") && ENV["SPINEL_STAGE0_REAL_LOADER"] == "1"
  body = stage0_node_source if path.end_with?("/ast/node.rb")
  body = stage0_list_source if path.end_with?("/ast/list.rb")
  body = stage0_runtime_source(path) if path.include?("/runtime/")
  literal_stubbed = path.include?("/ast/literals/")
  body = stage0_literal_source(path) if literal_stubbed
  body = stage0_ast_compat(body, path) if path.include?("/ast/")
  body = stage0_literal_compat(body, path) if path.include?("/ast/literals/") && !literal_stubbed
  body = ensure_stage0_doc_accessor(body) if path.include?("/ast/") && !path.end_with?("/ast/node.rb")
  body = strip_stage0_ast_methods(body) if path.include?("/ast/") && !path.end_with?("/ast/node.rb")
  body = inject_stage0_eval_in(body) if path.include?("/ast/") && !path.end_with?("/ast/node.rb")
  body = body.gsub("-name.to_s", "name.to_s")
  body = body.gsub("-value[prefix.length..]", "value[prefix.length..]")
  body = flatten_namespaces(body, path)
  body.lines.filter_map do |line|
    next if line.start_with?("# frozen_string_literal:")
    next if line.match?(/\A\s*require(?:_relative)?\s+/)
    next if line.match?(/\A\s*autoload\s+/)

    line
  end.join
end

def ensure_stage0_doc_accessor(body)
  body.gsub(/(^\s*class\s+[A-Za-z_0-9]+\s+<\s+[A-Za-z_:0-9]+\s*\n)(?!\s*attr_accessor\s+:doc\b)/,
            "\\1    attr_accessor :doc\n")
end

def stage0_runtime_source(path)
  case path
  when %r{/runtime/w_object\.rb\z}
    <<~RUBY
      module Tungsten
        module Runtime
          class UnboundSlot
          end

          class WObject
            attr_accessor :w_class, :ivar_values

            def initialize(w_class)
              @w_class = w_class
              @ivar_values = [nil, 0, ""]
              @ivar_values.clear
              n = w_class != nil ? w_class.ivar_count : 0
              i = 0
              while i < n
                @ivar_values.push(nil)
                i += 1
              end
            end

            def get_ivar_slot(slot)
              vals = @ivar_values
              return vals[slot] if slot < vals.length
              v = nil
              v
            end

            def set_ivar_slot(slot, value)
              vals = @ivar_values
              while vals.length <= slot
                vals.push(nil)
              end
              vals[slot] = value
              value
            end

            def get_ivar(name)
              return nil if @w_class.nil?
              get_ivar_slot(@w_class.ivar_slot(name))
            end

            def set_ivar(name, value)
              return value if @w_class.nil?
              set_ivar_slot(@w_class.ivar_slot(name), value)
            end

            def to_s
              "#<Object>"
            end
          end
        end
      end
    RUBY
  when %r{/runtime/w_class\.rb\z}
    <<~RUBY
      module Tungsten
        module Runtime
          class WClass
            attr_accessor :name, :superclass, :methods_table, :class_methods_table, :traits, :version, :class_vars, :constants_table, :ivar_slots, :ivar_count

            def initialize(name, superclass = nil)
              @name = name
              @superclass = superclass
              @methods_table = {"__spinel_mt_i__" => 0, "__spinel_mt_s__" => ""}
              @methods_table.clear
              @class_methods_table = {"__spinel_cmt_i__" => 0, "__spinel_cmt_s__" => ""}
              @class_methods_table.clear
              @traits = [nil, 0, ""]
              @traits.clear
              @version = 0
              @class_vars = {"__spinel_cv_i__" => 0, "__spinel_cv_s__" => ""}
              @class_vars.clear
              @constants_table = {"__spinel_c_i__" => 0, "__spinel_c_s__" => ""}
              @constants_table.clear
              @ivar_slots = {"__spinel_iv_slot__" => 0}
              @ivar_slots.clear
              @ivar_count = 0
            end

            def ivar_slot(name)
              k = name.to_s
              idx = @ivar_slots[k]
              return idx unless idx.nil?
              new_idx = @ivar_count
              @ivar_slots[k] = new_idx
              @ivar_count = new_idx + 1
              new_idx
            end

            def get_cvar(name)
              klass = self
              while klass != nil
                if klass.class_vars.key?(name)
                  v = nil
                  v = klass.class_vars[name]
                  return v
                end
                klass = klass.superclass
              end
              nil
            end

            def set_cvar(name, value)
              klass = self
              while klass != nil
                if klass.class_vars.key?(name)
                  klass.class_vars[name] = value
                  return value
                end
                klass = klass.superclass
              end
              @class_vars[name] = value
              value
            end

            def has_constant?(name)
              @constants_table.key?(name)
            end

            def get_constant(name)
              v = nil
              v = @constants_table[name]
              v
            end

            def set_constant(name, value)
              @constants_table[name] = value
              value
            end

            def lookup_method(name)
              klass = self
              while klass != nil
                method = klass.methods_table[name]
                return method if method != nil

                ti = klass.traits.length - 1
                while ti >= 0
                  tr = klass.traits[ti]
                  if tr != nil
                    tm = tr.lookup_method(name)
                    return tm if tm != nil
                  end
                  ti -= 1
                end

                klass = klass.superclass
              end
              nil
            end

            def define_method(name, method)
              @methods_table[name] = method
              @version += 1
              method
            end

            def lookup_class_method(name)
              klass = self
              while klass != nil
                method = klass.class_methods_table[name]
                return method if method != nil

                klass = klass.superclass
              end
              nil
            end

            def define_class_method(name, method)
              @class_methods_table[name] = method
              @version += 1
              method
            end

            def include_trait(trait)
              @traits.push(trait)
              @version += 1
            end

            def to_s
              "Class"
            end
          end
        end
      end
    RUBY
  when %r{/runtime/w_method\.rb\z}
    <<~RUBY
      module Tungsten
        module Runtime
          class WMethod
            attr_accessor :name, :params, :body, :defining_class, :splat_index

            def initialize(name, params, body, defining_class = nil, splat_index: nil)
              @name = name
              @params = params
              @body = body
              @defining_class = defining_class
              @splat_index = splat_index
            end
          end
        end
      end
    RUBY
  when %r{/runtime/raw_w_value\.rb\z}
    <<~RUBY
      module Tungsten
        module Runtime
          class RawWValue
            attr_accessor :bits, :raw

            def initialize(bits, raw = nil)
              @bits = bits
              @raw = "u0x0"
            end

            def hash
              0
            end

            def inspect
              @raw
            end

            def to_s
              @raw
            end
          end
        end
      end
    RUBY
  else
    File.read(path)
  end
end

def stage0_token_source
  <<~RUBY
    module Tungsten
      class Token
        attr_accessor :type, :value, :file, :row, :col

        def initialize
          @type = nil
          @value = ""
          @file = 0
          @row = 0
          @col = 0
        end

        def comma?
          @type == :","
        end

        def keyword?(sym)
          false
        end

        def location
          Location.new(0, @row, @col)
        end

        def location=(loc)
          self
        end

        def reset_location
          self
        end

        def type?(sym)
          @type == sym
        end

        def to_s
          "<Token>"
        end

        def inspect
          to_s
        end

        def suffix?
          false
        end

        def whitespace?
          @type == :SP || @type == :NL
        end

        def assignment_operator?
          false
        end

        def assignment_operators
          []
        end
      end
    end
  RUBY
end

def stage0_token_compat(body)
  body = body.sub("attr_accessor :file, :row, :col", "attr_accessor :file, :row, :col, :interp_parts")
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize
      @type = :EOF
      @value = :eof
      @value = ""
      @value = nil
      @file = nil
      @row = 0
      @col = 0
      @interp_parts = List.new
    end
  RUBY
  body = replace_method(body, "keyword?", <<~RUBY)
    def keyword?(sym)
      @type == :KEYWORD && (@value == sym || @value.to_s == sym.to_s)
    end
  RUBY
  body = replace_method(body, "location", <<~RUBY)
    def location
      Location.new(@file || 0, @row, @col)
    end
  RUBY
  body = replace_method(body, "to_s", <<~RUBY)
    def to_s
      "<Token>"
    end
  RUBY
  body = replace_method(body, "suffix?", <<~RUBY)
    def suffix?
      return false unless @type == :KEYWORD
      v = @value
      v == :if || v == :unless || v == :while || v == :until || v == :rescue || v == :ensure
    end
  RUBY
  body = replace_method(body, "assignment_operator?", <<~RUBY)
    def assignment_operator?
      t = @type
      t == :"+=" || t == :"-=" || t == :"*=" || t == :"/=" || t == :"//=" || t == :"%=" ||
        t == :"|=" || t == :"&=" || t == :"^=" || t == :"**=" || t == :"<<=" || t == :">>=" ||
        t == :"||=" || t == :"&&="
    end
  RUBY
  body
end

def stage0_codepoint_lexer_source
  <<~RUBY
    module Tungsten
      class CodepointLexer
        attr_accessor :file, :pos

        def initialize(code)
          @code = code
          @token = Token.new
          @emitted = false
          @pos = 0
        end

        def tokens
          list = []
          list << next_token
          list
        end

        def next_token
          @token.type = :EOF
          @token.value = nil
          @token.row = 1
          @token.col = 1
          @token
        end

        def string
          @code
        end

        def eos?
          true
        end

        def rest
          ""
        end

        def scan(pattern)
          [""]
        end

        def skip(pattern)
          0
        end

        def check(pattern)
          [""]
        end
      end
    end
  RUBY
end

def stage0_codepoint_lexer_compat(body)
  type_names_list = %w[
    bool int integer string string_buffer
    i4 i8 i16 i32 i64 i128
    u4 u8 u16 u32 u64 u128
    w64
    f16 f32 f64 f80 f128 f256
    d128 c32 c64 c128
    bigint bigdecimal
    bf16 tf32 fp8 fp4 nf4
    mxfp8 mxfp6 mxfp4 mxint8
    posit8 posit16 posit32 posit64
  ]
  type_hint_words_list = (type_names_list + %w[big recycle reuse reuse_drain no_raise fold hash array symbol float char object ptr]).uniq
  type_names_hash_src = "{ " + type_names_list.map { |n| "#{n.inspect} => true" }.join(", ") + " }"
  type_hint_words_hash_src = "{ " + type_hint_words_list.map { |n| "#{n.inspect} => true" }.join(", ") + " }"

  body = body.sub(/^\s*KEYWORDS_BY_FIRST_AND_LENGTH = .*?\.freeze\n\s*(?=TYPE_NAMES_BY_FIRST_AND_LENGTH = )/m, "")
  body = body.sub(/^\s*TYPE_NAMES_BY_FIRST_AND_LENGTH = .*?\.freeze\n\s*(?=TYPE_NAMES = )/m, "")
  body = body.gsub(/^\s*TYPE_NAMES = .*?\.freeze\n/, "    TYPE_NAMES = #{type_names_hash_src}\n")
  body = body.gsub(/^\s*TYPE_HINT_WORDS = .*?\.freeze\n/, "    TYPE_HINT_WORDS = #{type_hint_words_hash_src}\n")
  body = body.sub(/^\s*REGEX_PROFILE_NAMES = \{\n.*?^\s*\}\.freeze\n/m, "")
  body = body.gsub(/^\s*SUBSCRIPT_TAIL = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*SUPERSCRIPT_DIGITS = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*UNICODE_IDENTIFIER = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*DOUBLE_STRUCK_NAME = .*?\.freeze\n/, "")
  body = body.gsub("if ident_start_byte?(byte(1)) || match_regex_at(UNICODE_IDENTIFIER, @pos + 1)", "if ident_start_byte?(byte(1))")
  body = body.gsub(/^\s*BYTE_ARRAY_BINARY = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_OCTAL = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_DECIMAL = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_HEX_PREFIX = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_HEX = .*?\.freeze\n/, "")
  body = body.gsub("def initialize(code, profile: false)", "def initialize(code)")
  body = body.gsub("@profile_enabled = profile", "@profile_enabled = false")
  body = body.gsub(/^\s*@profile_.* if profile\n/, "")
  body = body.gsub(/^\s*@profile_.* if @profile_enabled\n/, "")
  body = body.gsub(/^\s*profile_path\(.* if @profile_enabled\n/, "")
  body = body.gsub("return scan_regex_capture if regex_capture_start?\n", "")
  body = body.gsub("return if hex_reference_literal_possible? && network_literal_shape_possible? && scan_network_literal", "return if false")
  body = body.gsub("return if byte(1) == 58 && network_literal_shape_possible? && scan_network_literal", "return if false")
  body = body.gsub("return if bracketed_ip6_start? && scan_network_literal", "return if false")
  body = body.gsub("if (fe80_start? || (hex_reference_literal_possible? && network_literal_shape_possible?)) && scan_network_literal", "if false")
  body = body.gsub("if next_byte == 126 && approximate_float_literal_possible?", "if false")
  body = body.gsub("if third && third != 9", "if third >= 0 && third != 9")
  body = body.gsub("if byte(2) == 92 && (esc = byte(3))", "if byte(2) == 92 && byte(3) >= 0\n        esc = byte(3)")

  body = replace_method(body, "clean", <<~RUBY)
    def clean(code)
      code.to_s
    end
  RUBY
  body = replace_method(body, "byte", <<~RUBY)
    def byte(offset = 0)
      idx = @pos + offset
      return -1 if idx < 0 || idx >= @length
      @source.getbyte(idx) || -1
    end
  RUBY
  body = replace_method(body, "utf8_width_at", <<~RUBY)
    def utf8_width_at(pos)
      return 1 if pos >= @length
      b = @source.getbyte(pos) || 0
      return 1 if b < 128
      return 2 if b < 224
      return 3 if b < 240
      4
    end
  RUBY
  body = replace_method(body, "set_token", <<~RUBY)
    def set_token(type, value = nil, row = @row, col = @col)
      @token.reset_location
      @token.file = @file
      @token.row = row
      @token.col = col
      @token.type = type
      @token.value = value
    end
  RUBY
  body = replace_method(body, "newline_byte?", <<~RUBY)
    def newline_byte?(b)
      b == 10
    end
  RUBY
  body = replace_method(body, "space_byte?", <<~RUBY)
    def space_byte?(b)
      b == 32
    end
  RUBY
  body = replace_method(body, "digit_byte?", <<~RUBY)
    def digit_byte?(b)
      b >= 48 && b <= 57
    end
  RUBY
  body = replace_method(body, "sign_byte?", <<~RUBY)
    def sign_byte?(b)
      b == 43 || b == 45
    end
  RUBY
  body = replace_method(body, "lower_byte?", <<~RUBY)
    def lower_byte?(b)
      b >= 97 && b <= 122
    end
  RUBY
  body = replace_method(body, "upper_byte?", <<~RUBY)
    def upper_byte?(b)
      b >= 65 && b <= 90
    end
  RUBY
  body = replace_method(body, "alpha_byte?", <<~RUBY)
    def alpha_byte?(b)
      lower_byte?(b) || upper_byte?(b)
    end
  RUBY
  body = replace_method(body, "ident_start_byte?", <<~RUBY)
    def ident_start_byte?(b)
      lower_byte?(b) || b == 95
    end
  RUBY
  body = replace_method(body, "ident_continue_byte?", <<~RUBY)
    def ident_continue_byte?(b)
      ident_start_byte?(b) || digit_byte?(b)
    end
  RUBY
  body = replace_method(body, "hex_byte?", <<~RUBY)
    def hex_byte?(b)
      digit_byte?(b) || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)
    end
  RUBY
  body = replace_method(body, "vigesimal_byte?", <<~RUBY)
    def vigesimal_byte?(b)
      digit_byte?(b) || (b >= 65 && b <= 74) || (b >= 97 && b <= 106)
    end
  RUBY
  body = replace_method(body, "unit_start_byte?", <<~RUBY)
    def unit_start_byte?(b)
      alpha_byte?(b) || non_ascii_byte?(b)
    end
  RUBY
  body = replace_method(body, "non_ascii_byte?", <<~RUBY)
    def non_ascii_byte?(b)
      b >= 128
    end
  RUBY
  body = replace_method(body, "prefix_int_byte?", <<~RUBY)
    def prefix_int_byte?(b)
      b == 98 || b == 66 || b == 100 || b == 111 || b == 79 || b == 114 || b == 118 || b == 120 || b == 88
    end
  RUBY
  body = replace_method(body, "terminator_byte?", <<~RUBY)
    def terminator_byte?(b)
      b <= 0 || b == 32 || b == 10 || b == 9 || b == 13 || b == 12 || b == 35 || b == 59 ||
        b == 40 || b == 41 || b == 91 || b == 93 || b == 123 || b == 125 || b == 44
    end
  RUBY
  body = replace_method(body, "method_operator_after?", <<~RUBY)
    def method_operator_after?(bytes)
      b = byte(bytes)
      b < 0 || b == 32 || b == 10 || b == 40 || b == 47
    end
  RUBY
  body = replace_method(body, "scan_symbol_or_colon", <<~RUBY)
    def scan_symbol_or_colon
      start_col = @col

      if byte(1) == 45
        third = byte(2)
        if third >= 0 && third != 9 && third != 10 && third != 13 && third != 32
          return scan_ascii_char_literal(start_col)
        end
      end

      if ident_start_byte?(byte(1)) || upper_byte?(byte(1)) || digit_byte?(byte(1))
        start = @pos
        advance
        if upper_byte?(byte)
          scan_ascii_name_bytes
        else
          scan_ident_bytes
        end
        return set_token(:SYMBOL, slice(start), @row, start_col)
      end

      operator = scan_symbol_operator
      return set_token(:SYMBOL, operator, @row, start_col) if operator

      advance
      set_token(:":", nil, @row, start_col)
    end
  RUBY
  body = replace_method(body, "scan_ascii_char_literal", <<~RUBY)
    def scan_ascii_char_literal(start_col)
      esc = byte(3)
      if byte(2) == 92 && esc >= 0
        cp =
          case esc
          when 110 then 10
          when 116 then 9
          when 114 then 13
          when 92  then 92
          when 48  then 0
          when 115 then 32
          when 39  then 39
          when 34  then 34
          else esc
          end
        advance(4)
        return set_token(:CHAR, cp, @row, start_col)
      end

      cp = byte(2)
      advance(3)
      set_token(:CHAR, cp, @row, start_col)
    end
  RUBY
  body = replace_method(body, "handle_indentation", <<~RUBY)
    def handle_indentation
      return unless @line_start

      if @bracket_depth > 0
        cp = @pos
        while cp < @length && @source.getbyte(cp) == 32
          cp += 1
        end
        @col += (cp - @pos)
        @pos = cp
        return
      end

      cp = @pos
      while cp < @length && @source.getbyte(cp) == 32
        cp += 1
      end
      if cp < @length && @source.getbyte(cp) == 35
        after = cp + 1 < @length ? (@source.getbyte(cp + 1) || -1) : -1
        if after < 0 || after == 32 || after == 10 || after == 35
          @col += (cp - @pos)
          @pos = cp
          return
        end
      end

      if eof? || (!space_byte?(byte) && !newline_byte?(byte))
        @dedebt += @indent
        return
      end

      p = @pos
      while p < @length && @source.getbyte(p) == 32
        p += 1
      end
      return unless p < @length && @source.getbyte(p) != 10

      spaces = p - @pos
      return if (spaces & 1) == 1

      @pos = p
      @col += spaces
      diff = (spaces / 2) - @indent
      if diff > 0
        @indebt = diff
      elsif diff < 0
        @dedebt = -diff
      end
    end
  RUBY
  body = replace_method(body, "primorial_ahead?", <<~RUBY)
    def primorial_ahead?
      return false if match_bytes?("##") || @pos <= 0
      prev = @source.getbyte(@pos - 1) || 0
      alpha_byte?(prev) || digit_byte?(prev) || prev == 95 || prev == 41 || prev == 93 || prev == 125 || prev == 33 || prev == 39 || prev == 34
    end
  RUBY
  body = replace_method(body, "type_hint_start?", <<~RUBY)
    def type_hint_start?(pos)
      return false if @line_start
      return false if pos >= @length
      b = @source.getbyte(pos) || -1
      return true if upper_byte?(b)

      if lower_byte?(b)
        p = pos
        while p < @length && ident_continue_byte?(@source.getbyte(p) || -1)
          p += 1
        end
        return true if p < @length && @source.getbyte(p) == 58
        word = @source.byteslice(pos, p - pos)
        return true if TYPE_HINT_WORDS.key?(word)
      end
      false
    end
  RUBY
  body = replace_method(body, "color_literal_ahead?", <<~RUBY)
    def color_literal_ahead?
      false
    end
  RUBY
  body = replace_method(body, "color_literal_hex", <<~RUBY)
    def color_literal_hex
      nil
    end
  RUBY
  body = replace_method(body, "scan_color_literal", <<~RUBY)
    def scan_color_literal
      false
    end
  RUBY
  body = replace_method(body, "error", <<~RUBY)
    def error(msg)
      raise "syntax on line " + @row.to_s + " col " + @col.to_s + " pos " + @pos.to_s + ": " + msg.to_s
    end
  RUBY
  body = replace_method(body, "scan", <<~RUBY)
    def scan(pattern)
      return "" if false

      nil
    end
  RUBY
  body = replace_method(body, "skip", <<~RUBY)
    def skip(pattern)
      0
    end
  RUBY
  body = replace_method(body, "check", <<~RUBY)
    def check(pattern)
      return "" if false

      nil
    end
  RUBY
  body = replace_method(body, "slice", <<~RUBY)
    def slice(start_pos = @pos, end_pos = @pos)
      start_i = start_pos.to_i
      end_i = end_pos.to_i
      @source.byteslice(start_i, end_i - start_i) || ""
    end
  RUBY
  body = replace_method(body, "match_scanner_pattern", <<~RUBY)
    def match_scanner_pattern(pattern)
      nil
    end
  RUBY
  body = replace_method(body, "unicode_rational_slash_at?", <<~RUBY)
    def unicode_rational_slash_at?(position = @pos)
      bytes_at?(position, "⁄") || bytes_at?(position, "∕")
    end
  RUBY
  body = replace_method(body, "scan_string", <<~RUBY)
    def scan_string
      start_col = @col
      advance
      parts = List.new
      str = ""
      has_interp = false

      loop do
        error "unterminated string" if eof?

        b = byte
        if b == 34
          advance
          break
        elsif b == 92
          str = str + scan_string_escape
        elsif b == 91
          if byte(1) != 93 && matching_close_bracket_before_newline?(@pos + 1)
            has_interp = true
            if !str.empty?
              pair_s = List.new
              pair_s.push(:str)
              pair_s.push(str)
              parts.push(pair_s)
              str = ""
            end
            advance
            expr_str = scan_interpolation_expr
            pair_e = List.new
            pair_e.push(:expr)
            pair_e.push(expr_str)
            parts.push(pair_e)
          else
            str = str + "["
            advance
          end
        else
          chunk_start = @pos
          advance_utf8_char
          str = str + slice(chunk_start)
        end
      end

      if has_interp
        if !str.empty?
          pair_tail = List.new
          pair_tail.push(:str)
          pair_tail.push(str)
          parts.push(pair_tail)
        end
        @token.interp_parts = parts
        set_token(:STRING_INTERP, "", @row, start_col)
      else
        set_token(:STRING, str, @row, start_col)
      end
    end
  RUBY
  body = replace_method(body, "scan_string_escape", <<~RUBY)
    def scan_string_escape
      if match_bytes?("\\\\n")
        advance(2)
        return 10.chr
      elsif match_bytes?("\\\\r")
        advance(2)
        return 13.chr
      elsif match_bytes?("\\\\t")
        advance(2)
        return 9.chr
      elsif match_bytes?("\\\\e[")
        advance(3)
        return 27.chr + "["
      elsif match_bytes?("\\\\e")
        advance(2)
        return 27.chr
      elsif match_bytes?("\\\\0")
        advance(2)
        return 0.chr
      elsif match_bytes?("\\\\\\\\")
        advance(2)
        return 92.chr
      elsif match_bytes?("\\\\\\"")
        advance(2)
        return 34.chr
      elsif match_bytes?("\\\\'")
        advance(2)
        return 39.chr
      elsif match_bytes?("\\\\[")
        advance(2)
        return "["
      elsif match_bytes?("\\\\]")
        advance(2)
        return "]"
      elsif match_bytes?("\\\\u") && hex_byte?(byte(2)) && hex_byte?(byte(3)) && hex_byte?(byte(4)) && hex_byte?(byte(5))
        cp = slice(@pos + 2, @pos + 6).to_i(16)
        advance(6)
        return encode_utf8_codepoint(cp)
      else
        advance
        return 92.chr
      end
    end

    def encode_utf8_codepoint(cp)
      if cp < 0x80
        cp.chr
      elsif cp < 0x800
        (0xC0 | (cp >> 6)).chr + (0x80 | (cp & 0x3F)).chr
      elsif cp < 0x10000
        (0xE0 | (cp >> 12)).chr + (0x80 | ((cp >> 6) & 0x3F)).chr + (0x80 | (cp & 0x3F)).chr
      else
        (0xF0 | (cp >> 18)).chr + (0x80 | ((cp >> 12) & 0x3F)).chr + (0x80 | ((cp >> 6) & 0x3F)).chr + (0x80 | (cp & 0x3F)).chr
      end
    end
  RUBY
  body = replace_method(body, "scan_heredoc", <<~RUBY)
    def scan_heredoc(start_col)
      start_row = @row
      advance(3)
      advance while byte == 32 || byte == 9
      delim_start = @pos
      if alpha_byte?(byte) || byte == 95
        advance while alpha_byte?(byte) || digit_byte?(byte) || byte == 95
      end
      delim = slice(delim_start)
      error "expected heredoc delimiter after <<~" if delim.empty?

      advance while !eof? && byte != 10
      error "unterminated heredoc" if eof?
      @pos += 1
      @row += 1
      @col = 1

      body_lines = [""]
      body_lines.clear
      min_indent = -1
      loop do
        error "unterminated heredoc" if eof?
        line_start = @pos
        advance while !eof? && byte != 10
        line = slice(line_start)
        if line.strip == delim
          break
        end
        body_lines.push(line)
        stripped = line.lstrip
        unless stripped.empty?
          indent = line.bytesize - stripped.bytesize
          min_indent = indent if min_indent < 0 || indent < min_indent
        end
        error "unterminated heredoc" if eof?
        @pos += 1
        @row += 1
        @col = 1
      end

      min_indent = 0 if min_indent < 0
      out_lines = [""]
      out_lines.clear
      i = 0
      while i < body_lines.length
        l = body_lines[i]
        if l.empty? || l.bytesize <= min_indent
          out_lines.push("")
        else
          out_lines.push(l.byteslice(min_indent, l.bytesize - min_indent) || "")
        end
        i += 1
      end

      set_token(:STRING, out_lines.join("\n"), start_row, start_col)
      true
    end
  RUBY
  body = replace_method(body, "scan_name", <<~RUBY)
    def scan_name
      start_col = @col
      start = @pos
      scan_ascii_name_bytes
      value = slice(start)
      type = constant_name?(value) ? :CONSTANT : :NAME
      set_token(type, value, @row, start_col)
    end
  RUBY
  keywords_list = [
    ["...", ':"..."'], ["alias", ":alias"], ["always", ":always"], ["begin", ":begin"],
    ["break", ":break"], ["case", ":case"], ["continue", ":continue"], ["else", ":else"],
    ["elsif", ":elsif"], ["ensure", ":ensure"], ["fn", ":fn"], ["if", ":if"],
    ["in", ":in"], ["is", ":is"], ["loop", ":loop"], ["module", ":module"],
    ["next", ":next"], ["on", ":on"], ["raise", ":raise"], ["recase", ":recase"],
    ["redo", ":redo"], ["rescue", ":rescue"], ["retry", ":retry"], ["return", ":return"],
    ["super", ":super"], ["then", ":then"], ["trait", ":trait"], ["unless", ":unless"],
    ["until", ":until"], ["use", ":use"], ["when", ":when"], ["while", ":while"],
    ["with", ":with"], ["yield", ":yield"]
  ]
  kw_cases = keywords_list.group_by { |w, _| w.bytesize }.sort.map do |len, group|
    b_cases = group.group_by { |w, _| w.getbyte(0) }.sort.map do |b0, items|
      checks = items.map { |w, sym| "return #{sym} if bytes_at?(start, #{w.inspect})" }.join("\n          ")
      "        when #{b0}\n          #{checks}"
    end.join("\n")
    "      when #{len}\n        case b0\n#{b_cases}\n        end"
  end.join("\n")
  body = replace_method(body, "keyword_at", <<~RUBY)
    def keyword_at(start, finish)
      len = finish - start
      return nil if len < 2 || len > 8
      b0 = @source.getbyte(start) || 0
      case len
#{kw_cases}
      end
      nil
    end
  RUBY
  tn_cases = type_names_list.group_by(&:bytesize).sort.map do |len, group|
    b_cases = group.group_by { |w| w.getbyte(0) }.sort.map do |b0, items|
      checks = items.map { |w| "return #{w.inspect} if bytes_at?(start, #{w.inspect})" }.join("\n          ")
      "        when #{b0}\n          #{checks}"
    end.join("\n")
    "      when #{len}\n        case b0\n#{b_cases}\n        end"
  end.join("\n")
  body = replace_method(body, "type_name_at", <<~RUBY)
    def type_name_at(start, finish)
      len = finish - start
      return nil if len < 2 || len > 13
      b0 = @source.getbyte(start) || 0
      case len
#{tn_cases}
      end
      nil
    end
  RUBY
  body = replace_method(body, "scan_byte_array", <<~RUBY)
    def scan_byte_array
      start_row = @row
      start_col = @col
      advance_utf8_char
      while @pos < @length
        if match_bytes?("»")
          break
        end
        advance_utf8_char
      end
      error "unterminated byte array" if eof?

      advance_utf8_char
      set_token(:BYTE_ARRAY, nil, start_row, start_col)
    end
  RUBY
  body = replace_method(body, "append_byte_array_value", <<~RUBY)
    def append_byte_array_value(bytes, match, base)
      nil
    end
  RUBY
  body = replace_method(body, "finish_number_token", <<~RUBY)
    def finish_number_token(num_str, num_type, start_col)
      set_token(num_type, num_str, @row, start_col)
    end
  RUBY
  body = replace_method(body, "scan_codepoint_literal", <<~RUBY)
    def scan_codepoint_literal
      start_col = @col
      start = @pos
      advance(2)
      advance while hex_byte?(byte)
      hex = slice(start + 2)
      cp = hex.to_i(16)
      set_token(:CODEPOINT, encode_utf8_codepoint(cp), @row, start_col)
    end
  RUBY
  body = replace_method(body, "scan_wvalue", <<~RUBY)
    def scan_wvalue
      start_col = @col
      start = @pos
      advance(3)
      advance while hex_byte?(byte)
      set_token(:WVALUE, slice(start), @row, start_col)
    end
  RUBY
  body = replace_method(body, "scan_regex_literal", <<~RUBY)
    def scan_regex_literal
      start = @pos
      start_col = @col
      i = start + 1
      escaped = false
      in_class = false

      while i < @length
        b = @source.getbyte(i) || -1
        error "unterminated regex literal" if b == 10

        if escaped
          escaped = false
        elsif b == 92
          escaped = true
        elsif b == 91
          in_class = true
        elsif b == 93
          in_class = false
        elsif b == 47 && !in_class
          pattern = @source.byteslice(start + 1, i - start - 1) || ""
          i += 1
          opts_start = i
          while i < @length && alpha_byte?(@source.getbyte(i) || -1)
            i += 1
          end
          opts = @source.byteslice(opts_start, i - opts_start) || ""
          advance(i - start)
          return set_token(:REGEX, pattern, @row, start_col)
        end
        i += 1
      end

      error "unterminated regex literal"
    end
  RUBY
  body = replace_method(body, "scan_superscript", <<~RUBY)
    def scan_superscript
      false
    end
  RUBY
  body = replace_method(body, "scan_unicode_identifier", <<~RUBY)
    def scan_unicode_identifier
      false
    end
  RUBY
  body = replace_method(body, "scan_unicode_name", <<~RUBY)
    def scan_unicode_name
      false
    end
  RUBY
  body = replace_method(body, "scan_subscript_tail", <<~RUBY)
    def scan_subscript_tail
      false
    end
  RUBY
  body = replace_method(body, "scan_reference_literal", <<~RUBY)
    def scan_reference_literal
      false
    end
  RUBY
  body = replace_method(body, "scan_numeric_reference_literal", <<~RUBY)
    def scan_numeric_reference_literal
      false
    end
  RUBY
  body = replace_method(body, "scan_unit_string", <<~RUBY)
    def scan_unit_string
      nil
    end
  RUBY
  body = replace_method(body, "extend_unit_with_word", <<~RUBY)
    def extend_unit_with_word(unit, separator)
      unit
    end
  RUBY
  body = replace_method(body, "extend_unit_with_of_phrase", <<~RUBY)
    def extend_unit_with_of_phrase(unit)
      unit
    end
  RUBY
  body = replace_method(body, "validate_duration_order!", <<~RUBY)
    def validate_duration_order!(str)
      nil
    end
  RUBY
  body = replace_method(body, "validate_week!", <<~RUBY)
    def validate_week!(match)
      nil
    end
  RUBY
  %w[
    fe80_start?
    bracketed_ip6_start?
    hex_reference_literal_possible?
    network_literal_shape_possible?
    special_decimal_literal_possible?
    rational_literal_possible?
    numeric_reference_possible?
    radix_number_literal?
    sexagesimal_decimal_prefix?
    approximate_float_literal_possible?
    regex_capture_start?
    scan_float_literal
    scan_rational_literal
    scan_special_decimal_literal
    scan_network_literal
    scan_calendar_literal
    scan_currency_literal
    scan_duration_literal
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
      def #{name}
        false
      end
    RUBY
  end
  body = replace_method(body, "approximate_decimal_after?", <<~RUBY)
    def approximate_decimal_after?(index)
      false
    end
  RUBY
  replace_method(body, "match_regex_at", <<~RUBY)
    def match_regex_at(regex, pos = 0)
      nil
    end
  RUBY
end

def stage0_postamble_source
  <<~RUBY
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
        nil
      end

      def self.new_lexer(code)
        CodepointLexer.new(code.to_s)
      end

      def self.parse(code)
        Parser.parse(code.to_s)
      end

      def self.run(source, file_path = "")
        Interpreter.new.run(source, file_path)
      end
    end
  RUBY
end

def stage0_entrypoint_source
  <<~'RUBY'
    if ARGV.length == 0
      exit 64
    end

    $stage0_argv = "\n"
    i = 1
    while i < ARGV.length
      $stage0_argv = $stage0_argv + ARGV[i] + "\n"
      i += 1
    end

    source = File.read(ARGV[0])
    dump_path = ENV["TUNGSTEN_SPINEL_STAGE0_SOURCE_DUMP"]
    if dump_path != nil
      if dump_path != ""
        File.write(dump_path, source)
      end
    end
    run(source, ARGV[0])
  RUBY
end

def stage0_parser_source
  <<~RUBY
    module Tungsten
      class Parser < Lexer
        attr_accessor :token

        EMPTY_ARGS = []
        VALID_METHOD_NAMES = []

        def self.parse(str = "")
          Parser.new(str).parse
        end

        def initialize(str = "")
          @source = str
          @token = Token.new
          @lexer_adapter = CodepointLexer.new(@source)
        end

        def parse
          next_token
          parse_statement_list(false)
        end

        def next_token
          @token = @lexer_adapter.next_token
        end

        def skip_spaces
          while @token.type?(:SP)
            next_token
          end
        end

        def skip_collection_whitespace
          while @token.type?(:SP) || @token.type?(:NL) || @token.type?(:INDENT) || @token.type?(:DEDENT)
            next_token
          end
        end

        def skip_statement_separators
          while @token.type?(:SP) || @token.type?(:NL) || @token.type?(:";") || @token.type?(:INDENT)
            next_token
          end
        end

        def keyword_value?(name)
          @token.value.to_s == name
        end

        def binary_operator?
          return true if keyword_value?("in")
          return true if @token.type?(:+)
          return true if @token.type?(:-)
          return true if @token.type?(:*)
          return true if @token.type?(:/)
          return true if @token.type?(:%)
          return true if @token.type?(:>)
          return true if @token.type?(:<)
          return true if @token.type?(:>=)
          return true if @token.type?(:<=)
          return true if @token.type?(:==)
          return true if @token.type?(:"!=")
          return true if @token.type?(:"||")
          return true if @token.type?(:"&&")
          false
        end

        def parse_statement_list(stop_at_else)
          list = List.new
          until @token.type?(:EOF)
            skip_statement_separators
            break if @token.type?(:EOF)
            break if @token.type?(:DEDENT)
            if stop_at_else
              break if keyword_value?("else")
            end
            before_pos = @lexer_adapter.pos
            list.push(parse_statement)
            if @lexer_adapter.pos == before_pos
              if !@token.type?(:EOF)
                next_token
              end
            end
          end
          list
        end

        def parse_indented_block
          while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT)
            next_token
          end
          body_col = @token.col
          block = List.new
          until @token.type?(:EOF)
          while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT) || @token.type?(:DEDENT)
            next_token
          end
          break if @token.type?(:EOF)
          break if @token.col < body_col
            before_pos = @lexer_adapter.pos
            block.push(parse_statement)
            if @lexer_adapter.pos == before_pos
              if !@token.type?(:EOF)
                next_token
              end
            end
            while @token.type?(:DEDENT)
              next_token
            end
            while @token.type?(:SP)
              next_token
            end
            if @token.type?(:NL)
              next_token
              while @token.type?(:SP) || @token.type?(:INDENT)
                next_token
              end
            end
          end
          if @token.type?(:DEDENT)
            next_token
          end
          block
        end

        def parse_statement
          skip_spaces
          if keyword_value?("if")
            return parse_stage0_if
          end
          if keyword_value?("while")
            return parse_stage0_while
          end
          if keyword_value?("return")
            return parse_stage0_return
          end
          if keyword_value?("use")
            return parse_stage0_use
          end
          if keyword_value?("class")
            return parse_stage0_class
          end
          if @token.type?(:+)
            return parse_stage0_class
          end
          if @token.type?(:"->")
            return parse_stage0_def
          end
          parse_assignment_or_expression
        end

        def parse_stage0_if
          if_col = @token.col
          next_token
          condition = parse_binary_expression
          then_block = parse_indented_block
          while !@token.type?(:EOF) && @token.col > if_col
            next_token
          end
          else_block = List.new
          if keyword_value?("elsif") && @token.col == if_col
            else_block = parse_stage0_elsif_tail(if_col)
          elsif keyword_value?("else") && @token.col == if_col
            next_token
            else_block = parse_indented_block
          end
          If.new(condition, then_block, else_block)
        end

        def parse_stage0_elsif_tail(if_col)
          next_token
          condition = parse_binary_expression
          then_block = parse_indented_block
          while !@token.type?(:EOF) && @token.col > if_col
            next_token
          end
          else_block = List.new
          if keyword_value?("elsif") && @token.col == if_col
            else_block = parse_stage0_elsif_tail(if_col)
          elsif keyword_value?("else") && @token.col == if_col
            next_token
            else_block = parse_indented_block
          end
          If.new(condition, then_block, else_block)
        end

        def parse_stage0_while
          next_token
          condition = parse_binary_expression
          body = parse_indented_block
          While.new(condition, body, true)
        end

        def parse_stage0_return
          next_token
          Return.new(parse_binary_expression)
        end

        def parse_stage0_use
          source_len = @source.bytesize
          path_start = @lexer_adapter.pos
          while path_start < source_len
            b = @source.getbyte(path_start)
            break unless b == 32 || b == 9

            path_start += 1
          end
          line_end = path_start
          while line_end < source_len
            b = @source.getbyte(line_end)
            break if b == 10 || b == 13

            line_end += 1
          end
          path = "" + @source.byteslice(path_start, line_end - path_start).to_s
          comment_pos = path.index("#")
          if comment_pos != nil
            path = "" + path.byteslice(0, comment_pos).to_s
          end
          while path.length > 0
            tail = path.getbyte(path.length - 1)
            break unless tail == 32 || tail == 9

            path = "" + path.byteslice(0, path.length - 1).to_s
          end
          if path.length >= 2
            first = path.byteslice(0, 1)
            last = path.byteslice(path.length - 1, 1)
            if (first == "\"" && last == "\"") || (first == "'" && last == "'")
              path = "" + path.byteslice(1, path.length - 2).to_s
            end
          end
          @lexer_adapter.pos = line_end
          next_token
          Use.new(path)
        end

        def parse_stage0_class
          next_token
          skip_spaces
          name = ""
          superclass = ""
          if @token.type?(:ID)
            name = @token.value
            next_token
          end
          skip_spaces
          if @token.type?(:<)
            next_token
            skip_spaces
            if @token.type?(:ID)
              superclass = @token.value
              next_token
            end
          end
          body = parse_indented_block
          ClassDef.new(name, body, superclass)
        end

        def parse_stage0_def
          next_token
          skip_spaces
          name = ""
          if @token.type?(:ID)
            name = @token.value
            next_token
          end
          if @token.type?(:"?")
            name = name + "?"
            next_token
          elsif @token.type?(:"!")
            name = name + "!"
            next_token
          end
          params = List.new
          ivar_assigns = List.new
          if @token.type?(:"(")
            next_token
            until @token.type?(:EOF) || @token.type?(:")")
              skip_spaces
              if @token.type?(:ID)
                params.push(Arg.new(@token.value))
                next_token
              elsif @token.type?(:IVAR)
                ivar_name = @token.value.to_s
                param_name = ivar_name.slice(1, ivar_name.length - 1)
                params.push(Arg.new(param_name))
                ivar_assigns.push(Assign.new(InstanceVar.new(ivar_name), Var.new(param_name), nil))
                next_token
              elsif @token.type?(:",")
                next_token
              else
                next_token
              end
            end
            if @token.type?(:")")
              next_token
            end
          end
          body = parse_indented_block
          if ivar_assigns.length > 0
            new_body = List.new
            i = 0
            while i < ivar_assigns.length
              new_body.push(ivar_assigns[i])
              i += 1
            end
            i = 0
            while i < body.length
              new_body.push(body[i])
              i += 1
            end
            body = new_body
          end
          Def.new(name, params, body)
        end

        def parse_assignment_or_expression
          skip_spaces
          if @token.type?(:IVAR)
            target = InstanceVar.new(@token.value)
            next_token
            skip_spaces
            if @token.type?(:"=")
              next_token
              value = parse_binary_expression
              return Assign.new(target, value)
            end
            if @token.type?(:"+=")
              next_token
              value = parse_binary_expression
              return AssignOp.new(target, :+, value)
            end
            return parse_binary_expression_from(parse_postfix(target))
          end
          if @token.type?(:ID)
            name = @token.value
            next_token
            if @token.type?(:"?")
              name = name + "?"
              next_token
            elsif @token.type?(:"!")
              name = name + "!"
              next_token
            end
            skip_spaces
            if @token.type?(:"=")
              next_token
              value = parse_binary_expression
              return Assign.new(name, value)
            end
            if @token.type?(:"+=")
              next_token
              value = parse_binary_expression
              return Assign.new(name, BinaryOp.new(Var.new(name), :+, value), nil)
            end
            if @token.type?(:"(")
              return parse_call_after_name(name)
            end
            if name == "exit"
              args = List.new
              if !@token.type?(:NL)
                if !@token.type?(:EOF)
                  args.push(parse_binary_expression)
                end
              end
              return Call.new(nil, name, args)
            end
            postfixed = parse_postfix(Var.new(name))
            skip_spaces
            if @token.type?(:"=") && postfixed.is_a?(Call) && postfixed.name == "[]"
              next_token
              new_args = List.new
              i = 0
              while i < postfixed.args.length
                new_args.push(postfixed.args[i])
                i += 1
              end
              new_args.push(parse_binary_expression)
              return Call.new(postfixed.obj, "[]=", new_args)
            end
            return parse_binary_expression_from(postfixed)
          end
          parse_binary_expression
        end

        def parse_call_after_name(name)
          args = List.new
          if @token.type?(:"(")
            next_token
            until @token.type?(:EOF) || @token.type?(:")")
              skip_spaces
              args.push(parse_binary_expression)
              skip_spaces
              if @token.type?(:",")
                next_token
              end
            end
            if @token.type?(:")")
              next_token
            end
          end
          Call.new(nil, name, args)
        end

        def parse_postfix(left)
          loop do
            skip_spaces
            if @token.type?(:".")
              next_token
              skip_spaces
              name = ""
              if @token.type?(:ID)
                name = @token.value
                next_token
              elsif @token.type?(:KEYWORD)
                name = @token.value
                next_token
              end
              if @token.type?(:"?")
                name = name + "?"
                next_token
              elsif @token.type?(:"!")
                name = name + "!"
                next_token
              end
              call_args = List.new
              if @token.type?(:"(")
                next_token
                until @token.type?(:EOF) || @token.type?(:")")
                  skip_spaces
                  call_args.push(parse_binary_expression)
                  skip_spaces
                  if @token.type?(:",")
                    next_token
                  end
                end
                if @token.type?(:")")
                  next_token
                end
              end
              left = Call.new(left, name, call_args)
            elsif @token.type?(:"[")
              next_token
              index_args = List.new
              until @token.type?(:EOF) || @token.type?(:"]")
                skip_spaces
                index_args.push(parse_binary_expression)
                skip_spaces
                if @token.type?(:",")
                  next_token
                end
              end
              if @token.type?(:"]")
                next_token
              end
              left = Call.new(left, "[]", index_args)
            else
              break
            end
          end
          left
        end

        def parse_binary_expression
          left = parse_binary_expression_from(parse_postfix(parse_primary))
          loop do
            skip_spaces
            if @token.type?(:"||") || @token.type?(:"&&")
              op = @token.type
              next_token
              right = parse_binary_expression_from(parse_postfix(parse_primary))
              left = BinaryOp.new(left, op, right)
            else
              break
            end
          end
          left
        end

        def parse_binary_expression_from(left)
          right = Nil.new
          loop do
            skip_spaces
            break if @token.type?(:"||") || @token.type?(:"&&")
            if binary_operator?
              op = @token.type
              if keyword_value?("in")
                op = :in
              end
              next_token
              right = parse_postfix(parse_primary)
              left = BinaryOp.new(left, op, right)
            else
              break
            end
          end
          left
        end

        def parse_primary
          skip_spaces
          if @token.type?(:-)
            next_token
            if @token.type?(:INT)
              value = "-" + @token.value.to_s
              next_token
              return Int.new(value)
            end
            return BinaryOp.new(Int.new(0), :-, parse_primary)
          end
          if @token.type?(:INT)
            value = @token.value
            next_token
            return Int.new(value)
          end
          if @token.type?(:CHAR)
            value = @token.value
            next_token
            return Int.new(value)
          end
          if @token.type?(:STRING)
            value = @token.value
            next_token
            return StringLiteral.new(value)
          end
          if @token.type?(:SYMBOL)
            value = @token.value.to_s
            next_token
            return StringLiteral.new(value)
          end
          if @token.type?(:TRUE)
            next_token
            return Boolean.new(true)
          end
          if @token.type?(:FALSE)
            next_token
            return Boolean.new(false)
          end
          if @token.type?(:NIL)
            next_token
            return Nil.new
          end
          if keyword_value?("true")
            next_token
            return Boolean.new(true)
          end
          if keyword_value?("false")
            next_token
            return Boolean.new(false)
          end
          if keyword_value?("nil")
            next_token
            return Nil.new
          end
          if @token.type?(:"[")
            next_token
            arr_lit = ArrayLiteral.new
            until @token.type?(:EOF) || @token.type?(:"]")
              skip_collection_whitespace
              if @token.type?(:"]")
                break
              end
              arr_lit.list.push(parse_binary_expression)
              skip_collection_whitespace
              if @token.type?(:",")
                next_token
              end
            end
            if @token.type?(:"]")
              next_token
            end
            return arr_lit
          end
          if @token.type?(:"{")
            next_token
            # Build entries as a List (poly_array internally) of
            # 2-element Lists; spinel infers `[]` as int_array which
            # later widens to ptr_array of PolyArrays — that disagrees
            # with HashLiteral's iv_entries (poly_array, see force_ivar
            # in spinel_codegen.rb), and visit_hash_literal then misreads
            # entry buffers (PtrArray's 8-byte stride vs PolyArray's
            # 16-byte). Using List explicitly pins the container type.
            entries = List.new
            until @token.type?(:EOF) || @token.type?(:"}")
              skip_collection_whitespace
              if @token.type?(:"}")
                break
              end
              key = nil
              if @token.type?(:ID)
                key = StringLiteral.new(@token.value)
                next_token
                skip_collection_whitespace
                if @token.type?(:":")
                  next_token
                end
              else
                key = parse_binary_expression
                skip_collection_whitespace
                if @token.type?(:"=>")
                  next_token
                elsif @token.type?(:":")
                  next_token
                end
              end
              skip_collection_whitespace
              value = parse_binary_expression
              pair = List.new
              pair.push(key)
              pair.push(value)
              entries.push(pair)
              skip_collection_whitespace
              if @token.type?(:",")
                next_token
              end
            end
            if @token.type?(:"}")
              next_token
            end
            return HashLiteral.new(entries)
          end
          if @token.type?(:ID)
            value = @token.value
            next_token
            if @token.type?(:"?")
              value = value + "?"
              next_token
            elsif @token.type?(:"!")
              value = value + "!"
              next_token
            end
            if @token.type?(:"(")
              return parse_call_after_name(value)
            end
            return Var.new(value)
          end
          if @token.type?(:IVAR)
            value = @token.value
            next_token
            return InstanceVar.new(value)
          end
          if @token.type?(:"(")
            next_token
            values = List.new
            until @token.type?(:EOF) || @token.type?(:")")
              skip_spaces
              if @token.type?(:")")
                break
              end
              values.push(parse_binary_expression)
              skip_spaces
              if @token.type?(:",")
                next_token
              end
            end
            if @token.type?(:")")
              next_token
            end
            if values.length == 1
              return values[0]
            end
            return values
          end
          if @token.type?(:"<<")
            next_token
            args = List.new
            args.push(parse_binary_expression)
            return Print.new(args)
          end
          next_token
          Nil.new
        end
      end
    end
  RUBY
end

def stage0_environment_source
  <<~RUBY
    module Tungsten
      class Environment
        def initialize(parent = nil, slot_names = nil)
          @parent = parent
        end

        def get(name)
          nil
        end

        def set(name, value)
          value
        end

        def define(name, value)
          value
        end

        def defined?(name)
          false
        end
      end
    end
  RUBY
end

def stage0_environment_compat(body)
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize(parent = nil)
      # Delegate the parent assignment to a helper: spinel's auto-generated
      # Environment.new wrapper INLINES this constructor but emits the
      # inlined `@parent = parent` WITHOUT the poly->sp_Environment* cast
      # that standalone methods get (iv_parent is sp_Environment*, the param
      # is sp_RbVal because Environment.new(nil) unions a poly nil in). The
      # standalone bind_parent_env keeps the casting codegen path.
      bind_parent_env(parent)
      # Placeholder entries narrow @values to str_poly_hash. Without
      # them spinel infers a generic hash type and downstream env
      # ops compile to the wrong call. We tried force_ivar_type +
      # `@values = {}` but the rebuilt spinel emitted a code path
      # that segfaulted bootstrap.
      @values = {"__spinel_env_poly_i__" => 0, "__spinel_env_poly_s__" => ""}
      @values.clear
      @own_slot_names = {"__spinel_slot0__" => 0}
      @own_slot_names.clear
      @slot_names = @own_slot_names
      @slot_values = [nil, 0, ""]
      @slot_values.clear
      @slot_values.push(nil)
      @barrier = true
      @slot_names_shared = false
      @layout_shape = 0
      @lookup_shape = 0
      @pool_next = nil
    end

    # Standalone parent setter so the poly->sp_Environment* cast is emitted
    # (see the comment in #initialize). Must NOT be inlined into the
    # Environment.new wrapper.
    def bind_parent_env(parent)
      @parent = parent
    end

    def set_barrier(flag)
      @barrier = flag
      self
    end

    def barrier
      @barrier
    end

    def unshare_slot_names
      @own_slot_names.clear
      @slot_names.each do |sk, sv|
        @own_slot_names["" + sk.to_s] = sv.to_i
      end
      @slot_names = @own_slot_names
      @slot_names_shared = false
      @layout_shape = 0
    end

    def pool_reset(parent)
      @parent = parent
      @values.clear if @values.length > 0
      @own_slot_names.clear if @own_slot_names.length > 0
      @slot_names = @own_slot_names
      @slot_values.clear
      @slot_values.push(nil)
      @barrier = true
      @slot_names_shared = false
      @layout_shape = 0
      @lookup_shape = 0
      @pool_next = nil
    end

    def pool_reset_frame(parent, slot_map, shape, slot_count, unbound)
      @parent = parent
      @values.clear if @values.length > 0
      @slot_names = slot_map
      @slot_names_shared = true
      sh = shape.to_i
      @layout_shape = sh
      @lookup_shape = sh
      @barrier = true
      @pool_next = nil
      sv = @slot_values
      sv.clear
      sv.push(nil)
      sc = slot_count.to_i
      i = 1
      while i < sc
        sv.push(unbound)
        i += 1
      end
    end
  RUBY
  body = replace_method(body, "self.next_shape", <<~RUBY)
    def self.next_shape
      0
    end
  RUBY
  body = replace_method(body, "self.slot_shape", <<~RUBY)
    def self.slot_shape(slot_names)
      0
    end
  RUBY
  body = replace_method(body, "self.layout_transition", <<~RUBY)
    def self.layout_transition(shape, name, index)
      shape
    end
  RUBY
  body = replace_method(body, "self.lookup_transition", <<~RUBY)
    def self.lookup_transition(parent_shape, layout_shape)
      layout_shape
    end
  RUBY
  body = replace_method(body, "barrier?", "    def barrier?\n      @barrier\n    end\n")
  body = replace_method(body, "lookup_shape", "    def lookup_shape\n      0\n    end\n")
  body = replace_method(body, "slot_index", <<~RUBY)
    def slot_index(name)
      v = @slot_names[name.to_s]
      v.nil? ? -1 : v.to_i
    end
  RUBY
  body = replace_method(body, "get_slot", <<~RUBY)
    def get_slot(index)
      @slot_values[index]
    end
  RUBY
  body = replace_method(body, "set_slot", <<~RUBY)
    def set_slot(index, value)
      @slot_values[index] = value
      value
    end
  RUBY
  body = replace_method(body, "get", <<~RUBY)
    def get(name)
      k = name.to_s
      env = self
      while true
        idx = env.slot_index(k)
        if idx > 0
          val = env.get_slot(idx)
          return val unless val.is_a?(UnboundSlot)
        end
        parent = env.parent
        if parent.nil?
          return nil
        end
        env = parent
      end
      nil
    end

    def values_table
      @values
    end

    def bind_value(name, value)
      @values["" + name.to_s] = value
      value
    end

    def pool_next
      @pool_next
    end

    def pool_link(next_env)
      @pool_next = next_env
      self
    end

    def mark_layout_shape(shape)
      sh = shape.to_i
      @layout_shape = sh
      @lookup_shape = sh
      self
    end
  RUBY
  body = replace_method(body, "set", <<~RUBY)
    def set(name, value)
      k = name.to_s
      idx = slot_index(k)
      if idx > 0 && (@barrier || !@slot_values[idx].is_a?(UnboundSlot))
        @slot_values[idx] = value
        return value
      end
      if !@barrier
        env = self
        while true
          parent = env.parent
          if parent.nil?
            break
          end
          env = parent
          idx2 = env.slot_index(k)
          if idx2 > 0 && (env.barrier? || !env.get_slot(idx2).is_a?(UnboundSlot))
            return env.set_slot(idx2, value)
          end
          if env.barrier?
            return env.bind_slot(k, value)
          end
        end
      end
      bind_slot(k, value)
      value
    end
  RUBY
  body = replace_method(body, "define", <<~RUBY)
    def define(name, value)
      bind_slot(name, value)
      value
    end
  RUBY
  body = replace_method(body, "define_slot", <<~RUBY)
    def define_slot(name, index, value)
      unshare_slot_names if @slot_names_shared
      i = index.to_i
      @slot_names["" + name.to_s] = i
      @slot_values[i] = value
      value
    end

    def bind_slot(name, value)
      k = name.to_s
      idx = slot_index(k)
      if idx > 0
        @slot_values[idx] = value
      else
        unshare_slot_names if @slot_names_shared
        new_idx = @slot_values.length
        @slot_names["" + k] = new_idx
        @slot_values.push(value)
      end
      value
    end

    def bind_new_slot(name, value)
      k = name.to_s
      if @slot_names_shared
        idx = slot_index(k)
        if idx > 0
          @slot_values[idx] = value
          return value
        end
        unshare_slot_names
      end
      new_idx = @slot_values.length
      @slot_names["" + k] = new_idx
      @slot_values.push(value)
      value
    end

  RUBY
  body = replace_method(body, "defined?", <<~RUBY)
    def defined?(name)
      idx = slot_index(name)
      return true if idx > 0 && !@slot_values[idx].is_a?(UnboundSlot)
      return @parent.defined?(name) if @parent
      false
    end
  RUBY
  body = replace_method(body, "defined_locally_or_in_scope?", <<~RUBY)
    def defined_locally_or_in_scope?(name)
      idx = slot_index(name)
      return true if idx > 0 && !@slot_values[idx].is_a?(UnboundSlot)
      return false if @barrier
      return @parent.defined_locally_or_in_scope?(name) if @parent
      false
    end
  RUBY
  body = replace_method(body, "defined_locally?", <<~RUBY)
    def defined_locally?(name)
      idx = slot_index(name)
      idx > 0 && !@slot_values[idx].is_a?(UnboundSlot)
    end
  RUBY
  body = replace_method(body, "fetch", <<~RUBY)
    def fetch(name)
      get(name)
    end
  RUBY
  body = replace_method(body, "bindings", "    def bindings\n      {}\n    end\n")
  body
end

def stage0_loader_source
  <<~RUBY
    module Tungsten
      class Loader
        def initialize
        end

        def load(path)
          nil
        end
      end
    end
  RUBY
end

def stage0_loader_compat(body)
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize(interpreter = nil)
      @interpreter = interpreter
      @loaded = Set.new
      @loading = Set.new
      @load_paths = []
      @ast_cache = {}
    end
  RUBY
  body = replace_method(body, "add_load_path", <<~RUBY)
    def add_load_path(path)
      nil
    end
  RUBY
  body = replace_method(body, "load_file", <<~RUBY)
    def load_file(path, from = nil)
      nil
    end
  RUBY
  body = replace_method(body, "load_prelude", <<~RUBY)
    def load_prelude
      nil
    end
  RUBY
  body = replace_method(body, "resolve", <<~RUBY)
    def resolve(path, from = nil)
      nil
    end
  RUBY
  replace_method(body, "cached_parse", <<~RUBY)
    def cached_parse(path, source)
      Parser.parse(source.to_s)
    end
  RUBY
end

def stage0_interpreter_source
  <<~RUBY
    module Tungsten
      class Interpreter
        def initialize
        end

        def run(source)
          Parser.parse(source)
        end
      end
    end
  RUBY
end

def stage0_ast_builtin_dispatch
  source = File.read(File.join(ROOT, "compiler/lib/ast.w"))
  ctor_source = source.split("-> ast_node_key(node)")[0]
  out = +""
  ctor_source.scan(/^-> (ast_[A-Za-z0-9_!?]+)(?:\(([^)]*)\))?/).each do |name, params_src|
    params_src ||= ""
    node_name = name.sub(/^ast_/, "")
    node_name = "nil_lit" if node_name == "nil"
    node_name = "self_ref" if node_name == "self"
    node_name = "return" if node_name == "return_nil"
    params = params_src.split(",").map do |part|
      pieces = part.strip.split("=", 2)
      { name: pieces[0].strip, default: pieces[1]&.strip }
    end.reject { |param| param[:name].empty? }

    out << "      if name_sym == :#{name}\n"
    fields = ["node: :#{node_name}"]
    params.each_with_index do |param, index|
      fallback = param[:default] || "nil"
      fields << "#{param[:name]}: (args.length > #{index} ? evaluate(args[#{index}]) : #{fallback})"
    end
    out << "          return {#{fields.join(', ')}}\n"
    out << "      end\n"
  end
  out
end

def stage0_real_interpreter_compat(body)
  body = body.gsub(/^\s*include (?:Runtime::)?CompilerIntrinsics\n/, "")
  body = body.sub(
    "    def to_s\n      match\n    end\n",
    "    def to_s\n      \"\" + match.to_s\n    end\n"
  )
  body = body.gsub(/^\s*public\s+:decode_w_value.*?(?=\n\s*\n|\n\s*if\b)/m, "")
  # Initialize @top_env alongside @env. visit_call's user-fn lookup
  # uses @top_env to skip the env parent-chain walk for top-level
  # Defs — most lookups resolve to a Def in the root env.
  # Use a linked free-list rather than an Array so the pool itself does not
  # allocate or fight Spinel's array type inference.
  body = body.gsub("@env = Environment.new\n", "@env = Environment.new(nil)\n      @top_env = @env\n      @unbound_slot = UnboundSlot.new\n      @env_pool = nil\n      @env_pool_count = 0\n      @env_pool_enabled = ENV[\"SP_GC_DISABLE\"] == \"0\" ? 0 : 1\n      @stage0_next_layout_shape = 1\n      @method_cache_epoch = 1\n      ac = [nil, 0, \"\"]\n      ac.clear\n      aci = 0\n      while aci < 128\n        ac.push(aci.chr)\n        aci += 1\n      end\n      @stage0_ascii_chars = ac\n")
  body = body.gsub("@env = Environment.new(@env, barrier: true)", "@env = Environment.new(@env)")
  body = body.gsub("Environment.new(parent, barrier:)", "Environment.new(parent)")
  body = body.gsub("Environment.new(parent, barrier:, slot_names: cached_param_slot_names(owner, params))", "Environment.new(parent)")
  body = body.gsub("Environment.new(parent, slot_names: cached_free_var_slot_names(block, free_vars))", "Environment.new(parent)")
  body = body.gsub("NO_DIRECT_CALL = Object.new.freeze", "NO_DIRECT_CALL = 0")
  body = body.gsub("HASH_MISS = Object.new.freeze", "HASH_MISS = 0")
  body = body.gsub(/^\s*TUNGSTEN_TYPE_NAMES = \{\n.*?^\s*\}\.freeze\n/m, "    TUNGSTEN_TYPE_NAMES = 0\n")
  body = body.gsub(/^\s*ENERGY_FUELS = \{\n.*?^\s*\}\.freeze\n/m, "    ENERGY_FUELS = {}\n")
  body = body.gsub(/^\s*ENERGY_OUTPUT_UNITS = \{\n.*?^\s*\}\.freeze\n/m, "    ENERGY_OUTPUT_UNITS = {}\n")
  body = body.gsub(/^\s*DIMENSION_AXES = \[\n.*?^\s*\]\.freeze\n/m, "    DIMENSION_AXES = []\n")
  body = body.gsub(/^\s*MOON_PHASES = \[\n.*?^\s*\]\.freeze\n/m, "    MOON_PHASES = []\n")
  body = body.gsub(/      @value_nodes = \{\n.*?      \}\.compare_by_identity\n/m, "      @value_nodes = {}\n")
  body = body.gsub(/^\s*@file_sources\[.*?\] = source.*\n/, "")
  body = body.gsub(
    "      @profile_dispatch_counts = Hash.new { |h, k| h[k] = Hash.new(0) }\n",
    "      @profile_dispatch_counts = {}\n" \
    "      @returning = false\n" \
    "      @return_value = nil\n" \
    "      @return_target_depth = -1\n" \
    "      @call_depth = 0\n" \
    "      @in_block_depth = 0\n" \
    "      @current_block_owner_depth = 0\n" \
    "      @breaking = false\n" \
    "      @nexting = false\n" \
    "      @exiting = false\n" \
    "      @current_block = nil\n" \
    "      @current_class = nil\n" \
    "      @current_module = nil\n" \
    "      @traits = {\"__spinel_trait__\" => Runtime::WClass.new(\"__spinel_trait__\", nil)}\n" \
    "      @traits.clear\n" \
      "      dummy_node = PackedNode.new(0, 0, 0)\n" \
    "      @ast_next_offset = 1\n" \
    "      @ast_store_gen = 1\n" \
    "      @ast_singletons = {0 => dummy_node}\n" \
    "      @ast_singletons.clear\n" \
    "      @ast_inline_nodes = {0 => dummy_node}\n" \
    "      @ast_inline_nodes.clear\n" \
    "      @ast_bool_nodes = {0 => dummy_node}\n" \
    "      @ast_bool_nodes.clear\n" \
    "      @ast_intern_next_id = 0\n" \
    "      @ast_intern_ids = {\"__spinel_intern__\" => 0}\n" \
    "      @ast_intern_ids.clear\n" \
    "      @ast_intern_strs = {0 => \"\"}\n" \
    "      @ast_intern_strs.clear\n" \
    "      @ast_intern_nodes = {0 => dummy_node}\n" \
    "      @ast_intern_nodes.clear\n" \
    "      @loc_files = [\"\"]\n" \
    "      @loc_line_tables = [List.new]\n" \
    "      @loc_col_tables = [List.new]\n" \
    "      @loc_sources = [\"\"]\n" \
    "      @lex64_tables = {\"__spinel_lex64__\" => \"\"}\n" \
    "      @lex64_tables.clear\n"
  )
  body = body.gsub("      init_compiler_intrinsics\n", "")
  body = body.gsub("      Runtime::Builtins.setup(self)\n", "")
  body = body.gsub("      Runtime::Builtins.setup(self, sandbox: sandbox)\n", "")
  body = body.gsub(
    /      BUILTIN_TYPES\.each \{ \|name\| @classes\[name\] \|\|= Runtime::WClass\.new\(name, nil\) \}\n/,
    "      BUILTIN_TYPES.each { |name| @classes[name] = Runtime::WClass.new(name, nil) }\n"
  )
  body = body.sub(/      @env\.set\("ℎ".*?      @env\.set\("𝐹".*?\n/m, "")
  body = replace_method(body, "self.body_has_return?", <<~RUBY)
    def self.body_has_return?(node)
      false
    end
  RUBY
  body = replace_method(body, "self.body_has_break?", <<~RUBY)
    def self.body_has_break?(node)
      false
    end
  RUBY
  body = replace_method(body, "self.body_has_next?", <<~RUBY)
    def self.body_has_next?(node)
      false
    end
  RUBY
  body = replace_method(body, "self.body_has_control_signal?", <<~RUBY)
    def self.body_has_control_signal?(node, signal_class, cache_ivar)
      false
    end
  RUBY
  body = replace_method(body, "save_state", <<~RUBY)
    def save_state
      nil
    end
  RUBY
  body = replace_method(body, "restore_state", <<~RUBY)
    def restore_state(snapshot)
      nil
    end
  RUBY
  body = replace_method(body, "evaluate_isolated", <<~RUBY)
    def evaluate_isolated(source = "", file_path = "")
      run(source.to_s, file_path)
    end
  RUBY
  body = replace_method(body, "snapshot_runtime_class_state", <<~RUBY)
    def snapshot_runtime_class_state
      nil
    end
  RUBY
  body = replace_method(body, "restore_runtime_class_state", <<~RUBY)
    def restore_runtime_class_state(snapshot)
      nil
    end
  RUBY
  body = replace_method(body, "source_for", <<~RUBY)
    def source_for(file)
      @source
    end
  RUBY
  body = replace_method(body, "visit_class_def", <<~RUBY)
    def visit_class_def(node)
      full_name = node.name.to_s
      if @current_module != nil && @current_module != "" && !full_name.include?(":")
        full_name = @current_module + ":" + full_name
      end
      ns_prefix = ""
      short_name = full_name
      if full_name.include?(":")
        last_colon = full_name.rindex(":")
        if last_colon != nil && last_colon > 0
          ns_prefix = full_name.slice(0, last_colon) || ""
          short_name = full_name.slice(last_colon + 1, full_name.length - last_colon - 1) || ""
        end
      end
      w_class = @classes[full_name]
      if w_class == nil
        superclass = nil
        if node.superclass
          super_name = node.superclass.to_s
          if ns_prefix != ""
            superclass = @classes[ns_prefix + ":" + super_name]
          end
          if superclass == nil && @current_module != nil && @current_module != ""
            superclass = @classes[@current_module + ":" + super_name]
          end
          if superclass == nil
            superclass = @classes[super_name]
          end
        end
        w_class = Runtime::WClass.new(full_name, superclass)
        @classes[full_name] = w_class
        if short_name != "" && short_name != full_name && @classes[short_name] == nil
          @classes[short_name] = w_class
        end
      end
      old_class = @current_class
      @current_class = w_class
      body = node.body.list
      i = 0
      while i < body.length
        stage0_define_class_body_method(w_class, body[i])
        i += 1
      end
      @current_class = old_class

      w_class
    end

    def stage0_define_class_body_method(w_class, expr)
      while expr != nil && expr.doc == 53
        expr = expr.value
      end
      return nil if expr == nil
      d = expr.doc
      if d == 12
        return stage0_define_class_method(w_class, expr)
      end
      if d == 13
        call_name = expr.name.to_s
        if call_name == "ro" || call_name == "rw"
          stage0_define_accessors(w_class, expr.args, call_name == "rw")
        end
        return nil
      end
      if d == 8
        target = expr.name
        val = evaluate(expr.value)
        if target.is_a?(String)
          w_class.set_constant(target, val)
          @env.bind_value(target, val)
        elsif target.doc == 9
          tname = target.name.to_s
          w_class.set_constant(tname, val)
          @env.bind_value(tname, val)
        elsif target.doc == 28
          w_class.set_cvar(target.name.to_s, val)
        end
        return val
      end
      if d == 46
        trait_name = expr.trait_name.to_s
        trait_obj = @traits[trait_name]
        if trait_obj != nil
          trait_obj.methods_table.each do |mname, mdef|
            if w_class.methods_table[mname] == nil
              w_class.methods_table[mname] = mdef
            end
          end
          @method_cache_epoch += 1
        end
        return nil
      end
      if d == 24 || d == 25 || d == 26
        return evaluate(expr)
      end
      nil
    end

    def stage0_define_accessors(w_class, args, writable)
      return nil if args == nil
      i = 0
      while i < args.length
        arg = args[i]
        attr_name = ""
        if arg.doc == 16
          attr_name = arg.value.to_s
          if attr_name.start_with?(":")
            attr_name = attr_name.slice(1, attr_name.length - 1)
          end
        elsif arg.doc == 9
          attr_name = arg.name.to_s
        elsif arg.doc == 4
          attr_name = arg.value.to_s
        end
        if attr_name != ""
          ivar_name = "@" + attr_name
          ivar_node = InstanceVar.new(ivar_name)
          getter_body = List.new([ivar_node])
          getter_def = Def.new(attr_name, [], getter_body)
          getter_def.accessor_kind = 1
          getter_def.accessor_ivar = ivar_name
          w_class.methods_table[attr_name] = getter_def
          if writable
            param_arg = Arg.new("val")
            assign_node = Assign.new(InstanceVar.new(ivar_name), Var.new("val"))
            setter_body = List.new([assign_node])
            setter_def = Def.new(attr_name + "=", [param_arg], setter_body)
            setter_def.accessor_kind = 2
            setter_def.accessor_ivar = ivar_name
            w_class.methods_table[attr_name + "="] = setter_def
          end
        end
        i += 1
      end
      @method_cache_epoch += 1
      nil
    end

    def stage0_define_class_method(w_class, expr)
      if expr.receiver != nil
        w_class.class_methods_table[expr.name.to_s] = expr
      else
        w_class.methods_table[expr.name.to_s] = expr
      end
      @method_cache_epoch += 1
      expr
    end
  RUBY
  body = replace_method(body, "visit_def", <<~RUBY)
    def visit_def(node)
      if @current_class != nil
        return stage0_define_class_method(@current_class, node)
      end
      @top_env.bind_value(node.name.to_s, node)
      if @env.object_id != @top_env.object_id
        @env.bind_value(node.name.to_s, node)
      end
      node
    end
  RUBY
  body = replace_method(body, "visit_begin", <<~RUBY)
    def visit_begin(node)
      evaluate(node.body)
    end
  RUBY
  body = replace_method(body, "evaluate_begin_rescue", <<~RUBY)
    def evaluate_begin_rescue(node, error)
      nil
    end
  RUBY
  if ENV["SPINEL_STAGE0_KEEP_INTERPRETER_CORE"] == "1"
    body = replace_method(body, "run", <<~RUBY)
      def run(source, file_path = "")
        source = stage0_normalize_compiler_source(source)
        @source = source
        @current_file = file_path
        @stage0_loading_depth = 0
        ast = parse_with_file(source, file_path)
        if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
          puts "stage0 source length"
          puts source.length
          puts "stage0 ast length"
          puts ast.length
        end
        evaluate(ast)
        0
      end
    RUBY
    body = replace_method(body, "method_source_location", <<~RUBY)
      def method_source_location(method, builtin)
        "unknown"
      end
    RUBY
    body = replace_method(body, "method_source_excerpt", <<~RUBY)
      def method_source_excerpt(method, builtin)
        []
      end
    RUBY
    body = replace_method(body, "method_reference", <<~RUBY)
      def method_reference(ref)
        nil
      end
    RUBY
    body = replace_method(body, "method_signature", <<~RUBY)
      def method_signature(method_name, method = nil)
        ""
      end
    RUBY
    body = replace_method(body, "completion_names", <<~RUBY)
      def completion_names
        []
      end
    RUBY
    body = replace_method(body, "define_builtin", <<~RUBY)
      def define_builtin(name, &block)
        nil
      end
    RUBY
    body = replace_method(body, "define_method_builtin", <<~RUBY)
      def define_method_builtin(name, &block)
        nil
      end
    RUBY
    body = replace_method(body, "runtime_error", <<~RUBY)
      def runtime_error(msg, node = nil, length = nil)
        puts msg.to_s
        exit 1
      end
    RUBY
    body = replace_method(body, "build_runtime_error", <<~RUBY)
      def build_runtime_error(msg, node = nil, length = nil)
        Error.new(msg.to_s)
      end
    RUBY
    body = replace_method(body, "runtime_error_from_exception", <<~RUBY)
      def runtime_error_from_exception(error = "", node = nil)
        error = error.to_s
        Error.new("runtime error")
      end
    RUBY
    body = replace_method(body, "reload_module", <<~RUBY)
      def reload_module(path = "")
        nil
      end
    RUBY
    body = replace_method(body, "parse_with_file", <<~RUBY)
      def parse_with_file(source, file = nil)
        parser = Parser.new(source.to_s)
        parser.parse
      end
    RUBY
    body = replace_method(body, "with_gc_paused_for_parse", <<~RUBY)
      def with_gc_paused_for_parse
        nil
      end
    RUBY
    body = replace_method(body, "profile_enabled?", <<~RUBY)
      def profile_enabled?
        false
      end
    RUBY
    body = replace_method(body, "profile_caller_label", <<~RUBY)
      def profile_caller_label
        "<top-level>"
      end
    RUBY
    body = replace_method(body, "profile_callable_label", <<~RUBY)
      def profile_callable_label(func)
        "<callable>"
      end
    RUBY
    body = replace_method(body, "with_profile_callable", <<~RUBY)
      def with_profile_callable(func)
        yield
      end
    RUBY
    body = replace_method(body, "profile_visit_call", <<~RUBY)
      def profile_visit_call(target_label)
        nil
      end
    RUBY
    body = replace_method(body, "profile_binary_op", <<~RUBY)
      def profile_binary_op(operator)
        nil
      end
    RUBY
    body = replace_method(body, "profile_dispatch_path", <<~RUBY)
      def profile_dispatch_path(table, key)
        nil
      end
    RUBY
    body = replace_method(body, "print_profile_table", <<~RUBY)
      def print_profile_table(io, title, table)
        nil
      end
    RUBY
    body = replace_method(body, "print_profile_report", <<~RUBY)
      def print_profile_report
        nil
      end
    RUBY
    body = replace_method(body, "environment_names", <<~RUBY)
      def environment_names(env)
        []
      end
    RUBY
    %w[
      quantity_inspection_lines color_inspection_lines date_inspection_lines date_time_inspection_lines
      ip4_inspection_lines cidr4_inspection_lines uuid_inspection_lines range_inspection_lines
      array_inspection_lines hash_inspection_lines wvalue_breakdown_lines singleton_breakdown
      object_breakdown double_breakdown stringy_breakdown int_breakdown instant_breakdown
      char_breakdown numeric_breakdown packed_breakdown duration_breakdown block_lines
      month_calendar_lines
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(value = nil, other = nil)
        []
      end
      RUBY
    end
    %w[
      quantity_unit_label quantity_dimension_label dimension_name_label dimension_signature
      expanded_quantity_label quantity_alias_labels quantity_conversion_labels canonical_unit_symbol
      exponent_label color_bar season_label moon_phase_label holiday_label floating_holiday_label
      ansi_color calendar_week_line i_to_ip4 ip4_class_label cidr_host_range_label cidr_diagram
      uuid_variant_label stringy_mode_label byte_label safe_codepoint_label category_label
      ipv4_label inspection_header_line inspection_field_line inspection_type_label color_palette_line
      project_relative_path project_root_for
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil, d = nil)
        ""
      end
      RUBY
    end
    %w[
      dimension_base_components ip4_octets coerce_value_to_wvalue coerce_integer_to_wvalue
      coerce_stringy_to_wvalue coerce_decimal_to_wvalue coerce_rational_to_wvalue
      coerce_color_to_wvalue coerce_date_to_wvalue coerce_date_time_to_wvalue
      coerce_packed_date_fields coerce_ip4_to_wvalue coerce_cidr4_to_wvalue coerce_packed_ip4
      coerce_currency_to_wvalue coerce_percentage_to_wvalue coerce_quantity_to_wvalue
      coerce_boxed_quantity_wvalue coerce_duration_to_wvalue exact_wvalue unsupported_wvalue
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil, d = nil, e = nil, f = nil)
        {}
      end
      RUBY
    end
    %w[
      convert_quantity_pipe decompose_quantity ast_to_unit_string apply_type_hint
      parse_energy_fuel substance_mass assign_target wrap_unsigned_bits wrap_signed_bits
      primitive_runtime_class tungsten_type_info
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil, d = nil)
        nil
      end
      RUBY
    end
    body = replace_method(body, "tungsten_class_name", <<~RUBY)
      def tungsten_class_name(value)
        "Object"
      end
    RUBY
    body = replace_method(body, "dimensionless_unit", <<~RUBY)
      def dimensionless_unit
        nil
      end
    RUBY
    body = replace_method(body, "visit_on_guard", <<~RUBY)
      def visit_on_guard(node)
        nil
      end
    RUBY
    body = replace_method(body, "expand_on_guards", <<~RUBY)
      def expand_on_guards(body)
        body
      end
    RUBY
    body = replace_method(body, "method_doc_for", <<~RUBY)
      def method_doc_for(class_name, method_name)
        ""
      end
    RUBY
    body = replace_method(body, "inline_signature_for", <<~RUBY)
      def inline_signature_for(source)
        ""
      end
    RUBY
    %w[
      color_palette_color hsl_to_rgb color_luma season_index easter_date
      ip4_to_i decode_w_value_double decode_w_value_char sign_extend signed_payload
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil)
        0
      end
      RUBY
    end
    %w[
      nth_weekday? last_weekday?
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil, d = nil)
        false
      end
      RUBY
    end
    %w[
      holiday_art halloween_pumpkin_art christmas_lights_line christmas_tree_art st_patricks_art
      easter_art fourth_of_july_art valentine_heart_art thanksgiving_art
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(value = nil)
        []
      end
      RUBY
    end
    %w[
      scene_columns scene_line blank_scene_line place_scene_text visible_length holiday_scene_label
      calendar_header_line calendar_separator_line calendar_place_day calendar_column
      date_scene_header_line date_scene_subheader_line date_scene_season_rail
      date_scene_season_column compact_cell fit_cell truncate_visible
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil, d = nil, e = nil)
        ""
      end
      RUBY
    end
    body = replace_method(body, "visible_length", <<~RUBY)
      def visible_length(a = nil, b = nil, c = nil, d = nil, e = nil)
        0
      end
    RUBY
    body = replace_method(body, "date_scene_season_column", <<~RUBY)
      def date_scene_season_column(a = nil, b = nil, c = nil)
        0
      end
    RUBY
    %w[
      date_scene_right_panel small_array_candidate coerce_array_to_wvalue
      decimal_sig_scale normalize_sig_scale
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil)
        []
      end
      RUBY
    end
    %w[
      array_sparkline
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil)
        ""
      end
      RUBY
    end
    %w[
      decode_w_value decode_w_value_stringy wvalue_quantity_unit_symbol
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil)
        nil
      end
      RUBY
    end
    body = replace_method(body, "w_value_double?", <<~RUBY)
      def w_value_double?(bits)
        false
      end
    RUBY
    body = replace_method(body, "inspection_value_label", <<~RUBY)
      def inspection_value_label(value)
        ""
      end
    RUBY
    body = replace_method(body, "visit_magic_constant", <<~RUBY)
      def visit_magic_constant(node)
        ""
      end
    RUBY
    body = replace_method(body, "visit_array_literal", <<~RUBY)
      def visit_array_literal(node)
        result = List.new
        list = node.list
        i = 0
        while i < list.length
          result.push(evaluate(list[i]))
          i += 1
        end
        result
      end
    RUBY
    body = replace_method(body, "visit_tuple", <<~RUBY)
      def visit_tuple(node)
        []
      end
    RUBY
    body = replace_method(body, "visit_hash_literal", <<~RUBY)
      def visit_hash_literal(node)
        entries = node.entries.list
        entry_count = entries.length
        if entry_count == 0
          return {}
        end
        entry_items = entries[0].list
        key_node = entry_items[0]
        if stage0_static_hash_key?(key_node)
          key = stage0_static_hash_key(key_node)
        else
          key = evaluate(key_node).to_s
        end
        value = evaluate(entry_items[1])
        result = {}
        result[key] = value
        i = 1
        while i < entry_count
          entry_items = entries[i].list
          key_node = entry_items[0]
          if stage0_static_hash_key?(key_node)
            key = stage0_static_hash_key(key_node)
          else
            key = evaluate(key_node).to_s
          end
          value = evaluate(entry_items[1])
          result[key] = value
          i += 1
        end
        result
      end
    RUBY
    body = replace_method(body, "visit_string_interpolation", <<~RUBY)
      def visit_string_interpolation(node)
        ""
      end
    RUBY
    body = replace_method(body, "visit_splat", <<~RUBY)
      def visit_splat(node)
        evaluate(node.exp)
      end
    RUBY
    body = replace_method(body, "inspect_wvalue_literal", <<~RUBY)
      def inspect_wvalue_literal(raw)
        raw.to_s
      end
    RUBY
    body = replace_method(body, "inspect_runtime_value", <<~RUBY)
      def inspect_runtime_value(value)
        value.to_s
      end
    RUBY
    body = replace_method(body, "format_wvalue_breakdown", <<~RUBY)
      def format_wvalue_breakdown(bits, raw = nil, note = nil)
        raw.to_s
      end
    RUBY
    body = replace_method(body, "box_float_wvalue", <<~RUBY)
      def box_float_wvalue(value)
        0
      end
    RUBY
    body = replace_method(body, "wvalue_object_space?", <<~RUBY)
      def wvalue_object_space?(bits)
        false
      end
    RUBY
    %w[
      visit_measurement_literal visit_quantity_literal visit_currency_literal visit_percentage_literal
      visit_date visit_date_time visit_time_literal visit_uuid visit_color_literal visit_rational_literal
      visit_duration visit_month visit_week visit_key_literal visit_byte_array_literal
      visit_byte_array_interpolation visit_typed_array
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(node)
        nil
      end
      RUBY
    end
    body = replace_method(body, "evaluate", <<~RUBY)
      def evaluate(node)
        return nil unless node

        d = node.doc || 0
        return visit_list(node) if d == 1
        if d == 2
          visit_print(node)
          return nil
        end
        return node.value if d == 3
        return node.value if d == 4
        return node.value if d == 5
        return nil if d == 6
        return visit_binary_op(node) if d == 7
        return visit_assign(node) if d == 8
        return visit_var(node) if d == 9
        return visit_if(node) if d == 10
        return visit_while(node) if d == 11
        return visit_def(node) if d == 12
        return visit_call(node) if d == 13
        return visit_return(node) if d == 14
        return visit_assign_op(node) if d == 15
        return cached_symbol_value(node) if d == 16
        return visit_array_literal(node) if d == 17
        return visit_hash_literal(node) if d == 18
        return visit_and(node) if d == 19
        return visit_or(node) if d == 20
        return visit_in_test(node) if d == 21
        return visit_case_expr(node) if d == 22
        return visit_use(node) if d == 23
        return visit_class_def(node) if d == 24
        return visit_module_def(node) if d == 25
        return visit_trait_def(node) if d == 26
        return visit_instance_var(node) if d == 27
        return visit_class_var(node) if d == 28
        return visit_global_var(node) if d == 29
        return visit_self(node) if d == 30
        return node.value if d == 31
        return node.value if d == 32
        return decode_w_value(node.value, node.raw) if d == 33
        return visit_begin(node) if d == 34
        return visit_raise(node) if d == 35
        if d == 36
          visit_write(node)
          return nil
        end
        return visit_fn(node) if d == 37
        return visit_yield(node) if d == 38
        return visit_break(node) if d == 39
        return visit_next(node) if d == 40
        return visit_not(node) if d == 41
        return visit_tuple(node) if d == 42
        return visit_splat(node) if d == 43
        return visit_string_interpolation(node) if d == 44
        return visit_alias(node) if d == 45
        return visit_is(node) if d == 46
        return visit_super(node) if d == 47
        nil
      end
    RUBY
    body = replace_method(body, "visit_list", <<~RUBY)
      def visit_list(node)
        result = nil
        i = 0
        while i < node.length
          result = evaluate(node[i])
          i += 1
        end
        result
      end
    RUBY
    body = replace_method(body, "visit_binary_op", <<~RUBY)
      def visit_binary_op(node)
        left = evaluate(node.left)
        op = node.operator.to_s

        if op == "in"
          if node.right.doc == 1
            i = 0
            while i < node.right.length
              return true if left == evaluate(node.right[i])
              i += 1
            end
          end
          return false
        end

        right = evaluate(node.right)

        if op == "=="
          return left == right
        end
        if op == "!="
          return !(left == right)
        end
        if op == "<"
          return left < right
        end
        if node.operator == :<=
          return left <= right
        end
        if node.operator == :>
          return left > right
        end
        if node.operator == :>=
          return left >= right
        end
        if node.operator == :+
          return left + right
        end
        if node.operator == :-
          return left - right
        end
        if node.operator == :*
          return left * right
        end
        if node.operator == :/
          return left / right
        end
        if node.operator == :%
          return left % right
        end
        if node.operator == :**
          return left ** right
        end
        if node.operator == :<<
          return left << right
        end
        if node.operator == :>>
          return left >> right
        end
        if node.operator == :&
          return left & right
        end
        if node.operator == :|
          return left | right
        end
        if node.operator == :^
          return left ^ right
        end

        runtime_error("unknown operator", node)
      end
    RUBY
    body = replace_method(body, "visit_assign", <<~RUBY)
      def visit_assign(node)
        value = evaluate(node.value)
        @env.set(node.name, value)
        value
      end
    RUBY
  body = replace_method(body, "visit_assign_op", <<~RUBY)
    def visit_assign_op(node)
      current = evaluate(node.name)
      value = evaluate(node.value)
      op = node.operator.to_s
      if ENV["TUNGSTEN_SPINEL_STAGE0_CALL_TRACE"] == "1"
        target_name = ""
        if node.name.doc == 9
          target_name = node.name.name.to_s
        end
        File.write("/tmp/tungsten-stage0-assign-op.txt", target_name + " op=" + op + " current=" + current.to_s + " value=" + value.to_s)
      end
      if op == "+" || op == "PLUS"
        result = current + value
      elsif op == "-" || op == "MINUS"
        result = current - value
      elsif op == "*" || op == "STAR"
        result = current * value
      elsif op == "/" || op == "SLASH"
        result = current / value
      else
        result = value
      end
      if node.name.doc == 9
        @env.set(node.name.name, result)
      elsif node.name.doc == 27
        self_obj = nil
        if @self_stack.length > 0
          self_obj = @self_stack[@self_stack.length - 1]
        end
        if self_obj != nil
          self_obj.set_ivar(node.name.name.to_s, result)
        end
      end
      result
    end
  RUBY
    body = replace_method(body, "visit_var", <<~RUBY)
      def visit_var(node)
        @env.get(node.name)
      end
    RUBY
    body = replace_method(body, "visit_global_var", <<~RUBY)
      def visit_global_var(node)
        nil
      end
    RUBY
    body = replace_method(body, "visit_instance_var", <<~RUBY)
      def visit_instance_var(node)
        nil
      end
    RUBY
    body = replace_method(body, "visit_class_var", <<~RUBY)
      def visit_class_var(node)
        nil
      end
    RUBY
    body = replace_method(body, "assign_target", <<~RUBY)
      def assign_target(target, value, node)
        value
      end
    RUBY
    body = replace_method(body, "find_current_class", <<~RUBY)
      def find_current_class
        nil
      end
    RUBY
    body = replace_method(body, "visit_range_literal", <<~RUBY)
      def visit_range_literal(node)
        nil
      end
    RUBY
    body = replace_method(body, "visit_print", <<~RUBY)
      def visit_print(node)
        i = 0
        while i < node.args.length
          puts w_to_s(evaluate(node.args[i]))
          i += 1
        end
        nil
      end
    RUBY
    body = replace_method(body, "visit_write", <<~RUBY)
      def visit_write(node)
        i = 0
        while i < node.args.length
          print w_to_s(evaluate(node.args[i]))
          i += 1
        end
        nil
      end
    RUBY
    body = replace_method(body, "truthy?", <<~RUBY)
      def truthy?(value)
        if value
          true
        else
          false
        end
      end
    RUBY
    body = replace_method(body, "visit_if", <<~RUBY)
      def visit_if(node)
        if truthy?(evaluate(node.condition))
          return evaluate(node.then_block)
        end
        evaluate(node.else_block)
      end
    RUBY
    body = replace_method(body, "visit_while", <<~RUBY)
      def visit_while(node)
        result = nil
        while truthy?(evaluate(node.condition))
          result = evaluate(node.body)
          break if @returning
          break if @exiting
        end
        result
      end
    RUBY
    body = replace_method(body, "visit_and", <<~RUBY)
      def visit_and(node)
        left = evaluate(node.left)
        return left if !truthy?(left)

        evaluate(node.right)
      end
    RUBY
    body = replace_method(body, "visit_or", <<~RUBY)
      def visit_or(node)
        left = evaluate(node.left)
        return left if truthy?(left)

        evaluate(node.right)
      end
    RUBY
    %w[
      visit_case_expr visit_until visit_with visit_trait_def visit_module_def visit_is visit_path
      visit_break visit_next visit_yield visit_alias visit_not visit_super visit_splat
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(node)
        nil
      end
      RUBY
    end
    body = replace_method(body, "resolve_cached_local", <<~RUBY)
      def resolve_cached_local(node, name)
        nil
      end
    RUBY
    body = replace_method(body, "call_primitive_method_from_nodes", <<~RUBY)
      def call_primitive_method_from_nodes(recv, name, arg_nodes, block = nil)
        nil
      end
    RUBY
    body = replace_method(body, "fits_signed_width?", <<~RUBY)
      def fits_signed_width?(value, width)
        true
      end
    RUBY
    body = replace_method(body, "w_to_s", <<~RUBY)
      def w_to_s(value)
        value.to_s
      end
    RUBY
    %w[
      cached_simple_method_plan build_simple_method_plan simple_method_expression
      execute_simple_method_plan_from_nodes simple_call_arg_value simple_method_value simple_method_value3
      simple_method_numeric_expression?
      cached_simple_block_plan build_simple_block_plan simple_block_statement simple_block_expression
      execute_simple_block_plan_from_nodes execute_simple_block_plan simple_block_value simple_block_env_ready?
      simple_block_env_bound? simple_block_env_value simple_block_env_assign simple_block_env_assign_op
      cached_simple_w_method_plan build_simple_w_method_plan simple_w_method_statement simple_w_method_expression
      execute_simple_w_method_plan simple_w_method_plan_ready? execute_simple_w_method_plan_on_ivars
      simple_w_method_value
      cached_simple_while_plan build_simple_while_plan simple_while_step simple_while_condition_expression
      simple_while_receiver_expression simple_while_expression execute_simple_while_plan
      execute_mixed_simple_while_plan bind_simple_while_plan bind_simple_while_condition_expression
      bind_simple_while_receiver_expression bind_simple_while_expression execute_mixed_simple_while_steps
      simple_while_condition_value simple_while_value simple_while_arithmetic simple_while_compare
      cached_literal_case_lookup build_literal_case_lookup literal_case_value
      static_condition_truth static_condition_literal_value static_condition_compare
      invoke_block invoke_block_from_nodes execute_bound_block collect_free_vars walk_free_vars
      new_free_var_env cached_param_slot_names cached_free_var_slot_names
      collect_local_slot_names collect_assign_target_slot_names add_local_slot_name
      catch_break_if_needed catch_next_if_needed iterate_with try_autoload_core
      bind_exact_small_args_from_nodes callable_body
      small_arg_length_without_splat no_call_args? one_call_arg_node direct_arg_value cached_symbol_value
      call_self_hosted_parser_intrinsic_from_nodes sync_self_hosted_parser_current_token
      skip_self_hosted_parser_tokens call_builtin_from_nodes call_builtin call_ruby_method_from_nodes
      invoke_method_builtin call_lambda_with_values with_profile_callable hash_indifferent_get
      wyhash_mix_u64_value wyhash_read_u32_value wyhash_read_u64_value wyhash64_string_value
      primitive_runtime_class tungsten_class_name tungsten_type_info substance_mass parse_energy_fuel
      evaluate_fallback read_ivar resolve_class_constant resolve_unique_namespaced_constant
    ].each do |name|
      body = replace_method(body, name, <<~RUBY)
      def #{name}(a = nil, b = nil, c = nil, d = nil)
        nil
      end
      RUBY
    end
    body = replace_method(body, "find_project_root", <<~RUBY)
      def find_project_root(path = ".")
        "."
      end
    RUBY
    body = replace_method(body, "resolve_use_path", <<~RUBY)
      def resolve_use_path(use_path)
        # See companion comment at the second replace_method site.
        # Spinel stage0 can't dispatch `file.split("/")` through
        # the .to_s chain — find the last "/" by walking
        # @current_file directly with byteslice instead.
        path = use_path
        base = "."
        if @current_file != nil
          last_slash = -1
          i = 0
          while i < @current_file.length
            if @current_file.byteslice(i, 1) == "/"
              last_slash = i
            end
            i += 1
          end
          if last_slash > 0
            base = @current_file.byteslice(0, last_slash)
          end
        end
        candidate = base + "/" + path
        if !candidate.end_with?(".w")
          candidate = candidate + ".w"
        end
        return candidate if File.exist?(candidate)

        candidate = "compiler/" + path
        if !candidate.end_with?(".w")
          candidate = candidate + ".w"
        end
        return candidate if File.exist?(candidate)

        candidate = path
        if !candidate.end_with?(".w")
          candidate = candidate + ".w"
        end
        candidate
      end
    RUBY
    body = replace_method(body, "visit_use", <<~RUBY)
      def visit_use(node)
        path = resolve_use_path(node.path)
        if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
          File.write("/tmp/tungsten-stage0-last-use.txt", path)
        end
        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace use"
          puts path
        end
        return nil if @loaded_files.include?(path)

        @loaded_files.add(path)
        raw_source = File.read(path)
      if path.end_with?("compiler/lib/lexer.w")
        source = stage0_normalize_lexer_source(raw_source)
      elsif path.end_with?("languages/tungsten/lexers/regex.w")
        source = stage0_normalize_regex_source(raw_source)
      else
        source = stage0_normalize_source(raw_source)
      end
        old_file = @current_file
        @current_file = path
        ast = parse_with_file(source, path)
        if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
          File.write("/tmp/tungsten-stage0-last-use-ast.txt", ast.length.to_s)
        end
        if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
          puts "stage0 use"
          puts path
          puts ast.length
        end
        @stage0_loading_depth += 1
        evaluate(ast)
        @stage0_loading_depth -= 1
        @current_file = old_file
        nil
      end
    RUBY
    body = replace_method(body, "instantiate", <<~RUBY)
      def instantiate(w_class, args)
        obj = WObject.new(w_class)
        constructor = w_class.lookup_method("new")
        call_w_method(obj, constructor, args) if constructor
        obj
      end
    RUBY
    body = replace_method(body, "visit_begin", <<~RUBY)
      def visit_begin(node)
        evaluate(node.body)
      end
    RUBY
    body = replace_method(body, "evaluate_begin_rescue", <<~RUBY)
      def evaluate_begin_rescue(node, error)
        nil
      end
    RUBY
    body = replace_method(body, "visit_raise", <<~RUBY)
      def visit_raise(node)
        runtime_error("runtime error", node)
      end
    RUBY
    body = replace_method(body, "visit_fn", <<~RUBY)
      def visit_fn(node)
        node.closure_env = @env
        @env.bind_value(node.name.to_s, node) if node.name
        node
      end
    RUBY
    body = replace_method(body, "visit_var", <<~RUBY)
      def visit_var(node)
        name = node.name.to_s
        value = @env.get(name)
        return value if value != nil

        value = @classes[name]
        return value if value != nil

        value = @modules[name]
        return value if value != nil

        nil
      end
    RUBY
    body = replace_method(body, "visit_assign", <<~RUBY)
      def visit_assign(node)
        value = evaluate(node.value)
        target = node
        target = node.name
        if target.is_a?(InstanceVar)
          self_obj = stage0_current_self
          if self_obj.is_a?(WObject)
            self_obj.set_ivar(target.name.to_s, value)
            return value
          end
        end
        @env.set(target.to_s, value)
        value
      end
    RUBY
    body = replace_method(body, "visit_instance_var", <<~RUBY)
      def visit_instance_var(node)
        self_obj = stage0_current_self
        if self_obj.is_a?(WObject)
          return self_obj.get_ivar(node.name.to_s)
        end
        nil
      end
    RUBY
    body = replace_method(body, "evaluate_args", <<~RUBY)
      def evaluate_args(arg_nodes)
        values = []
        return values if arg_nodes == nil

        i = 0
        while i < arg_nodes.length
          values.push(evaluate(arg_nodes[i]))
          i += 1
        end
        values
      end
    RUBY
    body = replace_method(body, "new_param_env", <<~RUBY)
      def new_param_env(parent, params, owner = nil, barrier: false)
        stage0_mark_env(Environment.new(parent))
      end
    RUBY
    body = replace_method(body, "bind_params", <<~RUBY)
      def bind_params(env, params, args, splat_index = nil)
        return nil if params == nil

        i = 0
        while i < params.length
          param = params[i]
          name = param.name.to_s
          if splat_index != nil && i == splat_index
            rest = []
            j = i
            while j < args.length
              rest.push(args[j])
              j += 1
            end
            env.bind_new_slot(name, rest)
          elsif i < args.length
            env.bind_new_slot(name, args[i])
          else
            env.bind_new_slot(name, nil)
          end
          i += 1
        end
        nil
      end
    RUBY
    body = replace_method(body, "execute_callable_body", <<~RUBY)
      def execute_callable_body(func, method_env, block = nil)
        old_env = @env
        old_returning = @returning
        old_return_value = @return_value
        @env = method_env
        @returning = false
        @return_value = nil
        result = evaluate(func.body)
        if @returning
          result = @return_value
        end
        @env = old_env
        @returning = old_returning
        @return_value = old_return_value
        result
      end
    RUBY
    body = replace_method(body, "call_method", <<~RUBY)
      def call_method(func, arg_nodes, block = nil)
        method_env = new_param_env(@env, func.args, func)
        bind_params(method_env, func.args, evaluate_args(arg_nodes), func.splat_index)
        execute_callable_body(func, method_env, block)
      end
    RUBY
    body = replace_method(body, "execute_bound_w_method", <<~RUBY)
      def execute_bound_w_method(recv, method, method_env, block = nil, call_node = nil)
        old_env = @env
        old_returning = @returning
        old_return_value = @return_value
        @self_stack.push(recv)
        @env = method_env
        @returning = false
        @return_value = nil
        result = evaluate(method.body)
        if @returning
          result = @return_value
        end
        @env = old_env
        @returning = old_returning
        @return_value = old_return_value
        @self_stack.pop
        result
      end
    RUBY
    body = replace_method(body, "call_w_method", <<~RUBY)
      def call_w_method(recv, method, args, block = nil, call_node: nil)
        return nil if method == nil

        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace call_w_method before env"
        end
        params = method.params
        if method.is_a?(Def)
          params = method.args
        end
        method_env = new_param_env(@env, params, method)
        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace call_w_method before bind"
        end
        bind_params(method_env, params, args, method.splat_index)
        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace call_w_method before execute"
        end
        execute_bound_w_method(recv, method, method_env, block, call_node)
      end
    RUBY
    body = replace_method(body, "call_w_method_from_nodes", <<~RUBY)
      def call_w_method_from_nodes(recv, method, arg_nodes, block = nil, call_node: nil)
        call_w_method(recv, method, evaluate_args(arg_nodes), block, call_node: call_node)
      end
    RUBY
    body = replace_method(body, "instantiate_from_nodes", <<~RUBY)
      def instantiate_from_nodes(w_class, arg_nodes)
        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace instantiate before object"
        end
        obj = WObject.new(w_class)
        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace instantiate before lookup"
        end
        constructor = w_class.lookup_method("new")
        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace instantiate before constructor"
        end
        call_w_method_from_nodes(obj, constructor, arg_nodes) if constructor
        if ENV["TUNGSTEN_SPINEL_STAGE0_TRACE"] == "1"
          puts "trace instantiate after constructor"
        end
        obj
      end
    RUBY
    body = insert_before_private(body, <<~RUBY)

      def instantiate_with_arg_offset(w_class, args, offset)
        obj = WObject.new(w_class)
        constructor = w_class.lookup_method("new")
        call_w_method_with_arg_offset(obj, constructor, args, offset) if constructor
        obj
      end

      def call_w_method_with_arg_offset(recv, method, args, offset)
        return nil if method == nil

        method_env = new_param_env(@env, method.params, method)
        bind_params_from_offset(method_env, method.params, args, offset, method.splat_index)
        execute_bound_w_method(recv, method, method_env, nil, nil)
      end

      def bind_params_from_offset(env, params, args, offset, splat_index = nil)
        return nil if params == nil

        i = 0
        while i < params.length
          param = params[i]
          name = param.name.to_s
          arg_index = i + offset
          if arg_index < args.length
            env.bind_new_slot(name, args[arg_index])
          else
            env.bind_new_slot(name, nil)
          end
          i += 1
        end
        nil
      end

      def stage0_instantiate_named(class_name, arg_nodes)
        w_class = @classes[class_name]
        if w_class == nil
          runtime_error("stage0 unknown class: " + class_name)
        end
        instantiate_from_nodes(w_class, arg_nodes)
      end
    RUBY
    body = replace_method(body, "visit_call", <<~RUBY)
      def visit_call(node)
        name = node.name.to_s
        if node.obj != nil
          recv = evaluate(node.obj)
          if recv.is_a?(WClass)
            if name == "new"
              return instantiate_from_nodes(recv, node.args)
            end
            method = recv.lookup_method(name)
            return call_w_method_from_nodes(recv, method, node.args, node.block, call_node: node) if method
          end
          if recv.is_a?(WObject)
            method = recv.w_class.lookup_method(name)
            return call_w_method_from_nodes(recv, method, node.args, node.block, call_node: node) if method
          end
          return stage0_primitive_call(recv, name, node.args)
        end

        if name == "argv"
          return []
        end
        if name == "<<"
          result = nil
          i = 0
          while i < node.args.length
            result = evaluate(node.args[i])
            puts result
            i += 1
          end
          return result
        end
        if name == "system"
          args = evaluate_args(node.args)
          return system(args[0].to_s)
        end
        if name == "write_file"
          args = evaluate_args(node.args)
          File.write(args[0].to_s, args[1].to_s)
          return nil
        end
        if name == "stage0_environment"
          return stage0_instantiate_named("Environment", node.args)
        end
        if name == "stage0_interpreter"
          return stage0_instantiate_named("Interpreter", node.args)
        end
        if name == "stage0_lexer"
          return stage0_instantiate_named("Lexer", node.args)
        end
        if name == "stage0_loader"
          return stage0_instantiate_named("Loader", node.args)
        end
        if name == "stage0_parser"
          return stage0_instantiate_named("Parser", node.args)
        end
        if name == "stage0_regex_lexer"
          return stage0_instantiate_named("RegexLexer", node.args)
        end
        if name == "stage0_repl"
          return stage0_instantiate_named("REPL", node.args)
        end
        if name == "stage0_new"
          args = evaluate_args(node.args)
          w_class = @classes[args[0].to_s]
          if w_class == nil
            runtime_error("stage0 unknown class: " + args[0].to_s, node)
          end
          return instantiate_with_arg_offset(w_class, args, 1)
        end
        if name == "exit"
          File.write("/tmp/stage0-trace-EXIT-A", "site=A_call_dispatch")
          @exiting = true
          return nil
        end

        w_class = @classes[name]
        return instantiate_from_nodes(w_class, node.args) if w_class != nil

        func = @env.get(name)
        return call_method(func, node.args, node.block) if func.is_a?(Def)

        self_obj = stage0_current_self
        if self_obj.is_a?(WObject)
          method = self_obj.w_class.lookup_method(name)
          return call_w_method_from_nodes(self_obj, method, node.args, node.block, call_node: node) if method
        end
        if self_obj.is_a?(WClass)
          method = self_obj.lookup_method(name)
          return call_w_method_from_nodes(self_obj, method, node.args, node.block, call_node: node) if method
        end
        if @stage0_loading_depth > 0
          return nil
        end

        runtime_error("stage0 unknown function: " + name, node)
      end
    RUBY
    body = insert_before_private(body, <<~RUBY)

      def stage0_primitive_call(recv, name, arg_nodes)
        args = evaluate_args(arg_nodes)
        index = 0
        if args.length > 0
          index = args[0].to_i
        end
        text = recv.to_s
        if name == "to_s"
          return text
        end
        if name == "nil?"
          return recv == nil
        end
        if name == "size" || name == "length"
          if recv.is_a?(List)
            return recv.length
          end
          return text.length
        end
        if name == "empty?"
          if recv.is_a?(List)
            return recv.empty?
          end
          return text.empty?
        end
        if name == "[]"
          if recv.is_a?(List)
            return recv[index]
          end
          return ""
        end
        if name == "[]="
          return args[1]
        end
        if name == "push" || name == "<<"
          if recv.is_a?(List)
            recv.push(args[0])
          end
          return recv
        end
        if name == "include?"
          return false
        end
        if name == "key?"
          return false
        end
        if name == "keys"
          return []
        end
        if name == "first"
          if recv.is_a?(List)
            return recv.first
          end
          return nil
        end
        if name == "last"
          if recv.is_a?(List)
            return recv.last
          end
          return nil
        end
        if name == "split"
          return text.split(args[0].to_s)
        end
        if name == "strip"
          return text.strip
        end
        if name == "starts_with?" || name == "start_with?"
          return text.start_with?(args[0].to_s)
        end
        if name == "ends_with?" || name == "end_with?"
          return text.end_with?(args[0].to_s)
        end
        if name == "replace"
          return text.gsub(args[0].to_s, args[1].to_s)
        end
        if name == "join"
          return text
        end
        if name == "to_i"
          return recv.to_i
        end
        if name == "ord"
          return text.ord
        end
        if @stage0_loading_depth > 0
          return nil
        end
        if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
          File.write("/tmp/tungsten-stage0-unsupported-receiver.txt", name + " recv=" + text)
        end
        runtime_error("stage0 unsupported receiver call: " + name)
      end

      def stage0_current_self
        @self_stack[@self_stack.length - 1]
      end

      def stage0_normalize_source(source)
        lines = source.to_s.split("\n")
        out = ""
        i = 0
        while i < lines.length
          line = lines[i]
          if line.strip.start_with?("#")
            i += 1
            next
          end
          line = stage0_rewrite_named_new(line, "Environment", "stage0_environment")
          line = stage0_rewrite_named_new(line, "Interpreter", "stage0_interpreter")
          line = stage0_rewrite_named_new(line, "Lexer", "stage0_lexer")
          line = stage0_rewrite_named_new(line, "Loader", "stage0_loader")
          line = stage0_rewrite_named_new(line, "Parser", "stage0_parser")
          line = stage0_rewrite_named_new(line, "RegexLexer", "stage0_regex_lexer")
          line = stage0_rewrite_named_new(line, "REPL", "stage0_repl")
          class_parts = line.split("+ ")
          if class_parts.length > 1 && class_parts[0] == ""
            out = out + "class " + class_parts[1]
          else
            out = out + line
          end
          out = out + "\n"
          i += 1
        end
        out
      end

      def stage0_normalize_regex_source(source)
        lines = source.to_s.split("\n")
        out = ""
        skipping = false
        i = 0
        while i < lines.length
          line = lines[i]
          if skipping
            if line.start_with?("  -> ")
              skipping = false
            else
              i += 1
              next
            end
          end
          if line == "  -> tokenize" || line == "  -> tokenize_one" || line == "  -> scan_regex"
            skipping = true
            i += 1
            next
          end
          out = out + line + "\n"
          i += 1
        end
        stage0_normalize_source(out)
      end

      def stage0_normalize_lexer_source(source)
        ""
      end

      def stage0_rewrite_named_new(line, class_name, helper_name)
        needle = class_name + ".new("
        parts = line.split(needle)
        if parts.length > 1
          return parts[0] + helper_name + "(" + parts[1]
        end
        line
      end
    RUBY
    return body
  end
  body = replace_method(body, "run", <<~RUBY)
    def run(source, file_path = "")
      source = source.to_s
      @source = source
      @current_file = file_path
      if file_path != nil && file_path != ""
        @loaded_files[file_path.to_s] = true
      end
      ast = parse_with_file(source, file_path)
      evaluate(ast)
      0
    end
  RUBY
  body = replace_method(body, "reload_module", <<~RUBY)
    def reload_module(path = "")
      source = File.read(path)
      @source = source
      ast = parse_with_file(source, path)
      evaluate(ast)
    end
  RUBY
  body = replace_method(body, "evaluate", <<~RUBY)
    def evaluate(node)
      node.nil? ? nil : node.eval_in(self)
    end
  RUBY
  body = replace_method(body, "visit_list", <<~RUBY)
    def visit_list(node)
      result = nil
      list = node.list
      n = list.length
      i = 0
      while i < n
        result = evaluate(list[i])
        break if @returning || @exiting || @breaking || @nexting
        i += 1
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_int", <<~RUBY)
    def visit_int(node)
      if node.is_a?(Int)
        return node.value
      end
      node.value.to_i
    end
  RUBY
  unless body.match?(/^[ \t]*def[ \t]+visit_int(?:\b|\s|\()/)
    body = body.sub(/(^[ \t]*)def[ \t]+visit_boolean\(node\)/, <<~RUBY.rstrip)
\\1def visit_int(node)
\\1  if node.is_a?(Int)
\\1    return node.value
\\1  end
\\1  node.value.to_i
\\1end

\\1def visit_boolean(node)
    RUBY
  end
  body = replace_method(body, "visit_print", <<~RUBY)
    def visit_print(node)
      result = nil
      i = 0
      while i < node.args.length
        result = evaluate(node.args[i])
        puts w_to_s(result)
        i += 1
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_string_literal", <<~RUBY)
    def visit_string_literal(node)
      node.value
    end
  RUBY
  body = replace_method(body, "visit_boolean", <<~RUBY)
    def visit_boolean(node)
      node.value
    end
  RUBY
  body = replace_method(body, "visit_nil", <<~RUBY)
    def visit_nil(node)
      value = nil
      value
    end
  RUBY
  body = replace_method(body, "visit_binary_op", <<~RUBY)
    def visit_binary_op(node)
      left = evaluate(node.left)
      op_code = node.bop_code
      rnode = node.right

      if op_code == 21
        if rnode.doc == 1
          i = 0
          while i < rnode.length
            value = evaluate(rnode[i])
            if value.is_a?(WRange)
              return true if value.include?(left)
            else
              return true if left == value
            end
            i += 1
          end
          return false
        end
        rhs = evaluate(rnode)
        return rhs.include?(left) if rhs.is_a?(WRange) || rhs.is_a?(List) || rhs.is_a?(Array) || rhs.is_a?(String)
        return false
      end

      if op_code == 19
        return left if truthy?(left)
        return evaluate(rnode)
      elsif op_code == 20
        return left unless truthy?(left)
        return evaluate(rnode)
      end

      right = evaluate(rnode)

      case op_code
      when 1
        if left.is_a?(PackedNode) && right.is_a?(PackedNode)
          left.object_id == right.object_id
        elsif left.is_a?(PackedNode) || right.is_a?(PackedNode)
          false
        else
          left == right
        end
      when 2
        if left.is_a?(PackedNode) && right.is_a?(PackedNode)
          left.object_id != right.object_id
        elsif left.is_a?(PackedNode) || right.is_a?(PackedNode)
          true
        else
          !(left == right)
        end
      when 3 then left < right
      when 4 then left <= right
      when 5 then left > right
      when 6 then left >= right
      when 7 then left <=> right
      when 8
        if left.is_a?(List) && right.is_a?(List)
          res = List.new
          li = 0
          while li < left.length
            res.push(left[li])
            li += 1
          end
          ri = 0
          while ri < right.length
            res.push(right[ri])
            ri += 1
          end
          res
        elsif left.is_a?(String) || right.is_a?(String)
          left.to_s + right.to_s
        else
          left + right
        end
      when 9 then left - right
      when 10
        if left.is_a?(List) && right.is_a?(Integer)
          res = List.new
          ti = 0
          while ti < right
            li = 0
            while li < left.length
              res.push(left[li])
              li += 1
            end
            ti += 1
          end
          res
        elsif left.is_a?(String) && right.is_a?(Integer)
          out_s = ""
          ti = 0
          while ti < right
            out_s = out_s + left
            ti += 1
          end
          out_s
        else
          left * right
        end
      when 11 then left / right
      when 12 then left % right
      when 13 then left ** right
      when 14
        if left.is_a?(StringBuffer)
          left.push(right.to_s)
        elsif left.is_a?(List)
          left.push(right)
          left
        else
          left << right
        end
      when 15 then left >> right
      when 16 then left & right
      when 17 then left | right
      when 18 then left ^ right
      when 22 then false
      else
        runtime_error("unknown operator", node: node)
      end
    end
  RUBY
  body = replace_method(body, "visit_assign", <<~RUBY)
    def visit_assign(node)
      value = evaluate(node.value)
      @returning = false
      @return_value = nil
      tkind = node.target_kind
      if tkind == 1
        env_shape = @env.layout_shape
        if env_shape > 1
          if node.cached_layout_shape == env_shape
            @env.set_slot(node.cached_slot, value)
            return value
          end
          idx = @env.slot_index(node.target_var_name)
          if idx > 0
            node.cached_slot = idx
            node.cached_layout_shape = env_shape
            @env.set_slot(idx, value)
            return value
          end
        end
        @env.set(node.target_var_name, value)
        return value
      elsif tkind == 2
        if @self_stack.length > 0
          self_obj = @self_stack[@self_stack.length - 1]
          if self_obj.is_a?(WObject)
            wcls = self_obj.w_class
            if !wcls.nil?
              if node.cached_w_class.equal?(wcls)
                return self_obj.set_ivar_slot(node.cached_ivar_slot, value)
              end
              slot = wcls.ivar_slot(node.target_var_name)
              node.cached_w_class = wcls
              node.cached_ivar_slot = slot
              return self_obj.set_ivar_slot(slot, value)
            end
          elsif !self_obj.nil?
            self_obj.set_ivar(node.target_var_name, value)
            return value
          end
        end
        return value
      end
      visit_assign_slow(node, value)
    end

    def visit_assign_slow(node, value)
      target = node.name
      if target.is_a?(String)
        @env.set(target, value)
        return value
      end
      tdoc = target.doc
      if tdoc == 28
        self_obj = @self_stack.length > 0 ? @self_stack[@self_stack.length - 1] : nil
        if self_obj.is_a?(WObject) && self_obj.w_class != nil
          self_obj.w_class.set_cvar(target.name.to_s, value)
        elsif self_obj.is_a?(WClass)
          self_obj.set_cvar(target.name.to_s, value)
        elsif @current_class != nil
          @current_class.set_cvar(target.name.to_s, value)
        end
        return value
      elsif tdoc == 29
        @globals[target.name.to_s] = value
        return value
      elsif tdoc == 17
        tlist = target.list
        ti = 0
        while ti < tlist.length
          sub = tlist[ti]
          elem_val = nil
          if value.is_a?(List) || value.is_a?(Array)
            if ti < value.length
              elem_val = value[ti]
            end
          elsif ti == 0
            elem_val = value
          end
          if sub.is_a?(String)
            @env.set(sub, elem_val)
          elsif sub.doc == 9
            @env.set(sub.name.to_s, elem_val)
          elsif sub.doc == 27
            self_obj = @self_stack.length > 0 ? @self_stack[@self_stack.length - 1] : nil
            self_obj.set_ivar(sub.name.to_s, elem_val) if self_obj != nil
          end
          ti += 1
        end
        return value
      elsif tdoc == 9
        @env.set(target.name.to_s, value)
      else
        @env.set(target.to_s, value)
      end
      value
    end
  RUBY
  body = replace_method(body, "visit_instance_var", <<~RUBY)
    def visit_instance_var(node)
      return nil if @self_stack.length == 0
      self_obj = @self_stack[@self_stack.length - 1]
      return nil if self_obj.nil?
      if self_obj.is_a?(WObject)
        wcls = self_obj.w_class
        if !wcls.nil?
          if node.cached_w_class.equal?(wcls)
            return self_obj.get_ivar_slot(node.cached_ivar_slot)
          end
          slot = wcls.ivar_slot(node.name)
          node.cached_w_class = wcls
          node.cached_ivar_slot = slot
          return self_obj.get_ivar_slot(slot)
        end
      end
      self_obj.get_ivar(node.name)
    end
  RUBY
  body = replace_method(body, "visit_var", <<~RUBY)
    def visit_var(node)
      name = stage0_var_name(node)
      value = stage0_env_get(@env, name)
      return value unless value.nil?

      klass = @classes[name]
      return klass unless klass.nil?

      nil
    end
  RUBY
  body = replace_method(body, "visit_if", <<~RUBY)
    def visit_if(node)
      condition = evaluate(node.condition)
      if truthy?(condition)
        return evaluate(node.then_block)
      end
      evaluate(node.else_block)
    end
  RUBY
  body = replace_method(body, "visit_while", <<~RUBY)
    def visit_while(node)
      result = nil
      while truthy?(evaluate(node.condition))
        result = evaluate(node.body)
        break if @returning
        break if @exiting
        if @breaking
          @breaking = false
          break
        end
        if @nexting
          @nexting = false
          next
        end
      end
      result
    end
  RUBY
  body = insert_before_private(body, <<~RUBY)
    def stage0_compiler_keyword?(word = "")
      case word
      when "begin", "break", "case", "else", "elsif", "ensure", "exit", "extern", "false", "fn", "go", "if",
           "in", "lib", "loop", "module", "nil", "next", "on", "parallel", "raise", "rescue", "return",
           "self", "super", "then", "trait", "true", "unless", "until", "use", "when", "while", "with", "yield"
        true
      else
        false
      end
    end

    def stage0_compiler_type_name?(word = "")
      case word
      when "bool", "int", "integer", "string", "string_buffer", "i4", "i8", "i16", "i32", "i64", "i128",
           "u4", "u8", "u16", "u32", "u64", "u128", "w64", "f16", "f32", "f64", "f80", "f128", "f256",
           "d128", "c32", "c64", "c128", "bigint", "bigdecimal", "bf16", "tf32", "fp8", "fp4", "nf4",
           "mxfp8", "mxfp6", "mxfp4", "mxint8", "posit8", "posit16", "posit32", "posit64"
        true
      else
        false
      end
    end

    def stage0_compiler_value_token?(type = "")
      case type
      when "INT", "FLOAT", "DECIMAL", "STRING", "STRING_INTERP", "SYMBOL", "NAME", "ID", "IVAR", "CVAR",
           "RPAREN", "RBRACKET", "RBRACE", "MAGIC_FILE", "MAGIC_LINE", "MAGIC_DIR", "UUID", "CURRENCY",
           "QUANTITY", "DURATION", "WVALUE", "BYTE_ARRAY", "BYTE_ARRAY_INTERP", "DATE", "DATETIME", "TIME",
           "MONTH", "IP4", "CIDR4", "RATIONAL", "CHAR", "CODEPOINT", "KEY", "WORD_ARRAY", "SYMBOL_ARRAY",
           "BASE32", "BASE58", "BASE64", "PARG", "SUPERSCRIPT", "COLOR", "VIEW_VAR"
        true
      else
        false
      end
    end

    def stage0_compiler_trivia_token?(type = "")
      type == "SP" || type == "NEWLINE" || type == "INDENT" || type == "DEDENT"
    end

    def stage0_compiler_operator_type(raw = "", prev_type = "")
      case raw
      when "->"
        "ARROW"
      when "<<"
        stage0_compiler_value_token?(prev_type) ? "LSHIFT" : "PUTS_OP"
      when "+"
        stage0_compiler_value_token?(prev_type) ? "PLUS" : "CLASS_DEF"
      when "<-"
        "PRINT_OP"
      when "<!"
        "RAISE_OP"
      when "=>"
        "FAT_ARROW"
      when "=="
        "EQ"
      when "=~"
        "MATCH"
      when "!="
        "NEQ"
      when "<="
        "LTE"
      when ">>"
        "RSHIFT"
      when ">="
        "GTE"
      when "&."
        "SAFE_NAV"
      when "&&"
        "AND"
      when "||="
        "OR_ASSIGN"
      when "||"
        "OR"
      when "|>"
        "PIPE_FWD"
      when "++"
        "PLUS_PLUS"
      when "+="
        "PLUS_EQ"
      when "--"
        "MINUS_MINUS"
      when "-="
        "MINUS_EQ"
      when "**"
        "POW"
      when "*="
        "STAR_EQ"
      when "/="
        "SLASH_EQ"
      when "%="
        "PERCENT_EQ"
      when "-"
        "MINUS"
      when "*"
        "STAR"
      when "/"
        "SLASH"
      when "%"
        "PERCENT"
      when "<"
        "LT"
      when ">"
        "GT"
      when "="
        "ASSIGN"
      when "!"
        "BANG"
      when "..."
        "DOTDOTDOT"
      when ".."
        "DOTDOT"
      when ".+"
        "DOT_PLUS"
      when ".-"
        "DOT_MINUS"
      when ".*"
        "DOT_STAR"
      when "./"
        "DOT_SLASH"
      when ".|"
        "DOT_PIPE"
      when ".&"
        "DOT_AMP"
      when ".^"
        "DOT_CARET"
      when ".<<"
        "DOT_LSHIFT"
      when ".>>"
        "DOT_RSHIFT"
      when "."
        "DOT"
      when ","
        "COMMA"
      when "&("
        "BLOCK_CALL"
      when "&"
        "AMPERSAND"
      when "|"
        "PIPE"
      when "^"
        "CARET"
      when "("
        "LPAREN"
      when ")"
        "RPAREN"
      when "{"
        "LBRACE"
      when "}"
        "RBRACE"
      when "["
        "LBRACKET"
      when "]"
        "RBRACKET"
      when "?"
        "QUESTION"
      when ":"
        "COLON"
      when ";"
        "SEMICOLON"
      else
        raw
      end
    end

    def stage0_compiler_token_type(tok, prev_type)
      type = tok.type
      value = tok.value.to_s
      case type
      when :NL
        "NEWLINE"
      when :EOF
        "EOF"
      when :ID
        return "KEYWORD" if stage0_compiler_keyword?(value)
        return "TYPE" if stage0_compiler_type_name?(value)
        if value.length > 0
          c = value[0].ord
          return "NAME" if c >= 65 && c <= 90
        end
        "ID"
      when :TRUE
        "TRUE"
      when :FALSE
        "FALSE"
      when :NIL
        "NIL"
      when :SP, :INDENT, :DEDENT, :INT, :FLOAT, :DECIMAL, :STRING, :SYMBOL, :KEYWORD, :TYPE, :NAME,
           :IVAR, :CVAR, :GLOBAL, :PARG, :WVALUE, :CODEPOINT, :BYTE_ARRAY, :SYMBOL_ARRAY, :WORD_ARRAY,
           :REGEX, :REGEX_CAPTURE, :STRING_INTERP, :BYTE_ARRAY_INTERP, :DATE, :DATETIME, :TIME, :MONTH,
           :IP4, :CIDR4, :RATIONAL, :UUID, :CURRENCY, :QUANTITY, :DURATION, :COLOR, :CHAR, :KEY,
           :TYPE_HINT
        type.to_s
      when :"->"
        "ARROW"
      when :"<<"
        stage0_compiler_value_token?(prev_type) ? "LSHIFT" : "PUTS_OP"
      when :"+"
        stage0_compiler_value_token?(prev_type) ? "PLUS" : "CLASS_DEF"
      when :"<-"
        "PRINT_OP"
      when :"<!"
        "RAISE_OP"
      when :"=>"
        "FAT_ARROW"
      when :"=="
        "EQ"
      when :"=~"
        "MATCH"
      when :"!="
        "NEQ"
      when :"<="
        "LTE"
      when :">>"
        "RSHIFT"
      when :">="
        "GTE"
      when :"&."
        "SAFE_NAV"
      when :"&&"
        "AND"
      when :"||="
        "OR_ASSIGN"
      when :"||"
        "OR"
      when :"|>"
        "PIPE_FWD"
      when :"++"
        "PLUS_PLUS"
      when :"+="
        "PLUS_EQ"
      when :"--"
        "MINUS_MINUS"
      when :"-="
        "MINUS_EQ"
      when :"**"
        "POW"
      when :"*="
        "STAR_EQ"
      when :"/="
        "SLASH_EQ"
      when :"%="
        "PERCENT_EQ"
      when :"-"
        "MINUS"
      when :"*"
        "STAR"
      when :"/", :MAP
        "SLASH"
      when :"%"
        "PERCENT"
      when :"<"
        "LT"
      when :">"
        "GT"
      when :"="
        "ASSIGN"
      when :"!"
        "BANG"
      when :"..."
        "DOTDOTDOT"
      when :".."
        "DOTDOT"
      when :".+"
        "DOT_PLUS"
      when :".-"
        "DOT_MINUS"
      when :".*"
        "DOT_STAR"
      when :"./"
        "DOT_SLASH"
      when :".|"
        "DOT_PIPE"
      when :".&"
        "DOT_AMP"
      when :".^"
        "DOT_CARET"
      when :".<<"
        "DOT_LSHIFT"
      when :".>>"
        "DOT_RSHIFT"
      when :"."
        "DOT"
      when :","
        "COMMA"
      when :"&("
        "BLOCK_CALL"
      when :"&"
        "AMPERSAND"
      when :"|"
        "PIPE"
      when :"^"
        "CARET"
      when :"("
        "LPAREN"
      when :")"
        "RPAREN"
      when :"{"
        "LBRACE"
      when :"}"
        "RBRACE"
      when :"["
        "LBRACKET"
      when :"]"
        "RBRACKET"
      when :"?"
        "QUESTION"
      when :":"
        "COLON"
      when :";"
        "SEMICOLON"
      else
        stage0_compiler_operator_type(type.to_s, prev_type)
      end
    end

    def stage0_compiler_token_value(tok, mapped_type)
      value = tok.value
      if value != nil
        return value
      end
      case mapped_type
      when "PLUS"
        "+"
      when "CLASS_DEF"
        "+"
      when "MINUS"
        "-"
      when "STAR"
        "*"
      when "SLASH"
        "/"
      when "PERCENT"
        "%"
      when "LSHIFT"
        "<<"
      when "PUTS_OP"
        "<<"
      when "RSHIFT"
        ">>"
      when "AMPERSAND"
        "&"
      when "PIPE"
        "|"
      when "CARET"
        "^"
      else
        tok.type.to_s
      end
    end

    def stage0_compiler_token_hash(type, value, file, row, col)
      {
        "type" => type, "value" => value, "file" => file, "line" => row, "col" => col,
        :type => type, :value => value, :file => file, :line => row, :col => col
      }
    end

    def stage0_use_path_from_source(source_text, row, col)
      lines = source_text.split("\n")
      idx = row.to_i - 1
      return "" if idx < 0 || idx >= lines.length
      line = lines[idx].to_s
      pos = col.to_i - 1 + 3
      pos = 0 if pos < 0
      while pos < line.length && (line.slice(pos, 1) == " " || line.slice(pos, 1) == "\t")
        pos += 1
      end
      out = line.slice(pos, line.length - pos)
      comment_pos = out.index("#")
      if comment_pos != nil && comment_pos >= 0
        out = out.slice(0, comment_pos)
      end
      while out.length > 0 && (out.slice(out.length - 1, 1) == " " || out.slice(out.length - 1, 1) == "\t")
        out = out.slice(0, out.length - 1)
      end
      if out.length >= 2 && ((out.slice(0, 1) == "\"" && out.slice(out.length - 1, 1) == "\"") || (out.slice(0, 1) == "'" && out.slice(out.length - 1, 1) == "'"))
        out = out.slice(1, out.length - 2)
      end
      out.to_s()
    end

    def stage0_tokenize_source_for_compiler(source, file)
      source_text = source.to_s
      lexer = CodepointLexer.new(source_text)
      tokens = List.new
      prev_type = nil
      trace_enabled = ENV["TUNGSTEN_STAGE0_TOKEN_TRACE"] == "1" && file.to_s.end_with?("compiler/tungsten.w")
      trace = ""
      loop do
        tok = lexer.next_token
        mapped = stage0_compiler_token_type(tok, prev_type)
        value = stage0_compiler_token_value(tok, mapped)
        if mapped == "@"
          name_tok = lexer.next_token
          name_mapped = stage0_compiler_token_type(name_tok, prev_type)
          if name_mapped == "ID" || name_mapped == "NAME"
            tokens.push(stage0_compiler_token_hash("IVAR", "@" + name_tok.value.to_s, file, tok.row, tok.col))
            prev_type = "IVAR"
            next
          end
          tokens.push(stage0_compiler_token_hash(mapped, value, file, tok.row, tok.col))
          tokens.push(stage0_compiler_token_hash(name_mapped, stage0_compiler_token_value(name_tok, name_mapped), file, name_tok.row, name_tok.col))
          prev_type = name_mapped unless stage0_compiler_trivia_token?(name_mapped)
          break if name_mapped == "EOF"
          next
        end
        if mapped == "KEYWORD" && (value == :use || value.to_s == "use")
          use_hash = stage0_compiler_token_hash(mapped, value, file, tok.row, tok.col)
          tokens.push(use_hash)
          path = stage0_use_path_from_source(source_text, tok.row, tok.col)
          path_row = tok.row
          path_col = tok.col + 4
          part_tok = tok
          part_type = "EOF"
          loop do
            part_tok = lexer.next_token
            part_type = stage0_compiler_token_type(part_tok, prev_type)
            break if part_type == "NEWLINE" || part_type == "EOF" || part_type == "SEMICOLON"
          end
          tokens.push(stage0_compiler_token_hash("STRING", path, file, path_row, path_col))
          tokens.push(stage0_compiler_token_hash(part_type, stage0_compiler_token_value(part_tok, part_type), file, part_tok.row, part_tok.col))
          prev_type = "STRING"
          break if part_type == "EOF"
          next
        end
        token_hash = stage0_compiler_token_hash(mapped, value, file, tok.row, tok.col)
        tokens.push(token_hash)
        if trace_enabled && tok.row >= 130 && tok.row <= 145
          trace = trace + mapped.to_s + ":" + value.to_s + ":" + tok.row.to_s + ":" + tok.col.to_s + "\n"
        end
        prev_type = mapped unless stage0_compiler_trivia_token?(mapped)
        break if mapped == "EOF"
      end
      if trace_enabled
        File.write("/tmp/tungsten-stage0-token-trace", trace)
      end
      tokens
    end

    # Maps a stage0 runtime value to its Tungsten type-name string,
    # mirroring runtime/runtime.c's __w_type. The `type(x)` builtin
    # (dispatched in visit_call) is load-bearing: compiler/tungsten.w,
    # loader.w, builtins.w and the lowering passes branch on
    # `type(node) == "Hash"` / `"Array"` / `"String"` etc.
    def stage0_type_name(value)
      return "Nil" if value.nil?
      return "Boolean" if value == true || value == false
      return "Int" if value.is_a?(Integer)
      return "Float" if value.is_a?(Float)
      return "String" if value.is_a?(String)
      return "StringBuffer" if value.is_a?(StringBuffer)
      return "Symbol" if value.is_a?(Symbol)
      return "Array" if value.is_a?(Array) || value.is_a?(List) || value.is_a?(WireSequence)
      return "Hash" if value.is_a?(Hash)
      return "WValue" if value.is_a?(PackedNode) || value.is_a?(WireRecord)
      return "ContentTempMap" if value.is_a?(ContentTempMap)
      if value.is_a?(WObject)
        klass = value.w_class
        return klass.name.to_s unless klass.nil?
        return "Object"
      end
      return "Class" if value.is_a?(WClass)
      "Unknown"
    end

    def stage0_wyhash_mix_u64(a, b)
      a0 = a & 0xFFFF
      a1 = (a >> 16) & 0xFFFF
      a2 = (a >> 32) & 0xFFFF
      a3 = (a >> 48) & 0xFFFF
      b0 = b & 0xFFFF
      b1 = (b >> 16) & 0xFFFF
      b2 = (b >> 32) & 0xFFFF
      b3 = (b >> 48) & 0xFFFF

      c0 = a0 * b0
      r0 = c0 & 0xFFFF
      c1 = (c0 >> 16) + a0 * b1 + a1 * b0
      r1 = c1 & 0xFFFF
      c2 = (c1 >> 16) + a0 * b2 + a1 * b1 + a2 * b0
      r2 = c2 & 0xFFFF
      c3 = (c2 >> 16) + a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0
      r3 = c3 & 0xFFFF
      c4 = (c3 >> 16) + a1 * b3 + a2 * b2 + a3 * b1
      r4 = c4 & 0xFFFF
      c5 = (c4 >> 16) + a2 * b3 + a3 * b2
      r5 = c5 & 0xFFFF
      c6 = (c5 >> 16) + a3 * b3
      r6 = c6 & 0xFFFF
      r7 = (c6 >> 16) & 0xFFFF

      lo0 = r0 ^ r4
      lo1 = r1 ^ r5
      lo2 = r2 ^ r6
      lo3 = r3 ^ r7
      out = lo0 | (lo1 << 16) | (lo2 << 32)
      if lo3 >= 0x8000
        out = (out | ((lo3 - 0x8000) << 48)) + (-9223372036854775807 - 1)
      else
        out = out | (lo3 << 48)
      end
      out
    end

    def stage0_wyhash_read_u32(text, offset)
      (text.getbyte(offset) || 0) |
        ((text.getbyte(offset + 1) || 0) << 8) |
        ((text.getbyte(offset + 2) || 0) << 16) |
        ((text.getbyte(offset + 3) || 0) << 24)
    end

    def stage0_wyhash_read_u64(text, offset)
      lo = stage0_wyhash_read_u32(text, offset)
      hi = stage0_wyhash_read_u32(text, offset + 4)
      if hi >= 0x80000000
        (lo | ((hi - 0x80000000) << 32)) + (-9223372036854775807 - 1)
      else
        lo | (hi << 32)
      end
    end

    def stage0_wyhash64_string(text)
      len = text.bytesize
      s0 = -6884282663029611473
      s1 = -1800455987208640293
      s2 = -8161530843051276573
      s3 = 6384245875588680899
      seed = 1311768467294899695
      a = 0
      b = 0
      if len <= 16
        if len >= 4
          head_offset = (len >> 3) << 2
          tail_offset = len - 4
          tail_head_offset = len - 4 - head_offset
          ah = stage0_wyhash_read_u32(text, 0)
          al = stage0_wyhash_read_u32(text, head_offset)
          if ah >= 0x80000000
            a = (al | ((ah - 0x80000000) << 32)) + (-9223372036854775807 - 1)
          else
            a = al | (ah << 32)
          end
          bh = stage0_wyhash_read_u32(text, tail_offset)
          bl = stage0_wyhash_read_u32(text, tail_head_offset)
          if bh >= 0x80000000
            b = (bl | ((bh - 0x80000000) << 32)) + (-9223372036854775807 - 1)
          else
            b = bl | (bh << 32)
          end
        elsif len > 0
          first = text.getbyte(0) || 0
          middle = text.getbyte(len >> 1) || 0
          last = text.getbyte(len - 1) || 0
          a = (first << 16) | (middle << 8) | last
        end
      else
        i = len
        offset = 0
        if i > 48
          s0v = seed
          s1v = seed
          s2v = seed
          while i > 48
            d0 = stage0_wyhash_read_u64(text, offset)
            d1 = stage0_wyhash_read_u64(text, offset + 8)
            d2 = stage0_wyhash_read_u64(text, offset + 16)
            d3 = stage0_wyhash_read_u64(text, offset + 24)
            d4 = stage0_wyhash_read_u64(text, offset + 32)
            d5 = stage0_wyhash_read_u64(text, offset + 40)
            s0v = stage0_wyhash_mix_u64(d0 ^ s1, d1 ^ s0v)
            s1v = stage0_wyhash_mix_u64(d2 ^ s2, d3 ^ s1v)
            s2v = stage0_wyhash_mix_u64(d4 ^ s3, d5 ^ s2v)
            offset += 48
            i -= 48
          end
          seed = s0v ^ s1v ^ s2v
        end
        while i > 16
          d0 = stage0_wyhash_read_u64(text, offset)
          d1 = stage0_wyhash_read_u64(text, offset + 8)
          seed = stage0_wyhash_mix_u64(d0 ^ s1, d1 ^ seed)
          offset += 16
          i -= 16
        end
        a = stage0_wyhash_read_u64(text, offset + i - 16)
        b = stage0_wyhash_read_u64(text, offset + i - 8)
      end
      stage0_wyhash_mix_u64(s1 ^ len, stage0_wyhash_mix_u64(a ^ s1, b ^ seed))
    end

    def stage0_u64_hex(u)
      hex_chars = "0123456789abcdef"
      out = ""
      shift = 60
      while shift >= 0
        idx = (u >> shift) & 15
        out = out + (hex_chars.byteslice(idx, 1) || "")
        shift -= 4
      end
      out
    end

    def stage0_shell_join(arr)
      cmd_s = ""
      if arr.is_a?(List) || arr.is_a?(Array)
        ai = 0
        while ai < arr.length
          arg_s = arr[ai].to_s
          cmd_s = cmd_s + " " if ai > 0
          cmd_s = cmd_s + "'" + arg_s.gsub("'", "'\\\\''") + "'"
          ai += 1
        end
      end
      cmd_s
    end
  RUBY
  body = replace_method(body, "visit_call", <<~RUBY)
    def visit_call(node)
      name_sym = node.cached_name_sym
      if name_sym == :__spinel_uncached_name__
        name_sym = stage0_str_to_sym(node.name)
        node.cached_name_sym = name_sym
      end
      obj = node.obj
      if !obj.nil?
        if name_sym == :new && obj.is_a?(Var)
          if node.cached_dispatch_version == @method_cache_epoch && !node.cached_dispatch_owner.nil?
            return instantiate_from_nodes(node.cached_dispatch_owner, node.args)
          end
          return visit_call_new_var(node, obj)
        end
        recv = evaluate(obj)
        if recv.is_a?(WObject)
          w_class = recv.w_class
          if !w_class.nil?
            method = nil
            if node.cached_dispatch_owner.equal?(w_class) && node.cached_dispatch_version == @method_cache_epoch
              method = node.cached_w_method
            else
              method = w_class.lookup_method(node.name)
              node.cached_dispatch_owner = w_class
              node.cached_dispatch_version = @method_cache_epoch
              node.cached_w_method = method
            end
            return call_w_method_from_nodes(recv, method, node.args, node.block) if !method.nil?
          end
        end
        return visit_call_receiver_slow(node, recv, name_sym)
      end

      bkind = node.call_builtin_kind
      if bkind == 0
        bkind = stage0_classify_bare_call(name_sym)
        node.call_builtin_kind = bkind
      end
      if bkind == 1
        return visit_call_pre_builtin(node, name_sym)
      end

      if @self_stack.length > 0
        self_obj = @self_stack[@self_stack.length - 1]
        if self_obj.is_a?(WObject)
          w_class = self_obj.w_class
          if !w_class.nil?
            method = nil
            if node.cached_dispatch_owner.equal?(w_class) && node.cached_dispatch_version == @method_cache_epoch
              method = node.cached_w_method
            else
              method = w_class.lookup_method(node.name)
              node.cached_dispatch_owner = w_class
              node.cached_dispatch_version = @method_cache_epoch
              node.cached_w_method = method
            end
            return call_w_method_from_nodes(self_obj, method, node.args, node.block) if !method.nil?
          end
        elsif !self_obj.nil?
          if self_obj.is_a?(WClass)
            method = self_obj.lookup_class_method(node.name)
            method = self_obj.lookup_method(node.name) if method.nil?
            return call_w_method_from_nodes(self_obj, method, node.args, node.block) if !method.nil?
          elsif self_obj.is_a?(PackedNode)
            w_class = @classes["Tungsten:AST:Node"] || @classes["Node"]
            if !w_class.nil?
              method = w_class.lookup_method(node.name)
              return call_w_method_from_nodes(self_obj, method, node.args, node.block) if !method.nil?
            end
          end
        end
      end

      if bkind == 2
        return visit_call_post_builtin(node, name_sym)
      end

      top_fn = node.cached_top_fn
      if !top_fn.nil?
        return stage0_call_def_from_nodes(top_fn, node.name, node.args, node.block)
      end

      visit_call_bare_slow(node)
    end

    def visit_call_new_var(node, obj)
      class_name = obj.name
      if class_name == "StringBuffer"
        return StringBuffer.new
      end
      w_class = @classes[class_name]
      if w_class.nil? && class_name == "Lexer"
        w_class = @classes["CodepointLexer"]
      end
      if !w_class.nil?
        node.cached_dispatch_owner = w_class
        node.cached_dispatch_version = @method_cache_epoch
        return instantiate_from_nodes(w_class, node.args)
      end
      recv = evaluate(obj)
      visit_call_receiver_slow(node, recv, :new)
    end

    def visit_call_receiver_slow(node, recv, name_sym)
      args = node.args
      name_s = node.name
      if name_sym == :new && recv.is_a?(WClass)
        return instantiate_from_nodes(recv, args)
      end
      if recv.is_a?(WClass)
        method = recv.lookup_class_method(name_s)
        method = recv.lookup_method(name_s) if method.nil?
        return call_w_method_from_nodes(recv, method, args, node.block) if !method.nil?
        if recv.has_constant?(name_s)
          return recv.get_constant(name_s)
        end
      elsif recv.is_a?(PackedNode)
        w_class = @classes["Tungsten:AST:Node"] || @classes["Node"]
        if !w_class.nil?
          method = w_class.lookup_method(name_s)
          return call_w_method_from_nodes(recv, method, args, node.block) if method
          if args.length == 0
            mm = w_class.lookup_method("method_missing")
            if mm
              mm_args = evaluate_args(nil)
              mm_args.push(name_sym)
              return call_w_method(recv, mm, mm_args, node.block)
            end
          elsif args.length == 1 && name_s.end_with?("=")
            mms = w_class.lookup_method("method_missing_set")
            if mms
              base_sym = name_s.slice(0, name_s.length - 1).to_sym
              mms_args = evaluate_args(nil)
              mms_args.push(base_sym)
              mms_args.push(evaluate(args[0]))
              return call_w_method(recv, mms, mms_args, node.block)
            end
          end
        end
      elsif recv.is_a?(Integer) && (recv & -70368744177664) == -1125899906842624
        return (recv >> 38) & 0xFF if name_sym == :type
        return (recv >> 2) & 0xFFFFFF if name_sym == :offset
        return (recv >> 26) & 0xFFF if name_sym == :length
        return (recv & 1) != 0 if name_sym == :line_start?
        if name_sym == :value
          src = evaluate(args[0]).to_s
          return src.slice((recv >> 2) & 0xFFFFFF, (recv >> 26) & 0xFFF) || ""
        end
        if name_sym == :equal?
          src = evaluate(args[0]).to_s
          lit = evaluate(args[1]).to_s
          tlen = (recv >> 26) & 0xFFF
          return false if tlen != lit.length
          return (src.slice((recv >> 2) & 0xFFFFFF, tlen) || "") == lit
        end
        w_class = @classes["Token"]
        if !w_class.nil?
          method = w_class.lookup_method(name_s)
          return call_w_method_from_nodes(recv, method, args, node.block) if method
        end
      end
      if node.block.nil?
        if name_sym == :"[]" && args.length == 1
          return stage0_aref(recv, evaluate(args[0]))
        end
        if name_sym == :length || name_sym == :size
          return stage0_value_length(recv)
        end
        if name_sym == :empty?
          return stage0_value_length(recv) == 0
        end
      end
      stage0_primitive_call(recv, name_sym, args, node.block)
    end

    def stage0_classify_bare_call(name_sym)
      case name_sym
      when :ccall, :ccall_nobox, :ccall_rawargs, :slab_alloc_init, :StringBuffer,
           :wyhash64_string, :digest_string64, :wyhash64_hex_string, :digest_sha256,
           :wyhash_mix_u64, :u64_hex, :digest_file64, :wymix, :wvalue_bits, :wvalue_from_bits
        1
      when :ro, :rw, :argv, :"<<", :puts, :log, :print, :flush, :alias_method,
           :runtime_identity, :block?, :block_given?, :cache_read, :cache_write,
           :exit, :clock, :clock_ms, :write_file, :write_file_bytes, :read_file, :read_file_bytes,
           :file?, :file_exists?, :file_file?, :file_directory?, :file_symlink?,
           :file_size, :file_mtime_ns, :file_stat_data, :file_unlink, :file_unlink_strict, :file_rm,
           :file_mkdir, :file_rename, :file_mv, :file_pwd, :__project_root,
           :file_realpath, :file_expand_path, :file_dirname, :file_basename, :file_extname, :file_join,
           :env, :system, :system_argv, :capture, :capture_argv, :popen, :popen_argv, :type
        2
      else
        -1
      end
    end

    def visit_call_pre_builtin(node, name_sym)
      args = node.args
      case name_sym
      when :ccall, :ccall_nobox, :ccall_rawargs
        stage0_dispatch_ccall(args)
      when :slab_alloc_init
        stage0_slab_alloc_init(args)
      when :StringBuffer
        StringBuffer.new
      when :wyhash64_string, :digest_string64
        stage0_wyhash64_string(evaluate(args[0]).to_s)
      when :wyhash64_hex_string, :digest_sha256
        stage0_u64_hex(stage0_wyhash64_string(evaluate(args[0]).to_s))
      when :wyhash_mix_u64
        stage0_wyhash_mix_u64(evaluate(args[0]).to_i, evaluate(args[1]).to_i)
      when :u64_hex
        stage0_u64_hex(evaluate(args[0]).to_i)
      when :digest_file64
        p = evaluate(args[0]).to_s
        return nil unless File.exist?(p)
        stage0_wyhash64_string(File.read(p))
      when :wymix
        res = stage0_wyhash_mix_u64(evaluate(args[0]).to_i, evaluate(args[1]).to_i)
        masked = res & 0x0000FFFFFFFFFFFF
        masked >= 0x800000000000 ? masked - 0x1000000000000 : masked
      when :wvalue_bits, :wvalue_from_bits
        args.length > 0 ? evaluate(args[0]) : nil
      else
        nil
      end
    end

    def visit_call_post_builtin(node, name_sym)
      args = node.args
      case name_sym
      when :ro, :rw
        if @current_class != nil
          stage0_define_accessors(@current_class, args, name_sym == :rw)
        end
        nil
      when :argv
        argv_list = List.new
        i = 1
        while i < ARGV.length
          argv_list.push(ARGV[i])
          i += 1
        end
        argv_list
      when :"<<"
        result = nil
        i = 0
        while i < args.length
          result = evaluate(args[i])
          puts w_to_s(result)
          i += 1
        end
        result
      when :puts, :log
        i = 0
        while i < args.length
          v = evaluate(args[i])
          puts(v.nil? ? "nil" : w_to_s(v))
          i += 1
        end
        nil
      when :print
        i = 0
        while i < args.length
          v = evaluate(args[i])
          print(v.nil? ? "nil" : w_to_s(v))
          i += 1
        end
        nil
      when :flush, :alias_method
        nil
      when :runtime_identity
        "ruby spinel"
      when :block?, :block_given?
        @current_block != nil
      when :cache_read
        nil
      when :cache_write
        false
      when :exit
        code = args.length > 0 ? evaluate(args[0]).to_i : 0
        exit(code)
      when :clock, :clock_ms
        0
      when :write_file, :write_file_bytes
        path = evaluate(args[0])
        data = evaluate(args[1])
        File.write(path.to_s, data.to_s)
        true
      when :read_file, :read_file_bytes
        path = evaluate(args[0])
        File.read(path.to_s)
      when :file?, :file_exists?, :file_file?
        path = evaluate(args[0])
        File.exist?(path.to_s)
      when :file_directory?
        Dir.exist?(evaluate(args[0]).to_s)
      when :file_symlink?
        false
      when :file_size
        path = evaluate(args[0]).to_s
        File.exist?(path) ? File.read(path).bytesize : nil
      when :file_mtime_ns
        path = evaluate(args[0]).to_s
        File.exist?(path) ? 1 : nil
      when :file_stat_data
        path = evaluate(args[0]).to_s
        return nil unless File.exist?(path)
        sz = File.read(path).bytesize
        List.new([0, 0, 0o100644, 1, 0, 0, 0, sz, 4096, 1, 1, 1, 1, 1, "file"])
      when :file_unlink, :file_unlink_strict, :file_rm
        path = evaluate(args[0]).to_s
        File.delete(path) if File.exist?(path)
        true
      when :file_mkdir
        path = evaluate(args[0]).to_s
        system("mkdir -p '" + path.gsub("'", "'\\''") + "'")
        true
      when :file_rename, :file_mv
        src = evaluate(args[0]).to_s
        dst = evaluate(args[1]).to_s
        system("mv -f '" + src.gsub("'", "'\\''") + "' '" + dst.gsub("'", "'\\''") + "'")
      when :file_pwd, :__project_root
        Dir.pwd
      when :file_realpath, :file_expand_path
        p = evaluate(args[0]).to_s
        if args.length > 1
          base = evaluate(args[1])
          if base != nil && !p.start_with?("/")
            p = base.to_s + "/" + p
          end
        elsif !p.start_with?("/")
          p = Dir.pwd + "/" + p
        end
        p
      when :file_dirname
        p = evaluate(args[0]).to_s
        idx = p.rindex("/")
        return "." if idx == nil
        return "/" if idx == 0
        p.byteslice(0, idx) || "."
      when :file_basename
        p = evaluate(args[0]).to_s
        idx = p.rindex("/")
        return p if idx == nil
        p.byteslice(idx + 1, p.bytesize - idx - 1) || ""
      when :file_extname
        b = evaluate(args[0]).to_s
        slash = b.rindex("/")
        if slash != nil
          b = b.byteslice(slash + 1, b.bytesize - slash - 1) || ""
        end
        dot = b.rindex(".")
        return "" if dot == nil || dot == 0
        b.byteslice(dot, b.bytesize - dot) || ""
      when :file_join
        out = ""
        i = 0
        while i < args.length
          seg = evaluate(args[i]).to_s
          if i == 0
            out = seg
          elsif out.end_with?("/")
            out = out + (seg.start_with?("/") ? (seg.byteslice(1, seg.bytesize - 1) || "") : seg)
          else
            out = out + (seg.start_with?("/") ? seg : "/" + seg)
          end
          i += 1
        end
        out
      when :env
        ENV[evaluate(args[0]).to_s]
      when :system
        system(evaluate(args[0]).to_s)
      when :system_argv
        system(stage0_shell_join(evaluate(args[0])))
      when :capture
        command = evaluate(args[0])
        `\#{command.to_s}`
      when :capture_argv
        arr = evaluate(args[0])
        `\#{stage0_shell_join(arr)}`
      when :popen
        command = evaluate(args[0]).to_s
        out = `\#{command}`
        List.new([out, $?.exitstatus == 0])
      when :popen_argv
        arr = evaluate(args[0])
        out = `\#{stage0_shell_join(arr)}`
        List.new([out, $?.exitstatus == 0])
      when :type
        stage0_type_name(evaluate(args[0]))
      else
        nil
      end
    end

    def visit_call_bare_slow(node)
      name = node.name
      args = node.args
      w_class = @classes[name]
      if !w_class.nil?
        return instantiate_from_nodes(w_class, args)
      end

      fn = stage0_str_poly_hash_get(@env.values_table, name)
      if fn.nil?
        if !@env.equal?(@top_env)
          fn = stage0_str_poly_hash_get(@top_env.values_table, name)
          if fn.is_a?(Def) && fn.doc == 12
            node.cached_top_fn = fn
            return stage0_call_def_from_nodes(fn, name, args, node.block)
          end
        end
      elsif @env.equal?(@top_env) && fn.is_a?(Def) && fn.doc == 12
        node.cached_top_fn = fn
        return stage0_call_def_from_nodes(fn, name, args, node.block)
      end

      if fn.nil?
        fn = stage0_env_get(@env, name)
      end
      if fn.nil?
        runtime_error("stage0 unknown function: " + name, node: node)
      end
      if fn.respond_to?(:doc)
        if fn.doc == 12 && fn.is_a?(Def)
          return stage0_call_def_from_nodes(fn, name, args, node.block)
        end
        if fn.doc == 37 || fn.doc == 38 || fn.doc == 54
          eval_args = evaluate_args(args)
          return stage0_invoke_block(fn, eval_args)
        end
      end
      nil
    end
  RUBY
  body = replace_method(body, "visit_return", <<~RUBY)
    def visit_return(node)
      @return_value = evaluate(node.value)
      @returning = true
      if @in_block_depth > 0
        @return_target_depth = @current_block_owner_depth
      else
        @return_target_depth = @call_depth
      end
      @return_value
    end
  RUBY
  body = replace_method(body, "truthy?", <<~RUBY)
    def truthy?(value)
      return false if value == false
      return false if value.nil?
      true
    end
  RUBY
  %w[
    call_method call_function_intrinsic_from_nodes cached_simple_method_plan build_simple_method_plan
    simple_method_expression execute_simple_method_plan_from_nodes simple_call_arg_value
    simple_method_value simple_method_value3 simple_method_numeric_expression?
    cached_simple_block_plan build_simple_block_plan simple_block_statement simple_block_expression
    execute_simple_block_plan_from_nodes execute_simple_block_plan simple_block_value simple_block_env_ready?
    simple_block_env_bound? simple_block_env_value simple_block_env_assign simple_block_env_assign_op
    invoke_block invoke_block_from_nodes execute_bound_block collect_free_vars walk_free_vars
    new_free_var_env cached_param_slot_names cached_free_var_slot_names
    collect_local_slot_names collect_assign_target_slot_names add_local_slot_name
    cached_symbol_value
    execute_callable_body
    call_w_method call_w_method_from_nodes execute_bound_w_method cached_simple_w_method_plan
    build_simple_w_method_plan simple_w_method_statement simple_w_method_expression
    execute_simple_w_method_plan simple_w_method_plan_ready? execute_simple_w_method_plan_on_ivars
    simple_w_method_value evaluate_args bind_exact_small_args_from_nodes bind_params new_param_env
    one_call_arg_node direct_arg_value call_primitive_method_from_nodes call_builtin_from_nodes
    call_ruby_method_from_nodes call_self_hosted_parser_intrinsic_from_nodes
    sync_self_hosted_parser_current_token skip_self_hosted_parser_tokens hash_indifferent_get
    instantiate evaluate_begin_rescue resolve_use_path try_autoload_core find_project_root
    cached_literal_case_lookup build_literal_case_lookup literal_case_value
    static_condition_truth static_condition_literal_value static_condition_compare
    expand_on_guards instantiate_from_nodes invoke_method_builtin call_lambda_with_values with_profile_callable
    cached_simple_while_plan build_simple_while_plan simple_while_step simple_while_condition_expression
    simple_while_receiver_expression simple_while_expression execute_simple_while_plan
    execute_mixed_simple_while_plan bind_simple_while_plan bind_simple_while_condition_expression
    bind_simple_while_receiver_expression bind_simple_while_expression execute_mixed_simple_while_steps
    simple_while_condition_value simple_while_value simple_while_arithmetic simple_while_compare
    wyhash_mix_u64_value wyhash_read_u32_value wyhash_read_u64_value wyhash64_string_value
    primitive_runtime_class tungsten_class_name tungsten_type_info call_builtin
    catch_break_if_needed catch_next_if_needed iterate_with
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(a = nil, b = nil, c = nil, d = nil)
      nil
    end
    RUBY
  end
  body = replace_method(body, "cached_symbol_value", <<~RUBY)
    def cached_symbol_value(node)
      node.value
    end
  RUBY
  %w[
    convert_quantity_pipe decompose_quantity ast_to_unit_string apply_type_hint
    parse_energy_fuel substance_mass assign_target wrap_unsigned_bits wrap_signed_bits
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(a = nil, b = nil, c = nil, d = nil)
      nil
    end
    RUBY
  end
  body = replace_method(body, "runtime_error", <<~RUBY)
    def runtime_error(msg, node: nil, length: nil)
      raise msg
    end
  RUBY
  body = replace_method(body, "build_runtime_error", <<~RUBY)
    def build_runtime_error(msg, node: nil, length: nil)
      msg
    end
  RUBY
  body = replace_method(body, "runtime_error_from_exception", <<~RUBY)
    def runtime_error_from_exception(error, node: nil)
      "runtime error"
    end
  RUBY
  body = replace_method(body, "resolve_cached_local", <<~RUBY)
    def resolve_cached_local(node, name)
      @env.get(name)
    end
  RUBY
  body = replace_method(body, "cached_w_method", <<~RUBY)
    def cached_w_method(node, owner)
      nil
    end
  RUBY
  body = replace_method(body, "cache_w_method", <<~RUBY)
    def cache_w_method(node, owner, method)
      method
    end
  RUBY
  body = replace_method(body, "parse_with_file", <<~RUBY)
    def parse_with_file(source, file)
      parser = Parser.new(source)
      parser.parse
    end
  RUBY
  body = replace_method(body, "w_to_s", <<~RUBY)
    def w_to_s(value)
      return "nil" if value == nil
      return "true" if value == true
      return "false" if value == false
      return value.to_s if value.is_a?(StringBuffer)
      if value.is_a?(List) || value.is_a?(Array)
        out = "["
        i = 0
        while i < value.length
          out = out + ", " if i > 0
          elem = value[i]
          if elem.is_a?(String)
            out = out + "\"" + elem + "\""
          else
            out = out + w_to_s(elem)
          end
          i += 1
        end
        return out + "]"
      end
      if value.is_a?(WObject) && value.w_class != nil
        to_s_method = value.w_class.lookup_method("to_s")
        if to_s_method != nil
          return call_w_method_from_nodes(value, to_s_method, nil).to_s
        end
      end
      value.to_s
    end
  RUBY
  body = replace_method(body, "with_gc_paused_for_parse", <<~RUBY)
    def with_gc_paused_for_parse
      yield
    end
  RUBY
  body = replace_method(body, "inspect_wvalue_literal", <<~RUBY)
    def inspect_wvalue_literal(raw)
      raw.to_s
    end
  RUBY
  body = replace_method(body, "inspect_runtime_value", <<~RUBY)
    def inspect_runtime_value(value)
      value.to_s
    end
  RUBY
  body = replace_method(body, "decode_w_value", <<~RUBY)
    def decode_w_value(bits, raw = nil)
      nil
    end
  RUBY
  body = replace_method(body, "w_value_double?", <<~RUBY)
    def w_value_double?(bits)
      false
    end
  RUBY
  body = replace_method(body, "decode_w_value_double", <<~RUBY)
    def decode_w_value_double(bits)
      0
    end
  RUBY
  body = replace_method(body, "decode_w_value_stringy", <<~RUBY)
    def decode_w_value_stringy(bits, raw)
      nil
    end
  RUBY
  body = replace_method(body, "decode_w_value_char", <<~RUBY)
    def decode_w_value_char(bits, raw)
      nil
    end
  RUBY
  body = replace_method(body, "sign_extend", <<~RUBY)
    def sign_extend(value, width)
      value
    end
  RUBY
  body = replace_method(body, "coerce_value_to_wvalue", <<~RUBY)
    def coerce_value_to_wvalue(value)
      {}
    end
  RUBY
  body = replace_method(body, "coerce_integer_to_wvalue", <<~RUBY)
    def coerce_integer_to_wvalue(value)
      {}
    end
  RUBY
  body = replace_method(body, "coerce_stringy_to_wvalue", <<~RUBY)
    def coerce_stringy_to_wvalue(text, is_symbol)
      {}
    end
  RUBY
  %w[
    coerce_decimal_to_wvalue coerce_rational_to_wvalue coerce_color_to_wvalue
    coerce_date_to_wvalue coerce_date_time_to_wvalue coerce_packed_date_fields
    coerce_ip4_to_wvalue coerce_cidr4_to_wvalue coerce_packed_ip4
    coerce_currency_to_wvalue coerce_percentage_to_wvalue coerce_quantity_to_wvalue
    coerce_boxed_quantity_wvalue coerce_duration_to_wvalue
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(a = nil, b = nil, c = nil, d = nil, e = nil, f = nil, g = nil)
      {}
    end
    RUBY
  end
  body = replace_method(body, "decimal_sig_scale", "    def decimal_sig_scale(value)\n      [0, 0]\n    end\n")
  body = replace_method(body, "normalize_sig_scale", "    def normalize_sig_scale(sig, scale)\n      [0, 0]\n    end\n")
  body = replace_method(body, "signed_payload", "    def signed_payload(value, width)\n      0\n    end\n")
  body = replace_method(body, "fits_signed_width?", "    def fits_signed_width?(value, width)\n      true\n    end\n")
  body = replace_method(body, "wvalue_quantity_unit_symbol", "    def wvalue_quantity_unit_symbol(unit)\n      \"\"\n    end\n")
  body = replace_method(body, "box_float_wvalue", <<~RUBY)
    def box_float_wvalue(value)
      0
    end
  RUBY
  body = replace_method(body, "exact_wvalue", <<~RUBY)
    def exact_wvalue(bits, note)
      {}
    end
  RUBY
  body = replace_method(body, "unsupported_wvalue", <<~RUBY)
    def unsupported_wvalue(note)
      {}
    end
  RUBY
  body = replace_method(body, "format_wvalue_breakdown", <<~RUBY)
    def format_wvalue_breakdown(bits, raw: nil, note: nil)
      raw.to_s
    end
  RUBY
  %w[
    wvalue_breakdown_lines singleton_breakdown object_breakdown double_breakdown stringy_breakdown int_breakdown
    instant_breakdown char_breakdown numeric_breakdown packed_breakdown duration_breakdown
    quantity_inspection_lines color_inspection_lines date_inspection_lines date_time_inspection_lines
    ip4_inspection_lines cidr4_inspection_lines uuid_inspection_lines range_inspection_lines
    array_inspection_lines hash_inspection_lines
    block_lines holiday_art halloween_pumpkin_art christmas_tree_art st_patricks_art easter_art
    fourth_of_july_art valentine_heart_art thanksgiving_art month_calendar_lines
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(value = nil, other = nil)
      []
    end
    RUBY
  end
  %w[
    quantity_unit_label quantity_dimension_label dimension_name_label dimension_signature expanded_quantity_label
    quantity_alias_labels quantity_conversion_labels canonical_unit_symbol exponent_label color_bar season_label
    moon_phase_label holiday_label floating_holiday_label ansi_color calendar_week_line i_to_ip4 ip4_class_label
    cidr_host_range_label cidr_diagram uuid_variant_label
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(a = nil, b = nil, c = nil, d = nil)
      ""
    end
    RUBY
  end
  %w[
    dimension_base_components ip4_octets
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(value = nil)
      {}
    end
    RUBY
  end
  %w[
    nth_weekday? last_weekday?
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(a = nil, b = nil, c = nil, d = nil)
      false
    end
    RUBY
  end
  body = replace_method(body, "dimensionless_unit", "    def dimensionless_unit\n      nil\n    end\n")
  body = replace_method(body, "rgb_to_hsl", "    def rgb_to_hsl(r, g, b)\n      [0, 0, 0]\n    end\n")
  body = replace_method(body, "color_luma", "    def color_luma(color)\n      0\n    end\n")
  body = replace_method(body, "color_palette_line", "    def color_palette_line(label, a = nil, b = nil)\n      \"\"\n    end\n")
  body = replace_method(body, "color_palette_color", "    def color_palette_color(hue, saturation, lightness)\n      nil\n    end\n")
  body = replace_method(body, "hsl_to_rgb", "    def hsl_to_rgb(hue, saturation, lightness)\n      [0, 0, 0]\n    end\n")
  body = replace_method(body, "hue_channel_to_rgb", "    def hue_channel_to_rgb(p, q, t)\n      0\n    end\n")
  body = replace_method(body, "ip4_to_i", "    def ip4_to_i(octets)\n      0\n    end\n")
  body = replace_method(body, "stringy_mode_label", "    def stringy_mode_label(mode)\n      \"\"\n    end\n")
  body = replace_method(body, "byte_label", "    def byte_label(byte)\n      \"\"\n    end\n")
  body = replace_method(body, "safe_codepoint_label", "    def safe_codepoint_label(codepoint)\n      \"\"\n    end\n")
  body = replace_method(body, "category_label", "    def category_label(index)\n      \"\"\n    end\n")
  body = replace_method(body, "ipv4_label", "    def ipv4_label(addr)\n      \"\"\n    end\n")
  body = replace_method(body, "inspection_header_line", "    def inspection_header_line(label, value)\n      \"\"\n    end\n")
  body = replace_method(body, "inspection_field_line", "    def inspection_field_line(label, bit_range, raw, meaning)\n      \"\"\n    end\n")
  body = replace_method(body, "inspection_value_label", "    def inspection_value_label(value)\n      value.to_s\n    end\n")
  body = replace_method(body, "inspection_type_label", "    def inspection_type_label(value)\n      \"Object\"\n    end\n")
  body = replace_method(body, "wvalue_object_space?", "    def wvalue_object_space?(bits)\n      false\n    end\n")
  body = replace_method(body, "scene_columns", "    def scene_columns(left, right)\n      \"\"\n    end\n")
  body = replace_method(body, "scene_line", "    def scene_line(text)\n      \"\"\n    end\n")
  body = replace_method(body, "blank_scene_line", "    def blank_scene_line\n      \"\"\n    end\n")
  body = replace_method(body, "place_scene_text", "    def place_scene_text(line, column, text)\n      nil\n    end\n")
  body = replace_method(body, "visible_length", "    def visible_length(text)\n      0\n    end\n")
  body = replace_method(body, "array_sparkline", "    def array_sparkline(array)\n      \"\"\n    end\n")
  body = replace_method(body, "compact_cell", "    def compact_cell(value)\n      \"\"\n    end\n")
  body = replace_method(body, "fit_cell", "    def fit_cell(text, width)\n      \"\"\n    end\n")
  body = replace_method(body, "truncate_visible", "    def truncate_visible(text, width)\n      \"\"\n    end\n")
  body = replace_method(body, "easter_date", "    def easter_date(year)\n      nil\n    end\n")
  body = replace_method(body, "completion_names", "    def completion_names\n      []\n    end\n")
  body = replace_method(body, "environment_names", "    def environment_names(env)\n      []\n    end\n")
  body = replace_method(body, "method_reference", "    def method_reference(ref)\n      nil\n    end\n")
  body = replace_method(body, "method_signature", "    def method_signature(method_name, method = nil)\n      \"\"\n    end\n")
  body = replace_method(body, "method_arg_label", "    def method_arg_label(arg)\n      \"\"\n    end\n")
  body = replace_method(body, "method_source_location", "    def method_source_location(method, builtin)\n      \"unknown\"\n    end\n")
  body = replace_method(body, "project_relative_path", "    def project_relative_path(path)\n      path.to_s\n    end\n")
  body = replace_method(body, "project_root_for", "    def project_root_for(path)\n      \".\"\n    end\n")
  body = replace_method(body, "method_source_excerpt", "    def method_source_excerpt(method, builtin)\n      []\n    end\n")
  body = replace_method(body, "method_doc_for", "    def method_doc_for(class_name, method_name)\n      \"\"\n    end\n")
  %w[
    visit_regex_literal visit_symbol visit_string_interpolation visit_char visit_magic_constant
    visit_tuple visit_range_literal visit_ip4 visit_ip6
    visit_cidr4 visit_cidr6 visit_date visit_date_time visit_time_literal visit_uuid visit_color_literal
    visit_rational_literal visit_duration visit_month visit_week visit_key_literal visit_byte_array_literal
    visit_typed_array visit_byte_array_interpolation visit_currency_literal visit_percentage_literal
    visit_quantity_literal visit_measurement_literal visit_global_var visit_class_var visit_self visit_write
    visit_trait_def visit_module_def visit_super visit_path visit_with
    visit_on_guard visit_case_expr visit_not visit_and visit_or visit_in_test visit_until
    visit_break visit_next visit_yield visit_alias visit_fn visit_raise
    visit_is visit_splat
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(node)
      nil
    end
    RUBY
  end
  body = replace_method(body, "visit_self", <<~RUBY)
    def visit_self(node)
      if @self_stack.length > 0
        return @self_stack[@self_stack.length - 1]
      end
      nil
    end
  RUBY
  body = replace_method(body, "visit_class_var", <<~RUBY)
    def visit_class_var(node)
      self_obj = nil
      if @self_stack.length > 0
        self_obj = @self_stack[@self_stack.length - 1]
      end
      if self_obj.is_a?(WObject) && self_obj.w_class != nil
        return self_obj.w_class.get_cvar(node.name.to_s)
      elsif self_obj.is_a?(WClass)
        return self_obj.get_cvar(node.name.to_s)
      elsif @current_class != nil
        return @current_class.get_cvar(node.name.to_s)
      end
      nil
    end
  RUBY
  body = replace_method(body, "visit_global_var", <<~RUBY)
    def visit_global_var(node)
      if node.name.to_s == "$value"
        return @self_stack.length > 0 ? @self_stack[@self_stack.length - 1] : nil
      end
      @globals[node.name.to_s]
    end
  RUBY
  body = replace_method(body, "visit_write", <<~RUBY)
    def visit_write(node)
      i = 0
      while i < node.args.length
        print w_to_s(evaluate(node.args[i]))
        i += 1
      end
      nil
    end
  RUBY
  body = replace_method(body, "visit_raise", <<~RUBY)
    def visit_raise(node)
      msg = evaluate(node.value)
      runtime_error(w_to_s(msg), node: node)
    end
  RUBY
  body = replace_method(body, "visit_module_def", <<~RUBY)
    def visit_module_def(node)
      mod_name = node.name.to_s
      if @current_module != nil && @current_module != ""
        mod_name = @current_module + ":" + mod_name
      end
      w_mod = @classes[mod_name]
      if w_mod == nil
        w_mod = Runtime::WClass.new(mod_name, nil)
        @classes[mod_name] = w_mod
      end
      old_mod = @current_module
      old_class = @current_class
      @current_module = mod_name
      @current_class = w_mod
      evaluate(node.body)
      @current_class = old_class
      @current_module = old_mod
      w_mod
    end
  RUBY
  body = replace_method(body, "visit_trait_def", <<~RUBY)
    def visit_trait_def(node)
      tname = node.name.to_s
      trait_obj = @traits[tname]
      if trait_obj == nil
        trait_obj = Runtime::WClass.new(tname, nil)
        @traits[tname] = trait_obj
      end
      old_class = @current_class
      @current_class = trait_obj
      body = node.body.list
      i = 0
      while i < body.length
        stage0_define_class_body_method(trait_obj, body[i])
        i += 1
      end
      @current_class = old_class
      trait_obj
    end
  RUBY
  body = replace_method(body, "visit_path", <<~RUBY)
    def visit_path(node)
      segs = node.names
      return nil if segs == nil || segs.length == 0
      full = ""
      i = 0
      while i < segs.length
        full = full + ":" if i > 0
        full = full + segs[i].to_s
        i += 1
      end
      cls = @classes[full]
      return cls if cls != nil
      if segs.length >= 2
        prefix = ""
        pi = 0
        while pi < segs.length - 1
          prefix = prefix + ":" if pi > 0
          prefix = prefix + segs[pi].to_s
          pi += 1
        end
        last_seg = segs[segs.length - 1].to_s
        owner = @classes[prefix]
        if owner.is_a?(WClass)
          if owner.has_constant?(last_seg)
            return owner.get_constant(last_seg)
          end
        end
        val = stage0_env_get(@env, last_seg)
        return val if val != nil
      end
      stage0_env_get(@env, full)
    end
  RUBY
  body = replace_method(body, "visit_unary_op", <<~RUBY)
    def visit_unary_op(node)
      val = evaluate(node.right)
      op = node.operator
      if op == :-
        return -val
      elsif op == :+
        return val
      elsif op == :~
        return ~val
      elsif op == :!
        return !truthy?(val)
      end
      val
    end
  RUBY
  body = replace_method(body, "visit_string_interpolation", <<~RUBY)
    def visit_string_interpolation(node)
      out = ""
      parts = node.parts
      i = 0
      while i < parts.length
        part = parts[i]
        if part.is_a?(String)
          out = out + part
        else
          out = out + w_to_s(evaluate(part))
        end
        i += 1
      end
      out
    end
  RUBY
  body = replace_method(body, "visit_range_literal", <<~RUBY)
    def visit_range_literal(node)
      from_val = evaluate(node.from)
      if node.to.nil?
        return WRange.new(from_val, 0, node.exclusive, true)
      end
      to_val = evaluate(node.to)
      WRange.new(from_val, to_val, node.exclusive, false)
    end
  RUBY
  body = replace_method(body, "visit_typed_array", <<~RUBY)
    def visit_typed_array(node)
      size = evaluate(node.size_node).to_i
      res = List.new
      et = node.element_type.to_s
      fill = 0
      if et == "bool"
        fill = false
      elsif et == "f32" || et == "f64"
        fill = 0.0
      end
      i = 0
      while i < size
        res.push(fill)
        i += 1
      end
      res
    end
  RUBY
  body = replace_method(body, "visit_magic_constant", <<~RUBY)
    def visit_magic_constant(node)
      if node.value == :__LINE__
        return node.location_row || 0
      elsif node.value == :__FILE__
        return @current_file || "(eval)"
      elsif node.value == :__DIR__
        return @current_file ? File.dirname(@current_file) : Dir.pwd
      end
      nil
    end
  RUBY
  body = replace_method(body, "visit_char", <<~RUBY)
    def visit_char(node)
      node.value
    end
  RUBY
  body = replace_method(body, "visit_until", <<~RUBY)
    def visit_until(node)
      result = nil
      while !truthy?(evaluate(node.condition))
        result = evaluate(node.body)
        break if @returning
        break if @exiting
        if @breaking
          @breaking = false
          break
        end
        if @nexting
          @nexting = false
          next
        end
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_with", <<~RUBY)
    def visit_with(node)
      bindings = node.bindings
      return nil if bindings == nil || bindings.length == 0
      pair = bindings[0]
      var_node = pair[0]
      coll = evaluate(pair[1])
      return nil if coll == nil
      items = nil
      if coll.is_a?(WRange)
        items = coll.to_list.list
      elsif coll.is_a?(List)
        items = coll.list
      elsif coll.is_a?(Array)
        items = coll
      elsif coll.is_a?(Hash)
        items = coll.keys
      end
      return nil if items == nil
      var_name = var_node != nil ? var_node.name.to_s : ""
      result = nil
      i = 0
      while i < items.length
        elem = items[i]
        if var_name != ""
          @env.set(var_name, elem)
        end
        @env.set("_", elem)
        result = evaluate(node.body)
        break if @returning
        break if @exiting
        if @breaking
          @breaking = false
          break
        end
        if @nexting
          @nexting = false
          i += 1
          next
        end
        i += 1
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_yield", <<~RUBY)
    def visit_yield(node)
      blk = @current_block
      return nil if blk == nil
      args = evaluate_args(node.args)
      stage0_invoke_block(blk, args)
    end
  RUBY
  body = replace_method(body, "visit_fn", <<~RUBY)
    def visit_fn(node)
      node
    end
  RUBY
  body = replace_method(body, "visit_break", <<~RUBY)
    def visit_break(node)
      @breaking = true
      nil
    end
  RUBY
  body = replace_method(body, "visit_next", <<~RUBY)
    def visit_next(node)
      @nexting = true
      nil
    end
  RUBY
  body = replace_method(body, "visit_and", <<~RUBY)
    def visit_and(node)
      left = evaluate(node.left)
      return left if !truthy?(left)
      evaluate(node.right)
    end
  RUBY
  body = replace_method(body, "visit_or", <<~RUBY)
    def visit_or(node)
      left = evaluate(node.left)
      return left if truthy?(left)
      evaluate(node.right)
    end
  RUBY
  body = replace_method(body, "visit_not", <<~RUBY)
    def visit_not(node)
      if truthy?(evaluate(node.operand))
        false
      else
        true
      end
    end
  RUBY
  body = replace_method(body, "visit_case_expr", <<~RUBY)
    def visit_case_expr(node)
      whens = node.whens
      if node.receiver
        receiver_val = evaluate(node.receiver)
        wi = 0
        while wi < whens.length
          ci = 0
          while ci < whens[wi][0].length
            cond_val = evaluate(whens[wi][0][ci])
            if cond_val.is_a?(WRange) ? cond_val.include?(receiver_val) : (cond_val == receiver_val)
              return evaluate(whens[wi][1])
            end
            ci += 1
          end
          wi += 1
        end
      else
        wi = 0
        while wi < whens.length
          ci = 0
          while ci < whens[wi][0].length
            if truthy?(evaluate(whens[wi][0][ci]))
              return evaluate(whens[wi][1])
            end
            ci += 1
          end
          wi += 1
        end
      end
      else_body = node.else_body
      if else_body != nil
        if else_body.is_a?(List) && else_body.empty?
          return nil
        end
        return evaluate(else_body)
      end
      nil
    end
  RUBY
  body = replace_method(body, "visit_in_test", <<~RUBY)
    def visit_in_test(node)
      left = evaluate(node.lhs)
      i = 0
      while i < node.elements.length
        return true if left == evaluate(node.elements[i])
        i += 1
      end
      false
    end
  RUBY
  body = replace_method(body, "visit_assign_op", <<~RUBY)
    def visit_assign_op(node)
      tkind = node.target_kind
      hit_slot = -1
      hit_wobj = nil
      hit_ivar_slot = -1
      current = nil
      if tkind == 1
        env_shape = @env.layout_shape
        if env_shape > 1
          if node.cached_layout_shape == env_shape
            hit_slot = node.cached_slot
          else
            idx = @env.slot_index(node.target_var_name)
            if idx > 0
              node.cached_slot = idx
              node.cached_layout_shape = env_shape
              hit_slot = idx
            end
          end
        end
        if hit_slot >= 0
          cur_slot_val = @env.get_slot(hit_slot)
          if cur_slot_val.is_a?(UnboundSlot)
            current = evaluate(node.name)
          else
            current = cur_slot_val
          end
        else
          current = @env.get(node.target_var_name)
        end
      elsif tkind == 2
        if @self_stack.length > 0
          sobj = @self_stack[@self_stack.length - 1]
          if sobj.is_a?(WObject)
            wcls = sobj.w_class
            if !wcls.nil?
              hit_wobj = sobj
              if node.cached_w_class.equal?(wcls)
                hit_ivar_slot = node.cached_ivar_slot
              else
                islot = wcls.ivar_slot(node.target_var_name)
                node.cached_w_class = wcls
                node.cached_ivar_slot = islot
                hit_ivar_slot = islot
              end
            end
          end
        end
        if !hit_wobj.nil?
          current = hit_wobj.get_ivar_slot(hit_ivar_slot)
        else
          current = evaluate(node.name)
        end
      else
        current = evaluate(node.name)
      end

      acode = node.aop_code
      result = nil
      if acode == 1
        return current if truthy?(current)
        result = evaluate(node.value)
      elsif acode == 2
        return current if !truthy?(current)
        result = evaluate(node.value)
      else
        value = evaluate(node.value)
        case acode
        when 3
          if current.is_a?(List) && value.is_a?(List)
            res = List.new
            li = 0
            while li < current.length
              res.push(current[li])
              li += 1
            end
            ri = 0
            while ri < value.length
              res.push(value[ri])
              ri += 1
            end
            result = res
          elsif current.is_a?(String) || value.is_a?(String)
            result = current.to_s + value.to_s
          else
            result = current + value
          end
        when 4 then result = current - value
        when 5 then result = current * value
        when 6 then result = current / value
        when 7 then result = current % value
        when 8 then result = current | value
        when 9 then result = current & value
        when 10 then result = current ^ value
        when 11 then result = current << value
        when 12 then result = current >> value
        else result = value
        end
      end

      if tkind == 1
        if hit_slot >= 0
          @env.set_slot(hit_slot, result)
        else
          @env.set(node.target_var_name, result)
        end
      elsif tkind == 2
        if !hit_wobj.nil?
          hit_wobj.set_ivar_slot(hit_ivar_slot, result)
        elsif @self_stack.length > 0
          self_obj = @self_stack[@self_stack.length - 1]
          self_obj.set_ivar(node.target_var_name, result) if !self_obj.nil?
        end
      else
        target = node.name
        if target.doc == 28
          self_obj = @self_stack.length > 0 ? @self_stack[@self_stack.length - 1] : nil
          if self_obj.is_a?(WObject) && self_obj.w_class != nil
            self_obj.w_class.set_cvar(target.name.to_s, result)
          elsif self_obj.is_a?(WClass)
            self_obj.set_cvar(target.name.to_s, result)
          end
        elsif target.doc == 29
          @globals[target.name.to_s] = result
        end
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_symbol", <<~RUBY)
    def visit_symbol(node)
      node.value
    end
  RUBY
  body = body.sub(/^\s*def visit_array_literal\(node\)\n.*?^\s*def visit_hash_literal\(node\)/m, <<~RUBY.rstrip)
    def visit_array_literal(node)
      result = List.new
      list = node.list
      i = 0
      while i < list.length
        result.push(evaluate(list[i]))
        i += 1
      end
      result
    end

    def visit_tuple(node)
      result = List.new
      elems = node.elements
      i = 0
      while i < elems.length
        result.push(evaluate(elems[i]))
        i += 1
      end
      result
    end

    def visit_hash_literal(node)
  RUBY
  body = body.sub(/^\s*def visit_hash_literal\(node\)\n.*?^\s*def visit_range_literal\(node\)/m, <<~RUBY.rstrip)
    def visit_hash_literal(node)
      entries = node.hash_entries.list
      entry_count = entries.length
      if entry_count == 0
        return {}
      end
      entry_items = entries[0].list
      key_node = entry_items[0]
      if stage0_static_hash_key?(key_node)
        key = stage0_static_hash_key(key_node)
      else
        key = evaluate(key_node)
      end
      value = evaluate(entry_items[1])
      result = {}
      result[key] = value
      i = 1
      while i < entry_count
        entry_items = entries[i].list
        key_node = entry_items[0]
        if stage0_static_hash_key?(key_node)
          key = stage0_static_hash_key(key_node)
        else
          key = evaluate(key_node)
        end
        value = evaluate(entry_items[1])
        result[key] = value
        i += 1
      end
      result
    end

    def visit_range_literal(node)
  RUBY
  body = replace_method(body, "define_builtin", <<~RUBY)
    def define_builtin(name, &block)
      nil
    end
  RUBY
  body = replace_method(body, "define_method_builtin", <<~RUBY)
    def define_method_builtin(name, &block)
      nil
    end
  RUBY
  body = replace_method(body, "profile_enabled?", <<~RUBY)
    def profile_enabled?
      false
    end
  RUBY
  body = replace_method(body, "profile_caller_label", <<~RUBY)
    def profile_caller_label
      "<top-level>"
    end
  RUBY
  body = replace_method(body, "profile_callable_label", <<~RUBY)
    def profile_callable_label(func)
      "<callable>"
    end
  RUBY
  body = replace_method(body, "with_profile_callable", <<~RUBY)
    def with_profile_callable(func)
      yield
    end
  RUBY
  body = replace_method(body, "profile_visit_call", <<~RUBY)
    def profile_visit_call(target_label)
      nil
    end
  RUBY
  body = replace_method(body, "profile_binary_op", <<~RUBY)
    def profile_binary_op(operator)
      nil
    end
  RUBY
  body = replace_method(body, "profile_dispatch_path", <<~RUBY)
    def profile_dispatch_path(table, key)
      nil
    end
  RUBY
  body = replace_method(body, "print_profile_table", <<~RUBY)
    def print_profile_table(io, title, table)
      nil
    end
  RUBY
  body = replace_method(body, "print_profile_report", <<~RUBY)
    def print_profile_report
      nil
    end
  RUBY
  body = replace_method(body, "resolve_builtin_constant", <<~RUBY)
    def resolve_builtin_constant(name)
      name = name.to_s
      return argv if name == "ARGV"
      Environment::UNDEFINED
    end
  RUBY
  body
end

def stage0_interpreter_compat(body)
  names = body.scan(/^\s*def (?:self\.)?([a-zA-Z_][a-zA-Z_0-9!?=]*)/).flatten.uniq
  stubs = names.reject { |name| name == "initialize" || name == "run" }.map do |name|
    <<~RUBY
      def #{name}
        nil
      end
    RUBY
  end.join("\n")

  <<~RUBY
    module Tungsten
      class Interpreter < Visitor
        def initialize
          @env = Environment.new(nil)
          @loader = Loader.new(self)
          @current_file = nil
        end

        def run(source)
          Parser.parse(source.to_s)
          0
        end

    #{stubs}
      end
    end
  RUBY
end

def stage0_full_interpreter_compat(body)
  body = body.sub(/\n    if DISPATCH_PROFILE_ENABLED\n.*?\n      prepend DispatchProfiling\n    end\n/m, "\n")
  body = body.gsub("@env = Environment.new\n", "@env = Environment.new(nil)\n")
  body = body.gsub("@env = Environment.new(@env, barrier: true)", "@env = Environment.new(@env)")
  body = body.gsub("Environment.new(parent, barrier:)", "Environment.new(parent)")
  body = body.gsub("Environment.new(parent, barrier:, slot_names: cached_param_slot_names(owner, params))", "Environment.new(parent)")
  body = body.gsub("Environment.new(parent, slot_names: cached_free_var_slot_names(block, free_vars))", "Environment.new(parent)")
  body = body.gsub("NO_DIRECT_CALL = Object.new.freeze", "NO_DIRECT_CALL = 0")
  body = body.gsub("HASH_MISS = Object.new.freeze", "HASH_MISS = 0")
  body = body.gsub(/^\s*TUNGSTEN_TYPE_NAMES = \{\n.*?^\s*\}\.freeze\n/m, "    TUNGSTEN_TYPE_NAMES = 0\n")
  body = body.gsub(/^\s*ENERGY_FUELS = \{\n.*?^\s*\}\.freeze\n/m, "    ENERGY_FUELS = {}\n")
  body = body.gsub(/^\s*ENERGY_OUTPUT_UNITS = \{\n.*?^\s*\}\.freeze\n/m, "    ENERGY_OUTPUT_UNITS = {}\n")
  body = body.gsub(/      @value_nodes = \{\n.*?      \}\.compare_by_identity\n/m, "      @value_nodes = {}\n")
  body = body.gsub("      init_compiler_intrinsics\n", "")
  body = body.gsub("      Runtime::Builtins.setup(self)\n", "")
  body = body.gsub("      Runtime::Builtins.setup(self, sandbox: sandbox)\n", "")
  body = body.gsub(/      BUILTIN_TYPES\.each \{ \|name\| @classes\[name\] \|\|= Runtime::WClass\.new\(name, nil\) \}\n/, "")
  body = body.gsub(/^\s*@file_sources\[.*?\] = source.*\n/, "")
  body = body.sub(/      @env\.set\("ℎ".*?      @env\.set\("𝐹".*?\n/m, "")
  body = replace_method(body, "self.body_has_return?", <<~RUBY)
    def self.body_has_return?(node)
      false
    end
  RUBY
  body = replace_method(body, "self.body_has_break?", <<~RUBY)
    def self.body_has_break?(node)
      false
    end
  RUBY
  body = replace_method(body, "self.body_has_next?", <<~RUBY)
    def self.body_has_next?(node)
      false
    end
  RUBY
  body = replace_method(body, "self.body_has_control_signal?", <<~RUBY)
    def self.body_has_control_signal?(node, signal_class, cache_ivar)
      false
    end
  RUBY
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize
      @env = Environment.new(nil)
      @loader = Loader.new(self)
      @classes = {}
      @modules = {}
      @self_stack = [nil]
      @call_methods = []
      @call_locations = []
      @builtins = {}
      @method_builtins = {}
      @globals = {}
      @dispatch = {}
      @env_pool = nil
      @env_pool_count = 0
      @env_pool_enabled = ENV["SP_GC_DISABLE"] == "0" ? 0 : 1
      @stage0_next_layout_shape = 1
      @loaded_files = Set.new
      @stage0_loading_depth = 0
      @current_file = nil
      @source = nil
      @file_sources = {}
      @profile_enabled = false
      @profile_reported = false
      @profile_caller_stack = ["<top-level>"]
      @profile_visit_calls_by_caller = {}
      @profile_visit_calls_by_target = {}
      @profile_binary_ops = {}
      @profile_dispatch_counts = {}
      @var_names = [""]
      @var_values = [nil, ""]
      @func_names = [""]
      @func_params = [""]
      @func_bodies = [nil, ""]
      @returning = false
      @return_value = ""
      @exiting = false
      @stage0_stack_trace_enabled = ENV["TUNGSTEN_STAGE0_STACK_TRACE"] == "1" ? 1 : 0
      @stage0_bind_trace_enabled = ENV["TUNGSTEN_STAGE0_BIND_TRACE"] == "1" ? 1 : 0
      @stage0_call_eval_trace_enabled = ENV["TUNGSTEN_STAGE0_CALL_EVAL_TRACE"] == "1" ? 1 : 0
      @stage0_call_trace_enabled = ENV["TUNGSTEN_SPINEL_STAGE0_CALL_TRACE"] == "1" ? 1 : 0
      @stage0_wparser_trace_enabled = ENV["TUNGSTEN_STAGE0_WPARSER_TRACE"] == "1" ? 1 : 0
    end
  RUBY
  body = replace_method(body, "run", <<~RUBY)
    def run(source, file_path = nil)
      source = source.to_s
      source = stage0_normalize_compiler_source(source)
      @source = source
      @current_file = file_path
      ast = parse_with_file(source, file_path)
      evaluate(ast)
      0
    end
  RUBY
  body = replace_method(body, "save_state", <<~RUBY)
    def save_state
      nil
    end
  RUBY
  body = replace_method(body, "restore_state", <<~RUBY)
    def restore_state(snapshot)
      nil
    end
  RUBY
  body = replace_method(body, "evaluate_isolated", <<~RUBY)
    def evaluate_isolated(source = "", file_path = nil)
      run(source.to_s, file_path)
    end
  RUBY
  body = replace_method(body, "snapshot_runtime_class_state", <<~RUBY)
    def snapshot_runtime_class_state
      nil
    end
  RUBY
  body = replace_method(body, "restore_runtime_class_state", <<~RUBY)
    def restore_runtime_class_state(snapshot)
      nil
    end
  RUBY
  body = replace_method(body, "reload_module", <<~RUBY)
    def reload_module(path = "")
      source = File.read(path)
      @source = source
      ast = parse_with_file(source, path)
      evaluate(ast)
    end
  RUBY
  body = replace_method(body, "source_for", <<~RUBY)
    def source_for(file)
      @source
    end
  RUBY
  body = replace_method(body, "evaluate", <<~RUBY)
    def evaluate(node)
      return nil if node.nil?
      return visit_list(node) if node.doc == 1
      return visit_print(node) if node.doc == 2
      return visit_int(node) if node.doc == 3
      return visit_string_literal(node) if node.doc == 4
      return visit_boolean(node) if node.doc == 5
      return visit_nil(node) if node.doc == 6
      return visit_binary_op(node) if node.doc == 7
      return visit_assign(node) if node.doc == 8
      return stage0_visit_var(node) if node.doc == 9
      return stage0_visit_if(node) if node.doc == 10
      return stage0_visit_while(node) if node.doc == 11
      return visit_def(node) if node.doc == 12
      return visit_call(node) if node.doc == 13
      return stage0_visit_return(node) if node.doc == 14
      nil
    end
  RUBY
  body = replace_method(body, "runtime_error", <<~RUBY)
    def runtime_error(msg, node = nil, length = nil)
      raise msg.to_s
    end
  RUBY
  body = replace_method(body, "build_runtime_error", <<~RUBY)
    def build_runtime_error(msg, node = nil, length = nil)
      msg.to_s
    end
  RUBY
  body = replace_method(body, "runtime_error_from_exception", <<~RUBY)
    def runtime_error_from_exception(error, node = nil)
      "runtime error"
    end
  RUBY
  body = replace_method(body, "parse_with_file", <<~RUBY)
    def parse_with_file(source, file)
      parser = Parser.new(source)
      parser.parse
    end
  RUBY
  body = replace_method(body, "resolve_cached_local", <<~RUBY)
    def resolve_cached_local(node, name)
      nil
    end
  RUBY
  body = replace_method(body, "cached_w_method", <<~RUBY)
    def cached_w_method(node, owner)
      nil
    end
  RUBY
  body = replace_method(body, "cache_w_method", <<~RUBY)
    def cache_w_method(node, owner, method)
      method
    end
  RUBY
  body = replace_method(body, "inspect_wvalue_literal", <<~RUBY)
    def inspect_wvalue_literal(raw)
      raw.to_s
    end
  RUBY
  body = replace_method(body, "inspect_runtime_value", <<~RUBY)
    def inspect_runtime_value(value)
      value.to_s
    end
  RUBY
  body = replace_method(body, "decode_w_value", <<~RUBY)
    def decode_w_value(bits, raw = nil)
      nil
    end
  RUBY
  body = replace_method(body, "w_value_double?", <<~RUBY)
    def w_value_double?(bits)
      false
    end
  RUBY
  body = replace_method(body, "decode_w_value_double", <<~RUBY)
    def decode_w_value_double(bits)
      0
    end
  RUBY
  body = replace_method(body, "decode_w_value_stringy", <<~RUBY)
    def decode_w_value_stringy(bits, raw)
      nil
    end
  RUBY
  body = replace_method(body, "decode_w_value_char", <<~RUBY)
    def decode_w_value_char(bits, raw)
      nil
    end
  RUBY
  body = replace_method(body, "sign_extend", <<~RUBY)
    def sign_extend(value, width)
      value
    end
  RUBY
  body = replace_method(body, "coerce_value_to_wvalue", <<~RUBY)
    def coerce_value_to_wvalue(value)
      {}
    end
  RUBY
  body = replace_method(body, "coerce_integer_to_wvalue", <<~RUBY)
    def coerce_integer_to_wvalue(value)
      {}
    end
  RUBY
  body = replace_method(body, "coerce_stringy_to_wvalue", <<~RUBY)
    def coerce_stringy_to_wvalue(text, is_symbol)
      {}
    end
  RUBY
  body = replace_method(body, "box_float_wvalue", <<~RUBY)
    def box_float_wvalue(value)
      0
    end
  RUBY
  body = replace_method(body, "exact_wvalue", <<~RUBY)
    def exact_wvalue(bits, note)
      {}
    end
  RUBY
  body = replace_method(body, "unsupported_wvalue", <<~RUBY)
    def unsupported_wvalue(note)
      {}
    end
  RUBY
  body = replace_method(body, "format_wvalue_breakdown", <<~RUBY)
    def format_wvalue_breakdown(bits, raw = nil, note = nil)
      raw.to_s
    end
  RUBY
  %w[
    wvalue_breakdown_lines singleton_breakdown object_breakdown double_breakdown stringy_breakdown int_breakdown
    instant_breakdown char_breakdown numeric_breakdown packed_breakdown duration_breakdown
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(value = nil, other = nil)
      []
    end
    RUBY
  end
  body = replace_method(body, "stringy_mode_label", <<~RUBY)
    def stringy_mode_label(mode)
      ""
    end
  RUBY
  body = replace_method(body, "byte_label", <<~RUBY)
    def byte_label(byte)
      ""
    end
  RUBY
  body = replace_method(body, "safe_codepoint_label", <<~RUBY)
    def safe_codepoint_label(codepoint)
      ""
    end
  RUBY
  body = replace_method(body, "category_label", <<~RUBY)
    def category_label(index)
      ""
    end
  RUBY
  body = replace_method(body, "ipv4_label", <<~RUBY)
    def ipv4_label(addr)
      ""
    end
  RUBY
  body = replace_method(body, "inspection_header_line", <<~RUBY)
    def inspection_header_line(label, value)
      ""
    end
  RUBY
  body = replace_method(body, "inspection_field_line", <<~RUBY)
    def inspection_field_line(label, bit_range, raw, meaning)
      ""
    end
  RUBY
  body = replace_method(body, "inspection_value_label", <<~RUBY)
    def inspection_value_label(value)
      value.to_s
    end
  RUBY
  body = replace_method(body, "inspection_type_label", <<~RUBY)
    def inspection_type_label(value)
      "Object"
    end
  RUBY
  body = replace_method(body, "wvalue_object_space?", <<~RUBY)
    def wvalue_object_space?(bits)
      false
    end
  RUBY
  body = strip_methods(body, ["w_value_double?"])
  body = replace_method(body, "define_builtin", <<~RUBY)
    def define_builtin(name, &block)
      nil
    end
  RUBY
  body = replace_method(body, "define_method_builtin", <<~RUBY)
    def define_method_builtin(name, &block)
      nil
    end
  RUBY
  body = replace_method(body, "profile_enabled?", <<~RUBY)
    def profile_enabled?
      false
    end
  RUBY
  body = replace_method(body, "profile_caller_label", <<~RUBY)
    def profile_caller_label
      "<top-level>"
    end
  RUBY
  body = replace_method(body, "profile_callable_label", <<~RUBY)
    def profile_callable_label(func)
      "<callable>"
    end
  RUBY
  body = replace_method(body, "with_profile_callable", <<~RUBY)
    def with_profile_callable(func)
      yield
    end
  RUBY
  body = replace_method(body, "profile_visit_call", <<~RUBY)
    def profile_visit_call(target_label)
      nil
    end
  RUBY
  body = replace_method(body, "profile_binary_op", <<~RUBY)
    def profile_binary_op(operator)
      nil
    end
  RUBY
  body = replace_method(body, "profile_dispatch_path", <<~RUBY)
    def profile_dispatch_path(table, key)
      nil
    end
  RUBY
  body = replace_method(body, "print_profile_table", <<~RUBY)
    def print_profile_table(io, title, table)
      nil
    end
  RUBY
  body = replace_method(body, "print_profile_report", <<~RUBY)
    def print_profile_report
      nil
    end
  RUBY
  %w[
    convert_quantity_pipe decompose_quantity ast_to_unit_string apply_type_hint wrap_unsigned_bits wrap_signed_bits
    find_current_class assign_target cached_symbol_value define_accessor call_w_method_from_nodes
    call_primitive_method_from_nodes call_ruby_method_from_nodes call_builtin_from_nodes call_builtin
    invoke_method_builtin instantiate_from_nodes primitive_runtime_class tungsten_type_info evaluate_args invoke_block
    invoke_block_from_nodes execute_bound_block collect_free_vars walk_free_vars call_w_method execute_bound_w_method
    call_lambda_with_values catch_break_if_needed catch_next_if_needed iterate_with
    instantiate evaluate_begin_rescue resolve_use_path try_autoload_core find_project_root
    cached_literal_case_lookup build_literal_case_lookup literal_case_value
    cached_simple_w_method_plan execute_simple_w_method_plan expand_on_guards substance_mass parse_energy_fuel
    call_method execute_callable_body new_param_env bind_exact_small_args_from_nodes bind_params
    call_function_intrinsic_from_nodes one_call_arg_node direct_arg_value wyhash64_string_value
    wyhash_mix_u64_value wyhash_read_u32_value wyhash_read_u64_value tungsten_class_name
    small_arg_length_without_splat no_call_args? call_self_hosted_parser_intrinsic_from_nodes
    sync_self_hosted_parser_current_token skip_self_hosted_parser_tokens hash_indifferent_get
    new_free_var_env cached_param_slot_names collect_local_slot_names collect_assign_target_slot_names
    add_local_slot_name cached_free_var_slot_names
    cached_simple_method_plan build_simple_method_plan simple_method_expression execute_simple_method_plan_from_nodes
    simple_call_arg_value simple_method_value simple_method_value3 simple_method_numeric_expression?
    cached_simple_block_plan build_simple_block_plan simple_block_statement simple_block_expression
    execute_simple_block_plan_from_nodes execute_simple_block_plan simple_block_value simple_block_env_ready?
    simple_block_env_bound? simple_block_env_value simple_block_env_assign simple_block_env_assign_op
    cached_simple_w_method_plan build_simple_w_method_plan simple_w_method_statement simple_w_method_expression
    execute_simple_w_method_plan simple_w_method_plan_ready? execute_simple_w_method_plan_on_ivars
    simple_w_method_value static_condition_truth static_condition_literal_value static_condition_compare
    cached_simple_while_plan build_simple_while_plan simple_while_step simple_while_condition_expression
    simple_while_receiver_expression simple_while_expression execute_simple_while_plan
    execute_mixed_simple_while_plan bind_simple_while_plan bind_simple_while_condition_expression
    bind_simple_while_receiver_expression bind_simple_while_expression execute_mixed_simple_while_steps
    simple_while_condition_value simple_while_value simple_while_arithmetic simple_while_compare
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(a = nil, b = nil, c = nil, d = nil, e = nil, f = nil)
      nil
    end
    RUBY
  end
  %w[
    visit_regex_literal visit_symbol visit_string_interpolation visit_char visit_magic_constant
    visit_array_literal visit_tuple visit_hash_literal visit_range_literal visit_ip4 visit_ip6
    visit_cidr4 visit_cidr6 visit_date visit_date_time visit_time_literal visit_uuid visit_color_literal
    visit_rational_literal visit_duration visit_month visit_week visit_key_literal visit_byte_array_literal
    visit_typed_array visit_byte_array_interpolation visit_currency_literal visit_percentage_literal
    visit_quantity_literal visit_global_var visit_instance_var visit_class_var visit_self visit_write
    visit_trait_def visit_module_def visit_super visit_path visit_with
    visit_on_guard visit_case_expr visit_not visit_and visit_or visit_in_test visit_if visit_while visit_until
    visit_break visit_next visit_return visit_var visit_yield visit_alias visit_fn visit_begin visit_raise
    visit_is visit_splat
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(node)
      ""
    end
    RUBY
  end
  body = replace_method(body, "visit_symbol", <<~RUBY)
    def visit_symbol(node)
      node.value
    end
  RUBY
  body = replace_method(body, "resolve_use_path", <<~RUBY)
    def resolve_use_path(use_path)
      # Spinel stage0: drop the `file = @current_file.to_s; parts =
      # file.split("/")` shape — analyzer folds the .to_s chain to
      # int-default, file's local-var slot is mrb_int, split() then
      # dispatches on int and compiles to `lv_parts = 0`. Every
      # relative `use` path then falls through to the bare
      # filename (the .w gets stripped of its `compiler/lib/`
      # prefix) and `compiler/lib/lowering.w` reads 0 bytes.
      #
      # Replacement: walk the current file path backward to find
      # the last "/" without involving .to_s. Uses byteslice
      # which has its own poly-recv arm in compile_poly_method_call
      # and a sp_str_byteslice runtime — both ported earlier this
      # session. byteslice on a const char* via the @current_file
      # ivar dispatches cleanly.
      path = use_path
      base = "."
      if @current_file != nil
        last_slash = -1
        i = 0
        while i < @current_file.length
          if @current_file.byteslice(i, 1) == "/"
            last_slash = i
          end
          i += 1
        end
        if last_slash > 0
          base = @current_file.byteslice(0, last_slash)
        end
      end
      candidate = base + "/" + path
      if !candidate.end_with?(".w")
        candidate = candidate + ".w"
      end
      return candidate if File.exist?(candidate)

      candidate = "compiler/" + path
      if !candidate.end_with?(".w")
        candidate = candidate + ".w"
      end
      return candidate if File.exist?(candidate)

      candidate = path
      if !candidate.end_with?(".w")
        candidate = candidate + ".w"
      end
      candidate
    end
  RUBY
  body = replace_method(body, "visit_use", <<~RUBY)
    def visit_use(node)
      path = resolve_use_path(node.path)
  if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
    puts "stage0 use"
    puts path
  end
      return nil if @loaded_files.include?(path)

      @loaded_files.add(path)
      raw_source = File.read(path)
      if path.end_with?("compiler/lib/lexer.w")
        source = stage0_normalize_lexer_source(raw_source)
      elsif path.end_with?("languages/tungsten/lexers/regex.w")
        source = stage0_normalize_regex_source(raw_source)
  else
    source = stage0_normalize_source(raw_source)
  end
  if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
    puts "stage0 use source length"
    puts source.length
  end
  old_file = @current_file
  @current_file = path
  ast = parse_with_file(source, path)
  if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
    puts "stage0 use ast length"
    puts ast.length
  end
  evaluate(ast)
      @current_file = old_file
      nil
    end
  RUBY
  body = strip_methods(body, %w[visit_use resolve_use_path])
  body = insert_before_private(body, <<~RUBY)
    def resolve_use_path(use_path)
      # Spinel stage0: `file.split("/")` after `file = @current_file.to_s`
      # folds to `lv_parts = 0` because the analyzer types `file`
      # as int (via the .to_s chain). Walking @current_file
      # directly with byteslice — both ported earlier this session
      # — bypasses the type-fold and finds the last "/" correctly.
      # Without this fix, every relative `use lowering` from
      # inside compiler/lib/compiler.w resolves to bare
      # "lowering.w" (no path prefix), reads 0 bytes, lower_ast
      # never binds, and stage 0 errors "unknown function: lower_ast".
      path = use_path
      base = "."
      if @current_file != nil
        last_slash = -1
        i = 0
        while i < @current_file.length
          if @current_file.byteslice(i, 1) == "/"
            last_slash = i
          end
          i += 1
        end
        if last_slash > 0
          base = @current_file.byteslice(0, last_slash)
        end
      end
      candidate = base + "/" + path
      if !candidate.end_with?(".w")
        candidate = candidate + ".w"
      end
      return candidate if File.exist?(candidate)

      candidate = "compiler/" + path
      if !candidate.end_with?(".w")
        candidate = candidate + ".w"
      end
      return candidate if File.exist?(candidate)

      candidate = path
      if !candidate.end_with?(".w")
        candidate = candidate + ".w"
      end
      candidate
    end

    def visit_use(node)
      path = resolve_use_path(node.path)
      if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
        puts "stage0 use"
        puts path
      end
      return nil if @loaded_files.include?(path)

      @loaded_files.add(path)
      raw_source = File.read(path)
      if path.end_with?("compiler/lib/lexer.w")
        source = stage0_normalize_lexer_source(raw_source)
      elsif path.end_with?("languages/tungsten/lexers/regex.w")
        source = stage0_normalize_regex_source(raw_source)
      else
        source = stage0_normalize_source(raw_source)
      end
      old_file = @current_file
      @current_file = path
      ast = parse_with_file(source, path)
      evaluate(ast)
      @current_file = old_file
      nil
    end
  RUBY
  body = replace_method(body, "visit_list", <<~RUBY)
    def visit_list(node)
      result = ""
      i = 0
      while i < node.length
        result = evaluate(node[i])
        break if @returning
        break if @exiting

        i += 1
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_print", <<~RUBY)
    def visit_print(node)
      i = 0
      while i < node.args.length
        value = evaluate(node.args[i])
        puts value
        i += 1
      end
      ""
    end
  RUBY
  body = replace_method(body, "visit_boolean", <<~RUBY)
    def visit_boolean(node)
      return "true" if node.value.to_s == "true"

      "false"
    end
  RUBY
  body = replace_method(body, "visit_nil", <<~RUBY)
    def visit_nil(node)
      ""
    end
  RUBY
  body = replace_method(body, "visit_binary_op", <<~RUBY)
    def visit_binary_op(node)
      left_value = evaluate(node.left)
      right_value = evaluate(node.right)
      op = node.operator.to_s
      if op == "in"
        if node.right.doc == 1
          i = 1
          while i < node.right.length
            if left_value.to_s == evaluate(node.right[i]).to_s
              return "true"
            end
            i += 1
          end
        end
        return "false"
      end
      if op == "=="
        return (left_value.to_s == right_value.to_s).to_s
      end
      if op == "!="
        return (left_value.to_s != right_value.to_s).to_s
      end
      left = left_value.to_s.to_i
      right = right_value.to_s.to_i
      result = 0
      if op == "+"
        result = left + right
      end
      if op == "-"
        result = left - right
      end
      if op == "*"
        result = left * right
      end
      if op == "/"
        result = left / right
      end
      if op == "%"
        result = left % right
      end
      if op == ">"
        return (left > right).to_s
      end
      if op == "<"
        return (left < right).to_s
      end
      if op == ">="
        return (left >= right).to_s
      end
      if op == "<="
        return (left <= right).to_s
      end
      result.to_s
    end
  RUBY
  body = replace_method(body, "visit_assign", <<~RUBY)
    def visit_assign(node)
      value = evaluate(node.value)
      set_var(node.name, value)
      value
    end
  RUBY
  body = replace_method(body, "visit_var", <<~RUBY)
    def visit_var(node)
      get_var(node.name)
    end
  RUBY
  body = replace_method(body, "visit_if", <<~RUBY)
    def visit_if(node)
      if truthy?(evaluate(node.condition))
        return evaluate(node.then_block)
      end
      evaluate(node.else_block)
    end
  RUBY
  body = replace_method(body, "visit_while", <<~RUBY)
    def visit_while(node)
      ""
    end
  RUBY
  body = replace_method(body, "visit_def", <<~RUBY)
    def visit_def(node)
      set_func(node.name, node.args, node.body)
      ""
    end
  RUBY
  body = replace_method(body, "visit_call", <<~RUBY)
    def visit_call(node)
      if node.name == "argv"
        return $stage0_argv
      end
      if !node.obj.nil?
        receiver = evaluate(node.obj).to_s
        if node.name == "size" || node.name == "length"
          if receiver.start_with?("\n")
            return encoded_array_size(receiver)
          end
          return receiver.length.to_s
        end
        if node.name == "[]"
          if receiver.start_with?("\n")
            if node.args.length > 0
              return encoded_array_get(receiver, evaluate(node.args[0]))
            end
          end
          return ""
        end
        if node.name == "to_s"
          return receiver.to_s
        end
        if node.name == "strip"
          return receiver.strip
        end
        if node.name == "starts_with?"
          return (receiver.start_with?(evaluate(node.args[0]).to_s)).to_s if node.args.length > 0

          return "false"
        end
        if node.name == "ends_with?"
          return (receiver.end_with?(evaluate(node.args[0]).to_s)).to_s if node.args.length > 0

          return "false"
        end
        return ""
      end
      if node.name == "exit"
        File.write("/tmp/stage0-trace-EXIT-C", "site=C_visit_call")
        @exiting = true
        return ""
      end
      call_func(node.name, node.args)
    end
  RUBY
  body = replace_method(body, "visit_return", <<~RUBY)
    def visit_return(node)
      ""
    end
  RUBY
  body = replace_method(body, "w_to_s", <<~RUBY)
    def w_to_s(value)
      value.to_s
    end
  RUBY
  body = strip_methods(body, %w[truthy?])
  body = insert_before_private(body, <<~RUBY)

    def stage0_visit_var(node)
      get_var(node.name)
    end

    def stage0_visit_if(node)
      if stage0_truthy?(evaluate(node.condition))
        return evaluate(node.then_block)
      end
      evaluate(node.else_block)
    end

    def stage0_visit_while(node)
      result = ""
      while stage0_truthy?(evaluate(node.condition))
        result = evaluate(node.body)
        break if @returning
        break if @exiting
      end
      result
    end

    def stage0_visit_return(node)
      @return_value = evaluate(node.value)
      @returning = true
      @return_value
    end

    def set_var(name, value)
      name_s = name.to_s
      i = 0
      while i < @var_names.length
        if @var_names[i] == name_s
          @var_values[i] = value
          return value
        end
        i += 1
      end
      @var_names.push(name_s)
      @var_values.push(value)
      value
    end

    def get_var(name)
      name_s = name.to_s
      i = 0
      while i < @var_names.length
        if @var_names[i] == name_s
          return @var_values[i]
        end
        i += 1
      end
      ""
    end

    def set_func(name, params, body)
      name_s = name.to_s
      params_s = params.to_s
      i = 0
      while i < @func_names.length
        if @func_names[i] == name_s
          @func_params[i] = params_s
          @func_bodies[i] = body
          return ""
        end
        i += 1
      end
      @func_names.push(name_s)
      @func_params.push(params_s)
      @func_bodies.push(body)
      ""
    end

    def call_func(name, args)
      name_s = name.to_s
      i = 0
      while i < @func_names.length
        if @func_names[i] == name_s
          arg_values = []
          a = 0
          while a < args.length
            arg_values.push(evaluate(args[a]))
            a += 1
          end
          old_names = @var_names
          old_values = @var_values
          old_returning = @returning
          old_return_value = @return_value
          @var_names = [""]
          @var_values = [nil, ""]
          @returning = false
          @return_value = ""
          params = @func_params[i].to_s.split(",")
          p = 0
          while p < params.length
            if p < args.length
              set_var(params[p], arg_values[p])
            end
            p += 1
          end
          result = evaluate(@func_bodies[i])
          if @returning
            result = @return_value
          end
          @var_names = old_names
          @var_values = old_values
          @returning = old_returning
          @return_value = old_return_value
          return result
        end
        i += 1
      end
      ""
    end

    def encoded_array_size(value)
      "0"
    end

    def encoded_array_get(value, wanted)
      ""
    end

    def stage0_truthy?(value)
      text = value.to_s
      return false if text == ""
      return false if text == "false"
      true
    end

    def truthy?(value)
      text = value.to_s
      return false if text == ""
      return false if text == "false"
      true
    end
  RUBY
  body
end

def stage0_interpreter_raw_compat(body)
  body = body.sub(/\n    if DISPATCH_PROFILE_ENABLED\n.*?\n      prepend DispatchProfiling\n    end\n/m, "\n")
  body = body.gsub("NO_DIRECT_CALL = Object.new.freeze", "NO_DIRECT_CALL = 0")
  body = body.gsub("HASH_MISS = Object.new.freeze", "HASH_MISS = 0")
  body = body.gsub("UNSUPPORTED_CASE_LITERAL = Object.new.freeze", "UNSUPPORTED_CASE_LITERAL = 0")
  body = body.gsub("NO_LITERAL_CASE_LOOKUP = Object.new.freeze", "NO_LITERAL_CASE_LOOKUP = 0")
  body = body.gsub("SIMPLE_WHILE_ALWAYS_TRUE = Object.new.freeze", "SIMPLE_WHILE_ALWAYS_TRUE = 0")
  body = body.gsub("STATIC_CONDITION_UNKNOWN = Object.new.freeze", "STATIC_CONDITION_UNKNOWN = 0")
  body = body.gsub("SIMPLE_WHILE_UNSUPPORTED = Object.new.freeze", "SIMPLE_WHILE_UNSUPPORTED = 0")
  body = body.gsub("SIMPLE_METHOD_UNSUPPORTED = Object.new.freeze", "SIMPLE_METHOD_UNSUPPORTED = 0")
  body = body.gsub("SIMPLE_W_METHOD_UNSUPPORTED = Object.new.freeze", "SIMPLE_W_METHOD_UNSUPPORTED = 0")
  body = body.gsub("SIMPLE_BLOCK_UNSUPPORTED = Object.new.freeze", "SIMPLE_BLOCK_UNSUPPORTED = 0")
  if ENV["SPINEL_STAGE0_STUB_VISITORS"] == "1"
    body = body.gsub(/^(\s*)def (visit_[a-zA-Z_0-9!?=]+)\(node\)\s*=.*$/, "\\1def \\2(node)\n\\1  nil\n\\1end")
  end
  body = replace_method(body, "self.body_has_return?", "    def self.body_has_return?(node)\n      false\n    end\n")
  body = replace_method(body, "self.body_has_break?", "    def self.body_has_break?(node)\n      false\n    end\n")
  body = replace_method(body, "self.body_has_next?", "    def self.body_has_next?(node)\n      false\n    end\n")
  body = replace_method(body, "self.body_has_control_signal?", "    def self.body_has_control_signal?(node, signal_class, cache_ivar)\n      false\n    end\n")
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize
      @env = Environment.new(nil)
      @classes = {}
      @modules = {}
      @self_stack = [nil]
      @call_methods = []
      @call_locations = []
      @builtins = {}
      @method_builtins = {}
      @globals = {}
      @dispatch = {}
      @env_pool = nil
      @env_pool_count = 0
      @env_pool_enabled = ENV["SP_GC_DISABLE"] == "0" ? 0 : 1
      @stage0_next_layout_shape = 1
      @loaded_files = Set.new
      @stage0_loading_depth = 0
      @current_file = nil
      @source = nil
      @file_sources = {}

      @profile_enabled = false
      @profile_reported = false
      @profile_caller_stack = ["<top-level>"]
      @profile_visit_calls_by_caller = {}
      @profile_visit_calls_by_target = {}
      @profile_binary_ops = {}
      @profile_dispatch_counts = {}
      @var_names = [""]
      @var_values = [nil, ""]
      @func_names = [""]
      @func_params = [""]
      @func_bodies = [nil, ""]
      @returning = false
      @return_value = ""
      @exiting = false
    end
  RUBY

  body = replace_method(body, "define_builtin", <<~RUBY)
    def define_builtin(name, &block)
      nil
    end
  RUBY
  body = replace_method(body, "define_method_builtin", <<~RUBY)
    def define_method_builtin(name, &block)
      nil
    end
  RUBY
  body = replace_method(body, "profile_caller_label", <<~RUBY)
    def profile_caller_label
      "<top-level>"
    end
  RUBY
  body = replace_method(body, "profile_callable_label", <<~RUBY)
    def profile_callable_label(func)
      "<callable>"
    end
  RUBY
  body = replace_method(body, "profile_dispatch_path", <<~RUBY)
    def profile_dispatch_path(table, key)
      nil
    end
  RUBY
  body = replace_method(body, "print_profile_table", <<~RUBY)
    def print_profile_table(io, title, table)
      nil
    end
  RUBY
  body = replace_method(body, "print_profile_report", <<~RUBY)
    def print_profile_report
      nil
    end
  RUBY
  body = replace_method(body, "set_variable", <<~RUBY)
    def set_variable(name, value)
      value
    end
  RUBY
  body = replace_method(body, "run", <<~RUBY)
    def run(source)
      @source = source
      ast = parse_with_file(source, nil)
      evaluate(ast)
    end
  RUBY
  body = replace_method(body, "save_state", <<~RUBY)
    def save_state
      {}
    end
  RUBY
  body = replace_method(body, "restore_state", <<~RUBY)
    def restore_state(snapshot)
      nil
    end
  RUBY
  body = replace_method(body, "evaluate_isolated", <<~RUBY)
    def evaluate_isolated(source)
      nil
    end
  RUBY
  body = replace_method(body, "snapshot_runtime_class_state", <<~RUBY)
    def snapshot_runtime_class_state
      {}
    end
  RUBY
  body = replace_method(body, "restore_runtime_class_state", <<~RUBY)
    def restore_runtime_class_state(snapshot)
      nil
    end
  RUBY
  body = replace_method(body, "reload_module", <<~RUBY)
    def reload_module(path)
      nil
    end
  RUBY
  body = replace_method(body, "runtime_error", <<~RUBY)
    def runtime_error(msg, node = nil, length = nil)
      nil
    end
  RUBY
  body = replace_method(body, "build_runtime_error", <<~RUBY)
    def build_runtime_error(msg, node = nil, length = nil)
      Error.new(msg)
    end
  RUBY
  body = replace_method(body, "runtime_error_from_exception", <<~RUBY)
    def runtime_error_from_exception(error, node = nil)
      build_runtime_error("runtime error", node: node)
    end
  RUBY
  body = replace_method(body, "parse_with_file", <<~RUBY)
    def parse_with_file(source, file)
      parser = Parser.new(source)
      parser.parse
    end
  RUBY
  body = replace_method(body, "resolve_cached_local", <<~RUBY)
    def resolve_cached_local(node, name)
      nil
    end
  RUBY
  body = replace_method(body, "cached_w_method", <<~RUBY)
    def cached_w_method(node, owner)
      nil
    end
  RUBY
  body = replace_method(body, "cache_w_method", <<~RUBY)
    def cache_w_method(node, owner, method)
      method
    end
  RUBY
  body = replace_method(body, "inspect_wvalue_literal", <<~RUBY)
    def inspect_wvalue_literal(raw)
      raw.to_s
    end
  RUBY
  body = replace_method(body, "inspect_runtime_value", <<~RUBY)
    def inspect_runtime_value(value)
      value.to_s
    end
  RUBY
  body = replace_method(body, "decode_w_value", <<~RUBY)
    def decode_w_value(bits, raw = nil)
      nil
    end
  RUBY
  body = replace_method(body, "w_value_double?", "    def w_value_double?(bits)\n      false\n    end\n")
  body = replace_method(body, "decode_w_value_double", "    def decode_w_value_double(bits)\n      0\n    end\n")
  body = replace_method(body, "decode_w_value_stringy", "    def decode_w_value_stringy(bits, raw)\n      nil\n    end\n")
  body = replace_method(body, "decode_w_value_char", "    def decode_w_value_char(bits, raw)\n      nil\n    end\n")
  body = replace_method(body, "sign_extend", "    def sign_extend(value, width)\n      value\n    end\n")
  body = replace_method(body, "coerce_value_to_wvalue", "    def coerce_value_to_wvalue(value)\n      {}\n    end\n")
  body = replace_method(body, "coerce_integer_to_wvalue", "    def coerce_integer_to_wvalue(value)\n      {}\n    end\n")
  body = replace_method(body, "coerce_stringy_to_wvalue", "    def coerce_stringy_to_wvalue(text, is_symbol)\n      {}\n    end\n")
  body = replace_method(body, "box_float_wvalue", "    def box_float_wvalue(value)\n      0\n    end\n")
  body = replace_method(body, "exact_wvalue", "    def exact_wvalue(bits, note)\n      {}\n    end\n")
  body = replace_method(body, "unsupported_wvalue", "    def unsupported_wvalue(note)\n      {}\n    end\n")
  body = replace_method(body, "format_wvalue_breakdown", "    def format_wvalue_breakdown(bits, raw = nil, note = nil)\n      raw.to_s\n    end\n")
  %w[
    wvalue_breakdown_lines singleton_breakdown object_breakdown double_breakdown stringy_breakdown int_breakdown
    instant_breakdown char_breakdown numeric_breakdown packed_breakdown duration_breakdown
  ].each do |name|
    body = replace_method(body, name, "    def #{name}(value = nil, other = nil)\n      []\n    end\n")
  end
  body = replace_method(body, "stringy_mode_label", "    def stringy_mode_label(mode)\n      \"\"\n    end\n")
  body = replace_method(body, "byte_label", "    def byte_label(byte)\n      \"\"\n    end\n")
  body = replace_method(body, "safe_codepoint_label", "    def safe_codepoint_label(codepoint)\n      \"\"\n    end\n")
  body = replace_method(body, "category_label", "    def category_label(index)\n      \"\"\n    end\n")
  body = replace_method(body, "ipv4_label", "    def ipv4_label(addr)\n      \"\"\n    end\n")
  body = replace_method(body, "inspection_header_line", "    def inspection_header_line(label, value)\n      \"\"\n    end\n")
  body = replace_method(body, "inspection_field_line", "    def inspection_field_line(label, bit_range, raw, meaning)\n      \"\"\n    end\n")
  body = replace_method(body, "inspection_value_label", "    def inspection_value_label(value)\n      value.to_s\n    end\n")
  body = replace_method(body, "inspection_type_label", "    def inspection_type_label(value)\n      \"Object\"\n    end\n")
  body = replace_method(body, "wvalue_object_space?", "    def wvalue_object_space?(bits)\n      false\n    end\n")
  if ENV["SPINEL_STAGE0_STUB_VISITORS"] == "1"
    body.scan(/^\s*def (visit_[a-zA-Z_0-9!?=]+)/).flatten.uniq.each do |name|
      body = replace_method(body, name, "    def #{name}(node)\n      nil\n    end\n")
    end
  end
  %w[
    convert_quantity_pipe decompose_quantity ast_to_unit_string apply_type_hint wrap_unsigned_bits wrap_signed_bits
    find_current_class assign_target
  ].each do |name|
    body = replace_method(body, name, "    def #{name}(a = nil, b = nil, c = nil)\n      nil\n    end\n")
  end
  body = replace_method(body, "cached_symbol_value", "    def cached_symbol_value(node)\n      nil\n    end\n")
  %w[
    call_method call_function_intrinsic_from_nodes cached_simple_method_plan build_simple_method_plan
    simple_method_expression execute_simple_method_plan_from_nodes simple_call_arg_value
    simple_method_value simple_method_value3 simple_method_numeric_expression?
    cached_simple_block_plan build_simple_block_plan simple_block_statement simple_block_expression
    execute_simple_block_plan_from_nodes execute_simple_block_plan simple_block_value simple_block_env_ready?
    simple_block_env_bound? simple_block_env_value simple_block_env_assign simple_block_env_assign_op
    call_w_method call_w_method_from_nodes execute_bound_w_method cached_simple_w_method_plan
    build_simple_w_method_plan simple_w_method_statement simple_w_method_expression
    execute_simple_w_method_plan simple_w_method_plan_ready? execute_simple_w_method_plan_on_ivars
    simple_w_method_value cached_simple_while_plan build_simple_while_plan simple_while_step
    simple_while_condition_expression simple_while_receiver_expression simple_while_expression
    execute_simple_while_plan execute_mixed_simple_while_plan bind_simple_while_plan
    bind_simple_while_condition_expression bind_simple_while_receiver_expression bind_simple_while_expression
    execute_mixed_simple_while_steps simple_while_condition_value simple_while_value
    simple_while_arithmetic simple_while_compare
    evaluate_args new_param_env bind_exact_small_args_from_nodes bind_params execute_callable_body
    invoke_block invoke_block_from_nodes execute_bound_block collect_free_vars walk_free_vars
    one_call_arg_node direct_arg_value call_primitive_method_from_nodes call_builtin_from_nodes
    call_ruby_method_from_nodes call_self_hosted_parser_intrinsic_from_nodes
    sync_self_hosted_parser_current_token skip_self_hosted_parser_tokens hash_indifferent_get
    instantiate evaluate_begin_rescue resolve_use_path try_autoload_core find_project_root
    parse_energy_fuel
    cached_literal_case_lookup build_literal_case_lookup literal_case_value
    static_condition_truth static_condition_literal_value static_condition_compare
    expand_on_guards instantiate_from_nodes new_free_var_env cached_param_slot_names cached_free_var_slot_names
    invoke_method_builtin call_lambda_with_values with_profile_callable
    wyhash_mix_u64_value wyhash_read_u32_value wyhash_read_u64_value wyhash64_string_value
    primitive_runtime_class tungsten_class_name tungsten_type_info call_builtin
    catch_break_if_needed catch_next_if_needed iterate_with substance_mass
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
    def #{name}(a = nil, b = nil, c = nil, d = nil, e = nil, f = nil)
      nil
    end
    RUBY
  end
  body = replace_method(body, "hash_indifferent_get", <<~RUBY)
    def hash_indifferent_get(hash, key, _c = nil, _d = nil)
      value = hash[key]
      return value if value != nil

      key_text = ""
      key_text = key.to_s
      hash[key_text]
    end
  RUBY
  if ENV["SPINEL_STAGE0_STUB_VISITORS"] == "1"
    body.scan(/^\s*def (visit_[a-zA-Z_0-9!?=]+)/).flatten.uniq.each do |name|
      body = replace_method(body, name, "    def #{name}(node)\n      nil\n    end\n")
    end
  end
  body = replace_method(body, "visit_list", <<~RUBY)
    def visit_list(node)
      result = nil
      i = 0
      while i < node.length
        result = evaluate(node[i])
        break if @returning
        break if @exiting
        i += 1
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_print", <<~RUBY)
    def visit_print(node)
      i = 0
      while i < node.args.length
        value = evaluate(node.args[i])
        puts value
        i += 1
      end
      ""
    end
  RUBY
  body = replace_method(body, "visit_int", <<~RUBY)
    def visit_int(node)
      node.value
    end
  RUBY
  unless body.match?(/^[ \t]*def[ \t]+visit_int(?:\b|\s|\()/)
    body = body.sub(/(^[ \t]*)def[ \t]+visit_boolean\(node\)/, <<~RUBY.rstrip)
\\1def visit_int(node)
\\1  text = node.value.to_s
\\1  text.to_i
\\1end

\\1def visit_boolean(node)
    RUBY
  end
  body = replace_method(body, "visit_binary_op", <<~RUBY)
    def visit_binary_op(node)
      left_value = evaluate(node.left)
      right_value = evaluate(node.right)
      op = node.operator.to_s
      if op == "in"
        if node.right.doc == 1
          i = 1
          while i < node.right.length
            if left_value.to_s == evaluate(node.right[i]).to_s
              return "true"
            end
            i += 1
          end
        end
        return "false"
      end
      if op == "=="
        return (left_value.to_s == right_value.to_s).to_s
      elsif op == "!="
        return (left_value.to_s != right_value.to_s).to_s
      end
      left = left_value.to_i
      right = right_value.to_i
      result = 0
      if node.operator == :+
        result = left + right
      elsif node.operator == :-
        result = left - right
      elsif node.operator == :*
        result = left * right
      elsif node.operator == :/
        result = left / right
      elsif node.operator == :%
        result = left % right
      elsif node.operator == :>
        return (left > right).to_s
      elsif node.operator == :<
        return (left < right).to_s
      elsif node.operator == :>=
        return (left >= right).to_s
      elsif node.operator == :<=
        return (left <= right).to_s
      end
      result.to_s
    end
  RUBY
  body = replace_method(body, "visit_assign", <<~RUBY)
    def visit_assign(node)
      value = evaluate(node.value)
      set_var(node.name, value)
      value
    end
  RUBY
  body = replace_method(body, "visit_var", <<~RUBY)
    def visit_var(node)
      get_var(node.name)
    end
  RUBY
  body = replace_method(body, "visit_if", <<~RUBY)
    def visit_if(node)
      if truthy?(evaluate(node.condition))
        return evaluate(node.then_block)
      end
      evaluate(node.else_block)
    end
  RUBY
  body = replace_method(body, "visit_while", <<~RUBY)
    def visit_while(node)
      result = ""
      while truthy?(evaluate(node.condition))
        result = evaluate(node.body)
        break if @returning
        break if @exiting
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_def", <<~RUBY)
    def visit_def(node)
      set_func(node.name, node.args, node.body)
      ""
    end
  RUBY
  body = replace_method(body, "visit_call", <<~RUBY)
    def visit_call(node)
      call_func(node.name, node.args)
    end
  RUBY
  body = replace_method(body, "visit_return", <<~RUBY)
    def visit_return(node)
      @return_value = evaluate(node.value)
      @returning = true
      @return_value
    end
  RUBY
  body = replace_method(body, "visit_string_literal", <<~RUBY)
    def visit_string_literal(node)
      node.value
    end
  RUBY
  body = replace_method(body, "visit_boolean", <<~RUBY)
    def visit_boolean(node)
      node.value.to_s
    end
  RUBY
  body = replace_method(body, "visit_nil", <<~RUBY)
    def visit_nil(node)
      ""
    end
  RUBY
  body = replace_method(body, "visit_range_literal", <<~RUBY)
    def visit_range_literal(node)
      ""
    end
  RUBY
  body = replace_method(body, "w_to_s", <<~RUBY)
    def w_to_s(value)
      value.to_s
    end
  RUBY
  body = replace_method(body, "source_for", <<~RUBY)
    def source_for(file)
      @source
    end
  RUBY
  body = replace_method(body, "run", <<~RUBY)
    def run(source)
      @source = source
      ast = parse_with_file(source, nil)
      evaluate(ast)
      0
    end
  RUBY

  body = replace_method(body, "evaluate", <<~RUBY)
    def evaluate(node)
      return "" unless node
      return visit_list(node) if node.doc == 1
      return visit_print(node) if node.doc == 2
      return visit_int(node) if node.doc == 3
      return visit_string_literal(node) if node.doc == 4
      return visit_boolean(node) if node.doc == 5
      return visit_nil(node) if node.doc == 6
      return visit_binary_op(node) if node.doc == 7
      return visit_assign(node) if node.doc == 8
      return visit_var(node) if node.doc == 9
      return visit_if(node) if node.doc == 10
      return visit_while(node) if node.doc == 11
      return visit_def(node) if node.doc == 12
      return visit_call(node) if node.doc == 13
      return visit_return(node) if node.doc == 14
      return visit_assign_op(node) if node.doc == 15
      return cached_symbol_value(node) if node.doc == 16
      return visit_array_literal(node) if node.doc == 17
      return visit_hash_literal(node) if node.doc == 18
      return visit_and(node) if node.doc == 19
      return visit_or(node) if node.doc == 20
      return visit_in_test(node) if node.doc == 21
      return visit_case_expr(node) if node.doc == 22
      return visit_use(node) if node.doc == 23
      return visit_class_def(node) if node.doc == 24
      return visit_module_def(node) if node.doc == 25
      return visit_trait_def(node) if node.doc == 26
      return visit_instance_var(node) if node.doc == 27
      return visit_class_var(node) if node.doc == 28
      return visit_global_var(node) if node.doc == 29
      return visit_self(node) if node.doc == 30
      return node.value if node.doc == 31
      return node.value if node.doc == 32
      return decode_w_value(node.value, node.raw) if node.doc == 33
      return visit_begin(node) if node.doc == 34
      return visit_raise(node) if node.doc == 35
      if node.doc == 36
        visit_write(node)
        return ""
      end
      return visit_fn(node) if node.doc == 37
      return visit_yield(node) if node.doc == 38
      return visit_break(node) if node.doc == 39
      return visit_next(node) if node.doc == 40
      return visit_not(node) if node.doc == 41
      return visit_tuple(node) if node.doc == 42
      return visit_splat(node) if node.doc == 43
      return visit_string_interpolation(node) if node.doc == 44
      return visit_alias(node) if node.doc == 45
      return visit_is(node) if node.doc == 46
      return visit_super(node) if node.doc == 47

      ""
    end
  RUBY
  body = strip_methods(body, %w[visit_var visit_if visit_while visit_def visit_call visit_return truthy?])
  body = insert_before_private(body, <<~RUBY)

      def visit_var(node)
        get_var(node.name)
      end

      def visit_if(node)
        if truthy?(evaluate(node.condition))
          return evaluate(node.then_block)
        end
        evaluate(node.else_block)
      end

      def visit_while(node)
        result = ""
        while truthy?(evaluate(node.condition))
          result = evaluate(node.body)
        end
        result
      end

      def visit_def(node)
        set_func(node.name, node.args, node.body)
        ""
      end

      def visit_call(node)
        if node.name == "argv"
          return $stage0_argv
        end
        if node.obj
          receiver = evaluate(node.obj)
          if node.name == "size"
            if receiver.start_with?("\n")
              return encoded_array_size(receiver)
            end
            return receiver.length.to_s
          end
          if node.name == "length"
            if receiver.start_with?("\n")
              return encoded_array_size(receiver)
            end
            return receiver.length.to_s
          end
          if node.name == "[]"
            if receiver.start_with?("\n")
              if node.args.length > 0
                return encoded_array_get(receiver, evaluate(node.args[0]))
              end
            end
            return ""
          end
          if node.name == "to_s"
            return receiver.to_s
          end
          if node.name == "strip"
            return receiver.strip
          end
          if node.name == "starts_with?"
            if node.args.length > 0
              prefix = evaluate(node.args[0])
              return (receiver.start_with?(prefix)).to_s
            end
            return "false"
          end
          if node.name == "ends_with?"
            if node.args.length > 0
              suffix = evaluate(node.args[0])
              return (receiver.end_with?(suffix)).to_s
            end
            return "false"
          end
          if node.name == "new"
            return ""
          end
          return ""
        end
        if node.name == "exit"
          File.write("/tmp/stage0-trace-EXIT-D", "site=D_visit_call_secondary")
          @exiting = true
          return ""
        end
        call_func(node.name, node.args)
      end

      def encoded_array_size(value)
        "0"
      end

      def encoded_array_get(value, wanted)
        ""
      end

      def visit_return(node)
        @return_value = evaluate(node.value)
        @returning = true
        @return_value
      end

      def set_var(name, value)
        name_s = name.to_s
        i = 0
        while i < @var_names.length
          if @var_names[i] == name_s
            @var_values[i] = value
            return value
          end
          i += 1
        end
        @var_names.push(name_s)
        @var_values.push(value)
        value
      end

      def get_var(name)
        name_s = name.to_s
        i = 0
        while i < @var_names.length
          if @var_names[i] == name_s
            return @var_values[i]
          end
          i += 1
        end
        ""
      end

      def set_func(name, params, body)
        name_s = name.to_s
        params_s = params.to_s
        i = 0
        while i < @func_names.length
          if @func_names[i] == name_s
            @func_params[i] = params_s
            @func_bodies[i] = body
            return ""
          end
          i += 1
        end
        @func_names.push(name_s)
        @func_params.push(params_s)
        @func_bodies.push(body)
        ""
      end

      def call_func(name, args)
        name_s = name.to_s
        i = 0
        while i < @func_names.length
          if @func_names[i] == name_s
            arg_values = [nil, ""]
            a = 0
            while a < args.length
              arg_values.push(evaluate(args[a]))
              a += 1
            end
            old_names = @var_names
            old_values = @var_values
            old_returning = @returning
            old_return_value = @return_value
            @var_names = [""]
            @var_values = [nil, ""]
            @returning = false
            @return_value = ""
            params = @func_params[i].split(",")
            p = 0
            while p < params.length
              if p < args.length
                set_var(params[p], arg_values[p + 1])
              end
              p += 1
            end
            result = evaluate(@func_bodies[i])
            if @returning
              result = @return_value
            end
            @var_names = old_names
            @var_values = old_values
            @returning = old_returning
            @return_value = old_return_value
            return result
          end
          i += 1
        end
        ""
      end

      def truthy?(value)
        return false if value == ""
        return false if value == "false"
        true
      end
  RUBY
  body
end

def stage0_list_source
  <<~RUBY
    module Tungsten::AST
      class List < Node
        attr_reader :list

        def self.from(obj)
          return new if obj.nil?
          return obj if obj.is_a?(List)
          if obj.is_a?(Array)
            res = new
            i = 0
            while i < obj.length
              res.push(obj[i])
              i += 1
            end
            return res
          end
          res = new
          res.push(obj)
          res
        end

        def initialize
          @doc = 1
          @list = []
        end

        def [](i)
          idx = i.to_i
          if idx < 0
            idx = @list.length + idx
          end
          return nil if idx < 0 || idx >= @list.length
          @list[idx]
        end

        def []=(i, value)
          idx = i.to_i
          if idx < 0
            idx = @list.length + idx
          end
          while @list.length <= idx
            @list.push(nil)
          end
          @list[idx] = value
          value
        end

        def set_at(i, value)
          self[i] = value
        end

        def <<(exp)
          @list.push(exp)
          self
        end

        def push(exp)
          @list.push(exp)
          self
        end

        def pop
          @list.pop
        end

        def clear
          @list.clear
          self
        end

        def delete_at(i)
          @list.delete_at(i.to_i)
        end

        def include?(val)
          i = 0
          while i < @list.length
            return true if @list[i] == val
            i += 1
          end
          false
        end

        def each(&block)
          @list.each(&block) if block
          self
        end

        def empty?
          @list.empty?
        end

        def last
          @list.last
        end

        def length
          @list.length
        end

        def size
          @list.length
        end

        def first
          @list.first
        end

        def to_a
          @list
        end
      end
    end
  RUBY
end

def stage0_literal_source(path)
  file = File.basename(path)
  case file
  when "nil.rb"
    <<~RUBY
      module Tungsten::AST
        class Nil < Node
          def initialize
            @doc = 6
          end
        end
      end
    RUBY
  when "color_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class ColorLiteral < Node
          attr_accessor :value, :r, :g, :b, :a
          def initialize(r, g, b, a = 255)
            @value = 0
            @r = r
            @g = g
            @b = b
            @a = a
          end
        end
      end
    RUBY
  when "currency_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class CurrencyLiteral < Node
          attr_accessor :value_str, :symbol
          def initialize(value_str, symbol)
            @value_str = value_str
            @symbol = symbol
          end
        end
      end
    RUBY
  when "percentage_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class PercentageLiteral < Node
          attr_accessor :value_str, :num_type
          def initialize(value_str, num_type)
            @value_str = value_str
            @num_type = num_type
          end
        end
      end
    RUBY
  when "quantity_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class QuantityLiteral < Node
          attr_accessor :number, :unit_string
          def initialize(number, unit_string)
            @number = number
            @unit_string = unit_string
          end
        end
      end
    RUBY
  when "measurement_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class MeasurementLiteral < Node
          attr_accessor :number, :uncertainty
          def initialize(number, uncertainty)
            @number = number
            @uncertainty = uncertainty
          end
        end
      end
    RUBY
  when "range_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class RangeLiteral < Node
          attr_accessor :from, :to, :exclusive
          def initialize(from, to, exclusive = false)
            @doc = 48
            @from = from
            @to = to
            @exclusive = exclusive
          end
        end
      end
    RUBY
  when "set_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class SetLiteral < Node
          attr_accessor :elements
          def initialize(elements)
            @elements = elements.to_a
          end
        end
        class MultisetLiteral < Node
          attr_accessor :elements
          def initialize(elements)
            @elements = elements.to_a
          end
        end
      end
    RUBY
  when "regex_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class RegexLiteral < Node
          attr_accessor :value, :pattern, :options
          def initialize(pattern, options = "")
            @doc = 31
            @pattern = pattern
            @options = options
            @value = pattern
          end
        end
      end
    RUBY
  when "typed_array.rb"
    <<~RUBY
      module Tungsten::AST
        class TypedArray < Node
          attr_accessor :element_type, :size_node
          def initialize(element_type, size)
            @doc = 49
            @element_type = element_type
            @size_node = size
          end
        end
      end
    RUBY
  when "char.rb"
    <<~RUBY
      module Tungsten::AST
        class Char < Node
          attr_accessor :value
          def initialize(value)
            @doc = 50
            if value.is_a?(String)
              cps = value.codepoints
              @value = cps.length > 0 ? cps[0] : 0
            else
              @value = value.to_i
            end
          end
        end
      end
    RUBY
  when "magic_constant.rb"
    <<~RUBY
      module Tungsten::AST
        class MagicConstant < Node
          attr_accessor :value
          def initialize(value)
            @doc = 51
            @value = value.to_sym
          end
        end
      end
    RUBY
  when "float.rb"
    <<~RUBY
      module Tungsten::AST
        class FloatLiteral < Node
          attr_accessor :value
          def initialize(value)
            @doc = 31
            s = value.to_s.delete("_")
            s = s[1, s.length - 1] if s.start_with?("~")
            @value = s.to_f
          end
        end
      end
    RUBY
  when "decimal.rb"
    <<~RUBY
      module Tungsten::AST
        class Decimal < Node
          attr_accessor :value
          def initialize(value)
            @doc = 31
            @value = value.to_s.delete("_").to_f
          end
        end
      end
    RUBY
  when "w_value.rb"
    <<~RUBY
      module Tungsten::AST
        class WValue < Node
          attr_accessor :value, :raw
          def initialize(value)
            @doc = 33
            @value = value
            @raw = value.to_s
          end
        end
      end
    RUBY
  when "int.rb"
    # Parse the integer literal ONCE here. The generic stub below just stores
    # the raw lexeme string in @value, so every arithmetic use of an int
    # literal re-parsed it via sp_poly_to_i -> strtoll (a top hot spot in the
    # real-stage1 profile). The compiler source uses hex (0x x259), binary
    # (0b), and underscored (1_000) literals, so a bare .to_i would corrupt
    # it — replicate int.rb's parse_literal in a spinel-compilable form:
    # "" + .to_s recovers the poly token value, delete/start_with?/two-arg
    # slice/to_i(base) all lower cleanly, and open-ended range slices (`[2..]`)
    # are avoided.
    <<~RUBY
      module Tungsten::AST
        class Int < Node
          attr_accessor :value, :raw
          def initialize(value)
            @doc = 3
            @raw = "" + value.to_s
            text = @raw.delete("_")
            neg = false
            if text.start_with?("-")
              neg = true
              text = text[1, text.length - 1]
            elsif text.start_with?("+")
              text = text[1, text.length - 1]
            end
            n = 0
            if text.start_with?("0x") || text.start_with?("0X")
              digits = text[2, text.length - 2]
              first = digits[0, 1].to_i(16)
              if !neg && digits.length == 16 && first >= 8
                # Spinel's native integers are signed i64s. Preserve a full
                # u64 literal as its two's-complement bit pattern instead of
                # asking String#to_i to overflow above INT64_MAX.
                high = first - 8
                tail = digits[1, 15].to_i(16)
                @value = (-9223372036854775807 - 1) + high * 1152921504606846976 + tail
                return
              end
              n = digits.to_i(16)
            elsif text.start_with?("0b") || text.start_with?("0B")
              n = text[2, text.length - 2].to_i(2)
            elsif text.start_with?("0o") || text.start_with?("0O")
              n = text[2, text.length - 2].to_i(8)
            elsif text.start_with?("0d") || text.start_with?("0D")
              n = text[2, text.length - 2].to_i(10)
            else
              # The compiler preserves raw literal text and reconstructs
              # decimal BigInts downstream. Avoid asking Spinel's native-i64
              # parser to consume those values while constructing this shim
              # AST; the placeholder is replaced from @raw before it matters.
              overflow = text.length > 19
              if text.length == 19
                limit = neg ? "9223372036854775808" : "9223372036854775807"
                overflow = text > limit
              end
              if overflow
                @value = 0
                return
              end
              n = text.to_i
            end
            if neg
              n = -n
            end
            @value = n
          end
        end
      end
    RUBY
  else
    class_name = {
      "boolean.rb" => "Boolean",
      "byte_array_literal.rb" => "ByteArrayLiteral",
      "char.rb" => "Char",
      "cidr4.rb" => "CIDR4",
      "cidr6.rb" => "CIDR6",
      "date.rb" => "Date",
      "date_time.rb" => "DateTime",
      "decimal.rb" => "Decimal",
      "duration.rb" => "Duration",
      "float.rb" => "FloatLiteral",
      "int.rb" => "Int",
      "ip4.rb" => "IP4",
      "ip6.rb" => "IP6",
      "key_literal.rb" => "KeyLiteral",
      "magic_constant.rb" => "MagicConstant",
      "month.rb" => "Month",
      "rational.rb" => "RationalLiteral",
      "string_literal.rb" => "StringLiteral",
      "time_literal.rb" => "TimeLiteral",
      "uuid.rb" => "UUID",
      "week.rb" => "Week"
    }.fetch(file)
    doc = case class_name
          when "Int" then 3
          when "StringLiteral" then 4
          when "Boolean" then 5
          when "Char", "FloatLiteral", "Decimal", "RationalLiteral", "Month", "Week" then 31
          else 32
          end

    <<~RUBY
      module Tungsten::AST
        class #{class_name} < Node
          attr_accessor :value
          def initialize(value)
            @doc = #{doc}
            @value = value
          end
        end
      end
    RUBY
  end
end

def stage0_literal_compat(body, path)
  body = body.gsub(/class\s+([A-Za-z_0-9]+)\s+<\s+Value/) do
    "class #{$1} < Node\n    attr_accessor :value"
  end

  case path
  when %r{/ast/literals/int\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(value)
        @doc = 3
        @value = value
      end
    RUBY
  when %r{/ast/literals/string_literal\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(value)
        @doc = 4
        @value = value
      end
    RUBY
  when %r{/ast/literals/decimal\.rb\z},
       %r{/ast/literals/rational\.rb\z},
       %r{/ast/literals/regex_literal\.rb\z},
       %r{/ast/literals/date\.rb\z},
       %r{/ast/literals/date_time\.rb\z},
       %r{/ast/literals/time_literal\.rb\z},
       %r{/ast/literals/week\.rb\z},
       %r{/ast/literals/month\.rb\z},
       %r{/ast/literals/uuid\.rb\z},
       %r{/ast/literals/w_value\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(value)
        @value = value
      end
    RUBY
  else
    body
  end
end

def stage0_ast_compat(body, path)
  case path
  when %r{/ast/symbol\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(value)
        @doc = 16
        v = value.to_s
        v = v[1, v.length - 1] if v.start_with?(":")
        @value = v.to_sym
      end
    RUBY
  when %r{/ast/array_literal\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class ArrayLiteral < List
          def initialize(list = nil)
            @doc = 17
            arr = [nil, 0, ""]
            arr.clear
            if !list.nil?
              li = 0
              llen = list.length
              while li < llen
                arr.push(list[li])
                li += 1
              end
            end
            @list = arr
          end
        end
      end
    RUBY
  when %r{/ast/hash_literal\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(entries = nil)
        @doc = 18
        if entries == nil
          @entries = List.new
        elsif entries.is_a?(List)
          @entries = entries
        else
          list = List.new
          i = 0
          while i < entries.length
            pair = entries[i]
            if pair.is_a?(List)
              to_push = entries
              to_push = pair
              list.push(to_push)
            else
              normalized_pair = List.new
              normalized_pair.push(pair[0])
              normalized_pair.push(pair[1])
              list.push(normalized_pair)
            end
            i += 1
          end
          @entries = list
        end
      end

      def hash_entries
        @entries
      end
    RUBY
  when %r{/ast/arg\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, default = nil, type = nil)
        @name = name.to_s
        @default = default
        @type = type
      end

      def default_value
        @default
      end
    RUBY
  when %r{/ast/keywords/with\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(bindings, body = nil)
        @doc = 57
        @bindings = bindings
        @body = List.from(body)
      end
    RUBY
  when %r{/ast/and\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(left, right)
        @doc = 19
        @left = left
        @right = right
      end
    RUBY
  when %r{/ast/or\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(left, right)
        @doc = 20
        @left = left
        @right = right
      end
    RUBY
  when %r{/ast/in_test\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(lhs, elements)
        @doc = 21
        @lhs = lhs
        @elements = elements.to_a
      end
    RUBY
  when %r{/ast/keywords/case_expr\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(receiver, whens, else_body = nil)
        @doc = 22
        @receiver = 0
        @receiver = ""
        @receiver = receiver
        @whens = 0
        @whens = whens
        @else_body = 0
        @else_body = else_body
      end
    RUBY
  when %r{/ast/keywords/use\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(path)
        @doc = 23
        @path = path.to_s
      end
    RUBY
  when %r{/ast/keywords/class_def\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, body = nil, superclass = "", class_role = nil)
        @doc = 24
        @name = name
        @body = List.from(body)
        @superclass = superclass
        @class_role = class_role
      end
    RUBY
  when %r{/ast/keywords/module_def\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, body = nil)
        @doc = 25
        @name = Tungsten::AST.intern_name(name)
        @body = List.from(body)
      end
    RUBY
  when %r{/ast/keywords/trait_def\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, body = nil)
        @doc = 26
        @name = Tungsten::AST.intern_name(name)
        @body = List.from(body)
      end
    RUBY
  when %r{/ast/instance_var\.rb\z}
    body = body.sub("    attr_accessor :name\n",
                    "    attr_accessor :name, :cached_w_class, :cached_ivar_slot\n")
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name)
        @doc = 27
        @name = "" + name.to_s
        @cached_w_class = nil
        @cached_ivar_slot = -1
      end
    RUBY
  when %r{/ast/class_var\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name)
        @doc = 28
        @name = Tungsten::AST.intern_name(name)
      end
    RUBY
  when %r{/ast/global_var\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name)
        @doc = 29
        @name = Tungsten::AST.intern_name(name)
      end
    RUBY
  when %r{/ast/self\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Self < Node
          def initialize
            @doc = 30
          end
        end
      end
    RUBY
  when %r{/ast/keywords/begin\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(body, rescue_var = nil, rescue_body = nil, ensure_body = nil)
        @doc = 34
        @body = List.from(body)
        @rescue_var = rescue_var
        @rescue_body = rescue_body ? List.from(rescue_body) : nil
        @ensure_body = ensure_body ? List.from(ensure_body) : nil
      end
    RUBY
  when %r{/ast/keywords/raise\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(value = nil)
        @doc = 35
        @value = value
      end
    RUBY
  when %r{/ast/keywords/write\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Write < KeywordArgs
          attr_accessor :args

          def initialize(args)
            @doc = 36
            @args = args
          end
        end
      end
    RUBY
  when %r{/ast/keywords/fn\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Fn < Def
          def initialize(name, args, body, receiver: nil, block: nil, yields: nil, splat_index: nil, double_splat: nil)
            @doc = 37
            @name = name ? ("" + name.to_s) : nil
            @args = args || []
            @body = body
            @receiver = receiver
            @block = block
            @splat_index = splat_index
            @double_splat = double_splat
            @accessor_kind = 0
            @accessor_ivar = ""
            @cached_w_class = nil
            @cached_ivar_slot = -1
            @frame_shape = 0
            @frame_slot_count = 1
            @frame_block_slot = 0
            @frame_slot_map = nil
            @stage0_param_names = [""]
            @stage0_param_names.clear
            if @args
              i = 0
              while i < @args.length
                @stage0_param_names.push("" + @args[i].name.to_s)
                i += 1
              end
            end
          end
        end
      end
    RUBY
  when %r{/ast/keywords/yield\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Yield < KeywordArgs
          attr_accessor :args

          def initialize(args)
            @doc = 38
            @args = args
          end
        end
      end
    RUBY
  when %r{/ast/keywords/break\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Break < Node
          attr_accessor :value

          def initialize(value = nil)
            @doc = 39
            @value = value
          end
        end
      end
    RUBY
  when %r{/ast/keywords/next\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Next < Node
          attr_accessor :value

          def initialize(value = nil)
            @doc = 40
            @value = value
          end
        end
      end
    RUBY
  when %r{/ast/not\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Not < UnaryExpression
          attr_accessor :operand

          def initialize(exp)
            @doc = 41
            @operand = 0
            @operand = ""
            @operand = exp
          end
        end
      end
    RUBY
  when %r{/ast/tuple\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(elements = [])
        @doc = 42
        @elements = (elements || []).to_a
      end
    RUBY
  when %r{/ast/splat\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(exp)
        @doc = 43
        @exp = exp
      end
    RUBY
  when %r{/ast/string_interpolation\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(parts = [])
        @doc = 44
        @parts = parts || []
      end
    RUBY
  when %r{/ast/keywords/alias\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(to, from)
        @doc = 45
        @to = to
        @from = from
      end
    RUBY
  when %r{/ast/keywords/is\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(trait_name)
        @doc = 46
        @trait_name = Tungsten::AST.intern_name(trait_name)
      end
    RUBY
  when %r{/ast/keywords/super\.rb\z},
       %r{/ast/super\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Super < Node
          attr_accessor :args

          def initialize(args = [])
            @doc = 47
            @args = args || []
          end
        end
      end
    RUBY
  when %r{/ast/keyword_args\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(args)
        @args = args
      end
    RUBY
  when %r{/ast/keywords/print\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Print < KeywordArgs
          attr_accessor :args

          def initialize(args)
            @doc = 2
            @args = args
          end
        end
      end
    RUBY
  when %r{/ast/path\.rb\z}
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(names, global = false)
        @doc = 52
        if names.is_a?(Array)
          @names = [""]
          @names.clear
          i = 0
          while i < names.length
            @names.push(names[i].to_s)
            i += 1
          end
        else
          @names = [names.to_s]
        end
        @global = global
      end
    RUBY
    body = replace_method(body, "single?", <<~RUBY)
      def single?(name)
        @names.length == 1 && @names[0] == name.to_s
      end
    RUBY
    replace_method(body, "single_name?", <<~RUBY)
      def single_name?
        if @names.length == 1 && !@global
          @names[0]
        else
          0
        end
      end
    RUBY
  when %r{/ast/type_hint\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(value, hint)
        @doc = 53
        @value = value
        @hint = hint
      end
    RUBY
  when %r{/ast/block\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(args = [], body = nil)
        @doc = 54
        @args = args || []
        @body = List.from(body)
      end
    RUBY
  when %r{/ast/keywords/on_guard\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(predicate, capabilities, body = nil)
        @doc = 55
        @predicate = predicate
        @capabilities = capabilities
        @body = List.from(body)
      end
    RUBY
  when %r{/ast/call\.rb\z}
    body = body.sub("    attr_accessor :obj, :name, :args, :block, :target_def, :default\n",
                    "    attr_accessor :obj, :name, :block, :target_def, :default\n    attr_reader :args\n")
    body = body.sub("    attr_accessor :cached_name_sym  # spinel-only: sym id for @name; -1 sentinel = not yet cached\n",
                    "    attr_accessor :cached_name_sym, :call_builtin_kind, :cached_top_fn\n")
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(obj, name, args = nil, block = nil, column = 0, parens = false)
        @doc = 13
        @obj = obj
        @name = "" + name.to_s
        arr = [nil, 0, ""]
        arr.clear
        if !args.nil?
          ai = 0
          alen = args.length
          while ai < alen
            arr.push(args[ai])
            ai += 1
          end
        end
        @args = arr
        @block = block
        @name_column_number = column
        @has_parens = parens
        @cached_name_sym = :__spinel_uncached_name__
        @call_builtin_kind = 0
        @cached_top_fn = nil
        @cached_dispatch_owner = nil
        @cached_dispatch_version = 0
        @cached_w_method = nil
      end
    RUBY
    replace_method(body, "can_assign?", <<~RUBY)
      def can_assign?
        (@obj.nil? && (@args.nil? || @args.empty?) && @block.nil?) || @name == "[]"
      end
    RUBY
  when %r{/ast/binary_op\.rb\z}
    body = body.sub("    attr_accessor :left, :operator, :right\n",
                    "    attr_accessor :left, :operator, :right, :bop_code\n")
    replace_method(body, "initialize", <<~RUBY)
      def initialize(left, operator, right)
        @doc = 7
        @left = left
        op_s = "" + operator.to_s
        @operator = op_s.to_sym
        @right = right
        @bop_code =
          if op_s == "==" then 1
          elsif op_s == "!=" then 2
          elsif op_s == "<" then 3
          elsif op_s == "<=" then 4
          elsif op_s == ">" then 5
          elsif op_s == ">=" then 6
          elsif op_s == "<=>" then 7
          elsif op_s == "+" then 8
          elsif op_s == "-" then 9
          elsif op_s == "*" then 10
          elsif op_s == "/" then 11
          elsif op_s == "%" then 12
          elsif op_s == "**" then 13
          elsif op_s == "<<" then 14
          elsif op_s == ">>" then 15
          elsif op_s == "&" then 16
          elsif op_s == "|" then 17
          elsif op_s == "^" then 18
          elsif op_s == "||" then 19
          elsif op_s == "&&" then 20
          elsif op_s == "in" then 21
          elsif op_s == "" then 22
          else 0
          end
      end
    RUBY
  when %r{/ast/assign\.rb\z}
    body = body.sub("    attr_accessor :cached_env, :cached_slot, :cached_layout_shape\n",
                    "    attr_accessor :cached_env, :cached_slot, :cached_layout_shape, :target_kind, :target_var_name, :cached_w_class, :cached_ivar_slot\n")
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, value, type_hint = nil)
        @doc = 8
        @name = name
        @value = value
        @type_hint = type_hint
        @cached_env = nil
        @cached_slot = -1
        @cached_layout_shape = 1
        @cached_w_class = nil
        @cached_ivar_slot = -1
        if name.is_a?(String)
          @target_kind = 1
          @target_var_name = "" + name
        elsif !name.nil? && name.doc == 9
          @target_kind = 1
          @target_var_name = "" + name.name.to_s
        elsif !name.nil? && name.doc == 27
          @target_kind = 2
          @target_var_name = "" + name.name.to_s
        else
          @target_kind = 0
          @target_var_name = ""
        end
      end
    RUBY
  when %r{/ast/assign_op\.rb\z}
    body = body.sub("    attr_accessor :name, :operator, :value\n",
                    "    attr_accessor :name, :operator, :value, :aop_code, :target_kind, :target_var_name, :cached_slot, :cached_layout_shape, :cached_w_class, :cached_ivar_slot\n")
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, operator, value)
        @doc = 15
        @name = name
        @operator = operator
        @value = value
        op_s = "" + operator.to_s
        @aop_code =
          if op_s == "||" || op_s == "OR_ASSIGN" then 1
          elsif op_s == "&&" || op_s == "AND_ASSIGN" then 2
          elsif op_s == "+" || op_s == "PLUS" then 3
          elsif op_s == "-" || op_s == "MINUS" then 4
          elsif op_s == "*" || op_s == "STAR" then 5
          elsif op_s == "/" || op_s == "SLASH" then 6
          elsif op_s == "%" || op_s == "PERCENT" then 7
          elsif op_s == "|" || op_s == "PIPE" then 8
          elsif op_s == "&" || op_s == "AMPERSAND" then 9
          elsif op_s == "^" || op_s == "CARET" then 10
          elsif op_s == "<<" || op_s == "LSHIFT" then 11
          elsif op_s == ">>" || op_s == "RSHIFT" then 12
          else 0
          end
        @cached_slot = -1
        @cached_layout_shape = 1
        @cached_w_class = nil
        @cached_ivar_slot = -1
        if name.is_a?(String)
          @target_kind = 1
          @target_var_name = "" + name
        elsif !name.nil? && name.doc == 9
          @target_kind = 1
          @target_var_name = "" + name.name.to_s
        elsif !name.nil? && name.doc == 27
          @target_kind = 2
          @target_var_name = "" + name.name.to_s
        else
          @target_kind = 0
          @target_var_name = ""
        end
      end
    RUBY
  when %r{/ast/var\.rb\z}
    body = body.sub("    attr_accessor :name\n",
                    "    attr_accessor :name, :var_kind, :cached_top_slot, :cached_const_val, :cached_const_epoch\n")
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(name)
        @doc = 9
        s = "" + name.to_s
        @name = s
        @var_kind = s == "self" ? 1 : (s == "clock" ? 2 : 0)
        @cached_slot = -1
        @cached_layout_shape = 1
        @cached_miss_shape = 0
        @cached_top_slot = -1
        @cached_const_val = nil
        @cached_const_epoch = -1
        @cached_dispatch_owner = nil
        @cached_dispatch_version = 0
        @cached_w_method = nil
      end
    RUBY
    replace_method(body, "constant?", <<~RUBY)
      def constant?
        false
      end
    RUBY
  when %r{/ast/keywords/if\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(condition, a_then, a_else = nil)
        @doc = 10
        @condition = condition
        @then_block = a_then
        @else_block = a_else
      end
    RUBY
  when %r{/ast/keywords/def\.rb\z}
    body = body.sub("    attr_accessor :instances, :owner\n",
                    "    attr_accessor :instances, :owner\n    attr_accessor :stage0_param_names, :accessor_kind, :accessor_ivar, :cached_w_class, :cached_ivar_slot, :frame_shape, :frame_slot_count, :frame_block_slot, :frame_slot_map\n")
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(name, args, body, receiver = nil, block = nil, yields = nil, splat_index = nil, double_splat = nil)
        @doc = 12
        @name = name ? ("" + name.to_s) : nil
        @args = args || []
        @body = body
        @receiver = receiver
        @block = block
        @splat_index = splat_index
        @double_splat = double_splat
        @accessor_kind = 0
        @accessor_ivar = ""
        @cached_w_class = nil
        @cached_ivar_slot = -1
        @frame_shape = 0
        @frame_slot_count = 1
        @frame_block_slot = 0
        @frame_slot_map = nil
        @stage0_param_names = [""]
        @stage0_param_names.clear
        if @args
          i = 0
          while i < @args.length
            @stage0_param_names.push("" + @args[i].name.to_s)
            i += 1
          end
        end
      end
    RUBY
    body = replace_method(body, "mangled_name", <<~RUBY)
      def mangled_name
        0
      end
    RUBY
    body = replace_method(body, "self.mangled_name", <<~RUBY)
      def self.mangled_name(owner, name, arg_types)
        0
      end
    RUBY
    body = replace_method(body, "add_instance", <<~RUBY)
      def add_instance(a_def)
        nil
      end
    RUBY
    replace_method(body, "lookup_instance", <<~RUBY)
      def lookup_instance(arg_types)
        nil
      end
    RUBY
  when %r{/ast/keywords/while\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class While < Node
          attr_accessor :condition, :body, :check_first

          def initialize(condition, body = nil, check_first = true)
            @doc = 11
            @condition = condition
            @body = List.from(body)
            @check_first = check_first
          end
        end

        class Until < While
          def initialize(condition, body = nil, check_first = true)
            @doc = 58
            @condition = condition
            @body = List.from(body)
            @check_first = check_first
          end
        end
      end
    RUBY
  when %r{/ast/keywords/return\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class Return < KeywordValue
          attr_accessor :value

          def initialize(value)
            @doc = 14
            @value = value
          end
        end
      end
    RUBY
  when %r{/ast/keywords/when\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(conditions, body)
        @conditions = conditions
        @body = body || Nil.new
        @splat = nil
        @single = nil
      end
    RUBY
  when %r{/ast/match\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(pattern, flags)
        @pattern = RegexLiteral.new(pattern)
      end
    RUBY
  when %r{/ast/unary_op\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(operator, right)
        @doc = 56
        @operator = operator.to_sym
        @right = right
      end
    RUBY
  else
    body
  end
end

def stage0_parser_compat(body)
  return stage0_parser_source if ENV["SPINEL_STAGE0_FULL_RUBY_INTERPRETER"] == "1" &&
                                 ENV["SPINEL_STAGE0_FULL_REAL_PARSER"] != "1"

  body = body.gsub(/^\s*def parse_continue = .*\n/, "    def parse_continue\n      Nil.new\n    end\n")
  body = body.gsub(/^\s*def parse_load\s*=.*\n/, "    def parse_load\n      Nil.new\n    end\n")
  body = body.gsub("parse_expression(allow_multi_assign: true)", "parse_expression(true)")
  body = body.gsub("parse_expression(allow_multi_assign: false)", "parse_expression(false)")
  body = replace_method(body, "self.parse", <<~RUBY)
    def self.parse(str = "")
      Parser.new(str.to_s).parse
    end
  RUBY
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize(str = "")
      str = str.to_s
      @source = ""
      @source = str
      @token = Token.new
      @lexer_adapter = CodepointLexer.new(@source)
      @assigning = []
      @method = {}
      @unclosed = []
      @scopes = [Set.new]
      @in_class_body = false
      @nested_methods = 0
    end
  RUBY
  body = replace_method(body, "file=", <<~RUBY)
    def file=(path)
      @file = 0
    end
  RUBY
  body = replace_method(body, "error", <<~RUBY)
    def error(msg)
      # Stage0/C-compiler: raise a bare message. The C compiler can't lower
      # the err.location=/source_code=/file_path= setters on the Error object
      # (CallNode `location=` -> "unsupported call"), and valid
      # compiler/tungsten.w shouldn't trigger parse errors anyway, so the
      # rich-metadata Error is unnecessary here.
      row = @token.row || 1
      col = @token.col || 1
      raise "syntax on line " + row.to_s + ": " + msg.to_s
    end
  RUBY
  body = replace_method(body, "parse", <<~RUBY)
    def parse
      next_token
      if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
        File.write("/tmp/tungsten-stage0-parser-debug.txt",
                   "source_length=" + @source.length.to_s + "\n" +
                   "first_token_type=" + @token.type.to_s + "\n" +
                   "first_token_value=" + @token.value.to_s + "\n")
      end
      parse_expressions
    end
  RUBY
  body = replace_method(body, "parse_expressions", <<~RUBY)
    def parse_expressions
      parse_statement_list(false)
    end
  RUBY
  body = replace_method(body, "parse_body", <<~RUBY)
    def parse_body
      List.new
    end
  RUBY
  body = replace_method(body, "parse_continuation_call", <<~RUBY)
    def parse_continuation_call(receiver, consume_self = false)
      receiver
    end
  RUBY
  body = replace_method(body, "finish_statement_expression", <<~RUBY)
    def finish_statement_expression(exp)
      exp
    end
  RUBY
  body = replace_method(body, "parse_expression", <<~RUBY)
    def parse_expression(allow_multi_assign = false)
      parse_statement
    end
  RUBY
  body = replace_method(body, "parse_assignment", <<~RUBY)
    def parse_assignment(allow_ops = true, allow_suffix = true)
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_expression_suffix", <<~RUBY)
    def parse_expression_suffix(exp, start_row = 0)
      exp
    end
  RUBY
  body = replace_method(body, "parse_assignment_no_control", <<~RUBY)
    def parse_assignment_no_control(allow_ops = true, allow_suffix = true)
      check_void
      parse_assignment(allow_ops, allow_suffix)
    end
  RUBY
  body = replace_method(body, "parse_condition", <<~RUBY)
    def parse_condition
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_ternary", <<~RUBY)
    def parse_ternary
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_range", <<~RUBY)
    def parse_range
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_pipeline", <<~RUBY)
    def parse_pipeline
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_pipeline_tail", <<~RUBY)
    def parse_pipeline_tail(left)
      left
    end
  RUBY
  body = replace_method(body, "pipe_target", <<~RUBY)
    def pipe_target(left, target)
      left
    end
  RUBY
  body = replace_method(body, "parse_in_test", <<~RUBY)
    def parse_in_test
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_binary_operators", <<~RUBY)
    def parse_binary_operators(left, min_prec = 0)
      left
    end
  RUBY
  body = replace_method(body, "parse_shift", <<~RUBY)
    def parse_shift
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_logical_or", <<~RUBY)
    def parse_logical_or
      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_statement_continuations", <<~RUBY)
    def parse_statement_continuations(exp)
      exp
    end
  RUBY
  body = replace_method(body, "parse_block", <<~RUBY)
    def parse_block(same_line = 0)
      if @token.type?(:"{")
        return nil if same_line != 0 && @token.row != same_line
        parse_block_inline
      elsif @token.type?(:"->")
        parse_block_multiline
      else
        nil
      end
    end
  RUBY
  body = replace_method(body, "parse_call_args", <<~RUBY)
    def parse_call_args
      []
    end
  RUBY
  body = replace_method(body, "scan_word_array_body", <<~RUBY)
    def scan_word_array_body
      []
    end
  RUBY
  body = replace_method(body, "self.parse_operator", <<~RUBY)
    def self.parse_operator(name, next_op, node, operators, right_assoc = false)
      nil
    end
  RUBY
  %w[
    parse_expression_suffix parse_assignment_no_control parse_assignment parse_ternary parse_range parse_pipeline
    parse_pipeline_tail pipe_target parse_in_test parse_shift parse_logical_or parse_unary parse_negation
    parse_atomic_with_method parse_atomic_method_suffix parse_atomic parse_array_literal parse_raise
    parse_exception_handler parse_continue parse_alias parse_in parse_is parse_trait parse_load parse_use parse_with
    parse_on_guard parse_target_or parse_target_and parse_target_not parse_target_primary parse_global_path
    parse_word_array parse_symbol_array parse_case parse_when_chain parse_when_clauses parse_when_clause_body
    parse_arrow_case_body parse_hash_literal parse_super parse_module parse_class parse_data_declaration parse_method
    parse_fn parse_lambda_with_arity parse_method_reset parse_method_internal parse_anonymous_lambda
    parse_method_arg parse_block_arg parse_method_name parse_arg_name parse_grouped_expression parse_var_or_call
    parse_set_literal_after_first parse_multiset_literal_after_first
    parse_block parse_block_inline parse_block_multiline parse_if parse_unless parse_loop parse_loop_forever
    parse_yield parse_block_call parse_return parse_break parse_next parse_quantity_token
    parse_measurement_token parse_measured_quantity_token number_node_for concise_uncertainty
  ].each do |name|
    body = replace_method(body, name, <<~RUBY)
      def #{name}
        Nil.new
      end
    RUBY
  end
  %w[parse_call_args parse_method_args].each do |name|
    body = replace_method(body, name, <<~RUBY)
      def #{name}
        []
      end
    RUBY
  end
  body = replace_method(body, "consume", <<~RUBY)
    def consume(token)
      consume_one(token)
    end
  RUBY
  body = replace_method(body, "unexpected", <<~RUBY)
    def unexpected(msg = nil, token = @token)
      if msg
        error "unexpected token"
      else
        error "unexpected token"
      end
    end
  RUBY
  body = body.gsub("check_for(*VALID_METHOD_NAMES)", "check_for_valid_method_name_type")
  body = replace_method(body, "check_for", <<~RUBY)
    def check_for(type)
      return if @token.type?(type)

      error "expecting token"
    end
  RUBY
  body = replace_method(body, "check_valid_method_name", <<~RUBY)
    def check_valid_method_name
      nil
    end
  RUBY
  body = replace_method(body, "looks_like_param_types_ahead?", <<~RUBY)
    def looks_like_param_types_ahead?
      false
    end
  RUBY
  body = replace_method(body, "looks_like_return_type_ahead?", <<~RUBY)
    def looks_like_return_type_ahead?
      false
    end
  RUBY
  body = replace_method(body, "detect_accumulator_name", <<~RUBY)
    def detect_accumulator_name(node)
      nil
    end
  RUBY
  body = replace_method(body, "generate_positional_args", <<~RUBY)
    def generate_positional_args(arity)
      nil
    end
  RUBY
  body = replace_method(body, "soft_identifier_keyword?", <<~RUBY)
    def soft_identifier_keyword?
      false
    end
  RUBY
  body = replace_method(body, "identifier_name_token?", <<~RUBY)
    def identifier_name_token?
      @token.type?(:ID)
    end
  RUBY
  body = replace_method(body, "label_colon_ahead?", <<~RUBY)
    def label_colon_ahead?
      false
    end
  RUBY
  body = replace_method(body, "keyword_label_token?", <<~RUBY)
    def keyword_label_token?
      false
    end
  RUBY
  body = replace_method(body, "named_label_token?", <<~RUBY)
    def named_label_token?
      false
    end
  RUBY
  body = replace_method(body, "with_loop_start?", <<~RUBY)
    def with_loop_start?
      false
    end
  RUBY
  body = replace_method(body, "looks_like_hash?", <<~RUBY)
    def looks_like_hash?
      false
    end
  RUBY
  body = replace_method(body, "check_void", <<~RUBY)
    def check_void
      nil
    end
  RUBY
  body = replace_method(body, "check_void_value", <<~RUBY)
    def check_void_value(value)
      nil
    end
  RUBY
  body = replace_method(body, "end_token?", <<~RUBY)
    def end_token?
      @token.type?(:EOF)
    end
  RUBY
  body = replace_method(body, "call_arg_start?", <<~RUBY)
    def call_arg_start?
      false
    end
  RUBY
  body = replace_method(body, "spaced_call_arg_end?", <<~RUBY)
    def spaced_call_arg_end?
      true
    end
  RUBY
  body = replace_method(body, "raw_whitespace_byte?", <<~RUBY)
    def raw_whitespace_byte?(byte)
      byte >= 0 && (byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12)
    end
  RUBY
  body = replace_method(body, "first_child_with_location", <<~RUBY)
    def first_child_with_location(node)
      nil
    end
  RUBY
  body = replace_method(body, "open", <<~RUBY)
    def open(name)
      nil
    end
  RUBY
  body = replace_method(body, "push_var", <<~RUBY)
    def push_var(node)
      node
    end
  RUBY
  body = replace_method(body, "push_var_name", <<~RUBY)
    def push_var_name(name)
      nil
    end
  RUBY
  body = replace_method(body, "var?", <<~RUBY)
    def var?(name)
      false
    end
  RUBY
  body = replace_method(body, "var_in_scope?", <<~RUBY)
    def var_in_scope?(name)
      false
    end
  RUBY
  body = replace_method(body, "with_indent", <<~RUBY)
    def with_indent
      List.new
    end
  RUBY
  body = replace_method(body, "with_isolated_scope", <<~RUBY)
    def with_isolated_scope(create_scope = true)
      nil
    end
  RUBY
  body = replace_method(body, "with_lexical_scope", <<~RUBY)
    def with_lexical_scope
      nil
    end
  RUBY
  body = body.gsub(/(?<!def )\bparse_assignment_no_control\b(?!\s*\()/, "parse_assignment_no_control(true, true)")
  body = insert_before_private(body, <<~RUBY)

      def check_for_valid_method_name_type
        check_valid_method_name
      end

      def check_for_any_name
        return if @token.type?(:ID)
        return if @token.type?(:NAME)
        return if @token.type?(:KEYWORD)

        error "expecting name"
      end

      def consume_one(token)
        error "expected token" unless @token.type?(token)
        next_token
      end

      def skip_spaces
        while @token.type?(:SP)
          next_token
        end
      end

      def skip_collection_whitespace
        while @token.type?(:SP) || @token.type?(:NL) || @token.type?(:INDENT) || @token.type?(:DEDENT)
          next_token
        end
      end

      def skip_statement_separators
        while @token.type?(:SP) || @token.type?(:NL) || @token.type?(:";") || @token.type?(:INDENT)
          next_token
        end
      end

      def keyword_value?(name)
        @token.value.to_s == name
      end

      def binary_operator?
        return true if keyword_value?("in")
        return true if @token.type?(:+)
        return true if @token.type?(:-)
        return true if @token.type?(:*)
        return true if @token.type?(:/)
        return true if @token.type?(:%)
        return true if @token.type?(:>)
        return true if @token.type?(:<)
        return true if @token.type?(:>=)
        return true if @token.type?(:<=)
        return true if @token.type?(:==)
        return true if @token.type?(:"!=")
        return true if @token.type?(:"||")
        return true if @token.type?(:"&&")
        false
      end

      def parse_statement_list(stop_at_else)
        list = List.new
        until @token.type?(:EOF)
          if ENV["TUNGSTEN_STAGE0_STATEMENT_TRACE"] == "1"
            File.write("/tmp/tungsten-stage0-statement-trace",
                       @token.file.to_s + ":" + @lexer_adapter.pos.to_s + ":" + @token.type.to_s + ":" + @token.value.to_s)
          end
          skip_statement_separators
          break if @token.type?(:EOF)
          break if @token.type?(:DEDENT)
          if stop_at_else
            break if keyword_value?("else")
          end
          before_pos = @lexer_adapter.pos
          list.push(parse_statement)
          if @lexer_adapter.pos == before_pos
            if !@token.type?(:EOF)
              next_token
            end
          end
        end
        list
      end

      def parse_indented_block
        while @token.type?(:NL)
          next_token
        end
        while @token.type?(:SP) || @token.type?(:INDENT)
          next_token
        end
        body_col = @token.col
        block = List.new
        until @token.type?(:EOF)
          if ENV["TUNGSTEN_STAGE0_STATEMENT_TRACE"] == "1"
            File.write("/tmp/tungsten-stage0-statement-trace",
                       @token.file.to_s + ":block:" + @lexer_adapter.pos.to_s + ":" + @token.type.to_s + ":" + @token.value.to_s)
          end
          # Skip blank lines: consecutive NLs or comment-only lines
          # mid-body shouldn't terminate the block. The col of a bare
          # NL token is the column the NL was emitted at (often 1),
          # which would otherwise trigger the col<body_col break below
          # and prematurely end the block.
          while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT) || @token.type?(:DEDENT)
            next_token
          end
          break if @token.type?(:EOF)
          break if @token.col < body_col
          before_pos = @lexer_adapter.pos
          block.push(parse_statement)
          if @lexer_adapter.pos == before_pos
            if !@token.type?(:EOF)
              next_token
            end
          end
          while @token.type?(:DEDENT)
            next_token
          end
          while @token.type?(:SP) || @token.type?(:INDENT)
            next_token
          end
          if @token.type?(:NL)
            next_token
            while @token.type?(:SP) || @token.type?(:INDENT)
              next_token
            end
          end
        end
        if @token.type?(:DEDENT)
          next_token
        end
        block
      end

      def parse_statement
        skip_spaces
        if keyword_value?("if")
          return parse_stage0_if
        end
        if keyword_value?("while")
          return parse_stage0_while
        end
        if keyword_value?("return")
          return parse_stage0_return
        end
        if keyword_value?("use")
          return parse_stage0_use
        end
        if keyword_value?("begin")
          return parse_stage0_begin
        end
        if keyword_value?("case")
          return parse_stage0_case
        end
        if keyword_value?("class")
          return parse_stage0_class
        end
        if @token.type?(:+)
          return parse_stage0_class
        end
        if @token.type?(:"->")
          return parse_stage0_def
        end
        parse_assignment_or_expression
      end

      def parse_stage0_case
        loc_file = @token.file
        loc_row = @token.row
        loc_col = @token.col
        next_token
        skip_spaces

        receiver = nil
        if !@token.type?(:NL) && !@token.type?(:EOF)
          receiver = parse_binary_expression
        end
        while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT) || @token.type?(:DEDENT)
          next_token
        end

        whens = List.new
        else_body = List.new

        # Tungsten's compact value-case form uses `condition => value` and a
        # bare `=> value` default arm. Build the same [conditions, body] pairs
        # as the Ruby-style `when` form so both syntaxes share evaluation.
        if !keyword_value?("when") && !keyword_value?("else")
          arrow_done = false
          while !arrow_done && !@token.type?(:EOF)
            default_arm = @token.type?(:"=>")
            conditions = List.new
            if !default_arm
              conditions.push(parse_binary_expression)
              skip_spaces
              if !@token.type?(:"=>")
                arrow_done = true
              end
            end
            if !arrow_done
              next_token
              skip_spaces
              body = List.new
              if @token.type?(:NL) || @token.type?(:INDENT)
                body = parse_indented_block
              else
                body.push(parse_statement)
              end
              if default_arm
                else_body = body
                arrow_done = true
              else
                pair = List.new
                pair.push(conditions)
                pair.push(body)
                whens.push(pair)
                while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT) || @token.type?(:DEDENT)
                  next_token
                end
              end
            end
          end
        else
          first_when = true
          while keyword_value?("when") && (@token.col == loc_col || (first_when && @token.col <= loc_col))
            first_when = false
            next_token
            skip_spaces
            conditions = List.new
            conditions.push(parse_binary_expression)
            skip_spaces
            while @token.type?(:",")
              next_token
              skip_spaces
              conditions.push(parse_binary_expression)
              skip_spaces
            end

            body = List.new
            if keyword_value?("then")
              next_token
              skip_spaces
              body.push(parse_statement)
            elsif @token.type?(:NL) || @token.type?(:INDENT)
              body = parse_indented_block
            else
              body.push(parse_statement)
            end

            pair = List.new
            pair.push(conditions)
            pair.push(body)
            whens.push(pair)
            while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT) || @token.type?(:DEDENT)
              next_token
            end
          end

          if keyword_value?("else") && @token.col == loc_col
            next_token
            skip_spaces
            if @token.type?(:NL) || @token.type?(:INDENT)
              else_body = parse_indented_block
            else
              else_body.push(parse_statement)
            end
          end
        end

        node = CaseExpr.new(receiver, whens, else_body)
        node.set_location(loc_file, loc_row, loc_col)
        node
      end

      def parse_stage0_begin
        begin_col = @token.col
        next_token
        body = parse_indented_block
        # Skip rescue clauses (and their bodies) — stage0 just runs the body.
        while keyword_value?("rescue") && @token.col == begin_col
          next_token
          # Optional rescue var (e.g. "rescue err"), and class list.
          while !@token.type?(:NL) && !@token.type?(:EOF)
            next_token
          end
          parse_indented_block
        end
        if keyword_value?("ensure") && @token.col == begin_col
          next_token
          parse_indented_block
        end
        Begin.new(body)
      end

      def parse_stage0_if
        if_col = @token.col
        next_token
        condition = parse_binary_expression
        then_block = parse_indented_block
        while !@token.type?(:EOF) && @token.col > if_col
          next_token
        end
        else_block = List.new
        # Only consume an elsif/else when it lines up with this if's column;
        # otherwise it belongs to an enclosing scope and parse_indented_block's
        # break-on-elsif/else has already returned us there.
        if keyword_value?("elsif") && @token.col == if_col
          else_block = parse_stage0_elsif_tail(if_col)
        elsif keyword_value?("else") && @token.col == if_col
          next_token
          else_block = parse_indented_block
        end
        If.new(condition, then_block, else_block)
      end

      def parse_stage0_elsif_tail(if_col)
        next_token
        condition = parse_binary_expression
        then_block = parse_indented_block
        while !@token.type?(:EOF) && @token.col > if_col
          next_token
        end
        else_block = List.new
        if keyword_value?("elsif") && @token.col == if_col
          else_block = parse_stage0_elsif_tail(if_col)
        elsif keyword_value?("else") && @token.col == if_col
          next_token
          else_block = parse_indented_block
        end
        If.new(condition, then_block, else_block)
      end

      def parse_stage0_while
        next_token
        condition = parse_binary_expression
        body = parse_indented_block
        While.new(condition, body, true)
      end

      def parse_stage0_return
        next_token
        Return.new(parse_binary_expression)
      end

      def parse_stage0_use
        source_len = @source.bytesize
        path_start = @lexer_adapter.pos
        while path_start < source_len
          b = @source.getbyte(path_start)
          break unless b == 32 || b == 9

          path_start += 1
        end
        line_end = path_start
        while line_end < source_len
          b = @source.getbyte(line_end)
          break if b == 10 || b == 13

          line_end += 1
        end
        path = "" + @source.byteslice(path_start, line_end - path_start).to_s
        comment_pos = path.index("#")
        if comment_pos != nil
          path = "" + path.byteslice(0, comment_pos).to_s
        end
        while path.length > 0
          tail = path.getbyte(path.length - 1)
          break unless tail == 32 || tail == 9

          path = "" + path.byteslice(0, path.length - 1).to_s
        end
        if path.length >= 2
          first = path.byteslice(0, 1)
          last = path.byteslice(path.length - 1, 1)
          if (first == "\"" && last == "\"") || (first == "'" && last == "'")
            path = "" + path.byteslice(1, path.length - 2).to_s
          end
        end
        @lexer_adapter.pos = line_end
        next_token
        Use.new(path)
      end

      def parse_stage0_class
        next_token
        skip_spaces
        name = ""
        superclass = ""
        if @token.type?(:ID)
          name = @token.value
          next_token
        end
        skip_spaces
        if @token.type?(:<)
          next_token
          skip_spaces
          if @token.type?(:ID)
            superclass = @token.value
            next_token
          end
        end
        body = parse_indented_block
        ClassDef.new(name, body, superclass)
      end

      def parse_stage0_def
        next_token
        skip_spaces
        name = ""
        if @token.type?(:ID)
          name = @token.value
          next_token
        end
        if @token.type?(:"?")
          name = name + "?"
          next_token
        elsif @token.type?(:"!")
          name = name + "!"
          next_token
        end
        params = List.new
        ivar_assigns = List.new
        if @token.type?(:"(")
          next_token
          until @token.type?(:EOF) || @token.type?(:")")
            skip_spaces
            if @token.type?(:ID)
              params.push(Arg.new(@token.value))
              next_token
            elsif @token.type?(:IVAR)
              ivar_name = @token.value.to_s
              param_name = ivar_name.slice(1, ivar_name.length - 1)
              params.push(Arg.new(param_name))
              ivar_assigns.push(Assign.new(InstanceVar.new(ivar_name), Var.new(param_name), nil))
              next_token
            elsif @token.type?(:",")
              next_token
            else
              next_token
            end
          end
          if @token.type?(:")")
            next_token
          end
        end
        body = parse_indented_block
        if ivar_assigns.length > 0
          new_body = List.new
          i = 0
          while i < ivar_assigns.length
            new_body.push(ivar_assigns[i])
            i += 1
          end
          i = 0
          while i < body.length
            new_body.push(body[i])
            i += 1
          end
          body = new_body
        end
        Def.new(name, params, body)
      end

      def parse_assignment_or_expression
        skip_spaces
        if @token.type?(:IVAR)
          target = InstanceVar.new(@token.value)
          next_token
          skip_spaces
          if @token.type?(:"=")
            next_token
            value = parse_binary_expression
            return Assign.new(target, value)
          end
          if @token.type?(:"+=")
            next_token
            value = parse_binary_expression
            return AssignOp.new(target, :+, value)
          end
          return parse_binary_expression_from(parse_postfix(target))
        end
        if @token.type?(:ID)
          name = @token.value
          next_token
          if @token.type?(:"?")
            name = name + "?"
            next_token
          elsif @token.type?(:"!")
            name = name + "!"
            next_token
          end
          skip_spaces
          if @token.type?(:"=")
            next_token
            value = parse_binary_expression
            return Assign.new(name, value)
          end
          if @token.type?(:"+=")
            next_token
            value = parse_binary_expression
            return Assign.new(name, BinaryOp.new(Var.new(name), :+, value), nil)
          end
          if @token.type?(:"(")
            return parse_call_after_name(name)
          end
          if name == "exit"
            args = List.new
            if !@token.type?(:NL)
              if !@token.type?(:EOF)
                args.push(parse_binary_expression)
              end
            end
            return Call.new(nil, name, args)
          end
          postfixed = parse_postfix(Var.new(name))
          skip_spaces
          if @token.type?(:"=") && postfixed.is_a?(Call) && postfixed.name == "[]"
            next_token
            new_args = List.new
            i = 0
            while i < postfixed.args.length
              new_args.push(postfixed.args[i])
              i += 1
            end
            new_args.push(parse_binary_expression)
            return Call.new(postfixed.obj, "[]=", new_args)
          end
          return parse_binary_expression_from(postfixed)
        end
        parse_binary_expression
      end

      def parse_call_after_name(name)
        args = List.new
        if @token.type?(:"(")
          next_token
          until @token.type?(:EOF) || @token.type?(:")")
            skip_spaces
            args.push(parse_binary_expression)
            skip_spaces
            if @token.type?(:",")
              next_token
            end
          end
          if @token.type?(:")")
            next_token
          end
        end
        Call.new(nil, name, args)
      end

      def parse_postfix(left)
        loop do
          skip_spaces
          if @token.type?(:".")
            next_token
            skip_spaces
            name = ""
            if @token.type?(:ID)
              name = @token.value
              next_token
            elsif @token.type?(:KEYWORD)
              name = @token.value
              next_token
            end
            if @token.type?(:"?")
              name = name + "?"
              next_token
            elsif @token.type?(:"!")
              name = name + "!"
              next_token
            end
            call_args = List.new
            if @token.type?(:"(")
              next_token
              until @token.type?(:EOF) || @token.type?(:")")
                skip_spaces
                call_args.push(parse_binary_expression)
                skip_spaces
                if @token.type?(:",")
                  next_token
                end
              end
              if @token.type?(:")")
                next_token
              end
            end
            left = Call.new(left, name, call_args)
          elsif @token.type?(:"[")
            next_token
            index_args = List.new
            until @token.type?(:EOF) || @token.type?(:"]")
              skip_spaces
              index_args.push(parse_binary_expression)
              skip_spaces
              if @token.type?(:",")
                next_token
              end
            end
            if @token.type?(:"]")
              next_token
            end
            left = Call.new(left, "[]", index_args)
          else
            break
          end
        end
        left
      end

      def parse_binary_expression
        # Top level chains && / || with lowest precedence; non-logical
        # binary ops (==, !=, +, -, ...) are handled by
        # parse_binary_expression_from. Without this split, `a && b != c`
        # parses left-to-right as `(a && b) != c`, which inverts the
        # semantics of compiler/tungsten.w's flag-parser guards.
        left = parse_binary_expression_from(parse_postfix(parse_primary))
        loop do
          skip_spaces
          if @token.type?(:"||") || @token.type?(:"&&")
            op = @token.type
            next_token
            right = parse_binary_expression_from(parse_postfix(parse_primary))
            left = BinaryOp.new(left, op, right)
          else
            break
          end
        end
        left
      end

      def parse_binary_expression_from(left)
        right = Nil.new
        loop do
          skip_spaces
          break if @token.type?(:"||") || @token.type?(:"&&")
          if binary_operator?
            op = @token.type
            if keyword_value?("in")
              op = :in
            end
            next_token
            right = parse_postfix(parse_primary)
            left = BinaryOp.new(left, op, right)
          else
            break
          end
        end
        left
      end

      def parse_primary
        skip_spaces
        if @token.type?(:-)
          next_token
          if @token.type?(:INT)
            value = "-" + @token.value.to_s
            next_token
            return Int.new(value)
          end
          return BinaryOp.new(Int.new(0), :-, parse_primary)
        end
        if @token.type?(:INT)
          value = @token.value
          next_token
          return Int.new(value)
        end
        if @token.type?(:STRING)
          value = @token.value
          next_token
          return StringLiteral.new(value)
        end
        if @token.type?(:SYMBOL)
          value = @token.value
          next_token
          return Symbol.new(value)
        end
        if @token.type?(:":")
          next_token
          value = ""
          if @token.type?(:ID) || @token.type?(:KEYWORD)
            value = @token.value
            next_token
          end
          return Symbol.new(value)
        end
        if @token.type?(:TRUE)
          next_token
          return Boolean.new(true)
        end
        if @token.type?(:FALSE)
          next_token
          return Boolean.new(false)
        end
        if @token.type?(:NIL)
          next_token
          return Nil.new
        end
        if keyword_value?("true")
          next_token
          return Boolean.new(true)
        end
        if keyword_value?("false")
          next_token
          return Boolean.new(false)
        end
        if keyword_value?("nil")
          next_token
          return Nil.new
        end
        if @token.type?(:"[")
          next_token
          arr_lit = ArrayLiteral.new
          until @token.type?(:EOF) || @token.type?(:"]")
            skip_collection_whitespace
            if @token.type?(:"]")
              break
            end
            arr_lit.list.push(parse_binary_expression)
            skip_collection_whitespace
            if @token.type?(:",")
              next_token
            end
          end
          if @token.type?(:"]")
            next_token
          end
          return arr_lit
        end
        if @token.type?(:"{")
          next_token
          # See parse_primary @ ~line 1689 — spinel can't naturally type
          # `entries = []` in a way that matches HashLiteral's poly_array
          # iv_entries; using List pins the container type.
          entries = List.new
          until @token.type?(:EOF) || @token.type?(:"}")
            skip_collection_whitespace
            if @token.type?(:"}")
              break
            end
            key = nil
            if @token.type?(:ID)
              key = StringLiteral.new(@token.value)
              next_token
              skip_collection_whitespace
              if @token.type?(:":")
                next_token
              end
            else
              key = parse_binary_expression
              skip_collection_whitespace
              if @token.type?(:"=>")
                next_token
              elsif @token.type?(:":")
                next_token
              end
            end
            skip_collection_whitespace
            value = parse_binary_expression
            pair = List.new
            pair.push(key)
            pair.push(value)
            entries.push(pair)
            skip_collection_whitespace
            if @token.type?(:",")
              next_token
            end
          end
          if @token.type?(:"}")
            next_token
          end
          return HashLiteral.new(entries)
        end
        if @token.type?(:ID)
          value = @token.value
          next_token
          if @token.type?(:"?")
            value = value + "?"
            next_token
          elsif @token.type?(:"!")
            value = value + "!"
            next_token
          end
          if @token.type?(:"(")
            return parse_call_after_name(value)
          end
          return Var.new(value)
        end
        if @token.type?(:IVAR)
          value = @token.value
          next_token
          return InstanceVar.new(value)
        end
        if @token.type?(:"(")
          next_token
          values = List.new
          until @token.type?(:EOF) || @token.type?(:")")
            skip_spaces
            if @token.type?(:")")
              break
            end
            values.push(parse_binary_expression)
            skip_spaces
            if @token.type?(:",")
              next_token
            end
          end
          if @token.type?(:")")
            next_token
          end
          if values.length == 1
            return values[0]
          end
          return values
          end
          if @token.type?(:"<<")
            next_token
            args = List.new
            args.push(parse_binary_expression)
            return Print.new(args)
          end
          next_token
          Nil.new
        end
  RUBY
  body
end

def stage0_parser_block_compat(body)
  body = body.gsub(/^\s*def parse_continue\s*=\s*parse_next\s*$/, "    def parse_continue\n      parse_next\n    end")
  body = body.gsub(/^\s*def parse_load\s*=\s*unexpected "load not yet implemented"\s*$/, "    def parse_load\n      unexpected \"load not yet implemented\"\n    end")
  body = body.gsub("parse_expression(allow_multi_assign: true)", "parse_expression(true)")
  body = body.gsub("parse_expression(allow_multi_assign: false)", "parse_expression(false)")
  body = body.gsub("def parse_expression(allow_multi_assign: false)", "def parse_expression(allow_multi_assign = false)")
  body = body.gsub("def parse_assignment_no_control(allow_ops: true, allow_suffix: true)", "def parse_assignment_no_control(allow_ops = true, allow_suffix = true)")
  body = body.gsub("parse_assignment(allow_ops:, allow_suffix:)", "parse_assignment(allow_ops, allow_suffix)")
  body = body.gsub("def parse_assignment(allow_ops: true, allow_suffix: true)", "def parse_assignment(allow_ops = true, allow_suffix = true)")
  body = body.gsub("def parse_continuation_call(receiver, consume_self: false)", "def parse_continuation_call(receiver, consume_self = false)")
  body = body.gsub("parse_continuation_call(exp, consume_self: true)", "parse_continuation_call(exp, true)")
  body = body.gsub("def parse_call_args(opening_consumed: false)", "def parse_call_args(opening_consumed = false)")
  body = body.gsub("parse_call_args(opening_consumed: fused_and_call)", "parse_call_args(fused_and_call)")
  body = body.gsub("def parse_block(same_line: nil)", "def parse_block(same_line = nil)")
  body = body.gsub("parse_block(same_line: start_row)", "parse_block(start_row)")
  body = body.gsub("RangeLiteral.new(exp, nil, exclusive:)", "RangeLiteral.new(exp, nil, exclusive)")
  body = body.gsub("RangeLiteral.new(exp, right, exclusive:)", "RangeLiteral.new(exp, right, exclusive)")
  body = body.gsub("parens: @last_call_parens", "0, @last_call_parens")
  body = body.gsub(/\bFloat\.new\(/, "FloatLiteral.new(")
  body = body.gsub("check(GENERIC_ARGS_AHEAD)", "generic_args_ahead?")
  body = body.gsub("check(/ in \\(/)", "string.byteslice(pos, 5) == \" in (\"")
  body = body.gsub('@token.type?(:SYMBOL) && @token.value.to_s.match?(/\A:[A-Z]/)', "capitalized_symbol_token?")
  body = body.gsub('elsif @token.type?(:ID) && @token.value == "self" && check(/\\./)', 'elsif @token.type?(:ID) && @token.value == "self" && source_byte_at(pos) == 46')
  body = body.gsub("parse_method_internal(node_class: Fn)", "parse_method_internal(true)")
  body = body.gsub("def parse_method_internal(node_class: Def)", "def parse_method_internal(fn_mode = false)")
  body = body.gsub("if node_class == Fn", "if fn_mode")
  body = body.gsub("return parse_anonymous_lambda(node_class:)", "return parse_anonymous_lambda(fn_mode)")
  body = body.gsub("def parse_anonymous_lambda(node_class: Def)", "def parse_anonymous_lambda(fn_mode = false)")
  body = body.gsub(/^[ \t]*node = node_class\.new\(base_name, args, body\)\n(?:[ \t]*node\.\w+\s*=.*\n)+[ \t]*node\.set_location\(loc_file, loc_row, loc_col\)\n\n[ \t]*node/, <<~RUBY.chomp)
      if fn_mode
        node = Fn.new(base_name, args, body)
        node.receiver     = receiver
        node.block        = block
        node.splat_index  = splat_index
        node.double_splat = double_splat
        node.param_types  = param_types
        node.return_type  = return_type
        node.set_location(loc_file, loc_row, loc_col)
        return node
      end

      node = Def.new(base_name, args, body)
      node.receiver     = receiver
      node.block        = block
      node.splat_index  = splat_index
      node.double_splat = double_splat
      node.param_types  = param_types
      node.return_type  = return_type
      node.set_location(loc_file, loc_row, loc_col)

      node
  RUBY
  body = body.gsub(/^[ \t]*node = node_class\.new\(nil, @method\[:args\]\.any\? \? @method\[:args\] : nil, body\)\n(?:[ \t]*node\.\w+\s*=.*\n)+\n[ \t]*node/, <<~RUBY.chomp)
      if fn_mode
        node = Fn.new(nil, @method[:args].any? ? @method[:args] : nil, body)
        node.block        = @method[:block]
        node.splat_index  = @method[:splat_index]
        node.double_splat = @method[:double_splat]
        return node
      end

      node = Def.new(nil, @method[:args].any? ? @method[:args] : nil, body)
      node.block        = @method[:block]
      node.splat_index  = @method[:splat_index]
      node.double_splat = @method[:double_splat]

      node
  RUBY
  body = replace_method(body, "self.parse_operator", <<~RUBY)
    def self.parse_operator(name, next_op, node, operators, right_assoc = false)
      nil
    end
  RUBY
  body = body.gsub(/^\s*parse_operator\s+:or,.*$/, <<~RUBY)
    def parse_or
      left = parse_and
      while true
        case @token.type
        when :SP
          next_token
        when :"||"
          check_void_value(left)
          next_token_skip_whitespace
          right = parse_and
          left = Or.new(left, right)
        else
          return left
        end
      end
    end
  RUBY
  body = body.gsub(/^\s*parse_operator\s+:and,.*$/, <<~RUBY)
    def parse_and
      left = parse_in_test
      while true
        case @token.type
        when :SP
          next_token
        when :"&&"
          check_void_value(left)
          next_token_skip_whitespace
          right = parse_in_test
          left = And.new(left, right)
        else
          return left
        end
      end
    end
  RUBY
  body = body.gsub(/^\s*parse_operator\s+:eql,.*$/, <<~RUBY)
    def parse_eql
      left = parse_logical_or
      while true
        case @token.type
        when :SP
          next_token
        when :"==", :"!=", :"=~", :"≈"
          check_void_value(left)
          operator = @token.type
          next_token_skip_whitespace
          right = parse_logical_or
          left = mathematical_binary(left, operator, right)
        else
          return left
        end
      end
    end
  RUBY
  body = body.gsub(/^\s*parse_operator\s+:logical_and,.*$/, <<~RUBY)
    def parse_logical_and
      left = parse_shift
      while true
        case @token.type
        when :SP
          next_token
        when :"&", :".&", :"∩"
          check_void_value(left)
          operator = @token.type
          next_token_skip_whitespace
          right = parse_shift
          left = mathematical_binary(left, operator, right)
        else
          return left
        end
      end
    end
  RUBY
  body = body.gsub(/^\s*parse_operator\s+:add_or_sub,.*$/, <<~RUBY)
    def parse_add_or_sub
      left = parse_mul_or_div
      while true
        case @token.type
        when :SP
          next_token
        when :"+", :"-", :"%+", :"%-", :".+", :".-", :"±"
          check_void_value(left)
          operator = @token.type
          next_token_skip_whitespace
          right = parse_mul_or_div
          left = mathematical_binary(left, operator, right)
        else
          return left
        end
      end
    end
  RUBY
  body = body.gsub(/^\s*parse_operator\s+:mul_or_div,.*$/, <<~RUBY)
    def parse_mul_or_div
      left = parse_pow
      while true
        case @token.type
        when :SP
          next_token
        when :"*", :"/", :"//", :"%", :"%*", :".*", :"./"
          check_void_value(left)
          operator = @token.type
          next_token_skip_whitespace
          right = parse_pow
          left = mathematical_binary(left, operator, right)
        else
          return left
        end
      end
    end
  RUBY
  body = body.gsub(/^\s*parse_operator\s+:pow,.*$/, <<~RUBY)
    def parse_pow
      left = parse_unary
      while true
        case @token.type
        when :SP
          next_token
        when :"**", :"%**", :"↑↑"
          check_void_value(left)
          operator = @token.type
          next_token_skip_whitespace
          right = parse_pow
          left = mathematical_binary(left, operator, right)
        else
          return left
        end
      end
    end
  RUBY
  body = replace_method(body, "self.parse", <<~RUBY)
    def self.parse(str = "")
      new(str.to_s).parse
    end
  RUBY
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize(str = "")
      @source = str.to_s
      @token = Token.new
      @lexer_adapter = CodepointLexer.new(@source)
      @assigning = []
      @method    = {}
      @unclosed  = []
      @scopes    = [Set.new]
      @in_class_body = false
      @namespace_prefix = nil
      @nested_methods = 0
      @no_spaced_call_args = false
      @suppress_block = false
      @last_call_parens = false
    end
  RUBY
  body = replace_method(body, "file=", <<~RUBY)
    def file=(path)
      @file = path
      @lexer_adapter.file = path if @lexer_adapter
    end
  RUBY
  body = replace_method(body, "error", <<~RUBY)
    def error(msg)
      row = @token.row || 1
      raise "syntax on line " + row.to_s + ": " + msg.to_s
    end
  RUBY
  body = replace_method(body, "next_token", <<~RUBY)
    def next_token
      @token = @lexer_adapter.next_token
    end
  RUBY
  body = replace_method(body, "pos", <<~RUBY)
    def pos
      @lexer_adapter.pos
    end
  RUBY
  body = replace_method(body, "pos=", <<~RUBY)
    def pos=(new_pos = 0)
      @lexer_adapter.pos = new_pos
    end
  RUBY
  body = replace_method(body, "string", <<~RUBY)
    def string
      @lexer_adapter.string
    end
  RUBY
  body = replace_method(body, "rest", <<~RUBY)
    def rest
      @lexer_adapter.rest
    end
  RUBY
  body = replace_method(body, "eos?", <<~RUBY)
    def eos?
      @lexer_adapter.eos?
    end
  RUBY
  body = body.sub(<<-'RUBY', <<-'RUBY')
      when :REGEX
        pattern, options = @token.value
        node_and_next_token RegexLiteral.new(pattern, options)
      when :STRING_INTERP
        parts = @token.value.map do |type, val|
          if type == :str
            StringLiteral.new(val)
          else
            Tungsten::Parser.parse_expression_fragment(val)
          end
        end
        node_and_next_token StringInterpolation.new(parts)
RUBY
      when :REGEX
        node_and_next_token RegexLiteral.new(@token.value.to_s, "")
      when :STRING_INTERP
        parts = []
        raw_parts = @token.interp_parts
        if raw_parts
          i = 0
          while i < raw_parts.length
            pair = raw_parts[i]
            part_node = nil
            if pair[0] == :str
              part_node = StringLiteral.new(pair[1].to_s)
            else
              part_node = Tungsten::Parser.parse_expression_fragment(pair[1].to_s)
            end
            parts << part_node
            i += 1
          end
        end
        node_and_next_token StringInterpolation.new(parts)
RUBY
  body = replace_method(body, "parse_logical_or", <<~RUBY)
    def parse_logical_or
      left = parse_logical_and

      while true
        case @token.type
        when :SP
          next_token
        when :∪
          next_token_skip_whitespace
          left = Call.new(left, "union", [parse_logical_and])
        when :|, :"»", :"^", :".|", :".^"
          check_void_value(left)
          method = @token.type
          next_token_skip_whitespace
          right = parse_logical_and
          left = BinaryOp.new(left, method, right)
        else
          return left
        end
      end
    end
  RUBY
  body = replace_method(body, "parse_atomic_with_method", <<~RUBY)
    def parse_atomic_with_method
      primary_type = @token.type
      atomic = parse_atomic
      if (@token.type == :"!" || @token.type == :PRIMORIAL) && pos >= 2
        prev_b = source_byte_at(pos - 2)
        if prev_b != 32 && prev_b != 9 && prev_b != 10 && prev_b != 13
          product_receiver = primary_type == :"(" ||
            ((primary_type == :INT || primary_type == :ID || primary_type == :IVAR ||
              primary_type == :CVAR || primary_type == :GLOBAL || primary_type == :PARG ||
              primary_type == :CONSTANT) &&
             (atomic.is_a?(Int) || atomic.is_a?(Var) || atomic.is_a?(InstanceVar) || atomic.is_a?(ClassVar) || atomic.is_a?(GlobalVar)) &&
             !(atomic.is_a?(Var) && atomic.name.end_with?("!")))
          if product_receiver
            name = @token.type == :"!" ? "factorial" : "primorial"
            loc_file = @token.file
            loc_row = @token.row
            loc_col = @token.col
            next_token
            atomic = Call.new(atomic, name, [])
            atomic.set_location(loc_file, loc_row, loc_col)
          end
        end
      end

      parse_atomic_method_suffix(atomic)
    end
  RUBY
  body = replace_method(body, "parse_use", <<~RUBY)
    def parse_use
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col

      s = string
      n = s.bytesize
      p = pos
      p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      if p < n && s.getbyte(p) == 34
        next_token_skip_space
        path = @token.value.to_s
        next_token
      else
        start = p
        while p < n
          b = s.getbyte(p)
          break if b == 32 || b == 9 || b == 10 || b == 13 || b == 59 || b == 35
          p += 1
        end
        path = s.byteslice(start, p - start) || ""
        self.pos = p
        next_token
      end

      node = Use.new(path)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end
  RUBY
  body = replace_method(body, "scan_word_array_body", <<~RUBY)
    def scan_word_array_body
      words = [""]
      words.clear
      s = string
      n = s.bytesize
      p = pos
      while true
        while p < n
          b = s.getbyte(p)
          break unless b == 32 || b == 9 || b == 10 || b == 13
          p += 1
        end
        error "unterminated word array" if p >= n
        if s.getbyte(p) == 93
          p += 1
          break
        end
        if s.getbyte(p) == 35
          p += 1 while p < n && s.getbyte(p) != 10
          next
        end
        w_start = p
        while p < n
          b = s.getbyte(p)
          break if b == 32 || b == 9 || b == 10 || b == 13 || b == 93 || b == 35
          p += 1
        end
        words.push(s.byteslice(w_start, p - w_start) || "")
      end
      self.pos = p
      next_token
      words
    end
  RUBY
  body = replace_method(body, "looks_like_param_types_ahead?", <<~RUBY)
    def looks_like_param_types_ahead?
      s = string
      n = s.bytesize
      p = pos
      p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      count = 0
      while p < n && s.getbyte(p) != 41
        w_start = p
        b = s.getbyte(p)
        if b >= 65 && b <= 90
          p += 1
          while p < n
            c = s.getbyte(p)
            break unless (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
            p += 1
          end
        elsif b >= 97 && b <= 122
          p += 1
          while p < n
            c = s.getbyte(p)
            break unless (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
            p += 1
          end
          word = s.byteslice(w_start, p - w_start) || ""
          return false unless Tungsten::CodepointLexer::TYPE_NAMES.key?(word)
        else
          return false
        end
        if p + 1 < n && s.getbyte(p) == 91 && s.getbyte(p + 1) == 93
          p += 2
        end
        count += 1
        p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      end
      count > 0 && p < n && s.getbyte(p) == 41
    end
  RUBY
  body = replace_method(body, "looks_like_return_type_ahead?", <<~RUBY)
    def looks_like_return_type_ahead?
      s = string
      n = s.bytesize
      p = pos
      if p + 1 < n && s.getbyte(p) == 91 && s.getbyte(p + 1) == 93
        p += 2
      end
      p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      return true if p >= n
      b = s.getbyte(p)
      b == 58 || b == 10 || b == 59
    end
  RUBY
  body = replace_method(body, "with_loop_start?", <<~RUBY)
    def with_loop_start?
      return false unless @token.keyword?(:with)
      s = string
      n = s.bytesize
      p = pos
      return false unless p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      return false if p >= n
      while p < n
        b = s.getbyte(p)
        break if b == 32 || b == 9 || b == 10 || b == 13
        p += 1
      end
      return false unless p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
      return false unless p + 2 <= n && s.byteslice(p, 2) == "in"
      after = p + 2 < n ? s.getbyte(p + 2) : 32
      after == 32 || after == 9 || after == 10 || after == 40
    end
  RUBY
  body = replace_method(body, "looks_like_hash?", <<~RUBY)
    def looks_like_hash?
      return false unless @token.type?(:"{")
      s = string
      n = s.bytesize
      p = pos
      p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9 || s.getbyte(p) == 10 || s.getbyte(p) == 13)
      return false if p >= n
      b = s.getbyte(p)
      return true if b == 125
      if b == 34
        p += 1
        while p < n && s.getbyte(p) != 34
          p += 1 if s.getbyte(p) == 92
          p += 1
        end
        return false if p >= n
        p += 1
        p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
        return p < n && s.getbyte(p) == 58
      elsif (b >= 97 && b <= 122) || b == 95
        p += 1
        while p < n
          c = s.getbyte(p)
          break unless (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
          p += 1
        end
        p += 1 while p < n && (s.getbyte(p) == 32 || s.getbyte(p) == 9)
        return p < n && s.getbyte(p) == 58
      end
      false
    end
  RUBY
  body = replace_method(body, "parse_class", <<~RUBY)
    def parse_class
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace

      check_for :NAME, :CONSTANT, :ID, :TYPE

      name = @token.value
      next_token_skip_space

      if capitalized_symbol_token?
        while capitalized_symbol_token?
          name = AST.intern_name("\#{name}:\#{AST.intern_name_without_prefix(@token.value, ":")}")
          next_token_skip_space
        end
      end
      name = AST.intern_name("\#{@namespace_prefix}:\#{name}") if @namespace_prefix && !name.to_s.include?(":")

      if @token.type?(:"<") && generic_args_ahead?
        next_token until @token.type?(:">") || @token.type?(:NL) || @token.type?(:EOF)
        consume :">"
        skip_space
      end

      superclass = nil
      class_role = nil

      if @token.type?(:"[")
        next_token_skip_space
        check_for :NAME, :CONSTANT, :ID, :TYPE
        class_role = @token.value
        next_token_skip_space
        check_for(:"]")
        next_token_skip_space
      end

      if @token.type?(:"<")
        next_token_skip_space
        check_for :NAME, :CONSTANT, :ID, :TYPE
        superclass = @token.value
        next_token_skip_space
        if @token.type?(:"<") && generic_args_ahead?
          next_token until @token.type?(:">") || @token.type?(:NL) || @token.type?(:EOF)
          consume :">"
          skip_space
        end
      end

      if @token.type?(:"[") && class_role.nil?
        next_token_skip_space
        check_for :NAME, :CONSTANT, :ID, :TYPE
        class_role = @token.value
        next_token_skip_space
        check_for(:"]")
        next_token_skip_space
      end

      skip_statement_end

      previous_in_class_body = @in_class_body
      @in_class_body = true
      if @token.type?(:INDENT)
        body = with_indent { parse_body }
      else
        body = List.new
      end
      @in_class_body = previous_in_class_body

      node = ClassDef.new(name, body, superclass, class_role)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end
  RUBY
  body = replace_method(body, "parse_data_declaration", <<~RUBY)
    def parse_data_declaration
      next_token_skip_space
      return Nil.new unless @token.type?(:ID) || @token.type?(:TYPE)

      kind = @token.value.to_s
      next_token_skip_space
      if @token.type?(:"(")
        next_token_skip_space
        check_for :NAME, :CONSTANT, :ID, :TYPE
        next_token_skip_space
        check_for :")"
        next_token_skip_space
      end
      skip_statement_end

      return Nil.new unless @token.type?(:INDENT)

      fields = [""]
      fields.clear
      line = [""]
      line.clear

      depth = 0
      loop do
        case @token.type
        when :INDENT
          depth += 1
        when :DEDENT
          if kind == "data" && !line.empty?
            if line[0] == "field" && line.length > 1
              fields.push(line[1])
            end
          end
          line.clear
          depth -= 1
          next_token
          break if depth <= 0
          next
        when :NL
          if depth > 0
            if kind == "data" && !line.empty?
              if line[0] == "field" && line.length > 1
                fields.push(line[1])
              end
            end
            line.clear
          end
        else
          if depth > 0 && @token.value
            line.push(@token.value.to_s)
          end
        end

        next_token
      end

      if kind == "data" && !fields.empty?
        sym_args = []
        i = 0
        while i < fields.length
          sym_args.push(Symbol.new(fields[i]))
          i += 1
        end
        return Call.new(nil, "ro", sym_args)
      end

      Nil.new
    end
  RUBY
  body = replace_method(body, "parse_case", <<~RUBY)
    def parse_case
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_space

      conditionless = @token.type?(:NL) || @token.type?(:";")
      receiver = conditionless ? nil : parse_assignment_no_control
      skip_statement_end

      whens = []
      else_body = nil

      if @token.keyword?(:when)
        whens, else_body = parse_when_clauses
      elsif !conditionless && @token.type?(:INDENT)
        consume :INDENT
        if @token.keyword?(:when)
          whens, else_body = parse_when_clauses
        else
          whens, else_body = parse_arrow_case_clauses
        end
        consume :DEDENT unless @token.type?(:EOF)
      else
        whens, else_body = parse_arrow_case_clauses
      end

      node = CaseExpr.new(receiver, whens, else_body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def case_arrow_stop?
      @token.type?(:DEDENT) || @token.type?(:EOF) || @token.type?(:")") ||
        @token.type?(:"]") || @token.type?(:"}") || @token.type?(:",")
    end

    def parse_arrow_case_clauses
      whens = []
      else_body = nil
      until case_arrow_stop?
        skip_statement_end
        break if case_arrow_stop?

        if @token.type?(:"=>")
          next_token_skip_space
          else_body = parse_arrow_case_body
        else
          conditions = [parse_expression]
          while @token.comma?
            next_token_skip_whitespace
            conditions << parse_expression
          end
          skip_space
          consume :"=>"
          skip_space
          body = parse_arrow_case_body
          whens << [conditions, body]
        end
      end
      [whens, else_body]
    end
  RUBY
  body = replace_method(body, "check_for", <<~RUBY)
    def check_for(a, b = nil, c = nil, d = nil, *rest)
      return if @token.type?(a)
      return if b && @token.type?(b)
      return if c && @token.type?(c)
      return if d && @token.type?(d)
      return if rest && rest.include?(@token.type)

      error "expecting token"
    end
  RUBY
  body = replace_method(body, "consume", <<~RUBY)
    def consume(a, b = nil, c = nil, d = nil)
      check_for(a)
      next_token
      if b
        check_for(b)
        next_token
      end
      if c
        check_for(c)
        next_token
      end
      if d
        check_for(d)
        next_token
      end
    end
  RUBY
  body = replace_method(body, "unexpected", <<~RUBY)
    def unexpected(msg = nil)
      if msg
        error msg.to_s
      else
        error "unexpected token"
      end
    end
  RUBY
  body = replace_method(body, "parse_expression", <<~RUBY)
    def parse_expression(allow_multi_assign = false)
      start_row = @token.row
      start_file = @token.file
      start_col = @token.col

      if allow_multi_assign && @in_class_body && @token.type?(:-)
        node = parse_data_declaration
        node.set_location(start_file, start_row, start_col)
        return node
      end

      exp = parse_assignment
      unless exp.location_row
        exp.set_location(start_file, start_row, start_col)
      end

      if allow_multi_assign && exp.is_a?(Var) && @token.type?(:",")
        targets = List.new
        targets.push(exp)
        while @token.type?(:",")
          next_token_skip_whitespace
          if @token.type?(:"*")
            next_token_skip_whitespace
            target = parse_ternary
            if target.is_a?(Call) && !target.obj && (target.args.nil? || target.args.empty?) && target.block.nil?
              target = Var.new(target.name)
            end
            target = Splat.new(target)
          else
            target = parse_ternary
            if target.is_a?(Call) && !target.obj && (target.args.nil? || target.args.empty?) && target.block.nil?
              target = Var.new(target.name)
            end
          end
          targets.push(target)
        end

        skip_space
        if @token.type?(:"=")
          next_token_skip_whitespace
          value = parse_assignment_no_control
          i = 0
          while i < targets.length
            t = targets[i]
            t = t.exp if t.is_a?(Splat)
            if t.is_a?(Var)
              push_var(t)
            end
            i += 1
          end
          loc_file = exp.location_file || start_file
          loc_row = exp.location_row || start_row
          loc_col = exp.location_col || start_col
          exp = Assign.new(ArrayLiteral.new(targets.list), value)
          exp.set_location(loc_file, loc_row, loc_col)
          return exp
        else
          error "expected '=' after multi-assignment targets"
        end
      end

      if @token.type?(:"<>")
        exp = Var.new(exp.name) if exp.is_a?(Call) && !exp.obj && (exp.args.nil? || exp.args.empty?) && exp.block.nil?
        error "expected a variable on the left of '<>'" unless exp.is_a?(Var)
        next_token_skip_whitespace
        rhs = parse_ternary
        rhs = Var.new(rhs.name) if rhs.is_a?(Call) && !rhs.obj && (rhs.args.nil? || rhs.args.empty?) && rhs.block.nil?
        error "expected a variable on the right of '<>'" unless rhs.is_a?(Var)
        push_var(exp)
        push_var(rhs)
        value = ArrayLiteral.new([Var.new(rhs.name), Var.new(exp.name)])
        swap = Assign.new(ArrayLiteral.new([Var.new(exp.name), Var.new(rhs.name)]), value)
        swap.set_location(start_file, start_row, start_col)
        return swap
      end

      if implicit_each?(exp)
        block = parse_block(start_row)
        if block
          if exp.is_a?(Var) && exp.name == "each"
            exp = Call.new(nil, "each", [], block)
          else
            exp = Call.new(exp, "each", [], block)
          end
        end
      end

      if @token.type?(:":") && @token.row == start_row
        next_token_skip_space
        exp = Begin.new([exp, parse_assignment_no_control])
      end

      parse_expression_suffix(exp, start_row)
    end
  RUBY
  body = replace_method(body, "first_child_with_location", <<~RUBY)
    def first_child_with_location(node)
      nil
    end
  RUBY
  body = replace_method(body, "parse_expression_suffix", <<~RUBY)
    def parse_expression_suffix(exp, start_row = @token.row)
      skip_space

      return exp unless @token.suffix?
      return exp if @token.row > start_row
      return exp if exp.is_a?(If) || exp.is_a?(While) || exp.is_a?(Begin) || exp.is_a?(Case)

      keyword = @token.value
      next_token_skip_space
      suffix = parse_assignment_no_control

      if keyword == :if
        exp = If.new(suffix, exp)
      elsif keyword == :unless
        exp = If.new(suffix, nil, exp)
      elsif keyword == :while
        exp = While.new(suffix, exp)
      elsif keyword == :until
        exp = While.new(Not.new(suffix), exp)
      elsif keyword == :rescue
        exp = Begin.new(exp, nil, suffix, nil)
      elsif keyword == :ensure
        exp = exp
      else
        unexpected
      end

      check_for :SP, :NL, :EOF, :"=>", :")" unless @token.row > start_row
      exp
    end
  RUBY
  body = replace_method(body, "parse_assignment", <<~RUBY)
    def parse_assignment(allow_ops = true, allow_suffix = true)
      exp = parse_ternary

      while true
        if @token.type?(:SP)
          next_token
        elsif @token.type?(:TYPE_HINT)
          hint = @token.value
          next_token
          if fold_hint_text?(hint) && (exp.is_a?(Print) || exp.is_a?(Write)) && exp.args.any?
            last_idx = exp.args.length - 1
            exp.args[last_idx] = TypeHint.new(exp.args[last_idx], hint).at(exp.args[last_idx])
          else
            exp = TypeHint.new(exp, hint).at(exp)
          end
        elsif @token.type?(:"=")
          target_hint = nil
          if exp.is_a?(TypeHint) && exp.value.is_a?(Var)
            target_hint = exp.hint
            exp = exp.value
          end
          if exp.is_a?(Call) && exp.name == "[]"
            next_token_skip_whitespace
            new_args = exp.args
            new_args << parse_assignment_no_control
            exp = Call.new(exp.obj, "[]=", new_args)
          else
            if exp.is_a?(Call) && !exp.obj.nil? && exp.args.empty? && exp.block.nil?
              next_token_skip_whitespace
              value = parse_assignment_no_control
              exp = Call.new(exp.obj, exp.name.to_s + "=", [value])
            else
              break unless exp.can_assign?

              if exp.is_a?(Var) && exp.name == "self"
                error "can't reassign self"
              end

              if exp.is_a?(Call) && (exp.name.end_with?("?") || exp.name.end_with?("!"))
                error "methods ending in '?' or '!' are invalid assignment targets"
              end

              exp = Var.new(exp.name) if exp.is_a?(Call)
              next_token_skip_whitespace

              if exp.is_a?(Var) && !var?(exp.name)
                @assigning.push exp.name
                value = parse_assignment_no_control
                @assigning.pop
              else
                value = parse_assignment_no_control
              end

              push_var(exp)

              hint = nil
              if @token.type?(:TYPE_HINT)
                hint = @token.value
                next_token
                stripped = hint.to_s.strip
                if stripped == "reuse" || stripped == "recycle" || stripped == "reuse_drain"
                  hint = nil
                end
              end

              exp = Assign.new(exp, value, hint || target_hint)
            end
          end
        else
          break unless @token.assignment_operator?
          unexpected unless allow_ops

          if compound_call_target?(exp)
            op = @token.type.to_s.chop.to_sym
            next_token_skip_whitespace
            value = parse_assignment_no_control
            exp = build_compound_call_assign(exp, op, value)
            allow_ops = true
            next
          end

          break unless exp.can_assign?

          if exp.is_a?(Path)
            error "can't reassign a constant"
          end

          if exp.is_a?(Var) && exp.name == "self"
            error "can't reassign self"
          end

          if exp.is_a?(Call) && exp.name != "[]" && !var?(exp.name)
            error "assignment target is not defined"
          end

          push_var(exp)
          method = @token.type.to_s.chop
          next_token_skip_whitespace
          value = parse_assignment_no_control
          if method == "||" || method == "&&"
            read = exp.is_a?(Call) ? Var.new(exp.name) : exp
            combined = method == "||" ? Or.new(read, value) : And.new(read, value)
            exp = Assign.new(read, combined)
          else
            exp = AssignOp.new(exp, method.to_sym, value)
          end
        end

        allow_ops = true
      end

      exp
    end
  RUBY
  body = replace_method(body, "compound_call_target?", <<~RUBY)
    def compound_call_target?(node)
      node.is_a?(Call) && node.obj && node.block.nil? &&
        (node.name == "[]" || (node.args.empty? && !node.name.to_s.end_with?("?") && !node.name.to_s.end_with?("!")))
    end

    def capitalized_symbol_token?
      return false unless @token.type?(:SYMBOL)
      s = @token.value.to_s
      return false unless s.bytesize >= 2 && s.getbyte(0) == 58
      b = s.getbyte(1)
      b >= 65 && b <= 90
    end

    def generic_args_ahead?
      i = pos
      s = string
      n = s.bytesize
      return false if i >= n
      b = s.getbyte(i)
      return false unless (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 || (b >= 48 && b <= 57)
      i += 1
      while i < n
        b = s.getbyte(i)
        if (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 95
          i += 1
        else
          break
        end
      end
      return false if i >= n
      b = s.getbyte(i)
      b == 62 || b == 44 || b == 47 || b == 42
    end
  RUBY
  body = replace_method(body, "pipe_target", <<~RUBY)
    def pipe_target(left, target)
      if target.is_a?(Call)
          if target.obj.is_a?(Self) || (target.obj.is_a?(Var) && target.obj.name == "self")
            Call.new(left, target.name, target.args, target.block)
          else
          if !target.obj.nil?
            Call.new(target.obj, target.name, [left] + target.args, target.block)
          else
            Call.new(nil, target.name, [left] + target.args, target.block)
          end
        end
      else
        if target.is_a?(Var)
          Call.new(nil, target.name, [left])
        else
          Call.new(target, "call", [left])
        end
      end
    end
  RUBY
  body = replace_method(body, "parse_begin", <<~RUBY)
    def parse_begin
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token
      skip_statement_end

      consume :INDENT
      body = parse_body
      consume :DEDENT unless @token.type?(:EOF)

      rescue_var = nil
      rescue_body = nil
      if @token.keyword?(:rescue)
        next_token_skip_space
        if @token.type?(:ID)
          rescue_var = @token.value.to_s
          next_token
          skip_space
          if @token.type?(:":")
            next_token_skip_space
            check_for :NAME, :CONSTANT
            next_token
          end
        end
        skip_statement_end
        consume :INDENT
        rescue_body = parse_body
        consume :DEDENT unless @token.type?(:EOF)
      end

      ensure_body = nil
      if @token.keyword?(:ensure) || @token.keyword?(:always)
        next_token
        skip_statement_end
        consume :INDENT
        ensure_body = parse_body
        consume :DEDENT unless @token.type?(:EOF)
      end

      node = Begin.new(body, rescue_var, rescue_body, ensure_body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end
  RUBY
  body = replace_method(body, "open", <<~RUBY)
    def open(name, &block)
      @unclosed.push Unclosed.new(name, @token.file, @token.row, @token.col)
      value = block.call
      @unclosed.pop
      value
    end
  RUBY
  body = replace_method(body, "with_indent", <<~RUBY)
    def with_indent(&block)
      consume :INDENT
      value = block.call
      consume :DEDENT unless @token.type?(:EOF)
      value
    end
  RUBY
  body = replace_method(body, "with_isolated_scope", <<~RUBY)
    def with_isolated_scope(create_scope = true, &block)
      return block.call unless create_scope

      @scopes.push(Set.new)
      value = block.call
      @scopes.pop
      value
    end
  RUBY
  replace_method(body, "with_lexical_scope", <<~RUBY)
    def with_lexical_scope(&block)
      @scopes.push(Set.new)
      value = block.call
      @scopes.pop
      value
    end
  RUBY
end

def replace_method(body, name, replacement)
  escaped = Regexp.escape(name)
  match = body.match(/^[ \t]*def[ \t]+#{escaped}(?:\b|\s|\()/)
  return body unless match

  start_index = match.begin(0)
  first_line_end = body.index("\n", start_index) || body.length
  first_line = body[start_index...first_line_end]

  if first_line.match?(/\A\s*def\s+[\w.?!]+(?:\([^)]*\))?\s*=\s+/) || first_line.include?("; end")
    end_index = first_line_end
    end_index += 1 if end_index < body.length
    return body[0...start_index] + replacement + body[end_index..]
  end

  depth = 1
  end_index = first_line_end
  end_index += 1 if end_index < body.length

  while end_index < body.length
    line_end = body.index("\n", end_index) || body.length
    line = body[end_index...line_end]
    code = line.sub(/#.*/, "")
    depth += 1 if code.match?(/\A\s*(?:def|class|module|if|unless|case|while|until|begin)\b/)
    depth += code.scan(/=\s*(?:if|unless|case|begin)\b/).length
    depth += code.scan(/\bdo\b/).length
    depth -= code.scan(/(?<![.\w])end\b/).length
    end_index = line_end
    end_index += 1 if end_index < body.length
    break if depth <= 0
  end

  body[0...start_index] + replacement + body[end_index..]
end

def insert_before_last_end(body, insertion)
  lines = body.lines
  idx = lines.rindex { |line| line.match?(/\A\s*end\s*(?:#.*)?\z/) }
  return body + insertion unless idx

  lines.insert(idx, insertion)
  lines.join
end

def insert_before_private(body, insertion)
  idx = body.rindex(/\n\s*private\n/)
  return body[0...idx] + "\n#{insertion}\n    private\n" + body[(idx + body[idx..].match(/\A\n\s*private\n/)[0].length)..] if idx

  insert_before_last_end(body, insertion)
end

STAGE0_EVAL_IN_BODY = {
  "Int" => "@value",
  "StringLiteral" => "@value",
  "Boolean" => "@value",
  "FloatLiteral" => "@value",
  "Decimal" => "@value",
  "Symbol" => "@value",
  "SymbolLit" => "@value",
  "Char" => "@value",
  "RationalLiteral" => "@value",
  "Month" => "@value",
  "Week" => "@value",
  "ByteArrayLiteral" => "@value",
  "CIDR4" => "@value",
  "CIDR6" => "@value",
  "Date" => "@value",
  "DateTime" => "@value",
  "Duration" => "@value",
  "IP4" => "@value",
  "IP6" => "@value",
  "KeyLiteral" => "@value",
  "TimeLiteral" => "@value",
  "UUID" => "@value",
  "Nil" => "nil",
  "RegexLiteral" => "nil",
  "ColorLiteral" => "nil",
  "CurrencyLiteral" => "nil",
  "PercentageLiteral" => "nil",
  "QuantityLiteral" => "nil",
  "MeasurementLiteral" => "nil",
  "ByteArrayInterpolation" => "nil",
  "Block" => "self",
  "TypeHint" => "interp.evaluate(@value)",
  "WValue" => "interp.decode_w_value(@value, @raw)",
  "Write" => "interp.visit_write(self); nil",
  "Use" => "interp.visit_use(self); nil",
  "Raise" => "interp.visit_raise(self); nil",
  "Break" => "interp.visit_break(self); nil",
  "Next" => "interp.visit_next(self); nil",
  "Alias" => "interp.visit_alias(self); nil",
  "Is" => "interp.visit_is(self); nil",
  "Super" => "interp.visit_super(self); nil",
  "Splat" => "interp.visit_splat(self); nil",
  "List" => "interp.visit_list(self)",
  "Print" => "interp.visit_print(self)",
  "BinaryOp" => "interp.visit_binary_op(self)",
  "Assign" => "interp.visit_assign(self)",
  "Var" => "interp.visit_var(self)",
  "If" => "interp.visit_if(self)",
  "While" => "interp.visit_while(self)",
  "Until" => "interp.visit_until(self)",
  "Def" => "interp.visit_def(self)",
  "Fn" => "interp.visit_fn(self)",
  "Call" => "interp.visit_call(self)",
  "Return" => "interp.visit_return(self)",
  "AssignOp" => "interp.visit_assign_op(self)",
  "ArrayLiteral" => "interp.visit_array_literal(self)",
  "HashLiteral" => "interp.visit_hash_literal(self)",
  "And" => "interp.visit_and(self)",
  "Or" => "interp.visit_or(self)",
  "InTest" => "interp.visit_in_test(self)",
  "CaseExpr" => "interp.visit_case_expr(self)",
  "ClassDef" => "interp.visit_class_def(self)",
  "ModuleDef" => "interp.visit_module_def(self)",
  "TraitDef" => "interp.visit_trait_def(self)",
  "InstanceVar" => "interp.visit_instance_var(self)",
  "ClassVar" => "interp.visit_class_var(self)",
  "GlobalVar" => "interp.visit_global_var(self)",
  "Self" => "interp.visit_self(self)",
  "Begin" => "interp.visit_begin(self)",
  "Yield" => "interp.visit_yield(self)",
  "Not" => "interp.visit_not(self)",
  "Tuple" => "interp.visit_tuple(self)",
  "StringInterpolation" => "interp.visit_string_interpolation(self)",
  "RangeLiteral" => "interp.visit_range_literal(self)",
  "TypedArray" => "interp.visit_typed_array(self)",
  "MagicConstant" => "interp.visit_magic_constant(self)",
  "Path" => "interp.visit_path(self)",
  "UnaryOp" => "interp.visit_unary_op(self)",
  "With" => "interp.visit_with(self)",
  "OnGuard" => "interp.visit_on_guard(self)",
  "Recase" => "interp.visit_recase(self)",
  "SetLiteral" => "interp.visit_set_literal(self)",
  "MultisetLiteral" => "interp.visit_multiset_literal(self)"
}.freeze

def inject_stage0_eval_in(body)
  body.gsub(/^(\s*class\s+([A-Za-z_0-9]+)\s+<\s+[A-Za-z_:0-9]+\s*\n)/) do |hdr|
    cls = Regexp.last_match(2)
    expr = STAGE0_EVAL_IN_BODY[cls]
    if expr
      "#{hdr}    def eval_in(interp)\n      #{expr}\n    end\n"
    else
      hdr
    end
  end
end

def strip_stage0_ast_methods(body)
  strip_methods(body, %w[eval_in children accept_children == clone to_sexp ast_fingerprint name_size])
end

def strip_methods(body, names)
  lines = body.lines
  out = []
  skipping = false
  depth = 0

  lines.each do |line|
    if skipping
      depth += 1 if line.match?(/\A\s*(?:def|class|module|if|unless|case|while|until|begin)\b/) || line.match?(/\bdo\b/)
      depth -= 1 if line.match?(/\A\s*end\s*(?:#.*)?\z/)
      skipping = false if depth <= 0
      next
    end

    if (match = line.match(/\A\s*def\s+([A-Za-z_0-9!?=]+|==)/)) && names.include?(match[1])
      next if line.include?("; end")

      skipping = true
      depth = 1
      next
    end

    out << line
  end

  out.join
end

def stage0_location_source
  <<~RUBY
    module Tungsten
      class Location
        attr_reader :file, :row, :col

        def initialize(file, row, col)
          @file = file
          @row = row
          @col = col
        end

        def dir
          ""
        end

        def between?(min, max)
          false
        end

        def inspect
          to_s
        end

        def to_s
          "(script):" + row.to_s + ":" + col.to_s
        end
      end
    end
  RUBY
end

def stage0_node_source
  <<~RUBY
    module Tungsten::AST
      def self.intern_name(name)
        return nil if name.nil?

        name.to_s
      end

      def self.intern_name_without_prefix(name, prefix)
        value = name.to_s
        return intern_name(value) unless value.start_with?(prefix)

        value[prefix.length..]
      end

      class Node
        attr_accessor :parent, :closure_env, :memo_cache, :cache_path, :doc

        def eval_in(interp)
          nil
        end

        def self.inherited(klass)
        end

        def ==(other)
          false
        end

        def location
          Location.new(0, @location_row, @location_col)
        end

        def location=(loc)
          if loc
            @location_file = 0
            @location_row = loc.row
            @location_col = loc.col
          else
            @location_file = 0
            @location_row = nil
            @location_col = nil
          end
        end

        def set_location(file, row, col)
          @location_file = 0
          @location_row = row
          @location_col = col
          self
        end

        def copy_location_from(other)
          set_location(0, other.location_row, other.location_col)
        end

        def location_file
          0
        end

        def location_row
          @location_row
        end

        def location_col
          @location_col
        end

        def at(obj)
          if obj.is_a?(Token) || obj.is_a?(Location)
            set_location(0, obj.row, obj.col)
          elsif obj
            set_location(0, obj.location_row, obj.location_col)
          else
            self
          end
        end

        def set_parents!(parent = nil)
          self
        end

        def attributes
          self
        end

        def children
          self
        end

        def can_assign?
          false
        end

        def clone
          self
        end

        def clone_from(other)
          self
        end

        def doc=(doc)
          @doc = doc
        end

        def inspect
          "#<Node>"
        end

        def name_column
          location_col || 0
        end

        def name_length
          0
        end

        def node_name
          "node"
        end

        def self.node_name
          "node"
        end

        def self.visitor_method
          :visit_node
        end

        def set_child(name, node)
          self
        end

        def transform(visitor, parent = nil, state = nil)
          self
        end

        class TransformState
          def initialize
            @changed = false
          end

          def changed?
            @changed
          end

          def change
            @changed = true
          end

          def reset
            @changed = false
          end
        end

        def accept(visitor, parent = nil)
          visitor.__send__(node_name, self, parent)
        end

        private

        def location_instance_var?(var)
          false
        end
      end
    end
  RUBY
end

def strip_outer_module(body, pattern)
  lines = body.lines
  idx = lines.index { |line| line.match?(pattern) }
  return body unless idx

  lines.delete_at(idx)
  last_end = lines.rindex { |line| line.match?(/\A\s*end\s*(?:#.*)?\z/) }
  lines.delete_at(last_end) if last_end
  lines.join
end

def flatten_namespaces(body, path)
  body = body.gsub(/@default\b/, "@default_value")
  body = body.gsub(/\.default\b/, ".default_value")
  body = body.gsub(/:default\b/, ":default_value")
  body = body.gsub(/&:default\b/, "&:default_value")
  body = body.gsub(/@else\b/, "@else_value")
  body = body.gsub(/\.else\b/, ".else_value")
  body = body.gsub(/:else\b/, ":else_value")
  body = body.gsub("proc { |*bargs| call_lambda_with_values(block, bargs) }", "nil")
  body = body.gsub("proc { |*bargs| invoke_block(block, bargs) }", "nil")
  body = body.gsub(/^\s*ASSIGNMENT_OPERATORS = .*\n/, "")
  body = body.gsub("ASSIGNMENT_OPERATORS.include?(type)", "%i[+= -= *= /= //= %= |= &= ^= **= <<= >>= ||= &&=].include?(type)")
  body = body.gsub("ASSIGNMENT_OPERATORS", "%i[+= -= *= /= //= %= |= &= ^= **= <<= >>= ||= &&=]")

  if path.include?("/ast/")
    body = strip_outer_module(body, /\A\s*module Tungsten::AST\s*\z/)
  elsif path.include?("/runtime/")
    body = strip_outer_module(body, /\A\s*module Tungsten\s*\z/)
    body = strip_outer_module(body, /\A\s*module Runtime\s*\z/)
    body = body.gsub(/\A(\s*)module Builtins\s*$/) { "#{$1}class Builtins" }
  else
    body = strip_outer_module(body, /\A\s*module Tungsten\s*\z/)
  end

  replacements = {
    "Tungsten::AST::" => "",
    "AST::" => "",
    "Tungsten::Runtime::" => "",
    "Runtime::" => "",
    "Tungsten::Lexer::" => "Lexer::",
    "Tungsten::Parser" => "Parser",
    "Tungsten::Location" => "Location",
    "Tungsten::Error" => "Error",
    "Tungsten.codepoint_lexer?" => "true",
    "Tungsten.new_lexer(str)" => "CodepointLexer.new(str)",
    "Tungsten.parse(" => "Parser.parse(",
    "include AST" => ""
  }

  replacements.each do |from, to|
    body = body.gsub(from, to)
  end

  body.gsub(/Tungsten::/, "")
end

FileUtils.mkdir_p(File.dirname(out))
File.write(out, <<~RUBY)
  # frozen_string_literal: true
  # Generated by implementations/spinel/scripts/build_bundle.rb.
  # Do not edit by hand.

RUBY

File.open(out, "a") do |f|
  sources.each do |path|
    unless File.exist?(path)
      warn "missing source: #{path}"
      next
    end

    f.puts
    f.puts "# -- #{path.delete_prefix("#{ROOT}/")} --"
    f.write(filtered_source(path))
    f.puts
  end
end

final_bundle = File.read(out)
final_bundle = strip_methods(final_bundle, %w[visit_use resolve_use_path visit_in_test])
final_bundle = replace_method(final_bundle, "hash_indifferent_get", <<~RUBY)
  def hash_indifferent_get(hash, key, _c = nil, _d = nil)
    value = hash[key]
    return value if value != nil

    key_text = ""
    key_text = key.to_s
    hash[key_text]
  end
RUBY
final_bundle = replace_method(final_bundle, "evaluate_args", <<~RUBY)
  def evaluate_args(arg_nodes)
    values = []
    if arg_nodes == nil
      return values
    end
    i = 0
    while i < arg_nodes.length
      values.push(evaluate(arg_nodes[i]))
      i += 1
    end
    values
  end
RUBY
final_bundle = replace_method(final_bundle, "new_param_env", <<~RUBY)
  def new_param_env(parent, params, owner = nil, barrier: false)
    stage0_mark_env(Environment.new(parent))
  end
RUBY
final_bundle = replace_method(final_bundle, "bind_params", <<~RUBY)
  def bind_params(env, params, args, splat_index = nil)
    return nil if params == nil

    old_env = @env
    @env = env
    i = 0
    while i < params.length
      param = params[i]
      name = param
      name = param.name
      if i < args.length
        env.bind_new_slot(name, args[i])
      elsif param.default_value != nil
        env.bind_new_slot(name, evaluate(param.default_value))
      else
        env.bind_new_slot(name, nil)
      end
      i += 1
    end
    @env = old_env
    nil
  end
RUBY
final_bundle = replace_method(final_bundle, "execute_bound_w_method", <<~RUBY)
  def execute_bound_w_method(recv, method, method_env, block = nil, call_node = nil)
    old_env = @env
    old_returning = @returning
    old_return_value = @return_value
    old_block = @current_block
    old_in_block = @in_block_depth
    prev_block_env = nil
    if block != nil
      prev_block_env = block.closure_env
      block.closure_env = old_env
    end
    @call_depth += 1
    my_depth = @call_depth
    @in_block_depth = 0
    @self_stack.push(recv)
    @env = method_env
    @current_block = block
    if method.is_a?(Def)
      bslot = method.frame_block_slot.to_i
      method_env.set_slot(bslot, block) if bslot > 0
    elsif method.block != nil
      bname = method.block.is_a?(Arg) ? method.block.name.to_s : method.block.to_s
      if bname != "" && bname != "&"
        method_env.bind_new_slot(bname, block)
      end
    end
    @returning = false
    @return_value = nil
    result = evaluate(method.body)
    if block != nil
      block.closure_env = prev_block_env
    end
    @env = old_env
    @current_block = old_block
    @in_block_depth = old_in_block
    @self_stack.pop
    @call_depth -= 1
    if @returning
      result = @return_value
      if @return_target_depth < 0 || @return_target_depth >= my_depth
        @returning = old_returning
        @return_value = old_return_value
        @return_target_depth = -1
      end
    else
      @returning = old_returning
      @return_value = old_return_value
    end
    result
  end
RUBY
final_bundle = replace_method(final_bundle, "call_w_method", <<~RUBY)
  def call_w_method(recv, method, args, block = nil, call_node: nil)
    return nil if method.nil?
    if method.is_a?(Def)
      stage0_prepare_def_frame(method) if method.frame_shape == 0
      ak = method.accessor_kind
      if ak != 0 && recv.is_a?(WObject)
        wcls = recv.w_class
        if !wcls.nil?
          if ak == 1 && (args.nil? || args.length == 0)
            if method.cached_w_class.equal?(wcls)
              return recv.get_ivar_slot(method.cached_ivar_slot)
            end
            slot = wcls.ivar_slot(method.accessor_ivar)
            method.cached_w_class = wcls
            method.cached_ivar_slot = slot
            return recv.get_ivar_slot(slot)
          elsif ak == 2 && !args.nil? && args.length == 1
            if method.cached_w_class.equal?(wcls)
              return recv.set_ivar_slot(method.cached_ivar_slot, args[0])
            end
            slot = wcls.ivar_slot(method.accessor_ivar)
            method.cached_w_class = wcls
            method.cached_ivar_slot = slot
            return recv.set_ivar_slot(slot, args[0])
          end
        end
      end

      if @env_pool_enabled == 1 && @env_pool_count > 0
        method_env = @env_pool
        @env_pool = method_env.pool_next
        @env_pool_count -= 1
      else
        method_env = Environment.new(@env)
      end
      method_env.pool_reset_frame(@env, method.frame_slot_map, method.frame_shape, method.frame_slot_count, @unbound_slot)
      params = method.args
      param_count = method.stage0_param_names.length
      arg_count = !args.nil? ? args.length : 0
      i = 0
      while i < param_count
        if i < arg_count
          method_env.set_slot(i + 1, args[i])
        else
          pnode = !params.nil? ? params[i] : nil
          if !pnode.nil? && !pnode.default_value.nil?
            old_env = @env
            @env = method_env
            method_env.set_slot(i + 1, evaluate(pnode.default_value))
            @env = old_env
          else
            method_env.set_slot(i + 1, nil)
          end
        end
        i += 1
      end
      result = execute_bound_w_method(recv, method, method_env, block, call_node)
      if @env_pool_enabled == 1
        method_env.pool_link(@env_pool)
        @env_pool = method_env
        @env_pool_count += 1
      end
      return result
    end

    params = method.args
    method_env = new_param_env(@env, params, method)
    bind_params(method_env, params, args, 0)
    execute_bound_w_method(recv, method, method_env, block, call_node)
  end
RUBY
final_bundle = replace_method(final_bundle, "call_w_method_from_nodes", <<~RUBY)
  def call_w_method_from_nodes(recv, method, arg_nodes, block = nil, call_node: nil)
    return nil if method.nil?
    unless method.is_a?(Def)
      return call_w_method(recv, method, evaluate_args(arg_nodes), block, call_node: call_node)
    end
    stage0_prepare_def_frame(method) if method.frame_shape == 0
    ak = method.accessor_kind
    if ak != 0 && recv.is_a?(WObject)
      wcls = recv.w_class
      if !wcls.nil?
        if ak == 1 && (arg_nodes.nil? || arg_nodes.length == 0)
          if method.cached_w_class.equal?(wcls)
            return recv.get_ivar_slot(method.cached_ivar_slot)
          end
          slot = wcls.ivar_slot(method.accessor_ivar)
          method.cached_w_class = wcls
          method.cached_ivar_slot = slot
          return recv.get_ivar_slot(slot)
        elsif ak == 2 && !arg_nodes.nil? && arg_nodes.length == 1
          val = evaluate(arg_nodes[0])
          if method.cached_w_class.equal?(wcls)
            return recv.set_ivar_slot(method.cached_ivar_slot, val)
          end
          slot = wcls.ivar_slot(method.accessor_ivar)
          method.cached_w_class = wcls
          method.cached_ivar_slot = slot
          return recv.set_ivar_slot(slot, val)
        end
      end
    end

    if @env_pool_enabled == 1 && @env_pool_count > 0
      method_env = @env_pool
      @env_pool = method_env.pool_next
      @env_pool_count -= 1
    else
      method_env = Environment.new(@env)
    end
    method_env.pool_reset_frame(@env, method.frame_slot_map, method.frame_shape, method.frame_slot_count, @unbound_slot)
    params = method.args
    param_count = method.stage0_param_names.length
    arg_count = !arg_nodes.nil? ? arg_nodes.length : 0
    i = 0
    while i < arg_count
      val = evaluate(arg_nodes[i])
      if i < param_count
        method_env.set_slot(i + 1, val)
      end
      i += 1
    end
    if i < param_count
      old_env = @env
      @env = method_env
      while i < param_count
        pnode = !params.nil? ? params[i] : nil
        if !pnode.nil? && !pnode.default_value.nil?
          method_env.set_slot(i + 1, evaluate(pnode.default_value))
        else
          method_env.set_slot(i + 1, nil)
        end
        i += 1
      end
      @env = old_env
    end
    result = execute_bound_w_method(recv, method, method_env, block, call_node)
    if @env_pool_enabled == 1
      method_env.pool_link(@env_pool)
      @env_pool = method_env
      @env_pool_count += 1
    end
    result
  end
RUBY
final_bundle = replace_method(final_bundle, "instantiate_from_nodes", <<~RUBY)
  def instantiate_from_nodes(w_class, arg_nodes)
    cm = w_class.lookup_class_method("new")
    return call_w_method_from_nodes(w_class, cm, arg_nodes) if cm != nil
    obj = WObject.new(w_class)
    constructor = w_class.lookup_method("new")
    call_w_method_from_nodes(obj, constructor, arg_nodes) if constructor
    obj
  end
RUBY
TRACE_ENV_VARS = %w[
  SPINEL_STAGE0_CALL_TRACE
  PROFILE_CALLS
  PROFILE_DISPATCH
  STAGE0_ARROW_TRACE
  STAGE0_BIND_TRACE
  STAGE0_BODY_TRACE
  STAGE0_CASE_TRACE
  STAGE0_COMPILE_TRACE
  STAGE0_CONVERT_TRACE
  STAGE0_DEFINE_METHOD_TRACE
  STAGE0_EMITTER_TRACE
  STAGE0_EMIT_FUNCTION_TRACE
  STAGE0_IF_TRACE
  STAGE0_LOAD_TRACE
  STAGE0_LOADER_TRACE
  STAGE0_LOWER_TRACE
  STAGE0_METHOD_BODY_TRACE
  STAGE0_METHOD_PARSE_TRACE
  STAGE0_PATCH_DEBUG
  STAGE0_PROGRAM_TRACE
  STAGE0_STATEMENT_TRACE
  STAGE0_WPARSER_INIT_TRACE
  SPINEL_STAGE0_DEBUG
  STAGE0_WPARSER_TRACE
  STAGE0_TOKEN_TRACE
  STAGE0_PARSE_DEBUG
  STAGE0_NORMALIZED_DUMP
  STAGE0_EVAL_TRACE
  STAGE0_CALL_EVAL_TRACE
  STAGE0_BOOT_TRACE
  SPINEL_STAGE0_WIRE_DUMP
  SPINEL_STAGE0_SOURCE_DUMP
  SPINEL_STAGE0_PARSER_DUMP
  SPINEL_STAGE0_LOWERING_DUMP
  SPINEL_STAGE0_EMITTER_DUMP
  BYTECODE
].freeze
fold_pattern = Regexp.union(TRACE_ENV_VARS.map { |v| "TUNGSTEN_#{v}" })
final_bundle = final_bundle.gsub(/ENV\["(?:#{fold_pattern.source})"\] == "1"/, "false")
final_bundle = final_bundle.gsub(/ENV\["(?:#{fold_pattern.source})"\] != "1"/, "true")
final_bundle = final_bundle.sub(
  "      @loaded_files = {}\n      @current_file = nil\n",
  "      @loaded_files = {}\n      @stage0_loading_depth = 0\n      @current_file = nil\n"
)
final_bundle = final_bundle.sub(
  "      @current_block = nil\n",
  "      @current_block = nil\n" \
  "      @stage0_current_function = \"\"\n" \
  "      @stage0_stack_trace_enabled = 0\n" \
  "      @stage0_call_stack = []\n"
)
final_use_methods = <<~RUBY

  def stage0_progress_mark(event, detail = nil)
    path = ENV["TUNGSTEN_PROGRESS_LOG"]
    stdout_enabled = ENV["TUNGSTEN_PROGRESS_STDOUT"] == "1"
    return nil if (path == nil || path == "") && !stdout_enabled

    stamp = Time.now.to_i.to_s
    line = stamp + "\\t" + event.to_s
    if detail != nil && detail != ""
      line = line + "\\t" + detail.to_s
    end

    if path != nil && path != ""
      text = ""
      if File.exist?(path)
        text = File.read(path)
      end
      out = text.to_s + line + "\\n"
      File.write(path, out.to_s)
    end
    if stdout_enabled
      puts "[progress] " + line
    end
    nil
  end

  def visit_unary_op(node)
    val = evaluate(node.right)
    op = node.operator.to_s
    if op == "-"
      return 0.0 - val if val.is_a?(Float)
      return 0 - val.to_i
    elsif op == "+"
      return val
    elsif op == "~"
      return ~val.to_i
    elsif op == "!"
      return !truthy?(val)
    end
    val
  end

  def stage0_eval_args(arg_nodes)
    evaluate_args(arg_nodes)
  end

  def stage0_aref(value, index)
    if index.is_a?(WRange)
      if value.is_a?(String)
        slen = value.length
        st = index.from
        st = slen + st if st < 0
        return "" if st < 0 || st > slen
        if index.endless
          en = slen - 1
        else
          en = index.to
          en = slen + en if en < 0
          en -= 1 if index.exclusive
        end
        return "" if en < st
        return value.slice(st, en - st + 1) || ""
      elsif value.is_a?(List) || value.is_a?(Array)
        alen = value.length
        res = List.new
        st = index.from
        st = alen + st if st < 0
        return res if st < 0 || st > alen
        if index.endless
          en = alen - 1
        else
          en = index.to
          en = alen + en if en < 0
          en -= 1 if index.exclusive
        end
        en = alen - 1 if en >= alen
        i = st
        while i <= en
          res.push(value[i])
          i += 1
        end
        return res
      end
    end
    if value.is_a?(WireRecord)
      return value.load(index)
    end
    if value.is_a?(WireSequence)
      return value[index.to_i]
    end
    if value.is_a?(PackedNode)
      node_cls = @classes["Tungsten:AST:Node"] || @classes["Node"]
      if node_cls != nil
        m = node_cls.lookup_method("[]")
        if m != nil
          aref_args = evaluate_args(nil)
          aref_args.push(index)
          return call_w_method(value, m, aref_args)
        end
      end
      return value.get_sparse(index)
    end
    if value.is_a?(Hash)
      hash_value = value[index]
      return hash_value if hash_value != nil
      if index.is_a?(String)
        hash_value = value[index.to_sym]
        return hash_value if hash_value != nil
      elsif index.is_a?(Symbol)
        return value[index.to_s]
      end
      return nil
    end
    if value.is_a?(String)
      return value.slice(index.to_i, 1) || ""
    end
    value[index]
  end

  def stage0_value_length(value)
    return 0 if value == nil
    return value.byte_length if value.is_a?(StringBuffer)
    return value.size if value.is_a?(WireSequence)
    return value.field_count if value.is_a?(WireRecord)
    return value.bytesize if value.is_a?(String)
    return value.length if value.is_a?(List) || value.is_a?(Array) || value.is_a?(Hash)
    value.to_s.bytesize
  end

  def stage0_collect_free_vars(node, env)
    vars = [""]
    vars.clear
    seen = {"__spinel_fv__" => true}
    seen.clear
    stage0_walk_free_vars(node, env, vars, seen)
    vars
  end

  def stage0_walk_free_vars(node, env, vars, seen)
    return nil unless node
    if node.is_a?(Array)
      i = 0
      while i < node.length
        stage0_walk_free_vars(node[i], env, vars, seen)
        i += 1
      end
      return nil
    end
    return nil unless node.respond_to?(:doc)
    doc = node.doc
    if doc == 1 || doc == 17
      i = 0
      while i < node.length
        stage0_walk_free_vars(node[i], env, vars, seen)
        i += 1
      end
      return nil
    end
    if doc == 9
      name = node.name.to_s
      if name.length > 0
        c0 = name.getbyte(0)
        is_const = c0 >= 65 && c0 <= 90
        if !seen[name] && !is_const && c0 != 64 && !env.defined_locally_or_in_scope?(name)
          seen[name] = true
          vars.push(name)
        end
      end
      return nil
    end
    if doc == 8
      stage0_walk_free_vars(node.value, env, vars, seen)
      t = node.name
      if t != nil && t.respond_to?(:doc) && t.doc == 9
        seen[t.name.to_s] = true
      else
        stage0_walk_free_vars(t, env, vars, seen)
      end
      return nil
    end
    if doc == 15
      stage0_walk_free_vars(node.value, env, vars, seen)
      stage0_walk_free_vars(node.name, env, vars, seen)
      return nil
    end
    if doc == 7 || doc == 19 || doc == 20
      stage0_walk_free_vars(node.left, env, vars, seen)
      stage0_walk_free_vars(node.right, env, vars, seen)
      return nil
    end
    if doc == 10
      stage0_walk_free_vars(node.condition, env, vars, seen)
      stage0_walk_free_vars(node.then_block, env, vars, seen)
      stage0_walk_free_vars(node.else_block, env, vars, seen)
      return nil
    end
    if doc == 11 || doc == 58
      stage0_walk_free_vars(node.condition, env, vars, seen)
      stage0_walk_free_vars(node.body, env, vars, seen)
      return nil
    end
    if doc == 13
      stage0_walk_free_vars(node.obj, env, vars, seen)
      cargs = node.args
      if cargs != nil
        i = 0
        while i < cargs.length
          stage0_walk_free_vars(cargs[i], env, vars, seen)
          i += 1
        end
      end
      return nil
    end
    if doc == 2 || doc == 36 || doc == 38 || doc == 47
      kargs = node.args
      if kargs != nil
        i = 0
        while i < kargs.length
          stage0_walk_free_vars(kargs[i], env, vars, seen)
          i += 1
        end
      end
      return nil
    end
    if doc == 14 || doc == 35 || doc == 39 || doc == 40 || doc == 53
      stage0_walk_free_vars(node.value, env, vars, seen)
      return nil
    end
    if doc == 18
      entries = node.entries
      if entries != nil
        i = 0
        while i < entries.length
          pair = entries[i]
          if pair != nil
            stage0_walk_free_vars(pair[0], env, vars, seen)
            stage0_walk_free_vars(pair[1], env, vars, seen)
          end
          i += 1
        end
      end
      return nil
    end
    if doc == 21
      stage0_walk_free_vars(node.lhs, env, vars, seen)
      elems = node.elements
      if elems != nil
        i = 0
        while i < elems.length
          stage0_walk_free_vars(elems[i], env, vars, seen)
          i += 1
        end
      end
      return nil
    end
    if doc == 22 && node.is_a?(CaseExpr)
      stage0_walk_free_vars(node.receiver, env, vars, seen)
      whens = node.whens
      if whens != nil
        wi = 0
        while wi < whens.length
          ci = 0
          while ci < whens[wi][0].length
            stage0_walk_free_vars(whens[wi][0][ci], env, vars, seen)
            ci += 1
          end
          stage0_walk_free_vars(whens[wi][1], env, vars, seen)
          wi += 1
        end
      end
      stage0_walk_free_vars(node.else_body, env, vars, seen)
      return nil
    end
    if doc == 34
      stage0_walk_free_vars(node.body, env, vars, seen)
      stage0_walk_free_vars(node.rescue_body, env, vars, seen)
      stage0_walk_free_vars(node.ensure_body, env, vars, seen)
      return nil
    end
    if doc == 41
      stage0_walk_free_vars(node.operand, env, vars, seen)
      return nil
    end
    if doc == 42
      elems = node.elements
      if elems != nil
        i = 0
        while i < elems.length
          stage0_walk_free_vars(elems[i], env, vars, seen)
          i += 1
        end
      end
      return nil
    end
    if doc == 43
      stage0_walk_free_vars(node.exp, env, vars, seen)
      return nil
    end
    if doc == 44
      parts = node.parts
      if parts != nil
        i = 0
        while i < parts.length
          stage0_walk_free_vars(parts[i], env, vars, seen)
          i += 1
        end
      end
      return nil
    end
    if doc == 48
      stage0_walk_free_vars(node.from, env, vars, seen)
      stage0_walk_free_vars(node.to, env, vars, seen)
      return nil
    end
    if doc == 49
      stage0_walk_free_vars(node.size_node, env, vars, seen)
      return nil
    end
    if doc == 56
      stage0_walk_free_vars(node.right, env, vars, seen)
      return nil
    end
    nil
  end

  def stage0_invoke_block(block, args)
    return nil if block == nil
    old_env = @env
    parent_env = block.closure_env != nil ? block.closure_env : old_env
    block_env = Environment.new(parent_env)
    block_env.set_barrier(false)
    stage0_mark_env(block_env)
    params = block.args
    if params != nil && params.length > 0
      if params.length > 1 && args.length == 1
        if args[0].is_a?(List)
          args = args[0].to_a
        elsif args[0].is_a?(Array)
          args = args[0]
        end
      end
      i = 0
      while i < params.length
        param = params[i]
        pname = param.name.to_s
        if i < args.length
          block_env.bind_new_slot(pname, args[i])
        elsif param.default_value != nil
          @env = block_env
          block_env.bind_new_slot(pname, evaluate(param.default_value))
          @env = old_env
        else
          block_env.bind_new_slot(pname, nil)
        end
        i += 1
      end
    elsif args.length > 0
      free_vars = block.free_var_cache
      if free_vars == nil
        free_vars = stage0_collect_free_vars(block.body, parent_env)
        block.free_var_cache = free_vars
      end
      if free_vars.length > 1 && args.length == 1
        if args[0].is_a?(List)
          args = args[0].to_a
        elsif args[0].is_a?(Array)
          args = args[0]
        end
      end
      fi = 0
      while fi < free_vars.length
        break if fi >= args.length
        block_env.bind_new_slot(free_vars[fi], args[fi])
        fi += 1
      end
      block_env.bind_new_slot("_", args[0])
      ai = 0
      while ai < args.length
        block_env.bind_new_slot("_" + (ai + 1).to_s, args[ai])
        ai += 1
      end
    end
    @env = block_env
    @in_block_depth += 1
    result = evaluate(block.body)
    @in_block_depth -= 1
    @env = old_env
    result
  end

  def stage0_prepare_def_frame(fn)
    @stage0_next_layout_shape += 1
    shape = @stage0_next_layout_shape
    shape = 2 if shape < 2
    slot_map = {"__spinel_slot0__" => 0}
    slot_map.clear
    pnames = fn.stage0_param_names
    pcount = pnames.length
    i = 0
    while i < pcount
      pname = "" + (pnames[i] || "")
      slot_map[pname] = i + 1 if pname != ""
      i += 1
    end
    next_slot = pcount + 1
    bslot = 0
    if !fn.block.nil?
      bname = "" + (fn.block.is_a?(Arg) ? fn.block.name.to_s : fn.block.to_s)
      if bname != "" && bname != "&"
        existing_b = slot_map[bname]
        if existing_b.nil?
          slot_map[bname] = next_slot
          bslot = next_slot
          next_slot += 1
        else
          bslot = existing_b
        end
      end
    end

    if fn.accessor_kind == 0 && fn.block.nil? && fn.splat_index.nil? && fn.double_splat.nil?
      fbody = fn.body
      if fbody.is_a?(List) && fbody.list.length == 1
        stmt = fbody.list[0]
        if !stmt.nil?
          if pcount == 0 && stmt.doc == 27 && stmt.is_a?(InstanceVar)
            fn.accessor_kind = 1
            fn.accessor_ivar = stmt.name
          elsif pcount == 1 && !fn.args.nil? && fn.args.length == 1 && fn.args[0].default_value.nil? &&
                stmt.doc == 8 && stmt.is_a?(Assign) && stmt.target_kind == 2 &&
                !stmt.value.nil? && stmt.value.doc == 9 && stmt.value.is_a?(Var) && stmt.value.name == pnames[0]
            fn.accessor_kind = 2
            fn.accessor_ivar = stmt.target_var_name
          end
        end
      end
    end

    stack = [nil, 0, ""]
    stack.clear
    if !fn.args.nil?
      ai = 0
      while ai < fn.args.length
        arg_n = fn.args[ai]
        stack.push(arg_n.default_value) if !arg_n.nil? && !arg_n.default_value.nil?
        ai += 1
      end
    end
    stack.push(fn.body)
    while stack.length > 0
      cur = stack.pop
      next if cur.nil?
      next unless cur.respond_to?(:doc)
      doc = cur.doc
      next if doc.nil?
      next if doc == 12 || doc == 37 || doc == 24 || doc == 25 || doc == 26
      if doc == 1 || doc == 17
        ci = 0
        while ci < cur.length
          stack.push(cur[ci])
          ci += 1
        end
      elsif doc == 8
        stack.push(cur.value)
        if cur.is_a?(Assign)
          if cur.target_kind == 1
            vn = "" + cur.target_var_name
            if vn != "" && slot_map[vn].nil?
              slot_map[vn] = next_slot
              next_slot += 1
            end
          elsif cur.target_kind == 0
            t = cur.name
            if !t.nil? && t.doc == 17
              ti = 0
              while ti < t.length
                sub = t[ti]
                if sub.is_a?(String)
                  if sub != "" && slot_map[sub].nil?
                    slot_map[sub] = next_slot
                    next_slot += 1
                  end
                elsif !sub.nil? && sub.doc == 9
                  svn = "" + sub.name.to_s
                  if svn != "" && slot_map[svn].nil?
                    slot_map[svn] = next_slot
                    next_slot += 1
                  end
                end
                ti += 1
              end
            else
              stack.push(t)
            end
          end
        end
      elsif doc == 15
        stack.push(cur.value)
        if cur.is_a?(AssignOp)
          if cur.target_kind == 1
            vn = "" + cur.target_var_name
            if vn != "" && slot_map[vn].nil?
              slot_map[vn] = next_slot
              next_slot += 1
            end
          elsif cur.target_kind == 0
            stack.push(cur.name)
          end
        end
      elsif doc == 7 || doc == 19 || doc == 20
        stack.push(cur.left)
        stack.push(cur.right)
      elsif doc == 10
        stack.push(cur.condition)
        stack.push(cur.then_block)
        stack.push(cur.else_block)
      elsif doc == 11 || doc == 58
        stack.push(cur.condition)
        stack.push(cur.body)
      elsif doc == 13
        stack.push(cur.obj)
        cargs = cur.args
        if !cargs.nil?
          ci = 0
          while ci < cargs.length
            stack.push(cargs[ci])
            ci += 1
          end
        end
        stack.push(cur.block) if cur.is_a?(Call) && !cur.block.nil?
      elsif doc == 54
        stack.push(cur.body) if cur.is_a?(Block)
      elsif doc == 2 || doc == 36 || doc == 38 || doc == 47
        kargs = cur.args
        if !kargs.nil?
          ci = 0
          while ci < kargs.length
            stack.push(kargs[ci])
            ci += 1
          end
        end
      elsif doc == 14 || doc == 35 || doc == 39 || doc == 40 || doc == 53
        stack.push(cur.value)
      elsif doc == 18
        entries = cur.entries
        if !entries.nil?
          ci = 0
          while ci < entries.length
            pair = entries[ci]
            if !pair.nil?
              stack.push(pair[0])
              stack.push(pair[1])
            end
            ci += 1
          end
        end
      elsif doc == 21
        stack.push(cur.lhs)
        elems = cur.elements
        if !elems.nil?
          ci = 0
          while ci < elems.length
            stack.push(elems[ci])
            ci += 1
          end
        end
      elsif doc == 22 && cur.is_a?(CaseExpr)
        stack.push(cur.receiver)
        whens = cur.whens
        if !whens.nil?
          wi = 0
          while wi < whens.length
            ci = 0
            while ci < whens[wi][0].length
              stack.push(whens[wi][0][ci])
              ci += 1
            end
            stack.push(whens[wi][1])
            wi += 1
          end
        end
        stack.push(cur.else_body)
      elsif doc == 34
        if cur.is_a?(Begin) && !cur.rescue_var.nil?
          rv = "" + cur.rescue_var.to_s
          if rv != "" && slot_map[rv].nil?
            slot_map[rv] = next_slot
            next_slot += 1
          end
        end
        stack.push(cur.body)
        stack.push(cur.rescue_body)
        stack.push(cur.ensure_body)
      elsif doc == 41
        stack.push(cur.operand)
      elsif doc == 42
        elems = cur.elements
        if !elems.nil?
          ci = 0
          while ci < elems.length
            stack.push(elems[ci])
            ci += 1
          end
        end
      elsif doc == 43
        stack.push(cur.exp)
      elsif doc == 44
        parts = cur.parts
        if !parts.nil?
          ci = 0
          while ci < parts.length
            stack.push(parts[ci])
            ci += 1
          end
        end
      elsif doc == 48
        stack.push(cur.from)
        stack.push(cur.to)
      elsif doc == 49
        stack.push(cur.size_node)
      elsif doc == 55
        if cur.is_a?(OnGuard)
          stack.push(cur.predicate)
          stack.push(cur.body)
        end
      elsif doc == 56
        stack.push(cur.right)
      elsif doc == 57
        if cur.is_a?(With)
          bindings = cur.bindings
          if !bindings.nil? && bindings.length > 0
            pair = bindings[0]
            if !pair.nil?
              vnode = pair[0]
              if !vnode.nil?
                vn = "" + vnode.name.to_s
                if vn != "" && slot_map[vn].nil?
                  slot_map[vn] = next_slot
                  next_slot += 1
                end
              end
              if slot_map["_"].nil?
                slot_map["_"] = next_slot
                next_slot += 1
              end
              stack.push(pair[1])
            end
          end
          stack.push(cur.body)
        end
      end
    end

    fn.frame_slot_map = slot_map
    fn.frame_slot_count = next_slot
    fn.frame_block_slot = bslot
    fn.frame_shape = shape
    nil
  end

  def stage0_call_def_from_nodes(fn, call_name, arg_nodes, block = nil)
    stage0_prepare_def_frame(fn) if fn.frame_shape == 0
    old_env = @env
    old_returning = @returning
    old_return_value = @return_value
    old_block = @current_block
    old_in_block = @in_block_depth
    old_owner_depth = @current_block_owner_depth
    prev_block_env = nil
    if block != nil
      prev_block_env = block.closure_env
      block.closure_env = old_env
    end
    if @env_pool_enabled == 1 && @env_pool_count > 0
      new_env = @env_pool
      @env_pool = new_env.pool_next
      @env_pool_count -= 1
    else
      new_env = Environment.new(old_env)
    end
    new_env.pool_reset_frame(old_env, fn.frame_slot_map, fn.frame_shape, fn.frame_slot_count, @unbound_slot)
    params = fn.args
    param_count = fn.stage0_param_names.length
    arg_count = arg_nodes != nil ? arg_nodes.length : 0
    i = 0
    while i < arg_count
      arg_node = arg_nodes[i]
      if i < param_count
        new_env.set_slot(i + 1, evaluate(arg_node))
      else
        evaluate(arg_node)
      end
      i += 1
    end
    @env = new_env
    if i < param_count
      while i < param_count
        pnode = params != nil ? params[i] : nil
        if pnode != nil && pnode.default_value != nil
          new_env.set_slot(i + 1, evaluate(pnode.default_value))
        else
          new_env.set_slot(i + 1, nil)
        end
        i += 1
      end
    end
    bslot = fn.frame_block_slot.to_i
    if bslot > 0
      new_env.set_slot(bslot, block)
    end
    if block != nil
      if @in_block_depth > 0
        # keep current_block_owner_depth pointing to outer method
      else
        @current_block_owner_depth = @call_depth
      end
    end
    @call_depth += 1
    my_depth = @call_depth
    @in_block_depth = 0
    @current_block = block
    @returning = false
    @return_value = nil
    @self_stack.push(nil)

    result = evaluate(fn.body)
    if block != nil
      block.closure_env = prev_block_env
    end
    @self_stack.pop
    @env = old_env
    @current_block = old_block
    @in_block_depth = old_in_block
    @current_block_owner_depth = old_owner_depth
    @call_depth -= 1
    if @returning
      result = @return_value
      if @return_target_depth < 0 || @return_target_depth >= my_depth
        @returning = old_returning
        @return_value = old_return_value
        @return_target_depth = -1
      end
    else
      @returning = old_returning
      @return_value = old_return_value
    end
    if @env_pool_enabled == 1
      new_env.pool_link(@env_pool)
      @env_pool = new_env
      @env_pool_count += 1
    end
    result
  end

  def stage0_slab_alloc_init(arg_nodes)
    kind_id = evaluate(arg_nodes[0]).to_i
    size_class = evaluate(arg_nodes[1]).to_i
    offset = @ast_next_offset
    @ast_next_offset += 8
    pnode = PackedNode.new(kind_id, size_class, offset)
    idx = 2
    slot = 0
    while idx < arg_nodes.length
      pnode.set_field(slot, evaluate(arg_nodes[idx]))
      slot += 1
      idx += 1
    end
    pnode
  end

  def stage0_clone_wire_value(val)
    if val.is_a?(WireRecord)
      copy = WireRecord.new(val.kind)
      n = val.field_count
      i = 0
      while i < n
        copy.store_at(i, val.key_at(i), stage0_clone_wire_value(val.value_at(i)))
        i += 1
      end
      return copy
    elsif val.is_a?(WireSequence)
      copy = WireSequence.new
      n = val.size
      i = 0
      while i < n
        copy.push(stage0_clone_wire_value(val[i]))
        i += 1
      end
      return copy
    elsif val.is_a?(List)
      cloned = []
      n = val.length
      i = 0
      while i < n
        cloned.push(stage0_clone_wire_value(val[i]))
        i += 1
      end
      return List.new(cloned)
    elsif val.is_a?(Hash)
      copy = {}
      val.each do |k, v|
        copy[k] = stage0_clone_wire_value(v)
      end
      return copy
    end
    val
  end

  def stage0_dispatch_ccall(arg_nodes)
    fn_name = evaluate(arg_nodes[0]).to_s
    argc = arg_nodes.length
    if fn_name == "w_is_node_extern"
      v = evaluate(arg_nodes[1])
      return v.is_a?(PackedNode) ? 1 : 0
    end
    if fn_name == "w_is_ast_node_full"
      v = evaluate(arg_nodes[1])
      return 0 if v == nil
      return 1 if v.is_a?(PackedNode)
      if v.is_a?(Hash) && argc > 2
        k = evaluate(arg_nodes[2])
        return (v[k] != nil || v[k.to_s] != nil || v[k.to_sym] != nil) ? 1 : 0
      end
      return 0
    end
    if fn_name == "w_node_alloc"
      kind_id = evaluate(arg_nodes[1]).to_i
      size_class = evaluate(arg_nodes[2]).to_i
      offset = @ast_next_offset
      @ast_next_offset += 8
      return PackedNode.new(kind_id, size_class, offset)
    end
    if fn_name == "w_node_field_store"
      n = evaluate(arg_nodes[1])
      slot = evaluate(arg_nodes[2]).to_i
      val = evaluate(arg_nodes[3])
      n.set_field(slot, val) if n.is_a?(PackedNode)
      return val
    end
    if fn_name == "w_node_field_load"
      n = evaluate(arg_nodes[1])
      slot = evaluate(arg_nodes[2]).to_i
      return n.get_field(slot) if n.is_a?(PackedNode)
      return nil
    end
    if fn_name == "w_node_kind_extern"
      n = evaluate(arg_nodes[1])
      return n.kind if n.is_a?(PackedNode)
      return 0
    end
    if fn_name == "w_node_kind_sym"
      n = evaluate(arg_nodes[1])
      tbl = evaluate(arg_nodes[2])
      if n.is_a?(PackedNode) && (tbl.is_a?(List) || tbl.is_a?(Array))
        kid = n.kind
        if kid >= 0 && kid < tbl.length
          return tbl[kid]
        end
      end
      return nil
    end
    if fn_name == "w_node_offset_extern"
      n = evaluate(arg_nodes[1])
      return n.offset if n.is_a?(PackedNode)
      return 0
    end
    if fn_name == "w_node_size_class_extern"
      n = evaluate(arg_nodes[1])
      return n.sc if n.is_a?(PackedNode)
      return 0
    end
    if fn_name == "w_node_singleton"
      kid = evaluate(arg_nodes[1]).to_i
      existing = @ast_singletons[kid]
      if existing == nil
        existing = PackedNode.new(kid, 0, kid)
        @ast_singletons[kid] = existing
      end
      return existing
    end
    if fn_name == "w_node_inline_payload"
      kid = evaluate(arg_nodes[1]).to_i
      payload = evaluate(arg_nodes[2]).to_i & 0xFFFFFFFF
      key = (kid << 32) | payload
      node = @ast_inline_nodes[key]
      if node == nil
        node = PackedNode.new(kid, 0, payload)
        @ast_inline_nodes[key] = node
      end
      return node
    end
    if fn_name == "w_ast_bool_cached"
      truthy = evaluate(arg_nodes[1]).to_i != 0
      key = truthy ? 1 : 0
      node = @ast_bool_nodes[key]
      if node == nil
        offset = @ast_next_offset
        @ast_next_offset += 8
        node = PackedNode.new(39, 1, offset)
        node.set_field(0, truthy)
        @ast_bool_nodes[key] = node
      end
      return node
    end
    if fn_name == "w_ast_intern_node"
      kid = evaluate(arg_nodes[1]).to_i
      val = evaluate(arg_nodes[2])
      str = val.to_s
      tag = val.is_a?(Symbol) ? "1:" : "0:"
      skey = tag + str
      sid = @ast_intern_ids[skey]
      if sid == nil
        @ast_intern_next_id += 1
        sid = @ast_intern_next_id
        @ast_intern_ids[skey] = sid
        @ast_intern_strs[sid] = str
      end
      nkey = (kid << 32) | sid
      cached = @ast_intern_nodes[nkey]
      if cached == nil
        cached = PackedNode.new(kid, 0, sid, str)
        @ast_intern_nodes[nkey] = cached
      end
      return cached
    end
    if fn_name == "w_ast_intern_str_of"
      n = evaluate(arg_nodes[1])
      if n.is_a?(PackedNode)
        s = n.intern_str
        return s if s != nil && s != ""
        return @ast_intern_strs[n.offset] || ""
      end
      return ""
    end
    if fn_name == "w_ast_sparse_set"
      n = evaluate(arg_nodes[1])
      k = evaluate(arg_nodes[2])
      v = evaluate(arg_nodes[3])
      n.set_sparse(k, v) if n.is_a?(PackedNode)
      return v
    end
    if fn_name == "w_ast_sparse_get"
      n = evaluate(arg_nodes[1])
      k = evaluate(arg_nodes[2])
      return n.get_sparse(k) if n.is_a?(PackedNode)
      return nil
    end
    if fn_name == "w_ast_sparse_copy"
      src = evaluate(arg_nodes[1])
      dst = evaluate(arg_nodes[2])
      if src.is_a?(PackedNode) && dst.is_a?(PackedNode)
        src.copy_metadata_to(dst)
      end
      return dst
    end
    if fn_name == "w_ast_analysis_set"
      n = evaluate(arg_nodes[1])
      v = evaluate(arg_nodes[2])
      n.analysis = v if n.is_a?(PackedNode)
      return v
    end
    if fn_name == "w_ast_analysis_get"
      n = evaluate(arg_nodes[1])
      return n.analysis if n.is_a?(PackedNode)
      return nil
    end
    if fn_name == "w_ast_ivar_offsets_set"
      n = evaluate(arg_nodes[1])
      v = evaluate(arg_nodes[2])
      n.ivar_offsets = v if n.is_a?(PackedNode)
      return v
    end
    if fn_name == "w_ast_ivar_offsets_get"
      n = evaluate(arg_nodes[1])
      return n.ivar_offsets if n.is_a?(PackedNode)
      return nil
    end
    if fn_name == "w_ast_ivar_count_set"
      n = evaluate(arg_nodes[1])
      v = evaluate(arg_nodes[2])
      n.ivar_count = v if n.is_a?(PackedNode)
      return v
    end
    if fn_name == "w_ast_ivar_count_get"
      n = evaluate(arg_nodes[1])
      return n.ivar_count if n.is_a?(PackedNode)
      return nil
    end
    if fn_name == "w_ast_store_reset"
      @ast_singletons.clear
      @ast_inline_nodes.clear
      @ast_bool_nodes.clear
      @ast_intern_ids.clear
      @ast_intern_nodes.clear
      @ast_intern_strs.clear
      @ast_intern_next_id = 0
      @ast_next_offset = 65536
      @ast_store_gen += 1
      return nil
    end
    if fn_name == "w_ast_store_generation"
      return @ast_store_gen
    end
    if fn_name == "w_ast_store_stats_dump"
      return nil
    end
    if fn_name == "w_ast_body_builder_new"
      return List.new
    end
    if fn_name == "w_ast_body_builder_push"
      storage = evaluate(arg_nodes[1])
      _size = evaluate(arg_nodes[2])
      val = evaluate(arg_nodes[3])
      storage.push(val) if storage.is_a?(List) || storage.is_a?(Array)
      return storage
    end
    if fn_name == "w_ast_body_builder_finish"
      storage = evaluate(arg_nodes[1])
      _size = evaluate(arg_nodes[2])
      return storage if storage.is_a?(List)
      return List.new(storage) if storage.is_a?(Array)
      return List.new
    end
    if fn_name == "w_content_temp_map_new"
      cap = evaluate(arg_nodes[1]).to_i
      start_id = evaluate(arg_nodes[2]).to_i
      return ContentTempMap.new(cap, start_id)
    end
    if fn_name == "w_content_temp_map_seed"
      m = evaluate(arg_nodes[1])
      name = evaluate(arg_nodes[2])
      idx = evaluate(arg_nodes[3]).to_i
      if m.is_a?(ContentTempMap)
        ord = -1
        if name.is_a?(String) && name.bytesize >= 3 && name.getbyte(0) == 37 && name.getbyte(1) == 116
          valid = true
          acc = 0
          bi = 2
          blen = name.bytesize
          while bi < blen
            b = name.getbyte(bi)
            if b >= 48 && b <= 57
              acc = acc * 10 + (b - 48)
            else
              valid = false
              break
            end
            bi += 1
          end
          ord = acc if valid
        end
        m.seed(ord, name, idx)
      end
      return nil
    end
    if fn_name == "w_content_temp_norm"
      name = evaluate(arg_nodes[1])
      m = evaluate(arg_nodes[2])
      if m.is_a?(ContentTempMap)
        ord = -1
        if name.is_a?(String) && name.bytesize >= 3 && name.getbyte(0) == 37 && name.getbyte(1) == 116
          valid = true
          acc = 0
          bi = 2
          blen = name.bytesize
          while bi < blen
            b = name.getbyte(bi)
            if b >= 48 && b <= 57
              acc = acc * 10 + (b - 48)
            else
              valid = false
              break
            end
            bi += 1
          end
          ord = acc if valid
        end
        return m.norm(ord, name)
      end
      return 0
    end
    if fn_name == "w_wire_function_record_new"
      fields = evaluate(arg_nodes[1])
      name = evaluate(arg_nodes[2])
      params = evaluate(arg_nodes[3])
      return_type = evaluate(arg_nodes[4])
      is_toplevel = evaluate(arg_nodes[5])
      extra_params = evaluate(arg_nodes[6])
      rec = WireRecord.new(265)
      rec.store_at(0, fields[0], name)
      rec.store_at(1, fields[1], name)
      rec.store_at(2, fields[2], params)
      rec.store_at(3, fields[3], extra_params)
      rec.store_at(4, fields[4], return_type)
      rec.store_at(5, fields[5], is_toplevel)
      rec.store_at(6, fields[6], List.new)
      rec.store_at(7, fields[7], {})
      rec.store_at(8, fields[8], {})
      rec.store_at(9, fields[9], 0)
      rec.store_at(10, fields[10], 0)
      rec.store_at(11, fields[11], 0)
      rec.store_at(12, fields[12], 0)
      rec.store_at(13, fields[13], List.new)
      rec.store_at(14, fields[14], 0)
      rec.store_at(15, fields[15], List.new)
      rec.store_at(16, fields[16], List.new)
      rec.store_at(17, fields[17], List.new([nil]))
      rec.store_at(18, fields[18], {})
      rec.store_at(19, fields[19], List.new)
      rec.store_at(20, fields[20], {})
      rec.store_at(21, fields[21], false)
      rec.store_at(22, fields[22], false)
      rec.store_at(23, fields[23], nil)
      rec.store_at(24, fields[24], nil)
      return rec
    end
    if fn_name == "w_wire_block_record_new"
      fields = evaluate(arg_nodes[1])
      label = evaluate(arg_nodes[2])
      rec = WireRecord.new(266)
      rec.store_at(0, fields[0], label)
      rec.store_at(1, fields[1], List.new)
      return rec
    end
    if fn_name == "w_wire_alloc" || fn_name == "w_wire_alloc_reserve"
      return WireRecord.new(evaluate(arg_nodes[1]).to_i)
    end
    if fn_name == "w_wire_field_store_at"
      rec = evaluate(arg_nodes[1])
      idx = evaluate(arg_nodes[2]).to_i
      sym = evaluate(arg_nodes[3])
      val = evaluate(arg_nodes[4])
      rec.store_at(idx, sym, val) if rec.is_a?(WireRecord)
      return val
    end
    if fn_name == "w_wire_field_store"
      rec = evaluate(arg_nodes[1])
      sym = evaluate(arg_nodes[2])
      val = evaluate(arg_nodes[3])
      if rec.is_a?(WireRecord)
        rec.store(sym, val)
      elsif rec.is_a?(Hash)
        rec[sym] = val
      end
      return val
    end
    if fn_name == "w_wire_field_load" || fn_name == "w_wire_field_load_nil"
      rec = evaluate(arg_nodes[1])
      sym = evaluate(arg_nodes[2])
      if rec.is_a?(WireRecord)
        return rec.load(sym)
      elsif rec.is_a?(Hash)
        v = rec[sym]
        return v if v != nil
        if sym.is_a?(String)
          return rec[sym.to_sym]
        elsif sym.is_a?(Symbol)
          return rec[sym.to_s]
        end
      end
      return nil
    end
    if fn_name == "w_wire_field_count"
      rec = evaluate(arg_nodes[1])
      return rec.field_count if rec.is_a?(WireRecord)
      return rec.length if rec.is_a?(Hash)
      return 0
    end
    if fn_name == "w_wire_field_symbol_at"
      rec = evaluate(arg_nodes[1])
      idx = evaluate(arg_nodes[2]).to_i
      return rec.key_at(idx) if rec.is_a?(WireRecord)
      return nil
    end
    if fn_name == "w_wire_field_value_at"
      rec = evaluate(arg_nodes[1])
      idx = evaluate(arg_nodes[2]).to_i
      return rec.value_at(idx) if rec.is_a?(WireRecord)
      return nil
    end
    if fn_name == "w_wire_kind_extern"
      rec = evaluate(arg_nodes[1])
      return rec.kind if rec.is_a?(WireRecord)
      return 267 if rec.is_a?(WireSequence)
      return 0
    end
    if fn_name == "w_wire_kind_sym"
      rec = evaluate(arg_nodes[1])
      tbl = evaluate(arg_nodes[2])
      if rec.is_a?(WireRecord) && (tbl.is_a?(List) || tbl.is_a?(Array))
        kid = rec.kind
        return tbl[kid] if kid >= 0 && kid < tbl.length
      end
      return nil
    end
    if fn_name == "w_is_wire_extern"
      rec = evaluate(arg_nodes[1])
      return (rec.is_a?(WireRecord) || rec.is_a?(WireSequence)) ? 1 : 0
    end
    if fn_name == "w_wire_sequence_from_array"
      arr = evaluate(arg_nodes[1])
      return arr if arr.is_a?(WireSequence)
      seq = WireSequence.new
      if arr.is_a?(List) || arr.is_a?(Array)
        i = 0
        while i < arr.length
          seq.push(arr[i])
          i += 1
        end
      end
      return seq
    end
    if fn_name == "w_wire_sequence_size"
      s = evaluate(arg_nodes[1])
      return s.size if s.is_a?(WireSequence)
      return s.length if s.is_a?(List) || s.is_a?(Array)
      return 0
    end
    if fn_name == "w_wire_sequence_get"
      s = evaluate(arg_nodes[1])
      idx = evaluate(arg_nodes[2]).to_i
      return s[idx] if s.is_a?(WireSequence) || s.is_a?(List) || s.is_a?(Array)
      return nil
    end
    if fn_name == "w_wire_sequence_set"
      s = evaluate(arg_nodes[1])
      idx = evaluate(arg_nodes[2]).to_i
      val = evaluate(arg_nodes[3])
      if s.is_a?(WireSequence) || s.is_a?(List) || s.is_a?(Array)
        s[idx] = val
        return val
      end
      return nil
    end
    if fn_name == "w_wire_store_reset" || fn_name == "w_wire_store_mark"
      return 0
    end
    if fn_name == "w_wire_clone"
      return stage0_clone_wire_value(evaluate(arg_nodes[1]))
    end
    if fn_name == "w_wire_temp_operands"
      rec = evaluate(arg_nodes[1])
      out = List.new
      if rec.is_a?(WireRecord)
        n = rec.field_count
        i = 0
        while i < n
          k = rec.key_at(i).to_s
          v = rec.value_at(i)
          i += 1
          next if k == "temp" || v == nil
          if v.is_a?(WireSequence)
            vn = v.size
            vi = 0
            while vi < vn
              item = v[vi]
              vi += 1
              if item.is_a?(String) && !item.empty? && item.getbyte(0) == 37
                out.push(item)
              elsif item.is_a?(Hash)
                iv = item[:value] || item["value"]
                out.push(iv) if iv.is_a?(String) && !iv.empty? && iv.getbyte(0) == 37
              elsif item.is_a?(List) || item.is_a?(Array)
                return nil
              end
            end
          elsif v.is_a?(String) && !v.empty? && v.getbyte(0) == 37
            out.push(v)
          elsif v.is_a?(List) || v.is_a?(Array) || v.is_a?(Hash)
            return nil
          end
        end
      end
      return out
    end
    if fn_name == "w_wire_func_current_instructions"
      fn_rec = evaluate(arg_nodes[1])
      return nil unless fn_rec.is_a?(WireRecord)
      blocks = fn_rec.load(:blocks)
      cbi = fn_rec.load(:current_block_index).to_i
      return nil if cbi < 0
      if blocks.is_a?(WireSequence) && cbi < blocks.size
        blk = blocks[cbi]
        return blk.load(:instructions) if blk.is_a?(WireRecord)
      elsif (blocks.is_a?(List) || blocks.is_a?(Array)) && cbi < blocks.length
        blk = blocks[cbi]
        return blk.load(:instructions) if blk.is_a?(WireRecord)
      end
      return nil
    end
    if fn_name == "w_wire_func_push_instruction"
      fn_rec = evaluate(arg_nodes[1])
      instr = evaluate(arg_nodes[2])
      if fn_rec.is_a?(WireRecord)
        blocks = fn_rec.load(:blocks)
        cbi = fn_rec.load(:current_block_index).to_i
        blk = nil
        if cbi >= 0
          if blocks.is_a?(WireSequence) && cbi < blocks.size
            blk = blocks[cbi]
          elsif (blocks.is_a?(List) || blocks.is_a?(Array)) && cbi < blocks.length
            blk = blocks[cbi]
          end
        end
        if blk.is_a?(WireRecord)
          seq = blk.load(:instructions)
          if seq.is_a?(WireSequence) || seq.is_a?(List) || seq.is_a?(Array)
            seq.push(instr)
          end
        end
      end
      return instr
    end
    if fn_name == "w_make_token_extern"
      t = evaluate(arg_nodes[1]).to_i & 0xFF
      l = evaluate(arg_nodes[2]).to_i & 0xFFF
      o = evaluate(arg_nodes[3]).to_i & 0xFFFFFF
      return -1125899906842624 | (t << 38) | (l << 26) | (o << 2)
    end
    if fn_name == "w_token_type_extern"
      return (evaluate(arg_nodes[1]).to_i >> 38) & 0xFF
    end
    if fn_name == "w_token_length_extern"
      return (evaluate(arg_nodes[1]).to_i >> 26) & 0xFFF
    end
    if fn_name == "w_token_offset_extern"
      return (evaluate(arg_nodes[1]).to_i >> 2) & 0xFFFFFF
    end
    if fn_name == "w_parser_tok_raw"
      return evaluate(arg_nodes[1]).to_i
    end
    if fn_name == "w_parser_chars_equal_ascii"
      chars = evaluate(arg_nodes[1])
      off = evaluate(arg_nodes[2]).to_i
      len = evaluate(arg_nodes[3]).to_i
      lit = evaluate(arg_nodes[4]).to_s
      return 0 if lit.bytesize != len
      if chars.is_a?(List) || chars.is_a?(Array)
        return 0 if off < 0 || off + len > chars.length
        i = 0
        while i < len
          return 0 if chars[off + i].to_i != lit.getbyte(i)
          i += 1
        end
        return 1
      elsif chars.is_a?(String)
        return 0 if off < 0 || off + len > chars.bytesize
        return chars.byteslice(off, len) == lit ? 1 : 0
      end
      return 0
    end
    if fn_name == "w_location_file"
      fid = evaluate(arg_nodes[1]).to_i & 0x3FFF
      line = evaluate(arg_nodes[2]).to_i & 0x3FFFF
      col = evaluate(arg_nodes[3]).to_i & 0x7FF
      return -307863255777280 | (fid << 29) | (line << 11) | col
    end
    if fn_name == "w_location_file_offset"
      fid = evaluate(arg_nodes[1]).to_i & 0x3FFF
      off = evaluate(arg_nodes[2]).to_i & 0x1FFFFFFF
      return -299067162755072 | (fid << 29) | off
    end
    if fn_name == "w_unbox_location_file_id" || fn_name == "w_unbox_location_file_id_extern"
      return (evaluate(arg_nodes[1]).to_i >> 29) & 0x3FFF
    end
    if fn_name == "w_unbox_location_line" || fn_name == "w_unbox_location_line_extern"
      return (evaluate(arg_nodes[1]).to_i >> 11) & 0x3FFFF
    end
    if fn_name == "w_unbox_location_col" || fn_name == "w_unbox_location_col_extern"
      return evaluate(arg_nodes[1]).to_i & 0x7FF
    end
    if fn_name == "w_unbox_location_offset" || fn_name == "w_unbox_location_offset_extern"
      return evaluate(arg_nodes[1]).to_i & 0x1FFFFFFF
    end
    if fn_name == "w_loc_register_file"
      path = evaluate(arg_nodes[1]).to_s
      line_at = argc > 2 ? evaluate(arg_nodes[2]) : nil
      col_at = argc > 3 ? evaluate(arg_nodes[3]) : nil
      fid = @loc_files.length
      @loc_files.push(path)
      @loc_line_tables.push(line_at)
      @loc_col_tables.push(col_at)
      @loc_sources.push("")
      return fid
    end
    if fn_name == "w_loc_register_source_text"
      fid = evaluate(arg_nodes[1]).to_i
      text = evaluate(arg_nodes[2]).to_s
      while @loc_sources.length <= fid
        @loc_sources.push("")
      end
      @loc_sources[fid] = text
      return fid
    end
    if fn_name == "w_loc_line_for_offset"
      fid = evaluate(arg_nodes[1]).to_i
      off = evaluate(arg_nodes[2]).to_i
      if fid > 0 && fid < @loc_line_tables.length
        tbl = @loc_line_tables[fid]
        if tbl.is_a?(List) || tbl.is_a?(Array)
          return tbl[off].to_i if off >= 0 && off < tbl.length
          return tbl[tbl.length - 1].to_i if tbl.length > 0
        end
      end
      src = (fid > 0 && fid < @loc_sources.length) ? @loc_sources[fid] : ""
      return 1 if src == nil || src == ""
      prefix = src.byteslice(0, off) || ""
      c = 0
      pi = 0
      plen = prefix.bytesize
      while pi < plen
        c += 1 if prefix.getbyte(pi) == 10
        pi += 1
      end
      return c + 1
    end
    if fn_name == "w_loc_col_for_offset"
      fid = evaluate(arg_nodes[1]).to_i
      off = evaluate(arg_nodes[2]).to_i
      if fid > 0 && fid < @loc_col_tables.length
        tbl = @loc_col_tables[fid]
        if tbl.is_a?(List) || tbl.is_a?(Array)
          return tbl[off].to_i if off >= 0 && off < tbl.length
          return tbl[tbl.length - 1].to_i if tbl.length > 0
        end
      end
      src = (fid > 0 && fid < @loc_sources.length) ? @loc_sources[fid] : ""
      return 1 if src == nil || src == ""
      prefix = src.byteslice(0, off) || ""
      nl = prefix.rindex("\\n")
      return nl == nil ? off + 1 : off - nl
    end
    if fn_name == "w_numeric_to_i64" || fn_name == "w_u64" || fn_name == "w_int"
      return evaluate(arg_nodes[1]).to_i
    end
    if fn_name == "w_int_to_hex_str"
      return stage0_u64_hex(evaluate(arg_nodes[1]).to_i)
    end
    if fn_name == "w_string_byte_length" || fn_name == "w_string_len"
      return evaluate(arg_nodes[1]).to_s.bytesize
    end
    if fn_name == "w_string_slice_bytes"
      s = evaluate(arg_nodes[1]).to_s
      st = evaluate(arg_nodes[2]).to_i
      ln = evaluate(arg_nodes[3]).to_i
      return "" if ln <= 0 || st < 0 || st >= s.bytesize
      return s.byteslice(st, ln) || ""
    end
    if fn_name == "w_string_eq_bytes_lit"
      s = evaluate(arg_nodes[1]).to_s
      st = evaluate(arg_nodes[2]).to_i
      ln = evaluate(arg_nodes[3]).to_i
      lit = evaluate(arg_nodes[4]).to_s
      return false if lit.bytesize != ln || st < 0 || st + ln > s.bytesize
      return s.byteslice(st, ln) == lit
    end
    if fn_name == "w_string_first_byte"
      s = evaluate(arg_nodes[1]).to_s
      return -1 if s.bytesize == 0
      return s.getbyte(0)
    end
    if fn_name == "w_algebra_rewrite_source"
      return evaluate(arg_nodes[1])
    end
    if fn_name == "w_array_data_ptr"
      return evaluate(arg_nodes[1])
    end
    if fn_name == "w_read_lex64_table"
      path = evaluate(arg_nodes[1]).to_s
      cached = @lex64_tables[path]
      return cached if cached != nil
      if File.exist?(path)
        data = File.binread(path)
        if data.bytesize >= 16 && data.byteslice(0, 4) == "WLX8"
          body = data.byteslice(16, data.bytesize - 16)
          @lex64_tables[path] = body
          return body
        end
      end
      return nil
    end
    if fn_name == "w_lchs_scan_64"
      s = evaluate(arg_nodes[1]).to_s
      pos = evaluate(arg_nodes[2]).to_i
      len = evaluate(arg_nodes[3]).to_i
      mask = evaluate(arg_nodes[4]).to_i
      limit = s.bytesize
      limit = len if len < limit
      i = pos
      while i < limit
        b = s.getbyte(i)
        if b < 64
          break if ((mask >> b) & 1) == 0
        else
          break if ((mask >> 63) & 1) == 0
        end
        i += 1
      end
      return i
    end
    if fn_name == "w_lex64_scan_to_cp"
      data = evaluate(arg_nodes[1])
      n = evaluate(arg_nodes[2]).to_i
      p = evaluate(arg_nodes[3]).to_i
      target = evaluate(arg_nodes[4]).to_i
      if data.is_a?(List) || data.is_a?(Array)
        limit = data.length < n ? data.length : n
        while p < limit
          lc = data[p].to_i
          cp_val = (lc >> 18) & 0x1FFFFF
          return p if cp_val == target
          p += 1
        end
      end
      return p
    end
    if fn_name == "w_executable_dir"
      return File.expand_path("bin")
    end
    if fn_name == "w_executable_path"
      return File.expand_path("bin/tungsten-compiler")
    end
    if fn_name == "w_runtime_dir"
      return File.expand_path("runtime")
    end
    if fn_name == "w_cpu_count" || fn_name == "__w_cpu_count"
      return 4
    end
    if fn_name == "w_isatty_stdout" || fn_name == "w_isatty_stdin"
      return false
    end
    if fn_name == "w_slab_is_frozen" || fn_name == "w_frozen_p" || fn_name == "w_core_cache_write"
      return false
    end
    if fn_name == "w_freeze"
      return evaluate(arg_nodes[1])
    end
    if fn_name == "w_host_cache_bytes_extern"
      return 0
    end
    if fn_name == "w_eputs"
      $stderr.puts(evaluate(arg_nodes[1]).to_s)
      return nil
    end
    if fn_name == "w_flush"
      $stdout.flush
      $stderr.flush
      return nil
    end
    if fn_name == "w_setenv"
      ENV[evaluate(arg_nodes[1]).to_s] = evaluate(arg_nodes[2]).to_s
      return nil
    end
    if fn_name == "w_run_argv"
      argv_val = evaluate(arg_nodes[1])
      cmd_s = ""
      if argv_val.is_a?(List) || argv_val.is_a?(Array)
        ai = 0
        while ai < argv_val.length
          cmd_s = cmd_s + " " if ai > 0
          arg_s = argv_val[ai].to_s
          cmd_s = cmd_s + "'" + arg_s.gsub("'", "'\\\\''") + "'"
          ai += 1
        end
      else
        cmd_s = argv_val.to_s
      end
      ok = system(cmd_s)
      return ok ? 0 : 1
    end
    if fn_name == "__w_bit_ctpop_u64" || fn_name == "__w_bit_ctpop_64" || fn_name == "__w_bit_ctpop_16" || fn_name == "__w_bit_ctpop_8"
      v = evaluate(arg_nodes[1]).to_i
      c = 0
      i = 0
      while i < 64
        c += (v >> i) & 1
        i += 1
      end
      return c
    end
    if fn_name == "__w_bit_ctpop_u32" || fn_name == "__w_bit_ctpop_32"
      v = evaluate(arg_nodes[1]).to_i & 0xFFFFFFFF
      c = 0
      while v > 0
        c += (v & 1)
        v = v >> 1
      end
      return c
    end
    if fn_name == "__w_bit_cttz_u64" || fn_name == "__w_bit_cttz_64"
      v = evaluate(arg_nodes[1]).to_i
      return 64 if v == 0
      c = 0
      while c < 64 && ((v >> c) & 1) == 0
        c += 1
      end
      return c
    end
    if fn_name == "__w_bit_cttz_u32" || fn_name == "__w_bit_cttz_32"
      v = evaluate(arg_nodes[1]).to_i & 0xFFFFFFFF
      return 32 if v == 0
      c = 0
      while c < 32 && ((v >> c) & 1) == 0
        c += 1
      end
      return c
    end
    if fn_name == "__w_bit_ctlz_u64" || fn_name == "__w_bit_ctlz_64"
      v = evaluate(arg_nodes[1]).to_i
      return 64 if v == 0
      c = 0
      i = 63
      while i >= 0 && ((v >> i) & 1) == 0
        c += 1
        i -= 1
      end
      return c
    end
    nil
  end

  def stage0_tungsten_lchs_flag(cp)
    if cp < 128
      return 0x80 if cp == 10 || cp == 13
      return 0x10 if cp == 32 || cp == 9
      return 0x02 if cp == 34 || cp == 39
      return 0x29 if cp >= 48 && cp <= 57
      return 0x08 if cp >= 65 && cp <= 70
      return 0x60 if cp == 95
      return 0x68 if cp >= 97 && cp <= 102
      return 0x60 if cp >= 103 && cp <= 122
      return 0x04 if cp == 33 || cp == 35 || cp == 37 || cp == 38 || (cp >= 40 && cp <= 47) || (cp >= 58 && cp <= 63) || cp == 91 || cp == 93 || cp == 94 || (cp >= 123 && cp <= 126)
      return 0
    end
    return 0x60 if cp == 0x00B5
    return 0x60 if cp >= 0x00C0 && cp <= 0x02AF && cp != 0x00D7 && cp != 0x00F7
    return 0x60 if cp >= 0x0370 && cp <= 0x04FF
    return 0x60 if cp >= 0x0904 && cp <= 0x0939
    return 0x60 if cp >= 0x1D00 && cp <= 0x1EFF
    return 0x60 if cp == 0x207F || (cp >= 0x2090 && cp <= 0x209C)
    return 0x60 if cp == 0x2107 || cp == 0x2113 || cp == 0x2119 || cp == 0x211A || cp == 0x212F
    return 0x60 if cp == 0x222B || cp == 0x2C7C
    return 0x60 if cp >= 0x3040 && cp <= 0x30FF
    return 0x60 if cp >= 0x1D400 && cp <= 0x1D7FF
    0
  end

  def stage0_hash_dup(h)
    res = {}
    if h.is_a?(Hash)
      h.each do |k, v|
        res[k] = v
      end
    end
    res
  end

  def stage0_hash_keys(h)
    res = List.new
    if h.is_a?(Hash)
      h.each do |k, _v|
        res.push(k)
      end
    end
    res
  end

  def stage0_hash_values(h)
    res = List.new
    if h.is_a?(Hash)
      h.each do |_k, v|
        res.push(v)
      end
    end
    res
  end

  def stage0_hash_merge(recv, other)
    res = {}
    if recv.is_a?(Hash)
      recv.each do |k, v|
        res[k] = v
      end
    end
    if other.is_a?(Hash)
      other.each do |k, v|
        res[k] = v
      end
    end
    res
  end

  def stage0_primitive_block_call(recv, name_sym, arg_nodes, block)
    if recv.is_a?(WRange)
      case name_sym
      when :include?, :cover?, :begin, :first, :min, :end, :last, :max, :exclude_end?, :to_a
        return stage0_primitive_call(recv, name_sym, arg_nodes, nil)
      else
        recv = recv.to_list
      end
    elsif recv.is_a?(WireSequence)
      case name_sym
      when :push, :"<<", :size, :length, :empty?, :get, :"[]", :set, :"[]=", :to_a
        return stage0_primitive_call(recv, name_sym, arg_nodes, nil)
      else
        recv = List.new(recv.items)
      end
    end

    case name_sym
    when :each
      old_owner = @current_block_owner_depth
      @current_block_owner_depth = @call_depth if @in_block_depth == 0
      if recv.is_a?(List) || recv.is_a?(Array)
        i = 0
        while i < recv.length
          stage0_invoke_block(block, [recv[i]])
          break if @returning || @exiting
          if @breaking
            @breaking = false
            break
          end
          @nexting = false if @nexting
          i += 1
        end
      elsif recv.is_a?(Hash)
        bparams = block.args
        bparam_len = bparams != nil ? bparams.length : 0
        recv.each do |k, v|
          if bparam_len >= 2
            stage0_invoke_block(block, [k, v])
          else
            stage0_invoke_block(block, [List.new([k, v])])
          end
          break if @returning || @exiting
          if @breaking
            @breaking = false
            break
          end
          @nexting = false if @nexting
        end
      end
      @current_block_owner_depth = old_owner
      return recv
    when :each_with_index
      old_owner = @current_block_owner_depth
      @current_block_owner_depth = @call_depth if @in_block_depth == 0
      if recv.is_a?(List) || recv.is_a?(Array)
        i = 0
        while i < recv.length
          stage0_invoke_block(block, [recv[i], i])
          break if @returning || @exiting
          if @breaking
            @breaking = false
            break
          end
          @nexting = false if @nexting
          i += 1
        end
      end
      @current_block_owner_depth = old_owner
      return recv
    when :map, :collect
      res = List.new
      old_owner = @current_block_owner_depth
      @current_block_owner_depth = @call_depth if @in_block_depth == 0
      if recv.is_a?(List) || recv.is_a?(Array)
        i = 0
        while i < recv.length
          val = stage0_invoke_block(block, [recv[i]])
          break if @returning || @exiting
          if @breaking
            @breaking = false
            break
          end
          res.push(val)
          i += 1
        end
      elsif recv.is_a?(Hash)
        bparams = block.args
        bparam_len = bparams != nil ? bparams.length : 0
        recv.each do |k, v|
          if bparam_len >= 2
            val = stage0_invoke_block(block, [k, v])
          else
            val = stage0_invoke_block(block, [List.new([k, v])])
          end
          break if @returning || @exiting
          res.push(val)
        end
      end
      @current_block_owner_depth = old_owner
      return res
    when :select, :filter, :find_all
      res = List.new
      if recv.is_a?(List) || recv.is_a?(Array)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        while i < recv.length
          elem = recv[i]
          keep = stage0_invoke_block(block, [elem])
          break if @returning || @exiting
          res.push(elem) if truthy?(keep)
          i += 1
        end
        @current_block_owner_depth = old_owner
      end
      return res
    when :reject
      res = List.new
      if recv.is_a?(List) || recv.is_a?(Array)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        while i < recv.length
          elem = recv[i]
          drop = stage0_invoke_block(block, [elem])
          break if @returning || @exiting
          res.push(elem) if !truthy?(drop)
          i += 1
        end
        @current_block_owner_depth = old_owner
      end
      return res
    when :any?
      if recv.is_a?(List) || recv.is_a?(Array)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        found = false
        while i < recv.length
          v = stage0_invoke_block(block, [recv[i]])
          break if @returning || @exiting
          if truthy?(v)
            found = true
            break
          end
          i += 1
        end
        @current_block_owner_depth = old_owner
        return found
      end
      return false
    when :all?
      if recv.is_a?(List) || recv.is_a?(Array)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        ok = true
        while i < recv.length
          v = stage0_invoke_block(block, [recv[i]])
          break if @returning || @exiting
          if !truthy?(v)
            ok = false
            break
          end
          i += 1
        end
        @current_block_owner_depth = old_owner
        return ok
      end
      return true
    when :none?
      if recv.is_a?(List) || recv.is_a?(Array)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        ok = true
        while i < recv.length
          v = stage0_invoke_block(block, [recv[i]])
          break if @returning || @exiting
          if truthy?(v)
            ok = false
            break
          end
          i += 1
        end
        @current_block_owner_depth = old_owner
        return ok
      end
      return true
    when :find, :detect
      if recv.is_a?(List) || recv.is_a?(Array)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        found_elem = nil
        while i < recv.length
          elem = recv[i]
          v = stage0_invoke_block(block, [elem])
          break if @returning || @exiting
          if truthy?(v)
            found_elem = elem
            break
          end
          i += 1
        end
        @current_block_owner_depth = old_owner
        return found_elem
      end
      return nil
    when :flat_map
      res = List.new
      if recv.is_a?(List) || recv.is_a?(Array)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        while i < recv.length
          sub = stage0_invoke_block(block, [recv[i]])
          break if @returning || @exiting
          if sub.is_a?(List) || sub.is_a?(Array)
            si = 0
            while si < sub.length
              res.push(sub[si])
              si += 1
            end
          else
            res.push(sub)
          end
          i += 1
        end
        @current_block_owner_depth = old_owner
      end
      return res
    when :times
      if recv.is_a?(Integer)
        old_owner = @current_block_owner_depth
        @current_block_owner_depth = @call_depth if @in_block_depth == 0
        i = 0
        while i < recv
          stage0_invoke_block(block, [i])
          break if @returning || @exiting
          if @breaking
            @breaking = false
            break
          end
          @nexting = false if @nexting
          i += 1
        end
        @current_block_owner_depth = old_owner
      end
      return recv
    when :sort_by
      if recv.is_a?(List) || recv.is_a?(Array)
        res = List.new
        keys = List.new
        i = 0
        while i < recv.length
          elem = recv[i]
          res.push(elem)
          keys.push(stage0_invoke_block(block, [elem]))
          i += 1
        end
        n = res.length
        a_idx = 0
        while a_idx < n
          b_idx = a_idx + 1
          while b_idx < n
            ka = keys[a_idx]
            kb = keys[b_idx]
            swap = (ka.is_a?(Integer) && kb.is_a?(Integer)) ? (kb < ka) : (kb.to_s < ka.to_s)
            if swap
              tmp = res[a_idx]
              res[a_idx] = res[b_idx]
              res[b_idx] = tmp
              ktmp = keys[a_idx]
              keys[a_idx] = keys[b_idx]
              keys[b_idx] = ktmp
            end
            b_idx += 1
          end
          a_idx += 1
        end
        return res
      end
      return recv
    when :count
      if recv.is_a?(List) || recv.is_a?(Array)
        c = 0
        i = 0
        while i < recv.length
          c += 1 if truthy?(stage0_invoke_block(block, [recv[i]]))
          i += 1
        end
        return c
      end
      return stage0_primitive_call(recv, name_sym, arg_nodes, nil)
    else
      stage0_primitive_call(recv, name_sym, arg_nodes, nil)
    end
  end

  def stage0_primitive_call(recv, name_sym, arg_nodes, block = nil)
    return stage0_primitive_block_call(recv, name_sym, arg_nodes, block) unless block.nil?

    argc = arg_nodes != nil ? arg_nodes.length : 0
    if recv.is_a?(StringBuffer)
      case name_sym
      when :push, :"<<", :append
        recv.push(evaluate(arg_nodes[0]).to_s)
        return recv
      when :push_char, :push_byte
        recv.push_byte(evaluate(arg_nodes[0]).to_i)
        return recv
      when :byte_length, :length, :size
        return recv.byte_length
      when :empty?
        return recv.empty?
      when :clear
        return recv.clear
      when :slice_bytes
        return recv.slice_bytes(evaluate(arg_nodes[0]).to_i, evaluate(arg_nodes[1]).to_i)
      end
    elsif recv.is_a?(WireRecord)
      case name_sym
      when :load, :"[]"
        return recv.load(evaluate(arg_nodes[0]))
      when :store, :"[]="
        return recv.store(evaluate(arg_nodes[0]), evaluate(arg_nodes[1]))
      end
    elsif recv.is_a?(WireSequence)
      case name_sym
      when :push, :"<<"
        return recv.push(evaluate(arg_nodes[0]))
      when :size, :length
        return recv.size
      when :empty?
        return recv.empty?
      when :get, :"[]"
        return recv[evaluate(arg_nodes[0]).to_i]
      when :set, :"[]="
        return recv[evaluate(arg_nodes[0]).to_i] = evaluate(arg_nodes[1])
      when :to_a
        return List.new(recv.items)
      when :nil?, :is_a?, :kind_of?, :to_s, :inspect
        # handled below without materializing List
      else
        recv = List.new(recv.items)
      end
    elsif recv.is_a?(WRange)
      case name_sym
      when :include?, :cover?
        return recv.include?(evaluate(arg_nodes[0]))
      when :begin, :first, :min
        return recv.from
      when :end, :last, :max
        return nil if recv.endless
        return recv.exclusive ? (recv.to - 1) : recv.to
      when :exclude_end?
        return recv.exclusive
      when :to_a
        return recv.to_list
      when :nil?, :is_a?, :kind_of?, :to_s, :inspect
        # handled below without materializing List
      else
        recv = recv.to_list
      end
    end

    case name_sym
    when :push, :append
      recv.push(evaluate(arg_nodes[0]))
      return recv
    when :"<<"
      v = evaluate(arg_nodes[0])
      if recv.is_a?(StringBuffer)
        recv.push(v.to_s)
        return recv
      elsif recv.is_a?(String)
        return ("" + recv.to_s) + v.to_s
      elsif recv.is_a?(List)
        recv.push(v)
        return recv
      end
      recv << v
      return recv
    when :"[]="
      key_v = evaluate(arg_nodes[0])
      val_v = evaluate(arg_nodes[1])
      if recv.is_a?(Hash)
        if key_v.is_a?(String) && recv.key?(key_v.to_sym)
          recv.delete(key_v.to_sym)
        elsif key_v.is_a?(Symbol) && recv.key?(key_v.to_s)
          recv.delete(key_v.to_s)
        end
        recv[key_v] = val_v
        return val_v
      end
      recv[key_v] = val_v
      return val_v
    when :"[]"
      idx_v = evaluate(arg_nodes[0])
      if argc == 2
        len_v = evaluate(arg_nodes[1]).to_i
        if recv.is_a?(List) || recv.is_a?(Array)
          res = List.new
          st = idx_v.to_i
          st = recv.length + st if st < 0
          return res if st < 0 || len_v <= 0
          ei = 0
          while ei < len_v && (st + ei) < recv.length
            res.push(recv[st + ei])
            ei += 1
          end
          return res
        else
          return recv.to_s.slice(idx_v.to_i, len_v) || ""
        end
      end
      return stage0_aref(recv, idx_v)
    when :size, :length, :bytesize, :byte_length
      return stage0_value_length(recv)
    when :empty?
      return stage0_value_length(recv) == 0
    when :nil?
      return recv == nil
    when :to_s, :inspect
      return w_to_s(recv)
    when :is_a?, :kind_of?
      target_t = evaluate(arg_nodes[0])
      target_name = ""
      if target_t.is_a?(WClass)
        target_name = target_t.name.to_s
      elsif target_t.is_a?(String) || target_t.is_a?(Symbol)
        target_name = target_t.to_s
      end
      return true if target_name == "Object"
      return stage0_type_name(recv) == target_name
    when :getbyte, :byte_at
      return recv.to_s.getbyte(evaluate(arg_nodes[0]).to_i)
    when :slice, :byteslice, :slice_bytes
      idx = evaluate(arg_nodes[0]).to_i
      if argc > 1
        len = evaluate(arg_nodes[1]).to_i
        if recv.is_a?(List) || recv.is_a?(Array)
          res = List.new
          st = idx < 0 ? recv.length + idx : idx
          return res if st < 0 || len <= 0
          ei = 0
          while ei < len && (st + ei) < recv.length
            res.push(recv[st + ei])
            ei += 1
          end
          return res
        else
          s = recv.to_s
          return (name_sym == :slice ? s.slice(idx, len) : s.byteslice(idx, len)) || ""
        end
      else
        if recv.is_a?(List) || recv.is_a?(Array)
          return recv[idx]
        else
          s = recv.to_s
          return (name_sym == :slice ? s.slice(idx, 1) : s.byteslice(idx, 1)) || ""
        end
      end
    when :start_with?, :starts_with?
      return recv.to_s.start_with?(evaluate(arg_nodes[0]).to_s)
    when :end_with?, :ends_with?
      return recv.to_s.end_with?(evaluate(arg_nodes[0]).to_s)
    when :has_key?, :key?
      k = evaluate(arg_nodes[0])
      if recv.is_a?(Hash)
        return true if recv.key?(k)
        if k.is_a?(String)
          return recv.key?(k.to_sym)
        elsif k.is_a?(Symbol)
          return recv.key?(k.to_s)
        end
      end
      return false
    when :include?, :contains?
      value = evaluate(arg_nodes[0])
      if recv.is_a?(Set)
        return recv.include?(value.to_s)
      end
      if recv.is_a?(List) || recv.is_a?(Array)
        i = 0
        while i < recv.length
          return true if recv[i] == value
          i += 1
        end
        return false
      end
      if recv.is_a?(Hash)
        return true if recv.key?(value)
        if value.is_a?(String)
          return recv.key?(value.to_sym)
        elsif value.is_a?(Symbol)
          return recv.key?(value.to_s)
        end
        return false
      end
      return recv.to_s.include?(value.to_s)
    when :pop
      return recv.pop if recv.is_a?(List) || recv.is_a?(Array)
      return nil
    when :shift
      if recv.is_a?(List)
        return nil if recv.length == 0
        return recv.delete_at(0)
      elsif recv.is_a?(Array)
        return recv.shift
      end
      return nil
    when :unshift
      val = evaluate(arg_nodes[0])
      if recv.is_a?(List)
        recv.list.unshift(val)
      elsif recv.is_a?(Array)
        recv.unshift(val)
      end
      return recv
    when :clear
      recv.clear
      return recv
    when :delete_at
      idx = evaluate(arg_nodes[0]).to_i
      return recv.delete_at(idx) if recv.is_a?(List) || recv.is_a?(Array)
      return nil
    when :delete
      k = evaluate(arg_nodes[0])
      if recv.is_a?(Hash)
        v = recv.delete(k)
        return v if v != nil
        if k.is_a?(String)
          return recv.delete(k.to_sym)
        elsif k.is_a?(Symbol)
          return recv.delete(k.to_s)
        end
        return nil
      elsif recv.is_a?(List)
        return recv.list.delete(k)
      elsif recv.is_a?(Array)
        return recv.delete(k)
      end
      return nil
    when :concat
      other = evaluate(arg_nodes[0])
      if (recv.is_a?(List) || recv.is_a?(Array)) && (other.is_a?(List) || other.is_a?(Array))
        oi = 0
        while oi < other.length
          recv.push(other[oi])
          oi += 1
        end
      end
      return recv
    when :dup, :clone
      if recv.is_a?(List)
        res = List.new
        i = 0
        while i < recv.length
          res.push(recv[i])
          i += 1
        end
        return res
      elsif recv.is_a?(Hash)
        return stage0_hash_dup(recv)
      elsif recv.is_a?(String)
        return "" + recv
      end
      return recv
    when :reverse
      if recv.is_a?(List) || recv.is_a?(Array)
        res = List.new
        i = recv.length - 1
        while i >= 0
          res.push(recv[i])
          i -= 1
        end
        return res
      end
      return recv.to_s.reverse
    when :uniq
      if recv.is_a?(List) || recv.is_a?(Array)
        res = List.new
        i = 0
        while i < recv.length
          elem = recv[i]
          found = false
          j = 0
          while j < res.length
            if res[j] == elem
              found = true
              break
            end
            j += 1
          end
          res.push(elem) unless found
          i += 1
        end
        return res
      end
      return recv
    when :compact
      if recv.is_a?(List) || recv.is_a?(Array)
        res = List.new
        i = 0
        while i < recv.length
          elem = recv[i]
          res.push(elem) if elem != nil
          i += 1
        end
        return res
      end
      return recv
    when :flatten
      if recv.is_a?(List) || recv.is_a?(Array)
        res = List.new
        i = 0
        while i < recv.length
          elem = recv[i]
          if elem.is_a?(List) || elem.is_a?(Array)
            j = 0
            while j < elem.length
              res.push(elem[j])
              j += 1
            end
          else
            res.push(elem)
          end
          i += 1
        end
        return res
      end
      return recv
    when :keys
      return stage0_hash_keys(recv)
    when :values
      return stage0_hash_values(recv)
    when :merge
      return stage0_hash_merge(recv, evaluate(arg_nodes[0]))
    when :fetch
      k = evaluate(arg_nodes[0])
      if recv.is_a?(Hash)
        return recv[k] if recv.key?(k)
        if k.is_a?(String) && recv.key?(k.to_sym)
          return recv[k.to_sym]
        elsif k.is_a?(Symbol) && recv.key?(k.to_s)
          return recv[k.to_s]
        end
      end
      return argc > 1 ? evaluate(arg_nodes[1]) : nil
    when :split
      sep = argc > 0 ? evaluate(arg_nodes[0]).to_s : " "
      parts = recv.to_s.split(sep)
      res = List.new
      i = 0
      while i < parts.length
        res.push(parts[i])
        i += 1
      end
      return res
    when :lines
      parts = recv.to_s.lines
      res = List.new
      i = 0
      while i < parts.length
        res.push(parts[i])
        i += 1
      end
      return res
    when :bytes
      bs = recv.to_s.bytes
      res = List.new
      i = 0
      while i < bs.length
        res.push(bs[i])
        i += 1
      end
      return res
    when :chars
      s = recv.to_s
      n = s.bytesize
      ascii = true
      i = 0
      while i < n
        if s.getbyte(i) >= 128
          ascii = false
          break
        end
        i += 1
      end
      res = List.new
      if ascii
        ac = @stage0_ascii_chars
        i = 0
        while i < n
          res.push(ac[s.getbyte(i)])
          i += 1
        end
        return res
      end
      cs = s.chars
      i = 0
      while i < cs.length
        res.push(cs[i])
        i += 1
      end
      return res
    when :codes, :codepoints
      cps = recv.to_s.codepoints
      res = List.new
      i = 0
      while i < cps.length
        res.push(cps[i])
        i += 1
      end
      return res
    when :lchs
      cps = recv.to_s.codepoints
      res = List.new
      has_lang = argc > 0 && evaluate(arg_nodes[0]).is_a?(String)
      lex64_tag = -1055531162664960
      i = 0
      while i < cps.length
        cp = cps[i]
        if has_lang
          fl = stage0_tungsten_lchs_flag(cp)
          res.push(lex64_tag | (cp << 18) | fl)
        else
          fl = 0
          fl |= 0x40 if (cp >= 97 && cp <= 122) || (cp >= 65 && cp <= 90) || cp == 95
          fl |= 0x20 if (fl & 0x40) != 0 || (cp >= 48 && cp <= 57)
          fl |= 0x10 if cp == 32 || cp == 9
          fl |= 0x08 if (cp >= 48 && cp <= 57) || (cp >= 97 && cp <= 102) || (cp >= 65 && cp <= 70)
          fl |= 0x01 if cp >= 48 && cp <= 57
          digit = (cp >= 48 && cp <= 57) ? cp - 48 : 0xF
          res.push(lex64_tag | (cp << 18) | (digit << 7) | fl)
        end
        i += 1
      end
      return res
    when :index
      needle = evaluate(arg_nodes[0])
      if recv.is_a?(List) || recv.is_a?(Array)
        i = argc > 1 ? evaluate(arg_nodes[1]).to_i : 0
        while i < recv.length
          return i if recv[i] == needle
          i += 1
        end
        return nil
      else
        s = recv.to_s
        return argc > 1 ? s.index(needle.to_s, evaluate(arg_nodes[1]).to_i) : s.index(needle.to_s)
      end
    when :rindex
      needle = evaluate(arg_nodes[0]).to_s
      return argc > 1 ? recv.to_s.rindex(needle, evaluate(arg_nodes[1]).to_i) : recv.to_s.rindex(needle)
    when :join
      sep = argc > 0 ? evaluate(arg_nodes[0]).to_s : ""
      if recv.is_a?(List) || recv.is_a?(Array)
        n = recv.length
        return "" if n == 0
        return w_to_s(recv[0]) if n == 1
        parts = [""]
        parts.clear
        i = 0
        while i < n
          parts.push(w_to_s(recv[i]))
          i += 1
        end
        return parts.join(sep)
      end
      return ""
    when :replace, :gsub
      a = evaluate(arg_nodes[0]).to_s
      if argc > 1
        b = evaluate(arg_nodes[1]).to_s
        return recv.to_s.gsub(a, b)
      end
      return recv.to_s
    when :sub
      a = evaluate(arg_nodes[0]).to_s
      b = evaluate(arg_nodes[1]).to_s
      return recv.to_s.sub(a, b)
    when :strip, :trim
      return recv.to_s.strip
    when :lstrip
      return recv.to_s.lstrip
    when :rstrip
      return recv.to_s.rstrip
    when :chomp
      return recv.to_s.chomp
    when :upcase, :upper
      return recv.to_s.upcase
    when :downcase, :lower
      return recv.to_s.downcase
    when :pad_left, :rjust
      width = evaluate(arg_nodes[0]).to_i
      pad_ch = argc > 1 ? evaluate(arg_nodes[1]).to_s : " "
      pad_ch = " " if pad_ch == ""
      s = recv.to_s
      while s.length < width
        s = pad_ch + s
      end
      return s
    when :pad_right, :ljust
      width = evaluate(arg_nodes[0]).to_i
      pad_ch = argc > 1 ? evaluate(arg_nodes[1]).to_s : " "
      pad_ch = " " if pad_ch == ""
      s = recv.to_s
      while s.length < width
        s = s + pad_ch
      end
      return s
    when :to_i
      return argc > 0 ? recv.to_s.to_i(evaluate(arg_nodes[0]).to_i) : recv.to_i
    when :to_f
      return recv.to_f
    when :to_sym
      return recv.to_s.to_sym
    when :to_a
      return recv if recv.is_a?(List)
      return List.new(recv) if recv.is_a?(Array)
      return List.new
    when :ord
      return recv.to_s.ord
    when :chr
      cp_chr = recv.to_i & 0xFF
      return @stage0_ascii_chars[cp_chr] if cp_chr < 128
      return cp_chr.chr
    when :abs
      return recv < 0 ? -recv : recv
    when :min
      if recv.is_a?(List) || recv.is_a?(Array)
        return nil if recv.length == 0
        m = recv[0]
        i = 1
        while i < recv.length
          m = recv[i] if recv[i] < m
          i += 1
        end
        return m
      end
      other = evaluate(arg_nodes[0])
      return recv <= other ? recv : other
    when :max
      if recv.is_a?(List) || recv.is_a?(Array)
        return nil if recv.length == 0
        m = recv[0]
        i = 1
        while i < recv.length
          m = recv[i] if recv[i] > m
          i += 1
        end
        return m
      end
      other = evaluate(arg_nodes[0])
      return recv >= other ? recv : other
    when :sort
      if recv.is_a?(List) || recv.is_a?(Array)
        res = List.new
        i = 0
        while i < recv.length
          res.push(recv[i])
          i += 1
        end
        n = res.length
        a_idx = 0
        while a_idx < n
          b_idx = a_idx + 1
          while b_idx < n
            if res[b_idx].to_s < res[a_idx].to_s
              tmp = res[a_idx]
              res[a_idx] = res[b_idx]
              res[b_idx] = tmp
            end
            b_idx += 1
          end
          a_idx += 1
        end
        return res
      end
      return recv
    when :first
      return (recv.is_a?(List) || recv.is_a?(Array)) && recv.length > 0 ? recv[0] : nil
    when :last
      return (recv.is_a?(List) || recv.is_a?(Array)) && recv.length > 0 ? recv[recv.length - 1] : nil
    when :count
      if recv.is_a?(String) && argc > 0
        s = recv.to_s
        sub = evaluate(arg_nodes[0]).to_s
        return 0 if sub.bytesize == 0
        b0 = sub.getbyte(0)
        c = 0
        i = 0
        slen = s.bytesize
        while i < slen
          c += 1 if s.getbyte(i) == b0
          i += 1
        end
        return c
      elsif recv.is_a?(List) || recv.is_a?(Array)
        if argc > 0
          target = evaluate(arg_nodes[0])
          c = 0
          i = 0
          while i < recv.length
            c += 1 if recv[i] == target
            i += 1
          end
          return c
        end
        return recv.length
      end
      return 0
    when :any?
      return (recv.is_a?(List) || recv.is_a?(Array)) ? (recv.length > 0) : false
    when :all?
      return true
    when :none?
      return (recv.is_a?(List) || recv.is_a?(Array)) ? (recv.length == 0) : true
    when :each, :each_with_index, :times, :sort_by
      return recv
    when :map, :collect, :select, :filter, :find_all, :reject, :flat_map
      return List.new
    when :find, :detect
      return nil
    when :valid_utf8?
      return true
    when :freeze
      return recv
    when :frozen?
      return false
    end

    if recv.is_a?(Hash)
      field_value = recv[name_sym]
      return field_value unless field_value.nil?
      return recv[name_sym.to_s]
    end
    nil
  end

  def stage0_static_hash_key?(node)
    doc = node.doc
    doc == 16 || doc == 4
  end

  def stage0_static_hash_key(node)
    node.value.to_s
  end

  def stage0_var_name(node)
    node.is_a?(Var) ? node.name : ("" + node.name.to_s)
  end

  def stage0_mark_env(env)
    @stage0_next_layout_shape += 1
    env.mark_layout_shape(@stage0_next_layout_shape)
  end

  def stage0_env_get(env, name)
    env.get(name)
  end

  def stage0_poly_poly_hash_get_str(table, key)
    table[key]
  end

  def stage0_call_name(node)
    node.is_a?(Call) ? node.name : ("" + node.name.to_s)
  end

  def stage0_str_to_sym(name)
    name.to_sym
  end

  def stage0_str_poly_hash_get(table, key)
    table[key]
  end

  def stage0_binary_op_operator(node)
    node.operator
  end

  def resolve_use_path(use_path)
    path = use_path.to_s
    base = "."
    if @current_file != nil
      last_slash = -1
      i = 0
      while i < @current_file.length
        if @current_file.byteslice(i, 1) == "/"
          last_slash = i
        end
        i += 1
      end
      if last_slash > 0
        base = @current_file.byteslice(0, last_slash)
      end
    end
    candidate = base + "/" + path
    if !candidate.end_with?(".w")
      candidate = candidate + ".w"
    end
    return candidate if File.exist?(candidate)

    candidate = "compiler/" + path
    if !candidate.end_with?(".w")
      candidate = candidate + ".w"
    end
    return candidate if File.exist?(candidate)

    candidate = path
    if !candidate.end_with?(".w")
      candidate = candidate + ".w"
    end
    candidate
  end

  def visit_in_test(node)
    lhs = evaluate(node.lhs)
    elements = node.elements
    i = 0
    while i < elements.length
      ev = evaluate(elements[i])
      if ev.is_a?(WRange)
        return true if ev.include?(lhs)
      else
        return true if ev == lhs
      end
      i += 1
    end
    false
  end

  def stage0_skip_use_path?(path)
    return true if path.end_with?("core/numeric/int.w")
    return true if path.end_with?("core/string.w")
    return true if path.end_with?("core/string_buffer.w")
    false
  end

  def visit_use(node)
    path = resolve_use_path(node.path)
    return nil if stage0_skip_use_path?(path)
    return nil if @loaded_files[path] == true

    @loaded_files[path] = true
    raw_source = File.read(path)
    old_file = @current_file
    old_source = @source
    old_returning = @returning
    old_return_value = @return_value
    old_exiting = @exiting
    @current_file = path
    @source = raw_source
    ast = parse_with_file(raw_source, path)
    evaluate(ast)
    @returning = old_returning
    @return_value = old_return_value
    @exiting = old_exiting
    @current_file = old_file
    @source = old_source
    nil
  end
  def visit_var_slow(node, vkind)
    name = node.name
    env_shape = @env.layout_shape
    idx = @env.slot_index(name)
    if idx > 0
      if env_shape > 1
        node.cached_slot = idx
        node.cached_layout_shape = env_shape
      end
      val = @env.get_slot(idx)
      return val unless val.is_a?(UnboundSlot)
    end

    pe = @env
    looking = true
    while looking
      if pe.barrier && !pe.parent.nil?
        pidx = @top_env.slot_index(name)
        if pidx > 0
          val = @top_env.get_slot(pidx)
          unless val.is_a?(UnboundSlot)
            if val.is_a?(Def) && (val.args.nil? || val.args.length == 0)
              return stage0_call_def_from_nodes(val, name, [], nil)
            end
            if env_shape > 1 && idx <= 0 && !val.is_a?(Def)
              node.cached_miss_shape = env_shape
              node.cached_top_slot = pidx
            end
            return val
          end
        end
        looking = false
      else
        np = pe.parent
        if np.nil?
          looking = false
        else
          pe = np
          pidx = pe.slot_index(name)
          if pidx > 0
            val = pe.get_slot(pidx)
            unless val.is_a?(UnboundSlot)
              if pe.equal?(@top_env) && val.is_a?(Def) && (val.args.nil? || val.args.length == 0)
                return stage0_call_def_from_nodes(val, name, [], nil)
              end
              return val
            end
          end
        end
      end
    end

    return 0 if vkind == 2

    if @self_stack.length > 0
      self_obj = @self_stack[@self_stack.length - 1]
      if self_obj.is_a?(WObject)
        wcls = self_obj.w_class
        if !wcls.nil?
          m = nil
          if node.cached_dispatch_owner.equal?(wcls) && node.cached_dispatch_version == @method_cache_epoch
            m = node.cached_w_method
          else
            m = wcls.lookup_method(name)
            node.cached_dispatch_owner = wcls
            node.cached_dispatch_version = @method_cache_epoch
            node.cached_w_method = m
          end
          return call_w_method_from_nodes(self_obj, m, nil) if !m.nil?
        end
      elsif self_obj.is_a?(WClass)
        cm = self_obj.lookup_class_method(name)
        return call_w_method_from_nodes(self_obj, cm, nil) if !cm.nil?
      elsif self_obj.is_a?(PackedNode)
        node_cls = @classes["Tungsten:AST:Node"] || @classes["Node"]
        if !node_cls.nil?
          m = node_cls.lookup_method(name)
          return call_w_method_from_nodes(self_obj, m, nil) if !m.nil?
        end
      elsif self_obj.is_a?(Integer) && (self_obj & -70368744177664) == -1125899906842624
        tok_cls = @classes["Token"]
        if !tok_cls.nil?
          m = tok_cls.lookup_method(name)
          return call_w_method_from_nodes(self_obj, m, nil) if !m.nil?
        end
      end
    end

    if node.cached_const_epoch == @method_cache_epoch && !node.cached_const_val.nil?
      return node.cached_const_val
    end

    fn = @top_env.values_table[name]
    if fn.is_a?(Def) && (fn.args.nil? || fn.args.length == 0)
      return stage0_call_def_from_nodes(fn, name, [], nil)
    end

    klass = @classes[name]
    unless klass.nil?
      node.cached_const_val = klass
      node.cached_const_epoch = @method_cache_epoch
      return klass
    end

    nil
  end
RUBY
postamble_marker = "\n  end\n\n\n# -- implementations/spinel/stage0/postamble.rb --"
final_bundle = replace_method(final_bundle, "visit_var", <<~RUBY)
  def visit_var(node)
    vkind = node.var_kind
    if vkind == 1
      return @self_stack.length > 0 ? @self_stack[@self_stack.length - 1] : nil
    end

    env_shape = @env.layout_shape
    if env_shape > 1
      if node.cached_layout_shape == env_shape
        val = @env.get_slot(node.cached_slot)
        return val unless val.is_a?(UnboundSlot)
      elsif node.cached_miss_shape == env_shape
        return @top_env.get_slot(node.cached_top_slot)
      end
    end

    visit_var_slow(node, vkind)
  end
RUBY
final_bundle = final_bundle.sub(postamble_marker) { final_use_methods + "\n  end\n\n\n# -- implementations/spinel/stage0/postamble.rb --" }

# Tungsten declares a `class Time < Literal` stub that visit_time_literal
# wraps values in. Spinel's runtime owns the C name `sp_Time` for its own
# wallclock helpers, so emitting another `sp_Time` from this Ruby class
# fails with `typedef redefinition`. Rename to a Tungsten-prefixed name
# both at the class declaration and at the single call site.
final_bundle = final_bundle.gsub(/\bclass Time\b/, "class TungstenTime")
final_bundle = final_bundle.gsub(/\bTime\.new\b/, "TungstenTime.new")

# Tungsten's AST `class Symbol < Value` literal node collides with spinel's
# built-in Symbol type: spinel emits an open-class method
# `sp___oc_Symbol_initialize(sp_RbVal self, ...)` with a POLY `self`, so the
# `@doc`/`@value` ivar stores (`self->iv_doc` …) fail to compile. Rename the
# AST node class to a non-colliding name at exactly the three sites that mean
# the AST node — the class declaration, the two parser construction sites, and
# the one `arg.is_a?(Symbol)` type check in define_accessor. The remaining
# `Symbol` references (the BUILTIN_TYPES word list and
# `value.is_a?(Symbol)` in stage0_ruby_ast_to_compiler_value) refer to the
# Ruby built-in symbol and MUST stay as `Symbol`.
final_bundle = final_bundle.gsub(/\bclass Symbol < Value\b/, "class SymbolLit < Value")
final_bundle = final_bundle.gsub(/\bSymbol\.new\(/, "SymbolLit.new(")
final_bundle = final_bundle.gsub(/\barg\.is_a\?\(Symbol\)/, "arg.is_a?(SymbolLit)")

# Module#simple_name uses bare `name` (= Ruby's Module#name, runtime class-name
# reflection) which spinel can't provide — it resolves to int 0, so the gsub
# scrutinee compiles as `sp_poly_to_s(0)` (passing int to sp_RbVal). The method
# is NEVER called anywhere in the stage0 bundle (cosmetic class-name helper), so
# stub it rather than fight spinel's lack of Module reflection.
final_bundle = replace_method(final_bundle, "simple_name", <<~RUBY)
  def simple_name
    ""
  end
RUBY

# spinel has no Array#to_h(&block). The interpreter builds membership sets
# with `%w[...].to_h { |w| [ w, true ] }` (TUNGSTEN_KEYWORDS / type-name
# words), which spinel can't lower (emits 0 -> `undefined method to_h for
# str_array` at init). Since build_bundle runs in Ruby, parse the %w at build
# time and emit an explicit `{ "w" => true, ... }` hash literal (a non-empty
# str->bool hash spinel types fine and indexes for membership exactly the same).
# spinel has no Hash#compare_by_identity (a key-comparison perf knob). The
# interpreter uses `{}.compare_by_identity` for dispatch/seen caches; value
# comparison is correct for stage0 (slightly slower at most), so strip it.
final_bundle = final_bundle.gsub(/\.compare_by_identity\b/, "")

final_bundle = final_bundle.gsub(/%([wi])\[([^\]]*)\]\.to_h \{ \|\w+\| \[ \w+, true \] \}/m) do
  sigil = Regexp.last_match(1)
  words = Regexp.last_match(2).split
  # %w -> string keys ("word" => true); %i -> symbol keys (:SYM => true).
  pairs = words.map { |w| sigil == "i" ? ":#{w} => true" : "#{w.inspect} => true" }.join(", ")
  "{ #{pairs} }"
end

# The upstream C compiler (matz's Ruby->C rewrite, fe74361b) cannot lower a
# forwarding `super` whose superclass is a runtime built-in
# (ForwardingSuperNode / "unsupported super: no parent method"). Two stage0
# super clusters forward to built-ins and are BOTH dead code here, so strip
# them so the C compiler never sees the forwarding super:
#
# 1. The Parser's StringScanner-subclass adapter methods (error/next_token/
#    scan/skip/check/pos/pos=/string/rest/eos?) only fall back to `super`
#    (StringScanner) when @lexer_adapter is nil — but stage0 ALWAYS sets
#    @lexer_adapter (the CodepointLexer), so the super branch never runs.
# 2. The DispatchProfiling module (prepended, gated on DISPATCH_PROFILE_ENABLED)
#    is debug-only and disabled in stage0.
final_bundle = final_bundle.gsub(/^[ \t]*return super unless @lexer_adapter\n/, "")
final_bundle = final_bundle.gsub(/@lexer_adapter \? (.+?) : super\b/, "\\1")
final_bundle = final_bundle.gsub(
  /def pos=\(new_pos\)\n[ \t]*if @lexer_adapter\n[ \t]*@lexer_adapter\.pos = new_pos\n[ \t]*else\n[ \t]*super\n[ \t]*end/,
  # The default `= 0` pins new_pos to an int parameter. @lexer_adapter is always
  # a CodepointLexer in stage0, but the cmig backend's inference unions Parser
  # into @lexer_adapter's type, so it emits a `case Parser:` arm in the
  # `@lexer_adapter.pos = x` dispatch that references sp_Parser_pos_set. Without
  # a typed parameter cmig's backstop prunes Parser#pos= as never-bound,
  # leaving that arm dangling at link time. Setter calls always pass exactly one
  # argument, so the default is never used at runtime; it only types the param.
  "def pos=(new_pos = 0)\n      @lexer_adapter.pos = new_pos"
)
final_bundle = final_bundle.gsub(
  /^    if DISPATCH_PROFILE_ENABLED\n.*?\n      prepend DispatchProfiling\n    end\n/m, ""
)
final_bundle = final_bundle.gsub(/^([ \t]*)private[ \t]*$/, "\\1public")
final_bundle = final_bundle.gsub(/\bList\.new\(\)/, "List.new")
final_bundle = final_bundle.gsub(/\bList\.new\(/, "List.from(")

File.write(out, final_bundle)

puts out
