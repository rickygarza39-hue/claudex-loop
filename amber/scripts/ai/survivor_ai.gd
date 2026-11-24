class_name SurvivorAI
extends RefCounted
## Bot survivor. Utility-style priorities, re-evaluated a few times a second.

static var claims := {}        # ItemPickup -> Survivor (who is going for it)
static var base_plans := {}    # duo id -> Vector2 chosen base site

var mt: Match
var s: Survivor
var think_t := 0.0
var goal := ""
var goal_pos := Vector2(INF, INF)
var goal_item: ItemPickup = null
var hold_id := ""
var hold_target = null
var threat: Killer = null
var threat_pos := Vector2.ZERO
var threat_seen_t := -100.0
var flee_target := Vector2(INF, INF)
var flee_repick := 0.0
var explore_target := Vector2(INF, INF)
var explore_t := 0.0
var alert_pos := Vector2(INF, INF)
var alert_t := -100.0
var skill := 0.5
var runner := true
var parry_decided := {}
var ability_t := 0.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var build_t := 0.0
var donate_t := 0.0
var steal_ok := false
var unreachable := {}
var dodge_t := 0.0
var dodge_dir := Vector2.ZERO


func _init(match_ref: Match, sv: Survivor) -> void:
	mt = match_ref
	s = sv
	skill = mt.rng.randf_range(0.3, 0.75)
	runner = s.role != Defs.Role.ENGINEER
	think_t = mt.rng.randf() * 0.3
	steal_ok = mt.rng.randf() < 0.45


func alert(p: Vector2) -> void:
	alert_pos = p
	alert_t = mt.time


# ------------------------------------------------------------------------------

func think(dt: float) -> void:
	if s.slot.outcome != "" or not is_instance_valid(s):
		return
	_reflexes(dt)
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.25
		_decide()
	_act(dt)


func _partner() -> Survivor:
	var p := s.duo.partner_of(s.slot)
	if p != null and p.outcome == "" and p.actor is Survivor:
		return p.actor
	return null


func _sense_killers() -> void:
	var sight := Tuning.SURV_SIGHT_DARK if mt.blackout() else Tuning.SURV_SIGHT
	var best: Killer = null
	var bd := INF
	for k in mt.killers:
		if not k.released:
			continue
		var d = k.pos.distance_to(s.pos)
		var seen := false
		var limit := sight
		if k.ktype == Defs.K.LURKER and k.is_main() and not k.spotted():
			limit = Tuning.LURKER_VISIBLE_RANGE
		if k.stalking():
			limit = 3.5
		if d < limit and mt.m.los(s.pos, s.y + s.eye_height(), k.pos, k.y + 1.3):
			seen = true
		# heartbeat: non-Lurker killers are felt within the terror radius
		if not seen and d < Tuning.TERROR_RADIUS and not (k.ktype == Defs.K.LURKER and k.is_main()) and not k.stalking() and not k.husk:
			seen = true
		if k.husk and d > 12.0:
			seen = false
		if seen and d < bd:
			bd = d
			best = k
	if best != null:
		threat = best
		threat_pos = best.pos
		threat_seen_t = mt.time
	elif mt.time - threat_seen_t > 6.0:
		threat = null


