class_name MapGen
extends RefCounted
## Procedural mining-town map. The district layout, buildings, tunnels, exits,
## item spots and loot are reshuffled from the seed every match.
##
## Districts (28x28 tiles each, 4x4 of them): M = mine, L = flooded lab,
## T = town, S = swamp, F = fields/woods, H = high ground.

const C := 28
const TEMPLATES := [
	["MMLM", "FTTH", "STTH", "SSFH"],
	["SFHH", "STTH", "MTTF", "LMMS"],
	["MLMS", "MTFS", "HTTF", "HHTS"],
	["HHFS", "HTTS", "FTTM", "SMLM"],
]

var m: MapData
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var grid: Array = []      # [cy][cx] zone letter
var n := 4
var ports := {}           # Vector2i cell -> Array of port tiles
var reserved := {}        # tiles other generators must keep clear
var vehicles: Array = []  # vehicle tiles (for spark plug spots)
var tower_interior: Array = []


func generate(seed_value: int) -> MapData:
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.075
	noise2.seed = seed_value + 77
	noise2.frequency = 0.13
	m = MapData.new()
	m.seed = seed_value
	n = 4
	m.init_arrays(C * n, C * n)
	_layout()
	_base_terrain()
	_reserve_cell_sites()
	for cy in n:
		for cx in n:
			match grid[cy][cx]:
				"T": _town(cx, cy)
				"S": _swamp(cx, cy)
				"F": _field(cx, cy)
	_high_ground()
	_underground()
	_boundary()
	_quarantine_cells()
	_connectivity()
	_gaps()
	_wall_styles()
	_terminals()
	_items()
	_lights_and_amber()
	m.build_zone_index()
	return m


# ------------------------------------------------------------------------------
# Helpers

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _cell_rect(cx: int, cy: int) -> Rect2i:
	return Rect2i(cx * C, cy * C, C, C)


func _zone_of_letter(l: String) -> int:
	match l:
		"T": return Defs.Z.TOWN
		"S": return Defs.Z.SWAMP
		"F": return Defs.Z.FIELD
		"M": return Defs.Z.MINE
		"L": return Defs.Z.LAB
		"H": return Defs.Z.HIGH
	return Defs.Z.NONE


func _underground_letter(l: String) -> bool:
	return l == "M" or l == "L"


func _put(p: Vector2i, tt: int, st: int = -1, rf: int = -1) -> void:
	if not m.inb(p.x, p.y):
		return
	if p.x == 0 or p.y == 0 or p.x == m.w - 1 or p.y == m.h - 1:
		return
	var i := m.idx(p.x, p.y)
	m.tiles[i] = tt
	if st >= 0:
		m.styles[i] = st
	if rf >= 0:
		m.roof[i] = rf


func _area_is(r: Rect2i, ok: Callable) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not m.inb(x, y) or not ok.call(x, y):
				return false
	return true


func _plain_floor(x: int, y: int) -> bool:
	var i := m.idx(x, y)
	return m.tiles[i] == Defs.T.FLOOR and m.roof[i] == Defs.R.NONE and m.floor_h[i] == 0.0 \
		and m.ramp_dir[i] == 0 and not reserved.has(Vector2i(x, y)) \
		and x > 1 and y > 1 and x < m.w - 2 and y < m.h - 2


func _dist_to_set(p: Vector2i, arr: Array) -> float:
	var best := INF
	for q in arr:
		best = minf(best, Vector2(p - q).length())
	return best


# ------------------------------------------------------------------------------
# Layout

func _layout() -> void:
	var tpl: Array = TEMPLATES[rng.randi() % TEMPLATES.size()]
	var g: Array = []
	for row in tpl:
		var r: Array = []
		for i in row.length():
			r.append(row[i])
		g.append(r)
	var rot := rng.randi() % 4
	for _k in rot:
		var ng: Array = []
		for y in n:
			var r2: Array = []
			for x in n:
				r2.append(g[n - 1 - x][y])
			ng.append(r2)
		g = ng
	if rng.randf() < 0.5:
		for y in n:
			g[y].reverse()
	for y in n:
		for x in n:
			if g[y][x] == "S" and rng.randf() < 0.3:
				g[y][x] = "F"
			elif g[y][x] == "F" and rng.randf() < 0.3:
				g[y][x] = "S"
	grid = g
	m.macro = g


func _base_terrain() -> void:
	for cy in n:
		for cx in n:
			var z := _zone_of_letter(grid[cy][cx])
			var st := Defs.S.DIRT
			match z:
				Defs.Z.SWAMP: st = Defs.S.MUD
				Defs.Z.FIELD, Defs.Z.HIGH: st = Defs.S.GRASS
				Defs.Z.MINE, Defs.Z.LAB: st = Defs.S.MINEFLOOR
			var r := _cell_rect(cx, cy)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var i := m.idx(x, y)
					m.zones[i] = z
					m.styles[i] = st
					if _underground_letter(grid[cy][cx]):
						m.tiles[i] = Defs.T.WALL
						m.styles[i] = Defs.S.ROCK
						m.roof[i] = Defs.R.CEILING


# ------------------------------------------------------------------------------
# Surface districts

func _building(r: Rect2i, wall_style: int, floor_style: int, doors: int, windows: int, boarded: float) -> void:
	var perim: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			var p := Vector2i(x, y)
			if edge:
				_put(p, Defs.T.WALL, wall_style, Defs.R.ROOF)
				var corner := (x == r.position.x or x == r.end.x - 1) and (y == r.position.y or y == r.end.y - 1)
				if not corner:
					perim.append(p)
			else:
				_put(p, Defs.T.FLOOR, floor_style, Defs.R.ROOF)
	_shuffle(perim)
	var placed_doors := 0
	var placed_windows := 0
	var used: Array = []
	for p in perim:
		if _dist_to_set(p, used) < 3.0:
			continue
		var out := _outward(p, r)
		if not m.inb(out.x, out.y) or m.t(out.x, out.y) != Defs.T.FLOOR:
			continue
		if placed_doors < doors:
			if rng.randf() < boarded:
				_put(p, Defs.T.BOARDS, Defs.S.PLANK, Defs.R.ROOF)
			else:
				_put(p, Defs.T.FLOOR, floor_style, Defs.R.ROOF)
			placed_doors += 1
			used.append(p)
		elif placed_windows < windows:
			_put(p, Defs.T.GAP, wall_style, Defs.R.ROOF)
			placed_windows += 1
			used.append(p)
		if placed_doors >= doors and placed_windows >= windows:
			break
	# a crate or two inside
	for _i in rng.randi_range(0, 2):
		var ip := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
		if _free_interior(ip, r):
			_put(ip, Defs.T.PROP, Defs.S.CRATE)


func _free_interior(p: Vector2i, r: Rect2i) -> bool:
	# keep doorways clear: no prop adjacent to the perimeter openings
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = p + d
		var tt := m.tv(q)
		if tt == Defs.T.GAP or tt == Defs.T.BOARDS:
			return false
		if (q.x == r.position.x or q.y == r.position.y or q.x == r.end.x - 1 or q.y == r.end.y - 1) and tt == Defs.T.FLOOR:
			return false
	return m.tv(p) == Defs.T.FLOOR


