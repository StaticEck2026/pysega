class_name ISSFrontEnd
extends Node2D
## The front end on the game's own screens (assets/iss/screens) and fonts,
## laid out like the original: the main menu (screen 0: match, International
## Cup, World Series, password, scenario, PK, training, options), the match
## type (screen 1: open game, short league, short tournament), player select
## (screen 2), team selection, the strategy screen ($0A), options ($11) and
## rules ($12), scenario select ($24), training select ($18), the
## competition tables and the result.
## The port saves competitions instead of showing passwords: "CONTINUE"
## picks a saved one up. Menus are driven by player 1's pad: the d-pad
## moves, pass (Z) or Start confirms, shoot (X) goes back.

signal start_match(home: int, away: int, options: Dictionary)

enum Page { MAIN, MATCH_TYPE, PLAYERS, TEAMS, PICK_TEAM, OPTIONS, RULES, STRATEGY, RESULT,
	COMP_SETUP, COMP_TABLE, SCENARIO, MESSAGE, TRAINING }

const SCREENS := "res://assets/iss/screens/"
const MAIN_ITEMS := ["MATCH", "INTERNATIONAL CUP", "WORLD SERIES", "CONTINUE", "SCENARIO", "PK",
	"TRAINING", "OPTIONS"]
const PLAYER_MODES := ["1P VS COM", "1P VS 2P", "COM VS COM"]
const PADS := [[1, 0], [1, 1], [0, 0]]
const WEATHERS := ["SNOW", "FINE", "RAIN"]
const STRATEGY_NAMES := ["ALL OUT ATTACK", "PUSH ALONG CENTRE", "PUSH ALONG WINGS", "COUNTER ATTACK",
	"ALL OUT DEFENCE", "PRESS UP", "ZONE PRESS", "OFFSIDE TRAP"]
const SLOT_BUTTONS := ["DASH", "PASS", "LOFT", "SHOOT"]
const SCENARIO_SAVE := "user://iss_scenarios.json"

## Settings kept between matches (g_settings), with the game's defaults.
static var settings := {"level": 2, "time": 2, "mono": 0, "fouls": true, "cards": true,
	"offside": true, "vgoal": 1, "referee": 1}
static var home := 0
static var away := 2
static var stadium := 0
static var weather := 1
## What the team page starts: "open", "pk", "training", "cup", "world_series".
static var game := "open"
static var players_mode := 0
static var home_formation := -1
static var away_formation := -1
static var strategy_slots: Array = [0, 2, 4, 7]
## The competition in progress (null = none).
static var comp: ISSCompetition = null
static var comp_kind := "league"
static var comp_humans := 1
static var comp_teams: Array = [0, 1, 2, 6, 7, 30, 31, 3]
static var scenario := 0
## The training drill (g_training_drill): 0 free, 1 defence, 2 free kick, 3 keeper.
static var drill := 0

var page := Page.MAIN
var cursor := 0
var result := {}
var message := ""
var _back_to := Page.MAIN
var _backdrop := Sprite2D.new()
var _flags: Array[Sprite2D] = []
var _blink := 0
var _held_frames := 0
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
	var training := result.has("training_menu")
	_sound.play_music(16 if not result.is_empty() and not training else 3)
	if training:
		# Start in training: the training menu (match_rules_update_3).
		show_page(Page.TRAINING)
		return
	if not result.is_empty():
		_after_match()
	show_page(Page.RESULT if not result.is_empty() else Page.MAIN)


func _after_match() -> void:
	if comp != null and result.get("comp", false):
		comp.record(int(result["home_score"]), int(result["away_score"]), result.get("penalties", []))
		comp.simulate_until_human()
		if comp.finished():
			ISSCompetition.clear_saved()
		else:
			comp.save()
	if result.has("scenario"):
		var won: bool = int(result["home_score"]) > int(result["away_score"])
		var rec := _scenario_records()
		var i := int(result["scenario"])
		rec[i]["tries"] = mini(99, int(rec[i]["tries"]) + 1)
		if won:
			rec[i]["cleared"] = true
		var f := FileAccess.open(SCENARIO_SAVE, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rec))


