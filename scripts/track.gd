extends Node3D
## Builds a race track entirely from code (Catmull-Rom spline -> road, curbs,
## walls, scenery) and answers spatial queries for karts, AI and items.

const Data = preload("res://scripts/data.gd")
const STEP_TARGET := 2.0
const ROUGH := 3.0

var def: Dictionary
var index := 0
var pts := PackedVector3Array()
var tans := PackedVector3Array()
var rights := PackedVector3Array()
var n := 0
var step := 2.0
var length := 0.0
var half := 8.0
var boost_pads := [] # [d, lat]
var item_rows := []  # d values
var _mm := {}        # key -> {mesh, xforms}
var _mats := {}

# ---------------------------------------------------------------- building
func build(track_index: int) -> void:
	index = track_index
	def = Data.TRACKS[track_index]
	half = def["half"]
	_make_samples(Data.track_points(track_index))
	for b in def["boosts"]:
		boost_pads.append([b[0] * length, b[1]])
	for f in def["items"]:
		item_rows.append(f * length)
	_build_road()
	_build_ground()
	_build_scenery()
	_flush_multimeshes()

func _make_samples(raw: Array) -> void:
	var cps: Array[Vector3] = []
	for p in raw:
		cps.append(Vector3(p[0], p[2], p[1]))
	var dense: Array[Vector3] = []
	var m := cps.size()
	for i in m:
		var p0 := cps[(i - 1 + m) % m]
		var p1 := cps[i]
		var p2 := cps[(i + 1) % m]
		var p3 := cps[(i + 2) % m]
		for s in 40:
			var t := s / 40.0
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	var cum := PackedFloat32Array()
	cum.append(0.0)
	var total := 0.0
	for i in dense.size():
		total += dense[i].distance_to(dense[(i + 1) % dense.size()])
		cum.append(total)
	length = total
	n = int(round(total / STEP_TARGET))
	step = total / n
	var j := 0
	for i in n:
		var d := i * step
		while j < dense.size() - 1 and cum[j + 1] < d:
			j += 1
		var seg := cum[j + 1] - cum[j]
		var f: float = 0.0 if seg <= 0.0 else (d - cum[j]) / seg
		pts.append(dense[j].lerp(dense[(j + 1) % dense.size()], f))
	for i in n:
		var t := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		tans.append(t)
		var r := t.cross(Vector3.UP)
		r.y = 0.0
		rights.append(r.normalized())

# ---------------------------------------------------------------- queries
func wrap_d(d: float) -> float:
	return fposmod(d, length)

func point_at(d: float, lat: float = 0.0) -> Vector3:
	d = wrap_d(d)
	var fi := d / step
	var i := int(fi) % n
	var f := fi - floorf(fi)
	var i2 := (i + 1) % n
	var p := pts[i].lerp(pts[i2], f)
	var r := rights[i].lerp(rights[i2], f).normalized()
	return p + r * lat

func tangent_at(d: float) -> Vector3:
	d = wrap_d(d)
	var fi := d / step
	var i := int(fi) % n
	return tans[i].lerp(tans[(i + 1) % n], fi - floorf(fi)).normalized()

func right_at(d: float) -> Vector3:
	d = wrap_d(d)
	var fi := d / step
	var i := int(fi) % n
	return rights[i].lerp(rights[(i + 1) % n], fi - floorf(fi)).normalized()

func yaw_at(d: float) -> float:
	var t := tangent_at(d)
	return atan2(-t.x, -t.z)

## Turn amount (radians, signed: + = left) between d and d+ahead.
func bend(d: float, ahead: float) -> float:
	var a := yaw_at(d)
	var b := yaw_at(d + ahead)
	return wrapf(b - a, -PI, PI)

