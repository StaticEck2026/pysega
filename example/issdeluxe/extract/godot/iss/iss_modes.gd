class_name ISSModes
extends RefCounted
## The game modes' RAM set-up as the main menu starts them (mode_start_*).
## g_game_mode: 0 training, 1 challenge, 2 PK, 3 open game, 4 short league,
## 5 short tournament, 6-8 International Cup rounds, 9 World Series,
## $A Championship, $B demo, $C scenario.

const S := preload("res://iss/iss_sym.gd")


static func _w(a: int, v: int) -> void:
	ISSRam.set_w(a, v)


static func _clear_status(n: int) -> void:
	ISSRam.clear(S.g_player_status, n)


## mode_start_pk: penalty shoot-out, England (0) against team 6 by default.
static func start_pk() -> void:
	_w(S.g_game_mode, 2)
	_w(S.g_knockout, 1)
	_w(0x1276, 0)
	_w(0x126A, 0)
	_w(0x1268, 0)
	_w(0x1264, 2)
	_w(0x1266, 2)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x127C, 0)
	_w(0x127E, 6)
	_clear_status(0x28)
	_w(S.g_shootout_kicks, 0)
	_w(0x14FA, 0)
	_w(0x14FC, 0)
	for i in 10:
		_w(0x1526 + 2 * i, 0xFFFF)
	_w(0x153A, 0)
	_w(0x153C, 0)
	for i in 10:
		_w(0x14FE + 2 * i, 10 - i)
		_w(0x1512 + 2 * i, 10 - i)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)
	_w(S.g_restart_team, 0)


## mode_start_international: the International Cup's elimination round.
static func start_international() -> void:
	_w(S.g_game_mode, 6)
	_w(S.g_knockout, 0)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x127C, 0)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_w(0x1266, 1)
	_clear_status(0x3C)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## mode_start_world_series: season 1 of the World Series.
static func start_world_series() -> void:
	_w(S.g_game_mode, 9)
	_w(S.g_knockout, 1)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x127C, 0)
	_w(0x127E, 0)
	_w(0x1280, 0)
	_w(0x1266, 1)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0x28)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)
	ISSRam.clear(0x129C, 0x48)
	_w(0x126C, 0)
	# The VDP's HV counter & 7: a random 0-7.
	_w(0x126E, randi() & 7)


## mode_start_scenario.
static func start_scenario() -> void:
	_w(S.g_game_mode, 0xC)
	_w(S.g_knockout, 0)
	_w(0x126A, 0)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x1266, 1)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1272, 0xFFFF)
	_clear_status(0x28)
	_w(0x1270, 0)
	ISSRam.clear(0x129C, 0x18)


## mode_start_open_game: open game, England against team 6 by default.
static func start_open_game() -> void:
	_w(S.g_game_mode, 3)
	_w(0x1268, 0)
	_w(0x1276, 0)
	_w(S.g_knockout, 1)
	_w(0x1264, 2)
	_w(0x1266, 2)
	_w(0x127C, 0)
	_w(0x127E, 6)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0x28)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## mode_start_short_league: six teams.
static func start_short_league() -> void:
	_w(S.g_game_mode, 4)
	_w(S.g_knockout, 0)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 6)
	_w(0x127C, 0)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0x78)
	_w(0x153E, 0)
	_w(S.g_pads_home, 0)
	_w(S.g_pads_away, 0)


## mode_start_short_tournament: eight teams.
static func start_short_tournament() -> void:
	_w(S.g_game_mode, 5)
	_w(S.g_knockout, 1)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 8)
	_w(0x127C, 0)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0xA0)
	_w(0x153E, 0)
	_w(S.g_pads_home, 0)
	_w(S.g_pads_away, 0)


# --------------------------------------------------------------------------
# Match set-up in RAM (what the pre-match screens then change).

