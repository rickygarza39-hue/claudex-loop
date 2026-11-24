class_name MapData
extends RefCounted
## The generated map: a grid of tiles plus feature lists. Pure data, no nodes,
## so the headless simulation can use it without building any 3D.

const TILE := Defs.TILE
const WALL_H := 3.6
const CLIFF_H := 4.2
const PLATEAU_H := 3.0
const VOID_H := -9.0
const CEILING_H := 3.3
const ROOF_H := 3.6

var w := 0
var h := 0
var seed := 0
var tiles := PackedByteArray()
var zones := PackedByteArray()
var styles := PackedByteArray()
var floor_h := PackedFloat32Array()
var ramp_dir := PackedByteArray()   # 0 none, 1 +x, 2 -x, 3 +y, 4 -y (direction of ascent)
var roof := PackedByteArray()
var dyn_top := PackedFloat32Array() # obstacle tops from survivor-built structures (0 = none)
var macro: Array = []               # rows of zone letters

# Features
var cells: Array = []        # quarantine cells: {rect, door, levers, worse, spawns}
var nest := Vector2i.ZERO
var nest_room := Rect2i()
var killer_spawns: Array = []
var terminals: Array = []    # Vector2i
var lights: Array = []       # {pos: Vector3, kind: String}
var amber: Array = []        # Vector3 crystal clusters
var decor: Array = []        # {kind, pos: Vector3, rot: float}
var items: Array = []        # {kind, part, tile: Vector2i, amount}
var mine_entrances: Array = []
var zone_tiles := {}         # zone -> Array[Vector2i] of walkable tiles (filled after gen)


func init_arrays(width: int, height: int) -> void:
	w = width
	h = height
	var n := w * h
	tiles.resize(n)
	tiles.fill(Defs.T.FLOOR)
	zones.resize(n)
	zones.fill(Defs.Z.NONE)
	styles.resize(n)
	styles.fill(Defs.S.DIRT)
	floor_h.resize(n)
	floor_h.fill(0.0)
	ramp_dir.resize(n)
	ramp_dir.fill(0)
	roof.resize(n)
	roof.fill(Defs.R.NONE)
	dyn_top.resize(n)
	dyn_top.fill(0.0)


func idx(x: int, y: int) -> int:
	return y * w + x


func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func t(x: int, y: int) -> int:
	if not inb(x, y):
		return Defs.T.WALL
	return tiles[y * w + x]


func set_t(x: int, y: int, v: int) -> void:
	if inb(x, y):
		tiles[y * w + x] = v


func tv(p: Vector2i) -> int:
	return t(p.x, p.y)


func zone(x: int, y: int) -> int:
	if not inb(x, y):
		return Defs.Z.NONE
	return zones[y * w + x]


func style(x: int, y: int) -> int:
	if not inb(x, y):
		return Defs.S.ROCK
	return styles[y * w + x]


static func walkable_type(tt: int, survivor: bool) -> bool:
	match tt:
		Defs.T.FLOOR, Defs.T.WATER, Defs.T.RAMP:
			return true
		Defs.T.GAP:
			return survivor
	return false


func walkable(x: int, y: int, survivor: bool) -> bool:
	return walkable_type(t(x, y), survivor)


func is_solid_static(x: int, y: int) -> bool:
	## Solid for everybody (ignores gaps and structures).
	return not walkable_type(t(x, y), true)


# ---- Coordinates --------------------------------------------------------------

static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


static func center_of(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TILE, (tile.y + 0.5) * TILE)


static func to3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func height_at(p: Vector2) -> float:
	var tl := tile_of(p)
	if not inb(tl.x, tl.y):
		return 0.0
	var i := idx(tl.x, tl.y)
	var base := floor_h[i]
	var rd := ramp_dir[i]
	if rd == 0:
		return base
	var c := center_of(tl)
	var off := 0.0
	match rd:
		1: off = p.x - c.x
		2: off = c.x - p.x
		3: off = p.y - c.y
		4: off = c.y - p.y
	return base + off * 0.5


func tile_height(tl: Vector2i) -> float:
	if not inb(tl.x, tl.y):
		return 0.0
	return floor_h[idx(tl.x, tl.y)]