## Projects a world position onto the track, searching near `hint` index.
## Returns [index, distance_along, lateral_offset].
func project(p: Vector3, hint: int, window: int = 10) -> Array:
	var best := hint
	var best_d := INF
	for k in range(-window, window + 1):
		var i := (hint + k + n) % n
		var q := pts[i]
		var dx := p.x - q.x
		var dz := p.z - q.z
		var dy := (p.y - q.y) * 2.0
		var dd := dx * dx + dz * dz + dy * dy
		if dd < best_d:
			best_d = dd
			best = i
	var t := tans[best]
	var rel := p - pts[best]
	var along := rel.x * t.x + rel.z * t.z
	var i0 := best
	if along < 0.0:
		i0 = (best - 1 + n) % n
		rel = p - pts[i0]
		t = tans[i0]
		along = rel.x * t.x + rel.z * t.z
	along = clampf(along, 0.0, step)
	var d := wrap_d(i0 * step + along)
	var c := point_at(d)
	var r := right_at(d)
	var lat := (p.x - c.x) * r.x + (p.z - c.z) * r.z
	return [best, d, lat]

func global_index(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in range(0, n, 2):
		var dd := p.distance_squared_to(pts[i])
		if dd < bd:
			bd = dd
			best = i
	return best

## Coarse horizontal distance from p to the nearest road centre sample.
func road_dist(p: Vector3, max_y: float = 1e9) -> float:
	var bd := INF
	for i in range(0, n, 3):
		var q := pts[i]
		if q.y > max_y:
			continue
		var dd := Vector2(p.x - q.x, p.z - q.z).length_squared()
		if dd < bd:
			bd = dd
	return sqrt(bd)

# ---------------------------------------------------------------- meshes
func mat(c: Color, unshaded: bool = false, alpha: bool = false, emit: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [c.to_html(), unshaded, alpha, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

func _vc_mat(_cull_off: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	# a-b along start edge, c-d along end edge (a->b left->right)
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0 and absf(nrm.y) > 0.3:
		nrm = -nrm
	st.set_color(col)
	st.set_normal(nrm)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(d)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)

func _build_road() -> void:
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rc: Color = def["road"]
	var rough: Color = def["rough"]
	var wa: Color = def["wall_a"]
	var wb: Color = def["wall_b"]
	var night: bool = def["night"]
	var curb_w := 0.9
	var edges := [-(half + ROUGH), -(half + curb_w), -half, half, half + curb_w, half + ROUGH]
	var use_skirt: bool = index != 3
	for i in n:
		var i2 := (i + 1) % n
		var c1 := pts[i]
		var c2 := pts[i2]
		var r1 := rights[i]
		var r2 := rights[i2]
		for e in 5:
			var l0: float = edges[e]
			var l1: float = edges[e + 1]
			var drop := -0.06 if (e == 0 or e == 4) else 0.0
			var a := c1 + r1 * l0 + Vector3(0, drop if e == 0 else 0.0, 0)
			var b := c1 + r1 * l1 + Vector3(0, drop if e == 4 else 0.0, 0)
			var c := c2 + r2 * l0 + Vector3(0, drop if e == 0 else 0.0, 0)
			var d := c2 + r2 * l1 + Vector3(0, drop if e == 4 else 0.0, 0)
			var col: Color
			if e == 2:
				col = rc if (i / 3) % 2 == 0 else rc.lightened(0.06)
				if i < 2:
					col = Color(1, 1, 1)
			elif e == 1 or e == 3:
				if night:
					col = wa if (i % 2 == 0) else wb
				else:
					col = Color(1, 0.25, 0.25) if (i % 2 == 0) else Color(1, 1, 1)
			else:
				col = rough if (i / 2) % 2 == 0 else rough.darkened(0.05)
			_quad(road, a, b, c, d, col)
		# walls on both sides
		for side: float in [-1.0, 1.0]:
			var w := (half + ROUGH) * side
			var p1 := c1 + r1 * w
			var p2 := c2 + r2 * w
			var h := 1.1
			var col2 := wa if (i / 3) % 2 == 0 else wb
			_quad(walls, p1, p1 + Vector3(0, h, 0), p2, p2 + Vector3(0, h, 0), col2)
			var o1 := p1 + r1 * 0.5 * side
			var o2 := p2 + r2 * 0.5 * side
			_quad(walls, p1 + Vector3(0, h, 0), o1 + Vector3(0, h, 0), p2 + Vector3(0, h, 0), o2 + Vector3(0, h, 0), col2.darkened(0.15))
			if use_skirt and (c1.y > 0.25 or c2.y > 0.25):
				var g := rough.darkened(0.35)
				_quad(walls, Vector3(o1.x, -0.2, o1.z), o1, Vector3(o2.x, -0.2, o2.z), o2, g)
	# start line checker
	for k in 8:
		var l0 := -half + k * (half * 2.0 / 8.0)
		var l1 := l0 + half * 2.0 / 8.0
		for row in 2:
			var d0 := row * 0.9
			var col := Color(0.08, 0.08, 0.1) if (k + row) % 2 == 0 else Color(1, 1, 1)
			var lift := Vector3(0, 0.03, 0)
			_quad(road, point_at(d0, l0) + lift, point_at(d0, l1) + lift, point_at(d0 + 0.9, l0) + lift, point_at(d0 + 0.9, l1) + lift, col)
	var mi := MeshInstance3D.new()
	mi.mesh = road.commit()
	mi.material_override = _vc_mat(false)
	add_child(mi)
	var wm := MeshInstance3D.new()
	wm.mesh = walls.commit()
	wm.material_override = _vc_mat(true)
	add_child(wm)
	# boost pads
	var pad_st := SurfaceTool.new()
	pad_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bp in boost_pads:
		var d0: float = bp[0]
		var lat: float = bp[1]
		for k in 3:
			var dd := d0 - 2.0 + k * 1.6
			var lift := Vector3(0, 0.05, 0)
			var tip := point_at(dd + 1.4, lat) + lift
			var lft := point_at(dd, lat - 2.0) + lift
			var rgt := point_at(dd, lat + 2.0) + lift
			var lin := point_at(dd + 0.7, lat - 2.0) + lift
			var rin := point_at(dd + 0.7, lat + 2.0) + lift
			var tip2 := point_at(dd + 2.1, lat) + lift
			pad_st.set_color(Color(1, 0.6, 0.1))
			pad_st.set_normal(Vector3.UP)
			for v in [lft, tip, lin, lin, tip, tip2, rgt, rin, tip, rin, tip2, tip]:
				pad_st.add_vertex(v)
	var pm := MeshInstance3D.new()
	pm.mesh = pad_st.commit()
	var padm := _vc_mat(true)
	padm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.material_override = padm
	add_child(pm)
	# start arch
	var d_arch := 1.5
	for side: float in [-1.0, 1.0]:
		var p := point_at(d_arch, (half + ROUGH + 0.8) * side)
		_add("arch_post", _cyl(0.5, 7.0), mat(wa), Transform3D(Basis(), p + Vector3(0, 3.5, 0)))
	var top := point_at(d_arch)
	var ab := Basis(Vector3.UP, yaw_at(d_arch))
	_add("arch_top", _box(Vector3((half + ROUGH + 0.8) * 2.0 + 1.0, 1.4, 1.0)), mat(wb), Transform3D(ab, top + Vector3(0, 7.2, 0)))
	_add("arch_band", _box(Vector3((half + ROUGH) * 2.0, 0.5, 1.05)), mat(wa), Transform3D(ab, top + Vector3(0, 7.2, 0)))
	# pillars under elevated sections (figure-eight bridge)
	if index == 3:
		for i in range(0, n, 6):
			var c := pts[i]
			if c.y < 2.0:
				continue
			for side: float in [-1.0, 1.0]:
				var p := c + rights[i] * (half + ROUGH - 0.5) * side
				if road_dist(p, c.y - 4.0) < half + ROUGH + 2.0:
					continue
				_add("pillar", _cyl(0.45, 1.0), mat(Color(0.35, 0.3, 0.55)), Transform3D(Basis().scaled(Vector3(1, p.y, 1)), Vector3(p.x, p.y * 0.5, p.z)))
		# underside of the bridge deck
		var under := SurfaceTool.new()
		under.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n:
			var i2 := (i + 1) % n
			if pts[i].y < 1.0:
				continue
			var off := Vector3(0, -0.6, 0)
			var w := half + ROUGH + 0.5
			_quad(under, pts[i] - rights[i] * w + off, pts[i] + rights[i] * w + off, pts[i2] - rights[i2] * w + off, pts[i2] + rights[i2] * w + off, Color(0.22, 0.18, 0.4))
		var um := MeshInstance3D.new()
		um.mesh = under.commit()
		um.material_override = _vc_mat(true)
		add_child(um)

func _build_ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1800, 1800)
	g.mesh = pm
	g.material_override = mat(def["ground"])
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= n
	g.position = Vector3(c.x, -0.25, c.z)
	add_child(g)

# ---------------------------------------------------------------- scenery
func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = s; return b
func _cyl(r: float, h: float, r_top: float = -1.0, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new(); c.bottom_radius = r; c.top_radius = r if r_top < 0.0 else r_top
	c.height = h; c.radial_segments = seg; c.rings = 1; return c
func _sph(r: float, seg: int = 10) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = seg; s.rings = seg / 2; return s

func _add(key: String, mesh: Mesh, m: Material, xf: Transform3D) -> void:
	if not _mm.has(key):
		_mm[key] = {"mesh": mesh, "mat": m, "xf": []}
	_mm[key]["xf"].append(xf)

func _flush_multimeshes() -> void:
	for key in _mm:
		var e: Dictionary = _mm[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e["mesh"]
		var xs: Array = e["xf"]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = e["mat"]
		add_child(mmi)
	_mm.clear()

func _scatter_spot(rng: RandomNumberGenerator, near: bool) -> Vector3:
	for attempt in 30:
		var i := rng.randi_range(0, n - 1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var off := (half + ROUGH + rng.randf_range(4.0, 14.0 if near else 60.0)) * side
		var p := pts[i] + rights[i] * off
		p.y = 0.0
		if road_dist(p) > half + ROUGH + 3.0:
			return p
	return Vector3(0, -100, 0)

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + index * 77
	var theme: String = def["theme"]
	for k in 110:
		var p := _scatter_spot(rng, k < 50)
		if p.y < -50.0:
			continue
		var s := rng.randf_range(0.8, 1.5)
		var rot := Basis(Vector3.UP, rng.randf() * TAU)
		var kind := rng.randi() % 4
		match theme:
			"park": _park_item(kind, p, s, rot, rng)
			"candy": _candy_item(kind, p, s, rot, rng)
			"snow": _snow_item(kind, p, s, rot, rng)
			"space": _space_item(kind, p, s, rot, rng)
	if theme == "space":
		for k in 160:
			var a := rng.randf() * TAU
			var el := rng.randf_range(0.15, 1.2)
			var dist := 700.0
			var sp := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el)) * dist
			_add("star", _box(Vector3(2.5, 2.5, 2.5)), mat(Color(1, 1, 0.9), true), Transform3D(Basis(), sp))
		_add("planet", _sph(60, 16), mat(Color(1.0, 0.55, 0.3), true), Transform3D(Basis(), Vector3(-350, 220, -500)))
		_add("ring", _cyl(110, 1.0, -1, 24), mat(Color(1.0, 0.85, 0.55, 0.7), true, true), Transform3D(Basis(Vector3(0, 0, 1), 0.35), Vector3(-350, 220, -500)))
		_add("moon", _sph(25, 12), mat(Color(0.75, 0.85, 1.0), true), Transform3D(Basis(), Vector3(420, 160, 380)))
	# distant hills ring for depth (not in space)
	if theme != "space":
		var hc: Color = def["ground"]
		for k in 22:
			var a := k / 22.0 * TAU + rng.randf() * 0.2
			var hp := Vector3(cos(a) * 520.0, -10.0, sin(a) * 520.0)
			var hs := rng.randf_range(60, 110)
			_add("hill", _sph(1.0, 8), mat(hc.darkened(0.12) if theme != "snow" else Color(0.85, 0.9, 1.0)), Transform3D(Basis().scaled(Vector3(hs * 1.6, hs * 0.7, hs * 1.3)), hp))

func _park_item(kind: int, p: Vector3, s: float, rot: Basis, rng: RandomNumberGenerator) -> void:
	match kind:
		0, 1:
			_add("trunk", _cyl(0.35, 3.0), mat(Color(0.5, 0.32, 0.2)), Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 1.5 * s, 0)))
			var greens := [Color(0.2, 0.62, 0.25), Color(0.3, 0.72, 0.2), Color(0.15, 0.5, 0.3)]
			_add("crown%d" % (kind), _sph(2.2, 7), mat(greens[kind]), Transform3D(rot.scaled(Vector3(s, s * 1.1, s)), p + Vector3(0, 4.0 * s, 0)))
		2:
			var cols := [Color(1, 0.3, 0.3), Color(0.3, 0.6, 1), Color(1, 0.85, 0.2), Color(0.5, 0.85, 0.3)]
			var c: Color = cols[rng.randi() % 4]
			_add("block" + c.to_html(), _box(Vector3(2, 2, 2)), mat(c), Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, s, 0)))
			if rng.randf() < 0.5:
				var c2: Color = cols[rng.randi() % 4]
				_add("block" + c2.to_html(), _box(Vector3(2, 2, 2)), mat(c2), Transform3D(rot.rotated(Vector3.UP, 0.6).scaled(Vector3(s, s, s)), p + Vector3(0, 3 * s, 0)))
		3:
			_add("stem", _cyl(0.05, 1.0), mat(Color(0.2, 0.6, 0.2)), Transform3D(Basis(), p + Vector3(0, 0.5, 0)))
			var fc := [Color(1, 0.4, 0.6), Color(1, 1, 0.4), Color(0.7, 0.5, 1)]
			_add("flower%d" % (rng.randi() % 3), _sph(0.35, 6), mat(fc[rng.randi() % 3]), Transform3D(Basis(), p + Vector3(0, 1.1, 0)))
			_add("balloon", _sph(0.9, 8), mat(Color(1, 0.3, 0.4)), Transform3D(Basis().scaled(Vector3(1, 1.2, 1)), p + Vector3(rng.randf() * 3, 9 + rng.randf() * 6, 0)))