const TM_KEEPER_MANUAL := 0x10
const TM_AI_LEVEL := 0x12
const TM_RATINGS := 0x1E
const TM_STRATEGY_ON := 0x2A
const TM_STRATEGY_LABEL := 0x2C
const TM_STRATEGY_SLOTS := 0x2E
const TM_FORMATION := 0x5C
const TM_CONDITION := 0x5E
const TM_PLAYERS := 0x60
const TM_KEEPER_SKILL := 0x62
## Player objects (20 a side, $8E bytes): +$4A side, +$51 role (6 = bench),
## +$52 / $53 formation x / y, +$54, +$55-$65 the block the squad screen
## swaps (+$56 squad index, +$57 energy, +$58 stamina drain, +$5A-$65 the
## 12-byte record of tbl_player_data: attributes, ..., position).
const PLAYER_SIZE := 0x8E


## The game's random step: g_random rotated left one bit (rol.w #1), and
## when the bit rotated out is set, exclusive-or $37E8.
static func _rand() -> int:
	var v := ISSRam.w(S.g_random)
	var carry := v & 0x8000
	v = ((v << 1) | (v >> 15)) & 0xFFFF
	if carry:
		v ^= 0x37E8
	ISSRam.set_w(S.g_random, v)
	return v


## rules_input_01487E: both teams' match state (struct team) and their 20
## player objects from g_team_home / g_team_away: handicap defaults,
## strategies cleared, ratings, kits (the second when they clash), kit
## palettes, player records, suspended starters replaced from the bench,
## the teams' own formations, edit points and energy.
static func team_info_init() -> void:
	ISSRam.set_l(0x1814, 0x0001E000)
	ISSRam.set_l(0x1818, ISSRom.addr("misc_data_024000"))
	_w(0x182A, 0)
	_w(0x18B2, 0)
	_w(0x182C, 0)
	_w(0x18B4, 0)
	ISSRam.set_l(0x1896, 0xFF20F6)
	ISSRam.set_l(0x189A, 0xFF20F6)
	ISSRam.set_l(0x189E, 0xFF1FDA)
	ISSRam.set_l(0x18A2, 0xFF2068)
	ISSRam.set_l(0x191E, 0xFF2C0E)
	ISSRam.set_l(0x1922, 0xFF2C0E)
	ISSRam.set_l(0x1926, 0xFF2AF2)
	ISSRam.set_l(0x192A, 0xFF2B80)
	_w(0x1836, 3)
	_w(0x18BE, 3)
	_w(0x1838, 1)
	_w(0x18C0, 1)
	var home := S.g_team_home_info
	var away := S.g_team_away_info
	for t in [home, away]:
		_w(t + TM_KEEPER_MANUAL, 0)
		_w(t + TM_CONDITION, 5)
		_w(t + TM_PLAYERS, 4)
		_w(t + TM_AI_LEVEL, 2)
		_w(t + TM_KEEPER_SKILL, 2)
	var level := ISSRam.w(S.g_game_level)
	if ISSRam.w(S.g_pads_home) == 0:
		_w(home + TM_AI_LEVEL, level)
		_w(home + TM_KEEPER_SKILL, level)
	if ISSRam.w(S.g_pads_away) == 0:
		_w(away + TM_AI_LEVEL, level)
		_w(away + TM_KEEPER_SKILL, level)
	for t in [home, away]:
		_w(t + TM_STRATEGY_ON, 1)
		_w(t + TM_STRATEGY_LABEL, 2)
		for i in 4:
			_w(t + TM_STRATEGY_SLOTS + 2 * i, 0xFFFF)
	var teams := [ISSRam.w(S.g_team_home), ISSRam.w(S.g_team_away)]
	for side in 2:
		var t: int = [home, away][side]
		for i in 5:
			ISSRam.set_b(t + TM_RATINGS + i, ISSRom.u8(ISSRom.addr("tbl_team_ratings") + teams[side] * 5 + i))
	var clash := ISSRom.addr("tbl_kit_clash")
	_w(S.g_kit_home, 0)
	_w(S.g_kit_away, 1 if ISSRom.u16(clash + teams[0] * 2) == ISSRom.u16(clash + teams[1] * 2) else 0)
	var pals := ISSRom.res(6, 12)
	for side in 2:
		var dst: int = [0x185A, 0x18E2][side]
		for i in 32:
			ISSRam.set_b(dst + i, pals[teams[side] * 32 + i])
	for side in 2:
		var rec := ISSRom.u32(ISSRom.addr("tbl_player_data") + teams[side] * 4)
		var status: int = S.g_player_status + ISSRam.w([0x1642, 0x1644][side]) * 20
		var obj: int = [S.g_team_home_players, S.g_team_away_players][side]
		for k in 20:
			for i in 12:
				ISSRam.set_b(obj + 0x5A + i, ISSRom.u8(rec + i))
			rec += 12
			_w(obj + 0x4A, side)
			ISSRam.set_b(obj + 0x56, k)
			var st := ISSRam.b(status + k)
			if st & 0x80 == 0:
				if st == 4:
					ISSRam.set_b(status + k, 0)
			elif st & 7 >= 3:
				ISSRam.set_b(status + k, 4)
			else:
				ISSRam.set_b(status + k, st & 7)
			_w(obj + 0x58, ISSRom.u16(ISSRom.addr("tbl_stamina_drain") + ISSRam.b(obj + 0x62) * 2))
			ISSRam.set_b(obj + 0x55, 0)
			ISSRam.set_b(obj + 0x0F, 0)
			ISSRam.set_b(obj + 0x54, 0xFF)
			obj += PLAYER_SIZE
	for side in 2:
		_replace_suspended(side)
	for side in 2:
		_team_formation(side)
	for side in 2:
		edit_points_reset(side)
	_energy()
	_w(0x1544, 0)
	_w(0x1546, 0)


