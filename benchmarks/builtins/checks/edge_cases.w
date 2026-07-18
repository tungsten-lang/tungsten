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
cp_arr = [10, 20, 30, 40, 50]
<< "cp1 " << cp_arr.copy(0)
<< "cp2 " << cp_arr.copy(2)
<< "cp3 " << cp_arr.copy(0 - 2)
<< "cp4 " << cp_arr.copy(1, 2)
<< "cp5 " << cp_arr.copy(0, 99)
<< "cp6 " << cp_arr.copy(3, 0)
<< "cp7 " << cp_arr.copy(0 - 99, 2)
<< "cp8 " << cp_arr.copy(2, 0 - 5)
<< "cp9 " << cp_arr.copy(5)
cp_empty = []
<< "cp10 " << cp_empty.copy(0)
da1 = [10, 20, 30, 40, 50]
<< "da1 " << da1.delete_at(0) << " " << da1
da2 = [10, 20, 30, 40, 50]
<< "da2 " << da2.delete_at(2) << " " << da2
da3 = [10, 20, 30, 40, 50]
<< "da3 " << da3.delete_at(4) << " " << da3
da4 = [10, 20, 30, 40, 50]
<< "da4 " << da4.delete_at(0 - 1) << " " << da4
da5 = [10, 20, 30, 40, 50]
<< "da5 " << da5.delete_at(0 - 5) << " " << da5
da6 = [10, 20, 30, 40, 50]
<< "da6 " << da6.delete_at(5) << " " << da6
da7 = [10, 20, 30, 40, 50]
<< "da7 " << da7.delete_at(0 - 6) << " " << da7
da8 = [99]
<< "da8 " << da8.delete_at(0) << " " << da8 << " " << da8.size
da9 = []
<< "da9 " << da9.delete_at(0) << " " << da9
<< "rv1 " << "".reverse
<< "rv2 " << "a".reverse
<< "rv3 " << "hello".reverse
<< "rv4 " << "héllo".reverse
<< "rv5 " << "🎉ab".reverse
<< "rv6 " << "exactly a slab sized string ok".reverse
<< "rv7 " << "aβcδe".reverse
<< "rv8 " << "ab".reverse
<< "ch1 " << "".chars
<< "ch2 " << "a".chars
<< "ch3 " << "hello".chars
<< "ch4 " << "abé🎉".chars
<< "ch5 " << "aβcδe".chars
<< "ch6 " << "a longer ascii string here ok".chars.size
