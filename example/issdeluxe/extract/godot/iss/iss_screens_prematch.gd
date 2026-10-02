class_name ISSScreensPrematch
extends ISSScreens
## The screens before a match: match type (1), player select (2), team
## select (3), stadium (4), handicap (5), the pre-match menu (6) and today's
## game ($10).

const RET_SCREENS := [6, 8, 9, 0xA, 0xB, 0xC, 0xD, 2, 0xE, 0xF]


func register(h: Dictionary) -> void:
	h[0x01] = screen_match_type
	h[0x02] = screen_player_select
	h[0x03] = screen_team_select
	h[0x04] = screen_stadium_select


# --------------------------------------------------------------------------
# Screen 1: open game / short league / short tournament.

func screen_match_type() -> void:
	set_w(0x153E, 0)
	set_w(S.g_pads_home, 0)
	set_w(S.g_pads_away, 0)
	spawn(screen_match_type_1)
	var o := spawn(Callable())
	menu_state_03D64C(o)


func screen_match_type_1(o: ISSMenu.Obj) -> void:
	o.update = screen_match_type_2
	o.set_w(T, 0)
	screen_match_type_2(o)


## B goes back to the main menu; the boxes.
func screen_match_type_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(0)
	m.boxes_draw_sprites(rom("screen_match_type_2_data"))


## One item of the match type menu: its two lines of description, C starts
## the mode, up / down move (wrapping), the box highlighted and the cursor.
func _match_item(o: ISSMenu.Obj, text: String, enter: Callable, idle: Callable) -> void:
	o.update = idle
	o.set_w(T, 0)
	var a := m.text_draw_large(0x38, 0x88, rom(text))
	m.text_draw_large(0x38, 0xA0, a)
	idle.call(o)


func _match_item_1(o: ISSMenu.Obj, start: Callable, screen: int, up: Callable, down: Callable,
		box: Array, cursor_x1: int, cursor_y: int, me: Callable) -> void:
	if pressed(PAD_C):
		start.call()
		goto_screen(screen)
		m.play_sfx(95)
	if pressed(PAD_UP):
		o.update = up
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		o.update = down
		m.play_sfx(77)
	if o.update == me:
		m.rect_highlight(box[0], box[1], box[2], box[3])
	else:
		m.rect_unhighlight(box[0], box[1], box[2], box[3])
	o.add_w(T, 1)
	m.cursor_draw_large(0, 0x40, cursor_x1, cursor_y)


func menu_state_03D64C(o: ISSMenu.Obj) -> void:
	_match_item(o, "menu_state_03D64C_data", menu_state_03D64C, menu_state_03D64C_1)


func menu_state_03D64C_1(o: ISSMenu.Obj) -> void:
	_match_item_1(o, ISSModes.start_open_game, 0x02, menu_state_03D838, menu_state_03D742,
		[0x40, 0x88, 0x28, 0x38], 0x88, 0x29, menu_state_03D64C_1)


func menu_state_03D742(o: ISSMenu.Obj) -> void:
	_match_item(o, "menu_state_03D742_data", menu_state_03D742, menu_state_03D742_1)


func menu_state_03D742_1(o: ISSMenu.Obj) -> void:
	_match_item_1(o, ISSModes.start_short_league, 0x34, menu_state_03D64C, menu_state_03D838,
		[0x40, 0xA0, 0x40, 0x50], 0xA0, 0x41, menu_state_03D742_1)


func menu_state_03D838(o: ISSMenu.Obj) -> void:
	_match_item(o, "menu_state_03D838_data", menu_state_03D838, menu_state_03D838_1)


func menu_state_03D838_1(o: ISSMenu.Obj) -> void:
	_match_item_1(o, ISSModes.start_short_tournament, 0x35, menu_state_03D742, menu_state_03D64C,
		[0x40, 0xC0, 0x58, 0x68], 0xC0, 0x59, menu_state_03D838_1)


# --------------------------------------------------------------------------
# Screen 2: player select. $1776 = humans (0-8), $1778 = how many of them
# play for the home side, $1780 = controllers connected; the backups
# $177A-$177E restore the old choice on B. In a competition ($1268) a row
# that would move the humans to the other side is greyed and refused.