static func _scenario_records() -> Array:
	if FileAccess.file_exists(SCENARIO_SAVE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO_SAVE))
		if d is Array and d.size() == 12:
			return d
	var out := []
	for i in 12:
		out.append({"cleared": false, "tries": 0})
	return out


func show_page(p: int) -> void:
	page = p
	cursor = 0
	var screen: String = {Page.MAIN: "00", Page.MATCH_TYPE: "01", Page.PLAYERS: "02", Page.TEAMS: "33",
		Page.PICK_TEAM: "33", Page.OPTIONS: "11", Page.RULES: "12", Page.STRATEGY: "0A", Page.RESULT: "33",
		Page.COMP_SETUP: "33", Page.COMP_TABLE: "33", Page.SCENARIO: "24", Page.MESSAGE: "33",
		Page.TRAINING: "18"}[p]
	_backdrop.texture = load(SCREENS + "screen_%s.png" % screen)
	queue_redraw()


func _message(text: String, back: int) -> void:
	message = text
	_back_to = back
	show_page(Page.MESSAGE)


func _physics_process(_delta: float) -> void:
	_blink += 1
	var pad := ISSInput.read(0)
	var dir: int = pad["dir"]
	var moved := Vector2i.ZERO
	if dir < 0:
		_held_frames = 0
	else:
		_held_frames += 1
		if _held_frames == 1 or (_held_frames > 20 and _held_frames % 8 == 0):
			var v := ISSProjection.heading_vector(dir)
			moved = Vector2i(roundi(v.x), roundi(v.y))
	var ok: bool = pad["press"] & (ISSFootballer.PASS | ISSFootballer.LOFT) or ISSInput.start_pressed(0)
	var back: bool = pad["press"] & ISSFootballer.SHOOT
	match page:
		Page.MAIN:
			_main(moved, ok)
		Page.MATCH_TYPE:
			_match_type(moved, ok, back)
		Page.PLAYERS:
			cursor = clampi(cursor + moved.y, 0, 2)
			if back:
				show_page(Page.MATCH_TYPE)
			elif ok:
				players_mode = cursor
				game = "open"
				show_page(Page.TEAMS)
		Page.TEAMS:
			_teams(moved, ok, back)
		Page.PICK_TEAM:
			_pick_team(moved, ok, back)
		Page.OPTIONS:
			_options(moved, ok, back)
		Page.RULES:
			_rules(moved, ok, back)
		Page.STRATEGY:
			cursor = clampi(cursor + moved.y, 0, 3)
			if moved.x != 0:
				strategy_slots[cursor] = posmod(int(strategy_slots[cursor]) + 1 + moved.x, 9) - 1
			if ok or back:
				show_page(_back_to)
		Page.RESULT:
			if ok or back:
				_sound.play_music(3)
				show_page(Page.COMP_TABLE if comp != null and result.get("comp", false) else Page.MAIN)
		Page.COMP_SETUP:
			_comp_setup(moved, ok, back)
		Page.COMP_TABLE:
			_comp_table(ok, back)
		Page.SCENARIO:
			_scenario(moved, ok, back)
		Page.MESSAGE:
			if ok or back:
				show_page(_back_to)
		Page.TRAINING:
			# screen_training_select: up and down wrap round.
			drill = posmod(drill + moved.y, 4)
			if back:
				show_page(Page.MAIN)
			elif ok:
				_start_training()
	if moved != Vector2i.ZERO or ok or back:
		_sound.play_sfx(0x5E)
	queue_redraw()


func _main(moved: Vector2i, ok: bool) -> void:
	cursor = clampi(cursor + moved.y * 2 + moved.x, 0, MAIN_ITEMS.size() - 1)
	if not ok:
		return
	match cursor:
		0:
			show_page(Page.MATCH_TYPE)
		1, 2:
			game = "cup" if cursor == 1 else "world_series"
			show_page(Page.PICK_TEAM)
		3:
			comp = ISSCompetition.load_saved()
			if comp == null:
				_message("NO SAVED GAME", Page.MAIN)
			else:
				show_page(Page.COMP_TABLE)
		4:
			show_page(Page.SCENARIO)
		5:
			game = "pk"
			players_mode = 0
			show_page(Page.TEAMS)
		6:
			# mode_start_training: one team, then free training ($13BC = 0).
			game = "training"
			show_page(Page.PICK_TEAM)
		7:
			show_page(Page.OPTIONS)