func _reflexes(dt: float) -> void:
	_sense_killers()
	ability_t -= dt
	if s.is_downed() or s.pinned_by != null:
		return
	for k in mt.killers:
		if k.atk_state == "windup" and k.pos.distance_to(s.pos) < 3.2:
			var key = k.get_instance_id()
			if k.atk_t > Tuning.ATTACK_WINDUP - 0.09 and not parry_decided.get(key, false):
				parry_decided[key] = true
				if mt.rng.randf() < skill * 0.32 and mt.time >= s.parry_cd_until:
					s.parry_until = mt.time + Tuning.PARRY_WINDOW
					s.parry_cd_until = mt.time + Tuning.PARRY_COOLDOWN
		elif k.atk_state != "windup":
			parry_decided.erase(k.get_instance_id())
	for k2 in mt.killers:
		if k2.ktype == Defs.K.BRUTE and (k2.power_state == "charge_windup" or k2.power_state == "charge"):
			var to = s.pos - k2.pos
			if to.length() < 14.0 and absf(k2.forward2().angle_to(to)) < 0.45 and dodge_t <= 0.0:
				if mt.rng.randf() < 0.25 + skill * 0.6:
					var side := Vector2(-k2.forward2().y, k2.forward2().x)
					if side.dot(to) < 0.0:
						side = -side
					dodge_dir = side
					dodge_t = 0.9
				else:
					dodge_t = 0.9
					dodge_dir = Vector2.ZERO
	if threat == null or ability_t > 0.0:
		return
	var d = threat.pos.distance_to(s.pos)
	# knockdown item
	if s.flare > 0 and d < 7.5 and threat.released and not threat.stunned() and (threat.is_main() or s.health == Defs.Health.WOUNDED) and mt.m.los(s.pos, s.y + 1.4, threat.pos, threat.y + 1.2):
		s.facing = Actor.yaw_of(threat.pos - s.pos)
		if mt.use_flare(s):
			ability_t = 2.0
			return
	match s.role:
		Defs.Role.TRAPPER:
			if d < 9.0 and (s.traps[0] > 0 or s.traps[1] > 0) and mt.rng.randf() < 0.5:
				var which := 0 if s.traps[0] > 0 else 1
				var keep := s.facing
				s.facing = Actor.yaw_of(threat.pos - s.pos)
				if mt.place_trap(s, which):
					ability_t = 6.0
				s.facing = keep
		Defs.Role.MEDIC:
			if threat.ktype == Defs.K.TRACKER and d < 22.0 and mt.time >= s.ability_cd_until:
				if mt.scent_mask(s):
					ability_t = 3.0
		Defs.Role.ENGINEER:
			if d < 7.0 and d > 2.5 and mt.time >= s.ability_cd_until:
				var keep2 := s.facing
				s.facing = Actor.yaw_of(threat.pos - s.pos)
				if mt.bases.quick_barricade(s):
					ability_t = 4.0
				s.facing = keep2


# ------------------------------------------------------------------------------
# Decisions

func _goal(g: String, p: Vector2, item: ItemPickup = null, hid: String = "", htarget = null) -> void:
	goal = g
	goal_pos = p
	goal_item = item
	hold_id = hid
	hold_target = htarget


