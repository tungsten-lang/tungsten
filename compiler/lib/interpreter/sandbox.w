# Embedding and sandboxing the tree-walking interpreter.
#
# A host program (a browser running page scripts, an editor running plugins)
# links the interpreter and runs untrusted Tungsten inside its own process:
#
#   interp = Interpreter.new([])
#   interp.sandbox!                       # no files, processes, sockets, env
#   interp.set_time_limit(50)             # ms per run; raises "sandbox: time limit"
#   interp.on_output(->(s) console(s))    # where << / puts / print go
#   interp.expose_host_class("Element")   # native objects scripts may call into
#   interp.define_global("document", doc) # values the script sees as names
#   interp.run(source, "page.w")
#   interp.call_closure(f, [arg])         # call a closure the script handed back
#
# Sandbox gates live at the interpreter's own boundaries, not in the runtime
# (Sandbox.enable is process-wide and would also stop the host):
#
#   - source-level ccall: a denylist of runtime entry points that reach files,
#     processes, sockets, the environment, or raw memory views; anything not in
#     the interpreter's ccall table was already refused
#   - builtins: read_file/write_file/system/capture/file_*/env/exit/gets/... raise
#     SecurityError (argv answers [], env answers nil)
#   - `use`: refused (a script cannot pull in files); core autoload still reads
#     the toolchain's own core/*.w, whose ccalls go through the same gate
#   - host objects: only instances of exposed classes are reachable, through
#     ordinary method calls (never `send`); interpreted closures passed as
#     arguments become native lambdas
#   - a wall-clock budget checked on loop iterations, calls and block calls,
#     and a call-depth limit (deep recursion would overflow the host stack)
#
# What it does not bound: memory (a script can allocate until the host's
# watchdog fires) and the cost of a single native call.

SANDBOX_DENIED_CCALL_PREFIXES = ["__w_file", "__w_mmap", "__w_proc", "__w_read", "__w_sleep", "__w_arr_", "w_array_view", "w_big_array_view", "w_array_memmove", "w_array_new_uninit", "w_array_new_aligned", "w_array_mat", "w_string_bytes_view", "w_string_take_byte_array", "w_tensor", "w_blas_", "w_carr_", "w_dns_", "w_env_", "w_setenv", "w_unsetenv", "w_executable", "w_udp_", "w_physical_memory", "w_class_by_name", "w_bigint_mark_shared", "w_bigint_shared", "w_thread_kill", "w_mutex_", "w_chan_", "w_thread_join"]

SANDBOX_DENIED_BUILTINS = {"cache_read" => true, "cache_write" => true, "capture" => true, "exit" => true, "gets" => true, "read_dir" => true, "read_file" => true, "read_file_bytes" => true, "system" => true, "tempfile_create" => true, "write_file" => true, "write_file_bytes" => true, "write_file_bytes_n" => true, "file?" => true, "file_chdir" => true, "file_chmod" => true, "file_directory?" => true, "file_exists?" => true, "file_expand_path" => true, "file_expand_path_base" => true, "file_fsync" => true, "file_fsync_parent" => true, "file_link" => true, "file_mkdir" => true, "file_mtime_ns" => true, "file_pwd" => true, "file_readlink" => true, "file_realpath" => true, "file_rename" => true, "file_rm" => true, "file_rmdir" => true, "file_size" => true, "file_stat_data" => true, "file_symlink" => true, "file_temp_for" => true, "file_touch" => true, "file_unlink" => true, "file_unlink_strict" => true, "freeze_slab" => true, "runtime_identity" => true}

# Method names a script may never call on a host object.
SANDBOX_DENIED_HOST_METHODS = {"send" => true, "__send__" => true, "public_send" => true, "method_missing" => true, "instance_variable_get" => true, "instance_variable_set" => true, "instance_variables" => true, "free" => true}

