extends Node3D
## Race manager: grid, AI drivers with rubber-banding, item boxes, power-ups,
## lap/position tracking, ghost record/playback and the chase camera.

signal event(kind: String, data: Variant)
signal race_over(results: Array)

const Data = preload("res://scripts/data.gd")
const Kart = preload("res://scripts/kart.gd")
const Track = preload("res://scripts/track.gd")
const GHOST_DT := 0.05

var mode := "attract" # attract | gp | quick | tt
var track = null
var karts: Array = []
var player = null
var state := "idle" # idle | countdown | racing | done
var countdown := 0.0
var race_time := 0.0
var boxes: Array = []
var shots: Array = []
var traps: Array = []
var fx: Array = []
var camera: Camera3D
var cam_yaw := 0.0
var shake := 0.0
var ghost_play := PackedFloat32Array()
var ghost_rec := PackedFloat32Array()
var ghost_kart = null
var _rec_acc := 0.0
var finish_wait := -1.0
var start_press := -1.0
var rng := RandomNumberGenerator.new()
var t_total := 0.0
var wrong_t := 0.0
var _box_mat: StandardMaterial3D
var _cam_snap := true
var _world: Node3D
var fov_bonus := 0.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 2500.0
	add_child(camera)
	camera.current = true

func clear() -> void:
	if _world:
		_world.queue_free()
		remove_child(_world)
	_world = null
	karts.clear(); boxes.clear(); shots.clear(); traps.clear(); fx.clear()
	player = null
	ghost_kart = null
	state = "idle"

## grid: driver indices in starting order (front first). player_drv = -1 for none.
func setup(track_index: int, race_mode: String, grid: Array, player_drv: int, ghost: PackedFloat32Array = PackedFloat32Array()) -> void:
	clear()
	mode = race_mode
	rng.seed = Time.get_ticks_usec()
	_world = Node3D.new()
	add_child(_world)
	track = Track.new()
	_world.add_child(track)
	track.build(track_index)
	var L: float = track.length
	for slot in grid.size():
		var drv: int = grid[slot]
		var k := Kart.new()
		_world.add_child(k)
		var is_p: bool = drv == player_drv and mode != "attract"
		k.setup(drv, is_p)
		var row := slot / 2
		var col := slot % 2
		k.place_at(track, L - 7.0 - row * 7.0 - col * 2.5, -3.4 if col == 0 else 3.4)
		k.ai_skill = rng.randf_range(0.93, 0.985)
		k.ai_lane = rng.randf_range(-0.4, 0.4)
		k.place = slot + 1
		if is_p:
			player = k
		karts.append(k)
	if mode == "tt":
		player.item = Data.ROCKET
		player.item_count = 3
		ghost_play = ghost
		if ghost.size() >= 8:
			ghost_kart = Kart.new()
			_world.add_child(ghost_kart)
			ghost_kart.setup(player.driver_index, false, true)
			ghost_kart.track = track
			_place_ghost(0.0)
	else:
		_make_boxes()
	ghost_rec = PackedFloat32Array()
	_rec_acc = 0.0
	race_time = 0.0
	countdown = 3.6 if mode != "attract" else 0.01
	state = "countdown"
	finish_wait = -1.0
	start_press = -1.0
	wrong_t = 0.0
	_cam_snap = true
	_update_camera(0.016)

func _make_boxes() -> void:
	_box_mat = StandardMaterial3D.new()
	_box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_mat.emission_enabled = true
	_box_mat.emission_energy_multiplier = 0.5
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 1.5, 1.5)
	for d0 in track.item_rows:
		for k in 4:
			var lat: float = (-0.6 + k * 0.4) * track.half
			var p: Vector3 = track.point_at(d0, lat) + Vector3(0, 1.3, 0)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = _box_mat
			mi.position = p
			var q := Label3D.new()
			q.text = "?"
			q.font_size = 96
			q.outline_size = 18
			q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			q.no_depth_test = false
			mi.add_child(q)
			_world.add_child(mi)
			boxes.append({"node": mi, "pos": p, "t": 0.0})

