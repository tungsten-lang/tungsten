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

sources << tungsten_file("ast/node.rb")
sources.concat(files_under("ast").reject { |path| path.end_with?("/node.rb") })

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
          class WObject
            attr_accessor :w_class, :instance_vars

            def initialize(w_class)
              @w_class = w_class
              # Poly-placeholder entries force spinel to type @instance_vars
              # as a str_poly_hash (mixed int+string values). An empty {}
              # fixpoints to a str_int_hash on the early pass, so get_ivar's
              # return type locks to int even though set_ivar stores poly
              # values — making spinel both mis-store the values and wrap the
              # (runtime-poly) get_ivar result in sp_box_int. The distinctively
              # named keys are inert (all ivar reads are specific-key lookups,
              # never full iteration). Mirrors Environment#initialize's @values.
              @instance_vars = {"__spinel_ivar_poly_i__" => 0, "__spinel_ivar_poly_s__" => ""}
            end

            def get_ivar(name)
              # Route through a poly-seeded local so get_ivar's return type is
              # unambiguously sp_RbVal. Callers (visit_instance_var) otherwise
              # fixpoint get_ivar's return to int on an early pass and insert a
              # spurious sp_box_int() around the (runtime-poly) result.
              v = nil
              v = @instance_vars[name.to_s]
              v
            end

            def set_ivar(name, value)
              @instance_vars[name.to_s] = value
              value
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
            attr_accessor :name, :superclass, :methods, :traits, :version, :class_vars

            def initialize(name, superclass = nil)
              @name = name
              @superclass = superclass
              @methods = {}
              @traits = []
              @version = 0
              @class_vars = {}
            end

            def lookup_method(name)
              # The "" + name.to_s key hoist that lived here was
              # made redundant by spinel commit efeaf10:
              #   force_class_method_param_type("WClass",
              #     "lookup_method", "name", "string")
              # plus force_ivar_type("WClass", "@methods",
              # "str_poly_hash") in 0d26277. Spinel now lowers
              # @methods[name] to sp_StrPolyHash_get(self->iv_methods,
              # lv_name) without an intermediate concat alloc.
              klass = self
              while klass != nil
                method = klass.methods[name]
                return method if method != nil

                klass = klass.superclass
              end
              nil
            end

            def define_method(name, method)
              # No "" + hoist — codegen-side string-param override
              # (see #lookup_method) makes name already const char*.
              @methods[name] = method
              @version += 1
              method
            end

            def include_trait(trait)
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
  body = replace_method(body, "initialize", <<~RUBY)
    def initialize
      @type = nil
      @value = nil
      @file = nil
      @row = 0
      @col = 0
    end
  RUBY
  body = replace_method(body, "keyword?", <<~RUBY)
    def keyword?(sym)
      false
    end
  RUBY
  body = replace_method(body, "to_s", <<~RUBY)
    def to_s
      "<Token>"
    end
  RUBY
  body = replace_method(body, "suffix?", <<~RUBY)
    def suffix?
      false
    end
  RUBY
  body = replace_method(body, "assignment_operator?", <<~RUBY)
    def assignment_operator?
      false
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
  # These class constants are lazy/data-table caches that the stage0 lexer never
  # reads (every reader is rewritten away below), so they were nilled out to
  # shrink the bundle. A `= nil` constant has no inferable type, which the C
  # Spinel backend cannot declare (it emits `cst_X = 0` with no declaration), so
  # delete the declarations outright instead of nilling them. Dropping a dead
  # constant is equivalent for the legacy Ruby path (its readers are unreachable
  # at runtime, and the C backend already eliminates each `nil`-receiver read).
  body = body.sub(/^\s*KEYWORDS_BY_FIRST_AND_LENGTH = .*?\.freeze\n\s*(?=TYPE_NAMES_BY_FIRST_AND_LENGTH = )/m, "")
  body = body.sub(/^\s*TYPE_NAMES_BY_FIRST_AND_LENGTH = .*?\.freeze\n\s*(?=TYPE_NAMES = )/m, "")
  # TYPE_NAMES keeps a typed (empty-hash) value rather than being deleted: its
  # reader `type_hint_start?` does `TYPE_NAMES.each_key`, and deleting the
  # constant would let that resolve to Lexer::TYPE_NAMES (a String array), whose
  # `each_key` is unsupported. An empty hash iterates zero times — the same
  # behavior the nil cache had in stage0 — and the C backend can declare it.
  body = body.gsub(/^\s*TYPE_NAMES = .*?\.freeze\n/, "    TYPE_NAMES = {}\n")
  body = body.sub(/^\s*ONE_CHAR_TOKENS = \{\n.*?^\s*\}\.freeze\n/m, "")
  body = body.sub(/^\s*REGEX_PROFILE_NAMES = \{\n.*?^\s*\}\.freeze\n/m, "")
  body = body.gsub(/^\s*SUBSCRIPT_TAIL = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*SUPERSCRIPT_DIGITS = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*UNICODE_IDENTIFIER = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_BINARY = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_OCTAL = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_DECIMAL = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_HEX_PREFIX = .*?\.freeze\n/, "")
  body = body.gsub(/^\s*BYTE_ARRAY_HEX = .*?\.freeze\n/, "")
  body = body.gsub("def initialize(code, profile: false)", "def initialize(code)")
  body = body.gsub("@profile_enabled = profile", "@profile_enabled = false")
  body = body.gsub(/^\s*@profile_.* if profile\n/, "")
  body = body.gsub("return scan_regex_capture if regex_capture_start?\n", "")
  body = body.gsub("return if hex_reference_literal_possible? && network_literal_shape_possible? && scan_network_literal", "return if false")
  body = body.gsub("return if byte(1) == 58 && network_literal_shape_possible? && scan_network_literal", "return if false")
  body = body.gsub("return if bracketed_ip6_start? && scan_network_literal", "return if false")
  body = body.gsub("if (fe80_start? || (hex_reference_literal_possible? && network_literal_shape_possible?)) && scan_network_literal", "if false")
  body = body.gsub(
    "return scan_codepoint_literal if byte(1) == 43 && hex_byte?(byte(2))",
    "if byte(1) == 43\n          return scan_codepoint_literal if hex_byte?(byte(2))\n        end"
  )
  body = body.sub(/      when 126\n        if digit_byte\?\(byte\(1\)\).*?        end\n      when 48/m, "      when 126\n        return emit_fixed(:~, 1)\n      when 48")
  body = body.sub(/      when 95\n        if match_bytes\?\("__FILE__"\).*?        return scan_identifier\n      when 74/m, "      when 95\n        return scan_identifier\n      when 74")
  body = body.sub(/      when 117\n        return scan_wvalue if byte\(1\) == 48 && byte\(2\) == 120\n\n        return scan_identifier\n      when 80/m,
                  "      when 117\n        return scan_identifier\n      when 80")
  body = body.gsub(
    "return scan_operator_or_punctuation if byte(1) == 42 || byte(1) == 61",
    "if byte(1) == 42\n          return scan_operator_or_punctuation\n        end\n        if byte(1) == 61\n          return scan_operator_or_punctuation\n        end"
  )
  body = body.gsub(
    "return scan_operator_or_punctuation if byte(1) == 61 || byte(1) == 62 || byte(1) == 126",
    "if byte(1) == 61\n          return scan_operator_or_punctuation\n        end\n        if byte(1) == 62\n          return scan_operator_or_punctuation\n        end\n        if byte(1) == 126\n          return scan_operator_or_punctuation\n        end"
  )
  body = body.sub(/        if \(@pos\.zero\? \|\| @line_start\) && space_byte\?\(next_byte\) && upper_byte\?\(byte\(2\)\)\n.*?        end\n\n        profile_path\(:plus\) if @profile_enabled\n/m,
                  "        profile_path(:plus) if @profile_enabled\n")
  body = body.sub(/      when 46\n        return scan_dot if byte\(1\) == 46\n\n        # Phase 4e dot-prefix elementwise operators:.*?\n\n        return emit_fixed\(:\"\.\"\, 1\)\n      when 47/m,
                  "      when 46\n        return emit_fixed(:\".\", 1)\n      when 47")
  body = body.gsub("if next_byte == 126 && approximate_float_literal_possible?", "if false")
  body = replace_method(body, "clean", <<~RUBY)
    def clean(code)
      code.to_s
    end
  RUBY
  body = replace_method(body, "set_token", <<~RUBY)
    def set_token(type, value = nil, row = @row, col = @col)
      @token.reset_location
      @token.file = 0
      @token.row = row
      @token.col = col
      @token.type = type
      @token.value = value.to_s
    end
  RUBY
  body = replace_method(body, "newline_byte?", <<~RUBY)
    def newline_byte?(b)
      b >= 0 && b == 10
    end
  RUBY
  body = replace_method(body, "space_byte?", <<~RUBY)
    def space_byte?(b)
      b >= 0 && b == 32
    end
  RUBY
  body = replace_method(body, "digit_byte?", <<~RUBY)
    def digit_byte?(b)
      b >= 48 && b <= 57
    end
  RUBY
  body = replace_method(body, "sign_byte?", <<~RUBY)
    def sign_byte?(b)
      b >= 0 && (b == 43 || b == 45)
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
      b >= 0 && (lower_byte?(b) || upper_byte?(b))
    end
  RUBY
  body = replace_method(body, "ident_start_byte?", <<~RUBY)
    def ident_start_byte?(b)
      b >= 0 && (lower_byte?(b) || b == 95)
    end
  RUBY
  body = replace_method(body, "ident_continue_byte?", <<~RUBY)
    def ident_continue_byte?(b)
      b >= 0 && (ident_start_byte?(b) || digit_byte?(b))
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
      b >= 0 &&
        (b == 98 || b == 66 || b == 100 || b == 111 || b == 79 || b == 114 || b == 118 || b == 120 || b == 88)
    end
  RUBY
  body = replace_method(body, "terminator_byte?", <<~RUBY)
    def terminator_byte?(b)
      b >= 0 &&
        (b == 0 || b == 32 || b == 10 || b == 9 || b == 13 || b == 12 || b == 35 || b == 59 ||
          b == 40 || b == 41 || b == 91 || b == 93 || b == 123 || b == 125 || b == 44)
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
  body = replace_method(body, "scan_name", <<~RUBY)
    def scan_name
      start_col = @col
      start = @pos
      while !eof?
        b = byte
        ok = false
        if b >= 65
          if b <= 90
            ok = true
          end
        end
        if b >= 97
          if b <= 122
            ok = true
          end
        end
        if b >= 48
          if b <= 57
            ok = true
          end
        end
        if b == 95
          ok = true
        end
        if ok
          advance
        else
          break
        end
      end
      set_token(:ID, slice(start), @row, start_col)
    end
  RUBY
  body = replace_method(body, "scan_operator_or_punctuation", <<~RUBY)
    def scan_operator_or_punctuation
      start_col = @col
      if byte == 60
        if byte(1) == 60
          advance(2)
          return set_token(:<<, nil, @row, start_col)
        end
      end
      if byte == 43
        if byte(1) == 61
          advance(2)
          return set_token(:"+=", nil, @row, start_col)
        end
      end
      if byte == 45
        if byte(1) == 61
          advance(2)
          return set_token(:"-=", nil, @row, start_col)
        end
      end
      if byte == 45
        if byte(1) == 62
          advance(2)
          return set_token(:"->", nil, @row, start_col)
        end
      end
      if byte == 61
        if byte(1) == 61
          advance(2)
          return set_token(:==, nil, @row, start_col)
        end
      end
      if byte == 33
        if byte(1) == 61
          advance(2)
          return set_token(:!=, nil, @row, start_col)
        end
      end
      if byte == 60
        if byte(1) == 61
          advance(2)
          return set_token(:<=, nil, @row, start_col)
        end
      end
      if byte == 62
        if byte(1) == 61
          advance(2)
          return set_token(:>=, nil, @row, start_col)
        end
      end
      if byte == 124
        if byte(1) == 124
          advance(2)
          return set_token(:"||", nil, @row, start_col)
        end
      end
      if byte == 38
        if byte(1) == 38
          advance(2)
          return set_token(:"&&", nil, @row, start_col)
        end
      end
      emit_fixed(byte.chr.to_sym, 1)
    end
  RUBY
  body = replace_method(body, "scan_multi_char_operator", <<~RUBY)
    def scan_multi_char_operator(one, start_col)
      if one == 60
        if byte(1) == 60
          return emit_operator(:<<, 2, start_col)
        end
        if byte(1) == 61
          return emit_operator(:<=, 2, start_col)
        end
      end
      if one == 43
        if byte(1) == 61
          return emit_operator(:"+=", 2, start_col)
        end
      end
      if one == 45
        if byte(1) == 61
          return emit_operator(:"-=", 2, start_col)
        end
        if byte(1) == 62
          return emit_operator(:"->", 2, start_col)
        end
      end
      if one == 61
        if byte(1) == 61
          return emit_operator(:==, 2, start_col)
        end
      end
      if one == 33
        if byte(1) == 61
          return emit_operator(:!=, 2, start_col)
        end
      end
      if one == 62
        if byte(1) == 61
          return emit_operator(:>=, 2, start_col)
        end
      end
      if one == 124
        if byte(1) == 124
          return emit_operator(:"||", 2, start_col)
        end
      end
      if one == 38
        if byte(1) == 38
          return emit_operator(:"&&", 2, start_col)
        end
      end
      nil
    end
  RUBY
  body = replace_method(body, "scan_space_or_newline", <<~RUBY)
    def scan_space_or_newline
      start_col = @col
      while space_byte?(byte)
        advance
      end
      if byte == 10
        advance
        @row += 1
        @col = 1
        @line_start = true
        set_token(:NL, 1, @row, start_col)
      else
        set_token(:SP, nil, @row, start_col)
      end
    end
  RUBY
  body = replace_method(body, "scan_comment", <<~RUBY)
    def scan_comment
      start_col = @col
      while @pos < @length
        if newline_byte?(byte)
          break
        end
        advance
      end
      if newline_byte?(byte)
        advance
        set_token(:NL, nil, @row, start_col)
        @row += 1
        @col = 1
        @line_start = true
      else
        set_token(:EOF, nil, @row, start_col)
      end
    end
  RUBY
  body = replace_method(body, "scan_key_literal", <<~RUBY)
    def scan_key_literal
      start_col = @col
      advance
      content_start = @pos
      while @pos < @length
        if byte == 93
          break
        end
        advance
      end
      error "unterminated key literal" if eof?

      content = slice(content_start).strip
      advance
      set_token(:KEY, content, @row, start_col)
    end
  RUBY
  body = replace_method(body, "consume_newlines", <<~RUBY)
    def consume_newlines
      p = @pos
      count = 0
      loop do
        before_spaces = p
        while p < @length
          if @source.getbyte(p) == 32
            p += 1
          else
            break
          end
        end
        if p < @length
          if @source.getbyte(p) == 10
            count += 1
            p += 1
          else
            p = before_spaces
            break
          end
        else
          p = before_spaces
          break
        end
      end
      return nil if count == 0

      advance(p - @pos)
      @row += count
      @col = 1
      @line_start = true
      set_token(:NL, count, @row, 1)
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
  body = replace_method(body, "scan_symbol_operator", <<~RUBY)
    def scan_symbol_operator
      return false unless byte == 58

      SYMBOL_OPERATORS.each do |op|
        next unless match_bytes?(op)

        advance(op.bytesize)
        return true
      end
      false
    end
  RUBY
  body = replace_method(body, "slice", <<~RUBY)
    def slice(start_pos = @pos, end_pos = @pos)
      @source.byteslice(start_pos, end_pos - start_pos)
    end
  RUBY
  body = replace_method(body, "pos=", <<~RUBY)
    def pos=(new_pos)
      @pos = new_pos
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
      str = ""

      loop do
        error "unterminated string" if eof?

        case byte
        when 34
          advance
          break
        when 92
          str = str + scan_string_escape
        else
          chunk_start = @pos
          advance_utf8_char
          str = str + slice(chunk_start)
        end
      end

      set_token(:STRING, str, @row, start_col)
    end
  RUBY
  body = replace_method(body, "scan_string_escape", <<~RUBY)
    def scan_string_escape
      advance
      b = byte
      if b == 110
        advance
        return 10.chr
      end
      if b == 114
        advance
        return 13.chr
      end
      if b == 116
        advance
        return 9.chr
      end
      if b == 92
        advance
        return 92.chr
      end
      if b == 34
        advance
        return 34.chr
      end
      if b == 91
        advance
        return "["
      end
      if b == 93
        advance
        return "]"
      end
      92.chr
    end
  RUBY
  body = replace_method(body, "scan_ident_bytes", <<~RUBY)
    def scan_ident_bytes
      advance while ident_continue_byte?(byte)
    end
  RUBY
  body = replace_method(body, "scan_identifier", <<~RUBY)
    def scan_identifier
      start_col = @col
      start = @pos
      scan_ident_bytes
      text = slice(start, @pos)
      if text == "if"
        return set_token(:KEYWORD, text, @row, start_col)
      end
      if text == "else"
        return set_token(:KEYWORD, text, @row, start_col)
      end
      if text == "elsif"
        return set_token(:KEYWORD, text, @row, start_col)
      end
      if text == "while"
        return set_token(:KEYWORD, text, @row, start_col)
      end
      if text == "return"
        return set_token(:KEYWORD, text, @row, start_col)
      end
      if text == "true"
        return set_token(:TRUE, nil, @row, start_col)
      end
      if text == "false"
        return set_token(:FALSE, nil, @row, start_col)
      end
      if text == "nil"
        return set_token(:NIL, nil, @row, start_col)
      end
      set_token(:ID, text, @row, start_col)
    end
  RUBY
  body = replace_method(body, "emit_reserved_identifier", <<~RUBY)
    def emit_reserved_identifier(start, finish, start_col)
      false
    end
  RUBY
  body = replace_method(body, "scan_ascii_name_bytes", <<~RUBY)
    def scan_ascii_name_bytes
      advance while ident_continue_byte?(byte)
    end
  RUBY
  body = replace_method(body, "scan_at", <<~RUBY)
    def scan_at
      start_col = @col
      start = @pos
      advance
      if ident_start_byte?(byte)
        advance while ident_continue_byte?(byte)
        return set_token(:IVAR, slice(start, @pos), @row, start_col)
      end
      set_token(:'@', "@", @row, start_col)
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
  body = replace_method(body, "keyword_at", <<~RUBY)
    def keyword_at(start, finish)
      text = slice(start, finish)
      return "if" if text == "if"
      return "else" if text == "else"
      return "while" if text == "while"
      return "true" if text == "true"
      return "false" if text == "false"
      return "nil" if text == "nil"
      nil
    end
  RUBY
  body = replace_method(body, "type_name_at", <<~RUBY)
    def type_name_at(start, finish)
      nil
    end
  RUBY
  body = replace_method(body, "constant_name?", <<~RUBY)
    def constant_name?(value)
      false
    end
  RUBY
  body = replace_method(body, "scan_number", <<~RUBY)
    def scan_number(approx: false)
      start_col = @col
      start = @pos
      consume_number_sign
      advance if approx || byte == 126
      consume_number_sign

      loop do
        b = byte
        break unless digit_byte?(b) || b == 95

        advance
      end
      if byte == 46 && digit_byte?(byte(1))
        advance
        loop do
          b = byte
          break unless digit_byte?(b) || b == 95

          advance
        end
        return set_token(:DECIMAL, slice(start), @row, start_col)
      end

      set_token(approx ? :FLOAT : :INT, slice(start), @row, start_col)
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
      set_token(:CODEPOINT, slice(start), @row, start_col)
    end
  RUBY
  body = replace_method(body, "regex_literal_allowed?", <<~RUBY)
    def regex_literal_allowed?
      true
    end
  RUBY
  body = replace_method(body, "regex_capture_start?", <<~RUBY)
    def regex_capture_start?
      false
    end
  RUBY
  body = replace_method(body, "bracketed_ip6_start?", <<~RUBY)
    def bracketed_ip6_start?
      false
    end
  RUBY
  body = replace_method(body, "approximate_decimal_after?", <<~RUBY)
    def approximate_decimal_after?(index)
      false
    end
  RUBY
  body = replace_method(body, "approximate_float_literal_possible?", <<~RUBY)
    def approximate_float_literal_possible?
      false
    end
  RUBY
  body = replace_method(body, "rational_literal_possible?", <<~RUBY)
    def rational_literal_possible?
      false
    end
  RUBY
  body = replace_method(body, "scan_regex_literal", <<~RUBY)
    def scan_regex_literal
      start = @pos
      start_col = @col
      advance
      while @pos < @length
        if byte == 47
          break
        end
        advance_utf8_char
      end
      error "unterminated regex literal" if eof?

      pattern = slice(start + 1, @pos)
      advance
      set_token(:REGEX, pattern, @row, start_col)
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
  body = replace_method(body, "scan_wvalue", <<~RUBY)
    def scan_wvalue
      start_col = @col
      start = @pos
      advance(3)
      advance while hex_byte?(byte)
      set_token(:WVALUE, slice(start), @row, start_col)
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
    hex_reference_literal_possible?
    network_literal_shape_possible?
    special_decimal_literal_possible?
    rational_literal_possible?
    numeric_reference_possible?
    radix_number_literal?
    sexagesimal_decimal_prefix?
    approximate_float_literal_possible?
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
          discard_duplicate_block(then_block)
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
          discard_duplicate_block(then_block)
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

        def current_starts_like?(node)
          return false if node.nil?
          if node.doc == 13
            return @token.type?(:ID) && @token.value.to_s == node.name.to_s
          end
          if node.doc == 8
            return @token.type?(:ID) && @token.value.to_s == node.name.to_s
          end
          if node.doc == 14
            return keyword_value?("return")
          end
          if node.doc == 10
            return keyword_value?("if")
          end
          if node.doc == 11
            return keyword_value?("while")
          end
          false
        end

        def discard_duplicate_block(block)
          return if block.nil?
          return if block.length == 0
          return unless current_starts_like?(block[0])

          i = 0
          while i < block.length && !@token.type?(:EOF)
            before_pos = @lexer_adapter.pos
            parse_statement
            if @lexer_adapter.pos == before_pos && !@token.type?(:EOF)
              next_token
            end
            while @token.type?(:DEDENT)
              next_token
            end
            while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT)
              next_token
            end
            i += 1
          end
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
              skip_spaces
              if @token.type?(:"]")
                break
              end
              arr_lit.list.push(parse_binary_expression)
              skip_spaces
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
              skip_spaces
              if @token.type?(:"}")
                break
              end
              key = nil
              if @token.type?(:ID)
                key = StringLiteral.new(@token.value)
                next_token
                skip_spaces
                if @token.type?(:":")
                  next_token
                end
              else
                key = parse_binary_expression
                skip_spaces
                if @token.type?(:"=>")
                  next_token
                elsif @token.type?(:":")
                  next_token
                end
              end
              skip_spaces
              value = parse_binary_expression
              pair = List.new
              pair.push(key)
              pair.push(value)
              entries.push(pair)
              skip_spaces
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
      @slot_names = {"__spinel_slot0__" => 0}
      @slot_values = [nil, 0, ""]
      @slot_values.clear
      @slot_values.push(nil)
      @barrier = false
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

    # Spinel-stage0 perf: pool-recycle entry point. Called by
    # call_w_method on env release to drain the str_poly_hash
    # back to its initial 2-placeholder shape (which keeps
    # spinel's str_poly_hash type inference happy — see comment
    # in #initialize) without reallocating the hash struct or its
    # internal arrays. Drops ~4 % CPU in stage 0 and (more
    # importantly) bounds the page-out traffic that's the real
    # bottleneck in NO_GC mode.
    #
    # Named pool_reset (not reset) to avoid spinel mis-dispatching
    # to Node_TransformState#reset, which also exists with a
    # different arity and confuses spinel's per-mname lookup.
    def pool_reset(parent)
      @parent = parent
      @values.clear
      @slot_names.clear
      @slot_names["__spinel_slot0__"] = 0
      @slot_values.clear
      @slot_values.push(nil)
      @barrier = false
      @slot_names_shared = false
      @layout_shape = 0
      @lookup_shape = 0
      @pool_next = nil
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
  body = replace_method(body, "barrier?", "    def barrier?\n      false\n    end\n")
  body = replace_method(body, "lookup_shape", "    def lookup_shape\n      0\n    end\n")
  body = replace_method(body, "slot_index", <<~RUBY)
    def slot_index(name)
      idx = @slot_names[name]
      return idx if idx > 0
      nil
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
      env = self
      while true
        idx = env.slot_index(name)
        if idx > 0
          return env.get_slot(idx)
        end
        parent = env.parent
        if parent == nil
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
      @values[name] = value
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
      @layout_shape = shape
      @lookup_shape = shape
      self
    end
  RUBY
  body = replace_method(body, "set", <<~RUBY)
    def set(name, value)
      # No "" + hoist — codegen-side string-param override (see
      # #get) makes name already const char*.
      bind_slot(name, value)
      value
    end
  RUBY
  body = replace_method(body, "define", <<~RUBY)
    def define(name, value)
      # No "" + hoist — codegen-side string-param override (see
      # #get).
      bind_slot(name, value)
      value
    end
  RUBY
  body = replace_method(body, "define_slot", <<~RUBY)
    def define_slot(name, index, value)
      @slot_names[name] = index
      @slot_values[index] = value
      value
    end

    def bind_slot(name, value)
      idx = @slot_names[name]
      if idx > 0
        @slot_values[idx] = value
      else
        idx = @slot_values.length
        @slot_names[name] = idx
        @slot_values.push(value)
      end
      value
    end

    def bind_new_slot(name, value)
      idx = @slot_values.length
      @slot_names[name] = idx
      @slot_values.push(value)
      value
    end

  RUBY
  body = replace_method(body, "defined?", <<~RUBY)
    def defined?(name)
      # No "" + hoist — codegen-side string-param override (see #get).
      return true if slot_index(name) > 0
      return @parent.defined?(name) if @parent
      false
    end
  RUBY
  body = replace_method(body, "defined_locally_or_in_scope?", <<~RUBY)
    def defined_locally_or_in_scope?(name)
      return true if slot_index(name) > 0
      return @parent.defined_locally_or_in_scope?(name) if @parent
      false
    end
  RUBY
  body = replace_method(body, "defined_locally?", <<~RUBY)
    def defined_locally?(name)
      slot_index(name) > 0
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
  # Initialize @top_env alongside @env. visit_call's user-fn lookup
  # uses @top_env to skip the env parent-chain walk for top-level
  # Defs — most lookups resolve to a Def in the root env.
  # Keep env recycling behind SP_GC_DISABLE. Reused Environment objects are
  # only safe in the no-GC bootstrap path. Use a linked free-list rather than
  # an Array so the pool itself does not allocate or fight Spinel's array type
  # inference.
  body = body.gsub("@env = Environment.new\n", "@env = Environment.new(nil)\n      @top_env = @env\n      @env_pool = nil\n      @env_pool_count = 0\n      @env_pool_enabled = ENV[\"SP_GC_DISABLE\"] == \"1\" ? 1 : 0\n      @stage0_next_layout_shape = 1\n")
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
    "      @breaking = false\n" \
    "      @nexting = false\n" \
    "      @exiting = false\n" \
    "      @current_block = \"\"\n"
  )
  body = body.gsub("      Runtime::Builtins.setup(self)\n", "")
  body = body.gsub(/      BUILTIN_TYPES\.each \{ \|name\| @classes\[name\] \|\|= Runtime::WClass\.new\(name, nil\) \}\n/, "")
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
      w_class = @classes[node.name]
      if w_class == nil
        superclass = nil
        if node.superclass
          superclass = @classes[node.superclass]
        end
        w_class = Runtime::WClass.new(node.name, superclass)
        @classes[node.name] = w_class
      end
      body = node.body.list
      i = 0
      while i < body.length
        stage0_define_class_body_method(w_class, body[i])
        i += 1
      end

      w_class
    end

    def stage0_define_class_body_method(w_class, expr)
      if expr.doc == 12
        return stage0_define_class_method(w_class, expr)
      end
      nil
    end

    def stage0_define_class_method(w_class, expr)
    if w_class.name == "RegexLexer"
      if expr.name == "tokenize" || expr.name == "tokenize_one"
        return nil
      end
    end
    if ENV["TUNGSTEN_STAGE0_DEFINE_METHOD_TRACE"] == "1"
      trace_path = "/tmp/tungsten-stage0-define-methods"
      trace_text = ""
      if File.exist?(trace_path)
        trace_text = File.read(trace_path)
      end
      File.write(trace_path, trace_text + w_class.name.to_s + ":" + expr.name.to_s + "\n")
    end
    w_class.methods[expr.name.to_s] = expr
    expr
  end
  RUBY
  body = replace_method(body, "visit_def", <<~RUBY)
    def visit_def(node)
      if @stage0_loading_depth != nil && @stage0_loading_depth > 0 && @current_file.to_s.end_with?("compiler/lib/parser.w")
        parser_class = @classes["Parser"]
        if parser_class != nil
          return stage0_define_class_method(parser_class, node)
        end
      end
      @env.bind_value(node.name.to_s, node)
      node
    end
  RUBY
  # visit_begin: spinel can't handle Ruby's begin/rescue cleanly in the
  # generated C, and the heavy version inside KEEP_INTERPRETER_CORE
  # never runs by default. Replace at top level so begin blocks actually
  # evaluate their body in stage0 (compiler/tungsten.w wraps compile_one
  # in begin/rescue, so without this the program silently exits).
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
      if file_path.to_s.end_with?("compiler/tungsten.w")
        source = stage0_normalize_compiler_source(source)
      else
        source = stage0_normalize_compiler_language_source(source)
      end
      dump_path = ENV["TUNGSTEN_STAGE0_NORMALIZED_DUMP"]
      if dump_path != nil && dump_path != ""
        File.write(dump_path, source)
      end
      @source = source
      @current_file = file_path
      ast = parse_with_file(source, file_path)
      if ENV["TUNGSTEN_STAGE0_BOOT_TRACE"] == "1"
        File.write("/tmp/tungsten-stage0-boot-parse-done", ast.length.to_s)
      end
      if ENV["TUNGSTEN_STAGE0_PARSE_DEBUG"] == "1"
        puts "stage0 source length"
        puts source.length
        puts "stage0 ast length"
        puts ast.length
        i = 0
        while i < ast.length && i < 20
          expr = ast[i]
          puts "stage0 ast doc " + i.to_s + " " + expr.doc.to_s
          if expr.respond_to?(:name)
            puts "stage0 ast name " + expr.name.to_s
          end
          i += 1
        end
      end
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
      return nil unless node
      # Hoist `node.doc` into a single read so spinel doesn't
      # re-emit the ~100-line cls_id type-switch per branch.
      # Original 47 separate `if node.doc == N` lines blew the
      # compiled `evaluate` to 5,700+ lines / 4,653 iv_doc reads;
      # one cached read drops it to a flat 47-arm dispatch.
      doc = node.doc
      return visit_list(node) if doc == 1
      return visit_print(node) if doc == 2
      return visit_int(node) if doc == 3
      return visit_string_literal(node) if doc == 4
      return visit_boolean(node) if doc == 5
      return visit_nil(node) if doc == 6
      return visit_binary_op(node) if doc == 7
      return visit_assign(node) if doc == 8
      return visit_var(node) if doc == 9
      return visit_if(node) if doc == 10
      return visit_while(node) if doc == 11
      return visit_def(node) if doc == 12
      return visit_call(node) if doc == 13
      return visit_return(node) if doc == 14
      return visit_assign_op(node) if doc == 15
      return cached_symbol_value(node) if doc == 16
      return visit_array_literal(node) if doc == 17
      return visit_hash_literal(node) if doc == 18
      return visit_and(node) if doc == 19
      return visit_or(node) if doc == 20
      return visit_in_test(node) if doc == 21
      return visit_case_expr(node) if doc == 22
      return visit_use(node) if doc == 23
      return visit_class_def(node) if doc == 24
      return visit_module_def(node) if doc == 25
      return visit_trait_def(node) if doc == 26
      return visit_instance_var(node) if doc == 27
      return visit_class_var(node) if doc == 28
      return visit_global_var(node) if doc == 29
      return visit_self(node) if doc == 30
      return node.value if doc == 31
      return node.value if doc == 32
      return decode_w_value(node.value, node.raw) if doc == 33
      return visit_begin(node) if doc == 34
      return visit_raise(node) if doc == 35
      if doc == 36
        visit_write(node)
        return nil
      end
      return visit_fn(node) if doc == 37
      return visit_yield(node) if doc == 38
      return visit_break(node) if doc == 39
      return visit_next(node) if doc == 40
      return visit_not(node) if doc == 41
      return visit_tuple(node) if doc == 42
      return visit_splat(node) if doc == 43
      return visit_string_interpolation(node) if doc == 44
      return visit_alias(node) if doc == 45
      return visit_is(node) if doc == 46
      return visit_super(node) if doc == 47
      nil
    end
  RUBY
  body = replace_method(body, "visit_list", <<~RUBY)
    def visit_list(node)
      # Debug ENV checks were the #1 hotspot per `sample` — getenv()
      # was called millions of times during compile. Stripped from the
      # interpreter hot path; rebuild with a debug bundle if needed.
      result = nil
      list = node.list
      i = 0
      if @stage0_eval_depth == nil
        @stage0_eval_depth = 0
      end
      @stage0_eval_depth += 1
      trace_eval = @stage0_eval_depth == 1
      while i < list.length
        if @stage0_loading_depth != nil && @stage0_loading_depth > 0
          doc = list[i].doc
          if doc != 12 && doc != 23 && doc != 24 && doc != 25 && doc != 26 && doc != 37
            i += 1
            next
          end
        end
        if trace_eval
          item = list[i]
          label = item.doc.to_s
          if item.respond_to?(:name)
            label = label + ":" + item.name.to_s
          elsif item.respond_to?(:path)
            label = label + ":" + item.path.to_s
          end
          File.write("/tmp/tungsten-stage0-eval-trace", "before:" + i.to_s + ":" + label)
        end
        result = evaluate(list[i])
        if trace_eval
          File.write("/tmp/tungsten-stage0-eval-trace", "after:" + i.to_s)
        end
        break if @returning
        break if @exiting
        break if @breaking
        break if @nexting
        i += 1
      end
      @stage0_eval_depth -= 1
      result
    end
  RUBY
  body = replace_method(body, "visit_int", <<~RUBY)
    def visit_int(node)
      text = node.value.to_s
      text.to_i
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
  body = replace_method(body, "visit_print", <<~RUBY)
    def visit_print(node)
      result = nil
      i = 0
      while i < node.args.length
        result = evaluate(node.args[i])
        puts result
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
      op = stage0_binary_op_operator(node)

      if op == :in
        if node.right.doc == 1
          i = 0
          while i < node.right.length
            value = evaluate(node.right[i])
            return true if left == value
            i += 1
          end
        end
        return false
      end

      # Short-circuit booleans: || returns left if truthy else right;
      # && returns right if left is truthy else left.
      if op == :"||"
        return left if truthy?(left)
        return evaluate(node.right)
      elsif op == :"&&"
        return left unless truthy?(left)
        return evaluate(node.right)
      end

      right = evaluate(node.right)

      if op == :""
        false
      elsif op == :==
        left == right
      elsif op == :!=
        !(left == right)
      elsif op == :<
        left < right
      elsif op == :<=
        left <= right
      elsif op == :>
        left > right
      elsif op == :>=
        left >= right
      elsif op == :<=>
        left <=> right
      elsif op == :+
        if left.is_a?(String) || right.is_a?(String)
          left.to_s + right.to_s
        else
          left + right
        end
      elsif op == :-
        left - right
      elsif op == :*
        left * right
      elsif op == :/
        left / right
      elsif op == :%
        left % right
      elsif op == :**
        left ** right
      elsif op == :<<
        left << right
      elsif op == :>>
        left >> right
      elsif op == :&
        left & right
      elsif op == :|
        left | right
      elsif op == :^
        left ^ right
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
      target = node
      target = node.name
      if target.doc == 27
        self_obj = nil
        if @self_stack.length > 0
          self_obj = @self_stack[@self_stack.length - 1]
        end
        if self_obj != nil
          self_obj.set_ivar(target.name.to_s, value)
          return value
        end
      end
      if target.doc == 9
        @env.set(target.name.to_s, value)
      else
        @env.set(target.to_s, value)
      end
      value
    end
  RUBY
  body = replace_method(body, "visit_instance_var", <<~RUBY)
    def visit_instance_var(node)
      self_obj = nil
      if @self_stack.length > 0
        self_obj = @self_stack[@self_stack.length - 1]
      end
      if self_obj != nil
        return self_obj.get_ivar(node.name.to_s)
      end
      nil
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
      return "Integer" if value.is_a?(Integer)
      return "Float" if value.is_a?(Float)
      return "String" if value.is_a?(String)
      return "Symbol" if value.is_a?(Symbol)
      return "Array" if value.is_a?(Array)
      return "Hash" if value.is_a?(Hash)
      if value.is_a?(WObject)
        klass = value.w_class
        return klass.name.to_s unless klass.nil?
        return "Object"
      end
      return "Class" if value.is_a?(WClass)
      "Unknown"
    end
  RUBY
  body = replace_method(body, "visit_call", <<~RUBY)
    def visit_call(node)
      result = nil
      # Hoist `node.name` and `node.args` once each — every `if
      # node.name == "X"` arm otherwise re-emits the ~20-line cls_id
      # type-switch to extract iv_name. The original visit_call
      # compiled to 2,075 lines / 703 iv_name reads; one cached pair
      # of reads collapses the bloat.
      name = stage0_call_name(node)
      if @stage0_call_eval_trace_enabled == 1
        File.write("/tmp/tungsten-stage0-call-eval-trace", name)
      end
      # Sym dispatch: convert name to sp_sym once and cache on the Call
      # node. Subsequent visits skip sp_sym_intern entirely — without
      # caching, the per-visit intern dominates the profile (the prior
      # uncached step-C bench landed strcmp at 583 samples).
      name_sym = node.cached_name_sym
      if name_sym < 0
        name_sym = stage0_str_to_sym(name)
        node.cached_name_sym = name_sym
      end
      args = node.args
      obj = node.obj
      if !obj.nil?
        if name_sym == :new
          if obj.doc == 9
            class_name = obj.name.to_s
            if class_name == "Environment" || class_name == "Interpreter" || class_name == "Loader" || class_name == "Parser" || class_name == "REPL" || class_name == "RegexLexer"
              w_class = @classes[class_name]
              if w_class.nil?
                runtime_error("stage0 unknown class: " + class_name)
              end
              return instantiate_from_nodes(w_class, args)
            end
            if class_name == "Lexer"
              w_class = @classes["Lexer"]
              if w_class.nil?
                w_class = @classes["CodepointLexer"]
              end
              if w_class.nil?
                runtime_error("stage0 unknown class: Lexer")
              end
              return instantiate_from_nodes(w_class, args)
            end
          end
        end
        recv = evaluate(obj)
        if name_sym == :new
          return instantiate_from_nodes(recv, args)
        end
        name_s = name
        owner = recv
        if recv.is_a?(WObject)
          owner = recv.w_class
        end
        # Spinel-stage0 hack: bypass the cached_dispatch_owner /
        # cached_w_method cache. Spinel emits .equal? on poly
        # objects as a no-op temp that always evaluates to TRUE in
        # the surrounding `if (..., TRUE) { ... }` shape — so the
        # cache hit branch fires on the FIRST call (when both
        # cached fields are nil), reads nil for method, falls
        # through to stage0_primitive_call, and every user-method
        # call returns nil. Skipping the cache walks lookup_method
        # on every dispatch (slow but correct).
        method = owner.lookup_method(name_s)
        return call_w_method_from_nodes(recv, method, args, node.block) if method
        w_class = recv.w_class
        if !w_class.nil?
          method = w_class.lookup_method(name_s)
          return call_w_method_from_nodes(recv, method, args, node.block) if method
        end
        # Inline the dominant primitive dispatches. `[]`, `length` /
        # `size`, and `empty?` sit on the parser/lowering hot path; the
        # generic primitive fallback also stringifies some non-List
        # values when sizing them, which is both slow and wrong.
        if name_sym == :"[]"
          return stage0_aref(recv, evaluate(args[0]))
        end
        if name_sym == :length || name_sym == :size
          return stage0_value_length(recv)
        end
        if name_sym == :empty?
          return stage0_value_length(recv) == 0
        end
        return stage0_primitive_call(recv, name_sym, args)
        runtime_error("stage0 unsupported receiver call: " + name, node: node)
      end
