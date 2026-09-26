extends Node2D
## Demo of the exported ISS Deluxe assets: a stadium and players running in
## all directions with alternating kits. Arrow keys scroll, +/- change the
## stadium, T changes the time of day.

const SPEED := 60.0

var _pitch := ISSPitch.new()
var _camera := Camera2D.new()
var _players: Array[ISSPlayerSprite] = []
var _pitch_pos: Array[Vector2] = []


func _ready() -> void:
	add_child(_pitch)
	var size := _pitch.pixel_size()
	_camera.position = Vector2(size) / 2.0
	_camera.zoom = Vector2(3, 3)
	add_child(_camera)
	for i in 16:
		var p := ISSPlayerSprite.new()
		p.facing = (i * 4) & 63
		p.team = (i / 2) % 43
		p.second_kit = i % 2 == 1
		p.action = 1 + i % 3
		add_child(p)
		_players.append(p)
		_pitch_pos.append(Vector2(700 + (i % 4) * 80, 400 + (i / 4) * 60))


func _process(delta: float) -> void:
	for i in _players.size():
		var angle := _players[i].facing / 64.0 * TAU
		_pitch_pos[i] += Vector2(cos(angle), sin(angle)) * SPEED * delta
		_players[i].position = ISSProjection.to_map(_pitch_pos[i])
		_players[i].z_index = int(_pitch_pos[i].y)
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_camera.position += move * 300.0 * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_pitch.stadium = (_pitch.stadium + 1) % 8
			KEY_MINUS, KEY_KP_SUBTRACT:
				_pitch.stadium = (_pitch.stadium + 7) % 8
			KEY_T:
				_pitch.time_of_day = (_pitch.time_of_day + 1) % 3