# ---------------------------------------------------------------- main step
func step(dt: float, pin: Dictionary) -> void:
	if state == "idle":
		return
	t_total += dt
	_update_fx(dt)
	if state == "countdown":
		var prev := countdown
		countdown -= dt
		if mode != "attract" and ceili(prev) != ceili(countdown) and countdown > 0.0 and countdown < 3.0:
			event.emit("count", ceili(countdown))
		if player and float(pin.get("throttle", 0.0)) > 0.5 and start_press < 0.0:
			start_press = countdown
		if countdown <= 0.0:
			state = "racing"
			race_time = 0.0
			if mode != "attract":
				event.emit("go", null)
			if player and start_press > 0.1 and start_press < 1.0:
				player.add_boost(1.1)
				event.emit("start_boost", null)
			for k in karts:
				k.lap_start = 0.0
				if k != player and rng.randf() < 0.5:
					k.add_boost(rng.randf_range(0.3, 0.9))
		for k in karts:
			k._update_visual(dt)
		_spin_boxes(dt)
		_update_camera(dt)
		return
	race_time += dt
	for k in karts:
		var inp: Dictionary
		var controlled: bool = k == player and not k.finished
		if controlled and k.magnet_t <= 0.0:
			inp = pin
		else:
			inp = _ai_input(k, k.magnet_t > 0.0 or k.finished)
		if k != player:
			k.speed_mult = _rubber(k)
		elif k.finished:
			k.speed_mult = 0.8
		var prev_lap: int = k.lap
		var prev_wall: float = k.wall_hit
		var rel: int = k.step(dt, inp)
		if k == player:
			if rel > 0:
				event.emit("drift_boost", rel)
			if k.wall_hit > prev_wall:
				shake = maxf(shake, 0.25)
				event.emit("bump", null)
		if k.lap > prev_lap:
			_on_lap(k)
		# items
		if k.roulette_t > 0.0:
			k.roulette_t -= dt
			if k.roulette_t <= 0.0:
				k.item = _roll_item(k)
				k.item_count = 1
				k.ai_item_t = rng.randf_range(0.6, 3.0)
				if k == player:
					event.emit("item_get", k.item)
		if controlled:
			if pin.get("item", false):
				_use_item(k)
		elif k != player and not k.finished:
			_ai_items(k, dt)
		# boost pads
		for bp in track.boost_pads:
			var dd: float = wrapf(k.d - float(bp[0]), -track.length * 0.5, track.length * 0.5)
			if absf(dd) < 2.4 and absf(k.lat - float(bp[1])) < 2.4 and k.spin_t <= 0.0:
				if k.boost_t < 0.6 and k == player:
					event.emit("pad", null)
				k.add_boost(0.9)
	_collide_karts()
	_update_boxes(dt)
	_update_shots(dt)
	_update_traps(dt)
	_update_places()
	if player and not player.finished:
		var dir := Vector3(-sin(player.move_yaw), 0, -cos(player.move_yaw))
		var tng: Vector3 = track.tangent_at(player.d)
		if dir.dot(tng) < -0.35 and player.speed > 3.0:
			wrong_t += dt
		else:
			wrong_t = 0.0
		_rec_acc += dt
		while _rec_acc >= GHOST_DT:
			_rec_acc -= GHOST_DT
			ghost_rec.append_array(PackedFloat32Array([player.pos.x, player.pos.y, player.pos.z, player.yaw]))
	if ghost_kart:
		_place_ghost(race_time)
	if finish_wait >= 0.0:
		finish_wait -= dt
		if finish_wait < 0.0:
			_end_race()
	_update_camera(dt)

func is_wrong_way() -> bool:
	return wrong_t > 1.2

