# Colour spaces and SDR Rec.709 video

Rendered frames are sRGB pixels. An SDR video master is Rec.709 Y'CbCr. This
guide covers the core classes that sit between the two: how colour spaces are
defined, which transfer function means what, how pixels become 4:2:0 planes
and bytes for an encoder, and how files are tagged. It ends with the choice a
YouTube master actually has to make.

| Class | File | What it does |
|---|---|---|
| `ColorSpace` | `core/color_space.w` | Primaries, white point, transfer; RGB↔XYZ matrices; conversion between spaces |
| `Transfer` | `core/color_space.w` | sRGB EOTF, BT.709 OETF, BT.1886 EOTF, and their inverses |
| `YCbCr` | `core/ycbcr.w` | R'G'B' ↔ Y'CbCr (BT.709, BT.601, BT.2020 matrices) with 8–16 bit quantization |
| `YuvFrame` | `core/ycbcr.w` | A picture as Y'CbCr planes; chroma subsampling; I420, NV12, P010 and other layouts |
| `Rec709`, `Cicp` | `core/rec709.w` | ITU-T H.273 code points, ffmpeg tags, shortcuts |
| `PngEncoder` | `core/raster.w` | Optional `cICP` / `sRGB` / `gAMA` / `cHRM` chunks |

## Colour spaces

A space is three primaries and a white point, as CIE 1931 x, y
chromaticities, plus the transfer function that maps its non-linear code
values (R'G'B', 0..1) to linear light. The names are the ones the drawing
canvas accepts:

| Name | Primaries, white | Transfer |
|---|---|---|
| `"srgb"` | BT.709, D65 | sRGB EOTF (IEC 61966-2-1) |
| `"rec709"` | BT.709, D65 | BT.1886 EOTF, gamma 2.4 |
| `"display_p3"` | P3 (SMPTE EG 432-1), D65 | sRGB EOTF |
| `"linear_srgb"` | BT.709, D65 | none |

```tungsten
ColorSpace.rec709.to_xyz               # [[0.4124, 0.3576, 0.1805], [0.2126, ...], ...]
ColorSpace.display_p3.matrix_to(:rec709)
ColorSpace.srgb.convert([~1.0, ~0.5, ~0.0], :rec709)   # code values -> code values
ColorSpace.named("display_p3").decode(~0.5)            # code value -> linear light
ColorSpace.rec709.with_transfer(:bt709)                # same primaries, camera curve
```

The matrices are derived in code from the chromaticities (SMPTE RP 177-1993),
not copied from tables. The specs check them against the 4-decimal matrix in
IEC 61966-2-1 and the exact rationals in CSS Color 4. `luma_weights`, the Y
row, rounds to BT.709's 0.2126, 0.7152, 0.0722. `convert` decodes, changes
primaries in linear light, clips each channel to [0, 1], and encodes. A
Display P3 colour outside BT.709 is clipped, not compressed. All four spaces
share D65, so no chromatic adaptation is needed, and `matrix_to` refuses a
pair whose white points differ.

## Transfer functions: scene-referred and display-referred

| Function | Standard | Meaning |
|---|---|---|
| `Transfer.bt709_oetf(L)` | ITU-R BT.709-6 item 1.2 | Scene light → camera signal. `1.099 L^0.45 − 0.099` for L ≥ 0.018, `4.5 L` below |
| `Transfer.bt1886_eotf(V, Lw, Lb)` | ITU-R BT.1886 Annex 1 | Signal → light on the reference display. `a·max(V + b, 0)^2.4`; Lw = 1, Lb = 0 gives `V^2.4` |
| `Transfer.srgb_eotf(V)` | IEC 61966-2-1 | sRGB pixel → display light. `V/12.92` up to 0.04045, else `((V + 0.055)/1.055)^2.4` |

Each has an inverse (`bt709_inverse_oetf`, `bt1886_inverse_eotf`,
`srgb_inverse_eotf`). The formulas keep the published constants. With
BT.709's rounded 1.099 / 0.018, the two pieces of the OETF meet only to
2.5e-4; the inverse switches at 0.081, so L → V → L is exact.

The OETF and the EOTF are not inverses of each other, and the difference is
deliberate. The OETF describes a camera looking at a scene. BT.709 itself
says (note 1 to item 1.2) that in practice the signal is adjusted until the
picture looks right on a BT.1886 reference monitor in a dim room (BT.2035).
So the code values of an SDR master are display-referred: they mean whatever
light a BT.1886 display makes from them. That is why `"rec709"` uses the
BT.1886 EOTF, and why converting graphics for video starts from the display,
not the camera.

`Transfer.srgb_to_bt1886(V)` is that conversion. It decodes with the sRGB
EOTF and encodes with the inverse BT.1886 EOTF, so an sRGB pixel makes the
same light on a BT.1886 display that it made on an sRGB one. Above sRGB's
breakpoint this is exactly `(V + 0.055) / 1.055`.

## Y'CbCr

`YCbCr` follows BT.709-6 items 3.2–3.4:

- E'Y = Kr R' + Kg G' + Kb B', with Kr = 0.2126 and Kb = 0.0722.
- E'CB = (B' − E'Y) / 1.8556 and E'CR = (R' − E'Y) / 1.5748.
- **Limited range:** D'Y = INT[(219 E'Y + 16)·2^(n−8)] and D'C = INT[(224 E'C + 128)·2^(n−8)]. At 8 bits Y' is 16..235 and C is 16..240; at 10 bits, 64..940 and 64..960.
- **Full range** (H.273 VideoFullRangeFlag = 1): D'Y = Round((2^n − 1) E'Y) and D'C = Round((2^n − 1) E'C + 2^(n−1)).

