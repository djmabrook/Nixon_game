# Music

Alberto's soundtrack goes here. Nothing to wire up:

- `surf.ogg` plays everywhere that has no track of its own.
- `<room_id>.ogg` plays in that region (`hub.ogg`, `lakeside.ogg`, `checkerboard.ogg`, ...).
- `.mp3` and `.wav` work too. Tracks loop and crossfade when you change region.

It plays on the `Music` bus. Its low-pass filter opens as the little man's flow builds, so the track
starts muffled and far away and blooms when he surfs well. See `Sound.play_music()` and
`Sound.set_music_intensity()` in `audio/sound.gd`.