func _place_ghost(t: float) -> void:
	var frames := ghost_play.size() / 4
	if frames < 2:
		return
	var fi := t / GHOST_DT
	var i := mini(int(fi), frames - 2)
	var f := clampf(fi - i, 0.0, 1.0)
	var a := Vector3(ghost_play[i * 4], ghost_play[i * 4 + 1], ghost_play[i * 4 + 2])
	var b := Vector3(ghost_play[i * 4 + 4], ghost_play[i * 4 + 5], ghost_play[i * 4 + 6])
	var y := lerp_angle(ghost_play[i * 4 + 3], ghost_play[i * 4 + 7], f)
	ghost_kart.pos = a.lerp(b, f)
	ghost_kart.yaw = y
	ghost_kart.transform = Transform3D(Basis(Vector3.UP, y), ghost_kart.pos)
	ghost_kart.visible = int(fi) < frames

# ---------------------------------------------------------------- laps & places
func _on_lap(k) -> void:
	if k.lap < 1:
		return
	var lt: float = race_time - k.lap_start
	k.lap_start = race_time
	if k.best_lap <= 0.0 or lt < k.best_lap:
		k.best_lap = lt
	if k == player:
		event.emit("lap", {"lap": k.lap, "time": lt})
	if k.lap >= Data.LAPS and not k.finished:
		k.finished = true
		k.finish_time = race_time
		_update_places()
		if k == player:
			event.emit("finish", k.place)
			finish_wait = 3.2
		elif mode == "attract" and finish_wait < 0.0:
			finish_wait = 2.0

func _update_places() -> void:
	var order := karts.duplicate()
	order.sort_custom(func(a, b):
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		return a.progress() > b.progress())
	for i in order.size():
		order[i].place = i + 1

func leader():
	for k in karts:
		if k.place == 1:
			return k
	return karts[0]

func _end_race() -> void:
	state = "done"
	var L: float = track.length
	var res := []
	for k in karts:
		var t: float = k.finish_time
		if not k.finished:
			var remain: float = Data.LAPS * L - k.progress()
			t = race_time + remain / maxf(10.0, k.max_speed * 0.85)
		res.append({"driver": k.driver_index, "player": k == player, "time": t, "best_lap": k.best_lap, "finished": k.finished})
	res.sort_custom(func(a, b): return a["time"] < b["time"])
	for i in res.size():
		res[i]["place"] = i + 1
	race_over.emit(res)

# ---------------------------------------------------------------- AI
func _rubber(k) -> float:
	var base: float = k.ai_skill
	if player == null or mode == "attract" or player.finished:
		return base
	var gap: float = k.progress() - player.progress()
	if gap > 0.0:
		return base * lerpf(1.0, 0.86, clampf(gap / 220.0, 0.0, 1.0))
	return base * lerpf(1.0, 1.12, clampf(-gap / 200.0, 0.0, 1.0))

func _ai_input(k, autopilot: bool) -> Dictionary:
	var look: float = 7.0 + absf(k.speed) * 0.45
	var lane: float = (sin(t_total * 0.31 + k.driver_index * 1.7) * 0.45 + k.ai_lane * 0.3) * track.half
	if autopilot:
		lane = clampf(k.lat, -2.0, 2.0)
	for tr in traps:
		var gap: float = wrapf(float(tr["d"]) - k.d, -track.length * 0.5, track.length * 0.5)
		if gap > 0.0 and gap < 28.0 and absf(float(tr["lat"]) - lane) < 3.0:
			lane = float(tr["lat"]) + (4.0 if lane >= float(tr["lat"]) else -4.0)
	lane = clampf(lane, -track.half + 1.0, track.half - 1.0)
	var target: Vector3 = track.point_at(k.d + look, lane)
	var to: Vector3 = target - k.pos
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - k.yaw, -PI, PI)
	var steer := clampf(-diff * 2.4, -1.0, 1.0)
	var throttle := 1.0
	var b := absf(track.bend(k.d + 5.0, 30.0))
	if b > 1.0 and k.speed > k.max_speed * 0.8:
		throttle = 0.4
	if autopilot:
		return {"steer": steer, "throttle": 1.0, "brake": 0.0, "drift": false}
	var drift := false
	var ba: float = track.bend(k.d + 4.0, 28.0)
	if k.drifting:
		drift = steer * k.drift_dir > -0.3 and absf(ba) > 0.2
	else:
		drift = absf(ba) > 0.55 and absf(steer) > 0.3 and k.speed > 14.0 and rng.randf() < 0.3
	return {"steer": steer, "throttle": throttle, "brake": 0.0, "drift": drift}

