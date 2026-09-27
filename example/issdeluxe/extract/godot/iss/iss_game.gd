class_name ISSGame
extends Control
## International Superstar Soccer Deluxe in Godot: the front end and the
## matches, drawn in a 256 x 224 viewport (the Mega Drive's H32 screen) and
## scaled by whole numbers to fit the window.

const SCREEN := Vector2i(256, 224)

var _container := SubViewportContainer.new()
var _view := SubViewport.new()
var _screen: Node = null


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	_view.size = SCREEN
	_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_view.snap_2d_transforms_to_pixel = true
	_view.audio_listener_enable_2d = true
	_container.add_child(_view)
	add_child(_container)
	get_viewport().size_changed.connect(_layout)
	_layout()
	ISSInput.ensure_actions()
	show_front_end({})


func _layout() -> void:
	var s := get_viewport_rect().size
	var k := maxf(1.0, floorf(minf(s.x / SCREEN.x, s.y / SCREEN.y)))
	_container.size = Vector2(SCREEN)
	_container.scale = Vector2(k, k)
	_container.position = ((s - Vector2(SCREEN) * k) / 2.0).floor()


func _set_screen(n: Node) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = n
	_view.add_child(n)


func show_front_end(result: Dictionary) -> void:
	var fe := ISSFrontEnd.new()
	fe.result = result
	fe.start_match.connect(_start_match)
	_set_screen(fe)


func _start_match(home: int, away: int, options: Dictionary) -> void:
	var m := ISSMatch.new()
	_set_screen(m)
	m.start(home, away, options)
	m.match_over.connect(show_front_end)
