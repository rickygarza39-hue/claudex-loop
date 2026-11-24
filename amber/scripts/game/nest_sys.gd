class_name NestSys
extends RefCounted
## The killers' shared Nest: fills from catches, base damage and survivor radio
## progress; when full the killers trigger their chosen event card.

var mt: Match
var meter := 0.0
var card := Defs.Card.PULSE
var ready := false
var cooldown_until := 0.0
var blackout_until := -1.0
var pulse_until := -1.0
var jam_until := -1.0
var fired := 0
var node: Node3D
var light: OmniLight3D


func _init(match_ref: Match, c: int) -> void:
	mt = match_ref
	card = c
	if mt.visuals:
		node = Models.make("nest")
		var p := MapData.center_of(mt.m.nest)
		node.position = Vector3(p.x, mt.m.height_at(p), p.y)
		mt.add_child(node)
		light = OmniLight3D.new()
		light.light_color = Defs.AMBER
		light.omni_range = 10.0
		light.light_energy = 1.0
		light.position = Vector3(0, 2.0, 0)
		node.add_child(light)


func add(v: float, _why: String) -> void:
	if ready:
		return
	var mult := Tuning.NEST_FINAL_PUSH_MULT if mt.time >= Tuning.FINAL_PUSH_AT else 1.0
	meter = minf(Tuning.NEST_MAX, meter + v * mult)


func tick(dt: float) -> void:
	if mt.time >= cooldown_until and not ready:
		add(Tuning.NEST_PASSIVE * dt, "passive")
		if meter >= Tuning.NEST_MAX:
			ready = true
			mt.feed_all("The Nest is glowing… the killers can unleash %s." % Defs.CARD_NAMES[card].to_upper(), "danger", 6.0)
			mt.make_noise(MapData.center_of(mt.m.nest), 999.0, "nest", null)
	if node:
		var heart := node.find_child("Heart", true, false) as Node3D
		var pulse := 1.0 + (0.12 * sin(mt.time * (5.0 if ready else 1.5)))
		if heart:
			heart.scale = Vector3.ONE * pulse
		light.light_energy = (3.5 if ready else 1.0) * pulse
	if mt.view:
		mt.view.set_blackout(1.0 if mt.time < blackout_until else move_toward(mt.view.blackout, 0.0, dt))


func can_trigger() -> bool:
	return ready and mt.time >= cooldown_until


func trigger(by: Killer, target: Base = null) -> bool:
	if not can_trigger():
		return false
	ready = false
	meter = 0.0
	fired += 1
	cooldown_until = mt.time + Tuning.NEST_COOLDOWN
	for k in mt.killers:
		if k.is_main():
			k.route_charges = mini(k.route_charges + Tuning.ROUTE_REFILL_ON_NEST, Tuning.ROUTE_CHARGES + 2)
	match card:
		Defs.Card.BLACKOUT:
			blackout_until = mt.time + Tuning.BLACKOUT_TIME
			mt.feed_all("BLACKOUT! The lights die across town.", "alert", 6.0)
		Defs.Card.PULSE:
			pulse_until = mt.time + Tuning.PULSE_TIME
			for s in mt.living_survivors():
				s.revealed_until = pulse_until
			mt.feed_all("PULSE! Every survivor has been revealed to the killers.", "alert", 6.0)
		Defs.Card.SWARM:
			var b := target if target != null else mt.best_swarm_target()
			if b != null:
				mt.spawn_swarm(b)
				mt.feed_all("SWARM! Infected are pouring toward %s duo's base." % b.duo.name, "alert", 6.0)
			else:
				mt.feed_all("The Nest howls, but finds no base to swarm.", "info")
		Defs.Card.JAM:
			jam_until = mt.time + Tuning.JAM_TIME
			mt.feed_all("SIGNAL JAM! All radio progress is frozen for %d seconds." % int(Tuning.JAM_TIME), "alert", 6.0)
	mt.log_event("Nest event %s triggered by %s" % [Defs.CARD_NAMES[card], by.slot.name if by and by.slot else "killers"])
	return true
