extends Node3D
## One kart: low-poly model built in code + arcade driving physics
## (drift charge levels, boosts, spin-outs, shield, magnet tow).

const Data = preload("res://scripts/data.gd")
const DRIFT_LEVELS := [0.8, 1.7, 2.7]
const DRIFT_BOOST := [0.5, 0.85, 1.3]
const DRIFT_COLORS := [Color(0.3, 0.75, 1.0), Color(1.0, 0.55, 0.1), Color(0.85, 0.35, 1.0)]

var driver: Dictionary
var driver_index := 0
var is_player := false
var is_ghost := false
var track

# physics state
var pos := Vector3.ZERO
var yaw := 0.0
var move_yaw := 0.0
var speed := 0.0
var idx := 0
var d := 0.0
var lat := 0.0
var lap := -1
var prev_d := 0.0
var max_speed := 28.0
var accel_rate := 14.0
var turn_rate := 1.9
var weight := 3.0
var speed_mult := 1.0

var drifting := false
var drift_dir := 0.0
var drift_charge := 0.0
var drift_level := 0
var boost_t := 0.0
var spin_t := 0.0
var shield_t := 0.0
var magnet_t := 0.0
var hop_t := 0.0
var squash := 0.0
var wall_hit := 0.0
var offroad := false

# race state
var finished := false
var finish_time := 0.0
var place := 1
var item := -1
var item_count := 0
var roulette_t := 0.0
var lap_start := 0.0
var best_lap := 0.0
var points := 0
var ai_lane := 0.0
var ai_item_t := 0.0
var ai_skill := 1.0

# visuals
var body: Node3D
var wheels: Array[Node3D] = []
var shield_mesh: MeshInstance3D
var spark_l: CPUParticles3D
var spark_r: CPUParticles3D
var flame: CPUParticles3D
var dust: CPUParticles3D
var _wheel_spin := 0.0
var _vis_yaw := 0.0
var _roll := 0.0
var _prop: Node3D = null

static var _mat_cache := {}

static func m(c: Color, unshaded: bool = false, alpha: bool = false) -> StandardMaterial3D:
	var key := c.to_html() + str(unshaded) + str(alpha)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = 0.6
	if unshaded:
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = mt
	return mt

func setup(drv_index: int, player: bool, ghost: bool = false) -> void:
	driver_index = drv_index
	driver = Data.DRIVERS[drv_index]
	is_player = player
	is_ghost = ghost
	var sp: int = driver["speed"]
	var ac: int = driver["accel"]
	var hd: int = driver["handling"]
	max_speed = 25.0 + sp * 1.5
	accel_rate = 7.0 + ac * 2.4
	turn_rate = 1.55 + hd * 0.15
	weight = float(driver["weight"])
	_build_model()

