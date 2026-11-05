extends RefCounted
## Static game data: drivers, tracks, power-ups and Grand Prix rules.

const LAPS := 3
const GP_POINTS := [10, 8, 6, 4, 2, 1]

enum { ROCKET, BALL, GOO, BEE, SHIELD, MAGNET }
const ITEM_NAMES := ["Rocket Pop", "Bounce Ball", "Goo Puddle", "Buzz Bee", "Bubble Shield", "Magnet Mitten"]
const ITEM_DESC := [
	"Instant turbo blast.",
	"Fires forward and ricochets off the walls.",
	"Drop it behind you. Splat!",
	"Homes in on the racer just ahead.",
	"Blocks the next hit for 10 seconds.",
	"Locks on and tows you up the track.",
]

# speed / accel / handling / weight are 1..5 and every driver totals 12.
const DRIVERS := [
	{"name": "Pip", "title": "The All-Rounder", "color": Color(1.0, 0.45, 0.18), "accent": Color(1.0, 0.86, 0.3), "skin": Color(1.0, 0.8, 0.62), "hat": 0, "speed": 3, "accel": 3, "handling": 3, "weight": 3},
	{"name": "Bolt", "title": "Top-Speed Rocket", "color": Color(0.2, 0.55, 1.0), "accent": Color(0.95, 0.95, 1.0), "skin": Color(0.86, 0.64, 0.46), "hat": 1, "speed": 5, "accel": 2, "handling": 2, "weight": 3},
	{"name": "Mochi", "title": "Quick Off The Line", "color": Color(1.0, 0.5, 0.75), "accent": Color(1.0, 1.0, 1.0), "skin": Color(1.0, 0.9, 0.8), "hat": 2, "speed": 2, "accel": 5, "handling": 4, "weight": 1},
	{"name": "Rumble", "title": "Heavyweight Bruiser", "color": Color(0.45, 0.75, 0.25), "accent": Color(0.3, 0.3, 0.32), "skin": Color(0.62, 0.42, 0.3), "hat": 3, "speed": 4, "accel": 1, "handling": 2, "weight": 5},
	{"name": "Zuzu", "title": "Corner Queen", "color": Color(0.62, 0.38, 1.0), "accent": Color(0.4, 1.0, 0.85), "skin": Color(0.95, 0.75, 0.55), "hat": 4, "speed": 2, "accel": 3, "handling": 5, "weight": 2},
	{"name": "Nova", "title": "Turbo Tinkerer", "color": Color(1.0, 0.85, 0.15), "accent": Color(0.15, 0.2, 0.35), "skin": Color(0.75, 0.55, 0.4), "hat": 5, "speed": 4, "accel": 4, "handling": 1, "weight": 3},
]

# Points are [x, z, height]. Catmull-Rom closed loops built by track.gd.
const TRACKS := [
	{
		"name": "Sunny Sandbox", "cup": "Sprout Cup", "theme": "park", "half": 9.0,
		"points": [[0,0,0],[80,0,0],[140,-10,0],[185,20,0],[195,75,0],[165,115,0],[110,115,0],[80,90,0],[45,95,0],[20,135,0],[-40,150,0],[-100,130,0],[-130,80,0],[-115,30,0],[-65,5,0]],
		"ground": Color(0.42, 0.78, 0.36), "road": Color(0.42, 0.42, 0.48), "rough": Color(0.93, 0.83, 0.55),
		"wall_a": Color(1.0, 0.35, 0.3), "wall_b": Color(1.0, 1.0, 1.0),
		"sky_top": Color(0.25, 0.55, 0.95), "sky_hor": Color(0.75, 0.9, 1.0), "sun": Color(1.0, 0.97, 0.88), "night": false,
		"boosts": [[0.22, 0.0], [0.6, -3.0], [0.84, 3.0]], "items": [0.12, 0.45, 0.72],
	},
	{
		"name": "Candy Canyon", "cup": "Sprout Cup", "theme": "candy", "half": 8.0,
		"points": [[0,0,0],[70,-5,2],[130,-30,6],[190,-20,10],[230,30,10],[220,90,6],[170,120,3],[120,100,0],[70,130,0],[30,180,4],[-40,190,8],[-100,160,8],[-130,100,5],[-120,40,2],[-60,10,0]],
		"ground": Color(1.0, 0.72, 0.82), "road": Color(0.55, 0.36, 0.3), "rough": Color(1.0, 0.92, 0.75),
		"wall_a": Color(1.0, 0.45, 0.7), "wall_b": Color(0.55, 0.95, 1.0),
		"sky_top": Color(0.62, 0.5, 0.98), "sky_hor": Color(1.0, 0.82, 0.92), "sun": Color(1.0, 0.92, 0.95), "night": false,
		"boosts": [[0.18, 0.0], [0.5, 2.5], [0.78, -2.5]], "items": [0.1, 0.38, 0.66, 0.9],
	},
	{
		"name": "Frosty Fort", "cup": "Sprout Cup", "theme": "snow", "half": 7.5,
		"points": [[0,0,0],[90,0,0],[150,20,1],[170,70,2],[140,110,2],[90,100,1],[60,60,0],[20,70,0],[0,120,1],[30,170,2],[90,190,3],[130,230,3],[90,270,2],[10,260,1],[-50,220,0],[-80,150,0],[-90,70,0],[-60,15,0]],
		"ground": Color(0.92, 0.96, 1.0), "road": Color(0.5, 0.56, 0.66), "rough": Color(0.78, 0.88, 0.98),
		"wall_a": Color(0.25, 0.55, 0.95), "wall_b": Color(1.0, 1.0, 1.0),
		"sky_top": Color(0.45, 0.62, 0.85), "sky_hor": Color(0.88, 0.93, 1.0), "sun": Color(0.95, 0.97, 1.0), "night": false,
		"boosts": [[0.08, 0.0], [0.42, 0.0], [0.7, 2.0]], "items": [0.15, 0.36, 0.58, 0.86],
	},
	{
		"name": "Starlight Speedway", "cup": "Sprout Cup", "theme": "space", "half": 8.0,
		"points": [], # generated: figure-eight with a bridge
		"ground": Color(0.1, 0.1, 0.24), "road": Color(0.18, 0.17, 0.32), "rough": Color(0.28, 0.2, 0.45),
		"wall_a": Color(0.2, 1.0, 0.9), "wall_b": Color(1.0, 0.3, 0.85),
		"sky_top": Color(0.02, 0.02, 0.1), "sky_hor": Color(0.25, 0.12, 0.4), "sun": Color(0.7, 0.75, 1.0), "night": true,
		"boosts": [[0.12, 0.0], [0.37, 0.0], [0.62, 0.0], [0.87, 0.0]], "items": [0.05, 0.3, 0.55, 0.8],
	},
]

static func track_points(i: int) -> Array:
	var t: Dictionary = TRACKS[i]
	if i == 3:
		var pts := []
		for k in 20:
			var a := float(k) / 20.0 * TAU + PI * 0.5
			pts.append([150.0 * sin(a), 100.0 * sin(2.0 * a), 6.0 + 6.0 * cos(a)])
		return pts
	if i == 2:
		var sc := []
		for p in t["points"]:
			sc.append([p[0] * 0.87, p[1] * 0.87, p[2]])
		return sc
	return t["points"]

static func ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return str(n) + "th"

static func fmt_time(t: float) -> String:
	if t <= 0.0 or t > 5999.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]