func _decide() -> void:
	var tm := mt.time
	if goal_item != null and (not is_instance_valid(goal_item) or goal_item.taken):
		goal_item = null
	# downed
	if s.is_downed():
		if s.cure > 0:
			_goal("cure_self", s.pos, null, "cure", s)
			return
		var p := _partner()
		if s.duo.base != null:
			_goal("crawl", s.duo.base.pos)
		elif p != null:
			_goal("crawl", p.pos)
		else:
			_goal("crawl", s.pos + (s.pos - threat_pos).normalized() * 6.0 if threat else s.pos)
		return
	if s.pinned_by != null:
		_goal("pinned", s.pos)
		return
	if s.hidden_in != null:
		var hb := s.duo.base
		if hb != null and hb.heli != null and (hb.heli.state == "landed" or (hb.heli.state == "approach" and hb.heli.time_left() < 4.0)):
			_goal("unhide", s.pos, null, "unhide", s.hidden_in)
			return
		if threat == null or tm - threat_seen_t > 8.0:
			_goal("unhide", s.pos, null, "unhide", s.hidden_in)
		else:
			_goal("hiding", s.pos)
		return
	var b := s.duo.base
	# board a landed helicopter
	if b != null and b.heli != null and b.heli.state == "landed":
		_goal("board", b.heli.lz, null, "board", b.heli)
		return
	# helicopter on the way: hold the landing zone
	if b != null and b.heli != null and b.heli.state in ["inbound", "approach", "hover"]:
		var lz: Vector2 = b.heli.lz
		if threat != null and threat.pos.distance_to(lz) < 20.0 and not s.duo.lockdown_used and b.heli.time_left() < 60.0:
			mt.bases.lockdown(s)
		var dthreat := threat.pos.distance_to(s.pos) if threat != null else INF
		if dthreat < 7.0 and tm - s.last_seen_by_killer < 2.0:
			_goal("flee", s.pos)
			return
		for st in mt.structures_near(lz, 9.0):
			if st.kind == Defs.B.LOCKER and st.occupant == null and threat != null and dthreat < 14.0 and b.heli.time_left() > 12.0:
				_goal("hide", st.pos, null, "hide", st)
				return
		_goal("wait_lz", lz + Vector2(mt.rng.randf_range(-2, 2), mt.rng.randf_range(-2, 2)) if goal != "wait_lz" else goal_pos)
		return
	# still in the cell
	var cell: Dictionary = s.duo.cell
	if not cell["open"]:
		if cell["worse"]:
			var idx := s.duo.members.find(s.slot)
			var lp := MapData.center_of(cell["levers"][idx % 2])
			_goal("lever", lp, null, "lever", {"cell": cell, "lever": idx % 2})
		else:
			_goal("cell", MapData.center_of(cell["door"]), null, "cell", cell)
		return
	# danger
	if threat != null:
		var d = threat.pos.distance_to(s.pos)
		var chased := tm - s.last_seen_by_killer < 2.5
		var close := 8.0
		if chased:
			close = 18.0
		if s.health == Defs.Health.WOUNDED:
			close += 4.0
		if d < close and tm - threat_seen_t < 3.5:
			# hide in a nearby locker when cornered
			for st in mt.structures_near(s.pos, 4.0):
				if st.kind == Defs.B.LOCKER and st.occupant == null and d > 7.0 and mt.rng.randf() < 0.3:
					_goal("hide", st.pos, null, "hide", st)
					return
			_goal("flee", s.pos)
			return
	# a killer is close but hasn't seen us: slip away behind cover
	if threat != null and tm - s.last_seen_by_killer > 3.0 and threat.pos.distance_to(s.pos) < 16.0 and goal not in ["board", "rescue", "revive", "cure"]:
		if goal != "evade" or s.pos.distance_to(goal_pos) < 1.5:
			var ev := _cover_point(threat.pos, 6.0, 12.0)
			_goal("evade", ev if ev.x < INF else s.pos)
		return
	var partner := _partner()
	# help a partner in trouble
	if partner != null:
		var pd := partner.pos.distance_to(s.pos)
		if partner.pinned_by != null and pd < 26.0:
			_goal("rescue", partner.pos, null, "break_tongue", partner)
			return
		if partner.is_downed():
			if s.role == Defs.Role.MEDIC and not s.revive_used and (_safe_near(partner.pos, 5.0) or skill > 0.6):
				_goal("revive", partner.pos, null, "revive", partner)
				return
			if s.cure > 0 and (_safe_near(partner.pos, 5.0) or skill > 0.6):
				_goal("cure", partner.pos, null, "cure", partner)
				return
			var t := _shop_target()
			if not t.is_empty() and mt.shop.why_not(s, "cure") == "" and s.duo.money >= Tuning.CURE_COST:
				_goal("shop", t["pos"], null, "shop", t)
				return
		if partner.health == Defs.Health.WOUNDED and s.health != Defs.Health.DOWNED and pd < 12.0 and threat == null and partner.channel.is_empty():
			if partner.pos.distance_to(s.pos) < 12.0 and (partner.duo.base == null or not partner.duo.base.heli_called):
				_goal("heal", partner.pos, null, "heal", partner)
				return
	if s.health == Defs.Health.WOUNDED and s.role == Defs.Role.MEDIC and threat == null:
		_goal("self_heal", s.pos, null, "self_heal", s)
		return
	# helicopter inbound: hold the landing zone
	if b != null and b.heli != null and b.heli.state in ["inbound", "approach", "hover"]:
		_goal("wait_lz", b.heli.lz + Vector2(mt.rng.randf_range(-3, 3), mt.rng.randf_range(-3, 3)) if goal != "wait_lz" else goal_pos)
		return
	# base
	if b == null:
		var site := _base_site()
		if site.x < INF:
			_goal("claim", site, null, "claim", null)
			return
	# shopping
	var st2 := _shop_target()
	if not st2.is_empty() and _wants_shop():
		_goal("shop", st2["pos"], null, "shop", st2)
		return
	# grab a flare gun if one is close
	var fl := _nearest_known(Defs.Item.FLARE, -1, 30.0)
	if fl != null and s.flare == 0:
		_goal("fetch", fl.pos, fl, "pickup", fl)
		return
	if b == null:
		_goal("explore", s.pos)
		return
	# carrying parts: bring them home
	if not s.parts.is_empty():
		_goal("deliver", b.pos)
		return
	if b.broken:
		var cost = int((b.next_cost() if b.stage < 3 else Tuning.STAGE_COST[2]) * Tuning.REPAIR_COST_FRAC)
		if s.duo.money >= cost:
			_goal("repair", b.pos, null, "repair", b)
			return
		# can't afford the repair yet: go find scrip
		var cash0 := _nearest_known(Defs.Item.CASH, -1, 140.0)
		if cash0 != null:
			_goal("fetch", cash0.pos, cash0, "pickup", cash0)
			claims[cash0] = s
			return
		_goal("explore", s.pos)
		return
	if b.stage >= 3:
		if not b.heli_called or (b.heli != null and b.heli.state == "gone"):
			_goal("call", b.pos, null, "call", b)
			return
		_goal("defend", b.pos)
		return
	# build the next stage when everything is ready
	if not b.broken and b.missing_parts().is_empty() and (b.paid or s.duo.money >= b.next_cost()) and not mt.jammed():
		_goal("build", b.pos, null, "build", b)
		return
	# donate surplus to a struggling duo once nearly done
	if b.stage >= 2 and s.duo.money > b.next_cost() + 120 and mt.time > donate_t:
		donate_t = mt.time + 60.0
		_donate()
	# grab loot lying close by
	if threat == null:
		for kind in [Defs.Item.CASH, Defs.Item.SCRAP]:
			var near_it := _nearest_known(kind, -1, 9.0)
			if near_it != null:
				_goal("fetch", near_it.pos, near_it, "pickup", near_it)
				claims[near_it] = s
				return
	# what do we still need?
	var need := _needed_parts()
	if not need.is_empty():
		# idle builder stays home when the partner is out fetching, unless nothing is known
		var it := _nearest_needed(need)
		if it != null:
			_goal("fetch", it.pos, it, "pickup", it)
			claims[it] = s
			return
		# steal when desperate and alone
		if partner == null and steal_ok:
			var victim := _steal_target(need)
			if victim != null:
				_goal("steal", victim.pos, null, "steal", victim)
				return
		_goal("explore", s.pos)
		explore_zone_for(need)
		return
	# parts are covered; we need money
	if not b.paid and s.duo.money < b.next_cost():
		var cash := _nearest_known(Defs.Item.CASH, -1, 120.0)
		if cash != null:
			_goal("fetch", cash.pos, cash, "pickup", cash)
			claims[cash] = s
			return
		_goal("explore", s.pos)
		return
	# something to do at base
	if mt.time > build_t and s.duo.scrap >= 1:
		build_t = mt.time + 12.0
		_build_defences()
	var scrap := _nearest_known(Defs.Item.SCRAP, -1, 40.0)
	if scrap != null:
		_goal("fetch", scrap.pos, scrap, "pickup", scrap)
		return
	_goal("defend", b.pos)


