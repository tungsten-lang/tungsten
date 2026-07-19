# Tungsten Spec — a behavior-driven testing framework for Tungsten.
# Inspired by RSpec: describe/context/it blocks, expect(...).to matchers,
# before/after hooks, and a pass/fail summary with a non-zero exit code
# on failure. Runs interpreted (bin/tungsten spec_file.w) and compiled
# (bin/tungsten -o) with identical output.
#
# Usage:
#   use spec
#
#   describe "Calculator" ->
#     context "addition" ->
#       it "adds two numbers" ->
#         expect(Calculator.add(2, 3)).to eq(5)
#
#   spec_summary   # prints "N examples: N passed, M failed"; exits 1 on failure
#
# v1 design notes (constraints verified by probe — do not "clean up"
# without re-probing both engines):
#   - Examples run IMMEDIATELY as the spec file evaluates; describe/context
#     maintain an indentation/hook stack rather than building a deferred
#     tree. There is no at_exit, so end every spec file with `spec_summary`
#     (alias: TungstenSpec.done).
#   - A failed expectation FLAGS $spec_current_failure instead of raising:
#     raising after any nested closure `.call` has completed inside the
#     same method chain segfaults the interpreter. Consequence: an example
#     keeps executing past a failed expect; the first failure is reported.
#   - Matchers are lambda-free classes (same segfault: a matcher holding
#     `-> (actual) ...` lambdas crashes on the failure path).
#   - Runtime errors raised by an example body ARE caught (`rescue e`
#     receives the message string) and fail just that example.
#   - Zero-arg DSL calls taking a block need parens: `before_each() ->`
#     (paren-less `name ->` is the implicit-.each iteration syntax).
#   - `spec_configure() -> ...` registers global hooks on both engines;
#     TungstenSpec.configure works interpreted only (compiled class-static
#     methods never receive an attached block).
#   - No instance_eval/method_missing exist, so `let`/`subject` bindings
#     cannot be injected as bare names; they are accepted but inert (see
#     context.w). Bind values inside the example instead.
#
# All definitions are top-level (no `in Tungsten:Spec`): namespaced bit
# classes are not reliably visible to `use spec` consumers today, and a
# flat framework that loads beats a namespaced one that doesn't.

use expectation
use matchers
use runner
use hooks
use context
use mock