func _outward(p: Vector2i, r: Rect2i) -> Vector2i:
	if p.x == r.position.x:
		return p + Vector2i(-1, 0)
	if p.x == r.end.x - 1:
		return p + Vector2i(1, 0)
	if p.y == r.position.y:
		return p + Vector2i(0, -1)
	return p + Vector2i(0, 1)


func _try_buildings(cx: int, cy: int, count: int, wmin: int, wmax: int, hmin: int, hmax: int,
		wall_style: int, floor_style: int, boarded: float) -> Array:
	var cell := _cell_rect(cx, cy)
	var made: Array = []
	var attempts := 0
	while made.size() < count and attempts < 80:
		attempts += 1
		var bw := rng.randi_range(wmin, wmax)
		var bh := rng.randi_range(hmin, hmax)
		var bx := rng.randi_range(cell.position.x + 2, cell.end.x - bw - 2)
		var by := rng.randi_range(cell.position.y + 2, cell.end.y - bh - 2)
		var r := Rect2i(bx, by, bw, bh)
		var grown := r.grow(2)
		if not _area_is(grown, func(x, y): return _plain_floor(x, y) and m.tiles[m.idx(x, y)] != Defs.T.WATER):
			continue
		_building(r, wall_style, floor_style, rng.randi_range(1, 2), rng.randi_range(1, 2), boarded)
		made.append(r)
	return made


func _vehicle(cx: int, cy: int) -> void:
	var cell := _cell_rect(cx, cy)
	for _a in 30:
		var p := Vector2i(rng.randi_range(cell.position.x + 2, cell.end.x - 4), rng.randi_range(cell.position.y + 2, cell.end.y - 4))
		var horiz := rng.randf() < 0.5
		var q := p + (Vector2i(1, 0) if horiz else Vector2i(0, 1))
		var area := Rect2i(p - Vector2i(1, 1), (q - p) + Vector2i(3, 3))
		if not _area_is(area, func(x, y): return _plain_floor(x, y)):
			continue
		_put(p, Defs.T.PROP, Defs.S.VEHICLE)
		_put(q, Defs.T.PROP, Defs.S.VEHICLE)
		vehicles.append(p)
		vehicles.append(q)
		m.decor.append({"kind": "vehicle", "pos": MapData.to3((MapData.center_of(p) + MapData.center_of(q)) * 0.5), "rot": 0.0 if horiz else PI * 0.5})
		return


func _scatter(cx: int, cy: int, chance: float, tt: int, st: int, noise_gate: float) -> void:
	var cell := _cell_rect(cx, cy)
	for y in range(cell.position.y + 1, cell.end.y - 1):
		for x in range(cell.position.x + 1, cell.end.x - 1):
			if not _plain_floor(x, y):
				continue
			if noise2.get_noise_2d(x, y) < noise_gate:
				continue
			if rng.randf() < chance:
				_put(Vector2i(x, y), tt, st)


func _fence_line(cx: int, cy: int) -> void:
	var cell := _cell_rect(cx, cy)
	var p := Vector2i(rng.randi_range(cell.position.x + 3, cell.end.x - 8), rng.randi_range(cell.position.y + 3, cell.end.y - 8))
	var d := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
	var length := rng.randi_range(3, 6)
	for i in length:
		var q := p + d * i
		if _plain_floor(q.x, q.y) and m.tiles[m.idx(q.x, q.y)] == Defs.T.FLOOR:
			_put(q, Defs.T.FENCE, Defs.S.FENCE)


func _town(cx: int, cy: int) -> void:
	_try_buildings(cx, cy, 5, 5, 9, 5, 8, Defs.S.WOOD, Defs.S.PLANK, 0.25)
	for _i in rng.randi_range(1, 2):
		_vehicle(cx, cy)
	for _i in 2:
		_fence_line(cx, cy)
	_scatter(cx, cy, 0.03, Defs.T.PROP, Defs.S.CRATE, -1.0)
	_poles(cx, cy, 3)


func _swamp(cx: int, cy: int) -> void:
	var cell := _cell_rect(cx, cy)
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if noise.get_noise_2d(x, y) > 0.12 and _plain_floor(x, y):
				m.tiles[m.idx(x, y)] = Defs.T.WATER
	# boardwalks across the water
	for _i in 2:
		var horiz := rng.randf() < 0.5
		var k := rng.randi_range(4, C - 5)
		for j in range(1, C - 1):
			var p := Vector2i(cell.position.x + j, cell.position.y + k) if horiz else Vector2i(cell.position.x + k, cell.position.y + j)
			if m.tv(p) == Defs.T.WATER:
				_put(p, Defs.T.FLOOR, Defs.S.PLANK)
	_try_buildings(cx, cy, 2, 4, 6, 4, 5, Defs.S.WOOD, Defs.S.PLANK, 0.3)
	_scatter(cx, cy, 0.08, Defs.T.TREE, Defs.S.GRASS, 0.0)
	if rng.randf() < 0.5:
		_vehicle(cx, cy)
	_poles(cx, cy, 1)


func _field(cx: int, cy: int) -> void:
	_try_buildings(cx, cy, 1, 7, 9, 6, 8, Defs.S.WOOD, Defs.S.PLANK, 0.3)  # barn
	_scatter(cx, cy, 0.35, Defs.T.TREE, Defs.S.GRASS, 0.2)
	_scatter(cx, cy, 0.02, Defs.T.PROP, Defs.S.BOULDER, -1.0)
	for _i in 3:
		_fence_line(cx, cy)
	_vehicle(cx, cy)
	_poles(cx, cy, 2)


func _poles(cx: int, cy: int, count: int) -> void:
	var cell := _cell_rect(cx, cy)
	var placed := 0
	for _a in 40:
		if placed >= count:
			return
		var p := Vector2i(rng.randi_range(cell.position.x + 2, cell.end.x - 3), rng.randi_range(cell.position.y + 2, cell.end.y - 3))
		if not _plain_floor(p.x, p.y):
			continue
		m.decor.append({"kind": "pole", "pos": MapData.to3(MapData.center_of(p) + Vector2(0.7, 0.7)), "rot": rng.randf() * TAU, "tile": p})
		placed += 1


# ------------------------------------------------------------------------------
# High ground

