class_name BaseSys
extends RefCounted
## Bases, radio stations, helicopters, structures, traps, lockers and hatches.

var mt: Match


func _init(match_ref: Match) -> void:
	mt = match_ref


# ------------------------------------------------------------------------------
# Claiming and the radio

func claim(s: Survivor) -> void:
	var d := s.duo
	if d.base != null or not mt.base_site_ok(s.pos, d):
		return
	var b := Base.new()
	b.duo = d
	b.tile = MapData.tile_of(s.pos)
	b.pos = MapData.center_of(b.tile)
	d.base = b
	if mt.visuals:
		_build_station_node(b)
	mt.feed_to_duo(d, "Radio base set up. Bring parts here; the station builds in 3 stages.", "good", 6.0)
	mt.log_event("%s duo set up a base in the %s" % [d.name, Defs.ZONE_NAMES[mt.m.zone_at(b.pos)]])
	mt.nav.set_struct(b.tile, true, true)


func _build_station_node(b: Base) -> void:
	var n := Node3D.new()
	n.position = Vector3(b.pos.x, mt.m.height_at(b.pos), b.pos.y)
	mt.add_child(n)
	b.node = n
	var table := Models.make("station_base")
	table.name = "Table"
	n.add_child(table)
	var flag := Models.box(n, Vector3(0.05, 2.6, 0.05), Mats.flat(Color(0.3, 0.3, 0.3)), Vector3(0.8, 1.3, 0.5))
	flag.name = "Pole"
	var cloth := Models.box(n, Vector3(0.6, 0.4, 0.03), Mats.flat(b.duo.color, 0.6), Vector3(1.12, 2.35, 0.5))
	cloth.name = "Flag"
	var lbl := Label3D.new()
	lbl.text = "%s duo — radio" % b.duo.name
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 28
	lbl.fixed_size = true
	lbl.pixel_size = 0.0011
	lbl.outline_size = 8
	lbl.modulate = b.duo.color
	lbl.position = Vector3(0, 3.1, 0)
	lbl.name = "Label"
	n.add_child(lbl)
	var glow := OmniLight3D.new()
	glow.light_color = b.duo.color.lerp(Color.WHITE, 0.5)
	glow.omni_range = 5.0
	glow.light_energy = 0.7
	glow.position = Vector3(0, 1.6, 0)
	n.add_child(glow)
	_refresh_station(b)


func _refresh_station(b: Base) -> void:
	if b.node == null:
		return
	var names := ["Antenna", "Generator", "Transmitter"]
	var slots := ["station_antenna", "station_generator", "station_transmitter"]
	var offs := [Vector3(-1.4, 0, -0.6), Vector3(1.3, 0, -0.9), Vector3(0, 0, 1.2)]
	for i in 3:
		var have := b.node.get_node_or_null(names[i])
		if i < b.stage and have == null:
			var part := Models.make(slots[i])
			part.name = names[i]
			part.position = offs[i]
			b.node.add_child(part)
			if i == 1 and mt.sfx:
				mt.sfx.loop3d(part, "generator", -10.0)
	var lbl := b.node.get_node_or_null("Label") as Label3D
	if lbl:
		var t := "%s duo — %s" % [b.duo.name, "radio" if b.stage < 3 else "RADIO READY"]
		if b.broken:
			t += " (BROKEN)"
		lbl.text = t


func auto_deposit(s: Survivor) -> void:
	var b := s.duo.base
	if b == null or s.parts.is_empty() or s.is_downed():
		return
	if s.pos.distance_to(b.pos) > Tuning.BASE_RADIUS * Defs.TILE * 0.6:
		return
	for p in s.parts:
		b.storage.append(p)
		mt.feed_to_duo(s.duo, "%s stored a %s at the radio." % [s.slot.name, Defs.PART_NAMES[p]], "info")
	s.parts.clear()


