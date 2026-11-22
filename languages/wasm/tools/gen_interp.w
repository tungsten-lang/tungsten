# Generate interp.w from interp.wt: substitute the OP_* names in `when` lines with their
# numbers from ops.w (globals are slow inside typed functions; literals compile to a
# jump table). Run from languages/wasm: bin/tungsten tools/gen_interp.w

dir = File.dirname(File.dirname(__FILE__))
ops = {}
File.read(dir + "/ops.w").split("\n").each ->(line)
  if line.starts_with?("OP_")
    parts = line.split(" = ")
    ops[parts[0]] = parts[1]
out = StringBuffer.new
File.read(dir + "/interp.wt").split("\n").each ->(line)
  t = line.strip
  if t.starts_with?("when OP_")
    names = t.slice(5, t.size - 5).split(", ")
    nums = names.map ->(n)
      raise "unknown op " + n if !ops.has_key?(n)
      ops[n]
    ind = line.slice(0, line.size - t.size)
    out.append(ind + "when " + nums.join(", ") + "\n")
  else
    out.append(line + "\n")
File.write(dir + "/interp.w", out.to_s)
<< "wrote interp.w"
