# Structural regression for the persisted degree-six shell-width S-class
# relation witnesses. The opt-in native verifier performs the mathematical
# replay.

use algebra
use core/file

-> artifact_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

path = "spec/fixtures/algebra/shell_width_degree6_s_class.rel"
lines = File.read(path).split("\n")
artifact_check("line.count", lines.size, 14)
artifact_check("trailing.newline", lines[13], "")
artifact_check("format", lines[0], "# tungsten-s-class-relations-v1")
artifact_check("theorem", lines[1], "# theorem=Cl(O_K,S)\[2\]=0")
artifact_check("degree", lines[2], "# field_component_degree=6")
artifact_check("discriminant",
               lines[3], "# field_discriminant=1168128")
artifact_check("factor.base", lines[5], "# factor_base_size=9")
artifact_check("rank", lines[6], "# relation_rank=9")

witnesses = []
i = 9
while i < lines.size - 1
  coefficients = lines[i].split(",")
  if coefficients.size != 6
    raise "FAIL witness " + (i - 9).to_s + " arity"
  if witnesses.include?(lines[i])
    raise "FAIL duplicate witness " + (i - 9).to_s
  witnesses.push(lines[i])
  i += 1

artifact_check("witness.count", witnesses.size, 4)