func _candy_item(kind: int, p: Vector3, s: float, rot: Basis, rng: RandomNumberGenerator) -> void:
	var cols := [Color(1, 0.3, 0.55), Color(0.4, 0.85, 1), Color(1, 0.9, 0.3), Color(0.6, 1, 0.5), Color(0.8, 0.5, 1)]
	var c: Color = cols[rng.randi() % cols.size()]
	match kind:
		0, 1:
			_add("lolli_stick", _cyl(0.15, 6.0), mat(Color(1, 1, 1)), Transform3D(Basis(), p + Vector3(0, 3.0 * s, 0)).scaled_local(Vector3(1, s, 1)))
			_add("lolli" + c.to_html(), _cyl(2.0, 0.6, -1, 14), mat(c), Transform3D(rot * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 6.5 * s, 0)))
			_add("lolli_c", _cyl(1.2, 0.65, -1, 14), mat(Color(1, 1, 1)), Transform3D(rot * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 6.5 * s, 0)))
		2:
			_add("gum" + c.to_html(), _sph(2.0, 8), mat(c), Transform3D(rot.scaled(Vector3(s, s * 0.9, s)), p))
		3:
			_add("cake", _cyl(2.0, 2.2, 2.4, 10), mat(Color(0.95, 0.75, 0.5)), Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3(0, 1.1 * s, 0)))
			_add("icing" + c.to_html(), _sph(2.3, 10), mat(c), Transform3D(Basis().scaled(Vector3(s, s * 0.6, s)), p + Vector3(0, 2.3 * s, 0)))
			_add("cherry", _sph(0.5, 6), mat(Color(0.9, 0.1, 0.2)), Transform3D(Basis(), p + Vector3(0, 3.8 * s, 0)))

