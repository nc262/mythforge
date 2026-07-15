extends Node
## Sfx — the game's small sounds: dice clatter, hit thud, combat sting,
## reward chime. Synthesized assets (scripts/make_sfx.py), played politely.

var _players := {}


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


func play(n: String) -> void:
	if _players.has(n):
		_players[n].play()
