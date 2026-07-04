# mini_interp.rb — a small tree-walking interpreter that is structurally
# representative of the Tungsten Ruby interpreter's HOT PATHS, but tiny
# enough to compile (spinel) in seconds and run a bounded workload.
#
# Why this exists: the full Tungsten bundle takes minutes to build via
# spinel and minutes more to run stage 1, which makes iterating on the
# matz-#282 perf levers painfully slow. This program reproduces the same
# per-operation costs the levers target at a fraction of the build time,
# so we can measure DIRECTIONAL improvement quickly.
#
# Representation: the AST is held in PARALLEL FLAT ARRAYS indexed by node
# id (nd_kind[id], nd_a[id], ...). Statement/arg lists and function param
# names are flattened into single flat arrays addressed by (start,len)
# offsets — NO arrays-of-arrays — so spinel compiles it with zero type
# overrides (empty `[]` infers int_array and an array-of-int_array would
# need the bundle's gated @list poly_array override; flattening sidesteps
# that entirely). Variable / function names stay STRINGS so the
# Environment remains a string-keyed hash — the single most important
# lever-1 hot path matz called out.
#
# Hot paths exercised (matz #282):
#   1. env_get/env set — string-keyed hash lookup per variable read.
#      (Lever 1: slot env. matz's #1 by a wide margin.)
#   3. visit_call allocates a fresh env hash + an args array per call,
#      binds params by string name. (Lever 3: stack-promote env frames;
#      the sp_PolyArray / sp_Environment pools.)
#   + the integer-kind evaluate() dispatch cascade.
#
# Workload: recursive fib (call/env/arg heavy) + a counting loop
# (assign/lookup heavy). No lexer/parser — the AST is built directly so
# the benchmark measures EVALUATION, which is what the levers optimize.

K_INT    = 1   # integer literal:   a = value
K_VAR    = 2   # variable read:     name
K_ASSIGN = 3   # assignment:        name, a = value-expr id
K_BINOP  = 4   # binary op:         b = op, a = left id, c = right id
K_IF     = 5   # conditional:       a = cond id, b = then list, c = else list (-1 = none)
K_WHILE  = 6   # loop:              a = cond id, b = body list
K_CALL   = 7   # function call:     name, a = args list
K_RETURN = 8   # return:            a = value-expr id

OP_ADD = 0
OP_SUB = 1
OP_MUL = 2
OP_LT  = 3
OP_EQ  = 4