func complete_stage(b: Base, by: Actor) -> void:
	for p in Defs.STAGE_PARTS[b.stage]:
		b.storage.erase(p)
	var done := b.stage
	b.stage += 1
	b.progress = 0.0
	b.paid = false
	mt.nest.add(Tuning.NEST_STAGE[done], "radio progress")
	mt.feed_all("%s duo built their %s (%d/3)." % [b.duo.name, Defs.STAGE_NAMES[done], b.stage], "info")
	mt.log_event("%s duo completed %s" % [b.duo.name, Defs.STAGE_NAMES[done]])
	b.reveal_until = mt.time + Tuning.REVEAL_ON_STAGE
	if b.stage == 2:
		mt.make_noise(b.pos, Tuning.NOISE_GENERATOR, "generator", null)
		mt.feed_to_duo(b.duo, "The generator is running. It's loud — killers nearby will hear it.", "danger", 7.0)
	if b.stage == 3:
		mt.feed_to_duo(b.duo, "The transmitter is ready. Call the helicopter at the station!", "good", 8.0)
	_refresh_station(b)


func damage_station(b: Base, amount: float, by: Killer) -> void:
	if b.stage == 0 or b.broken or mt.time < b.lockdown_until:
		return
	b.hp -= amount * (1.0 + (by.meta("k_smash") if by != null else 0.0))
	b.last_damage_time = mt.time
	b.reveal_until = maxf(b.reveal_until, mt.time + 20.0)
	mt.nest.add(amount * Tuning.NEST_STATION_DAMAGE, "base damage")
	mt.feed_to_duo(b.duo, "The radio station is being smashed!", "danger", 5.0)
	if b.hp <= 0.0:
		b.hp = 0.0
		b.broken = true
		b.repair_progress = 0.0
		b.progress = 0.0
		mt.feed_to_duo(b.duo, "Your radio station is BROKEN. Repair it before you can build or call.", "danger", 8.0)
		mt.log_event("%s duo's station broken by %s" % [b.duo.name, by.slot.name if by.slot else "a killer"])
		_refresh_station(b)


func finish_repair(b: Base, by: Actor) -> void:
	var cost := b.repair_cost()
	b.duo.money = maxi(0, b.duo.money - cost)
	b.broken = false
	b.hp = Tuning.STATION_HP
	b.repair_progress = 0.0
	mt.feed_to_duo(b.duo, "Station repaired.", "good")
	_refresh_station(b)


func call_heli(b: Base, by: Survivor) -> void:
	if b.stage < 3 or b.broken:
		return
	if b.heli != null and b.heli.state != "gone":
		return
	b.heli_called = true
	b.heli_calls += 1
	var h := Heli.new()
	mt.add_child(h)
	h.setup(mt, b, _landing_spot(b))
	b.heli = h
	b.revealed = true
	mt.nest.add(Tuning.NEST_HELI, "helicopter called")
	mt.feed_all("A HELICOPTER HAS BEEN CALLED by %s duo! It lands in %d seconds." % [b.duo.name, int(Tuning.HELI_ARRIVAL)], "alert", 8.0)
	mt.log_event("%s duo called a helicopter" % b.duo.name)
	mt.make_noise(b.pos, 999.0, "heli", null)


func _landing_spot(b: Base) -> Vector2:
	# the most open nearby tile
	var best := b.pos
	var best_score := -1
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var tl := b.tile + Vector2i(dx, dy)
			if not mt.nav.is_open(tl, true) or tl == b.tile:
				continue
			var open := 0
			for ey in range(-1, 2):
				for ex in range(-1, 2):
					if mt.nav.is_open(tl + Vector2i(ex, ey), false):
						open += 1
			var score := open * 10 - absi(dx) - absi(dy)
			if score > best_score:
				best_score = score
				best = MapData.center_of(tl)
	return best


func tick(dt: float) -> void:
	for d in mt.duos:
		var b: Base = d.base
		if b == null:
			continue
		if b.heli != null:
			b.heli.tick(dt)
		if b.stage >= 2 and not b.broken and d.active():
			b.gen_noise_t -= dt
			if b.gen_noise_t <= 0.0:
				b.gen_noise_t = Tuning.GENERATOR_NOISE_EVERY
				mt.make_noise(b.pos, Tuning.NOISE_GENERATOR, "generator", null)
	for st in mt.structure_list.duplicate():
		if is_instance_valid(st):
			st.tick(dt)


# ------------------------------------------------------------------------------
# Betrayal

