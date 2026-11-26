class_name Killer
extends Actor
## Killers (Tracker, Brute, Lurker), elite infected (weaker versions) and swarm husks.

var ktype := Defs.K.TRACKER
var elite := false
var husk := false
var husk_until := -1.0
var swarm_base: Base = null
var released := false

# attack
var want_attack := false
var want_power := false
var power_aim := Vector2.ZERO     # direction for charge / tongue
var atk_state := ""               # "", "windup", "recover"
var atk_t := 0.0

# signature power
var power_state := ""             # "", "stalk", "charge_windup", "charge", "tongue_fly", "tongue_pull"
var power_t := 0.0
var power_cd_until := 0.0
var charge_dir := Vector2.ZERO
var charge_hit := false
var tongue_tip := Vector2.ZERO
var tongue_dir := Vector2.ZERO
var tongue_victim: Survivor = null
var constrict_t := -1.0
var pull_prev_d := INF
var pull_stall_t := 0.0

# status
var stun_until := -1.0
var stun_kind := ""
var held_until := -1.0
var disoriented_until := -1.0
var trap_immune_until := -1.0
var spotted_until := -1.0
var spot_meter := 0.0
var bounty := 0
var route_charges := Tuning.ROUTE_CHARGES
var parry_paid := {}
var tongue_mesh: MeshInstance3D
var last_hit_time := -100.0
var chase_t := 0.0
var tired_until := -1.0
var fire_drop_t := 0.0


func setup_killer(match_ref: Match, s: Slot, p: Vector2, kt: int, is_elite: bool, is_husk: bool = false) -> void:
	is_survivor = false
	ktype = kt
	elite = is_elite
	husk = is_husk
	radius = Tuning.KILLER_RADIUS[kt] if not (elite or husk) else 0.34
	setup(match_ref, s, p)


func _build_model() -> void:
	var slot_name := "husk"
	if not husk:
		if elite:
			slot_name = "elite"
		else:
			slot_name = Defs.KILLER_SLOTS[ktype]
	var col := Color(0.35, 0.3, 0.25)
	if elite and slot != null and slot.duo != null:
		col = slot.duo.color
	attach_model(Models.make(slot_name, {"color": col}))
	if not elite and not husk:
		# a cold rim light from behind: the killer reads as a silhouette against the fog
		var rim := OmniLight3D.new()
		rim.light_color = Color(0.45, 0.55, 0.75)
		rim.light_energy = 0.9
		rim.omni_range = 3.2
		rim.position = Vector3(0, Tuning.KILLER_EYE[ktype] + 0.2, 0.9)
		rim.shadow_enabled = false
		model_root.add_child(rim)
	if elite:
		model_root.scale = Vector3.ONE * (1.0 + 0.05 * ktype)
	tongue_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.06
	cm.height = 1.0
	cm.radial_segments = 6
	tongue_mesh.mesh = cm
	tongue_mesh.material_override = Mats.flat(Color(0.55, 0.12, 0.12), 0.3, 0.4)
	tongue_mesh.visible = false
	add_child(tongue_mesh)


func eye_height() -> float:
	if husk:
		return 1.5
	if elite:
		return 1.7
	if ktype == Defs.K.HOLLOW and power_state == "skitter":
		return 0.8
	return Tuning.KILLER_EYE[ktype]


func body_height() -> float:
	return Tuning.KILLER_BODY[ktype] if not (elite or husk) else 1.1


func is_main() -> bool:
	return not elite and not husk


func power_mult() -> float:
	return 1.0 if is_main() else Tuning.ELITE_POWER_MULT


func stunned() -> bool:
	return mt.time < stun_until


func held() -> bool:
	return mt.time < held_until


func disoriented() -> bool:
	return mt.time < disoriented_until


func stalking() -> bool:
	return power_state == "stalk"


func spotted() -> bool:
	return mt.time < spotted_until


func uses_gaps() -> bool:
	## The Lurker crawls through survivor crevices (slowly); so does a skittering Hollow.
	## Elite Lurkers need the Vents skill for it.
	if ktype == Defs.K.HOLLOW and power_state == "skitter":
		return true
	if ktype != Defs.K.LURKER or husk:
		return false
	return is_main() or (slot != null and slot.perk("Vents") > 0)