class Interp
  attr_accessor :nd_kind, :nd_a, :nd_b, :nd_c, :nd_name,
                :list_start, :list_len, :list_items,
                :fn_param_start, :fn_param_len, :fn_param_items, :fn_body, :fn_index,
                :env_values, :returning, :return_value

  def initialize
    # Parallel AST arrays (all int_array except names). Index 0 reserved.
    @nd_kind = [0]
    @nd_a = [0]
    @nd_b = [0]
    @nd_c = [0]
    @nd_name = [""]
    # Flat list storage: a list id -> (start,len) into @list_items.
    @list_start = []
    @list_len = []
    @list_items = []
    # Flat function tables: fn id -> (param start,len) into @fn_param_items,
    # plus a body list id.
    @fn_param_start = []
    @fn_param_len = []
    @fn_param_items = [""]   # seed with "" so spinel infers str_array
    @fn_body = []
    @fn_index = {}           # function name -> fn id (string-keyed)
    # Current call frame: string-keyed int hash (THE lever-1 hot path).
    @env_values = {}
    @returning = false
    @return_value = 0
  end

  # ---- AST construction (returns a node id) ----
  def new_node(kind)
    @nd_kind.push(kind)
    @nd_a.push(0)
    @nd_b.push(0)
    @nd_c.push(0)
    @nd_name.push("")
    @nd_kind.length - 1
  end

  def mk_int(v)
    id = new_node(K_INT)
    @nd_a[id] = v
    id
  end

  def mk_var(name)
    id = new_node(K_VAR)
    @nd_name[id] = name
    id
  end

  def mk_assign(name, expr_id)
    id = new_node(K_ASSIGN)
    @nd_name[id] = name
    @nd_a[id] = expr_id
    id
  end

  def mk_binop(op, left_id, right_id)
    id = new_node(K_BINOP)
    @nd_b[id] = op
    @nd_a[id] = left_id
    @nd_c[id] = right_id
    id
  end

  def mk_if(cond_id, then_list, else_list)
    id = new_node(K_IF)
    @nd_a[id] = cond_id
    @nd_b[id] = then_list
    @nd_c[id] = else_list
    id
  end

  def mk_while(cond_id, body_list)
    id = new_node(K_WHILE)
    @nd_a[id] = cond_id
    @nd_b[id] = body_list
    id
  end

  def mk_call(name, args_list)
    id = new_node(K_CALL)
    @nd_name[id] = name
    @nd_a[id] = args_list
    id
  end

  def mk_return(expr_id)
    id = new_node(K_RETURN)
    @nd_a[id] = expr_id
    id
  end

  # Append a flat list of node ids; returns a list id.
  def add_list(ids)
    start = @list_items.length
    n = ids.length
    i = 0
    while i < n
      @list_items.push(ids[i])
      i += 1
    end
    @list_start.push(start)
    @list_len.push(n)
    @list_start.length - 1
  end

  # Append a function; param_names is a str_array. Returns fn id.
  def define_fn(name, param_names, body_list)
    pstart = @fn_param_items.length
    pn = param_names.length
    i = 0
    while i < pn
      @fn_param_items.push(param_names[i])
      i += 1
    end
    fid = @fn_body.length
    @fn_param_start.push(pstart)
    @fn_param_len.push(pn)
    @fn_body.push(body_list)
    @fn_index[name] = fid
    fid
  end

  # ---- Evaluation ----
  def evaluate(id)
    k = @nd_kind[id]
    if k == K_INT
      return @nd_a[id]
    end
    if k == K_VAR
      return @env_values[@nd_name[id]]
    end
    if k == K_ASSIGN
      v = evaluate(@nd_a[id])
      @env_values[@nd_name[id]] = v
      return v
    end
    if k == K_BINOP
      return visit_binop(id)
    end
    if k == K_IF
      return visit_if(id)
    end
    if k == K_WHILE
      return visit_while(id)
    end
    if k == K_CALL
      return visit_call(id)
    end
    if k == K_RETURN
      @return_value = evaluate(@nd_a[id])
      @returning = true
      return @return_value
    end
    0
  end

  def visit_binop(id)
    a = evaluate(@nd_a[id])
    b = evaluate(@nd_c[id])
    op = @nd_b[id]
    if op == OP_ADD
      return a + b
    end
    if op == OP_SUB
      return a - b
    end
    if op == OP_MUL
      return a * b
    end
    if op == OP_LT
      return a < b ? 1 : 0
    end
    if op == OP_EQ
      return a == b ? 1 : 0
    end
    0
  end

  def visit_if(id)
    c = evaluate(@nd_a[id])
    if c != 0
      return run_list(@nd_b[id])
    end
    else_list = @nd_c[id]
    if else_list >= 0
      return run_list(else_list)
    end
    0
  end

  def visit_while(id)
    result = 0
    cond_id = @nd_a[id]
    body_list = @nd_b[id]
    while evaluate(cond_id) != 0
      result = run_list(body_list)
      break if @returning
    end
    result
  end

  # Run a statement list (flat slice), stop early on return.
  def run_list(list_id)
    start = @list_start[list_id]
    n = @list_len[list_id]
    result = 0
    i = 0
    while i < n
      result = evaluate(@list_items[start + i])
      break if @returning
      i += 1
    end
    result
  end

  # Function call: evaluate args into a fresh array (per-call sp_PolyArray),
  # allocate a fresh env hash (per-call sp_Environment), bind params by
  # string name, run the body. The call_w_method + bind_params +
  # evaluate_args composite the levers most affect.
  def visit_call(id)
    name = @nd_name[id]
    fid = @fn_index[name]

    args_list = @nd_a[id]
    astart = @list_start[args_list]
    argc = @list_len[args_list]
    # evaluate_args: one fresh array per call.
    arg_vals = []
    i = 0
    while i < argc
      arg_vals.push(evaluate(@list_items[astart + i]))
      i += 1
    end

    # New call frame: fresh string-keyed hash (per-call env alloc).
    new_env = {}
    pstart = @fn_param_start[fid]
    pcount = @fn_param_len[fid]
    j = 0
    while j < pcount
      pname = @fn_param_items[pstart + j]
      if j < argc
        new_env[pname] = arg_vals[j]
      else
        new_env[pname] = 0
      end
      j += 1
    end

    prev_env = @env_values
    prev_returning = @returning
    prev_return_value = @return_value
    @env_values = new_env
    @returning = false
    @return_value = 0

    run_list(@fn_body[fid])
    result = @return_value

    @env_values = prev_env
    @returning = prev_returning
    @return_value = prev_return_value
    result
  end
