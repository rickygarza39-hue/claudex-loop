extends SceneTree
## Renders screenshots of a generated map from several viewpoints.
## xvfb-run godot --path . --rendering-driver opengl3 --script res://scripts/tests/view_test.gd -- --seed=2 --out=/tmp/shots

var m: MapData
var view: WorldView
var cam: Camera3D
var flash: SpotLight3D
var shots: Array = []
var frame := 0
var shot_i := 0
var wait := 0
var out_dir := "/tmp"
var root3d: Node3D


func _initialize() -> void:
	var seed_v := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	m = MapGen.new().generate(seed_v)
	root3d = Node3D.new()
	root.add_child(root3d)
	view = WorldView.new()
	root3d.add_child(view)
	view.build(m)
	cam = Camera3D.new()
	cam.fov = 75
	cam.near = 0.05
	cam.far = 130
	root3d.add_child(cam)
	flash = SpotLight3D.new()
	flash.spot_range = 24
	flash.spot_angle = 30
	flash.light_energy = 2.2
	flash.light_color = Color(1.0, 0.95, 0.85)
	flash.shadow_enabled = true
	cam.add_child(flash)
	_plan()


func _eye(tile: Vector2i, look: Vector2, h: float = 1.6) -> Dictionary:
	var p := MapData.center_of(tile)
	var y := m.height_at(p) + h
	return {"pos": Vector3(p.x, y, p.y), "target": Vector3(p.x + look.x, y - 0.15, p.y + look.y)}


func _plan() -> void:
	# town: stand two tiles from a lantern, look toward it
	for l in m.lights:
		if l["kind"] == "lantern" and m.zone_at(Vector2(l["pos"].x, l["pos"].z)) == Defs.Z.TOWN:
			var lp := Vector2(l["pos"].x, l["pos"].z)
			var best := Vector2i(-1, -1)
			for d in [Vector2(9, 0), Vector2(-9, 0), Vector2(0, 9), Vector2(0, -9), Vector2(7, 7), Vector2(-7, -7)]:
				var tl := MapData.tile_of(lp + d)
				if m.walkable(tl.x, tl.y, false) and m.roof[m.idx(tl.x, tl.y)] == Defs.R.NONE:
					best = tl
					break
			if best.x >= 0:
				var e := _eye(best, (lp - MapData.center_of(best)))
				e["name"] = "town"
				shots.append(e)
				break
	# mine entrance from outside, then inside
	if m.mine_entrances.size() > 0:
		var en: Dictionary = m.mine_entrances[0]
		var t0: Vector2i = en["tile"]
		var d: Vector2i = en["dir"]
		var outside := t0 + d * 6
		var e2 := _eye(outside, Vector2(-d) * 10.0)
		e2["name"] = "mine_entrance"
		shots.append(e2)
		var inside := t0 - d * 3
		if m.walkable(inside.x, inside.y, false):
			var e3 := _eye(inside, Vector2(-d) * 10.0)
			e3["name"] = "mine_inside"
			shots.append(e3)
	# lab near the nest
	var nest_c := MapData.center_of(m.nest)
	var lab_tl := MapData.tile_of(nest_c + Vector2(-5, -5))
	var e4 := _eye(lab_tl, nest_c - MapData.center_of(lab_tl))
	e4["name"] = "nest"
	shots.append(e4)
	# a lab room (emergency light)
	for l in m.lights:
		if l["kind"] == "emergency":
			var lp2 := Vector2(l["pos"].x, l["pos"].z)
			var tl2 := MapData.tile_of(lp2 + Vector2(-3, -3))
			if m.walkable(tl2.x, tl2.y, false):
				var e5 := _eye(tl2, lp2 - MapData.center_of(tl2))
				e5["name"] = "lab_room"
				shots.append(e5)
				break
	# watchtower / plateau
	for dd in m.decor:
		if dd["kind"] == "watchtower":
			var wp := Vector2(dd["pos"].x, dd["pos"].z)
			for off in [Vector2(12, 8), Vector2(-12, 8), Vector2(12, -8), Vector2(-12, -8), Vector2(0, 14), Vector2(14, 0)]:
				var tl3 := MapData.tile_of(wp + off)
				if m.walkable(tl3.x, tl3.y, false):
					var e6 := _eye(tl3, wp - MapData.center_of(tl3))
					e6["target"].y += 2.5
					e6["name"] = "watchtower"
					shots.append(e6)
					break
	# ramp
	for y in m.h:
		var found := false
		for x in m.w:
			if m.t(x, y) == Defs.T.RAMP and m.floor_h[m.idx(x, y)] < 1.0:
				var rd := m.ramp_dir[m.idx(x, y)]
				var up := Vector2(1, 0)
				match rd:
					2: up = Vector2(-1, 0)
					3: up = Vector2(0, 1)
					4: up = Vector2(0, -1)
				var stand := MapData.tile_of(MapData.center_of(Vector2i(x, y)) - up * 6.0)
				if m.walkable(stand.x, stand.y, false):
					var e7 := _eye(stand, up * 10.0)
					e7["target"].y += 2.0
					e7["name"] = "ramp"
					shots.append(e7)
					found = true
					break
		if found:
			break
	# swamp
	var sw: Array = m.zone_tiles.get(Defs.Z.SWAMP, [])
	if sw.size() > 0:
		var tl4: Vector2i = sw[sw.size() / 2]
		var e8 := _eye(tl4, Vector2(8, 5))
		e8["name"] = "swamp"
		shots.append(e8)
	# quarantine cell from outside
	if m.cells.size() > 0:
		var c: Dictionary = m.cells[0]
		var door: Vector2i = c["door"]
		var dirc: Vector2i = c["dir"]
		var st := door + dirc * 3
		var e9 := _eye(st, Vector2(-dirc) * 6.0)
		e9["name"] = "cell"
		shots.append(e9)
	# overhead
	var mid := Vector2(m.w, m.h) * Defs.TILE * 0.5
	shots.append({"name": "overhead", "pos": Vector3(mid.x, 170, mid.y + 120), "target": Vector3(mid.x, 0, mid.y), "fog": false})


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 25:
		return false
	if shot_i >= shots.size():
		return true
	var s: Dictionary = shots[shot_i]
	if wait == 0:
		cam.position = s["pos"]
		cam.look_at(s["target"], Vector3.UP)
		view.env.fog_enabled = s.get("fog", true)
		cam.far = 400 if not s.get("fog", true) else 130
		flash.visible = s.get("fog", true)
		if not s.get("fog", true):
			view.env.ambient_light_energy = 1.2
			for ch in view.get_children():
				if ch is MeshInstance3D:
					(ch as MeshInstance3D).visibility_range_end = 0.0
	wait += 1
	if wait < 6:
		return false
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, shot_i, s["name"]]
	img.save_png(path)
	print("saved ", path)
	wait = 0
	shot_i += 1
	return false