func perk(branch: String) -> int:
	if slot == null:
		return 0
	return slot.perk(branch)


func move_speed() -> float:
	if not released or stunned() or held():
		return 0.0
	if power_state == "charge_windup" or power_state == "tongue_fly" or power_state == "tongue_pull":
		return 0.0
	if not channel.is_empty():
		return 0.0
	if power_state == "charge":
		return Tuning.CHARGE_SPEED * (0.85 if elite else 1.0) * (1.0 + meta("charge"))
	var s: float
	if husk:
		s = Tuning.HUSK_SPEED
	elif elite:
		s = Tuning.ELITE_SPEED * (1.0 + 0.06 * perk("Speed"))
	else:
		s = Tuning.KILLER_SPEED[ktype]
	if stalking():
		s = Tuning.STALK_SPEED if is_main() else Tuning.STALK_SPEED * 0.85
	if in_gap:
		s = Tuning.LURKER_SQUEEZE * (1.0 + meta("k_squeeze"))
	if power_state == "skitter":
		s = Tuning.SKITTER_SPEED * (1.0 + meta("k_move"))
	elif power_state in ["slam_windup", "scream_windup", "standup"]:
		s *= 0.25
	if atk_state == "windup":
		s *= Tuning.WINDUP_MOVE
	elif atk_state == "recover":
		s *= 0.4
	if disoriented():
		s *= 0.5
	if ktype == Defs.K.LURKER and spotted() and is_main():
		s *= Tuning.LURKER_SPOTTED_SLOW
	if in_water:
		s *= 0.86
	if mt.time < tired_until:
		s *= Tuning.TIRE_MULT
	s *= mt.pack_bonus(self)
	s *= 1.0 + meta("k_move")
	return s


## Power cooldown multiplier from the progression trees.
func _cdm() -> float:
	return maxf(0.4, 1.0 - meta("k_power"))


# ------------------------------------------------------------------------------
# Status effects

## Stuns from knockdowns, traps, spikes and charge misses.
func stun(duration: float, kind: String) -> bool:
	if (kind == "snare" or kind == "flash") and mt.time < trap_immune_until:
		return false
	var d := duration
	if ktype == Defs.K.BRUTE and is_main():
		d *= Tuning.BRUTE_STUN_MULT
	d *= maxf(0.4, 1.0 - 0.2 * perk("Tank"))
	d *= maxf(0.4, 1.0 - meta("k_stun"))
	if kind == "snare":
		held_until = maxf(held_until, mt.time + d)
		trap_immune_until = mt.time + d + Tuning.TRAP_IMMUNITY
	elif kind == "flash":
		disoriented_until = maxf(disoriented_until, mt.time + d)
		trap_immune_until = mt.time + d + Tuning.TRAP_IMMUNITY
	else:
		stun_until = maxf(stun_until, mt.time + d)
		stun_kind = kind
	_interrupt()
	return true


func _interrupt() -> void:
	if power_state == "tongue_fly" or power_state == "tongue_pull":
		_end_tongue()
	if power_state == "charge" or power_state == "charge_windup":
		power_state = ""
		power_cd_until = mt.time + _cdm() * Tuning.CHARGE_COOLDOWN * 0.5
	if stalking():
		end_stalk()
	match power_state:
		"slam_windup":
			power_cd_until = mt.time + _cdm() * Tuning.SLAM_COOLDOWN * 0.5
		"scream_windup":
			power_cd_until = mt.time + _cdm() * Tuning.SCREAM_COOLDOWN * 0.5
		"skitter", "standup":
			power_cd_until = mt.time + _cdm() * Tuning.SKITTER_COOLDOWN
			crouch_amount = 0.0
		"burn":
			power_cd_until = mt.time + _cdm() * Tuning.FIRE_COOLDOWN
	if power_state in ["slam_windup", "scream_windup", "skitter", "standup", "burn"]:
		power_state = ""
	atk_state = ""
	anim_attack = 0.0
	if not channel.is_empty():
		mt.interact.on_cancel(self, channel)
		channel = {}


