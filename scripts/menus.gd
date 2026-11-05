extends Control
## Every menu screen, built in code: title, driver & track select, how-to-play,
## pause, results, Grand Prix standings and the trophy ceremony.

signal action(name: String, arg: Variant)

const Data = preload("res://scripts/data.gd")
const Hud = preload("res://scripts/hud.gd")

var screen: Control
var portrait := false
var _letters: Array[Label] = []
var _t := 0.0
var current := ""
var sound_on := true
var confetti: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	confetti = Confetti.new()
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(confetti)

func _process(dt: float) -> void:
	_t += dt
	for i in _letters.size():
		var l := _letters[i]
		l.pivot_offset = l.size * 0.5
		l.rotation = sin(_t * 3.0 + i * 0.6) * 0.08
		var s := 1.0 + sin(_t * 4.0 + i * 0.5) * 0.06
		l.scale = Vector2(s, s)

func hide_all() -> void:
	_clear()
	current = ""
	confetti.set("active", false)

func _clear() -> void:
	_letters.clear()
	if screen:
		screen.queue_free()
		screen = null

func _base() -> VBoxContainer:
	_clear()
	portrait = size.y > size.x
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	move_child(confetti, -1)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.06, 0.03, 0.18, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(sc)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(size.x, size.y)
	sc.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box

func _panel(box: VBoxContainer, w: float) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.25, 0.86)
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(4)
	sb.border_color = Color(1, 0.8, 0.3)
	sb.content_margin_left = 24; sb.content_margin_right = 24; sb.content_margin_top = 18; sb.content_margin_bottom = 18
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(minf(w, size.x - 28), 0)
	box.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	return v

func _label(parent: Control, text: String, sz: int, col: Color = Color(1, 1, 1), align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.2))
	l.add_theme_constant_override("outline_size", maxi(4, sz / 7))
	parent.add_child(l)
	return l

func _btn(parent: Control, text: String, act: String, arg: Variant = null, col: Color = Color(1, 0.55, 0.2)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 62)
	var n := StyleBoxFlat.new()
	n.bg_color = col
	n.set_corner_radius_all(18)
	n.border_width_bottom = 6
	n.border_color = col.darkened(0.35)
	n.content_margin_left = 18; n.content_margin_right = 18
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = col.lightened(0.18)
	h.border_color = Color(1, 1, 1)
	h.set_border_width_all(4)
	h.border_width_bottom = 6
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = col.darkened(0.15)
	p.border_width_bottom = 2
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.2))
	b.add_theme_constant_override("outline_size", 6)
	b.pressed.connect(func(): action.emit(act, arg))
	parent.add_child(b)
	return b

func _focus_first(b: Control) -> void:
	if b and is_inside_tree():
		b.call_deferred("grab_focus")

