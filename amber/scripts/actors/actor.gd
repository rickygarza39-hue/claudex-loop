class_name Actor
extends Node3D
## Base character: 2D movement on the tile grid with circle collision, path
## following, height following and a procedurally animated model.

const T := Defs.TILE

var mt: Match
var slot: Slot


## A stat bought in the progression trees (0 for bots and unbought stats).
func meta(key: String) -> float:
	return slot.mods.get(key, 0.0) if slot != null else 0.0

var pos := Vector2.ZERO
var y := 0.0
var facing := 0.0        # yaw (radians); forward = (-sin, -cos)
var look_pitch := 0.0
var radius := 0.32
var is_survivor := true
var visuals := true

# intents, set each frame by the PlayerController or an AI brain
var want_move := Vector2.ZERO
var want_run := false
var want_crouch := false
var want_interact := false
var want_face := Vector2.ZERO   # bots: direction to face (zero = movement direction)

# path following
var path := PackedVector2Array()
var path_i := 0
var path_goal := Vector2(INF, INF)
var path_age := 0.0
var path_siege := false

var cur_speed := 0.0
var moved := 0.0
var vel := Vector2.ZERO
var anim_phase := 0.0
var anim_attack := 0.0   # 0..1 arm swing for attacks
var in_gap := false
var in_water := false
var crouch_amount := 0.0
var downed_pose := 0.0
var shown := true
var channel := {}        # current hold interaction

var model_root: Node3D
var model: Node3D
var rig := {}
var tag: Label3D


func setup(match_ref: Match, s: Slot, p: Vector2) -> void:
	mt = match_ref
	slot = s
	pos = p
	visuals = mt.visuals
	y = mt.m.height_at(p)
	if visuals:
		model_root = Node3D.new()
		add_child(model_root)
		_build_model()
		tag = Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = false
		tag.font_size = 40
		tag.pixel_size = 0.004
		tag.outline_size = 8
		tag.position = Vector3(0, 2.15, 0)
		tag.visible = false
		add_child(tag)
	_sync_transform(0.0)


func _build_model() -> void:
	pass


func attach_model(n: Node3D) -> void:
	if model:
		model.queue_free()
	model = n
	model_root.add_child(n)
	rig.clear()
	for nm in ["Hips", "LegL", "LegR", "Torso", "ArmL", "ArmR", "Head", "Neck"]:
		var found := n.find_child(nm, true, false)
		if found is Node3D:
			rig[nm] = found


# ------------------------------------------------------------------------------
# Directions

func forward2() -> Vector2:
	return Vector2(-sin(facing), -cos(facing))


static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func face_dir(d: Vector2, dt: float, rate: float = 10.0) -> void:
	if d.length_squared() < 0.0001:
		return
	var target := yaw_of(d)
	facing = lerp_angle(facing, target, clampf(rate * dt, 0.0, 1.0))


func eye_height() -> float:
	return 1.6


func body_height() -> float:
	return 1.1


func eye_pos3() -> Vector3:
	return Vector3(pos.x, y + eye_height(), pos.y)


func move_speed() -> float:
	return 4.0


func uses_gaps() -> bool:
	return is_survivor


# ------------------------------------------------------------------------------
# Collision

func _tile_rects(tl: Vector2i, cur_h: float) -> Array:
	var m := mt.m
	if not m.inb(tl.x, tl.y):
		return [Rect2(tl.x * T, tl.y * T, T, T)]
	var tt := m.t(tl.x, tl.y)
	var full := Rect2(tl.x * T, tl.y * T, T, T)
	if tt == Defs.T.GAP:
		if not uses_gaps():
			return [full]
		if m.gap_along_x(tl.x, tl.y):
			return [Rect2(tl.x * T, tl.y * T, T, 0.5), Rect2(tl.x * T, tl.y * T + 1.5, T, 0.5)]
		return [Rect2(tl.x * T, tl.y * T, 0.5, T), Rect2(tl.x * T + 1.5, tl.y * T, 0.5, T)]
	if not MapData.walkable_type(tt, true):
		return [full]
	if mt.struct_blocks(tl, self):
		return [full]
	var th := m.floor_h[m.idx(tl.x, tl.y)]
	if absf(th - cur_h) > 1.15 and m.ramp_dir[m.idx(tl.x, tl.y)] == 0:
		return [full]
	return []


