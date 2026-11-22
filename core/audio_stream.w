# core/audio_stream.w — a PCM output stream: play float samples the program
# produces (a decoder, a synthesizer), with a clock for A/V sync.
#
#   s = audio_stream_open(48000, 2)
#   n = audio_stream_write(s, pcm, 0, frames)   # interleaved f32[]; returns frames accepted
#   t = audio_stream_time(s)                    # seconds heard since open / the last flush
#   audio_stream_pause(s, true)                 # the clock freezes; false resumes
#   audio_stream_flush(s)                       # drop what is queued (seek); the clock restarts at 0
#   audio_stream_volume(s, 0.5)
#   audio_stream_info(s)                        # {queued:, underruns:, rate:, channels:, latency:, device:, rendered:}
#   audio_stream_close(s)
#
# Output only: nothing is decoded here. The bridge (runtime/media/media_avf.m,
# an AVAudioEngine source node) pulls frames from a 4-second ring that
# audio_stream_write fills without blocking: it accepts as many frames as fit
# and returns that count, so a caller keeps the rest and writes again later
# (queued frames / rate is how far ahead it is). The engine converts the
# stream's rate and channel count to the device's.
#
# audio_stream_time is the position of the frame being heard: the frames
# rendered so far, advanced by the host clock since the last buffer went out,
# minus the output latency, and never past what was actually rendered — so it
# stops on an underrun, freezes while paused, and never runs backwards.
# Without an output device a real-time null sink consumes the frames, so the
# clock runs headless too (info's device: false). macOS only; other targets
# raise at the first call. Load with `use core/audio_stream`.

# A stream of `channels` interleaved channels at `rate` Hz; an opaque handle.
-> audio_stream_open(rate, channels)
  ccall("w_media_pcm_open", rate, channels)

# Queue frames [first, first + frames) of an interleaved f32[] (or a ByteArray
# of little-endian float32); frames < 0 means to the end. Returns the number of
# frames accepted (0 when the ring is full).
-> audio_stream_write(stream, samples, first = 0, frames = -1)
  ccall("w_media_pcm_write", stream, samples, first, frames)

# Seconds of audio heard since the stream opened or was last flushed.
-> audio_stream_time(stream)
  ccall("w_media_pcm_time", stream)

# Pause (true) or resume (false) the output. Frames the device had not yet
# played when paused are played again on resume.
-> audio_stream_pause(stream, paused = true)
  ccall("w_media_pcm_pause", stream, paused)

# Drop every queued frame; audio_stream_time restarts at 0.
-> audio_stream_flush(stream)
  ccall("w_media_pcm_flush", stream)

# Linear output gain, 0 … 1.
-> audio_stream_volume(stream, v)
  ccall("w_media_pcm_volume", stream, v)

-> audio_stream_info(stream)
  a = ccall("w_media_pcm_info", stream)
  {queued: a[0], underruns: a[1], rate: a[2], channels: a[3], latency: a[4], device: a[5] == 1, rendered: a[6]}

# Stop and release the stream. Closing twice is harmless.
-> audio_stream_close(stream)
  ccall("w_media_pcm_close", stream)