func _match_type(moved: Vector2i, ok: bool, back: bool) -> void:
	cursor = clampi(cursor + moved.y, 0, 2)
	if back:
		show_page(Page.MAIN)
	elif ok:
		match cursor:
			0:
				show_page(Page.PLAYERS)
			1, 2:
				comp_kind = "league" if cursor == 1 else "tournament"
				show_page(Page.COMP_SETUP)


func _base_options() -> Dictionary:
	var opts := settings.duplicate()
	opts["stadium"] = stadium
	opts["weather"] = weather
	opts["strategies"] = strategy_slots.duplicate()
	return opts


func _teams(moved: Vector2i, ok: bool, back: bool) -> void:
	var n := ISSMatchData.team_count() - 1 # the practice team stays out
	cursor = clampi(cursor + moved.y, 0, 7)
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
		_back_to = Page.TEAMS
		show_page(Page.STRATEGY)
	elif ok and cursor == 7:
		var opts := _base_options()
		opts["pads"] = PADS[players_mode]
		opts["formations"] = [home_formation, away_formation]
		# Open games are knockout matches ($1274 = 1): extra time, then penalties.
		opts["knockout"] = true
		opts["pk_only"] = game == "pk"
		start_match.emit(home, away, opts)


## The team page of the International Cup, the World Series and training:
## one side.
func _pick_team(moved: Vector2i, ok: bool, back: bool) -> void:
	# Both competitions are between the 36 national teams.
	var n := 36 if game != "training" else ISSMatchData.team_count() - 1
	cursor = clampi(cursor + moved.y, 0, 3)
	match cursor:
		0:
			home = posmod(home + moved.x, n)
			home_formation = -1
		1:
			home_formation = posmod(_formation(home, home_formation) + moved.x, 16) if moved.x != 0 else home_formation
	if back:
		show_page(Page.MAIN)
	elif ok and cursor == 2:
		_back_to = Page.PICK_TEAM
		show_page(Page.STRATEGY)
	elif ok and cursor == 3 and game == "training":
		drill = 0
		_start_training()
	elif ok and cursor == 3:
		comp = ISSCompetition.international_cup(home) if game == "cup" else ISSCompetition.world_series(home)
		comp.simulate_until_human()
		comp.save()
		show_page(Page.COMP_TABLE)


## Training (menu_state_03E8F0_2): the chosen team against the practice
## team ($2A) in stadium 0, fine weather, the computer at level 4.
func _start_training() -> void:
	var opts := _base_options()
	opts["stadium"] = 0
	opts["weather"] = 1
	opts["level"] = 4
	opts["pads"] = [1, 0]
	opts["knockout"] = false
	opts["formations"] = [home_formation, -1]
	opts["training"] = drill
	start_match.emit(home, int(ISSMatchData.consts["training"]["team"]), opts)


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
		show_page(Page.OPTIONS)


func _comp_size() -> int:
	return 6 if comp_kind == "league" else 8


## Number of human teams, then every team of the competition, then start.
func _comp_setup(moved: Vector2i, ok: bool, back: bool) -> void:
	var n := _comp_size()
	cursor = clampi(cursor + moved.y, 0, n + 1)
	if cursor == 0:
		comp_humans = clampi(comp_humans + moved.x, 1, n)
	elif cursor <= n and moved.x != 0:
		var teams := ISSMatchData.team_count() - 1
		var t: int = comp_teams[cursor - 1]
		for i in teams:
			t = posmod(t + moved.x, teams)
			if not comp_teams.slice(0, n).has(t):
				break
		comp_teams[cursor - 1] = t
	if back:
		show_page(Page.MATCH_TYPE)
	elif ok and cursor == n + 1:
		var ids := comp_teams.slice(0, n)
		comp = ISSCompetition.league(ids, comp_humans) if comp_kind == "league" \
			else ISSCompetition.tournament(ids, comp_humans)
		comp.simulate_until_human()
		comp.save()
		show_page(Page.COMP_TABLE)


