class_name WorldView
extends Node3D
## Builds the 3D world from MapData: chunked static meshes, dynamic tiles
## (doors, boards, gaps), lights, fog, amber crystals and decor.

const CHUNK := 8
const T := Defs.TILE

var m: MapData
var dyn_nodes := {}        # Vector2i -> Node3D
var light_list: Array = [] # {node, kind, base, phase}
var env: Environment
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var blackout := 0.0        # 0..1 blend for the Blackout event
var _time := 0.0
var _prim := {}            # primitive meshes for props


func build(map: MapData) -> void:
	m = map
	_environment()
	_prims()
	var cw := int(ceil(m.w / float(CHUNK)))
	var ch := int(ceil(m.h / float(CHUNK)))
	for cy in ch:
		for cx in cw:
			_build_chunk(cx, cy)
	for y in m.h:
		for x in m.w:
			var tt := m.t(x, y)
			if tt == Defs.T.GAP or tt == Defs.T.BOARDS or tt == Defs.T.CELL_DOOR:
				update_tile(Vector2i(x, y))
	_lights()
	_amber()
	_decor()
	_place_scan_props()
	_clutter()


# ------------------------------------------------------------------------------
# Environment

func _environment() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.42)
	env.ambient_light_energy = 0.11
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.12, 0.11)
	env.fog_light_energy = 1.0
	env.fog_density = 0.045
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.035
		env.volumetric_fog_albedo = Color(0.55, 0.6, 0.55)
		env.fog_density = 0.02
	world_env.environment = env
	add_child(world_env)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.8)
	moon.light_energy = 0.22
	moon.rotation = Vector3(deg_to_rad(-58), deg_to_rad(35), 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(moon)


func set_blackout(v: float) -> void:
	blackout = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var dim := 1.0 - blackout * 0.92
	moon.light_energy = 0.22 * (1.0 - blackout * 0.8)
	env.ambient_light_energy = 0.11 * (1.0 - blackout * 0.7)
	for l in light_list:
		var node: OmniLight3D = l["node"]
		var base: float = l["base"]
		var ph: float = l["phase"]
		match l["kind"]:
			"lantern", "mine", "tower", "cell":
				var f := 0.82 + 0.18 * sin(_time * 7.3 + ph) * sin(_time * 3.1 + ph * 2.0)
				if fmod(_time + ph, 9.0) < 0.12:
					f *= 0.25
				node.light_energy = base * f * dim
			"emergency":
				node.light_energy = base * (0.55 + 0.45 * absf(sin(_time * 1.6 + ph))) * maxf(dim, 0.35)
			"amber", "nest":
				node.light_energy = base * (0.85 + 0.15 * sin(_time * 1.2 + ph))
			_:
				node.light_energy = base * dim


# ------------------------------------------------------------------------------
# Geometry helpers

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	# Godot front faces are clockwise; flip winding if needed.
	var cr := (b - a).cross(c - a)
	if cr.dot(n) > 0.0:
		var tmp := b
		b = d
		d = tmp
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)


func _tool(tools: Dictionary, key: String) -> SurfaceTool:
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
	return tools[key]


func _box(st: SurfaceTool, mn: Vector3, mx: Vector3, faces: int = 63) -> void:
	# faces bitmask: 1 +X, 2 -X, 4 +Y, 8 -Y, 16 +Z, 32 -Z
	if faces & 1:
		_quad(st, Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3.RIGHT)
	if faces & 2:
		_quad(st, Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mx.y, mn.z), Vector3.LEFT)
	if faces & 4:
		_quad(st, Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3.UP)
	if faces & 8:
		_quad(st, Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z), Vector3.DOWN)
	if faces & 16:
		_quad(st, Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3.BACK)
	if faces & 32:
		_quad(st, Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3.FORWARD)


