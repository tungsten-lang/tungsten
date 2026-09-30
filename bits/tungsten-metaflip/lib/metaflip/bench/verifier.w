# The independent exactness gate of the benchmark. A backend is a command in
# verifiers.tsv that exits 0 when the scheme file computes the tensor of the
# given format over GF(2). Exit status 1 with the backend's `not_exact_marker`
# in its output is the verdict "not exact"; any other outcome means the
# verifier could not decide.
use core/file
use tables
use proc

+ Verifier
  ro :name

  -> new(@bench, @name)
    @row = @bench.verifier_row(@name)

  # true: exact; false: not exact; nil: the verifier could not run. The
  # verifier's output is kept next to the scheme as `<scheme>.verify.log`.
  -> exact?(scheme, n, m, p)
    values = {"bench" => @bench.dir, "scheme" => scheme, "n" => n, "m" => m, "p" => p, "shape" => n.to_s + "x" + m.to_s + "x" + p.to_s}
    command = Shell.expand(@row["command"], values) + " > " + Shell.quote(scheme + ".verify.log") + " 2>&1"
    child = Child.spawn(["/bin/sh", "-c", command])
    result = child.wait(600000)
    done = result[0]
    return nil if result[1] || done.signal != 0
    return true if done.code == 0
    log = read_file(scheme + ".verify.log")
    return false if done.code == 1 && log != nil && log.include?(@row["not_exact_marker"])
    nil
