class_name ISSFrontEnd
extends Node2D
## The front end on the game's own screens (assets/iss/screens) and fonts:
## the main menu (screen 0), team and stadium selection, the options
## (screen $11: game level, game time, sound) and rules (screen $12: foul,
## yellow card, offside, the referee), and the result after a match.
## Menus are driven by player 1's pad: d-pad moves, pass (Z) confirms,
## shoot (X) goes back.

signal start_match(home: int, away: int, options: Dictionary)

enum Page { MAIN, TEAMS, OPTIONS, RULES, RESULT }

const SCREENS := "res://assets/iss/screens/"
const MODES := ["1P VS COM", "1P VS 2P", "COM VS COM", "OPTIONS", "RULES", "PK"]
const PADS := [[1, 0], [1, 1], [0, 0], [], [], [1, 0]]
const WEATHERS := ["SNOW", "FINE", "RAIN"]
const REFEREES := ["CARLOS", "HEINZ", "HASEGAWA", "RANDOM"]

## Settings kept between matches (g_settings), with the game's defaults.
static var settings := {"level": 2, "time": 2, "mono": 0, "fouls": true, "cards": true,
	"offside": true, "vgoal": 1, "referee": 1}
static var home := 0
static var away := 2
static var stadium := 0
static var weather := 1
static var mode := 0
static var home_formation := -1
static var away_formation := -1

var page := Page.MAIN
var cursor := 0
var result := {}
var _backdrop := Sprite2D.new()
var _flags: Array[Sprite2D] = []
var _blink := 0
var _sound := ISSSound.new()


func _ready() -> void:
	ISSMatchData.ensure_loaded()
	ISSInput.ensure_actions()
	_backdrop.centered = false
	_backdrop.z_index = -10
	add_child(_backdrop)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	mat.set_shader_parameter("palette", load("res://assets/iss/hud/hud.pal.png"))
	for i in 2:
		var f := Sprite2D.new()
		f.centered = false
		f.material = mat
		f.visible = false
		add_child(f)
		_flags.append(f)
	add_child(_sound)
	# Song 3 is the main menu's (screen_main_menu), 16 the final whistle's.
	_sound.play_music(16 if not result.is_empty() else 3)
	show_page(Page.RESULT if not result.is_empty() else Page.MAIN)


func show_page(p: int) -> void:
	page = p
	cursor = 0
	var screen: String = {Page.MAIN: "00", Page.TEAMS: "33", Page.OPTIONS: "11", Page.RULES: "12", Page.RESULT: "33"}[p]
	_backdrop.texture = load(SCREENS + "screen_%s.png" % screen)
	queue_redraw()


func _physics_process(_delta: float) -> void:
	_blink += 1
	var pad := ISSInput.read(0)
	var dir: int = pad["dir"]
	var moved := Vector2i.ZERO
	if dir < 0:
		_held_frames = 0
	elif _repeat_ok():
		var v := ISSProjection.heading_vector(dir)
		moved = Vector2i(roundi(v.x), roundi(v.y))
	var ok: bool = pad["press"] & (ISSFootballer.PASS | ISSFootballer.LOFT) or ISSInput.start_pressed(0)
	var back: bool = pad["press"] & ISSFootballer.SHOOT
	match page:
		Page.MAIN:
			_main(moved, ok)
		Page.TEAMS:
			_teams(moved, ok, back)
		Page.OPTIONS:
			_options(moved, ok, back)
		Page.RULES:
			_rules(moved, ok, back)
		Page.RESULT:
			if ok or back:
				_sound.play_music(3)
				show_page(Page.MAIN)
	if moved != Vector2i.ZERO or ok or back:
		_sound.play_sfx(0x5E)
	queue_redraw()


var _held_frames := 0


## Auto-repeat for the d-pad: once on press, then every 8 frames after 20.
func _repeat_ok() -> bool:
	_held_frames += 1
	if _held_frames == 1:
		return true
	return _held_frames > 20 and _held_frames % 8 == 0