func _prims() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.26
	trunk.height = 1.0
	trunk.radial_segments = 7
	trunk.rings = 1
	_prim["trunk"] = trunk
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	_prim["cone"] = cone
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 7
	rock.rings = 4
	_prim["rock"] = rock
	var bx := BoxMesh.new()
	bx.size = Vector3.ONE
	_prim["box"] = bx


func _append(tools: Dictionary, key: String, mesh_key: String, xf: Transform3D) -> void:
	var st := _tool(tools, key + "#p")
	st.append_from(_prim[mesh_key], 0, xf)


# ------------------------------------------------------------------------------
# Tile classification

func _is_dynamic(tt: int) -> bool:
	return tt == Defs.T.GAP or tt == Defs.T.BOARDS or tt == Defs.T.CELL_DOOR or tt == Defs.T.RUBBLE or tt == Defs.T.SEALED


func _underground(x: int, y: int) -> bool:
	var z := m.zone(x, y)
	return z == Defs.Z.MINE or z == Defs.Z.LAB


func _wall_top(x: int, y: int) -> float:
	## Absolute top height of a static wall-like tile (or -INF if not wall-like).
	if not m.inb(x, y):
		return 50.0
	var tt := m.t(x, y)
	var i := m.idx(x, y)
	var base := m.floor_h[i]
	match tt:
		Defs.T.WALL:
			var st := m.styles[i]
			if st == Defs.S.CLIFF:
				return 9.0
			if _underground(x, y):
				return 6.5 if _outdoor_neighbor(x, y) else MapData.CEILING_H
			return base + MapData.WALL_H
		Defs.T.CLIFF:
			return MapData.CLIFF_H
	return -INF


func _outdoor_neighbor(x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if m.inb(nx, ny) and not _underground(nx, ny):
			return true
	return false


func _occludes(x: int, y: int, top: float, base: float) -> bool:
	## True when the neighbour tile fully hides a face between base and top.
	if not m.inb(x, y):
		return true
	var tt := m.t(x, y)
	if _is_dynamic(tt):
		return false
	var nt := _wall_top(x, y)
	if nt == -INF:
		return false
	var nb := m.tile_height(Vector2i(x, y)) if tt == Defs.T.WALL else 0.0
	return nt >= top - 0.01 and nb <= base + 0.01


# ------------------------------------------------------------------------------
# Chunk building

func _build_chunk(cx: int, cy: int) -> void:
	var tools := {}
	var x0 := cx * CHUNK
	var y0 := cy * CHUNK
	for y in range(y0, mini(y0 + CHUNK, m.h)):
		for x in range(x0, mini(x0 + CHUNK, m.w)):
			_emit_tile(tools, x, y)
	if tools.is_empty():
		return
	var mesh := ArrayMesh.new()
	for key in tools:
		var st: SurfaceTool = tools[key]
		st.commit(mesh)
		var mat_key: String = key.split("#")[0]
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.get_mat(mat_key))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Chunk_%d_%d" % [cx, cy]
	mi.visibility_range_end = 95.0
	add_child(mi)