func _high_ground() -> void:
	# Chebyshev distance from every high tile to the nearest non-high tile
	var dist := PackedInt32Array()
	dist.resize(m.w * m.h)
	dist.fill(-1)
	var bq: Array = []
	for y in m.h:
		for x in m.w:
			if m.zone(x, y) != Defs.Z.HIGH:
				dist[m.idx(x, y)] = 0
				bq.append(Vector2i(x, y))
	var head := 0
	while head < bq.size():
		var bp: Vector2i = bq[head]
		head += 1
		var dp := dist[m.idx(bp.x, bp.y)]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var o := bp + Vector2i(dx, dy)
				if not m.inb(o.x, o.y):
					continue
				var oi := m.idx(o.x, o.y)
				if dist[oi] == -1:
					dist[oi] = dp + 1
					bq.append(o)
	var plateau := {}
	for y in range(1, m.h - 1):
		for x in range(1, m.w - 1):
			var d := dist[m.idx(x, y)]
			if m.zone(x, y) == Defs.Z.HIGH and (d >= 5 or d == -1):
				plateau[Vector2i(x, y)] = true
	if plateau.is_empty():
		return
	# raise the plateau, keeping whatever was generated there flat
	for p in plateau:
		var i := m.idx(p.x, p.y)
		m.tiles[i] = Defs.T.FLOOR
		m.styles[i] = Defs.S.PLATEAU
		m.floor_h[i] = MapData.PLATEAU_H
	# cliff ring
	var ring: Array = []
	for p in plateau:
		var edge := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q: Vector2i = p + Vector2i(dx, dy)
				if not plateau.has(q) and q.x > 0 and q.y > 0 and q.x < m.w - 1 and q.y < m.h - 1:
					edge = true
		if edge:
			ring.append(p)
	for p in ring:
		var i := m.idx(p.x, p.y)
		m.tiles[i] = Defs.T.CLIFF
		m.styles[i] = Defs.S.CLIFF
	# ground strip around the plateau stays at ground level: make sure it is open
	for p in ring:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if not plateau.has(q) and m.t(q.x, q.y) == Defs.T.WALL and m.zone(q.x, q.y) == Defs.Z.HIGH:
				_put(q, Defs.T.FLOOR, Defs.S.GRASS, Defs.R.NONE)
	# ramps: try a few per high district
	var ramps_made := 0
	var cand := ring.duplicate()
	_shuffle(cand)
	var ramp_tiles: Array = []
	for c in cand:
		if ramps_made >= 4:
			break
		if _dist_to_set(c, ramp_tiles) < 14.0:
			continue
		if _try_ramp(c, plateau):
			ramp_tiles.append(c)
			ramps_made += 1
	# watchtower on the plateau
	var keys := plateau.keys()
	_shuffle(keys)
	for p in keys:
		var r := Rect2i(p.x, p.y, 4, 4)
		if _area_is(r.grow(2), func(x, y): return m.t(x, y) == Defs.T.FLOOR and m.floor_h[m.idx(x, y)] == MapData.PLATEAU_H):
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var q := Vector2i(x, y)
					var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
					if edge:
						_put(q, Defs.T.WALL, Defs.S.WOOD, Defs.R.ROOF)
					else:
						_put(q, Defs.T.FLOOR, Defs.S.PLANK, Defs.R.ROOF)
						tower_interior.append(q)
			_put(Vector2i(r.position.x + 1, r.end.y - 1), Defs.T.FLOOR, Defs.S.PLANK, Defs.R.ROOF)
			var c3 := MapData.to3(MapData.center_of(Vector2i(r.position.x + 1, r.position.y + 1)) + Vector2(1, 1), MapData.PLATEAU_H)
			m.decor.append({"kind": "watchtower", "pos": c3, "rot": 0.0})
			m.lights.append({"pos": c3 + Vector3(0, 9.5, 0), "kind": "tower"})
			break
	# scatter trees and boulders on the plateau
	for p in plateau:
		var i := m.idx(p.x, p.y)
		if m.tiles[i] != Defs.T.FLOOR or m.roof[i] != Defs.R.NONE:
			continue
		var near_ramp := false
		for rp in ramp_tiles:
			if Vector2(p - rp).length() < 4.0:
				near_ramp = true
		if near_ramp:
			continue
		if noise2.get_noise_2d(p.x, p.y) > 0.25 and rng.randf() < 0.3:
			m.tiles[i] = Defs.T.TREE
		elif rng.randf() < 0.015:
			m.tiles[i] = Defs.T.PROP
			m.styles[i] = Defs.S.BOULDER


func _try_ramp(c: Vector2i, plateau: Dictionary) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var inward: Vector2i = -d
		var lat := Vector2i(d.y, d.x)
		# c and c+lat must both be cliff; plateau behind them, open ground in front for 4 tiles
		var ok := true
		for w in [0, 1]:
			var b: Vector2i = c + lat * w
			if m.tv(b) != Defs.T.CLIFF:
				ok = false
				break
			var behind: Vector2i = b + inward
			if not plateau.has(behind) or m.tv(behind) != Defs.T.FLOOR:
				ok = false
				break
			for k in range(1, 5):
				var f: Vector2i = b + d * k
				if not m.inb(f.x, f.y) or f.x <= 1 or f.y <= 1 or f.x >= m.w - 2 or f.y >= m.h - 2:
					ok = false
					break
				if plateau.has(f):
					ok = false
					break
		if not ok:
			continue
		# carve: ramp tiles at c, c+d, c+2d (and the lateral twin), side walls of cliff
		var heights := [2.5, 1.5, 0.5]
		var rd := 0
		if inward == Vector2i(1, 0): rd = 1
		elif inward == Vector2i(-1, 0): rd = 2
		elif inward == Vector2i(0, 1): rd = 3
		else: rd = 4
		for w in [0, 1]:
			for k in 3:
				var q: Vector2i = c + lat * w + d * k
				var i := m.idx(q.x, q.y)
				m.tiles[i] = Defs.T.RAMP
				m.styles[i] = Defs.S.PLATEAU
				m.floor_h[i] = heights[k]
				m.ramp_dir[i] = rd
				m.roof[i] = Defs.R.NONE
				reserved[q] = true
			var front: Vector2i = c + lat * w + d * 3
			_put(front, Defs.T.FLOOR, Defs.S.GRASS, Defs.R.NONE)
			reserved[front] = true
		for k in range(1, 3):
			for side in [c - lat + d * k, c + lat * 2 + d * k]:
				var i2 := m.idx(side.x, side.y)
				m.tiles[i2] = Defs.T.CLIFF
				m.styles[i2] = Defs.S.CLIFF
				m.floor_h[i2] = 0.0
		return true
	return false


# ------------------------------------------------------------------------------
# Mines and the flooded lab