## rules_func_014D3E / 014D64: the side's points for the edit player screen
## (tbl_edit_points, 999 with code 3), all (tm +$14) and left (+$16).
static func edit_points_reset(side: int) -> void:
	var team := ISSRam.w([S.g_team_home, S.g_team_away][side])
	var v := 999 if ISSRam.w(0x125C) != 0 else ISSRom.u16(ISSRom.addr("tbl_edit_points") + team * 2)
	var t: int = [S.g_team_home_info, S.g_team_away_info][side]
	_w(t + 0x14, v)
	_w(t + 0x16, v)


## rules_input_01487E_1 / _2: a suspended starter (status 4) changes
## places with the first available substitute of his position (or the last
## available one).
static func _replace_suspended(side: int) -> void:
	var status: int = S.g_player_status + ISSRam.w([0x1642, 0x1644][side]) * 20
	var base: int = [S.g_team_home_players, S.g_team_away_players][side]
	for k in range(1, 11):
		var a4 := base + k * PLAYER_SIZE
		if ISSRam.b(status + k) != 4:
			continue
		var a0 := -1
		var a3 := base + 12 * PLAYER_SIZE
		for i in 8:
			if ISSRam.b(status + ISSRam.b(a3 + 0x56)) != 4:
				a0 = a3
				if ISSRam.b(a0 + 0x65) == ISSRam.b(a4 + 0x65):
					break
			a3 += PLAYER_SIZE
		if a0 < 0:
			continue
		for i in 0x11:
			var t := ISSRam.b(a4 + 0x55 + i)
			ISSRam.set_b(a4 + 0x55 + i, ISSRam.b(a0 + 0x55 + i))
			ISSRam.set_b(a0 + 0x55 + i, t)


## rules_func_014C9A / 014CEC: the team's own formation (tbl_team_formations)
## and the starters' places in it; the bench has role 6.
static func _team_formation(side: int) -> void:
	var team := ISSRam.w([S.g_team_home, S.g_team_away][side])
	var a := ISSRom.u32(ISSRom.addr("tbl_team_formations") + team * 4)
	_w([S.g_team_home_info, S.g_team_away_info][side] + TM_FORMATION, ISSRom.s8(a))
	a += 1
	var obj: int = [S.g_team_home_players, S.g_team_away_players][side]
	for k in 20:
		if k < 11:
			ISSRam.set_b(obj + 0x52, ISSRom.u8(a))
			ISSRam.set_b(obj + 0x53, ISSRom.u8(a + 1))
			ISSRam.set_b(obj + 0x51, ISSRom.u8(a + 2))
			a += 3
		else:
			ISSRam.set_b(obj + 0x52, 0)
			ISSRam.set_b(obj + 0x53, 0)
			ISSRam.set_b(obj + 0x51, 6)
		obj += PLAYER_SIZE