func _safe_near(p: Vector2, r: float) -> bool:
	if threat == null:
		return true
	return threat.pos.distance_to(p) > r or threat.stunned() or threat.held()


func _needed_parts() -> Array:
	var b := s.duo.base
	if b == null:
		return [Defs.P.CABLE]
	var need := b.all_missing()
	# parts the partner is carrying are covered
	var p := _partner()
	if p != null:
		for part in p.parts:
			need.erase(part)
	for part in s.parts:
		need.erase(part)
	# focus on the next stage first, but allow looking ahead
	var next := b.missing_parts()
	if p != null:
		for part in p.parts:
			next.erase(part)
	if not next.is_empty():
		var ordered: Array = next.duplicate()
		for part in need:
			if not ordered.has(part):
				ordered.append(part)
		return ordered
	return need


func _nearest_needed(need: Array) -> ItemPickup:
	var best: ItemPickup = null
	var bd := INF
	var first_stage := s.duo.base.missing_parts() if s.duo.base != null else []
	for it in s.duo.known_items.keys():
		if not is_instance_valid(it) or it.taken or it.kind != Defs.Item.PART:
			continue
		if not need.has(it.part):
			continue
		if unreachable.has(it):
			continue
		var c: Survivor = claims.get(it)
		if c != null and c != s and is_instance_valid(c) and c.slot.outcome == "" and c.duo == s.duo:
			continue
		var d = it.pos.distance_to(s.pos)
		if not first_stage.has(it.part):
			d += 35.0
		if threat != null and threat.pos.distance_to(it.pos) < 12.0:
			d += 40.0
		if d < bd:
			bd = d
			best = it
	return best


func _nearest_known(kind: int, part: int, max_d: float) -> ItemPickup:
	var best: ItemPickup = null
	var bd := max_d
	for it in s.duo.known_items.keys():
		if not is_instance_valid(it) or it.taken or it.kind != kind:
			continue
		if part >= 0 and it.part != part:
			continue
		if unreachable.has(it):
			continue
		var c: Survivor = claims.get(it)
		if c != null and c != s and is_instance_valid(c) and c.slot.outcome == "" and c.duo == s.duo:
			continue
		var d = it.pos.distance_to(s.pos)
		if d < bd:
			bd = d
			best = it
	return best


