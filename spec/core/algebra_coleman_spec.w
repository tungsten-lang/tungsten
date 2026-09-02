# Independent Chabauty--Coleman run for the shell-width quartic at p = 5.
# Native lane: at the default precision 26 every residue fits a machine word
# and the run takes about two seconds and 1.4 GB; TUNGSTEN_COLEMAN_PRECISION=40
# exercises the BigInt lane instead (about 90 s and ~100 GB of BigInt arena).
#
#   bin/tungsten compile spec/core/algebra_coleman_spec.w \
#     --out /tmp/algebra-coleman-spec --release
#   /tmp/algebra-coleman-spec

use algebra

-> coleman_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0

precision = 26
requested = env("TUNGSTEN_COLEMAN_PRECISION")
if requested != nil && requested != ""
  precision = requested.to_i

# known points in the curve's (B, S, Z) coordinates; the last one is the
# Abel--Jacobi base Q2 = (b, s) = (-3, -3), the middle one Q1 = (0, 9)
engine = C.chabauty_coleman(5, precision, [[1, 0, 0], [0, 9, 1], [-3, -3, 1]])
coleman_check("engine.jacobian_order", engine.jacobian_order, 222)
coleman_check("engine.pole_bound", engine.pole_bound, 228)
coleman_check("engine.basis_size", engine.basis_size, 226)

report = engine.run
coleman_check("report.complete", report[:complete], true)
coleman_check("report.total_points", report[:total_points], 3)
coleman_check("report.disks", report[:disks].size, 8)
coleman_check("report.scale_exponent", report[:scale_exponent], 3)

<< "generator log digits: " + report[:generator_log_digits].to_s
<< "annihilator digits: " + report[:annihilator_digits].to_s
<< "tail floor: 5^" + report[:tail_floor].to_s
resolved = 0
by_count = 0
located = 0
disk_index = 0
while disk_index < report[:disks].size
  disk = report[:disks][disk_index]
  disk_index += 1
  line = "disk " + disk[:name] + " kind " + disk[:kind].to_s
  line = line + " counts " + disk[:counts].to_s + " minima " + disk[:minima].to_s
  line = line + " digits " + disk[:digits].to_s + " status " + disk[:status]
  if disk[:root_point] != nil
    line = line + " root (x,y) mod 5^8 = " + disk[:root_point].to_s
    line = line + " other-fn val 5^" + disk[:other_valuation].to_s
  << line
  resolved += 1 if disk[:status] == "resolved-known"
  by_count += 1 if disk[:status] == "eliminated-count"
  located += 1 if disk[:status] == "eliminated-located"
coleman_check("report.resolved_known", resolved, 3)
coleman_check("report.eliminated", by_count + located, 5)

# every eliminated-located zero must be decided by a valuation far below the
# digits the function is known to
disk_index = 0
while disk_index < report[:disks].size
  disk = report[:disks][disk_index]
  disk_index += 1
  if disk[:status] == "eliminated-located"
    coleman_check("report." + disk[:name] + ".decisive",
                  disk[:other_valuation] < disk[:digits][0] - 8, true)

# located zeros versus the retained engine's published table
# (shell_width_chabauty_coleman_2026-08-01.md, p = 5): its bzt* values are
# parameters in its own charts, converted here to affine coordinates mod 5^8:
# d10 (b,s)=(1,0) s-chart s* = 294395; d11 s* = 1 + 387760; d21 b-chart
# b* = 2 + 282825; d42 b* = 4 + 304400.  This engine names disks d<s>_<b> and
# reports (x, y) = (s, b).
expected_roots = {
  "d0_1": [0, 294395],
  "d1_1": [0, 387761],
  "d1_2": [1, 282827],
  "d2_4": [1, 304404]
}
disk_index = 0
while disk_index < report[:disks].size
  disk = report[:disks][disk_index]
  disk_index += 1
  expected = expected_roots[disk[:name]]
  if expected != nil && disk[:root_point] != nil
    coleman_check("retained." + disk[:name] + ".root",
                  disk[:root_point][expected[0]], expected[1])

# internal cross-check: shifting an unknown disk's center along its own
# parameter changes the interpolated logarithm by the direct tiny integral
probe = nil
disk_index = 0
while disk_index < report[:disks].size
  disk = report[:disks][disk_index]
  disk_index += 1
  if probe == nil && disk[:status] != "resolved-known" && disk[:kind] != :infinity
    probe = disk[:name]
agreement = engine.consistency_check(probe)
<< "consistency check on " + probe + ": agreeing digits " + agreement.to_s
agree_ok = true
agreement.each -> (digits)
  agree_ok = false if digits < 12
coleman_check("consistency.digits", agree_ok, true)

<< "algebra_coleman_spec: all checks passed"
