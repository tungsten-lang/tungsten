# Structural regressions for the three supplied shell-width S-unit generator
# sets. The opt-in native verifier checks exact support, local characters,
# full rank, isomorphic transfer, and the diagonal quotient.

use algebra
use core/file

-> artifact_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> check_s_unit_artifact(path, degree, discriminant,
                         generator_count)
  lines = File.read(path).split("\n")
  artifact_check("degree." + degree.to_s,
                 lines[1],
                 "# field_component_degree=" + degree.to_s)
  artifact_check("discriminant." + degree.to_s,
                 lines[2],
                 "# field_discriminant=" + discriminant.to_s)
  artifact_check("rational.S." + degree.to_s,
                 lines[3], "# rational_S=2,3,13")
  artifact_check("generator.count.header." + degree.to_s,
                 lines[4],
                 "# generator_count=" + generator_count.to_s)
  artifact_check("line.count." + degree.to_s,
                 lines.size, generator_count + 6)
  artifact_check("trailing.newline." + degree.to_s,
                 lines[lines.size - 1], "")
  generators = []
  i = 5
  while i < lines.size - 1
    coefficients = lines[i].split(",")
    if coefficients.size != degree
      raise "FAIL degree " + degree.to_s + " generator arity"
    coefficients.each -> (coefficient)
      parts = coefficient.split("/")
      if parts.size != 2 || parts[1].to_i <= 0
        raise "FAIL invalid degree " + degree.to_s + " rational"
    if generators.include?(lines[i])
      raise "FAIL duplicate degree " + degree.to_s + " generator"
    generators.push(lines[i])
    i += 1
  artifact_check("generator.count." + degree.to_s,
                 generators.size, generator_count)

check_s_unit_artifact(
  "spec/fixtures/algebra/shell_width_degree6_s_units.rel",
  6, 1168128, 9)
check_s_unit_artifact(
  "spec/fixtures/algebra/shell_width_degree9_s_units.rel",
  9, 133451615232, 12)
check_s_unit_artifact(
  "spec/fixtures/algebra/shell_width_degree12_s_units.rel",
  12, 1364523024384, 14)