func explore_zone_for(need: Array) -> void:
	if explore_target.x < INF and mt.time < explore_t and s.pos.distance_to(explore_target) > 3.0:
		goal_pos = explore_target
		return
	var zone := Defs.Z.TOWN
	if not need.is_empty():
		match need[0]:
			Defs.P.CABLE: zone = Defs.Z.TOWN
			Defs.P.FUEL, Defs.P.CELL: zone = Defs.Z.MINE
			Defs.P.SPARK: zone = [Defs.Z.TOWN, Defs.Z.FIELD, Defs.Z.SWAMP][mt.rng.randi() % 3]
			Defs.P.CIRCUIT: zone = Defs.Z.LAB
			Defs.P.DISH: zone = Defs.Z.HIGH
	var tl = mt.m.random_walkable_in_zone(mt.rng, zone)
	if tl.x < 0:
		tl = MapData.tile_of(s.pos)
	explore_target = MapData.center_of(tl)
	# players learn where parts tend to spawn: often search near a real (unseen) spot
	if not need.is_empty() and mt.rng.randf() < 0.8:
		var cands: Array = []
		for it in mt.items:
			if not it.taken and it.kind == Defs.Item.PART and need.has(it.part) and it.pos.distance_to(s.pos) < 95.0:
				cands.append(it)
		if not cands.is_empty():
			var pick: ItemPickup = cands[mt.rng.randi() % cands.size()]
			var off := Vector2(mt.rng.randf_range(-5, 5), mt.rng.randf_range(-5, 5))
			var t2 := mt.nav.snap(MapData.tile_of(pick.pos + off), true, false, 4)
			if t2.x >= 0:
				explore_target = MapData.center_of(t2)
	explore_t = mt.time + 25.0
	goal_pos = explore_target


func _base_site() -> Vector2:
	if base_plans.has(s.duo.id):
		var p: Vector2 = base_plans[s.duo.id]
		if mt.base_site_ok(p, s.duo):
			return p
	var best := Vector2(INF, INF)
	var best_score := -INF
	for i in 160:
		var a := mt.rng.randf() * TAU
		var r := mt.rng.randf_range(6.0, 46.0)
		var p := s.pos + Vector2(cos(a), sin(a)) * r
		var tl := MapData.tile_of(p)
		var c := MapData.center_of(tl)
		if not mt.base_site_ok(c, s.duo):
			continue
		if not mt.nav.reachable(s.pos, c, true):
			continue
		# defensibility: solid tiles around, but not boxed in
		var solid := 0
		var water := 0
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var q := tl + Vector2i(dx, dy)
				var tt := mt.m.tv(q)
				if not MapData.walkable_type(tt, false):
					solid += 1
				if tt == Defs.T.WATER:
					water += 1
		var open_adj := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if mt.nav.is_open(tl + d, true):
				open_adj += 1
		if open_adj < 3:
			continue
		var score := minf(float(solid), 22.0) * 0.6 - water * 0.5 - r * 0.08 + mt.rng.randf() * 3.0
		score -= absf(mt.m.tile_height(tl)) * 0.2
		if Vector2(tl - mt.m.nest).length() < 30.0:
			score -= 10.0
		if score > best_score:
			best_score = score
			best = c
	if best.x < INF:
		base_plans[s.duo.id] = best
	return best


func _shop_target() -> Dictionary:
	var best: Dictionary = {}
	var bd := 70.0
	for t in mt.shop.open_terminals():
		var d: float = t["pos"].distance_to(s.pos)
		if d < bd:
			bd = d
			best = t
	return best


func _wants_shop() -> bool:
	if s.health == Defs.Health.WOUNDED and mt.shop.why_not(s, "medkit") == "" and s.role != Defs.Role.MEDIC:
		return true
	if s.role == Defs.Role.TRAPPER and s.traps[0] + s.traps[1] < 2 and mt.shop.why_not(s, "traps") == "":
		return true
	var b := s.duo.base
	if b != null and b.stage >= 1 and s.cure == 0 and mt.shop.why_not(s, "cure") == "" and s.duo.money >= Tuning.CURE_COST + (b.next_cost() if not b.paid else 0):
		return true
	return false


