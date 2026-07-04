# mini_interp_pool.rb — lever-3 (no per-call allocation) variant.
#
# Builds on mini_interp_slots.rb (static slot resolution) and changes ONLY
# the allocation strategy: instead of allocating a fresh IntArray env frame
# + a fresh args array on every call, frames live as (base, nslots) regions
# in a SINGLE pre-grown value stack. Call entry just bumps a stack pointer;
# call exit restores it. Zero per-call heap allocation. This is matz's
# lever 3 ("stack-promote env frames whose escape we can prove") taken to
# its limit — the canonical interpreter value-stack.
#
# Isolation: vs mini_interp_slots.rb (same static-slot env access, but
# allocates a fresh frame per call) the ONLY difference is allocation, so
# slots→pool measures lever 3 directly. The profile showed ~61% of
# self-time was malloc/free/GC from per-call frames + args arrays; this
# removes essentially all of it.
#
# Args: bound directly into the callee frame (no intermediate args array) —
# each arg is evaluated in the CALLER frame, then written to the new
# frame's slot, mirroring the real interp's bind-direct path.
#
# Same fib(33) + sumloop(10M) workload as the other variants.

K_INT    = 1
K_VAR    = 2
K_ASSIGN = 3
K_BINOP  = 4
K_IF     = 5
K_WHILE  = 6
K_CALL   = 7
K_RETURN = 8

OP_ADD = 0
OP_SUB = 1
OP_MUL = 2
OP_LT  = 3
OP_EQ  = 4

