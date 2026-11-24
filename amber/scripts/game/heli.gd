class_name Heli
extends Node3D
## The rescue helicopter for one duo: inbound -> (hover) -> landed -> departing.

var mt: Match
var base: Base
var state := "inbound"      # inbound, approach, hover, landed, departing, gone
var t := 0.0
var lz := Vector2.ZERO
var lz_h := 0.0
var hover_used := 0.0
var boarded: Array = []     # Slots
var model: Node3D
var spot: SpotLight3D
var from := Vector3.ZERO
var alt := 0.0


func setup(match_ref: Match, b: Base, landing: Vector2) -> void:
	mt = match_ref
	base = b
	lz = landing
	lz_h = mt.m.height_at(landing)
	t = Tuning.HELI_ARRIVAL
	var edge := Vector2(mt.m.w, mt.m.h) * Defs.TILE * 0.5
	var away := (lz - edge).normalized() if (lz - edge).length() > 1.0 else Vector2(1, 0)
	from = Vector3(lz.x + away.x * 160.0, 45.0, lz.y + away.y * 160.0)
	if mt.visuals:
		model = Models.make("helicopter")
		add_child(model)
		spot = SpotLight3D.new()
		spot.spot_range = 40.0
		spot.spot_angle = 22.0
		spot.light_energy = 6.0
		spot.light_color = Color(1.0, 0.96, 0.85)
		spot.rotation = Vector3(deg_to_rad(-90), 0, 0)
		spot.position = Vector3(0, 0.4, -2.0)
		spot.shadow_enabled = false
		add_child(spot)
	visible = false
	position = from


func time_left() -> float:
	return t if state == "inbound" or state == "approach" else 0.0


func killer_in_lz() -> bool:
	for k in mt.killers:
		if k.is_main() and k.released and k.pos.distance_to(lz) < Tuning.HELI_LZ_RADIUS:
			return true
	return false


func tick(dt: float) -> void:
	if model:
		var rotor := model.get_node_or_null("Rotor") as Node3D
		if rotor:
			rotor.rotation.y += dt * 28.0
		var tail := model.get_node_or_null("TailRotor") as Node3D
		if tail:
			tail.rotation.x += dt * 40.0
	match state:
		"inbound":
			if not mt.jammed():
				t -= dt
			if t <= 18.0:
				state = "approach"
				visible = true
				if mt.sfx:
					mt.sfx.loop3d(self, "heli", 6.0)
		"approach":
			if not mt.jammed():
				t -= dt
			var f := clampf(1.0 - t / 18.0, 0.0, 1.0)
			var target := Vector3(lz.x, lz_h + 9.0, lz.y)
			position = from.lerp(target, smoothstep(0.0, 1.0, f))
			_face(target - from)
			if t <= 0.0:
				if killer_in_lz() and hover_used < Tuning.HELI_MAX_HOVER:
					state = "hover"
					mt.feed_all("The helicopter is holding off — a killer is in the landing zone!", "danger")
				else:
					_land()
		"hover":
			hover_used += dt
			position = Vector3(lz.x, lz_h + 9.0 + sin(mt.time * 1.3) * 0.4, lz.y)
			if not killer_in_lz() or hover_used >= Tuning.HELI_MAX_HOVER:
				_land()
		"landed":
			t -= dt
			position.y = move_toward(position.y, lz_h, dt * 3.0)
			if t <= 0.0 or _all_aboard():
				_depart()
		"departing":
			t += dt
			position += Vector3(0, dt * 5.0, -dt * 14.0).rotated(Vector3.UP, rotation.y)
			if t > 12.0:
				state = "gone"
				visible = false


func _face(d: Vector3) -> void:
	if Vector2(d.x, d.z).length() > 0.1:
		rotation.y = atan2(-d.x, -d.z)


func _land() -> void:
	state = "landed"
	t = Tuning.HELI_BOARD_WINDOW
	# the searchlight blinds anyone waiting in the landing zone
	for k in mt.killers:
		if k.released and k.pos.distance_to(lz) < Tuning.HELI_LZ_RADIUS * 1.4:
			k.stun(Tuning.HELI_SEARCHLIGHT, "flash")
			if k.slot and k.slot.is_human and mt.hud:
				mt.hud.flash_screen()
	position = Vector3(lz.x, lz_h + 6.0, lz.y)
	mt.feed_to_duo(base.duo, "The helicopter has landed! Board within %d seconds!" % int(Tuning.HELI_BOARD_WINDOW), "good", 8.0)
	mt.feed_all("A helicopter has landed for %s duo." % base.duo.name, "info")


func _all_aboard() -> bool:
	return base.duo.living().is_empty() or (not boarded.is_empty() and _living_not_aboard().is_empty())


func _living_not_aboard() -> Array:
	var out: Array = []
	for s in base.duo.living():
		if not boarded.has(s):
			out.append(s)
	return out


func can_board(s: Survivor) -> bool:
	return state == "landed" and s.duo == base.duo and s.pos.distance_to(lz) < 4.5 and s.health != Defs.Health.DOWNED


func board(s: Survivor) -> void:
	boarded.append(s.slot)
	mt.on_boarded(s, self)


func _depart() -> void:
	state = "departing"
	t = 0.0
	mt.on_heli_departed(self)
