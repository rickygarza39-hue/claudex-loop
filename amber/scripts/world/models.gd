class_name Models
extends RefCounted
## Model registry.
##
## Every model in the game is requested by slot name. If a file named
## res://assets/models/<slot>.glb (or .gltf / .obj) exists — for example one
## exported from Forge — it is used instead of the built-in placeholder, scaled to
## the slot's size. See assets/models/README.md for the slot list.

const MODEL_DIR := "res://assets/models/"

# slot -> [target size in metres (height unless noted), description]
const SLOTS := {
	"survivor": [1.75, "Survivor, feet at origin, facing -Z"],
	"killer_tracker": [1.95, "Tracker killer: lean, hunched, clawed"],
	"killer_brute": [2.55, "Brute killer: huge tank"],
	"killer_lurker": [2.2, "Lurker killer: tall, thin, long neck"],
	"elite": [1.8, "Elite infected (turned survivor)"],
	"husk": [1.6, "Swarm husk (AI infected)"],
	"station_antenna": [6.0, "Radio stage 1: antenna mast"],
	"station_generator": [1.3, "Radio stage 2: generator"],
	"station_transmitter": [1.6, "Radio stage 3: transmitter with dish"],
	"station_base": [1.0, "Radio station crate/table (before stage 1)"],
	"helicopter": [3.2, "Rescue helicopter (length about 11 m)"],
	"shop_terminal": [1.9, "Company supply terminal"],
	"part_cable": [0.5, "Cable spool"],
	"part_fuel": [0.5, "Fuel can"],
	"part_spark": [0.3, "Spark plug / battery"],
	"part_circuit": [0.15, "Circuit board"],
	"part_cell": [0.45, "Power cell"],
	"part_dish": [0.6, "Radio dish"],
	"cash": [0.3, "Cash lockbox"],
	"scrap": [0.45, "Scrap pile"],
	"flare_gun": [0.25, "Flare gun (knockdown item)"],
	"trap_snare": [0.2, "Snare trap"],
	"trap_flash": [0.3, "Flash trap"],
	"build_wall": [3.0, "Survivor-built wall section, 2 m wide"],
	"build_door": [3.0, "Survivor-built door, 2 m wide"],
	"build_barricade": [1.4, "Quick barricade"],
	"build_alarm": [1.2, "Alarm post"],
	"build_floodlight": [3.0, "Floodlight"],
	"build_decoy": [0.6, "Noise decoy"],
	"build_locker": [2.0, "Hiding locker"],
	"build_hatch": [1.2, "Escape hatch"],
	"drop_ledge": [1.1, "Drop-down ledge marker at a cliff edge: broken railing, faces -Z (the drop)"],
	"vehicle": [1.5, "Abandoned car or truck (length about 4 m)"],
	"telegraph_pole": [7.0, "Telegraph pole"],
	"lantern_post": [2.9, "Lantern on a post"],
	"wall_lantern": [0.4, "Wall-mounted lantern"],
	"mine_frame": [4.0, "Timber frame at a mine entrance"],
	"watchtower_top": [4.0, "Watchtower cabin on stilts"],
	"nest": [2.0, "The Nest: amber heart of the infection"],
	"crate": [1.0, "Wooden crate"],
}

static var _mesh_cache := {}
static var _file_cache := {}


static func has_external(slot: String) -> bool:
	return _find_file(slot) != ""


static func _find_file(slot: String) -> String:
	if _file_cache.has(slot):
		return _file_cache[slot]
	var found := ""
	for ext in [".glb", ".gltf", ".obj", ".tscn"]:
		var p: String = MODEL_DIR + slot + ext
		if ResourceLoader.exists(p):
			found = p
			break
	_file_cache[slot] = found
	return found


## Returns a new Node3D for the slot. `opts` can carry colours etc. for placeholders.
static func make(slot: String, opts: Dictionary = {}) -> Node3D:
	var path := _find_file(slot)
	if path != "":
		var ext := _load_external(path, slot)
		if ext != null:
			return ext
	return _placeholder(slot, opts)


static func _load_external(path: String, slot: String) -> Node3D:
	var res = load(path)
	var node: Node3D = null
	if res is PackedScene:
		node = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		node = mi
	if node == null:
		return null
	var holder := Node3D.new()
	holder.name = "External_" + slot
	holder.add_child(node)
	var aabb := _aabb_of(node, Transform3D.IDENTITY)
	if aabb.size.y > 0.001:
		var target: float = SLOTS.get(slot, [1.0, ""])[0]
		var s := target / aabb.size.y
		node.scale = Vector3.ONE * s
		var c := aabb.get_center() * s
		node.position = Vector3(-c.x, -aabb.position.y * s, -c.z)
	holder.set_meta("external", true)
	return holder