Rounding is half away from zero (BT.709's INT, H.273's Round). Limited-range
codes are clipped to BT.709-6 item 4.7's video-data range (8-bit 1..254,
10-bit 4..1019, 12-bit 16..4079), because 0 and 255 are timing references.
Full-range codes are clipped to 0..2^n − 1. Decoding clamps R'G'B' to [0, 1].

```tungsten
q = YCbCr.bt709                 # 8-bit limited; YCbCr.bt709(10), YCbCr.bt709(8, :full)
q.encode(~1.0, ~1.0, ~0.0)      # [219, 16, 138]: 100% yellow
q.decode(219, 16, 138)          # R'G'B' in [0, 1]
q.encode_rgb8(255, 128, 0)      # from 8-bit RGB
YCbCr.bt601 / YCbCr.bt2020      # other matrices, for reading other streams
```

Round trips are bounded by quantization. 8-bit RGB through 8-bit 4:4:4
returns within 2 codes (1 for R and G). Through 10-bit it returns exactly,
since the error stays under half an 8-bit code.

## Frames, chroma subsampling, pixel layouts

```tungsten
f = YuvFrame.from_raster(raster)                  # 4:2:0, 8-bit, BT.709, limited, left siting
f = YuvFrame.from_raster(raster, {bits: 10, chroma: :yuv422, siting: :left, transfer: :passthrough})
f = YuvFrame.from_rgba(bytes, w, h, {order: :bgra, stride: w * 4})   # e.g. a CoreGraphics bitmap
f.to_i420   f.to_nv12   f.to_p010   f.to_yuv420p10le   f.to_bytes("p210le")
g = YuvFrame.from_bytes(bytes, "nv12", w, h)
g.to_raster                                       # back to sRGB 8-bit
YuvFrame.byte_size("yuv420p", 1920, 1080)         # 3110400
```

Options for `from_raster` and `from_rgba`:

- `chroma`: `:yuv420`, `:yuv422` or `:yuv444`.
- `bits`: 8, 10, 12 or 16.
- `range`: `:limited` or `:full`.
- `matrix`: `:bt709`, `:bt601` or `:bt2020`.
- `siting`: `:left`, `:center` or `:topleft`.
- `source`: the raster's colour space, default `"srgb"`.
- `transfer`: see below.

Alpha in RGBA input is ignored, so composite first.

**Subsampling.** Chroma is filtered at full resolution in R'G'B', then
decimated. Cb and Cr are linear in R'G'B', so this is the same as filtering
Cb and Cr. On each halved axis:

- A chroma sample co-sited with a luma sample is `[1 2 1]/4` around it.
- A sample midway between two luma samples is `[1 1]/2` of the two.

Edge samples are repeated. The sitings use the H.264/HEVC
`chroma_sample_loc_type` names:

- `:left` (type 0): co-sited horizontally and midway vertically for 4:2:0, co-sited for 4:2:2. This is the H.264, HEVC and MPEG-2 default, the one a decoder assumes when the stream does not say.
- `:center` (type 1, MPEG-1/JPEG): midway on both axes.
- `:topleft` (type 2): co-sited on both axes.

Upsampling interpolates linearly between the two nearest chroma samples on
each axis, at the same sites.

**Layouts** are tightly packed, with no row padding. Samples over 8 bits are
16-bit little-endian.

| Format | Planes | Notes |
|---|---|---|
| `yuv420p` (`i420`), `yuv422p`, `yuv444p` | Y, Cb, Cr | 8-bit |
| `yuv420p10le`, `…12le`, `…16le` (and 4:2:2, 4:4:4) | Y, Cb, Cr | value in the low bits |
| `nv12`, `nv16` | Y, then Cb Cr pairs | 8-bit 4:2:0 / 4:2:2 |
| `p010le`, `p210le` | Y, then Cb Cr pairs | 10 bits in the high bits (value << 6): VideoToolbox's 420 / 422 10-bit bi-planar |

**Speed** for one 1920×1080 frame, from `--release` builds of
`benchmarks/media/rec709_frame.w` on the M5 Max:

