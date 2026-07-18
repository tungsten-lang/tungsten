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
<< "chr1 " << 65.chr << " " << 122.chr << " " << 48.chr
<< "chr2 " << 0.chr.size << " " << (0 - 1).chr.size << " " << (0 - 256).chr.size
<< "chr3 " << 127.chr.size << " " << 128.chr.size << " " << 233.chr << " " << 2047.chr.size
<< "chr4 " << 2048.chr.size << " " << 65535.chr.size << " " << 65536.chr.size << " " << 128512.chr
<< "chr5 " << 1114111.chr.size
<< "tos1 " << 0.to_s << " " << 7.to_s << " " << 42.to_s << " " << 99999.to_s
<< "tos2 " << (0 - 1).to_s << " " << (0 - 9999).to_s << " " << (0 - 10000).to_s
<< "tos3 " << 100000.to_s << " " << 123456789.to_s << " " << (0 - 140737488355328).to_s << " " << 140737488355327.to_s
<< "tos4 " << 255.to_s(16) << " " << 255.to_s(2) << " " << (0 - 255).to_s(16) << " " << 35.to_s(36) << " " << 0.to_s(7)
<< "tos5 " << 123456.to_s(10) << " " << 140737488355327.to_s(36)
