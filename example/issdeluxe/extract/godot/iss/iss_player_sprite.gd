class_name ISSPlayerSprite
extends Sprite2D
## An ISS Deluxe player drawn from the exported animation frames.
##
## Frames are CRAM-index images (line * 16 + colour). The palette texture holds
## the kit on line 0, skin/hair on line 2 and the shadow colour on line 3, so a
## different kit is just a different palette row (set_kit).

const DIR := "res://assets/iss/players/"

static var _anims: Dictionary = {}
static var _kits: Array = []
static var _base_palette: Image

@export var action: int = 0
@export_range(0, 63) var facing: int = 0
@export var frames_per_second: float = 8.0
@export var team: int = 0
@export var second_kit: bool = false

var _frame := 0
var _time := 0.0


func _ready() -> void:
	if _anims.is_empty():
		_anims = JSON.parse_string(FileAccess.get_file_as_string(DIR + "animations.json"))
		_kits = JSON.parse_string(FileAccess.get_file_as_string(DIR + "kits.json"))["teams"]
		_base_palette = (load(DIR + "palette_match.pal.png") as Texture2D).get_image()
	centered = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	material = mat
	set_kit(team, second_kit)
	_show()


## Recolour the player with a team's first or second kit.
func set_kit(team_index: int, use_second: bool) -> void:
	team = team_index
	second_kit = use_second
	var img := _base_palette.duplicate() as Image
	var kit: Array = _kits[team]["second_kit" if use_second else "first_kit"]
	for i in 16:
		img.set_pixel(i, 0, MDPalette.cram_to_color(int(kit[i])))
	(material as ShaderMaterial).set_shader_parameter("palette", ImageTexture.create_from_image(img))


func play(new_action: int) -> void:
	if new_action != action:
		action = new_action
		_frame = 0
		_show()


func action_count() -> int:
	return (_anims["actions"] as Array).size()


func _process(delta: float) -> void:
	_time += delta
	if _time >= 1.0 / frames_per_second:
		_time = 0.0
		_frame += 1
		_show()


func _show() -> void:
	var dir := ISSProjection.direction(facing)
	var seq: Array = _anims["actions"][action]["directions"][dir]
	if seq.is_empty():
		return
	var f: Dictionary = _anims["frames"][seq[_frame % seq.size()]]
	var r: Dictionary = f["left" if dir >= 5 else "right"]
	texture = load(r["png"])
	offset = Vector2(-int(r["origin_x"]), -int(r["origin_y"]))