func _ai_items(k, dt: float) -> void:
	if k.item < 0 or k.roulette_t > 0.0:
		return
	k.ai_item_t -= dt
	if k.ai_item_t > 0.0:
		return
	var use := false
	match k.item:
		Data.ROCKET, Data.MAGNET:
			use = absf(track.bend(k.d, 40.0)) < 0.5
		Data.BALL, Data.BEE:
			for o in karts:
				var g: float = o.progress() - k.progress()
				if o != k and g > 3.0 and g < 70.0:
					use = true
			if k.place == 1 and k.item == Data.BEE:
				use = false
		Data.GOO:
			for o in karts:
				var g: float = k.progress() - o.progress()
				if o != k and g > 3.0 and g < 35.0:
					use = true
		Data.SHIELD:
			use = true
	if k.ai_item_t < -8.0 and k.place != 1:
		use = true
	if use:
		_use_item(k)
	else:
		k.ai_item_t = 0.4

func _roll_item(k) -> int:
	var rank := float(k.place - 1) / maxf(1.0, karts.size() - 1.0)
	var w: Array
	if mode == "tt":
		return Data.ROCKET
	if rank < 0.3:
		w = [8, 30, 35, 0, 27, 0]
	elif rank < 0.7:
		w = [20, 22, 15, 18, 13, 12]
	else:
		w = [30, 8, 0, 27, 5, 30]
	var total := 0
	for x in w:
		total += int(x)
	var r := rng.randi_range(1, total)
	for i in w.size():
		r -= int(w[i])
		if r <= 0:
			return i
	return Data.ROCKET

# ---------------------------------------------------------------- items
func _use_item(k) -> void:
	if k.item < 0 or k.roulette_t > 0.0 or k.spin_t > 0.0:
		return
	var kind: int = k.item
	match kind:
		Data.ROCKET:
			k.add_boost(1.3)
			k.squash = 0.25
		Data.BALL:
			var rel := wrapf(k.move_yaw - track.yaw_at(k.d), -PI, PI)
			_spawn_shot(Data.BALL, k, k.d + 2.6, k.lat, -sin(rel) * 14.0, maxf(k.speed, 0.0) + 24.0, 5.0, null)
		Data.BEE:
			var tgt = null
			for o in karts:
				if o.place == k.place - 1:
					tgt = o
			_spawn_shot(Data.BEE, k, k.d + 2.0, k.lat, 0.0, maxf(k.speed, 0.0) + 22.0, 7.0, tgt)
		Data.GOO:
			_spawn_trap(k.d - 3.6, k.lat)
		Data.SHIELD:
			k.shield_t = 10.0
		Data.MAGNET:
			k.magnet_t = 2.6
	k.item_count -= 1
	if k.item_count <= 0:
		k.item = -1
		k.item_count = 0
	event.emit("use_item", {"kind": kind, "player": k == player})

