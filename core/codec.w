# core/codec — image, audio and video codecs in pure Tungsten.
#
#   use core/codec
#   bm = Image.decode(File.read_bytes("photo.avif"))   # Bitmap: straight RGBA8, sRGB
#   d = demux_for(bytes)                                # an incremental demuxer, or nil
#   dec = Codec.video(d.tracks[0].cfg)                  # VideoFrame / AudioBlock out
#
# Layout (`use` any one file for just that codec; each pulls in its contract):
#   codec/image.w, codec/media.w   the contracts: Bitmap + Image registry;
#                                  CodecConfig, MediaSample, VideoFrame,
#                                  AudioBlock + Codec registry
#   codec/cicp.w                   CICP colour code points (ISO/IEC 23091-2)
#   codec/image/                   PNG, JPEG, GIF, BMP/ICO/CUR, WebP, TIFF, QOI,
#                                  OpenEXR, Radiance HDR, ICNS, DDS/KTX2, PNM,
#                                  TGA, HEIF (AVIF/HEIC), JPEG XL, JPEG 2000,
#                                  JPEG XR; ICC profiles
#   codec/video/                   H.264, HEVC, AV1, VP9, VP8, Theora; yuv.w
#                                  converts VideoFrames to RGBA
#   codec/audio/                   AAC (SBR/PS), Opus, MP3, FLAC, Vorbis, ALAC,
#                                  AC-3/E-AC-3, PCM
#   codec/container/               MP4, WebM/Matroska, Ogg, MPEG-TS, WAV/AIFF and
#                                  elementary-stream demuxers
#   codec/text/webvtt.w            WebVTT and SRT parsing, cue layout
#
# Each directory's all.w loads all of it; this file loads everything.

use core/codec/image/all
use core/codec/media
use core/codec/container/all
use core/codec/audio/all
use core/codec/text/webvtt
use core/codec/video/all
