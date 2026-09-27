class_name ISSMatchEngine
extends RefCounted
## The match, without any drawing: both teams, the ball, the referee's rules
## (match_rules_update) and the restart scripts run by the g_director object
## (tbl_restart_setup). step() is one 60 Hz frame of state_match_frame:
## controllers -> AI scheduling and team analysis -> every player's update ->
## the ball -> the referee. The view (ISSMatch) draws the state and turns the
## signals into sound, commentary and banners, so the same engine also runs
## headless (iss_selftest.gd plays whole matches with it).

signal sound(id: int)
signal speech(id: int)
signal banner(message: String)
signal banner_off
signal goal_scored(side: int, scorer: ISSFootballer, own_goal: bool)
signal finished

## g_restart_type; OFFSIDE is the offside branch of restart 5.
enum R { NONE = -1, THROW_IN, GOAL_KICK, CORNER, KICKOFF, MATCH_START, FREE_KICK, PENALTY,
	PENALTY_SPOT, OWN_GOAL, HALF_TIME, TIME_UP, GOAL, OFFSIDE = 20 }

var ball := ISSBall.new()
var teams: Array[ISSTeam] = []
var rect := Rect2()
var mid := Vector2.ZERO
var stadium := 0
var weather := 1
var options := {}
var referee_kit := 1

## Team defending the left goal (g_left_goal_team); ends swap at half time.
var left_goal_team := 0
var kickoff_side := 0
var frame := 0
var half := 0
var half_frames := 0
## Frames left in the half (g_match_clock).
var clock := 0
var over := false
var scorers: Array = []
var said_rush := false

var restart_type := R.NONE
var restart_side := 0
var restart_pos := Vector2.ZERO
var restart_phase := 0
var restart_timer := 0
var restart_taker: ISSFootballer = null
var restart_after := R.NONE
var ball_entered := true
var offside_side := -1

var referee_pos := Vector2.ZERO
var linesman_pos := Vector2.ZERO
var event_counts := {}


## options: stadium 0-7, weather 0 snow / 1 fine / 2 rain, time 1-3 (minutes
## per half = 2 * time + 1), level 0-4, fouls, cards, offside (bools),
## referee 0-3 (3 = random), pads [home, away] (0 = CPU), half_seconds
## (optional override of the half length).
func setup(home: int, away: int, opts: Dictionary) -> void:
	ISSMatchData.ensure_loaded()
	options = opts
	stadium = int(opts.get("stadium", 0))
	weather = int(opts.get("weather", 1))
	ball.weather = weather
	referee_kit = int(opts.get("referee", 1))
	if referee_kit == 3:
		referee_kit = randi() % 3
	rect = ISSMatchData.pitch_rect(stadium)
	mid = rect.get_center()
	var level := int(opts.get("level", 2))
	var pads: Array = opts.get("pads", [1, 0])
	var clash_home := int(ISSMatchData.teams[home]["kit_clash"])
	var clash_away := int(ISSMatchData.teams[away]["kit_clash"])
	for s in 2:
		var t := ISSTeam.new()
		var human: bool = int(pads[s]) > 0
		t.setup(self, s, home if s == 0 else away, 2 if human else level,
			s == 1 and (home == away or clash_home == clash_away))
		t.pads = int(pads[s])
		teams.append(t)
	var minutes := 2 * int(opts.get("time", 2)) + 1
	half_frames = int(opts.get("half_seconds", minutes * 60)) * 60
	clock = half_frames
	left_goal_team = 0
	kickoff_side = randi() % 2
	for t in teams:
		t.reset_lines()
	_place_for_kickoff(kickoff_side)
	referee_pos = mid + Vector2(-48, 64)
	linesman_pos = Vector2(mid.x, rect.position.y - 20)
	start_restart(R.MATCH_START, kickoff_side, mid)


## Break the engine / team / player references so that everything is freed.
func dispose() -> void:
	for t in teams:
		for p in t.players:
			p.eng = null
			p.kick_target = null
		t.players.clear()
		t.eng = null
		t.controlled = null
		t.nearest = null
		t.second = null
		t.front = null
		t.back = null
		t.cover = null
	teams.clear()
	ball.owner = null
	ball.kicker = null
	ball.last_touch = null
	restart_taker = null


# ---------------------------------------------------------------------------
# Geometry.

## +1 when the side attacks toward +x (it defends the left goal).
func attack_dir(side: int) -> float:
	return 1.0 if side == left_goal_team else -1.0


func goal_center(side: int) -> Vector2:
	return Vector2(rect.position.x if side == left_goal_team else rect.end.x, mid.y)


func goal_heading(p: ISSFootballer) -> float:
	var g := goal_center(1 - p.team) + Vector2(0, (randf() * 2.0 - 1.0) * 60.0)
	return ISSFootballer.heading_to(p.pos, g)


