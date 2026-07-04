+ Unsigned < Int

  # Maximum value of an N-bit unsigned integer: 2^N − 1.
  -> .max_value
    2 ** self.bits - 1

  -> .min_value 0
