# Random — random bytes and the UUID version constructors (core/random.w).
#
# Every method is a one-line delegation: `bytes` to Crypto.random_bytes, the
# `uuid*` family to the matching UUID.v* constructor. The same nine methods are
# declared twice, once as class methods and once as instance methods.
#
# Run:
#   bin/tungsten run --interpret spec/core/random_spec.w
#   bin/tungsten -o /tmp/random_spec spec/core/random_spec.w && /tmp/random_spec

use core/random

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# RFC 4122 DNS namespace, used for the name-based versions below.
dns = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

# ---- bytes ----
check("bytes returns an array", type(Random.bytes(8)) == "Array")
check("bytes honours the length", Random.bytes(8).size == 8)
check("bytes of zero is empty", Random.bytes(0).size == 0)
check("bytes of one", Random.bytes(1).size == 1)
check("bytes are in byte range", Random.bytes(32).all? -> (b) b >= 0 && b <= 255)
check("bytes differ between calls", Random.bytes(32) != Random.bytes(32))
check("a long draw still has the right size", Random.bytes(1024).size == 1024)

# ---- uuid / uuid4: random v4 ----
u = Random.uuid
check("uuid returns a UUID", type(u) == "UUID")
check("uuid renders in canonical form", u.to_s.size == 36)
check("uuid is version 4", u.version == :v4)
check("uuid4 is version 4", Random.uuid4.version == :v4)
check("uuid4 is the same generator as uuid", Random.uuid4.to_s.size == 36)
check("random uuids differ", Random.uuid.to_s != Random.uuid.to_s)
# Canonical layout 8-4-4-4-12: the version nibble sits at index 14.
check("uuid version nibble", Random.uuid.to_s.slice(14, 1) == "4")
check("uuid dashes", u.to_s.slice(8, 1) == "-" && u.to_s.slice(13, 1) == "-" && u.to_s.slice(18, 1) == "-")

# ---- the other versions ----
check("uuid1 is version 1", Random.uuid1.version == :v1)
check("uuid1 version nibble", Random.uuid1.to_s.slice(14, 1) == "1")
check("uuid2 is version 2", Random.uuid2.version == :v2)
check("uuid6 is version 6", Random.uuid6.version == :v6)
check("uuid6 version nibble", Random.uuid6.to_s.slice(14, 1) == "6")
check("uuid7 is version 7", Random.uuid7.version == :v7)
check("uuid7 version nibble", Random.uuid7.to_s.slice(14, 1) == "7")
check("uuid8 is version 8", Random.uuid8.version == :v8)

# ---- name-based versions are deterministic ----
check("uuid3 is version 3", Random.uuid3(dns, "x").version == :v3)
check("uuid3 is deterministic", Random.uuid3(dns, "x").to_s == Random.uuid3(dns, "x").to_s)
check("uuid3 discriminates by name", Random.uuid3(dns, "x").to_s != Random.uuid3(dns, "y").to_s)
check("uuid5 is version 5", Random.uuid5(dns, "x").version == :v5)
check("uuid5 is deterministic", Random.uuid5(dns, "x").to_s == Random.uuid5(dns, "x").to_s)
check("uuid5 discriminates by name", Random.uuid5(dns, "x").to_s != Random.uuid5(dns, "y").to_s)
check("uuid5 differs from uuid3 for the same input",
      Random.uuid5(dns, "x").to_s != Random.uuid3(dns, "x").to_s)

# ---- the instance-method half mirrors the class-method half ----
r = Random.new
check("instance constructs", type(r) == "Random")
check("instance bytes", r.bytes(4).size == 4)
check("instance uuid", r.uuid.version == :v4)
check("instance uuid1", r.uuid1.version == :v1)
check("instance uuid2", r.uuid2.version == :v2)
check("instance uuid3", r.uuid3(dns, "x").to_s == Random.uuid3(dns, "x").to_s)
check("instance uuid4", r.uuid4.version == :v4)
check("instance uuid5", r.uuid5(dns, "x").to_s == Random.uuid5(dns, "x").to_s)
check("instance uuid6", r.uuid6.version == :v6)
check("instance uuid7", r.uuid7.version == :v7)
check("instance uuid8", r.uuid8.version == :v8)

# BUG: UUID#== is identity, not value equality — two UUIDs built from the same name-based
# inputs render identically but compare unequal (so does `UUID.v4 == UUID.v4`, trivially).
# Repro: printf 'use core/random\nd = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"\n' > /tmp/u.w &&
#        printf '<< (Random.uuid5(d, "x") == Random.uuid5(d, "x"))\n' >> /tmp/u.w &&
#        bin/tungsten run --interpret /tmp/u.w   # false
# check("name-based uuids are equal", Random.uuid5(dns, "x") == Random.uuid5(dns, "x"))
# BUG: UUID#size raises "undefined method 'size'" — only `to_s.size` works.
# check("uuid size", Random.uuid.size == 36)

<< "ALL PASS random_spec ([passed.load()] checks)"