| Step | Time |
|---|---|
| Raster → I420 bytes | 21 ms |
| Raster → P010 bytes | 22 ms |
| I420 bytes → Raster | 19 ms |
| Display P3 source | 121 ms (per-pixel `pow`) |

Packing alone is under 0.5 ms. The planned Metal path will replace this.
This CPU path is the reference and the fallback for wasm and tests.

## Tagging

The ITU-T H.273 code points for SDR Rec.709 are colour primaries 1,
transfer characteristics 1, matrix coefficients 1 and video full range
flag 0:

```tungsten
Rec709.colour_primaries          # 1 (also transfer_characteristics, matrix_coefficients)
Rec709.video_full_range_flag     # 0
Rec709.cicp.to_a                 # [1, 1, 1, 0]
Rec709.ffmpeg_flags              # -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709
                                 # -colorspace bt709 -color_range tv
Rec709.ffmpeg_flags("yuv420p10le", :left)   # adds -chroma_sample_location left
Cicp.for("display_p3").to_a      # [12, 13, 0, 1]: an RGB picture (matrix 0, full range)
```

Tags describe pixels; they never convert them. H.273 names the BT.709 OETF
for transfer characteristics 1 and leaves the display to BT.1886. Players
read the tag differently, which is what the next section is about.

PNG output is unchanged unless you ask for a tag. With one:

- `r.write_png(path, "srgb")` writes the classic `cHRM` + `gAMA 45455` + `sRGB` set.
- `"rec709"`, `"display_p3"` and `"linear_srgb"` write `cICP` with RGB code points (matrix 0, full range), a `cHRM`, and a `gAMA` where one is exact enough (P3 45455, linear 100000).
- A `Cicp` writes `cICP` alone, and must have matrix 0.

All the chunks go before `IDAT`, as PNG 3rd edition requires.

## The SDR master: pass-through or BT.1886?

**What `youtube_master.sh` does today.** It renders sRGB PNG frames and lets
ffmpeg's `scale=out_color_matrix=bt709:out_range=tv:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p`
make 4:2:0 BT.709 limited-range planes. It then encodes with x264, tagged
`-color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv`.
No transfer function is applied: the sRGB code values become R'G'B' as they
are, and the stream says they are BT.709. This is the **pass-through**
convention. Comparing ffmpeg's planes with `YuvFrame` on a test card shows:

- Y' (and 4:4:4 chroma) match exactly on colour bars, and within 1 code (swscale's fixed point) on gradients.
- ffmpeg's 4:2:0 chroma is **center**-sited. `siting: :center` reproduces it within 7 codes, the difference being lanczos against a box filter at hard edges.
- The H.264 stream carries no chroma location, so decoders assume `:left`. Every master so far has its chroma half a luma pixel off horizontally. At 4K this is invisible; at 1080p it shows only on saturated hard edges.

`YuvFrame.from_raster(r, {siting: :center})` reproduces today's output.

**The alternative**, `transfer: :bt1886`, re-encodes each pixel so that a
BT.1886 display shows the light an sRGB display showed. Its effect is mostly
in the shadows, because sRGB's linear toe gives far more light near black
than gamma 2.4:

| sRGB pixel | Pass-through Y' | BT.1886 Y' |
|---|---|---|
| 10 | 25 | 36 |
| 128 | 126 | 132 |
| 255 | 235 | 235 |

**Recommendation: keep pass-through, and fix the siting.**

- **Appearance.** sRGB's reference viewing is a lit room. BT.1886's gamma 2.4 belongs with a dim room. The 2.2→2.4 difference is surround compensation, so sending the same code values to each display in its own environment preserves the look. The colorimetric conversion preserves the light instead, which looks lifted and flat in the dim room.
- **What viewers see.** Most players on phones, PCs and TVs show BT.709-tagged SDR code values essentially unchanged on an sRGB-like display. With pass-through, the uploaded picture is the one you reviewed. With the BT.1886 conversion, dark backgrounds would come out visibly grey (sRGB 10 becomes Y' 36) on exactly those players. Apple's QuickTime/Safari pipeline is the known exception: it decodes BT.709 with an effective gamma near 1.96 and looks lighter, whichever conversion you choose.
- **Siting.** Use the default `:left` siting, which matches what decoders assume. If the frames still go through ffmpeg, pass `Rec709.ffmpeg_flags(fmt, :left)` so the stream says so.

Use `transfer: :bt1886` when the master is graded on a BT.1886 reference
monitor, or when graphics must match camera footage already graded that way.
`transfer: :bt709` applies the camera OETF. It is what CoreGraphics'
`kCGColorSpaceITUR_709` uses as its curve (measured: parametric
γ 2.2222, a 0.9099, b 0.0901, c 0.2222, d 0.081), so a canvas in that space
does not give pass-through pixels.

For 10-bit delivery (HEVC Main10 through VideoToolbox), build frames with
`bits: 10` and hand over `to_p010`. Gradients then keep 4× the code values,
and 8-bit RGB round-trips exactly.