## Where the ball will be played from next: its landing point while in the
## air (obj_target_x of the ball), else where it is.
func ball_target() -> Vector2:
	if ball.owner == null and ball.z > 8.0:
		return ball.landing()[0]
	return ball.pos


func in_own_box(p: ISSFootballer) -> bool:
	var g := goal_center(p.team)
	return absf(p.pos.x - g.x) < 256.0 and absf(p.pos.y - g.y) < 220.0


func emit_sound(id: int) -> void:
	sound.emit(id)


func say(id: int) -> void:
	speech.emit(id)


func stats_shot_on_target(_side: int) -> void:
	pass


func all_players() -> Array[ISSFootballer]:
	var out: Array[ISSFootballer] = []
	for t in teams:
		out.append_array(t.active())
	return out


# ---------------------------------------------------------------------------
# One frame. pads[side] = {"dir": -1 or 0-63, "press": bits, "held": bits}.

func step(pads: Array = []) -> void:
	if over:
		return
	frame += 1
	var slot := frame & 15
	# Formation lines: one role per frame, home on slots 0-3, away on 4-7.
	var order: Array = ISSMatchData.consts["team_lines"]["order"]
	teams[(slot >> 2) & 1].update_line(int(order[slot & 3]))
	for t in teams:
		t.analyse()
	for t in teams:
		var pad: Dictionary = pads[t.side] if t.side < pads.size() and pads[t.side] != null else {}
		_control(t, pad)
		for p in t.active():
			if p.human:
				continue
			p.press = 0
			if slot == p.index:
				t.think(p)
			if p.state == ISSFootballer.S.KEEPER_HOLD:
				t.keeper_distribute(p)
			elif p.state == ISSFootballer.S.SET_PIECE:
				_cpu_set_piece(p)
			else:
				t.steer(p)
		if t.has_ball():
			t.stats["possession"] += 1
	for p in all_players():
		p.step()
	ball.step()
	_contacts()
	_bounds()
	if restart_type == R.NONE and ball.live:
		_check_out()
	_clock()
	_director()
	_officials()


## Human control: the pad drives the team's controlled player.
func _control(t: ISSTeam, pad: Dictionary) -> void:
	for p in t.players:
		p.human = false
	if t.pads == 0:
		t.controlled = null
		return
	var c := t.controlled
	var owner := ball.owner
	if owner != null and owner.team == t.side:
		c = owner
	elif restart_taker != null and restart_taker.team == t.side and restart_phase == 1:
		c = restart_taker
	elif c == null or c.state == ISSFootballer.S.SENT_OFF or c.is_keeper():
		c = t.nearest
	elif int(pad.get("press", 0)) & ISSFootballer.SWITCH:
		c = _nearest_to_ball(t, c)
	elif frame % 16 == 0 and (owner == null or owner.team != t.side) and t.nearest != null and t.nearest != c:
		var tgt := ball_target()
		if (c.pos - tgt).length() - (t.nearest.pos - tgt).length() > 48.0:
			c = t.nearest
	t.controlled = c
	if c == null:
		return
	# During a restart only the taker is the human's; the rest walk into place.
	if restart_type != R.NONE and c != restart_taker:
		return
	c.human = true
	c.input_dir = int(pad.get("dir", -1))
	c.press |= int(pad.get("press", 0))
	c.held = int(pad.get("held", 0))


func _nearest_to_ball(t: ISSTeam, not_this: ISSFootballer) -> ISSFootballer:
	var best: ISSFootballer = null
	var best_d := INF
	for p in t.active():
		if p == not_this or p.is_keeper():
			continue
		var d := (p.pos - ball.pos).length()
		if d < best_d:
			best_d = d
			best = p
	return best if best != null else not_this


# ---------------------------------------------------------------------------
# Ball contacts.

func _contacts() -> void:
	if not ball.live:
		return
	if ball.owner != null:
		_steals()
		return
	var best: ISSFootballer = null
	var best_d := INF
	for p in all_players():
		if not p.can_touch_ball():
			continue
		if p.state == ISSFootballer.S.SLIDE:
			continue # slide_contact handles it
		var dz := ball.z - p.z
		var reach := 10.0
		var top := 36.0
		if p.is_keeper() and in_own_box(p):
			reach = 14.0 + float(teams[p.team].keeper_skill)
			top = 56.0
		if dz < -4.0 or dz >= top:
			continue
		var d := (ball.pos - p.pos).length()
		if d < reach and d < best_d:
			best_d = d
			best = p
	if best != null:
		_touch(best)


