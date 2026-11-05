extends Node3D
## Game flow: title (with an attract-mode race behind it), driver/track select,
## Grand Prix, Time Trial with ghosts, Quick Race, pause, results and saving.

const Data = preload("res://scripts/data.gd")
const Race = preload("res://scripts/race.gd")
const Hud = preload("res://scripts/hud.gd")
const Menus = preload("res://scripts/menus.gd")
const Sfx = preload("res://scripts/sfx.gd")
const SAVE_PATH := "user://turbo_tots_kart.cfg"

var race
var hud
var menus
var sfx
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var state := "title" # title | race | results
var mode := ""
var drv := 0
var track_i := 0
var gp_race := 0
var gp_points := {}
var save := ConfigFile.new()
var sound_on := true
var touch := false
var paused := false
var portrait := false
var last_results: Array = []
var attract_track := 0

func _ready() -> void:
	_setup_input()
	save.load(SAVE_PATH)
	sound_on = bool(save.get_value("settings", "sound", true))
	_setup_env()
	race = Race.new()
	add_child(race)
	race.event.connect(_on_event)
	race.race_over.connect(_on_race_over)
	sfx = Sfx.new()
	add_child(sfx)
	var layer := CanvasLayer.new()
	add_child(layer)
	var root_ui := Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.theme = _make_theme()
	layer.add_child(root_ui)
	hud = Hud.new()
	root_ui.add_child(hud)
	hud.pause_pressed.connect(toggle_pause)
	hud.roulette_tick.connect(func(): sfx.play("tick", 1.0, -6.0))
	menus = Menus.new()
	root_ui.add_child(menus)
	menus.action.connect(_on_action)
	menus.sound_on = sound_on
	get_tree().root.size_changed.connect(_on_resize)
	touch = DisplayServer.is_touchscreen_available()
	_on_resize()
	sfx.set_muted(not sound_on)
	go_title()