+ Interpreter
  -> sandbox!
    @sandboxed = true
    self

  -> sandboxed?
    @sandboxed == true

  # Wall-clock budget for each subsequent run/call_closure, in ms (nil: none).
  -> set_time_limit(ms)
    @sb_limit_ms = ms
    self

  -> set_max_depth(n)
    @sb_max_depth = n
    self

  # Where << / puts / print output goes: a native lambda taking one String
  # (one call per line for << and puts, a bare fragment for print / <-).
  -> on_output(f)
    @output = f
    self

  -> output_line(s)
    if @output == nil
      << s
    else
      @output.call(s)
    nil

  -> output_text(s)
    if @output == nil
      <- s
    else
      @output.call(s)
    nil

  -> expose_host_class(name)
    @host_classes[name] = true
    self

  -> host_class?(name)
    @host_classes.has_key?(name)

  -> define_global(name, value)
    @env.define(name, value)
    value

  -> global(name)
    return nil if !@env.defined?(name)
    @env.get(name)

  # Calls the host makes into script code: start (or keep) the time budget.
  -> sandbox_begin
    if @sb_limit_ms != nil && @sb_entry == 0
      @sb_deadline = clock_ms() + @sb_limit_ms
      @sb_tripped = false
    @sb_entry += 1
    nil

  -> sandbox_end
    @sb_entry -= 1 if @sb_entry > 0
    nil

  # Run source the host trusts as much as the page (prelude, a later script):
  # the same environment, the same classes; errors propagate to the host.
  -> run_sandboxed(source, file_path)
    sandbox_begin()
    begin
      result = run(source, file_path)
    ensure
      sandbox_end()
    result

  # Top-level functions the script defined (`-> name(...)`), callable by name.
  -> function?(name)
    key = @global_method_keys[name]
    key = "__method__" + name if key == nil
    @env.defined?(key)

  -> call_function(name, args)
    key = @global_method_keys[name]
    key = "__method__" + name if key == nil
    if !@env.defined?(key)
      raise_typed("NoMethodError", "Undefined method '" + name + "'")
    m = nil
    overloads = @function_overloads[name]
    if overloads != nil
      m = select_typed_overload(overloads, args.size(), false, args)
    m = @env.get(key) if m == nil
    sandbox_begin()
    begin
      result = call_w_method(nil, m, args, nil, @env)
    ensure
      sandbox_end()
    result

  -> closure?(v)
    type(v) == "Array" && v.size() == 2 && is_ast_node?(v[1]) && ast_kind(v[1]) == :block

  # A host calls back into script: a closure the script passed it, or a native
  # lambda (called directly).
  -> call_closure(f, args)
    if closure?(f)
      sandbox_begin()
      begin
        result = call_block(f, args)
      ensure
        sandbox_end()
      return result
    if f == nil
      return nil
    hargs = []
    i = 0
    while i < args.size()
      hargs.push(host_callable(args[i]))
      i += 1
    ccall("w_method_call", f, "call", hargs)

  -> closure_arity(f)
    return 0 if !closure?(f)
    ast_get(f[1], :params).size()

  # An interpreted closure as a native lambda the host can `.call` with the
  # closure's own arity (extra host arguments are dropped, missing ones nil).
  -> host_callable(v)
    return v if !closure?(v)
    me = self
    n = closure_arity(v)
    if n == 0
      return ->() me.call_closure(v, [])
    if n == 1
      return ->(a) me.call_closure(v, [a])
    if n == 2
      return ->(a, b) me.call_closure(v, [a, b])
    if n == 3
      return ->(a, b, c) me.call_closure(v, [a, b, c])
    ->(a, b, c, d) me.call_closure(v, [a, b, c, d])

  -> sandbox_check_ccall(cname)
    i = 0
    while i < SANDBOX_DENIED_CCALL_PREFIXES.size()
      if cname.starts_with?(SANDBOX_DENIED_CCALL_PREFIXES[i])
        raise_typed("SecurityError", "sandbox: ccall " + cname + " is not available")
      i += 1
    nil

  # nil: not handled (dispatch normally); [value]: answer this value.
  -> sandbox_builtin(name)
    if name == "argv"
      return [[]]
    if name == "env"
      return [nil]
    if SANDBOX_DENIED_BUILTINS.has_key?(name)
      raise_typed("SecurityError", "sandbox: " + name + " is not available")
    nil

  # Loop iterations, calls and block calls land here. Cheap until the
  # counter runs out; then a clock read.
  -> sandbox_tick
    @sb_ticks += 1
    if @sb_tripped
      raise_typed("SecurityError", "sandbox: time limit exceeded")
    if (@sb_ticks & 1023) == 0 && @sb_deadline > 0 && @sb_entry > 0
      if clock_ms() > @sb_deadline
        @sb_tripped = true
        raise_typed("SecurityError", "sandbox: time limit exceeded")
    nil

  -> sandbox_enter_call
    @sb_depth += 1
    if @sb_depth > @sb_max_depth
      @sb_depth = 0
      raise_typed("SecurityError", "sandbox: call depth limit exceeded")
    sandbox_tick()
    nil

  -> sandbox_leave_call
    @sb_depth -= 1 if @sb_depth > 0
    nil

  # Native (compiled) receivers. Returns [value] when handled, nil otherwise.
  # Interpreted objects are :rt hashes and primitives have their own paths;
  # what reaches here is an instance of a class compiled into the host.
  -> host_dispatch(recv, name, args, block)
    t = type(recv)
    if !@host_classes.has_key?(t)
      return nil
    if SANDBOX_DENIED_HOST_METHODS.has_key?(name)
      raise_typed("NoMethodError", "undefined method '" + name + "' for " + t)
    if !ccall("w_method_call", recv, "respond_to?", ["" + name])
      raise_typed("NoMethodError", "undefined method '" + name + "' for " + t)
    hargs = []
    i = 0
    while i < args.size()
      hargs.push(host_callable(args[i]))
      i += 1
    if block != nil
      hargs.push(host_callable(block))
    [ccall("w_method_call", recv, "" + name, hargs)]

  -> native_global_callable?(name, env)
    v = nil
    if env != nil && env.defined?(name)
      v = env.get(name)
    elsif @env.defined?(name)
      v = @env.get(name)
    else
      return false
    native_callable?(v)

  # A native lambda (type Unknown, not a sync handle) called from script.
  -> native_callable?(v)
    type(v) == "Unknown" && ccall("w_sync_handle_kind_support", v) == 0
