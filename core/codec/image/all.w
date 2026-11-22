# core/codec/image/all — every image decoder, loaded for its img_register side
# effect (see core/codec/image for the contract). Image.sniff / Image.decode
# try formats in this order; each sniffs magic numbers only.
#
# AVIF and HEIC are HEIF containers whose payloads the AV1 and HEVC video
# decoders decode (they register with heif_codec_register).

use core/codec/image
use jxl
use jp2
use jxr
use heif
use core/codec/video/av1
use core/codec/video/hevc
use icc
use core/codec/cicp
use png
use jpeg
use gif
use webp
use bmp
use tiff
use qoi
use exr
use rgbe
use icns
use gputex
use pnm
use tga