func shop_visit(t: Dictionary) -> void:
	var p := _partner()
	if p != null and p.is_downed() and s.cure == 0:
		mt.shop.buy(s, "cure")
	if s.health == Defs.Health.WOUNDED and s.role != Defs.Role.MEDIC:
		mt.shop.buy(s, "medkit")
	if s.role == Defs.Role.TRAPPER:
		mt.shop.buy(s, "traps")
	var b := s.duo.base
	var reserve := (b.next_cost() if b != null and not b.paid else 0)
	if s.cure == 0 and s.duo.money - reserve >= Tuning.CURE_COST:
		mt.shop.buy(s, "cure")
	if s.duo.money - reserve > 60 and mt.rng.randf() < 0.5:
		mt.shop.buy(s, "scanner")
	if s.duo.scrap < 3 and s.duo.money - reserve > 50:
		mt.shop.buy(s, "scrap")


func _steal_target(need: Array) -> Base:
	for d in mt.duos:
		if d == s.duo or d.base == null:
			continue
		var b: Base = d.base
		var has := false
		for p in b.storage:
			if need.has(p):
				has = true
		if not has:
			continue
		var guarded := false
		for sl in d.living():
			if sl.actor and sl.actor.pos.distance_to(b.pos) < 15.0:
				guarded = true
		if not guarded:
			return b
	return null


func _donate() -> void:
	var poorest: Duo = null
	var low := INF
	for d in mt.duos:
		if d == s.duo or not d.active() or d.base == null:
			continue
		var prog = d.base.stage * 100.0 + d.money
		if prog < low:
			low = prog
			poorest = d
	if poorest != null:
		var amt := Tuning.DONATE_STEP * 2
		s.duo.money -= amt
		poorest.money += amt
		mt.feed_all("%s duo sent $%d to %s duo." % [s.duo.name, amt, poorest.name], "good")


func _build_defences() -> void:
	var b := s.duo.base
	if b == null or s.pos.distance_to(b.pos) > 9.0 or threat != null:
		return
	# doors at chokepoints, an alarm, a floodlight, and traps for the Trapper
	var want: Array = []
	var have := {}
	for st in b.structures:
		have[st.kind] = have.get(st.kind, 0) + 1
	if have.get(Defs.B.ALARM, 0) == 0:
		want.append(Defs.B.ALARM)
	if have.get(Defs.B.DOOR, 0) < 2:
		want.append(Defs.B.DOOR)
	if have.get(Defs.B.FLOODLIGHT, 0) == 0 and b.stage >= 2:
		want.append(Defs.B.FLOODLIGHT)
	if have.get(Defs.B.LOCKER, 0) == 0 and b.stage >= 1:
		want.append(Defs.B.LOCKER)
	if s.role == Defs.Role.TRAPPER and s.traps[0] > 1:
		want.append(Defs.B.SNARE)
	if want.is_empty():
		return
	var kind: int = want[mt.rng.randi() % want.size()]
	var tl := _pick_build_tile(kind, b)
	if tl.x >= 0:
		var st := mt.bases.place(s, kind, tl)
		if st != null and s.role == Defs.Role.ENGINEER and kind == Defs.B.DOOR and s.duo.money > 120 and mt.rng.randf() < 0.5:
			mt.bases.upgrade(s, st, mt.rng.randf() < 0.5)


func _pick_build_tile(kind: int, b: Base) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for i in 50:
		var tl := b.tile + Vector2i(mt.rng.randi_range(-5, 5), mt.rng.randi_range(-5, 5))
		if mt.bases.can_place(s, kind, tl) != "":
			continue
		var solid := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not mt.nav.is_open(tl + d, false):
				solid += 1
		var dist := Vector2(tl - b.tile).length()
		var score := 0.0
		match kind:
			Defs.B.DOOR:
				# doorway: walls on two opposite sides
				var lr := not mt.nav.is_open(tl + Vector2i(1, 0), false) and not mt.nav.is_open(tl + Vector2i(-1, 0), false)
				var ud := not mt.nav.is_open(tl + Vector2i(0, 1), false) and not mt.nav.is_open(tl + Vector2i(0, -1), false)
				if not (lr or ud):
					continue
				score = 10.0 - absf(dist - 4.0)
			Defs.B.ALARM, Defs.B.SNARE:
				score = 5.0 - absf(dist - 4.5) - solid
			Defs.B.FLOODLIGHT, Defs.B.LOCKER:
				score = 4.0 - absf(dist - 2.0) + solid
		if score > best_score:
			best_score = score
			best = tl
	return best


func _steal_ok_pos(_p: Vector2) -> bool:
	return true


# ------------------------------------------------------------------------------
# Acting on the goal

