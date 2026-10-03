class_name ISSScreensScenario
extends ISSScreens
## The scenarios (mode $C): twelve second halves to win from where they
## stand (screen $24, the cleared ones stamped), and the result after each
## attempt (screen $25: congratulations with the scenario's number when the
## human's side won), then the password, or once all twelve are cleared
## screen $26.
##
## RAM: $1270 the scenario under the cursor, $129C two bytes a scenario
## (cleared, attempts), $1272 0 when all are cleared.

func register(h: Dictionary) -> void:
	h[0x24] = screen_scenario_select
	h[0x25] = screen_scenario_failed


func _box(k: int) -> int:
	return rom("menu_data_052956") + k * 8


func screen_scenario_select() -> void:
	m.menu_music(5)
	for k in 12:
		if ISSRam.b(0x129C + k * 2) != 0:
			var b := _box(k)
			m.rect_fill_tiles(ISSRom.u16(b), ISSRom.u16(b + 2), ISSRom.u16(b + 4), ISSRom.u16(b + 6),
				tiles() + 0x330)
	spawn(screen_scenario_select_1)
	menu_state_052754(spawn(Callable()))


func screen_scenario_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_scenario_select_2
	o.set_w(T, 0)
	screen_scenario_select_2(o)


func screen_scenario_select_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("screen_scenario_select_2_data"))


## The way back (top right): C to the main menu; down / up return to the
## grid's top / bottom row.
func menu_state_052754_1(o: ISSMenu.Obj) -> void:
	o.update = menu_state_052754_2
	o.set_w(T, 0)
	menu_state_052754_2(o)


func menu_state_052754_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0)
		m.play_sfx(95)
	if pressed(PAD_DOWN):
		o.update = menu_state_052754
		set_w(0x1270, w(0x1270) % 3)
		m.play_sfx(77)
	if pressed(PAD_UP):
		o.update = menu_state_052754
		set_w(0x1270, w(0x1270) % 3 + 9)
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(0, 0xE0, 0xF8, 8)


## The scenario's description (tbl_scenario_texts: two large lines, six
## small) and the grid's cursor; C plays it.
func menu_state_052754(o: ISSMenu.Obj) -> void:
	o.update = menu_state_052754_3
	o.set_w(T, 0)
	var a := ISSRom.u32(rom("tbl_scenario_texts") + w(0x1270) * 4)
	a = m.text_draw_large(0x28, 0x80, a)
	a = m.text_draw_large(0x40, 0x90, a)
	for i in 6:
		a = m.text_draw_small(0x18, 0xA0 + i * 8, a)
	m.rect_highlight(0x40, 0xF0, 0x90, 0xA0)
	menu_state_052754_3(o)


func menu_state_052754_3(o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		o.update = menu_state_052754_1
	if pressed(PAD_C):
		ISSModes.scenario_setup()
		set_l(S.g_next_state, ISSMenu.STATE_MATCH)
		m.fade_out_start()
		m.play_sfx(95)
		return
	if pressed(PAD_RIGHT):
		add_w(0x1270, 1)
		if w(0x1270) > 0xB:
			set_w(0x1270, 0)
		o.update = menu_state_052754
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		add_w(0x1270, -1)
		if sw(0x1270) < 0:
			set_w(0x1270, 0xB)
		o.update = menu_state_052754
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		if w(0x1270) > 8:
			o.update = menu_state_052754_1
		else:
			add_w(0x1270, 3)
			o.update = menu_state_052754
		m.play_sfx(77)
	if pressed(PAD_UP):
		if w(0x1270) < 3:
			o.update = menu_state_052754_1
		else:
			add_w(0x1270, -3)
			o.update = menu_state_052754
		m.play_sfx(77)
	o.add_w(T, 1)
	var b := _box(w(0x1270))
	m.cursor_draw_large(0, ISSRom.u16(b), ISSRom.u16(b + 2), ISSRom.u16(b + 4) + 1)


# --------------------------------------------------------------------------
# Screen $25: the attempt recorded; a win shows "CONGRATULATIONS!!
# Scenario clear!!" with the scenario's number.

func screen_scenario_failed() -> void:
	m.menu_music(5)
	ISSModes.scenario_record_result()
	if sw(S.g_score_home) > sw(S.g_score_away):
		var a := m.text_draw_large(0x38, 0x48, rom("screen_scenario_failed_data"))
		m.text_draw_large(0x38, 0x60, a)
		m.rect_highlight(0x38, 0xC8, 0x48, 0x58)
		m.rect_fill_tiles(0x80, 0x88, 0x60, 0x70, tiles() + 0x320 + w(0x1270) * 2)
	spawn(screen_scenario_failed_1)


func screen_scenario_failed_1(o: ISSMenu.Obj) -> void:
	o.update = screen_scenario_failed_2
	screen_scenario_failed_2(o)


func screen_scenario_failed_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x26 if sw(0x1272) >= 0 else 0x3B)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_scenario_failed_2_data"))
