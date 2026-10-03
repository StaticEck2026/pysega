class_name ISSGame
extends Control
## International Superstar Soccer Deluxe in Godot: the game's main loop
## (main_loop: when a fade to black ends, jump to g_next_state) over the
## ported states, drawn in a 256 x 224 viewport (the Mega Drive's H32
## screen) scaled by whole numbers to fit the window.
##
## state_menu is ISSMenu (the front end's screens); state_match is ISSMatch
## playing one half from the RAM the menus leave (ISSMatchSetup.from_ram)
## and writing it back when the half ends, a side asks for the match menu,
## or the match is over; state_shootout is the engine's shoot-out; the
## presentations of state_screen (the teams coming out, a goal celebrated,
## a trophy) are not drawn yet, the game goes straight on to where they
## lead.

const SCREEN := Vector2i(256, 224)
const S := preload("res://iss/iss_sym.gd")

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
	ISSMenu.power_on()
	ISSRam.set_w(S.g_next_screen, 0)
	_menu()


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


## The state the game jumps to: $14 keeps the one it leaves.
func _jump(st: int) -> void:
	ISSRam.set_l(0x14, ISSRam.l(S.g_current_state))
	ISSRam.set_l(S.g_current_state, st)


## state_menu: the screen in g_next_screen.
func _menu() -> void:
	var m := ISSMenu.new()
	_set_screen(m)
	m.next_state.connect(_state)
	m.enter(ISSMenu.STATE_MENU)


func _state(st: int) -> void:
	match st:
		ISSMenu.STATE_MATCH:
			_match()
		ISSMenu.STATE_SHOOTOUT:
			_shootout()
		ISSMenu.STATE_SCREEN:
			_presentation()
		ISSMenu.STATE_INIT:
			# main_init: the boot screens (not drawn yet), then the main menu.
			_jump(ISSMenu.STATE_INIT)
			ISSRam.set_w(S.g_next_screen, 0)
			_menu()
		_:
			push_error("ISSGame: state $%06X is not ported" % st)
			ISSRam.set_w(S.g_next_screen, 0)
			_menu()


## state_match: one half (or the rest of it after the match menu).
func _match() -> void:
	# In a match: the pre-match menu is the match menu and resumes it.
	ISSRam.set_w(0x1638, 1)
	# match_create_objects: no side asking for the match menu yet ($182A /
	# $18B2 were the match menu's "chosen" marks).
	ISSRam.set_w(0x182A, 0)
	ISSRam.set_w(0x18B2, 0)
	var setup := ISSMatchSetup.from_ram()
	var m := ISSMatch.new()
	_set_screen(m)
	m.start(int(setup["home"]), int(setup["away"]), setup["options"])
	m.match_over.connect(func(_r: Dictionary) -> void: _match_left(m))


func _match_left(m: ISSMatch) -> void:
	var e := m.engine
	ISSRam.set_l(S.g_next_state, ISSMenu.STATE_MENU)
	if e.drill >= 0:
		# training_pause: Start returns to the drills (screen $18).
		ISSRam.set_w(S.g_next_screen, 0x18)
		_menu()
		return
	if e.challenge >= 0:
		# challenge_over: the record screen ($17).
		ISSMatchSetup.challenge_to_ram(e)
		ISSRam.set_w(S.g_next_screen, 0x17)
		_menu()
		return
	ISSMatchSetup.to_ram(e)
	match e.end_reason:
		"menu":
			# rules_state_0185BA: the match menu, the restart waiting.
			ISSRam.set_w(S.g_next_screen, 6)
		"result":
			# match_result_banner: a scenario's own screen, else the
			# statistics.
			ISSRam.set_w(S.g_next_screen, 0x25 if ISSRam.w(S.g_game_mode) == 0xC else 0x39)
		_:
			ISSRam.set_w(S.g_next_screen, 0x39)
	_menu()


## state_shootout: to the end with the engine's shoot-out; the kicks each
## side scored ($153A / $153C), then where the game mode goes after the
## match (state_shootout_frame_14).
func _shootout() -> void:
	var setup := ISSMatchSetup.from_ram()
	var opts: Dictionary = setup["options"]
	opts["pk_only"] = true
	var m := ISSMatch.new()
	_set_screen(m)
	m.start(int(setup["home"]), int(setup["away"]), opts)
	m.match_over.connect(func(_r: Dictionary) -> void: _shootout_over(m))


func _shootout_over(m: ISSMatch) -> void:
	var e := m.engine
	ISSRam.set_w(0x153A, int(e.pk_scores[0]))
	ISSRam.set_w(0x153C, int(e.pk_scores[1]))
	ISSRam.set_w(S.g_shootout_kicks, maxi(int(e.pk_taken[0]), int(e.pk_taken[1])))
	_jump(ISSMenu.STATE_SHOOTOUT)
	ISSModes.after_match(true)
	_menu()


## state_screen ($1730): 0 the teams coming out and the toss before the
## match, 1 a goal (a lead by one or a hat-trick), 2 a trophy. Not drawn:
## the game goes where each one leads (the toss leaves the kick-off and
## the ends as the set-up chose them).
func _presentation() -> void:
	match ISSRam.w(0x1730):
		0, 1:
			_jump(ISSMenu.STATE_SCREEN)
			_match()
		_:
			# menu_sound_03C97E_8: the trophy's way on.
			ISSRam.set_l(S.g_next_state, ISSMenu.STATE_MENU)
			if ISSRam.w(S.g_game_mode) == 8 or ISSRam.w(0x1260) != 0:
				ISSRam.set_w(S.g_next_screen, 0x33)
			elif ISSRam.w(0x126C) == 0:
				ISSModes.menu_func_05C404()
				ISSRam.set_w(S.g_next_screen, 0x37)
			else:
				ISSModes.mode_start_championship()
				ISSModes.match_setup_random()
				ISSRam.set_w(S.g_next_screen, 0x38)
			_jump(ISSMenu.STATE_SCREEN)
			_menu()