func _spawn_shot(kind: int, owner, d0: float, lat: float, vlat: float, spd: float, life: float, tgt) -> void:
	var node := Node3D.new()
	if kind == Data.BALL:
		var s := Kart.sph(0.6, 12)
		var mi := MeshInstance3D.new(); mi.mesh = s; mi.material_override = Kart.m(Color(0.25, 0.55, 1.0)); node.add_child(mi)
		var band := MeshInstance3D.new(); band.mesh = Kart.cyl(0.62, 0.22, -1, 12); band.material_override = Kart.m(Color(1, 1, 1)); node.add_child(band)
	else:
		var mi := MeshInstance3D.new(); mi.mesh = Kart.sph(0.5, 10); mi.material_override = Kart.m(Color(1.0, 0.85, 0.1)); mi.scale = Vector3(0.9, 0.9, 1.3); node.add_child(mi)
		var st := MeshInstance3D.new(); st.mesh = Kart.box(Vector3(0.95, 0.95, 0.22)); st.material_override = Kart.m(Color(0.1, 0.1, 0.1)); node.add_child(st)
		for sx in [-1.0, 1.0]:
			var wing := MeshInstance3D.new(); wing.mesh = Kart.box(Vector3(0.8, 0.05, 0.4)); wing.material_override = Kart.m(Color(1, 1, 1, 0.7), true, true)
			wing.position = Vector3(sx * 0.5, 0.45, 0.1); node.add_child(wing)
	_world.add_child(node)
	shots.append({"kind": kind, "node": node, "d": d0, "prog": owner.progress() + (d0 - owner.d), "lat": lat, "vlat": vlat, "speed": spd, "life": life, "age": 0.0, "owner": owner, "target": tgt})
	_update_shot_pos(shots[-1])

func _update_shot_pos(s: Dictionary) -> void:
	var h := 0.6 if s["kind"] == Data.BALL else 1.5 + sin(float(s["age"]) * 12.0) * 0.25
	var p: Vector3 = track.point_at(s["d"], s["lat"]) + Vector3(0, h, 0)
	var n3: Node3D = s["node"]
	n3.position = p
	n3.rotation = Vector3(-float(s["age"]) * 12.0 if s["kind"] == Data.BALL else 0.0, track.yaw_at(s["d"]), 0)

func _update_shots(dt: float) -> void:
	var lim: float = track.half + 3.0 - 0.7
	for s in shots.duplicate():
		s["life"] -= dt
		s["age"] += dt
		s["d"] = track.wrap_d(s["d"] + s["speed"] * dt)
		s["prog"] += s["speed"] * dt
		if s["kind"] == Data.BALL:
			s["lat"] += s["vlat"] * dt
			if absf(s["lat"]) > lim:
				s["lat"] = signf(s["lat"]) * lim
				s["vlat"] = -s["vlat"]
				if s["vlat"] == 0.0:
					s["vlat"] = 6.0
		else:
			var tgt = s["target"]
			if tgt and not tgt.finished:
				var gap: float = tgt.progress() - s["prog"]
				if gap < 35.0:
					s["lat"] = lerpf(s["lat"], tgt.lat, 1.0 - exp(-7.0 * dt))
				if gap < 0.0:
					s["speed"] = maxf(s["speed"] - 80.0 * dt, 5.0)
		_update_shot_pos(s)
		var p: Vector3 = (s["node"] as Node3D).position
		var done: bool = s["life"] <= 0.0
		for k in karts:
			if k == s["owner"] and s["age"] < 0.6:
				continue
			if k.finished and k != player:
				continue
			if k.pos.distance_to(p - Vector3(0, 0.4, 0)) < 2.0:
				_hit_kart(k, s["owner"])
				done = true
				break
		if done:
			_burst(p, Color(1, 1, 0.6) if s["kind"] == Data.BEE else Color(0.4, 0.7, 1), 18)
			(s["node"] as Node3D).queue_free()
			shots.erase(s)