func _touch(p: ISSFootballer) -> void:
	var b := ball
	if offside_side >= 0:
		if p.team == offside_side and p.offside and bool(options.get("offside", true)):
			_clear_offside()
			teams[p.team].stats["offsides"] += 1
			start_restart(R.OFFSIDE, 1 - p.team, p.pos)
			return
		_clear_offside()
	var keeper_catch := p.is_keeper() and in_own_box(p)
	var c: Dictionary = ISSMatchData.consts["ball"]
	if b.speed + b.vz > float(c["deflect_speed"]) and not keeper_catch:
		# ball_in_reach: too fast to control, it comes off the player.
		b.heading = fposmod(b.heading + 32.0 + float(randi() % 16 - 8), 64.0)
		b.speed /= 2.0
		b.vz -= b.vz / 4.0
		b.team = p.team
		b.last_touch = p
		b.kicker = p
		b.kick_cooldown = 8
		emit_sound(0x5A)
		return
	b.owner = p
	b.team = p.team
	b.last_touch = p
	b.kicker = null
	b.stop()
	said_rush = false
	p.ai_turns = 0
	p.protect = 24
	if keeper_catch:
		p.start_hold(true)
		emit_sound(0x5A)
	elif b.z > 12.0 or b.speed > 3.0:
		p.set_state(ISSFootballer.S.TRAP, ISSFootballer.A_TRAP, 10)


## Standing challenges: an opponent at the ball can knock it loose.
func _steals() -> void:
	var o := ball.owner
	if o.holding_in_hands() or o.protect > 0 or restart_type != R.NONE:
		return
	if frame % 6 != 0:
		return
	for p in teams[1 - o.team].active():
		if p.busy() or p.is_keeper() and not in_own_box(p):
			continue
		if (p.pos - ball.pos).length() > 9.0:
			continue
		var level := teams[p.team].ai_level if not p.human else 2
		var chance := 0.3 + 0.04 * float(p.a("balance") - o.a("dribble")) + 0.03 * float(level - 2)
		if randf() < chance:
			ball.owner = null
			ball.launch(p, p.facing + float(randi() % 9 - 4), 1.5 + p.speed * 0.4, 0.3)
			ball.kick_cooldown = 4
			o.stumble()
			emit_sound(0x58)
		else:
			p.protect = 12
		return


## A sliding tackle meeting the ball or a player (player_slide).
func slide_contact(s: ISSFootballer) -> void:
	var foot := s.pos + ISSProjection.heading_vector(s.facing) * 6.0
	var b := ball
	var hits_ball := b.live and b.z < 16.0 and (b.pos - foot).length() < 12.0
	if b.owner != null and (b.owner.team == s.team or b.owner.holding_in_hands()):
		hits_ball = false
	if hits_ball:
		var victim := b.owner
		b.owner = null
		b.launch(s, s.facing + float(randi() % 9 - 4), 1.5 + s.speed * 0.5, 0.5)
		if victim != null:
			victim.stumble()
		s.timer = maxi(s.timer, 27)
		_clear_offside()
		emit_sound(0x58)
		return
	for o in teams[1 - s.team].active():
		if o.state not in [ISSFootballer.S.MOVE, ISSFootballer.S.KICK, ISSFootballer.S.TRAP]:
			continue
		if (o.pos - foot).length() > 10.0:
			continue
		var from_behind := absf(ISSFootballer.angle_diff(s.facing, o.facing)) < 16.0
		var had_ball := b.owner == o or (b.pos - o.pos).length() < 40.0
		o.knock_over(s.facing)
		s.timer = maxi(s.timer, 27)
		if had_ball or from_behind:
			_foul(s, o, from_behind)
		return


func _foul(fouler: ISSFootballer, victim: ISSFootballer, severe: bool) -> void:
	if not bool(options.get("fouls", true)) or restart_type != R.NONE or not ball.live:
		return
	var strict: Array = ISSMatchData.consts["referee_strictness"][referee_kit]
	if int(strict[randi() & 3]) == 0:
		return # the referee did not see it
	teams[fouler.team].stats["fouls"] += 1
	emit_sound(0x48)
	var own_goal_x := goal_center(fouler.team).x
	var penalty := absf(victim.pos.x - own_goal_x) < float(ISSMatchData.consts["penalty_distance"])
	if bool(options.get("cards", true)) and (severe and randi() % 2 == 0 or randi() % 5 == 0):
		if fouler.booked:
			_send_off(fouler)
			banner.emit("red_card")
			teams[fouler.team].stats["red"] += 1
		else:
			fouler.booked = true
			banner.emit("yellow_card")
			teams[fouler.team].stats["yellow"] += 1
		say(0x29)
	if ball.owner != null:
		ball.owner = null
	if penalty:
		teams[victim.team].stats["penalties"] += 1
		start_restart(R.PENALTY, victim.team, goal_center(fouler.team) + Vector2(attack_dir(victim.team) * -256.0, 0))
	else:
		teams[victim.team].stats["free_kicks"] += 1
		start_restart(R.FREE_KICK, victim.team, victim.pos)


