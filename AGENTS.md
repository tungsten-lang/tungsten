# Agent guidance

## Testing

- While working locally, run only the focused specs and checks directly
  applicable to the files or behavior being changed.
- Do not run the full `rake` suite locally. CI is responsible for running the
  complete suite.
- Broaden local coverage only when needed to diagnose a failure in an
  applicable focused check.