func _main(moved: Vector2i, ok: bool) -> void:
	cursor = clampi(cursor + moved.y * 2 + moved.x, 0, MODES.size() - 1)
	if ok:
		match cursor:
			0, 1, 2, 5:
				mode = cursor
				show_page(Page.TEAMS)
			3:
				show_page(Page.OPTIONS)
			4:
				show_page(Page.RULES)


func _teams(moved: Vector2i, ok: bool, back: bool) -> void:
	var n := ISSMatchData.team_count() - 1 # the practice team stays out
	cursor = clampi(cursor + moved.y, 0, 6)
	match cursor:
		0:
			home = posmod(home + moved.x, n)
			home_formation = -1
		1:
			home_formation = posmod(_formation(home, home_formation) + moved.x, 16) if moved.x != 0 else home_formation
		2:
			away = posmod(away + moved.x, n)
			away_formation = -1
		3:
			away_formation = posmod(_formation(away, away_formation) + moved.x, 16) if moved.x != 0 else away_formation
		4:
			stadium = posmod(stadium + moved.x, 8)
		5:
			weather = posmod(weather + moved.x, 3)
	if back:
		show_page(Page.MAIN)
	elif ok and cursor == 6:
		var opts := settings.duplicate()
		opts["stadium"] = stadium
		opts["weather"] = weather
		opts["pads"] = PADS[mode]
		opts["formations"] = [home_formation, away_formation]
		# Open games are knockout matches ($1274 = 1): extra time, then penalties.
		opts["knockout"] = true
		opts["pk_only"] = mode == 5
		start_match.emit(home, away, opts)


## The team's own formation (tbl_team_formations) unless one was picked.
static func _formation(team: int, picked: int) -> int:
	return picked if picked >= 0 else int(ISSMatchData.teams[team]["formation"])


func _options(moved: Vector2i, ok: bool, back: bool) -> void:
	cursor = clampi(cursor + moved.y, 0, 3)
	match cursor:
		0:
			settings["level"] = clampi(int(settings["level"]) + moved.x, 0, 4)
		1:
			settings["time"] = clampi(int(settings["time"]) + moved.x, 1, 3)
		2:
			settings["mono"] = clampi(int(settings["mono"]) + moved.x, 0, 1)
	if back or (ok and cursor != 3):
		show_page(Page.MAIN)
	elif ok:
		show_page(Page.RULES)


func _rules(moved: Vector2i, ok: bool, back: bool) -> void:
	cursor = clampi(cursor + moved.y, 0, 4)
	var keys := ["fouls", "cards", "offside"]
	if cursor < 3 and moved.x != 0:
		settings[keys[cursor]] = moved.x < 0
	elif cursor == 3 and moved.x != 0:
		settings["vgoal"] = 1 if moved.x < 0 else 0
	elif cursor == 4:
		settings["referee"] = posmod(int(settings["referee"]) + moved.x, 4)
	if ok or back:
		show_page(Page.MAIN)


# ---------------------------------------------------------------------------

func _box(r: Rect2, on: bool) -> void:
	var c := Color(1, 1, 0.2) if on and (_blink / 8) % 2 == 0 else Color(1, 1, 1, 0.7)
	draw_rect(r.grow(1), c, false, 1.0)