func _send_off(p: ISSFootballer) -> void:
	if ball.owner == p:
		ball.owner = null
	p.set_state(ISSFootballer.S.SENT_OFF, ISSFootballer.A_STAND)
	p.pos = Vector2(mid.x, rect.position.y - 200.0)


## The goalkeeper's hands during a dive.
func keeper_reach(k: ISSFootballer) -> void:
	var b := ball
	if b.kicker == k:
		return
	var skill := float(teams[k.team].keeper_skill)
	var d := (b.pos - k.pos).length()
	# The diving body lies from the ground to about 40 px above his height.
	var dz := b.z - k.z
	if d > 16.0 + skill * 2.0 or dz < -28.0 or dz > 40.0:
		return
	if b.speed < 5.0 + skill * 0.5 or randf() < 0.35 + skill * 0.1:
		event_counts["saves"] = int(event_counts.get("saves", 0)) + 1
		_clear_offside()
		b.owner = k
		b.team = k.team
		b.last_touch = k
		b.stop()
		emit_sound(0x6A)
		say(0x0A)
	else:
		# Parried: pushed away from the goal.
		event_counts["parries"] = int(event_counts.get("parries", 0)) + 1
		var away := goal_center(k.team).direction_to(b.pos)
		b.launch(k, ISSFootballer.heading_to(Vector2.ZERO, away) + float(randi() % 17 - 8), b.speed * 0.4, 1.0, b.z)
		emit_sound(0x5A)


## A header or volley (ball_launch_shot / a header pass).
func head_ball(p: ISSFootballer) -> void:
	var b := ball
	_clear_offside()
	if p.kick_kind == ISSFootballer.K.SHOT:
		var r: Array = ISSMatchData.kick("rising")[clampi(4 + p.a("jump") / 2, 0, 8)]
		b.launch(p, goal_heading(p), float(r[0]) * 1.5, float(r[1]) * 0.3, b.z)
		teams[p.team].stats["shots"] += 1
		emit_sound(0x57)
		if randi() % 3 == 0:
			say(0x0E)
	else:
		b.launch(p, p.kick_heading, 3.0, 1.5, b.z)
		emit_sound(0x56)
	_mark_offside(p)
	_auto_switch(p)


## The ball leaves the kicker's foot (or hands).
func kick_ball(p: ISSFootballer) -> void:
	var b := ball
	if b.owner != p:
		return
	var h := p.kick_heading
	var power := clampi(p.kick_power, 0, 8)
	var target := p.kick_target
	var kind := p.kick_kind
	if p.human and target == null and kind in [ISSFootballer.K.PASS, ISSFootballer.K.LOFT, ISSFootballer.K.THROW_IN, ISSFootballer.K.KEEPER_THROW, ISSFootballer.K.KICKOFF]:
		target = _assist(p, h)
		if target != null:
			var lead := target.pos + ISSProjection.heading_vector(target.facing) * target.speed * 10.0
			h = ISSFootballer.heading_to(p.pos, lead)
			if kind == ISSFootballer.K.LOFT:
				power = teams[p.team]._lofted_power((lead - p.pos).length())
	var spd := 0.0
	var v := 0.0
	var z0 := 0.0
	var sfx := 0x56
	var bonus := float(p.a("shot_power") + ISSMatchData.position_bonus(p.position))
	match kind:
		ISSFootballer.K.PASS, ISSFootballer.K.KICKOFF:
			var k: Array = ISSMatchData.kick("pass")
			spd = float(k[0]) * (0.7 if kind == ISSFootballer.K.KICKOFF else 1.0)
			v = float(k[1])
			if target != null and (target.pos - p.pos).length() < 90.0:
				spd *= 0.8
		ISSFootballer.K.LOFT, ISSFootballer.K.PUNT:
			var k: Array = ISSMatchData.kick("lofted")[power]
			spd = float(k[0])
			v = float(k[1])
			sfx = 0x54
			if kind == ISSFootballer.K.PUNT:
				z0 = 12.0
		ISSFootballer.K.SHOT, ISSFootballer.K.DRIVE:
			if kind == ISSFootballer.K.SHOT and p.human:
				h = _human_shot_heading(p, h)
			var k: Array = ISSMatchData.kick("drive")
			var r: Array = ISSMatchData.kick("rising")[power]
			spd = float(k[0]) + 0.12 * bonus
			v = float(r[1]) * (0.35 if kind == ISSFootballer.K.SHOT else 0.6)
			sfx = 0x57
			if kind == ISSFootballer.K.SHOT or restart_type == R.PENALTY:
				teams[p.team].stats["shots"] += 1
				if randi() % 3 == 0:
					say(0x0E)
		ISSFootballer.K.THROW_IN:
			spd = 3.0
			v = 1.2
			z0 = 20.0
		ISSFootballer.K.KEEPER_THROW:
			spd = 3.2
			v = 1.2
			z0 = 16.0
	b.launch(p, h, spd, v, z0)
	emit_sound(sfx)
	var was := restart_type
	if restart_type != R.NONE and restart_phase == 1 and p == restart_taker:
		restart_type = R.NONE
		restart_taker = null
		restart_phase = 0
	# No offside from throw-ins, goal kicks and corners.
	if was not in [R.THROW_IN, R.GOAL_KICK, R.CORNER] and kind != ISSFootballer.K.SHOT:
		_mark_offside(p)
	_auto_switch(p)


