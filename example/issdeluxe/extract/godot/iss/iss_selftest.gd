extends SceneTree
## Headless check of the extracted ISS Deluxe assets and scripts:
##
##   godot --headless --path out/godot --import
##   godot --headless --path out/godot -s res://iss/iss_selftest.gd
##
## Exits with status 1 if anything is missing or behaves unexpectedly.

var _failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", what)


func _json(path: String) -> Variant:
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(doc != null, "parse " + path)
	return doc


func _init() -> void:
	var players = _json("res://assets/iss/players/animations.json")
	var ball = _json("res://assets/iss/ball/animations.json")
	var npc = _json("res://assets/iss/npc/animations.json")
	var weather = _json("res://assets/iss/weather/weather.json")
	var stadiums = _json("res://assets/iss/stadiums/stadiums.json")
	var teams = _json("res://assets/iss/teams.json")
	var flags = _json("res://assets/iss/flags/flags.json")
	var hud = _json("res://assets/iss/hud/hud.json")
	var sound = _json("res://assets/iss/sound/sound.json")
	var misc = _json("res://assets/iss/misc/misc.json")
	if _failures > 0:
		quit(1)
		return
	_check(players["actions"].size() == 54, "54 player actions")
	_check(ball["actions"].size() == 5, "5 ball actions")
	_check(npc["actions"].size() == 21 and npc["action_names"].size() == 21, "21 named NPC actions")
	_check(stadiums["stadiums"].size() == 8, "8 stadiums")
	_check(stadiums["stadiums"][0]["pitch_bounds"]["right"] == 1920, "stadium 0 pitch bounds")
	_check(flags["actions"].size() == 2 and flags["actions"][0].size() == 4, "flag frames")
	_check(teams != null and teams["teams"][0]["name"] == "England", "team names")
	_check(teams["teams"][0]["players"][9]["attributes"]["speed"] == 7 \
		and teams["teams"][0]["players"][0]["position"] == "goalkeeper", "player records")
	var formations = _json("res://assets/iss/formations.json")
	_check(formations["formations"].size() == 16 and formations["formations"][1]["name"] == "4-4-2", "formations")
	_check(hud["radar"]["mapping"].size() == 8, "radar mapping per stadium")
	_check(hud["banner_messages"]["throw_in"]["text"] == "  THROW IN  " \
		and ResourceLoader.exists("res://assets/iss/hud/banner_font.png"), "banner font and messages")
	_check(ResourceLoader.exists("res://assets/iss/hud/flags/flag_41.png"), "team flags")
	_check(hud["strategy_names"].size() == 8 \
		and ResourceLoader.exists("res://assets/iss/hud/strategies/strategy_7.png"), "strategy labels")
	_check(misc["particles"]["rain"]["actions"]["1"].size() == 3 and misc["goal_target"].size() == 2, "small sprites")
	_check(sound["samples"].size() == 65 and sound["sfx"].size() == 126, "65 PCM samples, 126 effects")
	for s: Dictionary in sound["samples"]:
		_check(ResourceLoader.exists(s["wav"]), "sample " + s["wav"])
	for id in [0x01, 0x2F, 0x4D]:
		_check(sound["sfx"][id].has("wav") and ResourceLoader.exists(sound["sfx"][id]["wav"]), "effect %X" % id)
	var crowd: AudioStreamWAV = load(sound["sfx"][0x62]["wav"])
	_check(crowd != null and crowd.loop_mode == AudioStreamWAV.LOOP_FORWARD \
		and crowd.loop_end == sound["sfx"][0x62]["loop"][1] - 1, "crowd loop points")
	var counts := [32, 0, 16]
	for w in 3:
		_check(weather["weathers"][w]["frames"].size() == counts[w], "weather %d frame count" % w)
	for doc in [players, ball, npc]:
		for f: Dictionary in doc["frames"].values():
			for side in ["right", "left", "shadow"]:
				if f.has(side):
					_check(ResourceLoader.exists(f[side]["png"]), "frame " + f[side]["png"])

	# Run the demo for two seconds of game time.
	var demo: Node = load("res://iss/iss_demo.tscn").instantiate()
	root.add_child(demo)
	for i in 120:
		await process_frame
	var b := ISSBallSprite.new()
	root.add_child(b)
	for h: int in [0, 0x3F, 0x40, 0x5F, 0x60, 0xC8]:
		b.height = h
		_check(b.action() == clampi((h - 0x20) >> 5, 0, 2), "ball action at height %d" % h)
	_check(ISSProjection.heading_vector(16).is_equal_approx(Vector2(1, 0)), "heading 16 = right")
	_check(ISSProjection.heading_vector(0).is_equal_approx(Vector2(0, -1)), "heading 0 = up")
	_check(ISSProjection.direction(60) == 0 and ISSProjection.direction(20) == 3, "direction index")
	var snd := ISSSound.new()
	root.add_child(snd)
	var rendered := FileAccess.file_exists("res://assets/iss/sound/rendered/rendered.json")
	_check(snd.play_sfx(0x2F), "commentary plays")
	_check(not snd.has_sfx(0x10), "commentary whose sample is missing")
	_check(snd.has_sfx(0x5F) == rendered, "PSG effect only with the rendered sound")
	_check(snd.play_music(5) == rendered, "music only with the rendered sound")
	if rendered:
		var ogg: AudioStreamOggVorbis = load("res://assets/iss/sound/rendered/song_12.ogg")
		_check(ogg != null and ogg.get_length() > 10.0, "rendered song")
	_check(snd.speech_context(0x2F) == "goal", "speech context")
	snd.stop_music()
	snd.stop_sfx()
	snd.queue_free()
	demo.queue_free()
	await process_frame
	_check_match_engine()
	_check_human_control()
	_check_knockout()
	_check_competitions()
	await _check_game()
	print("iss_selftest: ", "OK" if _failures == 0 else "%d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## A whole CPU v CPU match with 1-minute halves: kick-offs, half time, time up,
## restarts; the ball stays on or around the pitch and never dies for long.
func _check_match_engine() -> void:
	seed(7)
	var match_json = _json("res://assets/iss/match.json")
	_check(match_json["pitch_bounds"].size() == 8 and is_equal_approx(match_json["run_speed"], 1.875), "match constants")
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"stadium": 0, "weather": 1, "time": 1, "level": 2, "pads": [0, 0], "half_seconds": 60})
	var frames := 0
	var still := 0
	var worst := 0
	var outside := 0
	while not e.over and frames < 60 * 60 * 10:
		e.step([])
		frames += 1
		if e.restart_type == ISSMatchEngine.R.NONE and e.ball.live and e.ball.speed == 0.0 and e.ball.owner == null:
			still += 1
			worst = maxi(worst, still)
		else:
			still = 0
		if not e.rect.grow(96.0).has_point(e.ball.pos):
			outside += 1
	_check(e.over, "match finishes (%d frames)" % frames)
	_check(frames < 60 * 60 * 6, "match length %d frames" % frames)
	_check(int(e.event_counts.get(ISSMatchEngine.R.HALF_TIME, 0)) == 1 \
		and int(e.event_counts.get(ISSMatchEngine.R.TIME_UP, 0)) == 1, "half time and time up")
	_check(int(e.event_counts.get(ISSMatchEngine.R.KICKOFF, 0)) >= 1, "kick-offs")
	_check(worst < 60 * 20, "ball never left dead in play (%d frames)" % worst)
	_check(outside < 60 * 3, "ball stays near the pitch (%d frames outside)" % outside)
	var total := 0
	for k in e.event_counts:
		if k is int and k in [ISSMatchEngine.R.THROW_IN, ISSMatchEngine.R.GOAL_KICK, ISSMatchEngine.R.CORNER,
				ISSMatchEngine.R.FREE_KICK, ISSMatchEngine.R.GOAL, ISSMatchEngine.R.OWN_GOAL]:
			total += int(e.event_counts[k])
	_check(total > 0, "restarts happen")
	_check(e.scorers.size() == e.teams[0].score + e.teams[1].score, "every goal recorded")
	print("iss_selftest: match ", e.teams[0].name, " ", e.teams[0].score, "-", e.teams[1].score, " ", e.teams[1].name,
		" in ", frames, " frames, events ", e.event_counts)
	e.dispose()


