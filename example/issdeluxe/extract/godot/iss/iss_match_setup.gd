class_name ISSMatchSetup
extends RefCounted
## The bridge from the front end to the match: the menus leave the match
## set up in the game's RAM as the cartridge does (teams, stadium, weather,
## time of day, the teams' state with formation, strategies and handicap,
## the 20 player objects a side with their records, energy and places,
## the controllers), and the match engine takes it as options.

const S := preload("res://iss/iss_sym.gd")
const POSITIONS := ["forward", "midfielder", "defender", "goalkeeper", "attacking type 4", "defensive type 5"]
const ROLES := ["attack", "midfield", "defence", "goalkeeper"]
const ATTRIBUTES := ["speed", "dash", "shot_power", "curl", "intelligence", "balance", "jump", "dribble", "stamina"]


static func _w(a: int) -> int:
	return ISSRam.w(a)


## {"home", "away", "options"} for ISSMatch.start.
static func from_ram() -> Dictionary:
	var home := _w(S.g_team_home)
	var away := _w(S.g_team_away)
	var info := [S.g_team_home_info, S.g_team_away_info]
	var opts := {}
	opts["stadium"] = _w(S.g_stadium)
	opts["weather"] = _w(S.g_weather)
	opts["time_of_day"] = _w(0x1630)
	opts["level"] = _w(S.g_game_level)
	opts["time"] = _w(S.g_game_time)
	opts["referee"] = _w(S.g_officials_kit)
	opts["fouls"] = _w(S.g_opt_fouls_off) == 0
	opts["cards"] = _w(S.g_opt_cards_off) == 0
	opts["offside"] = _w(S.g_opt_offside_off) == 0
	opts["vgoal"] = _w(S.g_opt_vgoal)
	opts["knockout"] = _w(S.g_knockout) != 0
	opts["pads"] = [_w(S.g_pads_home), _w(S.g_pads_away)]
	opts["kits"] = [_w(S.g_kit_home), _w(S.g_kit_away)]
	var formations := []
	var conditions := []
	var players := []
	var keepers := []
	var skills := []
	var strategies := []
	for side in 2:
		var t: int = info[side]
		formations.append(_w(t + ISSModes.TM_FORMATION))
		conditions.append(_w(t + ISSModes.TM_CONDITION))
		players.append(_w(t + ISSModes.TM_PLAYERS) + 7)
		keepers.append(_w(t + ISSModes.TM_KEEPER_MANUAL))
		skills.append(_w(t + ISSModes.TM_KEEPER_SKILL))
		var slots := []
		for i in 4:
			slots.append(ISSRam.sw(t + ISSModes.TM_STRATEGY_SLOTS + 2 * i))
		strategies.append(slots)
	opts["formations"] = formations
	opts["conditions"] = conditions
	opts["players"] = players
	opts["keepers"] = keepers
	opts["keeper_skills"] = skills
	opts["strategies_by_side"] = strategies
	opts["squads"] = [squad(0), squad(1)]
	opts["controllers"] = controllers()
	return {"home": home, "away": away, "options": opts}


## One side's 20 player objects in their order: the squad index (+$56),
## the record (+$5A: nine attributes, number, hair, position), energy
## (+$57) and, for the eleven, the place in the formation (+$51 role, +$52
## / $53 x / y).
static func squad(side: int) -> Array:
	var out := []
	var obj: int = S.g_team_home_players if side == 0 else S.g_team_away_players
	for k in 20:
		var attrs := {}
		for i in ATTRIBUTES.size():
			attrs[ATTRIBUTES[i]] = ISSRam.b(obj + 0x5A + i)
		var e := {
			"index": ISSRam.b(obj + 0x56),
			"attributes": attrs,
			"number": ISSRam.b(obj + 0x63),
			"hair": ISSRam.b(obj + 0x64),
			"position": POSITIONS[clampi(ISSRam.b(obj + 0x65), 0, 5)],
			"energy": ISSRam.b(obj + 0x57),
			"mark": ISSRam.b(obj + 0x54) if ISSRam.b(obj + 0x54) < 0x80 else -1,
		}
		var role := ISSRam.b(obj + 0x51)
		if k < 11 and role < ROLES.size():
			e["slot"] = {"role": ROLES[role], "form_x": ISSRam.b(obj + 0x52), "form_y": ISSRam.b(obj + 0x53)}
		out.append(e)
		obj += ISSModes.PLAYER_SIZE
	return out


## The controllers in pad order: the home side's slots (g_control_slots),
## then the away side's ($15C4): player switch type (+$A), area (+$C),
## cursor change (+$E) and button layout (+$18). The layouts go to ISSInput.
static func controllers() -> Array:
	var out := []
	var pad := 0
	for side in 2:
		var base: int = S.g_control_slots if side == 0 else 0x15C4
		for i in _w(S.g_pads_home if side == 0 else S.g_pads_away):
			var a := base + i * 0x1A
			out.append({"side": side, "type": _w(a + 0xA), "area": _w(a + 0xC), "manual": _w(a + 0xE)})
			if pad < ISSInput.layouts.size():
				ISSInput.layouts[pad] = clampi(_w(a + 0x18) / 16, 0, 23)
			pad += 1
	return out
