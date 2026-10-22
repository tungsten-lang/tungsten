#!/bin/sh
# benchmarks/media/run.sh — VideoEncoder against the ffmpeg CLI on the same frames.
#
#   benchmarks/media/run.sh SRC.mp4 START_FRAME COUNT WORKDIR CONTENDER...
#
# Decodes COUNT frames of SRC from START_FRAME once to raw RGB24
# (WORKDIR/raw.rgb, 6.2 MB a 1080p frame), then for each contender encodes
# them, times it with /usr/bin/time -l (wall, user + sys CPU, peak RSS and
# peak memory footprint; encode_bench maps the raw file, so its RSS counts
# the file's page-cache pages and the footprint is the comparable number),
# and scores the output with libvmaf (VMAF v0.6.1 and SSIM, luma) against
# the raw frames. Both sides are converted to BT.709 limited-range 4:2:0 for
# scoring; each output is first decoded to RGB with the matrix it was
# encoded with (BT.601 for the untagged libx264 file, BT.709 for the rest),
# so a matrix mismatch is not counted as coding error. Results append to
# WORKDIR/results.tsv. Delete WORKDIR/raw.rgb when done.
#
# Contenders:
#   x264                 ffmpeg libx264 -preset medium -crf 18 -pix_fmt yuv420p -x264-params keyint=48 (the current settings)
#   ffvt-h264:Q          ffmpeg h264_videotoolbox -q:v Q (Q in 0..100), BT.709
#   ffvt-hevc:Q          ffmpeg hevc_videotoolbox -q:v Q
#   tw-h264:Q[:N]        encode_bench, VideoEncoder H.264 quality Q/100, N sessions
#   tw-hevc:Q[:N]        encode_bench, VideoEncoder HEVC quality Q/100
#   tw-h264r:Q, tw-hevcr:Q  the same with frame reordering (B-frames) inside segments
#
# Needs: ffmpeg with libx264, videotoolbox and libvmaf; ENCODE_BENCH set to an
# encode_bench binary built with --release.
set -eu
SRC=$1; START=$2; COUNT=$3; W=$4; shift 4
: "${ENCODE_BENCH:?set ENCODE_BENCH to a --release build of benchmarks/media/encode_bench.w}"
mkdir -p "$W"
RAW=$W/raw.rgb
SIZE=1920x1080
if [ ! -s "$RAW" ]; then
  T=$(awk -v f="$START" 'BEGIN { printf "%.6f", f / 24 }')
  ffmpeg -v error -y -ss "$T" -i "$SRC" -frames:v "$COUNT" -f rawvideo -pix_fmt rgb24 "$RAW"
fi
[ -f "$W/results.tsv" ] || printf 'contender\tframes\twall_s\tcpu_s\tpeak_rss_mb\tfootprint_mb\tbytes\tvmaf\tssim\n' > "$W/results.tsv"

score() {  # $1 file $2 matrix $3 json
  ffmpeg -v error -i "$1" -f rawvideo -pix_fmt rgb24 -s "$SIZE" -r 24 -i "$RAW" -lavfi \
    "[0:v]scale=in_color_matrix=$2:in_range=tv:flags=accurate_rnd+full_chroma_int,format=rgb48le,scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setpts=PTS-STARTPTS[d];[1:v]scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setpts=PTS-STARTPTS[r];[d][r]libvmaf=n_threads=12:log_fmt=json:log_path=$3:feature=name=float_ssim" \
    -frames:v "$COUNT" -f null -
  python3 -c "import json,sys; d=json.load(open(sys.argv[1]))['pooled_metrics']; print('%.3f\t%.5f' % (d['vmaf']['mean'], d['float_ssim']['mean']))" "$3"
}

for C in "$@"; do
  NAME=$(echo "$C" | tr ':' '_')
  OUT=$W/$NAME.mp4
  KIND=${C%%:*}; REST=${C#*:}; Q=${REST%%:*}; N=1
  case "$REST" in *:*) N=${REST#*:} ;; esac
  rm -f "$OUT"
  cat "$RAW" > /dev/null
  case "$KIND" in
    x264)
      MAT=bt601
      set -- ffmpeg -v error -y -f rawvideo -pix_fmt rgb24 -s $SIZE -r 24 -i "$RAW" -frames:v "$COUNT" -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -x264-params keyint=48 -movflags +faststart "$OUT" ;;
    ffvt-h264|ffvt-hevc)
      MAT=bt709
      ENC=h264_videotoolbox; TAG=avc1
      [ "$KIND" = ffvt-hevc ] && ENC=hevc_videotoolbox && TAG=hvc1
      set -- ffmpeg -v error -y -f rawvideo -pix_fmt rgb24 -s $SIZE -r 24 -i "$RAW" -frames:v "$COUNT" -vf "scale=out_color_matrix=bt709:out_range=tv,format=nv12" -c:v $ENC -q:v "$Q" -g 48 -tag:v $TAG -colorspace bt709 -color_primaries bt709 -color_trc bt709 -movflags +faststart "$OUT" ;;
    tw-h264|tw-hevc|tw-h264r|tw-hevcr)
      MAT=bt709
      CODEC=${KIND#tw-}
      EXTRA=
      case "$CODEC" in *r) CODEC=${CODEC%r}; EXTRA=--reorder ;; esac
      QF=$(awk -v q="$Q" 'BEGIN { printf "%.2f", q / 100 }')
      set -- "$ENCODE_BENCH" "$RAW" "$OUT" --frames "$COUNT" --size $SIZE --codec "$CODEC" --quality "$QF" --input rgb24 --sessions "$N" $EXTRA ;;
    *) echo "unknown contender $C" >&2; exit 2 ;;
  esac
  /usr/bin/time -l "$@" > "$W/$NAME.out" 2> "$W/$NAME.time"
  WALL=$(awk '/ real / { print $1 }' "$W/$NAME.time")
  CPU=$(awk '/ real / { print $3 + $5 }' "$W/$NAME.time")
  RSS=$(awk '/maximum resident set size/ { printf "%.0f", $1 / 1048576 }' "$W/$NAME.time")
  FOOT=$(awk '/peak memory footprint/ { printf "%.0f", $1 / 1048576 }' "$W/$NAME.time")
  BYTES=$(stat -f %z "$OUT")
  VS=$(score "$OUT" $MAT "$W/$NAME.vmaf.json")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$C" "$COUNT" "$WALL" "$CPU" "$RSS" "$FOOT" "$BYTES" "$VS" | tee -a "$W/results.tsv"
done
