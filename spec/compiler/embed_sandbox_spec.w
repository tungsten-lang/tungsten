# spec: compiled
# The embedded interpreter in sandbox mode (compiler/lib/interpreter/sandbox.w):
# a host links the tree-walker and runs untrusted Tungsten in-process.
#
#   bin/tungsten -o /tmp/embed spec/compiler/embed_sandbox_spec.w && /tmp/embed

use ../../compiler/lib/embed

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

+ HostBox
  rw :v
  -> new(@v)
  -> add(n)
    @v = @v + n
    self
  -> each_twice(f)
    f.call(@v)
    f.call(@v * 2)

+ Hidden
  -> new
  -> secret
    "leak"

-> denied?(interp, src)
  begin
    interp.run_sandboxed(src, "probe.w")
  rescue e
    return e.to_s.index("sandbox") != nil || e.to_s.index("undefined method") != nil
  false

out = []
interp = Interpreter.new([])
interp.sandbox!
interp.set_time_limit(300)
interp.on_output(->(s) out.push(s))
interp.expose_host_class("HostBox")
box = HostBox.new(5)
interp.define_global("box", box)
interp.define_global("hidden", Hidden.new)
interp.define_global("twice", ->(x) x * 2)

interp.run_sandboxed("x = 1 + 2\n<< \"x=\[x]\"", "a.w")
check("embed.output_hook", out.size == 1 && out[0] == "x=3")
interp.run_sandboxed("box.add(10)", "b.w")
check("embed.host_method", box.v == 15)
out.clear
interp.run_sandboxed("box.each_twice -> (q)\n  << q", "c.w")
check("embed.trailing_block_to_host", out.join(",") == "15,30")
check("embed.native_lambda", interp.run_sandboxed("twice(21)", "d.w") == 42)
interp.run_sandboxed("-> greet(n)\n  \"hi \" + n", "e.w")
check("embed.call_function", interp.function?("greet") && interp.call_function("greet", ["w"]) == "hi w")
f = interp.run_sandboxed("->(a) a + 1", "f.w")
check("embed.call_closure", interp.call_closure(f, [1]) == 2)

check("sandbox.read_file", denied?(interp, "read_file(\"/etc/hosts\")"))
check("sandbox.system", denied?(interp, "system(\"true\")"))
check("sandbox.self_system", denied?(interp, "self.system(\"true\")"))
check("sandbox.ccall", denied?(interp, "ccall(\"__w_read_file_prefix\", \"/etc/hosts\", 4)"))
check("sandbox.use", denied?(interp, "use json"))
check("sandbox.exit", denied?(interp, "exit(3)"))
check("sandbox.unexposed_host", denied?(interp, "hidden.secret"))
check("sandbox.send", denied?(interp, "box.send(\"add\", 1)"))
check("sandbox.env_stub", interp.run_sandboxed("env(\"HOME\")", "g.w") == nil)
check("sandbox.depth", denied?(interp, "-> f(n)\n  f(n + 1)\nf(0)"))
check("sandbox.time", denied?(interp, "while true\n  1"))
check("sandbox.time_not_rescuable", denied?(interp, "begin\n  while true\n    1\nrescue e\n  while true\n    2"))
check("sandbox.recovers", interp.run_sandboxed("1 + 1", "h.w") == 2)