func _comp_table(ok: bool, back: bool) -> void:
	if comp.finished():
		if ok or back:
			ISSCompetition.clear_saved()
			comp = null
			show_page(Page.MAIN)
		return
	if back:
		# Saved: CONTINUE picks it up again.
		comp = null
		show_page(Page.MAIN)
	elif ok:
		var g := comp.next_game()
		var opts := _base_options()
		opts["stadium"] = randi() % 8
		opts["weather"] = randi() % 3
		opts["pads"] = [1 if comp.is_human(g[0]) else 0, 1 if comp.is_human(g[1]) else 0]
		opts["knockout"] = comp.knockout()
		opts["comp"] = true
		start_match.emit(comp.team_of(g[0]), comp.team_of(g[1]), opts)


## Scenario select (screen $24): 3 columns x 4 rows, the story below.
func _scenario(moved: Vector2i, ok: bool, back: bool) -> void:
	scenario = clampi(scenario + moved.x + moved.y * 3, 0, 11)
	if back:
		show_page(Page.MAIN)
	elif ok:
		var sc: Dictionary = ISSMatchData.consts["scenarios"][scenario]
		var opts := _base_options()
		opts["stadium"] = int(sc["stadium"])
		opts["weather"] = 1
		opts["referee"] = int(sc["referee"])
		opts["pads"] = [1, 0]
		opts["knockout"] = false
		opts["scenario"] = sc
		opts["scenario_index"] = scenario
		start_match.emit(int(sc["home"]), int(sc["away"]), opts)


# ---------------------------------------------------------------------------

func _box(r: Rect2, on: bool) -> void:
	var c := Color(1, 1, 0.2) if on and (_blink / 8) % 2 == 0 else Color(1, 1, 1, 0.7)
	draw_rect(r.grow(1), c, false, 1.0)


func _team_name(team: int) -> String:
	return ISSMatchData.team_name(team).to_upper()