func _underground() -> void:
	ports.clear()
	var lab_cell := Vector2i(-1, -1)
	for cy in n:
		for cx in n:
			if grid[cy][cx] == "L":
				lab_cell = Vector2i(cx, cy)
	# ports between underground districts and entrances to the surface
	for cy in n:
		for cx in n:
			if not _underground_letter(grid[cy][cx]):
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var o: Vector2i = Vector2i(cx, cy) + d
				if o.x >= n or o.y >= n:
					continue
				if not _underground_letter(grid[o.y][o.x]):
					continue
				var k := rng.randi_range(7, C - 8)
				var a: Vector2i
				var b: Vector2i
				if d.x == 1:
					a = Vector2i((cx + 1) * C - 1, cy * C + k)
					b = Vector2i((cx + 1) * C, cy * C + k)
				else:
					a = Vector2i(cx * C + k, (cy + 1) * C - 1)
					b = Vector2i(cx * C + k, (cy + 1) * C)
				_add_port(Vector2i(cx, cy), a)
				_add_port(o, b)
	# entrances: each mine district gets one or two to neighbouring surface districts
	for cy in n:
		for cx in n:
			if grid[cy][cx] != "M":
				continue
			var sides: Array = []
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var o: Vector2i = Vector2i(cx, cy) + d
				if o.x < 0 or o.y < 0 or o.x >= n or o.y >= n:
					continue
				if _underground_letter(grid[o.y][o.x]):
					continue
				sides.append(d)
			_shuffle(sides)
			var count := mini(sides.size(), 1 + (1 if rng.randf() < 0.55 else 0))
			for i in count:
				var d: Vector2i = sides[i]
				var k := rng.randi_range(7, C - 9)
				var p: Vector2i
				if d == Vector2i(1, 0): p = Vector2i((cx + 1) * C - 1, cy * C + k)
				elif d == Vector2i(-1, 0): p = Vector2i(cx * C, cy * C + k)
				elif d == Vector2i(0, 1): p = Vector2i(cx * C + k, (cy + 1) * C - 1)
				else: p = Vector2i(cx * C + k, cy * C)
				_add_port(Vector2i(cx, cy), p)
				m.mine_entrances.append({"tile": p, "dir": d})
	# carve each district
	for cy in n:
		for cx in n:
			if grid[cy][cx] == "M":
				_mine_district(cx, cy)
			elif grid[cy][cx] == "L":
				_lab_district(cx, cy)
	# open the entrances onto the surface
	for e in m.mine_entrances:
		var p: Vector2i = e["tile"]
		var d: Vector2i = e["dir"]
		var lat := Vector2i(d.y, d.x)
		for k in range(0, 4):
			for w in [0, 1]:
				var q: Vector2i = p + d * k + lat * w
				if not m.inb(q.x, q.y):
					continue
				var under := m.zone(q.x, q.y) == Defs.Z.MINE
				if not under and m.tile_height(q) > 0.0:
					continue
				_put(q, Defs.T.FLOOR, Defs.S.MINEFLOOR if under else m.style(q.x, q.y), Defs.R.CEILING if under else Defs.R.NONE)
				reserved[q] = true
		var c2 := MapData.center_of(p) + Vector2(lat) * 1.0
		m.decor.append({"kind": "mine_frame", "pos": MapData.to3(c2), "rot": atan2(float(d.x), float(d.y))})
		m.lights.append({"pos": MapData.to3(c2 + Vector2(d) * 2.5, 2.6), "kind": "lantern"})


func _add_port(cell: Vector2i, p: Vector2i) -> void:
	if not ports.has(cell):
		ports[cell] = []
	ports[cell].append(p)


func _carve(p: Vector2i, size: int, st: int) -> void:
	for dy in size:
		for dx in size:
			var q := p + Vector2i(dx, dy)
			if q.x <= 0 or q.y <= 0 or q.x >= m.w - 1 or q.y >= m.h - 1:
				continue
			var i := m.idx(q.x, q.y)
			if m.zones[i] != Defs.Z.MINE and m.zones[i] != Defs.Z.LAB:
				continue
			if m.tiles[i] == Defs.T.WALL:
				m.tiles[i] = Defs.T.FLOOR
				m.styles[i] = st
				m.roof[i] = Defs.R.CEILING


func _tunnel(a: Vector2i, b: Vector2i, bounds: Rect2i, st: int, wiggle: float = 0.35) -> void:
	var p := a
	var guard := 0
	while p != b and guard < 3000:
		guard += 1
		_carve(p, 2, st)
		var d := b - p
		var step := Vector2i.ZERO
		if rng.randf() > wiggle:
			if absi(d.x) > absi(d.y):
				step.x = signi(d.x)
			else:
				step.y = signi(d.y)
		else:
			if rng.randf() < 0.5:
				step.x = 1 if rng.randf() < 0.5 else -1
			else:
				step.y = 1 if rng.randf() < 0.5 else -1
		p += step
		p.x = clampi(p.x, bounds.position.x, bounds.end.x - 1)
		p.y = clampi(p.y, bounds.position.y, bounds.end.y - 1)
	_carve(b, 2, st)


func _blob(c: Vector2i, r: float, st: int) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if Vector2(dx, dy).length() <= r + rng.randf() * 0.6:
				_carve(c + Vector2i(dx, dy), 1, st)


func _mine_district(cx: int, cy: int) -> void:
	var cell := _cell_rect(cx, cy)
	var inner := cell.grow(-1)
	var hub := Vector2i(rng.randi_range(cell.position.x + 9, cell.end.x - 10), rng.randi_range(cell.position.y + 9, cell.end.y - 10))
	_blob(hub, 2.5, Defs.S.MINEFLOOR)
	for p in ports.get(Vector2i(cx, cy), []):
		_tunnel(hub, p, cell, Defs.S.MINEFLOOR)
	# side chambers ("deep shafts")
	for _i in rng.randi_range(2, 3):
		var c := Vector2i(rng.randi_range(inner.position.x + 3, inner.end.x - 4), rng.randi_range(inner.position.y + 3, inner.end.y - 4))
		_blob(c, rng.randf_range(2.0, 3.2), Defs.S.MINEFLOOR)
		_tunnel(c, hub, inner, Defs.S.MINEFLOOR, 0.45)
	# an extra loop so the mine is not a pure tree
	var a := Vector2i(rng.randi_range(inner.position.x + 2, inner.end.x - 3), rng.randi_range(inner.position.y + 2, inner.end.y - 3))
	_tunnel(a, hub, inner, Defs.S.MINEFLOOR, 0.5)
	# rails and timber decor along a few tunnel tiles
	var count := 0
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if m.t(x, y) == Defs.T.FLOOR and rng.randf() < 0.025 and count < 10:
				m.decor.append({"kind": "timber", "pos": MapData.to3(MapData.center_of(Vector2i(x, y))), "rot": 0.0})
				count += 1


