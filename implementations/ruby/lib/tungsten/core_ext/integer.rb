class Integer
  # Number of 1 bits in the magnitude, matching Tungsten's Int#popcount
  # (Python int.bit_count): 0 -> 0, 255 -> 8, -255 -> 8.
  def popcount
    abs.digits(2).sum
  end

  alias_method :bit_count, :popcount
end