## Per number of humans: the home count's range, the cursor's y for the
## top row and whether the rows step from home_max (y = base + 24 *
## (home_max - home)). From the menu_state_03DC14 ... 03E3AE family.
const PLAYERS := [
	{"lo": 0, "hi": 1, "base": 0x58, "data": "menu_state_03DC14_data"},
	{"lo": 0, "hi": 1, "base": 0x58, "data": "menu_state_03DC14_data"},
	{"lo": 1, "hi": 2, "base": 0x58, "data": "menu_state_03DD40_data"},
	{"lo": 2, "hi": 3, "base": 0x58, "data": "menu_state_03DE66_data"},
	{"lo": 2, "hi": 4, "base": 0x50, "data": "menu_state_03DF8C_data"},
	{"lo": 3, "hi": 4, "base": 0x58, "data": "menu_state_03E0B2_data"},
	{"lo": 3, "hi": 4, "base": 0x58, "data": "menu_state_03E1D8_data"},
	{"lo": 4, "hi": 4, "base": 0x68, "data": "menu_state_03E2FE_data"},
	{"lo": 4, "hi": 4, "base": 0x68, "data": "menu_state_03E3AE_data"},
]


func screen_player_select() -> void:
	# A quieter cursor sound while song 25 (silence) is on.
	set_w(0x1782, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	spawn(screen_player_select_1)
	set_w(0x1780, w(0x153E))
	set_w(0x1776, w(0x153E))
	set_w(0x1778, w(S.g_pads_home))
	set_w(0x177A, w(0x153E))
	set_w(0x177C, w(S.g_pads_home))
	set_w(0x177E, w(S.g_pads_away))
	set_w(0x153E, 0)
	set_w(S.g_pads_home, 0)
	set_w(S.g_pads_away, 0)
	var o := spawn(Callable())
	_players_state(o, w(0x1776))


func screen_player_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_player_select_2
	screen_player_select_2(o)


func screen_player_select_2(o: ISSMenu.Obj) -> void:
	var n := 0
	while n < 8 and w(S.g_pad_type + 2 * n) != 0xF:
		n += 1
	set_w(0x1780, n)
	if pressed(PAD_B):
		set_w(0x153E, w(0x177A))
		set_w(S.g_pads_home, w(0x177C))
		set_w(S.g_pads_away, w(0x177E))
		set_w(S.g_next_screen, 0 if w(S.g_game_mode) == 2 else 1)
		_back_to_prematch()
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
	if pressed(PAD_C):
		if w(0x1268) != 0 and not _players_row_ok(w(0x1778), w(0x1776) - w(0x1778)):
			m.play_sfx(94)
		else:
			set_w(0x153E, w(0x1776))
			set_w(S.g_pads_home, w(0x1778))
			set_w(S.g_pads_away, w(0x1776) - w(0x1778))
			set_w(S.g_next_screen, 3)
			_back_to_prematch()
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
			m.play_sfx(95)
	if w(0x1780) > 1:
		o.add_w(T, 1)
		m.pad_icon_draw(0, 0x18, 0x68)
		m.pad_icon_draw(1, 0xE0, 0x68)
	m.boxes_draw_sprites(rom("screen_player_select_2_data"))


## From the pre-match menu's screens (6-$10) the choice returns there
## (menu_input_040F5E; its "player select" answer means the menu itself).
func _back_to_prematch() -> void:
	var prev := w(0x175A)
	if prev >= 6 and prev <= 0x10:
		menu_input_040F5E()
		if w(S.g_next_screen) == 2:
			set_w(S.g_next_screen, 6)


## In a competition the humans must stay on the sides they had.
func _players_row_ok(home: int, away: int) -> bool:
	return (w(0x177C) != 0) == (home != 0) and (w(0x177E) != 0) == (away != 0)


## Enter the state for n humans (the menu_state_03DC14 ... family).
func _players_state(o: ISSMenu.Obj, n: int) -> void:
	o.update = func(ob: ISSMenu.Obj) -> void: _players_frame(ob, n)
	o.set_w(T, 0)
	_players_draw(rom(PLAYERS[n]["data"]))
	_players_frame(o, n)


## menu_func_03DC08 ... 03E3A2: n humans, home count min(n, 4).
func _players_enter(o: ISSMenu.Obj, n: int) -> void:
	set_w(0x1778, mini(n, 4))
	set_w(0x1776, n)
	_players_state(o, n)


func _players_frame(o: ISSMenu.Obj, n: int) -> void:
	var p: Dictionary = PLAYERS[n]
	var lo: int = p["lo"]
	var hi: int = p["hi"]
	var sfx := w(0x1782)
	var pads := w(0x1780)
	if lo != hi:
		if pressed(PAD_UP):
			var h := w(0x1778) + 1
			set_w(0x1778, lo if h > hi else h)
			if n <= 1:
				set_w(0x1776, w(0x1778))
			m.play_sfx(sfx)
		if pressed(PAD_DOWN):
			var h := w(0x1778) - 1
			set_w(0x1778, hi if h < lo else h)
			if n <= 1:
				set_w(0x1776, w(0x1778))
			m.play_sfx(sfx)
	# Left / right pick the state the next frame enters (the ROM sets the
	# object's update to its menu_func); from 0 or 1 human left wraps to
	# every controller playing and right goes to 2.
	if pressed(PAD_LEFT) and (n > 1 or pads > 1):
		_players_next(o, pads if n <= 1 else n - 1)
		m.play_sfx(sfx)
	if pressed(PAD_RIGHT) and (n > 1 or pads > 1):
		if n <= 1:
			_players_next(o, 2)
		else:
			_players_next(o, n + 1 if pads > n and n < 8 else 1)
		m.play_sfx(sfx)
	if n >= 2 and pads < n:
		_players_next(o, 1)
	o.add_w(T, 1)
	var y: int = p["base"] + 0x18 * (hi - w(0x1778)) if lo != hi else p["base"]
	m.cursor_draw_large(0, 0x74, 0x8C, y)


## The next frame enters the state for n humans (the ROM switches the
## object's update to the menu_func, which runs from the next frame).
func _players_next(o: ISSMenu.Obj, n: int) -> void:
	o.update = func(ob: ISSMenu.Obj) -> void: _players_enter(ob, maxi(n, 1))


## menu_input_03E440: the rows of the table at a (y, home, away; -1 ends):
## "VS" between the sides, a controller icon per human (the 3-button pad's
## when that controller is one) under the player numbers, or the CPU.
func _players_draw(a: int) -> void:
	var base := w(S.g_stadium_vram) >> 5
	m.rect_fill(0x30, 0xD0, 0x40, 0xA0, base | 0x4000)
	while ISSRom.s16(a) >= 0:
		var pad := 0
		var y := ISSRom.u16(a)
		var home := ISSRom.u16(a + 2)
		var away := ISSRom.u16(a + 4)
		m.rect_fill_tiles(0x78, 0x88, y, y + 0x10, (base | 0xA000) + 0x1C8)
		if home > 0:
			for k in range(home - 1, -1, -1):
				var t := (base | 0xA000) + 0x1CC + (2 if w(S.g_pad_type + 2 * pad) == 0 else 0)
				pad += 1
				var x := 0x60 - k * 0x10
				m.rect_fill_tiles(x, x + 0x10, y + 8, y + 0x10, t)
			m.rect_fill_tiles(0x70 - home * 0x10, 0x70, y, y + 8, (base | 0xA000) + 0x1D0)
		else:
			m.rect_fill_tiles(0x60, 0x70, y, y + 0x10, (base | 0xA000) + 0x1A0)
		if away > 0:
			for k in away:
				var t := (base | 0xA000) + 0x1CC + (2 if w(S.g_pad_type + 2 * pad) == 0 else 0)
				pad += 1
				var x := 0x90 + k * 0x10
				m.rect_fill_tiles(x, x + 0x10, y + 8, y + 0x10, t)
			m.rect_fill_tiles(0x90, 0x90 + away * 0x10, y, y + 8, (base | 0xA000) + 0x1D0 + home * 2)
		else:
			m.rect_fill_tiles(0x90, 0xA0, y, y + 0x10, (base | 0xA000) + 0x1C4)
		if w(0x1268) != 0 and not _players_row_ok(home, away):
			m.rect_unhighlight(0x30, 0xD0, y, y + 0x10)
		a += 6


# --------------------------------------------------------------------------
# Screen 3: team select. $1786 = the team shown for side $1768 (written to
# $127C + 2 * side on C); the region's six flags, the team's flag, name,
# formation, photo and its GK / DF / MF / FW averages. Resource group 6:
# entry 1 the 16-tile name plates ($1776), 0 the regions' small plates
# ($177A), 2 the flags (VRAM $177E), 7 the photo bodies (VRAM $1780), 8 the
# photo heads ($1782), 11 / 12 the flag and photo palettes (raw).

func screen_team_select() -> void:
	set_l(0x1776, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(6, 1, l(S.g_unpack_buffer)))
	set_l(0x177A, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(6, 0, l(S.g_unpack_buffer)))
	set_w(0x177E, m.load_tiles(6, 2))
	set_w(0x1780, m.load_tiles(6, 7))
	add_w(S.g_unpack_vram, 0x300)
	set_l(0x1782, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(6, 8, l(S.g_unpack_buffer)))
	set_w(0x1768, 0)
	spawn(screen_team_select_1)
	var o := spawn(Callable())
	menu_func_03E8E0(o)


func screen_team_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_team_select_2
	screen_team_select_2(o)


## The controller icons, the team photo (ten heads from the players'
## records, then the bodies of the photo's layout) and the boxes.
func screen_team_select_2(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	m.pad_icon_draw(0, 0x10, 0xA8)
	m.pad_icon_draw(1, 0xE8, 0xA8)
	var team := w(0x1786)
	var rec := ISSRom.u32(rom("tbl_player_data") + team * 4) + 0x16
	var a := ISSRom.u32(rom("screen_team_select_2_data2") + team * 4)
	var base := w(0x1780) >> 5
	for k in 10:
		m.sprite(ISSRom.u16(a), ISSRom.u16(a + 2), base + ISSRom.u8(rec) + ISSRom.u16(a + 4), ISSRom.u16(a + 6))
		rec += 12
		a += 8
	var n := ISSRom.u16(a)
	a += 2
	for k in n + 1:
		m.sprite(ISSRom.u16(a), ISSRom.u16(a + 2), base + ISSRom.u16(a + 4), ISSRom.u16(a + 6))
		a += 8
	m.boxes_draw_sprites(rom("screen_team_select_2_data"))


## menu_func_03E8E0: show the team side $1768 has.
func menu_func_03E8E0(o: ISSMenu.Obj) -> void:
	set_w(0x1786, w(0x127C + w(0x1768) * 2))
	menu_state_03E8F0(o)


## A line's average of the nine attributes over the players whose record
## matches, as the bar's 0-7 steps (* 56 / players / 90).
func _line_average(team: int, roles: Array, fw_quirk: bool) -> int:
	var a := ISSRom.u32(rom("tbl_player_data") + team * 4)
	var n := 0
	var sum := 0
	for k in 20:
		var pos := ISSRom.u8(a + 0xB)
		# The forwards' test reads the next record's first byte instead of
		# this one's position (cmpi.b #4,$C(a3)).
		if pos in roles or (fw_quirk and ISSRom.u8(a + 0xC) == 4):
			n += 1
			for i in 9:
				sum += ISSRom.u8(a + i)
		a += 12
	if n == 0:
		return 0
	return (sum * 0x38 / n) / 0x5A


## menu_state_03E8F0: draw the team: name plates and photo heads to VRAM,
## flag colours, the four line averages, the region's name, the formation,
## the flags, the side's icon, the photo palette and the side's colours;
## then the pads that drive it ($1548).
func menu_state_03E8F0(o: ISSMenu.Obj) -> void:
	o.update = menu_state_03E8F0_1
	o.set_w(T, 0)
	var team := w(0x1786)
	var side := w(0x1768)
	m.vram_dma(w(S.g_overlay_vram) + 0x6A00, l(0x1776) + team * 0x200, 0x200)
	m.vram_dma(w(S.g_overlay_vram) + 0x6C00, l(0x177A) + (team / 6) * 0x1E * 32, 0x3C0)
	m.vram_dma(w(0x1780) + 0xD60, l(0x1782) + ISSRom.u16(rom("menu_state_03E8F0_data3") + team * 2), 0x300)
	var flag_pal := ISSRom.res(6, 11)
	for i in 8:
		ISSRam.set_b(0x778 + i, flag_pal[team * 8 + i])
	if w(S.g_fade_step) == 0x18:
		m.cram_dma(0x22, 0x778, 8)
	m.bar_draw_wide(0xA8, 0x40, 0, _line_average(team, [3], false))
	m.bar_draw_wide(0xA8, 0x48, 1, _line_average(team, [2, 5], false))
	m.bar_draw_wide(0xA8, 0x50, 2, _line_average(team, [1, 4, 5], false))
	m.bar_draw_wide(0xA8, 0x58, 3, _line_average(team, [0], true))
	m.text_draw_large(0x20, 0x80, rom("menu_state_03E8F0_data2") + (team / 6) * 12)
	var formation := ISSRom.u8(ISSRom.u32(rom("tbl_team_formations") + team * 4))
	m.text_draw_small(0xB8, 0x30, rom("str_formation_names") + formation * 6)
	var flags := (w(0x177E) >> 5) | 0xC000
	m.rect_fill_tiles(0x88, 0xA0, 0x20, 0x30, flags + team * 6)
	var v := flags + (team / 6) * 0x24
	for r: Array in [[0x40, 0x58, 0x98, 0xA8], [0x78, 0x90, 0x98, 0xA8], [0xB0, 0xC8, 0x98, 0xA8],
			[0x40, 0x58, 0xB8, 0xC8], [0x78, 0x90, 0xB8, 0xC8], [0xB0, 0xC8, 0xB8, 0xC8]]:
		v = m.rect_fill_tiles(r[0], r[1], r[2], r[3], v)
	var icon := ((w(S.g_stadium_vram) >> 5) | 0xC000) + (0x180 if side & 1 == 0 else 0x1A4)
	icon += side * 4 if w(0x1266) > side else 0x20
	m.rect_fill_tiles(8, 0x18, 8, 0x18, icon)
	if w(0x1264) > 2:
		m.text_draw_large(0x38, 8, rom("menu_data_03F04C") + side * 0x12)
	var pal := ISSRom.res(6, 12)
	for i in 32:
		ISSRam.set_b(S.g_palette_target + i, pal[team * 32 + i])
	var cols := rom("menu_state_03E8F0_data") if side & 1 == 0 else rom("engine_data_01FAD4")
	for i in 5:
		set_w(0x7C6 + 2 * i, ISSRom.u16(cols + 2 * i))
	if w(S.g_fade_step) == 0x18:
		m.cram_dma(0, S.g_palette_target, 0x80)
	if w(0x1264) >= 3:
		set_w(0x1548, 2)
	else:
		set_w(0x1548, side & 1)
		if w(S.g_pads_home if side & 1 == 0 else S.g_pads_away) == 0:
			set_w(0x1548, 2)
	menu_state_03E8F0_1(o)


## Team select input (the side's own pads): B back (side 0: the mode's
## previous screen), C takes the team (the next side, or on to the mode),
## left / right along the region's three columns into the next region,
## up / down between its two rows; the cursor on the team's flag.
func menu_state_03E8F0_1(o: ISSMenu.Obj) -> void:
	var p := w(S.g_pad_pressed_home)
	var side := w(0x1768)
	var mode := w(S.g_game_mode)
	if p & PAD_B:
		if side == 0:
			var back := {3: 2, 4: 0x1B, 5: 0x20, 6: 0, 9: 0, 2: 0, 0: 0x13}
			if back.has(mode):
				set_w(S.g_next_screen, back[mode])
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
		else:
			set_w(0x1768, side - 1)
			o.update = menu_func_03E8E0
	if p & PAD_C:
		var a := 0x127C + w(0x1768) * 2
		set_w(a, w(0x1786))
		if w(0x1264) - 1 > w(0x1768):
			add_w(0x1768, 1)
			o.update = menu_func_03E8E0
			if w(0x1264) > 2:
				set_w(a + 2, w(a))
		else:
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			var nxt := {4: 0x1C, 5: 0x21, 6: 0x29, 9: 0x2F}
			if nxt.has(mode):
				set_w(S.g_next_screen, nxt[mode])
			if mode == 3:
				ISSModes.open_game_setup()
				set_w(S.g_next_screen, 4)
			if mode == 2:
				ISSModes.pk_setup()
				set_w(S.g_next_screen, 4)
			if mode == 0:
				ISSModes.training_setup()
				set_w(S.g_next_screen, 4)
			m.fade_out_start()
		m.play_sfx(95)
	# The number of teams: 36, or 42 with code 1 outside the competitions.
	var count := 0x2A if w(0x125A) != 0 and w(0x1276) == 0 else 0x24
	if p & PAD_RIGHT:
		var t := w(0x1786)
		if t % 3 != 2:
			t += 1
		else:
			t += 4
			if t >= count:
				t -= count
		set_w(0x1786, t)
		o.update = menu_state_03E8F0
		m.play_sfx(77)
	if p & PAD_LEFT:
		var t := w(0x1786)
		if t % 3 != 0:
			t -= 1
		else:
			t -= 4
			if t < 0:
				t += count
		set_w(0x1786, t)
		o.update = menu_state_03E8F0
		m.play_sfx(77)
	if p & (PAD_UP | PAD_DOWN):
		var t := w(0x1786)
		set_w(0x1786, t + 3 if t % 6 <= 2 else t - 3)
		o.update = menu_state_03E8F0
		m.play_sfx(77)
	o.add_w(T, 1)
	var c := rom("menu_state_03E8F0_1_data") + (w(0x1786) % 6) * 8
	m.cursor_draw_large(0, ISSRom.u16(c), ISSRom.u16(c + 2), ISSRom.u16(c + 4))


# --------------------------------------------------------------------------
# Screen 4: stadium and weather. The stadiums' pictures (group 4 entry 15,
# $177A) and their countries' name plates (group 6 entry 1, eight plates
# copied to $1776 and recoloured), animated crowd tiles (group 4 entries 7
# and 8, raw), the weather boxes (menu_data_03FC5E).

## The plate of each stadium's country, by its offset in the unpacked
## plates at buffer + $1000.
const STADIUM_PLATES := [0x5400, 0x2200, 0x1400, 0x1000, 0x1200, 0x4C00, 0x4600, 0x4000]


func screen_stadium_select() -> void:
	set_l(0x177A, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(4, 15, l(S.g_unpack_buffer)))
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 1, buf + 0x1000)
	set_l(0x1776, buf)
	var a := buf
	for off: int in STADIUM_PLATES:
		ISSRam.copy(a, buf + off, 0x200)
		a += 0x200
	set_l(S.g_unpack_buffer, a)
	m.recolour(buf & 0xFFFF, 0x1000, 0xA, 0xD)
	m.recolour(buf & 0xFFFF, 0x1000, 0xB, 0xE)
	m.recolour(buf & 0xFFFF, 0x1000, 0xC, 0xF)
	spawn(screen_stadium_select_1)
	var o := spawn(Callable())
	menu_state_03FB56(o)
	menu_state_03FA38(o)


func screen_stadium_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_stadium_select_2
	screen_stadium_select_2(o)


## B back to team select; C on (training select, PK order or the
## shoot-out when no human plays, handicap); the animated crowd tiles, the
## stadium's sprites, the controller icons and the boxes.
func screen_stadium_select_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(3)
	if pressed(PAD_C):
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		var mode := w(S.g_game_mode)
		if mode == 0:
			set_w(S.g_next_screen, 0x18)
		if mode == 2:
			if w(S.g_pads_home) == 0:
				set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
				m.fade_out_start()
			else:
				set_w(0x176A, 0)
				set_w(S.g_next_screen, 0x1A)
		if mode == 3:
			set_w(S.g_next_screen, 5)
		m.fade_out_start()
		m.play_sfx(95)
	var fc := w(S.g_frame_counter)
	var ov := w(S.g_overlay_vram)
	if fc & 7 == 0:
		if fc & 8 == 0:
			m.vdp.dma(ov + 0x6D80, ISSRom.res(4, 7), (fc & 0xF0) << 2, 0x40)
		else:
			m.vdp.dma(ov + 0x6DC0, ISSRom.res(4, 7), ((fc + 0x80) & 0xF0) << 2, 0x40)
	if fc & 1 == 0:
		m.vdp.dma(ov + 0x6F80, ISSRom.res(4, 8), (fc & 0xE) << 5, 0x40)
	else:
		m.vdp.dma(ov + 0x6FC0, ISSRom.res(4, 8), ((fc + 8) & 0xE) << 5, 0x40)
	var a := rom("screen_stadium_select_2_data2")
	var n := ISSRom.u16(a)
	a += 2
	var base := w(S.g_stadium_vram) >> 5
	for k in n + 1:
		m.sprite(ISSRom.u16(a), ISSRom.u16(a + 2), base + ISSRom.u16(a + 4), ISSRom.u16(a + 6))
		a += 8
	o.add_w(T, 1)
	m.pad_icon_draw(0, 0x20, 0x40)
	m.pad_icon_draw(1, 0xD8, 0x40)
	m.boxes_draw_sprites(rom("screen_stadium_select_2_data"))


## The stadium: its picture and name plate to VRAM; left / right step
## through the eight (wrapping), up / down go to the weather; the box
## flashes while it is chosen.
func menu_state_03FA38(o: ISSMenu.Obj) -> void:
	o.update = menu_state_03FA38_1
	o.set_w(T, 0)
	m.vram_dma(w(S.g_overlay_vram) + 0x7200, l(0x177A) + w(S.g_stadium) * 0x200, 0x200)
	m.vram_dma(w(S.g_overlay_vram) + 0x7000, l(0x1776) + w(S.g_stadium) * 0x200, 0x200)
	menu_state_03FA38_1(o)


func menu_state_03FA38_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_UP | PAD_DOWN):
		o.update = menu_state_03FB56
		m.play_sfx(77)
	if pressed(PAD_RIGHT):
		set_w(S.g_stadium, 0 if w(S.g_stadium) >= 7 else w(S.g_stadium) + 1)
		o.update = menu_state_03FA38
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		set_w(S.g_stadium, 7 if w(S.g_stadium) <= 0 else w(S.g_stadium) - 1)
		o.update = menu_state_03FA38
		m.play_sfx(77)
	o.add_w(T, 1)
	if o.update == menu_state_03FA38_1:
		m.rect_flash(0x28, 0xD8, 0x18, 0x78)
	else:
		m.rect_unhighlight(0x28, 0xD8, 0x18, 0x78)


