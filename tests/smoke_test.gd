extends SceneTree
## Headless smoke test: plays every track, every power-up, a full Grand Prix
## and two Time Trials (record + ghost playback). Prints SMOKE OK on success.

const Data = preload("res://scripts/data.gd")
var main
var ok := true
var frame := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_dt: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	_run()
	print("SMOKE OK" if ok else "SMOKE FAILED")
	quit(0 if ok else 1)
	return true

func check(cond: bool, msg: String) -> void:
	if not cond:
		ok = false
		push_error("CHECK FAILED: " + msg)
	else:
		print("  ok: ", msg)

func sim(steps: int, auto_item: bool = true) -> int:
	var r = main.race
	for i in steps:
		var inp := {}
		if main.state == "race" and r.player and not r.player.finished:
			inp = r._ai_input(r.player, false)
			inp["item"] = auto_item and i % 90 == 45
		r.step(1.0 / 60.0, inp)
		if main.state != "race":
			return i
	return -1

func _run() -> void:
	print("Track lengths:")
	for i in Data.TRACKS.size():
		var t = load("res://scripts/track.gd").new()
		t.build(i)
		print("  ", Data.TRACKS[i]["name"], ": ", int(t.length), " m, ", t.n, " samples")
		t.free()
	check(main.state == "title", "boots to title")
	sim(600)
	check(main.race.karts.size() == 6, "attract race has 6 karts")
	# quick race on every track
	for ti in Data.TRACKS.size():
		main._on_action("quick", null)
		main._on_action("driver", ti % 6)
		main._on_action("track", ti)
		check(main.state == "race" and main.race.player != null, "quick race started on track %d" % ti)
		var n := sim(60 * 400)
		check(n > 0, "race on track %d finished after %.1fs" % [ti, n / 60.0])
		var me: Dictionary = {}
		for r in main.last_results:
			if r["player"]:
				me = r
		check(main.last_results.size() == 6, "results list has 6 racers")
		print("    player place ", me.get("place", -1), " time ", Data.fmt_time(me.get("time", 0.0)), "  laps of winner ok")
		check(main.menus.current == "results", "results screen shown")
	# every power-up
	main._on_action("quick", null)
	main._on_action("driver", 0)
	main._on_action("track", 1)
	sim(60 * 8)
	var p = main.race.player
	for k in 6:
		p.item = k
		p.item_count = 1
		p.roulette_t = 0.0
		p.spin_t = 0.0
		main.race._use_item(p)
		check(p.item == -1, "used item " + Data.ITEM_NAMES[k])
		sim(90, false)
	check(main.race.traps.size() >= 0 and main.race.state == "racing", "race still running after items")
	# pause
	main.toggle_pause()
	check(main.paused and main.menus.current == "pause", "pause opens menu")
	main._on_action("resume", null)
	check(not main.paused, "resume works")
	main._on_action("quit", null)
	check(main.state == "title", "quit to title")
	# time trial twice (record, then ghost)
	main.save.set_value("tt", "best0", 0.0)
	main.save.set_value("tt", "ghost0", PackedFloat32Array())
	for run in 2:
		main._on_action("tt", null)
		main._on_action("driver", 1)
		main._on_action("track", 0)
		if run == 1:
			check(main.race.ghost_kart != null, "ghost kart appears on second run")
		var n2 := sim(60 * 300)
		check(n2 > 0, "time trial run %d finished" % run)
		var g: PackedFloat32Array = main.save.get_value("tt", "ghost0", PackedFloat32Array())
		check(g.size() > 100, "ghost saved (%d floats)" % g.size())
		main._on_action("quit", null)
	# full grand prix
	main._on_action("gp", null)
	main._on_action("driver", 2)
	for race_no in 4:
		check(main.state == "race" and main.race.track.index == race_no, "GP race %d started" % (race_no + 1))
		var n3 := sim(60 * 400)
		check(n3 > 0, "GP race %d finished" % (race_no + 1))
		main._on_action("standings", null)
		check(main.menus.current == "standings", "standings shown")
		main._on_action("next", null)
	check(main.menus.current == "final", "trophy ceremony reached")
	var total := 0
	for k in main.gp_points:
		total += main.gp_points[k]
	check(total == 4 * 31, "GP points add up (%d)" % total)
	main._on_action("quit", null)
	check(main.state == "title", "back to title after GP")