func _emit_tile(tools: Dictionary, x: int, y: int) -> void:
	var i := m.idx(x, y)
	var tt := m.tiles[i]
	var st := m.styles[i]
	var x0 := x * T
	var z0 := y * T
	var x1 := x0 + T
	var z1 := z0 + T
	var fh := m.floor_h[i]
	var under := _underground(x, y)
	var rf := m.roof[i]

	# ---- floors
	var has_floor := tt != Defs.T.WALL and tt != Defs.T.CLIFF and tt != Defs.T.VOID
	if has_floor:
		var fkey := Mats.floor_key(st)
		if tt == Defs.T.RAMP:
			var h00 := m.height_at(Vector2(x0 + 0.001, z0 + 0.001))
			var h10 := m.height_at(Vector2(x1 - 0.001, z0 + 0.001))
			var h11 := m.height_at(Vector2(x1 - 0.001, z1 - 0.001))
			var h01 := m.height_at(Vector2(x0 + 0.001, z1 - 0.001))
			var a := Vector3(x0, h00, z0)
			var b := Vector3(x1, h10, z0)
			var c := Vector3(x1, h11, z1)
			var d := Vector3(x0, h01, z1)
			var n := (c - a).cross(b - d).normalized()
			if n.y < 0:
				n = -n
			_quad(_tool(tools, "plateau"), a, b, c, d, n)
		elif tt == Defs.T.WATER:
			var wy := fh - 0.45
			_quad(_tool(tools, "mud" if not under else "minefloor"), Vector3(x0, wy, z0), Vector3(x1, wy, z0), Vector3(x1, wy, z1), Vector3(x0, wy, z1), Vector3.UP)
			_quad(_tool(tools, "water"), Vector3(x0, fh - 0.12, z0), Vector3(x1, fh - 0.12, z0), Vector3(x1, fh - 0.12, z1), Vector3(x0, fh - 0.12, z1), Vector3.UP)
			# banks: vertical faces where water meets dry floor
			for d in [[Vector2i(1, 0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3.LEFT], [Vector2i(-1, 0), Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3.RIGHT], [Vector2i(0, 1), Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.FORWARD], [Vector2i(0, -1), Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3.BACK]]:
				var nt := m.t(x + d[0].x, y + d[0].y)
				if nt != Defs.T.WATER:
					var p0: Vector3 = d[1]
					var p1: Vector3 = d[2]
					_quad(_tool(tools, "mud" if not under else "minefloor"), Vector3(p0.x, wy, p0.z), Vector3(p1.x, wy, p1.z), Vector3(p1.x, fh, p1.z), Vector3(p0.x, fh, p0.z), d[3])
		else:
			_quad(_tool(tools, fkey), Vector3(x0, fh, z0), Vector3(x1, fh, z0), Vector3(x1, fh, z1), Vector3(x0, fh, z1), Vector3.UP)

	# ---- walls and cliffs
	if tt == Defs.T.WALL or tt == Defs.T.CLIFF:
		var top := _wall_top(x, y)
		var base := fh if tt == Defs.T.WALL else 0.0
		if tt == Defs.T.WALL and st == Defs.S.CLIFF:
			base = -0.5
		var key := Mats.wall_key(st) if tt == Defs.T.WALL else "cliff"
		if tt == Defs.T.WALL and under:
			key = "lab_wall" if st == Defs.S.LAB else "rock"
		var faces := 0
		if not _occludes(x + 1, y, top, base): faces |= 1
		if not _occludes(x - 1, y, top, base): faces |= 2
		if not _occludes(x, y + 1, top, base): faces |= 16
		if not _occludes(x, y - 1, top, base): faces |= 32
		var show_top := rf == Defs.R.NONE or st == Defs.S.CLIFF or tt == Defs.T.CLIFF or (under and top > 5.0)
		if show_top:
			faces |= 4
		if faces != 0:
			# lab walls: panels up to 2.4 m, rock above
			_box(_tool(tools, key), Vector3(x0, base, z0), Vector3(x1, top, z1), faces)

	# ---- props
	match tt:
		Defs.T.PROP:
			var c := Vector3(x0 + 1.0, fh, z0 + 1.0)
			var r := float((x * 7 + y * 13) % 10) / 10.0 * TAU
			var variants: Array = Models.CRATE_VARIANTS if st == Defs.S.CRATE else (Models.BOULDER_VARIANTS if st == Defs.S.BOULDER else [])
			var pick: String = variants[(x * 7 + y * 13) % variants.size()] if not variants.is_empty() else ""
			if pick != "" and Models.has_external(pick):
				_scan_props.append([pick, c, r, st == Defs.S.BOULDER])
			elif st == Defs.S.CRATE:
				var s := 0.95 + 0.15 * float((x * 3 + y) % 3)
				_box(_tool(tools, "crate"), c + Vector3(-s * 0.5, 0, -s * 0.5), c + Vector3(s * 0.5, s, s * 0.5))
				if (x + y) % 3 == 0:
					_box(_tool(tools, "crate"), c + Vector3(-0.3, s, -0.3), c + Vector3(0.3, s + 0.6, 0.3))
			elif st == Defs.S.BOULDER:
				var xf := Transform3D(Basis(Vector3.UP, r).scaled(Vector3(1.7, 1.2, 1.5)), c + Vector3(0, 0.45, 0))
				_append(tools, "rock", "rock", xf)
		Defs.T.TREE:
			var c2 := Vector3(x0 + 1.0, fh, z0 + 1.0)
			var hgt := 5.0 + float((x * 31 + y * 17) % 5)
			var dead := m.zone(x, y) == Defs.Z.SWAMP
			_append(tools, "bark", "trunk", Transform3D(Basis().scaled(Vector3(1, hgt, 1)), c2 + Vector3(0, hgt * 0.5, 0)))
			if dead:
				for k in 3:
					var a := float(k) * 2.1 + float(x)
					var br := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.9)
					_append(tools, "bark", "trunk", Transform3D(br.scaled(Vector3(0.35, 2.2, 0.35)), c2 + Vector3(sin(a) * 0.6, hgt * (0.55 + k * 0.12), cos(a) * 0.6)))
			else:
				for k in 3:
					var s2 := 2.0 - k * 0.55
					_append(tools, "foliage", "cone", Transform3D(Basis().scaled(Vector3(s2, 2.4, s2)), c2 + Vector3(0, hgt * 0.45 + k * 1.3, 0)))
		Defs.T.FENCE:
			var along_x := m.t(x + 1, y) == Defs.T.FENCE or m.t(x - 1, y) == Defs.T.FENCE
			var cf := Vector3(x0 + 1.0, fh, z0 + 1.0)
			if along_x:
				_box(_tool(tools, "plank"), cf + Vector3(-1.0, 0.35, -0.04), cf + Vector3(1.0, 0.5, 0.04))
				_box(_tool(tools, "plank"), cf + Vector3(-1.0, 0.8, -0.04), cf + Vector3(1.0, 0.95, 0.04))
				_box(_tool(tools, "plank"), cf + Vector3(-0.08, 0, -0.08), cf + Vector3(0.08, 1.1, 0.08))
			else:
				_box(_tool(tools, "plank"), cf + Vector3(-0.04, 0.35, -1.0), cf + Vector3(0.04, 0.5, 1.0))
				_box(_tool(tools, "plank"), cf + Vector3(-0.04, 0.8, -1.0), cf + Vector3(0.04, 0.95, 1.0))
				_box(_tool(tools, "plank"), cf + Vector3(-0.08, 0, -0.08), cf + Vector3(0.08, 1.1, 0.08))

	# ---- ceilings and roofs
	if rf == Defs.R.CEILING and has_floor:
		var cy_ := fh + MapData.CEILING_H
		_quad(_tool(tools, "ceiling"), Vector3(x0, cy_, z0), Vector3(x1, cy_, z0), Vector3(x1, cy_, z1), Vector3(x0, cy_, z1), Vector3.DOWN)
		# rock lintel above openings to the outside
		for d in [[Vector2i(1, 0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3.RIGHT], [Vector2i(-1, 0), Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3.LEFT], [Vector2i(0, 1), Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.BACK], [Vector2i(0, -1), Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3.FORWARD]]:
			var nx: int = x + d[0].x
			var ny: int = y + d[0].y
			if m.inb(nx, ny) and m.roof[m.idx(nx, ny)] == Defs.R.NONE and m.walkable(nx, ny, true):
				var p0: Vector3 = d[1]
				var p1: Vector3 = d[2]
				_quad(_tool(tools, "rock"), Vector3(p0.x, cy_, p0.z), Vector3(p1.x, cy_, p1.z), Vector3(p1.x, 6.5, p1.z), Vector3(p0.x, 6.5, p0.z), d[3])
	if under and (has_floor or tt == Defs.T.WALL):
		# the hill above the mines, seen from outside
		_quad(_tool(tools, "rock"), Vector3(x0, 6.5, z0), Vector3(x1, 6.5, z0), Vector3(x1, 6.5, z1), Vector3(x0, 6.5, z1), Vector3.UP)
	if rf == Defs.R.ROOF:
		var top_y := fh + MapData.ROOF_H
		if has_floor:
			_quad(_tool(tools, "plank"), Vector3(x0, top_y, z0), Vector3(x1, top_y, z0), Vector3(x1, top_y, z1), Vector3(x0, top_y, z1), Vector3.DOWN)
		_quad(_tool(tools, "roof"), Vector3(x0, top_y + 0.15, z0), Vector3(x1, top_y + 0.15, z0), Vector3(x1, top_y + 0.15, z1), Vector3(x0, top_y + 0.15, z1), Vector3.UP)
		for d in [[Vector2i(1, 0), 1], [Vector2i(-1, 0), 2], [Vector2i(0, 1), 16], [Vector2i(0, -1), 32]]:
			var nx: int = x + d[0].x
			var ny: int = y + d[0].y
			if m.inb(nx, ny) and m.roof[m.idx(nx, ny)] != Defs.R.ROOF:
				_box(_tool(tools, "roof"), Vector3(x0, top_y, z0), Vector3(x1, top_y + 0.15, z1), d[1])


# ------------------------------------------------------------------------------
# Dynamic tiles: gaps, boarded passages, cell doors, rubble

func update_tile(p: Vector2i) -> void:
	if dyn_nodes.has(p):
		dyn_nodes[p].queue_free()
		dyn_nodes.erase(p)
	var tt := m.tv(p)
	if not _is_dynamic(tt) and tt != Defs.T.FLOOR:
		return
	var i := m.idx(p.x, p.y)
	var st := m.styles[i]
	var fh := m.floor_h[i]
	var under := _underground(p.x, p.y)
	var top := fh + (MapData.CEILING_H if under else MapData.WALL_H)
	var key := Mats.wall_key(st)
	if under:
		key = "lab_wall" if st == Defs.S.LAB else "rock"
	var node := Node3D.new()
	node.position = Vector3(p.x * T + 1.0, fh, p.y * T + 1.0)
	var along_x := m.gap_along_x(p.x, p.y)
	var h := top - fh
	var mat := Mats.get_mat(key)
	match tt:
		Defs.T.GAP:
			# a narrow crack: pillars either side and a lintel above a 1 m x 1.6 m hole
			var tools := {}
			var s := _tool(tools, key)
			if along_x:
				_box(s, Vector3(-1, 0, -1), Vector3(1, h, -0.5))
				_box(s, Vector3(-1, 0, 0.5), Vector3(1, h, 1))
				_box(s, Vector3(-1, 1.6, -0.5), Vector3(1, h, 0.5))
			else:
				_box(s, Vector3(-1, 0, -1), Vector3(-0.5, h, 1))
				_box(s, Vector3(0.5, 0, -1), Vector3(1, h, 1))
				_box(s, Vector3(-0.5, 1.6, -1), Vector3(0.5, h, 1))
			node.add_child(_commit(tools))
			if st == Defs.S.WOOD or st == Defs.S.PLANK:
				# broken boards hanging in the hole
				Models.box(node, Vector3(0.9, 0.12, 0.05) if along_x else Vector3(0.05, 0.12, 0.9), Mats.get_mat("boards"), Vector3(0, 1.35, 0), Vector3(0, 0, 0.5) if along_x else Vector3(0.5, 0, 0))
		Defs.T.BOARDS, Defs.T.CELL_DOOR:
			var tools2 := {}
			var s2 := _tool(tools2, key)
			var horiz := m.is_solid_static(p.x - 1, p.y) and m.is_solid_static(p.x + 1, p.y)
			if horiz:
				_box(s2, Vector3(-1, 0, -1), Vector3(-0.7, h, 1))
				_box(s2, Vector3(0.7, 0, -1), Vector3(1, h, 1))
				_box(s2, Vector3(-0.7, 2.4, -1), Vector3(0.7, h, 1))
			else:
				_box(s2, Vector3(-1, 0, -1), Vector3(1, h, -0.7))
				_box(s2, Vector3(-1, 0, 0.7), Vector3(1, h, 1))
				_box(s2, Vector3(-1, 2.4, -0.7), Vector3(1, h, 0.7))
			node.add_child(_commit(tools2))
			var fill := Node3D.new()
			fill.name = "Fill"
			node.add_child(fill)
			if tt == Defs.T.BOARDS:
				var bm := Mats.get_mat("boards")
				for k in 4:
					var yy := 0.35 + k * 0.55
					Models.box(fill, Vector3(1.5, 0.3, 0.08) if horiz else Vector3(0.08, 0.3, 1.5), bm, Vector3(0, yy, 0), Vector3(0, 0, 0.1 * (k - 1.5)) if horiz else Vector3(0.1 * (k - 1.5), 0, 0))
			else:
				var bars := Mats.flat(Color(0.25, 0.27, 0.28), 0.0, 0.4, 0.8)
				Models.box(fill, Vector3(1.4, 0.1, 0.1) if horiz else Vector3(0.1, 0.1, 1.4), bars, Vector3(0, 2.3, 0))
				Models.box(fill, Vector3(1.4, 0.1, 0.1) if horiz else Vector3(0.1, 0.1, 1.4), bars, Vector3(0, 0.1, 0))
				Models.box(fill, Vector3(1.4, 0.08, 0.08) if horiz else Vector3(0.08, 0.08, 1.4), bars, Vector3(0, 1.2, 0))
				for k in 7:
					var off := -0.6 + k * 0.2
					Models.box(fill, Vector3(0.05, 2.3, 0.05), bars, Vector3(off, 1.2, 0) if horiz else Vector3(0, 1.2, off))
		Defs.T.RUBBLE:
			var rock := Mats.get_mat("rock")
			for k in 6:
				var a := k * 1.7
				Models.sphere(node, 0.7, rock, Vector3(sin(a) * 0.5, 0.4 + (k % 3) * 0.7, cos(a) * 0.5), Vector3(1.3, 0.9, 1.1), 7)
		Defs.T.SEALED:
			var tools3 := {}
			_box(_tool(tools3, key), Vector3(-1, 0, -1), Vector3(1, h, 1))
			node.add_child(_commit(tools3))
			Models.box(node, Vector3(1.2, 1.8, 2.05) if along_x else Vector3(2.05, 1.8, 1.2), Mats.get_mat("amber_dim"), Vector3(0, 0.9, 0))
		Defs.T.FLOOR:
			# an opened boarded passage keeps its frame
			if st == Defs.S.PLANK or st == Defs.S.QUARANTINE:
				pass
	add_child(node)
	dyn_nodes[p] = node


func _commit(tools: Dictionary) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key in tools:
		var st: SurfaceTool = tools[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.get_mat(key.split("#")[0]))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


## Opens a boarded passage or cell door visually (the tile becomes floor).
func open_tile(p: Vector2i) -> void:
	if dyn_nodes.has(p):
		var fill: Node = dyn_nodes[p].get_node_or_null("Fill")
		if fill:
			fill.queue_free()


# ------------------------------------------------------------------------------
# Lights, amber, decor

func _lights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = m.seed + 5
	for l in m.lights:
		var o := OmniLight3D.new()
		o.position = l["pos"]
		var kind: String = l["kind"]
		var base := 1.0
		match kind:
			"lantern":
				o.light_color = Color(1.0, 0.72, 0.42)
				o.omni_range = 9.0
				base = 1.6
			"mine":
				o.light_color = Color(1.0, 0.65, 0.35)
				o.omni_range = 7.0
				base = 1.1
			"tower":
				o.light_color = Color(1.0, 0.8, 0.5)
				o.omni_range = 12.0
				base = 1.6
			"emergency":
				o.light_color = Color(1.0, 0.12, 0.08)
				o.omni_range = 8.0
				base = 1.5
			"amber":
				o.light_color = Defs.AMBER
				o.omni_range = 6.5
				base = 1.4
			"nest":
				o.light_color = Defs.AMBER
				o.omni_range = 14.0
				base = 3.0
			"cell":
				o.light_color = Color(0.75, 0.85, 1.0)
				o.omni_range = 5.0
				base = 0.7
		o.omni_attenuation = 1.4
		o.light_energy = base
		o.shadow_enabled = false
		add_child(o)
		light_list.append({"node": o, "kind": kind, "base": base, "phase": rng.randf() * TAU})


func _amber() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var shard := PrismMesh.new()
	shard.size = Vector3(0.35, 1.0, 0.35)
	mm.mesh = shard
	var rng := RandomNumberGenerator.new()
	rng.seed = m.seed + 9
	var xfs: Array = []
	for p in m.amber:
		var count := rng.randi_range(5, 9)
		for k in count:
			var off := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
			var s := rng.randf_range(0.4, 1.4)
			var b := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.7))
			b = b.scaled(Vector3(s * 0.8, s * rng.randf_range(1.0, 2.0), s * 0.8))
			xfs.append(Transform3D(b, p + off + Vector3(0, s * 0.4, 0)))
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Mats.get_mat("amber")
	mmi.name = "Amber"
	add_child(mmi)