func _lab_district(cx: int, cy: int) -> void:
	var cell := _cell_rect(cx, cy)
	var rooms: Array = []
	for j in 3:
		for i in 3:
			var size := Vector2i(rng.randi_range(5, 7), rng.randi_range(5, 7))
			if i == 1 and j == 1:
				size = Vector2i(8, 8)
			var center := Vector2i(cell.position.x + 5 + i * 9, cell.position.y + 5 + j * 9)
			var pos := center - size / 2
			pos.x = clampi(pos.x, cell.position.x + 1, cell.end.x - size.x - 1)
			pos.y = clampi(pos.y, cell.position.y + 1, cell.end.y - size.y - 1)
			var r := Rect2i(pos, size)
			rooms.append(r)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var q := Vector2i(x, y)
					var ii := m.idx(x, y)
					m.tiles[ii] = Defs.T.FLOOR
					m.styles[ii] = Defs.S.LABFLOOR
					m.roof[ii] = Defs.R.CEILING
	# corridors: a spanning tree over the 3x3 room grid plus a couple of extras
	var edges: Array = []
	for j in 3:
		for i in 3:
			if i < 2:
				edges.append([j * 3 + i, j * 3 + i + 1])
			if j < 2:
				edges.append([j * 3 + i, (j + 1) * 3 + i])
	_shuffle(edges)
	var parent := []
	for i in 9:
		parent.append(i)
	var find := func(x: int) -> int:
		while parent[x] != x:
			x = parent[x]
		return x
	var extra := 0
	for e in edges:
		var ra: int = find.call(e[0])
		var rb: int = find.call(e[1])
		if ra != rb or extra < 2:
			if ra == rb:
				extra += 1
			parent[ra] = rb
			_corridor(rooms[e[0]].get_center(), rooms[e[1]].get_center())
	for p in ports.get(Vector2i(cx, cy), []):
		var best: Rect2i = rooms[0]
		for r in rooms:
			if Vector2(r.get_center() - p).length() < Vector2(best.get_center() - p).length():
				best = r
		_corridor(best.get_center(), p)
	# flooding
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			var ii := m.idx(x, y)
			if m.tiles[ii] == Defs.T.FLOOR and m.zones[ii] == Defs.Z.LAB and noise.get_noise_2d(x * 1.7, y * 1.7) > 0.05:
				m.tiles[ii] = Defs.T.WATER
	# the Nest sits in the central room
	var nest_r: Rect2i = rooms[4]
	m.nest_room = nest_r
	m.nest = nest_r.get_center()
	for y in range(nest_r.position.y, nest_r.end.y):
		for x in range(nest_r.position.x, nest_r.end.x):
			var ii := m.idx(x, y)
			m.tiles[ii] = Defs.T.FLOOR
			m.styles[ii] = Defs.S.LABFLOOR
			reserved[Vector2i(x, y)] = true
	var nc := MapData.center_of(m.nest)
	m.killer_spawns = [nc + Vector2(-2.5, -1.5), nc + Vector2(2.5, -1.5), nc + Vector2(0, 2.8)]
	m.lights.append({"pos": MapData.to3(nc, 1.2), "kind": "nest"})
	# emergency lights in rooms
	for r in rooms:
		if r == nest_r:
			continue
		m.lights.append({"pos": MapData.to3(MapData.center_of(r.get_center()), 2.9), "kind": "emergency"})


func _corridor(a: Vector2i, b: Vector2i) -> void:
	var p := a
	var horiz_first := rng.randf() < 0.5
	var guard := 0
	while p != b and guard < 200:
		guard += 1
		_carve_lab(p)
		var d := b - p
		if (horiz_first and d.x != 0) or d.y == 0:
			p.x += signi(d.x)
		else:
			p.y += signi(d.y)
	_carve_lab(b)


func _carve_lab(p: Vector2i) -> void:
	for dy in 2:
		for dx in 2:
			var q := p + Vector2i(dx, dy)
			if q.x <= 0 or q.y <= 0 or q.x >= m.w - 1 or q.y >= m.h - 1:
				continue
			var i := m.idx(q.x, q.y)
			if m.tiles[i] == Defs.T.WALL and (m.zones[i] == Defs.Z.LAB or m.zones[i] == Defs.Z.MINE):
				m.tiles[i] = Defs.T.FLOOR
				m.styles[i] = Defs.S.LABFLOOR if m.zones[i] == Defs.Z.LAB else Defs.S.MINEFLOOR
				m.roof[i] = Defs.R.CEILING


# ------------------------------------------------------------------------------
# Boundary, cells, connectivity, gaps

func _boundary() -> void:
	for x in m.w:
		for y in [0, m.h - 1]:
			var i := m.idx(x, y)
			m.tiles[i] = Defs.T.WALL
			m.styles[i] = Defs.S.CLIFF
	for y in m.h:
		for x in [0, m.w - 1]:
			var i := m.idx(x, y)
			m.tiles[i] = Defs.T.WALL
			m.styles[i] = Defs.S.CLIFF


var cell_sites: Array = []  # reserved 7x7 areas for the normal quarantine cells


func _reserve_cell_sites() -> void:
	var order: Array = []
	var lab := Vector2i(-1, -1)
	for cy in n:
		for cx in n:
			var l: String = grid[cy][cx]
			if l == "T" or l == "S" or l == "F":
				order.append(Vector2i(cx, cy))
			if l == "L":
				lab = Vector2i(cx, cy)
	_shuffle(order)
	var lab_c := Vector2(lab * C + Vector2i(C / 2, C / 2))
	var centers: Array = []
	for spacing in [26.0, 20.0, 14.0, 8.0]:
		for cellp in order:
			if cell_sites.size() >= Tuning.DUOS - 1:
				break
			var used := false
			for s2 in cell_sites:
				if s2["cell"] == cellp:
					used = true
			if used:
				continue
			var r := _cell_rect(cellp.x, cellp.y)
			for _a in 60:
				var p := Vector2i(rng.randi_range(r.position.x + 3, r.end.x - 10), rng.randi_range(r.position.y + 3, r.end.y - 10))
				var area := Rect2i(p, Vector2i(7, 7))
				var c := Vector2(area.get_center())
				if c.distance_to(lab_c) < 30.0:
					continue
				var ok := true
				for oc in centers:
					if c.distance_to(oc) < spacing:
						ok = false
				if not ok:
					continue
				cell_sites.append({"cell": cellp, "area": area})
				centers.append(c)
				for y in range(area.position.y, area.end.y):
					for x in range(area.position.x, area.end.x):
						reserved[Vector2i(x, y)] = true
				break
		if cell_sites.size() >= Tuning.DUOS - 1:
			break


func _quarantine_cells() -> void:
	var placed: Array = []
	var nest_c := m.nest
	for site in cell_sites:
		var area: Rect2i = site["area"]
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var i := m.idx(x, y)
				m.tiles[i] = Defs.T.FLOOR
				m.roof[i] = Defs.R.NONE
				m.floor_h[i] = 0.0
				m.ramp_dir[i] = 0
		_stamp_cell(Rect2i(area.position + Vector2i(1, 1), Vector2i(5, 5)), false)
		placed.append(area.get_center())
	var order: Array = []
	for cy in n:
		for cx in n:
			var l: String = grid[cy][cx]
			if l == "T" or l == "S" or l == "F":
				order.append(Vector2i(cx, cy))
	# the worse trap: deep in a mine
	var mine_cells: Array = []
	for cy in n:
		for cx in n:
			if grid[cy][cx] == "M":
				mine_cells.append(Vector2i(cx, cy))
	_shuffle(mine_cells)
	var done := false
	for mc in mine_cells:
		var r := _cell_rect(mc.x, mc.y)
		var floors: Array = []
		for y in range(r.position.y + 5, r.end.y - 5):
			for x in range(r.position.x + 5, r.end.x - 5):
				if m.t(x, y) == Defs.T.FLOOR:
					floors.append(Vector2i(x, y))
		_shuffle(floors)
		for f in floors:
			if Vector2(f - nest_c).length() < 22.0 or _dist_to_set(f, placed) < 22.0:
				continue
			var area := Rect2i(f - Vector2i(3, 3), Vector2i(7, 7))
			for y in range(area.position.y, area.end.y):
				for x in range(area.position.x, area.end.x):
					_put(Vector2i(x, y), Defs.T.FLOOR, Defs.S.MINEFLOOR, Defs.R.CEILING)
			_stamp_cell(Rect2i(area.position + Vector2i(1, 1), Vector2i(5, 5)), true)
			placed.append(f)
			done = true
			break
		if done:
			break
	# fallback: if the mine had no room, put the last cell on the surface
	var guard := 0
	while m.cells.size() < Tuning.DUOS and guard < 5000:
		guard += 1
		var cellp: Vector2i = order[rng.randi() % order.size()]
		var r := _cell_rect(cellp.x, cellp.y)
		var p := Vector2i(rng.randi_range(r.position.x + 2, r.end.x - 9), rng.randi_range(r.position.y + 2, r.end.y - 9))
		var area := Rect2i(p, Vector2i(7, 7))
		if _area_is(area, func(x, y): return _plain_floor(x, y)):
			_stamp_cell(Rect2i(p + Vector2i(1, 1), Vector2i(5, 5)), m.cells.size() == Tuning.DUOS - 1 and not done)
			done = true
	_shuffle(m.cells)