func _act(dt: float) -> void:
	s.want_interact = false
	s.want_run = false
	s.want_crouch = false
	s.want_face = Vector2.ZERO
	if dodge_t > 0.0:
		dodge_t -= dt
		if dodge_dir != Vector2.ZERO:
			s.want_move = dodge_dir
			s.want_run = true
			return
	var dest := goal_pos
	match goal:
		"pinned", "hiding":
			s.want_move = Vector2.ZERO
			return
		"flee":
			_flee(dt)
			return
		"crawl":
			_go(dest, 1.0)
			return
		"defend", "wait_lz":
			if s.pos.distance_to(dest) > 3.5:
				_go(dest, 0.0)
			else:
				s.want_move = Vector2.ZERO
				if threat == null and mt.rng.randf() < 0.01:
					goal_pos = dest + Vector2(mt.rng.randf_range(-3, 3), mt.rng.randf_range(-3, 3))
			return
		"explore":
			if explore_target.x == INF or s.pos.distance_to(explore_target) < 3.0 or mt.time > explore_t:
				explore_zone_for(_needed_parts())
			dest = explore_target
			if not _go(dest, 0.0):
				explore_target = Vector2(INF, INF)
			return
		"deliver":
			_go(dest, 0.0)
			return
		"evade":
			_go(dest, 0.0)
			s.want_run = false
			s.want_crouch = true
			return
	if goal == "" or dest.x == INF:
		s.want_move = Vector2.ZERO
		return
	# goals that end in an interaction
	var reach := 1.4
	if hold_id in ["build", "repair", "call", "steal", "cell", "shop"]:
		reach = 2.15
	if hold_id == "claim":
		reach = 0.8
	if hold_id == "board":
		reach = 3.0
	var d := s.pos.distance_to(dest)
	if d > reach:
		if not s.channel.is_empty():
			s.cancel_channel()
		if not _go(dest, 0.0):
			if goal_item != null:
				unreachable[goal_item] = true
				claims.erase(goal_item)
			if hold_id == "claim":
				base_plans.erase(s.duo.id)
			goal = "explore"
			explore_target = Vector2(INF, INF)
		return
	s.want_move = Vector2.ZERO
	s.want_face = dest - s.pos
	var opt := mt.interact.find(s, hold_id, hold_target)
	if opt.is_empty():
		if hold_id == "claim":
			# the exact tile may be blocked; claim where we stand if allowed
			opt = mt.interact.find(s, "claim")
		if opt.is_empty():
			goal = ""
			return
	if opt["blocked"] != "":
		goal = ""
		return
	mt.interact.begin(s, opt)
	s.want_interact = true


func _approach_point(dest: Vector2) -> Vector2:
	## For targets on solid tiles (doors, radios, terminals) walk to the best open neighbour.
	var tl := MapData.tile_of(dest)
	if mt.nav.is_open(tl, true):
		return dest
	var best := dest
	var bd := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = tl + d
		if not mt.nav.is_open(q, true):
			continue
		var c := MapData.center_of(q)
		var dist := c.distance_to(s.pos)
		if dist < bd:
			bd = dist
			best = c
	return best


func _go(dest: Vector2, _crawl: float) -> bool:
	var nav_goal := _approach_point(dest)
	if s.pos.distance_to(nav_goal) < 0.4 and nav_goal != dest:
		s.want_move = (dest - s.pos).normalized()
		return true
	if not s.nav_to(nav_goal):
		s.want_move = Vector2.ZERO
		return false
	var dir = s.steer_path()
	if dir == Vector2.ZERO and s.pos.distance_to(dest) > 0.35:
		# final approach to things that stand on solid tiles (doors, radios, terminals)
		dir = (dest - s.pos).normalized()
	s.want_move = dir
	var sneaking := threat != null and mt.time - s.last_seen_by_killer > 3.0 and goal != "flee" and threat.pos.distance_to(s.pos) < 26.0
	s.want_run = (threat != null and not sneaking) or goal in ["rescue", "board", "flee", "revive", "cure"]
	s.want_crouch = sneaking and goal not in ["rescue", "board", "revive", "cure"]
	if threat == null and goal in ["fetch", "explore", "deliver"] and mt.rng.randf() < 0.002:
		s.want_run = true
	# unstick
	if s.pos.distance_to(last_pos) < 0.02 and dir != Vector2.ZERO:
		stuck_t += mt.dt_last
		if stuck_t > 1.5:
			stuck_t = 0.0
			s.clear_path()
			s.want_move = Vector2(mt.rng.randf_range(-1, 1), mt.rng.randf_range(-1, 1)).normalized()
	else:
		stuck_t = 0.0
	last_pos = s.pos
	return true


