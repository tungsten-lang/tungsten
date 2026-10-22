#!/bin/zsh
# VMAF of the span benchmark's segments (VideoToolbox HEVC vs the libx264 adapter) against the engine's own
# pre-encode frames (studio raw), both scored in BT.709 limited-range 4:2:0.
#   vmaf_span.sh <episode.json> <from> <nframes> <log>      (run under the heavy lock)
E=$1; A=$2; N=$3; LOG=$4
D=$(cd "$(dirname $E)" && pwd)
S=${STUDIO_BIN:-$HOME/tungsten-worktrees/engine/apps/studio/bin/studio}
B=$(python3 -c "
import json; R=json.load(open('$D/build/full/timeline.resolved.json'))
segs=[s for s in R['segments'] if s['f0']>=$A]; a=segs[0]['f0']; b=a
for s in segs:
    if b-a>=$N: break
    b=s['f0']+s['n']
print(a,b)")
A=${B% *}; Z=${B#* }
T=$D/build/tmp/vmaf; mkdir -p $T
: > $LOG
echo "span $A..$Z ($((Z - A)) frames)" >> $LOG
STUDIO_SEGMENTS=$D/build/bench_segments_videotoolbox_j6 $S mux $E --from $A --to $Z --no-audio --out $T/vt.mp4 >> $LOG 2>&1
STUDIO_SEGMENTS=$D/build/bench_segments_ffmpeg_j6 STUDIO_ENCODER=ffmpeg $S mux $E --from $A --to $Z --no-audio --out $T/ff.mp4 >> $LOG 2>&1
$S raw $E $A $Z $T/ref.rgb >> $LOG 2>&1
for enc in vt ff; do
  ffmpeg -nostdin -v error -f rawvideo -pix_fmt rgb24 -s 1920x1080 -r 24 -i $T/ref.rgb -i $T/$enc.mp4 -lavfi \
    "[0:v]scale=out_color_matrix=bt709:out_range=tv:out_h_chr_pos=0:out_v_chr_pos=128:flags=bicubic+accurate_rnd+full_chroma_int,format=yuv420p[ref];[1:v]format=yuv420p[dist];[dist][ref]libvmaf=n_threads=8:log_fmt=json:log_path=$T/$enc.json" \
    -f null - >> $LOG 2>&1
  python3 -c "import json; d=json.load(open('$T/$enc.json')); p=d['pooled_metrics']['vmaf']; print('$enc VMAF mean', round(p['mean'],2), 'min', round(p['min'],2), 'harmonic', round(p['harmonic_mean'],2))" >> $LOG
  ls -l $T/$enc.mp4 | awk '{print "'$enc' bytes " $5}' >> $LOG
done
rm -f $T/ref.rgb
echo DONE >> $LOG
