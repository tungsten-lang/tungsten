use core/blas

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

zero_scale_x = f64_array(1)
zero_scale_x[0] = ~3.0

-> scale_zero
  dscal(2, zero_scale_x, 1)

# Bare zero-argument calls parse as Var rather than Call nodes.
fn invoke_zero
  scale_zero

# A mutating BLAS ccall must execute on every call, including when it is hidden
# behind forward, deep, recursive, or nested-container top-level helpers. If
# lowering misclassifies any caller as pure, fn memoization elides the second
# scale and leaves 6 rather than 12.
fn scale_direct(x)
  ccall("w_blas_dscal", ~2.0, x, 1)

fn scale_once(x)
  dscal(2, x, 1)

# Caller intentionally precedes both helpers: impurity must be source-order
# independent and propagate through an arbitrary-depth ordinary `->` chain.
fn scale_deep_forward(x)
  scale_deep_mid(x)

-> scale_deep_mid(x)
  scale_deep_leaf(x)

-> scale_deep_leaf(x)
  dscal(2, x, 1)

# elsif clauses and hash entries are represented as nested pair Arrays in the
# AST. The graph walker must recurse through those containers too.
fn scale_in_elsif(x, branch)
  if branch == 0
    x
  elsif branch == 1
    scale_deep_leaf(x)
  else
    x

fn scale_in_hash(x)
  {scaled: scale_deep_leaf(x)}

# Only cycle_seed directly reaches the impure bridge. cycle_peer must become
# impure through reverse reachability across the recursive SCC.
fn cycle_seed(x, depth)
  if depth == 0
    dscal(2, x, 1)
  else
    cycle_peer(x, depth - 1)

fn cycle_peer(x, depth)
  if depth == 0
    x
  else
    cycle_seed(x, depth - 1)

# This disconnected fn must remain eligible for memoization. The WIRE
# gate asserts that its calls still lower through memo_call1_i64 while every
# impure function above lowers through direct calls.
fn pure_echo(value)
  value

direct_x = f64_array(1)
direct_x[0] = ~3.0
scale_direct(direct_x)
scale_direct(direct_x)
expect("compiler direct mutating ccall is impure", direct_x[0] == ~12.0)

invoke_zero()
invoke_zero()
expect("compiler zero-arg Var wrapper is impure", zero_scale_x[0] == ~12.0)

wrapper_x = f64_array(1)
wrapper_x[0] = ~3.0
scale_once(wrapper_x)
scale_once(wrapper_x)
expect("compiler wrapper reaches mutating ccall", wrapper_x[0] == ~12.0)

deep_x = f64_array(1)
deep_x[0] = ~3.0
scale_deep_forward(deep_x)
scale_deep_forward(deep_x)
expect("compiler forward deep wrapper is impure", deep_x[0] == ~12.0)

elsif_x = f64_array(1)
elsif_x[0] = ~3.0
scale_in_elsif(elsif_x, 1)
scale_in_elsif(elsif_x, 1)
expect("compiler nested elsif call propagates impurity", elsif_x[0] == ~12.0)

hash_x = f64_array(1)
hash_x[0] = ~3.0
scale_in_hash(hash_x)
scale_in_hash(hash_x)
expect("compiler nested hash call propagates impurity", hash_x[0] == ~12.0)

cycle_x = f64_array(1)
cycle_x[0] = ~3.0
cycle_peer(cycle_x, 1)
cycle_peer(cycle_x, 1)
expect("compiler recursive SCC propagates impurity", cycle_x[0] == ~12.0)

expect("compiler disconnected pure fn remains correct", pure_echo("memo") == "memo")
expect("compiler disconnected pure fn repeat remains correct", pure_echo("memo") == "memo")
