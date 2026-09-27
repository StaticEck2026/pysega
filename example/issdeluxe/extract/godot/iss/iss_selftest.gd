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
	_check(hud["radar"]["mapping"].size() == 8, "radar mapping per stadium")
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
	_check(snd.play_sfx(0x2F) and not snd.play_sfx(0x5F), "commentary plays, FM effect has no file")
	_check(snd.speech_context(0x2F) == "goal", "speech context")
	snd.stop_sfx()
	snd.queue_free()
	demo.queue_free()
	await process_frame
	print("iss_selftest: ", "OK" if _failures == 0 else "%d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)