var _scan_props: Array = []   # [slot, position, yaw, is_boulder] from prop tiles


## Prop tiles get a scanned crate, barrel or boulder when the model file exists.
func _place_scan_props() -> void:
	for sp in _scan_props:
		var n := Models.make(sp[0])
		n.position = sp[1]
		n.rotation.y = sp[2]
		if sp[3]:
			n.scale = Vector3.ONE * (1.0 + fmod(sp[2], 0.6))
		add_child(n)
	_scan_props.clear()


## Small props against walls, chosen per zone. Visual only: nothing here blocks movement.
func _clutter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = m.seed * 17 + 5
	var placed := 0
	for y in range(1, m.h - 1):
		for x in range(1, m.w - 1):
			if placed >= 220 or m.t(x, y) != Defs.T.FLOOR or rng.randf() > 0.06:
				continue
			var zone := m.zone(x, y)
			if not Models.CLUTTER.has(zone):
				continue
			var wall := Vector2i.ZERO
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if m.t(x + d.x, y + d.y) == Defs.T.WALL:
					wall = d
					break
			if wall == Vector2i.ZERO:
				continue
			var opts: Array = Models.CLUTTER[zone]
			var slot: String = opts[rng.randi() % opts.size()]
			if not Models.has_external(slot):
				continue
			var c := MapData.center_of(Vector2i(x, y)) + Vector2(wall) * 0.6 + Vector2(-wall.y, wall.x) * rng.randf_range(-0.5, 0.5)
			var n := Models.make(slot)
			n.position = Vector3(c.x, m.tile_height(Vector2i(x, y)), c.y)
			n.rotation.y = Actor.yaw_of(-Vector2(wall)) + rng.randf_range(-0.4, 0.4)
			add_child(n)
			placed += 1


func _decor() -> void:
	for d in m.decor:
		var slot := ""
		match d["kind"]:
			"vehicle": slot = "vehicle"
			"pole": slot = "telegraph_pole"
			"lantern_post": slot = "lantern_post"
			"wall_lantern": slot = "wall_lantern"
			"mine_frame": slot = "mine_frame"
			"watchtower": slot = "watchtower_top"
		if slot == "":
			continue
		var n := Models.make(slot)
		n.position = d["pos"]
		n.rotation.y = d["rot"]
		add_child(n)