func _stamp_cell(r: Rect2i, worse: bool) -> void:
	var interior: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			if edge:
				_put(p, Defs.T.WALL, Defs.S.QUARANTINE, Defs.R.ROOF)
			else:
				_put(p, Defs.T.FLOOR, Defs.S.METAL, Defs.R.ROOF)
				interior.append(p)
			reserved[p] = true
	var sides := [
		[Vector2i(r.position.x + 2, r.position.y), Vector2i(0, -1)],
		[Vector2i(r.position.x + 2, r.end.y - 1), Vector2i(0, 1)],
		[Vector2i(r.position.x, r.position.y + 2), Vector2i(-1, 0)],
		[Vector2i(r.end.x - 1, r.position.y + 2), Vector2i(1, 0)],
	]
	_shuffle(sides)
	var door: Vector2i = sides[0][0]
	var ddir: Vector2i = sides[0][1]
	for s in sides:
		var outside: Vector2i = s[0] + s[1]
		if m.walkable(outside.x, outside.y, false):
			door = s[0]
			ddir = s[1]
			break
	_put(door, Defs.T.CELL_DOOR, Defs.S.QUARANTINE, Defs.R.ROOF)
	_put(door + ddir, Defs.T.FLOOR, -1, -1)
	var c := r.get_center()
	var levers: Array = []
	if worse:
		levers = [Vector2i(r.position.x + 1, r.position.y + 1), Vector2i(r.end.x - 2, r.end.y - 2)]
	var spawns := [MapData.center_of(Vector2i(r.position.x + 1, c.y)) , MapData.center_of(Vector2i(r.end.x - 2, c.y))]
	m.cells.append({"rect": r, "door": door, "dir": ddir, "levers": levers, "worse": worse, "spawns": spawns})
	m.lights.append({"pos": MapData.to3(MapData.center_of(c), 2.8), "kind": "cell"})


func _region_labels(include_doors: bool) -> Dictionary:
	var label := PackedInt32Array()
	label.resize(m.w * m.h)
	label.fill(-1)
	var sizes: Array = []
	var next := 0
	for y in m.h:
		for x in m.w:
			var i := m.idx(x, y)
			if label[i] != -1 or not _conn_walk(m.tiles[i], include_doors):
				continue
			var q := [Vector2i(x, y)]
			label[i] = next
			var size := 0
			var head := 0
			while head < q.size():
				var p: Vector2i = q[head]
				head += 1
				size += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var o: Vector2i = p + d
					if not m.inb(o.x, o.y):
						continue
					var oi := m.idx(o.x, o.y)
					if label[oi] != -1 or not _conn_walk(m.tiles[oi], include_doors):
						continue
					if not _height_step_ok(p, o):
						continue
					label[oi] = next
					q.append(o)
			sizes.append(size)
			next += 1
	return {"label": label, "sizes": sizes}


func _conn_walk(tt: int, include_doors: bool) -> bool:
	if tt == Defs.T.FLOOR or tt == Defs.T.WATER or tt == Defs.T.RAMP:
		return true
	if include_doors and (tt == Defs.T.CELL_DOOR or tt == Defs.T.BOARDS):
		return true
	return false


func _height_step_ok(a: Vector2i, b: Vector2i) -> bool:
	var ha := m.height_at((MapData.center_of(a) + MapData.center_of(b)) * 0.5 + (MapData.center_of(a) - MapData.center_of(b)) * 0.01)
	var hb := m.height_at((MapData.center_of(a) + MapData.center_of(b)) * 0.5 + (MapData.center_of(b) - MapData.center_of(a)) * 0.01)
	return absf(ha - hb) < 0.7


func _connectivity() -> void:
	for _iter in 12:
		var res := _region_labels(true)
		var label: PackedInt32Array = res["label"]
		var sizes: Array = res["sizes"]
		var main := label[m.idx(m.nest.x, m.nest.y)]
		if main < 0:
			var best := 0
			for i in sizes.size():
				if sizes[i] > sizes[best]:
					best = i
			main = best
		if sizes.size() <= 1:
			return
		var by_region := {}
		for y in m.h:
			for x in m.w:
				var lb := label[m.idx(x, y)]
				if lb >= 0 and lb != main:
					if not by_region.has(lb):
						by_region[lb] = []
					by_region[lb].append(Vector2i(x, y))
		var changed := false
		for rid in by_region:
			var tiles: Array = by_region[rid]
			if tiles.size() < 4:
				for p in tiles:
					_put(p, Defs.T.PROP, Defs.S.BOULDER)
				changed = true
				continue
			if _bridge_region(tiles, label, main):
				changed = true
				continue
			# an isolated piece of plateau: try to give it a ramp
			if m.tile_height(tiles[0]) > 2.0 and _ramp_for_region(tiles):
				changed = true
				continue
			# unreachable: close it off so nothing spawns there
			for p in tiles:
				_put(p, Defs.T.PROP, Defs.S.BOULDER)
			changed = true
		if not changed:
			return


func _ramp_for_region(tiles: Array) -> bool:
	var plateau := {}
	for y in m.h:
		for x in m.w:
			if m.floor_h[m.idx(x, y)] >= MapData.PLATEAU_H - 0.01:
				plateau[Vector2i(x, y)] = true
	var region := {}
	for p in tiles:
		region[p] = true
	var cliffs: Array = []
	for p in tiles:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var o: Vector2i = p + d
			if m.tv(o) == Defs.T.CLIFF:
				cliffs.append(o)
	_shuffle(cliffs)
	for c in cliffs:
		if _try_ramp(c, plateau):
			return true
	return false