## A human's shot goes at the goal when he faces it: up or down on the pad
## picks the near or far post side, otherwise the middle.
func _human_shot_heading(p: ISSFootballer, h: float) -> float:
	var g := goal_center(1 - p.team)
	var at_goal := ISSFootballer.heading_to(p.pos, g)
	if absf(ISSFootballer.angle_diff(at_goal, p.facing)) > 16.0:
		return h
	var aim := g.y + (randf() * 2.0 - 1.0) * 24.0
	if p.input_dir >= 0:
		var v := ISSProjection.heading_vector(p.input_dir)
		if absf(v.y) > 0.3:
			aim = g.y + signf(v.y) * (56.0 + randf() * 24.0)
	var spread := (100.0 - float(p.a("shot_power")) * 6.0) * (g - p.pos).length() / 800.0
	return ISSFootballer.heading_to(p.pos, Vector2(g.x, aim + (randf() * 2.0 - 1.0) * spread))


## Pass assist: the team-mate closest to the aimed direction.
func _assist(p: ISSFootballer, h: float) -> ISSFootballer:
	var best: ISSFootballer = null
	var best_score := INF
	for m in teams[p.team].active():
		if m == p or m.is_keeper():
			continue
		var off := m.pos - p.pos
		var dist := off.length()
		if dist > 520.0:
			continue
		var ang := absf(ISSFootballer.angle_diff(ISSFootballer.heading_to(p.pos, m.pos), h))
		if ang > 10.0:
			continue
		var score := ang * 12.0 + dist * 0.3
		if score < best_score:
			best_score = score
			best = m
	return best


## After a human team kicks, control moves to the team-mate nearest to where it lands.
func _auto_switch(p: ISSFootballer) -> void:
	var t := teams[p.team]
	if t.pads == 0:
		return
	var land: Vector2 = ball.landing()[0]
	var best: ISSFootballer = null
	var best_d := INF
	for m in t.active():
		if m == p or m.is_keeper():
			continue
		var d := (m.pos - land).length()
		if d < best_d:
			best_d = d
			best = m
	if best != null:
		t.controlled = best


## Offside (match_rules_update): when a pass is played, the team's players
## beyond the opponents' last defender (16 px tolerance), in the opponents'
## half and ahead of the ball are flagged; the first flagged one to touch
## the ball is offside.
func _mark_offside(p: ISSFootballer) -> void:
	_clear_offside()
	var t := teams[p.team]
	var o := teams[1 - p.team]
	var d := attack_dir(p.team)
	var last := -INF
	for q in o.active():
		if q.is_keeper():
			continue
		last = maxf(last, q.pos.x * d)
	if last == -INF:
		return
	var any := false
	for m in t.active():
		if m == p:
			continue
		var x := m.pos.x * d
		if x > last + 16.0 and x > mid.x * d and x > ball.pos.x * d:
			m.offside = true
			any = true
	if any:
		offside_side = p.team


func _clear_offside() -> void:
	if offside_side < 0:
		return
	for m in teams[offside_side].players:
		m.offside = false
	offside_side = -1


# ---------------------------------------------------------------------------
# Out of play, goals, posts and the bar.

func _bounds() -> void:
	var r := rect.grow(48.0)
	for p in all_players():
		p.pos = p.pos.clamp(r.position, r.end)


