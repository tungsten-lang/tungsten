# Structural regression for the persisted degree-twelve shell-width S-class
# relation witnesses. This deliberately does not claim to prove the theorem:
# the opt-in native verifier reconstructs the fields and exactly replays every
# principal-ideal relation.

use algebra
use core/file

-> artifact_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

path = "spec/fixtures/algebra/shell_width_degree12_s_class.rel"
lines = File.read(path).split("\n")
artifact_check("line.count", lines.size, 58)
artifact_check("trailing.newline", lines[57], "")
artifact_check("format", lines[0], "# tungsten-s-class-relations-v1")
artifact_check("theorem", lines[1], "# theorem=Cl(O_K,S)\[2\]=0")
artifact_check("degree", lines[2], "# field_component_degree=12")
artifact_check("discriminant",
               lines[3], "# field_discriminant=1364523024384")
artifact_check("rational.S", lines[4], "# rational_S=2,3,13")
artifact_check("factor.base", lines[5], "# factor_base_size=56")
artifact_check("rank", lines[6], "# relation_rank=56")
artifact_check("model.certified", lines[7], "# model_certified=true")
artifact_check("source.transfer.certified",
               lines[8], "# source_transfer_certified=true")

witnesses = []
i = 9
while i < lines.size - 1
  coefficients = lines[i].split(",")
  if coefficients.size != 12
    raise "FAIL witness " + (i - 9).to_s + " arity"
  coefficients.each -> (coefficient)
    parts = coefficient.split("/")
    if parts.size != 2 || parts[1].to_i <= 0
      raise "FAIL invalid rational in witness " + (i - 9).to_s
  if witnesses.include?(lines[i])
    raise "FAIL duplicate witness " + (i - 9).to_s
  witnesses.push(lines[i])
  i += 1

artifact_check("witness.count", witnesses.size, 48)