func steal(s: Survivor, b: Base) -> void:
	if b.storage.is_empty() or s.carry_space() <= 0:
		return
	# take the part the thief's own radio needs most, else anything
	var want := s.duo.base.all_missing() if s.duo.base != null else []
	var pick: int = b.storage[0]
	for p in b.storage:
		if want.has(p):
			pick = p
			break
	b.storage.erase(pick)
	s.parts.append(pick)
	mt.feed_to_duo(b.duo, "Someone stole a %s from your base!" % Defs.PART_NAMES[pick], "danger", 6.0)
	mt.log_event("%s stole a %s from %s duo" % [s.slot.name, Defs.PART_NAMES[pick], b.duo.name])
	if _witnessed(s, b):
		mark_thief(s)


func _witnessed(s: Survivor, b: Base) -> bool:
	for o in mt.living_survivors():
		if o == s or o.duo == s.duo:
			continue
		if o.pos.distance_to(s.pos) < Tuning.THIEF_SEEN_RANGE and mt.m.los(o.pos, o.y + o.eye_height(), s.pos, s.y + 1.0):
			return true
	return b.duo.living().size() > 0 and randf() < 0.25


func mark_thief(s: Survivor) -> void:
	if s.slot.thief:
		return
	s.slot.thief = true
	mt.feed_all("%s was caught stealing — they're marked as a THIEF." % s.slot.name, "danger", 7.0)


# ------------------------------------------------------------------------------
# Structures

func can_place(s: Survivor, kind: int, tl: Vector2i) -> String:
	var b := s.duo.base
	var is_trap := kind == Defs.B.SNARE or kind == Defs.B.FLASH
	if not is_trap:
		if b == null:
			return "Set up a base first"
		if MapData.center_of(tl).distance_to(b.pos) > b.radius_m() + 1.0:
			return "Too far from your radio"
	if mt.structure_at(tl) != null:
		return "Something is already there"
	var tt := mt.m.tv(tl)
	if kind == Defs.B.HATCH:
		if b.hatch != null:
			return "You already placed your escape hatch"
		if tt != Defs.T.WALL or mt.m.style(tl.x, tl.y) == Defs.S.CLIFF or mt.m.style(tl.x, tl.y) == Defs.S.QUARANTINE:
			return "Place the hatch on a wall or rock face"
		var m := mt.m
		var lr := m.walkable(tl.x - 1, tl.y, false) and m.walkable(tl.x + 1, tl.y, false)
		var ud := m.walkable(tl.x, tl.y - 1, false) and m.walkable(tl.x, tl.y + 1, false)
		if not (lr or ud):
			return "The hatch must lead somewhere (open ground on both sides)"
		return ""
	if tt != Defs.T.FLOOR:
		return "Needs open ground"
	if tl == b.tile if b != null else false:
		return "That's your radio"
	if not is_trap:
		for a in mt.all_actors():
			if MapData.tile_of(a.pos) == tl:
				return "Someone is standing there"
	var def: Dictionary = Tuning.BUILD[kind]
	if is_trap:
		var idx := 0 if kind == Defs.B.SNARE else 1
		if s.traps[idx] <= 0:
			return "No %s left" % Defs.TRAP_NAMES[idx].to_lower()
		return ""
	if s.duo.scrap < def["scrap"]:
		return "Needs %d scrap" % def["scrap"]
	if s.duo.money < def["money"]:
		return "Needs $%d" % def["money"]
	return ""


func place(s: Survivor, kind: int, tl: Vector2i) -> Structure:
	if can_place(s, kind, tl) != "":
		return null
	var def: Dictionary = Tuning.BUILD[kind]
	var is_trap := kind == Defs.B.SNARE or kind == Defs.B.FLASH
	if is_trap:
		s.traps[0 if kind == Defs.B.SNARE else 1] -= 1
	else:
		s.duo.scrap -= def["scrap"]
		s.duo.money -= def["money"]
	var st := Structure.new()
	mt.add_child(st)
	st.setup(mt, kind, tl, s.duo.base if not is_trap else null, s.duo)
	if is_trap:
		st.base = null
	mt.add_structure(st)
	if kind == Defs.B.HATCH:
		s.duo.base.hatch = st
		mt.m.set_t(tl.x, tl.y, Defs.T.GAP)
		mt.nav.refresh_tile(tl)
		if mt.view:
			mt.view.update_tile(tl)
	if s.role == Defs.Role.ENGINEER and not is_trap:
		mt.make_noise(s.pos, Tuning.NOISE_BUILD, "build", s)
	return st