func _check_out() -> void:
	var b := ball
	var g: Dictionary = ISSMatchData.consts["goal"]
	var rs: Dictionary = ISSMatchData.consts["restart"]
	# A throw-in starts outside the pitch: the ball is only out once it has
	# been back in (or if it dies outside).
	if not ball_entered:
		if rect.has_point(b.pos):
			ball_entered = true
		elif b.owner != null or b.speed > 0.2 or b.z > 0.0:
			return
	if b.pos.y < rect.position.y or b.pos.y > rect.end.y:
		_release()
		var y := rect.position.y - float(rs["throw_in_outside"]) if b.pos.y < rect.position.y else rect.end.y + float(rs["throw_in_outside"])
		var x := clampf(b.pos.x, rect.position.x + float(rs["throw_in_clamp"]), rect.end.x - float(rs["throw_in_clamp"]))
		emit_sound(0x59)
		start_restart(R.THROW_IN, 1 - b.team, Vector2(x, y))
		return
	if b.pos.x >= rect.position.x and b.pos.x <= rect.end.x:
		return
	var left := b.pos.x < rect.position.x
	var defending := left_goal_team if left else 1 - left_goal_team
	var dy := absf(b.pos.y - mid.y)
	var line_x := rect.position.x if left else rect.end.x
	if dy < float(g["post_inner"]) and b.z < float(g["bar"]):
		_goal(defending)
		return
	if dy < float(g["post_outer"]) and b.z < float(g["bar_top"]):
		# Post or bar: back into play.
		_release()
		b.heading = fposmod(64.0 - b.heading, 64.0)
		b.speed *= 0.6
		if b.z >= float(g["bar"]):
			b.vz = -absf(b.vz) * 0.5
		b.pos.x = line_x + (2.0 if left else -2.0)
		emit_sound(0x4B)
		return
	_release()
	var rsx := float(rs["goal_kick_x"])
	if b.team == defending:
		var cy := rect.position.y + float(rs["corner_inside"]) if b.pos.y < mid.y else rect.end.y - float(rs["corner_inside"])
		var cx := line_x + (float(rs["corner_inside"]) if left else -float(rs["corner_inside"]))
		teams[1 - defending].stats["corners"] += 1
		start_restart(R.CORNER, 1 - defending, Vector2(cx, cy))
	else:
		var gy := mid.y + (float(rs["goal_kick_y"]) if b.pos.y > mid.y else -float(rs["goal_kick_y"]))
		start_restart(R.GOAL_KICK, defending, Vector2(line_x + (rsx if left else -rsx), gy))


func _release() -> void:
	if ball.owner != null:
		var o := ball.owner
		ball.owner = null
		ball.speed = o.speed


func _goal(defending: int) -> void:
	_release()
	var scorer := ball.last_touch
	var own := scorer != null and scorer.team == defending
	var side := 1 - defending
	teams[side].score += 1
	teams[side].stats["goals"] += 1
	var minute := (half_frames - clock) / 3600 + half * (half_frames / 3600)
	scorers.append({"side": side, "name": scorer.name if scorer != null else "", "minute": minute, "own_goal": own})
	goal_scored.emit(side, scorer, own)
	for p in teams[side].active():
		if not p.is_keeper():
			p.celebrate()
	for p in teams[defending].active():
		p.deject()
	start_restart(R.OWN_GOAL if own else R.GOAL, defending, mid)


# ---------------------------------------------------------------------------
# Clock (g_match_clock) and halves.

func _clock() -> void:
	if restart_type in [R.GOAL, R.OWN_GOAL, R.HALF_TIME, R.TIME_UP, R.KICKOFF, R.MATCH_START]:
		return
	if clock > 0:
		clock -= 1
		return
	if restart_type == R.NONE and ball.live:
		_release()
		start_restart(R.HALF_TIME if half == 0 else R.TIME_UP, 0, ball.pos)


func clock_seconds() -> float:
	return float(clock) / 60.0


# ---------------------------------------------------------------------------
# Restarts (g_director).

const ANNOUNCE := {
	R.THROW_IN: ["throw_in", 0x03, 70], R.GOAL_KICK: ["goal_kick", 0x02, 80],
	R.CORNER: ["corner_kick", 0x01, 90], R.FREE_KICK: ["free_kick", 0x04, 90],
	R.PENALTY: ["penalty_kick", 0x05, 120], R.OFFSIDE: ["offside", 0x06, 90],
	R.GOAL: ["", 0x2F, 220], R.OWN_GOAL: ["own_goal", 0x32, 220],
	R.HALF_TIME: ["half_time", 0x08, 240], R.TIME_UP: ["time_up", 0x42, 240],
	R.KICKOFF: ["", 0x27, 60], R.MATCH_START: ["", 0x27, 90],
}


