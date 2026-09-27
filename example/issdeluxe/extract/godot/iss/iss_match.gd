class_name ISSMatch
extends Node2D
## A match on screen: the stadium, both teams, the ball, the officials, the
## weather, the HUD and the sound, driven by ISSMatchEngine at 60 frames per
## second. Put it in a 256 x 224 viewport (ISSGame does). Emits match_over
## with the result once the final whistle's banner has been shown.

signal match_over(result: Dictionary)

const SCREEN := Vector2(256, 224)

var engine := ISSMatchEngine.new()
var options := {}
var paused := false

var _pitch := ISSPitch.new()
var _weather := ISSWeather.new()
var _flags := ISSFlags.new()
var _hud := ISSHud.new()
var _camera := Camera2D.new()
var _sound := ISSSound.new()
var _ball := ISSBallSprite.new()
var _marker := Sprite2D.new()
var _referee := ISSNPCSprite.new()
var _linesman := ISSNPCSprite.new()
var _cursor := Cursor.new()
var _pause := PauseText.new()
var _sprites := {}
var _cam := Vector2.ZERO
var _lead := Vector2.ZERO
var _cam_z := 0.0
var _end_wait := -1


## "PAUSE" in the middle of the screen while the game is paused.
class PauseText:
	extends Node2D
	var on := false

	func _draw() -> void:
		if on:
			ISSText.draw_centred(self, "PAUSE", 128, 104, true, true)


## Arrow over the controlled players (home / away colours).
class Cursor:
	extends Node2D
	var points: Array = [] # [map position, colour]

	func _draw() -> void:
		for p in points:
			var at: Vector2 = p[0]
			draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -4), at + Vector2(3, -4), at]), p[1])


func start(home: int, away: int, opts: Dictionary) -> void:
	options = opts
	ISSMatchData.ensure_loaded()
	ISSInput.ensure_actions()
	engine.setup(home, away, opts)
	add_child(_sound)
	_pitch.stadium = engine.stadium
	_pitch.weather = engine.weather
	_pitch.z_index = -4096
	add_child(_pitch)
	_flags.stadium = engine.stadium
	add_child(_flags)
	_weather.stadium = engine.stadium
	_weather.weather = engine.weather
	_weather.area = _pitch.pixel_size()
	_weather.z_index = 4000
	add_child(_weather)
	for t in engine.teams:
		for p in t.players:
			var s := ISSPlayerSprite.new()
			s.team = t.team_id
			s.second_kit = t.second_kit
			add_child(s)
			_sprites[p] = s
	add_child(_ball)
	_marker.texture = load("res://assets/iss/misc/landing_marker.png")
	_marker.visible = false
	_marker.z_index = -100
	add_child(_marker)
	_referee.kit = engine.referee_kit
	add_child(_referee)
	_referee.set_kit(engine.referee_kit)
	add_child(_linesman)
	_linesman.set_kit(engine.referee_kit)
	_cursor.z_index = 4001
	add_child(_cursor)
	var size := Vector2(_pitch.pixel_size())
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(size.x)
	_camera.limit_bottom = int(size.y)
	_camera.offset = Vector2(0, 8)
	add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 10
	_hud.home_team = engine.teams[0].team_id
	_hud.away_team = engine.teams[1].team_id
	layer.add_child(_hud)
	layer.add_child(_pause)
	add_child(layer)
	_hud.set_stadium(engine.stadium)
	_hud.set_teams(engine.teams[0].team_id, engine.teams[1].team_id)
	engine.sound.connect(_sound.play_sfx)
	engine.speech.connect(_sound.say)
	engine.banner.connect(_hud.show_banner)
	engine.banner_off.connect(_hud.hide_banner)
	engine.finished.connect(func() -> void: _end_wait = 180)
	_sound.play_sfx(0x63) # crowd
	_cam = engine.ball.pos
	_sync()


