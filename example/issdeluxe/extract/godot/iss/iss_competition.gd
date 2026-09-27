class_name ISSCompetition
extends RefCounted
## The short league (mode 4) and short tournament (mode 5).
##
## League: 6 teams, each plays each once in the order of the ROM's fixture
## list ($05B17E, 15 games in 5 rounds); a win is worth 3 points and a draw 1
## (screen_league_table). Tournament: 8 teams in a knockout bracket, every
## game a knockout match (extra time, penalties). The first `humans` teams are
## played by people; games between computer teams are decided by
## match_simulate ($015442): the strength difference picks a row of the
## goals table and a random column gives each side's goals.

var kind := "league"
var teams: Array = []
var humans := 1
## Played games: {home, away, hg, ag, pk: [h, a] or []} (slots into teams).
var games: Array = []
## Tournament: slots still in, in bracket order.
var alive: Array = []


static func league(team_ids: Array, human_count: int) -> ISSCompetition:
	var c := ISSCompetition.new()
	c.kind = "league"
	c.teams = team_ids.duplicate()
	c.humans = human_count
	return c


static func tournament(team_ids: Array, human_count: int) -> ISSCompetition:
	var c := ISSCompetition.new()
	c.kind = "tournament"
	c.teams = team_ids.duplicate()
	c.humans = human_count
	c.alive = range(team_ids.size())
	return c


func is_human(slot: int) -> bool:
	return slot < humans


## The next game as [home slot, away slot], or [] when the competition is over.
func next_game() -> Array:
	if kind == "league":
		var f: Array = ISSMatchData.consts["league_fixtures"]
		if games.size() >= f.size():
			return []
		return [int(f[games.size()][0]), int(f[games.size()][1])]
	# Tournament: the next unplayed pair of this round.
	if alive.size() <= 1:
		return []
	var played := _round_games()
	var i := played * 2
	return [alive[i], alive[i + 1]]


func _round_games() -> int:
	# Games of the current round = games since the round began.
	var total := teams.size()
	var done := games.size()
	var round_size := total / 2
	while done >= round_size and round_size >= 1:
		done -= round_size
		round_size /= 2
	return done


func round_name() -> String:
	if kind == "league":
		return "ROUND %d" % (games.size() / 3 + 1)
	match alive.size():
		2:
			return "FINAL"
		4:
			return "SEMI FINAL"
	return "QUARTER FINAL"


## Record the result of the next game (from a match or a simulation).
func record(hg: int, ag: int, pk: Array = []) -> void:
	var g := next_game()
	if g.is_empty():
		return
	games.append({"home": g[0], "away": g[1], "hg": hg, "ag": ag, "pk": pk})
	if kind == "tournament" and _round_games() == 0:
		# The round is complete: keep the winners, in bracket order.
		var n := alive.size() / 2
		var winners := []
		for r in games.slice(games.size() - n):
			winners.append(_winner(r))
		alive = winners


static func _winner(r: Dictionary) -> int:
	var h: int = r["hg"]
	var a: int = r["ag"]
	if h == a and not r["pk"].is_empty():
		h = r["pk"][0]
		a = r["pk"][1]
	return r["home"] if h >= a else r["away"]


## Play the computer's games until one involves a human team (or the end).
func simulate_until_human() -> void:
	while true:
		var g := next_game()
		if g.is_empty() or is_human(g[0]) or is_human(g[1]):
			return
		var r := simulate(teams[g[0]], teams[g[1]], kind == "tournament")
		record(r[0], r[1], r[2])


## match_simulate ($015442).
static func simulate(home: int, away: int, knockout: bool) -> Array:
	ISSMatchData.ensure_loaded()
	var sim: Dictionary = ISSMatchData.consts["simulate"]
	var st: Array = sim["strength"]
	var goals: Array = sim["goals"]
	var d := int(st[home]) - int(st[away])
	var dh := clampi(d, 0, 63) & ~7
	var da := clampi(-d, 0, 63) & ~7
	var hg := int(goals[dh + randi() % 8])
	var ag := int(goals[da + randi() % 8])
	var pk := []
	if knockout and hg == ag:
		var ph := 3 + int(goals[dh + randi() % 8])
		var pa := 3 + int(goals[da + randi() % 8])
		if ph == pa:
			ph += 1
		pk = [ph, pa]
	return [hg, ag, pk]


## League standings: [{slot, w, d, l, p}] by points (ties keep slot order).
func table() -> Array:
	var rows := []
	for i in teams.size():
		rows.append({"slot": i, "w": 0, "d": 0, "l": 0, "p": 0})
	for r: Dictionary in games:
		var h: Dictionary = rows[r["home"]]
		var a: Dictionary = rows[r["away"]]
		if r["hg"] == r["ag"]:
			h["d"] += 1
			a["d"] += 1
			h["p"] += 1
			a["p"] += 1
		elif r["hg"] > r["ag"]:
			h["w"] += 1
			h["p"] += 3
			a["l"] += 1
		else:
			a["w"] += 1
			a["p"] += 3
			h["l"] += 1
	var out := []
	var left := rows.duplicate()
	while not left.is_empty():
		var best: Dictionary = left[0]
		for r: Dictionary in left:
			if r["p"] > best["p"]:
				best = r
		out.append(best)
		left.erase(best)
	return out


func finished() -> bool:
	return next_game().is_empty()


## The champion's slot (league leader or tournament winner).
func champion() -> int:
	if kind == "league":
		return table()[0]["slot"]
	return alive[0] if alive.size() == 1 else -1