func start_restart(type: int, side: int, pos: Vector2) -> void:
	restart_type = type
	restart_side = side
	restart_pos = pos
	restart_phase = 0
	restart_taker = null
	event_counts[type] = int(event_counts.get(type, 0)) + 1
	var a: Array = ANNOUNCE.get(type, ["", -1, 60])
	restart_timer = int(a[2])
	# Dead ball: no contacts and no rules until the restart is taken (the
	# ball itself rolls on, into the net after a goal).
	ball.live = false
	if type in [R.HALF_TIME, R.TIME_UP]:
		emit_sound(0x49)
	elif type in [R.FREE_KICK, R.PENALTY, R.OFFSIDE, R.THROW_IN, R.GOAL_KICK, R.CORNER]:
		emit_sound(0x61)
	if type == R.GOAL:
		emit_sound(0x64)
		var s := ball.last_touch
		banner.emit(s.name.to_upper() if s != null else "GOAL")
	elif a[0] != "":
		banner.emit(a[0])
	if int(a[1]) >= 0:
		if type == R.GOAL and randi() % 2 == 0:
			say(0x44)
		say(int(a[1]))
	for t in teams:
		for p in t.active():
			if p.state in [ISSFootballer.S.SET_PIECE, ISSFootballer.S.KEEPER_HOLD] and type not in [R.GOAL, R.OWN_GOAL]:
				p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)


func _director() -> void:
	if restart_type == R.NONE:
		return
	if restart_phase == 0:
		if restart_type in [R.GOAL, R.OWN_GOAL]:
			_ball_in_net()
		restart_timer -= 1
		if restart_timer > 0:
			return
		banner_off.emit()
		match restart_type:
			R.GOAL, R.OWN_GOAL:
				_start_kickoff(restart_side)
			R.HALF_TIME:
				half = 1
				left_goal_team = 1 - left_goal_team
				clock = half_frames
				for t in teams:
					t.reset_lines()
				_start_kickoff(1 - kickoff_side)
			R.TIME_UP:
				over = true
				finished.emit()
			_:
				_setup_restart()
	elif restart_phase == 1:
		if restart_taker == null or ball.owner != restart_taker:
			restart_type = R.NONE
			restart_phase = 0
			restart_taker = null


func _ball_in_net() -> void:
	var b := ball
	var depth := 24.0
	if b.pos.x < rect.position.x - depth or b.pos.x > rect.end.x + depth:
		b.speed = 0.0
		b.pos.x = clampf(b.pos.x, rect.position.x - depth, rect.end.x + depth)


func _start_kickoff(side: int) -> void:
	for t in teams:
		for p in t.active():
			if p.state in [ISSFootballer.S.CELEBRATE, ISSFootballer.S.DEJECTED]:
				p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)
	_place_for_kickoff(side)
	restart_type = R.KICKOFF
	restart_side = side
	restart_pos = mid
	restart_phase = 0
	restart_timer = 60
	say(0x27)
	event_counts[R.KICKOFF] = int(event_counts.get(R.KICKOFF, 0)) + 1
	# The kick-off itself: straight to the set piece.
	_setup_restart()


func _place_for_kickoff(side: int) -> void:
	ball.owner = null
	ball.stop()
	ball.pos = mid
	for t in teams:
		t.reset_lines()
		for p in t.active():
			p.pos = kickoff_place(p, side)
			p.speed = 0.0
			p.z = 0.0
			p.facing = 16 if attack_dir(p.team) > 0.0 else 48
			p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)


## tbl_kickoff_positions: (dx, dy) x16 px from the centre spot, negative dx
## toward the own goal; the kicking side's last two stand on the spot.
func kickoff_place(p: ISSFootballer, side: int) -> Vector2:
	var t := teams[p.team]
	var d := attack_dir(p.team)
	if p.is_keeper():
		return goal_center(p.team) + Vector2(d * 32.0, 0)
	var k: Array = t.kickoff_layout[clampi(p.index - 1, 0, 9)]
	var dx := float(k[0])
	var dy := float(k[1])
	if p.team != side:
		dx = minf(dx, -7.0)
	return mid + Vector2(dx * 16.0 * d, dy * 16.0)


## Where a player stands while a restart is being set up.
func restart_place(p: ISSFootballer) -> Vector2:
	var t := teams[p.team]
	if restart_type in [R.KICKOFF, R.MATCH_START]:
		return kickoff_place(p, restart_side)
	var home := t.home_position(p)
	if restart_type == R.PENALTY:
		var g := goal_center(1 - restart_side)
		var d := attack_dir(restart_side)
		if absf(home.x - g.x) < 320.0:
			home.x = g.x - d * 320.0
		return home
	# Keep the opponents 80 px from the ball.
	if p.team != restart_side and (home - restart_pos).length() < 80.0:
		home = restart_pos + restart_pos.direction_to(home) * 80.0 if home != restart_pos else restart_pos + Vector2(0, 80)
	return home