func _bridge_region(tiles: Array, label: PackedInt32Array, main: int) -> bool:
	# BFS outwards through carvable solid tiles until we touch the main region
	var prev := {}
	var q: Array = []
	for p in tiles:
		prev[p] = p
		q.append(p)
	var head := 0
	var target := Vector2i(-1, -1)
	var h0 := m.tile_height(tiles[0])
	while head < q.size() and head < 20000:
		var p: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var o: Vector2i = p + d
			if prev.has(o) or o.x <= 0 or o.y <= 0 or o.x >= m.w - 1 or o.y >= m.h - 1:
				continue
			var oi := m.idx(o.x, o.y)
			if label[oi] == main and absf(m.tile_height(o) - h0) < 0.1:
				prev[o] = p
				target = o
				break
			var tt := m.tiles[oi]
			if tt == Defs.T.CLIFF or tt == Defs.T.VOID or tt == Defs.T.RAMP or tt == Defs.T.CELL_DOOR:
				continue
			if absf(m.floor_h[oi] - h0) > 0.1 and tt != Defs.T.WALL:
				continue
			if m.styles[oi] == Defs.S.QUARANTINE or reserved.has(o) and tt != Defs.T.FLOOR:
				continue
			if label[oi] >= 0:
				continue  # a different small region: route around it
			prev[o] = p
			q.append(o)
		if target.x >= 0:
			break
	if target.x < 0:
		return false
	var cur: Vector2i = prev[target]
	while prev[cur] != cur:
		var i := m.idx(cur.x, cur.y)
		var under := m.zones[i] == Defs.Z.MINE or m.zones[i] == Defs.Z.LAB
		m.tiles[i] = Defs.T.FLOOR
		m.floor_h[i] = h0
		if under:
			m.styles[i] = Defs.S.MINEFLOOR
			m.roof[i] = Defs.R.CEILING
		elif m.roof[i] == Defs.R.ROOF:
			pass
		cur = prev[cur]
	return true


func _gaps() -> void:
	var cand: Array = []
	for y in range(2, m.h - 2):
		for x in range(2, m.w - 2):
			var i := m.idx(x, y)
			if m.tiles[i] != Defs.T.WALL:
				continue
			var st := m.styles[i]
			if st == Defs.S.CLIFF or st == Defs.S.QUARANTINE:
				continue
			var lr := m.walkable(x - 1, y, false) and m.walkable(x + 1, y, false) and m.is_solid_static(x, y - 1) and m.is_solid_static(x, y + 1)
			var ud := m.walkable(x, y - 1, false) and m.walkable(x, y + 1, false) and m.is_solid_static(x - 1, y) and m.is_solid_static(x + 1, y)
			if not (lr or ud):
				continue
			var a := Vector2i(x - 1, y) if lr else Vector2i(x, y - 1)
			var b := Vector2i(x + 1, y) if lr else Vector2i(x, y + 1)
			if absf(m.tile_height(a) - m.tile_height(b)) > 0.1 or m.tv(a) == Defs.T.RAMP or m.tv(b) == Defs.T.RAMP:
				continue
			var dist := _walk_dist(a, b, 13)
			if dist < 0 or dist > 12:
				cand.append(Vector2i(x, y))
	_shuffle(cand)
	var made: Array = []
	for p in cand:
		if made.size() >= 46:
			break
		if _dist_to_set(p, made) < 5.0:
			continue
		m.tiles[m.idx(p.x, p.y)] = Defs.T.GAP
		made.append(p)


func _walk_dist(a: Vector2i, b: Vector2i, limit: int) -> int:
	var dist := {a: 0}
	var q := [a]
	var head := 0
	while head < q.size():
		var p: Vector2i = q[head]
		head += 1
		var dp: int = dist[p]
		if p == b:
			return dp
		if dp >= limit:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var o: Vector2i = p + d
			if dist.has(o) or not m.walkable(o.x, o.y, false):
				continue
			dist[o] = dp + 1
			q.append(o)
	return -1


func _wall_styles() -> void:
	# lab walls get panels, mine walls next to wooden buildings stay rock
	for y in m.h:
		for x in m.w:
			var i := m.idx(x, y)
			if m.tiles[i] != Defs.T.WALL and m.tiles[i] != Defs.T.GAP:
				continue
			if m.zones[i] == Defs.Z.LAB and m.styles[i] == Defs.S.ROCK:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if m.style(x + d.x, y + d.y) == Defs.S.LABFLOOR:
						m.styles[i] = Defs.S.LAB
						break


# ------------------------------------------------------------------------------
# Terminals, items, lights

func _terminals() -> void:
	var want := ["T", "S", "F", "H", "T", "F", "S", "T", "H", "M"]
	var used_cells := {}
	for l in want:
		var spacing := 30.0 if m.terminals.size() < 3 else 20.0
		if m.terminals.size() >= Tuning.SHOP_TERMINALS:
			break
		var cells: Array = []
		for cy in n:
			for cx in n:
				if grid[cy][cx] == l and not used_cells.has(Vector2i(cx, cy)):
					cells.append(Vector2i(cx, cy))
		if cells.is_empty():
			continue
		var cp: Vector2i = cells[rng.randi() % cells.size()]
		var r := _cell_rect(cp.x, cp.y)
		for _a in 200:
			var p := Vector2i(rng.randi_range(r.position.x + 3, r.end.x - 4), rng.randi_range(r.position.y + 3, r.end.y - 4))
			var i := m.idx(p.x, p.y)
			if m.tiles[i] != Defs.T.FLOOR or m.roof[i] != Defs.R.NONE or reserved.has(p):
				continue
			if _dist_to_set(p, m.terminals) < spacing:
				continue
			var wall_n := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var tt := m.t(p.x + d.x, p.y + d.y)
				if tt == Defs.T.WALL or tt == Defs.T.CLIFF:
					wall_n = true
			if not wall_n:
				continue
			m.terminals.append(p)
			reserved[p] = true
			used_cells[cp] = true
			break


