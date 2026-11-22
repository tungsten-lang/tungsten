# USAC / xHE-AAC (core/codec/audio/usac) through LOAS framing
# (core/codec/audio/latm): 24 frames of an ISO/IEC 23003-3 FD conformance
# stream (Fd_2_c1_Ms_0x01: stereo, 88.2 kHz, M/S), re-muxed as LOAS. The
# decoder matches the ISO reference output within 0.03 LSB on the full
# stream (benchmarks/codec/usac_test.w); here the f32 output is pinned by
# its FNV-1a hash.
#
# spec: compiled -- the codec files call functions at load time before defining them (hoisting is compiled-only)
#
#   bin/tungsten spec/core/codec/usac_spec.w

use core/codec/container/all
use core/codec/audio/all
use core/codec/video/yuv
use media_support

b = codec_fixture("usac_fd_stereo.loas")
check("loas sniff", demux_sniff(b), :loas)
r = demux_all(b)
t = r[0].tracks[0]
check("codec", t.cfg.codec, "mp4a")
check("rate", t.cfg.sample_rate, 88200)
check("channels", t.cfg.channels, 2)
dec = Codec.audio(t.cfg)
check("usac decoder", dec.class.to_s, "UsacDec")
check("frame", dec.out_frame, 1024)
got = decode_audio(t.cfg, r[1][t.id])
check("decode", got, "frames=24576 fnv=703766377")
codec_done