func _spawn_trap(d0: float, lat: float) -> void:
	var node := Node3D.new()
	var col := Color(0.35, 0.9, 0.25)
	for i in 5:
		var mi := MeshInstance3D.new()
		mi.mesh = Kart.sph(0.6 if i == 0 else 0.4, 10)
		mi.material_override = Kart.m(col)
		var a := i * 1.3
		mi.position = Vector3(cos(a) * 0.6, 0.0, sin(a) * 0.6) if i > 0 else Vector3.ZERO
		mi.scale = Vector3(1.6, 0.35, 1.6)
		node.add_child(mi)
	var eye := MeshInstance3D.new(); eye.mesh = Kart.sph(0.14, 6); eye.material_override = Kart.m(Color(1, 1, 1)); eye.position = Vector3(-0.2, 0.25, 0); node.add_child(eye)
	var eye2 := MeshInstance3D.new(); eye2.mesh = Kart.sph(0.14, 6); eye2.material_override = Kart.m(Color(1, 1, 1)); eye2.position = Vector3(0.2, 0.25, 0); node.add_child(eye2)
	var p: Vector3 = track.point_at(d0, lat) + Vector3(0, 0.12, 0)
	node.position = p
	_world.add_child(node)
	traps.append({"node": node, "pos": p, "d": track.wrap_d(d0), "lat": lat, "life": 40.0})

func _update_traps(dt: float) -> void:
	for t in traps.duplicate():
		t["life"] -= dt
		var gone: bool = t["life"] <= 0.0
		for k in karts:
			if k.pos.distance_to(t["pos"]) < 1.9:
				_hit_kart(k, null, 0.8)
				gone = true
				break
		if gone:
			_burst(t["pos"], Color(0.4, 0.95, 0.3), 14)
			(t["node"] as Node3D).queue_free()
			traps.erase(t)

func _hit_kart(k, by, dur: float = 1.1) -> void:
	if k.hit(dur):
		_burst(k.pos + Vector3(0, 1.5, 0), Color(1, 0.95, 0.3), 22)
		if k == player:
			shake = 0.6
			event.emit("hit_me", null)
		elif by == player and player != null:
			event.emit("hit_other", k.driver_index)
		else:
			event.emit("hit_far", k.pos)
	elif k.shield_t <= 0.0 and k.spin_t <= 0.0:
		_burst(k.pos + Vector3(0, 1, 0), Color(0.5, 0.95, 1.0), 20)
		event.emit("shield_pop", k == player)

func _spin_boxes(dt: float) -> void:
	if _box_mat:
		var h := fposmod(t_total * 0.25, 1.0)
		_box_mat.albedo_color = Color.from_hsv(h, 0.55, 1.0, 0.7)
		_box_mat.emission = Color.from_hsv(h, 0.6, 1.0)
	for b in boxes:
		var n3: Node3D = b["node"]
		n3.rotation.y += dt * 1.6
		n3.rotation.x = sin(t_total * 1.3) * 0.3

func _update_boxes(dt: float) -> void:
	_spin_boxes(dt)
	for b in boxes:
		var n3: Node3D = b["node"]
		if b["t"] > 0.0:
			b["t"] -= dt
			if b["t"] <= 0.0:
				n3.visible = true
				n3.scale = Vector3.ONE * 0.2
			continue
		n3.scale = n3.scale.lerp(Vector3.ONE, minf(1.0, dt * 6.0))
		for k in karts:
			if k.pos.distance_to(b["pos"]) < 2.2:
				b["t"] = 3.0
				n3.visible = false
				_burst(b["pos"], Color.from_hsv(randf(), 0.6, 1.0), 16)
				if k.item < 0 and k.roulette_t <= 0.0 and not k.finished:
					k.roulette_t = 1.1
					if k == player:
						event.emit("box", null)
				break

