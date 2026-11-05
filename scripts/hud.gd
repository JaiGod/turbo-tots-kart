extends Control
## In-race HUD: lap/time, position, item slot with roulette, drift meter,
## minimap, standings column, pop-up messages and multi-touch controls.

signal pause_pressed
signal roulette_tick

const Data = preload("res://scripts/data.gd")

var lap_lbl: Label
var time_lbl: Label
var best_lbl: Label
var pos_lbl: Label
var msg_lbl: Label
var sub_lbl: Label
var speed_lbl: Label
var item_box: Control
var minimap: Control
var drift_bar: Control
var board: VBoxContainer
var touch: Control
var pause_btn: Button
var race = null
var _msg_t := 0.0
var _sub_t := 0.0
var _roulette_kind := 0
var _roulette_acc := 0.0
var touch_mode := false
var portrait := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	lap_lbl = _label(40, Color(1, 1, 1))
	time_lbl = _label(30, Color(1, 0.95, 0.6))
	best_lbl = _label(20, Color(0.85, 0.95, 1))
	var tl := VBoxContainer.new()
	tl.position = Vector2(20, 14)
	tl.add_theme_constant_override("separation", -4)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(lap_lbl); tl.add_child(time_lbl); tl.add_child(best_lbl)
	add_child(tl)
	pos_lbl = _label(84, Color(1, 0.85, 0.2))
	pos_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pos_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pos_lbl.offset_left = -330; pos_lbl.offset_right = -96; pos_lbl.offset_top = 0
	add_child(pos_lbl)
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.offset_left = -84; pause_btn.offset_right = -16; pause_btn.offset_top = 16; pause_btn.offset_bottom = 84
	pause_btn.pressed.connect(func(): pause_pressed.emit())
	add_child(pause_btn)
	item_box = ItemSlot.new()
	item_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	item_box.offset_left = -56; item_box.offset_right = 56; item_box.offset_top = 14; item_box.offset_bottom = 126
	item_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item_box)
	minimap = MiniMap.new()
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	board = VBoxContainer.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_theme_constant_override("separation", -6)
	add_child(board)
	for i in 6:
		var l := _label(20, Color(1, 1, 1))
		board.add_child(l)
	drift_bar = DriftBar.new()
	drift_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drift_bar)
	speed_lbl = _label(26, Color(1, 1, 1))
	speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(speed_lbl)
	msg_lbl = _label(110, Color(1, 1, 1))
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg_lbl.offset_bottom = -120
	add_child(msg_lbl)
	sub_lbl = _label(38, Color(1, 0.9, 0.4))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_lbl.offset_top = 150
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(sub_lbl)
	touch = TouchPad.new()
	touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch.visible = false
	add_child(touch)
	resized.connect(_layout)
	_layout()