func _draw() -> void:
	for f in _flags:
		f.visible = false
	match page:
		Page.MAIN:
			for i in MAIN_ITEMS.size():
				var cx := 64.0 if i % 2 == 0 else 192.0
				var cy := 40.0 + 48.0 * float(i / 2)
				var r := Rect2(cx - 57, cy - 18, 114, 36)
				draw_rect(r, Color(0, 0, 0.3, 0.75))
				var label: String = MAIN_ITEMS[i]
				if label.length() > 13:
					# Two lines: INTERNATIONAL / CUP.
					var words := label.split(" ")
					ISSText.draw_centred(self, words[0], cx, cy - 16, true, i == cursor)
					ISSText.draw_centred(self, " ".join(words.slice(1)), cx, cy, true, i == cursor)
				else:
					ISSText.draw_centred(self, label, cx, cy - 8, true, i == cursor)
				if i == cursor:
					_box(r, true)
		Page.MATCH_TYPE:
			_box(Rect2(60, 38 + 24 * cursor, 136, 20), true)
		Page.PLAYERS:
			for i in 3:
				ISSText.draw_centred(self, PLAYER_MODES[i], 128, 76 + i * 24, true, i == cursor)
		Page.TEAMS:
			var title: String = {"open": "-TODAYS GAME-", "pk": "-PK-"}.get(game, "")
			ISSText.draw_centred(self, title, 128, 8, true)
			_team_row(0, home, 30, "HOME")
			_formation_row(home, home_formation, 50, cursor == 1)
			ISSText.draw_centred(self, "VS", 128, 64, false)
			_team_row(1, away, 78, "AWAY")
			_formation_row(away, away_formation, 98, cursor == 3)
			ISSText.draw(self, "STADIUM %d" % (stadium + 1), Vector2(40, 116), true, cursor == 4)
			ISSText.draw(self, "WEATHER " + WEATHERS[weather], Vector2(40, 134), true, cursor == 5)
			ISSText.draw(self, "STRATEGY", Vector2(40, 152), true, cursor == 6)
			ISSText.draw_centred(self, "GAME START", 128, 176, true, cursor == 7)
			if game == "open":
				ISSText.draw_centred(self, PLAYER_MODES[players_mode], 128, 202, false)
		Page.PICK_TEAM:
			var title: String = {"cup": "-INTERNATIONAL CUP-", "world_series": "-WORLD SERIES-"}.get(game, "-TRAINING-")
			ISSText.draw_centred(self, title, 128, 16, true)
			_team_row(0, home, 60, "")
			_formation_row(home, home_formation, 84, cursor == 1)
			ISSText.draw(self, "STRATEGY", Vector2(80, 112), true, cursor == 2)
			ISSText.draw_centred(self, "START", 128, 150, true, cursor == 3)
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
		Page.STRATEGY:
			draw_rect(Rect2(16, 16, 124, 96), Color(0, 0, 0.3, 0.6))
			ISSText.draw(self, "STRATEGY", Vector2(20, 20), false)
			for i in 4:
				var st := int(strategy_slots[i])
				ISSText.draw(self, SLOT_BUTTONS[i], Vector2(20, 36 + i * 18), false, cursor == i)
				var label: String = "-" if st < 0 else STRATEGY_NAMES[st]
				ISSText.draw(self, label.left(15), Vector2(20, 45 + i * 18), false, cursor == i)
			var cur := int(strategy_slots[cursor])
			if cur >= 0:
				_box(Rect2(22 + 120 * (cur / 4), 136 + 16 * (cur % 4), 100, 16), true)
		Page.RESULT:
			_draw_result()
		Page.COMP_SETUP:
			var n := _comp_size()
			ISSText.draw_centred(self, "-SHORT LEAGUE-" if comp_kind == "league" else "-SHORT TOURNAMENT-", 128, 8, true)
			ISSText.draw(self, "HUMAN TEAMS %d" % comp_humans, Vector2(40, 30), false, cursor == 0)
			for i in n:
				var y := 44 + i * 18
				ISSText.draw(self, _team_name(int(comp_teams[i])), Vector2(56, y), true, cursor == i + 1)
				ISSText.draw(self, "%dP" % (i + 1) if i < comp_humans else "COM", Vector2(200, y + 4), false)
			ISSText.draw_centred(self, "START", 128, 44 + n * 18 + 4, true, cursor == n + 1)
		Page.COMP_TABLE:
			_draw_comp()
		Page.SCENARIO:
			_draw_scenarios()
		Page.MESSAGE:
			ISSText.draw_centred(self, message, 128, 100, true, true)
		Page.TRAINING:
			# The drill's box (tbl_drill_boxes) and its description in the
			# 8x8 font at (32, 152) (screen_training_select_menu).
			_box(Rect2(88, 56 + 16 * drill, 80, 16), true)
			# rect_fill clears the box under the text to the plain background.
			draw_rect(Rect2(32, 152, 192, 32), Color8(73, 73, 255))
			var y := 152
			for line: String in ISSMatchData.consts["training"]["texts"][drill]:
				ISSText.draw(self, line, Vector2(32, y), false)
				y += 8


func _team_row(i: int, team: int, y: float, side: String) -> void:
	var f := _flags[i]
	if team < 42:
		f.texture = load("res://assets/iss/hud/flags/flag_%02d.png" % team)
		f.position = Vector2(40, y)
		f.visible = true
	ISSText.draw(self, _team_name(team), Vector2(80, y), true, cursor == i * 2)
	if side != "":
		ISSText.draw(self, side, Vector2(208, y + 4), false)


func _formation_row(team: int, picked: int, y: float, on: bool) -> void:
	var fid := _formation(team, picked)
	ISSText.draw(self, "FORMATION " + str(ISSMatchData.formations[fid]["name"]), Vector2(80, y), false, on)