func _collide_karts() -> void:
	for i in karts.size():
		var a = karts[i]
		for j in range(i + 1, karts.size()):
			var b = karts[j]
			if absf(a.pos.y - b.pos.y) > 2.0:
				continue
			var dx: float = b.pos.x - a.pos.x
			var dz: float = b.pos.z - a.pos.z
			var dist := sqrt(dx * dx + dz * dz)
			if dist > 2.1 or dist < 0.001:
				continue
			var nrm := Vector3(dx / dist, 0, dz / dist)
			var push := (2.1 - dist)
			var wa: float = b.weight / (a.weight + b.weight)
			a.pos -= nrm * push * wa
			b.pos += nrm * push * (1.0 - wa)
			if a.magnet_t > 0.0 or (a.boost_t > 0.0 and a.weight > b.weight + 1.0):
				_hit_kart(b, a, 0.7)
			elif b.magnet_t > 0.0 or (b.boost_t > 0.0 and b.weight > a.weight + 1.0):
				_hit_kart(a, b, 0.7)
			else:
				var sa: float = a.speed
				a.speed = lerpf(a.speed, b.speed, 0.25 * (1.0 - wa))
				b.speed = lerpf(b.speed, sa, 0.25 * wa)
			if a == player or b == player:
				shake = maxf(shake, 0.18)
				event.emit("bump", null)

# ---------------------------------------------------------------- fx & camera
func _burst(p: Vector3, col: Color, count: int) -> void:
	if fx.size() > 24:
		return
	var cp := CPUParticles3D.new()
	cp.mesh = Kart._part_mesh if Kart._part_mesh else Kart.box(Vector3(0.2, 0.2, 0.2))
	cp.amount = count
	cp.one_shot = true
	cp.explosiveness = 0.95
	cp.lifetime = 0.8
	cp.direction = Vector3.UP
	cp.spread = 180.0
	cp.initial_velocity_min = 4.0
	cp.initial_velocity_max = 9.0
	cp.gravity = Vector3(0, -12, 0)
	cp.scale_amount_min = 1.0
	cp.scale_amount_max = 2.2
	cp.color = col
	cp.position = p
	_world.add_child(cp)
	cp.emitting = true
	fx.append({"node": cp, "t": 1.2})

func _update_fx(dt: float) -> void:
	for e in fx.duplicate():
		e["t"] -= dt
		if e["t"] <= 0.0:
			(e["node"] as Node).queue_free()
			fx.erase(e)

func focus_kart():
	if player:
		return player
	if karts.is_empty():
		return null
	return leader()

func _update_camera(dt: float) -> void:
	var k = focus_kart()
	if k == null:
		return
	var orbit: bool = (player != null and player.finished) or mode == "attract"
	var want_yaw: float = lerp_angle(k.yaw, k.move_yaw, 0.5)
	if orbit:
		want_yaw = k.yaw + sin(t_total * 0.25) * 1.2 + (t_total * 0.3 if player != null and player.finished else 0.0)
	cam_yaw = want_yaw if _cam_snap else lerp_angle(cam_yaw, want_yaw, 1.0 - exp(-5.0 * dt))
	var back := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var dist := 7.0 + (1.2 if k.boost_t > 0.0 else 0.0)
	var height := 3.1
	if orbit:
		dist = 9.0
		height = 4.0
	var want: Vector3 = k.pos + back * dist + Vector3(0, height, 0)
	if _cam_snap:
		camera.position = want
		_cam_snap = false
	else:
		camera.position = camera.position.lerp(want, 1.0 - exp(-9.0 * dt))
	camera.position.y = maxf(camera.position.y, k.pos.y + 1.6)
	var look: Vector3 = k.pos + Vector3(0, 1.3, 0) - back * 3.0
	if camera.position.distance_to(look) > 0.1:
		camera.look_at(look, Vector3.UP)
	var fov_t := 72.0 + fov_bonus + (9.0 if (k.boost_t > 0.0 or k.magnet_t > 0.0) else 0.0) + clampf(k.speed / 30.0, 0.0, 1.0) * 4.0
	camera.fov = lerpf(camera.fov, fov_t, 1.0 - exp(-4.0 * dt))
	if shake > 0.0:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.35
		shake = maxf(0.0, shake - dt * 1.8)
