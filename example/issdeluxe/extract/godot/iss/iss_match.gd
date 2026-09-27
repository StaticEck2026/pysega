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


## The pause menu (continue, substitutions) and the penalty tally during a
## shoot-out.
class PauseText:
	extends Node2D
	var on := false
	var pk := ""
	## 0 menu, 1 player coming off, 2 player coming on.
	var menu := 0
	var cursor := 0
	var team: ISSTeam = null

	func items() -> Array:
		match menu:
			1:
				var out := []
				for p in team.players:
					out.append("%2d %-10s %2d" % [p.number, p.name.to_upper().left(10), p.energy])
				return out
			2:
				var out := []
				for rec: Dictionary in team.bench:
					out.append("%2d %-10s %s" % [int(rec["number"]), str(rec["name"]).to_upper().left(10), rec["position"].left(3).to_upper()])
				return out
		return ["CONTINUE", "SUBSTITUTE %d" % team.subs_left]

	func _draw() -> void:
		if pk != "":
			ISSText.draw_centred(self, pk, 128, 36, false, true)
		if not on:
			return
		var list := items()
		var h := 20 + list.size() * 10
		var top := maxf(34.0, 112.0 - h / 2.0)
		draw_rect(Rect2(16, top, 224, h), Color(0, 0, 0.25, 0.85))
		ISSText.draw_centred(self, ["PAUSE", "SUBSTITUTE WHO    ENERGY", "BRING ON"][menu], 128, top + 4, false, true)
		for i in list.size():
			ISSText.draw(self, list[i], Vector2(24, top + 16 + i * 10), false, i == cursor)


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
	var sides := _human_sides()
	for i in sides.size():
		if ISSInput.start_pressed(i):
			paused = not paused
			_pause.on = paused
			_pause.menu = 0
			_pause.cursor = 0
			_pause_pad = i
			_pause.team = engine.teams[sides[i]]
			_pause.queue_redraw()
	if paused:
		_pause_menu(ISSInput.read(_pause_pad))
		return
	if _end_wait >= 0:
		_end_wait -= 1
		if _end_wait == 0:
			match_over.emit(result())
		_sync()
		return
	var pads: Array = [null, null]
	for i in sides.size():
		pads[sides[i]] = ISSInput.read(i)
	engine.step(pads)
	_sync()


var _pause_pad := 0
var _menu_hold := 0


## Pad n (in order) plays for side _human_sides()[n].
func _human_sides() -> Array:
	var out := []
	var p: Array = engine.options.get("pads", [1, 0])
	for side in 2:
		if int(p[side]) > 0:
			out.append(side)
	return out


func _pause_menu(pad: Dictionary) -> void:
	var dir: int = pad["dir"]
	var step := 0
	if dir < 0:
		_menu_hold = 0
	else:
		_menu_hold += 1
		if _menu_hold == 1 or (_menu_hold > 20 and _menu_hold % 6 == 0):
			var v := ISSProjection.heading_vector(dir)
			step = roundi(v.y)
	var ok: bool = pad["press"] & (ISSFootballer.PASS | ISSFootballer.LOFT)
	var back: bool = pad["press"] & ISSFootballer.SHOOT
	var n := _pause.items().size()
	_pause.cursor = clampi(_pause.cursor + step, 0, maxi(0, n - 1))
	var t := _pause.team
	match _pause.menu:
		0:
			if ok and _pause.cursor == 0:
				paused = false
				_pause.on = false
			elif ok and t.subs_left > 0 and not t.bench.is_empty():
				_pause.menu = 1
				_pause.cursor = 1
		1:
			if back:
				_pause.menu = 0
				_pause.cursor = 1
			elif ok:
				_sub_out = _pause.cursor
				_pause.menu = 2
				_pause.cursor = 0
		2:
			if back:
				_pause.menu = 1
				_pause.cursor = _sub_out
			elif ok:
				if t.substitute(_sub_out, _pause.cursor):
					_sound.play_sfx(0x48) # whistle
				_pause.menu = 0
				_pause.cursor = 0
	if step != 0 or ok or back:
		_pause.queue_redraw()


var _sub_out := -1


func _exit_tree() -> void:
	engine.dispose()


func result() -> Dictionary:
	var r := _result_core()
	if options.has("scenario_index"):
		r["scenario"] = int(options["scenario_index"])
	return r


func _result_core() -> Dictionary:
	return {"home": engine.teams[0].team_id, "away": engine.teams[1].team_id,
		"home_score": engine.teams[0].score, "away_score": engine.teams[1].score,
		"penalties": engine.pk_scores if engine.shootout else [],
		"comp": bool(options.get("comp", false)),
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
	_hud.home_strategy = e.teams[0].strategy
	_hud.away_strategy = e.teams[1].strategy
	_hud.set_radar(dots)
	var pk := "PK %d-%d" % [e.pk_scores[0], e.pk_scores[1]] if e.shootout else ""
	if pk != _pause.pk:
		_pause.pk = pk
		_pause.queue_redraw()
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
