extends Node
## Builds every pixel-art texture in code, so the game has no image files.

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

# Player ships are drawn from their shape in Game.SHIPS (see _ship_layout). Enemies are hand-drawn here.
# # w b c r m y = hull (blocks your own shots), g = gun pod, G = pod strut, e = engine nozzle.
const ENEMY_ART := {
	"raider": [
		"g.....#.....g",
		"#....#r#....#",
		"#r..#rrr#..r#",
		"#rr#rrrrr#rr#",
		".#rrrryrrrr#.",
		"..#rrryrrr#..",
		"..#rr###rr#..",
		"...#r#.#r#...",
		"....e...e....",
	],
	"gunner": [
		"gg.....#.....gg",
		"#g#...#r#...#g#",
		"#rr#.#rrr#.#rr#",
		"#rrr#rrrrr#rrr#",
		".#rrrrryrrrrr#.",
		".#rrrryyyrrrr#.",
		"..#rrrrrrrrr#..",
		"..#rr#####rr#..",
		"...ee.....ee...",
	],
	"sniper": [
		"....g....",
		"....#....",
		"...#r#...",
		"...#r#...",
		"..#rrr#..",
		"..#ryr#..",
		".#rrrrr#.",
		"#rr#r#rr#",
		"#r#.r.#r#",
		"#.#.e.#.#",
	],
	"swarmer": [
		"g..#..g",
		"#.#r#.#",
		"#rrrrr#",
		".#ryr#.",
		"..#e#..",
	],
	"captain": [
		"gg......#......gg",
		"#g#....#y#....#g#",
		"#rr#..#rrr#..#rr#",
		"#rrr##rrrrr##rrr#",
		".#rrrrrrrrrrrrr#.",
		".#rrryrrrrryrrr#.",
		"..#rrryyyyyrrr#..",
		"..#rrrrrrrrrrr#..",
		"...#rr#####rr#...",
		"...#r#.....#r#...",
		"....e.......e....",
	],
	"sentinel": [
		".....#.....",
		"....#m#....",
		"g..#mmm#..g",
		"#.#mmymm#.#",
		"#mmmyyymmm#",
		"#.#mmymm#.#",
		"g..#mmm#..g",
		"....#m#....",
		".....#.....",
	],
}
const ENEMY_PAL := {
	"raider": {"#": Color("2a0d0d"), "r": Color("c0392b"), "y": Color("ffd24a"), "g": Color("4a1a1a"), "e": Color("ff5a1f")},
	"gunner": {"#": Color("240b06"), "r": Color("a8402a"), "y": Color("ff9a3d"), "g": Color("3e1a12"), "e": Color("ff5a1f")},
	"sniper": {"#": Color("2a1206"), "r": Color("d35400"), "y": Color("ffe066"), "g": Color("4a2a12"), "e": Color("ff5a1f")},
	"swarmer": {"#": Color("2a0808"), "r": Color("e74c3c"), "y": Color("ffd24a"), "g": Color("4a1a1a"), "e": Color("ff7a3d")},
	"captain": {"#": Color("1a0505"), "r": Color("7b1010"), "y": Color("ffd700"), "g": Color("3a0d0d"), "e": Color("ff3d1f")},
	"sentinel": {"#": Color("1a0626"), "m": Color("8e44ad"), "y": Color("e0a0ff"), "g": Color("3a1450"), "e": Color("d050ff")},
}
const WRECK_ART := [
	"...##..........",
	"..#ww#...##....",
	".#wwbw#.#ww#...",
	"#wwwww##wwww#..",
	"#wbwwwwwwbww#..",
	".#www#.#wwwww#.",
	"..##.....#ww#..",
	".........#w#...",
	"..........#....",
]
const WRECK_PAL := {"#": Color("1c1e24"), "w": Color("5d6170"), "b": Color("8a5a2e")}
const CRATE_ART := [
	"#######",
	"#yy#yy#",
	"#y#y#y#",
	"##yyy##",
	"#y#y#y#",
	"#yy#yy#",
	"#######",
]
const CRATE_PAL := {"#": Color("5a4220"), "y": Color("c49a3c")}

