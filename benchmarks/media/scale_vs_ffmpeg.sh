#!/bin/sh
# benchmarks/media/scale_vs_ffmpeg.sh — Scaler's output against ffmpeg's
# swscale on the same RGBA input.
#
#   benchmarks/media/scale_vs_ffmpeg.sh DUMP_DIR
#
# DUMP_DIR comes from scale_bench (src_<k>.rgba: 1920x1080 RGBA frames, and
# <job>_<filter>_<k>.rgba: the CPU backend's output). For the stretch jobs (share
# 1280x720, 4k 3840x2160, 480p 854x480) and both filters, ffmpeg scales
# src.rgba with -sws_flags lanczos|bicubic+accurate_rnd+full_chroma_int
# (swscale's Lanczos is radius 3; its bicubic is B=0, C=0.6, a = -0.6, ours
# a = -0.5) and the two outputs are compared frame by frame with ffmpeg's
# psnr and ssim filters (all four channels). Prints one line per job.
set -eu
D=$1
W=1920; H=1080
N=$(ls "$D" | grep -c '^src_[0-9]*\.rgba$')
cat_frames() { k=0; while [ $k -lt $N ]; do cat "$D/$1_$k.rgba"; k=$((k + 1)); done; }
cat_frames src > "$D/src.rgba"
for job in share:1280:720 4k:3840:2160 480p:854:480; do
  name=${job%%:*}; rest=${job#*:}; dw=${rest%%:*}; dh=${rest#*:}
  for f in lanczos3 bicubic; do
    [ -s "$D/${name}_${f}_0.rgba" ] || continue
    ours=$D/${name}_$f.rgba
    cat_frames ${name}_$f > "$ours"
    sws=lanczos; [ $f = bicubic ] && sws=bicubic
    ff=$D/${name}_${f}_ffmpeg.rgba
    ffmpeg -v error -y -f rawvideo -pix_fmt rgba -s ${W}x$H -i "$D/src.rgba" \
      -vf "scale=$dw:$dh" -sws_flags $sws+accurate_rnd+full_chroma_int -f rawvideo -pix_fmt rgba "$ff"
    p=$(ffmpeg -hide_banner -f rawvideo -pix_fmt rgba -s ${dw}x$dh -i "$ours" -f rawvideo -pix_fmt rgba -s ${dw}x$dh -i "$ff" \
        -lavfi "[0][1]psnr" -f null - 2>&1 | sed -n 's/.*average:\([0-9.inf]*\).*/\1/p' | tail -1)
    s=$(ffmpeg -hide_banner -f rawvideo -pix_fmt rgba -s ${dw}x$dh -i "$ours" -f rawvideo -pix_fmt rgba -s ${dw}x$dh -i "$ff" \
        -lavfi "[0][1]ssim" -f null - 2>&1 | sed -n 's/.*All:\([0-9.]*\).*/\1/p' | tail -1)
    printf '%s\t%s\t%dx%d\t%d frames\tPSNR %s dB\tSSIM %s\n' "$name" "$f" "$dw" "$dh" "$N" "$p" "$s"
    rm -f "$ff" "$ours"
  done
done
rm -f "$D/src.rgba"