#{stage0_ast_builtin_dispatch}
      if name_sym == :argv
        # Read sp_argv (mapped from ARGV) directly. The previous design
        # cached args in $stage0_argv built via sp_str_concat3, but that
        # string lives in sp_str_heap and the global isn't a GC root, so
        # a sweep during program execution would reclaim it. ARGV[0] is
        # the .w file passed to stage0; user args start at ARGV[1].
        argv_list = List.new
        i = 1
        while i < ARGV.length
          argv_list.push(ARGV[i])
          i += 1
        end
        return argv_list
      end
      if name_sym == :"<<"
        i = 0
        while i < args.length
          result = evaluate(args[i])
          puts result
          i += 1
        end
        return result
      end
      if name_sym == :exit
        File.write("/tmp/stage0-trace-EXIT-B", "site=B_builtin_dispatch")
        @exiting = true
        return result
      end
      if name_sym == :clock
        return 0
      end
  if name_sym == :write_file
    path = evaluate(args[0])
    data = evaluate(args[1])
    File.write(path.to_s, data.to_s)
    File.write("/tmp/stage0-trace-WF-" + path.to_s.gsub("/", "_"), "len=" + data.to_s.length.to_s)
    return nil
  end
      if name_sym == :read_file
        path = evaluate(args[0])
        return File.read(path.to_s)
      end
      if name_sym == :file?
        path = evaluate(args[0])
        return File.exist?(path.to_s)
      end
      if name_sym == :env
        env_name = evaluate(args[0])
        return ENV[env_name.to_s]
      end
      if name_sym == :system
        command = evaluate(args[0])
        system(command.to_s)
        return nil
      end
      if name_sym == :capture
        command = evaluate(args[0])
        return IO.popen(command.to_s).read
      end
      if name_sym == :type
        return stage0_type_name(evaluate(args[0]))
      end
      if name_sym == :stage0_tokenize_source
        source = evaluate(args[0])
        file = evaluate(args[1])
        return stage0_tokenize_source_for_compiler(source, file)
      end
      if name_sym == :stage0_set_lexer_input
        @stage0_lexer_source = evaluate(args[0])
        @stage0_lexer_file = evaluate(args[1])
        return nil
      end
      if name_sym == :stage0_tokenize_lexer_input
        return stage0_tokenize_source_for_compiler(@stage0_lexer_source, @stage0_lexer_file)
      end
      if name_sym == :ast_node_key
        return evaluate(args[0])
      end
      if name_sym == :ast_get
        ast_node = evaluate(args[0])
        ast_key = evaluate(args[1])
        if ast_node.is_a?(Hash)
          ast_value = ast_node[ast_key]
          return ast_value if ast_value != nil
          ast_value = ast_node[ast_key.to_s]
          return ast_value if ast_value != nil
          ast_value = ast_node[ast_key.to_sym]
          return ast_value if ast_value != nil
        end
        return nil
      end
      if name_sym == :ast_set
        ast_node = evaluate(args[0])
        ast_key = evaluate(args[1])
        ast_value = evaluate(args[2])
        if ast_node.is_a?(Hash)
          ast_node[ast_key] = ast_value
          ast_node[ast_key.to_s] = ast_value
          return ast_value
        end
        return ast_value
      end
      if name_sym == :ast_kind
        ast_node = evaluate(args[0])
        if ast_node.is_a?(Hash)
          ast_value = ast_node[:node]
          return ast_value if ast_value != nil
          return ast_node["node"]
        end
        return nil
      end
      if name_sym == :program_body
        ast_node = evaluate(args[0])
        if ast_node.is_a?(Hash)
          return ast_node[:expressions]
        end
        return nil
      end
      if name_sym == :block_body
        ast_node = evaluate(args[0])
        if ast_node.is_a?(Hash)
          return ast_node[:body]
        end
        return nil
      end
      if name_sym == :is_ast_node?
        ast_node = evaluate(args[0])
        return ast_node.is_a?(Hash) && ast_node[:node] != nil
      end
      if name_sym == :ast_children || name_sym == :ast_array_fields || name_sym == :ast_children_program || name_sym == :ast_children_block
        ast_node = evaluate(args[0])
        out = []
        if ast_node.is_a?(Hash)
          ast_node.each_value do |value|
            if value.is_a?(Hash) && value[:node] != nil
              out.push(value)
            elsif value.is_a?(Array) || value.is_a?(List)
              value.each do |element|
                out.push(element) if element.is_a?(Hash) && element[:node] != nil
              end
            end
          end
        end
        return out
      end
      if name_sym == :ast_deep_clone
        return evaluate(args[0])
      end
      if name_sym == :keys
        return []
      end
      if name_sym == :size || name_sym == :length
        return 0
      end
      if name_sym == :empty?
        return true
      end
      if name_sym == :StringBuffer
        return ""
      end
      if name_sym == :stage0_str_append
        buf = evaluate(args[0])
        value = evaluate(args[1])
        return buf.to_s + value.to_s
      end
      if name_sym == :stage0_load_program_ast
        path = evaluate(args[0])
        return stage0_load_program_ast_direct(path.to_s)
      end
      if name_sym == :stage0_hash_set
        hash = evaluate(args[0])
        key = evaluate(args[1])
        value = evaluate(args[2])
        hash[key] = value
        return value
      end
      if name_sym == :stage0_class_has_method
        class_name = evaluate(args[0]).to_s
        method_name = evaluate(args[1]).to_s
        w_class = @classes[class_name]
        return false if w_class.nil?
        return !w_class.lookup_method(method_name).nil?
      end
      if name_sym == :stage0_class_method_body_summary
        class_name = evaluate(args[0]).to_s
        method_name = evaluate(args[1]).to_s
        w_class = @classes[class_name]
        return "" if w_class.nil?
        method = w_class.lookup_method(method_name)
        return "" if method.nil?
        out = "length=" + method.body.length.to_s + "\n"
        i = 0
        while i < method.body.length && i < 80
          expr = method.body[i]
          out = out + i.to_s + ":doc=" + expr.doc.to_s
          if expr.doc == 10
            out = out + ":then=" + expr.then_block.length.to_s + ":else=" + expr.else_block.length.to_s
            j = 0
            while j < expr.then_block.length && j < 8
              child = expr.then_block[j]
              out = out + ":t" + j.to_s + "=" + child.doc.to_s
              if child.doc == 13
                out = out + "/" + child.name.to_s
              end
              if child.doc == 8
                out = out + "/" + child.name.to_s
              end
              j += 1
            end
          end
          if expr.doc == 11
            out = out + ":body=" + expr.body.length.to_s
            j = 0
            while j < expr.body.length && j < 12
              child = expr.body[j]
              out = out + ":b" + j.to_s + "=" + child.doc.to_s
              if child.doc == 10
                out = out + "/if"
                out = out + "[then=" + child.then_block.length.to_s
                k = 0
                while k < child.then_block.length && k < 4
                  grandchild = child.then_block[k]
                  out = out + ":t" + k.to_s + "=" + grandchild.doc.to_s
                  if grandchild.doc == 13
                    out = out + "/" + grandchild.name.to_s
                  end
                  if grandchild.doc == 8
                    out = out + "/" + grandchild.name.to_s
                  end
                  k += 1
                end
                out = out + "]"
              end
              if child.doc == 8
                out = out + "/" + child.name.to_s
              end
              if child.doc == 13
                out = out + "/" + child.name.to_s
              end
              j += 1
            end
          end
          if expr.doc == 13
            out = out + ":call=" + expr.name.to_s
          end
          if expr.doc == 8
            out = out + ":assign=" + expr.name.to_s
          end
          out = out + "\n"
          i += 1
        end
        return out
      end
      if name_sym == :stage0_root_has
        root_name = evaluate(args[0]).to_s
        return @top_env.values_table.key?(root_name)
      end
      if name_sym == :stage0_reset_method_trace
        @stage0_method_trace_count = 0
        File.write("/tmp/tungsten-stage0-method-trace.txt", "")
        return nil
      end
      if name_sym == :stage0_wparser_trace
        if @stage0_wparser_trace_enabled == 1
          if @stage0_wparser_trace_count == nil
            @stage0_wparser_trace_count = 0
            File.write("/tmp/tungsten-stage0-wparser-trace.txt", "")
          end
          if @stage0_wparser_trace_count < 500
            trace_label_s = evaluate(args[0]).to_s
            trace_pos_s = evaluate(args[1]).to_s
            trace_type_s = evaluate(args[2]).to_s
            trace_value_s = evaluate(args[3]).to_s
            trace_text = ""
            if File.exist?("/tmp/tungsten-stage0-wparser-trace.txt")
              trace_text = File.read("/tmp/tungsten-stage0-wparser-trace.txt")
            end
            File.write("/tmp/tungsten-stage0-wparser-trace.txt",
                       trace_text + trace_label_s + " pos=" + trace_pos_s + " type=" + trace_type_s + " value=" + trace_value_s + "\n")
            @stage0_wparser_trace_count += 1
          end
        end
        return nil
      end

      # ccall / ccall_nobox dispatch — compiler/lib/ast.w builds
      # slab-AST nodes via `ccall("w_node_alloc", ...)` etc; stage 0
      # has no compiler/lowering pass to turn those into direct
      # extern calls, so the interpreter has to dispatch by C
      # function name to the WRuntime FFI module declared in
      # preamble.rb. Both forms behave identically at the runtime
      # level (only the lowering distinguishes them — ccall_nobox
      # tells lower_call to keep machine-int args raw).
      if name_sym == :ccall || name_sym == :ccall_nobox
        # Unbox args via .to_i before passing to FFI. Spinel's
        # compile_ffi_func_call emits `((long)(call_arg))` for :long
        # specs, which is a plain C cast — works on mrb_int but not
        # on sp_RbVal. Hoisting through .to_i (which unboxes poly to
        # int) keeps the FFI shim happy.
        fn_name = evaluate(args[0]).to_s
        # w_node_kind_sym is special: the runtime expects the table
        # arg as a WValue-tagged Tungsten Array, but stage 0
        # represents kind_sym_table_data as a plain spinel sp_List
        # — AND the top-level `kind_sym_table_data = [...]` assign
        # in compiler/lib/ast_schema.w never runs because the
        # @stage0_loading_depth > 0 visit_list filter strips
        # non-(def|use|class|module|trait) statements from `use`d
        # files. We can't loosen the filter (it triggered heavy
        # evaluation loops). Mirror the table inline here from
        # ast_schema.w:305 — keep in sync if KIND_ID_TABLE changes
        # (schema_hash check upstream catches drift). 135 entries
        # (indices 0..134).
        if fn_name == "w_node_kind_sym"
          node_val = evaluate(args[1]).to_i
          kind_id = WRuntime.w_node_kind_extern(node_val)
          return nil if kind_id < 0
          return nil if kind_id > 134
          return stage0_kind_sym_table[kind_id]
        end
        a1 = args.length > 1 ? evaluate(args[1]).to_i : 0
        a2 = args.length > 2 ? evaluate(args[2]).to_i : 0
        a3 = args.length > 3 ? evaluate(args[3]).to_i : 0
        if fn_name == "w_node_singleton"
          return WRuntime.w_node_singleton(a1)
        end
        if fn_name == "w_node_inline_payload"
          return WRuntime.w_node_inline_payload(a1, a2)
        end
        if fn_name == "w_node_offset_extern"
          return WRuntime.w_node_offset_extern(a1)
        end
        if fn_name == "w_ast_bool_cached"
          return WRuntime.w_ast_bool_cached(a1)
        end
        if fn_name == "w_node_kind_extern"
          return WRuntime.w_node_kind_extern(a1)
        end
        if fn_name == "w_is_ast_node_full"
          return WRuntime.w_is_ast_node_full(a1, a2)
        end
        if fn_name == "w_node_alloc"
          return WRuntime.w_node_alloc(a1, a2)
        end
        if fn_name == "w_node_field_load"
          return WRuntime.w_node_field_load(a1, a2)
        end
        if fn_name == "w_node_field_store"
          WRuntime.w_node_field_store(a1, a2, a3)
          return nil
        end
        runtime_error("stage0 unknown ccall target: " + fn_name, node: node)
      end

      self_obj = nil
      if @self_stack.length > 0
        self_obj = @self_stack[@self_stack.length - 1]
      end
      # Spinel-stage0 hack: skip the dispatch cache for self-method
      # lookup — see the receiver-method dispatch comment above for
      # why .equal? on poly always returns TRUE here.
      w_class = self_obj.w_class
      if !w_class.nil?
        method = w_class.lookup_method(name)
        return call_w_method_from_nodes(self_obj, method, args, node.block) if method
      end

      # Two-tier lookup: most user-fn references resolve to a Def in
      # the root env, so we skip the env-chain walk by probing the
      # current frame first and then jumping straight to @top_env.
      # Stage0 has no closures, so vars only live in the current frame
      # (params/locals) or the root (top-level Defs); intermediate
      # frames don't contain names not already shadowed by the current
      # frame. The chain-walking sp_Environment_get was ~300 samples
      # on the prior bootstrap profile.
      fn = nil
      if node.cached_dispatch_owner.nil?
        fn = node.cached_w_method
      end
      if fn.nil?
        local_table = @env.values_table
        fn = stage0_str_poly_hash_get(local_table, name)
        if fn.nil?
          if @env.object_id != @top_env.object_id
            fn = stage0_str_poly_hash_get(@top_env.values_table, name)
            if !fn.nil?
              node.cached_dispatch_owner = nil
              node.cached_w_method = fn
            end
          end
        elsif @env.object_id == @top_env.object_id
          node.cached_dispatch_owner = nil
          node.cached_w_method = fn
        end
      end
      if fn.nil?
        if !@stage0_loading_depth.nil? && @stage0_loading_depth > 0
          return nil
        end
        runtime_error("stage0 unknown function: " + name, node: node)
      end
      if fn.doc == 12
        return stage0_call_def_from_nodes(fn, name, args)
      end

      result
    end
  RUBY
  body = replace_method(body, "visit_return", <<~RUBY)
    def visit_return(node)
      @return_value = evaluate(node.value)
      @returning = true
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
      node.value.to_s
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
      if ENV["TUNGSTEN_STAGE0_CASE_TRACE"] == "1"
        trace = "case_enter whens=" + whens.length.to_s + " receiver_type=" + type(node.receiver).to_s + "\n"
        File.write("/tmp/tungsten-stage0-case-trace", trace)
      end
      if node.receiver
        receiver_val = evaluate(node.receiver)
        if ENV["TUNGSTEN_STAGE0_CASE_TRACE"] == "1"
          trace = "receiver=" + receiver_val.to_s + " type=" + type(receiver_val).to_s + " whens=" + whens.length.to_s + "\n"
          File.write("/tmp/tungsten-stage0-case-trace", trace)
        end
        wi = 0
        while wi < whens.length
          ci = 0
          while ci < whens[wi][0].length
            cond_val = evaluate(whens[wi][0][ci])
            if ENV["TUNGSTEN_STAGE0_CASE_TRACE"] == "1"
              trace = "compare receiver=" + receiver_val.to_s + " cond=" + cond_val.to_s + " wi=" + wi.to_s + " ci=" + ci.to_s + "\n"
              File.write("/tmp/tungsten-stage0-case-trace", trace)
            end
            if cond_val == receiver_val
              if ENV["TUNGSTEN_STAGE0_CASE_TRACE"] == "1"
                File.write("/tmp/tungsten-stage0-case-trace", "match wi=" + wi.to_s + " ci=" + ci.to_s + "\n")
              end
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
        if else_body.empty?
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
      current = evaluate(node.name)
      value = evaluate(node.value)
      op = node.operator.to_s
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

      target = node
      target = node.name
      if target.doc == 9
        @env.set(target.name.to_s, result)
      elsif target.doc == 27
        self_obj = nil
        if @self_stack.length > 0
          self_obj = @self_stack[@self_stack.length - 1]
        end
        if self_obj != nil
          self_obj.set_ivar(target.name.to_s, result)
        end
      end
      result
    end
  RUBY
  body = replace_method(body, "visit_symbol", <<~RUBY)
    def visit_symbol(node)
      value = node.value.to_s
      if value.start_with?(":")
        return value.slice(1, value.length - 1)
      end
      value
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
      if @stage0_call_trace_enabled == 1
        File.write("/tmp/tungsten-stage0-hash-visit.txt", "hash")
      end
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
  body = body.gsub("      Runtime::Builtins.setup(self)\n", "")
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
      @env_pool_enabled = ENV["SP_GC_DISABLE"] == "1" ? 1 : 0
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
      value = node.value.to_s
      if value.start_with?(":")
        return value.slice(1, value.length - 1)
      end
      value
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
      @env_pool_enabled = ENV["SP_GC_DISABLE"] == "1" ? 1 : 0
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
        attr_accessor :list

        def self.from(obj)
          result = new
          if obj
            obj.each do |item|
              result << item
            end
          end
          result
        end

        def initialize(list = [])
          @doc = 1
          @list = list
        end

        def [](i)
          @list[i.to_i]
        end

        def []=(i, value)
          @list[i.to_i] = value
          value
        end

        def set_at(i, value)
          @list[i.to_i] = value
          value
        end

        def <<(exp)
          @list << exp
          self
        end

        def push(exp)
          @list.push(exp)
          self
        end

        def each(&block)
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

        def first
          @list.first
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
          def initialize(from, to, exclusive:)
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
            @elements = elements
          end
        end
        class MultisetLiteral < Node
          attr_accessor :elements
          def initialize(elements)
            @elements = elements
          end
        end
      end
    RUBY
  when "regex_literal.rb"
    <<~RUBY
      module Tungsten::AST
        class RegexLiteral < Node
          attr_accessor :value, :pattern, :options
          def initialize(pattern)
            @pattern = pattern
            @options = 0
            @value = pattern
          end
        end
      end
    RUBY
  when "typed_array.rb"
    <<~RUBY
      module Tungsten::AST
        class TypedArray < Node
          attr_accessor :element_type, :size
          def initialize(element_type, size)
            @element_type = element_type
            @size = size
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
          attr_accessor :value
          def initialize(value)
            @doc = 3
            text = ("" + value.to_s).delete("_")
            neg = false
            if text.start_with?("-")
              neg = true
              text = text[1, text.length - 1]
            elsif text.start_with?("+")
              text = text[1, text.length - 1]
            end
            n = 0
            if text.start_with?("0x") || text.start_with?("0X")
              n = text[2, text.length - 2].to_i(16)
            elsif text.start_with?("0b") || text.start_with?("0B")
              n = text[2, text.length - 2].to_i(2)
            elsif text.start_with?("0o") || text.start_with?("0O")
              n = text[2, text.length - 2].to_i(8)
            elsif text.start_with?("0d") || text.start_with?("0D")
              n = text[2, text.length - 2].to_i(10)
            else
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
        @value = v.start_with?(":") ? v[1..] : v
      end
    RUBY
  when %r{/ast/array_literal\.rb\z}
    <<~RUBY
      module Tungsten::AST
        class ArrayLiteral < List
          def initialize(list = [])
            @doc = 17
            @list = list
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
              # Push through a poly-laundered local: inside the is_a?(List)
              # narrowed branch spinel would emit sp_box_obj(pair, 125) on the
              # already-boxed sp_RbVal `pair` (sp_box_obj wants a void*). Seeding
              # to_push from entries (poly) keeps the slot sp_RbVal and unnarrowed
              # so it's passed straight through to List#push (which takes sp_RbVal).
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
        @elements = elements
      end
    RUBY
  when %r{/ast/keywords/case_expr\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(receiver, whens, else_body = nil)
        @doc = 22
        @receiver = 0
        @receiver = ""
        @receiver = receiver
        @whens = List.new
        @whens = whens
        @else_body = List.from(else_body)
      end
    RUBY
  when %r{/ast/keywords/use\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(path)
        @doc = 23
        @path = path
      end
    RUBY
  when %r{/ast/keywords/class_def\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, body = nil, superclass = "", class_role: nil)
        @doc = 24
        @name = name
        @body = body
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
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name)
        @doc = 27
        @name = Tungsten::AST.intern_name(name)
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
        # Stage0's List#each is a no-op stub, so List.from(body) returns
        # an empty List. The parser already passes a List of statements
        # for body — assign it directly so visit_begin actually evaluates
        # the body block.
        @body = body
        @rescue_var = rescue_var
        @rescue_body = rescue_body
        @ensure_body = ensure_body
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
            @args = List.new
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
            @name = name.to_s
            @args = args.to_s
            @body = List.new
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
            @args = List.new
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
            @value = nil
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
            @value = nil
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
        @elements = elements || []
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
        @names = [names.to_s]
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
  when %r{/ast/call\.rb\z}
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(obj, name, args = [], block = nil, column = 0, parens = false)
        @doc = 13
        @obj = obj
        @name = name.to_s
        @args = args
        @block = block
        @name_column_number = column
        @has_parens = parens
        @cached_name_sym = -1
        @cached_w_method = nil
      end
    RUBY
    replace_method(body, "can_assign?", <<~RUBY)
      def can_assign?
        false
      end
    RUBY
  when %r{/ast/binary_op\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(left, operator, right)
        @doc = 7
        @left = left
        @operator = operator
        @right = right
      end
    RUBY
  when %r{/ast/assign\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, value, type_hint = nil)
        @doc = 8
        @name = name
        @value = value
        @type_hint = type_hint
      end
    RUBY
  when %r{/ast/assign_op\.rb\z}
    replace_method(body, "initialize", <<~RUBY)
      def initialize(name, operator, value)
        @doc = 15
        @name = name
        @operator = operator
        @value = value
      end
    RUBY
  when %r{/ast/var\.rb\z}
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(name)
        @doc = 9
        @name = name.to_s
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
                    "    attr_accessor :instances, :owner\n    attr_accessor :stage0_param_names\n")
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(name, args, body, receiver: nil, block: nil, yields: nil, splat_index: nil, double_splat: nil)
        @doc = 12
        @name = name.to_s
        @args = args
        @body = body
        @stage0_param_names = []
        i = 0
        while i < args.length
          @stage0_param_names.push(args[i].name.to_s)
          i += 1
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
    replace_method(body, "initialize", <<~RUBY)
      def initialize(condition, body = nil, check_first = true)
        @doc = 11
        @condition = condition
        @body = body
        @check_first = check_first
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
        @operator = operator
        @right = right
      end
    RUBY
  when %r{/ast/list\.rb\z}
    body = replace_method(body, "initialize", <<~RUBY)
      def initialize(list = [])
        @doc = 1
        @list = list
      end
    RUBY
    body = replace_method(body, "self.from", <<~RUBY)
      def self.from(obj)
        List.new
      end
    RUBY
    body = replace_method(body, "<<", <<~RUBY)
      def <<(exp)
        @list.push(exp)
        self
      end
    RUBY
    body = body.sub("def <<(exp)\n        @list.push(exp)\n        self\n      end\n", "def <<(exp)\n        @list.push(exp)\n        self\n      end\n\n      def push(exp)\n        @list.push(exp)\n        self\n      end\n")
    replace_method(body, "each", <<~RUBY)
      def each(&block)
        self
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
        discard_duplicate_block(then_block)
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
        discard_duplicate_block(then_block)
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

      def current_starts_like?(node)
        return false if node.nil?
        if node.doc == 13
          return @token.type?(:ID) && @token.value.to_s == node.name.to_s
        end
        if node.doc == 8
          return @token.type?(:ID) && @token.value.to_s == node.name.to_s
        end
        if node.doc == 14
          return keyword_value?("return")
        end
        if node.doc == 10
          return keyword_value?("if")
        end
        if node.doc == 11
          return keyword_value?("while")
        end
        false
      end

      def discard_duplicate_block(block)
        return if block.nil?
        return if block.length == 0
        return unless current_starts_like?(block[0])

        i = 0
        while i < block.length && !@token.type?(:EOF)
          before_pos = @lexer_adapter.pos
          parse_statement
          if @lexer_adapter.pos == before_pos && !@token.type?(:EOF)
            next_token
          end
          while @token.type?(:DEDENT)
            next_token
          end
          while @token.type?(:NL) || @token.type?(:SP) || @token.type?(:INDENT)
            next_token
          end
          i += 1
        end
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
            skip_spaces
            if @token.type?(:"]")
              break
            end
            arr_lit.list.push(parse_binary_expression)
            skip_spaces
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
            skip_spaces
            if @token.type?(:"}")
              break
            end
            key = nil
            if @token.type?(:ID)
              key = StringLiteral.new(@token.value)
              next_token
              skip_spaces
              if @token.type?(:":")
                next_token
              end
            else
              key = parse_binary_expression
              skip_spaces
              if @token.type?(:"=>")
                next_token
              elsif @token.type?(:":")
                next_token
              end
            end
            skip_spaces
            value = parse_binary_expression
            pair = List.new
            pair.push(key)
            pair.push(value)
            entries.push(pair)
            skip_spaces
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
  body = body.gsub("parse_method_internal(node_class: Fn)", "parse_method_internal(true)")
  body = body.gsub("def parse_method_internal(node_class: Def)", "def parse_method_internal(fn_mode = false)")
  body = body.gsub("if node_class == Fn", "if fn_mode")
  body = body.gsub("return parse_anonymous_lambda(node_class:)", "return parse_anonymous_lambda(fn_mode)")
  body = body.gsub("def parse_anonymous_lambda(node_class: Def)", "def parse_anonymous_lambda(fn_mode = false)")
  body = body.sub(<<~RUBY, <<~RUBY)
      node = node_class.new(base_name, args, body)
      node.receiver     = receiver
      node.block        = block
      node.splat_index  = splat_index
      node.double_splat = double_splat
      node.param_types  = param_types
      node.return_type  = return_type
      node.set_location(loc_file, loc_row, loc_col)

      node
  RUBY
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
  body = body.sub(<<~RUBY, <<~RUBY)
      node = node_class.new(nil, @method[:args].any? ? @method[:args] : nil, body)
      node.block        = @method[:block]
      node.splat_index  = @method[:splat_index]
      node.double_splat = @method[:double_splat]

      node
  RUBY
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
  body = replace_method(body, "check_for", <<~RUBY)
    def check_for(a, b = nil, c = nil, d = nil)
      return if @token.type?(a)
      return if b && @token.type?(b)
      return if c && @token.type?(c)
      return if d && @token.type?(d)

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

      if @in_class_body && @token.type?(:-)
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

      if implicit_each?(exp)
        block = parse_block
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

      check_for :SP, :NL, :EOF, :"=>"
      exp
    end
  RUBY
  body = replace_method(body, "parse_assignment", <<~RUBY)
    def parse_assignment(allow_ops = true, allow_suffix = true)
      exp = parse_ternary

      while true
        if @token.type?(:SP)
          next_token
        elsif @token.type?(:"=")
          if exp.is_a?(Call) && exp.name == "[]"
            next_token_skip_whitespace
            # Reconstruct rather than mutate: spinel can't narrow the poly
            # `exp` for the `exp.name =`/`exp.args <<` setters (it would emit
            # `exp->iv_name` on an sp_RbVal). Build a fresh Call with the new
            # name and the appended value instead. Reads (exp.obj/exp.args)
            # dispatch polymorphically and are fine.
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

              exp = Assign.new(exp, value, hint)
            end
          end
        else
          break unless @token.assignment_operator?
          unexpected unless allow_ops
          break unless exp.can_assign?

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
          exp = AssignOp.new(exp, method.to_sym, value)
        end

        allow_ops = true
      end

      exp
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
  return body.sub(/\n\s*private\n/, "\n#{insertion}\n    private\n") if body.match?(/\n\s*private\n/)

  insert_before_last_end(body, insertion)
end

def strip_stage0_ast_methods(body)
  strip_methods(body, %w[children accept_children == clone to_sexp ast_fingerprint name_size])
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
        attr_reader(*%i[file row col])

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
          set_location(0, obj.row, obj.col)
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
    # Spinel-stage0 perf: leave evaluate_args as the original
    # fresh-allocation shape — pooling here broke spinel's static
    # type inference (values typed int_array via empty-literal
    # default + pool's sp_RbVal return path can't be reconciled).
    # The env_pool already covers the dominant allocation source;
    # args-pool was a smaller win that's not worth fighting
    # spinel's type tracker over.
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

    # Spinel-stage0 hack: drop the splat-arg branch entirely.
    # Spinel emits `splat_index != nil` as `((_t, TRUE) && ...)` —
    # the TRUE always wins — so with splat_index defaulting to nil
    # (lowered to int 0 in spinel), `i == splat_index` then fires
    # on iteration 0 and binds args[0] as a single-element rest
    # array instead of binding it to the first param directly.
    # No compiler/lib/*.w def uses `*args` (verified by
    # `grep -rE '^\s*-> \w+\([^)]*\*' compiler/lib/`), so the
    # splat arm is dead code in stage 0 and removing it sidesteps
    # the nil-check landmine.
    i = 0
    while i < params.length
      param = params[i]
      # The "" + param.name.to_s key hoist that used to live here is
      # made redundant by the codegen-side string-param overrides for
      # Environment#set (in spinel commit 0d26277). param.name on an
      # sp_Arg / sp_Param node returns a const char* directly.
      # Dropping the hoist eliminates one alloc per param per call —
      # for compiler/tungsten.w that's tens of thousands of saved
      # string allocs over a full compile, directly reducing the
      # dirty-page traffic that drove jetsam kills.
      name = param      # poly-seed: force lv_name to sp_RbVal (param is poly)
      name = param.name
      if i < args.length
        env.bind_new_slot(name, args[i])
      else
        env.bind_new_slot(name, nil)
      end
      i += 1
    end
    nil
  end
RUBY
final_bundle = replace_method(final_bundle, "execute_bound_w_method", <<~RUBY)
  def execute_bound_w_method(recv, method, method_env, block = nil, call_node = nil)
    old_env = @env
    old_returning = @returning
    old_return_value = @return_value
    @self_stack.push(recv)
    @env = method_env
    @returning = false
    @return_value = nil
    old_current_function = @stage0_current_function
    @stage0_current_function = method.name
    if @stage0_stack_trace_enabled == 1
      if @stage0_call_stack == nil
        @stage0_call_stack = []
      end
      @stage0_call_stack.push(method.name.to_s)
      File.write("/tmp/tungsten-stage0-call-stack", @stage0_call_stack.join(">"))
    end
    result = evaluate(method.body)
    if @stage0_stack_trace_enabled == 1 && @stage0_call_stack != nil
      @stage0_call_stack.pop
    end
    @stage0_current_function = old_current_function
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
final_bundle = replace_method(final_bundle, "call_w_method", <<~RUBY)
  def call_w_method(recv, method, args, block = nil, call_node: nil)
    return nil if method == nil

    params = method.args
    if @stage0_bind_trace_enabled == 1
      trace_path = "/tmp/tungsten-stage0-bind-trace"
      trace_text = ""
      if File.exist?(trace_path)
        trace_text = "" + File.read(trace_path).to_s
      end
      trace_text = trace_text + method.name.to_s + " params=" + params.length.to_s + " args=" + args.length.to_s + "\n"
      File.write(trace_path, trace_text)
    end
    # Spinel-stage0 perf: with SPINEL_NO_GC=1 each Environment.new
    # leaks (no sweep, no recycle). Profile showed Environment_new
    # at 4.3 % CPU on the hot path; the page-out traffic those
    # leaks produce hit 137 GB / 920 s in a stage 0 run yesterday
    # and is the actual bottleneck (per macOS diagnostic report).
    # Recycle envs via a per-Interpreter free-list initialised in
    # initialize_env_pool. Cap at 4 K to bound stable footprint;
    # tested compiles use ~thousands of method calls but only
    # ~hundreds live at any moment (deepest stack).
    if @env_pool_enabled == 1 && @env_pool_count > 0
      method_env = @env_pool
      @env_pool = method_env.pool_next
      @env_pool_count -= 1
      method_env.pool_reset(@env)
      stage0_mark_env(method_env)
    else
      method_env = new_param_env(@env, params, method)
    end
    bind_params(method_env, params, args, 0)
    result = execute_bound_w_method(recv, method, method_env, block, call_node)
    # Release after execute; method_env's contents are now dead
    # (no SP_GC_ROOT in caller scope keeps any binding alive).
    if @env_pool_enabled == 1
      method_env.pool_link(@env_pool)
      @env_pool = method_env
      @env_pool_count += 1
    end
    result
  end
RUBY
final_bundle = replace_method(final_bundle, "call_w_method_from_nodes", <<~RUBY)
  def call_w_method_from_nodes(recv, method, arg_nodes, block = nil, call_node: nil)
    call_w_method(recv, method, evaluate_args(arg_nodes), block, call_node: call_node)
  end
RUBY
final_bundle = replace_method(final_bundle, "instantiate_from_nodes", <<~RUBY)
  def instantiate_from_nodes(w_class, arg_nodes)
    obj = WObject.new(w_class)
    constructor = w_class.lookup_method("new")
    call_w_method_from_nodes(obj, constructor, arg_nodes) if constructor
    obj
  end
RUBY
# Strip debug ENV lookups from hot paths. Each `ENV["TUNGSTEN_..."] == "1"`
# compiles to `sp_str_eq(sp_str_dup_external(getenv(X)), "1")` — getenv +
# heap alloc + strcmp on every visit_hash_literal/visit_use/etc. The
# dynamic version of stage0 has these unconditionally false; folding them
# at build time eliminates the runtime overhead.
#
# 2026-05-22: extended the fold-to-false list to cover every trace ENV
# var used by the bundle. Profiling stage 0 (compiler/tungsten.w under
# the spinel-bootstrap path) showed 11.4 % of CPU in
# getenv + __findenv_locked: there are 30 ENV[...] sites scattered
# through visit_call / visit_def / visit_use / stack-trace helpers,
# each hitting __findenv_locked's mutex on every interpreter step.
# Folding them all to `false` is sound for non-debug runs since stage 0
# only ever runs from the bootstrap script (no human sets these vars).
# If you need any of these traces at debug time, comment the fold out
# and rebuild.
TRACE_ENV_VARS = %w[
  SPINEL_STAGE0_CALL_TRACE
  PROFILE_CALLS
  PROFILE_DISPATCH
  STAGE0_ARROW_TRACE
  STAGE0_BIND_TRACE
  STAGE0_BODY_TRACE
  STAGE0_STACK_TRACE
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
# Also fold the != "1" inverse where it appears (`unless ENV[…] == "1"` etc.)
final_bundle = final_bundle.gsub(/ENV\["(?:#{fold_pattern.source})"\] != "1"/, "true")
final_bundle = final_bundle.sub(
  "      @loaded_files = {}\n      @current_file = nil\n",
  "      @loaded_files = {}\n      @stage0_loading_depth = 0\n      @current_file = nil\n"
)
final_use_methods = <<~RUBY

  def stage0_progress_mark(event, detail = nil)
    path = ENV["TUNGSTEN_PROGRESS_LOG"]
    stdout_enabled = ENV["TUNGSTEN_PROGRESS_STDOUT"] == "1"
    return nil if (path == nil || path == "") && !stdout_enabled

    # Build via string concatenation rather than `String.new << x`: in the
    # stage0 bundle `String.new` resolves to the bundle's own String shim
    # class (a user object with no `<<` operator), which the C spinel
    # rejects. `+` on string literals lowers cleanly under both compilers.
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

  def stage0_symbol_start_char?(ch)
    code = ch.ord
    return true if code >= 65 && code <= 90
    return true if code >= 97 && code <= 122
    ch == "_"
  end

  def stage0_symbol_part_char?(ch)
    code = ch.ord
    return true if code >= 65 && code <= 90
    return true if code >= 97 && code <= 122
    return true if code >= 48 && code <= 57
    return true if ch == "_"
    return true if ch == "?"
    ch == "!"
  end

  def stage0_stringify_symbol_literals(line)
    out = ""
    in_string = false
    i = 0
    while i < line.length
      ch = line.slice(i, 1)
      if in_string
        out = out + ch
        if ch == "\\\\\\\\"
          if i + 1 < line.length
            out = out + line.slice(i + 1, 1)
            i += 2
            next
          end
        elsif ch == "\\\""
          in_string = false
        end
        i += 1
        next
      end
      if ch == "\\\""
        in_string = true
        out = out + ch
        i += 1
        next
      end
      if ch == ":" && i + 1 < line.length
        next_ch = line.slice(i + 1, 1)
        if stage0_symbol_start_char?(next_ch)
          j = i + 2
          while j < line.length && stage0_symbol_part_char?(line.slice(j, 1))
            j += 1
          end
          sym_name = line.slice(i + 1, j - i - 1)
          out = out + "\\\""
          out = out + sym_name
          out = out + "\\\""
          i = j
          next
        end
      end
      out = out + ch
      i += 1
    end
    out
  end

  def stage0_collapse_simple_hash_blocks(source)
    lines = source.to_s.split("\n")
    out = ""
    i = 0
    while i < lines.length
      line = lines[i]
      stripped = line.strip
      if stripped.length > 0 && stripped.slice(stripped.length - 1, 1) == "{"
        joined = ""
        j = i + 1
        close_token = ""
        ok = true
        while j < lines.length
          inner = lines[j].strip
          if inner == "}" || inner == "})"
            close_token = inner
            break
          end
          if joined != ""
            joined = joined + " "
          end
          joined = joined + inner
          j += 1
        end
        if ok && close_token != "" && joined != ""
          out = out + line
          out = out + joined
          out = out + close_token
          out = out + "\n"
          i = j + 1
          next
        end
      end
      out = out + line
      out = out + "\n"
      i += 1
    end
    out
  end

  def stage0_strip_inline_language_comments(source)
    lines = source.to_s.split("\n")
    out = ""
    i = 0
    while i < lines.length
      line = lines[i]
      if !line.strip.start_with?("#")
        in_string = false
        j = 0
        cut = -1
        while j < line.length
          ch = line.slice(j, 1)
          if in_string
            if ch == "\\\\\\\\"
              j += 2
              next
            elsif ch == "\\\""
              in_string = false
            end
          elsif ch == "\\\""
            in_string = true
          elsif ch == "#"
            if j == 0 || line.slice(j - 1, 1) == " " || line.slice(j - 1, 1) == "\t"
              cut = j
              break
            end
          end
          j += 1
        end
        if cut >= 0
          line = line.slice(0, cut)
        end
      end
      out = out + line
      out = out + "\n"
      i += 1
    end
    out
  end

  def stage0_normalize_source(source)
    lines = source.to_s.split("\\n")
    out = ""
    # Rewrite `<recv> << <expr>` (5 names: out, parts, result, fn_out,
    # globals_out) to `<recv> = <recv> + <expr>` per-line — spinel's
    # gsub-with-block silently no-ops (the block never fires), so the
    # regex/block approach we tried first didn't work at runtime even
    # though it works in CRuby. This split/join variant matches what
    # the rest of the bundle uses (and what spinel supports).
    rewrite_recvs = %w[out parts result fn_out globals_out]
    new_lines = ""
    li = 0
    while li < lines.length
      cur = lines[li]
      cur_stripped = cur.strip
      did_rewrite = false
      ri = 0
      while ri < rewrite_recvs.length
        recv = rewrite_recvs[ri]
        prefix = recv + " <" + "< "
        if cur_stripped.start_with?(prefix)
          # Preserve leading indentation by finding it
          ws_len = cur.length - cur.lstrip.length
          ws = cur.slice(0, ws_len)
          expr = cur_stripped.slice(prefix.length, cur_stripped.length - prefix.length)
          cur = ws + recv + " = " + recv + " + " + expr
          did_rewrite = true
          ri = rewrite_recvs.length
        end
        ri = ri + 1
      end
      new_lines = new_lines + cur + "\\n"
      li = li + 1
    end
    source = new_lines
    lines = source.split("\\n")
    i = 0
    while i < lines.length
      line = lines[i]
      if line.strip == "" || line.strip.start_with?("#")
        i += 1
        next
      end
      line = self.stage0_stringify_symbol_literals(line)
      line = self.stage0_rewrite_named_new(line, "Environment", "stage0_environment")
      line = self.stage0_rewrite_named_new(line, "Interpreter", "stage0_interpreter")
      line = self.stage0_rewrite_named_new(line, "Lexer", "stage0_lexer")
      line = self.stage0_rewrite_named_new(line, "Loader", "stage0_loader")
      line = self.stage0_rewrite_named_new(line, "Parser", "stage0_parser")
      line = self.stage0_rewrite_named_new(line, "RegexLexer", "stage0_regex_lexer")
      line = self.stage0_rewrite_named_new(line, "REPL", "stage0_repl")
      class_parts = line.split("+ ")
      if class_parts.length > 1 && class_parts[0] == ""
        out = out + "class "
        out = out + class_parts[1]
      else
        out = out + line
      end
      out = out + "\\n"
      i += 1
    end
    out_s = out
    out_s = out_s.split("raw_int_candidate_map(body, child_var_types)").join("{}")
    out_s = out_s.split("raw_int_candidate_map(body, ctx[\\\"var_types\\\"])" ).join("{}")
    out_s = out_s.split("raw_int_candidate_map(ast[\\\"expressions\\\"], var_types)").join("{}")
    start_pos = out_s.index("-> wire_module")
    end_pos = out_s.index("-> next_call_site_id")
    if start_pos >= 0 && end_pos >= 0
      # The original wire.w wire_module returns a symbol-keyed hash
      # (`source_path:`, `functions:`, etc.) and the rest of the
      # compiler reads back via `mod[:foo]`. The earlier rewrite to
      # string-keyed (`"source_path" =>`) was inconsistent with how
      # callers (lower_ast, emit_artifact, ...) actually access the
      # hash, leading to nil reads + crashes in stage0_primitive_call
      # ([] on a nil-typed value). Keep symbol keys here so the
      # access paths match.
      wire_module = "-> wire_module(source_path)\\n" +
                    "  result = {source_path: source_path, functions: [], strings: [], string_ids_by_text: {}, known_classes: {}, known_traits: {}, known_calls: {}, known_static_methods: {}, known_fn_param_counts: {}, known_fn_overloads: {}, known_typed_overload_counts: {}, known_unique_typed_overload_keys: {}, known_unique_typed_overload_param_types: {}, known_pure_calls: {}, fn_return_types: {}, class_methods: {}, cvar_globals: {}, fn_memo_tables: {}, fn_memo_table_order: [], used_memo_tables: {}, used_memo_table_order: [], top_level_vars: {}, top_level_var_types: {}, top_level_static_types: {}, next_string: 0, next_block: 0, next_ic: 0, next_call_site: 0, reuse_sites: [], next_reuse_site: 0}\\n" +
                    "  result\\n\\n"
      out_s = out_s.slice(0, start_pos) + wire_module + out_s.slice(end_pos, out_s.length - end_pos)
    end
    out_s
  end

  def stage0_normalize_source_without_symbol_stringify(source)
    lines = source.to_s.split("\n")
    out = ""
    i = 0
    while i < lines.length
      line = lines[i]
      if line.strip == "" || line.strip.start_with?("#")
        i += 1
        next
      end
      line = self.stage0_rewrite_named_new(line, "Environment", "stage0_environment")
      line = self.stage0_rewrite_named_new(line, "Interpreter", "stage0_interpreter")
      line = self.stage0_rewrite_named_new(line, "Lexer", "stage0_lexer")
      line = self.stage0_rewrite_named_new(line, "Loader", "stage0_loader")
      line = self.stage0_rewrite_named_new(line, "Parser", "stage0_parser")
      line = self.stage0_rewrite_named_new(line, "RegexLexer", "stage0_regex_lexer")
      line = self.stage0_rewrite_named_new(line, "REPL", "stage0_repl")
      class_parts = line.split("+ ")
      if class_parts.length > 1 && class_parts[0] == ""
        out = out + "class "
        out = out + class_parts[1]
      else
        out = out + line
      end
      out = out + "\n"
      i += 1
    end
    out
  end

  def stage0_normalize_regex_source(source)
    lines = source.to_s.split("\\n")
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
      out = out + line
      out = out + "\\n"
      i += 1
    end
    self.stage0_normalize_source(out)
  end

  def stage0_normalize_lexer_source(source)
    "class Lexer\n" +
      "  -> new(source, file = nil)\n" +
      "    stage0_set_lexer_input(source, file)\n" +
      "  -> tokenize\n" +
      "    stage0_tokenize_lexer_input()\n"
  end

  def stage0_normalize_wire_source(source)
    lines = self.stage0_normalize_source(source).split("\\n")
    out = ""
    skip_result_after_entry = false
    i = 0
    while i < lines.length
      line = lines[i]
      if line == "    blocks:          [],"
        out = out + "    blocks:          [{label: \\"__entry\\", instructions: []}],\\n"
        i += 1
        next
      end
      if line == "  start_block(result, \\"__entry\\")"
        skip_result_after_entry = true
        i += 1
        next
      end
      if skip_result_after_entry && line == "  result"
        skip_result_after_entry = false
        i += 1
        next
      end
      skip_result_after_entry = false
      out = out + line
      out = out + "\\n"
      i += 1
    end
    out_s = out
    build_start = out_s.index("-> build_function")
    build_end = out_s.index("-> next_temp")
    if build_start >= 0 && build_end > build_start
      build_fn = ""
      build_fn = build_fn + "-> build_function(name, params, return_type, is_toplevel, extra_params)\\n"
      build_fn = build_fn + "  result = {name: name, original_name: name, params: params, extra_params: extra_params, return_type: return_type, is_toplevel: is_toplevel, blocks: [], var_slots: {}, var_slot_types: {}, next_temp: 0, next_label: 0, next_var: 0, next_scope: 0, loop_stack: [], scope_recycle_stack: [nil], recycle_vars: {}, is_memoized: false, exit_label: nil, result_slot: nil}\\n"
      build_fn = build_fn + "  start_block(result, \\"__entry\\")\\n"
      build_fn = build_fn + "  result\\n\\n"
      out_s = out_s.slice(0, build_start) + build_fn + out_s.slice(build_end, out_s.length - build_end)
    end
    emit_start = out_s.index("-> emit_instruction")
    emit_end = out_s.index("-> emit_scope_push")
    if emit_start >= 0 && emit_end > emit_start
      emit_fn = ""
      emit_fn = emit_fn + "-> emit_instruction(f, instruction)\\n"
      emit_fn = emit_fn + "  blk = current_block(f)\\n"
      emit_fn = emit_fn + "  instrs = blk[\\"instructions\\"]\\n"
      emit_fn = emit_fn + "  instrs.push(instruction)\\n"
      emit_fn = emit_fn + "  stage0_hash_set(blk, \\"instructions\\", instrs)\\n"
      emit_fn = emit_fn + "  nil\\n"
      out_s = out_s.slice(0, emit_start) + emit_fn + out_s.slice(emit_end, out_s.length - emit_end)
    end
    finalize_start = out_s.index("-> finalize_function")
    finalize_end = out_s.index("-> optimize_function")
    if finalize_start >= 0 && finalize_end > finalize_start
      finalize_fn = ""
      finalize_fn = finalize_fn + "-> finalize_function(f)\\n"
      finalize_fn = finalize_fn + "  terminated = block_terminated(f)\\n"
      finalize_fn = finalize_fn + "  if env(\\"TUNGSTEN_STAGE0_LOWER_TRACE\\") == \\"1\\"\\n"
      finalize_fn = finalize_fn + "    trace = \\"terminated=\\" + type(terminated).to_s() + \\":\\" + terminated.to_s() + \\" return_type=\\" + f[\\"return_type\\"].to_s() + \\" before=\\" + f[\\"blocks\\"][0][\\"instructions\\"].size().to_s() + \\"\\\\n\\"\\n"
      finalize_fn = finalize_fn + "  if terminated\\n"
      finalize_fn = finalize_fn + "    nil\\n"
      finalize_fn = finalize_fn + "  else\\n"
      finalize_fn = finalize_fn + "    if env(\\"TUNGSTEN_STAGE0_LOWER_TRACE\\") == \\"1\\"\\n"
      finalize_fn = finalize_fn + "      trace = trace + \\"branch=else\\\\n\\"\\n"
      finalize_fn = finalize_fn + "    emit_recycles_for_current_scope(f)\\n"
      finalize_fn = finalize_fn + "    emit_instruction(f, {op: \\"ret_i32\\", value: \\"0\\"})\\n"
      finalize_fn = finalize_fn + "  if env(\\"TUNGSTEN_STAGE0_LOWER_TRACE\\") == \\"1\\"\\n"
      finalize_fn = finalize_fn + "    trace = trace + \\"after=\\" + f[\\"blocks\\"][0][\\"instructions\\"].size().to_s() + \\"\\\\n\\"\\n"
      finalize_fn = finalize_fn + "    write_file(\\"/tmp/tungsten-stage0-finalize-fn\\", trace)\\n"
      finalize_fn = finalize_fn + "  nil\\n"
      out_s = out_s.slice(0, finalize_start) + finalize_fn + out_s.slice(finalize_end, out_s.length - finalize_end)
    end
    out_s
  end

  def stage0_normalize_target_source(source)
    out = ""
    out = out + "-> detect_target\\n"
    out = out + "  { os: \\"macos\\", arch: \\"arm64\\", features: [] }\\n"
    out = out + "-> detect_features(os)\\n"
    out = out + "  []\\n"
    out = out + "-> detect_llvm_target\\n"
    out = out + "  { datalayout: \\"\\", triple: \\"\\", fn_attrs: \\"\\" }\\n"
    out = out + "-> detect_host_fn_attrs\\n"
    out = out + "  \\"\\"\\n"
    out = out + "-> normalize_designator(name)\\n"
    out = out + "  if name in (\\"amd64\\" \\"intel\\")\\n"
    out = out + "    return \\"x86_64\\"\\n"
    out = out + "  if name == \\"aarch64\\"\\n"
    out = out + "    return \\"arm64\\"\\n"
    out = out + "  name\\n"
    out = out + "-> evaluate_target_predicate(node, target)\\n"
    out = out + "  case node[:node]\\n"
    out = out + "  when :target_designator\\n"
    out = out + "    name = normalize_designator(node[:name])\\n"
    out = out + "    return target[:os] == name || target[:arch] == name\\n"
    out = out + "  when :target_and\\n"
    out = out + "    return evaluate_target_predicate(node[:left], target) && evaluate_target_predicate(node[:right], target)\\n"
    out = out + "  when :target_or\\n"
    out = out + "    return evaluate_target_predicate(node[:left], target) || evaluate_target_predicate(node[:right], target)\\n"
    out = out + "  when :target_not\\n"
    out = out + "    return !evaluate_target_predicate(node[:expression], target)\\n"
    out = out + "  false\\n"
    out = out + "-> target_matches?(predicate, capabilities, target)\\n"
    out = out + "  if !evaluate_target_predicate(predicate, target)\\n"
    out = out + "    return false\\n"
    out = out + "  i = 0\\n"
    out = out + "  while i < capabilities.size()\\n"
    out = out + "    if !target[:features].include?(capabilities[i])\\n"
    out = out + "      return false\\n"
    out = out + "    i += 1\\n"
    out = out + "  true\\n"
    out = out + "-> expand_on_guards(body, target)\\n"
    out = out + "  result = []\\n"
    out = out + "  i = 0\\n"
    out = out + "  while i < body.size()\\n"
    out = out + "    expr = body[i]\\n"
    out = out + "    if expr[:node] == :on_guard\\n"
    out = out + "      if target_matches?(expr[:predicate], expr[:capabilities], target)\\n"
    out = out + "        j = 0\\n"
    out = out + "        while j < expr[:body].size()\\n"
    out = out + "          result.push(expr[:body][j])\\n"
    out = out + "          j += 1\\n"
    out = out + "    else\\n"
    out = out + "      result.push(expr)\\n"
    out = out + "    i += 1\\n"
    out = out + "  result\\n"
    out
  end

  def stage0_normalize_lowering_source(source)
    normalized = self.stage0_normalize_source(self.stage0_strip_inline_language_comments(source))
    start_pos = normalized.index("-> ast_uses_argv")
    end_pos = normalized.index("-> mark_builtin_runtime_class_uses")
    if start_pos >= 0 && end_pos >= 0
      normalized = normalized.slice(0, start_pos) +
                   "-> ast_uses_argv(node)\\n  false\\n" +
                   normalized.slice(end_pos, normalized.length - end_pos)
    end
    profile_start = normalized.index("-> lower_ast_print_profile")
    profile_end = normalized.index("-> lower_ast(ast")
    if profile_start >= 0 && profile_end >= 0
      normalized = normalized.slice(0, profile_start) +
                   "-> lower_ast_print_profile(profile)\\n  nil\\n" +
                   normalized.slice(profile_end, normalized.length - profile_end)
    end
    maps_start = normalized.index("-> build_infer_maps")
    maps_end = normalized.index("-> normalize_type_symbol")
    if maps_start >= 0 && maps_end >= 0
      normalized = normalized.slice(0, maps_start) +
                   "-> build_infer_maps(int_op_map, cmp_op_map, float_op_map, fcmp_op_map)\\n  nil\\n" +
                   normalized.slice(maps_end, normalized.length - maps_end)
    end
    normalized = normalized.split("max_iter = 3").join("max_iter = 0")
    normalized = normalized.split("still_changing = true").join("still_changing = false")
    normalized = normalized.split("builtin_runtime_classes = [\\"Socket\\", \\"Response\\", \\"TLS\\", \\"StringBuffer\\", \\"StandardError\\"]").join("builtin_runtime_classes = nil")
    normalized = normalized.split("static_cond = static_bool_value(node[:condition])").join("static_cond = nil")
    normalized = normalized.split("static_cond = static_bool_value(node[\\"condition\\"])").join("static_cond = nil")
    normalized = normalized.split("  setup_started_at = clock()\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"setup_start\\\")\n" \
      "  setup_started_at = clock()\n"
    )
    normalized = normalized.split("  mod = wire_module(source_path)\n").join(
      "  mod = wire_module(source_path)\n" \
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"wire_module_done\\\")\n"
    )
    normalized = normalized.split("  builtin_classes = builtin_runtime_classes\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_builtin_classes\\\")\n" \
      "  builtin_classes = builtin_runtime_classes\n" \
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"after_builtin_classes\\\")\n"
    )
    normalized = normalized.split("  prepass_started_at = clock()\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_prepass\\\")\n" \
      "  prepass_started_at = clock()\n"
    )
    normalized = normalized.split("  collect_top_level_static_types(mod, ast[\\\"expressions\\\"])\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_static_types\\\")\n" \
      "  collect_top_level_static_types(mod, ast[\\\"expressions\\\"])\n" \
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"after_static_types\\\")\n"
    )
    normalized = normalized.split("  mark_builtin_runtime_class_uses(ast[\\\"expressions\\\"], mod)\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_builtin_uses\\\")\n" \
      "  mark_builtin_runtime_class_uses(ast[\\\"expressions\\\"], mod)\n" \
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"after_builtin_uses\\\")\n"
    )
    normalized = normalized.split("  source_class_init_started_at = clock()\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_source_classes\\\")\n" \
      "  source_class_init_started_at = clock()\n"
    )
    normalized = normalized.split("  collect_ivar_types(mod)\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_ivar_types\\\")\n" \
      "  collect_ivar_types(mod)\n" \
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"after_ivar_types\\\")\n"
    )
    normalized = normalized.split("  mark_nonescaping_small_arrays(ast[:expressions])\n").join("  nil\n")
    normalized = normalized.split("  mark_nonescaping_small_arrays(ast[\\\"expressions\\\"])\n").join(
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"skip_small_arrays\\\")\n" \
      "  nil\n"
    )
    normalized = self.stage0_collapse_simple_hash_blocks(normalized)
    normalized = normalized.split("  if !block_terminated(main_fn)\\n").join("  if block_terminated(main_fn) == false\\n")
    normalized = normalized.split("  if !block_terminated(wfn)\\n").join("  if block_terminated(wfn) == false\\n")
    normalized = normalized.split("    if !block_terminated(wfn)\\n").join("    if block_terminated(wfn) == false\\n")
    normalized = normalized.split("  if !block_terminated(new_fn)\\n").join("  if block_terminated(new_fn) == false\\n")
    normalized = normalized.split("    if !block_terminated(new_fn)\\n").join("    if block_terminated(new_fn) == false\\n")

    lower_statement_start = normalized.index("-> lower_statement(ctx, node)")
    lower_statement_end = normalized.index("-> lower_expression", lower_statement_start || 0)
    if lower_statement_start != nil && lower_statement_end != nil && lower_statement_end > lower_statement_start
      lower_statement = ""
      lower_statement = lower_statement + "-> lower_statement(ctx, node)\\n"
      lower_statement = lower_statement + "  t = node[\\\"node\\\"]\\n"
      lower_statement = lower_statement + "  if t == \\\"assign\\\"\\n"
      lower_statement = lower_statement + "    lower_assign_expr(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"if\\\"\\n"
      lower_statement = lower_statement + "    materialize_bindings(ctx)\\n"
      lower_statement = lower_statement + "    return lower_if(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"call\\\"\\n"
      lower_statement = lower_statement + "    if node[\\\"receiver\\\"] == nil && node[\\\"name\\\"] == \\\"constant_alias\\\"\\n"
      lower_statement = lower_statement + "      return nil\\n"
      lower_statement = lower_statement + "    lower_expression(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"return\\\"\\n"
      lower_statement = lower_statement + "    return lower_return(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"compound_assign\\\"\\n"
      lower_statement = lower_statement + "    lower_compound_assign(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"binary_op\\\"\\n"
      lower_statement = lower_statement + "    lower_expression(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"while\\\"\\n"
      lower_statement = lower_statement + "    materialize_bindings(ctx)\\n"
      lower_statement = lower_statement + "    return lower_while(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"method_def\\\"\\n"
      lower_statement = lower_statement + "    idx = ctx[\\\"enclosing_stmt_idx\\\"]\\n"
      lower_statement = lower_statement + "    if idx == nil\\n"
      lower_statement = lower_statement + "      idx = 0\\n"
      lower_statement = lower_statement + "    if false\\n"
      lower_statement = lower_statement + "      nil\\n"
      lower_statement = lower_statement + "    return lower_method_def(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"puts\\\"\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"print\\\"\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"fn_def\\\"\\n"
      lower_statement = lower_statement + "    return lower_fn_def(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"class_def\\\" || t == \\\"module_def\\\"\\n"
      lower_statement = lower_statement + "    return lower_class_def(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"trait_def\\\" || t == \\\"trait_include\\\"\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"case\\\"\\n"
      lower_statement = lower_statement + "    materialize_bindings(ctx)\\n"
      lower_statement = lower_statement + "    lower_case(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"case_value\\\"\\n"
      lower_statement = lower_statement + "    materialize_bindings(ctx)\\n"
      lower_statement = lower_statement + "    lower_case_value(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"begin\\\"\\n"
      lower_statement = lower_statement + "    materialize_bindings(ctx)\\n"
      lower_statement = lower_statement + "    return lower_begin(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"raise\\\"\\n"
      lower_statement = lower_statement + "    return lower_raise(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"break\\\"\\n"
      lower_statement = lower_statement + "    return lower_break(ctx)\\n"
      lower_statement = lower_statement + "  if t == \\\"next\\\"\\n"
      lower_statement = lower_statement + "    return lower_next(ctx)\\n"
      lower_statement = lower_statement + "  if t == \\\"with\\\"\\n"
      lower_statement = lower_statement + "    materialize_bindings(ctx)\\n"
      lower_statement = lower_statement + "    return lower_with(ctx, node)\\n"
      lower_statement = lower_statement + "  if t == \\\"yield\\\"\\n"
      lower_statement = lower_statement + "    lower_yield(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"passthrough\\\"\\n"
      lower_statement = lower_statement + "    lower_expression(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"go\\\"\\n"
      lower_statement = lower_statement + "    lower_go(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"multi_assign\\\"\\n"
      lower_statement = lower_statement + "    lower_multi_assign(ctx, node)\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  if t == \\\"on_guard\\\"\\n"
      lower_statement = lower_statement + "    return nil\\n"
      lower_statement = lower_statement + "  nil\\n"
      normalized = normalized.slice(0, lower_statement_start) + lower_statement + normalized.slice(lower_statement_end, normalized.length - lower_statement_end)
    end
    # The Spinel-built stage0 parser currently loses the top-level dedent
    # after this particular multi-line hash argument in lower_var. Keep the
    # source equivalent, but make the call one physical line for stage0.
    lower_var_self_dispatch = "    emit_instruction(wfn, {\\n" +
      "      op: :call_method_i64,\\n" +
      "      temp: temp,\\n" +
      "      temp_args_val: temp_args,\\n" +
      "      receiver: self_reg,\\n" +
      "      method_name_val: method_name_val,\\n" +
      "      args: [],\\n" +
      "      ic_id: ic_id\\n" +
      "    })\\n"
    normalized = normalized.split(lower_var_self_dispatch).join(
      "    emit_instruction(wfn, {op: :call_method_i64, temp: temp, temp_args_val: temp_args, receiver: self_reg, method_name_val: method_name_val, args: [], ic_id: ic_id})\\n"
    )
    normalized = normalized.split("  mod[:functions].push(main_fn)\\n").join("  mod[:functions].push(main_fn)\\n  if env(\\"TUNGSTEN_SPINEL_STAGE0_CALL_TRACE\\") == \\"1\\"\\n    write_file(\\"/tmp/tungsten-stage0-functions-size.txt\\", mod[:functions].size())\\n    write_file(\\"/tmp/tungsten-stage0-functions-string-size.txt\\", mod[\\"functions\\"].size())\\n")
    ctx_start = normalized.index("  ctx = {")
    ctx_end = -1
    if ctx_start >= 0
      ctx_tail = normalized.slice(ctx_start, normalized.length - ctx_start)
      ctx_marker = ctx_tail.index("  mark_builtin_runtime_class_uses")
      if ctx_marker != nil && ctx_marker >= 0
        ctx_end = ctx_start + ctx_marker
      end
    end
    if ctx_start >= 0 && ctx_end > ctx_start
	      ctx_block = ""
	      ctx_block = ctx_block + "  ctx = {}\\n"
	      ctx_block = ctx_block + "  ctx[\\\"mod\\\"] = mod\\n"
	      ctx_block = ctx_block + "  ctx[\\\"func\\\"] = main_fn\\n"
	      ctx_block = ctx_block + "  ctx[\\\"var_types\\\"] = var_types\\n"
	      ctx_block = ctx_block + "  ctx[\\\"class_name\\\"] = nil\\n"
	      ctx_block = ctx_block + "  ctx[\\\"source_path\\\"] = source_path\\n"
	      ctx_block = ctx_block + "  ctx[\\\"bindings\\\"] = {}\\n"
	      ctx_block = ctx_block + "  ctx[\\\"unboxed_vars\\\"] = {}\\n"
	      ctx_block = ctx_block + "  ctx[\\\"raw_int_candidates\\\"] = {}\\n"
	      ctx_block = ctx_block + "  ctx[\\\"method_name\\\"] = nil\\n"
	      ctx_block = ctx_block + "  ctx[\\\"is_class_method\\\"] = false\\n"
	      ctx_block = ctx_block + "  ctx[\\\"is_block\\\"] = false\\n"
	      ctx_block = ctx_block + "  ctx[\\\"verbose\\\"] = verbose\\n"
	      ctx_block = ctx_block + "  ctx[\\\"profile\\\"] = profile\\n"
	      # progress_enabled?() isn't defined anywhere in compiler/ — the
	      # template references a function that was either removed or
	      # never existed. Hard-code false in stage 0 (no progress UI
	      # during bootstrap). Drop this stub if/when progress_enabled?
	      # lands upstream.
	      ctx_block = ctx_block + "  ctx[\\\"progress\\\"] = false\\n"
	      ctx_block = ctx_block + "  ctx[\\\"progress_lowered_functions\\\"] = 0\\n"
	      ctx_block = ctx_block + "  ctx[:progress] = ctx[\\\"progress\\\"]\\n"
      normalized = normalized.slice(0, ctx_start) + ctx_block + normalized.slice(ctx_end, normalized.length - ctx_end)
    end
	    normalized = normalized.split("lowering_op_map = init_op_map()\\n").join("")
	    normalized = normalized.split("  prepend_memo_table_initializers(main_fn, mod)\\n").join("  nil\\n")
	    # Compiler refactor (commit 9a98107f etc.) migrated ast["expressions"]
	    # to ast.expressions across the lowering pipeline. The stage 0 bundle's
	    # AST is a Hash (`{"expressions" => out, :expressions => out, ...}`)
	    # and `hash.expressions` returns nil under stage 0's interpreter, so
	    # the rewrite below — which substitutes the lower_program call site
	    # with an inline iteration — needs to match BOTH spellings. The
	    # `.expressions` form is what current sources use.
	    normalized = normalized.split("  lower_program(ctx, ast.expressions)\\n").join("  lower_program(ctx, ast[\\\"expressions\\\"])\\n")
	    normalized = normalized.split("  lower_program(ctx, ast[\\\"expressions\\\"])\\n").join(
	      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
	      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_lower_program\\\")\n" \
	      "  statements = ast[\\\"expressions\\\"]\n" \
	      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
	      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"after_statements\\\")\n" \
	      "  prev_stmts = ctx[\\\"enclosing_stmts\\\"]\n" \
	      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
	      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"after_prev_stmts\\\")\n" \
	      "  ctx[\\\"enclosing_stmts\\\"] = statements\n" \
	      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
	      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"after_ctx_stmts\\\")\n" \
	      "  stage0_i = 0\n" \
	      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\n" \
	      "    write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"before_loop_size\\\")\n" \
	      "  while stage0_i < statements.size()\n" \
	      "    if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\" && stage0_i == 0\n" \
	      "      write_file(\\\"/tmp/tungsten-stage0-lower-phase\\\", \\\"inside_loop\\\")\n" \
	      "    ctx[\\\"enclosing_stmt_idx\\\"] = stage0_i\n" \
	      "    if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\" && stage0_i < 5\n" \
	      "      st = statements[stage0_i]\n" \
	      "      write_file(\\\"/tmp/tungsten-stage0-lower-stmt-\\\" + stage0_i.to_s(), \\\"i=\\\" + stage0_i.to_s() + \\\" node=\\\" + st[\\\"node\\\"].to_s())\n" \
	      "    lower_statement(ctx, statements[stage0_i])\n" \
	      "    if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\" && stage0_i < 5\n" \
	      "      write_file(\\\"/tmp/tungsten-stage0-lower-stmt-after-\\\" + stage0_i.to_s(), \\\"after_i=\\\" + stage0_i.to_s())\n" \
	      "    stage0_i += 1\n" \
	      "  ctx[\\\"enclosing_stmts\\\"] = prev_stmts\n" \
	      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\\n" \
	      "    trace = \\\"exprs=\\\" + ast[\\\"expressions\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
      "    trace = trace + \\\"blocks=\\\" + main_fn[\\\"blocks\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
      "    if main_fn[\\\"blocks\\\"].size() > 0\\n" \
      "      trace = trace + \\\"after_lower_instrs=\\\" + main_fn[\\\"blocks\\\"][0][\\\"instructions\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-lower-trace\\\", trace)\\n"
    )
	    normalized = normalized.split("    lower_statement(ctx, statements[i])\\n").join(
	      "    if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\" && i < 5\\n" \
	      "      st = statements[i]\\n" \
	      "      trace = \\\"i=\\\" + i.to_s() + \\\" node=\\\" + st[\\\"node\\\"].to_s() + \\\"/\\\" + st[:node].to_s() + \\\"\\\\n\\\"\\n" \
	      "      write_file(\\\"/tmp/tungsten-stage0-lower-stmt-\\\" + i.to_s(), trace)\\n" \
      "    lower_statement(ctx, statements[i])\\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\" && i < 5\\n" \
      "      trace = \\\"after_i=\\\" + i.to_s() + \\\" instrs=\\\" + ctx[\\\"func\\\"][\\\"blocks\\\"][0][\\\"instructions\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
	      "      write_file(\\\"/tmp/tungsten-stage0-lower-stmt-after-\\\" + i.to_s(), trace)\\n"
	    )
    lower_program_start = normalized.index("-> lower_program(ctx, statements)")
    lower_program_end = normalized.index("-> lower_statement(ctx, node)", lower_program_start || 0)
    if lower_program_start != nil && lower_program_end != nil && lower_program_end > lower_program_start
      lower_program = ""
      lower_program = lower_program + "-> lower_program(ctx, statements)\\n"
      lower_program = lower_program + "  prev_stmts = ctx[\\\"enclosing_stmts\\\"]\\n"
      lower_program = lower_program + "  ctx[\\\"enclosing_stmts\\\"] = statements\\n"
      lower_program = lower_program + "  i = 0\\n"
      lower_program = lower_program + "  while i < statements.size()\\n"
      lower_program = lower_program + "    if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\" && i < 5\\n"
      lower_program = lower_program + "      st = statements[i]\\n"
      lower_program = lower_program + "      write_file(\\\"/tmp/tungsten-stage0-lower-stmt-\\\" + i.to_s(), \\\"i=\\\" + i.to_s() + \\\" node=\\\" + st[\\\"node\\\"].to_s())\\n"
      lower_program = lower_program + "    if block_terminated(ctx[\\\"func\\\"])\\n"
      lower_program = lower_program + "      ctx[\\\"enclosing_stmts\\\"] = prev_stmts\\n"
      lower_program = lower_program + "      return nil\\n"
      lower_program = lower_program + "    ctx[\\\"enclosing_stmt_idx\\\"] = i\\n"
      lower_program = lower_program + "    lower_statement(ctx, statements[i])\\n"
      lower_program = lower_program + "    if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\" && i < 5\\n"
      lower_program = lower_program + "      write_file(\\\"/tmp/tungsten-stage0-lower-stmt-after-\\\" + i.to_s(), \\\"after_i=\\\" + i.to_s())\\n"
      lower_program = lower_program + "    i += 1\\n"
      lower_program = lower_program + "  ctx[\\\"enclosing_stmts\\\"] = prev_stmts\\n"
      lower_program = lower_program + "  nil\\n"
      normalized = normalized.slice(0, lower_program_start) + lower_program + normalized.slice(lower_program_end, normalized.length - lower_program_end)
    end
	    normalized = normalized.split("  finalize_function(main_fn)\\n").join(
	      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\\n" \
      "    trace = \\\"before_finalize_blocks=\\\" + main_fn[\\\"blocks\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
      "    if main_fn[\\\"blocks\\\"].size() > 0\\n" \
      "      trace = trace + \\\"before_finalize_instrs=\\\" + main_fn[\\\"blocks\\\"][0][\\\"instructions\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
      "    bt = block_terminated(main_fn)\\n" \
      "    trace = trace + \\\"block_terminated=\\\" + type(bt).to_s() + \\\":\\\" + bt.to_s() + \\\"\\\\n\\\"\\n" \
      "    if bt == false\\n" \
      "      trace = trace + \\\"not_bt_branch=1\\\\n\\\"\\n" \
      "    else\\n" \
      "      trace = trace + \\\"not_bt_branch=0\\\\n\\\"\\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-finalize-before\\\", trace)\\n" \
      "  finalize_function(main_fn)\\n" \
      "  if env(\\\"TUNGSTEN_STAGE0_LOWER_TRACE\\\") == \\\"1\\\"\\n" \
      "    trace = \\\"after_finalize_blocks=\\\" + main_fn[\\\"blocks\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
      "    if main_fn[\\\"blocks\\\"].size() > 0\\n" \
      "      trace = trace + \\\"after_finalize_instrs=\\\" + main_fn[\\\"blocks\\\"][0][\\\"instructions\\\"].size().to_s() + \\\"\\\\n\\\"\\n" \
      "    write_file(\\\"/tmp/tungsten-stage0-finalize-after\\\", trace)\\n"
    )
    normalized = normalized.split("lowering_int_op_map = init_int_op_map()\\n").join("")
    normalized = normalized.split("lowering_cmp_op_map = init_cmp_op_map()\\n").join("")
    normalized = normalized.split("lowering_float_op_map = init_float_op_map()\\n").join("")
    normalized = normalized.split("lowering_fcmp_op_map = init_fcmp_op_map()\\n").join("")
    normalized = normalized.split("lowering_infer_maps = build_infer_maps(lowering_int_op_map, lowering_cmp_op_map, lowering_float_op_map, lowering_fcmp_op_map)\\n").join("")
    normalized
  end

  def stage0_normalize_content_hash_source(source)
    "-> content_hash_pass(mod, verbose = false)\\n  mod\\n"
  end

  def stage0_normalize_loader_source(_source)
    source = ""
    source = source + "use lexer\\n"
    source = source + "use parser\\n"
    source = source + "\\n"
    source = source + "+ Loader\\n"
    source = source + "  -> new(@verbose = false)\\n"
    source = source + "    @loaded_files = []\\n"
    source = source + "\\n"
    source = source + "  -> load_program_ast(path, from_file = nil)\\n"
    source = source + "    resolved = resolve_path(path, from_file)\\n"
    source = source + "    if env(\\\"TUNGSTEN_STAGE0_LOADER_TRACE\\\") == \\\"1\\\"\\n"
    source = source + "      trace_path = \\\"/tmp/tungsten-stage0-loader-trace.txt\\\"\\n"
    source = source + "      trace_text = \\\"\\\"\\n"
    source = source + "      if file?(trace_path)\\n"
    source = source + "        trace_text = read_file(trace_path)\\n"
    source = source + "      write_file(trace_path, trace_text + \\\"load \\\" + resolved + \\\"\\\\n\\\")\\n"
    source = source + "    if @loaded_files.include?(resolved)\\n"
    source = source + "      if env(\\\"TUNGSTEN_STAGE0_LOADER_TRACE\\\") == \\\"1\\\"\\n"
    source = source + "        trace_path = \\\"/tmp/tungsten-stage0-loader-trace.txt\\\"\\n"
    source = source + "        write_file(trace_path, read_file(trace_path) + \\\"skip \\\" + resolved + \\\"\\\\n\\\")\\n"
    source = source + "      empty_tokens = stage0_tokenize_source(\\\"\\\", resolved)\\n"
    source = source + "      empty_parser = Parser.new(empty_tokens)\\n"
    source = source + "      return empty_parser.parse()\\n"
    source = source + "    @loaded_files.push(resolved)\\n"
    source = source + "    if env(\\\"TUNGSTEN_STAGE0_LOADER_TRACE\\\") == \\\"1\\\"\\n"
    source = source + "      trace_path = \\\"/tmp/tungsten-stage0-loader-trace.txt\\\"\\n"
    source = source + "      write_file(trace_path, read_file(trace_path) + \\\"read \\\" + resolved + \\\"\\\\n\\\")\\n"
    source = source + "    source = read_file(resolved)\\n"
    source = source + "    tokens = stage0_tokenize_source(source, resolved)\\n"
    source = source + "    parser = Parser.new(tokens)\\n"
    source = source + "    if env(\\\"TUNGSTEN_STAGE0_LOADER_TRACE\\\") == \\\"1\\\"\\n"
    source = source + "      trace_path = \\\"/tmp/tungsten-stage0-loader-trace.txt\\\"\\n"
    source = source + "      write_file(trace_path, read_file(trace_path) + \\\"parser-new \\\" + resolved + \\\"\\\\n\\\")\\n"
    source = source + "    ast = parser.parse()\\n"
    source = source + "    if env(\\\"TUNGSTEN_STAGE0_LOADER_TRACE\\\") == \\\"1\\\"\\n"
    source = source + "      trace_path = \\\"/tmp/tungsten-stage0-loader-trace.txt\\\"\\n"
    source = source + "      write_file(trace_path, read_file(trace_path) + \\\"parsed \\\" + resolved + \\\"\\\\n\\\")\\n"
    source = source + "    expressions = []\\n"
    source = source + "    i = 0\\n"
    source = source + "    raw_expressions = ast_get(ast, :expressions)\\n"
    source = source + "    while i < raw_expressions.size()\\n"
    source = source + "      expr = raw_expressions[i]\\n"
    source = source + "      if ast_kind(expr) == :use\\n"
    source = source + "        imported = self.load_program_ast(ast_get(expr, :path), resolved)\\n"
    source = source + "        j = 0\\n"
    source = source + "        imported_expressions = ast_get(imported, :expressions)\\n"
    source = source + "        while j < imported_expressions.size()\\n"
    source = source + "          expressions.push(imported_expressions[j])\\n"
    source = source + "          j += 1\\n"
    source = source + "      else\\n"
    source = source + "        expressions.push(expr)\\n"
    source = source + "      i += 1\\n"
    source = source + "    ast_set(ast, :expressions, expressions)\\n"
    source = source + "    if env(\\\"TUNGSTEN_STAGE0_LOADER_TRACE\\\") == \\\"1\\\"\\n"
    source = source + "      trace_path = \\\"/tmp/tungsten-stage0-loader-trace.txt\\\"\\n"
    source = source + "      write_file(trace_path, read_file(trace_path) + \\\"done \\\" + resolved + \\\"\\\\n\\\")\\n"
    source = source + "    ast\\n"
    source = source + "\\n"
    source = source + "  -> resolve_path(path, from_file = nil)\\n"
    source = source + "    if path.ends_with?(\\\".w\\\") && file?(path)\\n"
    source = source + "      return path\\n"
    source = source + "    base_dir = \\\"\\\"\\n"
    source = source + "    root_dir = \\\"\\\"\\n"
    source = source + "    if from_file != nil\\n"
    source = source + "      parts = from_file.split(\\\"/\\\")\\n"
    source = source + "      count = parts.size() - 1\\n"
    source = source + "      pi = 0\\n"
    source = source + "      while pi < count\\n"
    source = source + "        if pi == 0\\n"
    source = source + "          base_dir = parts[pi]\\n"
    source = source + "        else\\n"
    source = source + "          base_dir = base_dir + \\\"/\\\" + parts[pi]\\n"
    source = source + "        pi += 1\\n"
    source = source + "      root_dir = base_dir\\n"
    source = source + "      if count > 0 && parts[count - 1] == \\\"lib\\\"\\n"
    source = source + "        root_dir = \\\"\\\"\\n"
    source = source + "        pi = 0\\n"
    source = source + "        while pi < count - 1\\n"
    source = source + "          if pi == 0\\n"
    source = source + "            root_dir = parts[pi]\\n"
    source = source + "          else\\n"
    source = source + "            root_dir = root_dir + \\\"/\\\" + parts[pi]\\n"
    source = source + "          pi += 1\\n"
    source = source + "    resolved = path\\n"
    source = source + "    if !resolved.ends_with?(\\\".w\\\")\\n"
    source = source + "      resolved = resolved + \\\".w\\\"\\n"
    source = source + "    if file?(resolved)\\n"
    source = source + "      return resolved\\n"
    source = source + "    candidate = base_dir + \\\"/\\\" + path\\n"
    source = source + "    if !candidate.ends_with?(\\\".w\\\")\\n"
    source = source + "      candidate = candidate + \\\".w\\\"\\n"
    source = source + "    if file?(candidate)\\n"
    source = source + "      return candidate\\n"
    source = source + "    if root_dir != \\\"\\\"\\n"
    source = source + "      candidate = root_dir + \\\"/\\\" + path\\n"
    source = source + "      if !candidate.ends_with?(\\\".w\\\")\\n"
    source = source + "        candidate = candidate + \\\".w\\\"\\n"
    source = source + "      if file?(candidate)\\n"
    source = source + "        return candidate\\n"
    source = source + "    candidate = \\\"compiler/\\\" + path\\n"
    source = source + "    if !candidate.ends_with?(\\\".w\\\")\\n"
    source = source + "      candidate = candidate + \\\".w\\\"\\n"
    source = source + "    if file?(candidate)\\n"
    source = source + "      return candidate\\n"
    source = source + "    resolved\\n"
    stage0_normalize_compiler_language_source(source)
  end

  def stage0_normalize_compiler_language_source(source)
    normalized = ""
    normalized = "" + self.stage0_normalize_source(self.stage0_strip_inline_language_comments(source)).to_s
    if normalized.include?("-> ast_file(path, source, body)") && normalized.include?("slab_alloc_init(")
      return "" + self.stage0_normalize_ast_source(normalized).to_s
    end
    normalized = normalized.split("stage0_loader(").join("Loader.new(")
    normalized = normalized.split("stage0_lexer(").join("Lexer.new(")
    normalized = normalized.split("stage0_parser(").join("Parser.new(")
    normalized = normalized.split("stage0_interpreter(").join("Interpreter.new(")
    normalized = normalized.split("stage0_regex_lexer(").join("RegexLexer.new(")
    normalized = self.stage0_patch_parser_source(normalized)
    "" + normalized.to_s
  end

  def stage0_normalize_ruby_parse_source(source)
    lines = self.stage0_strip_inline_language_comments(source).split("\n")
    out = ""
    i = 0
    while i < lines.length
      line = lines[i]
      stripped = line.strip
      if stripped != "" && !stripped.start_with?("#")
        line = self.stage0_stringify_symbol_literals(line)
        then_return = line.index(" then return ")
        if then_return != nil && then_return >= 0
          indent = ""
          j = 0
          while j < line.length && line.slice(j, 1) == " "
            indent = indent + " "
            j += 1
          end
          before = line.slice(0, then_return)
          after = line.slice(then_return + 13, line.length - then_return - 13)
          out = out + before
          out = out + "\n"
          out = out + indent
          out = out + "  return "
          out = out + after
          out = out + "\n"
        else
          out = out + line
          out = out + "\n"
        end
      end
      i += 1
    end
    normalized = out.split("emit_instruction(wfn, {op: \\\"const_color\\\", temp: temp,\\n    r: (packed >> 24) & 0xff,\\n    g: (packed >> 16) & 0xff,\\n    b: (packed >> 8) & 0xff,\\n    a: packed & 0xff})").join("emit_instruction(wfn, {op: \\\"const_color\\\", temp: temp, r: (packed >> 24) & 0xff, g: (packed >> 16) & 0xff, b: (packed >> 8) & 0xff, a: packed & 0xff})")
    normalized = normalized.split("raw_int_candidate_map(body, child_var_types)").join("{}")
    normalized = normalized.split("raw_int_candidate_map(body, ctx[\\\"var_types\\\"])" ).join("{}")
    normalized
  end

  def stage0_normalize_ast_source(source)
    return ""

    out = ""
    ctor_source = source.split("-> ast_node_key(node)")[0]
    ctor_source.split("\n").each do |line|
      stripped = line.strip
      next unless stripped.start_with?("-> ast_")

      sig = stripped.byteslice(3, stripped.length - 3)
      open_idx = sig.index("(")
      if open_idx == nil
        name = sig
        params_src = ""
      else
        name = sig.byteslice(0, open_idx)
        rest = sig.byteslice(open_idx + 1, sig.length - open_idx - 1)
        close_idx = rest.index(")")
        if close_idx == nil
          params_src = rest
        else
          params_src = rest.byteslice(0, close_idx)
        end
      end
      node_name = name.sub(/^ast_/, "")
      node_name = "nil_lit" if node_name == "nil"
      node_name = "self_ref" if node_name == "self"
      node_name = "return" if node_name == "return_nil"
      params = params_src.split(",").map do |part|
        part.strip.split("=").first.strip
      end.reject(&:empty?)

      out << "-> " + name
      out << "(" + params_src + ")" unless params_src.empty?
      out << "\n"
      fields = ["node: :" + node_name]
      params.each do |param_name|
        fields << param_name + ": " + param_name
      end
      out << "  {" + fields.join(", ") + "}\n\n"
    end

    out << <<~W
      -> ast_node_key(node)
        node

      -> ast_get(node, sym)
        if node == nil
          return nil
        if type(node) == "Hash"
          value = node[sym]
          if value != nil
            return value
          return node[sym.to_s()]
        nil

      -> ast_set(node, sym, value)
        if node == nil
          return nil
        if type(node) == "Hash"
          node[sym.to_s()] = value
          return value
        value

      -> ast_kind(node)
        if node == nil
          return nil
        if type(node) == "Hash"
          value = node["node"]
          if value != nil
            return value
          return node[:node]
        nil

      -> block_body(node)
        ast_get(node, :body)

      -> program_body(node)
        ast_get(node, :expressions)

      -> is_ast_node?(node)
        type(node) == "Hash" && ast_kind(node) != nil

      -> ast_children_program(node)
        out = []
        exprs = program_body(node)
        if exprs != nil
          j = 0
          while j < exprs.size()
            elt = exprs[j]
            if is_ast_node?(elt)
              out.push(elt)
            j += 1
        out

      -> ast_children_block(node)
        out = []
        params = ast_get(node, :params)
        if params != nil
          j = 0
          while j < params.size()
            elt = params[j]
            if is_ast_node?(elt)
              out.push(elt)
            j += 1
        body = block_body(node)
        if body != nil
          j = 0
          while j < body.size()
            elt = body[j]
            if is_ast_node?(elt)
              out.push(elt)
            j += 1
        out

      -> ast_children(node)
        out = []
        if type(node) != "Hash"
          return out
        keys = node.keys()
        i = 0
        while i < keys.size()
          v = node[keys[i]]
          if is_ast_node?(v)
            out.push(v)
          elsif type(v) == "Array"
            j = 0
            while j < v.size()
              elt = v[j]
              if is_ast_node?(elt)
                out.push(elt)
              j += 1
          i += 1
        out

      -> ast_array_fields(node)
        ast_children(node)

      -> ast_deep_clone(node)
        node
    W
    out
  end

  def stage0_replace_parser_method(source, name, replacement)
    marker = "  -> " + name
    start_pos = source.index(marker)
    if ENV["TUNGSTEN_STAGE0_PATCH_DEBUG"] == "1"
      File.write("/tmp/tungsten-stage0-patch-debug.txt",
                 "replace " + name.to_s + " start=" + start_pos.to_s + "\n")
    end
    if start_pos == nil || start_pos < 0
      return source
    end
    tail_start = start_pos + marker.length
    tail = source.slice(tail_start, source.length - tail_start)
    rel_end = tail.index("\n  -> ")
    if rel_end == nil || rel_end < 0
      end_pos = source.length
    else
      end_pos = tail_start + rel_end
    end
    source.slice(0, start_pos) + replacement + source.slice(end_pos, source.length - end_pos)
  end

  def stage0_prefix_parser_self_calls(source)
    source
  end

  def stage0_patch_parser_source(source)
    marker_pos = source.index("  -> parse_call_chain")
    if ENV["TUNGSTEN_STAGE0_PATCH_DEBUG"] == "1"
      File.write("/tmp/tungsten-stage0-patch-debug.txt",
                 "patch marker=" + marker_pos.to_s + "\n")
    end
    if marker_pos == nil || marker_pos < 0
      return source
    end
    source = source.split("  -> new(@tokens)\n").join(
      "  -> new(tokens)\n" \
      "    @tokens = tokens\n"
    )
    source = source.split("    @pos = 0\n    @token_count = @tokens.size()").join(
      "    @pos = 0\n" \
      "    @current_type = \\\"\\\"\n" \
      "    @current_value = \\\"\\\"\n" \
      "    @token_count = @tokens.size()"
    )
    source = source.split("    @pos = 0\n    @current_type = \\\"\\\"\n").join(
      "    @pos = 0\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_WPARSER_INIT_TRACE\\\") == \\\"1\\\"\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-parser-new-1\\\", @tokens.size().to_s())\n" \
      "    @current_type = \\\"\\\"\n"
    )
    source = source.split("    sync_current()\n  -> sync_current\n").join(
      "    if env(\\\"TUNGSTEN_STAGE0_WPARSER_INIT_TRACE\\\") == \\\"1\\\"\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-parser-new-before-sync\\\", @token_count.to_s())\n" \
      "    sync_current()\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_WPARSER_INIT_TRACE\\\") == \\\"1\\\"\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-parser-new-after-sync\\\", @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" \
      "  -> sync_current\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_WPARSER_INIT_TRACE\\\") == \\\"1\\\"\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-parser-sync-enter\\\", @pos.to_s() + \\\":\\\" + @token_count.to_s())\n"
    )
    source = source.split("      @current_type = @current_token[\\\"type\\\"]\n      @current_value = @current_token[\\\"value\\\"]").join(
      "      @current_type = @current_token[\\\"type\\\"].to_s()\n" \
      "      @current_value = @current_token[\\\"value\\\"]\n" \
      "      if env(\\\"TUNGSTEN_STAGE0_WPARSER_INIT_TRACE\\\") == \\\"1\\\"\n" \
      "        write_file(\\\"/tmp/tungsten-stage0-parser-sync-token\\\", @current_type.to_s() + \\\":\\\" + @current_value.to_s())"
    )
    source = source.split("    @current_type = \\\"EOF\\\"\n    @current_value = nil").join(
      "    @current_type = \\\"EOF\\\"\n" \
      "    @current_value = \\\"\\\""
    )
    source = source.split("  -> parse_primary\n").join("  -> parse_primary\n    skip_spaces()\n")
    source = source.split("  -> parse_primary\n    skip_spaces()\n").join(
      "  -> parse_primary\n" \
      "    skip_spaces()\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_ARROW_TRACE\\\") == \\\"1\\\" && at?(\\\"ARROW\\\")\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-arrow-primary\\\", @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n"
    )
    source = source.split("    left = parse_ternary()\n\n    # Multi-assignment").join(
      "    left = parse_ternary()\n" \
      "    skip_spaces()\n\n" \
      "    # Multi-assignment"
    )
    source = source.split("    left = parse_ternary()\n    if at?(\\\"COMMA\\\")").join(
      "    left = parse_ternary()\n" \
      "    skip_spaces()\n" \
      "    if at?(\\\"COMMA\\\")"
    )
    {
      "PLUS_EQ" => "PLUS_EQ",
      "MINUS_EQ" => "MINUS_EQ",
      "STAR_EQ" => "STAR_EQ",
      "SLASH_EQ" => "SLASH_EQ",
      "PERCENT_EQ" => "PERCENT_EQ",
      "PLUS_PLUS" => "PLUS_PLUS",
      "MINUS_MINUS" => "MINUS_MINUS",
      "OR_ASSIGN" => "OR_ASSIGN"
    }.each do |sym_name, string_name|
      source = source.split("if at?(:" + sym_name + ")").join("if at?(\\\"" + string_name + "\\\")")
    end
    source = source.split("    tok = @current_token\n    while tok[\\\"type\\\"] in").join(
      "    skip_spaces()\n" \
      "    tok = @current_token\n" \
      "    while tok[\\\"type\\\"] in"
    )
    source = source.split("      left = ast_binary_op(left, op, right)\n      tok = @current_token").join(
      "      left = ast_binary_op(left, op, right)\n" \
      "      skip_spaces()\n" \
      "      tok = @current_token"
    )
    source = source.split("    left = parse_unary()\n    if at?(\\\"POW\\\")").join(
      "    left = parse_unary()\n" \
      "    skip_spaces()\n" \
      "    if at?(\\\"POW\\\")"
    )
    source = source.split("      return parse_method_def()\n").join(
      "      if env(\\\"TUNGSTEN_STAGE0_ARROW_TRACE\\\") == \\\"1\\\"\n" \
      "        write_file(\\\"/tmp/tungsten-stage0-arrow-method-branch\\\", @pos.to_s() + \\\":peek=\\" + peek()[\\\"type\\\"].to_s())\n" \
      "      return parse_method_def()\n"
    )
    source = source.split("    if at?(\\\"KEYWORD\\\", \\\"true\\\")\n").join(
      "    if at?(\\\"TRUE\\\")\n" \
      "      advance()\n" \
      "      return ast_bool(true)\n" \
      "    if at?(\\\"FALSE\\\")\n" \
      "      advance()\n" \
      "      return ast_bool(false)\n" \
      "    if at?(\\\"NIL\\\")\n" \
      "      advance()\n" \
      "      return ast_nil()\n" \
      "    if at?(\\\"KEYWORD\\\", \\\"true\\\")\n"
    )
    source = source.split("    if at?(:PUTS_OP)\n").join(
      "    if at?(\\\"LSHIFT\\\")\n" \
      "      advance()\n" \
      "      value = parse_assignment()\n" \
      "      return ast_puts(value)\n" \
      "    if at?(\\\"PUTS_OP\\\")\n" \
      "      advance()\n" \
      "      value = parse_assignment()\n" \
      "      return ast_puts(value)\n" \
      "    if at?(:PUTS_OP)\n"
    )
    source = source.split("    then_body = parse_body()\n\n    elsif_clauses = []\n").join(
      "    then_body = parse_body()\n" \
      "    skip_newlines()\n" \
      "    skip_spaces()\n\n" \
      "    elsif_clauses = []\n"
    )
    source = source.split("    then_body = parse_body()\n    elsif_clauses = []\n").join(
      "    then_body = parse_body()\n" \
      "    skip_newlines()\n" \
      "    skip_spaces()\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_IF_TRACE\\\") == \\\"1\\\"\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-if-trace\\\", @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" \
      "    elsif_clauses = []\n"
    )
    source = source.split("    while at?(\\\"KEYWORD\\\", \\\"elsif\\\")\n").join(
      "    while at?(\\\"KEYWORD\\\", \\\"elsif\\\")\n" \
      "      if env(\\\"TUNGSTEN_STAGE0_IF_TRACE\\\") == \\\"1\\\"\n" \
      "        write_file(\\\"/tmp/tungsten-stage0-if-trace\\\", \\\"elsif:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n"
    )
    source = source.split("    arrow_tok = expect(\\\"ARROW\\\")\n    method_line = arrow_tok[\\\"line\\\"]\n").join(
      "    arrow_tok = expect(\\\"ARROW\\\")\n" \
      "    skip_spaces()\n" \
      "    method_line = arrow_tok[\\\"line\\\"]\n"
    )
    source = source.split("elsif at?(\\\"INDENT\\\")\n      body = parse_body()").join(
      "elsif at?(\\\"INDENT\\\")\n" \
      "      body = parse_body()\n" \
      "    elsif at?(\\\"SP\\\")\n" \
      "      body = parse_body()"
    )
    source = source.split("        match?(\\\"COMMA\\\")\n      expect(\\\"RPAREN\\\")").join(
      "        match?(\\\"COMMA\\\")\n" \
      "        skip_spaces()\n" \
      "      expect(\\\"RPAREN\\\")"
    )
    source = source.split("    elsif at?(\\\"LPAREN\\\")\n      advance()\n      while !at?(\\\"RPAREN\\\")\n        params.push(parse_method_param())\n        match?(\\\"COMMA\\\")\n        skip_spaces()\n      expect(\\\"RPAREN\\\")").join(
      "    elsif at?(\\\"LPAREN\\\")\n" \
      "      advance()\n" \
      "      keep_params = true\n" \
      "      while keep_params\n" \
      "        skip_spaces()\n" \
      "        if at?(\\\"RPAREN\\\")\n" \
      "          keep_params = false\n" \
      "        else\n" \
      "          params.push(parse_method_param())\n" \
      "          skip_spaces()\n" \
      "          if at?(\\\"COMMA\\\")\n" \
      "            advance()\n" \
      "            skip_spaces()\n" \
      "          else\n" \
      "            keep_params = false\n" \
      "      expect(\\\"RPAREN\\\")"
    )
    source = source.split("      tok = expect_identifier_name()\n      param_name = tok[\\\"value\\\"]\n    if at?(\\\"COLON\\\")\n").join(
      "      tok = expect_identifier_name()\n" \
      "      param_name = tok[\\\"value\\\"]\n" \
      "    skip_spaces()\n" \
      "    if at?(\\\"COLON\\\")\n"
    )
    source = source.split("      advance()\n      default = nil\n      if !at?(\\\"COMMA\\\") && !at?(\\\"RPAREN\\\")\n").join(
      "      advance()\n" \
      "      skip_spaces()\n" \
      "      default = nil\n" \
      "      if !at?(\\\"COMMA\\\") && !at?(\\\"RPAREN\\\")\n"
    )
    source = source.split("    if at?(\\\"ASSIGN\\\")\n      advance()\n      default = parse_expression()\n").join(
      "    if at?(\\\"ASSIGN\\\")\n" \
      "      advance()\n" \
      "      skip_spaces()\n" \
      "      default = parse_expression()\n"
    )
    source = source.split("    skip_newlines()\n    body = nil\n").join(
      "    skip_newlines()\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_METHOD_BODY_TRACE\\\") == \\\"1\\\"\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-method-body-start\\\", base_name.to_s() + \\\":\\" + @pos.to_s() + \\\":\\" + @current_type.to_s() + \\\":\\" + @current_value.to_s())\n" \
      "    body = nil\n"
    )
    source = source.split("      if !at?(\\\"NEWLINE\\\") && !at?(\\\"DEDENT\\\") && !at?(\\\"EOF\\\") && !at?(\\\"SEMICOLON\\\")\n        trailing_expr = parse_expression()\n").join(
      "      stop_trailing = false\n" \
      "      if at?(\\\"NEWLINE\\\")\n" \
      "        stop_trailing = true\n" \
      "      if at?(\\\"DEDENT\\\")\n" \
      "        stop_trailing = true\n" \
      "      if at?(\\\"EOF\\\")\n" \
      "        stop_trailing = true\n" \
      "      if at?(\\\"SEMICOLON\\\")\n" \
      "        stop_trailing = true\n" \
      "      if stop_trailing == false\n" \
      "        trailing_expr = parse_expression()\n"
    )
    source = source.split("    result = ast_method_def(base_name, params, body, type_hints, is_class_method)\n").join(
      "    result = ast_method_def(base_name, params, body, type_hints, is_class_method)\n" \
      "    if env(\\\"TUNGSTEN_STAGE0_METHOD_PARSE_TRACE\\\") == \\\"1\\\"\n" \
      "      write_file(\\\"/tmp/tungsten-stage0-method-parse-trace\\\", base_name.to_s() + \\\":\\\" + result[\\\"node\\\"].to_s())\n"
    )
    source = source.split("      elsif_body = parse_body()\n      elsif_clauses.push([elsif_cond, elsif_body])\n").join(
      "      elsif_body = parse_body()\n" \
      "      skip_newlines()\n" \
      "      skip_spaces()\n" \
      "      elsif_clauses.push([elsif_cond, elsif_body])\n"
    )
    source = source.split("    body = parse_body()\n\n    rescue_var = nil\n").join(
      "    body = parse_body()\n" \
      "    skip_newlines()\n" \
      "    skip_spaces()\n\n" \
      "    rescue_var = nil\n"
    )
    source = source.split("    body = parse_body()\n    rescue_var = nil\n").join(
      "    body = parse_body()\n" \
      "    skip_newlines()\n" \
      "    skip_spaces()\n" \
      "    rescue_var = nil\n"
    )
    source = source.split("      rescue_body = parse_body()\n\n    ensure_body = nil\n").join(
      "      rescue_body = parse_body()\n" \
      "      skip_newlines()\n" \
      "      skip_spaces()\n\n" \
      "    ensure_body = nil\n"
    )
    source = source.split("      rescue_body = parse_body()\n    ensure_body = nil\n").join(
      "      rescue_body = parse_body()\n" \
      "      skip_newlines()\n" \
      "      skip_spaces()\n" \
      "    ensure_body = nil\n"
    )

    parse_call_chain = "  -> parse_call_chain\n" +
      "    expr = parse_primary()\n" +
      "    skip_spaces()\n" +
      "    cont = true\n" +
      "    while cont\n" +
      "      cont = false\n" +
      "      if at?(\\\"DOT\\\")\n" +
      "        advance()\n" +
      "        name_tok = expect_method_name()\n" +
      "        name = name_tok[\\\"value\\\"]\n" +
      "        result = parse_call_args_and_block(true, name_tok[:line], name_tok[\\\"col\\\"], name_tok[\\\"value\\\"])\n" +
      "        args = result[0]\n" +
      "        block = result[1]\n" +
      "        if args == nil\n" +
      "          args = []\n" +
      "        expr = ast_call(expr, name, args, block)\n" +
      "        expr[:line] = name_tok[:line]\n" +
      "        expr[\\\"col\\\"] = name_tok[\\\"col\\\"]\n" +
      "        cont = true\n" +
      "      if at?(\\\"SAFE_NAV\\\")\n" +
      "        advance()\n" +
      "        name_tok = expect_method_name()\n" +
      "        name = name_tok[\\\"value\\\"]\n" +
      "        result = parse_call_args_and_block(true, name_tok[:line], name_tok[\\\"col\\\"], name_tok[\\\"value\\\"])\n" +
      "        args = result[0]\n" +
      "        block = result[1]\n" +
      "        if args == nil\n" +
      "          args = []\n" +
      "        expr = ast_safe_nav(expr, name, args, block)\n" +
      "        expr[:line] = name_tok[:line]\n" +
      "        expr[\\\"col\\\"] = name_tok[\\\"col\\\"]\n" +
      "        cont = true\n" +
      "      if at?(\\\"LBRACKET\\\")\n" +
      "        if is_block_node?(expr)\n" +
      "          cont = false\n" +
      "        else\n" +
      "          lbr_tok = current()\n" +
      "          advance()\n" +
      "          index = parse_expression()\n" +
      "          expect(\\\"RBRACKET\\\")\n" +
      "          assigned = false\n" +
      "          if at?(\\\"ASSIGN\\\")\n" +
      "            advance()\n" +
      "            value = parse_assignment()\n" +
      "            expr = ast_call(expr, \\\"[]=\\\", [index, value])\n" +
      "            assigned = true\n" +
      "          if assigned == false\n" +
      "            expr = ast_call(expr, \\\"[]\\\", [index])\n" +
      "          expr[:line] = lbr_tok[:line]\n" +
      "          expr[\\\"col\\\"] = lbr_tok[\\\"col\\\"]\n" +
      "          cont = true\n" +
      "      skip_spaces()\n" +
      "    expr\n"

    parse_call_args = "  -> parse_call_args_and_block(allow_block_without_args, call_line, call_col, call_name)\n" +
      "    args = nil\n" +
      "    block = nil\n" +
      "    has_parens = false\n" +
      "    if at?(\\\"LPAREN\\\")\n" +
      "      has_parens = true\n" +
      "      advance()\n" +
      "      args = parse_arg_list(\\\"RPAREN\\\")\n" +
      "      expect(\\\"RPAREN\\\")\n" +
      "    if args != nil || has_parens || allow_block_without_args\n" +
      "      if at?(\\\"LBRACE\\\")\n" +
      "        block = parse_block()\n" +
      "      if block == nil && at?(\\\"ARROW\\\")\n" +
      "        block = parse_lambda()\n" +
      "    [args, block]\n"

    parse_arg_list = "  -> parse_arg_list(terminator)\n" +
      "    args = []\n" +
      "    skip_newlines()\n" +
      "    while true\n" +
      "      skip_spaces()\n" +
      "      skip_newlines()\n" +
      "      skip_spaces()\n" +
      "      if at?(terminator)\n" +
      "        return args\n" +
      "      if at?(\\\"AMPERSAND\\\")\n" +
      "        advance()\n" +
      "        name_tok = expect_identifier_name()\n" +
      "        args.push(ast_var(name_tok[\\\"value\\\"]))\n" +
      "      elsif at?(\\\"POW\\\")\n" +
      "        advance()\n" +
      "        args.push(parse_expression())\n" +
      "      elsif at?(\\\"STAR\\\")\n" +
      "        advance()\n" +
      "        if at?(\\\"STAR\\\")\n" +
      "          advance()\n" +
      "        args.push(parse_expression())\n" +
      "      elsif keyword_label_token?()\n" +
      "        entries = []\n" +
      "        while keyword_label_token?()\n" +
      "          key_tok = advance()\n" +
      "          advance()\n" +
      "          val = parse_expression()\n" +
      "          entries.push([ast_symbol(key_tok[\\\"value\\\"]), val])\n" +
      "          skip_spaces()\n" +
      "          if at?(\\\"COMMA\\\")\n" +
      "            advance()\n" +
      "            skip_spaces()\n" +
      "            skip_newlines()\n" +
      "          else\n" +
      "            kwh = ast_hash_literal(entries)\n" +
      "            kwh[:from_kwargs] = true\n" +
      "            args.push(kwh)\n" +
      "            if at?(\\\"COMMA\\\")\n" +
      "              advance()\n" +
      "              skip_spaces()\n" +
      "              skip_newlines()\n" +
      "            else\n" +
      "              return args\n" +
      "        kwh = ast_hash_literal(entries)\n" +
      "        kwh[:from_kwargs] = true\n" +
      "        args.push(kwh)\n" +
      "      else\n" +
      "        arg = parse_expression()\n" +
      "        skip_spaces()\n" +
      "        if at?(\\\"FAT_ARROW\\\")\n" +
      "          advance()\n" +
      "          val = parse_expression()\n" +
      "          arg = ast_hash_literal([[arg, val]])\n" +
      "        args.push(arg)\n" +
      "      skip_spaces()\n" +
      "      if at?(\\\"COMMA\\\")\n" +
      "        advance()\n" +
      "        skip_spaces()\n" +
      "        skip_newlines()\n" +
      "      else\n" +
      "        return args\n" +
      "    args\n"

    parse_if = "  -> parse_if\n" +
      "    expect(\\\"KEYWORD\\\", \\\"if\\\")\n" +
      "    condition = parse_expression()\n" +
      "    if at?(\\\"KEYWORD\\\", \\\"then\\\")\n" +
      "      advance()\n" +
      "      then_expr = parse_expression()\n" +
      "      else_body = nil\n" +
      "      if at?(\\\"KEYWORD\\\", \\\"else\\\")\n" +
      "        advance()\n" +
      "        else_body = [parse_expression()]\n" +
      "      return ast_if(condition, [then_expr], [], else_body)\n" +
      "    skip_newlines()\n" +
      "    skip_spaces()\n" +
      "    then_body = parse_body()\n" +
      "    skip_newlines()\n" +
      "    skip_spaces()\n" +
      "    if env(\\\"TUNGSTEN_STAGE0_IF_TRACE\\\") == \\\"1\\\"\n" +
      "      write_file(\\\"/tmp/tungsten-stage0-if-trace\\\", \\\"after_then:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "    elsif_clauses = []\n" +
      "    keep_elsif = true\n" +
      "    while keep_elsif\n" +
      "      skip_newlines()\n" +
      "      skip_spaces()\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_IF_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-if-trace\\\", \\\"elsif_check:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "      if at?(\\\"KEYWORD\\\", \\\"elsif\\\")\n" +
      "        if env(\\\"TUNGSTEN_STAGE0_IF_TRACE\\\") == \\\"1\\\"\n" +
      "          write_file(\\\"/tmp/tungsten-stage0-if-trace\\\", \\\"elsif_take:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "        advance()\n" +
      "        elsif_cond = parse_expression()\n" +
      "        skip_newlines()\n" +
      "        skip_spaces()\n" +
      "        elsif_body = parse_body()\n" +
      "        elsif_clauses.push([elsif_cond, elsif_body])\n" +
      "      else\n" +
      "        keep_elsif = false\n" +
      "    skip_newlines()\n" +
      "    skip_spaces()\n" +
      "    else_body = nil\n" +
      "    if at?(\\\"KEYWORD\\\", \\\"else\\\")\n" +
      "      advance()\n" +
      "      skip_newlines()\n" +
      "      skip_spaces()\n" +
      "      else_body = parse_body()\n" +
      "    ast_if(condition, then_body, elsif_clauses, else_body)\n"

    parse_range = "  -> parse_range\n" +
      "    left = parse_pipeline()\n" +
      "    skip_spaces()\n" +
      "    if at?(\\\"DOTDOT\\\")\n" +
      "      advance()\n" +
      "      right = nil\n" +
      "      stop = false\n" +
      "      if at?(\\\"RBRACKET\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"RPAREN\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"NEWLINE\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"EOF\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"COMMA\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"DEDENT\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"ARROW\\\")\n" +
      "        stop = true\n" +
      "      if stop == false\n" +
      "        right = parse_or()\n" +
      "      return ast_range(left, right, false)\n" +
      "    if at?(\\\"DOTDOTDOT\\\")\n" +
      "      advance()\n" +
      "      right = nil\n" +
      "      stop = false\n" +
      "      if at?(\\\"RBRACKET\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"RPAREN\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"NEWLINE\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"EOF\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"COMMA\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"DEDENT\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"ARROW\\\")\n" +
      "        stop = true\n" +
      "      if stop == false\n" +
      "        right = parse_or()\n" +
      "      return ast_range(left, right, true)\n" +
      "    left\n"

    parse_or = "  -> parse_or\n" +
      "    left = parse_and()\n" +
      "    skip_spaces()\n" +
      "    while at?(\\\"OR\\\")\n" +
      "      advance()\n" +
      "      skip_spaces()\n" +
      "      right = parse_and()\n" +
      "      left = ast_or(left, right)\n" +
      "      skip_spaces()\n" +
      "    left\n"

    parse_and = "  -> parse_and\n" +
      "    left = parse_in_test()\n" +
      "    skip_spaces()\n" +
      "    while at?(\\\"AND\\\")\n" +
      "      advance()\n" +
      "      skip_spaces()\n" +
      "      right = parse_in_test()\n" +
      "      left = ast_and(left, right)\n" +
      "      skip_spaces()\n" +
      "    left\n"

    parse_in_test = "  -> parse_in_test\n" +
      "    left = parse_bitwise_or()\n" +
      "    skip_spaces()\n" +
      "    if at?(\\\"KEYWORD\\\", \\\"in\\\")\n" +
      "      advance()\n" +
      "      skip_spaces()\n" +
      "      tok = current()\n" +
      "      if at?(\\\"LPAREN\\\")\n" +
      "        advance()\n" +
      "      else\n" +
      "        raise {rt: :compile_error, code: :E_PARSE_IN_EXPECTS_TUPLE, message: \\\"`in` requires a parenthesized tuple on the right-hand side\\\", file: tok[:file], row: tok[:line], col: tok[:col], span_length: 1}\n" +
      "      elements = []\n" +
      "      keep = true\n" +
      "      while keep\n" +
      "        skip_spaces()\n" +
      "        if at?(\\\"RPAREN\\\")\n" +
      "          advance()\n" +
      "          keep = false\n" +
      "        elsif at?(\\\"EOF\\\")\n" +
      "          keep = false\n" +
      "        else\n" +
      "          elements.push(parse_expression())\n" +
      "          skip_spaces()\n" +
      "      if elements.size() == 0\n" +
      "        raise {rt: :compile_error, code: :E_PARSE_IN_EMPTY_TUPLE, message: \\\"`in` tuple must have at least one element\\\", file: tok[:file], row: tok[:line], col: tok[:col], span_length: 1}\n" +
      "      return ast_in_test(left, elements)\n" +
      "    left\n"

    parse_begin = "  -> parse_begin\n" +
      "    expect(\\\"KEYWORD\\\", \\\"begin\\\")\n" +
      "    skip_newlines()\n" +
      "    skip_spaces()\n" +
      "    body = parse_body()\n" +
      "    skip_newlines()\n" +
      "    skip_spaces()\n" +
      "    rescue_var = nil\n" +
      "    rescue_body = nil\n" +
      "    if at?(\\\"KEYWORD\\\", \\\"rescue\\\")\n" +
      "      advance()\n" +
      "      skip_spaces()\n" +
      "      if at?(\\\"ID\\\")\n" +
      "        rescue_var = expect(\\\"ID\\\")[\\\"value\\\"]\n" +
      "        skip_spaces()\n" +
      "        if at?(\\\"COLON\\\")\n" +
      "          advance()\n" +
      "          skip_spaces()\n" +
      "          expect(\\\"NAME\\\")\n" +
      "      skip_newlines()\n" +
      "      skip_spaces()\n" +
      "      rescue_body = parse_body()\n" +
      "      skip_newlines()\n" +
      "      skip_spaces()\n" +
      "    ensure_body = nil\n" +
      "    if at?(\\\"KEYWORD\\\", \\\"ensure\\\")\n" +
      "      advance()\n" +
      "      skip_newlines()\n" +
      "      skip_spaces()\n" +
      "      ensure_body = parse_body()\n" +
      "    ast_begin(body, rescue_var, rescue_body, ensure_body)\n"

    parse_raise = "  -> parse_raise\n" +
      "    raise_tok = current()\n" +
      "    advance()\n" +
      "    skip_spaces()\n" +
      "    node = ast_raise(parse_expression())\n" +
      "    node[:line] = raise_tok[:line]\n" +
      "    node[\\\"col\\\"] = raise_tok[\\\"col\\\"]\n" +
      "    node\n"

    skip_structure_whitespace = "  -> skip_structure_whitespace\n" +
      "    keep = true\n" +
      "    while keep\n" +
      "      keep = false\n" +
      "      type_name = @current_type.to_s()\n" +
      "      if type_name == \\\"NEWLINE\\\"\n" +
      "        advance()\n" +
      "        keep = true\n" +
      "      if type_name == \\\"SEMICOLON\\\"\n" +
      "        advance()\n" +
      "        keep = true\n" +
      "      if type_name == \\\"INDENT\\\"\n" +
      "        advance()\n" +
      "        keep = true\n" +
      "      if type_name == \\\"DEDENT\\\"\n" +
      "        advance()\n" +
      "        keep = true\n" +
      "      if type_name == \\\"SP\\\"\n" +
      "        advance()\n" +
      "        keep = true\n"

    parse_hash_literal = "  -> parse_hash_literal\n" +
      "    expect(\\\"LBRACE\\\")\n" +
      "    skip_structure_whitespace()\n" +
      "    entries = []\n" +
      "    while true\n" +
      "      skip_structure_whitespace()\n" +
      "      if at?(\\\"RBRACE\\\")\n" +
      "        advance()\n" +
      "        return ast_hash_literal(entries)\n" +
      "      key_like = false\n" +
      "      if @current_type.to_s() == \\\"ID\\\"\n" +
      "        key_like = true\n" +
      "      if @current_type.to_s() == \\\"TYPE\\\"\n" +
      "        key_like = true\n" +
      "      if soft_identifier_keyword?(@current_token)\n" +
      "        key_like = true\n" +
      "      if key_like\n" +
      "        if peek()[\\\"type\\\"].to_s() == \\\"COLON\\\"\n" +
      "          key_tok = advance()\n" +
      "          advance()\n" +
      "          skip_spaces()\n" +
      "          shorthand = false\n" +
      "          if at?(\\\"COMMA\\\")\n" +
      "            shorthand = true\n" +
      "          if at?(\\\"RBRACE\\\")\n" +
      "            shorthand = true\n" +
      "          if at?(\\\"NEWLINE\\\")\n" +
      "            shorthand = true\n" +
      "          if at?(\\\"DEDENT\\\")\n" +
      "            shorthand = true\n" +
      "          if shorthand\n" +
      "            entries.push([ast_symbol(key_tok[\\\"value\\\"]), ast_var(key_tok[\\\"value\\\"])])\n" +
      "          else\n" +
      "            value = parse_expression()\n" +
      "            entries.push([ast_symbol(key_tok[\\\"value\\\"]), value])\n" +
      "        else\n" +
      "          key = parse_expression(false)\n" +
      "          skip_spaces()\n" +
      "          if at?(\\\"FAT_ARROW\\\")\n" +
      "            advance()\n" +
      "          else\n" +
      "            expect(\\\"COLON\\\")\n" +
      "          value = parse_expression()\n" +
      "          entries.push([key, value])\n" +
      "      else\n" +
      "        key = parse_expression(false)\n" +
      "        skip_spaces()\n" +
      "        if at?(\\\"FAT_ARROW\\\")\n" +
      "          advance()\n" +
      "        else\n" +
      "          expect(\\\"COLON\\\")\n" +
      "        value = parse_expression()\n" +
      "        entries.push([key, value])\n" +
      "      skip_structure_whitespace()\n" +
      "      if at?(\\\"COMMA\\\")\n" +
      "        advance()\n" +
      "        skip_structure_whitespace()\n" +
      "      else\n" +
      "        expect(\\\"RBRACE\\\")\n" +
      "        return ast_hash_literal(entries)\n" +
      "    ast_hash_literal(entries)\n"

    parse_expression = "  -> parse_expression(allow_passthrough = true)\n" +
      "    if env(\\\"TUNGSTEN_STAGE0_ARROW_TRACE\\\") == \\\"1\\\" && at?(\\\"ARROW\\\")\n" +
      "      write_file(\\\"/tmp/tungsten-stage0-arrow-expression\\\", @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "    if at?(\\\"KEYWORD\\\", \\\"trait\\\")\n" +
      "      return parse_trait_def()\n" +
      "    if at?(\\\"CLASS_DEF\\\")\n" +
      "      return parse_class_def()\n" +
      "    start_line = current()[:line]\n" +
      "    expr = parse_assignment()\n" +
      "    if is_block_node?(expr) == false\n" +
      "      if current()[:line] == start_line\n" +
      "        if at?(\\\"KEYWORD\\\", \\\"if\\\")\n" +
      "          advance()\n" +
      "          condition = parse_assignment()\n" +
      "          expr = ast_if(condition, [expr])\n" +
      "        if at?(\\\"KEYWORD\\\", \\\"unless\\\")\n" +
      "          advance()\n" +
      "          condition = parse_assignment()\n" +
      "          expr = ast_if(ast_not(condition), [expr])\n" +
      "        if at?(\\\"KEYWORD\\\", \\\"while\\\")\n" +
      "          advance()\n" +
      "          condition = parse_assignment()\n" +
      "          expr = ast_while(condition, [expr])\n" +
      "        if at?(\\\"KEYWORD\\\", \\\"rescue\\\")\n" +
      "          advance()\n" +
      "          fallback = parse_assignment()\n" +
      "          expr = ast_rescue_expr(expr, fallback)\n" +
      "    if allow_passthrough\n" +
      "      if current()[:line] == start_line\n" +
      "        if at?(\\\"COLON\\\")\n" +
      "          advance()\n" +
      "          passthrough = parse_assignment()\n" +
      "          expr = ast_passthrough(expr, passthrough)\n" +
      "    expr\n"

    parse_program = "  -> parse_program\n" +
      "    skip_newlines()\n" +
      "    exprs = []\n" +
      "    while true\n" +
      "      skip_newlines()\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_PROGRAM_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-program-trace\\\", \\\"loop:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "      if @current_type.to_s() == \\\"EOF\\\"\n" +
      "        return exprs\n" +
      "      if @current_type.to_s() == \\\"DEDENT\\\"\n" +
      "        return exprs\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_PROGRAM_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-program-trace\\\", \\\"before_expr:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "      expr = parse_expression()\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_PROGRAM_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-program-trace\\\", \\\"after_expr:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "      exprs.push(finish_statement_expression(expr))\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_PROGRAM_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-program-trace\\\", \\\"after_finish:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "    exprs\n"

    parse_body = "  -> parse_body\n" +
      "    if @current_type == \\\"INDENT\\\"\n" +
      "      advance()\n" +
      "    skip_newlines()\n" +
      "    skip_spaces()\n" +
      "    body_col = current()[\\\"col\\\"]\n" +
      "    exprs = []\n" +
      "    active = true\n" +
      "    while active\n" +
      "      skip_newlines()\n" +
      "      skip_spaces()\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_BODY_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-body-trace\\\", \\\"loop:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "      stop = false\n" +
      "      if @current_type.to_s() == \\\"EOF\\\"\n" +
      "        stop = true\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_BODY_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-body-trace\\\", \\\"after_eof_guard:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s())\n" +
      "      if @current_type.to_s() == \\\"DEDENT\\\"\n" +
      "        advance()\n" +
      "        stop = true\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_BODY_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-body-trace\\\", \\\"after_dedent_guard:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s())\n" +
      "      if env(\\\"TUNGSTEN_STAGE0_BODY_TRACE\\\") == \\\"1\\\"\n" +
      "        write_file(\\\"/tmp/tungsten-stage0-body-trace\\\", \\\"before_col_guard:\\\" + @pos.to_s() + \\\":\\\" + current()[\\\"col\\\"].to_s() + \\\":\\\" + body_col.to_s())\n" +
      "      current_col_text = current()[\\\"col\\\"].to_s()\n" +
      "      body_col_text = body_col.to_s()\n" +
      "      if current_col_text == body_col_text\n" +
      "        current_col_text = body_col_text\n" +
      "      else\n" +
      "        stop = true\n" +
      "      if stop\n" +
      "        active = false\n" +
      "      else\n" +
      "        if env(\\\"TUNGSTEN_STAGE0_BODY_TRACE\\\") == \\\"1\\\"\n" +
      "          write_file(\\\"/tmp/tungsten-stage0-body-trace\\\", \\\"before_expr:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "        expr = parse_expression()\n" +
      "        if env(\\\"TUNGSTEN_STAGE0_BODY_TRACE\\\") == \\\"1\\\"\n" +
      "          write_file(\\\"/tmp/tungsten-stage0-body-trace\\\", \\\"after_expr:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "        exprs.push(finish_statement_expression(expr))\n" +
      "        if env(\\\"TUNGSTEN_STAGE0_BODY_TRACE\\\") == \\\"1\\\"\n" +
      "          write_file(\\\"/tmp/tungsten-stage0-body-trace\\\", \\\"after_finish:\\\" + @pos.to_s() + \\\":\\\" + @current_type.to_s() + \\\":\\\" + @current_value.to_s())\n" +
      "    exprs\n"

    parse_fn_def = "  -> parse_fn_def\n" +
      "    fn_tok = expect(\\\"KEYWORD\\\", \\\"fn\\\")\n" +
      "    fn_line = fn_tok[\\\"line\\\"]\n" +
      "    name = expect(\\\"ID\\\")[\\\"value\\\"]\n" +
      "    params = []\n" +
      "    if at?(\\\"LPAREN\\\")\n" +
      "      advance()\n" +
      "      while !at?(\\\"RPAREN\\\")\n" +
      "        params.push(parse_method_param())\n" +
      "        match?(\\\"COMMA\\\")\n" +
      "        skip_spaces()\n" +
      "      expect(\\\"RPAREN\\\")\n" +
      "    skip_newlines()\n" +
      "    body = []\n" +
      "    if at?(\\\"INDENT\\\")\n" +
      "      body = parse_body()\n" +
      "    elsif at?(\\\"DEDENT\\\") || at?(\\\"EOF\\\") || at?(\\\"CLASS_DEF\\\") || at?(\\\"ARROW\\\")\n" +
      "      body = []\n" +
      "    else\n" +
      "      body = [parse_expression()]\n" +
      "    if @in_class_body\n" +
      "      return ast_method_def(name, params, body, nil, false)\n" +
      "    result = ast_fn_def(name, params, body, nil)\n" +
      "    ast_set(result, \\\"line\\\", fn_line)\n" +
      "    result\n"

    parse_int_value = "  -> parse_int_value(str)\n" +
      "    if str.size() >= 2\n" +
      "      prefix = str.slice(0, 2)\n" +
      "      if prefix in (\\\"0x\\\" \\\"0X\\\")\n" +
      "        return parse_hex_int(str)\n" +
      "      if prefix in (\\\"0b\\\" \\\"0B\\\")\n" +
      "        return parse_bin_int(str)\n" +
      "      if prefix in (\\\"0o\\\" \\\"0O\\\")\n" +
      "        return parse_oct_int(str)\n" +
      "    str.replace(\\\"_\\\", \\\"\\\").to_i()\n"

    parse_use = "  -> parse_use\n" +
      "    advance()\n" +
      "    path = \\\"\\\"\n" +
      "    active = true\n" +
      "    while active\n" +
      "      stop = false\n" +
      "      if at?(\\\"NEWLINE\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"EOF\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"DEDENT\\\")\n" +
      "        stop = true\n" +
      "      if at?(\\\"SEMICOLON\\\")\n" +
      "        stop = true\n" +
      "      if stop\n" +
      "        active = false\n" +
      "      else\n" +
      "        if at?(\\\"SP\\\")\n" +
      "          advance()\n" +
      "        else\n" +
      "          path = path + @current_value.to_s()\n" +
      "          advance()\n" +
      "    ast_use(path)\n"

    at_predicate = "  -> at?(type, value = nil)\n" +
      "    if @current_type.to_s() != type.to_s()\n" +
      "      return false\n" +
      "    if value == nil\n" +
      "      return true\n" +
      "    @current_value == value\n"

    expect = "  -> expect(type, value = nil)\n" +
      "    tok = @current_token\n" +
      "    bad = false\n" +
      "    if @current_type.to_s() != type.to_s()\n" +
      "      bad = true\n" +
      "    if value != nil\n" +
      "      if @current_value != value\n" +
      "        bad = true\n" +
      "    if bad\n" +
      "      raise {rt: :compile_error, code: :E_PARSE_EXPECTED_TOKEN, message: \\\"Expected token\\\", file: tok[:file], row: tok[:line], col: tok[:col], span_length: 1}\n" +
      "    advance()\n" +
      "    tok\n"

    skip_spaces = "  -> skip_spaces\n" +
      "    while at?(\\\"SP\\\")\n" +
      "      advance()\n"

    skip_newlines = "  -> skip_newlines\n" +
      "    keep = true\n" +
      "    while keep\n" +
      "      keep = false\n" +
      "      type_name = @current_type.to_s()\n" +
      "      if type_name == \\\"TYPE_HINT\\\"\n" +
      "        @pending_type_hints.push(@current_value)\n" +
      "        advance()\n" +
      "        keep = true\n" +
      "      if type_name == \\\"NEWLINE\\\"\n" +
      "        advance()\n" +
      "        keep = true\n"

    skip_statement_end = "  -> skip_statement_end\n" +
      "    keep = true\n" +
      "    while keep\n" +
      "      keep = false\n" +
      "      type_name = @current_type.to_s()\n" +
      "      if type_name == \\\"TYPE_HINT\\\"\n" +
      "        @pending_type_hints.push(@current_value)\n" +
      "        advance()\n" +
      "        keep = true\n" +
      "      if type_name == \\\"NEWLINE\\\"\n" +
      "        advance()\n" +
      "        keep = true\n" +
      "      if type_name == \\\"SEMICOLON\\\"\n" +
      "        advance()\n" +
      "        keep = true\n"

    source = stage0_replace_parser_method(source, "at?", at_predicate)
    source = stage0_replace_parser_method(source, "expect", expect)
    source = stage0_replace_parser_method(source, "skip_newlines", skip_newlines)
    source = stage0_replace_parser_method(source, "skip_spaces", skip_spaces)
    source = stage0_replace_parser_method(source, "skip_statement_end", skip_statement_end)
    source = stage0_replace_parser_method(source, "parse_call_chain", parse_call_chain)
    source = stage0_replace_parser_method(source, "parse_call_args_and_block", parse_call_args)
    source = stage0_replace_parser_method(source, "parse_arg_list", parse_arg_list)
    source = stage0_replace_parser_method(source, "parse_if", parse_if)
    source = stage0_replace_parser_method(source, "parse_range", parse_range)
    source = stage0_replace_parser_method(source, "parse_or", parse_or)
    source = stage0_replace_parser_method(source, "parse_and", parse_and)
    source = stage0_replace_parser_method(source, "parse_in_test", parse_in_test)
    source = stage0_replace_parser_method(source, "parse_begin", parse_begin)
    source = stage0_replace_parser_method(source, "parse_raise", parse_raise)
    source = stage0_replace_parser_method(source, "skip_structure_whitespace", skip_structure_whitespace)
    source = stage0_replace_parser_method(source, "parse_hash_literal", parse_hash_literal)
    source = stage0_replace_parser_method(source, "parse_program", parse_program)
    source = stage0_replace_parser_method(source, "parse_body", parse_body)
    source = stage0_replace_parser_method(source, "parse_fn_def", parse_fn_def)
    source = stage0_replace_parser_method(source, "parse_int_value", parse_int_value)
    source = stage0_replace_parser_method(source, "parse_use", parse_use)
    source = source.split("      return parse_var_or_call()\n").join(
      "      tok = advance()\n" \
      "      return ast_var(tok[\\\"value\\\"])\n"
    )
    source = self.stage0_prefix_parser_self_calls(source)
    source = source.split("at?(:*)").join("at?(\\\"STAR\\\")")
    source = source.split("@current_type.to_s()").join("@current_type")
    source = source.split("type.to_s()").join("type")
    source
  end

  def stage0_normalize_compiler_source(source)
    normalized = ""
    normalized = self.stage0_normalize_compiler_language_source(source)
    args_parts = normalized.split("args = argv()\\n")
    if args_parts.length > 1
      phase_parts = args_parts[1].split("-> phase_elapsed")
      if phase_parts.length > 1
        driver = ""
        driver = driver + "args = argv()\\n"
        driver = driver + "command        = \\"compile\\"\\n"
        driver = driver + "out_path       = nil\\n"
        driver = driver + "file_path      = \\"compiler/tungsten.w\\"\\n"
        driver = driver + "eval_code      = nil\\n"
        driver = driver + "emit_wire      = false\\n"
        driver = driver + "verbose        = false\\n"
        driver = driver + "show_ast       = false\\n"
        driver = driver + "show_lex       = false\\n"
        driver = driver + "no_lto         = false\\n"
        driver = driver + "frame_pointers = false\\n"
        driver = driver + "keep_ll        = false\\n"
        driver = driver + "emit_ll_only   = true\\n"
        driver = driver + "release_mode   = true\\n"
        driver = driver + "fast_mode      = false\\n"
        driver = driver + "intern_algo    = \\"raw\\"\\n"
        driver = driver + "runtime_archive = nil\\n\\n"
        tail = phase_parts[1]
        pi = 2
        while pi < phase_parts.length
          tail = tail + "-> phase_elapsed" + phase_parts[pi]
          pi += 1
        end
        normalized = args_parts[0] + driver + "-> phase_elapsed" + tail
      end
    end
    start_pos = normalized.index("-> compile(ast")
    end_pos = normalized.index("-> compile_to_wire")
    if start_pos >= 0 && end_pos >= 0
      compile_fn = ""
      compile_fn = compile_fn + "-> compile(ast, source_path, verbose = false, frame_pointers = false, sidemap_path = nil, release_mode = false, fast_mode = false)\\n"
      compile_fn = compile_fn + "  if env(\\"TUNGSTEN_STAGE0_COMPILE_TRACE\\") == \\"1\\"\\n"
      compile_fn = compile_fn + "    exprs = ast[\\"expressions\\"]\\n"
      compile_fn = compile_fn + "    trace = \\"ast_exprs=\\" + type(exprs).to_s() + \\":\\" + exprs.size().to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "    if exprs.size() > 0\\n"
      compile_fn = compile_fn + "      e0 = exprs[0]\\n"
      compile_fn = compile_fn + "      trace = trace + \\"e0=\\" + type(e0).to_s() + \\":\\" + e0[\\"node\\"].to_s() + \\"/\\" + e0[:node].to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "    node_trace = \\"\\"\\n"
      compile_fn = compile_fn + "    ni = 0\\n"
      compile_fn = compile_fn + "    while ni < exprs.size() && ni < 80\\n"
      compile_fn = compile_fn + "      node_trace = node_trace + ni.to_s() + \\":\\" + exprs[ni][\\"node\\"].to_s() + \\":line=\\" + exprs[ni][\\"line\\"].to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "      ni += 1\\n"
      compile_fn = compile_fn + "    fn_count = 0\\n"
      compile_fn = compile_fn + "    method_count = 0\\n"
      compile_fn = compile_fn + "    class_count = 0\\n"
      compile_fn = compile_fn + "    def_count = 0\\n"
      compile_fn = compile_fn + "    i = 0\\n"
      compile_fn = compile_fn + "    while i < exprs.size()\\n"
      compile_fn = compile_fn + "      nt = exprs[i][\\"node\\"]\\n"
      compile_fn = compile_fn + "      if nt == \\"fn_def\\"\\n"
      compile_fn = compile_fn + "        fn_count += 1\\n"
      compile_fn = compile_fn + "      if nt == \\"method_def\\"\\n"
      compile_fn = compile_fn + "        method_count += 1\\n"
      compile_fn = compile_fn + "      if nt == \\"class_def\\"\\n"
      compile_fn = compile_fn + "        class_count += 1\\n"
      compile_fn = compile_fn + "      if nt == \\"def\\"\\n"
      compile_fn = compile_fn + "        def_count += 1\\n"
      compile_fn = compile_fn + "      i += 1\\n"
      compile_fn = compile_fn + "    trace = trace + \\"ast_counts fn=\\" + fn_count.to_s() + \\" method=\\" + method_count.to_s() + \\" class=\\" + class_count.to_s() + \\" def=\\" + def_count.to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "    trace = trace + node_trace\\n"
      compile_fn = compile_fn + "    write_file(\\"/tmp/tungsten-stage0-ast-trace\\", trace)\\n"
      compile_fn = compile_fn + "  mod = lower_ast(ast, source_path, verbose, fast_mode)\\n"
      compile_fn = compile_fn + "  if env(\\"TUNGSTEN_STAGE0_COMPILE_TRACE\\") == \\"1\\"\\n"
      compile_fn = compile_fn + "    fns = mod[\\"functions\\"]\\n"
      compile_fn = compile_fn + "    trace = \\"functions=\\" + type(fns).to_s() + \\":\\" + fns.size().to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "    if fns.size() > 0\\n"
      compile_fn = compile_fn + "      f0 = fns[0]\\n"
      compile_fn = compile_fn + "      trace = trace + \\"f0=\\" + type(f0).to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "      trace = trace + \\"name=\\" + f0[\\"name\\"].to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "      trace = trace + \\"ret=\\" + f0[\\"return_type\\"].to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "      trace = trace + \\"blocks=\\" + f0[\\"blocks\\"].size().to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "      if f0[\\"blocks\\"].size() > 0\\n"
      compile_fn = compile_fn + "        trace = trace + \\"instrs=\\" + f0[\\"blocks\\"][0][\\"instructions\\"].size().to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "        if f0[\\"blocks\\"][0][\\"instructions\\"].size() > 0\\n"
      compile_fn = compile_fn + "          inst0 = f0[\\"blocks\\"][0][\\"instructions\\"][0]\\n"
      compile_fn = compile_fn + "          trace = trace + \\"inst0=\\" + inst0[\\"op\\"].to_s() + \\" value=\\" + inst0[\\"value\\"].to_s() + \\" name=\\" + inst0[\\"name\\"].to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "        if f0[\\"blocks\\"][0][\\"instructions\\"].size() > 1\\n"
      compile_fn = compile_fn + "          inst1 = f0[\\"blocks\\"][0][\\"instructions\\"][1]\\n"
      compile_fn = compile_fn + "          trace = trace + \\"inst1=\\" + inst1[\\"op\\"].to_s() + \\" value=\\" + inst1[\\"value\\"].to_s() + \\" name=\\" + inst1[\\"name\\"].to_s() + \\"\\\\n\\"\\n"
      compile_fn = compile_fn + "    write_file(\\"/tmp/tungsten-stage0-compile-trace\\", trace)\\n"
      compile_fn = compile_fn + "  content_hash_pass(mod, verbose)\\n"
      compile_fn = compile_fn + "  mod[:enhanced_stacktraces] = true\\n"
      compile_fn = compile_fn + "  if release_mode\\n"
      compile_fn = compile_fn + "    mod[:enhanced_stacktraces] = false\\n"
      compile_fn = compile_fn + "  llvm_target = detect_llvm_target()\\n"
      compile_fn = compile_fn + "  llvm_datalayout = llvm_target[\\"datalayout\\"]\\n"
      compile_fn = compile_fn + "  llvm_triple = llvm_target[\\"triple\\"]\\n"
      compile_fn = compile_fn + "  llvm_fn_attrs = llvm_target[\\"fn_attrs\\"]\\n"
      compile_fn = compile_fn + "  if llvm_datalayout == nil\\n"
      compile_fn = compile_fn + "    llvm_datalayout = \\"\\"\\n"
      compile_fn = compile_fn + "  if llvm_triple == nil\\n"
      compile_fn = compile_fn + "    llvm_triple = \\"\\"\\n"
      compile_fn = compile_fn + "  if llvm_fn_attrs == nil\\n"
      compile_fn = compile_fn + "    llvm_fn_attrs = \\"\\"\\n"
      compile_fn = compile_fn + "  stage0_hash_set(mod, \\"llvm_datalayout\\", llvm_datalayout)\\n"
      compile_fn = compile_fn + "  stage0_hash_set(mod, \\"llvm_triple\\", llvm_triple)\\n"
      compile_fn = compile_fn + "  stage0_hash_set(mod, \\"llvm_fn_attrs\\", llvm_fn_attrs)\\n"
      compile_fn = compile_fn + "  ir = emit_artifact(mod, frame_pointers)\\n"
      compile_fn = compile_fn + "  if sidemap_path != nil\\n"
      compile_fn = compile_fn + "    sidemap_text = mod[:symbol_sidemap_text]\\n"
      compile_fn = compile_fn + "    if sidemap_text != nil\\n"
      compile_fn = compile_fn + "      write_file(sidemap_path, sidemap_text)\\n"
      compile_fn = compile_fn + "  ir\\n\\n"
      normalized = normalized.slice(0, start_pos) + compile_fn + normalized.slice(end_pos, normalized.length - end_pos)
    end
    dispatch_parts = normalized.split("if eval_code != nil\\n")
    if dispatch_parts.length > 1
      normalized = dispatch_parts[0] +
                   "compile_one(file_path, out_path, emit_wire, verbose, intern_algo, emit_ll_only)\\n"
    end
    normalized = normalized.split("  loader = Loader.new(verbose)\\n  load_started_at = clock\\n  ast = loader.load_program_ast(file_path)\\n").join(
      "  load_started_at = clock\\n  ast = stage0_load_program_ast(file_path)\\n"
    )
    normalized = normalized.split(
      "  if env(\\\"TUNGSTEN_STOP_AFTER_LOAD_PARSE\\\") == \\\"1\\\"\\n" \
      "    if verbose\\n" \
      "      << \\\"\\\"\\n" \
      "      << fmt_elapsed(phase_elapsed(load_started_at)) + \\\" load+parse\\\"\\n" \
      "    exit 0\\n"
    ).join("")
    if normalized.include?("  kernels = collect_gpu_kernels(ast)\\n") && normalized.include?("-> runtime_event_source")
      guard_start = normalized.index("  if emit_ll_only_arg\\n    write_file(ll_path + \\\".done\\\", \\\"done\\\")\\n")
      runtime_start = normalized.index("-> runtime_event_source")
      if guard_start >= 0 && runtime_start > guard_start
        emit_done = "  write_file(ll_path + \\\".done\\\", \\\"done\\\")\\n" \
                    "  return ll_path\\n"
        normalized = normalized.slice(0, guard_start) + emit_done + normalized.slice(runtime_start, normalized.length - runtime_start)
      end
    end
    "" + normalized.to_s
  end

  def stage0_normalize_emitter_source(source)
    normalized = self.stage0_normalize_source(source)
    # The `<var> << <expr>` -> `<var> = <var> + <expr>` append rewrite (for
    # out, parts, result, fn_out, globals_out) is already performed inside
    # stage0_normalize_source above with the identical receiver list, so the
    # gsub-with-block that used to live here was pure duplication. It also
    # silently no-ops under spinel (the block never fires — see the note in
    # stage0_normalize_source), and the C spinel rejects
    # gsub(Regexp.new(...)) { block } outright. Dropped.
    start_pos = normalized.index("-> build_string_wvalues")
    end_pos = normalized.index("-> emit_string_constants")
    if start_pos >= 0 && end_pos >= 0
      normalized = normalized.slice(0, start_pos) +
                   "-> build_string_wvalues(strings)\\n  result = {}\\n  result[:wvalues] = {}\\n  result[:slab_entries] = []\\n  result[:total_slots] = 1\\n  result\\n" +
                   normalized.slice(end_pos, normalized.length - end_pos)
    end
    string_consts_start = normalized.index("-> emit_string_constants")
    string_consts_end = normalized.index("-> declare_runtime")
    if string_consts_start >= 0 && string_consts_end > string_consts_start
      normalized = normalized.slice(0, string_consts_start) +
                   "-> emit_string_constants(strings, slab_info, used_ptr_ids)\\n  \\"\\"\\n" +
                   normalized.slice(string_consts_end, normalized.length - string_consts_end)
    end
    normalized = normalized.split("  out.to_s()\\n-> declare_fn").join("  out\\n-> declare_fn")
    normalized = normalized.split("  attr_id = function_attr_group_id(attr_groups, attr_text)\\n  out = out + \\"define \\"\\n").join(
      "  attr_id = function_attr_group_id(attr_groups, attr_text)\\n" \
      "  if env(\\"TUNGSTEN_STAGE0_EMIT_FUNCTION_TRACE\\") == \\"1\\"\\n" \
      "    write_file(\\"/tmp/tungsten-stage0-emit-function-after-attr\\", out.to_s())\\n" \
      "  out = out + \\"define \\"\\n" \
      "  if env(\\"TUNGSTEN_STAGE0_EMIT_FUNCTION_TRACE\\") == \\"1\\"\\n" \
      "    write_file(\\"/tmp/tungsten-stage0-emit-function-after-define\\", out.to_s())\\n"
    )
    normalized = normalized.split("  out.to_s()\\n-> emit_param_signature").join(
      "  if env(\\"TUNGSTEN_STAGE0_EMIT_FUNCTION_TRACE\\") == \\"1\\"\\n" \
      "    write_file(\\"/tmp/tungsten-stage0-emit-function-len\\", out.to_s().size().to_s())\\n" \
      "    write_file(\\"/tmp/tungsten-stage0-emit-function-text\\", out.to_s())\\n" \
      "  out.to_s()\\n-> emit_param_signature"
    )
    declare_fn_start = normalized.index("-> declare_fn(name")
    declare_fn_end = normalized.index("-> join_arg_types2")
    if declare_fn_start >= 0 && declare_fn_end > declare_fn_start
      declare_helpers = ""
      declare_helpers = declare_helpers + "-> declare_fn(name, ret_type, arg_types_str)\\n  declare_fn_attrs(name, ret_type, arg_types_str, \\"nounwind\\")\\n"
      declare_helpers = declare_helpers + "-> declare_fn_noreturn(name, ret_type, arg_types_str)\\n  declare_fn_attrs(name, ret_type, arg_types_str, \\"noreturn cold nounwind\\")\\n"
      declare_helpers = declare_helpers + "-> declare_fn_attrs(name, ret_type, arg_types_str, attrs)\\n  \\"declare \\" + ret_type + \\" @\\" + name + \\"(\\" + arg_types_str + \\") \\" + attrs + \\"\\\\n\\"\\n"
      normalized = normalized.slice(0, declare_fn_start) + declare_helpers + normalized.slice(declare_fn_end, normalized.length - declare_fn_end)
    end
    join_start = normalized.index("-> join_arg_types2")
    join_end = normalized.index("-> runtime_decl_name")
    if join_start >= 0 && join_end > join_start
      join_helpers = ""
      join_helpers = join_helpers + "-> join_arg_types2(lhs, rhs)\\n  lhs + \\", \\" + rhs\\n"
      join_helpers = join_helpers + "-> join_arg_types3(a, b, c)\\n  a + \\", \\" + b + \\", \\" + c\\n"
      join_helpers = join_helpers + "-> join_arg_types4(a, b, c, d)\\n  a + \\", \\" + b + \\", \\" + c + \\", \\" + d\\n"
      join_helpers = join_helpers + "-> join_arg_types5(a, b, c, d, e)\\n  a + \\", \\" + b + \\", \\" + c + \\", \\" + d + \\", \\" + e\\n"
      normalized = normalized.slice(0, join_start) + join_helpers + normalized.slice(join_end, normalized.length - join_end)
    end
    filter_start = normalized.index("-> filter_runtime_decls")
    filter_end = normalized.index("-> function_attr_text")
    if filter_start >= 0 && filter_end > filter_start
      normalized = normalized.slice(0, filter_start) +
                   "-> filter_runtime_decls(decls, used_fns)\\n  decls\\n" +
                   normalized.slice(filter_end, normalized.length - filter_end)
    end
    attr_text_start = normalized.index("-> function_attr_text")
    attr_text_end = normalized.index("-> function_attr_group_id")
    if attr_text_start >= 0 && attr_text_end > attr_text_start
      normalized = normalized.slice(0, attr_text_start) +
                   "-> function_attr_text(frame_pointers, host_fn_attrs)\\n  \\"nounwind\\"\\n" +
                   normalized.slice(attr_text_end, normalized.length - attr_text_end)
    end
    attr_groups_start = normalized.index("-> emit_function_attr_groups")
    attr_groups_end = normalized.index("-> call_prefix")
    if attr_groups_start >= 0 && attr_groups_end > attr_groups_start
      normalized = normalized.slice(0, attr_groups_start) +
                   "-> emit_function_attr_groups(attr_groups)\\n  \\"\\"\\n" +
                   normalized.slice(attr_groups_end, normalized.length - attr_groups_end)
    end
    redirect_map_start = normalized.index("-> build_phi_label_redirects")
    redirect_map_end = normalized.index("-> emit_function(f", redirect_map_start)
    if redirect_map_start >= 0 && redirect_map_end > redirect_map_start
      redirect_helpers = ""
      redirect_helpers = redirect_helpers + "-> build_phi_label_redirects(f)\\n  nil\\n"
      redirect_helpers = redirect_helpers + "-> redirect_phi_label(label, redirect)\\n  label\\n\\n"
      normalized = normalized.slice(0, redirect_map_start) + redirect_helpers + normalized.slice(redirect_map_end, normalized.length - redirect_map_end)
    end
    normalized = normalized.split("  triple = mod[:llvm_triple]\\n").join(
      "  triple = mod[:llvm_triple]\\n" +
      "  if datalayout == nil\\n" +
      "    datalayout = \\\"\\\"\\n" +
      "  if triple == nil\\n" +
      "    triple = \\\"\\\"\\n"
    )
    small_array_start = normalized.index("  sa_consts = mod[:small_array_consts]")
    small_array_end = normalized.index("  rsites = mod[:reuse_sites]")
    if small_array_start >= 0 && small_array_end > small_array_start
      normalized = normalized.slice(0, small_array_start) +
                   "  sa_consts = []\\n" +
                   normalized.slice(small_array_end, normalized.length - small_array_end)
    end
    reuse_start = normalized.index("  rsites = mod[:reuse_sites]")
    reuse_end = normalized.index("  used_ptr_ids = {}")
    if reuse_start >= 0 && reuse_end > reuse_start
      normalized = normalized.slice(0, reuse_start) +
                   normalized.slice(reuse_end, normalized.length - reuse_end)
    end
    artifact_join = ""
    artifact_join = artifact_join + "  artifact = header\\n"
    artifact_join = artifact_join + "  artifact = artifact + decls_out\\n"
    artifact_join = artifact_join + "  artifact = artifact + globals_out\\n"
    artifact_join = artifact_join + "  artifact = artifact + strings_out\\n"
    artifact_join = artifact_join + "  artifact = artifact + fn_out\\n"
    artifact_join = artifact_join + "  artifact = artifact + fn_meta_out\\n"
    artifact_join = artifact_join + "  artifact = artifact + call_site_out\\n"
    artifact_join = artifact_join + "  artifact = artifact + llvm_used_out\\n"
    artifact_join = artifact_join + "  artifact = artifact + attr_groups_out\\n"
    artifact_join = artifact_join + "  artifact"
    normalized = normalized.split("  header + decls_out + globals_out.to_s() + strings_out + fn_out.to_s() + fn_meta_out + call_site_out + llvm_used_out + attr_groups_out").join(artifact_join)
    normalized = normalized.split("  header + decls_out + globals_out + strings_out + fn_out + fn_meta_out + call_site_out + llvm_used_out + attr_groups_out").join(artifact_join)
    normalized = normalized.split("  op = inst[\\"op\\"]\\n  case op\\n").join(
      "  op = inst[\\"op\\"]\\n" \
      "  op_text = op.to_s()\\n" \
      "  if op_text == \\"ret_i32\\"\\n" \
      "    return \\"ret i32 \\" + inst[\\"value\\"]\\n" \
      "  if op_text == \\"ret_i64\\"\\n" \
      "    return \\"ret i64 \\" + inst[\\"value\\"]\\n" \
      "  if op_text == \\"ret_void\\"\\n" \
      "    return \\"ret void\\"\\n" \
      "  if op_text == \\"call_direct_void\\"\\n" \
      "    args = inst[\\"args\\"]\\n" \
      "    if args == nil || args.size() == 0\\n" \
      "      return \\"call void @\\" + inst[\\"name\\"] + \\"()\\"\\n" \
      "  case op\\n"
    )
    normalized = normalized.split("  attr_groups_out = emit_function_attr_groups(attr_groups)\\n  artifact = header\\n").join(
      "  attr_groups_out = emit_function_attr_groups(attr_groups)\\n" +
      "  if env(\\\"TUNGSTEN_STAGE0_EMITTER_TRACE\\\") == \\\"1\\\"\\n" +
      "    trace = \\\"globals=\\\" + type(globals_out).to_s() + \\\":\\\" + globals_out.to_s().size().to_s() + \\\"\\\\n\\\"\\n" +
      "    trace = trace + \\\"strings=\\\" + type(strings_out).to_s() + \\\":\\\" + strings_out.to_s().size().to_s() + \\\"\\\\n\\\"\\n" +
      "    trace = trace + \\\"fn=\\\" + type(fn_out).to_s() + \\\":\\\" + fn_out.to_s().size().to_s() + \\\"\\\\n\\\"\\n" +
      "    trace = trace + \\\"fn_meta=\\\" + type(fn_meta_out).to_s() + \\\":\\\" + fn_meta_out.to_s().size().to_s() + \\\"\\\\n\\\"\\n" +
      "    trace = trace + \\\"call_site=\\\" + type(call_site_out).to_s() + \\\":\\\" + call_site_out.to_s().size().to_s() + \\\"\\\\n\\\"\\n" +
      "    trace = trace + \\\"llvm_used=\\\" + type(llvm_used_out).to_s() + \\\":\\\" + llvm_used_out.to_s().size().to_s() + \\\"\\\\n\\\"\\n" +
      "    trace = trace + \\\"attrs=\\\" + type(attr_groups_out).to_s() + \\\":\\\" + attr_groups_out.to_s().size().to_s() + \\\"\\\\n\\\"\\n" +
      "    write_file(\\\"/tmp/tungsten-stage0-emitter-components\\\", trace)\\n" +
      "  artifact = header\\n"
    )
    meta_start = normalized.index("-> collect_call_sites")
    meta_end = normalized.index("-> emit_artifact")
    if meta_start >= 0 && meta_end > meta_start
      meta_stubs = ""
      meta_stubs = meta_stubs + "-> collect_call_sites(mod)\\n  {sites: [], files: {}}\\n"
      meta_stubs = meta_stubs + "-> emit_call_site_table(mod)\\n  \\"\\"\\n"
      meta_stubs = meta_stubs + "-> emit_fn_meta_table(mod)\\n  \\"\\"\\n"
      meta_stubs = meta_stubs + "-> emit_stacktrace_llvm_used()\\n  \\"\\"\\n"
      meta_stubs = meta_stubs + "-> address_taken_function_for_inst(inst)\\n  nil\\n"
      meta_stubs = meta_stubs + "-> collect_address_taken_functions(mod)\\n  {}\\n"
      meta_stubs = meta_stubs + "-> internal_fastcc_candidate?(func, address_taken)\\n  false\\n"
      meta_stubs = meta_stubs + "-> fastcc_direct_call_op?(op)\\n  false\\n"
      meta_stubs = meta_stubs + "-> apply_fastcc_plan(mod)\\n  mod[:fastcc_count] = 0\\n  nil\\n"
      normalized = normalized.slice(0, meta_start) + meta_stubs + normalized.slice(meta_end, normalized.length - meta_end)
    end
    lines = normalized.split("\\n")
    rewritten = ""
    li = 0
    while li < lines.length
      line = lines[li]
      pos = 0
      while pos < line.length && line.slice(pos, 1) == " "
        pos += 1
      end
      indent = line.slice(0, pos)
      rest = line.slice(pos, line.length - pos)
      marker = rest.index(" << ")
      if marker != nil && marker >= 0
        lhs = rest.slice(0, marker)
        rhs = rest.slice(marker + 4, rest.length - marker - 4)
        space_pos = lhs.index(" ")
        dot_pos = lhs.index(".")
        bracket_pos = lhs.index("[")
        if lhs != "" && (space_pos == nil || space_pos < 0) && (dot_pos == nil || dot_pos < 0) && (bracket_pos == nil || bracket_pos < 0)
          rewritten = rewritten + indent + lhs + " = stage0_str_append(" + lhs + ", " + rhs + ")\\n"
        else
          rewritten = rewritten + line + "\\n"
        end
      else
        rewritten = rewritten + line + "\\n"
      end
      li += 1
    end
    normalized = rewritten
    normalized = normalized.split("out = stage0_str_append(out, \\"define \\")").join("out = stage0_str_append(out, \\"define i32 @\\")")
    normalized = normalized.split("out = stage0_str_append(out, ret_ty)").join("out = out")
    normalized = normalized.split("out = stage0_str_append(out, \\" @\\")").join("out = out")
    normalized
  end

  def stage0_rewrite_named_new(line, class_name, helper_name)
    needle = class_name + ".new("
    parts = line.split(needle)
    if parts.length > 1
      return parts[0] + helper_name + "(" + parts[1]
    end
    line
  end

  def stage0_eval_args(arg_nodes)
    args = []
    i = 0
    while i < arg_nodes.length
      args.push(evaluate(arg_nodes[i]))
      i += 1
    end
    args
  end

  def stage0_aref(value, index)
    if value.is_a?(Hash)
      hash_value = value[index]
      return hash_value if hash_value != nil
      return value[index.to_s]
    end
    value[index]
  end

  def stage0_value_length(value)
    value.length
  end

  def stage0_call_def_from_nodes(fn, call_name, arg_nodes)
    # Evaluate arg expressions in the caller's @env, then bind into
    # the callee's fresh env. The old code allocated an intermediate
    # arg_values poly_array per call (and looped twice); skip that —
    # Ruby semantics let us evaluate each arg in the old env and
    # set into the new env directly. ~50% fewer per-call allocations
    # in the dominant hot path of compiler/lib/lowering.w.
    # Diagnostic: trace dispatch for compile/emit_ir/load_program_ast +
    # lower_X dispatchers + intermediate compile() passes + lower_ast
    # setup helpers (the hang is in compile()'s scaffolding — bug is
    # input-independent, fires even on a 1-line `puts "hello"`)
    if call_name == "compile" || call_name == "emit_ir" || call_name == "stage0_load_program_ast" || call_name == "compile_one" || call_name == "load_program_ast" || call_name == "write_file" || call_name == "lower_program" || call_name == "lower_statement" || call_name == "lower_method_def" || call_name == "lower_class_def" || call_name == "lower_fn_def" || call_name == "emit_artifact" || call_name == "lower_ast" || call_name == "analyze_function" || call_name == "ssa_convert" || call_name == "prune_empty_blocks" || call_name == "ownership_pass" || call_name == "escape_pass" || call_name == "free_insertion_pass" || call_name == "content_hash_pass" || call_name == "detect_llvm_target" || call_name == "wire_module" || call_name == "register_ast_constructor_return_types" || call_name == "collect_top_level_static_types" || call_name == "collect_ivar_types" || call_name == "mark_builtin_runtime_class_uses" || call_name == "mark_nonescaping_small_arrays" || call_name == "register_class_method" || call_name == "builtin_runtime_classes" || call_name == "lower_expression" || call_name == "lower_if" || call_name == "lower_while" || call_name == "lower_call"
      File.write("/tmp/stage0-trace-CALL-" + call_name, "n=" + arg_nodes.length.to_s)
    end
    old_env = @env
    old_returning = @returning
    old_return_value = @return_value
    if @env_pool_enabled == 1 && @env_pool_count > 0
      new_env = @env_pool
      @env_pool = new_env.pool_next
      @env_pool_count -= 1
      new_env.pool_reset(old_env)
    else
      new_env = Environment.new(old_env)
    end
    stage0_mark_env(new_env)
    param_names = fn.stage0_param_names
    arg_count = arg_nodes.length
    param_count = param_names.length
    i = 0
    while i < arg_count
      arg_node = arg_nodes[i]
      if i < param_count
        new_env.bind_new_slot(param_names[i], evaluate(arg_node))
      else
        evaluate(arg_node)
      end
      i += 1
    end
    @env = new_env
    @returning = false
    @return_value = nil

    old_current_function = @stage0_current_function
    @stage0_current_function = call_name
    if @stage0_stack_trace_enabled == 1
      if @stage0_call_stack == nil
        @stage0_call_stack = []
      end
      @stage0_call_stack.push(call_name.to_s)
      File.write("/tmp/tungsten-stage0-call-stack", @stage0_call_stack.join(">"))
    end
    result = evaluate(fn.body)
    if @stage0_stack_trace_enabled == 1 && @stage0_call_stack != nil
      @stage0_call_stack.pop
    end
    @stage0_current_function = old_current_function
    if @returning
      result = @return_value
    end
    # Diagnostic: log return type for key dispatched defs
    if call_name == "compile" || call_name == "emit_ir" || call_name == "compile_one"
      File.write("/tmp/stage0-trace-RET-" + call_name, "type=" + result.class.to_s + " nil?=" + (result == nil).to_s + " len=" + (result.respond_to?(:length) ? result.length.to_s : "n/a"))
    end

    @env = old_env
    @returning = old_returning
    @return_value = old_return_value
    if @env_pool_enabled == 1
      new_env.pool_link(@env_pool)
      @env_pool = new_env
      @env_pool_count += 1
    end
    result
  end

  def stage0_primitive_call(recv, name_sym, arg_nodes)
    # Lazy arg evaluation: skip the per-call `args = []` poly_array
    # allocation (and the inline-cap-16 sp_RbVal buffer it triggers)
    # for branches that need only args[0] / args[1] / no args. The
    # original code eagerly allocated a fresh array every primitive
    # call; in compiler/lib/lowering.w that's millions of allocs/sec.
    # Branches that use args[0]/args[1] now call evaluate(arg_nodes[0])
    # / evaluate(arg_nodes[1]) directly. Order branches hottest-first
    # so the common cases match before the strcmp chain reaches the
    # rare ones.
    if name_sym == :"[]"
      # Hoist the index eval into a local. Spinel's []-on-poly emits a
      # per-cls_id dispatch table that re-evaluates the index expression
      # ONCE PER BRANCH (~10 cls_id branches), each hitting a fresh
      # poly_to_s/poly_to_i — burning millions of evaluate+alloc/free
      # per second on the lowering hot path.
      idx_v = evaluate(arg_nodes[0])
      if recv.is_a?(Hash)
        hash_value = recv[idx_v]
        return hash_value if hash_value != nil
        hash_value = recv[idx_v.to_sym]
        return hash_value if hash_value != nil
        return recv[idx_v.to_s]
      end
      return recv[idx_v]
    end
    if name_sym == :size || name_sym == :length
      if recv.is_a?(List)
        return recv.length
      end
      if recv.is_a?(Array)
        return recv.length
      end
      if recv.is_a?(Hash)
        return recv.length
      end
      return recv.to_s.length
    end
    if name_sym == :to_s
      return recv.to_s
    end
    if name_sym == :nil?
      return recv == nil
    end
    if name_sym == :empty?
      if recv.is_a?(List)
        return recv.empty?
      end
      return recv.to_s.empty?
    end
    if name_sym == :push
      recv.push(evaluate(arg_nodes[0]))
      return recv
    end
    if name_sym == :"[]="
      key_v = evaluate(arg_nodes[0])
      val_v = evaluate(arg_nodes[1])
      if recv.is_a?(Hash)
        recv[key_v] = val_v
        recv[key_v.to_s] = val_v
        return val_v
      end
      recv[key_v] = val_v
      return val_v
    end
    if name_sym == :"<<"
      v = evaluate(arg_nodes[0])
      if recv.is_a?(String)
        # recv is poly here (spinel doesn't narrow is_a?(String)); spinel
        # strings are immutable const char* so in-place << is already a
        # new-string concat — string-coerce recv and return the result.
        return ("" + recv.to_s) + v.to_s
      end
      recv << v
      return recv
    end
      if name_sym == :include?
        value = evaluate(arg_nodes[0])
        if recv.is_a?(Set)
          return recv.include?(value.to_s)
        end
        if recv.is_a?(List)
          i = 0
          while i < recv.length
            return true if recv[i] == value
            i += 1
          end
          return false
        end
        return recv.include?(value)
      end
    if name_sym == :has_key? || name_sym == :key?
      return recv.key?(evaluate(arg_nodes[0]))
    end
    if name_sym == :start_with? || name_sym == :starts_with?
      return recv.to_s.start_with?(evaluate(arg_nodes[0]).to_s)
    end
    if name_sym == :end_with? || name_sym == :ends_with?
      return recv.to_s.end_with?(evaluate(arg_nodes[0]).to_s)
    end
    if name_sym == :split
      return recv.to_s.split(evaluate(arg_nodes[0]).to_s)
    end
    if name_sym == :join
      sep = ""
      if arg_nodes.length > 0
        sep = evaluate(arg_nodes[0]).to_s
      end
      out = ""
      i = 0
      while i < recv.length
        if i > 0
          out = out + sep
        end
        out = out + recv[i].to_s
        i += 1
      end
      return out
    end
    if name_sym == :replace
      a = evaluate(arg_nodes[0]).to_s
      b = evaluate(arg_nodes[1]).to_s
      return recv.to_s.gsub(a, b)
    end
    if name_sym == :strip
      return recv.to_s.strip
    end
    if name_sym == :to_i
      text = recv.to_s
      return text.to_i
    end
    if name_sym == :ord
      return recv.to_s.ord
    end
    if name_sym == :keys
      return []
    end
    if name_sym == :sort
      return recv
    end
    if name_sym == :first
      return nil
    end
    if name_sym == :last
      return nil
    end
    nil
  end

  def stage0_program_resolve_path(path, from_file = nil)
    base = ""
    if path.byteslice(0, 1) == "/"
      candidate = path
      if !candidate.end_with?(".w")
        candidate = candidate + ".w"
      end
      return candidate if File.exist?(candidate)
    end

    if from_file != nil
      # Use a FRESH String local: the `from_file = nil` default types the param
      # TY_UNKNOWN (and the C compiler is flow-insensitive, so reassigning
      # from_file doesn't re-type it), making from_file.byteslice(...) TY_UNKNOWN
      # and `== "/"` hit "unsupported equality". `ff` is only ever assigned a
      # String ("" + ...), so it types TY_STRING and byteslice/== resolve.
      ff = "" + from_file.to_s
      last_slash = -1
      i = 0
      while i < ff.length
        if ff.byteslice(i, 1) == "/"
          last_slash = i
        end
        i += 1
      end
      if last_slash > 0
        base = ff.byteslice(0, last_slash)
        candidate = base + "/" + path
        if !candidate.end_with?(".w")
          candidate = candidate + ".w"
        end
        return candidate if File.exist?(candidate)
      end
    end

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

  def stage0_hash_get_any(hash, string_key, symbol_key)
    value = hash[string_key]
    return value if value != nil
    hash[symbol_key]
  end

  def stage0_ast_hash(kind)
    # Include one nil field so spinel infers a string-keyed poly hash.
    # A string-only hash becomes SymStrHash, and later poly-valued fields
    # such as params/body are silently skipped by the generated []= path.
    {"node" => kind, "line" => nil}
  end

  def stage0_ast_hash_set(hash, key, value)
    hash[key.to_s] = value
    value
  end

  def stage0_ast_hash_set_node(hash, key, value)
    stage0_ast_hash_set(hash, key, stage0_ruby_ast_to_compiler_value(value))
  end

  def stage0_ruby_ast_list_to_array(list_node)
    out = []
    return out if list_node == nil

    items = list_node.list
    return out if items == nil

    i = 0
    while i < items.length
      out.push(stage0_ruby_ast_to_compiler_value(items[i]))
      i += 1
    end
    out
  end

  def stage0_ruby_ast_array_to_array(array)
    out = []
    return out if array == nil

    i = 0
    while i < array.length
      out.push(stage0_ruby_ast_to_compiler_value(array[i]))
      i += 1
    end
    out
  end

  def stage0_ruby_ast_pair_array_to_array(array)
    out = []
    return out if array == nil

    i = 0
    while i < array.length
      pair = array[i]
      out.push([stage0_ruby_ast_to_compiler_value(pair[0]), stage0_ruby_ast_to_compiler_value(pair[1])])
      i += 1
    end
    out
  end

  def stage0_ruby_ast_node_kind(node)
    doc = node.doc
    return "list" if doc == 1
    return "print" if doc == 2
    return "int" if doc == 3
    return "string" if doc == 4
    return "bool" if doc == 5
    return "nil_lit" if doc == 6
    return "binary_op" if doc == 7
    return "assign" if doc == 8
    return "var" if doc == 9
    return "if" if doc == 10
    return "while" if doc == 11
    return "method_def" if doc == 12
    return "call" if doc == 13
    return "return" if doc == 14
    return "compound_assign" if doc == 15
    return "symbol" if doc == 16
    return "array" if doc == 17
    return "hash_literal" if doc == 18
    return "and" if doc == 19
    return "or" if doc == 20
    return "in_test" if doc == 21
    return "case" if doc == 22
    return "use" if doc == 23
    return "class_def" if doc == 24
    return "module_def" if doc == 25
    return "trait_def" if doc == 26
    return "ivar" if doc == 27
    return "cvar" if doc == 28
    return "global" if doc == 29
    return "self_ref" if doc == 30
    return "float" if doc == 31
    return "decimal" if doc == 32
    return "wvalue" if doc == 33
    return "begin" if doc == 34
    return "raise" if doc == 35
    return "puts" if doc == 36
    return "fn_def" if doc == 37
    return "block" if doc == 38
    return "param" if doc == 39
    return "not" if doc == 40
    return "byte_array" if doc == 41
    return "string_interp" if doc == 42
    return "regex" if doc == 43
    return "range" if doc == 44
    return "typed_array" if doc == 45
    return "target_designator" if doc == 46
    return "target_and" if doc == 47
    return "target_or" if doc == 48
    return "target_not" if doc == 49
    "unknown"
  end

  def stage0_static_hash_key?(node)
    doc = node.doc
    doc == 16 || doc == 4
  end

  def stage0_static_hash_key(node)
    node.value.to_s
  end

  def stage0_var_name(node)
    node.name
  end

  def stage0_mark_env(env)
    @stage0_next_layout_shape += 1
    env.mark_layout_shape(@stage0_next_layout_shape)
  end

  def stage0_env_get(env, name)
    env.get(name)
  end

  def stage0_env_local_slot_index(env, name)
    env.slot_index(name)
  end

  def stage0_env_get_slot(env, index)
    env.get_slot(index)
  end

  def stage0_poly_poly_hash_get_str(table, key)
    table[key]
  end

  def stage0_call_name(node)
    node.name
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

  def stage0_ruby_ast_field_name(kind, name)
    name_s = name.to_s
    return "receiver" if name_s == "obj"
    return "op" if name_s == "operator"
    return "operand" if kind == "unary_op" && name_s == "right"
    return "target" if kind == "assign" && name_s == "name"
    return "target" if kind == "compound_assign" && name_s == "name"
    return "params" if (kind == "method_def" || kind == "fn_def" || kind == "block") && name_s == "args"
    return "then_body" if name_s == "then_block"
    return "else_body" if name_s == "else_block" || name_s == "else"
    return "subject" if name_s == "receiver" && kind == "case_value"
    name_s
  end

  def stage0_ruby_ast_known_node?(value)
    true
  end

  def stage0_ruby_ast_to_compiler_value(value)
    return nil if value == nil
    if value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Float) || value == true || value == false
      return value
    end
    if value.is_a?(Symbol)
      return value.to_s
    end

    doc = value.doc
    if ENV["TUNGSTEN_STAGE0_CONVERT_TRACE"] == "1"
      if @stage0_convert_trace_count == nil
        @stage0_convert_trace_count = 0
      end
      if @stage0_convert_trace_count < 80
        trace_path = "/tmp/tungsten-stage0-convert-trace"
        trace_text = ""
        if File.exist?(trace_path)
          trace_text = File.read(trace_path)
        end
        trace_text = trace_text + @stage0_convert_trace_count.to_s + ":doc=" + doc.to_s + "\n"
        File.write(trace_path, trace_text)
        @stage0_convert_trace_count += 1
      end
    end

    if doc == 1
      return stage0_ruby_ast_list_to_array(value)
    end
    if doc == 3 || doc == 4 || doc == 5 || doc == 16 || doc == 31 || doc == 32 || doc == 33 || doc == 41
      h = stage0_ast_hash(stage0_ruby_ast_node_kind(value))
      stage0_ast_hash_set(h, "value", value.value)
      return h
    end
    if doc == 6
      return stage0_ast_hash("nil_lit")
    end

    kind = stage0_ruby_ast_node_kind(value)
    h = stage0_ast_hash(kind)

    if doc == 2 || doc == 36
      args = stage0_ruby_ast_array_to_array(value.args)
      if args.length > 0
        stage0_ast_hash_set(h, "value", args[0])
      else
        stage0_ast_hash_set(h, "value", nil)
      end
      return h
    end
    if doc == 7
      stage0_ast_hash_set_node(h, "left", value.left)
      stage0_ast_hash_set(h, "op", value.operator)
      stage0_ast_hash_set_node(h, "right", value.right)
      return h
    end
    if doc == 8
      stage0_ast_hash_set_node(h, "target", value.name)
      stage0_ast_hash_set_node(h, "value", value.value)
      stage0_ast_hash_set_node(h, "type_hint", value.type_hint)
      return h
    end
    if doc == 9 || doc == 27 || doc == 28 || doc == 29 || doc == 46
      stage0_ast_hash_set(h, "name", value.name)
      return h
    end
    if doc == 10
      stage0_ast_hash_set_node(h, "condition", value.condition)
      stage0_ast_hash_set_node(h, "then_body", value.then_block)
      stage0_ast_hash_set(h, "elsif_clauses", [])
      stage0_ast_hash_set_node(h, "else_body", value.else_block)
      return h
    end
    if doc == 11
      stage0_ast_hash_set_node(h, "condition", value.condition)
      stage0_ast_hash_set_node(h, "body", value.body)
      stage0_ast_hash_set(h, "check_first", value.check_first)
      return h
    end
    if doc == 12 || doc == 37
      stage0_ast_hash_set(h, "name", value.name)
      stage0_ast_hash_set(h, "params", stage0_ruby_ast_array_to_array(value.args))
      stage0_ast_hash_set_node(h, "body", value.body)
      stage0_ast_hash_set(h, "type_hints", nil)
      stage0_ast_hash_set(h, "is_class_method", false) if doc == 12
      stage0_ast_hash_set(h, "param_types", stage0_ruby_ast_array_to_array(value.param_types)) if value.param_types != nil
      stage0_ast_hash_set(h, "return_type", value.return_type) if value.return_type != nil
      return h
    end
    if doc == 13
      stage0_ast_hash_set_node(h, "receiver", value.obj)
      stage0_ast_hash_set(h, "name", value.name)
      stage0_ast_hash_set(h, "args", stage0_ruby_ast_array_to_array(value.args))
      stage0_ast_hash_set_node(h, "block", value.block)
      return h
    end
    if doc == 14 || doc == 35
      stage0_ast_hash_set_node(h, "value", value.value)
      return h
    end
    if doc == 15
      stage0_ast_hash_set_node(h, "target", value.name)
      stage0_ast_hash_set(h, "op", value.operator)
      stage0_ast_hash_set_node(h, "value", value.value)
      return h
    end
    if doc == 17
      stage0_ast_hash_set(h, "elements", stage0_ruby_ast_list_to_array(value))
      return h
    end
    if doc == 18
      stage0_ast_hash_set(h, "entries", stage0_ruby_ast_pair_array_to_array(value.entries))
      return h
    end
    if doc == 19 || doc == 20 || doc == 47 || doc == 48
      stage0_ast_hash_set_node(h, "left", value.left)
      stage0_ast_hash_set_node(h, "right", value.right)
      return h
    end
    if doc == 21
      stage0_ast_hash_set_node(h, "lhs", value.lhs)
      stage0_ast_hash_set(h, "elements", stage0_ruby_ast_array_to_array(value.elements))
      return h
    end
    if doc == 22
      stage0_ast_hash_set(h, "whens", stage0_ruby_ast_array_to_array(value.whens))
      stage0_ast_hash_set_node(h, "else_body", value.else)
      return h
    end
    if doc == 23
      stage0_ast_hash_set(h, "path", value.path)
      return h
    end
    if doc == 24
      stage0_ast_hash_set(h, "name", value.name)
      stage0_ast_hash_set_node(h, "superclass", value.superclass)
      stage0_ast_hash_set_node(h, "body", value.body)
      stage0_ast_hash_set(h, "class_role", value.class_role)
      return h
    end
    if doc == 25 || doc == 26
      stage0_ast_hash_set(h, "name", value.name)
      stage0_ast_hash_set_node(h, "body", value.body)
      return h
    end
    if doc == 30
      return h
    end
    if doc == 34
      stage0_ast_hash_set_node(h, "body", value.body)
      stage0_ast_hash_set(h, "rescue_var", value.rescue_var)
      stage0_ast_hash_set_node(h, "rescue_body", value.rescue_body)
      stage0_ast_hash_set_node(h, "ensure_body", value.ensure_body)
      return h
    end
    if doc == 38
      stage0_ast_hash_set(h, "params", stage0_ruby_ast_array_to_array(value.args))
      stage0_ast_hash_set_node(h, "body", value.body)
      return h
    end
    if doc == 39
      stage0_ast_hash_set(h, "name", value.name)
      stage0_ast_hash_set_node(h, "default", value.default)
      stage0_ast_hash_set(h, "ivar_assign", false)
      stage0_ast_hash_set(h, "keyword", value.keyword)
      stage0_ast_hash_set(h, "block_param", false)
      stage0_ast_hash_set(h, "splat", false)
      return h
    end
    if doc == 40 || doc == 49
      stage0_ast_hash_set_node(h, "operand", value.exp)
      return h
    end
    if doc == 42
      stage0_ast_hash_set(h, "parts", stage0_ruby_ast_array_to_array(value.parts))
      return h
    end
    if doc == 43
      stage0_ast_hash_set(h, "pattern", value.pattern)
      stage0_ast_hash_set(h, "options", value.options)
      return h
    end
    if doc == 44
      stage0_ast_hash_set_node(h, "from", value.from)
      stage0_ast_hash_set_node(h, "to", value.to)
      stage0_ast_hash_set(h, "exclusive", value.exclusive)
      return h
    end
    if doc == 45
      stage0_ast_hash_set(h, "element_type", value.element_type)
      stage0_ast_hash_set_node(h, "size", value.size)
      return h
    end
    h
  end

  def stage0_ruby_ast_program(list_node)
    exprs = stage0_ruby_ast_list_to_array(list_node)
    {"node" => "program", :node => "program", "expressions" => exprs, :expressions => exprs}
  end

  def stage0_parse_append_chunk_exprs(out, chunk, resolved)
    return out if chunk.strip == ""

    parsed = parse_with_file(chunk, resolved)
    exprs = stage0_ruby_ast_list_to_array(parsed)
    i = 0
    while i < exprs.length
      out.push(exprs[i])
      i += 1
    end
    out
  end

  def stage0_parse_source_exprs(source, resolved)
    out = stage0_ruby_ast_array_to_array(nil)
    chunk = ""
    source_text = source.to_s
    lines = source_text.split("\n")
    i = 0
    while i < lines.length
      line = lines[i]
      stripped = line.strip
      top_level = false
      if stripped != "" && line.slice(0, 1) != " " && line.slice(0, 1) != "\t"
        if stripped.start_with?("use ") || stripped.start_with?("-> ") ||
           stripped.start_with?("class ") || stripped.start_with?("module ") ||
           stripped.start_with?("trait ") || stripped.start_with?("fn ")
          top_level = true
        end
      end
      if top_level && chunk.strip != ""
        stage0_parse_append_chunk_exprs(out, chunk, resolved)
        chunk = ""
      end
      chunk = chunk + line
      chunk = chunk + "\n"
      i += 1
    end
    stage0_parse_append_chunk_exprs(out, chunk, resolved)
    out
  end

  def stage0_direct_source_for(resolved, raw_source)
    if resolved.end_with?("compiler/lib/compiler.w")
      return stage0_normalize_compiler_source(raw_source)
    end
    if resolved.end_with?("compiler/lib/content_hash.w")
      return stage0_normalize_content_hash_source(raw_source)
    end
    if resolved.end_with?("compiler/lib/target.w")
      return stage0_normalize_target_source(raw_source)
    end
    if resolved.end_with?("compiler/lib/lowering/pass_registry.w")
      return stage0_normalize_lowering_source(raw_source)
    end
    if resolved.end_with?("compiler/lib/lowering/analysis.w")
      source = stage0_normalize_source(raw_source)
      raw_start = source.index("-> raw_int_candidate_map")
      raw_end = source.index("-> find_reassigned_params", raw_start || 0)
      if raw_start != nil && raw_end != nil && raw_end > raw_start
        source = source.slice(0, raw_start) +
                 "-> raw_int_candidate_map(body, declared_types)\n  {}\n\n" +
                 source.slice(raw_end, source.length - raw_end)
      end
      return source
    end
    if resolved.end_with?("compiler/lib/lowering.w")
      return stage0_normalize_lowering_source(raw_source)
    end
    # All four files (cfg.w, ownership.w, escape.w, metal_emitter.w)
    # used to be stubbed to empty source on the assumption that the
    # stage 0 parser couldn't handle them. Empirical testing showed
    # they parse fine — each loads with the expected expression
    # count. The stubs were unnecessary defensive code.
    # metal_emitter.w used to be stubbed too; trying without the stub.
    # If stage 0 chokes on its source we'll see a parser error in
    # the run output and can add it back. The compiler being
    # bootstrapped doesn't use @gpu kernels itself, so the
    # metal_emitter passes are dead code at stage 1 — failing to
    # parse them only matters when stage 0 builds the IR layout.
    stage0_normalize_ruby_parse_source(raw_source)
  end

  def stage0_parse_program_file(path, from_file, loaded)
    resolved = stage0_program_resolve_path(path, from_file)
    stage0_progress_mark("load:start", resolved)
    if loaded[resolved] == true
      stage0_progress_mark("load:skip", resolved)
      return {"node" => "program", :node => "program", "expressions" => [], :expressions => []}
    end

    loaded[resolved] = true
    raw_source = File.read(resolved)
    stage0_progress_mark("load:read", resolved + "\\tbytes=" + raw_source.length.to_s)
    source = stage0_direct_source_for(resolved, raw_source)
    exprs = stage0_parse_source_exprs(source, resolved)
    stage0_progress_mark("load:parsed", resolved + "\\texpressions=" + exprs.length.to_s)
    if ENV["TUNGSTEN_STAGE0_LOAD_TRACE"] == "1"
      trace_path = "/tmp/tungsten-stage0-load-trace"
      trace_text = ""
      if File.exist?(trace_path)
        trace_text = File.read(trace_path)
      end
      trace_text = trace_text + "load " + resolved + " exprs=" + exprs.length.to_s + "\n"
      File.write(trace_path, trace_text)
    end
    out = []
    i = 0
    while i < exprs.length
      expr = exprs[i]
      if stage0_hash_get_any(expr, "node", :node).to_s == "use"
        use_path = stage0_hash_get_any(expr, "path", :path).to_s
        stage0_progress_mark("load:use", resolved + "\\tpath=" + use_path)
        imported = stage0_parse_program_file(use_path, resolved, loaded)
        imported_exprs = stage0_hash_get_any(imported, "expressions", :expressions)
        if ENV["TUNGSTEN_STAGE0_LOAD_TRACE"] == "1"
          trace_path = "/tmp/tungsten-stage0-load-trace"
          trace_text = ""
          if File.exist?(trace_path)
            trace_text = File.read(trace_path)
          end
          trace_text = trace_text + "use " + stage0_hash_get_any(expr, "path", :path).to_s + " imported=" + imported_exprs.length.to_s + "\n"
          File.write(trace_path, trace_text)
        end
        j = 0
        while j < imported_exprs.length
          out.push(imported_exprs[j])
          j += 1
        end
      else
        out.push(expr)
      end
      i += 1
    end
    if ENV["TUNGSTEN_STAGE0_LOAD_TRACE"] == "1"
      trace_path = "/tmp/tungsten-stage0-load-trace"
      trace_text = ""
      if File.exist?(trace_path)
        trace_text = File.read(trace_path)
      end
      trace_text = trace_text + "done " + resolved + " out=" + out.length.to_s + "\n"
      File.write(trace_path, trace_text)
    end
    stage0_progress_mark("load:done", resolved + "\\texpressions=" + out.length.to_s)
    {"node" => "program", :node => "program", "expressions" => out, :expressions => out}
  end

  def stage0_load_program_ast_direct(path)
    stage0_parse_program_file(path, nil, {})
  end

  def resolve_use_path(use_path)
    # Spinel stage0: avoid the `file = @current_file.to_s;
    # parts = file.split("/")` chain — analyzer folds the .to_s
    # to int-default and split lowers to `lv_parts = 0`. Use
    # byteslice on @current_file directly to find the last "/".
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

  def visit_in_test(node)
    lhs = evaluate(node.lhs)
    elements = node.elements
    i = 0
    while i < elements.length
      return true if evaluate(elements[i]) == lhs
      i += 1
    end
    false
  end

  def stage0_parse_interpreter_append_chunk(out, chunk, path)
    return out if chunk.strip == ""

    parsed = parse_with_file(chunk, path)
    items = parsed.list
    i = 0
    while i < items.length
      out.push(items[i])
      i += 1
    end
    out
  end

  def stage0_parse_interpreter_source(source, path)
    out = stage0_ruby_ast_array_to_array(nil)
    chunk = ""
    lines = source.split("\n")
    i = 0
    while i < lines.length
      line = lines[i]
      stripped = line.strip
      top_level = false
      if stripped != "" && line.slice(0, 1) != " " && line.slice(0, 1) != "\t"
        if stripped.start_with?("use ") || stripped.start_with?("-> ") ||
           stripped.start_with?("class ") || stripped.start_with?("module ") ||
           stripped.start_with?("trait ") || stripped.start_with?("fn ")
          top_level = true
        end
      end
      if top_level && chunk.strip != ""
        stage0_parse_interpreter_append_chunk(out, chunk, path)
        chunk = ""
      end
      chunk = chunk + line + "\n"
      i += 1
    end
    stage0_parse_interpreter_append_chunk(out, chunk, path)
    List.new(out)
  end

  def visit_use(node)
    path = resolve_use_path(node.path)
    if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
      puts "stage0 use"
      puts path
    end
    return nil if @loaded_files[path] == true

    @loaded_files[path] = true
    raw_source = File.read(path)
    source = ""
    if ENV["TUNGSTEN_SPINEL_STAGE0_CALL_TRACE"] == "1"
      use_trace_path = "/tmp/tungsten-stage0-use-trace.txt"
      use_trace_text = ""
      if File.exist?(use_trace_path)
        use_trace_text = File.read(use_trace_path)
      end
      File.write(use_trace_path, use_trace_text + path + "\n")
    end
    if path.end_with?("compiler/lib/compiler.w")
      source = self.stage0_normalize_compiler_source(raw_source)
    elsif path.end_with?("compiler/lib/ast.w")
      source = self.stage0_normalize_ast_source(raw_source)
    elsif path.end_with?("compiler/lib/loader.w")
      source = self.stage0_normalize_loader_source(raw_source)
    elsif path.end_with?("compiler/lib/lexer.w")
      source = self.stage0_normalize_lexer_source(raw_source)
    elsif path.end_with?("compiler/lib/parser.w")
      source = self.stage0_normalize_compiler_language_source(raw_source)
      dump_path = ENV["TUNGSTEN_SPINEL_STAGE0_PARSER_DUMP"]
      if dump_path != nil && dump_path != ""
        File.write(dump_path, source)
      end
    elsif path.end_with?("compiler/lib/interpreter.w") ||
       path.end_with?("compiler/lib/loader.w") ||
       path.end_with?("compiler/lib/error_formatter.w") ||
       path.end_with?("compiler/lib/metal_emitter.w")
      source = self.stage0_normalize_lexer_source(raw_source)
    elsif path.end_with?("compiler/lib/wire.w")
      source = self.stage0_normalize_wire_source(raw_source)
      dump_path = ENV["TUNGSTEN_SPINEL_STAGE0_WIRE_DUMP"]
      if dump_path != nil && dump_path != ""
        File.write(dump_path, source)
      end
    elsif path.end_with?("compiler/lib/target.w")
      source = self.stage0_normalize_target_source(raw_source)
    elsif path.end_with?("compiler/lib/lowering/analysis.w")
      source = self.stage0_normalize_source(raw_source)
      raw_start = source.index("-> raw_int_candidate_map")
      raw_end = source.index("-> find_reassigned_params", raw_start || 0)
      if raw_start != nil && raw_end != nil && raw_end > raw_start
        source = source.slice(0, raw_start) +
                 "-> raw_int_candidate_map(body, declared_types)\n  {}\n\n" +
                 source.slice(raw_end, source.length - raw_end)
      end
    elsif path.end_with?("compiler/lib/lowering.w")
      source = self.stage0_normalize_lowering_source(raw_source)
      dump_path = ENV["TUNGSTEN_SPINEL_STAGE0_LOWERING_DUMP"]
      if dump_path != nil && dump_path != ""
        File.write(dump_path, source)
      end
    elsif path.end_with?("compiler/lib/lowering/pass_registry.w")
      source = self.stage0_normalize_lowering_source(raw_source)
      dump_path = ENV["TUNGSTEN_SPINEL_STAGE0_PASS_REGISTRY_DUMP"]
      if dump_path != nil && dump_path != ""
        File.write(dump_path, source)
      end
    elsif path.end_with?("compiler/lib/content_hash.w")
      source = self.stage0_normalize_content_hash_source(raw_source)
    elsif path.end_with?("compiler/lib/emitter.w")
      source = self.stage0_normalize_emitter_source(raw_source)
      dump_path = ENV["TUNGSTEN_SPINEL_STAGE0_EMITTER_DUMP"]
      if dump_path != nil && dump_path != ""
        File.write(dump_path, source)
      end
    elsif path.end_with?("languages/tungsten/lexers/regex.w")
      source = self.stage0_normalize_regex_source(raw_source)
    else
      source = self.stage0_normalize_source(raw_source)
    end
    if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
      puts "stage0 use source length"
      puts source.length
    end
    old_file = @current_file
    old_returning = @returning
    old_return_value = @return_value
    old_exiting = @exiting
    if @stage0_loading_depth == nil
      @stage0_loading_depth = 0
    end
    @current_file = path
    ast = stage0_parse_interpreter_source(source, path)
    if ENV["TUNGSTEN_SPINEL_STAGE0_DEBUG"] == "1"
      puts "stage0 use ast length"
      puts ast.length
    end
    @stage0_loading_depth += 1
    evaluate(ast)
    @stage0_loading_depth -= 1
    if ENV["TUNGSTEN_SPINEL_STAGE0_CALL_TRACE"] == "1"
      use_trace_path = "/tmp/tungsten-stage0-use-trace.txt"
      use_trace_text = ""
      if File.exist?(use_trace_path)
        use_trace_text = File.read(use_trace_path)
      end
      File.write(use_trace_path, use_trace_text + path + " done\n")
    end
    @returning = old_returning
    @return_value = old_return_value
    @exiting = old_exiting
    @current_file = old_file
    nil
  end
RUBY
postamble_marker = "\n  end\n\n\n# -- implementations/spinel/stage0/postamble.rb --"
final_bundle = replace_method(final_bundle, "visit_var", <<~RUBY)
  def visit_var(node)
    cached_slot = node.cached_slot
    if cached_slot > 0 && node.cached_layout_shape == @env.layout_shape
      value = @env.get_slot(cached_slot)
      return value unless value.nil?
    end

    name = stage0_var_name(node)
    idx = @env.slot_index(name)
    if idx > 0
      node.cached_slot = idx
      node.cached_layout_shape = @env.layout_shape
      value = @env.get_slot(idx)
      return value unless value.nil?
    end

    # Walk the parent chain with concrete sp_Environment* locals, mirroring
    # Environment#get EXACTLY: spinel can't box an sp_Environment* into a
    # poly slot, the .get poly dispatch flips the local poly, and even a
    # `while pe != nil` loop CONDITION boxes pe -> poly. Using a flag-driven
    # loop with `if np == nil` STATEMENT checks (as get does) and only
    # concrete `.parent`/Environment-method uses keeps pe/np typed
    # sp_Environment*. Stops at the first slot found (get's semantics).
    pe = @env
    looking = true
    while looking
      np = pe.parent
      if np == nil
        looking = false
      else
        pe = np
        pidx = pe.slot_index(name)
        if pidx > 0
          value = pe.get_slot(pidx)
          return value unless value.nil?
          looking = false
        end
      end
    end

    klass = @classes[name]
    return klass unless klass.nil?

    nil
  end
RUBY
final_bundle = final_bundle.sub(postamble_marker, final_use_methods + "\n  end\n\n\n# -- implementations/spinel/stage0/postamble.rb --")

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

File.write(out, final_bundle)

puts out
