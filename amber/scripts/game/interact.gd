class_name Interact
extends RefCounted
## Context interactions ("hold E") for survivors and killers. The player picks the
## option in front of them; bots ask for a specific option id + target.

var mt: Match

const REACH := 2.1


func _init(match_ref: Match) -> void:
	mt = match_ref


func _opt(id: String, label: String, at: Vector2, hold: float, target = null, blocked: String = "", prio: int = 0) -> Dictionary:
	return {"id": id, "label": label, "pos": at, "time": hold, "target": target, "blocked": blocked, "prio": prio}


# ------------------------------------------------------------------------------
# Option lists

func options(a: Actor) -> Array:
	if a is Survivor:
		return _survivor_options(a as Survivor)
	return _killer_options(a as Killer)


func _survivor_options(s: Survivor) -> Array:
	var out: Array = []
	if s.slot.outcome != "":
		return out
	var tm := mt.time
	if s.hidden_in != null:
		out.append(_opt("unhide", "Leave the locker", s.hidden_in.pos, 0.0, s.hidden_in, "", 10))
		return out
	if s.is_downed():
		if s.cure > 0:
			out.append(_opt("cure", "Use your cure on yourself", s.pos, Tuning.CURE_USE_TIME / (1.0 + s.meta("heal")), s, "", 10))
		return out
	if s.pinned_by != null or tm < s.dazed_until:
		return out
	# items
	for it in mt.items_near(s.pos, REACH):
		var blocked := ""
		if it.kind == Defs.Item.PART and s.carry_space() <= 0:
			blocked = "Hands full (2 parts)"
		if it.kind == Defs.Item.FLARE and s.flare > 0:
			blocked = "Already carrying a flare gun"
		out.append(_opt("pickup", "Pick up " + it.title(), it.pos, 0.0, it, blocked, 5))
	# quarantine cells
	for c in mt.cells:
		if c["open"]:
			continue
		var door_c := MapData.center_of(c["door"])
		if c["worse"]:
			for li in c["levers"].size():
				var lp := MapData.center_of(c["levers"][li])
				if s.pos.distance_to(lp) < 1.9:
					out.append(_opt("lever", "Hold the lever (both levers together)", lp, 9999.0, {"cell": c, "lever": li}, "", 9))
		elif s.pos.distance_to(door_c) < 2.3:
			out.append(_opt("cell", "Pick the cell lock", door_c, 9999.0, c, "", 9))
	# own base
	var b := s.duo.base
	if b == null:
		if mt.base_site_ok(s.pos, s.duo):
			out.append(_opt("claim", "Set up your radio base here", s.pos, 2.5, null, "", 1))
	else:
		var d := s.pos.distance_to(b.pos)
		if d < REACH + 0.4:
			if b.broken:
				var cost := b.repair_cost()
				var blocked2 := "" if s.duo.money >= cost else "Need $%d to repair" % cost
				out.append(_opt("repair", "Repair the station ($%d)" % cost, b.pos, Tuning.REPAIR_TIME / mt.build_mult(s), b, blocked2, 8))
			elif b.stage < 3:
				var miss := b.missing_parts()
				var blocked3 := ""
				if not miss.is_empty():
					var names: Array = []
					for p in miss:
						names.append(Defs.PART_NAMES[p])
					blocked3 = "Needs: " + ", ".join(names)
				elif not b.paid and s.duo.money < b.next_cost():
					blocked3 = "Needs $%d (you have $%d)" % [b.next_cost(), s.duo.money]
				elif mt.jammed():
					blocked3 = "Signal jammed!"
				var lbl := "Build the %s" % Defs.STAGE_NAMES[b.stage]
				if not b.paid and b.next_cost() > 0:
					lbl += " ($%d)" % b.next_cost()
				out.append(_opt("build", lbl, b.pos, Tuning.STAGE_BUILD_TIME[b.stage] / mt.build_mult(s), b, blocked3, 8))
			elif not b.heli_called or (b.heli != null and b.heli.state == "gone" and s.duo.active()):
				out.append(_opt("call", "Call the helicopter", b.pos, 1.0, b, "", 9))
		if b.heli != null and b.heli.can_board(s):
			out.append(_opt("board", "BOARD THE HELICOPTER", b.heli.lz, 0.0, b.heli, "", 20))
	# other duos' stations: steal stored parts
	for od in mt.duos:
		if od == s.duo or od.base == null:
			continue
		if s.pos.distance_to(od.base.pos) < REACH + 0.4:
			var blocked4 := "" if not od.base.storage.is_empty() else "Nothing stored to steal"
			if blocked4 == "" and s.carry_space() <= 0:
				blocked4 = "Hands full"
			out.append(_opt("steal", "Steal a stored part from %s duo" % od.name, od.base.pos, Tuning.STEAL_TIME, od.base, blocked4, 2))
	# other survivors
	for o in mt.living_survivors():
		if o == s:
			continue
		var dd := s.pos.distance_to(o.pos)
		if o.pinned_by != null and dd < 2.4:
			out.append(_opt("break_tongue", "Break the tongue!", o.pos, Tuning.TONGUE_BREAK_TIME, o, "", 15))
			continue
		if dd > REACH:
			continue
		if o.is_downed():
			if s.role == Defs.Role.MEDIC and o.duo == s.duo and not s.revive_used:
				out.append(_opt("revive", "Revive your partner (once per match)", o.pos, Tuning.REVIVE_TIME / (1.0 + s.meta("heal")), o, "", 12))
			if s.cure > 0:
				out.append(_opt("cure", "Use your cure on %s" % o.slot.name, o.pos, Tuning.CURE_USE_TIME / (1.0 + s.meta("heal")), o, "", 11))
			elif o.duo == s.duo:
				out.append(_opt("none", "Partner downed — needs a cure or a Medic", o.pos, 0.0, o, "No cure", 0))
		elif o.health == Defs.Health.WOUNDED and o.channel.is_empty():
			var ht := Tuning.MEDIC_HEAL_TIME if s.role == Defs.Role.MEDIC else Tuning.HEAL_TIME
			out.append(_opt("heal", "Heal %s" % o.slot.name, o.pos, ht / (1.0 + s.meta("heal")), o, "", 7))
	if s.role == Defs.Role.MEDIC and s.health == Defs.Health.WOUNDED:
		out.append(_opt("self_heal", "Patch yourself up", s.pos, Tuning.MEDIC_SELF_HEAL_TIME / (1.0 + s.meta("heal")), s, "", 1))
	# lockers
	for st in mt.structures_near(s.pos, 1.8):
		if st.kind == Defs.B.LOCKER and st.occupant == null:
			out.append(_opt("hide", "Hide in the locker", st.pos, 0.6, st, "", 4))
	return out


