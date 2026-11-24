class_name Nav
extends RefCounted
## A* pathfinding on the tile grid. Survivors can use squeeze gaps; killers can't.
## A third grid ignores survivor-built structures so killers can plan sieges.

var m: MapData
var grid_s := AStarGrid2D.new()
var grid_k := AStarGrid2D.new()
var grid_ks := AStarGrid2D.new()
var struct_tiles := {}  # Vector2i -> {"s": bool, "k": bool}


func _init(map: MapData) -> void:
	m = map
	for g in [grid_s, grid_k, grid_ks]:
		g.region = Rect2i(0, 0, m.w, m.h)
		g.cell_size = Vector2(1, 1)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
	for y in m.h:
		for x in m.w:
			refresh_tile(Vector2i(x, y))


func refresh_tile(p: Vector2i) -> void:
	var tt := m.tv(p)
	var ws := MapData.walkable_type(tt, true)
	var wk := MapData.walkable_type(tt, false)
	var st: Dictionary = struct_tiles.get(p, {})
	grid_s.set_point_solid(p, not ws or st.get("s", false))
	grid_k.set_point_solid(p, not wk or st.get("k", false))
	grid_ks.set_point_solid(p, not wk)
	var w := 1.0
	if tt == Defs.T.WATER:
		w = 1.7
	grid_s.set_point_weight_scale(p, 2.2 if tt == Defs.T.GAP else w)
	grid_k.set_point_weight_scale(p, w)
	grid_ks.set_point_weight_scale(p, 6.0 if st.get("k", false) else w)


func set_struct(p: Vector2i, blocks_survivors: bool, blocks_killers: bool) -> void:
	if not blocks_survivors and not blocks_killers:
		struct_tiles.erase(p)
	else:
		struct_tiles[p] = {"s": blocks_survivors, "k": blocks_killers}
	refresh_tile(p)


func _grid(survivor: bool, siege: bool) -> AStarGrid2D:
	if survivor:
		return grid_s
	return grid_ks if siege else grid_k


func is_open(p: Vector2i, survivor: bool, siege: bool = false) -> bool:
	if not m.inb(p.x, p.y):
		return false
	return not _grid(survivor, siege).is_point_solid(p)


## Nearest open tile to p (spiral search).
func snap(p: Vector2i, survivor: bool, siege: bool = false, max_r: int = 6) -> Vector2i:
	if is_open(p, survivor, siege):
		return p
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if is_open(q, survivor, siege):
					return q
	return Vector2i(-1, -1)


## World-space path (tile centres) from a to b. Empty when unreachable.
func path(a: Vector2, b: Vector2, survivor: bool, siege: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var g := _grid(survivor, siege)
	var ta := snap(MapData.tile_of(a), survivor, siege)
	var tb := snap(MapData.tile_of(b), survivor, siege)
	if ta.x < 0 or tb.x < 0:
		return out
	var ids := g.get_id_path(ta, tb, true)
	for i in ids.size():
		out.append(MapData.center_of(ids[i]))
	if out.size() > 0 and tb == MapData.tile_of(b):
		out[out.size() - 1] = b
	return out


func path_length(a: Vector2, b: Vector2, survivor: bool) -> float:
	var p := path(a, b, survivor)
	if p.is_empty():
		return INF
	var d := a.distance_to(p[0])
	for i in range(1, p.size()):
		d += p[i - 1].distance_to(p[i])
	return d


func reachable(a: Vector2, b: Vector2, survivor: bool) -> bool:
	var p := path(a, b, survivor)
	return not p.is_empty() and p[p.size() - 1].distance_to(b) < Defs.TILE * 1.5