class Interp
  attr_accessor :nd_kind, :nd_a, :nd_b, :nd_c, :nd_name, :nd_slot,
                :list_start, :list_len, :list_items,
                :fn_param_start, :fn_param_len, :fn_param_items, :fn_body,
                :fn_index, :fn_nslots,
                :stack, :frame_base, :sp, :returning, :return_value

  def initialize
    @nd_kind = [0]
    @nd_a = [0]
    @nd_b = [0]
    @nd_c = [0]
    @nd_name = [""]
    @nd_slot = [0]          # resolved slot index for VAR / ASSIGN nodes
    @list_start = []
    @list_len = []
    @list_items = []
    @fn_param_start = []
    @fn_param_len = []
    @fn_param_items = [""]
    @fn_body = []
    @fn_index = {}
    @fn_nslots = []          # fn id -> number of distinct local slots
    # Single value stack: frames are (base, nslots) regions. Pre-grown so
    # the hot path never allocates. fib(33) recursion depth is ~33; 65536
    # slots is generous headroom (one ~512KB allocation at startup).
    @stack = []
    s = 0
    while s < 65536
      @stack.push(0)
      s += 1
    end
    @frame_base = 0          # base offset of the current frame in @stack
    @sp = 0                  # next free stack slot
    @returning = false
    @return_value = 0
  end

  def new_node(kind)
    @nd_kind.push(kind)
    @nd_a.push(0)
    @nd_b.push(0)
    @nd_c.push(0)
    @nd_name.push("")
    @nd_slot.push(0)
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
    @fn_nslots.push(0)
    fid
  end

  # ---- Build-time name resolution (the lever-1 pass) ----
  # Walk a function body; assign each distinct variable name a slot index
  # (params first, in declaration order), and stamp nd_slot on every
  # VAR/ASSIGN node. Returns the slot count. Runs ONCE per function at
  # build time — never on the hot path.
  def resolve_fn(fid)
    name_to_slot = {}
    next_slot = 0
    # Params take the first slots.
    pstart = @fn_param_start[fid]
    pcount = @fn_param_len[fid]
    j = 0
    while j < pcount
      name_to_slot[@fn_param_items[pstart + j]] = next_slot
      next_slot += 1
      j += 1
    end
    next_slot = resolve_list(@fn_body[fid], name_to_slot, next_slot)
    @fn_nslots[fid] = next_slot
    next_slot
  end

  def resolve_list(list_id, name_to_slot, next_slot)
    start = @list_start[list_id]
    n = @list_len[list_id]
    i = 0
    while i < n
      next_slot = resolve_node(@list_items[start + i], name_to_slot, next_slot)
      i += 1
    end
    next_slot
  end

  def resolve_node(id, name_to_slot, next_slot)
    k = @nd_kind[id]
    if k == K_VAR || k == K_ASSIGN
      name = @nd_name[id]
      if name_to_slot.key?(name)
        @nd_slot[id] = name_to_slot[name]
      else
        name_to_slot[name] = next_slot
        @nd_slot[id] = next_slot
        next_slot += 1
      end
      if k == K_ASSIGN
        next_slot = resolve_node(@nd_a[id], name_to_slot, next_slot)
      end
      return next_slot
    end
    if k == K_BINOP
      next_slot = resolve_node(@nd_a[id], name_to_slot, next_slot)
      next_slot = resolve_node(@nd_c[id], name_to_slot, next_slot)
      return next_slot
    end
    if k == K_IF
      next_slot = resolve_node(@nd_a[id], name_to_slot, next_slot)
      next_slot = resolve_list(@nd_b[id], name_to_slot, next_slot)
      else_list = @nd_c[id]
      if else_list >= 0
        next_slot = resolve_list(else_list, name_to_slot, next_slot)
      end
      return next_slot
    end
    if k == K_WHILE
      next_slot = resolve_node(@nd_a[id], name_to_slot, next_slot)
      next_slot = resolve_list(@nd_b[id], name_to_slot, next_slot)
      return next_slot
    end
    if k == K_CALL
      next_slot = resolve_list(@nd_a[id], name_to_slot, next_slot)
      return next_slot
    end
    if k == K_RETURN
      next_slot = resolve_node(@nd_a[id], name_to_slot, next_slot)
      return next_slot
    end
    next_slot
  end

  # ---- Evaluation ----
  def evaluate(id)
    k = @nd_kind[id]
    if k == K_INT
      return @nd_a[id]
    end
    if k == K_VAR
      return @stack[@frame_base + @nd_slot[id]]   # value-stack load, no alloc
    end
    if k == K_ASSIGN
      v = evaluate(@nd_a[id])
      @stack[@frame_base + @nd_slot[id]] = v       # value-stack store
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

  # Function call: evaluate args, allocate a fresh IntArray slot frame
  # sized to the function's slot count, bind params to slots 0..argc-1,
  # run the body. ZERO per-call heap allocation: the new frame is a region
  # of the pre-grown value stack; args bind directly into it.
  def visit_call(id)
    name = @nd_name[id]
    fid = @fn_index[name]

    args_list = @nd_a[id]
    astart = @list_start[args_list]
    argc = @list_len[args_list]
    nslots = @fn_nslots[fid]

    # The new frame starts at the current top of stack.
    new_base = @sp
    # Zero the new frame's slots (locals start at 0; params overwritten next).
    s = 0
    while s < nslots
      @stack[new_base + s] = 0
      s += 1
    end
    # Bind args: evaluate each in the CALLER frame (frame_base unchanged),
    # write directly into the new frame's param slot. No args array.
    j = 0
    while j < argc
      v = evaluate(@list_items[astart + j])
      @stack[new_base + j] = v
      j += 1
    end

    prev_base = @frame_base
    prev_sp = @sp
    prev_returning = @returning
    prev_return_value = @return_value
    @frame_base = new_base
    @sp = new_base + nslots
    @returning = false
    @return_value = 0

    run_list(@fn_body[fid])
    result = @return_value

    @frame_base = prev_base
    @sp = prev_sp
    @returning = prev_returning
    @return_value = prev_return_value
    result
  end
end

FIB_N = 33
SUM_LIMIT = 10000000

ip = Interp.new

fib_then = ip.add_list([ip.mk_return(ip.mk_var("n"))])
fib_guard = ip.mk_if(ip.mk_binop(OP_LT, ip.mk_var("n"), ip.mk_int(2)), fib_then, -1)
fib_rec = ip.mk_binop(
  OP_ADD,
  ip.mk_call("fib", ip.add_list([ip.mk_binop(OP_SUB, ip.mk_var("n"), ip.mk_int(1))])),
  ip.mk_call("fib", ip.add_list([ip.mk_binop(OP_SUB, ip.mk_var("n"), ip.mk_int(2))]))
)
fib_body = ip.add_list([fib_guard, ip.mk_return(fib_rec)])
ip.define_fn("fib", ["n"], fib_body)

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

# Resolve slots for every function (build-time, once).
ip.resolve_fn(ip.fn_index["fib"])
ip.resolve_fn(ip.fn_index["sumloop"])

fib_call = ip.mk_call("fib", ip.add_list([ip.mk_int(FIB_N)]))
fib_result = ip.evaluate(fib_call)
puts "fib(" + FIB_N.to_s + ") = " + fib_result.to_s

sum_call = ip.mk_call("sumloop", ip.add_list([ip.mk_int(SUM_LIMIT)]))
sum_result = ip.evaluate(sum_call)
puts "sumloop(" + SUM_LIMIT.to_s + ") = " + sum_result.to_s