func _collide(p: Vector2) -> Vector2:
	var r := radius
	var cur_tl := MapData.tile_of(pos)
	var cur_h := mt.m.tile_height(cur_tl)
	for _iter in 2:
		var minx := int(floor((p.x - r) / T))
		var maxx := int(floor((p.x + r) / T))
		var miny := int(floor((p.y - r) / T))
		var maxy := int(floor((p.y + r) / T))
		for ty in range(miny, maxy + 1):
			for tx in range(minx, maxx + 1):
				for rect in _tile_rects(Vector2i(tx, ty), cur_h):
					var cx := clampf(p.x, rect.position.x, rect.end.x)
					var cy := clampf(p.y, rect.position.y, rect.end.y)
					var d := Vector2(p.x - cx, p.y - cy)
					var dl := d.length()
					if dl < r:
						if dl > 0.0001:
							p += d / dl * (r - dl)
						else:
							# centre inside the rect: push out along the shortest side
							var left = p.x - rect.position.x
							var right = rect.end.x - p.x
							var up = p.y - rect.position.y
							var down = rect.end.y - p.y
							var mn := minf(minf(left, right), minf(up, down))
							if mn == left:
								p.x = rect.position.x - r
							elif mn == right:
								p.x = rect.end.x + r
							elif mn == up:
								p.y = rect.position.y - r
							else:
								p.y = rect.end.y + r
	return p


func move_by(d: Vector2) -> void:
	var len := d.length()
	if len < 0.00001:
		return
	var steps := int(ceil(len / 0.3))
	var step := d / steps
	var start := pos
	for _i in steps:
		var np := _collide(Vector2(pos.x + step.x, pos.y))
		np = _collide(Vector2(np.x, np.y + step.y))
		pos = np
	moved += pos.distance_to(start)


func _gap_assist(dir: Vector2, dt: float) -> Vector2:
	## Steer survivors into the 1 m slot of a squeeze gap they are walking toward.
	if not uses_gaps() or dir == Vector2.ZERO:
		return dir
	var m := mt.m
	var ahead := pos + dir.normalized() * 1.2
	var tl := MapData.tile_of(ahead)
	var here := MapData.tile_of(pos)
	for cand in [tl, here]:
		if m.t(cand.x, cand.y) != Defs.T.GAP:
			continue
		var c := MapData.center_of(cand)
		var along_x := m.gap_along_x(cand.x, cand.y)
		if along_x:
			if absf(dir.x) < 0.3:
				return dir
			var off := c.y - pos.y
			return Vector2(dir.x, clampf(off * 3.0, -1.0, 1.0)).normalized()
		else:
			if absf(dir.y) < 0.3:
				return dir
			var off2 := c.x - pos.x
			return Vector2(clampf(off2 * 3.0, -1.0, 1.0), dir.y).normalized()
	return dir


func physics_step(dt: float) -> void:
	moved = 0.0
	var m := mt.m
	var tl := MapData.tile_of(pos)
	in_gap = m.t(tl.x, tl.y) == Defs.T.GAP
	in_water = m.t(tl.x, tl.y) == Defs.T.WATER
	var spd := move_speed()
	var dir := want_move
	if dir.length() > 1.0:
		dir = dir.normalized()
	dir = _gap_assist(dir, dt)
	cur_speed = spd * dir.length()
	vel = dir * spd
	move_by(vel * dt)
	if want_face != Vector2.ZERO:
		face_dir(want_face, dt, 12.0)
	_post_move(dt)


func _post_move(_dt: float) -> void:
	pass


