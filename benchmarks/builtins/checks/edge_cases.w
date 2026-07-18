# Edge-case behavior probe for builtins being ported from C to Tungsten.
# Run before and after a port; outputs must be byte-identical.
<< "gcd " << 0.gcd(0) << " " << 0.gcd(5) << " " << (0 - 12).gcd(18) << " " << 12.gcd(0 - 18) << " " << 1234567890.gcd(987654321)
<< "gcd_big " << (2 ** 70).gcd(2 ** 35)
<< "lcm " << 0.lcm(5) << " " << 5.lcm(0) << " " << 0.lcm(0) << " " << (0 - 4).lcm(6) << " " << 4.lcm(0 - 6) << " " << 21.lcm(6)
<< "cap1 " << "".capitalize
<< "cap2 " << "a".capitalize
<< "cap3 " << "A".capitalize
<< "cap4 " << "hello World FROM x".capitalize
<< "cap5 " << "9lives".capitalize
<< "cap6 " << "tiny".capitalize
<< "swap1 " << "".swapcase
<< "swap2 " << "aB".swapcase
<< "swap3 " << "Hello, World! 123".swapcase
<< "swap4 " << "tiny".swapcase
<< "swap5 " << "six4U!".swapcase
<< "swap6 " << :aB.swapcase
<< "swap7 " << "exactly slab sized str".swapcase
<< "cap7 " << "sixCHR".capitalize
<< "cap8 " << :abC.capitalize
rev_empty = []
<< "rev1 " << rev_empty.reverse
<< "rev2 " << [1].reverse
<< "rev3 " << [1, 2, 3, "x", nil].reverse
take_arr = [1, 2, 3]
<< "take1 " << take_arr.take(0)
<< "take2 " << take_arr.take(2)
<< "take3 " << take_arr.take(3)
<< "take4 " << take_arr.take(99)
<< "drop1 " << take_arr.drop(0)
<< "drop2 " << take_arr.drop(2)
<< "drop3 " << take_arr.drop(3)
<< "drop4 " << take_arr.drop(99)
<< "uniq1 " << rev_empty.uniq
<< "uniq2 " << [1, 1, 1].uniq
<< "uniq3 " << [3, 1, 3, 2, 1, "a", "a", nil, nil].uniq
<< "mm1 " << [5].minmax
<< "mm2 " << [3, 9, 1, 7].minmax
<< "mm3 " << [2, 2].minmax
mm_empty = []
<< "mm4 " << mm_empty.minmax
