class_name PlayerController
extends Node3D
## First-person control of the local player's actor (survivor, killer or elite),
## plus a follow camera while spectating.

var mt: Match
var actor: Actor = null
var cam: Camera3D
var flashlight: SpotLight3D
var fill_light: OmniLight3D
var yaw := 0.0
var pitch := 0.0
var bob_t := 0.0
var shake := 0.0
var flash_on := true
var build_mode := false
var build_kind := Defs.B.DOOR
var tool := 0                   # 0 flare, 1 snare, 2 flash
var ui_block := false           # a menu is open: no look / no actions
var spectating := false
var spec_i := 0
var spec_free := false
var ghost: MeshInstance3D
var build_target := Vector2i(-1, -1)
var build_error := ""
var map_open := false
# Camera: survivors choose third person (over the shoulder) or first person with V;
# killers and elites are always first person.
var third_person := true        # the survivor's choice
var shoulder := 1.0             # 1 right shoulder, -1 left (X swaps)
var tp_blend := 0.0             # 0 first person .. 1 third person, eased
const TP_DIST := 3.1
const TP_SIDE := 0.6
const TP_UP := 0.3

const BUILD_ORDER := [Defs.B.DOOR, Defs.B.WALL, Defs.B.BARRICADE, Defs.B.ALARM, Defs.B.FLOODLIGHT, Defs.B.DECOY, Defs.B.LOCKER, Defs.B.SNARE, Defs.B.FLASH, Defs.B.HATCH]


func setup(match_ref: Match) -> void:
	mt = match_ref
	cam = Camera3D.new()
	cam.fov = 78
	cam.near = 0.05
	cam.far = 120.0
	add_child(cam)
	cam.current = true
	flashlight = SpotLight3D.new()
	flashlight.spot_range = 26.0
	flashlight.spot_angle = 28.0
	flashlight.spot_angle_attenuation = 0.8
	flashlight.light_energy = 2.4
	flashlight.light_color = Color(1.0, 0.95, 0.84)
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.18, -0.15, 0)
	cam.add_child(flashlight)
	fill_light = OmniLight3D.new()
	fill_light.omni_range = 4.0
	fill_light.light_energy = 0.25
	fill_light.light_color = Color(0.9, 0.9, 1.0)
	cam.add_child(fill_light)
	ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 0.08, 2.0)
	ghost.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 1.0, 0.5, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = gm
	ghost.visible = false
	mt.add_child(ghost)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func possess(a: Actor) -> void:
	actor = a
	spectating = false
	yaw = a.facing
	pitch = 0.0
	build_mode = false
	if Game.has_arg("first_person"):
		third_person = false
	tp_blend = 1.0 if wants_third_person() else 0.0
	_apply_side_look()


func _apply_side_look() -> void:
	if mt.view == null:
		return
	var killer := actor is Killer
	flashlight.visible = not killer and flash_on
	fill_light.light_energy = 0.25
	var env := mt.view.env
	if killer:
		# killers see in the dark, through a red haze
		env.ambient_light_color = Color(0.75, 0.32, 0.28)
		env.ambient_light_energy = 0.55
		env.fog_light_color = Color(0.22, 0.08, 0.07)
		fill_light.light_energy = 0.0
	else:
		env.ambient_light_color = Color(0.32, 0.38, 0.42)
		env.ambient_light_energy = 0.11
		env.fog_light_color = Color(0.1, 0.12, 0.11)


## Third person only for survivors, and never while hiding in a locker.
func wants_third_person() -> bool:
	if actor == null or not is_instance_valid(actor) or not (actor is Survivor):
		return false
	var s := actor as Survivor
	if s.hidden_in != null:
		return false
	if s.is_downed() or s.pinned_by != null:
		return true             # downed or grabbed: pull out so you can see what's happening
	return third_person


## Match asks this to decide whether to draw the player's own body.
func shows_own_body() -> bool:
	return tp_blend > 0.35


func _place_third_person(pivot: Vector3, delta: float) -> void:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	var back := basis.z
	var right := basis.x
	var want := pivot + right * TP_SIDE * shoulder + Vector3.UP * TP_UP + back * TP_DIST
	var cpos := _clamp_camera(pivot, want)
	var fp_pos := pivot
	var target := fp_pos.lerp(cpos, tp_blend)
	cam.global_position = target
	cam.global_rotation = Vector3(pitch, yaw, 0)