# ------------------------------------------------------------------------------
# Path following

func nav_to(goal: Vector2, siege: bool = false, max_age: float = 1.2) -> bool:
	## Plans (or keeps) a path to goal. Returns false when no path exists.
	path_age += mt.dt_last
	var need := path.is_empty() or path_goal.distance_to(goal) > 1.5 or path_age > max_age or siege != path_siege
	if need:
		path = mt.nav.path(pos, goal, uses_gaps(), siege)
		path_i = 0
		path_goal = goal
		path_age = 0.0
		path_siege = siege
		if path.is_empty():
			return false
	return true


func steer_path() -> Vector2:
	## Direction toward the next useful waypoint (with simple string pulling).
	if path.is_empty():
		return Vector2.ZERO
	while path_i < path.size() - 1 and pos.distance_to(path[path_i]) < 0.6:
		path_i += 1
	# look ahead: skip waypoints we can walk to directly
	var best := path_i
	var limit := mini(path.size() - 1, path_i + 4)
	for k in range(path_i + 1, limit + 1):
		if mt.m.clear_line(pos, path[k], radius + 0.05, uses_gaps(), mt.solid_fn_for(self)):
			best = k
		else:
			break
	path_i = best
	var target := path[path_i]
	var d := target - pos
	if path_i == path.size() - 1 and d.length() < 0.25:
		return Vector2.ZERO
	return d.normalized()


func path_done() -> bool:
	return path.is_empty() or (path_i >= path.size() - 1 and pos.distance_to(path[path.size() - 1]) < 0.5)


func clear_path() -> void:
	path = PackedVector2Array()
	path_goal = Vector2(INF, INF)


# ------------------------------------------------------------------------------
# Visuals

func set_shown(v: bool) -> void:
	shown = v
	if model_root:
		model_root.visible = v


func _sync_transform(dt: float) -> void:
	var target_y := mt.m.height_at(pos)
	if in_water:
		target_y -= 0.32
	if dt <= 0.0:
		y = target_y
	else:
		y = lerpf(y, target_y, clampf(dt * 14.0, 0.0, 1.0))
	position = Vector3(pos.x, y, pos.y)
	if model_root:
		model_root.rotation.y = facing


func update_visual(dt: float) -> void:
	_sync_transform(dt)
	if not visuals or model == null:
		return
	var speed_frac := clampf(moved / maxf(dt, 0.0001) / 4.0, 0.0, 1.6)
	anim_phase += moved * 2.4
	var swing := sin(anim_phase) * 0.7 * clampf(speed_frac * 1.4, 0.0, 1.0)
	if rig.has("LegL"):
		rig["LegL"].rotation.x = swing
		rig["LegR"].rotation.x = -swing
	if rig.has("ArmL"):
		rig["ArmL"].rotation.x = -swing * 0.8
		rig["ArmR"].rotation.x = swing * 0.8 - anim_attack * 2.2
	if rig.has("Hips"):
		var bob := absf(sin(anim_phase)) * 0.05 * clampf(speed_frac, 0.0, 1.0)
		var base_y: float = rig["Hips"].get_meta("base_y", rig["Hips"].position.y)
		if not rig["Hips"].has_meta("base_y"):
			rig["Hips"].set_meta("base_y", base_y)
		rig["Hips"].position.y = base_y + bob - crouch_amount * 0.38
	if rig.has("Torso"):
		var base_rx: float = rig["Torso"].get_meta("base_rx", rig["Torso"].rotation.x)
		if not rig["Torso"].has_meta("base_rx"):
			rig["Torso"].set_meta("base_rx", base_rx)
		rig["Torso"].rotation.x = base_rx - crouch_amount * 0.45
	if not rig.has("Hips") and model.has_meta("external"):
		model.position.y = absf(sin(anim_phase)) * 0.05
	# lying down when downed
	model_root.rotation.x = -downed_pose * 1.45
	model_root.position.y = downed_pose * 0.25
	model_root.position.z = 0.0
