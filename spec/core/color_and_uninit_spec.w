# SDR Color bitop fast paths, #to_rgba_u32 / #to_bgra_u32, HDR fallback, and ByteArray.uninit.
#
# Run:
#   bin/tungsten spec/core/color_and_uninit_spec.w
#   bin/tungsten run --interpret spec/core/color_and_uninit_spec.w
#   bin/tungsten --ruby spec/core/color_and_uninit_spec.w

use core/color
use core/byte_array

passed = [0]

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed[0] = passed[0] + 1

c1 = Color.rgb(18, 52, 86)
check("rgb type", type(c1) == "Color")
check("rgb r", c1.r == 18)
check("rgb g", c1.g == 52)
check("rgb b", c1.b == 86)
check("rgb a", c1.a == 255)
check("rgb to_s", c1.to_s == "#123456")
check("rgb to_rgba_u32", c1.to_rgba_u32 == 0xFF563412)
check("rgb to_bgra_u32", c1.to_bgra_u32 == 0xFF123456)

c2 = Color.rgba(18, 52, 86, 120)
check("rgba r", c2.r == 18)
check("rgba g", c2.g == 52)
check("rgba b", c2.b == 86)
check("rgba a", c2.a == 120)
check("rgba to_rgba_u32", c2.to_rgba_u32 == 0x78563412)
check("rgba to_bgra_u32", c2.to_bgra_u32 == 0x78123456)
check("rgba equality", c2 == Color.rgba(18, 52, 86, 120))
check("rgba inequality", c2 != c1)

# Byte masking (& 0xFF) on SDR constructors
cl = Color.rgba(-10, 300, 128, 999)
check("mask r", cl.r == 246)
check("mask g", cl.g == 44)
check("mask b", cl.b == 128)
check("mask a", cl.a == 231)

# Hex parsing (#RGB, #RGBA, #RRGGBB, #RRGGBBAA)
check("hex #RGB", Color.hex("#1aF") == Color.rgb(0x11, 0xAA, 0xFF))
check("hex #RGBA", Color.hex("#1aF8") == Color.rgba(0x11, 0xAA, 0xFF, 0x88))
check("hex #RRGGBB", Color.hex("#123456") == c1)
check("hex #RRGGBBAA", Color.hex("#12345678") == c2)

# ByteArray.uninit
b0 = ByteArray.uninit(0)
check("uninit(0) size", b0.size == 0)

buf = ByteArray.uninit(64)
check("uninit(64) size", buf.size == 64)
i = 0
while i < 64
  buf[i] = (i * 3 + 7) & 255
  i += 1
ok = true
i = 0
while i < 64
  if buf[i] != ((i * 3 + 7) & 255)
    ok = false
  i += 1
check("uninit write/read roundtrip", ok)

neg_raised = false
begin
  ByteArray.uninit(-1)
rescue e
  neg_raised = true
check("uninit(-1) raises", neg_raised)

<< "ALL PASS color_and_uninit_spec (" + passed[0].to_s + " checks)"