func _draw() -> void:
	for f in _flags:
		f.visible = false
	match page:
		Page.MAIN:
			for i in MODES.size():
				var cx := 64.0 if i % 2 == 0 else 192.0
				var cy := 40.0 + 48.0 * float(i / 2)
				var r := Rect2(cx - 57, cy - 18, 114, 36)
				draw_rect(r, Color(0, 0, 0.3, 0.75))
				ISSText.draw_centred(self, MODES[i], cx, cy - 8, true, i == cursor)
				if i == cursor:
					_box(r, true)
			ISSText.draw_centred(self, "SUPERSTAR SOCCER DELUXE", 128, 210, false)
		Page.TEAMS:
			ISSText.draw_centred(self, "-TODAYS GAME-", 128, 8, true)
			_team_row(0, home, 30)
			_formation_row(home, home_formation, 50, cursor == 1)
			ISSText.draw_centred(self, "VS", 128, 64, false)
			_team_row(1, away, 78)
			_formation_row(away, away_formation, 98, cursor == 3)
			ISSText.draw(self, "STADIUM %d" % (stadium + 1), Vector2(40, 120), true, cursor == 4)
			ISSText.draw(self, "WEATHER " + WEATHERS[weather], Vector2(40, 140), true, cursor == 5)
			ISSText.draw_centred(self, "GAME START", 128, 168, true, cursor == 6)
			ISSText.draw_centred(self, MODES[mode], 128, 200, false)
		Page.OPTIONS:
			var level := int(settings["level"])
			_box(Rect2(120 + 24 * level, 40, 8, 16), cursor == 0)
			var t := int(settings["time"])
			_box(Rect2(120 + 48 * (t - 1), 64, 8, 16), cursor == 1)
			var mono := int(settings["mono"])
			_box(Rect2(120, 88, 48, 16) if mono == 0 else Rect2(192, 88, 32, 16), cursor == 2)
			if cursor == 3:
				_box(Rect2(24, 112, 40, 16), true)
		Page.RULES:
			for i in 3:
				var on: bool = settings[["fouls", "cards", "offside"][i]]
				_box(Rect2(144, 40 + 24 * i, 16, 16) if on else Rect2(168, 40 + 24 * i, 24, 16), cursor == i)
			var vgoal := int(settings["vgoal"]) == 1
			_box(Rect2(112, 112, 48, 16) if vgoal else Rect2(168, 112, 64, 16), cursor == 3)
			var ref := int(settings["referee"])
			_box(Rect2(20 + 56 * ref, 150, 48, 64), cursor == 4)
		Page.RESULT:
			ISSText.draw_centred(self, "FULL TIME", 128, 24, true)
			var hs := int(result.get("home_score", 0))
			var as_ := int(result.get("away_score", 0))
			var hn := ISSMatchData.team_name(int(result.get("home", 0))).to_upper()
			var an := ISSMatchData.team_name(int(result.get("away", 0))).to_upper()
			ISSText.draw_centred(self, "%s %d - %d %s" % [hn, hs, as_, an], 128, 56, true)
			var y := 88
			for s: Dictionary in result.get("scorers", []):
				if y > 184:
					break
				var who := "%s %s%s" % [str(s["minute"] + 1) + "'", s["name"], " (OG)" if s["own_goal"] else ""]
				ISSText.draw(self, who, Vector2(24 if int(s["side"]) == 0 else 136, y), false)
				y += 12
			var pk: Array = result.get("penalties", [])
			if not pk.is_empty():
				ISSText.draw_centred(self, "PK %d - %d" % [pk[0], pk[1]], 128, 74, false)
				hs = int(pk[0])
				as_ = int(pk[1])
			var winner := "MATCH DRAWN" if hs == as_ else (hn if hs > as_ else an) + " WINS"
			ISSText.draw_centred(self, winner, 128, 196, true, true)


func _team_row(i: int, team: int, y: float) -> void:
	var f := _flags[i]
	if team < 42:
		f.texture = load("res://assets/iss/hud/flags/flag_%02d.png" % team)
		f.position = Vector2(40, y)
		f.visible = true
	var name := ISSMatchData.team_name(team).to_upper()
	ISSText.draw(self, name, Vector2(80, y), true, cursor == i * 2)
	ISSText.draw(self, "HOME" if i == 0 else "AWAY", Vector2(208, y + 4), false)


func _formation_row(team: int, picked: int, y: float, on: bool) -> void:
	var fid := _formation(team, picked)
	ISSText.draw(self, "FORMATION " + str(ISSMatchData.formations[fid]["name"]), Vector2(80, y), false, on)