end

# ---- Build workload ----
# Sized so the spinel-compiled run is ~2-3s — long enough that lever
# deltas (10-40%) sit well above startup noise, short enough to iterate.
# fib is call/env/arg-heavy; sumloop is assign/lookup-heavy.
FIB_N = 33
SUM_LIMIT = 10000000

ip = Interp.new

# fn fib(n):
#   if n < 2: return n
#   return fib(n-1) + fib(n-2)
fib_then = ip.add_list([ip.mk_return(ip.mk_var("n"))])
fib_guard = ip.mk_if(ip.mk_binop(OP_LT, ip.mk_var("n"), ip.mk_int(2)), fib_then, -1)
fib_rec = ip.mk_binop(
  OP_ADD,
  ip.mk_call("fib", ip.add_list([ip.mk_binop(OP_SUB, ip.mk_var("n"), ip.mk_int(1))])),
  ip.mk_call("fib", ip.add_list([ip.mk_binop(OP_SUB, ip.mk_var("n"), ip.mk_int(2))]))
)
fib_body = ip.add_list([fib_guard, ip.mk_return(fib_rec)])
ip.define_fn("fib", ["n"], fib_body)

# fn sumloop(limit):
#   i = 0; acc = 0
#   while i < limit: acc = acc + i; i = i + 1
#   return acc
sum_loop_body = ip.add_list([
  ip.mk_assign("acc", ip.mk_binop(OP_ADD, ip.mk_var("acc"), ip.mk_var("i"))),
  ip.mk_assign("i", ip.mk_binop(OP_ADD, ip.mk_var("i"), ip.mk_int(1)))
])
sum_body = ip.add_list([
  ip.mk_assign("i", ip.mk_int(0)),
  ip.mk_assign("acc", ip.mk_int(0)),
  ip.mk_while(ip.mk_binop(OP_LT, ip.mk_var("i"), ip.mk_var("limit")), sum_loop_body),
  ip.mk_return(ip.mk_var("acc"))
])
ip.define_fn("sumloop", ["limit"], sum_body)

# ---- Run ----
fib_call = ip.mk_call("fib", ip.add_list([ip.mk_int(FIB_N)]))
fib_result = ip.evaluate(fib_call)
puts "fib(" + FIB_N.to_s + ") = " + fib_result.to_s

sum_call = ip.mk_call("sumloop", ip.add_list([ip.mk_int(SUM_LIMIT)]))
sum_result = ip.evaluate(sum_call)
puts "sumloop(" + SUM_LIMIT.to_s + ") = " + sum_result.to_s