# ------------------------------------------------------------------------------
# Per-frame logic

func tick(dt: float) -> void:
	if husk and mt.time > husk_until:
		mt.remove_husk(self)
		return
	if not released:
		return
	# attack state machine
	match atk_state:
		"":
			if want_attack and power_state in ["", "burn"] and not stunned() and not held() and channel.is_empty():
				atk_state = "windup"
				atk_t = 0.0
		"windup":
			atk_t += dt
			anim_attack = clampf(atk_t / Tuning.ATTACK_WINDUP, 0.0, 1.0) * 0.6
			if atk_t >= (Tuning.ELITE_WINDUP if elite else Tuning.ATTACK_WINDUP):
				_resolve_attack()
		"recover":
			atk_t -= dt
			anim_attack = maxf(0.0, anim_attack - dt * 3.0)
			if atk_t <= 0.0:
				atk_state = ""
	# powers
	if want_power and not stunned() and not held() and channel.is_empty():
		_try_power()
	_tick_power(dt)
	if is_main() and ktype == Defs.K.LURKER:
		_tick_spotting(dt)
	_tick_fatigue(dt)


func _post_move(dt: float) -> void:
	if power_state == "charge":
		return
	if want_face != Vector2.ZERO:
		return
	if want_move != Vector2.ZERO and moved > 0.0:
		face_dir(want_move, dt, 9.0)


func _resolve_attack() -> void:
	anim_attack = 1.0
	if mt.sfx:
		mt.sfx.play3d("swing", Vector3(pos.x, y + 1.4, pos.y), -6.0)
	var fwd := forward2()
	var best: Survivor = null
	var best_d := INF
	for s in mt.living_survivors():
		if s.is_downed() or s.hidden_in != null:
			continue
		var d = s.pos - pos
		var dist = d.length()
		if dist > Tuning.ATTACK_RANGE + s.radius:
			continue
		if absf(fwd.angle_to(d)) > deg_to_rad(Tuning.ATTACK_ARC_DEG * 0.5) and dist > radius + s.radius + 0.25:
			continue
		if not mt.m.los(pos, y + 1.2, s.pos, s.y + 1.0):
			continue
		if dist < best_d:
			best = s
			best_d = dist
	atk_state = "recover"
	if best != null:
		var res := best.take_hit(self)
		if res == "parried":
			mt.on_parry(best, self)
			atk_t = (Tuning.ATTACK_RECOVER_MISS) * maxf(0.5, 1.0 - meta("k_recover"))
		else:
			mt.on_hit(best, self, res)
			last_hit_time = mt.time
			atk_t = (Tuning.ELITE_RECOVER_HIT if elite else Tuning.ATTACK_RECOVER_HIT) * maxf(0.5, 1.0 - meta("k_recover"))
			if perk("Bully") > 0:
				best.slow_until = mt.time + 1.5 * perk("Bully")
		return
	# no survivor: hit a structure or station in front
	var mult := Tuning.BRUTE_STRUCT_MULT if ktype == Defs.K.BRUTE else 1.0
	mult *= 1.0 + 0.35 * perk("Smash")
	var dmg := Tuning.KILLER_STRUCT_DPS * (Tuning.ATTACK_WINDUP + Tuning.ATTACK_RECOVER_MISS) * mult
	if not mt.damage_in_front(self, dmg):
		mt.make_noise(pos, 6.0, "swing", self)
	atk_t = (Tuning.ATTACK_RECOVER_MISS) * maxf(0.5, 1.0 - meta("k_recover"))


