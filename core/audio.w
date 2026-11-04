# core/audio.w — a minimal audio player: play a sound file (WAV, AIFF, CAF,
# M4A, MP3 …) from a time, pause, stop, read the current time, set the volume.
#
#   p = audio_open("mix.wav")
#   audio_volume(p, 0.8)
#   audio_play(p, 12.5)          # from 12.5 s (audio_play(p, -1) resumes)
#   t = audio_time(p)            # seconds into the file: the output's clock
#   audio_pause(p)
#   audio_stop(p)                # stop and rewind
#   audio_close(p)
#
# A thin facade over AVAudioPlayer in the media bridge (runtime/media/
# media_avf.m, linked when a program references a w_media_ symbol). Playback
# runs on the player's own threads, so a program needs no run loop and can
# keep drawing: a playhead follows audio_time (the time of the sample being
# heard, as the player reports it), not a wall clock. macOS only; other
# targets raise at the first call. Load with `use core/audio`.

# Open a sound file; an opaque handle. Raises when the file cannot be read.
-> audio_open(path)
  ccall("w_media_audio_open", path)

# Play from `t` seconds (t < 0: from where it is, after a pause). True when
# playback started.
-> audio_play(player, t)
  ccall("w_media_audio_play", player, t)

-> audio_pause(player)
  ccall("w_media_audio_pause", player)

# Stop and rewind to the start.
-> audio_stop(player)
  ccall("w_media_audio_stop", player)

# The current position in seconds.
-> audio_time(player)
  ccall("w_media_audio_time", player)

# Output volume, 0 … 1 (a linear gain).
-> audio_volume(player, v)
  ccall("w_media_audio_volume", player, v)

# {duration: seconds, playing: true/false, rate: sample rate, channels:}
-> audio_info(player)
  a = ccall("w_media_audio_info", player)
  {duration: a[0], playing: a[1] == 1, rate: a[2], channels: a[3]}

# Release the player (stops it). Closing twice is harmless.
-> audio_close(player)
  ccall("w_media_audio_close", player)
