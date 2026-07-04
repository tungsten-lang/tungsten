+ Signed < Int

  # Maximum value of an N-bit signed integer: 2^(N-1) − 1.
  -> .max_value
    2 ** (bits - 1) - 1

  # Minimum value of an N-bit signed integer: −2^(N-1).
  -> .min_value
    -(2 ** (bits - 1))
