# tungsten/languages/ruby/ruby.w — Tungsten's Ruby 3.4 / 4.0 language library.
#
# Parses Ruby 3.4 / 4.0 directly onto Tungsten's AST node vocabulary (with tracked
# superset extension nodes for singleton_class, pattern matching, complex, defined?,
# alias/undef, redo/retry, stabby lambdas), executes Ruby with full Ruby semantics
# (mutable strings + Encoding + frozen_string_literal, floor integer division + BigInt +
# Rational + Complex + Numeric#coerce, Regexp + MatchData + named capture locals + $~,
# open classes + eigenclasses + prepend/include/extend + Struct + Data.define, blocks +
# Proc + lambda + Ruby 3.4 `it` + non-local return, pattern matching, exceptions), and
# provides a direct zero-copy Ruby <-> Tungsten calling protocol via `Tungsten`.
#
# Quick start:
#   use core/ruby                         # or use languages/ruby/ruby
#   Ruby.eval("1 + 2 * 3")                # => 7
#   Ruby.eval("(1/3r + 1/6r).to_s")       # => "1/2"
#   vm = Ruby.vm
#   vm.register("hypot", ->(a) Math.sqrt(a[0]*a[0] + a[1]*a[1]))
#   vm.eval("Tungsten.hypot(3.0, 4.0)")   # => 5.0
#   Ruby.to_tungsten_ast("def f(x) = x * 2")

use ast
use lexer_full
use parser_full
use vm
use runtime

+ Ruby
  -> .vm
    RbVM.new

  -> .parse(source)
    rb_parse(source)

  -> .to_tungsten_ast(source)
    rb_to_tungsten_ast(rb_parse(source))

  -> .ast_extensions(source)
    rb_ast_superset_extensions(rb_parse(source))

  -> .eval(source, vm = nil)
    v = vm == nil ? RbVM.new : vm
    rb_to_tungsten(v.eval_source(source))

  -> .eval_raw(source, vm = nil)
    v = vm == nil ? RbVM.new : vm
    v.eval_source(source)