func _try_power() -> void:
	if power_state != "":
		if power_state == "stalk":
			end_stalk()
		return
	if mt.time < power_cd_until or atk_state != "":
		return
	if husk:
		return
	match ktype:
		Defs.K.TRACKER:
			power_state = "stalk"
			power_t = Tuning.STALK_TIME * power_mult() * (1.0 + meta("stalk"))
			mt.on_stalk(self, true)
		Defs.K.BRUTE:
			power_state = "charge_windup"
			power_t = Tuning.CHARGE_WINDUP
			charge_dir = power_aim if power_aim != Vector2.ZERO else forward2()
			charge_hit = false
			mt.make_noise(pos, 24.0, "roar", self)
		Defs.K.LURKER:
			power_state = "tongue_fly"
			tongue_dir = (power_aim if power_aim != Vector2.ZERO else forward2()).normalized()
			tongue_tip = pos
			facing = Actor.yaw_of(tongue_dir)
		Defs.K.FOREMAN:
			power_state = "slam_windup"
			power_t = Tuning.SLAM_WINDUP
			mt.make_noise(pos, 14.0, "roar", self)
		Defs.K.HOLLOW:
			power_state = "skitter"
			power_t = Tuning.SKITTER_TIME * power_mult() * (1.0 + meta("skitter"))
			mt.make_noise(pos, 10.0, "roar", self)
		Defs.K.FURNACE:
			power_state = "burn"
			power_t = Tuning.FIRE_TIME * power_mult() * (1.0 + meta("fire"))
			fire_drop_t = 0.0
			mt.make_noise(pos, 18.0, "roar", self)
		Defs.K.TALLY:
			mt.blink(self, (power_aim if power_aim != Vector2.ZERO else forward2()).normalized(), Tuning.BLINK_RANGE * power_mult() * (1.0 + meta("blink")))
			power_cd_until = mt.time + _cdm() * Tuning.BLINK_COOLDOWN
		Defs.K.CHOIR:
			power_state = "scream_windup"
			power_t = Tuning.SCREAM_WINDUP


func end_stalk() -> void:
	if power_state == "stalk":
		power_state = ""
		power_cd_until = mt.time + _cdm() * Tuning.STALK_COOLDOWN
		mt.on_stalk(self, false)