## Put the ball down and give it to the taker (tbl_restart_setup).
func _setup_restart() -> void:
	var type := restart_type
	var side := restart_side
	var t := teams[side]
	var taker: ISSFootballer = null
	ball.owner = null
	ball.stop()
	ball.pos = restart_pos
	ball.live = true
	ball_entered = rect.has_point(restart_pos)
	match type:
		R.GOAL_KICK:
			taker = t.players[0]
		R.KICKOFF, R.MATCH_START:
			taker = _kickoff_taker(t)
		_:
			var best := INF
			for p in t.active():
				if p.is_keeper() and type != R.FREE_KICK:
					continue
				var d := (p.pos - restart_pos).length()
				if d < best:
					best = d
					taker = p
	if taker == null:
		taker = t.players[0]
	var d := attack_dir(side)
	var aim := 16.0 if d > 0.0 else 48.0
	match type:
		R.THROW_IN:
			# Into the pitch, half turned toward the goal the side attacks.
			aim = 32.0 - 8.0 * d if restart_pos.y < mid.y else fposmod(8.0 * d, 64.0)
		R.CORNER, R.PENALTY, R.FREE_KICK, R.OFFSIDE:
			aim = ISSFootballer.heading_to(restart_pos, goal_center(1 - side))
	taker.pos = restart_pos - ISSProjection.heading_vector(int(aim) & 63) * 8.0
	if type == R.THROW_IN:
		taker.pos = restart_pos
	taker.z = 0.0
	taker.start_set_piece(aim)
	taker.ai_wait = 50 + randi() % 50
	taker.kick_target = null
	ball.owner = taker
	ball.team = side
	ball.last_touch = taker
	ball.step()
	restart_taker = taker
	restart_phase = 1
	if type == R.PENALTY:
		_setup_penalty(taker)
	elif type in [R.KICKOFF, R.MATCH_START]:
		emit_sound(0x47)


func _kickoff_taker(t: ISSTeam) -> ISSFootballer:
	var best: ISSFootballer = null
	var best_d := INF
	for p in t.active():
		if p.is_keeper():
			continue
		var d := (p.pos - mid).length()
		if d < best_d:
			best_d = d
			best = p
	return best


func _setup_penalty(taker: ISSFootballer) -> void:
	var defending := teams[1 - taker.team]
	var k := defending.players[0]
	k.pos = goal_center(defending.side) + Vector2(attack_dir(defending.side) * 4.0, 0)
	k.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_READY)
	for t in teams:
		for p in t.active():
			if p == taker or p.is_keeper():
				continue
			p.pos = restart_place(p)


## A CPU taker (or a human team's taker while no pad drives him).
func _cpu_set_piece(p: ISSFootballer) -> void:
	p.input_dir = -1
	p.ai_wait -= 1
	if p.ai_wait > 0 or ball.owner != p:
		return
	var t := teams[p.team]
	match restart_type:
		R.PENALTY:
			var g := goal_center(1 - p.team) + Vector2(0, (randf() * 2.0 - 1.0) * 70.0)
			p.facing = int(ISSFootballer.heading_to(p.pos, g)) & 63
			p.kick_target = null
			p.kick_power = 3 + randi() % 4
			p.press = ISSFootballer.SHOOT
			# The keeper guesses.
			var k := teams[1 - p.team].players[0]
			var guess := randi() % 3
			if guess < 2:
				k.start_dive(0.0 if guess == 0 else 32.0)
		R.KICKOFF, R.MATCH_START:
			var mate := t._best_mate(p, t.their_goal(), 200.0)
			p.kick_target = mate
			if mate != null:
				p.facing = int(ISSFootballer.heading_to(p.pos, mate.pos)) & 63
			p.press = ISSFootballer.PASS
		_:
			var to_goal := (goal_center(1 - p.team) - p.pos).length()
			if restart_type in [R.FREE_KICK, R.OFFSIDE] and to_goal < 420.0:
				p.facing = int(goal_heading(p)) & 63
				p.kick_power = 4
				p.press = ISSFootballer.SHOOT
				return
			var mate := t._best_mate(p, t.their_goal(), 520.0)
			if mate == null:
				p.facing = 16 if attack_dir(p.team) > 0.0 else 48
				p.kick_power = 6
				p.press = ISSFootballer.LOFT
				return
			p.kick_target = mate
			var dist := (mate.pos - p.pos).length()
			p.facing = int(ISSFootballer.heading_to(p.pos, mate.pos)) & 63
			if restart_type == R.CORNER or dist > 230.0:
				p.kick_power = t._lofted_power(dist)
				p.press = ISSFootballer.LOFT
			else:
				p.press = ISSFootballer.PASS
	p.kick_heading = p.facing


# ---------------------------------------------------------------------------
# Officials: the referee trails the ball, the linesman runs the touchline.

func _officials() -> void:
	var target := ball.pos + Vector2(-64.0 * attack_dir(ball.team if ball.team >= 0 else 0), 72.0)
	referee_pos += (target - referee_pos).limit_length(2.0)
	var lx := clampf(ball.pos.x, rect.position.x, rect.end.x)
	linesman_pos.x += clampf(lx - linesman_pos.x, -2.2, 2.2)
	linesman_pos.y = rect.position.y - 20.0
