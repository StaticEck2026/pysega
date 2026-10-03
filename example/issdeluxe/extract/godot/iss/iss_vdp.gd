class_name ISSVdp
extends Node2D
## The Mega Drive's picture as the front end builds it: VRAM (tiles, plane B
## at $0000 and plane A at $2000, 64 x 32 cells each), the CRAM and a sprite
## list, drawn by iss_vdp.gdshader at 256 x 224 with the VDP's priority and
## shadow/highlight rules. The front end writes VRAM and CRAM as the game's
## DMA does and adds sprites as sprite_alloc does; the textures are sent to
## the GPU once a frame when something changed.

const PLANE_B := 0x0000
const PLANE_A := 0x2000
const MAX_SPRITES := 64

var vram := PackedByteArray()
## CRAM words (----bbb-ggg-rrr-).
var cram := PackedInt32Array()
## Sprite table: 8 bytes per sprite (y + 128, size, attr, x + 128), in the
## order they were added (the link order).
var sat := PackedByteArray()
var sprite_count := 0
var scroll_a := Vector2i.ZERO
var scroll_b := Vector2i.ZERO
## Each line's horizontal scroll of planes A and B (register 11's cell or
## line mode, the hardware's own values: positive moves the plane right);
## empty for the full-screen scroll.
var lines_a := PackedInt32Array()
var lines_b := PackedInt32Array()
var backdrop := 0x20
var shadow_highlight := true

var _vram_img: Image
var _vram_tex: ImageTexture
var _cram_img: Image
var _cram_tex: ImageTexture
var _sat_img: Image
var _sat_tex: ImageTexture
var _mat := ShaderMaterial.new()
var _vram_dirty := true
var _cram_dirty := true


func _init() -> void:
	vram.resize(0x10000)
	cram.resize(64)
	sat.resize(MAX_SPRITES * 8)
	_vram_img = Image.create_from_data(256, 256, false, Image.FORMAT_R8, vram)
	_vram_tex = ImageTexture.create_from_image(_vram_img)
	_cram_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_cram_tex = ImageTexture.create_from_image(_cram_img)
	_sat_img = Image.create_from_data(MAX_SPRITES * 8, 1, false, Image.FORMAT_R8, sat)
	_sat_tex = ImageTexture.create_from_image(_sat_img)
	_mat.shader = load("res://iss/iss_vdp.gdshader")
	_mat.set_shader_parameter("vram", _vram_tex)
	_mat.set_shader_parameter("cram", _cram_tex)
	_mat.set_shader_parameter("sat", _sat_tex)
	material = _mat


## Copy bytes into VRAM (a DMA).
func dma(addr: int, data: PackedByteArray, offset := 0, length := -1) -> void:
	if length < 0:
		length = data.size() - offset
	for i in length:
		vram[(addr + i) & 0xFFFF] = data[offset + i]
	_vram_dirty = true


func vram_w(addr: int) -> int:
	return (vram[addr & 0xFFFF] << 8) | vram[(addr + 1) & 0xFFFF]


func set_vram_w(addr: int, v: int) -> void:
	vram[addr & 0xFFFF] = (v >> 8) & 0xFF
	vram[(addr + 1) & 0xFFFF] = v & 0xFF
	_vram_dirty = true


## Write a 64 x 32 nametable (2048 words, as the game keeps them in RAM).
func set_plane(base: int, words: PackedInt32Array) -> void:
	for i in mini(words.size(), 2048):
		var v := words[i]
		vram[base + 2 * i] = (v >> 8) & 0xFF
		vram[base + 2 * i + 1] = v & 0xFF
	_vram_dirty = true


func set_cram(words: PackedInt32Array) -> void:
	for i in 64:
		cram[i] = words[i] if i < words.size() else 0
	_cram_dirty = true


func clear_sprites() -> void:
	sprite_count = 0


## Add a sprite (sprite_alloc + the four words): y and x with the VDP's
## +128 offset, size byte (w - 1) << 2 | (h - 1), attribute word. Returns
## false when the 64 are used.
func add_sprite(y: int, size: int, attr: int, x: int) -> bool:
	if sprite_count >= MAX_SPRITES:
		return false
	var o := sprite_count * 8
	sat[o] = (y >> 8) & 0xFF
	sat[o + 1] = y & 0xFF
	sat[o + 2] = size & 0x0F
	sat[o + 3] = 0
	sat[o + 4] = (attr >> 8) & 0xFF
	sat[o + 5] = attr & 0xFF
	sat[o + 6] = (x >> 8) & 0xFF
	sat[o + 7] = x & 0xFF
	sprite_count += 1
	return true


static func md_color(w: int) -> Color:
	const LV := [0, 52, 87, 116, 144, 172, 206, 255]
	return Color8(LV[(w >> 1) & 7], LV[(w >> 5) & 7], LV[(w >> 9) & 7])


func _process(_delta: float) -> void:
	flush()


## Send what changed to the GPU and set the registers.
func flush() -> void:
	if _vram_dirty:
		_vram_img.set_data(256, 256, false, Image.FORMAT_R8, vram)
		_vram_tex.update(_vram_img)
		_vram_dirty = false
	if _cram_dirty:
		for i in 64:
			_cram_img.set_pixel(i, 0, md_color(cram[i]))
		_cram_tex.update(_cram_img)
		_cram_dirty = false
	_sat_img.set_data(MAX_SPRITES * 8, 1, false, Image.FORMAT_R8, sat)
	_sat_tex.update(_sat_img)
	_mat.set_shader_parameter("sprites", sprite_count)
	_mat.set_shader_parameter("scroll_ax", scroll_a.x)
	_mat.set_shader_parameter("scroll_ay", scroll_a.y)
	_mat.set_shader_parameter("scroll_bx", scroll_b.x)
	_mat.set_shader_parameter("scroll_by", scroll_b.y)
	_mat.set_shader_parameter("line_scroll", not lines_b.is_empty())
	if not lines_b.is_empty():
		_mat.set_shader_parameter("lines_a", lines_a)
		_mat.set_shader_parameter("lines_b", lines_b)
	_mat.set_shader_parameter("backdrop", backdrop)
	_mat.set_shader_parameter("shadow_highlight", shadow_highlight)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 256, 224), Color.WHITE)


## The scroll table as the VDP reads it from VRAM (a word for plane A, one
## for plane B per line, at table in RAM): every line its own (line mode)
## or every eighth line's for its row (cell mode).
func set_line_scroll(table: int, cell: bool) -> void:
	lines_a.resize(224)
	lines_b.resize(224)
	for y in 224:
		var a := table + (y & ~7 if cell else y) * 4
		lines_a[y] = ISSRam.w(a) & 0x3FF
		lines_b[y] = ISSRam.w(a + 2) & 0x3FF