## The weather: snow, fine, rain boxes (the chosen one highlighted, or
## flashing while the weather is being chosen).
func menu_state_03FB56(o: ISSMenu.Obj) -> void:
	o.update = menu_state_03FB56_1
	o.set_w(T, 0)
	var a := rom("menu_data_03FC5E")
	for k in 3:
		var r := [ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6)]
		if k == w(S.g_weather):
			m.rect_highlight(r[0], r[1], r[2], r[3])
		else:
			m.rect_unhighlight(r[0], r[1], r[2], r[3])
		a += 8
	menu_state_03FB56_1(o)


func menu_state_03FB56_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_UP | PAD_DOWN):
		o.update = menu_state_03FA38
		m.play_sfx(77)
	if pressed(PAD_RIGHT):
		set_w(S.g_weather, 0 if w(S.g_weather) >= 2 else w(S.g_weather) + 1)
		o.update = menu_state_03FB56
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		set_w(S.g_weather, 2 if w(S.g_weather) <= 0 else w(S.g_weather) - 1)
		o.update = menu_state_03FB56
		m.play_sfx(77)
	o.add_w(T, 1)
	var a := rom("menu_data_03FC5E") + w(S.g_weather) * 8
	if o.update == menu_state_03FB56_1:
		m.rect_flash(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6))
	else:
		m.rect_highlight(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6))


# --------------------------------------------------------------------------

## menu_input_040F5E: where a pre-match sub-screen returns. Training and
## challenges have their own menus; with humans on both sides the home
## side's choice is followed by the away side's on the same item
## ($176A = 1, g_prematch_item through menu_data_041012), or after the last
## item the competition's own screen; otherwise the pre-match menu.
func menu_input_040F5E() -> void:
	var mode := w(S.g_game_mode)
	if mode == 0:
		set_w(S.g_next_screen, 0x19)
		return
	if mode == 1:
		set_w(S.g_next_screen, 0x16)
		return
	if w(0x1768) != 0 or w(S.g_pads_away) == 0:
		set_w(S.g_next_screen, 6)
		return
	set_w(0x176A, 1)
	var item := w(0x18B4)
	if item < 10:
		set_w(S.g_next_screen, ISSRom.u16(rom("menu_data_041012") + item * 2))
		return
	match mode:
		4, 6, 7:
			set_w(S.g_next_screen, 0x1E)
		5, 8:
			set_w(S.g_next_screen, 0x23)
		9:
			set_w(S.g_next_screen, 0x32)
