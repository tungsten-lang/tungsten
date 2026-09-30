# Child processes under measurement. A child runs in its own process group
# and is reaped with wait4, so the resource usage it reports covers the CPU
# time (user + system) of the child and every descendant it waited for.
use core/process

# How a child ended and what it used.
+ Exit
  ro :code, :signal, :user_us, :sys_us, :max_rss_bytes
  -> new(@code, @signal, @user_us, @sys_us, @max_rss_bytes)

  -> cpu_us
    @user_us + @sys_us

  # Microseconds as seconds.
  -> .seconds(us) (i64) f64
    us.to_f / 1000000.to_f

  -> cpu_s
    Exit.seconds(@user_us + @sys_us)

  -> user_s
    Exit.seconds(@user_us)

  -> sys_s
    Exit.seconds(@sys_us)

  -> ok?
    @signal == 0 && @code == 0

+ Proc
  # Address of the first element of a typed array.
  -> .address(cells) (i64[]) i64
    ccall_nobox("w_typed_array_data_ptr", cells)

  -> .now_ms() i64
    ccall("__w_clock_ms")

  -> .sleep_ms(ms) (i64)
    ccall("__w_sleep_ms", ms)

  # The one-minute load average.
  -> .load1() f64
    cells = f64[3]
    at = Proc.address_f64(cells) ## i64
    ccall_nobox("getloadavg", at, 3)
    cells[0]

  -> .address_f64(cells) (f64[]) i64
    ccall_nobox("w_typed_array_data_ptr", cells)

  -> .hostname()
    capture("hostname").strip

  # True after SIGINT or SIGTERM was latched by `Proc.trap`.
  -> .interrupted?()
    ccall("__w_interrupted") > 0

  -> .trap()
    ccall("__w_trap_interrupts")

# A running child.
+ Child
  ro :pid, :started_ms

  # Starts `argv` (no shell) in a new process group.
  -> .spawn(argv)
    process = Process.spawn(argv)
    Child.new(process, Proc.now_ms())

  -> new(@process, @started_ms)
    @pid = @process.pid
    @status = i64[2]
    @usage = i64[24]
    @done = false

  # nil while the child runs, else its Exit.
  -> poll
    return nil if @done
    @status[0] = 0
    pid = @pid ## i64
    status_at = Proc.address(@status) ## i64
    usage_at = Proc.address(@usage) ## i64
    reaped = ccall_nobox("wait4", pid, status_at, 1, usage_at) ## i64
    return nil if reaped == 0
    @done = true
    raw = @status[0] & 4294967295 ## i64
    signal = raw & 127 ## i64
    code = (raw >> 8) & 255 ## i64
    if reaped < 0
      return Exit.new(0 - 1, 0, 0, 0, 0)
    user = @usage[0] * 1000000 + (@usage[1] & 4294967295) ## i64
    sys = @usage[2] * 1000000 + (@usage[3] & 4294967295) ## i64
    Exit.new(code, signal, user, sys, @usage[4])

  # Blocks until the child ends; kills its process group after `limit_ms`
  # of wall-clock time (nil: no limit). The second element tells whether it was killed.
  -> wait(limit_ms)
    killed = false
    result = self.poll
    while result == nil
      if limit_ms != nil && !killed && Proc.now_ms() - @started_ms > limit_ms
        self.kill
        killed = true
      Proc.sleep_ms(2)
      result = self.poll
    [result, killed]

  # SIGKILLs the whole process group of a child that has not been reaped.
  -> kill
    @process.kill(9) if !@done

# Shell command lines.
+ Shell
  # `text` as one shell word.
  -> .quote(text)
    "'" + text.replace("'", "'\"'\"'") + "'"

  # The template with every `{key}` replaced by the quoted value of `values[key]`.
  -> .expand(template, values)
    out = template
    values.keys.each -> (key)
      out = out.replace("{" + key + "}", Shell.quote(values[key].to_s))
    out

# File names as strings.
+ Paths
  -> .dirname(path)
    slash = path.rindex("/")
    return "." if slash == nil
    return "/" if slash == 0
    path.slice(0, slash)

  -> .basename(path)
    slash = path.rindex("/")
    return path if slash == nil
    path.slice(slash + 1, path.size - slash - 1)
