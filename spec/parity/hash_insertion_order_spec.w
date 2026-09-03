# Hashes: insertion order is preserved through overwrite, delete and
# re-insert; keys/values/to_a/map follow it; symbol, string and int keys.
#
# Cross-engine parity spec (scripts/parity.sh).

h = {name: "Alice", age: 30}
<< "lit.keys [h.keys] lit.values [h.values.join(",")]"
<< "get [h[:name]]"
<< "keys [h.keys]"
<< "values [h.values.join(",")]"
<< "size [h.size]"
<< "has [h.has_key?(:age)]"
h[:zip] = "12345"
h[:name] = "Bob"
<< "overwrite.keys [h.keys]"
<< "overwrite.values [h.values.join(",")]"
h.delete(:age)
<< "delete.keys [h.keys] [h.values.join(",")]"
h[:age] = 31
<< "reinsert.keys [h.keys]"
<< "str.keys [{"b" => 2, "a" => 1}.keys.join(",")]"
<< "int.keys [{1 => 10, 2 => 20}]"
<< "merge [{a: 1}.merge({b: 2})]"
<< "map [(h.map ->(k, v) "[k]=[v]").join(",")]"
<< "to_a [{a: 1, b: 2}.to_a]"
<< "empty [{}]"
<< "select [{a: 1, b: 2, c: 3}.select ->(k, v) v > 1]"
<< "sort [{b: 2, a: 1}.sort]"
<< "tos [{a: 1}.to_s]"
<< "nested [{a: {b: [1, 2]}}]"
<< "fetch [{a: 1}.fetch(:a)]"
<< {x: 1, y: [2, 3]}