func _tick_power(dt: float) -> void:
	match power_state:
		"slam_windup":
			power_t -= dt
			anim_attack = 1.0 - clampf(power_t / Tuning.SLAM_WINDUP, 0.0, 1.0)
			if power_t <= 0.0:
				power_state = ""
				anim_attack = 0.0
				power_cd_until = mt.time + _cdm() * Tuning.SLAM_COOLDOWN
				mt.slam(self, pos + forward2() * 2.0, Tuning.SLAM_RADIUS * power_mult() * (1.0 + meta("slam")))
		"skitter":
			power_t -= dt
			crouch_amount = 1.0
			if power_t <= 0.0 or want_attack:
				power_state = "standup"
				power_t = Tuning.SKITTER_STANDUP
				want_attack = false
		"standup":
			power_t -= dt
			if power_t <= 0.0:
				power_state = ""
				crouch_amount = 0.0
				power_cd_until = mt.time + _cdm() * Tuning.SKITTER_COOLDOWN
		"burn":
			power_t -= dt
			fire_drop_t -= dt
			if fire_drop_t <= 0.0:
				fire_drop_t = Tuning.FIRE_DROP_EVERY
				mt.add_fire(pos, self)
			if power_t <= 0.0:
				power_state = ""
				power_cd_until = mt.time + _cdm() * Tuning.FIRE_COOLDOWN
		"scream_windup":
			power_t -= dt
			if power_t <= 0.0:
				power_state = ""
				power_cd_until = mt.time + _cdm() * Tuning.SCREAM_COOLDOWN
				mt.scream(self, Tuning.SCREAM_RADIUS * power_mult() * (1.0 + meta("scream")))
		"stalk":
			power_t -= dt
			if power_t <= 0.0 or atk_state == "windup":
				end_stalk()
		"charge_windup":
			power_t -= dt
			if power_aim != Vector2.ZERO:
				charge_dir = power_aim.normalized()
			facing = Actor.yaw_of(charge_dir)
			if power_t <= 0.0:
				power_state = "charge"
				power_t = Tuning.CHARGE_TIME * (0.7 if elite else 1.0)
		"charge":
			power_t -= dt
			# limited steering
			if power_aim != Vector2.ZERO:
				var want := power_aim.normalized()
				var ang := charge_dir.angle_to(want)
				var maxr := deg_to_rad(Tuning.CHARGE_TURN_DEG) * dt
				charge_dir = charge_dir.rotated(clampf(ang, -maxr, maxr))
			facing = Actor.yaw_of(charge_dir)
			var before := pos
			move_by(charge_dir * Tuning.CHARGE_SPEED * (1.0 + meta("charge")) * dt)
			moved = pos.distance_to(before)
			# survivors in the way
			for s in mt.living_survivors():
				if s.is_downed() or s.hidden_in != null:
					continue
				if s.pos.distance_to(pos) < radius + s.radius + 0.55:
					# a charge is one unparryable hit that throws the survivor aside
					var r = s.take_hit(self, true, Tuning.CHARGE_INSTANT_DOWN and is_main())
					mt.on_hit(s, self, r)
					var side := Vector2(-charge_dir.y, charge_dir.x)
					if side.dot(s.pos - pos) < 0.0:
						side = -side
					s.move_by((side * 0.6 + charge_dir * 0.8).normalized() * 1.6)
					charge_hit = true
					power_state = ""
					power_cd_until = mt.time + _cdm() * Tuning.CHARGE_COOLDOWN
					atk_state = "recover"
					atk_t = Tuning.CHARGE_HIT_RECOVER
					return
			# walls and structures
			var ahead := pos + charge_dir * (radius + 0.45)
			var tl := MapData.tile_of(ahead)
			var st := mt.structure_at(tl)
			if st != null and st.blocks_killer():
				if st.metal:
					stun(Tuning.CHARGE_METAL_STUN, "metal")
					mt.make_noise(pos, 20.0, "clang", self)
					power_state = ""
					power_cd_until = mt.time + _cdm() * Tuning.CHARGE_COOLDOWN
					return
				st.damage(9999.0, self)
				mt.make_noise(pos, 22.0, "smash", self)
			elif moved < Tuning.CHARGE_SPEED * dt * 0.3:
				# rammed a solid wall
				power_state = ""
				power_cd_until = mt.time + _cdm() * Tuning.CHARGE_COOLDOWN
				stun(Tuning.CHARGE_MISS_STUN, "miss")
				mt.make_noise(pos, 18.0, "thud", self)
				return
			if power_t <= 0.0:
				power_state = ""
				power_cd_until = mt.time + _cdm() * Tuning.CHARGE_COOLDOWN
				if not charge_hit:
					stun(Tuning.CHARGE_MISS_STUN, "miss")
		"tongue_fly":
			var step := Tuning.TONGUE_SPEED * dt
			var range_m = Tuning.TONGUE_RANGE * (0.5 if elite else 1.0) * (1.0 + meta("tongue"))
			var next := tongue_tip + tongue_dir * step
			# wall?
			var tl2 := MapData.tile_of(next)
			if mt.m.obstacle_top(tl2.x, tl2.y) > y + 1.0 or mt.struct_blocks_sight(tl2):
				_end_tongue()
				return
			tongue_tip = next
			for s in mt.living_survivors():
				if s.is_downed() or s.hidden_in != null or s.pinned_by != null or s.dropping():
					continue
				if s.pos.distance_to(tongue_tip) < s.radius + 0.45:
					tongue_victim = s
					pull_prev_d = INF
					pull_stall_t = 0.0
					s.pinned_by = self
					s.cancel_channel()
					power_state = "tongue_pull"
					mt.on_tongue(self, s)
					return
			if tongue_tip.distance_to(pos) >= range_m:
				_end_tongue()
		"tongue_pull":
			if tongue_victim == null or tongue_victim.pinned_by != self:
				_end_tongue()
				return
			tongue_tip = tongue_victim.pos
			if constrict_t >= 0.0:
				constrict_t -= dt
				if constrict_t <= 0.0:
					_finish_constrict()
					return
			else:
				# the tongue snaps if the pull is stuck on a corner or loses sight
				var dd := pos.distance_to(tongue_victim.pos)
				if dd > pull_prev_d - 0.05 * dt:
					pull_stall_t += dt
				else:
					pull_stall_t = 0.0
				pull_prev_d = dd
				if pull_stall_t > 1.0 or not mt.m.los(pos, y + 1.4, tongue_victim.pos, tongue_victim.y + 1.0):
					_end_tongue()
					return
			if is_main():
				spotted_until = maxf(spotted_until, mt.time + 1.0)
	_update_tongue_visual()