# ------------------------------------------------------------------ title
func show_title(info: Dictionary) -> void:
	current = "title"
	var box := _base()
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 2)
	box.add_child(hb)
	var cols := [Color(1, 0.4, 0.3), Color(1, 0.75, 0.2), Color(0.4, 0.9, 0.4), Color(0.35, 0.7, 1), Color(0.8, 0.5, 1)]
	var word := "TURBO TOTS"
	var fs := 70 if not portrait else 64
	for i in word.length():
		var l := _label(hb, word[i], fs, cols[i % cols.size()])
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_constant_override("outline_size", 16)
		if word[i] != " ":
			_letters.append(l)
	var k := _label(box, "K A R T", fs + 20, Color(1, 1, 1))
	k.add_theme_constant_override("outline_size", 18)
	_label(box, "Tiny drivers. Huge drifts.", 26, Color(1, 0.9, 0.6))
	var v := _panel(box, 440)
	var first := _btn(v, "Grand Prix", "gp", null, Color(1, 0.45, 0.25))
	_btn(v, "Time Trial", "tt", null, Color(0.25, 0.6, 1))
	_btn(v, "Quick Race", "quick", null, Color(0.35, 0.75, 0.3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var hbtn := _btn(row, "How to Play", "howto", null, Color(0.6, 0.4, 0.95))
	hbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := _btn(row, "Sound: " + ("On" if sound_on else "Off"), "sound", null, Color(0.45, 0.45, 0.6))
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.add_theme_font_size_override("font_size", 24)
	hbtn.add_theme_font_size_override("font_size", 24)
	var trophies: String = info.get("trophies", "")
	if trophies != "":
		_label(box, trophies, 22, Color(1, 0.85, 0.3))
	_label(box, "Made by Jaineil Rana (JaKing)  -  JaiGod", 18, Color(0.85, 0.85, 1))
	_focus_first(first)

# ------------------------------------------------------------------ drivers
func show_drivers(mode_name: String) -> void:
	current = "drivers"
	var box := _base()
	_label(box, "Choose your driver", 46, Color(1, 0.85, 0.3))
	_label(box, {"gp": "Grand Prix - 4 races", "tt": "Time Trial", "quick": "Quick Race"}.get(mode_name, ""), 24, Color(0.85, 0.9, 1))
	var grid := GridContainer.new()
	grid.columns = 2 if portrait else 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	var first: Button = null
	var cw := minf(300.0, (size.x - 50) / grid.columns)
	for i in Data.DRIVERS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(cw, 200)
		var dc: Color = Data.DRIVERS[i]["color"]
		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.12, 0.08, 0.28, 0.92)
		n.set_corner_radius_all(18)
		n.set_border_width_all(3)
		n.border_color = dc.darkened(0.2)
		var h := n.duplicate() as StyleBoxFlat
		h.border_color = Color(1, 1, 1)
		h.set_border_width_all(6)
		h.bg_color = dc.darkened(0.55)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("focus", h)
		b.add_theme_stylebox_override("pressed", h)
		var card := DriverCard.new()
		card.drv = i
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		b.pressed.connect(func(): action.emit("driver", i))
		grid.add_child(b)
		if first == null:
			first = b
	_btn(box, "Back", "back", null, Color(0.45, 0.45, 0.6)).custom_minimum_size = Vector2(220, 56)
	_focus_first(first)

# ------------------------------------------------------------------ tracks
func show_tracks(bests: Array) -> void:
	current = "tracks"
	var box := _base()
	_label(box, "Pick a track", 46, Color(1, 0.85, 0.3))
	var grid := GridContainer.new()
	grid.columns = 1 if portrait else 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	var first: Button = null
	for i in Data.TRACKS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(minf(400, size.x - 40), 150 if portrait else 170)
		var tc: Color = Data.TRACKS[i]["wall_a"]
		var n := StyleBoxFlat.new()
		n.bg_color = (Data.TRACKS[i]["ground"] as Color).darkened(0.45)
		n.set_corner_radius_all(18)
		n.set_border_width_all(3)
		n.border_color = tc
		var h := n.duplicate() as StyleBoxFlat
		h.border_color = Color(1, 1, 1)
		h.set_border_width_all(6)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("focus", h)
		b.add_theme_stylebox_override("pressed", h)
		var card := TrackCard.new()
		card.trk = i
		card.best = bests[i] if i < bests.size() else 0.0
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		b.pressed.connect(func(): action.emit("track", i))
		grid.add_child(b)
		if first == null:
			first = b
	_btn(box, "Back", "back", null, Color(0.45, 0.45, 0.6)).custom_minimum_size = Vector2(220, 56)
	_focus_first(first)

# ------------------------------------------------------------------ how to play
func show_howto() -> void:
	current = "howto"
	var box := _base()
	var v := _panel(box, 760)
	_label(v, "How to Play", 44, Color(1, 0.85, 0.3))
	var lines := [
		"Drive: W/S or Up/Down  -  Steer: A/D or Left/Right",
		"Drift: hold SPACE (or Shift) while turning. Sparks go blue > orange > purple - let go for a turbo!",
		"Item: E or J  -  Pause: Esc or P  -  Mute: M",
		"Gamepad: A gas, B brake, stick steer, R1/RB drift, X or L1 item, Start pause",
		"Touch: auto-gas. Tap < > to steer, hold DRIFT, tap ITEM.",
		"Tip: hold gas just as '1' fades on the countdown for a rocket start!",
		"Orange arrow pads give a free boost. Rainbow ? cubes give power-ups.",
	]
	for t in lines:
		_label(v, t, 22, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
	_label(v, "Power-ups", 32, Color(0.6, 0.95, 1))
	var grid := GridContainer.new()
	grid.columns = 1 if portrait else 2
	v.add_child(grid)
	for i in 6:
		var row := HBoxContainer.new()
		var ic := ItemIcon.new()
		ic.kind = i
		ic.custom_minimum_size = Vector2(56, 56)
		row.add_child(ic)
		var l := _label(row, Data.ITEM_NAMES[i] + ": " + Data.ITEM_DESC[i], 20, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(minf(290, size.x - 140), 0)
		grid.add_child(row)
	_label(v, "Grand Prix: 4 races, points 10-8-6-4-2-1. Finish top 3 overall for a trophy!", 22, Color(1, 0.9, 0.6))
	_focus_first(_btn(v, "Got it!", "back", null, Color(0.35, 0.75, 0.3)))

# ------------------------------------------------------------------ pause
func show_pause() -> void:
	current = "pause"
	var box := _base()
	var v := _panel(box, 420)
	_label(v, "Paused", 52, Color(1, 0.85, 0.3))
	var f := _btn(v, "Resume", "resume", null, Color(0.35, 0.75, 0.3))
	_btn(v, "Restart Race", "restart", null, Color(1, 0.55, 0.2))
	_btn(v, "Sound: " + ("On" if sound_on else "Off"), "sound", null, Color(0.45, 0.45, 0.6))
	_btn(v, "Quit to Title", "quit", null, Color(0.85, 0.3, 0.4))
	_focus_first(f)

# ------------------------------------------------------------------ results
func show_results(res: Array, mode_name: String, info: Dictionary) -> void:
	current = "results"
	var box := _base()
	var v := _panel(box, 640)
	var title: String = info.get("title", "Results")
	_label(v, title, 46, Color(1, 0.85, 0.3))
	if info.has("sub"):
		_label(v, info["sub"], 26, Color(0.8, 0.95, 1))
	var grid := GridContainer.new()
	grid.columns = 4 if mode_name == "gp" else 3
	grid.add_theme_constant_override("h_separation", 22)
	v.add_child(grid)
	for r in res:
		var col := Color(1, 0.9, 0.3) if r["player"] else Color(1, 1, 1)
		_label(grid, Data.ordinal(r["place"]), 26, col, HORIZONTAL_ALIGNMENT_LEFT)
		var nm: String = Data.DRIVERS[r["driver"]]["name"]
		_label(grid, nm + (" (you)" if r["player"] else ""), 26, col, HORIZONTAL_ALIGNMENT_LEFT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(grid, Data.fmt_time(r["time"]) if r.get("finished", true) else "+" + Data.fmt_time(r["time"]), 24, col, HORIZONTAL_ALIGNMENT_RIGHT)
		if mode_name == "gp":
			_label(grid, "+%d" % Data.GP_POINTS[r["place"] - 1], 24, Color(0.6, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	if info.has("note"):
		_label(v, info["note"], 24, Color(1, 0.75, 0.9))
	var first: Button = null
	for b in info.get("buttons", [["Continue", "next"]]):
		var bt := _btn(v, b[0], b[1], null, Color(1, 0.55, 0.2) if first == null else Color(0.45, 0.45, 0.6))
		if first == null:
			first = bt
	_focus_first(first)
	if info.get("confetti", false):
		confetti.call("burst")

func show_standings(rows: Array, race_no: int) -> void:
	current = "standings"
	var box := _base()
	var v := _panel(box, 560)
	_label(v, "Grand Prix Standings", 42, Color(1, 0.85, 0.3))
	_label(v, "After race %d of 4" % race_no, 24, Color(0.8, 0.95, 1))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	v.add_child(grid)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var col := Color(1, 0.9, 0.3) if r["player"] else Color(1, 1, 1)
		_label(grid, Data.ordinal(i + 1), 28, col, HORIZONTAL_ALIGNMENT_LEFT)
		_label(grid, Data.DRIVERS[r["driver"]]["name"], 28, col, HORIZONTAL_ALIGNMENT_LEFT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(grid, "%d pts" % r["points"], 28, col, HORIZONTAL_ALIGNMENT_RIGHT)
	_focus_first(_btn(v, "Next Race" if race_no < 4 else "Trophy Ceremony", "next", null, Color(1, 0.55, 0.2)))
	_btn(v, "Quit to Title", "quit", null, Color(0.45, 0.45, 0.6))

func show_final(place: int, driver: int, pts: int) -> void:
	current = "final"
	var box := _base()
	var v := _panel(box, 560)
	var names := ["GOLD TROPHY!", "SILVER TROPHY!", "BRONZE TROPHY!"]
	_label(v, names[place - 1] if place <= 3 else "Grand Prix Complete", 50, [Color(1, 0.85, 0.2), Color(0.85, 0.9, 1), Color(1, 0.6, 0.35)][place - 1] if place <= 3 else Color(1, 1, 1))
	var tr := Trophy.new()
	tr.place = place
	tr.custom_minimum_size = Vector2(220, 220)
	v.add_child(tr)
	var nm: String = Data.DRIVERS[driver]["name"]
	_label(v, "%s finished %s overall with %d points." % [nm, Data.ordinal(place), pts], 26, Color(1, 1, 1))
	if place > 3:
		_label(v, "So close! Top 3 wins a trophy - try drifting more for turbo boosts.", 22, Color(1, 0.8, 0.8))
	_focus_first(_btn(v, "Back to Title", "quit", null, Color(1, 0.55, 0.2)))
	if place <= 3:
		confetti.call("burst")

# =================================================================== widgets
class ItemIcon extends Control:
	const H = preload("res://scripts/hud.gd")
	var kind := 0
	func _draw() -> void:
		H.ItemSlot.draw_item(self, kind, size * 0.5, size.x * 0.45)

class DriverCard extends Control:
	const D = preload("res://scripts/data.gd")
	var drv := 0
	func _draw() -> void:
		var d: Dictionary = D.DRIVERS[drv]
		var f := get_theme_default_font()
		var c := Vector2(62, 74)
		var col: Color = d["color"]
		draw_circle(c, 48, col.darkened(0.25))
		draw_circle(c + Vector2(0, 6), 38, d["skin"])
		draw_circle(c + Vector2(0, -16), 36, col)
		draw_rect(Rect2(c.x - 40, c.y - 10, 80, 12), d["accent"])
		for sx in [-14.0, 14.0]:
			draw_circle(c + Vector2(sx, 14), 9, Color(1, 1, 1))
			draw_circle(c + Vector2(sx, 16), 5, Color(0.05, 0.05, 0.1))
		draw_arc(c + Vector2(0, 26), 10, 0.3, PI - 0.3, 10, Color(0.5, 0.1, 0.1), 3)
		var x := 126.0
		var nm: String = d["name"]
		var tt: String = d["title"]
		draw_string_outline(f, Vector2(x, 44), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 6, Color(0.05, 0.02, 0.15))
		draw_string(f, Vector2(x, 44), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, col.lightened(0.3))
		draw_string(f, Vector2(x, 70), tt, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 6, 17, Color(0.85, 0.85, 1))
		var stats := [["SPD", "speed"], ["ACC", "accel"], ["HDL", "handling"], ["WGT", "weight"]]
		for i in 4:
			var y := 132.0 + i * 16.0
			var lx := 14.0
			draw_string(f, Vector2(lx, y + 5), stats[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1))
			var bw := (size.x - 70.0) / 5.0
			for s in 5:
				var on: bool = s < int(d[stats[i][1]])
				draw_rect(Rect2(58 + s * bw, y - 5, bw - 4, 10), col.lightened(0.15) if on else Color(1, 1, 1, 0.15))

class TrackCard extends Control:
	const D = preload("res://scripts/data.gd")
	var trk := 0
	var best := 0.0
	func _draw() -> void:
		var t: Dictionary = D.TRACKS[trk]
		var f := get_theme_default_font()
		var pts: Array = D.track_points(trk)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in pts:
			mn = mn.min(Vector2(p[0], p[1])); mx = mx.max(Vector2(p[0], p[1]))
		var box := minf(size.y - 30, 150.0)
		var sc := box / maxf(mx.x - mn.x, mx.y - mn.y)
		var off := Vector2(16, (size.y - (mx.y - mn.y) * sc) * 0.5)
		var poly := PackedVector2Array()
		for p in pts:
			poly.append((Vector2(p[0], p[1]) - mn) * sc + off)
		poly.append(poly[0])
		draw_polyline(poly, Color(0, 0, 0, 0.5), 12, true)
		draw_polyline(poly, t["wall_a"], 6, true)
		draw_circle(poly[0], 6, Color(1, 1, 1))
		var x := box + 36.0
		var nm: String = t["name"]
		draw_string_outline(f, Vector2(x, 56), nm, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8, 30, 6, Color(0.05, 0.02, 0.15))
		draw_string(f, Vector2(x, 56), nm, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8, 30, Color(1, 1, 1))
		draw_string(f, Vector2(x, 90), "Track %d  -  %d m" % [trk + 1, int(_len(pts))], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.9, 1))
		draw_string(f, Vector2(x, 120), "Best: " + D.fmt_time(best), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.3))
	func _len(pts: Array) -> float:
		var l := 0.0
		for i in pts.size():
			var a: Array = pts[i]
			var b: Array = pts[(i + 1) % pts.size()]
			l += Vector2(a[0] - b[0], a[1] - b[1]).length()
		return l * 1.03

class Trophy extends Control:
	var place := 1
	var t := 0.0
	func _process(dt: float) -> void:
		t += dt
		queue_redraw()
	func _draw() -> void:
		var cols := [Color(1, 0.8, 0.15), Color(0.82, 0.86, 0.95), Color(0.85, 0.5, 0.25), Color(0.6, 0.6, 0.7)]
		var c: Color = cols[mini(place, 4) - 1]
		var cx := size.x * 0.5
		var bob := sin(t * 2.0) * 6.0
		for k in 8:
			var a := t * 0.6 + k * TAU / 8.0
			draw_line(Vector2(cx, 100 + bob), Vector2(cx, 100 + bob) + Vector2(cos(a), sin(a)) * 110, Color(1, 1, 0.7, 0.18), 10)
		draw_rect(Rect2(cx - 60, 190, 120, 26), c.darkened(0.4))
		draw_rect(Rect2(cx - 14, 140 + bob, 28, 52 - bob), c.darkened(0.15))
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 70, 30 + bob), Vector2(cx + 70, 30 + bob), Vector2(cx + 50, 120 + bob), Vector2(cx, 145 + bob), Vector2(cx - 50, 120 + bob)]), c)
		draw_arc(Vector2(cx - 70, 70 + bob), 28, PI * 0.5, PI * 1.5, 16, c, 10)
		draw_arc(Vector2(cx + 70, 70 + bob), 28, -PI * 0.5, PI * 0.5, 16, c, 10)
		draw_circle(Vector2(cx - 30, 60 + bob), 10, Color(1, 1, 1, 0.6))
		var f := get_theme_default_font()
		var s := str(place)
		draw_string(f, Vector2(cx - 12, 102 + bob), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, c.darkened(0.45))

class Confetti extends Control:
	var bits := []
	var active := false
	func burst() -> void:
		active = true
		bits.clear()
		for i in 140:
			bits.append({"p": Vector2(randf() * size.x, -randf() * size.y * 0.8), "v": Vector2(randf_range(-40, 40), randf_range(120, 260)), "c": Color.from_hsv(randf(), 0.7, 1.0), "r": randf() * TAU, "s": randf_range(8, 16)})
	func _process(dt: float) -> void:
		if not active:
			if not bits.is_empty():
				bits.clear()
				queue_redraw()
			return
		for b in bits:
			b["p"] += b["v"] * dt
			b["r"] += dt * 5.0
			if b["p"].y > size.y + 20:
				b["p"] = Vector2(randf() * size.x, -20)
		queue_redraw()
	func _draw() -> void:
		for b in bits:
			draw_set_transform(b["p"], b["r"], Vector2.ONE)
			draw_rect(Rect2(-b["s"] * 0.5, -b["s"] * 0.25, b["s"], b["s"] * 0.5), b["c"])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