func _label(sz: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.2))
	l.add_theme_constant_override("outline_size", maxi(6, sz / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func set_touch(on: bool) -> void:
	touch_mode = on
	touch.visible = on and visible
	_layout()

func _layout() -> void:
	var s := size
	portrait = s.y > s.x
	var mm := 200.0 if not portrait else 170.0
	minimap.size = Vector2(mm, mm)
	if portrait:
		minimap.position = Vector2(s.x - mm - 12, 150)
		board.position = Vector2(16, 150)
	else:
		minimap.position = Vector2(s.x - mm - 16, 120)
		board.position = Vector2(20, 160)
	var bottom := s.y - (300.0 if (touch_mode and portrait) else (210.0 if touch_mode else 70.0))
	drift_bar.size = Vector2(320, 26)
	drift_bar.position = Vector2(s.x * 0.5 - 160, bottom)
	speed_lbl.size = Vector2(320, 36)
	speed_lbl.position = Vector2(s.x * 0.5 - 160, bottom - 40)
	if touch:
		touch.call("relayout")

func show_msg(text: String, dur: float = 1.2, col: Color = Color(1, 1, 1)) -> void:
	msg_lbl.text = text
	msg_lbl.add_theme_color_override("font_color", col)
	_msg_t = dur
	msg_lbl.pivot_offset = msg_lbl.size * 0.5
	msg_lbl.scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(msg_lbl, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func show_warn(text: String, col: Color) -> void:
	if _msg_t > 0.25 and msg_lbl.text != text:
		return
	msg_lbl.text = text
	msg_lbl.scale = Vector2.ONE
	msg_lbl.add_theme_color_override("font_color", col)
	_msg_t = 0.2

func show_sub(text: String, dur: float = 1.5) -> void:
	sub_lbl.text = text
	_sub_t = dur

func update_hud(r, dt: float) -> void:
	race = r
	_msg_t -= dt
	_sub_t -= dt
	msg_lbl.visible = _msg_t > 0.0
	sub_lbl.visible = _sub_t > 0.0
	minimap.set("race", r)
	minimap.queue_redraw()
	var p = r.player
	if p == null:
		return
	var lp: int = clampi(p.lap + 1, 1, Data.LAPS)
	lap_lbl.text = "LAP %d/%d" % [lp, Data.LAPS]
	time_lbl.text = Data.fmt_time(r.race_time) if r.state != "countdown" else "0:00.00"
	best_lbl.text = ("BEST LAP " + Data.fmt_time(p.best_lap)) if p.best_lap > 0.0 else ""
	if r.mode == "tt":
		pos_lbl.text = ""
	else:
		pos_lbl.text = Data.ordinal(p.place)
		var cols := [Color(1, 0.85, 0.2), Color(0.85, 0.9, 1.0), Color(1, 0.6, 0.35)]
		pos_lbl.add_theme_color_override("font_color", cols[p.place - 1] if p.place <= 3 else Color(1, 1, 1))
	speed_lbl.text = "%d km/h" % int(absf(p.speed) * 3.6)
	drift_bar.set("charge", p.drift_charge if p.drifting else 0.0)
	drift_bar.set("boost", p.boost_t > 0.0 or p.magnet_t > 0.0)
	drift_bar.queue_redraw()
	# item slot
	var kind: int = p.item
	if p.roulette_t > 0.0:
		_roulette_acc += dt
		if _roulette_acc > 0.07:
			_roulette_acc = 0.0
			_roulette_kind = (_roulette_kind + 1) % 6
			roulette_tick.emit()
		kind = _roulette_kind
	item_box.set("kind", kind)
	item_box.set("count", p.item_count if p.roulette_t <= 0.0 else 0)
	item_box.set("rolling", p.roulette_t > 0.0)
	item_box.queue_redraw()
	# standings column
	var order := []
	for k in r.karts:
		order.append(k)
	order.sort_custom(func(a, b): return a.place < b.place)
	var labels := board.get_children()
	for i in labels.size():
		var l: Label = labels[i]
		if i < order.size() and r.mode != "tt":
			var k = order[i]
			l.text = "%d  %s" % [i + 1, k.driver["name"]]
			l.add_theme_color_override("font_color", Color(1, 0.9, 0.3) if k == p else (k.driver["color"] as Color).lightened(0.35))
			l.visible = true
		else:
			l.visible = false

# ===================================================================== widgets
class ItemSlot extends Control:
	const D = preload("res://scripts/data.gd")
	static func draw_item(ci: CanvasItem, kind: int, c: Vector2, r: float) -> void:
		match kind:
			D.ROCKET:
				var body := PackedVector2Array([c + Vector2(-r * 0.3, r * 0.6), c + Vector2(-r * 0.3, -r * 0.3), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.3, -r * 0.3), c + Vector2(r * 0.3, r * 0.6)])
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, r * 0.25), c + Vector2(-r * 0.6, r * 0.75), c + Vector2(-r * 0.3, r * 0.6)]), Color(0.2, 0.5, 1))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.3, r * 0.25), c + Vector2(r * 0.6, r * 0.75), c + Vector2(r * 0.3, r * 0.6)]), Color(0.2, 0.5, 1))
				ci.draw_colored_polygon(body, Color(1, 0.3, 0.3))
				ci.draw_circle(c + Vector2(0, -r * 0.15), r * 0.14, Color(1, 1, 1))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.2, r * 0.62), c + Vector2(0, r * 1.0), c + Vector2(r * 0.2, r * 0.62)]), Color(1, 0.75, 0.1))
			D.BALL:
				ci.draw_circle(c, r * 0.7, Color(0.25, 0.55, 1))
				ci.draw_rect(Rect2(c.x - r * 0.7, c.y - r * 0.12, r * 1.4, r * 0.24), Color(1, 1, 1))
				ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.12, Color(1, 1, 1, 0.8))
			D.GOO:
				for k in 6:
					var a := k * TAU / 6.0
					ci.draw_circle(c + Vector2(cos(a), sin(a) * 0.6) * r * 0.45 + Vector2(0, r * 0.2), r * 0.32, Color(0.35, 0.9, 0.25))
				ci.draw_circle(c + Vector2(0, r * 0.1), r * 0.45, Color(0.35, 0.9, 0.25))
				ci.draw_circle(c + Vector2(-r * 0.18, 0), r * 0.12, Color(1, 1, 1))
				ci.draw_circle(c + Vector2(r * 0.18, 0), r * 0.12, Color(1, 1, 1))
				ci.draw_circle(c + Vector2(-r * 0.18, 0), r * 0.06, Color(0, 0, 0))
				ci.draw_circle(c + Vector2(r * 0.18, 0), r * 0.06, Color(0, 0, 0))
			D.BEE:
				ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.45), r * 0.3, Color(1, 1, 1, 0.8))
				ci.draw_circle(c + Vector2(r * 0.2, -r * 0.45), r * 0.3, Color(1, 1, 1, 0.8))
				ci.draw_set_transform(c, 0.0, Vector2(1.3, 0.85))
				ci.draw_circle(Vector2.ZERO, r * 0.5, Color(1, 0.85, 0.1))
				ci.draw_rect(Rect2(-r * 0.12, -r * 0.5, r * 0.18, r), Color(0.1, 0.1, 0.1))
				ci.draw_rect(Rect2(r * 0.2, -r * 0.45, r * 0.14, r * 0.9), Color(0.1, 0.1, 0.1))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				ci.draw_circle(c + Vector2(-r * 0.42, -r * 0.05), r * 0.08, Color(0, 0, 0))
			D.SHIELD:
				ci.draw_circle(c, r * 0.75, Color(0.4, 0.9, 1, 0.35))
				ci.draw_arc(c, r * 0.75, 0, TAU, 32, Color(0.6, 1, 1), r * 0.12)
				ci.draw_arc(c, r * 0.45, -2.4, -1.2, 12, Color(1, 1, 1, 0.9), r * 0.1)
			D.MAGNET:
				ci.draw_arc(c + Vector2(0, -r * 0.05), r * 0.5, 0.0, PI, 16, Color(1, 0.25, 0.3), r * 0.3)
				ci.draw_arc(c + Vector2(0, -r * 0.05), r * 0.5, 0.0, PI, 16, Color(1, 0.25, 0.3), r * 0.3)
				ci.draw_rect(Rect2(c.x - r * 0.65, c.y - r * 0.7, r * 0.3, r * 0.65), Color(1, 0.25, 0.3))
				ci.draw_rect(Rect2(c.x + r * 0.35, c.y - r * 0.7, r * 0.3, r * 0.65), Color(1, 0.25, 0.3))
				ci.draw_rect(Rect2(c.x - r * 0.65, c.y - r * 0.85, r * 0.3, r * 0.2), Color(0.9, 0.9, 0.95))
				ci.draw_rect(Rect2(c.x + r * 0.35, c.y - r * 0.85, r * 0.3, r * 0.2), Color(0.9, 0.9, 0.95))

	var kind := -1
	var count := 0
	var rolling := false
	func _draw() -> void:
		var r := size.x * 0.5
		var c := size * 0.5
		draw_circle(c, r, Color(0.05, 0.05, 0.15, 0.55))
		draw_arc(c, r - 3, 0, TAU, 40, Color(1, 1, 1, 0.9) if not rolling else Color.from_hsv(fposmod(Time.get_ticks_msec() * 0.002, 1.0), 0.6, 1.0), 6)
		if kind >= 0:
			draw_item(self, kind, c, r * 0.72)
		if count > 1:
			var f := get_theme_default_font()
			draw_string_outline(f, Vector2(size.x - 34, size.y - 4), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 6, Color(0, 0, 0))
			draw_string(f, Vector2(size.x - 34, size.y - 4), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1))