## rules_func_014D8A: each player's energy from the team's condition, or
## at random from [1, 2, 2, 3, 3, 3, 4, 4] for condition 5.
static func _energy() -> void:
	var tbl := ISSRom.addr("tbl_random_condition")
	for side in 2:
		var cond := ISSRam.w([S.g_team_home_info, S.g_team_away_info][side] + TM_CONDITION)
		var obj: int = [S.g_team_home_players, S.g_team_away_players][side]
		for k in 20:
			if cond != 5:
				ISSRam.set_b(obj + 0x57, cond)
			else:
				ISSRam.set_b(obj + 0x57, ISSRom.u8(tbl + (_rand() & 7)))
			obj += PLAYER_SIZE


## match_stats_clear.
static func match_stats_clear() -> void:
	_w(S.g_training, 0)
	_w(S.g_no_restarts, 0)
	for a in [S.g_stats_home, 0x1650, 0x1652, 0x1654, 0x1656, 0x1658, 0x165A, S.g_score_home,
			S.g_stats_away, 0x1660, 0x1662, 0x1664, 0x1666, 0x1668, 0x166A, S.g_score_away]:
		_w(a, 0)


## The clock at the start of the first half: 2 * g_game_time + 1 minutes.
static func _clock_start() -> void:
	_w(S.g_half, 0)
	_w(S.g_restart_timer, 0)
	ISSRam.set_l(S.g_match_clock, 0)
	ISSRam.set_b(S.g_match_clock, ISSRam.w(S.g_game_time) * 2 + 1)


## menu_func_05AEAC: an open game (and the scenarios, the PK code ...):
## kick-off sides at random, stadium 0 in fine weather, the referee (3 =
## any of the three), a random time of day ($1630), the game time from
## the options, then the teams.
static func open_game_setup() -> void:
	_w(0x1638, 0)
	_w(0x1634, randi() & 1)
	_w(S.g_left_goal_team, 0)
	_w(S.g_restart_type, 4)
	_w(S.g_stadium, 0)
	_w(S.g_weather, 1)
	var ref := ISSRam.w(S.g_opt_referee)
	_w(S.g_officials_kit, randi() % 3 if ref == 3 else ref)
	_w(0x1630, randi() % 3)
	_w(S.g_game_time, ISSRam.w(S.g_opt_time))
	_clock_start()
	match_stats_clear()
	_w(S.g_team_home, ISSRam.w(0x127C))
	_w(S.g_team_away, ISSRam.w(0x127E))
	_w(0x1642, 0)
	_w(0x1644, 1)
	team_info_init()


## menu_state_03E8F0_2: training, the chosen team against the practice team
## ($2A, second kit) in stadium 0, restart 12 (the drill).
static func training_setup() -> void:
	_w(S.g_training_drill, 0)
	_w(0x1638, 0)
	_w(0x1634, 0)
	_w(S.g_left_goal_team, 0)
	_w(S.g_restart_type, 0xC)
	_w(S.g_team_home, ISSRam.w(0x127C))
	_w(S.g_team_away, 0x2A)
	_w(0x1642, 0)
	_w(S.g_stadium, 0)
	_w(S.g_weather, 1)
	_w(S.g_game_time, 0)
	_w(S.g_training, 1)
	team_info_init()
	_w(S.g_kit_away, 1)


## menu_state_03E8F0_3: PK, the two chosen teams in stadium 0.
static func pk_setup() -> void:
	_w(S.g_team_home, ISSRam.w(0x127C))
	_w(S.g_team_away, ISSRam.w(0x127E))
	_w(0x1642, 0)
	_w(0x1644, 1)
	_w(S.g_stadium, 0)
	_w(S.g_weather, 1)
	_w(0x1638, 0)
	_w(0x17D8, 0)
	team_info_init()


# --------------------------------------------------------------------------
# After the match.