# 9x9 icons: x = icon colour, l = lighter, o = darker
const ICONS := {
	"shield": [".xxxxxxx.", "xlllxxxxx", "xlxxxxxxx", "xxxxxxxxx", "xxxxxxxxx", ".xxxxxxx.", "..xxxxx..", "...xxx...", "....x...."],
	"hull": ["...xxx...", "...xlx...", "...xxx...", "xxxxxxxxx", "xlxxxxxlx", "xxxxxxxxx", "...xxx...", "...xxx...", "...xxx..."],
	"cargo": ["xxxxxxxxx", "xlllllllx", "xlxxxxxlx", "xxlxxxlxx", "xxxlxlxxx", "xxlxxxlxx", "xlxxxxxlx", "xlllllllx", "xxxxxxxxx"],
	"probe": ["....x....", "...xlx...", "...xxx...", "..xxxxx..", ".xx.x.xx.", "x...x...x", "....x....", "...x.x...", "..x...x.."],
	"credits": ["..xxxxx..", ".xlllllx.", "xlxxoxxlx", "xlxoxxxlx", "xlxxoxxlx", "xlxxxoxlx", "xlxxoxxlx", ".xlllllx.", "..xxxxx.."],
	"energy": [".....xx..", "....xx...", "...xx....", "..xxxxx..", "....xx...", "...xx....", "..xx.....", ".xx......", "x........"],
	"throttle": ["....x....", "...xxx...", "..xx.xx..", ".xx...xx.", "....x....", "...xxx...", "..xx.xx..", ".xx...xx.", "xx.....xx"],
	"planet": ["..xxxxx..", ".xllxxxx.", "xllxxxxxx", "xlxxxxxxx", "xxxxxxxxx", "xxxxxxxox", "xxxxxxoox", ".xxxxoox.", "..xxxxx.."],
	"gate": ["..xxxxx..", ".xx...xx.", "xx..l..xx", "x..lll..x", "x.lllll.x", "x..lll..x", "xx..l..xx", ".xx...xx.", "..xxxxx.."],
	"anomaly": ["....x....", "x...x...x", ".x.xlx.x.", "..xlllx..", "xxlllllxx", "..xlllx..", ".x.xlx.x.", "x...x...x", "....x...."],
	"station": ["xxx.x.xxx", "xlx.x.xlx", "xxxxxxxxx", "...xlx...", "..xlllx..", "...xlx...", "xxxxxxxxx", "xlx.x.xlx", "xxx.x.xxx"],
	"ore": ["..xxxxx..", ".xlllxxx.", "xlxxxxxxx", "xxlxxxxox", ".xxxxxox.", "..xxxox..", "...xox...", "....x....", "........."],
	"spice": ["......xx.", "....xxlx.", "...xllxx.", "..xlxxxx.", ".xlxxxx..", ".xxxxx...", "x.xxx....", "xx.......", "........."],
	"module": [".x.x.x.x.", "xxxxxxxxx", ".xlllllx.", "xxlxxxlxx", ".xlxoxlx.", "xxlxxxlxx", ".xlllllx.", "xxxxxxxxx", ".x.x.x.x."],
	"ship": ["...xxx...", "...xlx...", "xx.xxx.xx", "xxxxxxxxx", "xx.xlx.xx", "...xxx...", "...xxx...", "...x.x...", "........."],
	"weapon": ["....x....", "..xxxxx..", ".x..x..x.", ".x.....x.", "xxx.l.xxx", ".x.....x.", ".x..x..x.", "..xxxxx..", "....x...."],
	"star": ["....x....", "...xlx...", "xxxxlxxxx", ".xlllllx.", "..xlllx..", "..xxxxx..", ".xx...xx.", "xx.....xx", "........."],
	"mission": [".xxxxxxx.", "xlllllllx", "xlxxxxxlx", "xlllllllx", "xlxxxxxlx", "xlllllllx", "xlxxxlllx", "xlllllllx", ".xxxxxxx."],
	"skull": ["..xxxxx..", ".xxxxxxx.", "xxxxxxxxx", "xo.xxx.ox", "xooxxxoox", "xxxxoxxxx", ".xxxxxxx.", "..x.x.x..", "..xxxxx.."],
	"flame": ["....x....", "...xx....", "...xlx...", "..xllx.x.", ".xxllxxx.", ".xlllllx.", "xllllllx.", ".xlllllx.", "..xxxxx.."],
	"wrench": [".xx......", "x..x.....", "x...x....", ".x..xx...", "..xxlxx..", "....xlxx.", ".....xlxx", "......xxx", ".......x."],
	"obelisk": ["....x....", "...xlx...", "...xxx...", "...xlx...", "...xxx...", "..xxlxx..", "..xxxxx..", ".xxxxxxx.", "xxxxxxxxx"],
	"wreck": ["...xx....", "..xlx.xx.", ".xxxx.lx.", "xlxx..xx.", "xx...xxx.", ".x..xlx..", "...xxx...", "..xx.....", "........."],
	"radar": ["..xxxxx..", ".x.....x.", "x...l...x", "x..l.l..x", "x.l.x.l.x", "x..l.l..x", "x...l...x", ".x.....x.", "..xxxxx.."],
}
const OBELISK_ART := [
	"....#....",
	"...#a#...",
	"...#m#...",
	"..#aaa#..",
	"..#ama#..",
	"..#aaa#..",
	"..#aaa#..",
	"..#ama#..",
	"..#aaa#..",
	"..#aaa#..",
	".#aamaa#.",
	".#aaaaa#.",
	"#########",
	"#sssssss#",
	"#########",
]
const OBELISK_PAL := {"#": Color("120e1c"), "a": Color("2d2540"), "m": Color("d050ff"), "s": Color("4a4458")}

