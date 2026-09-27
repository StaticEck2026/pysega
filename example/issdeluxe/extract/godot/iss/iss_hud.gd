class_name ISSHud
extends Node2D
## The ISS Deluxe match HUD (window plane) rebuilt from assets/iss/hud:
## team flags and names, score, clock and the radar. Put it on a CanvasLayer;
## it draws in window-plane pixels (256 x 256, the HUD rows of a 256 x 224
## screen are rows 0-3 and 20-26).

const DIR := "res://assets/iss/hud/"

@export var home_team: int = 0
@export var away_team: int = 1
@export var home_score: int = 0
@export var away_score: int = 0
## Clock in seconds (the game counts down).
@export var clock_seconds: float = 300.0
@export var second_half := false
@export_range(0, 7) var stadium: int = 0

var _doc: Dictionary
var _mat := ShaderMaterial.new()
var _window: Texture2D
var _digits: Texture2D
var _time_up: Texture2D
var _radar_dots: Array = [] # [pitch position, kind] set by set_radar()

## Radar dot colours: palette line 2 colours $D, $A, 9, 8, 1 and outline $F.
const DOT_COLOURS := {"home": 13, "away": 10, "controlled_home": 9, "controlled_away": 8, "ball": 1}

var _bounds := Rect2()
var _radar := RadarLayer.new()
var _banner := BannerLayer.new()
var _team_sprites := {} # "home_flag" etc. -> Sprite2D


## The radar dots are drawn unshaded, with colours from the HUD palette.
class RadarLayer:
	extends Node2D
	var hud: ISSHud
	var line2: Array[Color] = []

	func _draw() -> void:
		if line2.is_empty():
			return
		var origin := hud._cell("radar")
		var m: Dictionary = hud._doc["radar"]["mapping"][hud.stadium]
		var xs: Array = m["x"]
		var ys: Array = m["y"]
		for dot in hud._radar_dots:
			var p: Vector2 = dot[0]
			var ix := clampi(int((p.x - hud._bounds.position.x) / 16), 0, xs.size() - 1)
			var iy := clampi(int((p.y - hud._bounds.position.y) / 16), 0, ys.size() - 1)
			var at := origin + Vector2(int(xs[ix]), int(ys[iy]))
			var col: Color = line2[ISSHud.DOT_COLOURS[dot[1]]]
			if dot[1] != "home" and dot[1] != "away":
				draw_rect(Rect2(at - Vector2(1, 1), Vector2(4, 4)), line2[15])
			draw_rect(Rect2(at, Vector2(2, 2)), col)


## Banner text (banner_draw): 16x32 letters over the bottom window rows.
class BannerLayer:
	extends Node2D
	var font: Texture2D
	var text := ""
	var column := 5

	func _draw() -> void:
		for i in text.length():
			var g := text.unicode_at(i) - 0x40 # '@' = space, then A-Z
			if text[i] == " ":
				g = 0
			if g < 0 or g > 26:
				continue
			draw_texture_rect_region(font, Rect2((column + 2 * i) * 8, 23 * 8, 16, 32), Rect2(g * 16, 0, 16, 32))


func _ready() -> void:
	_doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "hud.json"))
	_mat.shader = load("res://md/md_indexed.gdshader")
	_mat.set_shader_parameter("palette", load(DIR + "hud.pal.png"))
	material = _mat
	_window = load(DIR + "window.png")
	_digits = load(DIR + "digits.png")
	_time_up = load(DIR + "time_up.png")
	var pal := (load(DIR + "hud.pal.png") as Texture2D).get_image()
	for i in 16:
		_radar.line2.append(pal.get_pixel(i, 2))
	_radar.hud = self
	for item in ["home_flag", "home_name", "away_flag", "away_name"]:
		var sp := Sprite2D.new()
		sp.centered = false
		sp.use_parent_material = true
		sp.position = _cell(item)
		add_child(sp)
		_team_sprites[item] = sp
	add_child(_radar)
	_banner.font = load(DIR + "banner_font.png")
	_banner.use_parent_material = true
	_banner.visible = false
	add_child(_banner)
	set_teams(home_team, away_team)
	set_stadium(stadium)


func set_teams(home: int, away: int) -> void:
	home_team = home
	away_team = away
	for side in [["home", home], ["away", away]]:
		var team: int = side[1]
		var ok := team >= 0 and team < 42
		var flag: Sprite2D = _team_sprites[side[0] + "_flag"]
		var name_plate: Sprite2D = _team_sprites[side[0] + "_name"]
		flag.texture = load(DIR + "flags/flag_%02d.png" % team) if ok else null
		name_plate.texture = load(DIR + "names/name_%02d.png" % team) if ok else null


func set_stadium(index: int) -> void:
	stadium = index
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iss/stadiums/stadiums.json"))
	var b: Dictionary = doc["stadiums"][stadium]["pitch_bounds"]
	_bounds = Rect2(b["left"], b["top"], b["right"] - b["left"], b["bottom"] - b["top"])


func _process(_delta: float) -> void:
	queue_redraw()
	_radar.queue_redraw()


## Shows a banner: message is a key of hud.json banner_messages ("throw_in",
## "goal_kick", "half_time", ...) or any text in capitals.
func show_banner(message: String) -> void:
	var m: Dictionary = _doc["banner_messages"].get(message, {"text": message, "column": 5})
	_banner.text = m["text"]
	_banner.column = int(m["column"])
	_banner.visible = true
	_banner.queue_redraw()


func hide_banner() -> void:
	_banner.visible = false


## Radar contents: an array of [Vector2 pitch position, kind], kind one of
## "home", "away", "controlled_home", "controlled_away", "ball".
func set_radar(dots: Array) -> void:
	_radar_dots = dots


func _cell(item: String) -> Vector2:
	var c: Array = _doc["items"][item]["cells"]
	return Vector2(int(c[0]) * 8, int(c[1]) * 8)


func _digit(d: int, at: Vector2) -> void:
	draw_texture_rect_region(_digits, Rect2(at, Vector2(8, 16)), Rect2(d * 8, 0, 8, 16))


func _number(n: int, at: Vector2, blank_tens: bool) -> void:
	if n >= 10 or not blank_tens:
		_digit((n / 10) % 10, at)
	_digit(n % 10, at + Vector2(8, 0))


func _draw() -> void:
	# The window plane only shows the score rows and the radar (the banner
	# strip below the radar is visible while a banner is up).
	draw_texture_rect_region(_window, Rect2(0, 0, 256, 32), Rect2(0, 0, 256, 32))
	var r := Rect2(_cell("radar"), Vector2(80, 56))
	draw_texture_rect_region(_window, r, r)
	_number(home_score, _cell("home_score"), true)
	_number(away_score, _cell("away_score"), true)
	var clock := _cell("clock")
	if clock_seconds <= 0.0:
		draw_texture(_time_up, clock)
	else:
		var s := int(ceil(clock_seconds))
		_digit(s / 60 % 10, clock)
		_number(s % 60, clock + Vector2(16, 0), false)
