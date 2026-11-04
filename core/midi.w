# core/midi.w — MIDI in and out through CoreMIDI (macOS).
#
#   midi_destinations()          # ["IAC Driver Bus 1", "Arranger In", …]: where an output can go
#   o = midi_out(0)              # to destination 0; midi_out(-1, "Arranger") a virtual source others can listen to
#   midi_send(o, 0x90, 60, 100)  # note on (channel 1), then midi_send(o, 0x80, 60, 0)
#   i = midi_in(-1, "Arranger In")   # a virtual destination others can send to; midi_in(k) from source k
#   midi_read(i)                 # [[status, data1, data2, seconds], …] received since the last read
#   midi_close(o)
#
# The media bridge's CoreMIDI half (runtime/media/media_avf.m; CoreMIDI is loaded at the first call). Messages are channel
# messages (note on/off, control and program changes, pitch bend …); system and running-status bytes are skipped on input.
# Times are seconds of the system's uptime clock. Load with `use core/midi`.

-> midi_destinations()
  ccall("w_media_midi_destinations")

-> midi_sources()
  ccall("w_media_midi_sources")

-> midi_out(index, name = "")
  ccall("w_media_midi_out_open", index, name)

-> midi_send(out, status, data1 = -1, data2 = -1)
  ccall("w_media_midi_send", out, status, data1, data2)

# a message scheduled for a host time (seconds, midi_now's clock; 0 now): delivered then by CoreMIDI
-> midi_send_at(out, at, message)
  ccall("w_media_midi_send_at", out, at, message)

# drop what is scheduled on an output and not yet delivered
-> midi_flush(out)
  ccall("w_media_midi_flush", out)

# the host clock (seconds): input timestamps, midi_send_at and live_play's times
-> midi_now()
  ccall("w_media_midi_now")

-> midi_in(index, name = "")
  ccall("w_media_midi_in_open", index, name)

-> midi_read(input)
  ccall("w_media_midi_read", input)

-> midi_close(port)
  ccall("w_media_midi_close", port)