class DriftBar extends Control:
	var charge := 0.0
	var boost := false
	func _draw() -> void:
		if charge <= 0.0 and not boost:
			return
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.45))
		var lv := [0.8, 1.7, 2.7]
		var cols := [Color(0.3, 0.75, 1.0), Color(1.0, 0.55, 0.1), Color(0.85, 0.35, 1.0)]
		var f := clampf(charge / 2.7, 0.0, 1.0)
		var col := Color(1, 1, 1)
		for i in 3:
			if charge >= lv[i]:
				col = cols[i]
		if boost:
			f = 1.0
			col = Color(1, 0.6, 0.15)
		draw_rect(Rect2(3, 3, (w - 6) * f, h - 6), col)
		for i in 3:
			var x: float = 3 + (w - 6) * lv[i] / 2.7
			draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.8), 2)

class MiniMap extends Control:
	var race = null
	var _pts := PackedVector2Array()
	var _for_track = null
	func _draw() -> void:
		if race == null or race.track == null:
			return
		var tr = race.track
		if _for_track != tr:
			_for_track = tr
			var mn := Vector2(INF, INF)
			var mx := Vector2(-INF, -INF)
			for p in tr.pts:
				mn = mn.min(Vector2(p.x, p.z)); mx = mx.max(Vector2(p.x, p.z))
			var sc: float = (size.x - 20) / maxf(mx.x - mn.x, mx.y - mn.y)
			set_meta("mn", mn); set_meta("sc", sc); set_meta("off", (size - (mx - mn) * sc) * 0.5)
			_pts = PackedVector2Array()
			for i in range(0, tr.n, 3):
				_pts.append(_map(tr.pts[i]))
			_pts.append(_pts[0])
		draw_polyline(_pts, Color(0, 0, 0, 0.5), 12)
		draw_polyline(_pts, Color(1, 1, 1, 0.85), 6)
		var s0 := _map(tr.point_at(0.0))
		draw_circle(s0, 5, Color(0.1, 0.1, 0.1))
		for k in race.karts:
			if k == race.player:
				continue
			draw_circle(_map(k.pos), 6, k.driver["color"])
		if race.ghost_kart and race.ghost_kart.visible:
			draw_circle(_map(race.ghost_kart.pos), 6, Color(1, 1, 1, 0.5))
		if race.player:
			draw_circle(_map(race.player.pos), 10, Color(0, 0, 0))
			draw_circle(_map(race.player.pos), 7.5, race.player.driver["color"])
	func _map(p: Vector3) -> Vector2:
		var mn: Vector2 = get_meta("mn")
		var sc: float = get_meta("sc")
		var off: Vector2 = get_meta("off")
		return (Vector2(p.x, p.z) - mn) * sc + off