func upgrade(s: Survivor, st: Structure, metal: bool) -> String:
	if s.role != Defs.Role.ENGINEER:
		return "Only Engineers can upgrade walls"
	if st.kind != Defs.B.WALL and st.kind != Defs.B.DOOR:
		return "Only walls and doors can be upgraded"
	var cost: Dictionary = Tuning.METAL_UPGRADE if metal else Tuning.SPIKE_UPGRADE
	if (metal and st.metal) or (not metal and st.spiked):
		return "Already upgraded"
	if s.duo.scrap < cost["scrap"] or s.duo.money < cost["money"]:
		return "Needs %d scrap and $%d" % [cost["scrap"], cost["money"]]
	s.duo.scrap -= cost["scrap"]
	s.duo.money -= cost["money"]
	if metal:
		st.metal = true
		st.hp = Tuning.METAL_HP
		st.max_hp = Tuning.METAL_HP
	else:
		st.spiked = true
	if mt.visuals:
		st._rebuild_model()
	return ""


func quick_barricade(s: Survivor) -> bool:
	## Engineer ability: drop a barricade on the tile in front.
	if s.role != Defs.Role.ENGINEER or mt.time < s.ability_cd_until:
		return false
	var tl := MapData.tile_of(s.pos + s.forward2() * 1.6)
	if mt.m.tv(tl) != Defs.T.FLOOR or mt.structure_at(tl) != null:
		return false
	for a in mt.all_actors():
		if MapData.tile_of(a.pos) == tl:
			return false
	var st := Structure.new()
	mt.add_child(st)
	st.setup(mt, Defs.B.BARRICADE, tl, null, s.duo)
	st.expires = mt.time + Tuning.BARRICADE_LIFETIME
	mt.add_structure(st)
	s.ability_cd_until = mt.time + Tuning.ENGINEER_BARRICADE_COOLDOWN * (1.0 - s.meta("ability_cd"))
	mt.make_noise(s.pos, 14.0, "build", s)
	return true


func lockdown(s: Survivor) -> bool:
	var b := s.duo.base
	if b == null or s.duo.lockdown_used:
		return false
	s.duo.lockdown_used = true
	b.lockdown_until = mt.time + Tuning.LOCKDOWN_TIME
	for st in b.structures:
		mt.nav.set_struct(st.tile, st.blocks_survivor(), true)
	if b.hatch != null:
		mt.nav.set_struct(b.hatch.tile, true, true)
	mt.feed_to_duo(s.duo, "LOCKDOWN: base sealed for %d seconds." % int(Tuning.LOCKDOWN_TIME), "good", 6.0)
	mt.make_noise(b.pos, 30.0, "lockdown", s)
	return true


func hide(s: Survivor, st: Structure) -> void:
	if st.occupant != null:
		return
	st.occupant = s
	s.hidden_in = st
	s.pos = st.pos
	s.set_shown(false)


func unhide(s: Survivor) -> void:
	var st := s.hidden_in
	if st == null:
		return
	st.occupant = null
	s.hidden_in = null
	s.set_shown(true)
	# step out in front of the locker
	for d in [Vector2(0, 1.4), Vector2(1.4, 0), Vector2(-1.4, 0), Vector2(0, -1.4)]:
		var p: Vector2 = st.pos + d
		var tl := MapData.tile_of(p)
		if mt.nav.is_open(tl, true):
			s.pos = MapData.center_of(tl)
			break


func search_locker(k: Killer, st: Structure) -> void:
	if st.occupant != null:
		var s := st.occupant
		unhide(s)
		var res := s.take_hit(k, true)
		mt.on_hit(s, k, res)
		mt.feed_all("%s was dragged out of a locker!" % s.slot.name, "danger")


func seal_hatch(k: Killer, st: Structure) -> void:
	if k.route_charges <= 0:
		return
	k.route_charges -= 1
	mt.m.set_t(st.tile.x, st.tile.y, Defs.T.SEALED)
	mt.nav.refresh_tile(st.tile)
	if mt.view:
		mt.view.update_tile(st.tile)
	if st.base != null:
		st.base.hatch = null
	mt.remove_structure(st, false)
	mt.feed_all("A killer sealed an escape hatch.", "danger")
