# frozen_string_literal: true

require "bigdecimal"

module Tungsten
  # Control-flow signals use throw/catch instead of raise/rescue for performance.
  # throw/catch bypasses rescue clause checking during stack unwinding.
  BREAK_SIGNAL  = :w_break
  NEXT_SIGNAL   = :w_next
  RETURN_SIGNAL = :w_return

  class Interpreter < Visitor
    W_NIL           = 0x0000_0000_0000_0000
    W_FALSE         = 0x0000_0000_0000_0001
    W_TRUE          = 0x0000_0000_0000_0002
    W_UNDEF         = 0x0000_0000_0000_0003
    W_MEMO_MISS     = 0x0000_0000_0000_0004

    W_DOUBLE_BIAS   = 0x0001_0000_0000_0000

    W_TAG_STRINGSYM = 0xFFF9_0000_0000_0000
    W_TAG_INT       = 0xFFFA_0000_0000_0000
    W_TAG_INSTANT   = 0xFFFB_0000_0000_0000
    W_TAG_CHAR      = 0xFFFC_0000_0000_0000
    W_TAG_DECIMAL   = 0xFFFD_0000_0000_0000
    W_TAG_PACKED    = 0xFFFE_0000_0000_0000
    W_TAG_DURATION  = 0xFFFF_0000_0000_0000

    W_PAYLOAD_MASK  = 0x0000_FFFF_FFFF_FFFF
    W_DOUBLE_MAX    = 0xFFF8_FFFF_FFFF_FFFF
    W_TAG_MASK      = 0xFFFF_0000_0000_0000

    W_INT48_MAX = (1 << 47) - 1
    W_INT48_MIN = -(1 << 47)
    W_DECIMAL_SIG_MAX = (1 << 38) - 1
    W_DECIMAL_SIG_MIN = -(1 << 38)
    W_DECIMAL_SCALE_MAX = 63
    W_DECIMAL_SCALE_MIN = -64
    W_CURRENCY_SIG_MAX = (1 << 36) - 1
    W_CURRENCY_SIG_MIN = -(1 << 36)
    W_CURRENCY_SCALE_MAX = 15
    W_CURRENCY_SCALE_MIN = -16
    W_QUANTITY_SIG_MAX = (1 << 30) - 1
    W_QUANTITY_SIG_MIN = -(1 << 30)
    W_DURATION_NS_MAX = (1 << 46) - 1
    W_DURATION_NS_MIN = -(1 << 46)
    W_DURATION_MONTHS_MAX = (1 << 14) - 1
    W_DURATION_MONTHS_MIN = -(1 << 14)

    BUILTIN_METHODS = %w[to_s class class_name nil? is_a? respond_to? itself].freeze
    HIDDEN_RUBY_OBJECT_METHODS = {
      "object_id" => true,
      "__id__" => true,
      "equal?" => true
    }.freeze
    TYPE_INFO_METHODS = {
      "class" => true,
      "class_name" => true,
      "superclass" => true,
      "ancestors" => true
    }.freeze
    MEMO_MAX_SIZE = 10_000
    PROFILE_REPORT_LIMIT = 40
    UNSUPPORTED_CASE_LITERAL = Object.new.freeze
    NO_LITERAL_CASE_LOOKUP = Object.new.freeze
    BYTECODE_ENABLED = ENV["TUNGSTEN_BYTECODE"] == "1"
    DISPATCH_PROFILE_ENABLED = ENV["TUNGSTEN_PROFILE_CALLS"] == "1" || ENV["TUNGSTEN_PROFILE_DISPATCH"] == "1"
    SIMPLE_WHILE_UNSUPPORTED = Object.new.freeze
    SIMPLE_WHILE_ALWAYS_TRUE = Object.new.freeze
    SIMPLE_METHOD_UNSUPPORTED = Object.new.freeze
    SIMPLE_W_METHOD_UNSUPPORTED = Object.new.freeze
    SIMPLE_BLOCK_UNSUPPORTED = Object.new.freeze
    STATIC_CONDITION_UNKNOWN = Object.new.freeze
    WYHASH_U64_MASK = 0xFFFF_FFFF_FFFF_FFFF
    WYHASH_S1 = 0xE703_7ED1_A0B4_28DB
    SIMPLE_WHILE_COMPARE_OPS = {
      :== => true,
      :!= => true,
      :< => true,
      :> => true,
      :<= => true,
      :>= => true
    }.freeze
    SIMPLE_WHILE_ARITH_OPS = {
      :+ => true,
      :- => true,
      :* => true,
      :/ => true,
      :% => true,
      :** => true,
      :& => true,
      :| => true,
      :^ => true,
      :<< => true,
      :>> => true
    }.freeze

    # Pre-compute once per method body whether it contains a Return node.
    # Avoids catch(RETURN_SIGNAL) overhead (~3% of total) on every call
    # when the method never returns early.
    def self.body_has_return?(node)
      return true if node.is_a?(AST::Return)
      node.children { |c| return true if body_has_return?(c) }
      false
    end

    def self.body_has_break?(node)
      body_has_control_signal?(node, AST::Break, :@has_break) do |child|
        child.is_a?(AST::Def) || child.is_a?(AST::Fn) ||
          child.is_a?(AST::While) || child.is_a?(AST::Until) || child.is_a?(AST::With)
      end
    end

    def self.body_has_next?(node)
      body_has_control_signal?(node, AST::Next, :@has_next) do |child|
        child.is_a?(AST::Def) || child.is_a?(AST::Fn) || child.is_a?(AST::Block) ||
          child.is_a?(AST::While) || child.is_a?(AST::With)
      end
    end

    def self.body_has_control_signal?(node, signal_class, cache_ivar, &boundary)
      return false unless node
      return true if node.is_a?(signal_class)
      return false if boundary.call(node)
      return node.instance_variable_get(cache_ivar) if node.instance_variable_defined?(cache_ivar)

      has_signal = false
      node.children do |child|
        if body_has_control_signal?(child, signal_class, cache_ivar, &boundary)
          has_signal = true
          break
        end
      end

      node.instance_variable_set(cache_ivar, has_signal)
      has_signal
    end
    private_class_method :body_has_control_signal?

    BUILTIN_TYPES = %w[
      String Integer Float Boolean Nil
      Array Hash Symbol Range Decimal Tuple
      Class Tungsten
    ].freeze
    BUILTIN_CONSTANT_NAMES = %w[
      π τ ϕ φ ℯ ℇ ∞ ℎ ℏ c G g₀ Nₐ kB e₀ R ε₀ μ₀ µ₀ σ α mₑ mₚ a₀ Eₕ Ry 𝐹
    ].freeze
    TUNGSTEN_KEYWORDS = %w[
      begin break case else elsif ensure exit extern false fn go if in is loop module nil next on parallel
      raise rescue return self super then trait true unless until use when while with yield
    ].to_h { |word| [ word, true ] }.freeze
    TUNGSTEN_TYPE_NAME_WORDS = %w[
      bool int integer string string_buffer
      i1 i4 i8 i16 i32 i64 i128
      u1 u4 u8 u16 u32 u64 u128
      w64
      f16 f32 f64 f80 f128 f256
      d128 c32 c64 c128
      bigint bigdecimal
      bf16 tf32 fp8 fp4 nf4
      mxfp8 mxfp6 mxfp4 mxint8
      posit8 posit16 posit32 posit64
    ].to_h { |word| [ word, true ] }.freeze
    LEXER_VALUE_TOKEN_TYPES = %i[
      INT FLOAT DECIMAL STRING STRING_INTERP REGEX REGEX_CAPTURE SYMBOL NAME ID IVAR CVAR GLOBAL RPAREN RBRACKET
      RBRACE MAGIC_FILE MAGIC_LINE MAGIC_DIR UUID CURRENCY QUANTITY DURATION WVALUE BYTE_ARRAY BYTE_ARRAY_INTERP DATE
      DATETIME TIME MONTH IP4 CIDR4 RATIONAL CHAR CODEPOINT KEY WORD_ARRAY SYMBOL_ARRAY BASE32 BASE58 BASE64 PARG
      SUPERSCRIPT COLOR
    ].to_h { |type| [ type, true ] }.freeze
    LEXER_OP_TYPES = {
      "<-" => :PRINT_OP,
      "<!" => :RAISE_OP,
      "=>" => :FAT_ARROW,
      "==" => :EQ,
      "=~" => :MATCH,
      "!=" => :NEQ,
      "<=" => :LTE,
      ">>" => :RSHIFT,
      ">=" => :GTE,
      "&." => :SAFE_NAV,
      "&&" => :AND,
      "||=" => :OR_ASSIGN,
      "||" => :OR,
      "|>" => :PIPE_FWD,
      "++" => :PLUS_PLUS,
      "+=" => :PLUS_EQ,
      "--" => :MINUS_MINUS,
      "-=" => :MINUS_EQ,
      "**" => :POW,
      "*=" => :STAR_EQ,
      "/=" => :SLASH_EQ,
      "%=" => :PERCENT_EQ,
      "-" => :MINUS,
      "*" => :STAR,
      "/" => :SLASH,
      "·" => :DOT_PRODUCT,
      "⋅" => :DOT_PRODUCT,
      "×" => :CROSS_PRODUCT,
      "%" => :PERCENT,
      "<" => :LT,
      ">" => :GT,
      "=" => :ASSIGN,
      "!" => :BANG,
      "..." => :DOTDOTDOT,
      ".." => :DOTDOT,
      ".+" => :DOT_PLUS,
      ".-" => :DOT_MINUS,
      ".*" => :DOT_STAR,
      "./" => :DOT_SLASH,
      ".|" => :DOT_PIPE,
      ".&" => :DOT_AMP,
      ".^" => :DOT_CARET,
      ".<<" => :DOT_LSHIFT,
      ".>>" => :DOT_RSHIFT,
      "." => :DOT,
      "," => :COMMA,
      "&(" => :BLOCK_CALL,
      "&" => :AMPERSAND,
      "|" => :PIPE,
      "^" => :CARET,
      "(" => :LPAREN,
      ")" => :RPAREN,
      "{" => :LBRACE,
      "}" => :RBRACE,
      "[" => :LBRACKET,
      "]" => :RBRACKET,
      "?" => :QUESTION,
      ":" => :COLON,
      ";" => :SEMICOLON
    }.freeze

    def initialize(argv: nil)
      @env = Environment.new
      @classes = {}
      @modules = {}
      @self_stack = [nil]
      @call_methods = []
      @call_locations = []
      @builtins = {}
      @method_builtins = {}
      @globals = {}
      @argv = (argv || ARGV).map(&:to_s)
      @dispatch = {}.compare_by_identity

      @loaded_files = {}
      @current_file = nil
      @source = nil
      @file_sources = {}  # file_path => source_code

      @profile_enabled = ENV["TUNGSTEN_PROFILE_CALLS"] == "1"
      @profile_reported = false
      @profile_caller_stack = ["<top-level>"]
      @profile_visit_calls_by_caller = Hash.new(0)
      @profile_visit_calls_by_target = Hash.new(0)
      @profile_binary_ops = Hash.new(0)
      @profile_dispatch_counts = Hash.new { |h, k| h[k] = Hash.new(0) }

      Runtime::Builtins.setup(self)
      BUILTIN_TYPES.each { |name| @classes[name] ||= Runtime::WClass.new(name, nil) }
    end

    def define_builtin(name, &block)
      @builtins[name] = block
    end

    def define_method_builtin(name, &block)
      @method_builtins[name] = block
    end

    def argv
      @argv.dup
    end

    def argv=(values)
      @argv = values.map(&:to_s)
    end

    def profile_enabled?
      @profile_enabled
    end

    def profile_caller_label
      @profile_caller_stack.last || "<top-level>"
    end

    def profile_callable_label(func)
      case func
      when Runtime::WMethod
        owner = func.defining_class&.name || "<?>"
        "#{owner}##{func.name}"
      when AST::Def, AST::Fn
        loc = func.location
        file_label = loc&.file ? File.basename(loc.file) : "<?>"
        func.name ? "#{file_label}::#{func.name}" : "#{file_label}::<lambda>"
      else
        func.class.name.split("::").last
      end
    end

    def with_profile_callable(func)
      return yield unless profile_enabled?

      @profile_caller_stack.push(profile_callable_label(func))
      yield
    ensure
      @profile_caller_stack.pop
    end

    def profile_visit_call(target_label)
      return unless profile_enabled?

      @profile_visit_calls_by_caller[profile_caller_label] += 1
      @profile_visit_calls_by_target[target_label] += 1
    end

    def profile_binary_op(operator)
      return unless profile_enabled?

      @profile_binary_ops[operator] += 1
    end

    def profile_dispatch_path(table, key)
      return unless DISPATCH_PROFILE_ENABLED

      @profile_dispatch_counts[table][key] += 1
    end

    def print_profile_table(io, title, table)
      io.puts title
      io.puts "  (none)" if table.empty?
      table.sort_by { |name, count| [-count, name.to_s] }.first(PROFILE_REPORT_LIMIT).each do |name, count|
        io.puts format("  %9d  %s", count, name)
      end
    end

    def print_profile_report
      return unless profile_enabled? || DISPATCH_PROFILE_ENABLED
      return if @profile_reported

      @profile_reported = true
      io = $stderr
      io.puts
      io.puts "== Ruby Interpreter Counters =="
      print_profile_table(io, "visit_call by caller", @profile_visit_calls_by_caller)
      io.puts
      print_profile_table(io, "visit_call by target", @profile_visit_calls_by_target)
      io.puts
      print_profile_table(io, "visit_binary_op by operator", @profile_binary_ops)
      @profile_dispatch_counts.each do |title, table|
        io.puts
        print_profile_table(io, title, table)
      end
    end

    def set_variable(name, value)
      @env.set(name, value)
    end

    def run(source, file_path: nil)
      @current_file = File.expand_path(file_path) if file_path
      @source = source
      @file_sources[@current_file] = source if @current_file
      ast = parse_with_file(source, @current_file)
      evaluate(ast)
    rescue Tungsten::Error => e
      e.call_stack ||= build_call_stack
      raise
    rescue NoMethodError, ZeroDivisionError, SystemStackError, TypeError => e
      raise runtime_error_from_exception(e)
    ensure
      print_profile_report
    end

    def save_state
      {
        env: @env,
        classes: @classes.dup,
        modules: @modules.dup,
        self_stack: @self_stack.dup,
        call_methods: @call_methods.dup,
        call_locations: @call_locations.dup,
        globals: @globals.dup,
        loaded_files: @loaded_files.dup,
        current_file: @current_file,
        source: @source,
        file_sources: @file_sources.dup,
        runtime_class_state: snapshot_runtime_class_state
      }
    end

    def restore_state(snapshot)
      restore_runtime_class_state(snapshot[:runtime_class_state])
      @env = snapshot[:env]
      @classes = snapshot[:classes]
      @modules = snapshot[:modules]
      @self_stack = snapshot[:self_stack]
      @call_methods = snapshot[:call_methods]
      @call_locations = snapshot[:call_locations]
      @globals = snapshot[:globals]
      @loaded_files = snapshot[:loaded_files]
      @current_file = snapshot[:current_file]
      @source = snapshot[:source]
      @file_sources = snapshot[:file_sources]
    end

    def evaluate_isolated(source, file_path: nil)
      snapshot = save_state
      @env = Environment.new(@env, barrier: true)
      run(source, file_path: file_path)
    ensure
      restore_state(snapshot)
    end

    def snapshot_runtime_class_state
      seen = {}.compare_by_identity
      (@classes.values + @modules.values).each do |klass|
        next unless klass.is_a?(Runtime::WClass)
        next if seen.key?(klass)

        seen[klass] = {
          superclass: klass.superclass,
          methods: klass.methods.dup,
          traits: klass.traits.dup,
          version: klass.version,
          class_vars: klass.class_vars.dup
        }
      end
      seen
    end

    def restore_runtime_class_state(snapshot)
      return unless snapshot

      snapshot.each do |klass, state|
        klass.superclass = state[:superclass]
        klass.methods = state[:methods]
        klass.traits = state[:traits]
        klass.version = state[:version]
        klass.class_vars = state[:class_vars]
      end
    end

    def reload_module(path)
      path = File.expand_path(path)
      source = File.read(path)
      prev_file = @current_file
      @current_file = path
      @source = source
      @file_sources[path] = source
      ast = parse_with_file(source, path)
      evaluate(ast)
    ensure
      @current_file = prev_file
    end

    def evaluate(node)
      klass = node.class
      case
      when klass == AST::List          then return visit_list(node)
      when klass == AST::Print         then return visit_print(node)
      when klass == AST::Int           then return node.value
      when klass == AST::Var           then return visit_var(node)
      when klass == AST::BinaryOp      then return visit_binary_op(node)
      when klass == AST::Call          then return visit_call(node)
      when klass == AST::Write         then return visit_write(node)
      when klass == AST::Symbol        then return cached_symbol_value(node)
      when klass == AST::If            then return visit_if(node)
      when klass == AST::Assign        then return visit_assign(node)
      when klass == AST::StringLiteral then return node.value
      when klass == AST::Nil           then return nil
      when klass == AST::InstanceVar   then return @self_stack.last.instance_vars[node.name]
      when klass == AST::AssignOp      then return visit_assign_op(node)
      when klass == AST::And           then return visit_and(node)
      when klass == AST::Return        then return visit_return(node)
      when klass == AST::Boolean       then return node.value
      when klass == AST::Or            then return visit_or(node)
      when klass == AST::InTest        then return visit_in_test(node)
      when klass == AST::While         then return visit_while(node)
      when klass == AST::CaseExpr      then return visit_case_expr(node)
      when klass == AST::HashLiteral   then return visit_hash_literal(node)
      when klass == AST::ArrayLiteral  then return visit_array_literal(node)
      end
      return decode_w_value(node.value, node.raw) if klass.name == "Tungsten::AST::WValue"
      case klass.name
      when "Tungsten::AST::Char"
        return Tungsten::CharValue.new(node.value)
      when "Tungsten::AST::Float",
           "Tungsten::AST::Decimal",
           "Tungsten::AST::Month",
           "Tungsten::AST::Week"
        return node.value
      end

      __send__(@dispatch[klass] ||= klass.visitor_method, node)
    end

    def runtime_error(msg, node: nil, length: nil)
      raise build_runtime_error(msg, node: node, length: length)
    end

    def build_runtime_error(msg, node: nil, length: nil)
      err = Tungsten::Error.new(msg)
      err.location = node&.location
      err.source_code = source_for(node&.location&.file)
      err.file_path = node&.location&.file || @current_file
      err.name_length = length
      err.call_stack = build_call_stack
      err
    end

    def runtime_error_from_exception(error, node: nil)
      case error
      when NoMethodError
        receiver = begin
          error.receiver
        rescue ArgumentError
          nil
        end
        build_runtime_error("undefined method '#{error.name}'#{receiver ? " for #{receiver.inspect}" : ""}", node: node)
      when ZeroDivisionError
        build_runtime_error("division by zero", node: node)
      when SystemStackError
        build_runtime_error("stack level too deep (infinite recursion?)", node: node)
      when TypeError
        build_runtime_error(error.message, node: node)
      else
        raise error
      end
    end

    def source_for(file)
      return @source unless file
      @file_sources[file] || @source
    end

    def resolve_cached_local(node, name)
      if node.cached_layout_shape == @env.layout_shape
        return @env.get_slot(node.cached_slot)
      end

      if (ce = node.cached_env) && ce.equal?(@env)
        return ce.get_slot(node.cached_slot)
      end

      idx = @env.slot_index(name)
      if idx
        node.cached_env = @env
        node.cached_slot = idx
        node.cached_layout_shape = @env.layout_shape
        return @env.get_slot(idx)
      end

      env = @env
      env = env.parent
      while env
        idx = env.slot_index(name)
        if idx
          node.cached_env = env
          node.cached_slot = idx
          node.cached_layout_shape = 1
          return env.get_slot(idx)
        end

        env = env.parent
      end

      Environment::UNDEFINED
    end

    def cached_w_method(node, owner)
      return nil unless owner
      return nil unless (cached_owner = node.cached_dispatch_owner)&.equal?(owner)
      return nil unless node.cached_dispatch_version == owner.version

      node.cached_w_method
    end

    def cache_w_method(node, owner, method)
      node.cached_dispatch_owner = owner
      node.cached_dispatch_version = owner.version
      node.cached_w_method = method
    end

    def resolve_w_method(node, owner, name)
      return nil unless owner

      if (cached_owner = node.cached_dispatch_owner)&.equal?(owner) &&
         node.cached_dispatch_version == owner.version
        return node.cached_w_method
      end

      method = owner.lookup_method(name)
      cache_w_method(node, owner, method) if method
      method
    end

    def build_call_stack
      @call_methods.each_with_index.map do |method, i|
        recv = method.defining_class&.name
        name = method.name
        label = recv ? "#{recv}##{name}" : name.to_s
        { label: label, location: @call_locations[i] }
      end
    end

    def parse_with_file(source, file)
      with_gc_paused_for_parse do
        parser = Tungsten::Parser.new(source)
        parser.file = file if file
        parser.parse.set_parents!
      end
    end

    def inspect_wvalue_literal(raw)
      load_inspection_support
      inspect_wvalue_literal(raw)
    end

    def inspect_runtime_value(value)
      load_inspection_support
      inspect_runtime_value(value)
    end

    def completion_names
      load_inspection_support
      completion_names
    end

    def inline_signature_for(source)
      load_inspection_support
      inline_signature_for(source)
    end

    def method_reference(ref)
      load_inspection_support
      method_reference(ref)
    end

    private

    def load_inspection_support
      require "tungsten/interpreter/inspection"
    end

    def load_quantity_support
      require "tungsten/interpreter/quantity_support"
    end

    def load_builtin_constant_support
      require "tungsten/interpreter/builtin_constants"
    end

    def with_gc_paused_for_parse
      already_disabled = GC.disable
      yield
    ensure
      return if already_disabled

      GC.enable
      # Parsing creates a burst of short-lived lexer/parser objects.
      # Collect once before interpretation so the next GC runs later.
      GC.start(full_mark: false, immediate_mark: false, immediate_sweep: true)
    end

    def visit_w_value(node)
      decode_w_value(node.value, node.raw)
    end

    def decode_w_value(bits, raw = nil)
      bits = bits.to_i

      case bits
      when W_NIL then return nil
      when W_FALSE then return false
      when W_TRUE then return true
      end

      return decode_w_value_double(bits) if w_value_double?(bits)

      case bits & W_TAG_MASK
      when W_TAG_INT
        sign_extend(bits & W_PAYLOAD_MASK, 48)
      when W_TAG_STRINGSYM
        decode_w_value_stringy(bits, raw)
      when W_TAG_CHAR
        decode_w_value_char(bits, raw)
      else
        Runtime::RawWValue.new(bits, raw)
      end
    end

    def w_value_double?(bits)
      bits >= W_DOUBLE_BIAS && bits <= W_DOUBLE_MAX
    end

    def decode_w_value_double(bits)
      ieee_bits = bits - W_DOUBLE_BIAS
      [ ieee_bits ].pack("Q>").unpack1("G")
    end

    def decode_w_value_stringy(bits, raw)
      mode = (bits >> 1) & 0x7
      is_symbol = (bits & 1) == 1
      return Runtime::RawWValue.new(bits, raw) if mode > 5

      bytes = []
      mode.times do |i|
        bytes << ((bits >> (4 + (8 * i))) & 0xFF)
      end

      text = bytes.pack("C*").force_encoding(Encoding::UTF_8)
      is_symbol ? text.to_sym : text
    end

    def decode_w_value_char(bits, raw)
      subtype = (bits >> 46) & 0x3
      return Runtime::RawWValue.new(bits, raw) unless subtype == 3

      Tungsten::CharValue.new(bits & 0x1F_FFFF)
    rescue RangeError
      Runtime::RawWValue.new(bits, raw)
    end

    def sign_extend(value, width)
      sign_bit = 1 << (width - 1)
      mask = 1 << width
      value >= sign_bit ? value - mask : value
    end

    def visit_boolean(node)
      node.value
    end

    def visit_nil(node)
      nil
    end

    def visit_string_literal(node)
      node.value
    end

    def visit_regex_literal(node)
      node.value
    end

    def visit_symbol(node)
      cached_symbol_value(node)
    end

    def visit_string_interpolation(node)
      node.parts.map { |part| w_to_s(evaluate(part)) }.join
    end

    def visit_char(node)
      Tungsten::CharValue.new(node.value)
    end

    def visit_magic_constant(node)
      case node.value
      when :__LINE__
        node.location&.row || 0
      when :__FILE__
        @current_file || "(eval)"
      when :__DIR__
        @current_file ? File.dirname(@current_file) : Dir.pwd
      end
    end

    def visit_array_literal(node)
      result = []
      node.list.each do |e|
        if e.is_a?(Tungsten::AST::Splat)
          result.concat(Array(evaluate(e.exp)))
        else
          result << evaluate(e)
        end
      end
      result
    end

    def visit_tuple(node)
      node.elements.map { |e| evaluate(e) }.freeze
    end

    def visit_hash_literal(node)
      result = {}
      node.entries.each do |key_node, value_node|
        result[evaluate(key_node)] = evaluate(value_node)
      end
      result
    end

    def visit_range_literal(node)
      from = evaluate(node.from)
      if node.to.nil?
        return node.exclusive ? (from...) : (from..)
      end
      to = evaluate(node.to)
      node.exclusive ? (from...to) : (from..to)
    end

    def visit_ip4(node)          = IP4.new(node.value)
    def visit_ip6(node)          = IP6.new(node.value)
    def visit_cidr4(node)        = CIDR4.new(node.value)
    def visit_cidr6(node)        = CIDR6.new(node.value)
    def visit_date(node)         = Date.new(node.value)
    def visit_date_time(node)    = DateTime.new(node.value)
    def visit_time_literal(node) = Time.new(node.value)
    def visit_set_literal(node)      = SetLiteral.new(node.elements.map { |e| evaluate(e) })
    def visit_multiset_literal(node) = MultisetLiteral.new(node.elements.map { |e| evaluate(e) })
    def visit_uuid(node)         = UUID.new(node.value)
    def visit_color_literal(node) = Color.new(node.r, node.g, node.b, node.a)
    def visit_rational_literal(node) = node.value
    def visit_duration(node)     = Duration.parse(node.value)
    def visit_month(node)        = node.value
    def visit_week(node)         = node.value

    def visit_key_literal(node)
      Tungsten::Key.parse(node.value)
    end

    def visit_byte_array_literal(node)
      Tungsten::ByteArray.new(node.value)
    end

    def visit_typed_array(node)
      size = evaluate(node.size).to_i
      case node.element_type.to_s
      when "bool"
        Array.new(size, false)
      when "f32", "f64"
        Array.new(size, 0.0)
      else
        Array.new(size, 0)
      end
    end

    def visit_byte_array_interpolation(node)
      result = []
      node.parts.each do |part|
        val = evaluate(part)
        case val
        when Tungsten::ByteArray
          result.concat(val.bytes)
        when Integer
          runtime_error("byte value #{val} out of range (0-255)", node: node) unless val >= 0 && val <= 255
          result << val
        else
          runtime_error(
            "byte array interpolation must produce Integer or ByteArray, got #{tungsten_class_name(val)}",
            node: node
          )
        end
      end
      Tungsten::ByteArray.new(result)
    end

    def visit_currency_literal(node)
      value = BigDecimal(node.value_str.to_s.delete("_"))
      Tungsten::Currency.new(value, node.symbol)
    end

    def visit_percentage_literal(node)
      value = case node.num_type
              when :FLOAT   then node.value_str.delete("~").to_f
              when :DECIMAL then BigDecimal(node.value_str)
              else               node.value_str.to_f
              end
      Tungsten::Percentage.new(value)
    end

    def visit_measurement_literal(node)
      value = evaluate(node.number)
      Tungsten::Measurement.new(value, node.uncertainty)
    end

    def visit_quantity_literal(node)
      load_quantity_support
      visit_quantity_literal(node)
    end

    def visit_list(node)
      result = nil
      node.each { |exp| result = evaluate(exp) }
      result
    end

    def visit_binary_op(node)
      @profile_binary_ops[node.operator] += 1 if @profile_enabled
      left = evaluate(node.left)

      case node.operator
      when :|
        if left.is_a?(Quantity)
          return convert_quantity_pipe(left, node.right)
        end
      when :"»"
        runtime_error("» requires a Quantity on the left", node: node) unless left.is_a?(Quantity)
        return convert_quantity_pipe(left, node.right)
      end

      right = evaluate(node.right)

      case node.operator
      when :==  then left == right
      when :<   then left < right
      when :!=  then !(left == right)
      when :"=~"
        regex, subject = left.is_a?(Regexp) ? [left, right] : [right, left]
        runtime_error("=~ requires a regex operand", node: node) unless regex.is_a?(Regexp)
        match = regex.match(subject.to_s)
        if match
          @globals["$~"] = match
          @globals["$0"] = match[0]
          match.captures.each_with_index { |capture, i| @globals["$#{i + 1}"] = capture }
        end
        !!match
      when :+
        # char + int → shift codepoint
        if left.is_a?(String) && left.length == 1 && right.is_a?(Integer)
          return [left.ord + right].pack("U")
        end
        if left.is_a?(Integer) && right.is_a?(String) && right.length == 1
          return [left + right.ord].pack("U")
        end
        left + right
      when :*   then left * right
      when :<<  then left << right
      when :±
        # `5.0 ± 0.1` → Measurement(5.0, 0.1).
        # If either side already carries uncertainty, that's a layered situation
        # (e.g. `(a ± b) ± c`) — treat it as updating the sigma rather than nesting.
        l_val = left.is_a?(Tungsten::Measurement) ? left.value : left
        r_val = right.is_a?(Tungsten::Measurement) ? right.value : right
        Tungsten::Measurement.new(l_val, r_val.abs)
      when :-
        # char - int → shift codepoint, char - char → int difference
        if left.is_a?(String) && left.length == 1 && right.is_a?(Integer)
          return [left.ord - right].pack("U")
        end
        if left.is_a?(String) && left.length == 1 && right.is_a?(String) && right.length == 1
          return left.ord - right.ord
        end
        left - right
      when :/   then left / right
      when :%   then left % right
      when :**  then left ** right
      when :<=  then left <= right
      when :>   then left > right
      when :>=  then left >= right
      when :<=> then left <=> right
      when :>>  then left >> right
      when :&   then left & right
      when :|   then left | right
      when :^   then left ^ right
      when :".+", :".-", :".*", :"./", :".|", :".&", :".^", :".<<", :".>>"
        # Phase 4e dot-prefix elementwise operators. Mirrors the runtime
        # `w_array_*_elem` kernels — lhs is array, rhs is array (paired)
        # or scalar (broadcast). Returns a fresh array with values
        # computed pair-by-pair.
        op = node.operator
        scalar = case op
                 when :".+"  then ->(a, b) { a + b }
                 when :".-"  then ->(a, b) { a - b }
                 when :".*"  then ->(a, b) { a * b }
                 when :"./"  then ->(a, b) { b == 0 ? 0 : a / b }
                 when :".|"  then ->(a, b) { a.to_i | b.to_i }
                 when :".&"  then ->(a, b) { a.to_i & b.to_i }
                 when :".^"  then ->(a, b) { a.to_i ^ b.to_i }
                 when :".<<" then ->(a, b) { a.to_i << b.to_i }
                 when :".>>" then ->(a, b) { a.to_i >> b.to_i }
                 end
        runtime_error("dot-prefix operator requires array on the left", node: node) unless left.is_a?(Array)
        if right.is_a?(Array)
          runtime_error("elementwise op: lhs.size != rhs.size", node: node) unless left.size == right.size
          left.each_with_index.map { |v, i| scalar.call(v, right[i]) }
        else
          left.map { |v| scalar.call(v, right) }
        end
      else runtime_error("unknown operator: #{node.operator}", node: node)
      end
    end

    def convert_quantity_pipe(qty, node)
      load_quantity_support
      convert_quantity_pipe(qty, node)
    end

    def visit_global_var(node)
      if node.name.to_s.match?(/\A\$\d+\z/)
        return @globals[node.name.to_s]
      end
      @globals[node.name]
    end

    def visit_instance_var(node)
      obj = @self_stack.last
      runtime_error("instance variable '#{node.name}' outside object", node: node) unless obj.is_a?(Runtime::WObject)
      obj.instance_vars[node.name]
    end

    def visit_class_var(node)
      w_class = find_current_class
      runtime_error("class variable '#{node.name}' outside class", node: node) unless w_class
      w_class.class_vars[node.name]
    end

    def visit_self(node)
      @self_stack.last
    end

    def visit_assign(node)
      value = apply_type_hint(evaluate(node.value), node.type_hint)
      target = node.name

      if target.is_a?(Tungsten::AST::ArrayLiteral)
        values = value.is_a?(::Array) ? value : [value]
        splat_index = target.list.index { |t| t.is_a?(Tungsten::AST::Splat) }

        if splat_index
          targets = target.list
          remaining = values.dup
          post_count = targets.size - splat_index - 1

          targets.each_with_index do |t, i|
            if i < splat_index
              assign_target(t, remaining.shift, node)
            elsif i == splat_index
              assign_target(t.exp, remaining.shift([remaining.size - post_count, 0].max), node)
            else
              assign_target(t, remaining.shift, node)
            end
          end
        else
          target.list.each_with_index do |t, i|
            assign_target(t, values[i], node)
          end
        end
      else
        assign_target(target, value, node)
      end

      value
    end

    def apply_type_hint(value, hint)
      return value unless hint && value.is_a?(Integer)

      case hint.to_s
      when "u64"
        wrap_unsigned_bits(value, 64)
      when "i64"
        wrap_signed_bits(value, 64)
      when "u128"
        wrap_unsigned_bits(value, 128)
      when "i128"
        wrap_signed_bits(value, 128)
      else
        value
      end
    end

    def wrap_unsigned_bits(value, bits)
      modulus = 1 << bits
      wrapped = value % modulus
      wrapped += modulus if wrapped.negative?
      wrapped
    end

    def wrap_signed_bits(value, bits)
      modulus = 1 << bits
      wrapped = wrap_unsigned_bits(value, bits)
      sign_bit = 1 << (bits - 1)
      wrapped >= sign_bit ? wrapped - modulus : wrapped
    end

    def find_current_class
      @self_stack.reverse_each do |obj|
        return obj if obj.is_a?(Runtime::WClass)
        return obj.w_class if obj.is_a?(Runtime::WObject) && obj.respond_to?(:w_class)
      end
      nil
    end

    def assign_target(target, value, node)
      if target.is_a?(Tungsten::AST::InstanceVar)
        name = target.name.to_s
        obj = @self_stack.last
        runtime_error("instance variable '#{name}' outside object", node: node) unless obj.is_a?(Runtime::WObject)
        obj.set_ivar(name, value)
      elsif target.is_a?(Tungsten::AST::ClassVar)
        w_class = find_current_class
        runtime_error("class variable '#{target.name}' outside class", node: node) unless w_class
        w_class.class_vars[target.name.to_s] = value
      elsif target.is_a?(Tungsten::AST::GlobalVar)
        @globals[target.name.to_s] = value
      elsif target.is_a?(Tungsten::AST::Var) && target.cached_layout_shape == @env.layout_shape
        @env.set_slot(target.cached_slot, value)
      elsif target.is_a?(Tungsten::AST::Var) && (ce = target.cached_env) && ce.equal?(@env)
        # Inline cache hit for assignment — same env, same slot
        ce.set_slot(target.cached_slot, value)
      elsif target.is_a?(Tungsten::AST::Var)
        name = target.name.to_s
        @env.set(name, value)
        if (idx = @env.slot_index(name))
          target.cached_env = @env
          target.cached_slot = idx
          target.cached_layout_shape = @env.layout_shape
        end
      else
        @env.set(target.name.to_s, value)
      end
    end

    def visit_assign_op(node)
      target = node.name
      right = evaluate(node.value)

      if target.is_a?(Tungsten::AST::Var) && target.cached_layout_shape == @env.layout_shape
        slot = target.cached_slot
        current = @env.get_slot(slot)
        result = case node.operator
                 when :+  then current + right
                 when :-  then current - right
                 when :*  then current * right
                 when :/  then current / right
                 when :%  then current % right
                 when :** then current ** right
                 else runtime_error("unknown compound operator: #{node.operator}", node: node)
                 end
        @env.set_slot(slot, result)
        return result
      end

      if target.is_a?(Tungsten::AST::Var) && (ce = target.cached_env) && ce.equal?(@env)
        slot = target.cached_slot
        current = ce.get_slot(slot)
        result = case node.operator
                 when :+  then current + right
                 when :-  then current - right
                 when :*  then current * right
                 when :/  then current / right
                 when :%  then current % right
                 when :** then current ** right
                 else runtime_error("unknown compound operator: #{node.operator}", node: node)
                 end
        ce.set_slot(slot, result)
        return result
      end

      if target.is_a?(Tungsten::AST::InstanceVar)
        name = target.name.to_s
        obj = @self_stack.last
        runtime_error("instance variable '#{name}' outside object", node: node) unless obj.is_a?(Runtime::WObject)
        current = obj.get_ivar(name)
      elsif target.is_a?(Tungsten::AST::ClassVar)
        name = target.name.to_s
        w_class = find_current_class
        runtime_error("class variable '#{name}' outside class", node: node) unless w_class
        current = w_class.class_vars[name]
      elsif target.is_a?(Tungsten::AST::GlobalVar)
        name = target.name.to_s
        current = @globals[name]
      else
        name = target.name.to_s
        current = if (ce = target.cached_env) && ce.equal?(@env)
                    ce.get_slot(target.cached_slot)
                  else
                    resolved = resolve_cached_local(target, name)
                    if resolved.equal?(Environment::UNDEFINED)
                      runtime_error("Undefined variable '#{name}'", node: node, length: name.length)
                    end
                    resolved
                  end
      end

      result = case node.operator
               when :+  then current + right
               when :-  then current - right
               when :*  then current * right
               when :/  then current / right
               when :%  then current % right
               when :** then current ** right
               else runtime_error("unknown compound operator: #{node.operator}", node: node)
               end

      if target.is_a?(Tungsten::AST::InstanceVar)
        obj.set_ivar(name, result)
      elsif target.is_a?(Tungsten::AST::ClassVar)
        w_class.class_vars[name] = result
      elsif target.is_a?(Tungsten::AST::GlobalVar)
        @globals[name] = result
      elsif (ce = target.cached_env)
        # AssignOp is read-modify-write: write back to whichever env the
        # read found the slot in (may be an outer captured scope across a
        # barrier). The cache was just refreshed by resolve_cached_local
        # in the read path above.
        ce.set_slot(target.cached_slot, result)
      else
        @env.set(name, result)
      end

      result
    end

    def visit_print(node)
      node.args.each do |arg|
        value = evaluate(arg)
        $stdout.puts(w_to_s(value))
      end
      nil
    end

    def visit_write(node)
      node.args.each do |arg|
        value = evaluate(arg)
        $stdout.print(w_to_s(value))
      end
      nil
    end

    def visit_class_def(node)
      # Class re-open: if a class with this name already exists, merge the
      # new methods/accessors/traits into it. First-declaration wins for
      # superclass; last-registered method wins on name collision
      # (handled by define_method's hash-keyed storage).
      existing = @classes[node.name]
      if existing
        w_class = existing
      else
        superclass = if node.superclass
          # An explicit `< Super` wins; any `[role]` alongside it (e.g.
          # `< Node [slab]`) is a compiler annotation the interpreter ignores.
          @classes[node.superclass]
        elsif node.class_role
          # Legacy form: a bare `[Role]` that resolves to a class names the
          # superclass (e.g. `+ Foo [Global]`). A role that doesn't resolve to
          # a class is a compiler-only annotation (e.g. a standalone `[slab]`)
          # and leaves the class with no superclass.
          role_name = node.class_role
          resolved = begin; @env.get(role_name); rescue; nil; end
          resolved ||= @classes[role_name]
          resolved.is_a?(Runtime::WClass) ? resolved : (resolved && @classes[resolved.to_s])
        end

        w_class = Runtime::WClass.new(node.name, superclass)
        @classes[node.name] = w_class
      end

      effective_body = expand_on_guards(node.body)

      @self_stack.push(w_class)
      begin
        effective_body.each do |expr|
          case expr
          when Tungsten::AST::Def
            body = register_trailing_accessors(expr, w_class)
            w_method = Runtime::WMethod.new(expr.name, expr.args, body, w_class, splat_index: expr.splat_index)
            w_class.define_method(expr.name.to_s, w_method)
          when Tungsten::AST::Is
            trait = @modules[expr.trait_name]
            runtime_error("unknown trait '#{expr.trait_name}'", node: expr) unless trait
            w_class.include_trait(trait)
          when Tungsten::AST::Call
            if expr.obj.nil? && %w[ro rw].include?(expr.name.to_s) && expr.args&.first.is_a?(Tungsten::AST::Symbol)
              define_accessor(w_class, expr)
            else
              evaluate(expr)
            end
          else
            evaluate(expr)
          end
        end
      ensure
        @self_stack.pop
      end

      w_class
    end

    # `-> new(@x, @y) ro` — a bare ro/rw body statement on a method with
    # @-bound params generates accessors for those params (readers for ro,
    # readers + writers for rw); the marker itself is stripped from the
    # body. Mirrors the compiled tree-walker's register_trailing_accessors.
    # Returns the (possibly rewritten) method body.
    def register_trailing_accessors(node, w_class)
      body = node.body
      ivar_args = node.args ? node.args.select { |a| a.is_a?(AST::Arg) && a.ivar } : []
      return body if ivar_args.empty? || body.nil?

      statements = body.is_a?(AST::List) ? body.list : [body]
      marker = nil
      kept = []
      statements.each do |st|
        if marker.nil? && accessor_marker?(st)
          marker = st.name.to_s
        else
          kept << st
        end
      end
      return body unless marker

      writable = marker == "rw"
      ivar_args.each do |arg|
        field = arg.name.to_s
        ivar = "@#{field}"

        unless w_class.methods.key?(field)
          getter = Runtime::WMethod.new(field, nil, AST::InstanceVar.new(ivar), w_class)
          w_class.define_method(field, getter)
        end

        next unless writable

        setter_name = "#{field}="
        next if w_class.methods.key?(setter_name)

        setter_body = AST::Assign.new(AST::InstanceVar.new(ivar), AST::Var.new("value"))
        setter = Runtime::WMethod.new(setter_name, [AST::Arg.new("value")], setter_body, w_class)
        w_class.define_method(setter_name, setter)
      end

      AST::List.from(kept)
    end

    # A bare `ro` / `rw` statement: a Var read or a receiverless,
    # argument-less Call by that name.
    def accessor_marker?(st)
      case st
      when AST::Var
        %w[ro rw].include?(st.name.to_s)
      when AST::Call
        st.obj.nil? && %w[ro rw].include?(st.name.to_s) && (st.args.nil? || st.args.empty?)
      else
        false
      end
    end

    def define_accessor(w_class, expr)
      writable = expr.name.to_s == "rw"

      expr.args.each do |arg|
        field = arg.is_a?(Tungsten::AST::Symbol) ? arg.value.to_s.delete_prefix(":") : arg.to_s
        ivar = "@#{field}"

        # Getter: -> field; @field
        getter_body = if expr.default
          AST::List.new([
            AST::If.new(
              AST::BinaryOp.new(AST::InstanceVar.new(ivar), :==, AST::Nil.new),
              AST::Assign.new(AST::InstanceVar.new(ivar), expr.default),
              nil
            ),
            AST::InstanceVar.new(ivar)
          ])
        else
          AST::InstanceVar.new(ivar)
        end
        getter = Runtime::WMethod.new(field, nil, getter_body, w_class)
        w_class.define_method(field, getter)

        next unless writable

        # Setter: -> field=(value); @field = value
        setter_arg = AST::Arg.new("value")
        setter_body = AST::Assign.new(AST::InstanceVar.new(ivar), AST::Var.new("value"))
        setter = Runtime::WMethod.new("#{field}=", [setter_arg], setter_body, w_class)
        w_class.define_method("#{field}=", setter)
      end
    end

    def visit_def(node)
      node.closure_env = @env
      @env.set(node.name.to_s, node) if node.name
      node
    end

    def visit_fn(node)
      node.closure_env = @env

      # Build name_map: self-name → "SELF", arg names → positional, known fn's → SHA
      name_map = {}
      name_map[node.name] = "SELF" if node.name
      node.args&.each_with_index { |arg, i| name_map[arg.name] = "arg_#{i}" }
      @fn_shas&.each { |fn_name, sha| name_map[fn_name] = "function_#{sha}" }

      sha = node.ast_sha(name_map)

      # Track SHA for downstream fn's
      @fn_shas ||= {}
      @fn_shas[node.name] = sha if node.name

      # Load persistent cache (silent degrade on any error)
      cache_path = File.join(Dir.home, ".tungsten", "cache", "#{sha}.memo")
      memo = begin
        File.exist?(cache_path) ? Marshal.load(File.binread(cache_path)) : {}
      rescue
        {}
      end
      memo = {} unless memo.is_a?(Hash)

      node.memo_cache = memo
      node.cache_path = cache_path
      @env.set(node.name.to_s, node) if node.name
      node
    end

    def visit_call(node)
      if node.obj
        recv = evaluate(node.obj)
        block = node.block

        if !@profile_enabled && !block && recv.is_a?(Runtime::WObject) &&
           node.name != "-" && node.name != "+" && (!node.args || node.args.empty?)
          owner = recv.w_class
          method = resolve_w_method(node, owner, node.name)
          if method
            if (method.params || EMPTY_ARGS).empty? && (plan = cached_simple_w_method_plan(method))
              result = execute_simple_w_method_plan(recv, plan)
              return result unless result.equal?(SIMPLE_W_METHOD_UNSUPPORTED)
            end
          end
        end

        if @profile_enabled
          profile_visit_call(
            if recv.is_a?(Runtime::WObject)
              "#{recv.w_class.name}##{node.name}"
            elsif recv.is_a?(Runtime::WClass)
              "#{recv.name}.#{node.name}"
            else
              "#{tungsten_class_name(recv)}##{node.name}"
            end
          )
        end
        block.closure_env = @env if block

        if recv.is_a?(Quantity) && node.name == "of"
          substance = evaluate(node.args[0]).to_s
          substance = "burned #{substance}" if recv.instance_variable_get(:@burned)
          return substance_mass(recv, substance)
        end

        case node.name
        when "-" then return -recv
        when "+" then return +recv
        end

        if recv.is_a?(Runtime::WObject)
          owner = recv.w_class
          method = resolve_w_method(node, owner, node.name)
          if method
            # Implicit construction from the receiver's class: a one-param
            # method called with N>1 args wraps them in receiver.class.new(...)
            # when that constructor takes N args —
            # p.distance(2, 3, 4) ≡ p.distance(Point.new(2, 3, 4)).
            if node.args && node.args.size > 1 &&
               (method.params || EMPTY_ARGS).size == 1 && method.splat_index.nil?
              constructor = owner.lookup_method("new")
              if constructor && (constructor.params || EMPTY_ARGS).size == node.args.size
                instance = instantiate_from_nodes(owner, node.args)
                return call_w_method(recv, method, [instance], block, call_node: node)
              end
            end
            call_w_method_from_nodes(recv, method, node.args, block, call_node: node)
          elsif (method_builtin = @method_builtins[node.name])
            args = evaluate_args(node.args)
            invoke_method_builtin(method_builtin, recv, args, block)
          else
            result = call_builtin_from_nodes(recv, node.name, node.args)
            if result.equal?(NO_DIRECT_CALL)
              args = evaluate_args(node.args)
              result = call_builtin(recv, node.name, args)
            end
            if result.nil? && !BUILTIN_METHODS.include?(node.name)
              runtime_error("undefined method '#{node.name}' for #{recv}", node: node, length: node.name.to_s.length)
            end
            result
          end
        elsif recv.is_a?(Runtime::WClass)
          if recv.name == "Tungsten" && node.name == "root" && no_call_args?(node.args)
            root_builtin = @builtins["__project_root"]
            Tungsten::PathValue.new(root_builtin ? root_builtin.call(nil, EMPTY_ARGS, nil) : Dir.pwd)
          elsif node.name == "new"
            instantiate_from_nodes(recv, node.args)
          elsif node.name == "methods"
            (recv.methods.keys + @method_builtins.keys + BUILTIN_METHODS).uniq.sort.map(&:to_sym)
          elsif node.name == "class"
            class_class_singleton
          elsif node.name == "class_name"
            "Class"
          elsif node.name == "name"
            recv.name
          else
            method = resolve_w_method(node, recv, node.name)
            if method
              begin
                call_w_method_from_nodes(recv, method, node.args, block, call_node: node)
              rescue Tungsten::Error => e
                # ccall methods fail in interpreter — try Ruby class fallback
                ruby_class = ruby_constant_for_w_class(recv.name)
                if !hidden_ruby_object_method?(node.name) && ruby_class&.respond_to?(node.name)
                  args = evaluate_args(node.args)
                  return ruby_class.send(node.name, *args)
                end
                raise
              end
            else
              # ccall-backed core class methods (Math.sqrt, Math.exp, …)
              # have no .w body in the interpreter — try Ruby class fallback
              ruby_class = ruby_constant_for_w_class(recv.name)
              if !hidden_ruby_object_method?(node.name) && ruby_class&.respond_to?(node.name)
                args = evaluate_args(node.args)
                return ruby_class.send(node.name, *args)
              end
              runtime_error("undefined method '#{node.name}' for #{recv}", node: node, length: node.name.to_s.length)
            end
          end
        else
          if (w_class = primitive_runtime_class(recv))
            method = resolve_w_method(node, w_class, node.name)
            if method
              begin
                return call_w_method_from_nodes(recv, method, node.args, block, call_node: node)
              rescue Tungsten::Error
                if !hidden_ruby_object_method?(node.name) && recv.respond_to?(node.name)
                  args = evaluate_args(node.args)
                  return recv.public_send(node.name, *args)
                end
                raise
              end
            end
          end

          direct_result = call_primitive_method_from_nodes(recv, node.name, node.args, block)
          return direct_result unless direct_result.equal?(NO_DIRECT_CALL)

          if TYPE_INFO_METHODS[node.name]
            tungsten_type_info(recv, node.name)
          elsif (method_builtin = @method_builtins[node.name])
            args = evaluate_args(node.args)
            invoke_method_builtin(method_builtin, recv, args, block)
          elsif recv.nil?
            runtime_error("undefined method '#{node.name}' for nil", node: node, length: node.name.to_s.length)
          elsif hidden_ruby_object_method?(node.name)
            runtime_error("undefined method '#{node.name}' for #{recv}", node: node, length: node.name.to_s.length)
          else
            direct_result = call_ruby_method_from_nodes(recv, node.name, node.args, block)
            return direct_result unless direct_result.equal?(NO_DIRECT_CALL)

            args = evaluate_args(node.args)
            if block
              recv.public_send(node.name, *args) { |*bargs| invoke_block(block, bargs) }
            else
              recv.public_send(node.name, *args)
            end
          end
        end
      else
        name = node.name.to_s

        # Class constructor call: Dog("Rex") → Dog.new("Rex")
        if (w_class = @classes[name])
          profile_visit_call("#{name}.new") if @profile_enabled
          return instantiate_from_nodes(w_class, node.args)
        end

        # Module method call: Greetable.method
        if (w_module = @modules[name])
          profile_visit_call("module #{name}") if @profile_enabled
          return w_module
        end

        local_miss_cached = !@profile_enabled &&
                            (miss_shape = node.cached_local_miss_shape) &&
                            miss_shape == @env.lookup_shape

        if local_miss_cached
          self_obj = @self_stack.last
          if self_obj.is_a?(Runtime::WClass)
            method = resolve_w_method(node, self_obj, name)
            if method
              block = node.block
              block.closure_env = @env if block
              return call_w_method_from_nodes(self_obj, method, node.args, block, call_node: node)
            end
          elsif self_obj.is_a?(Runtime::WObject)
            owner = self_obj.w_class
            method = resolve_w_method(node, owner, name)
            if method
              block = node.block
              block.closure_env = @env if block
              return call_w_method_from_nodes(self_obj, method, node.args, block, call_node: node)
            end
          end
        end

        func = local_miss_cached ? Environment::UNDEFINED : resolve_cached_local(node, name)

        unless func.equal?(Environment::UNDEFINED)
          if func.is_a?(Tungsten::AST::Def)
            profile_visit_call("local #{name}") if @profile_enabled
            block = node.block
            block.closure_env = @env if block
            return call_method(func, node.args, block)
          end
        end

        if (builtin = @builtins[name])
          profile_visit_call("builtin #{name}") if @profile_enabled
          block = node.block
          block.closure_env = @env if block
          args = evaluate_args(node.args)
          return invoke_builtin(builtin, nil, args, block)
        end

        # Implicit self dispatch: bare method call inside a class or instance method
        self_obj = @self_stack.last
        if self_obj.is_a?(Runtime::WClass)
          method = resolve_w_method(node, self_obj, name)
          if method
            profile_visit_call("#{self_obj.name}##{name}") if @profile_enabled
            if !@profile_enabled && @env.barrier? && !@env.defined_locally_or_in_scope?(name)
              node.cached_local_miss_shape = @env.lookup_shape
            end
            block = node.block
            block.closure_env = @env if block
            return call_w_method_from_nodes(self_obj, method, node.args, block, call_node: node)
          end
        elsif self_obj.is_a?(Runtime::WObject)
          owner = self_obj.w_class
          method = resolve_w_method(node, owner, name)
          if method
            profile_visit_call("#{owner.name}##{name}") if @profile_enabled
            if !@profile_enabled && @env.barrier? && !@env.defined_locally_or_in_scope?(name)
              node.cached_local_miss_shape = @env.lookup_shape
            end
            block = node.block
            block.closure_env = @env if block
            return call_w_method_from_nodes(self_obj, method, node.args, block, call_node: node)
          end
        end

        # Δ-prefixed identifier: an UNDEFINED `Δx` reads as `x - x'`
        # (x - @1.x) — the prime-notation delta. Mirrors the compiled
        # lowering's lower_var fallback; a real Δx variable or method
        # resolves through the normal paths above and never reaches this.
        if !node.has_parens && name.to_s.start_with?("Δ") && name.to_s.length > 1
          base = name.to_s.delete_prefix("Δ")
          delta = Tungsten::AST::BinaryOp.new(
            Tungsten::AST::Call.new(nil, base),
            :-,
            Tungsten::AST::Call.new(Tungsten::AST::Var.new("__arg1"), base)
          )
          return evaluate(delta)
        end

        if node.has_parens
          runtime_error("undefined method '#{name}'", node: node, length: name.length)
        else
          runtime_error("undefined local variable or method '#{name}'", node: node, length: name.length)
        end
      end
    end

    def call_method(func, arg_nodes, block = nil)
      if !@profile_enabled && !block
        intrinsic_result = call_function_intrinsic_from_nodes(func, arg_nodes)
        return intrinsic_result unless intrinsic_result.equal?(NO_DIRECT_CALL)
      end

      if !@profile_enabled && (plan = cached_simple_method_plan(func))
        result = execute_simple_method_plan_from_nodes(plan, arg_nodes)
        return result unless result.equal?(SIMPLE_METHOD_UNSUPPORTED)
      end

      closure_env = func.closure_env || @env
      params = func.args || EMPTY_ARGS
      method_env = new_param_env(closure_env, params, func, barrier: true)

      if bind_exact_small_args_from_nodes(method_env, params, arg_nodes, func.splat_index, func.memo_cache)
        return execute_callable_body(func, method_env, block)
      end

      args = evaluate_args(arg_nodes)

      # Memoization for pure functions (Fn nodes)
      memo = func.memo_cache
      if memo && memo.key?(args)
        memo[args] = memo.delete(args) # LRU: move to end on hit
        return memo[args]
      end

      bind_params(method_env, params, args, func.splat_index)

      if func.splat_index.nil? && args.size > params.size
        raise Tungsten::Error, "too many arguments for '#{func.name}' (#{args.size} for #{params.size})"
      end

      result = execute_callable_body(func, method_env, block)

      if memo
        memo[args] = result

        # LRU eviction: Ruby Hash is insertion-ordered, shift removes oldest
        memo.shift while memo.size > MEMO_MAX_SIZE

        # Persist (silent degrade on any error)
        if (cache_path = func.cache_path)
          begin
            require "fileutils"
            FileUtils.mkdir_p(File.dirname(cache_path))
            File.binwrite(cache_path, Marshal.dump(memo))
          rescue
            # Cache write failure is non-fatal — in-memory memo still works
          end
        end
      end

      result
    end

    def call_function_intrinsic_from_nodes(func, arg_nodes)
      case func.name.to_s
      when "wyhash64_string"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        text = direct_arg_value(arg)
        text.is_a?(::String) ? wyhash64_string_value(text) : NO_DIRECT_CALL
      when "is_keyword?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        TUNGSTEN_KEYWORDS[direct_arg_value(arg)] == true
      when "is_type_name?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        TUNGSTEN_TYPE_NAME_WORDS[direct_arg_value(arg)] == true
      when "is_value_type?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        LEXER_VALUE_TOKEN_TYPES[direct_arg_value(arg)] == true
      when "lc_cp"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        (direct_arg_value(arg) >> 18) & 0x1FFFFF
      when "is_digit?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        ((direct_arg_value(arg) >> 7) & 15) != 15
      when "is_lower?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        cp = (direct_arg_value(arg) >> 18) & 0x1FFFFF
        cp >= 97 && cp <= 122
      when "is_upper?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        cp = (direct_arg_value(arg) >> 18) & 0x1FFFFF
        cp >= 65 && cp <= 90
      when "is_alpha?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        cp = (direct_arg_value(arg) >> 18) & 0x1FFFFF
        (cp >= 97 && cp <= 122) || (cp >= 65 && cp <= 90)
      when "is_ident_start?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        (direct_arg_value(arg) & 64) != 0
      when "is_ident_char?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        (direct_arg_value(arg) & 32) != 0
      when "is_name_char?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        lc = direct_arg_value(arg)
        cp = (lc >> 18) & 0x1FFFFF
        (lc & 32) != 0 || (cp >= 65 && cp <= 90)
      when "is_currency_suffix?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        ch = direct_arg_value(arg)
        ch == "¢" || ch == "円" || ch == "元"
      else
        NO_DIRECT_CALL
      end
    end

    def cached_simple_method_plan(func)
      if func.instance_variable_defined?(:@simple_method_plan)
        plan = func.instance_variable_get(:@simple_method_plan)
        return nil if plan.equal?(SIMPLE_METHOD_UNSUPPORTED)

        return plan
      end

      plan = build_simple_method_plan(func) || SIMPLE_METHOD_UNSUPPORTED
      func.instance_variable_set(:@simple_method_plan, plan)
      plan.equal?(SIMPLE_METHOD_UNSUPPORTED) ? nil : plan
    end

    def build_simple_method_plan(func)
      return nil if func.splat_index || func.memo_cache

      params = func.args || EMPTY_ARGS
      return nil if params.any?(&:default)

      body = func.body.list
      return nil unless body.length == 1

      param_slots = {}
      params.each_with_index { |param, i| param_slots[param.name] = i }
      expression = simple_method_expression(body[0], param_slots)
      return nil unless expression

      [params.length, expression]
    end

    def simple_method_expression(node, param_slots)
      case node
      when AST::Var
        slot = param_slots[node.name]
        return nil unless slot

        [:arg, slot]
      when AST::Int, AST::Float, AST::Decimal
        [:literal, node.value]
      when AST::BinaryOp
        return nil unless SIMPLE_WHILE_ARITH_OPS[node.operator] || SIMPLE_WHILE_COMPARE_OPS[node.operator]

        left = simple_method_expression(node.left, param_slots)
        right = simple_method_expression(node.right, param_slots)
        return nil unless left && right

        [:binary, node.operator, left, right]
      end
    end

    def execute_simple_method_plan_from_nodes(plan, arg_nodes)
      param_count, expression = plan
      arg_count = arg_nodes ? arg_nodes.length : 0
      return SIMPLE_METHOD_UNSUPPORTED unless arg_count == param_count

      case param_count
      when 0
        return simple_method_value3(nil, nil, nil, expression)
      when 1
        arg0 = simple_call_arg_value(arg_nodes[0])
        return SIMPLE_METHOD_UNSUPPORTED unless arg0.is_a?(Numeric)

        return simple_method_value3(arg0, nil, nil, expression)
      when 2
        arg0 = simple_call_arg_value(arg_nodes[0])
        arg1 = simple_call_arg_value(arg_nodes[1])
        return SIMPLE_METHOD_UNSUPPORTED unless arg0.is_a?(Numeric) && arg1.is_a?(Numeric)

        return simple_method_value3(arg0, arg1, nil, expression)
      when 3
        arg0 = simple_call_arg_value(arg_nodes[0])
        arg1 = simple_call_arg_value(arg_nodes[1])
        arg2 = simple_call_arg_value(arg_nodes[2])
        return SIMPLE_METHOD_UNSUPPORTED unless arg0.is_a?(Numeric) && arg1.is_a?(Numeric) && arg2.is_a?(Numeric)

        return simple_method_value3(arg0, arg1, arg2, expression)
      end

      args = Array.new(arg_count)
      i = 0
      while i < arg_count
        value = simple_call_arg_value(arg_nodes[i])
        return SIMPLE_METHOD_UNSUPPORTED unless value.is_a?(Numeric)

        args[i] = value
        i += 1
      end

      simple_method_value(args, expression)
    end

    def simple_call_arg_value(node)
      case node
      when AST::Var
        if (ce = node.cached_env) && ce.equal?(@env)
          ce.get_slot(node.cached_slot)
        elsif (slot = @env.slot_index(node.name))
          node.cached_env = @env
          node.cached_slot = slot
          @env.get_slot(slot)
        else
          SIMPLE_METHOD_UNSUPPORTED
        end
      when AST::Int, AST::Float, AST::Decimal
        node.value
      when AST::BinaryOp
        return SIMPLE_METHOD_UNSUPPORTED unless SIMPLE_WHILE_ARITH_OPS[node.operator]

        left = simple_call_arg_value(node.left)
        right = simple_call_arg_value(node.right)
        return SIMPLE_METHOD_UNSUPPORTED unless left.is_a?(Numeric) && right.is_a?(Numeric)

        simple_while_arithmetic(left, node.operator, right)
      else
        SIMPLE_METHOD_UNSUPPORTED
      end
    end

    def simple_method_value(args, expr)
      case expr[0]
      when :arg
        args[expr[1]]
      when :literal
        expr[1]
      when :binary
        left = simple_method_value(args, expr[2])
        right = simple_method_value(args, expr[3])
        if SIMPLE_WHILE_ARITH_OPS[expr[1]]
          simple_while_arithmetic(left, expr[1], right)
        else
          simple_while_compare(left, expr[1], right)
        end
      end
    end

    def simple_method_value3(arg0, arg1, arg2, expr)
      case expr[0]
      when :arg
        case expr[1]
        when 0 then arg0
        when 1 then arg1
        when 2 then arg2
        end
      when :literal
        expr[1]
      when :binary
        left = simple_method_value3(arg0, arg1, arg2, expr[2])
        right = simple_method_value3(arg0, arg1, arg2, expr[3])
        if SIMPLE_WHILE_ARITH_OPS[expr[1]]
          simple_while_arithmetic(left, expr[1], right)
        else
          simple_while_compare(left, expr[1], right)
        end
      end
    end

    def simple_method_numeric_expression?(expr)
      case expr[0]
      when :arg
        true
      when :literal
        expr[1].is_a?(Numeric)
      when :binary
        SIMPLE_WHILE_ARITH_OPS[expr[1]] &&
          simple_method_numeric_expression?(expr[2]) &&
          simple_method_numeric_expression?(expr[3])
      else
        false
      end
    end

    def visit_yield(node)
      runtime_error("yield called without a block", node: node) unless @current_block

      invoke_block_from_nodes(@current_block, node.args)
    end

    def invoke_block(block, args)
      closure_env = block.closure_env || @env
      params = block.args || EMPTY_ARGS
      if params.empty? && args.any?
        free_vars = block.free_var_cache ||= collect_free_vars(block.body, closure_env)
        block_env = new_free_var_env(closure_env, block, free_vars)
        free_vars.each_index do |i|
          break if i >= args.length
          block_env.set_slot(i, args[i])
        end
      else
        block_env = new_param_env(closure_env, params, block)
        params.each_index do |i|
          block_env.set_slot(i, args[i])
        end
      end

      execute_bound_block(block, block_env)
    end

    def invoke_block_from_nodes(block, arg_nodes)
      if !@profile_enabled && (plan = cached_simple_block_plan(block))
        result = execute_simple_block_plan_from_nodes(block, plan, arg_nodes)
        return result unless result.equal?(SIMPLE_BLOCK_UNSUPPORTED)
      end

      closure_env = block.closure_env || @env
      params = block.args || EMPTY_ARGS
      block_env = new_param_env(closure_env, params, block)

      if bind_exact_small_args_from_nodes(block_env, params, arg_nodes, nil, nil)
        return execute_bound_block(block, block_env)
      end

      args = evaluate_args(arg_nodes)
      invoke_block(block, args)
    end

    def cached_simple_block_plan(block)
      if block.instance_variable_defined?(:@simple_block_plan)
        plan = block.instance_variable_get(:@simple_block_plan)
        return nil if plan.equal?(SIMPLE_BLOCK_UNSUPPORTED)

        return plan
      end

      plan = build_simple_block_plan(block) || SIMPLE_BLOCK_UNSUPPORTED
      block.instance_variable_set(:@simple_block_plan, plan)
      plan.equal?(SIMPLE_BLOCK_UNSUPPORTED) ? nil : plan
    end

    def build_simple_block_plan(block)
      return nil if Interpreter.body_has_next?(block.body)

      params = block.args || EMPTY_ARGS
      return nil if params.length > 3 || params.any?(&:default)

      param_slots = EMPTY_SLOT_NAMES
      unless params.empty?
        param_slots = {}
        params.each_with_index { |param, i| param_slots[param.name] = i }
      end

      env_names = {}
      nodes = block.body.is_a?(AST::List) ? block.body.list : [block.body]
      return nil if nodes.empty?

      steps = []
      nodes.each do |node|
        step = simple_block_statement(node, param_slots, env_names)
        return nil unless step

        steps << step
      end

      [params.length, steps.length == 1 ? steps[0] : [:sequence, steps], env_names.keys]
    end

    def simple_block_statement(node, param_slots, env_names)
      case node
      when AST::Assign
        return nil unless node.name.is_a?(AST::Var)
        return nil if node.type_hint
        return nil if param_slots.key?(node.name.name)

        expr = simple_block_expression(node.value, param_slots, env_names)
        expr && [:assign_env, node.name.name, expr]
      when AST::AssignOp
        return nil unless node.name.is_a?(AST::Var)
        return nil unless SIMPLE_WHILE_ARITH_OPS[node.operator]
        return nil if param_slots.key?(node.name.name)

        expr = simple_block_expression(node.value, param_slots, env_names)
        expr && [:assign_env_op, node.name.name, node.operator, expr]
      else
        expr = simple_block_expression(node, param_slots, env_names)
        expr && [:value, expr]
      end
    end

    def simple_block_expression(node, param_slots, env_names)
      case node
      when AST::Var
        if (slot = param_slots[node.name])
          [:arg, slot]
        else
          env_names[node.name] = true
          [:env, node.name]
        end
      when AST::Int, AST::Float, AST::Decimal, AST::StringLiteral, AST::Boolean
        [:literal, node.value]
      when AST::Char
        [ :literal, Tungsten::CharValue.new(node.value) ]
      when AST::Nil
        [:literal, nil]
      when AST::BinaryOp
        return nil unless SIMPLE_WHILE_ARITH_OPS[node.operator] || SIMPLE_WHILE_COMPARE_OPS[node.operator]

        left = simple_block_expression(node.left, param_slots, env_names)
        right = simple_block_expression(node.right, param_slots, env_names)
        return nil unless left && right

        [:binary, node.operator, left, right]
      end
    end

    def execute_simple_block_plan_from_nodes(block, plan, arg_nodes)
      param_count, steps, env_names = plan
      arg_count = small_arg_length_without_splat(arg_nodes)
      return SIMPLE_BLOCK_UNSUPPORTED unless arg_count == param_count

      closure_env = block.closure_env || @env
      return SIMPLE_BLOCK_UNSUPPORTED unless simple_block_env_ready?(closure_env, env_names)

      case arg_count
      when 0
        execute_simple_block_plan(closure_env, steps)
      when 1
        execute_simple_block_plan(closure_env, steps, evaluate(arg_nodes[0]))
      when 2
        execute_simple_block_plan(closure_env, steps, evaluate(arg_nodes[0]), evaluate(arg_nodes[1]))
      when 3
        execute_simple_block_plan(
          closure_env, steps, evaluate(arg_nodes[0]), evaluate(arg_nodes[1]), evaluate(arg_nodes[2])
        )
      else
        SIMPLE_BLOCK_UNSUPPORTED
      end
    end

    def execute_simple_block_plan(env, step, arg0 = nil, arg1 = nil, arg2 = nil)
      case step[0]
      when :value
        simple_block_value(env, step[1], arg0, arg1, arg2)
      when :assign_env
        value = simple_block_value(env, step[2], arg0, arg1, arg2)
        return value if value.equal?(SIMPLE_BLOCK_UNSUPPORTED)

        simple_block_env_assign(env, step[1], value)
      when :assign_env_op
        right = simple_block_value(env, step[3], arg0, arg1, arg2)
        return right if right.equal?(SIMPLE_BLOCK_UNSUPPORTED)

        simple_block_env_assign_op(env, step[1], step[2], right)
      when :sequence
        result = nil
        steps = step[1]
        i = 0
        while i < steps.length
          result = execute_simple_block_plan(env, steps[i], arg0, arg1, arg2)
          return result if result.equal?(SIMPLE_BLOCK_UNSUPPORTED)

          i += 1
        end
        result
      else
        SIMPLE_BLOCK_UNSUPPORTED
      end
    end

    def simple_block_value(env, expr, arg0 = nil, arg1 = nil, arg2 = nil)
      case expr[0]
      when :arg
        case expr[1]
        when 0 then arg0
        when 1 then arg1
        when 2 then arg2
        end
      when :env
        simple_block_env_value(env, expr[1])
      when :literal
        expr[1]
      when :binary
        left = simple_block_value(env, expr[2], arg0, arg1, arg2)
        return left if left.equal?(SIMPLE_BLOCK_UNSUPPORTED)

        right = simple_block_value(env, expr[3], arg0, arg1, arg2)
        return right if right.equal?(SIMPLE_BLOCK_UNSUPPORTED)

        if SIMPLE_WHILE_ARITH_OPS[expr[1]]
          simple_while_arithmetic(left, expr[1], right)
        else
          simple_while_compare(left, expr[1], right)
        end
      end
    end

    def simple_block_env_ready?(env, names)
      i = 0
      while i < names.length
        return false unless simple_block_env_bound?(env, names[i])

        i += 1
      end
      true
    end

    def simple_block_env_bound?(env, name)
      while env
        return true if env.slot_index(name)

        env = env.parent
      end
      false
    end

    def simple_block_env_value(env, name)
      while env
        if (idx = env.slot_index(name))
          return env.get_slot(idx)
        end

        env = env.parent
      end
      SIMPLE_BLOCK_UNSUPPORTED
    end

    def simple_block_env_assign(env, name, value)
      while env
        if (idx = env.slot_index(name))
          env.set_slot(idx, value)
          return value
        end

        env = env.parent
      end
      SIMPLE_BLOCK_UNSUPPORTED
    end

    def simple_block_env_assign_op(env, name, op, right)
      while env
        if (idx = env.slot_index(name))
          result = simple_while_arithmetic(env.get_slot(idx), op, right)
          env.set_slot(idx, result)
          return result
        end

        env = env.parent
      end
      SIMPLE_BLOCK_UNSUPPORTED
    end

    def execute_bound_block(block, env)
      old_env = @env
      @env = env
      begin
        catch_next_if_needed(block.body) { evaluate(block.body) }
      ensure
        @env = old_env
      end
    end

    def collect_free_vars(node, env)
      vars = []
      seen = {}
      walk_free_vars(node, env, vars, seen)
      vars
    end

    def walk_free_vars(node, env, vars, seen)
      return unless node

      case node
      when AST::Var
        name = node.name.to_s
        unless seen[name] || node.constant? || name.start_with?("@") || env.defined_locally_or_in_scope?(name)
          seen[name] = true
          vars << name
        end
      when AST::Assign
        walk_free_vars(node.value, env, vars, seen)
        seen[node.name.name.to_s] = true if node.name.is_a?(AST::Var)
      when AST::AssignOp
        walk_free_vars(node.value, env, vars, seen)
        walk_free_vars(node.name, env, vars, seen)
      when AST::Block
        # Don't descend into nested blocks
      else
        node.children { |child| walk_free_vars(child, env, vars, seen) }
      end
    end

    def call_w_method(recv, method, args, block = nil, call_node: nil)
      if !@profile_enabled && !block && args.empty? && (method.params || EMPTY_ARGS).empty? &&
         (plan = cached_simple_w_method_plan(method))
        result = execute_simple_w_method_plan(recv, plan)
        return result unless result.equal?(SIMPLE_W_METHOD_UNSUPPORTED)
      end

      params = method.params || EMPTY_ARGS
      method_env = new_param_env(@env, params, method, barrier: true)

      bind_params(method_env, params, args, method.splat_index)

      execute_bound_w_method(recv, method, method_env, block, call_node)
    end

    def call_w_method_from_nodes(recv, method, arg_nodes, block = nil, call_node: nil)
      if !@profile_enabled && !block
        result = call_self_hosted_parser_intrinsic_from_nodes(recv, method, arg_nodes)
        return result unless result.equal?(NO_DIRECT_CALL)
      end

      if !@profile_enabled && !block && (!arg_nodes || arg_nodes.empty?) && (method.params || EMPTY_ARGS).empty? &&
         (plan = cached_simple_w_method_plan(method))
        result = execute_simple_w_method_plan(recv, plan)
        return result unless result.equal?(SIMPLE_W_METHOD_UNSUPPORTED)
      end

      params = method.params || EMPTY_ARGS
      method_env = new_param_env(@env, params, method, barrier: true)

      if bind_exact_small_args_from_nodes(method_env, params, arg_nodes, method.splat_index, nil)
        return execute_bound_w_method(recv, method, method_env, block, call_node)
      end

      args = evaluate_args(arg_nodes)
      bind_params(method_env, params, args, method.splat_index)

      execute_bound_w_method(recv, method, method_env, block, call_node)
    end

    def cached_simple_w_method_plan(method)
      if method.instance_variable_defined?(:@simple_w_method_plan)
        plan = method.instance_variable_get(:@simple_w_method_plan)
        return nil if plan.equal?(SIMPLE_W_METHOD_UNSUPPORTED)

        return plan
      end

      plan = build_simple_w_method_plan(method) || SIMPLE_W_METHOD_UNSUPPORTED
      method.instance_variable_set(:@simple_w_method_plan, plan)
      plan.equal?(SIMPLE_W_METHOD_UNSUPPORTED) ? nil : plan
    end

    def build_simple_w_method_plan(method)
      params = method.params || EMPTY_ARGS
      return nil if method.splat_index

      param_slots = EMPTY_SLOT_NAMES
      unless params.empty?
        return nil if params.any?(&:default)

        param_slots = {}
        params.each_with_index { |param, i| param_slots[param.name] = i }
      end

      body = method.body
      nodes = body.is_a?(AST::List) ? body.list : [body]
      return nil if nodes.empty?

      steps = []
      nodes.each do |node|
        step = simple_w_method_statement(node, method, param_slots)
        return nil unless step

        steps << step
      end

      steps.length == 1 ? steps[0] : [:sequence, steps]
    end

    def simple_w_method_statement(node, method, param_slots)
      case node
      when AST::InstanceVar
        expr = simple_w_method_expression(node, param_slots)
        expr && [:value, expr]
      when AST::Assign
        return nil unless node.name.is_a?(AST::InstanceVar)
        return nil if node.type_hint

        expr = simple_w_method_expression(node.value, param_slots)
        expr && [:assign_ivar, node.name.name.to_s, expr]
      when AST::AssignOp
        return nil unless node.name.is_a?(AST::InstanceVar)
        return nil unless SIMPLE_WHILE_ARITH_OPS[node.operator]

        name = node.name.name.to_s
        expr = simple_w_method_expression(node.value, param_slots)
        expr && [:assign_ivar_op, name, node.operator, expr]
      when AST::Var
        owner = method.defining_class
        return nil unless owner&.lookup_method(node.name)

        [:call_self, owner, node.name, nil, nil]
      end
    end

    def simple_w_method_expression(node, param_slots)
      case node
      when AST::InstanceVar
        [:ivar, node.name.to_s]
      when AST::Var
        slot = param_slots[node.name]
        slot.nil? ? nil : [:arg, slot]
      when AST::Int, AST::Float, AST::Decimal, AST::StringLiteral, AST::Boolean
        [:literal, node.value]
      when AST::Char
        [ :literal, Tungsten::CharValue.new(node.value) ]
      when AST::Nil
        [:literal, nil]
      when AST::Symbol
        [:literal, node.value.to_sym]
      when AST::BinaryOp
        return nil unless SIMPLE_WHILE_ARITH_OPS[node.operator] || SIMPLE_WHILE_COMPARE_OPS[node.operator]

        left = simple_w_method_expression(node.left, param_slots)
        right = simple_w_method_expression(node.right, param_slots)
        return nil unless left && right

        [:binary, node.operator, left, right]
      end
    end

    def execute_simple_w_method_plan(recv, plan)
      return SIMPLE_W_METHOD_UNSUPPORTED unless recv.is_a?(Runtime::WObject)
      return SIMPLE_W_METHOD_UNSUPPORTED unless simple_w_method_plan_ready?(plan)

      execute_simple_w_method_plan_on_ivars(recv, recv.instance_vars, plan)
    end

    def simple_w_method_plan_ready?(plan, depth = 0)
      return false if depth > 32

      case plan[0]
      when :sequence
        steps = plan[1]
        i = 0
        while i < steps.length
          return false unless simple_w_method_plan_ready?(steps[i], depth + 1)

          i += 1
        end
        true
      when :call_self
        owner = plan[1]
        if plan[3] != owner.version || plan[4].nil?
          method = owner.lookup_method(plan[2])
          return false unless method

          callee_plan = cached_simple_w_method_plan(method)
          return false unless callee_plan && !callee_plan.equal?(plan)

          plan[3] = owner.version
          plan[4] = callee_plan
        end
        simple_w_method_plan_ready?(plan[4], depth + 1)
      else
        true
      end
    end

    def execute_simple_w_method_plan_on_ivars(recv, ivars, plan, arg0 = nil, arg1 = nil, arg2 = nil)
      case plan[0]
      when :value
        simple_w_method_value(ivars, plan[1], arg0, arg1, arg2)
      when :assign_ivar
        value = simple_w_method_value(ivars, plan[2], arg0, arg1, arg2)
        ivars[plan[1]] = value
      when :assign_ivar_op
        value = simple_while_arithmetic(
          ivars[plan[1]], plan[2], simple_w_method_value(ivars, plan[3], arg0, arg1, arg2)
        )
        ivars[plan[1]] = value
      when :sequence
        result = nil
        steps = plan[1]
        i = 0
        while i < steps.length
          result = execute_simple_w_method_plan_on_ivars(recv, ivars, steps[i], arg0, arg1, arg2)
          return result if result.equal?(SIMPLE_W_METHOD_UNSUPPORTED)

          i += 1
        end
        result
      when :call_self
        execute_simple_w_method_plan_on_ivars(recv, ivars, plan[4], arg0, arg1, arg2)
      else
        SIMPLE_W_METHOD_UNSUPPORTED
      end
    end

    def simple_w_method_value(ivars, expr, arg0 = nil, arg1 = nil, arg2 = nil)
      case expr[0]
      when :ivar
        ivars[expr[1]]
      when :arg
        case expr[1]
        when 0 then arg0
        when 1 then arg1
        when 2 then arg2
        end
      when :literal
        expr[1]
      when :binary
        left = simple_w_method_value(ivars, expr[2], arg0, arg1, arg2)
        right = simple_w_method_value(ivars, expr[3], arg0, arg1, arg2)
        if SIMPLE_WHILE_ARITH_OPS[expr[1]]
          simple_while_arithmetic(left, expr[1], right)
        else
          simple_while_compare(left, expr[1], right)
        end
      end
    end

    def execute_bound_w_method(recv, method, env, block, call_node)
      old_env = @env
      old_block = @current_block
      @env = env
      @current_block = block
      @self_stack.push(recv)
      @call_methods.push(method)
      @call_locations.push(call_node&.location)

      begin
        with_profile_callable(method) do
          body = method.body
          if method.instance_variable_defined?(:@has_return)
            hr = method.instance_variable_get(:@has_return)
          else
            hr = Interpreter.body_has_return?(body)
            method.instance_variable_set(:@has_return, hr)
          end
          hr ? catch(RETURN_SIGNAL) { evaluate(body) } : evaluate(body)
        end
      ensure
        @call_locations.pop
        @call_methods.pop
        @self_stack.pop
        @current_block = old_block
        @env = old_env
      end
    end

    def instantiate(w_class, args)
      obj = Runtime::WObject.new(w_class)
      constructor = w_class.lookup_method("new")
      call_w_method(obj, constructor, args) if constructor
      obj
    end

    def visit_begin(node)
      result = nil
      begin
        result = evaluate(node.body)
      rescue Tungsten::Error => e
        result = evaluate_begin_rescue(node, e)
      rescue NoMethodError, ZeroDivisionError, SystemStackError, TypeError => e
        result = evaluate_begin_rescue(node, runtime_error_from_exception(e, node: node))
      ensure
        evaluate(node.ensure_body) if node.ensure_body && !node.ensure_body.empty?
      end
      result
    end

    def evaluate_begin_rescue(node, error)
      if node.rescue_body && !node.rescue_body.empty?
        @env.set(node.rescue_var, error.message) if node.rescue_var
        evaluate(node.rescue_body)
      else
        raise error
      end
    end

    def visit_raise(node)
      value = node.value ? evaluate(node.value) : "runtime error"
      runtime_error(value.to_s, node: node)
    end

    def visit_use(node)
      path = resolve_use_path(node.path)
      return nil if @loaded_files.key?(path)
      @loaded_files[path] = true

      source = File.read(path)
      @file_sources[path] = source
      prev_file = @current_file
      @current_file = path
      begin
        ast = parse_with_file(source, path)
        evaluate(ast)
      ensure
        @current_file = prev_file
      end
    end

    # Resolve a use path by searching:
    # 1. `core/<name>` prefix — always resolves to <project_root>/core/<name>.w
    # 2. Relative to the current file
    # 3. bits/<name>/lib/<name>.w (exact bit match)
    # 4. bits/tungsten-<name>/lib/<name>.w (tungsten-prefixed bit)
    # 5. namespaced bit modules: bits/tungsten-<name>/lib/<name>/<path>.w
    # 6. core/<path>.w (stdlib fallback for bare names)
    # 7. lib/<path>.w (legacy stdlib, backward compat during migration)
    #
    # For paths like "tungsten-hammer", strips the prefix for the entry point:
    #   bits/tungsten-hammer/lib/hammer.w
    def resolve_use_path(use_path)
      base_dir = @current_file ? File.dirname(@current_file) : Dir.pwd

      # `core/` prefix: always resolves to <project_root>/core/<rest>.w.
      # This is the explicit path a bit uses to reach core classes.
      if use_path.start_with?("core/")
        project_root = find_project_root(base_dir)
        if project_root
          explicit_core = File.join(project_root, "#{use_path}.w")
          return explicit_core if File.exist?(explicit_core)
        end
      end

      candidate = File.expand_path(use_path, base_dir)
      candidate += ".w" unless candidate.end_with?(".w")
      return candidate if File.exist?(candidate)

      project_root = find_project_root(base_dir)
      if project_root
        bit_name = use_path.split("/").first.downcase
        sub_path = use_path.split("/")[1..].join("/")

        # If the name starts with tungsten-, resolve directly to that bit
        # e.g. use "tungsten-hammer" → bits/tungsten-hammer/lib/hammer.w
        if bit_name.start_with?("tungsten-")
          entry = bit_name.delete_prefix("tungsten-")
          entry_file = sub_path.empty? ? "#{entry}.w" : "#{sub_path}.w"
          bit_path = File.join(project_root, "bits", bit_name, "lib", entry_file)
          return bit_path if File.exist?(bit_path)
          unless sub_path.empty?
            namespaced_path = File.join(project_root, "bits", bit_name, "lib", entry, "#{sub_path}.w")
            return namespaced_path if File.exist?(namespaced_path)
          end
        else
          # Try exact bit match first: bits/<name>/lib/<name>.w
          entry_file = sub_path.empty? ? "#{bit_name}.w" : "#{sub_path}.w"
          exact_path = File.join(project_root, "bits", bit_name, "lib", entry_file)
          return exact_path if File.exist?(exact_path)
          unless sub_path.empty?
            namespaced_exact = File.join(project_root, "bits", bit_name, "lib", bit_name, "#{sub_path}.w")
            return namespaced_exact if File.exist?(namespaced_exact)
          end

          # Then try tungsten-prefixed: bits/tungsten-<name>/lib/<name>.w
          prefixed_path = File.join(project_root, "bits", "tungsten-#{bit_name}", "lib", entry_file)
          return prefixed_path if File.exist?(prefixed_path)
          unless sub_path.empty?
            namespaced_prefixed = File.join(project_root, "bits", "tungsten-#{bit_name}", "lib", bit_name, "#{sub_path}.w")
            return namespaced_prefixed if File.exist?(namespaced_prefixed)
          end
        end

        # Core library: core/<path>.w
        core_path = File.join(project_root, "core", "#{use_path}.w")
        return core_path if File.exist?(core_path)

        # Standard library (legacy): lib/<path>.w
        lib_path = File.join(project_root, "lib", "#{use_path}.w")
        return lib_path if File.exist?(lib_path)
      end

      # Fall back to the original (may raise on File.read)
      candidate
    end

    def try_autoload_core(name)
      base_dir = @current_file ? File.dirname(@current_file) : Dir.pwd
      root = find_project_root(base_dir)
      return nil unless root

      core_path = File.join(root, "core", "#{name.downcase}.w")
      return nil unless File.exist?(core_path)
      return nil if @loaded_files.key?(core_path)

      @loaded_files[core_path] = true
      source = File.read(core_path)
      @file_sources[core_path] = source
      prev_file = @current_file
      @current_file = core_path
      begin
        ast = parse_with_file(source, core_path)
        evaluate(ast)
      ensure
        @current_file = prev_file
      end

      @classes[name] || @modules[name]
    end

    def ruby_constant_for_w_class(name)
      name.to_s.split(":").reduce(Tungsten) { |mod, part| mod.const_get(part) }
    rescue NameError
      nil
    end

    def find_project_root(dir)
      d = dir
      10.times do
        return d if File.directory?(File.join(d, "bits"))
        return d if File.directory?(File.join(d, "bit"))
        parent = File.dirname(d)
        break if parent == d
        d = parent
      end
      configured_root = ENV["TUNGSTEN_ROOT"]
      if configured_root && File.directory?(File.join(configured_root, "core"))
        return File.expand_path(configured_root)
      end

      nil
    end

    def cached_literal_case_lookup(node)
      if node.instance_variable_defined?(:@literal_case_lookup)
        lookup = node.instance_variable_get(:@literal_case_lookup)
        return nil if lookup.equal?(NO_LITERAL_CASE_LOOKUP)

        return lookup
      end

      lookup = build_literal_case_lookup(node) || NO_LITERAL_CASE_LOOKUP
      node.instance_variable_set(:@literal_case_lookup, lookup)
      return nil if lookup.equal?(NO_LITERAL_CASE_LOOKUP)

      lookup
    end

    def build_literal_case_lookup(node)
      return nil unless node.receiver

      lookup = {}

      node.whens.each do |conditions, body|
        conditions.each do |cond|
          value = literal_case_value(cond)
          return nil if value.equal?(UNSUPPORTED_CASE_LITERAL)

          exact_matches = (lookup[value.class] ||= {})
          exact_matches[value] ||= body
        end
      end

      lookup
    end

    def literal_case_value(node)
      case node
      when AST::Int, AST::Float, AST::Decimal, AST::Boolean, AST::StringLiteral
        node.value
      when AST::Char
        Tungsten::CharValue.new(node.value)
      when AST::Symbol
        node.value.to_sym
      when AST::Nil
        nil
      else
        UNSUPPORTED_CASE_LITERAL
      end
    end

    def visit_case_expr(node)
      if node.receiver
        receiver_val = evaluate(node.receiver)
        if (lookup = cached_literal_case_lookup(node))
          exact_matches = lookup[receiver_val.class]
          if exact_matches&.key?(receiver_val)
            return evaluate(exact_matches[receiver_val])
          end
        end

        node.whens.each do |conditions, body|
          conditions.each do |cond|
            cond_val = evaluate(cond)
            if cond_val.is_a?(Regexp)
              if (match = cond_val.match(receiver_val.to_s))
                @globals["$~"] = match
                @globals["$0"] = match[0]
                match.captures.each_with_index { |capture, i| @globals["$#{i + 1}"] = capture }
                return evaluate(body)
              end
            elsif cond_val === receiver_val || cond_val == receiver_val
              return evaluate(body)
            end
          end
        end
      else
        # Condition-less case: each when condition is a boolean guard
        node.whens.each do |conditions, body|
          if conditions.any? { |cond| truthy?(evaluate(cond)) }
            return evaluate(body)
          end
        end
      end
      node.else_body && !node.else_body.empty? ? evaluate(node.else_body) : nil
    end

    def visit_not(node)
      !truthy?(evaluate(node.exp))
    end

    def visit_if(node)
      if truthy?(evaluate(node.condition))
        evaluate(node.then_block)
      elsif (else_block = node.else_block) && !else_block.empty?
        evaluate(else_block)
      end
    end

    def visit_while(node)
      if !@profile_enabled && (plan = cached_simple_while_plan(node))
        result = execute_simple_while_plan(plan)
        return result unless result.equal?(SIMPLE_WHILE_UNSUPPORTED)
      end

      loop_body = node.check_first == true ? node.body : node.check_first
      has_next = Interpreter.body_has_next?(loop_body)
      static_truth = static_condition_truth(node.condition)

      catch_break_if_needed(loop_body) do
        result = nil
        if node.check_first == true
          if static_truth == true
            loop do
              result = has_next ? catch(NEXT_SIGNAL) { evaluate(node.body) } : evaluate(node.body)
            end
          elsif static_truth == false
            result
          else
            while truthy?(evaluate(node.condition))
              result = has_next ? catch(NEXT_SIGNAL) { evaluate(node.body) } : evaluate(node.body)
            end
          end
        else
          # suffix while — body is in check_first
          if static_truth == true
            loop do
              if has_next
                catch(NEXT_SIGNAL) { result = evaluate(node.check_first) }
              else
                result = evaluate(node.check_first)
              end
            end
          else
            loop do
              if has_next
                did_next = true
                catch(NEXT_SIGNAL) do
                  result = evaluate(node.check_first)
                  did_next = false
                end
                next if did_next
              else
                result = evaluate(node.check_first)
              end
              break if static_truth == false
              break unless truthy?(evaluate(node.condition))
            end
          end
        end
        result
      end
    end

    def static_condition_truth(node)
      value = static_condition_literal_value(node)
      return truthy?(value) unless value.equal?(STATIC_CONDITION_UNKNOWN)

      return STATIC_CONDITION_UNKNOWN unless node.is_a?(AST::BinaryOp)
      return STATIC_CONDITION_UNKNOWN unless SIMPLE_WHILE_COMPARE_OPS[node.operator]

      left = static_condition_literal_value(node.left)
      return STATIC_CONDITION_UNKNOWN if left.equal?(STATIC_CONDITION_UNKNOWN)

      right = static_condition_literal_value(node.right)
      return STATIC_CONDITION_UNKNOWN if right.equal?(STATIC_CONDITION_UNKNOWN)

      static_condition_compare(left, node.operator, right)
    end

    def static_condition_literal_value(node)
      case node
      when AST::Int, AST::Float, AST::Decimal, AST::StringLiteral, AST::Boolean
        node.value
      when AST::Char
        Tungsten::CharValue.new(node.value)
      when AST::Nil
        nil
      when AST::Symbol
        node.value.to_sym
      else
        STATIC_CONDITION_UNKNOWN
      end
    end

    def static_condition_compare(left, op, right)
      case op
      when :== then left == right
      when :!= then left != right
      when :<  then left < right
      when :>  then left > right
      when :<= then left <= right
      when :>= then left >= right
      end
    rescue StandardError
      STATIC_CONDITION_UNKNOWN
    end

    def cached_simple_while_plan(node)
      if node.instance_variable_defined?(:@simple_while_plan)
        plan = node.instance_variable_get(:@simple_while_plan)
        return nil if plan.equal?(SIMPLE_WHILE_UNSUPPORTED)

        return plan
      end

      plan = build_simple_while_plan(node) || SIMPLE_WHILE_UNSUPPORTED
      node.instance_variable_set(:@simple_while_plan, plan)
      plan.equal?(SIMPLE_WHILE_UNSUPPORTED) ? nil : plan
    end

    def build_simple_while_plan(node)
      return nil unless node.check_first == true

      condition = node.condition
      names = {}
      condition_truth = static_condition_truth(condition)
      if condition_truth == true
        condition_op = SIMPLE_WHILE_ALWAYS_TRUE
        left = nil
        right = nil
      elsif condition_truth == false
        return nil
      else
        return nil unless condition.is_a?(AST::BinaryOp)
        return nil unless SIMPLE_WHILE_COMPARE_OPS[condition.operator]

        condition_op = condition.operator
        left = simple_while_expression(condition.left, names)
        right = simple_while_expression(condition.right, names)
        return nil unless left && right
      end

      body = node.body.list
      return nil if body.empty?

      steps = []
      body.each do |expr|
        step = simple_while_step(expr, names)
        return nil unless step

        steps << step
      end

      [condition_op, left, right, steps, names.keys]
    end

    def simple_while_step(node, names)
      case node
      when AST::Assign
        return nil if node.type_hint
        return nil unless node.name.is_a?(AST::Var)

        target = node.name.name
        value = simple_while_expression(node.value, names)
        return nil unless value

        names[target] = true
        [:assign, target, value]
      when AST::AssignOp
        return nil unless node.name.is_a?(AST::Var)
        return nil unless SIMPLE_WHILE_ARITH_OPS[node.operator]

        target = node.name.name
        value = simple_while_expression(node.value, names)
        return nil unless value

        names[target] = true
        [:assign, target, [:binary, node.operator, [:var, target], value]]
      when AST::If
        return nil unless node.else_block.empty?
        return nil unless node.then_block.list.length == 1

        branch = node.then_block.list[0]
        return nil unless branch.is_a?(AST::Break)

        condition = simple_while_condition_expression(node.condition, names)
        return nil unless condition

        value = branch.value && simple_while_expression(branch.value, names)
        return nil if branch.value && !value

        [:break_if, condition, value]
      when AST::Call
        return nil unless node.obj
        return nil if node.block

        receiver = simple_while_receiver_expression(node.obj, names)
        return nil unless receiver

        args = node.args || EMPTY_ARGS
        return nil if args.length > 3

        expressions = []
        args.each do |arg|
          return nil if arg.is_a?(AST::Splat)

          expression = simple_while_expression(arg, names)
          return nil unless expression

          expressions << expression
        end
        [:w_call, receiver, node.name.to_s, expressions]
      when AST::Yield
        args = node.args || EMPTY_ARGS
        return nil if args.length > 3

        expressions = []
        args.each do |arg|
          return nil if arg.is_a?(AST::Splat)

          expression = simple_while_expression(arg, names)
          return nil unless expression

          expressions << expression
        end
        [:yield, expressions]
      end
    end

    def simple_while_condition_expression(node, names)
      literal = static_condition_literal_value(node)
      return [:literal_condition, literal] unless literal.equal?(STATIC_CONDITION_UNKNOWN)

      return nil unless node.is_a?(AST::BinaryOp)
      return nil unless SIMPLE_WHILE_COMPARE_OPS[node.operator]

      left = simple_while_expression(node.left, names)
      right = simple_while_expression(node.right, names)
      return nil unless left && right

      [:compare, node.operator, left, right]
    end

    def simple_while_receiver_expression(node, names)
      case node
      when AST::Var
        names[node.name] = true
        [:var, node.name]
      end
    end

    def simple_while_expression(node, names)
      case node
      when AST::Var
        names[node.name] = true
        [:var, node.name]
      when AST::Int, AST::Float, AST::Decimal
        [:literal, node.value]
      when AST::BinaryOp
        return nil unless SIMPLE_WHILE_ARITH_OPS[node.operator]

        left = simple_while_expression(node.left, names)
        right = simple_while_expression(node.right, names)
        return nil unless left && right

        [:binary, node.operator, left, right]
      when AST::Call
        return nil if node.obj || node.block

        args = node.args || EMPTY_ARGS
        return nil if args.length > 3

        expressions = []
        args.each do |arg|
          return nil if arg.is_a?(AST::Splat)

          expression = simple_while_expression(arg, names)
          return nil unless expression

          expressions << expression
        end
        [:local_call, node.name.to_s, expressions]
      end
    end

    def execute_simple_while_plan(plan)
      bound = bind_simple_while_plan(plan)
      return SIMPLE_WHILE_UNSUPPORTED unless bound

      slots, condition_op, left, right, steps, assign_only = bound
      if assign_only
        result = nil
        if condition_op.equal?(SIMPLE_WHILE_ALWAYS_TRUE)
          loop do
            i = 0
            while i < steps.length
              step = steps[i]
              result = simple_while_value(slots, step[1])
              slots[step[0]] = result
              i += 1
            end
          end
        end

        while simple_while_compare(simple_while_value(slots, left), condition_op, simple_while_value(slots, right))
          i = 0
          while i < steps.length
            step = steps[i]
            result = simple_while_value(slots, step[1])
            slots[step[0]] = result
            i += 1
          end
        end
        return result
      end

      execute_mixed_simple_while_plan(slots, condition_op, left, right, steps)
    end

    def execute_mixed_simple_while_plan(slots, condition_op, left, right, steps)
      result = nil
      if condition_op.equal?(SIMPLE_WHILE_ALWAYS_TRUE)
        loop do
          result = execute_mixed_simple_while_steps(slots, steps)
          return result if @simple_while_break_taken
        end
      end

      while simple_while_compare(simple_while_value(slots, left), condition_op, simple_while_value(slots, right))
        result = execute_mixed_simple_while_steps(slots, steps)
        return result if @simple_while_break_taken
      end
      result
    end

    def bind_simple_while_plan(plan)
      condition_op, left, right, steps, names = plan
      env = @env
      slot_map = {}
      names.each do |name|
        slot = env.slot_index(name)
        return nil unless slot

        slot_map[name] = slot
      end

      slots = env.instance_variable_get(:@slot_values)

      bound_left = nil
      bound_right = nil
      unless condition_op.equal?(SIMPLE_WHILE_ALWAYS_TRUE)
        bound_left = bind_simple_while_expression(left, slot_map, env, slots)
        bound_right = bind_simple_while_expression(right, slot_map, env, slots)
        return nil unless bound_left && bound_right
      end

      assign_only = true
      i = 0
      while i < steps.length
        if steps[i][0] != :assign
          assign_only = false
          break
        end
        i += 1
      end

      bound_steps = []
      steps.each do |step|
        case step[0]
        when :assign
          bound_value = bind_simple_while_expression(step[2], slot_map, env, slots)
          return nil unless bound_value

          if assign_only
            bound_steps << [slot_map[step[1]], bound_value]
          else
            bound_steps << [:assign, slot_map[step[1]], bound_value]
          end
        when :break_if
          bound_condition = bind_simple_while_condition_expression(step[1], slot_map, env, slots)
          return nil unless bound_condition

          bound_value = step[2] && bind_simple_while_expression(step[2], slot_map, env, slots)
          return nil if step[2] && !bound_value

          bound_steps << [:break_if, bound_condition, bound_value]
        when :w_call
          bound_receiver = bind_simple_while_receiver_expression(step[1], slot_map)
          return nil unless bound_receiver

          recv = slots[bound_receiver]
          return nil unless recv.is_a?(Runtime::WObject)

          method = recv.w_class.lookup_method(step[2])
          return nil unless method
          params = method.params || EMPTY_ARGS
          args = step[3] || EMPTY_ARGS
          return nil unless params.length == args.length

          plan = cached_simple_w_method_plan(method)
          return nil unless plan && simple_w_method_plan_ready?(plan)

          bound_args = []
          args.each do |arg|
            bound_arg = bind_simple_while_expression(arg, slot_map, env, slots)
            return nil unless bound_arg

            bound_args << bound_arg
          end
          bound_steps << [:w_call, bound_receiver, plan, bound_args]
        when :yield
          block = @current_block
          return nil unless block

          block_plan = cached_simple_block_plan(block)
          return nil unless block_plan && block_plan[0] == step[1].length

          closure_env = block.closure_env || @env
          return nil unless simple_block_env_ready?(closure_env, block_plan[2])

          bound_args = []
          step[1].each do |arg|
            bound_arg = bind_simple_while_expression(arg, slot_map, env, slots)
            return nil unless bound_arg

            bound_args << bound_arg
          end
          bound_steps << [:yield, closure_env, block_plan[1], bound_args]
        else
          return nil
        end
      end

      [slots, condition_op, bound_left, bound_right, bound_steps, assign_only]
    end

    def bind_simple_while_condition_expression(expr, slot_map, env, slots)
      case expr[0]
      when :literal_condition
        expr
      when :compare
        left = bind_simple_while_expression(expr[2], slot_map, env, slots)
        right = bind_simple_while_expression(expr[3], slot_map, env, slots)
        return nil unless left && right

        [:compare, expr[1], left, right]
      end
    end

    def bind_simple_while_receiver_expression(expr, slot_map)
      case expr[0]
      when :var
        slot_map.fetch(expr[1])
      end
    end

    def bind_simple_while_expression(expr, slot_map, env, slots = nil)
      slots ||= env.instance_variable_get(:@slot_values)
      case expr[0]
      when :var
        slot = slot_map.fetch(expr[1])
        return nil unless slots[slot].is_a?(Numeric)

        [:slot, slot]
      when :literal
        return nil unless expr[1].is_a?(Numeric)

        expr
      when :binary
        left = bind_simple_while_expression(expr[2], slot_map, env, slots)
        right = bind_simple_while_expression(expr[3], slot_map, env, slots)
        return nil unless left && right

        [:binary, expr[1], left, right]
      when :local_call
        func = env.fetch(expr[1])
        return nil unless func.is_a?(AST::Def)

        method_plan = cached_simple_method_plan(func)
        return nil unless method_plan && method_plan[0] == expr[2].length
        return nil unless simple_method_numeric_expression?(method_plan[1])

        args = []
        expr[2].each do |arg|
          bound_arg = bind_simple_while_expression(arg, slot_map, env, slots)
          return nil unless bound_arg

          args << bound_arg
        end
        [:local_call, method_plan, args]
      end
    end

    def execute_mixed_simple_while_steps(slots, steps)
      @simple_while_break_taken = false
      result = nil
      i = 0
      while i < steps.length
        step = steps[i]
        case step[0]
        when :assign
          result = simple_while_value(slots, step[2])
          slots[step[1]] = result
        when :break_if
          if simple_while_condition_value(slots, step[1])
            @simple_while_break_taken = true
            return step[2] ? simple_while_value(slots, step[2]) : nil
          end
        when :w_call
          recv = slots[step[1]]
          args = step[3]
          case args.length
          when 0
            result = execute_simple_w_method_plan_on_ivars(recv, recv.instance_vars, step[2])
          when 1
            result = execute_simple_w_method_plan_on_ivars(
              recv, recv.instance_vars, step[2], simple_while_value(slots, args[0])
            )
          when 2
            result = execute_simple_w_method_plan_on_ivars(
              recv,
              recv.instance_vars,
              step[2],
              simple_while_value(slots, args[0]),
              simple_while_value(slots, args[1])
            )
          when 3
            result = execute_simple_w_method_plan_on_ivars(
              recv,
              recv.instance_vars,
              step[2],
              simple_while_value(slots, args[0]),
              simple_while_value(slots, args[1]),
              simple_while_value(slots, args[2])
            )
          end
        when :yield
          args = step[3]
          case args.length
          when 0
            result = execute_simple_block_plan(step[1], step[2])
          when 1
            result = execute_simple_block_plan(step[1], step[2], simple_while_value(slots, args[0]))
          when 2
            result = execute_simple_block_plan(
              step[1], step[2], simple_while_value(slots, args[0]), simple_while_value(slots, args[1])
            )
          when 3
            result = execute_simple_block_plan(
              step[1],
              step[2],
              simple_while_value(slots, args[0]),
              simple_while_value(slots, args[1]),
              simple_while_value(slots, args[2])
            )
          end
        end
        i += 1
      end
      result
    end

    def simple_while_condition_value(slots, expr)
      case expr[0]
      when :literal_condition
        truthy?(expr[1])
      when :compare
        simple_while_compare(simple_while_value(slots, expr[2]), expr[1], simple_while_value(slots, expr[3]))
      end
    end

    def simple_while_value(slots, expr)
      case expr[0]
      when :slot
        slots[expr[1]]
      when :literal
        expr[1]
      when :binary
        left = simple_while_value(slots, expr[2])
        right = simple_while_value(slots, expr[3])
        simple_while_arithmetic(left, expr[1], right)
      when :local_call
        plan = expr[1]
        args = expr[2]
        case plan[0]
        when 0
          simple_method_value3(nil, nil, nil, plan[1])
        when 1
          simple_method_value3(simple_while_value(slots, args[0]), nil, nil, plan[1])
        when 2
          simple_method_value3(
            simple_while_value(slots, args[0]),
            simple_while_value(slots, args[1]),
            nil,
            plan[1]
          )
        when 3
          simple_method_value3(
            simple_while_value(slots, args[0]),
            simple_while_value(slots, args[1]),
            simple_while_value(slots, args[2]),
            plan[1]
          )
        end
      end
    end

    def simple_while_arithmetic(left, op, right)
      case op
      when :+  then left + right
      when :-  then left - right
      when :*  then left * right
      when :/  then left / right
      when :%  then left % right
      when :** then left ** right
      when :&  then left & right
      when :|  then left | right
      when :^  then left ^ right
      when :<< then left << right
      when :>> then left >> right
      end
    end

    def simple_while_compare(left, op, right)
      case op
      when :== then left == right
      when :!= then left != right
      when :<  then left < right
      when :>  then left > right
      when :<= then left <= right
      when :>= then left >= right
      end
    end

    def visit_until(node)
      loop_body = node.check_first == true ? node.body : node.check_first
      has_next = Interpreter.body_has_next?(loop_body)

      catch_break_if_needed(loop_body) do
        result = nil
        if node.check_first == true
          until truthy?(evaluate(node.condition))
            result = has_next ? catch(NEXT_SIGNAL) { evaluate(node.body) } : evaluate(node.body)
          end
        else
          loop do
            result = has_next ? catch(NEXT_SIGNAL) { evaluate(node.check_first) } : evaluate(node.check_first)
            break if truthy?(evaluate(node.condition))
          end
        end
        result
      end
    end

    def visit_with(node)
      body_has_next = Interpreter.body_has_next?(node.body)

      catch_break_if_needed(node.body) do
        collections = node.bindings.map { |_var, expr| evaluate(expr) }
        result = nil
        iterate_with(node.bindings, collections, 0, node.body, body_has_next:) { |r| result = r }
        result
      end
    end

    def visit_on_guard(node)
      return nil unless Tungsten::Target.matches?(node.predicate, node.capabilities)

      result = nil
      node.body.each { |expr| result = evaluate(expr) }
      result
    end

    # Expand OnGuard nodes: matching guards inline their body, non-matching are dropped.
    # Guarded defs override unguarded fallback defs with the same name.
    # Two matching guards defining the same method name is a compile-time error.
    def expand_on_guards(body)
      # First pass: collect guarded method names, detecting duplicates across guards
      guarded_names = {}
      body.each do |expr|
        next unless expr.is_a?(Tungsten::AST::OnGuard)
        next unless Tungsten::Target.matches?(expr.predicate, expr.capabilities)

        expr.body.each do |inner|
          next unless inner.is_a?(Tungsten::AST::Def)
          name = inner.name.to_s
          if guarded_names[name]
            runtime_error(
              "ambiguous platform guard: multiple guarded definitions of '#{name}' match the current target",
              node: expr
            )
          end
          guarded_names[name] = true
        end
      end

      # Second pass: inline matching guards, drop unguarded defs overridden by guards
      body.flat_map do |expr|
        if expr.is_a?(Tungsten::AST::OnGuard)
          if Tungsten::Target.matches?(expr.predicate, expr.capabilities)
            expr.body.to_a
          else
            []
          end
        elsif expr.is_a?(Tungsten::AST::Def) && guarded_names[expr.name.to_s]
          []
        else
          [expr]
        end
      end
    end

    def visit_and(node)
      left = evaluate(node.left)
      truthy?(left) ? evaluate(node.right) : left
    end

    def visit_or(node)
      left = evaluate(node.left)
      truthy?(left) ? left : evaluate(node.right)
    end

    def visit_in_test(node)
      lhs = evaluate(node.lhs)
      node.elements.any? { |el| evaluate(el) == lhs }
    end

    def visit_break(node)
      throw BREAK_SIGNAL, (node.value ? evaluate(node.value) : nil)
    end

    def visit_next(node)
      throw NEXT_SIGNAL, (node.value ? evaluate(node.value) : nil)
    end

    def visit_return(node)
      throw RETURN_SIGNAL, (node.value ? evaluate(node.value) : nil)
    end

    def visit_var(node)
      # Inline cache hit: same Environment instance → same slot layout
      if (ce = node.cached_env) && ce.equal?(@env)
        value = ce.get_slot(node.cached_slot)
        return value unless value.equal?(Environment::UNDEFINED)
      end

      name = node.name
      return @self_stack.last if name == "self"

      # Class/module reference (with core autoload)
      if node.constant?
        w_class = @classes[name] || try_autoload_core(name)
        return w_class if w_class

        w_module = @modules[name]
        return w_module if w_module

        namespaced = resolve_unique_namespaced_constant(name)
        return namespaced if namespaced
      end

      value = resolve_cached_local(node, name)
      unless value.equal?(Environment::UNDEFINED)
        if value.is_a?(Tungsten::AST::Def) && (value.args.nil? || value.args.all? { |a| a.default })
          return call_method(value, [])
        end
        return value
      end

      builtin_constant = resolve_builtin_constant(name)
      unless builtin_constant.equal?(Environment::UNDEFINED)
        @env.set(name, builtin_constant)
        return builtin_constant
      end

      builtin = @builtins[name]
      return builtin.call(nil, [], nil) if builtin

      # Implicit self dispatch for bare names (no parens) inside class/instance methods
      self_obj = @self_stack.last
      if self_obj.is_a?(Runtime::WClass)
        method = resolve_w_method(node, self_obj, name)
        if method
          return call_w_method_from_nodes(self_obj, method, [], nil, call_node: node)
        end
      elsif self_obj.is_a?(Runtime::WObject)
        owner = self_obj.w_class
        method = resolve_w_method(node, owner, name)
        if method
          return call_w_method_from_nodes(self_obj, method, [], nil, call_node: node)
        end
      end

      # Δ-prefixed identifier: an UNDEFINED `Δx` reads as `x - x'`
      # (x - @1.x) — the prime-notation delta. Mirrors the compiled
      # lowering's lower_var fallback; a real Δx resolves above.
      if name.to_s.start_with?("Δ") && name.to_s.length > 1
        base = name.to_s.delete_prefix("Δ")
        delta = Tungsten::AST::BinaryOp.new(
          Tungsten::AST::Call.new(nil, base),
          :-,
          Tungsten::AST::Call.new(Tungsten::AST::Var.new("__arg1"), base)
        )
        return evaluate(delta)
      end

      runtime_error("undefined local variable or method '#{name}'", node: node, length: name.length)
    end

    def resolve_unique_namespaced_constant(name)
      suffix = ":#{name}"
      matches = []
      @classes.each { |constant_name, value| matches << value if constant_name.to_s.end_with?(suffix) }
      @modules.each { |constant_name, value| matches << value if constant_name.to_s.end_with?(suffix) }
      matches.size == 1 ? matches.first : nil
    end

    def visit_trait_def(node)
      w_trait = Runtime::WClass.new(node.name)
      @modules[node.name] = w_trait

      expand_on_guards(node.body).each do |expr|
        if expr.is_a?(Tungsten::AST::Def)
          w_method = Runtime::WMethod.new(expr.name, expr.args, expr.body, w_trait, splat_index: expr.splat_index)
          w_trait.define_method(expr.name.to_s, w_method)
        end
      end

      w_trait
    end

    def visit_is(node)
      # `is TraitName` inside a class body — mix in the trait's methods
      trait = @modules[node.trait_name]
      runtime_error("unknown trait '#{node.trait_name}'", node: node) unless trait

      # Find the class being defined (the current self's class, or the class on the stack)
      obj = @self_stack.last
      w_class = if obj.is_a?(Runtime::WClass)
                  obj
                elsif obj.is_a?(Runtime::WObject)
                  obj.w_class
                end

      runtime_error("'is' must be used inside a class definition", node: node) unless w_class

      w_class.include_trait(trait)
      nil
    end

    def visit_module_def(node)
      w_module = Runtime::WClass.new(node.name)
      @modules[node.name] = w_module

      expand_on_guards(node.body).each do |expr|
        if expr.is_a?(Tungsten::AST::Def)
          w_method = Runtime::WMethod.new(expr.name, expr.args, expr.body, w_module, splat_index: expr.splat_index)
          w_module.define_method(expr.name.to_s, w_method)
        else
          evaluate(expr)
        end
      end

      w_module
    end

    def visit_super(node)
      method = @call_methods.last
      runtime_error("super called outside method", node: node) unless method

      superclass = method.defining_class&.superclass
      runtime_error("no superclass", node: node) unless superclass

      super_method = superclass.lookup_method(method.name)
      runtime_error("undefined super method '#{method.name}'", node: node) unless super_method

      args = evaluate_args(node.args)
      recv = @self_stack.last
      call_w_method(recv, super_method, args, call_node: node)
    end

    def visit_path(node)
      # Try the full namespaced name first (e.g., "Argon:Result")
      full_name = node.names.join(":")
      if node.names.length > 1 && (@classes[full_name] || @modules[full_name])
        return @classes[full_name] || @modules[full_name]
      end

      name = node.names.first
      result = @classes[name] || @modules[name]

      # Autoload: try core/<name>.w on first reference
      if result.nil?
        result = try_autoload_core(name)
      end

      runtime_error("undefined constant '#{name}'", node: node, length: name.length) unless result

      node.names[1..].each do |n|
        runtime_error("'#{name}' is not a module", node: node) unless result.is_a?(Runtime::WClass)
        method = result.lookup_method(n)
        if method
          result = method
        else
          runtime_error("undefined constant '#{n}' in #{name}", node: node, length: n.length)
        end
        name = n
      end

      result
    end

    def visit_alias(node)
      new_name = node.to.to_s
      old_name = node.from.to_s

      obj = @self_stack.last
      if obj.is_a?(Runtime::WObject)
        method = obj.w_class.lookup_method(old_name)
        runtime_error("undefined method '#{old_name}' for alias", node: node) unless method
        obj.w_class.define_method(new_name, method)
      elsif @env.defined?(old_name)
        @env.set(new_name, @env.get(old_name))
      else
        runtime_error("undefined method or variable '#{old_name}' for alias", node: node)
      end

      nil
    end

    def visit_splat(node)
      evaluate(node.exp)
    end

    EMPTY_ARGS = [].freeze
    EMPTY_SLOT_NAMES = {}.freeze
    NO_DIRECT_CALL = Object.new.freeze
    HASH_MISS = Object.new.freeze

    def evaluate_args(arg_nodes)
      return EMPTY_ARGS unless arg_nodes
      len = arg_nodes.size
      return EMPTY_ARGS if len == 0
      args = Array.new(len)
      i = 0
      has_splat = false
      while i < len
        a = arg_nodes[i]
        if a.is_a?(Tungsten::AST::Splat)
          has_splat = true
          break
        end
        args[i] = evaluate(a)
        i += 1
      end
      if has_splat
        # Rare path: rebuild with splat expansion
        result = args[0, i]
        while i < len
          a = arg_nodes[i]
          if a.is_a?(Tungsten::AST::Splat)
            result.concat(Array(evaluate(a.exp)))
          else
            result << evaluate(a)
          end
          i += 1
        end
        result
      else
        args
      end
    end

    def small_arg_length_without_splat(arg_nodes)
      return 0 unless arg_nodes

      len = arg_nodes.length
      return nil if len > 3

      i = 0
      while i < len
        return nil if arg_nodes[i].is_a?(Tungsten::AST::Splat)
        i += 1
      end

      len
    end

    def no_call_args?(arg_nodes)
      !arg_nodes || arg_nodes.empty?
    end

    def one_call_arg_node(arg_nodes)
      return nil unless arg_nodes && arg_nodes.length == 1

      arg = arg_nodes[0]
      arg.is_a?(Tungsten::AST::Splat) ? nil : arg
    end

    def cached_symbol_value(node)
      return node.instance_variable_get(:@runtime_symbol) if node.instance_variable_defined?(:@runtime_symbol)

      value = node.value.to_sym
      node.instance_variable_set(:@runtime_symbol, value)
      value
    end

    def direct_arg_value(node)
      case node
      when AST::Symbol
        cached_symbol_value(node)
      when AST::Int, AST::Float, AST::Decimal, AST::StringLiteral, AST::Boolean
        node.value
      when AST::Char
        Tungsten::CharValue.new(node.value)
      when AST::Nil
        nil
      else
        evaluate(node)
      end
    end

    # Int#prime? — tiered deterministic primality, mirroring the compiled
    # runtime intrinsic (runtime/runtime.c `w_prime_test_u64`): a small-prime
    # screen, then prime trial division up to 1e8, then Miller-Rabin with
    # smaller deterministic witness sets for mid-sized integers.
    # Ruby's bignum Integer#pow(d, n) keeps the modular arithmetic exact at any
    # size. The 7-base witness set is deterministic for n < 3.317e24 (Sinclair),
    # a strong-probable-prime test above that.
    PRIME_MR_BASES = [ 2, 325, 9375, 28178, 450775, 9780504, 1795265022 ].freeze
    PRIME_MR_BASES_32 = [ 2, 7, 61 ].freeze
    PRIME_MR_BASES_1T = [ 2, 13, 23, 1_662_803 ].freeze
    PRIME_SMALL = [ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37 ].freeze
    PRIME_TRIAL_DIVISORS = begin
      divisors = []
      41.step(10_000, 2) do |candidate|
        composite = PRIME_SMALL.any? { |p| (candidate % p).zero? }
        divisors.each do |p|
          break if composite || p * p > candidate

          composite = true if (candidate % p).zero?
        end
        divisors << candidate unless composite
      end
      divisors.freeze
    end

    def tungsten_int_prime?(n)
      return false if n < 2

      PRIME_SMALL.each { |p| return n == p if (n % p).zero? }
      return true if n < 1681 # no factor <= 37 and below 41^2 => prime

      if n <= 100_000_000
        PRIME_TRIAL_DIVISORS.each do |p|
          break if p * p > n

          return false if (n % p).zero?
        end
        return true
      end

      d = n - 1
      s = 0
      while d.even?
        d >>= 1
        s += 1
      end

      bases =
        if n < 4_759_123_141
          PRIME_MR_BASES_32
        elsif n < 1_122_004_669_633
          PRIME_MR_BASES_1T
        else
          PRIME_MR_BASES
        end
      bases.each do |base|
        a = base % n
        next if a.zero?

        x = a.pow(d, n)
        next if x == 1 || x == n - 1

        composite = true
        (s - 1).times do
          x = x.pow(2, n)
          if x == n - 1
            composite = false
            break
          end
        end
        return false if composite
      end
      # MR-7 is an exact proof through 2^64; above it, confirm with a strong
      # Lucas test -> Baillie-PSW (no known counterexample at any size).
      return true if n <= (1 << 64)

      lucas_strong_prp?(n)
    end

    # Jacobi symbol (a / n) for odd n > 0.
    def tungsten_jacobi(a, n)
      a %= n
      result = 1
      while a != 0
        while a.even?
          a >>= 1
          result = -result if [3, 5].include?(n % 8)
        end
        a, n = n, a # reciprocity swap
        result = -result if a % 4 == 3 && n % 4 == 3
        a %= n
      end
      n == 1 ? result : 0
    end

    # Strong Lucas probable-prime test, Selfridge parameters (D = first of
    # 5, -7, 9, -11, ... with Jacobi(D, n) = -1; P = 1, Q = (1 - D) / 4).
    def lucas_strong_prp?(n)
      d = 5
      loop do
        j = tungsten_jacobi(d, n)
        return false if j.zero? # gcd(d, n) > 1 => composite

        break if j == -1

        d = d.positive? ? -(d + 2) : -(d - 2)
      end
      q = (1 - d) / 4

      m = n + 1 # delta = n - Jacobi(D,n) = n + 1
      s = 0
      while m.even?
        m >>= 1
        s += 1
      end

      # Lucas ladder over the bits of m below the leading 1 (P = 1). Ruby's
      # floored % keeps every residue in [0, n) without sign correction.
      u = 1
      v = 1
      qk = q % n
      (m.bit_length - 2).downto(0) do |i|
        u = u * v % n
        v = (v * v - 2 * qk) % n
        qk = qk * qk % n
        next unless m[i] == 1

        nu = (u + v) % n
        nv = (d * u + v) % n
        nu += n if nu.odd?
        nv += n if nv.odd?
        u = nu / 2 % n
        v = nv / 2 % n
        qk = qk * q % n
      end

      return true if (u % n).zero?

      s.times do
        return true if (v % n).zero?

        v = (v * v - 2 * qk) % n
        qk = qk * qk % n
      end
      false
    end

    def call_primitive_method_from_nodes(recv, name, arg_nodes, block)
      return NO_DIRECT_CALL if block

      case name
      when "[]"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        key = direct_arg_value(arg)
        case recv
        when ::Hash
          hash_indifferent_get(recv, key)
        when ::Array, ::String, Tungsten::ByteArray
          recv[key]
        else
          NO_DIRECT_CALL
        end
      when "[]="
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 2

        key = direct_arg_value(arg_nodes[0])
        value = direct_arg_value(arg_nodes[1])
        case recv
        when ::Hash, ::Array, Tungsten::ByteArray
          recv[key] = value
        else
          NO_DIRECT_CALL
        end
      when "length", "size"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        case recv
        when ::Array, ::Hash, ::String, Tungsten::ByteArray
          recv.length
        else
          NO_DIRECT_CALL
        end
      when "empty?"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        recv.respond_to?(:empty?) ? recv.empty? : NO_DIRECT_CALL
      when "first"
        recv.is_a?(::Array) && no_call_args?(arg_nodes) ? recv.first : NO_DIRECT_CALL
      when "last"
        recv.is_a?(::Array) && no_call_args?(arg_nodes) ? recv.last : NO_DIRECT_CALL
      when "push"
        return NO_DIRECT_CALL unless recv.is_a?(::Array)

        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len

        case len
        when 0
          recv.push
        when 1
          recv.push(direct_arg_value(arg_nodes[0]))
        when 2
          recv.push(direct_arg_value(arg_nodes[0]), direct_arg_value(arg_nodes[1]))
        when 3
          recv.push(direct_arg_value(arg_nodes[0]), direct_arg_value(arg_nodes[1]), direct_arg_value(arg_nodes[2]))
        end
      when "pop"
        recv.is_a?(::Array) && no_call_args?(arg_nodes) ? recv.pop : NO_DIRECT_CALL
      when "shift"
        recv.is_a?(::Array) && no_call_args?(arg_nodes) ? recv.shift : NO_DIRECT_CALL
      when "to_s"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 0 || len == 1

        if len == 1 && recv.is_a?(::Integer)
          recv.to_s(direct_arg_value(arg_nodes[0]).to_i)
        elsif len == 0
          recv.to_s
        else
          NO_DIRECT_CALL
        end
      when "to_i"
        no_call_args?(arg_nodes) ? Runtime::Builtins.stable_to_i(recv) : NO_DIRECT_CALL
      when "to_f"
        recv.is_a?(::Integer) && no_call_args?(arg_nodes) ? recv.to_f : NO_DIRECT_CALL
      when "prev"
        recv.is_a?(::Integer) && no_call_args?(arg_nodes) ? recv - 1 : NO_DIRECT_CALL
      when "next", "succ"
        recv.is_a?(::Integer) && no_call_args?(arg_nodes) ? recv + 1 : NO_DIRECT_CALL
      when "prime?"
        recv.is_a?(::Integer) && no_call_args?(arg_nodes) ? tungsten_int_prime?(recv) : NO_DIRECT_CALL
      when "chars"
        recv.is_a?(::String) && no_call_args?(arg_nodes) ? recv.chars : NO_DIRECT_CALL
      when "bytes"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        case recv
        when Tungsten::Key then recv.bytes
        when Tungsten::ByteArray then recv
        when Tungsten::CharValue then recv.bytes
        when ::String then Tungsten::ByteArray.new(recv.bytes)
        when ::Symbol then Tungsten::ByteArray.new(recv.to_s.bytes)
        else NO_DIRECT_CALL
        end
      when "starts_with?"
        return NO_DIRECT_CALL unless recv.is_a?(::String)

        arg = one_call_arg_node(arg_nodes)
        arg ? recv.start_with?(direct_arg_value(arg).to_s) : NO_DIRECT_CALL
      when "includes?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        recv.respond_to?(:include?) ? recv.include?(direct_arg_value(arg)) : NO_DIRECT_CALL
      when "replace"
        return NO_DIRECT_CALL unless recv.is_a?(::String)

        len = small_arg_length_without_splat(arg_nodes)
        len == 2 ? recv.gsub(direct_arg_value(arg_nodes[0]), direct_arg_value(arg_nodes[1])) : NO_DIRECT_CALL
      when "keys"
        recv.is_a?(::Hash) && no_call_args?(arg_nodes) ? recv.keys : NO_DIRECT_CALL
      when "values"
        recv.is_a?(::Hash) && no_call_args?(arg_nodes) ? recv.values : NO_DIRECT_CALL
      when "has_key?", "key?"
        return NO_DIRECT_CALL unless recv.is_a?(::Hash)

        arg = one_call_arg_node(arg_nodes)
        arg ? recv.key?(direct_arg_value(arg)) : NO_DIRECT_CALL
      when "slice"
        return NO_DIRECT_CALL unless recv.is_a?(::String)

        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len

        case len
        when 1
          recv.slice(direct_arg_value(arg_nodes[0]))
        when 2
          recv.slice(direct_arg_value(arg_nodes[0]), direct_arg_value(arg_nodes[1]))
        else
          NO_DIRECT_CALL
        end
      when "copy"
        return NO_DIRECT_CALL unless recv.is_a?(::Array)

        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len

        case len
        when 1
          recv.slice(direct_arg_value(arg_nodes[0]), recv.length - direct_arg_value(arg_nodes[0]).to_i)
        when 2
          recv.slice(direct_arg_value(arg_nodes[0]), direct_arg_value(arg_nodes[1]))
        else
          NO_DIRECT_CALL
        end
      when "sort"
        if recv.is_a?(::Array) && no_call_args?(arg_nodes)
          Runtime::Builtins.array_mergesort_copy(recv)
        else
          NO_DIRECT_CALL
        end
      when "sort!", "mergesort!"
        if recv.is_a?(::Array) && no_call_args?(arg_nodes)
          Runtime::Builtins.array_mergesort_in_place!(recv)
        else
          NO_DIRECT_CALL
        end
      when "shuffle"
        return NO_DIRECT_CALL unless recv.is_a?(::Array)

        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len

        case len
        when 0
          Runtime::Builtins.array_shuffle_copy(recv)
        when 1
          return NO_DIRECT_CALL if arg_nodes[0].is_a?(Tungsten::AST::HashLiteral)

          indexes = direct_arg_value(arg_nodes[0])
          indexes.is_a?(::Hash) ? NO_DIRECT_CALL : Runtime::Builtins.array_gather(recv, indexes)
        else
          NO_DIRECT_CALL
        end
      when "shuffle!"
        if recv.is_a?(::Array) && no_call_args?(arg_nodes)
          Runtime::Builtins.array_shuffle_in_place!(recv)
        else
          NO_DIRECT_CALL
        end
      when "rotate"
        return NO_DIRECT_CALL unless recv.is_a?(::Array)

        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 0 || len == 1

        Runtime::Builtins.array_rotate_copy(recv, len == 0 ? 1 : direct_arg_value(arg_nodes[0]))
      when "rotate!"
        return NO_DIRECT_CALL unless recv.is_a?(::Array)

        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 0 || len == 1

        Runtime::Builtins.array_rotate_in_place!(recv, len == 0 ? 1 : direct_arg_value(arg_nodes[0]))
      when "join"
        return NO_DIRECT_CALL unless recv.is_a?(::Array)

        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 0 || len == 1

        recv.join(len == 0 ? "" : direct_arg_value(arg_nodes[0]))
      when "ord"
        if (recv.is_a?(::String) || recv.is_a?(Tungsten::CharValue)) && no_call_args?(arg_nodes)
          recv.ord
        else
          NO_DIRECT_CALL
        end
      when "respond_to?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        method_name = direct_arg_value(arg).to_s
        !hidden_ruby_object_method?(method_name) && recv.respond_to?(method_name)
      else
        NO_DIRECT_CALL
      end
    end

    def call_self_hosted_parser_intrinsic_from_nodes(recv, method, arg_nodes)
      owner = method.defining_class&.name
      call_self_hosted_intrinsic_by_name(recv, owner, method.name, arg_nodes)
    end

    def call_self_hosted_intrinsic_by_name(recv, owner, name, arg_nodes)
      return call_self_hosted_lexer_intrinsic_from_nodes(recv, name, arg_nodes) if owner == "Lexer"
      return NO_DIRECT_CALL unless owner == "Parser"

      # Like the lexer intrinsic, these parser fast paths predate the packed
      # token migration: they read materialized token hashes from @tokens
      # (sync_current does @tokens[@pos]), but the parser now consumes the
      # packed i64 stream and has no @tokens. Every method parser.w actually
      # calls (sync_current / advance / skip_* / expect_method_name) is defined
      # in parser.w against the packed stream; the intrinsic-only arms
      # (current / peek / at? / at_any? / match? / expect) are dead (parser.w
      # never calls them). Fall back to parser.w's real methods.
      return NO_DIRECT_CALL

      ivars = recv.instance_vars
      case name
      when "current"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        ivars["@current_token"]
      when "sync_current"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        sync_self_hosted_parser_current_token(ivars)
      when "advance"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        pos = ivars["@pos"]
        token_count = ivars["@token_count"]
        return ivars["@eof_token"] if pos >= token_count

        tok = ivars["@current_token"]
        ivars["@pos"] = pos + 1
        sync_self_hosted_parser_current_token(ivars)
        tok
      when "peek"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 0 || len == 1

        offset = len == 0 ? 1 : direct_arg_value(arg_nodes[0])
        idx = ivars["@pos"] + offset
        idx < ivars["@token_count"] ? ivars["@tokens"][idx] : ivars["@eof_token"]
      when "at?"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 1 || len == 2

        return false unless ivars["@current_type"] == direct_arg_value(arg_nodes[0])
        return true if len == 1

        ivars["@current_value"] == direct_arg_value(arg_nodes[1])
      when "at_any?"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        direct_arg_value(arg).include?(ivars["@current_type"])
      when "match?"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 1 || len == 2

        return false unless ivars["@current_type"] == direct_arg_value(arg_nodes[0])
        return false if len == 2 && ivars["@current_value"] != direct_arg_value(arg_nodes[1])

        ivars["@pos"] += 1
        sync_self_hosted_parser_current_token(ivars)
        true
      when "expect"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 1 || len == 2

        tok = ivars["@current_token"]
        return NO_DIRECT_CALL unless ivars["@current_type"] == direct_arg_value(arg_nodes[0])
        return NO_DIRECT_CALL if len == 2 && ivars["@current_value"] != direct_arg_value(arg_nodes[1])

        ivars["@pos"] += 1
        sync_self_hosted_parser_current_token(ivars)
        tok
      when "expect_method_name"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        tok = ivars["@current_token"]
        type = ivars["@current_type"]
        return NO_DIRECT_CALL unless type == :ID || type == :KEYWORD

        ivars["@pos"] += 1
        sync_self_hosted_parser_current_token(ivars)
        tok
      when "skip_newlines"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        skip_self_hosted_parser_tokens(ivars, :NEWLINE, nil, :TYPE_HINT)
      when "skip_statement_end"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        skip_self_hosted_parser_tokens(ivars, :NEWLINE, :SEMICOLON, :TYPE_HINT)
      when "skip_block_whitespace"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        skip_self_hosted_parser_tokens(ivars, :NEWLINE, :SEMICOLON, :INDENT, :DEDENT)
      else
        NO_DIRECT_CALL
      end
    end

    def call_self_hosted_lexer_intrinsic_from_nodes(recv, name, arg_nodes)
      # These fast paths were written for an older Lexer that materialized
      # token hashes into an @tokens array. The lexer now emits a packed i64
      # token stream (@packed_tokens + a parallel @values array) and has no
      # @tokens — so the intrinsics are stale and would push onto a nil
      # @tokens. lexer.w defines real implementations of every method these
      # intercepted (build_line_index/push_token/emit_at/materialize_*/…), so
      # fall back to running them. (Re-introduce packed-aware intrinsics here
      # if interpreter bootstrap speed needs it.)
      return NO_DIRECT_CALL

      ivars = recv.instance_vars

      case name
      when "build_line_index"
        return NO_DIRECT_CALL unless no_call_args?(arg_nodes)

        chars = ivars["@chars"]
        char_count = ivars["@char_count"]
        line_at = []
        col_at = []
        line = 1
        col = 1
        i = 0
        while i < char_count
          line_at << line
          col_at << col
          if chars[i] == "\n"
            line += 1
            col = 1
          else
            col += 1
          end
          i += 1
        end
        line_at << line
        col_at << col
        ivars["@line_at"] = line_at
        ivars["@col_at"] = col_at
        nil
      when "packed_type_id"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        (direct_arg_value(arg) >> 40) & 0x3F
      when "packed_offset"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        (direct_arg_value(arg) >> 4) & 0xFFFFFF
      when "packed_length"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        (direct_arg_value(arg) >> 28) & 0xFFF
      when "slice_chars"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 2

        off = direct_arg_value(arg_nodes[0])
        count = direct_arg_value(arg_nodes[1])
        source = ivars["@source"]
        source.slice(off, count) || ""
      when "reset_scan_position"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        off = direct_arg_value(arg)
        ivars["@pos"] = off
        ivars["@line"] = ivars["@line_at"][off]
        ivars["@col"] = ivars["@col_at"][off]
        nil
      when "push_token"
        arg = one_call_arg_node(arg_nodes)
        return NO_DIRECT_CALL unless arg

        push_self_hosted_lexer_token(ivars, direct_arg_value(arg))
      when "emit_at"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 3

        type = direct_arg_value(arg_nodes[0])
        value = direct_arg_value(arg_nodes[1])
        off = direct_arg_value(arg_nodes[2])
        push_self_hosted_lexer_token(
          ivars,
          { type: type, value: value, line: ivars["@line_at"][off], col: ivars["@col_at"][off], file: ivars["@file"] }
        )
      when "materialize_id"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 2

        materialize_self_hosted_lexer_id(ivars, direct_arg_value(arg_nodes[0]), direct_arg_value(arg_nodes[1]))
      when "materialize_op"
        len = small_arg_length_without_splat(arg_nodes)
        return NO_DIRECT_CALL unless len == 2

        materialize_self_hosted_lexer_op(ivars, direct_arg_value(arg_nodes[0]), direct_arg_value(arg_nodes[1]))
      else
        NO_DIRECT_CALL
      end
    end

    def push_self_hosted_lexer_token(ivars, tok)
      ivars["@tokens"].push(tok)
      ivars["@token_count"] += 1
      ivars["@last_token"] = tok
      type = hash_indifferent_get(tok, :type)
      ivars["@last_token_type"] = type
      ivars["@regex_capture_scope"] = true if type == :REGEX
      ivars["@regex_capture_scope"] = false if type == :NEWLINE || type == :SEMICOLON
      nil
    end

    def emit_self_hosted_lexer_token(ivars, type, value, off)
      push_self_hosted_lexer_token(
        ivars,
        { type: type, value: value, line: ivars["@line_at"][off], col: ivars["@col_at"][off], file: ivars["@file"] }
      )
    end

    def materialize_self_hosted_lexer_id(ivars, raw, off)
      if raw.start_with?("$")
        return emit_self_hosted_lexer_token(ivars, :GLOBAL, raw, off)
      end
      return NO_DIRECT_CALL if raw.start_with?("u0x") && raw.length == 19

      if raw == "and"
        emit_self_hosted_lexer_token(ivars, :AND, raw, off)
      elsif raw == "or"
        emit_self_hosted_lexer_token(ivars, :OR, raw, off)
      elsif TUNGSTEN_KEYWORDS[raw]
        emit_self_hosted_lexer_token(ivars, :KEYWORD, raw, off)
      elsif TUNGSTEN_TYPE_NAME_WORDS[raw]
        emit_self_hosted_lexer_token(ivars, :TYPE, raw, off)
      else
        emit_self_hosted_lexer_token(ivars, :ID, raw, off)
      end
    end

    def materialize_self_hosted_lexer_op(ivars, raw, off)
      if raw == "->" || raw.start_with?("->/")
        type = raw.start_with?("->/") ? :LAMBDA_ARITY : :ARROW
        return emit_self_hosted_lexer_token(ivars, type, raw, off)
      end

      last_type = ivars["@last_token_type"]
      if raw == "<<"
        type = LEXER_VALUE_TOKEN_TYPES[last_type] ? :LSHIFT : :PUTS_OP
        return emit_self_hosted_lexer_token(ivars, type, raw, off)
      end
      if raw == "+"
        type = LEXER_VALUE_TOKEN_TYPES[last_type] ? :PLUS : :CLASS_DEF
        return emit_self_hosted_lexer_token(ivars, type, raw, off)
      end
      if raw == "/" && !LEXER_VALUE_TOKEN_TYPES[last_type]
        lc = ivars["@lc"]
        if off + 1 < ivars["@char_count"] && (lc[off + 1] & 64) != 0
          return emit_self_hosted_lexer_token(ivars, :MAP, raw, off)
        end
      end

      type = LEXER_OP_TYPES[raw]
      return NO_DIRECT_CALL unless type

      emit_self_hosted_lexer_token(ivars, type, raw, off)
    end

    def sync_self_hosted_parser_current_token(ivars)
      if ivars["@pos"] < ivars["@token_count"]
        tok = ivars["@tokens"][ivars["@pos"]]
        ivars["@current_token"] = tok
        ivars["@current_type"] = hash_indifferent_get(tok, :type)
        ivars["@current_value"] = hash_indifferent_get(tok, :value)
        return tok
      end

      tok = ivars["@eof_token"]
      ivars["@current_token"] = tok
      ivars["@current_type"] = :EOF
      ivars["@current_value"] = nil
      tok
    end

    def skip_self_hosted_parser_tokens(ivars, type0, type1, type2, type3 = nil)
      loop do
        type = ivars["@current_type"]
        break unless type == type0 || type == type1 || type == type2 || type == type3

        if type == :TYPE_HINT
          ivars["@pending_type_hints"].push(ivars["@current_value"])
        end
        ivars["@pos"] += 1
        sync_self_hosted_parser_current_token(ivars)
      end
      nil
    end

    def call_builtin_from_nodes(recv, name, arg_nodes)
      len = small_arg_length_without_splat(arg_nodes)
      return NO_DIRECT_CALL unless len

      case name
      when "to_s"
        len == 0 ? recv.to_s : NO_DIRECT_CALL
      when "class"
        len == 0 ? class_object_for(recv) : NO_DIRECT_CALL
      when "class_name"
        len == 0 ? class_object_for(recv).name : NO_DIRECT_CALL
      when "nil?"
        len == 0 ? false : NO_DIRECT_CALL
      when "itself"
        len == 0 ? recv : NO_DIRECT_CALL
      when "is_a?"
        return NO_DIRECT_CALL unless len == 1

        target = evaluate(arg_nodes[0]).to_s
        klass = recv.w_class
        while klass
          return true if klass.name == target
          klass = klass.superclass
        end
        false
      when "respond_to?"
        return NO_DIRECT_CALL unless len == 1

        method_name = evaluate(arg_nodes[0]).to_s
        !!recv.w_class.lookup_method(method_name) ||
          @method_builtins.key?(method_name) ||
          BUILTIN_METHODS.include?(method_name) ||
          TYPE_INFO_METHODS.key?(method_name)
      else
        NO_DIRECT_CALL
      end
    end

    def call_ruby_method_from_nodes(recv, name, arg_nodes, block)
      return NO_DIRECT_CALL if hidden_ruby_object_method?(name)

      len = small_arg_length_without_splat(arg_nodes)
      return NO_DIRECT_CALL unless len

      case len
      when 0
        block ? recv.public_send(name) { |*bargs| invoke_block(block, bargs) } : recv.public_send(name)
      when 1
        arg0 = evaluate(arg_nodes[0])
        block ? recv.public_send(name, arg0) { |*bargs| invoke_block(block, bargs) } : recv.public_send(name, arg0)
      when 2
        arg0 = evaluate(arg_nodes[0])
        arg1 = evaluate(arg_nodes[1])
        if block
          recv.public_send(name, arg0, arg1) { |*bargs| invoke_block(block, bargs) }
        else
          recv.public_send(name, arg0, arg1)
        end
      when 3
        arg0 = evaluate(arg_nodes[0])
        arg1 = evaluate(arg_nodes[1])
        arg2 = evaluate(arg_nodes[2])
        if block
          recv.public_send(name, arg0, arg1, arg2) { |*bargs| invoke_block(block, bargs) }
        else
          recv.public_send(name, arg0, arg1, arg2)
        end
      end
    end

    def hidden_ruby_object_method?(name)
      HIDDEN_RUBY_OBJECT_METHODS.key?(name.to_s)
    end

    def instantiate_from_nodes(w_class, arg_nodes)
      obj = Runtime::WObject.new(w_class)
      constructor = w_class.lookup_method("new")
      call_w_method_from_nodes(obj, constructor, arg_nodes) if constructor
      obj
    end

    def bind_exact_small_args_from_nodes(env, params, arg_nodes, splat_index, memo)
      return false if memo || splat_index

      arg_len = arg_nodes ? arg_nodes.length : 0
      return false unless arg_len == params.length && arg_len <= 3

      case arg_len
      when 0
        true
      when 1
        param0 = params[0]
        arg0 = arg_nodes[0]
        return false if param0.default || arg0.is_a?(Tungsten::AST::Splat)

        env.set_slot(0, evaluate(arg0))
        true
      when 2
        param0 = params[0]
        param1 = params[1]
        arg0 = arg_nodes[0]
        arg1 = arg_nodes[1]
        return false if param0.default || param1.default
        return false if arg0.is_a?(Tungsten::AST::Splat) || arg1.is_a?(Tungsten::AST::Splat)

        env.set_slot(0, evaluate(arg0))
        env.set_slot(1, evaluate(arg1))
        true
      when 3
        param0 = params[0]
        param1 = params[1]
        param2 = params[2]
        arg0 = arg_nodes[0]
        arg1 = arg_nodes[1]
        arg2 = arg_nodes[2]
        return false if param0.default || param1.default || param2.default
        return false if arg0.is_a?(Tungsten::AST::Splat) || arg1.is_a?(Tungsten::AST::Splat) || arg2.is_a?(Tungsten::AST::Splat)

        env.set_slot(0, evaluate(arg0))
        env.set_slot(1, evaluate(arg1))
        env.set_slot(2, evaluate(arg2))
        true
      else
        false
      end
    end

    def new_param_env(parent, params, owner, barrier: false)
      slot_names = cached_param_slot_names(owner, params)
      return Environment.new(parent, barrier:) if slot_names.empty?

      Environment.new(parent, barrier:, slot_names:, undefined_from: params.length)
    end

    def new_free_var_env(parent, block, free_vars)
      return Environment.new(parent) if free_vars.empty?

      Environment.new(parent, slot_names: cached_free_var_slot_names(block, free_vars))
    end

    def cached_param_slot_names(owner, params)
      if owner.instance_variable_defined?(:@slot_names_template)
        owner.instance_variable_get(:@slot_names_template)
      else
        slot_names = {}
        i = 0
        while i < params.length
          slot_names[params[i].name] = i
          i += 1
        end
        collect_local_slot_names(callable_body(owner), slot_names)
        slot_names.freeze
        owner.instance_variable_set(:@slot_names_template, slot_names)
      end
    end

    def callable_body(owner)
      owner.respond_to?(:body) ? owner.body : nil
    end

    def collect_local_slot_names(node, slot_names)
      return unless node

      case node
      when AST::Assign
        collect_assign_target_slot_names(node.name, slot_names)
        collect_local_slot_names(node.value, slot_names)
      when AST::AssignOp
        # `x += y` requires `x` to already exist; do not pre-allocate a local
        # slot here, or it shadows captured outer vars in lambdas/methods.
        collect_local_slot_names(node.value, slot_names)
      when AST::With
        node.bindings.each do |var, expr|
          collect_assign_target_slot_names(var, slot_names)
          collect_local_slot_names(expr, slot_names)
        end
        collect_local_slot_names(node.body, slot_names)
      when AST::Def, AST::Fn
        add_local_slot_name(node.name, slot_names) if node.name
      when AST::Block, AST::ClassDef, AST::ModuleDef, AST::TraitDef
        nil
      else
        node.children { |child| collect_local_slot_names(child, slot_names) }
      end
    end

    def collect_assign_target_slot_names(target, slot_names)
      case target
      when AST::Var
        add_local_slot_name(target.name, slot_names) unless target.constant?
      when AST::Splat
        collect_assign_target_slot_names(target.exp, slot_names)
      when AST::ArrayLiteral
        target.list.each { |entry| collect_assign_target_slot_names(entry, slot_names) }
      end
    end

    def add_local_slot_name(name, slot_names)
      name = name.to_s
      slot_names[name] = slot_names.size unless slot_names.key?(name)
    end

    def cached_free_var_slot_names(block, free_vars)
      return EMPTY_SLOT_NAMES if free_vars.empty?

      if block.instance_variable_defined?(:@free_var_slot_names_template)
        block.instance_variable_get(:@free_var_slot_names_template)
      else
        slot_names = {}
        i = 0
        while i < free_vars.length
          slot_names[free_vars[i]] = i
          i += 1
        end
        slot_names.freeze
        block.instance_variable_set(:@free_var_slot_names_template, slot_names)
      end
    end

    def execute_callable_body(func, env, block)
      old_env = @env
      old_block = @current_block
      @env = env
      @current_block = block
      with_profile_callable(func) do
        body = func.body

        # The bytecode VM is still experimental and is slower than the tree
        # walker for common numeric loops, so keep it opt-in while tuning.
        if BYTECODE_ENABLED && !block && !func.instance_variable_get(:@bc_checked)
          func.instance_variable_set(:@bc_checked, true)
          bc = Bytecode::Compiler.new(func.args || EMPTY_ARGS).compile(body)
          func.instance_variable_set(:@bytecode, bc) if bc
        end

        bc = func.instance_variable_get(:@bytecode)
        if bc
          begin
            return (@bc_vm ||= Bytecode::VM.new(self)).execute(bc, env)
          rescue => e
            # Bytecode execution failed (e.g. unsupported op hit) — fall through to tree-walker
            func.instance_variable_set(:@bytecode, nil)
          ensure
            @current_block = old_block
            @env = old_env
          end
        end

        if func.instance_variable_defined?(:@has_return)
          hr = func.instance_variable_get(:@has_return)
        else
          hr = Interpreter.body_has_return?(body)
          func.instance_variable_set(:@has_return, hr)
        end
        begin
          hr ? catch(RETURN_SIGNAL) { evaluate(body) } : evaluate(body)
        ensure
          @current_block = old_block
          @env = old_env
        end
      end
    end

    def bind_params(env, params, args, splat_index)
      len = params.size
      if splat_index
        i = 0
        while i < len
          param = params[i]
          if i < splat_index
            env.set_slot(i, args[i])
          elsif i == splat_index
            splat_count = [args.size - len + 1, 0].max
            env.set_slot(i, args[i, splat_count])
          else
            env.set_slot(i, args[args.size - len + i])
          end
          i += 1
        end
      else
        i = 0
        while i < len
          param = params[i]
          if i < args.size
            env.set_slot(i, args[i])
          elsif param.default
            env.set_slot(i, evaluate(param.default))
          else
            raise Tungsten::Error, "missing argument: #{param.name}"
          end
          i += 1
        end
      end
    end

    def invoke_method_builtin(method_builtin, recv, args, block)
      invoke_builtin(method_builtin, recv, args, block)
    end

    def invoke_builtin(builtin, recv, args, block)
      # Auto-convert a lambda argument to a block if no block is given
      if !block && args.last.is_a?(Tungsten::AST::Def)
        block = args.pop
      end

      blk =
        if block.is_a?(Tungsten::AST::Def)
          proc { |*bargs| call_lambda_with_values(block, bargs) }
        elsif block
          proc { |*bargs| invoke_block(block, bargs) }
        end
      builtin.call(recv, args, blk)
    end

    def call_lambda_with_values(func, values)
      closure_env = func.closure_env || @env
      params = func.args || EMPTY_ARGS
      method_env = new_param_env(closure_env, params, func, barrier: true)
      params.each_index do |i|
        method_env.set_slot(i, i < values.size ? values[i] : nil)
      end

      old_env = @env
      @env = method_env
      with_profile_callable(func) do
        body = func.body
        if func.instance_variable_defined?(:@has_return)
          hr = func.instance_variable_get(:@has_return)
        else
          hr = Interpreter.body_has_return?(body)
          func.instance_variable_set(:@has_return, hr)
        end
        begin
          hr ? catch(RETURN_SIGNAL) { evaluate(body) } : evaluate(body)
        ensure
          @env = old_env
        end
      end
    end

    def hash_indifferent_get(hash, key)
      val = hash.fetch(key, HASH_MISS)
      return val unless val.equal?(HASH_MISS)

      # Try alternate key form (symbol ↔ string only)
      if key.is_a?(::Symbol)
        hash[key.name]
      elsif key.is_a?(String)
        hash[key.to_sym]
      end
    end

    def wyhash_mix_u64_value(a, b)
      product = (a & WYHASH_U64_MASK) * (b & WYHASH_U64_MASK)
      ((product >> 64) ^ product) & WYHASH_U64_MASK
    end

    def wyhash_read_u32_value(text, offset)
      text.getbyte(offset) |
        (text.getbyte(offset + 1) << 8) |
        (text.getbyte(offset + 2) << 16) |
        (text.getbyte(offset + 3) << 24)
    end

    def wyhash_read_u64_value(text, offset)
      text.getbyte(offset) |
        (text.getbyte(offset + 1) << 8) |
        (text.getbyte(offset + 2) << 16) |
        (text.getbyte(offset + 3) << 24) |
        (text.getbyte(offset + 4) << 32) |
        (text.getbyte(offset + 5) << 40) |
        (text.getbyte(offset + 6) << 48) |
        (text.getbyte(offset + 7) << 56)
    end

    def wyhash64_string_value(text)
      len = text.bytesize
      s0 = 0xA076_1D64_78BD_642F
      s1 = WYHASH_S1
      s2 = 0x8EBC_6AF0_9C88_C6E3
      s3 = 0x5899_65CC_7537_4CC3
      seed = 0x1234_5678_90AB_CDEF
      a = 0
      b = 0

      if len <= 16
        if len >= 4
          head_offset = (len >> 3) << 2
          tail_offset = len - 4
          tail_head_offset = len - 4 - head_offset
          a = (wyhash_read_u32_value(text, 0) << 32) | wyhash_read_u32_value(text, head_offset)
          b = (wyhash_read_u32_value(text, tail_offset) << 32) | wyhash_read_u32_value(text, tail_head_offset)
        elsif len.positive?
          first = text.getbyte(0)
          middle = text.getbyte(len >> 1)
          last = text.getbyte(len - 1)
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
            d0 = wyhash_read_u64_value(text, offset)
            d1 = wyhash_read_u64_value(text, offset + 8)
            d2 = wyhash_read_u64_value(text, offset + 16)
            d3 = wyhash_read_u64_value(text, offset + 24)
            d4 = wyhash_read_u64_value(text, offset + 32)
            d5 = wyhash_read_u64_value(text, offset + 40)
            s0v = wyhash_mix_u64_value(d0 ^ s1, d1 ^ s0v)
            s1v = wyhash_mix_u64_value(d2 ^ s2, d3 ^ s1v)
            s2v = wyhash_mix_u64_value(d4 ^ s3, d5 ^ s2v)
            offset += 48
            i -= 48
          end
          seed = s0v ^ s1v ^ s2v
        end
        while i > 16
          d0 = wyhash_read_u64_value(text, offset)
          d1 = wyhash_read_u64_value(text, offset + 8)
          seed = wyhash_mix_u64_value(d0 ^ s1, d1 ^ seed)
          offset += 16
          i -= 16
        end
        a = wyhash_read_u64_value(text, offset + i - 16)
        b = wyhash_read_u64_value(text, offset + i - 8)
      end

      wyhash_mix_u64_value(s1 ^ len, wyhash_mix_u64_value(a ^ s1, b ^ seed))
    end

    TUNGSTEN_TYPE_NAMES = {
      Integer    => "Int",
      ::Float    => "Float",
      BigDecimal => "Decimal",
      ::Rational => "Rational",
      ::String   => "String",
      ::Symbol   => "Symbol",
      ::Array    => "List",
      ::Hash     => "Map",
      ::Range    => "Range",
      TrueClass  => "Bool",
      FalseClass => "Bool",
      NilClass   => "Nil",
    }.freeze

    def tungsten_class_name(recv)
      case recv
      when Tungsten::ByteArray    then "ByteArray"
      when Tungsten::CharValue    then "Char"
      when Tungsten::StringBuffer then "StringBuffer"
      when Tungsten::PathValue    then "Path"
      when Tungsten::Literal      then recv.class.name.split("::").last
      when Tungsten::Quantity     then "Quantity"
      when Tungsten::Currency     then "Currency"
      when Tungsten::Duration     then "Duration"
      when Tungsten::Percentage   then "Percentage"
      when Tungsten::Key          then "Key"
      else TUNGSTEN_TYPE_NAMES[recv.class] || recv.class.name.split("::").last
      end
    end

    def primitive_runtime_class(recv)
      name =
        case recv
        when ::Array then "Array"
        when ::Hash then "Hash"
        when ::String then "String"
        when ::Symbol then "Symbol"
        when Tungsten::CharValue then "Char"
        when ::Integer then "Integer"
        when ::Float then "Float"
        when TrueClass, FalseClass then "Bool"
        when NilClass then "Nil"
        end

      name && @classes[name]
    end

    # The class object for `.class` dispatch. Returns the WClass for
    # WObject instances, the auto-created WClass stub for primitives
    # (populated at boot from BUILTIN_TYPES), or a freshly-cached stub
    # if neither path finds one. Always returns a WClass so callers
    # can chain `.name`, `.superclass`, etc.
    #
    # Receiver is itself a WClass → return the singleton "Class" WClass
    # (Class.class == Class, Integer.class == Class). The fixpoint matches
    # Ruby: Class.class.class.class is the same identity.
    def class_object_for(recv)
      return class_class_singleton if recv.is_a?(Tungsten::Runtime::WClass)
      return recv.w_class if recv.respond_to?(:w_class) && recv.w_class
      primitive_runtime_class(recv) || begin
        cname = tungsten_class_name(recv)
        @class_stub_cache ||= {}
        @class_stub_cache[cname] ||= Tungsten::Runtime::WClass.new(cname)
      end
    end

    def class_class_singleton
      @classes["Class"] ||= Tungsten::Runtime::WClass.new("Class")
    end

    def tungsten_type_info(recv, method)
      case method
      when "class"
        class_object_for(recv)
      when "class_name"
        class_object_for(recv).name
      when "superclass"
        nil
      when "ancestors"
        [tungsten_class_name(recv)]
      end
    end

    def call_builtin(recv, name, args)
      case name
      when "to_s"       then recv.to_s
      when "class"      then class_object_for(recv)
      when "class_name" then class_object_for(recv).name
      when "nil?"    then false
      when "itself" then recv
      when "is_a?"
        target = args[0].to_s
        klass = recv.w_class
        while klass
          return true if klass.name == target
          klass = klass.superclass
        end
        false
      when "respond_to?"
        method_name = args[0].to_s
        !!recv.w_class.lookup_method(method_name) ||
          @method_builtins.key?(method_name) ||
          BUILTIN_METHODS.include?(method_name) ||
          TYPE_INFO_METHODS.key?(method_name)
      end
    end

    def catch_break_if_needed(body)
      if Interpreter.body_has_break?(body)
        catch(BREAK_SIGNAL) { yield }
      else
        yield
      end
    end

    def catch_next_if_needed(body)
      if Interpreter.body_has_next?(body)
        catch(NEXT_SIGNAL) { yield }
      else
        yield
      end
    end

    def iterate_with(bindings, collections, depth, body, body_has_next:)
      var, = bindings[depth]
      collections[depth].each do |val|
        @env.set(var.name, val)
        if depth + 1 < bindings.size
          iterate_with(bindings, collections, depth + 1, body, body_has_next:) { |r| yield r }
        else
          body_has_next ? catch(NEXT_SIGNAL) { yield evaluate(body) } : yield(evaluate(body))
        end
      end
    end

    def substance_mass(qty, substance)
      load_quantity_support
      substance_mass(qty, substance)
    end

    def truthy?(value)
      value != false && !value.nil?
    end

    def w_to_s(value)
      case value
      when nil then "nil"
      when BigDecimal
        # BigDecimal#to_s defaults to engineering notation ("0.15e1"); print the
        # plain form to match the compiled path (1.5, 0.3), with whole values as
        # integers (100.0 -> "100"). Guard non-finite so #to_i can't raise.
        value.finite? && value.frac.zero? ? value.to_i.to_s : value.to_s("F")
      else value.to_s
      end
    end

    def resolve_builtin_constant(name)
      name = name.to_s
      case name
      when "ARGV" then argv
      when "SecureRandom"
        require "securerandom"
        SecureRandom
      when "π" then Math::PI
      when "τ" then Math::PI * 2
      when "ϕ", "φ" then (1 + Math.sqrt(5)) / 2.0
      when "ℯ" then Math::E
      when "ℇ" then 0.5772156649015329
      when "∞" then Float::INFINITY
      when "α" then 7.2973525643e-3
      when "ℎ", "ℏ", "c", "G", "g₀", "Nₐ", "kB", "e₀", "R", "ε₀", "μ₀", "µ₀", "σ", "mₑ", "mₚ", "a₀", "Eₕ", "Ry", "𝐹"
        load_builtin_constant_support
        resolve_builtin_constant(name)
      else Environment::UNDEFINED
      end
    end

    if DISPATCH_PROFILE_ENABLED
      module DispatchProfiling
        def evaluate(node)
          profile_dispatch_path("evaluate node class", node.class.name)
          super
        end

        def visit_call(node)
          profile_dispatch_path("visit_call form", node.obj ? "receiver" : "bare")
          profile_dispatch_path("visit_call name", node.name.to_s)
          super
        end

        def visit_binary_op(node)
          profile_dispatch_path("visit_binary_op operator", node.operator)
          super
        end

        def visit_assign_op(node)
          profile_dispatch_path("visit_assign_op operator", node.operator)
          super
        end

        def call_function_intrinsic_from_nodes(func, arg_nodes)
          profile_dispatch_path("function intrinsic dispatch", func.name.to_s)
          super
        end

        def simple_while_arithmetic(left, op, right)
          profile_dispatch_path("simple_while_arithmetic operator", op)
          super
        end

        def simple_while_compare(left, op, right)
          profile_dispatch_path("simple_while_compare operator", op)
          super
        end

        def direct_arg_value(node)
          profile_dispatch_path("direct_arg_value node class", node.class.name)
          super
        end

        def call_primitive_method_from_nodes(recv, name, arg_nodes, block)
          profile_dispatch_path("primitive method dispatch", name)
          super
        end

        def call_self_hosted_parser_intrinsic_from_nodes(recv, method, arg_nodes)
          profile_dispatch_path("self_hosted_parser_intrinsic", method.name)
          super
        end

        def call_builtin_from_nodes(recv, name, arg_nodes)
          profile_dispatch_path("w_object builtin dispatch", name)
          super
        end

        def call_builtin(recv, name, args)
          profile_dispatch_path("w_object builtin fallback dispatch", name)
          super
        end
      end

      prepend DispatchProfiling
    end
  end
end