func _killer_options(k: Killer) -> Array:
	var out: Array = []
	if not k.released or k.stunned() or k.held():
		return out
	for s in mt.living_survivors():
		if s.is_downed() and s.pos.distance_to(k.pos) < 2.0:
			var blocked := ""
			if k.elite and not Tuning.ELITES_CAN_CATCH:
				blocked = "Only main killers can catch"
			if k.husk:
				blocked = "Husks can't catch"
			out.append(_opt("catch", "Catch %s" % s.slot.name, s.pos, Tuning.CATCH_TIME / (1.0 + k.meta("k_catch")), s, blocked, 10))
	var here := MapData.tile_of(k.pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var tl := here + Vector2i(dx, dy)
			var tt := mt.m.tv(tl)
			var c := MapData.center_of(tl)
			if k.pos.distance_to(c) > 2.2:
				continue
			if tt == Defs.T.BOARDS:
				out.append(_opt("smash", "Smash the boards", c, Tuning.SMASH_TIME, tl, "", 5))
			elif tt == Defs.T.CELL_DOOR:
				out.append(_opt("smash", "Smash the cell door", c, Tuning.SMASH_TIME, tl, "", 5))
	for st in mt.structures_near(k.pos, 2.0):
		if st.kind == Defs.B.LOCKER:
			out.append(_opt("search", "Search the locker", st.pos, 1.0, st, "", 6))
		if st.kind == Defs.B.HATCH and st.found and k.route_charges > 0:
			out.append(_opt("seal_hatch", "Seal the escape hatch (1 route charge)", st.pos, 1.5, st, "", 6))
	return out


## The option the player is looking at (or the highest-priority one in reach).
func best_for_player(a: Actor) -> Dictionary:
	var opts := options(a)
	var best: Dictionary = {}
	var best_score := -INF
	var fwd := a.forward2()
	for o in opts:
		var d: Vector2 = o["pos"] - a.pos
		var ang := 0.0 if d.length() < 0.4 else absf(fwd.angle_to(d))
		if ang > 1.4 and d.length() > 0.8:
			continue
		var score: float = o["prio"] * 2.0 - ang * 3.0 - d.length()
		if o["blocked"] != "":
			score -= 4.0
		if score > best_score:
			best_score = score
			best = o
	return best


func find(a: Actor, id: String, target = null) -> Dictionary:
	for o in options(a):
		if o["id"] != id:
			continue
		if typeof(target) == TYPE_NIL or (typeof(o["target"]) == typeof(target) and o["target"] == target):
			return o
	return {}


# ------------------------------------------------------------------------------
# Running interactions

func _channel_of(a: Actor) -> Dictionary:
	return a.channel


func begin(a: Actor, o: Dictionary) -> void:
	if o.is_empty() or o["blocked"] != "":
		return
	if o["time"] <= 0.0:
		_finish(a, o)
		return
	if not a.channel.is_empty() and a.channel["id"] == o["id"] and typeof(a.channel["target"]) == typeof(o["target"]) and a.channel["target"] == o["target"]:
		return
	var ch := o.duplicate()
	ch["progress"] = 0.0
	a.channel = ch
	_on_begin(a, ch)


## Called every frame while the actor keeps holding interact.
func hold(a: Actor, dt: float) -> void:
	var ch: Dictionary = a.channel
	if ch.is_empty():
		return
	# still valid?
	var fresh := find(a, ch["id"], ch["target"])
	if fresh.is_empty() or fresh["blocked"] != "":
		on_cancel(a, ch)
		a.channel = {}
		return
	match ch["id"]:
		"cell":
			var c: Dictionary = ch["target"]
			c["progress"] += dt * (1.0 + a.meta("pick"))
			mt.make_noise(a.pos, 8.0, "lock", a, 0.6)
			if c["progress"] >= Tuning.CELL_PICK_TIME:
				mt.open_cell(c)
				a.channel = {}
			return
		"lever":
			var cl: Dictionary = ch["target"]["cell"]
			cl["held_" + str(ch["target"]["lever"])] = mt.time
			var both = mt.time - cl.get("held_0", -10.0) < 0.25 and mt.time - cl.get("held_1", -10.0) < 0.25
			if both:
				cl["progress"] += dt
			if cl["progress"] >= Tuning.WORSE_LEVER_TIME:
				mt.open_cell(cl)
				a.channel = {}
			return
		"build":
			var b: Base = ch["target"]
			if not b.paid:
				var bd: Duo = (a as Survivor).duo
				if bd.money < b.next_cost():
					on_cancel(a, ch)
					a.channel = {}
					return
				bd.money -= b.next_cost()
				b.paid = true
			b.progress += dt * mt.build_mult(a)
			if (a as Survivor).role == Defs.Role.ENGINEER or randf() < dt * 0.6:
				mt.make_noise(a.pos, Tuning.NOISE_BUILD, "build", a, 1.0)
			ch["progress"] = b.progress / Tuning.STAGE_BUILD_TIME[b.stage]
			if b.progress >= Tuning.STAGE_BUILD_TIME[b.stage]:
				mt.bases.complete_stage(b, a)
				a.channel = {}
			return
		"repair":
			var rb: Base = ch["target"]
			rb.repair_progress += dt * mt.build_mult(a)
			mt.make_noise(a.pos, Tuning.NOISE_BUILD * 0.7, "build", a, 1.0)
			ch["progress"] = rb.repair_progress / Tuning.REPAIR_TIME
			if rb.repair_progress >= Tuning.REPAIR_TIME:
				mt.bases.finish_repair(rb, a)
				a.channel = {}
			return
		"steal":
			mt.make_noise(a.pos, Tuning.NOISE_STEAL, "steal", a, 1.0)
		"smash":
			mt.make_noise(a.pos, Tuning.NOISE_SMASH, "smash", a, 0.8)
		"catch":
			var victim: Survivor = ch["target"]
			if victim.health != Defs.Health.DOWNED:
				on_cancel(a, ch)
				a.channel = {}
				return
	ch["progress"] += dt
	if ch["progress"] >= ch["time"]:
		a.channel = {}
		_finish(a, ch)


func on_cancel(_a: Actor, _ch: Dictionary) -> void:
	pass


func _on_begin(a: Actor, ch: Dictionary) -> void:
	if ch["id"] == "steal":
		mt.on_steal_started(a as Survivor, ch["target"])


func _finish(a: Actor, o: Dictionary) -> void:
	var tgt = o["target"]
	match o["id"]:
		"pickup":
			mt.pickup(a as Survivor, tgt)
		"claim":
			mt.bases.claim(a as Survivor)
		"call":
			mt.bases.call_heli(tgt, a as Survivor)
		"board":
			(tgt as Heli).board(a as Survivor)
		"heal":
			var o2: Survivor = tgt
			o2.heal_one()
			var hd: Duo = (a as Survivor).duo
			mt.reward(hd, Tuning.REWARD_HEAL if o2.duo == hd else Tuning.REWARD_HEAL * 2, "healed %s" % o2.slot.name, a.slot)
		"self_heal":
			(a as Survivor).heal_one()
		"revive":
			var r: Survivor = tgt
			(a as Survivor).revive_used = true
			r.get_up()
			mt.reward((a as Survivor).duo, Tuning.REWARD_SAVE, "revived your partner", a.slot)
			mt.feed_all("%s revived %s!" % [a.slot.name, r.slot.name], "good")
		"cure":
			var c: Survivor = tgt
			(a as Survivor).cure -= 1
			c.get_up()
			mt.reward((a as Survivor).duo, Tuning.REWARD_SAVE, "cured %s" % c.slot.name, a.slot)
			mt.feed_all("%s used a cure on %s." % [a.slot.name, c.slot.name], "good")
		"break_tongue":
			var v: Survivor = tgt
			if v.pinned_by != null:
				var lk := v.pinned_by
				v.release_pin()
				lk.power_cd_until = mt.time + Tuning.TONGUE_COOLDOWN
				mt.reward((a as Survivor).duo, Tuning.REWARD_SAVE, "broke a tongue", a.slot)
		"steal":
			mt.bases.steal(a as Survivor, tgt)
		"hide":
			mt.bases.hide(a as Survivor, tgt)
		"unhide":
			mt.bases.unhide(a as Survivor)
		"catch":
			mt.on_caught(tgt, a as Killer)
		"smash":
			mt.smash_tile(tgt, a as Killer)
		"search":
			mt.bases.search_locker(a as Killer, tgt)
		"seal_hatch":
			mt.bases.seal_hatch(a as Killer, tgt)