func _snow_item(kind: int, p: Vector3, s: float, rot: Basis, rng: RandomNumberGenerator) -> void:
	match kind:
		0, 1:
			for k in 3:
				var r := (2.4 - k * 0.6) * s
				_add("pine%d" % k, _cyl(r, 2.6 * s, 0.0, 7), mat(Color(0.15, 0.45, 0.35)), Transform3D(rot, p + Vector3(0, (1.8 + k * 1.5) * s, 0)))
				_add("pinesnow%d" % k, _cyl(r * 0.45, 1.0 * s, 0.0, 7), mat(Color(1, 1, 1)), Transform3D(rot, p + Vector3(0, (2.7 + k * 1.5) * s, 0)))
			_add("ptrunk", _cyl(0.35, 1.2), mat(Color(0.4, 0.28, 0.2)), Transform3D(Basis(), p + Vector3(0, 0.6, 0)))
		2:
			_add("snowb", _sph(1.2, 8), mat(Color(1, 1, 1)), Transform3D(Basis(), p + Vector3(0, 1.0, 0)))
			_add("snowm", _sph(0.85, 8), mat(Color(1, 1, 1)), Transform3D(Basis(), p + Vector3(0, 2.7, 0)))
			_add("snowh", _sph(0.6, 8), mat(Color(1, 1, 1)), Transform3D(Basis(), p + Vector3(0, 3.9, 0)))
			_add("snown", _cyl(0.12, 0.6, 0.0, 6), mat(Color(1, 0.5, 0.1)), Transform3D(rot * Basis(Vector3.RIGHT, -PI * 0.5), p + Vector3(0, 3.9, 0) + rot * Vector3(0, 0, -0.75)))
			_add("snowhat", _cyl(0.45, 0.7), mat(Color(0.2, 0.25, 0.5)), Transform3D(Basis(), p + Vector3(0, 4.6, 0)))
		3:
			_add("ice", _box(Vector3(3, 3, 3)), mat(Color(0.6, 0.85, 1.0, 0.75), false, true), Transform3D(rot.scaled(Vector3(s, s * 1.4, s)), p + Vector3(0, 1.5 * s * 1.4, 0)))
			if rng.randf() < 0.5:
				_add("fortw", _box(Vector3(8, 4, 1.6)), mat(Color(0.88, 0.93, 1.0)), Transform3D(rot, p + Vector3(0, 2, 0)))
				for k in 3:
					_add("fortc", _box(Vector3(1.6, 1.4, 1.6)), mat(Color(0.88, 0.93, 1.0)), Transform3D(rot, p + Vector3(0, 4.6, 0) + rot * Vector3(-3 + k * 3, 0, 0)))