## Player 1's pad drives the controlled player: run right with dash, then
## pass; the kick-off taker is the human's when the home side kicks off.
func _check_human_control() -> void:
	seed(3)
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"stadium": 0, "weather": 1, "time": 1, "level": 2, "pads": [1, 0], "half_seconds": 60})
	var idle := {"dir": -1, "press": 0, "held": 0}
	var frames := 0
	# Wait for the kick-off to be ready (the CPU may kick off).
	while e.restart_type != ISSMatchEngine.R.NONE and frames < 600:
		if e.restart_taker != null and e.restart_taker.team == 0 and e.restart_phase == 1:
			e.step([{"dir": 16, "press": ISSFootballer.PASS, "held": 0}, null])
		else:
			e.step([idle, null])
		frames += 1
	_check(e.restart_type == ISSMatchEngine.R.NONE, "kick-off taken")
	var c := e.teams[0].controlled
	_check(c != null, "a controlled player")
	if c == null:
		e.dispose()
		return
	var x0 := c.pos.x
	for i in 60:
		e.step([{"dir": 16, "press": 0, "held": ISSFootballer.DASH}, null])
	c = e.teams[0].controlled
	_check(c != null and c.human, "human flag on the controlled player")
	# Get the ball to a home player and pass it.
	e.ball.owner = null
	e.ball.stop()
	var p := e.teams[0].players[6]
	e.ball.pos = p.pos + Vector2(4, 0)
	e.teams[0].controlled = p
	for i in 4:
		e.step([idle, null])
	_check(e.ball.owner == p, "the controlled player picks up the ball")
	var kicked := false
	for i in 40:
		e.step([{"dir": 16, "press": ISSFootballer.PASS if i == 0 else 0, "held": 0}, null])
		if e.ball.owner == null and e.ball.kicker == p:
			kicked = true
	_check(kicked, "the pad's pass button kicks the ball")
	_check(absf(x0) > 0.0, "controlled player moved")
	e.dispose()


