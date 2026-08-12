# A selected WGSL dialect must diagnose unsupported storage types, not emit a
# successful sidecar containing a `// skipped` comment.

## f16[]: values
@gpu fn unsupported_wgsl_storage(values)
  values[0] = values[0]
