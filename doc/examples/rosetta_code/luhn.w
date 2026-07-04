# https://rosettacode.org/wiki/Luhn_test_of_credit_card_numbers#Ruby

+ String
  #  @note to_i.digits fails for cases with leading zeros
  -> luhn?
    scan(/\d/).reverse
              .each_slice(2)
              .sum ->(i, k = 0) i.to_i + (k.to_i * 2).digits.sum
              .modulo(10).zero?

%s[49927398716 49927398717 1234567812345678 1234567812345670]:luhn?

## expect skip currently unsupported in this runtime
