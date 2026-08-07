# Surface forms the agent-facing docs teach, pinned against the
# production engines: explicit-star symbolic products (`2 * x` must
# agree with the `2x` juxtaposition), and date/datetime ± duration
# arithmetic in both ns and calendar (months) modes.
#
# Run compiled:    bin/tungsten -o /tmp/docsurf spec/core/doc_taught_surface_spec.w && /tmp/docsurf
# Run interpreted: bin/tungsten spec/core/doc_taught_surface_spec.w

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- explicit star mirrors juxtaposition for undefined names --
check("star.symbolic", (2 * x).to_s(), (2x).to_s())
check("star.reversed", (x * 3).to_s(), "3 x")
check("star.sum", (2 * x + 3 * x).to_s(), "5 x")
k = 3
check("star.defined_untouched", 2 * k, 6)

# -- date ± duration --
d = 2024-01-15
check("date.plus_days", (d + 210 days).to_s(), (d + 210).to_s())
check("date.duration_first", (210 days + d).to_s(), (d + 210).to_s())
check("date.minus_days", (d - 30 days).to_s(), (d - 30).to_s())
check("date.plus_hours", (2024-01-15T12:00:00Z + 2h).to_s(), "2024-01-15T14:00:00Z")
check("date.plus_minsec", (2024-01-15T23:59:00Z + 90s).to_s(), "2024-01-16T00:00:30Z")
check("date.plus_month", (d + 1mo).to_s(), "2024-02-15T00:00:00Z")
check("date.month_clamp", (2024-01-31 + 1mo).to_s(), "2024-02-29T00:00:00Z")

<< "doc_taught_surface_spec: all green"