func _physics_process(_delta: float) -> void:
	if engine.teams.is_empty():
		return
	for i in 2:
		if ISSInput.start_pressed(i) and int(engine.options.get("pads", [1, 0])[i]) > 0:
			paused = not paused
			_pause.on = paused
			_pause.queue_redraw()
	if paused:
		return
	if _end_wait >= 0:
		_end_wait -= 1
		if _end_wait == 0:
			match_over.emit(result())
		_sync()
		return
	var pads: Array = [null, null]
	var p: Array = engine.options.get("pads", [1, 0])
	var next := 0
	for side in 2:
		if int(p[side]) > 0:
			pads[side] = ISSInput.read(next)
			next += 1
	engine.step(pads)
	_sync()


func _exit_tree() -> void:
	engine.dispose()


func result() -> Dictionary:
	return {"home": engine.teams[0].team_id, "away": engine.teams[1].team_id,
		"home_score": engine.teams[0].score, "away_score": engine.teams[1].score,
		"scorers": engine.scorers, "home_stats": engine.teams[0].stats, "away_stats": engine.teams[1].stats}


# ---------------------------------------------------------------------------
# Drawing the engine's state.

const LOOPING := [0, 1, 2, 6, 7, 9, 27, 30, 31, 32, 33, 34, 38, 50, 53]


func _sync() -> void:
	var e := engine
	var dots: Array = []
	var cursors: Array = []
	for t in e.teams:
		for p in t.players:
			var s: ISSPlayerSprite = _sprites[p]
			s.visible = p.state != ISSFootballer.S.SENT_OFF
			if not s.visible:
				continue
			s.set_pose(p.action, p.anim_frame, p.facing, p.action in LOOPING)
			s.position = ISSProjection.to_map(p.pos, p.z).round()
			s.z_index = int(p.pos.y)
			dots.append([p.pos, ("controlled_" if p == t.controlled and t.pads > 0 else "") + ("home" if t.side == 0 else "away")])
			if p == t.controlled and t.pads > 0:
				var colour := Color(1, 1, 0.3) if t.side == 0 else Color(0.4, 1, 1)
				cursors.append([s.position + Vector2(0, -42), colour])
	var b := e.ball
	_ball.position = ISSProjection.to_map(b.pos).round()
	_ball.height = b.z
	_ball.facing = roundi(b.heading) & 63
	_ball.spin = b.spin
	_ball.z_index = int(b.pos.y) + 1
	_ball.visible = true
	dots.append([b.pos, "ball"])
	# Landing marker for balls in the air (landing_marker_start).
	if b.is_loose() and b.z > 20.0 and b.live:
		_marker.visible = true
		_marker.position = ISSProjection.to_map(b.landing()[0]).round()
	else:
		_marker.visible = false
	_referee.position = ISSProjection.to_map(e.referee_pos).round()
	_referee.z_index = int(e.referee_pos.y)
	_referee.facing = int(ISSFootballer.heading_to(e.referee_pos, b.pos)) & 63
	_referee.play(2 if (e.referee_pos - b.pos).length() > 90.0 else 1)
	_linesman.position = ISSProjection.to_map(e.linesman_pos).round()
	_linesman.z_index = int(e.linesman_pos.y)
	_linesman.facing = 16 if b.pos.x > e.linesman_pos.x else 48
	_linesman.play(6 if absf(b.pos.x - e.linesman_pos.x) > 8.0 else 5)
	_cursor.points = cursors
	_cursor.queue_redraw()
	_hud.home_score = e.teams[0].score
	_hud.away_score = e.teams[1].score
	_hud.clock_seconds = e.clock_seconds()
	_hud.second_half = e.half > 0
	_hud.set_radar(dots)
	_update_camera()


## camera_update: follow the ball (or whoever has it) with a lead that eases
## 1/32 per frame toward 32 px ahead in the direction the focus's team attacks.
func _update_camera() -> void:
	var e := engine
	var focus := e.ball.pos
	var team := e.ball.team if e.ball.team >= 0 else 0
	var want := Vector2(32.0 * e.attack_dir(team), 0.0)
	_lead += (want - _lead) / 32.0
	var target := focus + _lead
	var r := e.rect
	target.x = clampf(target.x, r.position.x - 32.0, r.end.x + 32.0)
	_cam += (target - _cam) / 4.0
	_cam_z += (e.ball.z * 0.25 - _cam_z) / 8.0
	_camera.position = ISSProjection.to_map(_cam, _cam_z).round()