func _draw_result() -> void:
	var title := "FULL TIME"
	if result.has("scenario"):
		title = "SCENARIO CLEARED" if int(result["home_score"]) > int(result["away_score"]) else "UNLUCKY"
	ISSText.draw_centred(self, title, 128, 24, true)
	var hs := int(result.get("home_score", 0))
	var as_ := int(result.get("away_score", 0))
	var hn := _team_name(int(result.get("home", 0)))
	var an := _team_name(int(result.get("away", 0)))
	ISSText.draw_centred(self, "%s %d - %d %s" % [hn, hs, as_, an], 128, 56, true)
	var pk: Array = result.get("penalties", [])
	if not pk.is_empty():
		ISSText.draw_centred(self, "PK %d - %d" % [pk[0], pk[1]], 128, 74, false)
		hs = int(pk[0])
		as_ = int(pk[1])
	var y := 88
	for s: Dictionary in result.get("scorers", []):
		if y > 184:
			break
		var who := "%s %s%s" % [str(int(s["minute"]) + 1), s["name"], " (OG)" if s["own_goal"] else ""]
		ISSText.draw(self, who, Vector2(24 if int(s["side"]) == 0 else 136, y), false)
		y += 12
	var winner := "MATCH DRAWN" if hs == as_ else (hn if hs > as_ else an) + " WINS"
	ISSText.draw_centred(self, winner, 128, 196, true, true)


func _draw_comp() -> void:
	var titles := {"league": "-SHORT LEAGUE-", "tournament": "-SHORT TOURNAMENT-",
		"cup": "-INTERNATIONAL CUP-", "world_series": "-WORLD SERIES-"}
	ISSText.draw_centred(self, titles[comp.kind], 128, 8, true)
	if comp.alive.is_empty():
		# Round robin: the table (the World Series shows its top ten).
		ISSText.draw(self, "TEAM", Vector2(24, 30), false)
		ISSText.draw(self, "W  D  L  P", Vector2(160, 30), false)
		var y := 42
		var rows := comp.table()
		for k in mini(rows.size(), 10):
			var r: Dictionary = rows[k]
			var name := _team_name(comp.team_of(r["slot"]))
			ISSText.draw(self, "%2d %s" % [k + 1, name], Vector2(8, y), false, comp.is_human(r["slot"]))
			ISSText.draw(self, "%d  %d  %d %2d" % [r["w"], r["d"], r["l"], r["p"]], Vector2(160, y), false)
			y += 11
	else:
		var y := 30
		for r: Dictionary in comp.games.slice(maxi(0, comp.games.size() - 10)):
			var line := "%s %d-%d %s" % [_team_name(comp.team_of(r["home"])), r["hg"], r["ag"],
				_team_name(comp.team_of(r["away"]))]
			if not r["pk"].is_empty():
				line += " PK%d-%d" % [r["pk"][0], r["pk"][1]]
			ISSText.draw(self, line, Vector2(8, y), false)
			y += 11
	if comp.finished():
		var c := comp.champion()
		if c < 0:
			ISSText.draw_centred(self, "GAME OVER", 128, 180, true, true)
		else:
			ISSText.draw_centred(self, "CHAMPION", 128, 164, true, true)
			ISSText.draw_centred(self, _team_name(comp.team_of(c)), 128, 184, true)
	else:
		var g := comp.next_game()
		ISSText.draw_centred(self, comp.round_name(), 128, 158, false)
		ISSText.draw_centred(self, _team_name(comp.team_of(g[0])) + " VS " + _team_name(comp.team_of(g[1])), 128, 172, true)
		ISSText.draw_centred(self, "PRESS START", 128, 196, false, (_blink / 16) % 2 == 0)


## Scenario select: NO.1-12 at their places on screen $24, cleared ones
## marked, the chosen one's story in the box below (tbl_scenario_texts).
func _draw_scenarios() -> void:
	var rec := _scenario_records()
	for i in 12:
		var at := Vector2(48 + 56 * (i % 3), 26 + 24 * (i / 3))
		if bool(rec[i]["cleared"]):
			ISSText.draw(self, "OK", at + Vector2(40, 0), false, true)
		if i == scenario:
			_box(Rect2(at - Vector2(2, 2), Vector2(44, 20)), true)
	var sc: Dictionary = ISSMatchData.consts["scenarios"][scenario]
	var title: Array = sc["title"]
	# Where menu_state_052754 draws them: the title in the 8x16 font at
	# (40, 128) and (64, 144), the story in the 8x8 font from (24, 160).
	ISSText.draw(self, str(title[0]).to_upper(), Vector2(40, 128), true)
	ISSText.draw(self, str(title[1]).replace("`", "").to_upper(), Vector2(64, 144), true)
	var y := 160
	for line: String in sc["text"]:
		ISSText.draw(self, line.replace("`", ""), Vector2(24, y), false)
		y += 8