func _space_item(kind: int, p: Vector3, s: float, rot: Basis, rng: RandomNumberGenerator) -> void:
	match kind:
		0:
			_add("pylon", _cyl(0.3, 8.0, 0.1, 6), mat(Color(0.3, 0.3, 0.5)), Transform3D(Basis(), p + Vector3(0, 4, 0)))
			_add("pylon_l", _sph(0.7, 8), mat(Color(0.2, 1, 0.9), true), Transform3D(Basis(), p + Vector3(0, 8.3, 0)))
		1:
			_add("crystal", _cyl(1.2, 5.0, 0.0, 5), mat(Color(1, 0.3, 0.85), false, false, 0.8), Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 2.5 * s, 0)))
		2:
			_add("rock", _sph(2.0, 6), mat(Color(0.3, 0.25, 0.45)), Transform3D(rot.scaled(Vector3(s * 1.3, s * 0.7, s)), p))
		3:
			_add("dome", _sph(3.0, 10), mat(Color(0.5, 0.8, 1.0, 0.45), false, true), Transform3D(Basis().scaled(Vector3(s, s, s)), p))
			_add("domebase", _cyl(3.2, 0.5, -1, 12), mat(Color(0.6, 0.6, 0.75)), Transform3D(Basis().scaled(Vector3(s, 1, s)), p + Vector3(0, 0.25, 0)))