## Pull the camera in front of walls, below ceilings and above the floor (the world is a tile grid, not physics bodies).
func _clamp_camera(pivot: Vector3, want: Vector3) -> Vector3:
	var m := mt.m
	var best := pivot
	const STEPS := 24
	for i in range(1, STEPS + 1):
		var f := float(i) / STEPS
		var p := pivot.lerp(want, f)
		var p2 := Vector2(p.x, p.z)
		if not m.los(Vector2(pivot.x, pivot.z), pivot.y, p2, p.y):
			break
		var tl := MapData.tile_of(p2)
		if not m.inb(tl.x, tl.y):
			break
		var fh := m.tile_height(tl)
		var rf := m.roof[m.idx(tl.x, tl.y)]
		if rf == Defs.R.CEILING and p.y > fh + MapData.CEILING_H - 0.3:
			break
		if rf == Defs.R.ROOF and p.y > fh + MapData.ROOF_H - 0.3 and pivot.y < fh + MapData.ROOF_H:
			break
		if p.y < m.height_at(p2) + 0.35:
			break
		best = p
	# keep a little gap from whatever stopped us
	var d := best - pivot
	if best != want and d.length() > 0.4:
		best = pivot + d * ((d.length() - 0.3) / d.length())
	return best


func on_actor_retired(a: Actor) -> void:
	if a == actor:
		actor = null
		spectating = true
		build_mode = false
		ghost.visible = false
		flashlight.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if ui_block:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * Game.mouse_sensitivity
		var inv := -1.0 if Game.invert_y else 1.0
		pitch = clampf(pitch - mm.relative.y * Game.mouse_sensitivity * inv, deg_to_rad(-85), deg_to_rad(85))
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if build_mode and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var i := BUILD_ORDER.find(build_kind)
			i = (i + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1) + BUILD_ORDER.size()) % BUILD_ORDER.size()
			build_kind = BUILD_ORDER[i]
		elif not build_mode and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			tool = (tool + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else 2)) % 3
		if spectating and mb.button_index == MOUSE_BUTTON_LEFT:
			spec_i += 1