const SPICE_ART := [
	"rrwwrrwwrrwwrrwwrr",
	"rrwwrrwwrrwwrrwwrr",
	".#..............#.",
	".#..............#.",
	".#..oo..yy..pp..#.",
	".#.#oo#.yy#.pp#.#.",
	"##################",
	"#ssssssssssssssss#",
	"##################",
]
const SPICE_PAL := {"r": Color("c0392b"), "w": Color("f4e9d8"), "#": Color("3a2a1f"), "o": Color("ff6a3d"),
	"y": Color("ffb03d"), "p": Color("ff7de9"), "s": Color("7a5a3a")}

const PLANET_PAL := {
	"rocky": [Color("3b3330"), Color("5a4a42"), Color("7d6a5c"), Color("a08a74"), Color("c2ae96")],
	"ice": [Color("4a6c8c"), Color("6f97b8"), Color("a6c8e0"), Color("d8ecf7"), Color("ffffff")],
	"gas": [Color("7a4e2d"), Color("b07a45"), Color("d9a86a"), Color("f0d2a0"), Color("c46a3a")],
	"lava": [Color("1a0d0d"), Color("3a1a14"), Color("5c2a1c"), Color("ff5a1f"), Color("ffb347")],
	"ocean": [Color("0d2a5c"), Color("14427f"), Color("1f66a8"), Color("3f8f4a"), Color("7fb45a")],
	"toxic": [Color("2d3b12"), Color("4f6b1a"), Color("7fa62a"), Color("c4e34a"), Color("eaff8a")],
	"desert": [Color("6b4a2a"), Color("946a3e"), Color("bf9157"), Color("dbb57a"), Color("f2d8a6")],
	"void": [Color("120318"), Color("2a0a3a"), Color("4f1670"), Color("8a2be2"), Color("e0a0ff")],
}

var _cache := {}


func _bayer(x: int, y: int) -> float:
	return BAYER[(y % 4) * 4 + x % 4] / 16.0


