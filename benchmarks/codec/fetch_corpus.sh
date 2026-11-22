#!/bin/sh
# Fetch the public conformance corpora the codec harnesses in this directory
# run against (they stay out of the repository; spec/core/codec/ has the tiny
# fixtures the spec suite uses).
#
#   sh benchmarks/codec/fetch_corpus.sh [DIR]      # default benchmarks/codec/corpus
#
# Then, for example:
#   bin/tungsten -o /tmp/imgtest --release benchmarks/codec/imgtest.w
#   /tmp/imgtest -- benchmarks/codec/corpus/pngsuite/*.png
#   bin/tungsten benchmarks/codec/heiftest.w -- benchmarks/codec/corpus/avif-sample-images
#   bin/tungsten benchmarks/codec/vtest.w -- -r ref.yuv benchmarks/codec/corpus/libvpx/vp90-2-00-quantizer-00.webm
#   bin/tungsten benchmarks/codec/opus_test.w -- tv benchmarks/codec/corpus/opus_testvectors
#   bin/tungsten benchmarks/codec/webvtt_test.w -- benchmarks/codec/corpus/wpt-webvtt
#
# References (ImageIO / ffmpeg / libwebp / libjxl decodes) are made by each
# harness or by hand with the reference tool; see each harness's header.
set -e
DIR=${1:-benchmarks/codec/corpus}
mkdir -p "$DIR"
cd "$DIR"

clone() {  # clone URL DIR: shallow, once
  [ -d "$2" ] || git clone --depth 1 "$1" "$2"
}
get() {    # get URL FILE: once
  [ -s "$2" ] || curl -fsSL -o "$2" "$1"
}

# Images
mkdir -p pngsuite
get http://www.schaik.com/pngsuite/PngSuite-2017jul19.tgz pngsuite.tgz
tar -xzf pngsuite.tgz -C pngsuite
clone https://github.com/webmproject/libwebp-test-data.git libwebp-test-data
clone https://github.com/link-u/avif-sample-images.git avif-sample-images
clone https://github.com/nokiatech/heif_conformance.git heif_conformance
clone https://github.com/libjxl/conformance.git jxl-conformance
clone https://github.com/uclouvain/openjpeg-data.git openjpeg-data
clone https://github.com/4creators/jxrlib.git jxrlib
clone https://github.com/robert-ancell/pygif.git pygif

# Video: libvpx test vectors (VP8 / VP9, with .md5 of the decoded frames)
mkdir -p libvpx
for v in vp80-00-comprehensive-001.ivf vp80-00-comprehensive-007.ivf vp80-05-sharpness-1428.ivf \
         vp90-2-00-quantizer-00.webm vp90-2-02-size-08x08.webm vp90-2-03-size-196x196.webm \
         vp90-2-05-resize.ivf vp90-2-08-tile-4x4.webm vp90-2-16-intra-only.webm vp91-2-04-yuv444.webm; do
  get https://storage.googleapis.com/downloads.webmproject.org/test_data/libvpx/$v libvpx/$v
  get https://storage.googleapis.com/downloads.webmproject.org/test_data/libvpx/$v.md5 libvpx/$v.md5
done
# H.264 (ITU-T H.264.1 conformance bitstreams; unzip for the .264/.jsv and _dec.yuv references)
mkdir -p jvt
for z in AVCv1/BA1_Sony_D.zip AVCv1/CABA1_SVA_B.zip AVCv1/CAPAMA3_Sand_F.zip AVCv1/BAMQ1_JVC_C.zip FRExt/FRExt1_Panasonic_D.zip; do
  get https://www.itu.int/wftp3/av-arch/jvt-site/draft_conformance/$z jvt/$(basename $z)
done

# Audio
get https://opus-codec.org/static/testvectors/opus_testvectors-rfc8251.tar.gz opus_testvectors.tar.gz
mkdir -p opus_testvectors && tar -xzf opus_testvectors.tar.gz -C opus_testvectors
clone https://github.com/ietf-wg-cellar/flac-test-files.git flac-test-files

# Text tracks: the WebVTT parsing tests of web-platform-tests
if [ ! -d wpt-webvtt ]; then
  git clone --depth 1 --filter=blob:none --sparse https://github.com/web-platform-tests/wpt.git wpt-webvtt
  git -C wpt-webvtt sparse-checkout set webvtt
fi
echo "corpus in $DIR"
