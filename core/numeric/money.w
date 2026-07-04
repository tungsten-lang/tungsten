# @example
#   $2.50.inspect
#   $2.50 * 3
#   $2.50 - 20%
#
#   $2.50.convert("€")
+ Money < Decimal
  is Accountable

  -> new(@currency: Tungsten.locale.currency)