## Where the game goes when the match is over (screen_match_stats_2 at the end,
## state_shootout_frame_14 after a shoot-out): the main menu, or the game
## mode's own screen once its tables have the result (the league's
## fixtures, the tournament's bracket, the cup's rounds, the World Series,
## the championship). Leagues and group rounds have no shoot-outs.
static func after_match(shootout: bool) -> void:
	ISSRam.set_l(S.g_next_state, ISSMenu.STATE_MENU)
	_w(S.g_next_screen, 0)
	match ISSRam.w(S.g_game_mode):
		4:
			if not shootout:
				menu_func_05B150()
				_w(S.g_next_screen, 0x1D)
		5:
			menu_func_05B58C()
			_w(S.g_next_screen, 0x22)
		6:
			if not shootout:
				menu_func_05B966()
				_w(S.g_next_screen, 0x29)
		7:
			if not shootout:
				menu_func_05BE12()
				_w(S.g_next_screen, 0x2B)
		8:
			menu_func_05C2A2()
			_w(S.g_next_screen, 0x2D)
		9:
			_w(S.g_next_screen, 0x30)
		0xA:
			menu_func_05D124()
			menu_func_05D13C()
			_w(S.g_next_screen, 0x33 if ISSRam.w(0x1272) == 0 else 0x27)


## shootout_start: the shoot-out after extra time: out of the match ($1638),
## no kicks yet, the takers' places ($1526) free, nought each, both orders
## 10, 9 ... 1, the home side first.
static func shootout_start() -> void:
	_w(0x1638, 0)
	_w(S.g_shootout_kicks, 0)
	_w(0x14FA, 0)
	_w(0x14FC, 0)
	for i in 10:
		_w(0x1526 + 2 * i, 0xFFFF)
	_w(0x153A, 0)
	_w(0x153C, 0)
	for i in 10:
		_w(0x14FE + 2 * i, 10 - i)
		_w(0x1512 + 2 * i, 10 - i)
	_w(S.g_restart_team, 0)


# The competitions' result bookkeeping; ported with their screens.

static func menu_func_05B150() -> void:
	push_error("ISSModes.menu_func_05B150 is not ported yet")


static func menu_func_05B58C() -> void:
	push_error("ISSModes.menu_func_05B58C is not ported yet")


static func menu_func_05B966() -> void:
	push_error("ISSModes.menu_func_05B966 is not ported yet")


static func menu_func_05BE12() -> void:
	push_error("ISSModes.menu_func_05BE12 is not ported yet")


static func menu_func_05C2A2() -> void:
	push_error("ISSModes.menu_func_05C2A2 is not ported yet")


static func menu_func_05D124() -> void:
	push_error("ISSModes.menu_func_05D124 is not ported yet")


static func menu_func_05D13C() -> void:
	push_error("ISSModes.menu_func_05D13C is not ported yet")


static func mode_start_championship() -> void:
	push_error("ISSModes.mode_start_championship is not ported yet")


static func match_setup_random() -> void:
	push_error("ISSModes.match_setup_random is not ported yet")


# The main menu's code 4 shortcuts (straight to a competition's last round);
# ported with the competitions.

static func international_finals() -> void:
	push_error("ISSModes.international_finals is not ported yet")


static func menu_input_05C16E() -> void:
	push_error("ISSModes.menu_input_05C16E is not ported yet")


static func menu_func_05C404() -> void:
	push_error("ISSModes.menu_func_05C404 is not ported yet")


static func menu_func_05C4FE() -> void:
	push_error("ISSModes.menu_func_05C4FE is not ported yet")


static func menu_func_05AEAC() -> void:
	push_error("ISSModes.menu_func_05AEAC is not ported yet")


## menu_input_040F5E: where a pre-match sub-screen returns. Training and
## challenges have their own menus; with humans on both sides the home
## side's choice is followed by the away side's on the same item
## ($176A = 1, the item through tbl_prematch_screens), or after the last
## item the competition's own screen; otherwise the pre-match menu.
static func prematch_return() -> void:
	var mode := ISSRam.w(S.g_game_mode)
	if mode == 0:
		_w(S.g_next_screen, 0x19)
		return
	if mode == 1:
		_w(S.g_next_screen, 0x16)
		return
	if ISSRam.w(0x1768) != 0 or ISSRam.w(S.g_pads_away) == 0:
		_w(S.g_next_screen, 6)
		return
	_w(0x176A, 1)
	var item := ISSRam.w(0x18B4)
	if item < 10:
		_w(S.g_next_screen, ISSRom.u16(ISSRom.addr("tbl_prematch_screens") + item * 2))
		return
	match mode:
		4, 6, 7:
			_w(S.g_next_screen, 0x1E)
		5, 8:
			_w(S.g_next_screen, 0x23)
		9:
			_w(S.g_next_screen, 0x32)