## The game scene: front end first, then a match on screen.
func _check_game() -> void:
	var game: ISSGame = load("res://iss/iss_game.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	game._start_match(3, 4, {"stadium": 2, "weather": 2, "time": 1, "level": 2, "pads": [0, 0], "half_seconds": 30})
	for i in 120:
		await physics_frame
	var m := game._screen as ISSMatch
	_check(m != null and m.engine.frame > 60, "match runs on screen")
	game.queue_free()
	await process_frame


## A level knockout match goes through extra time to a shoot-out that ends
## with a winner; PK mode is a shoot-out on its own.
func _check_knockout() -> void:
	seed(21)
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"pads": [0, 0], "half_seconds": 20, "knockout": true, "vgoal": 0})
	var halves := {}
	var frames := 0
	while not e.over and frames < 60 * 60 * 20:
		if not e.shootout:
			e.teams[1].score = e.teams[0].score
		e.step([])
		halves[e.half] = true
		frames += 1
	_check(e.over and e.shootout and halves.size() == 5, "extra time then penalties")
	_check(e.pk_scores[0] != e.pk_scores[1] and e.pk_taken[0] >= 3, "the shoot-out has a winner")
	e.dispose()
	var p := ISSMatchEngine.new()
	p.setup(2, 3, {"pads": [0, 0], "pk_only": true})
	frames = 0
	while not p.over and frames < 60 * 60 * 10:
		p.step([])
		frames += 1
	_check(p.over and p.half == 4, "PK mode")
	p.dispose()


## Short league and tournament between computer teams, and a league that
## stops at the human team's games.
func _check_competitions() -> void:
	seed(4)
	var lg := ISSCompetition.league([0, 1, 2, 3, 4, 5], 0)
	lg.simulate_until_human()
	_check(lg.finished() and lg.games.size() == 15, "league: 15 games")
	var w := 0
	var l := 0
	for r: Dictionary in lg.table():
		_check(r["w"] + r["d"] + r["l"] == 5, "league: 5 games each")
		w += r["w"]
		l += r["l"]
	_check(w == l, "league: wins match losses")
	var t := lg.table()
	_check(t[0]["p"] >= t[5]["p"], "league: sorted by points")
	var cup := ISSCompetition.tournament([6, 7, 8, 9, 10, 11, 12, 13], 0)
	cup.simulate_until_human()
	_check(cup.finished() and cup.games.size() == 7 and cup.champion() >= 0, "tournament: 7 games, a champion")
	for r: Dictionary in cup.games:
		_check(r["hg"] != r["ag"] or not r["pk"].is_empty(), "tournament: every game has a winner")
	var mine := ISSCompetition.league([0, 1, 2, 3, 4, 5], 1)
	mine.simulate_until_human()
	_check(mine.games.is_empty() and mine.next_game() == [0, 2], "league: the human's first game comes first")
	mine.record(2, 1)
	mine.simulate_until_human()
	_check(mine.games.size() == 3 and mine.next_game() == [0, 4], "league: computer games played in between")