func _items() -> void:
	var cand := []
	for _k in 6:
		cand.append([])
	var entr: Array = []
	for e in m.mine_entrances:
		entr.append(e["tile"])
	var vehicle_set := {}
	for v in vehicles:
		vehicle_set[v] = true
	var pole_tiles: Array = []
	for d in m.decor:
		if d["kind"] == "pole":
			pole_tiles.append(d["tile"])
	var any_floor: Array = []
	for y in range(1, m.h - 1):
		for x in range(1, m.w - 1):
			var i := m.idx(x, y)
			var tt := m.tiles[i]
			if tt != Defs.T.FLOOR:
				continue
			var p := Vector2i(x, y)
			if reserved.has(p) and m.zone(x, y) != Defs.Z.HIGH:
				continue
			if m.nest_room.grow(2).has_point(p):
				continue
			var z := m.zones[i]
			var near_wall := false
			var near_vehicle := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var o: Vector2i = p + d
				var ot := m.tv(o)
				if ot == Defs.T.WALL:
					near_wall = true
				if vehicle_set.has(o):
					near_vehicle = true
			any_floor.append(p)
			if (z == Defs.Z.TOWN or z == Defs.Z.FIELD or z == Defs.Z.SWAMP) and (m.roof[i] == Defs.R.ROOF or _dist_to_set(p, pole_tiles) < 2.5):
				if m.styles[i] != Defs.S.METAL:
					cand[Defs.P.CABLE].append(p)
			if near_vehicle:
				cand[Defs.P.SPARK].append(p)
			if z == Defs.Z.MINE:
				var de := _dist_to_set(p, entr)
				if de < 11.0:
					cand[Defs.P.FUEL].append(p)
				elif de > 15.0:
					cand[Defs.P.CELL].append(p)
			if z == Defs.Z.LAB:
				cand[Defs.P.CIRCUIT].append(p)
			if z == Defs.Z.HIGH and m.floor_h[i] > 2.0:
				var cliff_n := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if m.tv(p + d) == Defs.T.CLIFF:
						cliff_n = true
				if cliff_n or tower_interior.has(p):
					cand[Defs.P.DISH].append(p)
	var taken := {}
	for part in 6:
		var arr: Array = cand[part]
		if part == Defs.P.DISH:
			# always one in the watchtower
			for tp in tower_interior:
				if m.tv(tp) == Defs.T.FLOOR:
					m.items.append({"kind": Defs.Item.PART, "part": part, "tile": tp, "amount": 1})
					taken[tp] = true
					break
		_shuffle(arr)
		var picked: Array = []
		var want: int = Tuning.PART_COUNTS[part]
		if part == Defs.P.DISH:
			want -= 1
		for spacing in [9.0, 6.0, 3.0, 0.0]:
			for p in arr:
				if picked.size() >= want:
					break
				if taken.has(p) or _dist_to_set(p, picked) < spacing:
					continue
				picked.append(p)
				taken[p] = true
			if picked.size() >= want:
				break
		# not enough special spots (small zones): fall back to any floor in the right zone family
		while picked.size() < want and not any_floor.is_empty():
			var p2: Vector2i = any_floor[rng.randi() % any_floor.size()]
			if not taken.has(p2):
				picked.append(p2)
				taken[p2] = true
		for p in picked:
			m.items.append({"kind": Defs.Item.PART, "part": part, "tile": p, "amount": 1})
	_shuffle(any_floor)
	var cash := 0
	var scrap := 0
	var flares: Array = []
	var cells_rects: Array = []
	for c in m.cells:
		cells_rects.append(c["rect"].grow(1))
	var loot_grid := {}
	for p in any_floor:
		if taken.has(p) or m.terminals.has(p):
			continue
		var in_cell := false
		for r in cells_rects:
			if r.has_point(p):
				in_cell = true
		if in_cell:
			continue
		var coarse := Vector2i(p.x / 3, p.y / 3)
		if loot_grid.has(coarse):
			continue
		loot_grid[coarse] = true
		var i := m.idx(p.x, p.y)
		var roofed := m.roof[i] != Defs.R.NONE
		if flares.size() < Tuning.FLARE_COUNT and _dist_to_set(p, flares) > 34.0 and Vector2(p - m.nest).length() > 20.0:
			flares.append(p)
			taken[p] = true
			m.items.append({"kind": Defs.Item.FLARE, "part": -1, "tile": p, "amount": 1})
			continue
		if cash < Tuning.CASH_CACHES and (roofed or rng.randf() < 0.45):
			cash += 1
			taken[p] = true
			m.items.append({"kind": Defs.Item.CASH, "part": -1, "tile": p, "amount": rng.randi_range(Tuning.CASH_MIN, Tuning.CASH_MAX)})
			continue
		if scrap < Tuning.SCRAP_PILES and rng.randf() < 0.5:
			scrap += 1
			taken[p] = true
			m.items.append({"kind": Defs.Item.SCRAP, "part": -1, "tile": p, "amount": Tuning.SCRAP_PER_PILE})
		if cash >= Tuning.CASH_CACHES and scrap >= Tuning.SCRAP_PILES and flares.size() >= Tuning.FLARE_COUNT:
			break


func _lights_and_amber() -> void:
	# lanterns mounted on building walls and on posts
	var floors_by_zone := {}
	for y in range(1, m.h - 1):
		for x in range(1, m.w - 1):
			var i := m.idx(x, y)
			if m.tiles[i] != Defs.T.FLOOR or m.roof[i] != Defs.R.NONE:
				continue
			var z := int(m.zones[i])
			if not floors_by_zone.has(z):
				floors_by_zone[z] = []
			floors_by_zone[z].append(Vector2i(x, y))
	var want := {Defs.Z.TOWN: 6, Defs.Z.SWAMP: 3, Defs.Z.FIELD: 2, Defs.Z.HIGH: 3}
	var lit: Array = []
	for cy in n:
		for cx in n:
			var z := _zone_of_letter(grid[cy][cx])
			if not want.has(z):
				continue
			var r := _cell_rect(cx, cy)
			var count := 0
			var arr: Array = []
			for p in floors_by_zone.get(z, []):
				if r.has_point(p):
					arr.append(p)
			_shuffle(arr)
			for p in arr:
				if count >= want[z]:
					break
				if _dist_to_set(p, lit) < 8.0:
					continue
				var wall_dir := Vector2i.ZERO
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if m.tv(p + d) == Defs.T.WALL:
						wall_dir = d
				var c := MapData.center_of(p)
				var hgt := m.tile_height(p)
				if wall_dir != Vector2i.ZERO:
					var lp := c + Vector2(wall_dir) * 0.8
					m.lights.append({"pos": MapData.to3(lp, hgt + 2.5), "kind": "lantern"})
					m.decor.append({"kind": "wall_lantern", "pos": MapData.to3(lp, hgt + 2.5), "rot": atan2(float(wall_dir.x), float(wall_dir.y))})
				else:
					m.lights.append({"pos": MapData.to3(c, hgt + 2.7), "kind": "lantern"})
					m.decor.append({"kind": "lantern_post", "pos": MapData.to3(c, hgt), "rot": 0.0})
				lit.append(p)
				count += 1
	# a few dim lanterns deep in the mines
	var mine_floor: Array = []
	for p in m.zone_tiles_raw(Defs.Z.MINE):
		mine_floor.append(p)
	_shuffle(mine_floor)
	var mines_lit := 0
	for p in mine_floor:
		if mines_lit >= 6:
			break
		if _dist_to_set(p, lit) < 14.0:
			continue
		m.lights.append({"pos": MapData.to3(MapData.center_of(p), 2.4), "kind": "mine"})
		lit.append(p)
		mines_lit += 1
	# amber: the infection grows out of walls, thickest underground
	var amber_cand: Array = []
	for y in range(1, m.h - 1):
		for x in range(1, m.w - 1):
			var i := m.idx(x, y)
			if m.tiles[i] != Defs.T.FLOOR and m.tiles[i] != Defs.T.WATER:
				continue
			var z := m.zones[i]
			var wgt := 0.25
			if z == Defs.Z.MINE or z == Defs.Z.LAB:
				wgt = 1.0
			elif z == Defs.Z.SWAMP:
				wgt = 0.6
			var wall_n := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var tt := m.t(x + d.x, y + d.y)
				if tt == Defs.T.WALL or tt == Defs.T.CLIFF:
					wall_n = true
			if wall_n and rng.randf() < wgt * 0.05:
				amber_cand.append(Vector2i(x, y))
	_shuffle(amber_cand)
	var made: Array = []
	for p in amber_cand:
		if made.size() >= 46:
			break
		if _dist_to_set(p, made) < 7.0:
			continue
		var c3 := MapData.to3(MapData.center_of(p), m.tile_height(p))
		m.amber.append(c3)
		made.append(p)
		if made.size() % 2 == 0:
			m.lights.append({"pos": c3 + Vector3(0, 0.8, 0), "kind": "amber"})
	# the nest room is full of it
	for k in 7:
		var a := float(k) / 7.0 * TAU
		var c3 := MapData.to3(MapData.center_of(m.nest) + Vector2(cos(a), sin(a)) * 4.5, 0.0)
		m.amber.append(c3)