func _cover_point(from: Vector2, rmin: float, rmax: float) -> Vector2:
	## A reachable spot away from `from` that it cannot see.
	var best := Vector2(INF, INF)
	var best_score := -INF
	var away := (s.pos - from).normalized()
	if away == Vector2.ZERO:
		away = Vector2(1, 0)
	for i in 12:
		var a := away.angle() + mt.rng.randf_range(-1.7, 1.7)
		var p := s.pos + Vector2(cos(a), sin(a)) * mt.rng.randf_range(rmin, rmax)
		var tl := mt.nav.snap(MapData.tile_of(p), true, false, 2)
		if tl.x < 0:
			continue
		var c := MapData.center_of(tl)
		var score := c.distance_to(from) - c.distance_to(s.pos) * 0.4
		if not mt.m.los(from, mt.m.height_at(from) + 1.7, c, mt.m.height_at(c) + 0.8):
			score += 10.0
		if score > best_score:
			best_score = score
			best = c
	return best


func _gap_escape(from: Vector2) -> Vector2:
	## A squeeze gap we reach before the killer, exiting on the far side.
	var best := Vector2(INF, INF)
	var best_score := -INF
	for g in mt.gap_tiles:
		if mt.m.tv(g) != Defs.T.GAP:
			continue
		var gc := MapData.center_of(g)
		var dm := gc.distance_to(s.pos)
		if dm > 22.0:
			continue
		var dk := gc.distance_to(from)
		if dm > dk - 1.5:
			continue
		var axis := Vector2(1, 0) if mt.m.gap_along_x(g.x, g.y) else Vector2(0, 1)
		var e1 := gc + axis * 3.0
		var e2 := gc - axis * 3.0
		var exit_p := e1 if e1.distance_to(from) > e2.distance_to(from) else e2
		var entry := e2 if exit_p == e1 else e1
		if s.pos.distance_to(entry) > s.pos.distance_to(exit_p):
			continue
		if not mt.nav.is_open(MapData.tile_of(exit_p), true):
			continue
		var score := 40.0 - dm + (dk - dm) * 0.6
		if score > best_score:
			best_score = score
			best = exit_p
	return best


func _flee(dt: float) -> void:
	flee_repick -= dt
	var from := threat_pos
	if threat != null:
		from = threat.pos
	var bad_dir := false
	if flee_target.x < INF:
		var to_t := flee_target - s.pos
		var away := s.pos - from
		if to_t.length() > 0.1 and away.length() > 0.1 and absf(to_t.angle_to(away)) > 1.9:
			bad_dir = true
	if flee_repick <= 0.0 or flee_target.x == INF or s.pos.distance_to(flee_target) < 2.0 or bad_dir:
		flee_repick = 3.5
		var gap_exit := _gap_escape(from)
		if gap_exit.x < INF:
			flee_target = gap_exit
			if not _go(flee_target, 0.0):
				flee_target = Vector2(INF, INF)
			s.want_run = true
			s.want_crouch = false
			return
		var best := s.pos
		var best_score := -INF
		var away := (s.pos - from).normalized()
		for i in 14:
			var a = away.angle() + mt.rng.randf_range(-1.1, 1.1)
			var r = mt.rng.randf_range(14.0, 26.0)
			var p = s.pos + Vector2(cos(a), sin(a)) * r
			var tl := mt.nav.snap(MapData.tile_of(p), true, false, 2)
			if tl.x < 0:
				continue
			var c := MapData.center_of(tl)
			var score := c.distance_to(from) - c.distance_to(s.pos) * 0.3
			if not mt.m.los(from, mt.m.height_at(from) + 1.7, c, mt.m.height_at(c) + 1.0):
				score += 7.0
			# squeeze gaps and our own base are good places to run to
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if mt.m.tv(tl + Vector2i(dx, dy)) == Defs.T.GAP:
						score += 5.0
			if s.duo.base != null and s.duo.base.contains(c):
				score += 8.0 if not s.duo.base.structures.is_empty() else 3.0
			if s.duo.base != null and s.duo.base.heli != null and s.duo.base.heli.state in ["inbound", "approach", "hover", "landed"]:
				score -= maxf(0.0, c.distance_to(s.duo.base.heli.lz) - 16.0) * 2.0
			if score > best_score:
				best_score = score
				best = c
		flee_target = best
	if not _go(flee_target, 0.0):
		flee_target = Vector2(INF, INF)
	s.want_run = true