func tongue_arrived(s: Survivor) -> void:
	## Reeled in: the survivor is held (constricted) until freed or the hold ends.
	if constrict_t < 0.0:
		constrict_t = Tuning.TONGUE_CONSTRICT


func _finish_constrict() -> void:
	var s := tongue_victim
	constrict_t = -1.0
	if s != null and is_instance_valid(s) and s.pinned_by == self:
		if is_main():
			var res = s.take_hit(self, true)
			mt.on_hit(s, self, res)
		s.pinned_by = null
	_end_tongue()
	atk_state = "recover"
	atk_t = Tuning.TONGUE_RECOVER


func tongue_released() -> void:
	if power_state == "tongue_pull":
		_end_tongue()


func _end_tongue() -> void:
	if tongue_victim != null and tongue_victim.pinned_by == self:
		tongue_victim.pinned_by = null
	tongue_victim = null
	constrict_t = -1.0
	power_state = ""
	power_cd_until = mt.time + _cdm() * Tuning.TONGUE_COOLDOWN * (1.0 if is_main() else 2.0)
	if tongue_mesh:
		tongue_mesh.visible = false


func _update_tongue_visual() -> void:
	if tongue_mesh == null:
		return
	var active := power_state == "tongue_fly" or power_state == "tongue_pull"
	tongue_mesh.visible = active and shown
	if not active:
		return
	var a := Vector3(pos.x, y + eye_height() - 0.2, pos.y)
	var b := Vector3(tongue_tip.x, y + 1.0, tongue_tip.y)
	if tongue_victim != null:
		b = Vector3(tongue_victim.pos.x, tongue_victim.y + 1.1, tongue_victim.pos.y)
	var mid := (a + b) * 0.5
	var len := a.distance_to(b)
	tongue_mesh.global_position = mid
	if len > 0.01:
		var up := (b - a).normalized()
		var basis := Basis()
		var x_axis := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
		var z_axis := x_axis.cross(up).normalized()
		basis = Basis(x_axis, up, z_axis).scaled(Vector3(1, len, 1))
		tongue_mesh.global_transform = Transform3D(basis, mid)


func _tick_fatigue(dt: float) -> void:
	## Long chases tire killers out ("killers who rush face penalties").
	if husk or mt.time < tired_until:
		chase_t = 0.0
		return
	var chasing := false
	for s in mt.living_survivors():
		if not s.is_downed() and s.pos.distance_to(pos) < 14.0 and moved > 0.0:
			chasing = true
			break
	if chasing:
		chase_t += dt
		if chase_t >= Tuning.TIRE_AFTER + meta("k_fatigue"):
			chase_t = 0.0
			tired_until = mt.time + Tuning.TIRE_TIME
			mt.make_noise(pos, 12.0, "pant", self)
	else:
		chase_t = maxf(0.0, chase_t - dt * 2.0)


func tired() -> bool:
	return mt.time < tired_until


func _tick_spotting(dt: float) -> void:
	var seen := mt.lurker_seen(self)
	if seen:
		spot_meter += dt
		if spot_meter >= Tuning.LURKER_SPOT_TIME:
			if not spotted():
				mt.on_spotted(self)
			spotted_until = mt.time + Tuning.LURKER_SPOTTED_FOR
	else:
		spot_meter = maxf(0.0, spot_meter - dt * 0.5)


func update_visual(dt: float) -> void:
	super.update_visual(dt)
	if model_root == null:
		return
	# stunned killers slump; charging Brutes lean in
	if stunned() or held():
		model_root.rotation.z = sin(mt.time * 6.0) * 0.08
	else:
		model_root.rotation.z = 0.0
	if power_state == "charge" or power_state == "charge_windup":
		model_root.rotation.x = -0.35
	elif downed_pose == 0.0:
		model_root.rotation.x = 0.0
