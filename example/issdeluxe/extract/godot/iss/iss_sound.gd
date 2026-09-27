class_name ISSSound
extends Node
## ISS Deluxe sound from assets/iss/sound/sound.json: the effects that use
## PCM (commentary, ball, crowd) rendered from the ROM's sound scripts, a
## commentary queue that works like speech_queue_update, and music loaded
## from captures you supply (the FM/PSG songs are not rendered by the
## extractor): res://assets/iss/music/song_NN.ogg for song NN.

const DIR := "res://assets/iss/sound/"
const MUSIC_DIR := "res://assets/iss/music/"
## speech_queue_update plays one queued line every $40 frames, 4 queued at most.
const SPEECH_GAP := 64.0 / 60.0
const SPEECH_QUEUE := 4

var _doc: Dictionary
var _voices: Array[AudioStreamPlayer] = [] # PCM voice 0 (crowd, ball) and 1 (commentary)
var _priority := [0, 0]
var _speech: Array[int] = []
var _speech_wait := 0.0
var _music := AudioStreamPlayer.new()


func _ready() -> void:
	_doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "sound.json"))
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.finished.connect(func() -> void: _priority[i] = 0)
		add_child(p)
		_voices.append(p)
	add_child(_music)


## True when effect id has a rendered file (FM/PSG-only effects need a capture).
func has_sfx(id: int) -> bool:
	return id >= 0 and id < _doc["sfx"].size() and _doc["sfx"][id].has("wav")


## Plays effect id (sound_play_sfx) on its PCM voice. Like the driver, an
## effect only replaces a playing one of higher priority.
func play_sfx(id: int) -> bool:
	if not has_sfx(id):
		return false
	var s: Dictionary = _doc["sfx"][id]
	var v: int = s["pcm"][0]["voice"]
	var p := _voices[v]
	if p.playing and int(s["priority"]) < _priority[v]:
		return false
	p.stream = load(s["wav"])
	p.play()
	_priority[v] = int(s["priority"])
	return true


func stop_sfx() -> void:
	for i in 2:
		_voices[i].stop()
		_priority[i] = 0


## Queues commentary line id (speech_queue_push).
func say(id: int) -> void:
	if _speech.size() < SPEECH_QUEUE:
		_speech.append(id)


## The event a commentary line belongs to ("goal", "corner kick", ...), or "".
func speech_context(id: int) -> String:
	return _doc["sfx"][id].get("speech", "")


func _process(delta: float) -> void:
	if _speech_wait > 0.0:
		_speech_wait -= delta
		return
	if not _speech.is_empty():
		play_sfx(_speech.pop_front())
		_speech_wait = SPEECH_GAP


## Plays a captured song (sound_play_music d0 = id); false if none is supplied.
func play_music(id: int) -> bool:
	var path := MUSIC_DIR + "song_%02d.ogg" % id
	if not ResourceLoader.exists(path):
		return false
	_music.stream = load(path)
	_music.play()
	return true


func stop_music() -> void:
	_music.stop()