# ------------------------------------------------------------------ setup
func _setup_input() -> void:
	_act("accel", [KEY_W, KEY_UP], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_act("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_B], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_act("left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_act("right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_act("drift", [KEY_SPACE, KEY_SHIFT, KEY_K], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_act("item", [KEY_E, KEY_J, KEY_CTRL], [JOY_BUTTON_X, JOY_BUTTON_LEFT_SHOULDER], [])
	_act("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_act("mute", [KEY_M], [], [])

func _act(name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(name, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(name, e)

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.95)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_density = 0.0016
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = false
	add_child(sun)

func _apply_env(i: int) -> void:
	var t: Dictionary = Data.TRACKS[i]
	sky_mat.sky_top_color = t["sky_top"]
	sky_mat.sky_horizon_color = t["sky_hor"]
	sky_mat.ground_horizon_color = t["sky_hor"]
	sky_mat.ground_bottom_color = (t["ground"] as Color).darkened(0.3)
	sky_mat.sun_angle_max = 20.0
	env.fog_light_color = t["sky_hor"]
	sun.light_color = t["sun"]
	var night: bool = t["night"]
	sun.light_energy = 0.75 if night else 1.05
	env.ambient_light_color = Color(0.55, 0.5, 0.9) if night else Color(0.78, 0.82, 0.95)
	env.ambient_light_energy = 0.8 if night else 0.55

func _make_theme() -> Theme:
	var th := Theme.new()
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.7
	th.default_font = fv
	th.default_font_size = 26
	th.set_color("font_color", "Button", Color(1, 1, 1))
	th.set_color("font_hover_color", "Button", Color(1, 1, 0.85))
	th.set_color("font_focus_color", "Button", Color(1, 1, 0.85))
	th.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.06, 0.3, 0.7)
	sb.set_corner_radius_all(16)
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.3, 0.2, 0.6, 0.8)
	th.set_stylebox("hover", "Button", sbh)
	th.set_stylebox("pressed", "Button", sbh)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return th

func _on_resize() -> void:
	var s: Vector2i = get_tree().root.size
	portrait = s.y > s.x
	get_tree().root.content_scale_size = Vector2i(648, 1152) if portrait else Vector2i(1152, 648)
	if race and race.camera:
		race.set("fov_bonus", 18.0 if portrait else 0.0)
	if menus and menus.current != "":
		_refresh_menu()

func _refresh_menu() -> void:
	match menus.current:
		"title": menus.show_title(_title_info())
		"drivers": menus.show_drivers(mode)
		"tracks": menus.show_tracks(_bests())
		"howto": menus.show_howto()
		"pause": menus.show_pause()
		"standings": menus.show_standings(_standings(), gp_race + 1)

# ------------------------------------------------------------------ flow
func go_title() -> void:
	state = "title"
	paused = false
	hud.visible = false
	_start_attract()
	menus.show_title(_title_info())
	sfx.set_music("menu")
	sfx.set_engine(false, 0.0, false)

func _start_attract() -> void:
	attract_track = (attract_track + 1 + randi() % 3) % Data.TRACKS.size()
	var grid := [0, 1, 2, 3, 4, 5]
	grid.shuffle()
	race.setup(attract_track, "attract", grid, -1)
	_apply_env(attract_track)

func _title_info() -> Dictionary:
	var best: int = int(save.get_value("gp", "best", 0))
	var txt := ""
	if best >= 1 and best <= 3:
		txt = "Best Grand Prix: " + ["Gold", "Silver", "Bronze"][best - 1] + " Trophy"
	var wins: int = int(save.get_value("stats", "wins", 0))
	if wins > 0:
		txt += ("   " if txt != "" else "") + "Race wins: %d" % wins
	return {"trophies": txt}

func _bests() -> Array:
	var b := []
	for i in Data.TRACKS.size():
		b.append(float(save.get_value("tt", "best%d" % i, 0.0)))
	return b

func start_gp() -> void:
	gp_race = 0
	gp_points = {}
	for i in Data.DRIVERS.size():
		gp_points[i] = 0
	track_i = 0
	start_race()

func start_race() -> void:
	var grid := []
	if mode == "tt":
		grid = [drv]
	elif mode == "gp" and gp_race > 0:
		var rows := _standings()
		for r in rows:
			grid.append(r["driver"])
	else:
		for i in Data.DRIVERS.size():
			if i != drv:
				grid.append(i)
		grid.shuffle()
		grid.append(drv)
	if mode == "gp":
		track_i = gp_race
	var ghost := PackedFloat32Array()
	if mode == "tt":
		ghost = save.get_value("tt", "ghost%d" % track_i, PackedFloat32Array())
	race.setup(track_i, mode, grid, drv, ghost)
	race.set("fov_bonus", 18.0 if portrait else 0.0)
	_apply_env(track_i)
	state = "race"
	paused = false
	menus.hide_all()
	hud.visible = true
	hud.set_touch(touch)
	var sub: String = Data.TRACKS[track_i]["name"]
	if mode == "gp":
		sub += "  -  Race %d of 4" % (gp_race + 1)
	elif mode == "tt":
		sub += "  -  Time Trial" + ("  (ghost on)" if ghost.size() > 8 else "")
	hud.show_sub(sub, 3.0)
	sfx.set_music("race")

func _standings() -> Array:
	var rows := []
	for i in Data.DRIVERS.size():
		rows.append({"driver": i, "points": int(gp_points.get(i, 0)), "player": i == drv})
	rows.sort_custom(func(a, b):
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		return a["player"] and not b["player"])
	return rows

func toggle_pause() -> void:
	if state != "race":
		return
	paused = not paused
	if paused:
		menus.show_pause()
		hud.touch.visible = false
		sfx.set_engine(false, 0.0, false)
		sfx.play("click")
	else:
		menus.hide_all()
		hud.set_touch(touch)

func _on_action(name: String, arg: Variant) -> void:
	sfx.play("select")
	match name:
		"gp", "tt", "quick":
			mode = name
			menus.show_drivers(mode)
		"driver":
			drv = int(arg)
			if mode == "gp":
				start_gp()
			else:
				menus.show_tracks(_bests())
		"track":
			track_i = int(arg)
			start_race()
		"tracks":
			if state == "results":
				state = "title"
				_start_attract()
				sfx.set_music("menu")
			menus.show_tracks(_bests())
		"howto":
			menus.show_howto()
		"back":
			if menus.current == "tracks":
				menus.show_drivers(mode)
			else:
				menus.show_title(_title_info())
		"sound":
			_toggle_sound()
		"resume":
			toggle_pause()
		"restart":
			start_race()
		"quit":
			go_title()
		"standings":
			menus.show_standings(_standings(), gp_race + 1)
		"next":
			if mode == "gp" and menus.current == "standings":
				if gp_race < 3:
					gp_race += 1
					start_race()
				else:
					_show_final()

func _toggle_sound() -> void:
	sound_on = not sound_on
	menus.sound_on = sound_on
	sfx.set_muted(not sound_on)
	save.set_value("settings", "sound", sound_on)
	_save()
	_refresh_menu()
	if sound_on:
		sfx.play("select")

func _show_final() -> void:
	var rows := _standings()
	var place := 1
	for i in rows.size():
		if rows[i]["player"]:
			place = i + 1
	var best: int = int(save.get_value("gp", "best", 0))
	if place <= 3 and (best == 0 or place < best):
		save.set_value("gp", "best", place)
		_save()
	sfx.play("finish" if place <= 3 else "lose")
	menus.show_final(place, drv, int(gp_points.get(drv, 0)))

func _save() -> void:
	var err := save.save(SAVE_PATH)
	if err != OK:
		push_warning("Could not save progress")

# ------------------------------------------------------------------ events
func _on_event(kind: String, data: Variant) -> void:
	if state != "race":
		return
	match kind:
		"count":
			sfx.play("count")
			hud.show_msg(str(data), 0.9, [Color(0.4, 1, 0.5), Color(1, 0.85, 0.2), Color(1, 0.4, 0.35)][clampi(int(data) - 1, 0, 2)])
		"go":
			sfx.play("go")
			hud.show_msg("GO!", 1.0, Color(0.4, 1, 0.5))
		"start_boost":
			sfx.play("boost")
			hud.show_sub("ROCKET START!", 1.5)
		"drift_boost":
			sfx.play("drift%d" % int(data))
			sfx.play("boost", 0.9 + int(data) * 0.1, -4.0)
			if int(data) == 3:
				hud.show_sub("ULTRA TURBO!", 1.0)
		"bump":
			sfx.play("bump", randf_range(0.9, 1.1))
		"pad":
			sfx.play("boost", 1.2, -6.0)
		"lap":
			var lp: int = data["lap"]
			if lp == Data.LAPS - 1:
				sfx.play("final")
				hud.show_msg("FINAL LAP!", 1.6, Color(1, 0.6, 0.2))
			elif lp < Data.LAPS:
				sfx.play("lap")
				hud.show_msg("LAP %d" % (lp + 1), 1.2)
			hud.show_sub("Lap time  " + Data.fmt_time(data["time"]), 2.0)
		"finish":
			var pl: int = int(data)
			if mode == "tt" or pl <= 3:
				sfx.play("finish")
			else:
				sfx.play("lose")
			hud.show_msg("FINISH!" if mode == "tt" else Data.ordinal(pl) + "!", 3.0, Color(1, 0.85, 0.2))
		"box":
			sfx.play("box")
		"item_get":
			sfx.play("item_get")
		"use_item":
			if data["player"]:
				match int(data["kind"]):
					Data.ROCKET, Data.MAGNET: sfx.play("boost")
					Data.BALL, Data.BEE: sfx.play("shoot")
					Data.GOO: sfx.play("splat")
					Data.SHIELD: sfx.play("shield")
		"hit_me":
			sfx.play("hit")
			hud.show_sub(["Ouch!", "Wobbly!", "Spun out!"][randi() % 3], 1.0)
		"hit_other":
			sfx.play("pop")
			hud.show_sub("Bonk! Got " + Data.DRIVERS[int(data)]["name"] + "!", 1.2)
		"shield_pop":
			sfx.play("pop", 1.3)

func _on_race_over(res: Array) -> void:
	if state == "title":
		_start_attract()
		return
	if state != "race":
		return
	state = "results"
	paused = false
	hud.visible = false
	sfx.set_engine(false, 0.0, false)
	sfx.set_music("menu")
	last_results = res
	var me: Dictionary = {}
	for r in res:
		if r["player"]:
			me = r
	var info := {}
	match mode:
		"tt":
			var t: float = me["time"]
			var key := "best%d" % track_i
			var best: float = float(save.get_value("tt", key, 0.0))
			var record := best <= 0.0 or t < best
			if record:
				save.set_value("tt", key, t)
				save.set_value("tt", "ghost%d" % track_i, race.ghost_rec)
				_save()
				sfx.play("record")
			info = {"title": "New Record!" if record else "Time Trial", "sub": "Time %s   Best lap %s" % [Data.fmt_time(t), Data.fmt_time(me["best_lap"])],
				"note": ("Your ghost will race you next time." if record else "Record to beat: " + Data.fmt_time(best)),
				"buttons": [["Retry", "restart"], ["Change Track", "tracks"], ["Title", "quit"]], "confetti": record}
		"quick":
			var pl: int = me["place"]
			if pl == 1:
				save.set_value("stats", "wins", int(save.get_value("stats", "wins", 0)) + 1)
				_save()
			info = {"title": "You Win!" if pl == 1 else "You finished " + Data.ordinal(pl), "sub": Data.TRACKS[track_i]["name"],
				"buttons": [["Race Again", "restart"], ["Change Track", "tracks"], ["Title", "quit"]], "confetti": pl <= 3}
		"gp":
			for r in res:
				gp_points[r["driver"]] = int(gp_points.get(r["driver"], 0)) + Data.GP_POINTS[r["place"] - 1]
			var pl2: int = me["place"]
			if pl2 == 1:
				save.set_value("stats", "wins", int(save.get_value("stats", "wins", 0)) + 1)
				_save()
			info = {"title": "Race %d of 4 - %s" % [gp_race + 1, Data.ordinal(pl2)], "sub": Data.TRACKS[track_i]["name"],
				"buttons": [["Standings", "standings"]], "confetti": pl2 == 1}
	menus.show_results(res if mode != "tt" else [me], mode, info)

# ------------------------------------------------------------------ loop
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "race" and not paused:
		toggle_pause()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and not touch:
		touch = true
		hud.set_touch(state == "race" and not paused)
	if e.is_action_pressed("pause"):
		if state == "race":
			toggle_pause()
			get_viewport().set_input_as_handled()
			return
	if e.is_action_pressed("mute"):
		_toggle_sound()
	if e.is_action_pressed("ui_cancel") and state != "race":
		if menus.current in ["drivers", "howto"]:
			_on_action("back", null)
		elif menus.current == "tracks":
			_on_action("back", null)

func gather_input() -> Dictionary:
	var steer := Input.get_axis("left", "right")
	var thr := Input.get_action_strength("accel")
	var brk := Input.get_action_strength("brake")
	var drift := Input.is_action_pressed("drift")
	var item := Input.is_action_just_pressed("item")
	if touch and hud.touch.visible:
		var tp = hud.touch
		if tp.held("left"):
			steer -= 1.0
		if tp.held("right"):
			steer += 1.0
		if tp.held("drift"):
			drift = true
		if tp.held("brake"):
			brk = 1.0
		elif thr < 0.5:
			thr = 1.0
		if tp.take_item():
			item = true
	return {"steer": clampf(steer, -1.0, 1.0), "throttle": thr, "brake": brk, "drift": drift, "item": item}

func _physics_process(dt: float) -> void:
	if paused:
		return
	if state == "title" or state == "race" or state == "results":
		race.step(dt, gather_input() if state == "race" else {})
	if state == "race":
		hud.update_hud(race, dt)
		var p = race.player
		if p:
			sfx.set_engine(true, absf(p.speed) / p.max_speed, p.boost_t > 0.0)
			if race.is_wrong_way():
				hud.show_warn("WRONG WAY!", Color(1, 0.3, 0.3))