func art(rows: Array, pal: Dictionary) -> Image:
	var w := 0
	for row in rows:
		w = maxi(w, row.length())
	var img := Image.create_empty(w, rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	return img


## Builds a player ship from its shape: a rectangle hull with gun pods spaced evenly down both sides
## (half the ship's gun slots on each side) and engines below. Returns {"rows", "pods"} where pods are
## the pod centres in art pixels, in slot order: front-left, front-right, second-left, ...
func _ship_layout(id: String) -> Dictionary:
	var s: Dictionary = Game.SHIPS[id]
	var bw: int = s.body.x
	var bh: int = s.body.y
	var gap: int = s.gap
	var pod: int = s.pod
	var per_side: int = maxi(1, s.guns >> 1)
	var style: String = s.style
	var w := bw + 2 * (2 + gap)
	var x0 := 2 + gap
	var cx := bw >> 1
	var half_cockpit := maxi(1, int(bw / 3.0)) >> 1
	var centers := []
	for k in per_side:
		centers.append(int((k + 0.5) * bh / per_side))
	var rows := []
	for y in bh:
		var row := ""
		var pod_here := -1
		for k in per_side:
			if y >= centers[k] - (pod >> 1) and y < centers[k] - (pod >> 1) + pod:
				pod_here = k
		for x in w:
			var ch := "."
			var bx := x - x0
			if bx >= 0 and bx < bw:
				if bx == 0 or bx == bw - 1 or y == 0 or y == bh - 1:
					ch = "#"
				elif y >= 1 and y <= 2 and absi(bx - cx) <= half_cockpit:
					ch = "c"
				else:
					ch = "w"
					match style:
						"h":
							if y >= 4 and y % 3 == 1 and bx >= 2 and bx <= bw - 3:
								ch = "b"
						"v":
							if (bx == 1 or bx == bw - 2) and y >= 3:
								ch = "b"
						"x":
							if y >= 4 and (bx + y) % 4 == 0:
								ch = "b"
						"n":
							if y >= 4 and y % 4 == 0 and bx == cx:
								ch = "b"
			elif pod_here >= 0:
				if x < 2 or x >= w - 2:
					ch = "g"
				elif y == centers[pod_here] or y == centers[pod_here] - 1:
					ch = "G"
			row += ch
		rows.append(row)
	var engines := ""
	var q := int(bw / 4.0)
	for x in w:
		var bx := x - x0
		var e := false
		if bw >= 9:
			e = bx == q or bx == q + 1 or bx == bw - 1 - q or bx == bw - 2 - q
			if bw >= 17:
				e = e or bx == cx or bx == cx - 1
		else:
			e = bx == 1 or bx == bw - 2
		engines += "e" if e else "."
	rows.append(engines)
	var pods := []
	for k in per_side:
		pods.append(Vector2(1.0, centers[k]))
		pods.append(Vector2(w - 1.0, centers[k]))
	return {"rows": rows, "pods": pods}

func _ship_pal(id: String) -> Dictionary:
	var c: Array = Game.SHIPS[id].colors
	return {"#": c[0].darkened(0.78), "w": c[0], "b": c[1], "c": c[2], "g": c[1].darkened(0.55),
		"G": c[0].darkened(0.5), "e": Color("ff9a3d")}


## Returns {"tex", "muzzles", "engines", "size", "mask", "w", "h"}. Offsets are in art pixels from the
## sprite centre; muzzles[0] is the left gun, muzzles[1] the right. mask marks hull pixels.
func ship(id: String) -> Dictionary:
	var key := "ship:" + id
	if _cache.has(key):
		return _cache[key]
	var rows: Array
	var img: Image
	var pods := []
	if Game.SHIPS.has(id):
		var layout := _ship_layout(id)
		rows = layout.rows
		pods = layout.pods
		img = art(rows, _ship_pal(id))
	else:
		rows = ENEMY_ART[id]
		img = art(rows, ENEMY_PAL[id])
	var w := img.get_width()
	var h := img.get_height()
	var half := Vector2(w, h) / 2.0
	var mask := PackedByteArray()
	mask.resize(w * h)
	var sides := [[], []]
	var engines := []
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == "g":
				sides[0 if x < w / 2.0 else 1].append(Vector2(x + 0.5, y + 0.5))
			elif ch == "e":
				engines.append(Vector2(x + 0.5, y + 1) - half)
			if not ".gGe".contains(ch):
				mask[y * w + x] = 1
	var muzzles := []
	if not pods.is_empty():
		muzzles = pods.map(func(p): return p - half)
	else:
		# hand-drawn enemies: one gun per side, at the middle of that side's pod pixels
		for pod in sides:
			if not pod.is_empty():
				var sum := Vector2.ZERO
				for p in pod:
					sum += p
				muzzles.append(sum / pod.size() - half)
	var out := {"tex": ImageTexture.create_from_image(img), "muzzles": muzzles, "engines": engines,
		"size": half * 2.0, "mask": mask, "w": w, "h": h}
	_cache[key] = out
	return out

## True if a shot from `from` toward `to` (art pixels, ship-local) would pass through the ship's own hull.
func ray_blocked(id: String, from: Vector2, to: Vector2, step := 0.25) -> bool:
	var data := ship(id)
	var mask: PackedByteArray = data.mask
	var w: int = data.w
	var h: int = data.h
	var a: Vector2 = from + data.size / 2.0
	var dir := to - from
	var dist := dir.length()
	if dist < 0.001:
		return true
	dir /= dist
	var limit := minf(dist, float(w + h))
	var t := 0.0
	while t < limit:
		var p := a + dir * t
		var cx := floori(p.x)
		var cy := floori(p.y)
		if cx >= 0 and cy >= 0 and cx < w and cy < h and mask[cy * w + cx] == 1:
			return true
		t += step
	return false


## 180 samples around the ship (ship-local angle i * 2 degrees from +x). Bit k set = gun slot k can fire that way.
func fire_arcs(id: String) -> PackedInt32Array:
	var key := "arcs:" + id
	if _cache.has(key):
		return _cache[key]
	var muzzles: Array = ship(id).muzzles
	var arcs := PackedInt32Array()
	arcs.resize(180)
	for i in 180:
		var target := Vector2.from_angle(i * TAU / 180.0) * 160.0
		var bits := 0
		for k in muzzles.size():
			if not ray_blocked(id, muzzles[k], target, 0.5):
				bits |= 1 << k
		arcs[i] = bits
	_cache[key] = arcs
	return arcs

func from_art(key: String, rows: Array, pal: Dictionary) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(art(rows, pal))
	return _cache[key]


func obelisk() -> ImageTexture:
	return from_art("obelisk", OBELISK_ART, OBELISK_PAL)


func spice_stand() -> ImageTexture:
	return from_art("spice", SPICE_ART, SPICE_PAL)


func rect(w: int, h: int, color: Color) -> ImageTexture:
	var key := "rect:%d:%d:%s" % [w, h, color.to_html()]
	if not _cache.has(key):
		var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		img.fill(color)
		# bright core down the middle of each bolt
		for y in range(1, h - 1):
			img.set_pixel(w >> 1, y, color.lerp(Color.WHITE, 0.6))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


func ore_chunk(ore_id: String, q: int) -> ImageTexture:
	var key := "chunk:%s:%d" % [ore_id, q]
	if _cache.has(key):
		return _cache[key]
	var c: Color = Game.ORES[ore_id].color
	if q == 0:
		c = c.lerp(Color(0.5, 0.5, 0.5), 0.4)
	var img := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 7:
			var m := absi(x - 3) + absi(y - 3)
			if m == 3:
				img.set_pixel(x, y, c.darkened(0.6))
			elif m < 3:
				img.set_pixel(x, y, c)
	img.set_pixel(2, 2, c.lightened(0.5))
	img.set_pixel(3, 2, c.lightened(0.3))
	if q >= 2:
		img.set_pixel(3, 3, Game.Q_COLORS[q])
		img.set_pixel(4, 3, Game.Q_COLORS[q])
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


func asteroid(r: int, ore_color: Color, q: int, rock_seed: int) -> ImageTexture:
	var size := r * 2 + 4
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = rock_seed
	n.frequency = 0.08
	var c := Vector2(size, size) / 2.0
	var base := Color("5d5650")
	var dark := Color("37322e")
	var light := Color("857c73")
	var orec := ore_color.lerp(Color(0.45, 0.45, 0.45), 0.4) if q == 0 else ore_color
	var thresh: float = [0.3, 0.24, 0.18, 0.12][q]
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var ang := d.angle()
			var rr := r * (0.8 + 0.22 * n.get_noise_2d(cos(ang) * 40.0, sin(ang) * 40.0))
			var dist := d.length()
			if dist > rr:
				continue
			var shade := -(d.x + d.y) / (r * 2.0)
			var v := shade + n.get_noise_2d(x * 3.0, y * 3.0) * 0.4 + (_bayer(x, y) - 0.5) * 0.25
			var col := base
			if v > 0.22:
				col = light
			elif v < -0.2:
				col = dark
			if dist > rr - 1.3:
				col = Color("1a1716")
			elif n.get_noise_2d(x * 9.0 + 100.0, y * 9.0) > thresh:
				col = orec if v > -0.25 else orec.darkened(0.35)
				if q == 3 and _bayer(x, y) > 0.8:
					col = Color.WHITE
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func planet(ptype: String, planet_seed: int, r: int) -> ImageTexture:
	var key := "planet:%s:%d:%d" % [ptype, planet_seed, r]
	if _cache.has(key):
		return _cache[key]
	var pad := 6
	var size := r * 2 + pad * 2
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = planet_seed
	noise.frequency = 0.015
	noise.fractal_octaves = 4
	var pal: Array = PLANET_PAL[ptype]
	var atmo: Color = pal[3].lightened(0.3)
	var light := Vector3(-0.55, -0.45, 0.7).normalized()
	var light2 := Vector2(-0.6, -0.5).normalized()
	var c := Vector2(size, size) / 2.0
	var mults := [0.16, 0.42, 0.72, 1.0]
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var dist := d.length()
			if dist > r + 4:
				continue
			if dist > r:
				# thin atmosphere emissive on the lit side
				var lit := clampf(0.35 + d.normalized().dot(light2), 0.0, 1.0)
				var a := (1.0 - (dist - r) / 4.0) * lit
				if a + (_bayer(x, y) - 0.5) * 0.4 > 0.3:
					img.set_pixel(x, y, Color(atmo, 0.55))
				continue
			var nx := d.x / r
			var ny := d.y / r
			var nz := sqrt(maxf(0.0, 1.0 - nx * nx - ny * ny))
			var nv := noise.get_noise_3d(nx * 100.0, ny * 100.0, nz * 100.0)
			var idx := 0
			var emissive := false
			match ptype:
				"gas":
					var band := sin(ny * 9.0 + nv * 3.0) * 0.5 + 0.5
					idx = clampi(int(band * 5.0), 0, 4)
				"lava":
					if absf(nv) < 0.04:
						idx = 4 if absf(nv) < 0.02 else 3
						emissive = true
					else:
						idx = clampi(int((nv * 0.9 + 0.5) * 3.0), 0, 2)
				_:
					idx = clampi(int(clampf(nv * 1.1 + 0.5, 0.0, 0.999) * 5.0), 0, 4)
			var base: Color = pal[idx]
			var lam := clampf(Vector3(nx, ny, nz).dot(light), 0.0, 1.0)
			var lvl := clampi(int(lam * 3.4 + _bayer(x, y) - 0.2), 0, 3)
			var m: float = mults[lvl]
			if emissive:
				m = maxf(m, 0.85)
			img.set_pixel(x, y, Color(base.r * m, base.g * m, base.b * m, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


func station() -> ImageTexture:
	if _cache.has("station"):
		return _cache["station"]
	var size := 96
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var dist := d.length()
			var col := Color(0, 0, 0, 0)
			if dist >= 26.0 and dist <= 32.0:
				col = Color("5d6577")
				if dist > 31.0 or dist < 27.0:
					col = Color("2a2f3b")
				elif int(rad_to_deg(d.angle()) + 360.0) % 30 < 4:
					col = Color("ffd27a")
			elif dist < 10.0:
				col = Color("8a93a6")
				if dist > 9.0:
					col = Color("2a2f3b")
				elif dist < 2.5:
					col = Color("7ff0ff")
				elif dist < 5.0:
					col = Color("c9d1e0")
			elif dist < 26.0 and (absf(d.x) < 2.0 or absf(d.y) < 2.0):
				col = Color("6f788c")
			elif absf(d.x) > 33.0 and absf(d.x) < 47.0 and absf(d.y) < 7.0:
				col = Color("2b4f8a") if (x % 3 != 0 and y % 3 != 0) else Color("1a2a44")
			elif absf(d.x) > 32.0 and absf(d.x) <= 33.0 and absf(d.y) < 2.0:
				col = Color("6f788c")
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_cache["station"] = tex
	return tex


func gate() -> ImageTexture:
	if _cache.has("gate"):
		return _cache["gate"]
	var size := 84
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var dist := d.length()
			var deg := fposmod(rad_to_deg(d.angle()), 45.0)
			var pylon := deg < 7.0 or deg > 38.0
			if pylon and dist >= 34.0 and dist <= 41.0:
				img.set_pixel(x, y, Color("7ff0ff") if dist > 39.0 else Color("a0a6b8"))
			elif dist >= 31.0 and dist <= 37.0:
				var col := Color("6b6f80")
				if dist > 36.0 or dist < 32.0:
					col = Color("2a2c36")
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_cache["gate"] = tex
	return tex


func nebula(neb_seed: int) -> ImageTexture:
	var key := "nebula:%d" % neb_seed
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = neb_seed
	n.frequency = 0.012
	n.fractal_octaves = 5
	for y in size:
		for x in size:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var edge := minf(minf(x, size - x), minf(y, size - y)) / 40.0
			v *= clampf(edge, 0.0, 1.0)
			var a := floorf(clampf((v - 0.45) * 3.0 + (_bayer(x, y) - 0.5) * 0.2, 0.0, 1.0) * 4.0) / 4.0
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a * 0.22))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


func wreck() -> ImageTexture:
	return from_art("wreck", WRECK_ART, WRECK_PAL)


func crate() -> ImageTexture:
	return from_art("crate", CRATE_ART, CRATE_PAL)


## A 9x9 pixel icon, pre-scaled so each art pixel is `scale` screen pixels.
func icon(icon_name: String, color: Color, scale := 2) -> ImageTexture:
	var key := "icon:%s:%s:%d" % [icon_name, color.to_html(), scale]
	if _cache.has(key):
		return _cache[key]
	var img := art(ICONS[icon_name], {"x": color, "l": color.lightened(0.5), "o": color.darkened(0.65)})
	img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## A 12x12 bevelled pixel frame for 9-slice UI boxes (each art pixel is `scale` screen pixels).
## Corners are notched; `light` runs along the top/left inside edge and `shade` along the bottom/right.
func frame(fill: Color, border: Color, light: Color, shade: Color, scale := 3) -> ImageTexture:
	var key := "frame:%s:%s:%s:%s:%d" % [fill.to_html(), border.to_html(), light.to_html(), shade.to_html(), scale]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	var outline := Color(0.0, 0.0, 0.0, maxf(fill.a, 0.6))
	for y in 12:
		for x in 12:
			var edge_x := x == 0 or x == 11
			var edge_y := y == 0 or y == 11
			var col := fill
			if edge_x and edge_y:
				continue
			elif edge_x or edge_y:
				col = outline
			elif (x == 1 or x == 10) and (y == 1 or y == 10):
				col = outline
			elif x == 1 or x == 10 or y == 1 or y == 10:
				col = border
			elif x == 2 or y == 2:
				col = light
			elif x == 9 or y == 9:
				col = shade
			img.set_pixel(x, y, col)
	img.resize(12 * scale, 12 * scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## A soft round glow, pixelated and dithered so it still looks like pixel art. White; tint with modulate.
func glow() -> ImageTexture:
	if _cache.has("glow"):
		return _cache["glow"]
	var size := 32
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - Vector2(16, 16)).length() / 16.0
			if d >= 1.0:
				continue
			var v := pow(1.0 - d, 2.2)
			v = floorf(clampf(v + (_bayer(x, y) - 0.5) * 0.12, 0.0, 1.0) * 6.0) / 6.0
			if v > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, v))
	var tex := ImageTexture.create_from_image(img)
	_cache["glow"] = tex
	return tex


