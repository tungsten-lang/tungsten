#!/bin/sh
# Regenerate the tiny codec fixtures of spec/core/codec/*_spec.w.
#
# Encoders (independent of core/codec): ffmpeg (libx264, libx265, libsvtav1,
# libvpx, libopus, libmp3lame, native aac/ac3/alac/flac/vorbis), cwebp,
# avifenc, cjxl, opj_compress, sips (HEIC, ICNS). The spec pins hashes of the
# decoded output, so after regenerating, re-pin the spec expectations (run the
# spec: a FAIL line prints the new value) and check the change is the
# encoder's, not the decoder's.
#
# Not generated here (no encoder available; copied from public test suites):
#   tiny.jxr     a 70x45 JPEG XR test stream (jxrlib's JxrEncApp output)
#   bc1.ktx2     a BC1 KTX2 texture (KTX-Software toktx)
#   theora.ogv   the headers and first frames of a Theora clip, cut at an Ogg
#                page boundary (Xiph's susie-exp.ogg)
#
# Run from this directory: sh make_fixtures.sh
set -e
python3 -I - <<'PY'
import zlib, struct
W, H = 23, 17
raw = bytearray()
for y in range(H):
    raw.append(0)
    for x in range(W):
        raw += bytes([(x * 11) & 255, (y * 15) & 255, ((x + y) * 7) & 255, 255 if (x + y) % 5 else 128])
def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
open("rgba.png", "wb").write(png)
PY
FF="ffmpeg -nostdin -hide_banner -loglevel error -y"
$FF -i rgba.png -q:v 4 -pix_fmt yuvj420p tiny.jpg
$FF -i rgba.png tiny.gif
$FF -i rgba.png -pix_fmt bgra tiny.bmp
$FF -i rgba.png -pix_fmt rgba tiny.tif
$FF -i rgba.png tiny.qoi
$FF -i rgba.png -pix_fmt gbrapf32le tiny.exr
$FF -i rgba.png -pix_fmt gbrpf32le tiny.hdr
$FF -i rgba.png -pix_fmt rgb24 tiny.ppm
$FF -i rgba.png -pix_fmt bgra tiny.tga
cwebp -quiet -q 80 rgba.png -o lossy.webp
cwebp -quiet -lossless rgba.png -o lossless.webp
avifenc -q 60 -s 10 rgba.png tiny.avif > /dev/null
sips -s format heic rgba.png --out tiny.heic > /dev/null
cjxl -q 90 rgba.png vardct.jxl > /dev/null 2>&1
cjxl -d 0 rgba.png modular.jxl > /dev/null 2>&1
opj_compress -n 3 -i tiny.ppm -o tiny.jp2 > /dev/null
sips -z 16 16 rgba.png --out icon16.png > /dev/null
mkdir -p tiny.iconset && cp icon16.png tiny.iconset/icon_16x16.png && iconutil -c icns tiny.iconset -o tiny.icns
rm -rf tiny.iconset icon16.png
# ICO with one BMP entry (16x16, 32 bpp) and DDS (8x8 BC1), written by hand
python3 -I - <<'PY'
import struct
w = h = 16
xor = bytearray()
for y in range(h):
    for x in range(w):
        xor += bytes([x * 16, y * 16, 128, 255])        # BGRA, bottom-up
andm = bytes(4 * h)
bih = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, len(xor) + len(andm), 0, 0, 0, 0)
img = bih + xor + andm
ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(img), 22) + img
open("tiny.ico", "wb").write(ico)
hdr = struct.pack("<4sIIIIIII", b"DDS ", 124, 0x1007 | 0x80000, 8, 8, 32, 0, 1) + bytes(44)
hdr += struct.pack("<II4sIIIII", 32, 4, b"DXT1", 0, 0, 0, 0, 0) + struct.pack("<IIIII", 0x1000, 0, 0, 0, 0)
blocks = b"".join(struct.pack("<HHI", 0xF800 >> (i % 2) * 5, 0x001F << i, 0xE4E4E4E4 ^ (i * 0x11111111)) for i in range(4))
open("bc1.dds", "wb").write(hdr + blocks)
PY
# video: 3 frames of testsrc
SRC="-f lavfi -i testsrc=size=32x24:rate=10 -frames:v 3"
$FF $SRC -c:v libx264 -pix_fmt yuv420p h264.mp4
$FF $SRC -c:v libx265 -x265-params log-level=none -tag:v hvc1 -pix_fmt yuv420p hevc.mp4
$FF -f lavfi -i testsrc=size=64x64:rate=10 -frames:v 3 -c:v libsvtav1 -preset 12 -pix_fmt yuv420p av1.mp4 2> /dev/null
$FF $SRC -c:v libvpx-vp9 -pix_fmt yuv420p vp9.webm
$FF $SRC -c:v libvpx -pix_fmt yuv420p vp8.webm
# audio: 0.1 s of a 440 Hz / 660 Hz stereo tone
TONE="-f lavfi -i sine=frequency=440:sample_rate=48000:duration=0.1 -f lavfi -i sine=frequency=660:sample_rate=48000:duration=0.1 -filter_complex [0:a][1:a]amerge=inputs=2"
$FF $TONE -c:a aac -b:a 64k aac.m4a
$FF $TONE -c:a libopus -b:a 32k opus.ogg
$FF $TONE -c:a vorbis -strict -2 vorbis.ogg
$FF $TONE -c:a libmp3lame -b:a 64k tone.mp3
$FF $TONE -c:a flac tone.flac
$FF $TONE -c:a alac alac.m4a
$FF $TONE -c:a ac3 -b:a 96k tone.ac3
$FF $TONE -c:a pcm_s16le tone.wav
$FF $TONE -c:a pcm_s16be tone.aiff
$FF -f lavfi -i testsrc=size=32x24:rate=10 -f lavfi -i sine=frequency=440:sample_rate=48000:duration=0.1 \
  -frames:v 3 -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 64k av.ts