# ---------------------------------------------------------------- model
func _part(parent: Node3D, mesh: Mesh, c: Color, p: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m(c, false, is_ghost) if not is_ghost else m(Color(c.r, c.g, c.b, 0.38), false, true)
	mi.position = p
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = s; return b
static func cyl(r: float, h: float, rt: float = -1.0, seg: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new(); c.bottom_radius = r; c.top_radius = r if rt < 0.0 else rt; c.height = h; c.radial_segments = seg; c.rings = 1; return c
static func sph(r: float, seg: int = 12) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = seg; s.rings = seg / 2; return s

func _build_model() -> void:
	body = Node3D.new()
	add_child(body)
	var c: Color = driver["color"]
	var a: Color = driver["accent"]
	var skin: Color = driver["skin"]
	var dark := Color(0.13, 0.13, 0.16)
	_part(body, box(Vector3(1.45, 0.38, 2.1)), c, Vector3(0, 0.48, 0))
	_part(body, box(Vector3(1.15, 0.28, 0.7)), a, Vector3(0, 0.42, -1.25))
	_part(body, box(Vector3(1.7, 0.22, 0.35)), dark, Vector3(0, 0.36, -1.62))
	_part(body, box(Vector3(1.0, 0.65, 0.25)), dark, Vector3(0, 0.88, 0.62))
	_part(body, box(Vector3(1.6, 0.1, 0.45)), a, Vector3(0, 1.18, 1.05))
	_part(body, box(Vector3(0.1, 0.45, 0.1)), dark, Vector3(-0.5, 0.92, 1.05))
	_part(body, box(Vector3(0.1, 0.45, 0.1)), dark, Vector3(0.5, 0.92, 1.05))
	_part(body, cyl(0.12, 0.4), Color(0.7, 0.7, 0.75), Vector3(-0.35, 0.5, 1.15), Vector3(PI * 0.5, 0, 0))
	_part(body, cyl(0.12, 0.4), Color(0.7, 0.7, 0.75), Vector3(0.35, 0.5, 1.15), Vector3(PI * 0.5, 0, 0))
	# steering wheel
	_part(body, cyl(0.22, 0.06, -1, 10), dark, Vector3(0, 0.95, -0.35), Vector3(-1.0, 0, 0))
	# wheels
	for wp in [Vector3(-0.82, 0.34, -0.72), Vector3(0.82, 0.34, -0.72), Vector3(-0.85, 0.4, 0.75), Vector3(0.85, 0.4, 0.75)]:
		var holder := Node3D.new()
		holder.position = wp
		body.add_child(holder)
		var r := 0.34 if wp.z < 0.0 else 0.42
		_part(holder, cyl(r, 0.34, -1, 10), dark, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		_part(holder, cyl(r * 0.45, 0.36, -1, 6), a, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		wheels.append(holder)
	# driver
	_part(body, cyl(0.32, 0.5), c.darkened(0.2), Vector3(0, 1.0, 0.25))
	var head := _part(body, sph(0.46), skin, Vector3(0, 1.55, 0.2))
	_part(head, sph(0.13, 8), Color(1, 1, 1), Vector3(-0.17, 0.08, -0.38))
	_part(head, sph(0.13, 8), Color(1, 1, 1), Vector3(0.17, 0.08, -0.38))
	_part(head, sph(0.07, 6), Color(0.05, 0.05, 0.1), Vector3(-0.17, 0.08, -0.49))
	_part(head, sph(0.07, 6), Color(0.05, 0.05, 0.1), Vector3(0.17, 0.08, -0.49))
	_part(head, box(Vector3(0.22, 0.05, 0.05)), Color(0.55, 0.15, 0.15), Vector3(0, -0.17, -0.42))
	_part(head, sph(0.48, 12), c, Vector3(0, 0.12, 0.06)).scale = Vector3(1.0, 0.75, 1.0)
	_part(head, box(Vector3(0.8, 0.12, 0.4)), a, Vector3(0, 0.12, -0.35))
	match int(driver["hat"]):
		1: # lightning fin
			_part(head, box(Vector3(0.08, 0.45, 0.6)), a, Vector3(0, 0.6, 0.05))
		2: # bunny ears
			_part(head, box(Vector3(0.14, 0.6, 0.08)), Color(1, 1, 1), Vector3(-0.2, 0.75, 0.05), Vector3(0, 0, 0.2))
			_part(head, box(Vector3(0.14, 0.6, 0.08)), Color(1, 1, 1), Vector3(0.2, 0.75, 0.05), Vector3(0, 0, -0.2))
		3: # horns
			_part(head, cyl(0.1, 0.4, 0.0, 6), Color(1, 0.95, 0.8), Vector3(-0.32, 0.55, 0.05), Vector3(0, 0, 0.5))
			_part(head, cyl(0.1, 0.4, 0.0, 6), Color(1, 0.95, 0.8), Vector3(0.32, 0.55, 0.05), Vector3(0, 0, -0.5))
		4: # propeller cap
			_part(head, cyl(0.04, 0.3), dark, Vector3(0, 0.62, 0.05))
			_part(head, box(Vector3(0.9, 0.04, 0.14)), a, Vector3(0, 0.78, 0.05)).name = "Prop"
		5: # star antenna
			_part(head, cyl(0.03, 0.5), dark, Vector3(0.15, 0.7, 0.1))
			_part(head, sph(0.13, 8), a, Vector3(0.15, 0.98, 0.1))
		_: # tuft
			_part(head, sph(0.16, 8), a, Vector3(0, 0.62, 0.05))
	if is_ghost:
		return
	# blob shadow
	var sh := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(2.0, 2.8)
	sh.mesh = qm
	sh.material_override = m(Color(0, 0, 0, 0.35), true, true)
	sh.position = Vector3(0, 0.04, 0)
	add_child(sh)
	shield_mesh = MeshInstance3D.new()
	shield_mesh.mesh = sph(1.7, 16)
	shield_mesh.material_override = m(Color(0.4, 0.9, 1.0, 0.3), true, true)
	shield_mesh.position = Vector3(0, 0.9, 0)
	shield_mesh.visible = false
	body.add_child(shield_mesh)
	spark_l = _particles(Vector3(-0.8, 0.15, 0.9), Color(0.3, 0.75, 1.0), 0.32, Vector3(-0.6, 1, 1), 4.0)
	spark_r = _particles(Vector3(0.8, 0.15, 0.9), Color(0.3, 0.75, 1.0), 0.32, Vector3(0.6, 1, 1), 4.0)
	flame = _particles(Vector3(0, 0.5, 1.4), Color(1.0, 0.55, 0.15), 0.22, Vector3(0, 0.2, 1), 7.0)
	dust = _particles(Vector3(0, 0.2, 1.0), Color(0.85, 0.78, 0.6, 0.8), 0.5, Vector3(0, 1, 1), 2.0)

static var _part_mesh: Mesh

func _particles(p: Vector3, col: Color, life: float, dir: Vector3, vel: float) -> CPUParticles3D:
	if _part_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.16, 0.16)
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.vertex_color_use_as_albedo = true
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.material = pm
		_part_mesh = bm
	var cp := CPUParticles3D.new()
	cp.mesh = _part_mesh
	cp.amount = 20
	cp.lifetime = life
	cp.local_coords = false
	cp.direction = dir
	cp.spread = 30.0
	cp.initial_velocity_min = vel * 0.6
	cp.initial_velocity_max = vel
	cp.gravity = Vector3(0, -6, 0)
	cp.scale_amount_min = 0.6
	cp.scale_amount_max = 1.3
	cp.color = col
	cp.emitting = false
	cp.position = p
	body.add_child(cp)
	return cp

# ---------------------------------------------------------------- physics
func place_at(tr, dist: float, lateral: float) -> void:
	track = tr
	d = tr.wrap_d(dist)
	lat = lateral
	pos = tr.point_at(d, lat)
	yaw = tr.yaw_at(d)
	move_yaw = yaw
	idx = int(d / tr.step) % tr.n
	prev_d = d
	speed = 0.0
	lap = -1 if d > tr.length * 0.5 else 0
	_update_visual(0.0)

func progress() -> float:
	return lap * track.length + d

func charge_level() -> int:
	var lv := 0
	for k in 3:
		if drift_charge >= DRIFT_LEVELS[k]:
			lv = k + 1
	return lv

func add_boost(t: float) -> void:
	boost_t = maxf(boost_t, t)

## Returns true if the hit landed (false if a shield absorbed it).
func hit(duration: float = 1.1) -> bool:
	if shield_t > 0.0:
		shield_t = 0.0
		return false
	if spin_t > 0.0 or magnet_t > 0.0:
		return false
	spin_t = duration
	speed *= 0.35
	drifting = false
	drift_charge = 0.0
	boost_t = 0.0
	return true

## inp: steer (-1..1, + = right), throttle, brake (0..1), drift (bool)
## Returns the drift level released this frame (0 if none).
func step(dt: float, inp: Dictionary) -> int:
	var released := 0
	var steer: float = inp.get("steer", 0.0)
	var throttle: float = inp.get("throttle", 0.0)
	var brake: float = inp.get("brake", 0.0)
	var drift_btn: bool = inp.get("drift", false)
	var mx := max_speed * speed_mult
	offroad = absf(lat) > track.half + 0.4
	if offroad and boost_t <= 0.0 and magnet_t <= 0.0:
		mx *= 0.55
	if boost_t > 0.0:
		boost_t -= dt
		mx *= 1.35
	if magnet_t > 0.0:
		magnet_t -= dt
		mx *= 1.3
	shield_t = maxf(0.0, shield_t - dt)
	hop_t = maxf(0.0, hop_t - dt)
	wall_hit = maxf(0.0, wall_hit - dt)
	if spin_t > 0.0:
		spin_t -= dt
		throttle = 0.0
		brake = 0.0
		steer = 0.0
		drift_btn = false
		speed = move_toward(speed, 0.0, 22.0 * dt)
	# longitudinal
	if boost_t > 0.0 or magnet_t > 0.0:
		speed = move_toward(speed, mx, 45.0 * dt)
	elif throttle > 0.05:
		if speed < mx:
			speed = minf(mx, speed + accel_rate * throttle * (1.0 - clampf(speed / mx, 0.0, 1.0) * 0.6) * dt)
		else:
			speed = move_toward(speed, mx, 14.0 * dt)
	elif brake > 0.05:
		speed = move_toward(speed, -9.0, (30.0 if speed > 0.0 else 10.0) * brake * dt)
	else:
		speed = move_toward(speed, 0.0, 7.0 * dt)
	if speed > mx and boost_t <= 0.0:
		speed = move_toward(speed, mx, 18.0 * dt)
	# drift start / release
	if drift_btn and not drifting and absf(steer) > 0.25 and speed > 11.0 and spin_t <= 0.0:
		drifting = true
		drift_dir = signf(steer)
		drift_charge = 0.0
		hop_t = 0.22
	if drifting and (not drift_btn or speed < 7.0 or spin_t > 0.0):
		released = charge_level()
		if released > 0 and spin_t <= 0.0:
			add_boost(DRIFT_BOOST[released - 1])
		else:
			released = 0
		drifting = false
		drift_charge = 0.0
	# turning
	var turn: float
	if drifting:
		var s := clampf(steer * drift_dir, -1.0, 1.0)
		turn = drift_dir * (0.75 + 0.55 * s) * turn_rate * 1.05
		drift_charge += dt * (0.7 + 0.6 * maxf(s, 0.0))
	else:
		turn = steer * turn_rate
	var sf := clampf(absf(speed) / 7.0, 0.0, 1.0) * signf(speed)
	turn *= 1.0 - 0.22 * clampf(speed / max_speed, 0.0, 1.2)
	if spin_t > 0.0:
		_vis_yaw += dt * 14.0
	else:
		_vis_yaw = lerp_angle(_vis_yaw, 0.0, minf(1.0, dt * 8.0))
	yaw -= turn * sf * dt
	var grip := 2.6 if drifting else 8.5
	move_yaw = lerp_angle(move_yaw, yaw, 1.0 - exp(-grip * dt))
	var dir := Vector3(-sin(move_yaw), 0.0, -cos(move_yaw))
	pos += dir * speed * dt
	_constrain(dt)
	drift_level = charge_level() if drifting else 0
	_update_visual(dt)
	return released

func _constrain(_dt: float) -> void:
	var pr: Array = track.project(pos, idx)
	idx = pr[0]
	prev_d = d
	d = pr[1]
	lat = pr[2]
	var lim: float = track.half + 3.0 - 0.95
	if absf(lat) > lim:
		var r: Vector3 = track.right_at(d)
		var side := signf(lat)
		pos -= r * side * (absf(lat) - lim)
		lat = side * lim
		var dir := Vector3(-sin(move_yaw), 0.0, -cos(move_yaw))
		var into := dir.dot(r * side)
		if into > 0.08:
			speed *= 1.0 - 0.45 * into
			var ty: float = track.yaw_at(d)
			if speed < 0.0:
				ty += PI
			move_yaw = lerp_angle(move_yaw, ty, 0.6)
			yaw = lerp_angle(yaw, ty, 0.35)
			if wall_hit <= 0.0 and absf(speed) > 6.0:
				wall_hit = 0.35
	var c: Vector3 = track.point_at(d, lat)
	pos.y = c.y
	# lap counting
	var L: float = track.length
	if prev_d > L * 0.75 and d < L * 0.25:
		lap += 1
	elif prev_d < L * 0.25 and d > L * 0.75:
		lap -= 1

func _update_visual(dt: float) -> void:
	if track == null:
		return
	var t: Vector3 = track.tangent_at(d)
	var pitch := asin(clampf(t.y, -0.9, 0.9))
	var steer_roll := 0.0
	if drifting:
		steer_roll = -drift_dir * 0.08
	_roll = lerpf(_roll, steer_roll, minf(1.0, dt * 6.0)) if dt > 0.0 else steer_roll
	var hop := sin((0.22 - hop_t) / 0.22 * PI) * 0.45 if hop_t > 0.0 else 0.0
	transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), pos)
	if body:
		var dy := (drift_dir * 0.38 if drifting else 0.0) + _vis_yaw
		body.rotation = Vector3(0, dy, _roll)
		body.position = Vector3(0, hop + (sin(Time.get_ticks_msec() * 0.03) * 0.025 if absf(speed) > 3.0 else 0.0), 0)
		var sq := 1.0 + squash
		body.scale = Vector3(sq, 1.0 / sq, sq)
		squash = lerpf(squash, 0.0, minf(1.0, dt * 8.0))
	_wheel_spin += speed * dt / 0.38
	for w in wheels:
		w.rotation.x = -_wheel_spin
	if is_ghost or spark_l == null:
		return
	shield_mesh.visible = shield_t > 0.0
	if shield_t > 0.0:
		shield_mesh.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.04)
	var lv := charge_level() if drifting else 0
	spark_l.emitting = lv > 0
	spark_r.emitting = lv > 0
	if lv > 0:
		spark_l.color = DRIFT_COLORS[lv - 1]
		spark_r.color = DRIFT_COLORS[lv - 1]
	flame.emitting = boost_t > 0.0 or magnet_t > 0.0
	flame.color = Color(0.4, 0.8, 1.0) if magnet_t > 0.0 else Color(1.0, 0.55, 0.15)
	dust.emitting = offroad and absf(speed) > 6.0
	if _prop == null:
		_prop = body.find_child("Prop", true, false)
		if _prop == null:
			_prop = body
	if _prop != body:
		_prop.rotation.y += dt * (8.0 + speed)
