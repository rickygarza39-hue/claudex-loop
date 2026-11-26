class_name Structure
extends Node3D
## Survivor-built base pieces and traps.

var mt: Match
var kind := Defs.B.WALL
var tile := Vector2i.ZERO
var pos := Vector2.ZERO
var base: Base = null
var owner_duo: Duo = null
var hp := 100.0
var max_hp := 100.0
var metal := false
var spiked := false
var found := false        # escape hatch / traps: known to killers
var armed := true
var occupant: Survivor = null
var decoy_t := 0.0
var alarm_cd := 0.0
var built := 1.0          # 0..1 while under construction
var expires := -1.0
var model: Node3D
var light: Light3D
var cover: MeshInstance3D  # hides an unfound hatch from killer players


func setup(match_ref: Match, k: int, tl: Vector2i, b: Base, d: Duo) -> void:
	mt = match_ref
	kind = k
	tile = tl
	pos = MapData.center_of(tl)
	base = b
	owner_duo = d
	var def: Dictionary = Tuning.BUILD[k]
	hp = def["hp"]
	max_hp = hp
	position = Vector3(pos.x, mt.m.height_at(pos), pos.y)
	if mt.visuals:
		_rebuild_model()


func _rebuild_model() -> void:
	if model:
		model.queue_free()
	var slot := ""
	match kind:
		Defs.B.WALL: slot = "build_wall"
		Defs.B.DOOR: slot = "build_door"
		Defs.B.BARRICADE: slot = "build_barricade"
		Defs.B.ALARM: slot = "build_alarm"
		Defs.B.FLOODLIGHT: slot = "build_floodlight"
		Defs.B.DECOY: slot = "build_decoy"
		Defs.B.LOCKER: slot = "build_locker"
		Defs.B.SNARE: slot = "trap_snare"
		Defs.B.FLASH: slot = "trap_flash"
		Defs.B.HATCH: slot = "build_hatch"
	model = Models.make(slot, {"metal": metal, "spiked": spiked})
	add_child(model)
	# orient walls and doors across the passage
	if kind in [Defs.B.WALL, Defs.B.DOOR, Defs.B.BARRICADE, Defs.B.HATCH]:
		model.rotation.y = PI * 0.5 if _runs_along_z() else 0.0
	if kind == Defs.B.FLOODLIGHT and light == null:
		var s := SpotLight3D.new()
		s.spot_range = Tuning.FLOODLIGHT_RADIUS * 1.6
		s.spot_angle = 55.0
		s.light_energy = 3.0
		s.light_color = Color(1.0, 0.95, 0.85)
		s.position = Vector3(0, 3.0, 0)
		s.rotation = Vector3(deg_to_rad(-60), 0, 0)
		add_child(s)
		light = s
	if kind == Defs.B.HATCH:
		cover = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.02, 3.62, 2.02)
		cover.mesh = bm
		cover.material_override = Mats.get_mat("rock" if mt.m.zone(tile.x, tile.y) in [Defs.Z.MINE, Defs.Z.LAB] else "wood")
		cover.position = Vector3(0, 1.8, 0)
		cover.visible = false
		add_child(cover)


func _runs_along_z() -> bool:
	# a wall piece spans the tile; turn it to line up with neighbouring solids
	var m := mt.m
	var lr := m.is_solid_static(tile.x - 1, tile.y) or m.is_solid_static(tile.x + 1, tile.y) \
		or mt.structure_at(tile + Vector2i(1, 0)) != null or mt.structure_at(tile + Vector2i(-1, 0)) != null
	var ud := m.is_solid_static(tile.x, tile.y - 1) or m.is_solid_static(tile.x, tile.y + 1) \
		or mt.structure_at(tile + Vector2i(0, 1)) != null or mt.structure_at(tile + Vector2i(0, -1)) != null
	return ud and not lr


func is_trap() -> bool:
	return kind == Defs.B.SNARE or kind == Defs.B.FLASH


func blocks_survivor() -> bool:
	return kind == Defs.B.WALL or kind == Defs.B.BARRICADE or kind == Defs.B.LOCKER


func blocks_killer() -> bool:
	if base != null and mt.time < base.lockdown_until and kind in [Defs.B.DOOR, Defs.B.WALL, Defs.B.BARRICADE]:
		return true
	return kind == Defs.B.WALL or kind == Defs.B.DOOR or kind == Defs.B.BARRICADE or kind == Defs.B.LOCKER


func blocks_sight_h() -> float:
	match kind:
		Defs.B.WALL, Defs.B.DOOR: return 3.0
		Defs.B.LOCKER: return 2.0
		Defs.B.BARRICADE: return 1.3
	return 0.0


func invulnerable() -> bool:
	return base != null and mt.time < base.lockdown_until


func damage(amount: float, by: Killer) -> void:
	if invulnerable() or kind == Defs.B.HATCH:
		return
	hp -= amount * (1.0 + (by.meta("k_smash") if by != null else 0.0))
	if spiked and by != null and kind == Defs.B.WALL:
		by.stun(Tuning.SPIKE_STUN, "spikes")
	mt.make_noise(pos, 18.0, "smash", by)
	if base != null:
		base.last_damage_time = mt.time
		mt.feed_to_duo(base.duo, "Your %s is under attack!" % Defs.BUILD_NAMES[kind].to_lower(), "danger", 6.0)
	if hp <= 0.0:
		mt.remove_structure(self, true)


func tick(dt: float) -> void:
	alarm_cd -= dt
	if expires > 0.0 and mt.time >= expires:
		mt.remove_structure(self, false)
		return
	match kind:
		Defs.B.ALARM:
			if alarm_cd <= 0.0:
				for k in mt.killers:
					if k.released and k.pos.distance_to(pos) < Tuning.ALARM_RADIUS:
						alarm_cd = 6.0
						mt.on_alarm(self, k)
						break
		Defs.B.DECOY:
			decoy_t -= dt
			if decoy_t <= 0.0:
				decoy_t = Tuning.DECOY_INTERVAL
				mt.make_noise(pos, 26.0, "decoy", null)
		Defs.B.SNARE, Defs.B.FLASH:
			if not armed:
				return
			var r := 0.9 if kind == Defs.B.SNARE else 2.0
			for k in mt.killers:
				if k.released and not k.husk and k.pos.distance_to(pos) < r + k.radius:
					if mt.time < k.trap_immune_until:
						continue
					if k.perk("Traps") > 0:
						# elite trap-sense: steps around it and wrecks it instead
						mt.remove_structure(self, false)
						return
					armed = false
					mt.on_trap(self, k)
					return