## Shared additive-blend material: things drawn with it add light instead of covering what's behind.
func add_mat() -> CanvasItemMaterial:
	if not _cache.has("add_mat"):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_cache["add_mat"] = m
	return _cache["add_mat"]


## An additive glow sprite `px` screen pixels across.
func glow_sprite(color: Color, px: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = glow()
	s.material = add_mat()
	s.modulate = color
	s.scale = Vector2.ONE * px / 32.0
	return s

# Menu cursor animation: ring radius (art pixels) for each frame. It pops out past its resting size
# and settles back, so the ring "jumps up" around the dot.
const RING_FRAMES := [0.0, 3.0, 6.0, 9.0, 11.5, 12.5, 11.5, 10.5, 10.0]
const RING_SIZE := 29  # art pixels across; drawn at 2x
const RING_HOTSPOT := Vector2(29, 29)  # the centre of the dot, in screen pixels


## One frame of the dot-and-ring cursor (frame 0 is just the dot).
func cursor_ring(step: int, color := Color("eef4ff")) -> ImageTexture:
	var key := "ring:%d:%s" % [step, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(RING_SIZE, RING_SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2(RING_SIZE, RING_SIZE) / 2.0
	var r: float = RING_FRAMES[step]
	var dark := Color("0a0f1c")
	for y in RING_SIZE:
		for x in RING_SIZE:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length()
			if r > 0.5:
				if absf(d - r) < 0.75:
					img.set_pixel(x, y, color)
				elif absf(d - r) < 1.6:
					img.set_pixel(x, y, dark)
			# the dot itself: 3x3 with a dark rim, always on top
			var o := Vector2(x, y) - (c - Vector2(0.5, 0.5))
			if absi(int(o.x)) <= 1 and absi(int(o.y)) <= 1:
				img.set_pixel(x, y, color)
			elif absi(int(o.x)) <= 2 and absi(int(o.y)) <= 2 and not (absi(int(o.x)) == 2 and absi(int(o.y)) == 2):
				img.set_pixel(x, y, dark)
	img.resize(RING_SIZE * 2, RING_SIZE * 2, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex