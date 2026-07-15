extends Node
## Sfx — sounds and the ambient score. Effects are one-shots; music is a
## pair of looping pad players that crossfade between world moods and the
## combat drone. All synthesized (scripts/make_sfx.py) — no licenses, no
## downloads.

var enabled := true
var ambient_enabled := true
var ambient_volume := 0.6

var _players := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _front_is_a := true
var _current_track := ""


func _ready() -> void:
	for n in ["dice", "hit", "sting", "chime"]:
		var stream = load("res://assets/sfx/%s.wav" % n)
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = -8.0
		add_child(p)
		_players[n] = p
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for mp in [_music_a, _music_b]:
		mp.volume_db = -80.0
		add_child(mp)


func play(n: String) -> void:
	if enabled and _players.has(n):
		_players[n].play()


func _vol_db() -> float:
	return linear_to_db(clampf(ambient_volume, 0.05, 1.0)) - 10.0


## Crossfade the score to a mood: "embervale" | "neonspire" | "everyday" |
## "arcane" | "combat" | "" (silence).
func music(track: String) -> void:
	if not ambient_enabled:
		track = ""
	if track == _current_track:
		return
	_current_track = track
	var front := _music_a if _front_is_a else _music_b
	var back := _music_b if _front_is_a else _music_a
	_front_is_a = not _front_is_a
	var tw := create_tween()
	tw.tween_property(front, "volume_db", -80.0, 1.6)
	if track == "":
		return
	var stream = load("res://assets/sfx/amb_%s.wav" % track)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = stream.data.size() / 2  # 16-bit mono: bytes → frames
	back.stream = stream
	back.volume_db = -80.0
	back.play()
	var tw2 := create_tween()
	tw2.tween_property(back, "volume_db", _vol_db(), 1.6)


func set_ambient(on: bool, volume: float) -> void:
	ambient_enabled = on
	ambient_volume = volume
	var front := _music_a if _front_is_a else _music_b
	if not on:
		front.stop()
		_current_track = ""
	else:
		front.volume_db = _vol_db()
