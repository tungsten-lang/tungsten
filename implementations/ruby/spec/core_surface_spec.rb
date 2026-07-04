RSpec.describe "core scalar and object surfaces" do
  def run(code)
    Tungsten::Interpreter.new.run(code)
  end

  it "reports character literals as Char" do
    result = run(<<~W)
      [
        :-/.class.name,
        :-..class.name,
        :-(.class.name,
        :-A.class.name,
        U+221E.class.name,
        :-/.type,
        U+221E.type
      ]
    W

    expect(result).to eq([ "Char", "Char", "Char", "Char", "Char", "Char", "Char" ])
  end

  it "exposes Unicode character operations" do
    result = run(<<~W)
      [
        U+0041.ord,
        U+0041.to_s,
        U+0041.letter?,
        U+0041.uppercase?,
        U+0061.upcase.to_s,
        U+0039.digit?,
        U+0020.whitespace?,
        U+002E.punctuation?,
        U+221E.symbol?,
        U+0041.category,
        U+0041.general_category,
        U+0041.unicode_escape,
        :-A.next.to_s,
        :-B.prev.to_s
      ]
    W

    expect(result).to eq([
      65,
      "A",
      true,
      true,
      "A",
      true,
      true,
      true,
      true,
      "Lu",
      "Uppercase Letter",
      "U+0041",
      "B",
      "A"
    ])
  end

  it "supports integer conversion and neighbors" do
    result = run(<<~W)
      [
        42.to_s,
        42.to_s(16),
        42.to_s(2),
        42.to_f,
        42.prev,
        42.next,
        42.succ
      ]
    W

    expect(result).to eq([ "42", "2a", "101010", 42.0, 41, 43, 43 ])
  end

  it "exposes network address and CIDR helpers" do
    result = run(<<~W)
      ip = IPv4.parse("192.168.1.42")
      net = CIDR.parse("192.168.1.0/24")
      any = CIDR.parse("0.0.0.0/0")
      v6 = IPv6.parse("2001:db8::1")
      v6net = CIDR.parse("2001:db8::/32")
      mac = MAC.parse("02-11-22-33-44-55")

      [
        ip.to_s,
        ip.octets,
        ip[3],
        ip.private?,
        ip.global?,
        net.to_s,
        net.prefix,
        net.network.to_s,
        net.broadcast.to_s,
        net.netmask.to_s,
        net.include?(ip),
        net.include?(IPv4.parse("192.168.2.1")),
        any.to_s,
        any.include?(IPv4.parse("8.8.8.8")),
        v6.bytes[0],
        v6.bytes[1],
        v6.loopback?,
        v6net.prefix,
        v6net.include?(v6),
        v6net.include?(IPv6.parse("2001:db9::1")),
        mac.to_s,
        mac.bytes,
        mac.local?,
        mac.multicast?,
        mac.unicast?
      ]
    W

    expect(result).to eq([
      "192.168.1.42",
      [192, 168, 1, 42],
      42,
      true,
      false,
      "192.168.1.0/24",
      24,
      "192.168.1.0/24",
      "192.168.1.255/24",
      "255.255.255.0",
      true,
      false,
      "0.0.0.0/0",
      true,
      32,
      1,
      false,
      32,
      true,
      false,
      "02:11:22:33:44:55",
      [2, 17, 34, 51, 68, 85],
      true,
      false,
      true
    ])
  end

  it "exposes runtime-backed digest helpers" do
    result = run(<<~W)
      [
        Digest.md5("abc"),
        Digest.sha1("abc"),
        Digest.sha1_base64("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"),
        Digest.sha224("abc"),
        Digest.sha256("abc"),
        Digest.sha384("abc"),
        Digest.sha512("abc"),
        Digest.sha512_224("abc"),
        Digest.sha512_256("abc"),
        Digest.sha2("abc", 224),
        Digest.sha2("abc"),
        Digest.sha2("abc", 384),
        Digest.sha2("abc", 512),
        Digest.sha2("abc", "512/224"),
        Digest.sha2("abc", "512/256"),
        Crypto.sha224("abc"),
        Crypto.sha256("abc"),
        Crypto.sha384("abc"),
        Crypto.sha512("abc"),
        Crypto.sha512_224("abc"),
        Crypto.sha512_256("abc"),
        Crypto.sha2("abc"),
        Digest.sha224_bytes("abc").size,
        Digest.sha256_bytes("abc").size,
        Digest.sha384_bytes("abc").size,
        Digest.sha512_bytes("abc").size,
        Digest.sha512_224_bytes("abc").size,
        Digest.sha512_256_bytes("abc").size,
        Crypto.random_bytes(8).size,
        Random.bytes(8).size
      ]
    W

    expect(result).to eq([
      "900150983cd24fb0d6963f7d28e17f72",
      "a9993e364706816aba3e25717850c26c9cd0d89d",
      "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
      "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
      "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa",
      "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23",
      "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
      "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa",
      "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23",
      "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
      "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa",
      "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23",
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      28,
      32,
      48,
      64,
      28,
      32,
      8,
      8
    ])
  end

  it "generates and parses UUIDs" do
    result = run(<<~W)
      v1 = UUID.v1()
      v1_custom = UUID.v1({time: 0, mac: [2, 17, 34, 51, 68, 85]})
      v2 = UUID.v2({local_identifier: 123, domain: 1, time: 0, mac: [2, 17, 34, 51, 68, 85]})
      v3 = UUID.v3(UUID.dns(), "www.example.com")
      v4 = UUID.v4()
      v5 = UUID.v5(UUID.dns(), "www.example.com")
      v6 = UUID.v6()
      v7 = UUID.v7()
      v8 = UUID.v8()
      v8_custom = UUID.v8(Digest.md5_bytes("abc"))
      [
        v1.version,
        v1.variant,
        v1_custom.byte(10),
        v1_custom.byte(11),
        v1_custom.byte(12),
        v1_custom.byte(13),
        v1_custom.byte(14),
        v1_custom.byte(15),
        v2.version,
        v2.variant,
        v2.byte(9),
        v2.byte(10),
        v2.byte(11),
        v2.byte(12),
        v2.byte(13),
        v2.byte(14),
        v2.byte(15),
        v3.version,
        v3.variant,
        v4.version,
        v4.variant,
        v4.to_s.size,
        v5.version,
        v5.variant,
        v6.version,
        v6.variant,
        v7.version,
        v7.variant,
        v8.version,
        v8.variant,
        v8_custom.version,
        v8_custom.variant,
        v8_custom.to_s,
        Random.uuid.version,
        Random.uuid1().version,
        Random.uuid2({local_identifier: 123, domain: 1}).version,
        Random.uuid3(UUID.dns(), "www.example.com").version,
        Random.uuid4().version,
        Random.uuid5(UUID.dns(), "www.example.com").version,
        Random.uuid6().version,
        Random.uuid7().version,
        Random.uuid8().version,
        v3.to_s,
        v5.to_s,
        UUID.parse("urn:uuid:2ed6657d-e927-568b-95e1-2665a8aea6a2").to_s
      ]
    W

    expect(result).to eq([
      :v1,
      :rfc4122,
      2,
      17,
      34,
      51,
      68,
      85,
      :v2,
      :rfc4122,
      1,
      2,
      17,
      34,
      51,
      68,
      85,
      :v3,
      :rfc4122,
      :v4,
      :rfc4122,
      36,
      :v5,
      :rfc4122,
      :v6,
      :rfc4122,
      :v7,
      :rfc4122,
      :v8,
      :rfc4122,
      :v8,
      :rfc4122,
      "90015098-3cd2-8fb0-9696-3f7d28e17f72",
      :v4,
      :v1,
      :v2,
      :v3,
      :v4,
      :v5,
      :v6,
      :v7,
      :v8,
      "5df41881-3aed-3515-88a7-2f4a814cf09e",
      "2ed6657d-e927-568b-95e1-2665a8aea6a2",
      "2ed6657d-e927-568b-95e1-2665a8aea6a2"
    ])
  end

  it "keeps Object introspection usable without identity hooks" do
    result = run(<<~W)
      + Box
        -> new(@value) ro

      box = Box(1)
      [
        box.class.name,
        box.class_name,
        box.type,
        box.itself.class_name,
        box.respond_to?(:object_id),
        box.respond_to?(:__id__),
        box.respond_to?(:equal?),
        box.respond_to?(:class_name),
        1.respond_to?(:object_id),
        1.respond_to?(:__id__),
        1.respond_to?(:equal?),
        "x".respond_to?(:object_id),
        true.respond_to?(:equal?)
      ]
    W

    expect(result).to eq([
      "Box",
      "Box",
      "Box",
      "Box",
      false,
      false,
      false,
      true,
      false,
      false,
      false,
      false,
      false
    ])

    expect { run("1.object_id") }.to raise_error(Tungsten::Error, /undefined method 'object_id'/)
    expect { run("1.__id__") }.to raise_error(Tungsten::Error, /undefined method '__id__'/)
    expect { run("1.equal?(1)") }.to raise_error(Tungsten::Error, /undefined method 'equal\?'/)
  end
end
