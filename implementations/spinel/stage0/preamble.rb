# frozen_string_literal: true

$stage0_argv = "\n"

# AST class with stub singleton methods. The bundle's
# implementations/ruby/lib/tungsten/ast/node.rb defines `def self.intern_name`
# inside `module Tungsten::AST`; flatten_namespaces strips that outer
# module, leaving the def at top-level. AST is still referenced as
# `AST.intern_name(name)` from Arg/Var/etc constructors though, so we
# define an AST class here whose class methods delegate to plain
# String#to_s. Spinel resolves `AST.intern_name` via this class.
class AST
  def self.intern_name(name)
    return nil if name.nil?
    name.to_s
  end

  def self.intern_name_without_prefix(name, prefix)
    value = name.to_s
    return intern_name(value) unless value.start_with?(prefix)
    value[prefix.length..]
  end
end

# kind_sym_table_data — mirror of compiler/lib/ast_schema.w:305. The
# table maps slab-node kind ids → :symbol literals. Stage 0 can't run
# the top-level `kind_sym_table_data = [...]` assign in ast_schema.w
# (the visit_list loading-depth filter skips non-(def|use|class|
# module|trait) statements in `use`d files, and relaxing that filter
# triggers heavy evaluation chains elsewhere — gets stage 0 stuck in
# multi-minute loops). visit_call's :ccall arm intercepts
# w_node_kind_sym to look up this table directly via
# stage0_kind_sym_table(idx) below. Keep in sync if the schema
# changes — the schema_hash check upstream catches drift.
def stage0_kind_sym_table
  return @stage0_kind_sym_table if @stage0_kind_sym_table
  @stage0_kind_sym_table = [
    nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, nil, nil, :nil_lit, :self_ref, :view_base, :view_value, :return,
    nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
    nil, nil, nil, :and, :array, :assign, :begin, :binary_op, :block, :bool,
    :break, :byte_array, :byte_array_interp, :call, :case, :case_arm, :case_value, :char, :cidr4, :class_def,
    :codepoint, :color, :compound_assign, :currency, :cvar, :date, :datetime, :decimal, :duration, :encoded,
    :extern_fn, :extern_lib, :field_decl, :float, :fn_def, :go, :gpu_kernel_def, :hash_literal, :if, :in_test,
    :int, :ip4, :ivar, :key, :lambda_arity, :layout_def, :magic_constant, :map_op, :method_def, :module_def,
    :month, :multi_assign, :next, nil, :not, :on_guard, :or, :parallel_with, :param, :parg,
    :passthrough, :print, :program, :puts, :quantity, :raise, :range, :rational, :regex, :regex_capture,
    :rescue_expr, :return, :safe_nav, :schedule_def, nil, :string, :string_interp, :super, :superscript, :symbol,
    :symbol_array, :target_and, :target_designator, :target_not, :target_or, :time, :trait_def, :trait_include, :typed_array, :typed_array_new,
    :unary_op, :use, :uuid, :var, :view_access, nil, :view_decl, :view_field, nil, :when,
    :while, :with, :word_array, :wvalue, :yield
  ]
end

module Tungsten
  LEXER_MODE_ENV = "TUNGSTEN_LEXER"

  class Error < StandardError
    attr_accessor :location, :source_code, :file_path, :call_stack, :name_length

    def initialize(message = "")
      @message = message
    end

    def to_s
      @message
    end
  end

  class DimensionError < Error
  end
end