static func _aabb_of(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var a := t * (n as MeshInstance3D).mesh.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _aabb_of(c, t)
		if ca.size == Vector3.ZERO:
			continue
		if first:
			out = ca
			first = false
		else:
			out = out.merge(ca)
	return out


# ---- primitive helpers ---------------------------------------------------------

static func _mesh(key: String, maker: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = maker.call()
	return _mesh_cache[key]


static func box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("box%s" % size, func():
		var b := BoxMesh.new()
		b.size = size
		return b)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, segs: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("cyl%.3f_%.3f_%.3f_%d" % [r_top, r_bot, h, segs], func():
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bot
		c.height = h
		c.radial_segments = segs
		c.rings = 1
		return c)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("sph%.3f_%d" % [r, segs], func():
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = segs
		s.rings = maxi(4, segs / 2)
		return s)
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func capsule(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("cap%.3f_%.3f" % [r, h], func():
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = maxf(h, r * 2.0)
		c.radial_segments = 10
		c.rings = 3
		return c)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = name
	p.position = pos
	parent.add_child(p)
	return p


# ---- placeholders ----------------------------------------------------------------

static func _placeholder(slot: String, o: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = slot
	match slot:
		"survivor": CharacterModels.survivor(root, o)
		"killer_tracker": CharacterModels.tracker(root, o)
		"killer_brute": CharacterModels.brute(root, o)
		"killer_lurker": CharacterModels.lurker(root, o)
		"elite": CharacterModels.elite(root, o)
		"husk": CharacterModels.husk(root, o)
		"vehicle": _vehicle(root, o)
		"telegraph_pole": _pole(root)
		"lantern_post": _lantern_post(root)
		"wall_lantern": _wall_lantern(root)
		"mine_frame": _mine_frame(root)
		"watchtower_top": _watchtower_top(root)
		"crate":
			box(root, Vector3(1.0, 1.0, 1.0), Mats.get_mat("crate"), Vector3(0, 0.5, 0))
		_:
			# objects are defined in ObjectModels to keep this file manageable
			ObjectModels.build(slot, root, o)
	return root


static func _vehicle(root: Node3D, o: Dictionary) -> void:
	var rust := Mats.get_mat("rust")
	var dark := Mats.flat(Color(0.05, 0.05, 0.05))
	var glass := Mats.flat(Color(0.08, 0.1, 0.1), 0.0, 0.1, 0.3)
	box(root, Vector3(1.8, 0.75, 4.0), rust, Vector3(0, 0.65, 0))
	box(root, Vector3(1.6, 0.6, 1.9), rust, Vector3(0, 1.3, 0.2))
	box(root, Vector3(1.5, 0.5, 0.05), glass, Vector3(0, 1.32, -0.76), Vector3(0.35, 0, 0))
	for x in [-0.85, 0.85]:
		for z in [-1.3, 1.3]:
			cyl(root, 0.36, 0.36, 0.25, dark, Vector3(x, 0.36, z), Vector3(0, 0, PI * 0.5))
	box(root, Vector3(1.7, 0.18, 0.1), Mats.flat(Color(0.25, 0.25, 0.25), 0.0, 0.5, 0.6), Vector3(0, 0.55, -2.02))


static func _pole(root: Node3D) -> void:
	var wood := Mats.get_mat("bark")
	cyl(root, 0.13, 0.16, 7.0, wood, Vector3(0, 3.5, 0))
	box(root, Vector3(1.8, 0.12, 0.12), wood, Vector3(0, 6.4, 0))
	for x in [-0.75, 0.0, 0.75]:
		cyl(root, 0.04, 0.04, 0.12, Mats.flat(Color(0.5, 0.6, 0.55)), Vector3(x, 6.52, 0))


static func _lantern_post(root: Node3D) -> void:
	var wood := Mats.get_mat("bark")
	cyl(root, 0.06, 0.08, 2.6, wood, Vector3(0, 1.3, 0))
	box(root, Vector3(0.5, 0.06, 0.06), wood, Vector3(0.2, 2.55, 0))
	box(root, Vector3(0.16, 0.24, 0.16), Mats.get_mat("lamp"), Vector3(0.4, 2.38, 0))


static func _wall_lantern(root: Node3D) -> void:
	box(root, Vector3(0.05, 0.05, 0.3), Mats.flat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.1, 0.1))
	box(root, Vector3(0.15, 0.22, 0.15), Mats.get_mat("lamp"), Vector3(0, -0.05, 0.25))


static func _mine_frame(root: Node3D) -> void:
	var wood := Mats.get_mat("plank")
	for x in [-2.0, 2.0]:
		box(root, Vector3(0.3, 3.4, 0.3), wood, Vector3(x, 1.7, 0))
	box(root, Vector3(4.6, 0.35, 0.35), wood, Vector3(0, 3.35, 0))
	box(root, Vector3(1.4, 0.5, 0.06), Mats.flat(Color(0.5, 0.42, 0.25)), Vector3(0, 3.0, 0.2))


static func _watchtower_top(root: Node3D) -> void:
	var wood := Mats.get_mat("wood")
	var plank := Mats.get_mat("plank")
	for x in [-1.6, 1.6]:
		for z in [-1.6, 1.6]:
			box(root, Vector3(0.25, 5.0, 0.25), plank, Vector3(x, 6.1, z))
	box(root, Vector3(4.4, 0.25, 4.4), plank, Vector3(0, 3.75, 0))
	box(root, Vector3(4.0, 0.2, 4.0), plank, Vector3(0, 7.1, 0))
	for side in 4:
		var a := side * PI * 0.5
		box(root, Vector3(4.0, 1.0, 0.12), wood, Vector3(sin(a) * 2.0, 7.7, cos(a) * 2.0), Vector3(0, a, 0))
	box(root, Vector3(4.8, 0.25, 4.8), Mats.get_mat("roof"), Vector3(0, 8.8, 0))
	box(root, Vector3(3.0, 0.2, 3.0), Mats.get_mat("roof"), Vector3(0, 9.05, 0))