## Called by the match at the start of every simulation step.
func update_intents(_dt: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if has_meta("autopilot") and mt.brains.has(actor):
		return
	actor.want_move = Vector2.ZERO
	actor.want_interact = false
	actor.want_run = false
	actor.want_crouch = false
	if actor is Killer:
		var kk := actor as Killer
		kk.want_attack = false
		kk.want_power = false
	if ui_block:
		return
	actor.facing = yaw
	actor.look_pitch = pitch
	var inp := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	var fwd := actor.forward2()
	var right := Vector2(-fwd.y, fwd.x) * -1.0
	right = Vector2(cos(yaw), -sin(yaw))
	var mv := right * inp.x + fwd * (-inp.y)
	if mv.length() > 1.0:
		mv = mv.normalized()
	actor.want_move = mv
	actor.want_run = Input.is_action_pressed("run")
	actor.want_crouch = Input.is_action_pressed("crouch")
	# interact: instant options on press, hold options while held
	if Input.is_action_pressed("interact"):
		if actor.channel.is_empty():
			var opt := mt.interact.best_for_player(actor)
			if not opt.is_empty() and opt["blocked"] == "":
				if opt["time"] > 0.0 or Input.is_action_just_pressed("interact"):
					mt.interact.begin(actor, opt)
		actor.want_interact = not actor.channel.is_empty()
	if actor is Survivor:
		_survivor_actions(actor as Survivor)
	else:
		_killer_actions(actor as Killer)


func _survivor_actions(s: Survivor) -> void:
	if Input.is_action_just_pressed("camera_toggle"):
		third_person = not third_person
	if Input.is_action_just_pressed("shoulder_swap"):
		shoulder = -shoulder
	if Input.is_action_just_pressed("flashlight"):
		flash_on = not flash_on
		flashlight.visible = flash_on
	if Input.is_action_just_pressed("tool_1"):
		tool = 0
	if Input.is_action_just_pressed("tool_2"):
		tool = 1
	if Input.is_action_just_pressed("tool_3"):
		tool = 2
	if Input.is_action_just_pressed("build"):
		build_mode = not build_mode
	if build_mode:
		_build_input(s)
		return
	if not s.can_act():
		return
	if Input.is_action_just_pressed("alt") and mt.time >= s.parry_cd_until:
		s.parry_until = mt.time + Tuning.PARRY_WINDOW
		s.parry_cd_until = mt.time + Tuning.PARRY_COOLDOWN
		if mt.hud:
			mt.hud.on_parry_pressed()
	if Input.is_action_just_pressed("primary"):
		match tool:
			0:
				if s.flare > 0:
					mt.use_flare(s)
				else:
					mt.hud.toast("No flare gun. Four are hidden on the map (shown on your map, Tab).")
			1, 2:
				if not mt.place_trap(s, tool - 1):
					mt.hud.toast("No %s to place." % Defs.TRAP_NAMES[tool - 1].to_lower())
	if Input.is_action_just_pressed("ability"):
		match s.role:
			Defs.Role.ENGINEER:
				if not mt.bases.quick_barricade(s):
					mt.hud.toast("Barricade not ready (or no room in front).")
			Defs.Role.MEDIC:
				if not mt.scent_mask(s):
					mt.hud.toast("Scent mask recharging.")
			Defs.Role.TRAPPER:
				var which := 0 if s.traps[0] > 0 else 1
				if not mt.place_trap(s, which):
					mt.hud.toast("No traps left. Buy a trap kit at a terminal.")
	if Input.is_action_just_pressed("lockdown"):
		if s.duo.base == null:
			mt.hud.toast("You need a base first.")
		elif s.duo.lockdown_used:
			mt.hud.toast("Lockdown already used this match.")
		else:
			mt.bases.lockdown(s)
	if Input.is_action_just_pressed("donate"):
		_donate(s)


func _donate(s: Survivor) -> void:
	var poorest: Duo = null
	var low := INF
	for d in mt.duos:
		if d == s.duo or not d.active():
			continue
		var p = (d.base.stage if d.base else 0) * 100.0 + d.money
		if p < low:
			low = p
			poorest = d
	if poorest == null or s.duo.money < Tuning.DONATE_STEP:
		mt.hud.toast("Nothing to give (or no one to give it to).")
		return
	s.duo.money -= Tuning.DONATE_STEP
	poorest.money += Tuning.DONATE_STEP
	mt.feed_all("Your duo sent $%d to %s duo." % [Tuning.DONATE_STEP, poorest.name], "good")


func _build_input(s: Survivor) -> void:
	for i in 9:
		if Input.is_action_just_pressed("tool_%d" % (i + 1)) and i < BUILD_ORDER.size():
			build_kind = BUILD_ORDER[i]
	if Input.is_action_just_pressed("hatch_key"):
		build_kind = Defs.B.HATCH
	build_target = _aim_tile(build_kind == Defs.B.HATCH)
	build_error = "Aim at the ground near your radio" if build_target.x < 0 else mt.bases.can_place(s, build_kind, build_target)
	var st := mt.structure_at(build_target) if build_target.x >= 0 else null
	if st != null and (st.kind == Defs.B.WALL or st.kind == Defs.B.DOOR):
		if Input.is_action_just_pressed("upgrade_spikes"):
			var e := mt.bases.upgrade(s, st, false)
			mt.hud.toast(e if e != "" else "Spikes added.")
		if Input.is_action_just_pressed("upgrade_metal"):
			var e2 := mt.bases.upgrade(s, st, true)
			mt.hud.toast(e2 if e2 != "" else "Reinforced with metal. Brutes can't charge through it.")
	if Input.is_action_just_pressed("primary"):
		if build_error == "":
			mt.bases.place(s, build_kind, build_target)
		else:
			mt.hud.toast(build_error)
	if Input.is_action_just_pressed("alt"):
		build_mode = false


func _aim_tile(want_wall: bool) -> Vector2i:
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var p := origin
	for i in 90:
		p += dir * 0.08
		var tl := MapData.tile_of(Vector2(p.x, p.z))
		var tt := mt.m.tv(tl)
		var fh := mt.m.tile_height(tl)
		if want_wall:
			if tt == Defs.T.WALL and p.y < fh + 3.5:
				return tl
			continue
		if not MapData.walkable_type(tt, true) and p.y < fh + 3.5:
			return Vector2i(-1, -1)
		if p.y <= fh + 0.02:
			return tl
	if want_wall:
		return Vector2i(-1, -1)
	var tl2 := MapData.tile_of(actor.pos + actor.forward2() * 2.0)
	return tl2


func _killer_actions(k: Killer) -> void:
	k.want_attack = Input.is_action_pressed("primary")
	if Input.is_action_just_pressed("alt"):
		k.want_power = true
	k.power_aim = k.forward2()
	if Input.is_action_just_pressed("route"):
		var tl := _aim_tile(false)
		var e := "Aim at a squeeze gap or a narrow tunnel" if tl.x < 0 else mt.route_edit(k, tl)
		if e != "":
			# also allow aiming straight at a gap tile (it is a wall-like tile)
			var tl2 := _aim_gap()
			if tl2.x >= 0:
				e = mt.route_edit(k, tl2)
		mt.hud.toast(e if e != "" else "Route edited. %d charges left." % k.route_charges)
	if Input.is_action_just_pressed("nest"):
		if not mt.nest.can_trigger():
			mt.hud.toast("The Nest isn't ready (%d%%)." % int(mt.nest.meter))
		else:
			var target: Base = null
			var bd := INF
			for d in mt.duos:
				if d.base != null and d.active() and d.base.pos.distance_to(k.pos) < bd and (d.base.revealed or d.base.pos.distance_to(k.pos) < 40.0):
					bd = d.base.pos.distance_to(k.pos)
					target = d.base
			mt.nest.trigger(k, target)


func _aim_gap() -> Vector2i:
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var p := origin
	for i in 60:
		p += dir * 0.08
		var tl := MapData.tile_of(Vector2(p.x, p.z))
		if mt.m.tv(tl) == Defs.T.GAP:
			return tl
		if mt.m.is_solid_static(tl.x, tl.y):
			return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _process(delta: float) -> void:
	if mt == null:
		return
	if actor != null and is_instance_valid(actor) and not spectating:
		var eye := actor.eye_height()
		var moving := actor.moved > 0.001
		if moving:
			var before := floorf(bob_t / PI)
			bob_t += actor.moved * 1.9
			if floorf(bob_t / PI) != before and mt.sfx and not actor.want_crouch:
				mt.sfx.play2d("step", -6.0 if actor.want_run else -13.0, 1.15 if actor is Survivor else 0.7)
		var bob := sin(bob_t * 2.0) * 0.035 * (1.0 if moving else 0.0)
		var sway := sin(bob_t) * 0.02 * (1.0 if moving else 0.0)
		shake = maxf(0.0, shake - delta * 3.0)
		var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.05
		var tp_target := 1.0 if wants_third_person() else 0.0
		tp_blend = move_toward(tp_blend, tp_target, delta * 4.0)
		var fp := 1.0 - tp_blend
		var base_pos := Vector3(actor.pos.x, actor.y + eye + bob * fp, actor.pos.y)
		if actor is Survivor and (actor as Survivor).hidden_in != null:
			base_pos.y = actor.y + 1.5
		global_position = base_pos
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		if tp_blend > 0.0:
			_place_third_person(base_pos + Vector3(0, -0.15, 0) * tp_blend, delta)
			cam.global_position += sh
		else:
			cam.position = right * sway + sh
			var roll := 0.0
			if actor is Survivor and (actor as Survivor).is_downed():
				roll = 0.25
			cam.rotation = Vector3(pitch, yaw, roll)
		var target_fov := 78.0
		if actor.want_run and moving:
			target_fov = 84.0
		if actor is Killer and (actor as Killer).power_state == "charge":
			target_fov = 95.0
		cam.fov = lerpf(cam.fov, target_fov, clampf(delta * 6.0, 0.0, 1.0))
		# flashlight lags a little behind the view
		flashlight.rotation = flashlight.rotation.lerp(Vector3.ZERO, clampf(delta * 8.0, 0.0, 1.0))
		if tp_blend > 0.0:
			# in third person the torch is held at the shoulder, not behind the camera
			flashlight.global_position = base_pos + right * 0.28 * shoulder + Vector3(0, -0.25, 0) + (-cam.global_transform.basis.z) * 0.3
			fill_light.global_position = base_pos
		else:
			flashlight.position = Vector3(0.18, -0.15, 0)
			fill_light.position = Vector3.ZERO
		_update_ghost()
	elif spectating:
		_spectate(delta)


func _update_ghost() -> void:
	if not build_mode or build_target.x < 0 or not (actor is Survivor):
		ghost.visible = false
		return
	ghost.visible = true
	var c := MapData.center_of(build_target)
	ghost.global_position = Vector3(c.x, mt.m.tile_height(build_target) + 0.05, c.y)
	var gm := ghost.material_override as StandardMaterial3D
	gm.albedo_color = Color(0.3, 1.0, 0.5, 0.35) if build_error == "" else Color(1.0, 0.3, 0.25, 0.35)


func _spectate(delta: float) -> void:
	var acts: Array = mt.all_actors()
	if acts.is_empty():
		return
	var a: Actor = acts[spec_i % acts.size()]
	var back := Vector3(sin(a.facing), 0, cos(a.facing)) * 4.0
	var target := Vector3(a.pos.x, a.y + 1.6, a.pos.y)
	global_position = global_position.lerp(target + back + Vector3(0, 1.6, 0), clampf(delta * 4.0, 0.0, 1.0))
	cam.position = Vector3.ZERO
	cam.look_at(target, Vector3.UP)


func hit_feedback(strength: float) -> void:
	shake = maxf(shake, strength)