## Height of whatever blocks sight on this tile; -INF when nothing does.
func obstacle_top(x: int, y: int) -> float:
	if not inb(x, y):
		return 100.0
	var i := idx(x, y)
	var d := dyn_top[i]
	match tiles[i]:
		Defs.T.WALL, Defs.T.BOARDS, Defs.T.CELL_DOOR, Defs.T.RUBBLE, Defs.T.SEALED, Defs.T.GAP:
			return floor_h[i] + WALL_H
		Defs.T.CLIFF:
			return CLIFF_H
		Defs.T.PROP:
			return floor_h[i] + (1.45 if styles[i] == Defs.S.VEHICLE else 1.05)
		Defs.T.FENCE:
			return floor_h[i] + 1.05
	if d > 0.0:
		return floor_h[i] + d
	return -INF


## Line of sight between two points given as (2D position, absolute height).
func los(a: Vector2, ah: float, b: Vector2, bh: float) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 0.05:
		return true
	var steps := int(dist / (TILE * 0.25)) + 1
	var last := Vector2i(-99999, -99999)
	var ta := tile_of(a)
	var tb := tile_of(b)
	for i in range(1, steps):
		var f := float(i) / steps
		var p := a + d * f
		var tl := tile_of(p)
		if tl == last or tl == ta or tl == tb:
			continue
		last = tl
		var top := obstacle_top(tl.x, tl.y)
		if top == -INF:
			continue
		if top > lerpf(ah, bh, f):
			return false
	return true


## True when a circle of radius r can travel straight from a to b (used for path smoothing).
func clear_line(a: Vector2, b: Vector2, r: float, survivor: bool, solid_fn: Callable) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 0.01:
		return true
	var steps := int(dist / 0.5) + 1
	var n := d / dist
	var side := Vector2(-n.y, n.x) * r
	for i in range(0, steps + 1):
		var p := a + d * (float(i) / steps)
		for q in [p + side, p - side, p + n * r]:
			var tl := tile_of(q)
			if solid_fn.call(tl.x, tl.y, survivor):
				return false
	return true


func random_walkable_in_zone(rng: RandomNumberGenerator, z: int) -> Vector2i:
	var arr: Array = zone_tiles.get(z, [])
	if arr.is_empty():
		return Vector2i(-1, -1)
	return arr[rng.randi() % arr.size()]


func build_zone_index() -> void:
	zone_tiles.clear()
	for y in h:
		for x in w:
			var i := idx(x, y)
			if walkable_type(tiles[i], false):
				var z := int(zones[i])
				if not zone_tiles.has(z):
					zone_tiles[z] = []
				zone_tiles[z].append(Vector2i(x, y))


func zone_tiles_raw(z: int) -> Array:
	var out: Array = []
	for y in h:
		for x in w:
			var i := idx(x, y)
			if zones[i] == z and walkable_type(tiles[i], false):
				out.append(Vector2i(x, y))
	return out


func zone_at(p: Vector2) -> int:
	var tl := tile_of(p)
	return zone(tl.x, tl.y)


## Gap orientation: true when the passage runs along x (walls above and below).
func gap_along_x(x: int, y: int) -> bool:
	var up_solid := is_solid_static(x, y - 1) or t(x, y - 1) == Defs.T.GAP
	var dn_solid := is_solid_static(x, y + 1) or t(x, y + 1) == Defs.T.GAP
	return up_solid and dn_solid


func to_ascii() -> String:
	var s := ""
	for y in h:
		var line := ""
		for x in w:
			var c := "."
			match t(x, y):
				Defs.T.VOID: c = " "
				Defs.T.FLOOR:
					c = "."
					if roof[idx(x, y)] == Defs.R.CEILING: c = ","
					elif roof[idx(x, y)] == Defs.R.ROOF: c = "_"
					if floor_h[idx(x, y)] > 2.0: c = "^"
				Defs.T.WALL: c = "#"
				Defs.T.WATER: c = "~"
				Defs.T.GAP: c = "g"
				Defs.T.CLIFF: c = "C"
				Defs.T.RAMP: c = "/"
				Defs.T.BOARDS: c = "b"
				Defs.T.CELL_DOOR: c = "D"
				Defs.T.PROP: c = "o"
				Defs.T.FENCE: c = "f"
				Defs.T.TREE: c = "T"
				Defs.T.RUBBLE: c = "r"
				Defs.T.SEALED: c = "s"
			line += c
		s += line + "\n"
	return s