class TouchPad extends Control:
	var btns := {}
	var touches := {}
	var item_tap := false
	func relayout() -> void:
		var s := size
		var portrait := s.y > s.x
		var r := 74.0 if portrait else 70.0
		var y := s.y - r - 26.0
		btns = {
			"left": {"c": Vector2(r + 18, y), "r": r, "t": "<"},
			"right": {"c": Vector2(r * 3 + 34, y), "r": r, "t": ">"},
			"drift": {"c": Vector2(s.x - r - 18, y), "r": r, "t": "DRIFT"},
			"item": {"c": Vector2(s.x - r - 18, y - r * 2 - 20), "r": r * 0.8, "t": "ITEM"},
			"brake": {"c": Vector2(s.x - r * 3 - 34, y), "r": r * 0.8, "t": "BRAKE"},
		}
		queue_redraw()
	func _hit(p: Vector2) -> String:
		var best := ""
		var bd := INF
		for k in btns:
			var dd: float = p.distance_to(btns[k]["c"])
			if dd < float(btns[k]["r"]) * 1.25 and dd < bd:
				bd = dd
				best = k
		return best
	func _input(e: InputEvent) -> void:
		if not is_visible_in_tree():
			touches.clear()
			return
		if e is InputEventScreenTouch:
			var le := make_input_local(e) as InputEventScreenTouch
			if le.pressed:
				var b := _hit(le.position)
				if b != "":
					touches[le.index] = b
					if b == "item":
						item_tap = true
			else:
				touches.erase(le.index)
			queue_redraw()
		elif e is InputEventScreenDrag:
			var le := make_input_local(e) as InputEventScreenDrag
			if touches.has(le.index):
				var b := _hit(le.position)
				if b != "" and b != "item":
					touches[le.index] = b
				queue_redraw()
	func held(name: String) -> bool:
		return touches.values().has(name)
	func take_item() -> bool:
		var t := item_tap
		item_tap = false
		return t
	func _draw() -> void:
		var f := get_theme_default_font()
		for k in btns:
			var b: Dictionary = btns[k]
			var on := held(k)
			var c: Vector2 = b["c"]
			var r: float = b["r"]
			draw_circle(c, r, Color(1, 1, 1, 0.32) if on else Color(0.05, 0.05, 0.2, 0.35))
			draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.75), 4)
			var t: String = b["t"]
			var fs := 52 if t.length() == 1 else 24
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-w * 0.5, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
